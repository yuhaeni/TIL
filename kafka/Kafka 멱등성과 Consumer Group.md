# Kafka 멱등성과 Consumer Group

> 날짜: 2026-04-27

## 내용

### Spring 이벤트 vs Kafka — 영속성과 분산

둘 다 비동기가 가능하지만, **영속성과 분산 환경 지원**이 결정적으로 다르다.

| 비교 | Spring 이벤트 | Kafka |
|---|---|---|
| **영속성** | 메모리 (휘발성) | 디스크 (영속) |
| **재시도** | 직접 구현 어려움 | offset 관리로 쉬움 |
| **확장성** | 같은 JVM 내 | 여러 시스템 간 |
| **컨슈머** | `@EventListener` (앱 내부) | 다른 서비스도 가능 |
| **순서 보장** | 단일 스레드만 | 파티션 단위 보장 |
| **장애 격리** | JVM 장애 시 다 죽음 | 정산 죽어도 메시지 큐는 살아있음 |

**시나리오 — 정산 서버 다운:**

**Spring `@Async`:**
```
SkipListener 이벤트 발행 → 핸들러 큐(JVM 메모리)
→ 핸들러 실행 전에 서버 다운!
→ 이벤트 사라짐 ❌ 데이터 유실
```

**Kafka:**
```
SkipListener → Kafka 디스크 저장 ✅
→ 정산 서버 다운
→ 다른 서버(또는 재시작 후) 컨슈머가 메시지 수신
→ 처리 정상 진행 ✅
```

**점진적 발전 전략:**
- M1~M6: Spring 이벤트 (개발 빠름)
- M7: Kafka 교체 (운영 안정성 향상)
- 발행자(`SettlementSkipListener`)는 **수정 안 함** — 추상화 잘되어 있으면 교체 비용 낮음

> **면접 예상 질문:** Spring 이벤트와 Kafka 중 무엇을 언제 선택하는가? 정산 시스템에 Kafka가 적합한 이유는?

---

### 메시지 중복 방지 — 멱등성 Consumer 단

같은 메시지가 두 번 들어오면 `skip_logs`에 **중복 INSERT** 위험.

| 방법 | 영구성 | 성능 | 복잡도 | 추천 |
|---|---|---|---|---|
| **DB Unique Constraint** | ✅ 영구 | 중간 | 낮음 | **일반적 권장** |
| **Inbox 테이블** | ✅ 영구 | 중간 | 중간 | 감사 필요 시 |
| **Redis TTL** | ⚠ TTL 한정 | 빠름 | 중간 | 단기 중복 방지 |

**방법 A — DB Unique Constraint (가장 안전):**
```sql
CREATE TABLE settlement_skip_logs (
    id BIGSERIAL PRIMARY KEY,
    event_id VARCHAR(255) UNIQUE NOT NULL,
    ...
);
```
```java
try {
    skipLogRepository.save(...);
} catch (DataIntegrityViolationException e) {
    log.info("이미 처리된 이벤트: {}", eventId);
}
```

**방법 B — Inbox 테이블 (먼저 체크 → 처리):**
```java
@Transactional
public void handle(event) {
    if (processedEventRepository.existsById(event.id())) return;
    skipLogRepository.save(...);
    processedEventRepository.save(new ProcessedEvent(event.id()));
}
```

**방법 C — Redis TTL (`SETNX`):**
```
SETNX(eventId, "processed", TTL=24h)
  ├─ 성공 → 처음! → DB INSERT
  └─ 실패 → 중복 → 스킵
```

**정산 시스템 권장:** **DB Unique Constraint** (영구 보장 우선) 또는 **하이브리드** (Redis 1차 + DB 최종).

> **면접 예상 질문:** Kafka 메시지 중복 처리는 어떻게 보장하는가? DB Unique vs Redis TTL 트레이드오프는?

---

### Kafka Producer 멱등성 — `enable.idempotence=true`

**중복이 발생하는 이유:**
```
1. Producer → 메시지 발행 → 브로커 저장 → ack 보냄
2. ack가 네트워크에서 유실 (타임아웃)
3. Producer "실패했나?" 재시도
4. 같은 메시지 두 번 저장! ❌
```

**`enable.idempotence=true` 동작 — PID + Sequence Number:**
```
첫 발행:    [PID=123, SeqNum=1, Message] → 저장 ✅
재시도:    [PID=123, SeqNum=1, Message] → 이미 있음 → 무시 ✅
```

**권장 설정 세트:**
```properties
enable.idempotence=true                          # 멱등성 활성화
acks=all                                         # 모든 replica ack 후 (유실 방지)
retries=Integer.MAX_VALUE                        # 무한 재시도 (멱등성이 보장하므로 안전)
max.in.flight.requests.per.connection=5          # 진행 중 요청 제한 (순서 보장)
```

> **면접 예상 질문:** Kafka Producer 멱등성은 어떻게 동작하는가? `enable.idempotence`만으로 충분한가?

---

### Exactly-Once Semantics와 End-to-End 멱등성

**Exactly-Once = `enable.idempotence=true` + 트랜잭션 Producer:**

```java
producer.initTransactions();
try {
    producer.beginTransaction();
    producer.send(record1);
    producer.send(record2);
    producer.commitTransaction();   // 둘 다 성공 or 둘 다 실패
} catch (Exception e) {
    producer.abortTransaction();
}
```

**End-to-End Exactly Once 패턴:**

```
[Producer 단 — Kafka]
  enable.idempotence=true
  → Producer 재시도로 인한 중복 차단 ✅

[Consumer 단 — 우리 코드]
  DB Unique Constraint (event_id)
  → Consumer 재처리로 인한 중복 차단 ✅

→ 양쪽 멱등성 보장 = End-to-End Exactly Once
```

> **면접 예상 질문:** Exactly-Once Semantics를 어떻게 달성하는가? Producer 멱등성과 Consumer 멱등성의 역할 분담은?

---

### Kafka는 Pub-Sub인가 옵저버인가?

**결론: 순수 Pub-Sub.**

| 옵저버 조건 | Kafka |
|---|---|
| 같은 프로세스 내 | ❌ (별도 시스템) |
| Subject가 Observer 직접 관리 | ❌ (브로커가 관리) |
| 동기 호출 | ❌ (비동기) |

**Kafka 구조:**
```
[Producer JVM]                    [Consumer JVM 1]
    │                                  ↑
    └──> [Kafka Broker] ─────────────┤
         - 디스크 저장                  ↓
         - Topic/Partition 관리   [Consumer JVM 2]
```

특징: Producer ↔ Consumer **완전 분리**, 브로커 **필수 매개**, **비동기**, **디스크 영속화** → 완벽한 Pub-Sub.

> **면접 예상 질문:** Kafka는 어떤 메시징 모델인가? 옵저버 패턴과 비교했을 때 차이점은?

---

### Consumer Group — 분산 처리와 브로드캐스트의 결합

**Consumer Group은 옵저버 패턴의 브로드캐스트에 큐(Queue) 분산 처리를 결합한 모델.**

**케이스 1 — Group A (Consumer 3명):**
```
Group A
  ├─ Consumer A1: 메시지 1, 4, 7... (분담)
  ├─ Consumer A2: 메시지 2, 5, 8... (분담)
  └─ Consumer A3: 메시지 3, 6, 9... (분담)
→ 100건을 3명이 나눠서 처리 (병렬!)
```

**케이스 2 — Group A + Group B 동시 존재:**
```
Group A (3 consumer): 100건 다 받음 → 3명이 분산
Group B (2 consumer): 같은 100건 다 받음 → 2명이 분산
→ 같은 메시지를 두 그룹 모두 받음 (브로드캐스트)
→ 그룹 내에서는 분산
```

**옵저버 패턴과의 차이:**

| 옵저버 패턴 (전통) | Kafka Consumer Group |
|---|---|
| 모든 Observer가 같은 이벤트 수신 (브로드캐스트만) | 같은 그룹 내 분산 + 다른 그룹 간 브로드캐스트 |
| 분산/병렬 개념 없음 | Queue 모드 + Pub-Sub 모드 동시 지원 |

**핵심 한 줄:**
> **"같은 그룹 = 분산 처리, 다른 그룹 = 브로드캐스트."**

> **면접 예상 질문:** Kafka Consumer Group은 어떻게 동작하는가? 옵저버 패턴을 어떻게 확장한 것인가?

---

### 정산 시스템 적용 예시

```
SettlementSkippedEvent → Kafka Topic
  │
  ├─> Group: skip-log-saver (3 consumer)
  │     → DB에 분산 저장 (3배 빠름)
  │
  ├─> Group: slack-notifier (1 consumer)
  │     → 슬랙 알림 (단일 처리)
  │
  └─> Group: analytics (2 consumer)
        → 분석 시스템 (병렬 분석)
```

→ 한 메시지로 **여러 시스템 + 각자 분산 처리**.

이런 구조는 Spring 이벤트로는 불가능 — 같은 JVM 내에서만 동작하기 때문.

> **면접 예상 질문:** 하나의 이벤트를 여러 시스템이 받아 각자 분산 처리하려면 어떤 구조가 필요한가?

---

## 학습 정리

- Spring 이벤트는 **JVM 메모리 기반**으로 휘발성, Kafka는 **디스크 영속 + 분산** — 정산처럼 유실 치명적이면 Kafka
- Consumer 단 멱등성은 **DB Unique Constraint**가 가장 안전 (영구 보장), Redis TTL은 단기 방어선
- Producer 단 멱등성은 **`enable.idempotence=true`** — PID + Sequence Number로 ack 유실 재시도 중복 차단
- 권장 Producer 설정: `enable.idempotence=true` + `acks=all` + `retries=MAX` + `max.in.flight=5`
- **Exactly-Once = `enable.idempotence` + 트랜잭션 Producer**
- **End-to-End 멱등성 = Producer 멱등성 + Consumer DB Unique** 조합
- Kafka는 **순수 Pub-Sub** — 별도 브로커, 비동기, 영속화로 옵저버 조건 미충족
- **Consumer Group**은 **같은 그룹 내 분산(Queue) + 다른 그룹 간 브로드캐스트(Pub-Sub)** 동시 지원
- 발행자(`SkipListener`)를 잘 추상화하면 **Spring 이벤트 → Kafka 교체 비용 낮음**

## 참고

- CarrotSettle 정산 시스템 SkipListener → Kafka 전환 설계
- Apache Kafka 공식 문서 — Idempotent Producer, Transactional Producer
- Confluent — Exactly-Once Semantics in Kafka
- Kafka Consumer Group Coordination 문서
