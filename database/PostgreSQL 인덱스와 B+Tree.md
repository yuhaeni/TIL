# PostgreSQL 인덱스와 B+Tree

> 날짜: 2026-04-20

## 내용

### B-Tree vs B+Tree

PostgreSQL은 인덱스 기본 구조로 **B+Tree**를 채택한다.

**핵심 차이점:**

| | B-Tree | B+Tree |
|---|---|---|
| 데이터 위치 | 모든 노드(내부 + 리프) | **리프 노드에만** |
| 리프 노드 연결 | 없음 | **양방향 링크드 리스트** |
| 범위 탐색 | 트리를 다시 타고 내려가야 함 | 리프 노드만 순회하면 됨 → **빠름** |

```
B+Tree 리프 노드 연결:
[10, 20, 30] ⇄ [40, 50, 60] ⇄ [70, 80, 90]

→ "20 ~ 70 범위 조회"는 리프 노드만 좌우로 순회
```

**트레이드오프:**
- 리프 노드 간 링크 포인터를 항상 최신 상태로 유지 → **쓰기 오버헤드 ↑**
- INSERT/DELETE 시 B-Tree보다 부담이 큼

> ⚠️ "노드 하나에 여러 key 저장"은 B-Tree와 이진 탐색 트리의 차이지, B-Tree와 B+Tree의 차이가 아니다. 혼동 주의!

> **면접 예상 질문:** PostgreSQL이 B-Tree 대신 B+Tree를 채택한 이유와 트레이드오프는?

---

### 클러스터드 vs 논클러스터드 인덱스

| | 클러스터드 인덱스 | 논클러스터드 인덱스 |
|---|---|---|
| 리프 노드 내용 | **데이터 자체** | 데이터의 **주소**(포인터) |
| 테이블당 개수 | 1개 (정렬 기준) | 여러 개 가능 |
| 조회 시 접근 | 1번 (리프=데이터) | 2번 (인덱스 → 데이터) |

**PostgreSQL의 특징: 모든 인덱스가 논클러스터드**

```
PostgreSQL 구조:
[B+Tree 인덱스]      [힙(Heap) 파일]
 리프: ctid(주소) → 실제 데이터 행

→ 인덱스 조회 후 항상 힙 파일로 한 번 더 이동
→ "2번 접근"이 기본
```

PostgreSQL에서 Primary Key를 만들면 자동 생성되는 인덱스도 **논클러스터드**다. (MySQL InnoDB는 PK 인덱스가 클러스터드라는 점과 큰 차이!)

> **면접 예상 질문:** PostgreSQL의 PK 인덱스는 클러스터드인가? MySQL InnoDB와 어떻게 다른가?

---

### 커버링 인덱스(Covering Index)

**커버링 인덱스란**: 쿼리에 필요한 모든 컬럼을 인덱스 리프 노드에 포함시켜, **힙 파일 접근 자체를 없애는** 인덱스다.

```sql
-- 자주 실행되는 쿼리
SELECT user_id, status FROM orders WHERE created_at > '2026-01-01';

-- 일반 인덱스: created_at 인덱스 → 힙 접근 (2번)
CREATE INDEX idx_orders_created_at ON orders(created_at);

-- 커버링 인덱스: 인덱스만으로 결과 완성 (1번)
CREATE INDEX idx_orders_covering ON orders(created_at) INCLUDE (user_id, status);
```

**왜 PostgreSQL에서 더 중요한가?**
- 모든 인덱스가 논클러스터드 → **무조건 2번 접근이 기본**
- 커버링 인덱스로 힙 접근(랜덤 I/O)을 제거하면 성능 향상 효과가 크다

MySQL InnoDB는 PK 조회 시 자연스럽게 클러스터드라 빠르지만, **PostgreSQL은 커버링 인덱스 설계가 훨씬 중요**하다.

> **면접 예상 질문:** PostgreSQL에서 커버링 인덱스가 왜 더 중요한가? MySQL과 어떤 차이가 있는가?

---

### 인덱스에 모든 컬럼을 포함하면 안 되는 이유

커버링 인덱스가 좋다고 모든 컬럼을 넣으면 안 된다.

| 문제 | 설명 |
|---|---|
| **디스크 용량 증가** | 인덱스 자체가 비대해짐 |
| **쓰기 성능 저하** | INSERT/UPDATE/DELETE 시 인덱스도 정렬 유지 → 컬럼 많을수록 비용 ↑ |
| **메모리 효율 저하** | 인덱스가 캐시(shared_buffers)에 덜 올라옴 |

→ **자주 조회되는 컬럼만 선별**해서 커버링 인덱스 설계하는 것이 핵심.

> **면접 예상 질문:** 커버링 인덱스에 모든 컬럼을 포함하면 왜 안 되는가?

---

### 랜덤 I/O vs 풀 테이블 스캔

**랜덤 I/O 발생 원리:**
- 인덱스 리프에 주소(ctid)만 있음 → 힙 파일로 이동해 실제 데이터 조회
- 결과가 여러 건이면 디스크 여러 위치를 왔다갔다 → **랜덤 I/O 누적**

**풀 테이블 스캔이 더 빠른 경우:**

```
비유:
- 인덱스 조회 = 계단을 위/아래로 왔다갔다
- 풀 테이블 스캔 = 1층부터 끝까지 쭉 훑기

→ 결과가 전체 데이터의 대부분이면 쭉 훑는 게 더 빠름
```

PostgreSQL **쿼리 플래너(Query Planner)** 가 통계 정보를 바탕으로 자동으로 판단한다. 통계가 잘못되어 있으면 잘못된 선택을 할 수 있어 `ANALYZE`로 통계를 최신 상태로 유지하는 것이 중요하다.

> **면접 예상 질문:** 인덱스가 있어도 풀 테이블 스캔이 더 빠른 경우는? 쿼리 플래너는 무엇을 보고 판단하는가?

---

### 실무 쿼리 튜닝 순서

**1단계: 실행 계획 확인**

```sql
EXPLAIN SELECT ...        -- 예상 실행 계획만
EXPLAIN ANALYZE SELECT ... -- 실제 실행 시간까지 측정
```

**2단계: 인덱스 사용 여부 확인**
- `Seq Scan` → 풀 테이블 스캔 (인덱스 미사용)
- `Index Scan` / `Index Only Scan` → 인덱스 사용

**3단계: 풀스캔이라면 원인 분석**
- 조회 비율이 너무 높아 풀스캔이 더 유리한가?
- 인덱스가 없는 컬럼으로 조회하나?
- 통계가 오래되었나?

**4단계: 해결책 적용**

```sql
-- (1) 쿼리 조건 좁히기
-- Before: WHERE status = 'PAID' (80만 건)
-- After:
WHERE status = 'PAID' AND created_at > '2026-01-01'

-- (2) 커버링 인덱스 적용
-- SELECT * 대신 필요한 컬럼만 명시
SELECT user_id, amount FROM payments WHERE created_at > '2026-01-01';

CREATE INDEX idx_payments_covering
  ON payments(created_at)
  INCLUDE (user_id, amount);
```

> 💡 `SELECT *` 금지 규칙이 단순히 데이터 전송량 때문만이 아니라, **커버링 인덱스 최적화와 직결**된다는 점이 핵심!

> **면접 예상 질문:** 느린 쿼리를 트러블슈팅하는 순서는? `EXPLAIN`과 `EXPLAIN ANALYZE`의 차이는?

---

### Spring Data JPA 환경에서 쿼리 튜닝

JPA는 SQL을 추상화하므로 **실제 날아가는 쿼리를 먼저 확인**해야 한다.

```yaml
# application.yml
spring:
  jpa:
    show-sql: true
    properties:
      hibernate:
        format_sql: true
logging:
  level:
    org.hibernate.SQL: DEBUG
    org.hibernate.orm.jdbc.bind: TRACE  # 파라미터 바인딩 값까지
```

**튜닝 흐름:**
1. **하이버네이트 로그**로 실제 SQL 확인
2. 해당 SQL에 `EXPLAIN ANALYZE` 붙여서 실행 계획 분석
3. 풀스캔이면 → 조건 수정 또는 커버링 인덱스 적용
4. JPQL `SELECT new ...DTO(...)` 또는 Projection으로 필요한 컬럼만 조회

> **면접 예상 질문:** Spring Data JPA 환경에서 쿼리 튜닝은 어떤 순서로 진행하는가?

---

## 학습 정리

- **B+Tree**: 리프 노드 양방향 링크 → 범위 탐색에 강함, 쓰기 오버헤드 큼
- **PostgreSQL은 모든 인덱스가 논클러스터드** (MySQL InnoDB의 PK 클러스터드와 차이)
- 논클러스터드는 항상 "인덱스 → 힙" 2번 접근 → **커버링 인덱스로 힙 접근 제거**가 핵심 최적화
- 인덱스에 모든 컬럼 포함은 금지 → 디스크 용량/쓰기 비용 증가, 자주 조회 컬럼만 선별
- 조회 결과가 전체의 대부분이면 풀 테이블 스캔이 더 빠름 → 쿼리 플래너가 자동 판단
- 튜닝 시작점은 항상 **`EXPLAIN ANALYZE`**, JPA는 하이버네이트 로그 → EXPLAIN ANALYZE → 조건/커버링 인덱스 순
- `SELECT *` 금지는 데이터 전송량뿐 아니라 **커버링 인덱스 최적화**와 직결됨

## 참고

- PostgreSQL 공식 문서: Indexes
- Use The Index, Luke! (https://use-the-index-luke.com/)
- CarrotSettle (Java, Spring Boot 4.0.x) 프로젝트 기반 학습
