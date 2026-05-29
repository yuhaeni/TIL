# DataSource 주입과 Reader 자원 관리 — JdbcCursorItemReader, 커넥션 풀, @Qualifier

> 날짜: 2026-05-29

## 내용

Spring Batch 코드를 읽다 보면 `JdbcCursorItemReader`가 `DataSource`를 주입받는 패턴이 자주 보인다.

```kotlin
@Configuration
class DiaryReminderJobConfig {
    @Bean
    @StepScope
    fun diaryReminderReader(
        dataSource: DataSource,
        @Value("#{jobParameters['targetDate']}") targetDate: String,
    ): JdbcCursorItemReader<DiaryReminderTarget> =
        JdbcCursorItemReaderBuilder<DiaryReminderTarget>()
            .name("diaryReminderReader")
            .dataSource(dataSource)
            .sql(SQL)
            .preparedStatementSetter { it.setObject(1, LocalDate.parse(targetDate)) }
            .rowMapper { rs, _ -> DiaryReminderTarget(rs.getLong("id"), ...) }
            .fetchSize(500)
            .build()
}
```

"왜 굳이 `DataSource`라는 추상화를 주입받지? Connection을 직접 받으면 안 되나?" 라는 의문에서 출발해, **자원 관리의 책임을 누가 지느냐**라는 질문까지 거슬러 올라갈 수 있다.

---

### DataSource — 커넥션 풀의 "창구" 인터페이스

`JdbcCursorItemReader`가 하는 일은 단순하다. **DB에 SQL을 던지고 결과를 한 줄씩 읽어오는 것.** 이 동작을 하려면 최소한 DB 연결이 필요하다.

그런데 매번 SQL을 던질 때마다 `DriverManager.getConnection(url, user, pw)`로 새 커넥션을 열고 닫는다면?

- TCP 핸드셰이크 비용
- DB 인증(로그인) 비용

→ 정작 SQL 실행보다 *연결 비용*이 더 커진다.

그래서 어플리케이션은 커넥션을 미리 N개 만들어놓고 재사용하는 **커넥션 풀**(HikariCP 등)을 쓴다.

`DataSource`는 **"커넥션을 달라고 하면 풀에서 하나 꺼내주는 창구"** 추상화다.

```
Reader  ──getConnection()──▶  DataSource  ──▶  HikariCP Pool
                                                  │
        ◀────── Connection ──────────────────────┘
```

Spring Boot는 `application.yml`의 DB 설정을 읽어 HikariCP 기반 `DataSource` 빈을 자동 등록한다. 그래서 `dataSource: DataSource` 한 줄만 적으면 풀까지 함께 연결되는 것.

> **면접 예상 질문:** JdbcCursorItemReader가 Connection이 아닌 DataSource를 주입받는 이유는 무엇인가? DataSource가 인터페이스로 추상화돼 있어서 얻는 이점은?

---

### Reader 생명주기와 자원 관리 책임 — open / read / close

`DataSource`는 "창구"일 뿐, *언제 빌리고 언제 반납할지*를 결정하지는 않는다. 그 책임은 **`JdbcCursorItemReader` 자신**(과 그것을 호출하는 Spring Batch Step)이 진다.

```
Step 시작
   │
   ├─ Reader.open()   → dataSource.getConnection()    [풀에서 1개 대여]
   │
   ├─ Reader.read()   → 커서로 한 줄씩 가져옴
   ├─ Reader.read()
   ├─ Reader.read()
   │   ...
   │
   └─ Reader.close()  → connection.close()            [풀에 반납]
```

여기서 중요한 포인트:
- `connection.close()`는 실제로 *물리 연결을 끊는 것*이 아니라 **풀로 반납**하는 호출이다 (HikariCP가 wrapping해서 `close()` 메서드를 가로챈다).
- `open() / close()`를 호출하는 주체는 **Reader 본인** 이다. `DataSource` 가 알아서 해주는 게 아니다.

**만약 `close()`가 호출되지 않으면?**
- 빌린 커넥션이 반납되지 않아 *점유 상태로 남는다* → **Connection Leak**
- 풀 사이즈가 10인데 Leak이 누적되면 → 풀 고갈 → 새 요청은 `getConnection()`에서 무한 대기 → 타임아웃 → 서비스 장애

> **면접 예상 질문:** Connection Leak이 발생하는 시나리오와 그 결과를 설명하라. `connection.close()`가 실제로 어떤 동작을 하는지 HikariCP 관점에서 설명하라.

---

### 다중 DB와 @Qualifier — Spring의 빈 해소 순서

`DataSource` 빈은 보통 DB 하나당 하나다. 메인 DB와 통계 DB를 동시에 쓴다면 `DataSource` 빈도 2개가 등록된다.

이때 `dataSource: DataSource` 라고만 적으면 Spring은 어떤 빈을 골라야 할지 모른다.

**Spring의 빈 해소 순서:**
1. **타입으로 찾는다** → `DataSource` 타입 빈이 2개라 모호
2. **`@Primary` 가 붙은 빈이 있으면 그것을 우선** → 없으면 다음 단계
3. **파라미터 이름과 빈 이름을 매칭** → `dataSource` 라는 이름의 빈이 있으면 선택
4. **그래도 모호하면 `NoUniqueBeanDefinitionException`**

**주의 — 파라미터 이름 매칭의 함정:**
- 컴파일 옵션 `-parameters` 가 없으면 *런타임에 파라미터 이름이 사라진다*
- Kotlin도 마찬가지. 빌드 설정에 따라 매칭이 동작하지 않을 수 있음

그래서 **명시적인 `@Qualifier` 사용이 안전**하다.

```kotlin
fun diaryReminderReader(
    @Qualifier("statisticsDataSource") dataSource: DataSource,
    ...
): JdbcCursorItemReader<DiaryReminderTarget> = ...
```

> **면접 예상 질문:** Spring이 같은 타입의 빈이 여러 개일 때 어떻게 하나를 선택하는가? `@Primary` 와 `@Qualifier` 의 차이와 각각 언제 쓰는가?

---

## 학습 정리

- `JdbcCursorItemReader`가 `DataSource`를 받는 이유는 **자원 관리 책임을 풀(인프라)에 위임**하기 위함. Reader는 "쓰기만" 하고, 빌리고 반납하는 메커니즘은 `DataSource` + 커넥션 풀이 담당한다.
- `DataSource`는 풀의 *창구* 추상화. `getConnection()` = 풀에서 대여, `connection.close()` = 풀로 반납.
- 커넥션 대여·반납을 *호출하는 주체*는 `DataSource`가 아니라 **Reader 본인**(`open()` / `close()` 생명주기 메서드). 누락 시 Connection Leak → 풀 고갈 → 서비스 장애.
- 한 어플리케이션이 DB를 여러 개 쓰면 `DataSource` 빈도 여러 개. 파라미터 이름 매칭은 컴파일 옵션 의존이라 불안정 → **`@Qualifier` 로 명시**하는 게 안전.
