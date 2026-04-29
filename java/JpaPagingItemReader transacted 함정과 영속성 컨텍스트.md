# JpaPagingItemReader `transacted` 함정과 영속성 컨텍스트

> 날짜: 2026-04-29

## 내용

### 문제 — chunk 경계에서 터지는 `StaleStateException`

Spring Batch에서 `JpaPagingItemReader` 기본 설정 + read-modify-write 패턴 조합으로 운영하다 chunk 경계를 넘는 순간 발생한 실제 장애.

**증상:**
- chunk size 10 + 1,000건 정산 배치 → Job FAILED
- 에러: `StaleStateException: Unexpected row count (expected row count 1 but was 0)`
- 기존 통합테스트(chunk size 100 + 데이터 3건)는 정상 통과 → **chunk 1회로 끝나는 케이스에선 노출 안 됨**

> **면접 예상 질문:** Spring Batch의 `StaleStateException`은 어떤 상황에서 발생하는가? 통합테스트 통과가 안전성을 보장하지 못하는 사례는?

---

### 영속성 컨텍스트(EntityManager) = "작업 책상"

**핵심 비유:** EntityManager = JPA가 entity를 임시로 보관하는 **작업 책상**.

**`transacted=true` (Spring Batch 기본값)일 때 컴포넌트별 책상:**

| 컴포넌트 | 사용 EntityManager |
|---|---|
| **Reader** | 자체 트랜잭션 + 자체 EM (page fetch 전용) |
| **Processor** | Reader EM의 영속 entity를 직접 수정 (`settlement.complete()`) |
| **Writer** | Step 트랜잭션의 별도 EM (`em.merge → flush → clear`) |

**핵심 원칙:** 같은 entity가 **두 책상에 동시에 올라가면** 한쪽 변경이 다른 쪽에 반영되지 않아 **stale state**로 폭발한다.

> **면접 예상 질문:** EntityManager는 무엇이고 왜 "작업 책상"에 비유할 수 있는가?

---

### 폭발 시나리오 — chunk N+1 read에서 stale flush

```
[chunk N]
  Reader EM   : Settlement#1 영속화 (version=0)
  Processor   : Reader EM 안 entity를 dirty 변경 (status=COMPLETED)
  Writer EM   : merge → UPDATE → DB version 0→1
                em.clear() ── Writer EM만 비워짐, Reader EM은 그대로 ⚠️

[chunk N+1 read 진입]
  Reader EM   : doReadPage 내부에서 flush()
                → 자기 EM에 잔류한 dirty entity (version=0) 발견
                → UPDATE WHERE id=1 AND version=0
                → DB는 이미 version=1 → 0 row affected
                → StaleStateException 💥
```

**왜 기존 테스트는 통과?**
- chunk size 100 + 데이터 3건 → chunk가 **1번만 돌고 끝**
- 다음 chunk read 자체가 없으니 Reader EM이 flush할 기회 없음
- chunk size 10 + 1,000건(=100 chunks)에서야 **두 번째 chunk read 시점**에 폭발

> **면접 예상 질문:** Reader EM과 Writer EM이 분리되어 있을 때 read-modify-write 패턴이 왜 위험한가?

---

### 해결 — `.transacted(false)`

`JpaPagingItemReaderBuilder`에 `.transacted(false)` 추가해 **Reader가 Step 트랜잭션의 EM을 공유**하도록 변경.

```java
return new JpaPagingItemReaderBuilder<Settlement>()
    .name("settlementReader")
    .entityManagerFactory(entityManagerFactory)
    .queryProvider(queryProvider)
    .parameterValues(parameters)
    .pageSize(chunkSize)
    .transacted(false)        // ← 핵심
    .build();
```

| 옵션 | 동작 |
|---|---|
| `transacted=true` (기본) | Reader 자체 트랜잭션/자체 EM → Writer EM과 분리 → **본 이슈 발생** |
| `transacted=false` | Reader가 Step 트랜잭션 EM 공유 → Writer `em.clear()` 시 Reader 시야에서도 정리 |

> **면접 예상 질문:** `JpaPagingItemReader.transacted(false)`는 어떤 동작 차이를 만드는가?

---

### 왜 기본값이 `transacted=true`인가 — 교과서 ETL 패턴 기준

Spring Batch의 "교과서 패턴"은 대부분 **read-only** 또는 **다른 곳으로 출력**:
- A 테이블에서 읽어 → 가공 → 파일로 쓰기
- A에서 읽어 → Kafka로 보내기
- A에서 읽어 → 다른 테이블에 INSERT

이런 ETL 패턴에서 Reader가 **자기 트랜잭션**을 가지면:
- **페이지마다 짧은 트랜잭션** → 락을 오래 안 잡음
- **스냅샷 일관성** 보장

→ 일반 ETL에 최적화된 기본값.

**이번 케이스는 read-modify-write** (읽은 entity를 수정해 같은 테이블 UPDATE) 라는 **특수 케이스** → 두 EM이 충돌.

> **면접 예상 질문:** `transacted=true`가 일반 ETL에는 적합한 이유는? 어떤 패턴에서 부적합한가?

---

### read-modify-write 대안 비교

| 방법 | 특징 | 트레이드오프 |
|---|---|---|
| `JpaPagingItemReader` + `transacted(false)` | 가장 적은 코드 변경 | Step 트랜잭션이 길어짐, 락 점유 증가 |
| `JdbcCursorItemReader` + `JdbcTemplate` | JPA 영속성 컨텍스트 자체 회피 | JPA 도메인 로직 활용 어려움 |
| Reader는 **ID만** 읽고, Processor에서 새 EM으로 조회+수정 | entity를 Reader EM에 묶지 않음 | 추가 SELECT 비용 |
| JPQL **bulk update** | 단순 상태 전이만 있을 때 빠름 | per-row 검증/이벤트 로직 못 살림 |

**선택 가이드:**
- 도메인 로직 풍부 → `transacted(false)` 또는 ID-only Reader
- 대량 단순 상태 전이 → bulk update
- 복잡한 가공 + 다른 시스템 연계 → JdbcCursor + JPA 분리

> **면접 예상 질문:** Spring Batch에서 read-modify-write 패턴의 4가지 대안과 각각의 트레이드오프는?

---

### 핵심 교훈 — 통합테스트 설계와 기본값 인지

1. **같은 entity는 하나의 EM(책상)에서만 다뤄야 한다.** 두 EM에 동시 올라가면 한쪽 변경이 반영 안 돼 stale state로 폭발.
2. **통합테스트 통과 ≠ 안전.** **chunk 경계를 넘는 케이스**(chunk size < 데이터량)도 반드시 테스트.
3. **기본값을 쓸 때도 그 기본값이 무엇을 하는지 알고 써야 한다.** `transacted=true`는 ETL용 기본값이지 만능 안전 옵션이 아님.

**테스트 설계 체크리스트:**
- [ ] chunk size < 데이터량 (chunk 경계 다회 발생)
- [ ] skip / retry 동작 시
- [ ] 빈 결과 / 1건 / 정확히 chunk size 배수
- [ ] 트랜잭션 롤백 후 재실행

> **면접 예상 질문:** Spring Batch 통합테스트 설계 시 반드시 검증해야 할 시나리오는?

---

## 학습 정리

- `JpaPagingItemReader`의 `transacted=true`(기본)는 **Reader 자체 EM** 사용 → Writer EM과 분리됨
- read-modify-write 패턴에서 Reader EM에 dirty entity가 잔류 → 다음 chunk read의 flush가 stale UPDATE → `StaleStateException`
- chunk 1회로 끝나는 테스트는 **chunk 경계를 못 넘어** 이슈 노출 X
- 해결: `.transacted(false)` → Reader가 Step 트랜잭션 EM 공유 → Writer `clear()`가 Reader에도 반영됨
- `transacted=true` 기본값은 **read-only ETL 최적화** — 짧은 트랜잭션, 스냅샷 일관성
- read-modify-write 대안: `transacted(false)` / JdbcCursor / ID-only Reader / bulk update
- 교훈: **하나의 EM 원칙**, **chunk 경계 테스트 필수**, **기본값을 모르고 쓰지 말기**

## 참고

- Spring Batch Reference — `JpaPagingItemReader`, transactional behavior
- Hibernate Reference — Persistence Context, OptimisticLockException/StaleStateException
- CarrotSettle 정산 시스템 chunk 경계 장애 분석 기반
