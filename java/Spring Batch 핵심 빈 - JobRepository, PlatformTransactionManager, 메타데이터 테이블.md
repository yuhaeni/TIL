# Spring Batch 핵심 빈 — JobRepository, PlatformTransactionManager, 메타데이터 테이블

> 날짜: 2026-05-30

## 내용

`JobBuilder`와 `StepBuilder`를 만들 때 항상 따라다니는 두 친구가 있다. `JobRepository`와 `PlatformTransactionManager`. 이 둘은 직접 `new`로 생성하지 않고 메서드 파라미터로 주입받는다. 정체와 협력 관계를 정리한다.

```kotlin
@Bean
fun diaryReminderJob(
    jobRepository: JobRepository,
    diaryReminderStep: Step,
): Job =
    JobBuilder(JOB_NAME, jobRepository)
        .start(diaryReminderStep)
        .build()

@Bean
fun diaryReminderStep(
    jobRepository: JobRepository,
    transactionManager: PlatformTransactionManager,
    // ...
): Step =
    StepBuilder(STEP_NAME, jobRepository)
        .chunk<DiaryReminderResult, DiaryReminderMessage>(CHUNK_SIZE, transactionManager)
        // ...
        .build()
```

---

### JobRepository — 메타데이터 기록자

Job/Step의 실행 이력을 **메타데이터 테이블에 기록**하는 저장소다. 배치 도중 서버가 죽어도 "어디까지 처리했는지", "어디서 실패했는지"가 DB에 남아 있어 재시작이 가능하다.

기록 대상 테이블:

- `BATCH_JOB_INSTANCE` — Job 인스턴스 정보 (Job 이름 + 파라미터 조합)
- `BATCH_JOB_EXECUTION` — Job 실행 단위 정보 (시작/종료 시간, STATUS, ExitCode)
- `BATCH_STEP_EXECUTION` — Step별 세부 통계 (read/write/skip/commit count, STATUS)

> **면접 예상 질문:** Spring Batch에서 Job이 실행 도중 서버가 종료됐을 때, 재시작 시 이전 진행 상황을 어떻게 복원하는가? JobRepository와 메타데이터 테이블의 역할로 설명하라.

---

### PlatformTransactionManager — chunk 단위 트랜잭션 실행자

`StepBuilder.chunk(500, transactionManager)`로 넘기면 **chunk 하나 = 트랜잭션 하나** 단위로 묶인다. 500개 모두 성공하면 commit, 중간에 예외가 발생하면 그 500개를 통째로 rollback 한다.

chunk 단위 트랜잭션이 없다면:
- 499번째에서 실패 → 앞서 처리한 498개는 commit 상태로 남음
- Job 재시작 시 498개를 또 처리 → **중복 처리 (멱등성 깨짐)**
- 알림 배치라면 같은 사용자에게 푸시 2번 발송

> **면접 예상 질문:** Spring Batch가 chunk 단위로 트랜잭션을 묶는 이유는 무엇인가? 만약 트랜잭션 경계가 없거나, chunk 크기를 1로 잡거나, 전체 Job을 하나의 트랜잭션으로 묶으면 각각 어떤 문제가 생기는가?

---

### 두 빈의 협력 관계 — 참조가 아니라 각자의 책임

처음에는 "`JobRepository`에 기록된 정보를 바탕으로 `PlatformTransactionManager`가 commit/rollback을 결정한다"고 오해하기 쉽다. **틀린 설명이다.** 둘은 참조 관계가 아니라 협력 관계다.

**실행 중 (런타임)**:
- `PlatformTransactionManager`: 예외 발생 시 **자기 판단으로 바로 rollback** (JobRepository 안 봄)
- `JobRepository`: "이 chunk가 rollback 됐고, skip 1건 발생했다"는 **결과를 기록**
- → 각자 자기 일을 함

**재시작 시점**:
- `JobRepository`를 **참조해서** "이 Job 어디서 멈췄지? 어디부터 다시 시작하지?"를 판단

| 빈 | 역할 | 정체성 |
|------|------|------|
| `JobRepository` | Job/Step 메타정보 기록 | 기록자 (관찰자) |
| `PlatformTransactionManager` | chunk 단위 commit/rollback 실행 | 실행자 |

> **면접 예상 질문:** Spring Batch에서 JobRepository와 PlatformTransactionManager는 어떤 관계인가? 둘 사이에 직접적인 호출/참조 관계가 있는가, 아니면 독립적으로 동작하는가?

---

### API 위치의 의미 — StepBuilder vs .chunk()

두 빈을 받는 **위치가 다른 것**이 우연이 아니다. 각 빈의 **적용 범위**가 호출 위치에 그대로 드러나도록 의도된 설계다.

```kotlin
StepBuilder(STEP_NAME, jobRepository)                              // ← Step 전체 책임
    .chunk<DiaryReminderResult, DiaryReminderMessage>(
        CHUNK_SIZE, transactionManager                             // ← chunk 단위 책임
    )
    .reader(diaryReminderReader)
    .processor(diaryReminderProcessor)
    .writer(diaryReminderWriter)
    .build()
```

| 위치 | 빈 | 적용 범위 |
|------|------|------|
| `StepBuilder(name, jobRepository)` | `JobRepository` | **Step 전체** (시작/종료/STATUS/count 집계) |
| `.chunk(size, transactionManager)` | `PlatformTransactionManager` | **chunk 단위** (commit/rollback 경계) |

만약 `.chunk()` 대신 `.tasklet()` 으로 Step을 구성하면 `transactionManager`는 **tasklet 한 번 실행 전체**를 묶는 트랜잭션이 된다. 같은 빈이라도 어떤 Step 빌더 메서드에 넘기느냐에 따라 트랜잭션 경계가 달라진다.

> **면접 예상 질문:** Spring Batch의 StepBuilder에서 jobRepository는 생성자 인자로, transactionManager는 .chunk() 인자로 받는다. 이렇게 받는 위치가 다른 이유는 무엇인가? .tasklet()으로 Step을 만들 때 transactionManager의 적용 범위는 어떻게 달라지는가?

---

### skip 동작 흐름 — rollback → 재시도 → 격리

skip은 "한 건 그냥 건너뛴다"가 아니라 **rollback + 한 건씩 재처리 + 문제 item만 격리**하는 영리한 메커니즘이다.

1. chunk(500개) 처리 중 예외 발생 → **그 chunk 전체 rollback**
2. Spring Batch가 **한 건씩 다시 처리** (chunk size를 1로 줄인 것처럼 동작)
3. 문제 일으킨 item만 **skip**, 나머지는 정상 처리 후 commit
4. skip된 건수는 `JobRepository`에 `skipCount`로 기록

> **면접 예상 질문:** Spring Batch의 skip 정책이 동작할 때, 실패한 chunk의 데이터는 어떻게 처리되는가? 단순히 실패한 한 건만 건너뛰는 것과 chunk 전체를 다시 처리하는 것의 차이는 무엇인가?

---

### Spring Boot 자동 설정 — spring-batch-starter와 IoC/DI

`JobRepository`, `PlatformTransactionManager`, `DataSource`를 `new`로 생성하지 않고 메서드 파라미터로 받을 수 있는 이유는 **Spring Boot 자동 설정** 덕분이다.

1. `build.gradle`에 `spring-batch-starter` 추가
2. Spring Boot가 시작 시 위 빈들을 자동으로 만들어서 **컨테이너에 등록**
3. `@Bean` 메서드가 호출될 때, 컨테이너가 **파라미터 타입을 보고 해당 빈을 주입**

용어 정리 (자주 혼동되는 셋):
- **IoC (제어의 역전, Inversion of Control)**: 객체 생성/관리의 주도권이 개발자 → Spring Container로 넘어간 것
- **DI (의존성 주입, Dependency Injection)**: 컨테이너가 필요한 빈을 꽂아주는 방식 (생성자/필드/setter)
- **DIP (의존성 역전 원칙, Dependency Inversion Principle)**: SOLID의 D, 구체 클래스가 아닌 추상에 의존하라는 **설계 원칙** (← 위 둘과 다른 개념)

> **면접 예상 질문:** Spring의 IoC, DI, DIP는 어떻게 다른가? IoC와 DI는 종종 함께 언급되는데, DIP와는 어떤 차이가 있는가?

---

### Job 메타데이터 vs Step 메타데이터 — 왜 둘 다 필요한가

`JobBuilder(JOB_NAME, jobRepository)`와 `StepBuilder(STEP_NAME, jobRepository)`처럼 Job과 Step **둘 다** JobRepository를 받는다. 각각 다른 레벨의 정보를 기록하기 때문이다.

**Job 레벨이 기록하는 것** (`BATCH_JOB_EXECUTION`):
- Job 시작/종료 시간
- Job 전체 STATUS (`STARTED`, `COMPLETED`, `FAILED`)
- Job Parameters (예: `targetDate=2026-05-30`)

**Step 레벨이 기록하는 것** (`BATCH_STEP_EXECUTION`):
- Step 이름과 STATUS
- `READ_COUNT`, `WRITE_COUNT`, `COMMIT_COUNT`, `ROLLBACK_COUNT`, `SKIP_COUNT`
- 어느 chunk까지 처리했는지

비유하면 **프로젝트 전체 보고서(Job)** 와 **개별 업무 보고서(Step)** 의 관계다. 프로젝트 요약만 있으면 "어디서 망했는지" 모르고, 업무 보고서만 있으면 "프로젝트가 끝났는지" 모른다.

> **면접 예상 질문:** Spring Batch의 메타데이터 테이블이 BATCH_JOB_EXECUTION과 BATCH_STEP_EXECUTION으로 나뉘어 있는 이유는 무엇인가? Job 레벨 정보와 Step 레벨 정보가 분리되어야 하는 실무적 이유를 설명하라.

---

### 재시작 메커니즘 — STATUS 컬럼으로 건너뛰기

Job에 Step이 3개 있고 2번째 Step에서 실패한 경우, 재시작 시 Spring Batch는 다음 흐름으로 동작한다.

1. `JobRepository`로 **이전 JobExecution**을 조회
2. 각 Step의 `BATCH_STEP_EXECUTION.STATUS`를 확인:
   - `COMPLETED` → **건너뜀** ✅
   - `FAILED` → **다시 실행** 🔄
3. 1번 Step이 `COMPLETED`면 자동 스킵, 2번 Step부터 재실행

이것이 동일한 JobInstance(Job 이름 + JobParameters 조합) 재시작 시의 기본 동작이다. JobInstance가 이미 `COMPLETED` 상태라면 재시작 자체가 `JobInstanceAlreadyCompleteException`으로 거부된다.

> **면접 예상 질문:** Spring Batch에서 동일한 JobParameters로 실패한 Job을 재시작할 때, 이미 성공한 Step은 어떻게 건너뛰는가? 만약 모든 Step이 COMPLETED인 JobInstance를 재실행하려고 하면 어떻게 되는가?

---

## 학습 정리

- **`JobRepository`** = Job/Step 메타데이터 기록자 (`BATCH_JOB_EXECUTION`, `BATCH_STEP_EXECUTION` 등에 기록). 재시작과 이력 추적의 근거.
- **`PlatformTransactionManager`** = chunk 단위 트랜잭션 실행자. 예외 발생 시 자기 판단으로 rollback, JobRepository를 참조하지 않음.
- 두 빈은 **참조 관계가 아니라 협력 관계** — 각자 자기 책임을 다하면서 Step을 함께 굴린다.
- `StepBuilder(name, jobRepository)` vs `.chunk(size, transactionManager)` — **빈을 받는 위치가 곧 적용 범위**다. JobRepository는 Step 전체, TransactionManager는 chunk 단위. `.tasklet()`이면 tasklet 실행 전체로 경계가 달라진다.
- skip은 "한 건 건너뛰기"가 아니라 **chunk rollback → 한 건씩 재처리 → 문제 item만 격리** 메커니즘.
- Spring Boot의 `spring-batch-starter`가 두 빈을 자동 등록 (IoC/DI). IoC는 제어의 역전, DI는 주입 방식, DIP는 SOLID 설계 원칙 — 셋은 다른 개념.
- Job과 Step이 **둘 다** JobRepository를 받는 이유: Job 레벨(전체 메타정보)과 Step 레벨(세부 통계)을 각각 기록하기 위함.
- 재시작 시 Spring Batch는 `BATCH_STEP_EXECUTION.STATUS`를 보고 `COMPLETED` Step은 건너뛰고 `FAILED` Step부터 다시 실행한다.
