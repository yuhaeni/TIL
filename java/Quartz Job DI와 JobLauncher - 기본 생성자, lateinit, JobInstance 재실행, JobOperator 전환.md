# Quartz Job DI와 JobLauncher — 기본 생성자, lateinit, createBean, JobInstance 재실행, JobOperator 전환

> 날짜: 2026-06-02

## 내용

배경: Quartz `cron`으로 Spring Batch Job을 발화시키는 `DiaryReminderQuartzJob` 코드를 분석하며 DI 방식·Kotlin 키워드·IntelliJ 경고·`JobLauncher` 역할·`JobOperator` 마이그레이션까지 한번에 정리했다.

```kotlin
@Suppress("SpringJavaInjectionPointsAutowiringInspection")
class DiaryReminderQuartzJob : QuartzJobBean() {
    @Autowired lateinit var jobOperator: JobOperator
    @Autowired @Qualifier("diaryReminderJob") lateinit var diaryReminderJob: Job

    override fun executeInternal(context: JobExecutionContext) {
        val targetDate = LocalDate.now(ZoneId.of("Asia/Seoul"))
        val params = JobParametersBuilder()
            .addLocalDate("targetDate", targetDate)
            .addLong("runAt", System.currentTimeMillis()) // JobInstance 중복 방지
            .toJobParameters()
        jobOperator.start(diaryReminderJob, params)
    }
}
```

### Quartz Job 인스턴스화 — 누가 만드는가, 생성자 주입 가능한가

일반 Spring 빈은 **생성자 주입**이 권장된다. 불변성, 테스트 용이성, 순환참조 조기 발견(Fail Fast). 그런데 Quartz Job은 인스턴스화 주체가 다르다.

| 컴포넌트 | 누가 만드는가 |
|---|---|
| 일반 `@Component` / `@Service` | Spring이 부팅 시점에 생성자 주입하면서 생성 |
| `QuartzJobBean` 상속 클래스 | cron 발화 시점에 **Quartz Scheduler**가 JobFactory를 통해 생성 |

Quartz는 `JobFactory.newJob()` 으로 객체를 만들고, 내부적으로 `Class.getDeclaredConstructor().newInstance()` 즉 **기본 생성자**를 호출한다. 인자 없는 생성자 → 생성자에 의존성을 전달할 방법 자체가 없다.

따라서 Quartz Job은 **생성자 주입이 권장이 아니라 물리적으로 불가능**하며, 필드 주입(`@Autowired`)을 써야 한다.

> **면접 예상 질문:** 일반 Spring 빈에서는 생성자 주입이 권장되는데, Quartz Job에서는 왜 필드 주입을 쓸 수밖에 없는지 인스턴스 생성 주체와 호출되는 생성자 종류까지 설명해보세요.

---

### Kotlin lateinit — non-null 타입과 늦은 주입의 충돌 해결

Kotlin은 **모든 타입이 기본적으로 non-null**이다. `JobOperator` 타입 변수에는 null이 들어갈 수 없다(`JobOperator?` 처럼 `?`를 붙여야 nullable).

컴파일러는 둘 중 하나를 강제한다:
1. 선언과 동시에 초기화 (`var name: String = "기본값"`)
2. 생성자에서 초기화 (`class Foo(val launcher: JobOperator)`)

Quartz Job은 둘 다 불가능하다.
- 생성자에서 못 받음 (Quartz가 기본 생성자로 만듦)
- 선언 시점에 `JobOperator` 인스턴스를 어디서도 가져올 수 없음

이 딜레마를 푸는 키워드가 `lateinit`. 컴파일러에게:

> "이 변수는 non-null인데 지금은 초기화 못 해. 내가 사용하기 전에 누군가 값을 넣어줄 거야, 믿어줘."

약속을 어기고 주입 전에 접근하면 `UninitializedPropertyAccessException` (Java NPE와 유사한 안전망).

`lateinit` 사용 제약:

| 제약 | 이유 |
|---|---|
| `var`여야 함 | 나중에 값이 채워지므로 변경 가능해야 함 |
| primitive 타입 불가 | `Int`, `Boolean` 등은 별도 메커니즘 |
| `val` 불가 | 한 번만 할당되는 불변 — "나중 할당" 의미와 충돌 |

전형적 사용처: DI 프레임워크 필드 주입(`@Autowired`, `@Inject`), 테스트의 `@BeforeEach` 세팅.

> **면접 예상 질문:** Kotlin에서 `lateinit var`와 `var name: String? = null` 의 차이를 null safety 관점에서 설명하고, DI 필드에 왜 전자를 선호하는지 답해보세요.

---

### Spring Boot Quartz의 @Autowired 작동 원리 — createBean()

여기가 가장 헷갈리는 지점. 결론부터: **스톡 Spring Boot에서 `@Autowired`는 정상 작동한다.**

[Spring Boot의 `QuartzAutoConfiguration`](https://github.com/spring-projects/spring-boot/blob/main/module/spring-boot-quartz/src/main/java/org/springframework/boot/quartz/autoconfigure/QuartzAutoConfiguration.java)이 등록하는 JobFactory:

```java
SpringBeanJobFactory jobFactory = new SpringBeanJobFactory();
jobFactory.setApplicationContext(applicationContext);
schedulerFactoryBean.setJobFactory(jobFactory);
```

핵심은 [`SpringBeanJobFactory.createJobInstance()`](https://github.com/spring-projects/spring-framework/blob/main/spring-context-support/src/main/java/org/springframework/scheduling/quartz/SpringBeanJobFactory.java) 내부:

```java
Object job = (this.applicationContext != null ?
    this.applicationContext.getAutowireCapableBeanFactory()
        .createBean(bundle.getJobDetail().getJobClass()) :   // ← 여기!
    super.createJobInstance(bundle));
```

`applicationContext`가 set 되어있으면(Spring Boot가 자동으로 set) → **`createBean(Class)`** 호출. `createBean()`이 하는 일:

1. 기본 생성자로 인스턴스화
2. **BeanPostProcessor들 차례로 실행**
3. 그 중 `AutowiredAnnotationBeanPostProcessor`가 **`@Autowired`가 붙은 필드/세터를 찾아 주입**

즉 Spring의 풀 라이프사이클을 Quartz Job 인스턴스에도 적용한다. 그래서 별도의 커스텀 `AutowiringSpringBeanJobFactory`를 직접 만들 필요가 없다. (Spring 4 이전엔 필요했던 패턴이지만, 현재는 프레임워크가 알아서 해결.)

**`@Autowired` 없이 그냥 `lateinit var jobOperator: JobOperator` 만 쓰면?**
→ `AutowiredAnnotationBeanPostProcessor`가 처리할 마커가 없음 → 주입 안 됨 → 호출 시 `UninitializedPropertyAccessException`.

**필드 주입은 항상 `@Autowired` (또는 `@Inject`) 마커가 필요**. Spring이 "어떤 필드에 무엇을 넣어야 할지" 알 방법이 그것뿐이기 때문. (생성자 주입은 생성자 시그니처로 매칭 가능해서 Spring 4.3+에선 단일 생성자에 한해 `@Autowired` 생략 가능하지만, 필드 주입은 절대 생략 불가.)

> **면접 예상 질문:** Spring Boot Quartz에서 `@Autowired`가 어떻게 동작하는지 `SpringBeanJobFactory`의 `createBean()` 흐름으로 설명하고, 필드 주입 시 `@Autowired`를 생략할 수 없는 이유를 답해보세요.

---

### IntelliJ "Autowired members must be defined in valid Spring bean" 경고

Quartz Job 클래스에 `@Autowired`를 쓰면 IntelliJ가 경고를 띄운다:

> Autowired members must be defined in valid Spring bean (@Component | @Service | ...)

정적 분석 관점에서는 맞는 말 — 클래스에 stereotype(`@Component`, `@Service` 등)이 없으니 "Spring 빈처럼 보이지 않는다." 하지만 위에서 본 것처럼 **런타임에는 `createBean()`이 알아서 처리**하므로 `@Autowired`는 정상 작동한다. **false positive.**

해결: 클래스에 `@Suppress`를 붙여 해당 인스펙션만 끄기.

```kotlin
@Suppress("SpringJavaInjectionPointsAutowiringInspection")
class DiaryReminderQuartzJob : QuartzJobBean() { ... }
```

**주의: `@Component`를 추가로 붙이는 것은 잘못된 해결책.** 그러면 Spring이 빈으로 하나 만들고, Quartz가 또 `newInstance()`로 하나 만들어서 **두 개의 다른 인스턴스**가 생긴다. Quartz가 실행하는 건 자기가 만든 쪽이라 Spring 측 빈에 들어간 상태는 무의미.

> **면접 예상 질문:** Quartz Job에 `@Component`를 붙이면 어떤 문제가 생기는지, 인스턴스 생성 주체 관점에서 설명해보세요.

---

### Spring Batch JobLauncher — Job 실행 오케스트레이션

`JobLauncher` (그리고 후술할 `JobOperator`)는 단순히 "Job을 실행시켜주는 인터페이스"가 아니라 **Job 실행을 둘러싼 부가 작업을 책임지는 오케스트레이터**다. 관심사 분리(SoC) 관점에서 보면 명확하다.

| 컴포넌트 | 관심사 |
|---|---|
| `Job` / `Step` | **무엇을** 처리할지 — 비즈니스 로직 (예: 일기 알림 발송) |
| `JobLauncher` / `JobOperator` | **어떻게** 실행할지 — 파라미터 검증, JobInstance 식별, 동기/비동기 결정 |
| `JobRepository` | **실행 결과를** 어디에 저장할지 — 메타데이터 영속화 |

`jobOperator.start(job, params)` 한 줄이 내부적으로 하는 일:

1. `JobRepository`에 조회: "이 jobName + 이 JobParameters 조합의 JobInstance가 이미 있는가?"
2. 있다면 상태 확인 → COMPLETED면 거부, FAILED면 재실행(restart) 처리
3. 새 `JobExecution` 기록 생성 (시작 시각, 상태)
4. `TaskExecutor` 설정에 따라 동기/비동기 실행
5. 실행 결과를 다시 `JobRepository`에 업데이트

즉 Quartz에서 호출 한 줄이 **Spring Batch 메타데이터 추적 시스템 전체를 활성화**한다.

> **면접 예상 질문:** Spring Batch에서 `Job`이 자기 `execute()` 메서드를 직접 갖지 않고 `JobLauncher`/`JobOperator`라는 별도 컴포넌트가 존재하는 이유를 관심사 분리 관점에서 설명해보세요.

---

### JobInstance 중복 방지 — runAt 파라미터를 추가하는 이유

`addLong("runAt", System.currentTimeMillis())` 의 의도는 "동시 실행 막기"가 아니라 **JobInstance 식별 정책** 관련이다.

**Spring Batch의 재실행 정책:**

| 이전 JobInstance 상태 | 같은 파라미터로 다시 실행 시 |
|---|---|
| COMPLETED (성공) | `JobInstanceAlreadyCompleteException` — **거부** |
| FAILED | **restart 허용** — 이전 ExecutionContext 이어받아 재개 |

JobInstance는 `(jobName, JobParameters)` 조합으로 유일 식별. 같은 파라미터로 성공한 Job은 두 번 못 돈다(멱등성).

**`targetDate`만으론 부족한 이유:**

cron이 매일 9시 발화면 `targetDate`가 매일 바뀌니 새 JobInstance로 인식. 그런데 운영 중 흔한 케이스:
- 오늘 9시 배치가 정상 완료됐는데, 데이터 이슈로 **같은 날짜로 재실행** 필요
- `targetDate=2026-06-02` 그대로 → 이미 COMPLETED → 거부

`runAt`에 `currentTimeMillis()`를 넣으면 호출마다 값이 달라 → **강제로 새 JobInstance** 생성.

(참고: 이전 [Cursor 페이징 구현 - getPage 0과 멱등 restart](Cursor%20페이징%20구현%20-%20getPage%200과%20멱등%20restart.md)에서 다룬 `JobInstanceAlreadyCompleteException`과 동일 메커니즘.)

> **면접 예상 질문:** Spring Batch에서 JobInstance가 어떻게 식별되는지, 그리고 동일 파라미터로 이미 성공한 Job을 강제로 다시 돌리고 싶을 때 어떻게 처리하는지 설명해보세요.

---

### JobLauncher Deprecated (Spring Batch 6.0) — JobOperator로 통합

Spring Batch 6.0부터 `JobLauncher` 인터페이스가 deprecated 됐다. **6.2 이상에서 제거 예정.**

```java
@Deprecated(since = "6.0", forRemoval = true)
public interface JobLauncher {
    JobExecution run(Job job, JobParameters jobParameters) throws ...;
}
```

대체재는 `JobOperator` — 별도 인터페이스가 아니라 `JobOperator extends JobLauncher`. 즉 통합.

| 항목 | JobLauncher (deprecated) | JobOperator (6.0+) |
|---|---|---|
| 실행 (run/start) | ✅ | ✅ (상속받음) |
| 운영 기능 | ❌ | ✅ start / restart / stop / abandon |
| 빈 등록 | 별도 `JobLauncher` 빈 | **`JobOperator` 하나로 통합** |

6.0 마이그레이션 가이드 핵심:
- `JobStep#setJobLauncher` → `setJobOperator`
- `JobStepBuilder#launcher` → `operator`
- `JobLauncherTestUtils` → `JobOperatorTestUtils`, `launch*` 메서드 → `start*`
- `JobLaunchingGateway`, `JobLaunchingMessageHandler` 생성자도 `JobOperator` 수용

운영 기능까지 한 빈에서 다 쓸 수 있다는 게 핵심 이점. 별도 `JobOperator` 빈을 또 주입할 필요가 없어졌다.

> **면접 예상 질문:** Spring Batch 6.0에서 `JobLauncher`가 deprecated된 이유를 인터페이스 통합 관점에서 설명하고, `JobOperator`로 마이그레이션할 때 주의할 변경점을 답해보세요.

---

## 학습 정리

- Quartz Job은 스케줄러가 **기본 생성자로 인스턴스화** → 생성자 주입 불가 → 필드 주입(`@Autowired`) 강제
- Kotlin `lateinit var`는 **non-null 타입 + 늦은 주입**의 충돌을 컴파일러에게 명시적으로 양해 구하는 키워드
- 스톡 Spring Boot의 `SpringBeanJobFactory`는 내부적으로 **`autowireCapableBeanFactory.createBean()`** 호출 → `AutowiredAnnotationBeanPostProcessor`가 `@Autowired` 처리 → 커스텀 팩토리 불필요
- IntelliJ의 "Autowired members must be defined in valid Spring bean" 경고는 **false positive**. `@Suppress("SpringJavaInjectionPointsAutowiringInspection")` 로 끈다. `@Component` 추가는 절대 금지 (인스턴스 중복)
- 필드 주입은 항상 `@Autowired` 마커 필수 (Spring 4.3+ 단일 생성자에서 `@Autowired` 생략은 생성자 주입에만 적용)
- `JobInstance = (jobName, JobParameters)` 유일 식별 → COMPLETED는 거부, FAILED는 restart → 강제 재실행은 `runAt` 같은 unique 파라미터로 새 인스턴스 생성
- Spring Batch 6.0부터 `JobLauncher` deprecated, **`JobOperator extends JobLauncher`** 로 통합 (6.2 제거 예정)

## 참고

- [Spring Boot QuartzAutoConfiguration 소스](https://github.com/spring-projects/spring-boot/blob/main/module/spring-boot-quartz/src/main/java/org/springframework/boot/quartz/autoconfigure/QuartzAutoConfiguration.java)
- [Spring Framework SpringBeanJobFactory 소스](https://github.com/spring-projects/spring-framework/blob/main/spring-context-support/src/main/java/org/springframework/scheduling/quartz/SpringBeanJobFactory.java)
- [Spring Batch 6.0 Migration Guide](https://github.com/spring-projects/spring-batch/wiki/Spring-Batch-6.0-Migration-Guide)
- [What's new in Spring Batch 6](https://docs.spring.io/spring-batch/reference/whatsnew.html)
- [JobOperator (Spring Batch 6.0.3 API)](https://docs.spring.io/spring-batch/reference/api/org/springframework/batch/core/launch/JobOperator.html)
