# Spring DI/IoC와 Bean 생성 순서

> 날짜: 2026-04-28

## 내용

### `@Configuration` + `@Bean` — 컨테이너가 빈을 등록하는 원리

`@Configuration` 클래스의 `@Bean` 메서드는 **개발자가 직접 호출하지 않는다**. 애플리케이션 시작 시점에 **Spring 컨테이너(`ApplicationContext`)** 가 호출하고, 그 반환값을 **빈으로 등록**한다.

**부팅 흐름:**
```
1. 컴포넌트 스캔 → @Configuration 클래스 발견
2. 그 안의 @Bean 메서드들을 호출 (의존성 그래프 순서대로)
3. 반환된 객체를 BeanFactory에 등록 (싱글톤이 기본)
4. 다른 빈들이 @Autowired/생성자 주입으로 가져다 씀
```

**`@Configuration`의 숨은 장치 — CGLIB 프록시:**
- `@Configuration` 클래스는 Spring이 **CGLIB로 프록시화**
- 같은 `@Configuration` 안에서 `@Bean` 메서드를 직접 호출해도 **싱글톤 보장** (실제 호출은 컨테이너로 위임됨)
- `@Bean`만 단독 사용(`@Component`에 `@Bean`)하면 **lite mode** — 프록시 X, 호출 시마다 새 객체

> **면접 예상 질문:** `@Configuration`의 `@Bean` 메서드는 누가 호출하는가? `@Configuration`과 단순 `@Component + @Bean`의 차이는?

---

### 빈 이름과 주입 매칭 — 타입 우선, 이름 보조

```java
@Bean
public Job settlementJob(JobRepository repo, Step settlementStep) { ... }
```

위 메서드는 **메서드명이 빈 이름**이 되어 `"settlementJob"`으로 등록된다. 주입 시 매칭은 두 단계:

| 단계 | 기준 | 예시 |
|---|---|---|
| 1차 | **타입(Type)** 으로 후보 검색 | `Job` 타입 빈 모두 |
| 2차 | 후보 여러 개면 **이름(Name)** 으로 좁힘 | 변수명 = 빈 이름 매칭 |

**시나리오:**

| 상황 | 결과 |
|---|---|
| `Job` 타입 빈 1개 | 변수명 달라도 **타입 매칭으로 OK** |
| `Job` 타입 빈 2개+ + 변수명 일치 | 이름으로 매칭 OK |
| `Job` 타입 빈 2개+ + 변수명 불일치 | **`NoUniqueBeanDefinitionException`** |

**같은 타입 다중 빈 — `@Qualifier`로 명시:**
```java
public SettlementBatchService(
    @Qualifier("settlementJob") Job job
) { ... }
```

**주의 — 이름 충돌 함정:**
```java
public static final String JOB_NAME = "settlementJob";  // Spring Batch JobRepository 식별자
private final Job settlementJob;                         // Spring DI 변수명
```
**둘은 우연히 이름이 같을 뿐 다른 개념** — 헷갈리지 말 것.

> **면접 예상 질문:** Spring DI에서 타입과 이름 중 무엇이 우선인가? `@Qualifier`는 언제 쓰는가?

---

### 빈 생성 순서 — 개념적 계층 ≠ 의존성 방향

```java
@Bean
public Job settlementJob(JobRepository repo, Step settlementStep) {
                                            // ↑ Step에 의존
    return new JobBuilder(JOB_NAME, repo).start(settlementStep).build();
}
```

**누가 먼저 만들어지는가? → `settlementStep`이 먼저.**

> 💡 **핵심 통찰: 개념적 계층(Job > Step)과 빈 생성 순서는 별개**

Spring은 **의존성 그래프(Dependency Graph)** 를 분석해 **의존되는 쪽(재료)부터** 먼저 생성한다. 자동차 조립 시 바퀴가 먼저 있어야 차체에 끼울 수 있는 것과 동일.

**의존성 그래프 예:**
```
JobRepository ──┐
                ├─→ Step (settlementStep)
EntityManager ──┘         │
                          └─→ Job (settlementJob)
                                      │
                                      └─→ SettlementBatchService
```

**순환 의존성(Circular Dependency):**
- A → B, B → A 형태면 그래프 분석 실패 → `BeanCurrentlyInCreationException`
- 해결: 설계 분리, `@Lazy`, 세터 주입 (생성자 주입은 순환 시 즉시 실패해서 오히려 안전)

> **면접 예상 질문:** Spring은 빈 생성 순서를 어떻게 결정하는가? 순환 의존성이 발생하면 어떻게 되는가?

---

### `@StepScope` — Lazy 생성과 Late Binding

`@StepScope`가 붙은 빈은 **컨테이너 시작 시점이 아니라 Step 실행 시점에 lazy 생성**된다.

```java
@Bean
@StepScope
public JpaPagingItemReader<Settlement> settlementReader(
    @Value("#{jobParameters['targetDate']}") LocalDate targetDate, ...) { ... }
```

**왜 lazy?**
- 컨테이너 시작 시점엔 `jobParameters`가 아직 없음
- Step 실행 시 비로소 SpEL `#{jobParameters[...]}` 평가 가능
- 이를 **Late Binding** 패턴이라 함

→ 일반 빈은 부팅 시점에 생성, `@StepScope` 빈은 **Step마다 새로** 생성되어 격리/멀티스레드 안전.

> **면접 예상 질문:** `@StepScope` 빈은 일반 빈과 생성 시점이 어떻게 다른가? Late Binding이 필요한 이유는?

---

### IoC(제어의 역전) — 의존성을 컨테이너가 주입한다

| 일반 코드 | IoC |
|---|---|
| `new Job(new Step(new Reader(...)))` | Spring이 의존성 그래프를 따라 만들어 주입 |
| 내가 의존성 생성 책임 | 컨테이너에 위임 |
| 변경 시 호출부 다 수정 | 의존 대상 교체만 |

**IoC의 효과:**
- **결합도 감소** — 구현체가 아닌 인터페이스에 의존
- **테스트 용이** — 목 객체 주입 쉬움
- **OCP 자연스러움** — 새 구현 추가 시 기존 코드 수정 X

**DI(Dependency Injection)의 3가지 방식:**

| 방식 | 권장도 | 비고 |
|---|---|---|
| **생성자 주입** | ✅ 강력 권장 | 불변, 순환 의존 즉시 발견, 테스트 용이 |
| 세터 주입 | △ | 선택적 의존성에만 |
| 필드 주입 | ❌ | `final` 불가, 테스트 어려움 |

**`@RequiredArgsConstructor` (Lombok):** `final` 필드들로 자동 생성자 생성 → 생성자 주입 보일러플레이트 제거.

> **면접 예상 질문:** IoC와 DI의 차이는? 생성자 주입을 권장하는 이유 3가지는?

---

## 학습 정리

- `@Configuration` 클래스의 `@Bean` 메서드는 **컨테이너가 부팅 시점에 호출**해 반환값을 빈으로 등록
- `@Configuration`은 **CGLIB 프록시**로 싱글톤 보장 — `@Component + @Bean` lite mode와 다름
- 메서드명 = 빈 이름, 주입은 **타입 우선 → 이름 보조** 2단계
- 같은 타입 빈 여러 개면 `@Qualifier`로 명시
- 빈 생성 순서는 **개념적 계층이 아닌 의존성 그래프** 기준 — Job보다 Step이 먼저 생성
- `@StepScope` 빈은 **Step 실행 시점 lazy 생성**(Late Binding) — `jobParameters` SpEL 바인딩 위해 필요
- **IoC = 의존성 생성 책임을 컨테이너에 위임** — 결합도↓, 테스트 용이, OCP
- DI는 **생성자 주입 권장** — `final` + 순환 의존 즉시 발견 + 테스트 용이

## 참고

- Spring Framework Reference — IoC Container, `@Configuration`
- Spring Batch Reference — Late Binding of Job and Step Attributes
- CarrotSettle 정산 시스템 `SettlementBatchConfig` 설계 기반
