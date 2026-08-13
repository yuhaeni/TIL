# PostgreSQL EXPLAIN ANALYZE 실전 분석 — Index Cond, Filter, Nested Loop, 부분 복합 인덱스

> 날짜: 2026-08-13

## 내용

### 실행계획 읽기 — 추정치와 실제값, 부모·자식 노드

`EXPLAIN`은 플래너의 **예상 실행계획**을, `EXPLAIN ANALYZE`는 쿼리를 실제로 실행한 **실측 결과**까지 보여 준다. 노드 줄의 앞쪽 `cost`, `rows`, `width`는 추정치이고, `actual` 뒤의 `time`, `rows`, `loops`는 실제값이다.

```text
Seq Scan on entity e
  (cost=0.00..41.75 rows=1 width=8)
  (actual time=0.628..0.628 rows=1 loops=1)
```

- `actual time=시작..종료`는 각각 첫 행을 부모에게 전달하기까지와 노드 처리가 끝날 때까지의 경과 시간(ms)이다.
- `actual rows`는 **한 번의 실행(loop)에서** 부모에게 전달한 행 수다.
- `loops`는 노드가 실행된 횟수이며, 총 전달 행 수는 대략 `actual rows × loops`로 파악한다.

실행계획은 들여쓰기 구조를 따른다. 안쪽에 들여쓰기된 노드는 자식이고, 자식 결과를 받아 처리하는 바깥 노드가 부모다. 예를 들어 아래에서 바깥 `Nested Loop`가 부모이며, 안쪽 `Nested Loop`와 `Seq Scan on entity`가 각각 왼쪽·오른쪽 자식이다.

```text
-> Nested Loop
     -> Nested Loop
     -> Seq Scan on entity e
```

> **면접 예상 질문:** EXPLAIN ANALYZE에서 추정 `rows`와 `actual rows`를 구분해야 하는 이유와, `loops`를 포함해 실제 처리량을 해석하는 방법을 설명해보세요.

---

### Index Cond, Filter, Join Filter — 조건이 처리되는 위치

`WHERE` 절의 모든 조건이 같은 시점에 처리되지는 않는다. 실행계획에서는 조건이 **인덱스 탐색 전에 후보를 줄이는지**, 아니면 **행을 읽은 후 버리는지**를 구분해서 봐야 한다.

| 표기 | 의미 | 일반적인 사례 |
|---|---|---|
| `Index Cond` | 인덱스 스캔 범위를 정하는 조건 | `group_id = 42`, `parent_id = p.id AND occurred_on = CURRENT_DATE` |
| `Filter` | 노드가 읽은 후보 행에서 사후 제거하는 조건 | `state = 'DONE'`, 오늘 `completed_at` 범위, 추가 검증 조건 |
| `Join Filter` | 두 자식 노드의 결과를 조인한 뒤 조합을 남길지 판단하는 조건 | `a.owner_id = b.owner_id` |

예를 들어 baseline의 작업 이력 노드에서는 `group_id`만 `Index Cond`였고, 완료 상태와 오늘 완료 시각은 `Filter`였다. 따라서 같은 그룹의 과거 작업도 후보로 읽은 뒤 `Rows Removed by Filter: 365`만큼 버렸다.

```text
Index Cond: (group_id = 42)
Filter: state = 'DONE' AND completed_at is today
Rows Removed by Filter: 365
```

여기서 `Index Scan`이 보인다고 전체 테이블을 읽었다고 단정하면 안 된다. 인덱스 후보를 읽고 있었지만, 인덱스가 `state`, `completed_at`까지 탐색 범위로 제한하지 못해 불필요한 후보를 많이 읽은 것이 병목이다.

> **면접 예상 질문:** `Index Cond`와 `Filter`의 차이를 설명하고, 인덱스를 사용한 실행계획에서도 `Rows Removed by Filter`가 많이 나올 수 있는 이유를 말해보세요.

---

### Nested Loop — 왼쪽 결과마다 오른쪽을 반복하는 조인

`Nested Loop`는 왼쪽 자식이 반환한 각 행마다 오른쪽 자식을 실행해 조인한다. 왼쪽이 10행이고 오른쪽이 매번 1행을 반환하면 최대 10개의 조합이 생긴다. 오른쪽 자식의 `loops`는 보통 왼쪽 자식이 실제로 넘긴 행 수와 연결된다.

예시 baseline에서는 왼쪽 자식이 1행을 반환했으므로 오른쪽 `Seq Scan on entity`도 `loops=1`이었다. 그 뒤 `Join Filter: (a.owner_id = b.owner_id)`가 두 결과의 `owner_id`가 같은 조합만 남겼고, 부모 `Nested Loop`는 실제 1행을 반환했다.

중요한 점은 `Join Filter`가 조인 결과를 대상으로 한 사후 비교라는 것이다. 왼쪽 행 수가 커질수록 오른쪽 노드의 반복 실행과 조인 비교가 늘어날 수 있으므로, `actual rows`와 `loops`를 함께 봐야 한다.

> **면접 예상 질문:** Nested Loop의 동작 방식과, 실행계획에서 오른쪽 자식의 `loops`가 성능 병목을 판단하는 데 중요한 이유를 설명해보세요.

---

### 부분 복합 인덱스 — 완료 상태·그룹·오늘 범위를 먼저 좁히기

baseline 병목은 결과 테이블이 아니라 특정 그룹의 오늘 완료 작업을 찾는 작업 이력 탐색이었다. 결과 테이블의 기존 `(parent_id, occurred_on)` 인덱스는 이미 사용되고 있었으므로 유지했다.

```sql
CREATE INDEX idx_activity_latest_done
    ON activity (group_id, completed_at DESC, activity_id DESC)
    WHERE state = 'DONE';
```

각 구성 요소의 역할은 다음과 같다.

- `WHERE state = 'DONE'`: 완료가 아닌 작업은 인덱스 엔트리 자체에 넣지 않는 **부분 인덱스** 조건이다.
- `group_id`: 완료 작업 중 요청한 그룹의 작업으로 좁힌다.
- `completed_at DESC`: 해당 그룹 작업 중 조회 SQL의 오늘 범위로 좁히고, 완료 시각을 내림차순으로 보관한다.
- `activity_id DESC`: 같은 `completed_at`일 때의 추가 정렬 기준이며, 결과 테이블의 `parent_id`와 조인할 키를 인덱스에서 제공한다. 큰 ID가 항상 더 최신이라는 일반 규칙으로 해석하면 안 된다.

candidate에서는 완료 상태가 부분 인덱스 조건으로 충족되고, 그룹과 오늘 완료 시각이 모두 `Index Cond`에 들어갔다. 그 결과 baseline에서 사후에 제거하던 과거 작업 후보를 처음부터 읽지 않게 됐다.

```text
Index Only Scan using idx_activity_latest_done
  Index Cond: group_id = 42 AND completed_at is today
```

> **면접 예상 질문:** 부분 복합 인덱스의 키 순서와 부분 인덱스 술어를 어떤 기준으로 설계했는지, 그리고 인덱스 추가에 따른 쓰기 비용 트레이드오프를 설명해보세요.

---

### Index Only Scan, Heap Fetches, Buffers — 인덱스만 읽은 조건과 측정 해석

PostgreSQL의 B-tree 인덱스 리프 항목에는 인덱스에 정의한 키 값과 실제 행 위치 정보가 있다. 따라서 쿼리·조인에 필요한 값이 인덱스에 모두 있으면 실제 행 데이터가 있는 Heap을 다시 읽지 않고 `Index Only Scan`으로 결과를 낼 수 있다.

후보 인덱스는 `group_id`, `completed_at`, `activity_id`를 가진다. 이 중 `activity_id`는 결과 테이블의 `parent_id`와 조인하는 데 쓰이므로, 작업 이력 Heap을 다시 읽지 않고 다음 조인으로 전달할 수 있었다.

```text
Index Only Scan using idx_activity_latest_done
  Heap Fetches: 0
  Buffers: shared hit=7
```

다만 필요한 컬럼이 인덱스에 있다는 사실만으로 `Heap Fetches: 0`이 항상 보장되지는 않는다. PostgreSQL은 MVCC 가시성 확인이 필요하면 Heap을 다시 읽을 수 있다. 이번 측정에서 `Heap Fetches: 0`은 인덱스가 필요한 값을 제공했고, 해당 행들의 가시성 상태도 Heap 확인을 요구하지 않았다는 뜻이다.

`Buffers: shared hit=7`은 PostgreSQL shared buffer 캐시에서 **8KB 페이지 7개를 접근**했다는 의미다. 이는 물리 디스크 I/O가 7페이지 발생했다는 뜻이 아니다. baseline의 최상위 `shared hit=3,324`와 candidate의 `shared hit=26` 비교는 캐시 버퍼 접근량이 줄었다는 근거로 표현해야 한다.

동일한 warm cache 조건에서 10회 측정한 실행 시간 중앙값은 `7.0905ms → 0.0325ms`로 99.5% 감소했고, 최상위 shared buffer 접근량은 `3,324 → 26 pages`로 99.2% 감소했다. 물리 디스크 I/O 감소라고 과장하지 않고, **실행 시간 중앙값과 shared buffer 접근량을 개선했다**고 설명하는 것이 정확하다.

> **면접 예상 질문:** Index Only Scan이 선택되기 위한 조건과 `Heap Fetches: 0`이 항상 보장되지 않는 이유를 MVCC 가시성 관점에서 설명하고, `shared hit`을 물리 I/O로 해석하면 안 되는 이유를 말해보세요.

---

## 학습 정리

- 실행계획의 `cost`·앞쪽 `rows`는 추정치이고, `actual time`·`actual rows`·`loops`는 실제 실행 결과다.
- `Index Cond`는 인덱스 탐색 범위를 줄이고, `Filter`와 `Join Filter`는 이미 읽은 행 또는 조합을 사후에 걸러낸다.
- Nested Loop는 왼쪽 행마다 오른쪽 자식을 실행하므로, `actual rows × loops`와 오른쪽 자식의 반복 횟수를 함께 본다.
- 부분 복합 인덱스로 완료 상태·그룹·오늘 완료 시각을 탐색 단계에 반영해 과거 작업을 후보에서 제외했다.
- `Heap Fetches: 0`은 인덱스만으로 필요한 값을 반환하고 Heap 가시성 확인도 없었던 결과이며, `shared hit`은 물리 디스크 I/O가 아닌 shared buffer 접근량이다.

## 참고

- PostgreSQL `EXPLAIN (ANALYZE, BUFFERS)` 실행 결과
