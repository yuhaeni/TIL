# @Transactional 격리 수준

> 날짜: 2026-04-17

## 내용

### 격리 수준(Isolation Level)이란?

"다른 트랜잭션의 변경 사항을 어디까지 허용할 거냐"를 결정하는 옵션이다.

```java
@Transactional(isolation = Isolation.READ_COMMITTED)
```

- 격리 수준 **낮음** → 성능 좋음, 데이터 정합성 낮음
- 격리 수준 **높음** → 데이터 정합성 높음, 성능 낮음

> **면접 예상 질문:** 격리 수준이 높을수록 좋은 건가? 트레이드오프는?

---

### 동시성으로 인한 3가지 문제

#### Dirty Read (더티 리드)

커밋되지 않은 데이터를 읽는 현상이다.

```
트랜잭션 A: 주문 금액을 0원으로 UPDATE (미커밋)
트랜잭션 B: 0원으로 읽어서 계산
트랜잭션 A: 롤백!
→ B는 존재하지 않는 데이터를 읽은 꼴
```

#### Non-Repeatable Read (반복 불가능한 읽기)

같은 행을 두 번 읽었는데 값이 달라지는 현상이다. 다른 트랜잭션의 **UPDATE**가 원인이다.

```
트랜잭션 B:
  1. SELECT amount → 10,000원
  (트랜잭션 A가 5,000원으로 UPDATE 후 커밋)
  2. SELECT amount → 5,000원 (같은 쿼리인데 결과가 달라짐)
```

#### Phantom Read (유령 읽기)

같은 범위 쿼리를 두 번 실행했는데 행의 개수가 달라지는 현상이다. 다른 트랜잭션의 **INSERT/DELETE**가 원인이다.

```
트랜잭션 B:
  1. SELECT COUNT(*) WHERE status = 'CONFIRMED' → 100건
  (트랜잭션 A가 새 주문 INSERT 후 커밋)
  2. SELECT COUNT(*) WHERE status = 'CONFIRMED' → 101건
```

| | Non-Repeatable Read | Phantom Read |
|---|---|---|
| 대상 | 같은 행의 **값 변경** | **행 자체 추가/삭제** |
| 원인 | UPDATE | INSERT / DELETE |

> **면접 예상 질문:** Dirty Read, Non-Repeatable Read, Phantom Read의 차이는?

---

### 격리 수준 4단계

| 격리 수준 | Dirty Read | Non-Repeatable Read | Phantom Read | 성능 |
|---|---|---|---|---|
| `READ_UNCOMMITTED` | 허용 | 허용 | 허용 | 가장 빠름 |
| `READ_COMMITTED` | 방지 | 허용 | 허용 | 빠름 |
| `REPEATABLE_READ` | 방지 | 방지 | 허용 | 중간 |
| `SERIALIZABLE` | 방지 | 방지 | 방지 | 가장 느림 |

**이름이 주는 힌트:**
- `READ_UNCOMMITTED` → "커밋 안 된 것도 읽음"
- `READ_COMMITTED` → "커밋된 것만 읽음"
- `REPEATABLE_READ` → "반복해서 읽어도 같은 결과 보장"
- `SERIALIZABLE` → "순차적으로 처리" (동시성 거의 제거)

**DB별 기본 격리 수준:**

| DB | 기본 격리 수준 |
|---|---|
| MySQL (InnoDB) | REPEATABLE_READ |
| PostgreSQL | READ_COMMITTED |
| Oracle | READ_COMMITTED |

MySQL InnoDB가 `REPEATABLE_READ`를 기본으로 쓰는 이유: MVCC 기반으로 읽기 시 락 없이 스냅샷으로 동작하고, Gap Lock으로 Phantom Read까지 상당 부분 방지하여 안정성과 성능을 동시에 확보할 수 있기 때문이다.

> **면접 예상 질문:** MySQL의 기본 격리 수준이 REPEATABLE_READ인 이유는?

---

### 격리 수준 선택 기준 — 정산 시스템 예시

정산 시스템에서 가장 위험한 문제는 잘못된 데이터를 읽어 금액을 잘못 계산하는 것이다.

```
트랜잭션 A: 환불 처리 중 (10,000원 → 0원 UPDATE, 미커밋)
트랜잭션 B: 정산 배치 실행
    → Dirty Read로 0원 읽음 → 정산금 0원 계산
    → A가 롤백됨 → 정산은 이미 0원으로 처리됨! 💥
```

**`REPEATABLE_READ` 권장 근거:**
- Dirty Read 방지 필수 (정산 금액 정합성)
- Non-Repeatable Read 방지 필요 (배치 중 같은 주문을 두 번 읽을 때 값 변경 방지)
- Phantom Read는 "기준일 자정 이전 확정 건만 처리"하는 설계로 애플리케이션 레벨에서 방지 가능
- `SERIALIZABLE`은 대량 배치에 과도한 성능 저하

```java
@Transactional(isolation = Isolation.REPEATABLE_READ)
public void calculateSettlement(LocalDate baseDate) { ... }

@Transactional(isolation = Isolation.READ_COMMITTED, readOnly = true)
public List<SettlementResponse> findSettlements(...) { ... }
```

> **면접 예상 질문:** 정산 시스템에 적합한 격리 수준은? `SERIALIZABLE`을 쓰지 않아도 되는 이유는?

---

## 학습 정리

- 격리 수준은 성능과 데이터 정합성 사이의 트레이드오프
- Dirty Read(미커밋 읽기) → Non-Repeatable Read(값 변경) → Phantom Read(행 추가/삭제) 순으로 심각도 증가
- READ_COMMITTED: 대부분의 일반 서비스에 적합 / REPEATABLE_READ: 정합성이 중요한 금융/정산 시스템
- Phantom Read는 격리 수준보다 애플리케이션 레벨 설계로 방지하는 것이 성능상 유리한 경우가 많음
- MySQL InnoDB는 MVCC + Gap Lock으로 REPEATABLE_READ에서도 높은 안정성 제공

## 참고

- CarrotSettle (Java, Spring Boot 4.0.x) 프로젝트 기반 학습
