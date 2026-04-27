# @StepScope와 Late Binding

> 날짜: 2026-04-27

## 내용

### @StepScope가 필요한 이유 — Late Binding

Spring Batch에서 `@StepScope`가 필요한 본질적 이유는 **`jobParameters`가 주입되는 시점이 Step 실행 시점이기 때문**이다.

**시간 순서로 이해하기:**
```
1. 애플리케이션 시작 (스프링 컨텍스트 로딩)
   → 일반 @Bean들은 이때 생성됨 (싱글톤)
   → 이때는 jobParameters 없음! ❌

2. API 호출 → Job 실행 → jobParameters 생성
   → "targetDate=2026-04-27" 같은 값이 이때 들어옴

3. Step 시작
   → @StepScope 달린 Bean이 이때 생성됨
   → 이제야 jobParameters 사용 가능! ✅
```

**Late Binding 패턴:** `@StepScope` = **"Step이 실행될 때까지 Bean 생성을 미뤄라"**.

`@StepScope` 없이 일반 `@Bean`이라면:
- 앱 시작 시점에 생성 시도 → `@Value("#{jobParameters['targetDate']}")` 평가 시도
- **`jobParameters`가 아직 없음** → 에러

```java
@Bean
@StepScope
public JpaPagingItemReader<Settlement> settlementReader(
    @Value("#{jobParameters['targetDate']}") LocalDate targetDate,
    EntityManagerFactory entityManagerFactory) {
    // ...
}
```

> **면접 예상 질문:** `@StepScope`는 왜 필요한가? Late Binding이란 무엇인가?

---

### @StepScope vs @JobScope vs 싱글톤

| 스코프 | 생성 시점 | 생명주기 |
|---|---|---|
| **싱글톤(기본)** | 애플리케이션 시작 | 앱 종료까지 |
| **@JobScope** | Job 시작 | Job 종료까지 |
| **@StepScope** | Step 시작 | Step 종료까지 |

**선택 기준:**
- **`@JobScope`** — Job 전체에서 공유, 여러 Step이 같은 인스턴스 사용
- **`@StepScope`** — Step마다 새 인스턴스, **Reader/Processor/Writer는 보통 이쪽**

**실무 권장: `@StepScope`를 기본**으로 사용
- Step별 격리 (다른 Step에 영향 X)
- 멀티 Step Job에서 Step별 다른 jobParameters 주입 가능
- 멀티스레드 Step에서도 안전

> **면접 예상 질문:** `@StepScope`와 `@JobScope`의 차이는? Reader/Writer에 `@StepScope`를 권장하는 이유는?

---

### Job, Step, Reader/Processor/Writer 구조

```
Job (settlementJob) — 배치 작업 전체
  └─ Step (settlementStep) — 하나의 처리 단계
        ├─ Reader  — 데이터 읽기
        ├─ Processor — 가공
        └─ Writer  — 저장
```

**비유 — 공장의 생산 라인:**
- **Job** = 공장 전체 (오늘의 생산 작업)
- **Step** = 하나의 생산 라인 (조립 라인 1개)
- **Reader/Processor/Writer** = 라인 위의 기계들

**Step이 여러 개일 수도 있다:**
```
Job (월말 정산)
  ├─ Step 1: 정산 계산 (Reader → Processor → Writer)
  ├─ Step 2: 정산 알림 발송 (Reader → Processor → Writer)
  └─ Step 3: 보고서 생성 (Tasklet)
```

**`@StepScope` Bean은 Step마다 새로 생성:**
```
Step 1 시작 → settlementReader 인스턴스 1 생성 → Step 1 종료 → 소멸
Step 2 시작 → settlementReader 인스턴스 2 생성 (새로!) → Step 2 종료 → 소멸
```

**왜 매번 새로 생성?** 각 Step의 **독립적 상태 격리**:
- Step 1의 EntityManager가 Step 2에 영향 X
- Step 1의 페이징 상태가 Step 2에 영향 X
- 멀티스레드 Step에서 동시성 문제 방지

> **면접 예상 질문:** Job/Step/Reader 구조는? `@StepScope` Bean은 Step이 여러 개일 때 몇 번 생성되는가?

---

### SpEL `#{jobParameters[...]}` — 약속된 이름

**왜 `jobParameters`라는 문자열을 써야 하는가?**

→ Spring Batch가 **SpEL 평가 컨텍스트에 미리 등록하는 "약속된 이름"** 이기 때문.

**Spring Batch가 약속한 변수들:**
```java
#{jobParameters['targetDate']}      // Job 파라미터
#{jobExecutionContext['key']}       // Job 실행 컨텍스트
#{stepExecutionContext['key']}      // Step 실행 컨텍스트
```

**내부 동작:**
1. `@StepScope` Bean 생성 시점
2. Spring Batch가 SpEL 평가 컨텍스트에 변수들을 **미리 등록**
   - `jobParameters` → 현재 Job 파라미터 Map
   - `jobExecutionContext` → 현재 Job 실행 컨텍스트
   - `stepExecutionContext` → 현재 Step 실행 컨텍스트
3. `#{jobParameters['targetDate']}` 평가 → Map에서 키로 값 꺼냄

임의로 `myParams`라고 쓰면 Spring Batch는 그 이름을 모르므로 **에러**.

> **면접 예상 질문:** `jobParameters`라는 이름은 어디서 오는가? Spring Batch가 SpEL 컨텍스트를 어떻게 구성하는가?

---

### 왜 어노테이션 방식이 아닌 SpEL 문자열 방식인가?

**핵심: SpEL의 표현력**

자바 어노테이션 속성은 **컴파일 타임 상수만** 받는다:
- `int`, `String`, `Class<?>`, `enum`, 다른 어노테이션 (또는 이들의 배열)
- **변수/메서드 호출 결과 ❌**

**SpEL로 가능한 표현:**
```java
@Value("#{jobParameters['targetDate']}")              // 단순 추출
@Value("#{jobParameters['date'] + '-batch'}")         // 문자열 조합
@Value("#{jobParameters['amount'] * 1.1}")            // 산술 연산
@Value("#{jobParameters['mode'] == 'TEST' ? 100 : 1000}") // 조건
@Value("#{configBean.maxRetry}")                      // 다른 빈 참조
```

**가상 어노테이션 방식이라면:**
```java
@JobParameter("targetDate") LocalDate targetDate;  // 단순만 가능
// 복잡한 표현식 → 불가능
```

| 방식 | 장점 | 단점 |
|---|---|---|
| **SpEL 문자열** | 유연, 모든 표현식 | 컴파일 검증 X, 오타 위험 |
| **전용 어노테이션** | 타입 안전, 명확 | 표현 제한적 |

> **면접 예상 질문:** Spring이 SpEL 문자열 방식을 채택한 이유는? 어노테이션 방식의 한계는?

---

### SpEL 오타 위험을 줄이는 패턴 — 상수 추출

SpEL의 단점은 **컴파일 타임에 오타 검증이 안 된다는 것**. 상수로 추출하면 보완 가능.

```java
public static final String PARAM_TARGET_DATE = "targetDate";

@Bean
@StepScope
public JpaPagingItemReader<Settlement> settlementReader(
    @Value("#{jobParameters['" + PARAM_TARGET_DATE + "']}") LocalDate targetDate, ...) {
    // ...
}
```

**장점:**
- `targetDate` 오타 방지 (한 곳에서 관리)
- IDE에서 사용처 추적 가능 (Find Usages)
- 파라미터 이름 변경 시 한 곳만 수정

**면접 답변 템플릿:**
> "SpEL 문자열 방식은 컴파일 타임 검증이 안 되어 오타가 있어도 빌드가 성공하고 런타임에 에러가 납니다. 저는 이를 보완하기 위해 `public static final String PARAM_TARGET_DATE = "targetDate"` 같은 상수로 추출해 사용합니다. IDE에서 사용처 추적도 가능하고 오타 위험도 줄일 수 있습니다."

> **면접 예상 질문:** SpEL 문자열의 단점을 어떻게 보완할 수 있는가?

---

## 학습 정리

- **`@StepScope`는 Late Binding 패턴** — Step 실행 시점에 Bean을 생성해 `jobParameters` 같은 런타임 값을 주입받게 함
- 일반 `@Bean`은 싱글톤이라 앱 시작 시점에 생성되어 `jobParameters` 주입 불가
- **`@JobScope`는 Job 단위, `@StepScope`는 Step 단위** — Reader/Processor/Writer는 보통 `@StepScope`
- Step이 여러 개면 `@StepScope` Bean도 **Step마다 새로 생성** → 격리/멀티스레드 안전
- **`jobParameters` / `jobExecutionContext` / `stepExecutionContext`** 는 Spring Batch가 SpEL 컨텍스트에 미리 등록하는 약속된 변수
- 자바 어노테이션은 컴파일 상수만 받기 때문에 **SpEL 문자열 방식이 표현력 측면에서 유리**
- SpEL의 컴파일 검증 부재 단점은 **`public static final` 상수 추출**로 보완

## 참고

- Spring Batch 공식 문서 — Late Binding of Job and Step Attributes
- `org.springframework.batch.core.scope.StepScope` 소스
- Spring Expression Language(SpEL) 공식 문서
