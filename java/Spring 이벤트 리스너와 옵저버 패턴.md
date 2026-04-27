# Spring 이벤트 리스너와 옵저버 패턴

> 날짜: 2026-04-27

## 내용

### Spring Batch `.listener()` — 라이프사이클 콜백

`.listener()`는 배치가 돌아가는 **특정 시점마다 호출될 콜백**을 등록한다.

**Spring Batch Listener 종류:**

| Listener | 호출 시점 |
|---|---|
| **StepExecutionListener** | Step 시작/종료 |
| **ChunkListener** | Chunk 시작/종료/에러 |
| **ItemReadListener** | Read 전/후/에러 |
| **ItemProcessListener** | Process 전/후/에러 |
| **ItemWriteListener** | Write 전/후/에러 |
| **SkipListener** | Skip 발생 시 |
| **RetryListener** | Retry 발생 시 |

`.listener()` **하나로 모든 타입 등록 가능** — Spring Batch가 구현한 인터페이스를 자동 감지.

```java
.listener(myListener)  // 자동 감지!
```

**SkipListener의 3가지 콜백:**
```java
public interface SkipListener<T, S> {
  void onSkipInRead(Throwable t);
  void onSkipInProcess(T item, Throwable t);
  void onSkipInWrite(S item, Throwable t);
}
```

> **면접 예상 질문:** Spring Batch의 Listener 종류와 `.listener()` 메서드의 자동 감지 메커니즘은?

---

### ApplicationEventPublisher와 옵저버 패턴

**ApplicationEventPublisher** = Spring 애플리케이션 내부에서 이벤트를 발행하는 도구. **옵저버 패턴**의 Spring 구현체다.

```java
// 1. 이벤트 발행
eventPublisher.publishEvent(new SettlementSkippedEvent(...));

// 2. 어디선가 누군가 듣고 있음
@Component
public class SettlementSkippedHandler {
    @EventListener
    public void handle(SettlementSkippedEvent event) {
        skipLogRepository.save(...);
        slackNotifier.send(...);
    }
}
```

**왜 이벤트 패턴을 쓰는가? — OCP + 책임 분리**

```java
// ❌ 직접 처리 (책임 비대)
public void onSkipInProcess(Settlement item, Throwable t) {
    skipLogRepository.save(...);
    slackNotifier.send(...);
    metricCounter.increment(...);
    emailService.send(...);
}

// ✅ 이벤트 발행 (책임 분리)
public void onSkipInProcess(Settlement item, Throwable t) {
    eventPublisher.publishEvent(new SettlementSkippedEvent(...));
}

@EventListener public void saveToDlq(...) { ... }     // 핸들러 1
@EventListener public void sendSlack(...) { ... }     // 핸들러 2
@EventListener public void recordMetric(...) { ... }  // 핸들러 3
```

**옵저버 패턴 ↔ Spring Event 매칭:**

| 옵저버 패턴 | Spring Event |
|---|---|
| Subject | `ApplicationEventPublisher` |
| `register(observer)` | `@EventListener` (자동 등록) |
| `notify(event)` | `publishEvent(event)` |
| Observer | `@EventListener` 메서드 |

> **면접 예상 질문:** `ApplicationEventPublisher`를 쓰면 무엇이 좋은가? 옵저버 패턴과 어떻게 매칭되는가?

---

### SkipListener에서 이벤트 발행 — 트랜잭션 함정

**핵심 원칙: "롤백되는 트랜잭션 안에서 이벤트 발행 = 이벤트 핸들러의 DB 작업도 함께 롤백"**

**❌ Processor에서 발행했을 때:**
```
Chunk 트랜잭션 시작
  ├─ 50번 item 처리 중 음수 발견
  │   ├─ eventPublisher.publishEvent(...) ← 이벤트 발행!
  │   │   └─ @EventListener가 받아서 DLQ에 INSERT
  │   └─ throw IllegalStateException
  └─ Chunk 트랜잭션 ROLLBACK ❌
      └─ DLQ에 INSERT한 것도 함께 롤백됨! 💥
```

**✅ SkipListener에서 발행했을 때:**
```
Chunk 트랜잭션 ROLLBACK 후
  └─ Spring Batch가 Skip 처리 단계 진입 (별도 컨텍스트)
      └─ SkipListener.onSkipInProcess() 호출
          └─ eventPublisher.publishEvent(...) ← 안전!
              └─ 핸들러가 DLQ에 INSERT (커밋됨!) ✅
```

**비슷한 함정 (실무 자주 만남!):**
- `@Transactional` 메서드 안에서 이벤트 발행 + 핸들러가 DB 작업 → 메인 롤백 시 핸들러도 롤백

**해결책:**
- **`@TransactionalEventListener(phase = AFTER_COMMIT)`** — 트랜잭션 커밋 후에만 이벤트 처리
- **`@Async`** — 별도 스레드에서 처리 (트랜잭션 분리)

> **면접 예상 질문:** Processor가 아닌 SkipListener에서 이벤트를 발행하는 이유는? `@TransactionalEventListener`는 어떤 문제를 해결하는가?

---

### Skip 모드와 Single-item 재처리

Spring Batch의 Skip 활성화 시 **1건씩 개별 트랜잭션으로 재실행**해 정상 데이터를 보존한다.

```
1단계: 일반 chunk 처리 시도
  ├─ 100건 한 번에 처리
  ├─ 50번에서 예외 발생!
  └─ Chunk 전체 ROLLBACK ❌

2단계: Skip 활성화 → 1건씩 재처리 (Single-item mode)
  ├─ 1번 처리 → 커밋 ✅
  ├─ ...
  ├─ 50번 처리 → 예외! → Skip!
  │   └─ SkipListener.onSkipInProcess() 호출 ✅
  ├─ 51번 처리 → 커밋 ✅
  └─ 100번 처리 → 커밋 ✅
```

**다음 chunk부터는 다시 정상 chunk 모드로 복귀** — Skip은 예외 상황 대응용.

| 모드 | 트랜잭션 횟수 | 성능 | 데이터 보존 |
|---|---|---|---|
| 정상 chunk | 1번 | 빠름 | 전체 롤백 |
| Skip 모드(1건씩) | 100번 | 느림 | 정상 데이터 보존 |

> **면접 예상 질문:** Skip 모드는 어떻게 정상 데이터를 보존하는가? 성능 트레이드오프는?

---

### chunk size vs skipLimit

| 개념 | 역할 |
|---|---|
| **chunk size** | 한 번에 처리할 **데이터 묶음 크기** (예: 100건씩 묶기) |
| **skipLimit** | Skip을 허용하는 **누적 한도** (예: 100건까지 허용) |

```java
.<Settlement, Settlement>chunk(CHUNK_SIZE)   // 100건씩 묶어서 처리
.skipLimit(SKIP_LIMIT)                       // 누적 Skip 100건까지만 허용
```

**skipLimit 초과 시:** `SkipLimitExceededException` → **Job 전체 FAIL** (Fail Fast 원칙).

**왜 Fail Fast?** 일정 한도까지는 운영 부담 줄이고, 그 이상이면 시스템 이상 신호 → 즉시 멈춰 알림.

**적정값 가이드 (정산 시스템):** 일일 데이터의 **0.05% ~ 0.1%** 보수적 시작 → 1만 건이면 10~20, 10만 건이면 50~100.

> **면접 예상 질문:** chunk size와 skipLimit의 차이는? skipLimit 초과 시 동작은?

---

### REQUIRES_NEW로 방어적 트랜잭션 분리

이벤트 핸들러에 `Propagation.REQUIRES_NEW`를 적용하면 **호출자의 트랜잭션과 무관하게 새 트랜잭션을 시작**한다.

**비유 — 회사 결재 시스템:**
- **REQUIRED (기본)**: "팀장 결재 라인이 있으면 묻어가자"
- **REQUIRES_NEW**: "팀장 결재 어떻든 상관없이, 별도 결재 라인 새로!"

**❌ 없을 때:**
```
호출자 트랜잭션 시작
  ├─ handle(event) → save() → 같은 트랜잭션
  └─ 호출자 ROLLBACK → save도 롤백! 유실
```

**✅ 있을 때:**
```
호출자 트랜잭션 (있든 없든)
  ├─ handle(event)
  │   ├─ 기존 트랜잭션 suspend
  │   ├─ 새 트랜잭션 시작 → save → 즉시 커밋 ✅
  │   └─ 기존 트랜잭션 resume
  └─ 호출자 ROLLBACK해도 save는 이미 커밋됨!
```

**왜 방어적으로?** Spring Batch 버전 변경, 다른 호출자, 테스트 환경, 핸들러 체이닝 등 어떤 시나리오에서도 **skip log 보존 보장**.

> **면접 예상 질문:** `Propagation.REQUIRES_NEW`는 어떻게 동작하는가? 방어적 프로그래밍 관점에서 언제 사용하는가?

---

### 옵저버 패턴 vs Pub-Sub 패턴

엄밀하게 보면 둘은 강조점이 다르다.

| 구분 | 옵저버 패턴 | Pub-Sub 패턴 |
|---|---|---|
| 호출 방식 | Subject가 Observer **직접 호출** | 중간 **브로커** 경유 |
| Subject ↔ Observer | 서로 인터페이스 알고 있음 | 서로 모름 |
| 환경 | 같은 프로세스 | 분산 시스템 가능 |
| 예시 | Java Swing `addActionListener`, RxJava | Kafka, RabbitMQ, AWS SNS |

**Spring `ApplicationEventPublisher`는 중간 위치** — 같은 JVM 내 매개체 활용 → 옵저버와 Pub-Sub의 하이브리드.

**구분 기준:**
| 상황 | 부르는 이름 |
|---|---|
| 같은 JVM + 동기 | 옵저버 패턴 |
| 분산 환경 + 비동기 | Pub-Sub |
| 메시지 큐 (Kafka, RabbitMQ) | Pub-Sub |
| GUI 이벤트 | 옵저버 |

**핵심 기억:**
> "별도 브로커가 있고 분산되어 있으면 **Pub-Sub**, 같은 프로세스에서 직접 호출이면 **옵저버**."

> **면접 예상 질문:** 옵저버 패턴과 Pub-Sub 패턴의 차이는? Spring 이벤트는 어디에 속하는가?

---

### 옵저버 패턴의 3가지 핵심 장점

1. **느슨한 결합 (Loose Coupling)** — Subject는 Observer가 누군지 모름, 인터페이스만 알면 OK
2. **OCP 준수** — 새 Observer 추가 시 Subject 수정 X
3. **동적 구독/해제** — 런타임에 Observer를 자유롭게 추가/제거

**잘 어울리는 상황:** 여러 후속 처리 필요 (알림 + 로깅 + 메트릭)
**잘 어울리지 않는 상황:** 딱 하나의 결과만 필요 (직접 호출이 더 명확)

> **면접 예상 질문:** 옵저버 패턴의 장점은? 언제 쓰지 말아야 하는가?

---

## 학습 정리

- Spring Batch `.listener()`는 **여러 인터페이스를 자동 감지**해 라이프사이클 콜백 등록
- `ApplicationEventPublisher` + `@EventListener`는 **옵저버 패턴의 Spring 구현체** — OCP/책임 분리 자연스럽게 달성
- **SkipListener에서 이벤트 발행**해야 chunk 롤백과 분리되어 DLQ 저장이 안전 (Processor에서 발행하면 같이 롤백)
- `@TransactionalEventListener(phase = AFTER_COMMIT)`로 일반 트랜잭션 함정도 회피
- Spring Batch는 **Skip 활성화 시 1건씩 재처리(Single-item mode)** 로 정상 데이터 보존
- `chunk size`와 `skipLimit`은 다른 개념 — Skip 누적 한도 초과 시 Fail Fast
- 이벤트 핸들러에 **`REQUIRES_NEW`** 적용해 호출자 트랜잭션과 분리하는 방어적 프로그래밍 권장
- 옵저버 패턴 vs Pub-Sub: **브로커 유무**가 핵심 — Spring 이벤트는 중간 위치

## 참고

- CarrotSettle Spring Batch SkipListener 설계 기반
- GoF — Observer Pattern
- Spring Framework Reference — `ApplicationEventPublisher`, `@TransactionalEventListener`
- Spring Batch Reference — Listener, Skip Configuration
