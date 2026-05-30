# Spring Batch Step 구성요소 — Reader/Processor/Writer 작성 패턴과 filter vs skip

> 날짜: 2026-05-30

## 내용

chunk-oriented Step의 세 구성요소를 다룬다. 코드를 보면 Reader/Writer는 빌더 패턴으로 만드는데 Processor는 람다로 쓴다. 왜 이렇게 다른지, 그리고 ItemProcessor가 `null`을 반환하면 어떻게 되는지 (그리고 그게 skip 정책과 어떻게 다른지) 정리한다.

```kotlin
// Reader: 빌더 패턴
JdbcCursorItemReaderBuilder<DiaryReminderResult>()
    .name("diaryReminderReader")
    .dataSource(dataSource)
    .fetchSize(CHUNK_SIZE)
    .sql("...")
    .rowMapper { rs, _ -> DiaryReminderResult(userId = rs.getLong("user_id")) }
    .build()

// Processor: 람다
ItemProcessor { item ->
    // TODO: pushOptIn / device_token 유효성 검사 — null 반환 시 chunk 에서 skip
    DiaryReminderMessage(userId = item.userId, targetDate = LocalDate.parse(targetDate))
}

// Writer: 람다 (stub) — 실제 운영 Writer는 빌더로 만드는 게 일반적
ItemWriter { chunk ->
    chunk.items.forEach { msg -> println("[DiaryReminder] publish stub: $msg") }
}
```

---

### Reader/Writer = 인프라, Processor = 비즈니스 로직

세 구성요소의 **본질적 책임**이 다르다.

| 구성요소 | 책임 | 영역 |
|------|------|------|
| **Reader** | 데이터 소스 접근 (DB/파일/MQ에서 읽기) | 인프라 / 어댑터 |
| **Processor** | 가져온 데이터의 판단·변환·필터링 | **비즈니스 로직 / 도메인** |
| **Writer** | 데이터 출력 (DB/파일/MQ로 쓰기) | 인프라 / 어댑터 |

Reader는 "DB에 어떻게 접근할지" (dataSource, sql, fetchSize, rowMapper) 를 설정한다. 이건 **택배 회사가 짐을 어떻게 가져올지** 같은 영역이고, 우리 서비스 도메인과 무관하다. Writer도 마찬가지다.

Processor는 "이 사용자에게 알림을 보낼까? `pushOptIn`이 false면 제외, `device_token`이 만료됐으면 제외" 같은 **서비스 고유 룰**을 적용한다. 이게 비즈니스 로직이다.

> **면접 예상 질문:** Spring Batch의 chunk-oriented Step에서 Reader/Processor/Writer가 각각 담당하는 책임은 무엇인가? 인프라 영역과 도메인 영역을 어떻게 구분할 수 있는가?

---

### 작성 패턴 차이 — 빌더 vs 함수형 인터페이스 람다

책임이 다르니 **작성 방식**도 다르다.

**Reader/Writer (빌더 패턴)**:
- Spring Batch가 표준 구현체를 제공: `JdbcCursorItemReader`, `JpaPagingItemReader`, `FlatFileItemReader`, `JpaItemWriter`, `JdbcBatchItemWriter`, `FlatFileItemWriter` 등
- 설정할 옵션이 많음 (dataSource, sql, fetchSize, rowMapper, name, ...)
- → **빌더 패턴**으로 옵션을 명시적으로 주입

**Processor (함수형 인터페이스 람다)**:
- 비즈니스 로직은 도메인마다 달라서 표준 구현체가 거의 없음 (`CompositeItemProcessor`, `ClassifierCompositeItemProcessor`, `ValidatingItemProcessor` 정도)
- `ItemProcessor<I, O>`는 메서드가 하나인 **함수형 인터페이스**

```kotlin
fun interface ItemProcessor<I, O> {
    fun process(item: I): O?
}
```

- → **람다**로 변환 로직만 짧게 작성하면 끝

> 참고: Reader/Writer도 커스텀 구현(예: 외부 API 호출 Reader)이라면 `ItemReader { ... }` / `ItemWriter { ... }` 람다로 직접 작성 가능. 단지 표준 패턴(DB/파일)에는 이미 좋은 빌더가 있어서 안 쓸 뿐.

> **면접 예상 질문:** Spring Batch에서 Reader/Writer는 빌더 패턴으로 만들고 Processor는 람다로 작성하는 경우가 많다. 이런 차이가 발생하는 이유를 함수형 인터페이스와 표준 구현체 제공 여부 관점에서 설명하라.

---

### ItemProcessor null 반환 — 의도된 필터링

Processor가 `null`을 반환하면 그 item은 **Writer로 전달되지 않는다**. 단, **chunk 전체가 건너뛰는 게 아니라 그 item 하나만** 빠진다.

```
Reader → [item1, item2, item3, item4, item5]   (5개 읽음)
Processor → item3에서 null 반환 (필터링)
Writer ← [out1, out2,        out4, out5]       (4개만 받음)
```

활용 예시:
- 알림 옵트인하지 않은 사용자 제외 (`pushOptIn == false`)
- 만료된 device_token 보유 사용자 제외
- 비즈니스 룰상 처리 불필요한 데이터 제외

Spring Batch는 이 케이스를 메타데이터에 **`filterCount`** 로 집계한다 (별도 카운터로, write에서 제외된 건수).

> **면접 예상 질문:** Spring Batch의 ItemProcessor가 null을 반환하면 어떤 동작이 발생하는가? Reader가 읽은 chunk 전체가 영향을 받는가, 아니면 해당 item 하나만 영향을 받는가? 이 동작은 어떤 비즈니스 시나리오에 적합한가?

---

### filter vs skip — 같은 "건너뛴다"라도 의미가 다르다

면접에서 헷갈리는 포인트. **둘 다 "건너뛴다"는 표현을 쓰지만 트리거와 동작이 완전히 다르다.**

| 구분 | Processor null 반환 (filter) | skip 정책 (faultTolerant) |
|------|------|------|
| **트리거** | 정상 흐름 (의도된 필터링) | **예외 발생** (실패) |
| **동작** | 그 item을 Writer로 안 넘김 | chunk rollback → 한 건씩 재시도 → 문제 item만 격리 |
| **메타데이터** | `filterCount` 증가 | `skipCount` 증가 |
| **트랜잭션** | rollback 없음 | rollback 발생 |
| **사용 예** | 옵트인 false, 토큰 만료 등 비즈니스 룰 | DB 제약 위반, 외부 API timeout 등 예외 케이스 |

같은 "사용자를 건너뛴다"라도:
- 옵트인 안 한 사용자는 `null` 반환 (filter) — **예외 던지지 말 것**. 트랜잭션을 굳이 rollback 시킬 이유가 없음
- DB write 중 제약 위반은 예외 발생 → `.faultTolerant().skip(...)` 으로 skip — 이건 진짜 실패의 격리

> **면접 예상 질문:** Spring Batch에서 ItemProcessor의 null 반환(filter)과 faultTolerant skip 정책은 어떻게 다른가? 트리거, 트랜잭션 동작, 메타데이터 집계 관점에서 비교하라. 옵트인하지 않은 사용자를 건너뛰어야 한다면 어느 쪽으로 구현해야 하는가?

---

## 학습 정리

- chunk Step의 세 구성요소: **Reader = 인프라 (입력 어댑터)**, **Processor = 비즈니스 로직 (변환/필터링)**, **Writer = 인프라 (출력 어댑터)**.
- Reader/Writer는 표준 구현체가 많고 옵션이 다양해서 **빌더 패턴**. Processor는 `ItemProcessor<I, O>` 함수형 인터페이스라 **람다**가 자연스럽다.
- ItemProcessor가 **`null`을 반환하면 그 item만 Writer로 안 넘어감** (chunk 전체가 빠지는 게 아님). `filterCount`로 집계.
- **filter (null 반환)** 와 **skip (예외 격리)** 는 다른 개념. filter는 의도된 필터링·트랜잭션 그대로 commit, skip은 예외 발생·rollback·재시도·격리.
- 비즈니스 룰 필터링에 예외를 던지지 말 것 — 트랜잭션을 굳이 rollback시킬 이유가 없다. `null` 반환이 정답.
