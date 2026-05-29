# NOT EXISTS 최적화 — Anti Join, Short-circuit, NULL 3치 논리, SELECT 1

> 날짜: 2026-05-29

## 내용

### 일기 미작성 유저 조회 — 세 가지 방식

"일기를 작성하지 않은 유저"를 찾는 SQL은 보통 세 가지로 쓴다.

```sql
-- 1) LEFT JOIN + IS NULL
SELECT u.*
FROM users u
LEFT JOIN diaries d ON u.id = d.user_id
WHERE d.user_id IS NULL;

-- 2) NOT EXISTS (권장)
SELECT u.*
FROM users u
WHERE NOT EXISTS (
    SELECT 1
    FROM diaries d
    WHERE d.user_id = u.id
);

-- 3) NOT IN (주의 필요)
SELECT *
FROM users
WHERE id NOT IN (
    SELECT user_id
    FROM diaries
    WHERE user_id IS NOT NULL
);
```

세 쿼리 모두 결과는 같아 보이지만, **옵티마이저 동작**과 **NULL 안전성** 측면에서 차이가 크다.

> **면접 예상 질문:** "일기를 작성하지 않은 유저"를 조회하는 SQL을 세 가지 이상 작성하고, 각각의 차이를 설명해주세요.

---

### Short-circuit — NOT EXISTS의 첫 번째 강점

`NOT EXISTS`는 서브쿼리에서 **매칭되는 row가 1개라도 발견되면 즉시 중단**한다. 일기가 100개 있는 유저를 검사할 때, 1개만 찾고 바로 "있음"으로 판단하고 다음 유저로 넘어간다.

반면 `LEFT JOIN + IS NULL`은:
- 일기 100개를 **전부 매칭**한 뒤
- WHERE 절에서 NULL인 row만 걸러낸다
- → 100개나 매칭된 유저는 어차피 결과에서 **버려질 행**이므로, 비싼 작업이 낭비된다

핵심은 **"존재 여부만 보면 되는 작업을 값 매칭으로 풀면 비효율적"** 이라는 점.

> **면접 예상 질문:** NOT EXISTS와 LEFT JOIN + IS NULL의 옵티마이저 동작 차이를 short-circuit 관점에서 설명해주세요.

---

### Anti Join — 옵티마이저의 내부 변환

NOT EXISTS는 옵티마이저에 의해 **Anti Join**으로 변환된다. 조인 종류 중 다음 두 가지를 알아두면 좋다.

| 조인 종류 | 동작 | SQL 표현 |
|---|---|---|
| **Semi Join** | 매칭 row가 있으면 왼쪽 row 반환 | `EXISTS` |
| **Anti Join** | 매칭 row가 **없으면** 왼쪽 row 반환 | `NOT EXISTS` |

PostgreSQL `EXPLAIN` 결과에서 `Hash Anti Join`, `Nested Loop Anti Join` 같은 표현으로 등장한다. 똑똑한 옵티마이저라면 `LEFT JOIN + IS NULL`도 같은 Anti Join으로 변환해주기 때문에, 현대 DB(PostgreSQL/MySQL 8.0+)에서는 실행 계획이 거의 동일하게 나오는 경우가 많다.

Anti Join의 동작 방식:
- 왼쪽 테이블(users)의 각 row마다
- 오른쪽 테이블(diaries)에서 매칭되는 row를 **하나라도** 찾으면 → 버림
- 하나도 못 찾으면 → 결과에 포함

→ Short-circuit과 불필요한 매칭 회피가 자연스럽게 따라온다.

> **면접 예상 질문:** Semi Join과 Anti Join의 차이는 무엇이며, EXISTS/NOT EXISTS는 옵티마이저에서 어떻게 변환되나요?

---

### NULL 3치 논리 — NOT IN이 위험한 이유

SQL의 NULL은 "값이 없음"이 아니라 **"알 수 없음(unknown)"** 이다. 그래서 다음 비교 결과는 모두 `UNKNOWN`이 된다.

```sql
5 != NULL        -- UNKNOWN (false 아님!)
5 = NULL         -- UNKNOWN
NULL = NULL      -- UNKNOWN
```

AND 진리표에서 **`true AND UNKNOWN`은 `UNKNOWN`** 이다. 그리고 WHERE 절은 **`true`인 row만** 통과시킨다 (`false`, `UNKNOWN` 모두 탈락).

이게 `NOT IN`의 함정이다.

```sql
WHERE id NOT IN (1, 2, NULL)
-- 내부적으로 풀면
WHERE id != 1 AND id != 2 AND id != NULL
-- 마지막 조건 → UNKNOWN
-- 전체 결과 → true AND true AND UNKNOWN = UNKNOWN
-- → 모든 row가 WHERE에서 탈락 → 결과 텅 빔
```

서브쿼리 결과에 NULL이 **단 하나라도 섞이면** 전체 결과가 비어버린다. 그래서 `WHERE user_id IS NOT NULL`을 반드시 붙여야 한다.

반면 **NOT EXISTS**는 값을 비교하지 않고 **"행이 존재하느냐 안 하느냐"** 만 본다 (`true` / `false` 둘 중 하나). NULL이 끼어들 여지가 없으니 3치 논리에 휘말리지 않는다.

> **면접 예상 질문:** NOT IN에서 NULL이 위험한 이유를 3치 논리 관점에서 설명해주세요. NOT EXISTS는 왜 안전한가요?

---

### Anti Join과 인덱스 — diaries.user_id의 중요성

Anti Join은 결국 "users의 각 row마다 diaries에서 `user_id = u.id`인 row를 찾는다"는 작업이다.

| 상황 | 비교 횟수 (users 1만 × diaries 100만) |
|---|---|
| 인덱스 없음 (풀스캔) | 1만 × 100만 = **100억 번** |
| `diaries.user_id` 인덱스 (B+Tree) | 1만 × log(100만) ≈ **20만 번** |

오른쪽 테이블의 **조인 키 인덱스**가 Anti Join 성능의 핵심이다. NOT EXISTS든 LEFT JOIN이든 이 인덱스가 없으면 풀스캔으로 떨어진다.

> **면접 예상 질문:** NOT EXISTS 쿼리의 성능을 좌우하는 인덱스 설계 포인트는 무엇인가요?

---

### SELECT 1 — 관용구의 진짜 이유

`NOT EXISTS (SELECT 1 FROM ...)`에서 `1`은 **'hello'와 똑같이 의미 없는 값**이다. EXISTS는 row의 존재 여부만 보므로 SELECT 절에 뭘 쓰든 결과가 같다.

```sql
SELECT 1 FROM diaries WHERE ...
SELECT * FROM diaries WHERE ...
SELECT 'hello' FROM diaries WHERE ...
-- 모두 EXISTS 결과 동일
```

**현대 옵티마이저**(PostgreSQL, MySQL 8.0+, Oracle)는 `EXISTS (SELECT *)`도 "어차피 존재 여부만 보면 되니까" 자동 최적화한다. 즉 **실행 계획이 완전히 동일**하다.

그럼에도 `SELECT 1`을 관용으로 쓰는 이유는 **성능이 아니라 가독성**이다.

1. **가장 짧음** — 1글자
2. **컬럼을 안 읽음** — `SELECT *`는 "모든 컬럼을 읽나?" 오해 소지
3. **관용구** — `SELECT 1 FROM ... WHERE EXISTS`를 보면 "아, 존재 확인이구나" 한눈에 파악

→ **사람을 위한 컨벤션**. 면접에서 "SELECT 1을 쓰는 이유가 성능 때문인가요?"는 살짝 함정 질문이다.

> **면접 예상 질문:** EXISTS 서브쿼리에서 `SELECT 1`과 `SELECT *`의 차이는 무엇인가요? 성능 차이가 있나요?

---

## 학습 정리

- **NOT EXISTS가 권장되는 4가지 이유**: ①Short-circuit(row 1개 찾으면 중단) ②불필요한 매칭 회피(LEFT JOIN 대비) ③NULL 안전(3치 논리 무관) ④Anti Join으로 옵티마이저 변환
- **NOT IN의 함정**: 서브쿼리에 NULL 1개라도 섞이면 `true AND UNKNOWN = UNKNOWN`이 되어 전체 결과가 비어버린다. `WHERE ... IS NOT NULL` 필수
- **Anti Join의 성능 핵심**: 오른쪽 테이블의 조인 키 인덱스. 없으면 풀스캔으로 떨어져 N×M 비교가 발생
- **SELECT 1은 성능이 아니라 가독성**: 옵티마이저 입장에서 `SELECT *`과 동일. 의도 전달용 관용구
- 현대 옵티마이저는 `LEFT JOIN + IS NULL`과 `NOT EXISTS`를 같은 Anti Join으로 변환하는 경우가 많지만, **의도 표현과 NULL 안정성** 측면에서 NOT EXISTS가 가장 무난한 선택
