# PostgreSQL 인덱스와 B+Tree

> 날짜: 2026-04-20

## 내용

### B-Tree vs B+Tree

<img width="662" height="275" alt="image" src="https://github.com/user-attachments/assets/a4bc9c75-464e-4d2e-a1d7-665032555309" />


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

PostgreSQL **쿼리 플래너(Query Planner)** 가 통계 정보(Statistics)를 바탕으로 자동으로 판단한다. 통계가 잘못되어 있으면 잘못된 선택을 할 수 있어 `ANALYZE`로 통계를 최신 상태로 유지하는 것이 중요하다.

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

### 통계 정보와 ANALYZE/autovacuum — 옵티마이저의 판단 재료

쿼리 플래너(옵티마이저)는 **통계 정보(Statistics)** 를 보고 "Seq Scan이 빠를지, Index Scan이 빠를지" 비용을 추정한다.

> 💡 **용어 정리**: 쿼리 플래너(Query Planner) = 옵티마이저(Optimizer). PostgreSQL 공식 문서/소스코드는 `planner/optimizer`를 슬래시로 묶어 같은 개념으로 다룬다. PostgreSQL 진영은 `Planner`, MySQL/Oracle 진영은 `Optimizer` 용어를 선호한다.

**통계 정보의 정체**:
- `pg_statistic` 시스템 카탈로그에 저장
- 테이블 row 수, 컬럼 값 분포(어떤 값이 얼마나 흔한지), NULL 비율, 카디널리티 등

**ANALYZE — 통계 갱신 명령**:

```sql
ANALYZE 테이블명;          -- 특정 테이블만
ANALYZE;                  -- 전체 테이블
VACUUM ANALYZE 테이블명;   -- dead tuple 정리 + 통계 갱신
```

**autovacuum — 자동 갱신 데몬**:
- 백그라운드 데몬이 변경 row 비율이 `autovacuum_analyze_threshold` 임계값을 초과하면 자동 트리거
- 보통은 손으로 `ANALYZE` 안 쳐도 통계가 어느 정도 최신으로 유지됨

**왜 중요한가? — 통계가 오래되면 Bad Plan**:

```
어제까지 1만 row였던 테이블 → 오늘 9,999개 삭제 → 통계는 아직 어제 거
플래너: "1만 row니까 Seq Scan이 빠르겠다" 잘못 판단
실제로는 1 row만 남음 → 인덱스 스캔이 압도적으로 빠름
```

이런 걸 실무에서 **Bad Plan 문제**라 부르고, 갑자기 쿼리가 느려지는 흔한 원인이다.

**실무 팁**: 대량 INSERT/UPDATE 직후처럼 autovacuum이 따라잡기 전 쿼리가 폭주하는 시점엔 통계가 뒤처질 수 있다. 이럴 땐 **수동 `ANALYZE`를 명시적으로 실행**해서 신선도를 보장한다.

> **면접 예상 질문:** 옵티마이저는 무엇을 보고 실행 계획을 결정하는가? 통계가 오래되면 어떤 문제가 생기고 어떻게 관리하는가?

---

### 인덱스 무력화 함정 — Index가 있어도 안 타는 5가지 케이스

인덱스를 만들어놓고도 쿼리를 어떻게 쓰느냐에 따라 무력화되는 경우가 많다.

| 함정 | 예시 | 왜 안 타나? |
|---|---|---|
| 앞쪽 와일드카드 | `WHERE name LIKE '%토지%'` | 정렬 기준점 사라짐 (B+Tree는 prefix 기준) |
| 컬럼에 함수 적용 | `WHERE UPPER(name) = 'TOJI'` | 인덱스는 원본값 기준 정렬 |
| 타입 불일치 | `WHERE varchar_col = 123` | 암묵적 형변환 발생 |
| OR 조건 | `WHERE a = 1 OR b = 2` | 한쪽만 인덱스면 무력화 가능 |
| 부정 연산 | `WHERE name != '토지'` | 범위가 너무 넓어 옵티마이저가 Seq Scan 선택 |

**비유 — 도서관 색인**:
색인은 책 제목이 ㄱ→ㄴ→ㄷ→...→ㅎ 순서로 정렬되어 있다.
- ✅ "제목이 '토지'로 **시작**하는 책" → ㅌ 칸으로 점프 가능
- ❌ "제목 **어디에든** '토지'가 들어가는 책" → `대지토지수업` 같은 책은 ㄷ 칸에 있으니 ㄱ부터 ㅎ까지 다 뒤져야 함

**해결책**:
- **함수 인덱스 / 표현식 인덱스**: `CREATE INDEX idx_upper_name ON users (UPPER(name));`
- **부분 매칭이 필요하면 풀텍스트 검색**: PostgreSQL `pg_trgm` + GIN 인덱스, 또는 AWS Opensearch 같은 검색 엔진
- **OR → UNION 분리** 등 쿼리 리팩토링

> **면접 예상 질문:** 인덱스가 있는데도 Seq Scan으로 풀리는 흔한 함정은? 각각의 해결책은?

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

### 인덱스의 단점 — 별도 파일 저장과 쓰기 비용

인덱스는 결국 **별도의 물리 객체**로 디스크에 저장된다.

**PostgreSQL의 저장 구조**:

```
테이블 데이터  →  heap 파일 (예: base/16384/24576)
인덱스        →  별도의 인덱스 파일 (예: base/16384/24580)
메타 정보     →  시스템 카탈로그 (pg_class, pg_index 등)
```

`CREATE INDEX idx_name ON users(name);` 한 줄을 실행하면:
1. `pg_class`, `pg_index` 시스템 카탈로그에 인덱스 객체 등록
2. 디스크에 별도 파일이 생성되고 거기에 B+Tree 데이터 저장

**인덱스의 두 가지 핵심 단점**:

1. **저장 공간 증가**: 인덱스 파일이 추가되므로 디스크 용량을 추가로 차지. 인덱스 5개면 테이블 외에 인덱스 파일 5개.
2. **쓰기 성능 저하**: INSERT/UPDATE/DELETE 시 B+Tree에 노드 분할(split)/병합(merge)이 발생. 인덱스가 N개면 N개 트리 모두 재조정.

**비유 — 도서관 신간 입고**:

```
새 책 한 권 들어오면 → 책장(테이블)에만 꽂으면 끝? 아니!
색인 카드함(인덱스)에도 가나다순 정확한 자리에 카드 끼워넣어야 한다.
색인이 5종류면 5개 카드함 다 업데이트.
```

**실무 원칙**: 자주 조회되는 WHERE/JOIN 컬럼 중심으로 **선택적으로** 설계한다. 모든 컬럼에 인덱스를 거는 건 저장 공간과 쓰기 성능을 희생하는 거라 안 한다.

> **면접 예상 질문:** 인덱스의 단점은? 무작정 많이 만들면 안 되는 이유는?

---

## 학습 정리

- **B+Tree**: 리프 노드 양방향 링크 → 범위 탐색에 강함, 쓰기 오버헤드 큼
- **PostgreSQL은 모든 인덱스가 논클러스터드** (MySQL InnoDB의 PK 클러스터드와 차이)
- 논클러스터드는 항상 "인덱스 → 힙" 2번 접근 → **커버링 인덱스로 힙 접근 제거**가 핵심 최적화
- 인덱스에 모든 컬럼 포함은 금지 → 디스크 용량/쓰기 비용 증가, 자주 조회 컬럼만 선별
- 조회 결과가 전체의 대부분이면 풀 테이블 스캔이 더 빠름 → 쿼리 플래너가 자동 판단
- 튜닝 시작점은 항상 **`EXPLAIN ANALYZE`**, JPA는 하이버네이트 로그 → EXPLAIN ANALYZE → 조건/커버링 인덱스 순
- `SELECT *` 금지는 데이터 전송량뿐 아니라 **커버링 인덱스 최적화**와 직결됨
- **쿼리 플래너 = 옵티마이저**, `pg_statistic` 통계 정보 기반 비용 추정 → 통계가 오래되면 Bad Plan, `ANALYZE`/autovacuum으로 관리
- **인덱스 무력화 함정 5종**: LIKE '%xx%', 컬럼 함수 적용, 타입 불일치, OR, 부정 연산 → 함수 인덱스/풀텍스트 검색/쿼리 리팩토링으로 우회
- 인덱스는 **별도 파일**로 저장 → 저장 공간 증가 + B+Tree split/merge로 쓰기 성능 저하 → 선택적 설계 원칙

## 참고

- PostgreSQL 공식 문서: Indexes
- Use The Index, Luke! (https://use-the-index-luke.com/)
- CarrotSettle (Java, Spring Boot 4.0.x) 프로젝트 기반 학습
