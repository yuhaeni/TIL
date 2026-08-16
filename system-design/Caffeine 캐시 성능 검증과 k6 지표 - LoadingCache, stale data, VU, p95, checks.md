# Caffeine 캐시 성능 검증과 k6 지표 — LoadingCache, stale data, VU, p95, checks

> 날짜: 2026-08-14

## 내용

Caffeine 로컬 캐시가 원본 저장소 접근을 줄이는 흐름과, 그 효과를 k6로 측정할 때 결과를 과장하지 않고 해석하는 방법을 정리한다.

### LoadingCache의 hit · miss · load — 캐시에 값이 채워지는 시점

`LoadingCache`는 애플리케이션이 `get(key)`로 조회할 때 동작한다. 캐시에 key A의 값이 있으면 **cache hit**으로 값을 즉시 반환하므로 원본 저장소를 읽지 않는다. A가 없으면 **cache miss**가 발생하고, loader가 원본 저장소에서 A를 조회해 캐시에 넣는 **load**를 수행한 뒤 값을 반환한다.

- hit: 캐시에서 값을 찾음 → 원본 저장소 조회 없음
- miss: 캐시에 값이 없음 → loader 실행 필요
- load: loader가 원본 저장소에서 값을 가져와 캐시를 채움
- put: load한 값을 캐시에 저장한 횟수로 해석할 수 있는 메트릭

`maximumSize=500`은 최대 500개 키를 캐시에 유지한다는 뜻이다. `expireAfterWrite=10m`은 저장 또는 갱신된 뒤 10분이 지난 항목을 만료시키는 TTL 정책이다. 단, TTL이 지난 값을 반드시 정확히 10분 정각에 물리적으로 즉시 삭제한다는 뜻은 아니다. Caffeine은 읽기·쓰기·정리 작업 중 만료 항목을 제거할 수 있으므로, TTL은 값의 유효성 정책으로 이해하는 편이 정확하다.

워밍업에서 대상 키 100개를 모두 한 번 load한 뒤 본 측정을 수행했다면, 본 측정의 `hit delta`가 전체 요청 수와 같고 `miss delta=0`, `put delta=0`인 결과가 가능하다. 이는 본 측정 동안 원본 저장소 재조회 없이 warm cache를 사용했다는 인과 근거다.

> **면접 예상 질문:** `LoadingCache`에서 hit, miss, load의 실행 순서를 설명하고, `hit delta`만 증가하고 miss·put delta가 0인 측정 결과를 어떻게 해석하겠습니까?

---

### stale data와 무효화 — TTL만으로 충분하지 않은 이유

캐시는 hit 시 원본 저장소를 조회하지 않으므로, 원본 데이터 A가 바뀌어도 캐시에 이전 A가 남아 있을 수 있다. 이 상태가 **stale data**다. 캐시를 사용하는 서로 다른 요청이 갱신 전후의 값을 읽으면, 데이터 일관성이 깨질 수 있다.

기본 대응은 원본 데이터 변경이 성공한 뒤 해당 키를 `invalidate(A)`로 무효화하는 것이다. 다음 A 조회는 miss가 되고 최신 원본 값으로 load된다. TTL은 무효화 호출이 누락됐을 때 stale 상태를 유한하게 만드는 안전망이지만, TTL이 남아 있는 동안의 오래된 값을 막지는 못한다.

무효화 이벤트는 원본 데이터 트랜잭션이 실제로 커밋된 뒤에 발행해야 한다. 커밋 전에 캐시를 비우면 롤백된 변경 때문에 캐시만 불필요하게 비워져 원본 저장소 I/O가 늘어난다. 더 위험하게는 다른 요청이 아직 커밋되지 않은 이전 값을 다시 load해 캐싱한 후 원래 트랜잭션이 커밋되어, 새 stale window가 생길 수 있다. 따라서 `AFTER_COMMIT` 시점의 무효화가 정합성 측면에서 자연스럽다.

로컬 Caffeine은 인스턴스별 JVM heap에 따로 존재한다. 다중 인스턴스 환경에서 한 인스턴스만 A를 무효화하면 다른 인스턴스는 TTL이 끝날 때까지 이전 A를 제공할 수 있다. 변경 이벤트를 발행하고 모든 인스턴스가 이를 구독해 각자의 A를 무효화하거나, 변경 빈도·운영 비용·지연 목표를 고려해 Redis 같은 분산 캐시를 선택한다.

> **면접 예상 질문:** 로컬 캐시에서 stale data가 생기는 이유와 TTL·키 기반 무효화를 함께 사용하는 이유를 설명하고, 다중 인스턴스 환경에서는 어떤 방식으로 무효화 범위를 확장하겠습니까?

---

### maximumSize와 W-TinyLFU — 검증 범위를 구분하기

Caffeine의 `maximumSize`는 캐시가 보관할 수 있는 키 수의 상한이다. 캐시 용량이 압박을 받으면 W-TinyLFU는 새 후보와 Probation의 제거 후보(victim)의 접근 빈도를 Frequency Sketch로 비교해, 더 자주 사용될 가능성이 큰 항목을 남긴다. 새 후보의 빈도가 낮으면 새 후보를 거절하고 기존 victim을 보존할 수 있다.

하지만 `maximumSize=500`인데 부하 대상 키가 100개뿐이면, 캐시가 포화되지 않는다. 이때 hit ratio가 100%라는 사실은 warm-cache 조회 효과의 근거가 되지만, W-TinyLFU의 admission·eviction 품질까지 검증한 결과는 아니다. eviction을 검증하려면 용량보다 큰 키 집합, 인기 편향, 장기 실행, eviction 메트릭을 포함해야 한다.

> **면접 예상 질문:** 100개 키만 요청한 실험에서 `maximumSize=500` 캐시의 hit ratio가 100%였습니다. 이 결과로 증명할 수 있는 것과 W-TinyLFU 관점에서 증명할 수 없는 것을 구분해 설명해 보세요.

---

### k6 지표 — VU, RPS, percentile, checks를 함께 해석하기

k6의 **VU(Virtual User)** 는 테스트 스크립트를 독립적으로 반복 실행하는 가상 사용자다. 같은 100 VU에서도 API 응답이 빨라지면 각 VU가 다음 반복을 더 빨리 시작할 수 있으므로 **RPS(Requests Per Second)** 가 증가할 수 있다. 따라서 캐시 적용 전후에는 RPS와 응답 시간을 함께 봐야 한다.

`p95=110ms`는 요청의 95%가 110ms 이하로 처리됐다는 뜻이지 평균이 110ms라는 뜻이 아니다. 평균은 일부 매우 느린 요청을 감출 수 있으므로 p95와 p99를 함께 확인한다. p99가 높으면 적은 비율의 사용자에게 긴 대기 경험이 발생하거나, 간헐적 병목·GC·DB 지연 같은 꼬리 지연이 있다는 신호일 수 있다.

성능 수치만으로 정상 동작을 단정해서는 안 된다.

| 지표 | 확인하는 대상 | 예시 해석 |
|---|---|---|
| `http_req_failed` | k6가 판단한 HTTP 요청 실패 | 0%면 HTTP 요청 실패가 없었음 |
| `checks_failed` | 테스트 작성자가 `check()`에 정의한 기대값 실패 | 0%면 상태 코드·응답 본문 등 정의한 검증이 모두 통과 |
| `checks_total` | 실행된 check의 총 횟수 | 요청 1건에 check 2개면 요청 수의 약 2배가 될 수 있음 |

예를 들어 한 요청마다 `status is 200`, `response field is expected value` 두 개의 `check()`를 실행하면, HTTP 200이면서도 응답 본문 값이 기대와 다른 오류를 `checks_failed`로 잡을 수 있다. 그러므로 `http_req_failed=0%`와 `checks_failed=0%`를 함께 확인해야, 빠른 응답이면서 테스트가 정의한 정상 응답도 유지됐다고 해석할 수 있다.

> **면접 예상 질문:** k6에서 100 VU 부하 후 RPS는 증가했지만 p99가 악화됐습니다. `http_req_duration`, `http_req_failed`, `checks_failed`를 어떻게 조합해 원인을 좁히고 결과를 설명하겠습니까?

---

### 캐시 성능 결과를 주장하는 근거와 한계

캐시 효과는 단순히 “after가 before보다 빨랐다”로 주장하지 않는다. k6의 p95·RPS 변화와 함께 캐시 hit/miss/put delta, 원본 저장소 조회 수, HTTP 실패율과 check 실패율을 교차 확인한다. 이 조합은 캐시 hit이 원본 저장소 조회 제거로 이어졌고 그 상태에서 성능 결과가 나왔다는 설명력을 높인다.

다만 warm-cache 실험은 첫 miss 지연, TTL 만료, 캐시 포화와 eviction을 검증하지 않는다. 단일 호스트에서 앱·k6·DB를 함께 실행하면 OS 부하, JVM JIT, DB 버퍼가 run 순서에 따라 달라질 수 있다. 따라서 조건별 여러 run을 섞어 실행하고 중앙값·평균·표준편차를 제시하며, 단일 최고 수치가 아니라 재현 가능한 대표값을 이력서와 면접 답변에 사용한다.

> **면접 예상 질문:** Caffeine 적용 후 p95와 RPS가 개선됐다는 결과가 있습니다. 캐시가 실제 원인이라고 주장하기 위해 추가로 확인할 지표와, 이 실험 결과를 일반화할 수 없는 한계를 설명해 보세요.

---

## 학습 정리

- `LoadingCache`는 miss 시 loader가 원본 저장소에서 값을 읽어 캐시를 채우며, 이후 hit은 원본 저장소 접근을 제거한다.
- stale data는 쓰기 성공 후 키 기반 무효화로 줄이고, TTL은 무효화 누락에 대비하는 안전망으로 둔다.
- 다중 인스턴스에서는 변경 이벤트를 모든 인스턴스에 전파해 각 로컬 캐시를 무효화하거나 분산 캐시를 검토한다.
- 100개 키와 `maximumSize=500`의 warm-cache 실험은 hit 효과는 보이지만 W-TinyLFU eviction은 검증하지 못한다.
- k6에서는 VU·RPS·p95/p99와 함께 `http_req_failed`, `checks_failed`를 확인해 성능과 응답 정상성을 함께 검증한다.

## 참고

- [Caffeine 캐시 적용과 stale data 전략](../java/Caffeine%20캐시%20적용과%20stale%20data%20전략%20-%20evict%2C%20CacheEvict%20AOP%2C%20Component%20vs%20Configuration%2C%20캐시%20단위.md)
- [Caffeine W-TinyLFU 내부 구조](../java/Caffeine%20W-TinyLFU%20내부%20구조%20-%20Window%2C%20Probation%2C%20Protected%2C%20Frequency%20Sketch.md)
