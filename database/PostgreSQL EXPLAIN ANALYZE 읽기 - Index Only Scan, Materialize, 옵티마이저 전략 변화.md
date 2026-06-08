# PostgreSQL EXPLAIN ANALYZE 읽기 — Index Only Scan, Materialize, 옵티마이저 전략 변화

> 날짜: 2026-06-07

## 내용

### EXPLAIN ANALYZE 읽는 법 — 안쪽부터 바깥, estimated vs actual

EXPLAIN 결과는 **들여쓰기 깊은 곳(안쪽)부터 바깥으로** 읽는다. 트리 구조라 가장 안쪽 노드가 먼저 실행되고, 그 결과가 위로 올라가면서 조립된다.

각 노드 줄에는 두 가지 숫자 묶음이 뜬다.

```
Seq Scan on diary d  (cost=0.00..3.50 rows=1 width=8)
                     (actual time=0.018..0.019 rows=2 loops=1)
```

- `cost=...`, `rows=`, `width=` → **옵티마이저가 미리 예측한 값** (추정치)
- `actual time=...`, `rows=`, `loops=` → **실제 실행해본 결과값**

`EXPLAIN` 만 쓰면 추정치만 나오고, `ANALYZE` 를 붙여야 진짜 쿼리를 돌려보고 실제값까지 함께 나온다. 둘이 많이 다르면 통계가 잘못됐다는 신호다.

`Rows Removed by Filter: 120` 같은 줄도 자주 보이는데, 이건 필터로 걸러서 버린 행 수다. 실제 통과 행 + 버린 행 ≈ 그 단계에서 읽은 전체 행 수라 테이블 크기를 역산하는 단서가 된다.

> **면접 예상 질문:** EXPLAIN과 EXPLAIN ANALYZE의 차이는 무엇이고, 실행계획에서 estimated와 actual이 크게 어긋날 때 어떤 문제를 의심해야 하나요?

---

### cost — 시간이 아닌 상대 점수, startup과 total

`cost=0.00..3.50` 처럼 점 두 개로 묶인 숫자는 옵티마이저가 매긴 **예상 작업량 점수**다. 시간(ms)이 아니라 상대 점수.

- 앞 숫자 (`0.00`) = **startup cost**: 첫 번째 결과 행이 나오기 시작하기까지의 비용
- 뒤 숫자 (`3.50`) = **total cost**: 마지막 행까지 다 가져오는 데 드는 총비용

기준은 보통 **"디스크 페이지 한 장을 순차로 읽는 비용 = 1.0 (`seq_page_cost`)"** 으로 잡고, 거기에 행 처리 비용 등을 더해서 계산한다.

| 연산 종류 | startup vs total | 이유 |
|---|---|---|
| Seq Scan | startup `0.00`, total 큼 | 처음부터 쭉 읽으므로 첫 행이 바로 나옴 |
| Hash, Sort | startup = total | 입력을 다 모아둬야 첫 결과가 나옴 |

옵티마이저는 실제 쿼리를 돌리기 *전에*, 머릿속으로 "Seq Scan 점수 vs Index Scan 점수"를 계산해서 더 싼 쪽을 고른다.

> **면접 예상 질문:** EXPLAIN의 cost 값은 무엇을 의미하며, startup cost와 total cost가 같아지는 노드는 어떤 특징이 있나요?

---

### Seq Scan이 선택되는 이유 — 페이지 단위 I/O와 selectivity

인덱스가 있는데도 Seq Scan이 떴다고 무조건 잘못된 게 아니다. PostgreSQL은 데이터를 **행 단위가 아니라 "페이지(보통 8KB)" 묶음**으로 읽는다. 행 하나가 약 40바이트라면 페이지 한 장에 ~200행이 들어간다.

예: 722건짜리 테이블 → 페이지 약 4장 → Seq Scan은 그냥 4장 읽으면 끝이라 거의 공짜다. 오히려 인덱스를 타면 "색인 뒤지고 → 다시 데이터 페이지 찾아가고" 하는 랜덤 I/O가 더 비싸진다.

**Selectivity(선택도)**가 핵심이다.

- 인덱스가 빛나는 상황: 전체 중 **아주 일부**만 콕 집어 찾을 때 (예: `WHERE user_id = 199`)
- Seq Scan이 유리한 상황: **대부분/전부**를 훑어야 할 때 (예: 전체 유저 대상 안티 조인)

도서관 비유로, "홍길동이 쓴 책 한 권 찾기"는 색인 카드로 직진하면 빠르지만, "모든 작가의 책을 다 확인해야 한다"면 색인 카드를 200번 왔다 갔다 하느니 책장 전체를 한 번 쭉 훑는 게 빠르다.

> **면접 예상 질문:** 인덱스가 있는데도 옵티마이저가 Seq Scan을 선택하는 이유 두 가지 이상을 데이터 규모와 selectivity 관점에서 설명해보세요.

---

### Stale Statistics — ANALYZE로 통계 갱신

옵티마이저가 cost를 계산할 때 테이블 행 수를 매번 세지 않는다. 미리 모아둔 **통계 정보(`pg_statistic`, `pg_class.reltuples`)** 를 본다.

그래서 대량 INSERT 직후에는 옵티마이저가 옛 행 수로 잘못된 플랜을 고를 수 있다. 창고에 물건이 잔뜩 들어왔는데 재고 장부를 아직 안 고친 상황이다.

증거 찾는 법: EXPLAIN ANALYZE 결과에서 **예측 `rows=` 와 실제 `actual ... rows=` 가 크게 어긋나면** 통계가 stale일 가능성이 높다.

해결: 통계만 갱신하면 된다.

```sql
ANALYZE diary;
-- 또는 VACUUM과 함께
VACUUM ANALYZE diary;
```

> **면접 예상 질문:** PostgreSQL에서 옵티마이저가 잘못된 실행계획을 고르는 흔한 원인 중 하나가 stale statistics입니다. 어떻게 발견하고 어떻게 해결하나요?

---

### Index Only Scan vs Index Scan — 커버링 인덱스와 Heap Fetches

두 종류를 헷갈리지 말 것.

| 구분 | 동작 | Heap Fetches |
|---|---|---|
| **Index Scan** | ①인덱스에서 위치 찾고 → ②실제 테이블(=heap)로 가서 나머지 컬럼 읽기 | 발생 |
| **Index Only Scan** | 쿼리가 필요로 하는 컬럼이 인덱스에 전부 있어서 ②번 단계 생략 | `0` |

인덱스는 그냥 화살표만 갖고 있는 게 아니라 **인덱스에 포함된 컬럼 값을 실제로 복사해서 정렬된 상태로 품고 있다.** `idx_diary_user_id_date(user_id, date)` 안에는 `user_id`, `date` 값이 그대로 들어있다.

쿼리가 user_id와 date만 필요로 한다면, 인덱스만 봐도 답이 나오니까 무거운 테이블 본체를 안 건드린다. → `Heap Fetches: 0`

이렇게 "쿼리가 필요한 모든 컬럼을 인덱스가 전부 갖고 있어서 테이블을 안 봐도 되는" 인덱스를 **커버링 인덱스(Covering Index)** 라고 한다. PostgreSQL에서는 `CREATE INDEX ... INCLUDE (...)` 로 비-key 컬럼을 인덱스에 추가로 실어 의도적으로 커버링 인덱스를 만들 수도 있다.

> **면접 예상 질문:** Index Scan과 Index Only Scan의 차이를 설명하고, 커버링 인덱스를 활용했을 때의 이점과 트레이드오프를 말해보세요.

---

### Materialize와 loops — 한 번 긁어 캐시, 200번 재사용

`loops`는 그 노드가 **몇 번 실행됐는지**의 횟수다. Nested Loop에서 바깥쪽이 200행이면 안쪽 노드는 보통 `loops=200` 으로 200번 실행된다.

함정: `actual time=...`, `rows=` 는 **1 loop 기준 평균값**이다. 진짜 총합을 구하려면 `× loops` 해야 한다.

`Materialize` 노드는 자식 결과를 **메모리에 캐시**해서, 부모가 반복 실행될 때 자식을 재실행하지 않고 캐시만 다시 읽게 만든다.

```
-> Materialize (loops=200)        ← 200번 호출되지만
   -> Index Only Scan (loops=1)   ← 자식은 1번만 실제 실행됨
```

비유: 시험 자료를 200명한테 나눠줘야 하는데, 매번 도서관 가서 원본을 다시 찾기 귀찮으니까 한 번만 찾아서 복사본을 떠두고 200명한테 그 복사본을 돌려보는 것.

옵티마이저는 자식 결과가 **작고 반복적으로 재사용될 때** Materialize를 끼워 넣는다.

> **면접 예상 질문:** 실행계획에서 Materialize 노드가 등장하는 이유와, 부모 노드의 `loops` 값과 자식 노드의 `loops` 값이 다를 수 있는 이유를 설명해보세요.

---

### Index Cond vs Join Filter — 인덱스가 직접 vs 메모리에서

같은 조건이라도 어디서 처리되느냐에 따라 비용이 다르다.

| 표기 | 처리 위치 | 의미 |
|---|---|---|
| `Index Cond` | 인덱스 내부 | 정렬을 이용해 인덱스가 **직접 점프해서** 찾는 조건. 빠름. |
| `Filter` / `Join Filter` | 메모리 (행 가져온 뒤) | 인덱스로는 못 좁히고 **일단 가져온 다음 대조**해서 거르는 조건. 상대적으로 느림. |

쿼리에 `WHERE d.user_id = u.id AND d.date = '2026-06-04'` 가 있어도, 실행계획에 따라 `user_id` 가 `Index Cond` 에 들어갈 수도 있고 `Join Filter` 로 빠질 수도 있다. 사라진 게 아니라 **자리를 옮긴 것**.

> **면접 예상 질문:** Index Cond와 Filter(또는 Join Filter)의 차이는 무엇이며, 같은 컬럼 조건이 둘 중 어디에 위치하느냐에 따라 성능에 어떤 영향을 주나요?

---

### 옵티마이저 전략 변화 — 데이터 양에 따라 작전 자체가 바뀐다

**같은 쿼리, 같은 인덱스, 같은 스키마**여도 데이터 양에 따라 옵티마이저는 전혀 다른 실행계획을 고른다.

실험: `NOT EXISTS` 안티 조인 쿼리 (`users` 200건, 인덱스 `idx_diary_user_id_date(user_id, date)`)

**Case A — diary 120건 (특정 날짜 일기 ≈ 2건)**

```
Nested Loop Anti Join
  Join Filter: (d.user_id = u.id)             ← user_id는 여기서 메모리 대조
  -> Seq Scan on users u   (rows=200, loops=1)
  -> Materialize           (rows=1, loops=200)
       -> Index Only Scan on diary d
            Index Cond: (date = '2026-06-04')  ← date만
            Heap Fetches: 0
```

전략: `date` 조건만으로 오늘치 일기 한 줌(2건)을 **1번만** 인덱스 스캔으로 긁어 Materialize에 캐시 → 유저 200명 돌면서 메모장에서 `user_id` 대조.

**Case B — diary 5만건**

```
Nested Loop Anti Join
  -> Seq Scan on users u   (rows=200, loops=1)
  -> Index Only Scan on diary d   (loops=200)
       Index Cond: (user_id = u.id) AND (date = '2026-06-04')  ← 둘 다
       Heap Fetches: 0
```

전략: 오늘치 일기를 통째로 캐시하기엔 양이 많으니, 유저 200명을 하나씩 돌면서 **매번 `(user_id, date)` 정밀 조준**으로 인덱스 probe. 인덱스 작업이 200번이지만 각각이 매우 작음.

| | Case A (120건) | Case B (5만건) |
|---|---|---|
| `Index Cond` | `date` 만 | `user_id` + `date` |
| `user_id` 처리 | `Join Filter` (메모리) | `Index Cond` (인덱스) |
| `Materialize` | O | X |
| 인덱스 스캔 횟수 | 1번 | 200번 |
| 캐시 양 | 2건 | (없음) |

핵심: 옵티마이저는 **"중간 결과 크기"와 "반복 횟수"의 곱**을 비교해서 더 싼 쪽을 고른다. 데이터가 적으면 "한 번 긁어 캐시 + 메모리 대조"가 싸고, 많으면 "유저별 정밀 probe 반복"이 싸다.

> **면접 예상 질문:** 같은 쿼리에 같은 인덱스가 걸려 있어도 데이터 양에 따라 실행계획이 달라지는 이유를 옵티마이저의 cost 모델 관점에서 설명해보세요.

---

## 학습 정리

- EXPLAIN 결과는 **안쪽부터 바깥**으로 읽고, `estimated rows`와 `actual rows`가 크게 어긋나면 stale statistics를 의심한다 (`ANALYZE 테이블;` 으로 갱신).
- `cost`는 시간(ms)이 아닌 **상대 점수**다 (디스크 페이지 1장 순차 읽기 = 1.0 기준). `startup..total` 두 값을 함께 본다.
- PostgreSQL은 **페이지(8KB) 단위**로 I/O 하므로 소량 데이터에서는 Seq Scan이 더 싸다. 인덱스는 **selectivity가 높을 때(소수만 콕 집을 때)** 빛난다.
- `Index Only Scan`은 **커버링 인덱스**일 때 발생하며 `Heap Fetches: 0` 으로 테이블 본체를 안 건드린다.
- `Materialize` 는 작은 자식 결과를 캐시해 반복 재사용한다. `actual time/rows` 는 항상 **1 loop 기준**이라 총합 계산 시 `× loops` 한다.
- `Index Cond`(인덱스가 직접) vs `Filter`/`Join Filter`(메모리에서 대조) 의 차이는 어떤 단계에서 거르는지의 문제다.
- 같은 쿼리·같은 인덱스도 데이터 양에 따라 옵티마이저가 **전략 자체를 바꾼다** ("한 번 긁어 캐시" ↔ "유저별 정밀 probe").
