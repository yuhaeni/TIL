# REQUIRES_NEW 커넥션 풀 데드락과 Outbox 패턴 — phase별 이벤트 분리, HikariCP 메트릭

> 날짜: 2026-05-16

## 내용

### 트랜잭션·스레드·커넥션 — 3개 개념 분리

트랜잭션이 헷갈리는 이유는 보통 트랜잭션/스레드/커넥션을 한 덩어리로 묶어서 이해하기 때문이다. 셋은 서로 다른 층위의 개념이다.

| 개념 | 비유 | 의미 |
|---|---|---|
| **트랜잭션** | "송금 한 묶음" | 작업 단위의 약속 — 전부 성공하거나 전부 실패 |
| **커넥션** | "은행 창구" | DB와 대화하는 물리적 통로 (SQL이 오가는 파이프) |
| **스레드** | "직원" | 창구에 앉아 일하는 사람 |

- **트랜잭션 = 개념적 약속** (`COMMIT`/`ROLLBACK`)
- **커넥션 = 물리적 통로** (HikariCP가 풀에 미리 만들어 둠)
- **스레드 = 일꾼** (HTTP 요청 1개 = 톰캣 워커 스레드 1개)

`COMMIT`이라는 SQL도 결국 **커넥션을 타고** DB로 전송된다. 트랜잭션은 결국 "한 커넥션 위에서 일어나는 일련의 SQL"이다.

> **면접 예상 질문:** 트랜잭션·스레드·커넥션은 어떻게 구분되는가? COMMIT은 어디를 통해 DB에 전달되는가?

---

### REQUIRES_NEW의 동작 — 트랜잭션 2개 + 커넥션 2개

`REQUIRES_NEW`는 기존 트랜잭션이 있으면 **일시 중지(suspend)** 시키고 새 트랜잭션을 시작한다. 이때 트랜잭션은 동시에 2개가 살아있게 된다.

```java
@Service
public class PaymentService {
    @Transactional  // 바깥 트랜잭션 (REQUIRED)
    public void processPayment(PaymentRequest req) {
        accountService.withdraw(req.getUserId(), req.getAmount());
        paymentRepository.save(payment);
        auditService.log(req);  // ← REQUIRES_NEW 호출
    }
}

@Service
public class AuditService {
    @Transactional(propagation = REQUIRES_NEW)
    public void log(PaymentRequest req) {
        auditRepository.save(...);
    }
}
```

**왜 바깥이 "일시 중지"되는가?**

- 한 스레드는 동시에 단 1개의 **"활성(active)" 트랜잭션**만 진행할 수 있다 (사람이 멀티태스킹하는 것처럼 보여도 한 순간엔 하나)
- Spring은 `TransactionSynchronizationManager`라는 **ThreadLocal**에 "현재 활성 트랜잭션"을 추적한다
- `REQUIRES_NEW`를 만나면 바깥 트랜잭션을 ThreadLocal에서 잠깐 빼고(suspend), 안쪽이 끝나면 다시 넣는다(resume)
- 단, **바깥의 커넥션 점유는 그대로 유지**된다 (resume 후에 이어서 써야 하니까)

```
[스레드 A]
├─ 바깥 트랜잭션 시작 → 커넥션A 점유, "활성 상태"
├─ 안쪽 REQUIRES_NEW 만남
│  ├─ 바깥을 잠깐 "옆 책상에 치워둠" (suspend) — 커넥션A 점유는 유지
│  └─ 안쪽 트랜잭션 시작 → 커넥션B 점유, "활성 상태"
├─ 안쪽 commit/rollback → 커넥션B 반환
└─ 옆 책상의 바깥을 다시 가져옴 (resume) → 커넥션A 다시 "활성 상태"
```

→ **요청 1개당 커넥션 2개를 동시에 점유**한다.

> **면접 예상 질문:** REQUIRES_NEW로 호출 시 바깥 트랜잭션은 왜 일시 중지되는가? 이때 바깥 커넥션은 어떻게 되는가?

---

### 커넥션 풀 데드락 시나리오 — OS 교착 상태 4조건과 매칭

HikariCP 풀 사이즈가 10이고, 위 코드에 **10개의 요청이 거의 동시에** 들어오는 상황을 가정한다.

```
시점 T1: 10개 요청이 동시에 바깥 트랜잭션 시작
  → 커넥션 10개 모두 점유, 풀 잔량 0

시점 T2: 10개 요청 모두 auditService.log() (REQUIRES_NEW) 호출
  → 안쪽 트랜잭션을 위한 새 커넥션 요청
  → 풀에 없음 → 10개 스레드 모두 "커넥션 대기" 상태
  → 누구도 일을 못 끝내니, 누구도 커넥션을 반납하지 않음 → 데드락 💀
```

`auditService.log()`는 **아직 시작도 못 했다**. 새 커넥션을 못 받아서 `auditRepository.save()` 한 줄도 실행 못 한 채 대기 중이다. 그러니 안쪽은 commit/rollback을 할 수 없고, 안쪽 커넥션도 반납 못 한다. 바깥은 안쪽이 끝나기를 기다리니 바깥도 끝날 수 없다.

**OS 교착 상태 4가지 조건과 정확히 매칭된다:**

| 조건 | 이 시나리오 |
|---|---|
| **상호 배제** | 커넥션 1개는 한 트랜잭션만 점유 |
| **점유와 대기** | 바깥 커넥션 잡은 채로 새 커넥션 대기 |
| **비선점** | 누가 강제로 뺏을 수 없음 |
| **환형 대기** | 10개 스레드가 서로의 커넥션을 기다리는 구조 |

결국 `connectionTimeout` 만료로 전부 타임아웃 예외가 터지고, 결제 API가 전부 실패한다.

> **면접 예상 질문:** REQUIRES_NEW가 어떻게 커넥션 풀 데드락을 만드는지 설명하라. OS 교착 상태 4조건과 어떻게 매칭되는가?

---

### REQUIRED로 바꾸면? — 트레이드오프

가장 단순한 해결책은 `REQUIRES_NEW`를 기본값 `REQUIRED`로 바꾸는 것이다. 그러면 같은 트랜잭션·같은 커넥션을 공유한다.

| | `REQUIRED` (기본값) | `REQUIRES_NEW` |
|---|---|---|
| 기존 트랜잭션 있을 때 | **합류 (참여)** | 기존 것 **일시 중지** 후 새로 시작 |
| **커넥션** | 기존 것 **공유** (1개) | **새 커넥션** (총 2개) |
| **커밋/롤백 운명** | 바깥과 **함께** | 바깥과 **독립적** |

**그런데 트레이드오프가 있다:**

원래 요구사항이 "결제 실패해도 감사 로그는 무조건 남아야 한다"였다. `REQUIRED`로 바꾸면 결제 롤백 시 감사 로그도 함께 롤백된다 → **요구사항 위배**.

→ 단순히 `REQUIRED`로 바꾸는 건 데드락은 해소하지만 **비즈니스 요구사항을 깨뜨린다**.

> **면접 예상 질문:** REQUIRED로 바꿔서 데드락을 해소할 때 어떤 단점이 있는가?

---

### `@TransactionalEventListener` — phase별 이벤트 분리

이벤트 리스너로 후속 처리를 분리하면 메인 트랜잭션과 시점적으로 분리할 수 있다.

```java
@Service
public class PaymentService {
    @Transactional
    public void processPayment(PaymentRequest req) {
        accountService.withdraw(...);
        paymentRepository.save(...);
        eventPublisher.publishEvent(new PaymentEvent(...));  // 이벤트 발행만
    }
}

@Component
public class AuditListener {
    @TransactionalEventListener(phase = AFTER_COMPLETION)
    @Transactional(propagation = REQUIRES_NEW)
    public void onPayment(PaymentEvent event) {
        auditRepository.save(...);
    }
}
```

**리스너 호출의 정체:** `@TransactionalEventListener`는 메인 트랜잭션이 끝난 시점에 **콜백으로 호출되는 메서드**다. 리스너 자체는 트랜잭션이 아니라 단순 메서드 호출이며, DB 작업이 필요하면 메서드에 `@Transactional`을 별도로 붙여야 한다.

**phase 선택은 비즈니스 요구사항에 따라 다르다:**

| phase | 실행 시점 | 적합한 후속 처리 |
|---|---|---|
| `BEFORE_COMMIT` | 메인 트랜잭션 커밋 직전 | 메인과 운명을 같이하는 검증/연동 |
| `AFTER_COMMIT` | 커밋 성공 후만 | 푸시 알림, 포인트 적립 (성공 시에만) |
| `AFTER_ROLLBACK` | 롤백 시만 | 결제 실패 알림 |
| **`AFTER_COMPLETION`** | **커밋/롤백 무관 무조건** | **감사 로그 (시도 자체 기록)** |

**시간 순으로 보면 — 왜 데드락이 풀리는가:**

```
[스레드 A]
├─ ① 결제 트랜잭션 시작 (커넥션1 점유)
├─ ② withdraw, save
├─ ③ 결제 트랜잭션 COMMIT/ROLLBACK ✅ (커넥션1 반납!)
│
└─ ④ AFTER_COMPLETION 리스너 호출 (트랜잭션 없음)
   └─ ⑤ 리스너의 @Transactional(REQUIRES_NEW) 발동
      └─ 감사 로그 트랜잭션 시작 (커넥션1 다시 빌림)
      └─ 감사 로그 save → COMMIT (커넥션1 반납)
```

✅ 메인 트랜잭션이 **끝난 후**에 새 트랜잭션이 시작되므로 동시에 점유하는 커넥션은 **1개**다 → 풀 데드락 없음.

**주의:** `@TransactionalEventListener`는 기본적으로 **같은 스레드**에서 실행된다. 별도 스레드를 원한다면 `@Async`를 추가해야 한다.

> **면접 예상 질문:** `@TransactionalEventListener`의 phase 4가지는 각각 어떤 후속 처리에 적합한가? 리스너 자체는 트랜잭션인가?

---

### Spring 이벤트의 한계 — 재시도 안 됨

`AFTER_COMPLETION` + `REQUIRES_NEW`로 데드락은 풀었지만, 또 다른 함정이 있다.

```
1) 결제 트랜잭션 COMMIT ✅
2) AFTER_COMPLETION 리스너 호출
3) 감사 로그 트랜잭션 시작
4) auditRepository.save(...) 호출
5) DB 네트워크 단절 😱
6) 감사 로그 저장 실패!
```

`ApplicationEventPublisher`는 **단순한 인메모리 이벤트 발행** 메커니즘이다. 리스너가 실패해도 누구도 재시도 책임을 지지 않는다. 그냥 로그만 찍히고 끝.

→ 결과: **결제는 성공했는데 감사 로그가 영구 누락**. 핀테크에서는 규제 위반(PCI-DSS, 전자금융감독규정 등)과 직결되는 치명적 문제.

> **면접 예상 질문:** Spring `ApplicationEventPublisher`로 후속 처리를 분리할 때의 한계는?

---

### Dual Write Problem — DB와 Kafka 정합성 문제

재시도를 보장하려면 Kafka 같은 메시지 큐로 분리한다. 그런데 또 다른 문제가 생긴다.

```java
@Transactional
public void processPayment() {
    accountService.withdraw(...);
    paymentRepository.save(...);
    kafkaTemplate.send("payment-events", event);  // 트랜잭션 안에서 발행
}
```

**최악의 시나리오: Kafka 발행은 성공했는데 DB 커밋이 실패**

| 시스템 | 상태 |
|---|---|
| DB (결제 내역/잔액) | ❌ 롤백됨 (결제 안 일어남) |
| Kafka 메시지 | ✅ 이미 발행됨 ("결제 발생!") |

→ Kafka를 구독하는 알림 컨슈머가 "결제 완료!" 푸시를 보냄, 포인트 컨슈머가 포인트 적립, 감사 로그 컨슈머가 가짜 결제에 대한 로그 저장. **실제론 결제 안 됐는데 사용자에게 잘못된 정보가 전달**된다.

이를 **Dual Write Problem**(트랜잭션 경계 외부 시스템 정합성 문제)이라 한다. DB는 RDBMS 트랜잭션, Kafka는 별도 시스템이라 하나의 트랜잭션으로 묶을 수 없다.

**Kafka offset은 이걸 못 푼다:** offset은 컨슈머가 "어디까지 읽었는지" 추적하는 개념이다. 프로듀서의 `send()` 자체가 실패하면 Kafka에는 메시지가 아예 존재하지 않으므로 offset으로 추적할 대상도 없다.

> **면접 예상 질문:** Dual Write Problem이란 무엇인가? Kafka offset으로 해결할 수 있는 문제인가?

---

### Transactional Outbox Pattern — 원자성 보장

발행할 메시지를 **DB의 outbox 테이블에 같은 트랜잭션으로 저장**하는 패턴이다.

```
┌─ [같은 DB 트랜잭션 안에서] ─────────────────┐
│  1) payment 테이블에 결제 데이터 INSERT      │
│  2) outbox 테이블에 발행할 메시지 INSERT     │
│  → 둘 다 같이 COMMIT (원자성 보장!) ✅       │
└──────────────────────────────────────────┘
              ↓
┌─ [별도 프로세스: Outbox Relay] ───────────────┐
│  3) outbox 테이블 폴링                       │
│  4) 메시지를 Kafka로 발행                    │
│  5) 발행 성공 시 outbox 메시지 처리됨 표시   │
│  6) 실패 시 → 다음 폴링 때 재시도            │
└──────────────────────────────────────────┘
```

- DB 커밋과 메시지 저장이 **하나의 트랜잭션 = 원자적**
- Kafka 발행이 실패해도 outbox에 메시지가 남아있어 **재시도 가능**
- 실무에서는 **Debezium 같은 CDC(Change Data Capture) 도구**로 outbox 테이블 변경을 watch해서 Kafka로 자동 전달하기도 한다

| 패턴 | 보장 수준 |
|---|---|
| 일반 `kafkaTemplate.send()` (트랜잭션 안) | ❌ Dual Write 문제 |
| `AFTER_COMMIT` + Kafka send | ⚠️ DB 커밋은 OK, Kafka 발행 실패 시 누락 가능 |
| **Transactional Outbox Pattern** | ✅ 원자성 보장 + 재시도 |

> **면접 예상 질문:** Transactional Outbox Pattern은 어떤 문제를 해결하는가? CDC와는 어떻게 연결되는가?

---

### HikariCP 메트릭 — 데드락 진단

운영 중 데드락이 발생했을 때 무엇을 보고 진단할까?

**핵심 메트릭 (Prometheus + Grafana):**

| 메트릭 이름 | 의미 |
|---|---|
| `hikaricp_connections_active` | 현재 사용 중인 커넥션 수 |
| `hikaricp_connections_idle` | 현재 유휴 커넥션 수 |
| **`hikaricp_connections_pending`** | **커넥션을 기다리는 스레드 수** 🚨 |
| `hikaricp_connections_timeout` | 커넥션 획득 타임아웃 횟수 |
| `hikaricp_connections_acquire` | 커넥션 획득에 걸린 시간 (히스토그램) |

**데드락 발생 시 패턴:**

```
[정상] active=3, idle=7, pending=0,  timeout=0
[데드락 🚨] active=10, idle=0, pending=50, timeout=30
```

- `active=max`만 봐서는 "단순 트래픽 증가"와 구분이 안 된다
- **`pending`이 치솟으면** → "확실히 풀이 부족하거나 누군가 비정상적으로 점유 중" → 데드락 의심

**추가 진단 도구:**

| 도구 | 용도 |
|---|---|
| `jstack <pid>` (스레드 덤프) | 어떤 스레드가 어디서 `getConnection()` 대기 중인지 확인 |
| HikariCP `leakDetectionThreshold` | 일정 시간 이상 안 반납되는 커넥션 자동 경고 |
| PostgreSQL `pg_stat_activity` | DB쪽에서 `idle in transaction` 상태 쿼리 확인 |
| APM (DataDog, NewRelic) | 트랜잭션 전파 추적, 메서드별 대기 시간 |

**진단 시나리오:**

1. Grafana에서 `hikaricp_connections_pending`이 치솟는지 확인
2. `pending`이 비정상이면 `jstack`으로 스레드 덤프를 떠서 어떤 코드에서 커넥션 대기 중인지 확인
3. DB쪽에서 `pg_stat_activity`로 long-running transaction 확인
4. 코드 리뷰: `REQUIRES_NEW` 사용 지점, 트랜잭션 안의 외부 API 호출 등 의심 패턴 점검

> **면접 예상 질문:** 운영 중 커넥션 풀 데드락을 어떻게 발견하는가? 어떤 메트릭이 결정적 신호인가?

---

## 학습 정리

- **트랜잭션·스레드·커넥션은 다른 층위의 개념** — 트랜잭션은 약속, 커넥션은 통로, 스레드는 일꾼
- **REQUIRES_NEW**는 바깥을 ThreadLocal에서 suspend하고 새 트랜잭션을 시작 — 한 스레드가 동시에 2개의 활성 트랜잭션을 가질 수 없기 때문 (커넥션 점유는 유지)
- 풀 사이즈만큼 동시 요청 + REQUIRES_NEW 호출 → 모든 스레드가 두 번째 커넥션을 기다리며 **커넥션 풀 데드락** 발생 (OS 교착 4조건과 정확히 매칭)
- `REQUIRED`로 바꾸면 데드락은 해소되지만 "실패해도 남아야 한다"는 요구사항을 깨뜨림 → 트레이드오프
- `@TransactionalEventListener` + `@Transactional(REQUIRES_NEW)` 조합으로 메인 트랜잭션 종료 **후**에 후속 처리 → 동시 점유 커넥션 1개로 데드락 해소
- **phase 선택은 비즈니스 요구사항에 따라**: 감사 로그(`AFTER_COMPLETION`), 알림/포인트(`AFTER_COMMIT`), 실패 알림(`AFTER_ROLLBACK`)
- Spring 이벤트는 **재시도를 보장하지 않음** — 핀테크에서 감사 로그 누락은 규제 위반과 직결
- Kafka로 분리하면 **Dual Write Problem** 발생 → **Transactional Outbox Pattern**으로 DB 트랜잭션 안에서 outbox에 메시지 저장 + 별도 릴레이가 Kafka 발행 + 재시도
- HikariCP 메트릭 중 **`hikaricp_connections_pending`**이 데드락의 결정적 신호 — `active=max`만으론 트래픽 폭증과 구분 불가
- 진단 도구 조합: Grafana 메트릭 → `jstack` 스레드 덤프 → `pg_stat_activity` → 코드 리뷰

## 참고

- Spring Framework Reference — `TransactionSynchronizationManager`, `@TransactionalEventListener`
- HikariCP Wiki — MBean/Metrics
- Microservices.io — Transactional Outbox Pattern
- Debezium 공식 문서 — Outbox Event Router
