# JPA 핵심 용어 — fetch, dirty, flush, version, auto-flush

> 날짜: 2026-05-07

## 내용

### fetch — DB에서 메모리로 데이터 끌어오기

**fetch = DB에서 데이터를 조회해서 메모리(애플리케이션)로 가져오는 동작.**

이미 익숙한 단어들에서 만난 적이 있다:
- `JOIN FETCH` — 연관된 자식 엔티티까지 함께 조회
- `FetchType.LAZY` / `FetchType.EAGER` — 언제 가져올지 전략

**`JpaPagingItemReader`의 "page fetch"** = 페이지 단위(`pageSize`)로 DB에서 데이터를 조회.

```java
SELECT * FROM settlement WHERE status='INCOMPLETED'
ORDER BY id LIMIT 10 OFFSET 0   -- 한 번의 fetch
```

> **면접 예상 질문:** JPA에서 fetch는 정확히 어떤 동작인가? `FetchType.LAZY`와 `EAGER`는 무엇을 결정하는가?

---

### dirty — 스냅샷과 달라진 상태

**dirty = 영속성 컨텍스트의 "스냅샷"(엔티티가 처음 영속화될 때 모습)과 달라진 상태.**

JPA는 엔티티를 영속화할 때 그 시점 모습을 **스냅샷**으로 떠 둔다. 이후 필드 변경 시 스냅샷과 달라지면 → **dirty**.

**Dirty Checking:** commit/flush 시점에 dirty 엔티티를 자동으로 UPDATE 해주는 메커니즘. **명시적 `save()` 호출 없이도** 변경이 DB에 반영되는 마법의 정체.

```java
Settlement s = repo.findById(1).get();   // 영속화 + 스냅샷 (status=INCOMPLETED)
s.setStatus(COMPLETED);                  // ✅ dirty
// commit 시점에 JPA가 알아서 UPDATE 실행
```

> **면접 예상 질문:** JPA의 Dirty Checking 메커니즘을 설명해보라. `save()` 호출 없이도 변경이 반영되는 이유는?

---

### flush — 변경사항을 SQL로 내보내기

**flush = 영속성 컨텍스트에 쌓인 변경사항을 실제 DB로 전송(SQL 실행)하는 동작.**

화장실 변기 flush의 어감 — "모아둔 걸 한꺼번에 내보낸다".

JPA는 성능상의 이유로 변경 즉시 SQL을 날리지 않고, **모았다가 flush 시점에 한 번에** 내보낸다.

**flush ≠ commit:**

| 구분 | flush | commit |
|---|---|---|
| 의미 | DB로 SQL 보내기 | 트랜잭션 확정 |
| 롤백 가능? | ✅ (아직 트랜잭션 안 끝남) | ❌ |
| 호출 시점 | auto-flush + 명시적 호출 | 트랜잭션 종료 |

**flush 발동 시점:**
- 트랜잭션 commit 시 (자동)
- JPQL 쿼리 실행 직전 (auto-flush)
- `em.flush()` 명시적 호출
- `EntityManager.setFlushMode()`에 따라 정책 변경 가능

> **면접 예상 질문:** flush와 commit의 차이는? JPA가 변경을 즉시 SQL로 보내지 않는 이유는?

---

### `@Version` — 낙관적 락의 충돌 감지 도구

**`@Version` 컬럼 = 낙관적 락(OptimisticLock)이 충돌을 감지하는 데 쓰는 컬럼.**

**낙관적 락 철학:** "충돌 안 날 거야" 하고 그냥 진행한 뒤 **나중에** 충돌 여부 확인.

```sql
UPDATE settlement
SET status='COMPLETED', version=1
WHERE id=1 AND version=0    -- ← 핵심
```

다른 트랜잭션이 먼저 commit 해 DB version이 이미 1이라면:
- `WHERE version=0`이 매칭 안 됨
- **영향 받은 행 0건**
- JPA가 감지 → `OptimisticLockException` (또는 `StaleStateException`)

**낙관적 락 vs 비관적 락:**

| | 낙관적 락 (`@Version`) | 비관적 락 (`SELECT FOR UPDATE`) |
|---|---|---|
| 전략 | 충돌 안 날 거라 가정 | 충돌 날 거라 가정 |
| 락 시점 | 없음 (commit 때 검증) | SELECT 시점부터 |
| 충돌 시 | 예외 → 재시도 | 대기 → 직렬화 |
| 적합 | 읽기 많고 쓰기 적음 | 쓰기 많고 경합 심함 |

> **면접 예상 질문:** 낙관적 락과 비관적 락의 차이는? `@Version` 컬럼은 어떻게 충돌을 감지하는가?

---

### auto-flush — 쿼리 실행 직전의 자동 flush

**auto-flush = 명시적으로 `em.flush()`를 호출하지 않아도 JPA가 특정 시점에 자동으로 flush를 발동시키는 동작.**

**언제 자동 발동?** → **쿼리 실행 직전.**

**왜 그래야 할까? — 일관성 때문:**

```java
order.setStatus(ACTIVE);                                    // dirty (아직 flush X)
List<Order> active = em.createQuery(
    "SELECT o FROM Order o WHERE o.status = 'ACTIVE'"
).getResultList();
```

**auto-flush 없으면:** 방금 변경한 order가 결과에서 **빠짐** ❌

**auto-flush 있음:** 쿼리 직전 dirty를 DB에 먼저 반영 → 일관된 결과 ✅

`JpaPagingItemReader`의 "다음 chunk read 직전 Reader EM의 auto-flush" = 다음 페이지 SELECT 직전, Reader EM이 자기가 들고 있던 dirty 엔티티를 먼저 DB로 flush 시도.

> **면접 예상 질문:** auto-flush는 언제 발동하는가? auto-flush가 없으면 어떤 일관성 문제가 생기는가?

---

### 통합 시나리오 — 5개 용어가 한 번에 폭발하는 상황

`JpaPagingItemReader transacted=true` + read-modify-write의 폭발 시나리오를 5개 용어로 재구성.

```
[chunk N]
1. Reader EM이 page를 fetch       → id=1 엔티티 영속화 (version=0 스냅샷)
2. Processor가 status 변경        → Reader EM에서 dirty 상태
3. Writer EM이 같은 엔티티 merge   → flush + commit으로 DB version=0→1

⚠️ Reader EM은 Writer가 한 일을 모름. 여전히 version=0 스냅샷을 들고 있음.

[chunk N+1]
4. 다음 page SELECT 직전, Reader EM auto-flush 시도
5. UPDATE settlement SET version=1 WHERE id=1 AND version=0
6. DB version은 이미 1 → 0 row affected
7. 💥 OptimisticLockException → batch FAILED
```

**해결:** `reader.setTransacted(false)` → Reader가 Step 트랜잭션의 EM을 그대로 사용 → **EM 1개로 통합** → Writer commit 결과를 Reader도 같은 EM으로 보고 있어 stale state 발생 여지 자체 소멸.

> **면접 예상 질문:** Reader EM과 Writer EM이 분리됐을 때 fetch / dirty / flush / version / auto-flush가 어떻게 충돌하는지 시나리오로 설명해보라.

---

## 학습 정리

- **fetch** = DB → 메모리로 데이터 가져오는 동작 (`JOIN FETCH`, `FetchType`이 그 예)
- **dirty** = 스냅샷과 달라진 상태 → Dirty Checking이 commit 시 자동 UPDATE 발동
- **flush** = 변경사항을 SQL로 내보내기 (≠ commit, 아직 롤백 가능)
- **`@Version`** = 낙관적 락의 충돌 감지 컬럼 → `WHERE version=N`이 0건 매칭이면 `OptimisticLockException`
- **auto-flush** = 쿼리 실행 직전 자동 flush → 메모리/DB 일관성 보장
- 5개 용어가 함께 폭발하는 대표 사례: **`JpaPagingItemReader transacted=true` + read-modify-write** → `transacted(false)`로 EM 통합해 해결

## 참고

- Hibernate Reference — Persistence Context, Flush Modes
- JPA 2.x Spec — Optimistic Locking, `@Version`
- Spring Batch Reference — `JpaPagingItemReader.transacted`
- CarrotSettle 정산 배치 트러블슈팅 분석 기반
