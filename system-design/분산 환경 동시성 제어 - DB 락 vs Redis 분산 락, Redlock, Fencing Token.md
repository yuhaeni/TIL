# 분산 환경 동시성 제어 — DB 락 vs Redis 분산 락, Redlock, Fencing Token

> 날짜: 2026-05-13

## 내용

### Race Condition — 동시성 문제의 본질

**정의**: 두 개 이상의 스레드/요청이 같은 자원에 *동시에* 접근할 때, 실행 순서에 따라 결과가 달라지는 상황. 한국어로 "경쟁 상태".

**고전적 예시 — 은행 계좌 잔액 차감**:

```
계좌 잔액 1,000원, 두 사용자가 동시에 100원씩 차감
기대 결과: 1,000 → 900 → 800

⏱️ Race Condition 발생:
   [트랜잭션 A]                       [트랜잭션 B]
   1초  SELECT balance → 1,000
   2초                                SELECT balance → 1,000  ← A의 변경 전 값!
   3초  UPDATE = 1,000 - 100
   4초                                UPDATE = 1,000 - 100
   5초  COMMIT (잔액: 900)
   6초                                COMMIT (잔액: 900)  ← 800이어야 함!

❌ 100원 사라짐 (Lost Update)
```

**선착순 시나리오**도 동일:

```
"100명 선착순 무료 크레딧 지급" → 1000명 동시 요청
→ 모두 "현재 91명 가입" 동시 SELECT
→ 모두 "내가 92번째 OK!" 판단 → INSERT 1000건 발생 💥
```

**왜 발생?** 읽고 → 판단 → 쓰는 사이에 **다른 트랜잭션이 끼어들 수 있기 때문**. 이를 막는 도구가 **락(Lock)**.

> **면접 예상 질문:** Race Condition은 왜 발생하는가? 락이 필요한 본질적 이유는?

---

### synchronized와 JVM 내부 락의 한계 — 분산 환경에서 깨지는 이유

`synchronized`는 **JVM 내부 락(Intrinsic Lock / Monitor Lock)**. 각 JVM(서버)마다 독립적으로 동작한다.

```java
public synchronized void registerUser() {
    // 한 번에 한 스레드만 진입 (같은 JVM 내에서만!)
}
```

**분산 환경의 함정**:

```
🚨 1000명 동시 요청 → 로드밸런서가 서버 A/B/C에 분산
   - 서버 A로 간 333명: A 내부 synchronized로 직렬화 ✅
   - 서버 B로 간 333명: B 내부 synchronized로 직렬화 ✅
   - 서버 C로 간 333명: C 내부 synchronized로 직렬화 ✅

❌ A, B, C는 서로 모름!
❌ 셋이 동시에 DB INSERT → race condition 여전히 발생
```

**결론**: 분산 환경에선 **모든 서버가 공유하는 외부 공간**에서 락을 관리해야 한다. 후보 두 곳:
- 🗄️ **DB 락** (PostgreSQL 락 기능)
- 🔴 **Redis 분산 락** (Redisson, SETNX)

> **면접 예상 질문:** synchronized로 분산 환경 동시성을 해결할 수 있는가? 안 된다면 왜인가?

---

### 비관적 락 (Pessimistic Lock) — "충돌은 무조건 일어난다!"

미리 자물쇠 걸고 시작. **읽는 시점부터 락 획득**.

```sql
-- PostgreSQL
BEGIN;
SELECT * FROM users WHERE id = 1 FOR UPDATE;  -- 🔒 락!
UPDATE users SET credit = credit + 10000 WHERE id = 1;
COMMIT;  -- 🔓 락 해제
```

```java
// JPA
@Lock(LockModeType.PESSIMISTIC_WRITE)
@Query("SELECT u FROM User u WHERE u.id = :id")
User findByIdWithLock(@Param("id") Long id);
```

**동작 흐름**:
1. 트랜잭션 A가 `SELECT FOR UPDATE` → DB가 해당 row에 락 걸기
2. 트랜잭션 B가 같은 row 접근 시도 → **대기(블로킹)**
3. A가 COMMIT/ROLLBACK 하면 락 해제 → B 진행

**비유**: "이 책 빌릴 거니까 다른 사람 못 만지게 자물쇠 걸어둠"

> **면접 예상 질문:** 비관적 락은 어떤 SQL/JPA 문법으로 구현하는가? 어떤 상황에 적합한가?

---

### 낙관적 락 (Optimistic Lock) — "충돌은 거의 안 일어난다!"

일단 진행하고, 충돌나면 그때 처리. **쓸 때 검증**.

```java
@Entity
public class User {
    @Id
    private Long id;
    private int credit;

    @Version  // ⭐ JPA가 이걸 보고 자동 낙관적 락
    private int version;
}
```

JPA가 자동 생성하는 UPDATE:

```sql
UPDATE users
SET credit = ?, version = version + 1
WHERE id = ? AND version = ?  -- ⭐ 내가 읽었을 때 version과 같은지 검증
```

**동작 흐름**:
1. 트랜잭션 A: row 읽음 (version=5)
2. 트랜잭션 B: 같은 row 읽음 (version=5)
3. A: UPDATE 성공 → version=6
4. B: UPDATE 시도 → `WHERE version=5` 매칭 실패 → **0건 업데이트**
5. JPA가 감지 → `OptimisticLockException` 발생 → 재시도 필요

**비유**: "여러 명이 동시에 책 들고가서 읽다가, 반납할 때 '내가 가져갔을 때 페이지 100이었지? 지금도 100이야?' 확인. 다르면 재시도"

> **면접 예상 질문:** 낙관적 락은 어떻게 충돌을 감지하는가? `@Version` 컬럼이 없으면 어떻게 동작하는가?

---

### 비관적 vs 낙관적 락 — 트레이드오프와 선택 기준

| | 비관적 락 | 낙관적 락 |
|---|---|---|
| 락 시점 | **읽을 때부터** | **쓸 때 검증** |
| 충돌 처리 | 대기(블로킹) | 예외 발생 → 재시도 |
| 성능 (충돌 적을 때) | ❌ 락 오버헤드 | ✅ 빠름 |
| 성능 (충돌 많을 때) | ✅ 안정적 | ❌ 재시도 폭주 (Retry Storm) |
| 데드락 위험 | ⚠️ 있음 | ✅ 거의 없음 |
| 사용 사례 | **재고 차감, 결제** (충돌 잦음) | **게시글/프로필 수정** (충돌 드뭄) |

**시나리오 매칭 (미리캔버스 예시)**:

| 시나리오 | 적합한 락 | 이유 |
|---|---|---|
| 🎨 프로필 정보(닉네임) 수정 | 낙관적 | 본인 외 동시 수정 거의 없음 → 락 오버헤드 낭비 |
| 💰 선착순 100명 무료 크레딧 | 비관적 | 1000명이 1자리 두고 경쟁 → 낙관적 쓰면 Retry Storm 발생 |

> **면접 예상 질문:** 비관적 락과 낙관적 락의 트레이드오프는? 어떤 시나리오에 어떤 걸 선택할 것인가?

---

### 비관적 락의 실무 함정 — 커넥션 풀 고갈

비관적 락은 **DB 커넥션을 점유한 채로 락을 대기**한다. 트래픽이 몰리면 위험!

```
🔌 HikariCP 풀 사이즈 = 50 (보통)

🚨 1000명 동시 SELECT FOR UPDATE
   - 트랜잭션 1: 락 획득 + 커넥션 1개 점유 (작업 중)
   - 트랜잭션 2~50: 락 대기 + 커넥션 49개 점유 ⏳
   - 트랜잭션 51~1000: 커넥션 자체를 못 받음 → 대기 → 타임아웃 ❌

💀 결과:
   - 같은 풀을 쓰는 다른 API들도 커넥션 못 받음
   - 게시판 조회, 프로필 조회 등 무관한 기능까지 장애
   - "한 기능의 락 → 서비스 전체 장애"로 번짐
```

이걸 회피하기 위한 5년차 대안:

1. **Redis 분산 락** (가장 흔한 선택) — DB 커넥션 점유 없이 락 가능
2. **PostgreSQL `SKIP LOCKED`** — 락 잡힌 row는 건너뛰기 (큐/배치 처리)
3. **메시지 큐로 비동기 직렬화** (Kafka) — 락 자체가 필요 없게

```sql
-- SKIP LOCKED 예시
SELECT * FROM users
WHERE status = 'PENDING'
FOR UPDATE SKIP LOCKED  -- 🆕 락 잡힌 row는 스킵
LIMIT 1;
```

> **면접 예상 질문:** 비관적 락의 실무 함정은? 어떤 장애로 이어지고 어떻게 회피하는가?

---

### Redis 분산 락 동작 원리 — SETNX와 TTL

**핵심**: Redis는 **단일 스레드(EventLoop)**라 명령어가 한 줄로 직렬화 → race condition 자체가 불가능.

**`SETNX`** = SET if Not eXists (키가 없을 때만 저장)

```
[클라이언트 A]                [Redis]
SETNX "user:1:lock" "A"  →   { user:1:lock: "A" }  ← 락 획득 🥇

[클라이언트 B] (동시 시도)
SETNX "user:1:lock" "B"  →   이미 있음! → 실패 ❌

[A 작업 끝]
DEL "user:1:lock"        →   {}  ← 락 해제 🔓
```

**문제 1**: 클라이언트가 죽으면 락이 영원히 안 풀림 → 데드락
**해결**: TTL 함께 설정

```
SET "user:1:lock" "A" NX EX 10  ← "10초 후 자동 만료"
```

**문제 2**: 작업이 TTL보다 오래 걸리면?

```
[클라이언트 A] 락 획득 (TTL 10초) → 작업이 11초 걸림
[10초 지점] Redis: 락 자동 만료 → 락 해제됨
[클라이언트 B] SETNX 성공 → 새 락 획득 → 작업 시작
[11초 지점] A도 작업 끝났다 생각 → DB UPDATE 시도
😱 A와 B가 동시에 같은 데이터 수정 → Mutual Exclusion 깨짐!
```

> **면접 예상 질문:** Redis 분산 락의 기본 동작은? TTL 없이 락을 걸면 어떤 문제가 생기는가?

---

### Redisson Watchdog — TTL 자동 갱신

**TTL의 함정을 해결하는 메커니즘**: 작업 중에는 백그라운드 스레드가 락 TTL을 자동으로 연장.

```
🐶 Watchdog = "작업이 끝날 때까지 락 TTL을 자동으로 연장해주는 데몬"

[클라이언트 A] 락 획득 (TTL 30초)
   ↓
[10초마다] 🐶 "아직 일하는 중이지?" → TTL을 30초로 자동 갱신
   ↓
[작업 끝] unlock() → 🐶 멈춤 + 락 해제

⚠️ 만약 A가 완전히 죽으면 (네트워크 단절 / JVM crash):
   → Watchdog도 멈춤 → TTL 갱신 안 됨 → 30초 후 자동 만료 → 다른 클라이언트 진입 가능 ✅
```

```java
RLock lock = redisson.getLock("user:1:lock");
try {
    if (lock.tryLock(3, 10, TimeUnit.SECONDS)) {  // Watchdog 활성화
        // Double-Checked Locking
        Template cached = cache.get(1L);
        if (cached != null) return cached;

        // 임계 영역
        process();
    }
} finally {
    lock.unlock();
}
```

**핵심 포인트**:
- `tryLock` 안에서 캐시/상태 재확인(**Double-Checked Locking**) 필수 — 락 대기 중 다른 요청이 이미 처리했을 수 있음
- Redisson의 `lockWatchdogTimeout` 기본값 30초

> **면접 예상 질문:** Redisson Watchdog은 어떤 문제를 해결하는가? 어떻게 동작하는가?

---

### Redis 분산 락의 한계 — SPOF와 Master-Slave 복제 지연

**한계 1: 단일 장애점 (SPOF, Single Point of Failure)**

```
[클라이언트 A] 락 획득
[Redis 다운] 💀 → 락 정보 자체가 손실
[클라이언트 B] SETNX 성공 → 락 획득
😱 A와 B가 동시 임계 영역 침범
```

**한계 2: Master-Slave 복제 지연 (Replication Lag)**

실무에선 Redis를 Master + Slave 구조로 띄우는데, 복제는 **비동기**라 사고가 가능:

```
🖥️ [클라이언트 A]
   1. Master에 SETNX → 락 획득 ✅
   2. 작업 시작...

⏱️ [Master → Slave 복제는 비동기]
   - 락 정보가 아직 Slave에 복제 안 됨!

💥 [Master 다운]
   - Slave가 새 Master로 승격(Failover)
   - 새 Master엔 락 정보 없음!

🖥️ [클라이언트 B]
   1. 새 Master에 SETNX → 락 정보 없음 → 성공! 🥈
   2. 작업 시작...

😱 A와 B가 동시에 락 보유
```

이게 Redis 분산 락의 **가장 유명한 함정**.

> **면접 예상 질문:** Redis 분산 락의 SPOF/복제 지연 문제는 어떻게 발생하는가? 왜 Master-Slave 구조여도 위험한가?

---

### Redlock 알고리즘 — 여러 Redis로 SPOF 해소

Redis 만든 사람(Antirez)이 제안한 분산 락 알고리즘.

```
🔴 Redlock = "여러 개의 독립적인 Redis 인스턴스에 동시 락 획득"

[5개의 독립 Redis] (서로 복제 X, 완전 독립)

1. 클라이언트 A: 5개 Redis 모두에 SETNX 시도
2. 5개 중 과반수(3개 이상) 성공해야 → 진짜 락 획득 ✅
3. 한두 개 죽어도 나머지에서 과반수면 안전!
```

**핵심 보호**:
- 단일 Redis SPOF 해소 (1개 죽어도 4개에서 락 유효)
- Master-Slave 복제 지연 회피 (독립 인스턴스라 복제 자체 없음)

```java
// Redisson에서 Redlock 사용
RedissonClient redisson1 = Redisson.create(config1);
RedissonClient redisson2 = Redisson.create(config2);
RedissonClient redisson3 = Redisson.create(config3);

RLock lock1 = redisson1.getLock("lockKey");
RLock lock2 = redisson2.getLock("lockKey");
RLock lock3 = redisson3.getLock("lockKey");

RedissonRedLock redLock = new RedissonRedLock(lock1, lock2, lock3);
redLock.tryLock(3, 10, TimeUnit.SECONDS);
```

> **면접 예상 질문:** Redlock은 단일 Redis 분산 락의 어떤 문제를 해결하는가? 과반수(majority) 합의는 왜 필요한가?

---

### Redlock 논쟁과 Fencing Token — Kleppmann vs Antirez

학계에서 유명한 **Martin Kleppmann vs Antirez(Redis 창시자)** 논쟁.

**Kleppmann (분산 시스템 학자) 주장**:
> "Redlock도 완벽하지 않다. 클라이언트와 Redis 간의 **시계(clock) 동기화**가 보장 안 되거나, 클라이언트에서 **GC pause(Stop-the-World)** 같은 일이 일어나면 락 만료 판단이 어긋난다. 그동안 다른 클라이언트가 락을 잡고 일을 시작했는데, GC 풀린 첫 클라이언트가 자기는 아직 락 있다고 착각하고 작업을 계속할 수 있다."

**Kleppmann의 대안: Fencing Token** 🛡️

```
🔢 락을 줄 때마다 단조 증가 토큰 발급 (1, 2, 3, ...)

[클라이언트 A] 락 획득 → 토큰 33
[A의 GC pause로 멈춤 — 락 만료]
[클라이언트 B] 락 획득 → 토큰 34 → 작업 완료

[A가 깨어나서 DB write 시도] → "내 토큰 33"
   → DB/자원 서버: "이미 토큰 34가 처리됐어. 33은 무효!" → 거부 ✅
```

**핵심**: **DB나 자원 서버가 토큰을 검증해 오래된 락의 작업을 무력화**. 락 자체에 의존하지 않고 자원 측에서 한 번 더 검증.

**실무 적용 난이도**: Fencing Token은 자원 서버(DB 등)에 토큰 검증 로직을 추가해야 해서 도입 비용이 큼. 그래서 대부분 서비스는 Redisson Watchdog + 짧은 TTL로 타협하고, 미션 크리티컬한 영역에만 Fencing Token 도입.

> **면접 예상 질문:** Redlock의 한계는? Fencing Token은 어떤 원리로 동작하며 왜 더 안전한가?

---

### 락 회피 대안 — SKIP LOCKED, Kafka 비동기 직렬화

락 자체를 안 쓰고 동시성 문제를 해결하는 패턴들.

**1. PostgreSQL `SKIP LOCKED`** (큐/배치 워커 패턴):

```sql
-- 여러 워커가 대기 큐에서 동시 pull
SELECT * FROM job_queue
WHERE status = 'PENDING'
FOR UPDATE SKIP LOCKED  -- 다른 워커가 잡은 건 스킵
LIMIT 1;
```

- 워커 N개가 동시 실행해도 충돌 없이 각자 다른 row 처리
- Spring Batch, 메시지 처리, 작업 큐 등에 활용

**2. Kafka로 비동기 직렬화**:

```
요청 → Kafka 토픽에 적재 (즉시 응답)
     → Consumer 1개가 순차 처리 (파티션 키로 같은 자원은 같은 파티션 → 직렬화)
     → 락 자체가 필요 없음
```

- 락 없이도 **파티션 키 기반 순서 보장**으로 race condition 회피
- 응답 시간 단축 (요청만 적재하고 즉시 응답)
- 단점: 비동기 처리라 결과를 즉시 못 받음 (이벤트/폴링 필요)

**5년차 답변 정리**: 락은 만능이 아니다. **요건에 따라 락을 피해가는 설계**도 동시성 제어의 일부다.

> **면접 예상 질문:** 락을 쓰지 않고 동시성 문제를 해결하는 패턴은 어떤 게 있는가? 각 패턴은 어떤 상황에 적합한가?

---

## 학습 정리

- **Race Condition**은 동시성 문제의 본질. 락은 이를 막는 도구.
- `synchronized`는 JVM 내부 락이라 **서버마다 독립** → 분산 환경에선 외부 락(DB or Redis) 필요.
- **비관적 락(SELECT FOR UPDATE)** vs **낙관적 락(@Version)** — 충돌 빈도로 선택. 충돌 잦으면 비관적, 드물면 낙관적.
- **비관적 락은 DB 커넥션 점유 + 락 대기** → 트래픽 폭주 시 **커넥션 풀 고갈 → 서비스 전체 장애**로 번질 위험.
- **Redis 분산 락**은 DB 커넥션 점유 없이 락 가능. 핵심은 **SETNX + TTL + Redisson Watchdog(자동 TTL 갱신)**.
- Redis 분산 락도 **SPOF / Master-Slave 복제 지연** 함정이 있어 **Redlock(여러 Redis 과반수)** → **Fencing Token(자원 측 토큰 검증)** 으로 보강.
- 락 회피 대안: **PostgreSQL `SKIP LOCKED`(큐 처리)**, **Kafka 비동기 직렬화(파티션 키 기반 순서 보장)**.

## 참고

- Martin Kleppmann, "How to do distributed locking" (Redlock 비판 글)
- Antirez, "Is Redlock safe?" (반박 글)
- Redisson 공식 문서: `RLock`, `RedissonRedLock`, Watchdog
- 미리디 면접 대비 Q3 (분산 환경 동시성 제어) 모의 면접 기반 학습
