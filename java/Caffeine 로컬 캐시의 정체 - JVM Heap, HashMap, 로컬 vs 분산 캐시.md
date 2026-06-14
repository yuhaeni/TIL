# Caffeine 로컬 캐시의 정체 — JVM Heap, HashMap, 로컬 vs 분산 캐시

> 날짜: 2026-06-14

## 내용

"Caffeine 캐시가 정확히 뭐냐"가 감이 안 잡힐 때, 이미 아는 자료구조(HashMap)와 JVM 메모리 구조에서 출발해 정체를 그려본다.

---

### Caffeine = JVM Heap 위에 사는 똑똑한 HashMap

캐시를 쓸 때 `cache.get(productId)`, `cache.invalidate(productId)`처럼 **키(productId)로 값(LoanProduct)을 넣고 꺼낸다.** 타입도 `LoadingCache<Long, LoanProduct>` — 즉 본질은 우리가 자바에서 수없이 써본 **`Map<Long, LoanProduct>`** 다.

Caffeine은 그 Map에 평범한 HashMap엔 없는 "똑똑함"을 더한 것:

| 기능 | Caffeine | 일반 HashMap |
|---|---|---|
| `maximumSize(500)` | 꽉 차면 알아서 비움(eviction) | 끝없이 커짐 |
| `expireAfterWrite(10분)` | 시간 지나면 자동 만료 | 영원히 보관 |
| `recordStats()` | 히트/미스 통계 집계 | 못 셈 |
| `build(this::loadFromDb)` | 없으면 DB에서 자동 로딩 | 직접 채워야 함 |

> 한 문장: **Caffeine = JVM Heap에 올라간 자바 객체(거대한 Map)** 인데, 만료·용량 제한·통계·자동 로딩이 붙은 버전.

> **면접 예상 질문:** Caffeine 캐시는 자료구조 관점에서 무엇과 가장 비슷하며, 일반 HashMap과 무엇이 다른가?

---

### 왜 "로컬" 캐시인가 — JVM Heap에 산다

`new`로 만든 자바 객체는 **JVM 메모리의 Heap 영역**에 올라간다. Caffeine 캐시도 결국 Heap에 올라간 Map 객체다. 그래서 `cache.get(productId)`는 — **네트워크도, 디스크도 안 거치고** Heap에 있는 Map에서 키로 값을 참조해 바로 꺼낸다. 같은 JVM(프로세스) 안에 있어서 **로컬(local)** 캐시라 부른다.

캐시를 도입한 이유와 연결된다: **DB·Redis 같은 외부 I/O를 줄이려고.** 외부 저장소는 네트워크/디스크를 거쳐 느리지만, 로컬 캐시는 같은 프로세스 메모리라 가장 빠르다.

속도: **로컬 캐시(Caffeine) > Redis > DB**

| | 위치 | I/O | 속도 |
|---|---|---|---|
| Caffeine | 내 JVM Heap | 없음(메모리 참조) | 가장 빠름 |
| Redis | 별도 서버 | 네트워크 | 중간 |
| DB | 별도 서버 + 디스크 | 네트워크 + 디스크 | 가장 느림 |

> **면접 예상 질문:** 로컬 캐시가 빠른 이유를 JVM 메모리 구조로 설명하고, Caffeine·Redis·DB의 접근 속도 차이는 왜 생기는가?

---

### Heap 공유 범위 — 스레드 간 O, 프로세스/서버 간 X

여기서 헷갈리기 쉬운 포인트. "Heap은 공유 영역"이라는 말은 **하나의 JVM 프로세스 안에서 여러 스레드끼리** 공유한다는 뜻이다(Stack은 스레드마다, Heap은 스레드끼리 공유).

하지만 **서버를 2대로 늘리면 JVM 프로세스가 2개**가 뜬다. 1번 서버 JVM과 2번 서버 JVM은 서로 다른 프로세스라 **각자 자기만의 Heap**을 갖는다. → 한 서버의 Caffeine 캐시를 다른 서버가 공유받을 수 없다.

> 비유: 두 사람이 각자 자기 수첩(Heap)에 메모(캐시)를 적으면, A의 수첩 메모를 B는 볼 수 없다.

결과적으로:
- 1번 서버가 `productId=5`를 캐싱해도 2번 서버는 그 캐시를 공유받지 못한다.
- 1번 서버에서만 `evict`하면 **2번 서버는 갱신 안 된 stale 캐시**를 그대로 들고 있다. → 로컬 캐시의 한계(서버 간 정합성).

> **면접 예상 질문:** "Heap은 공유된다"는 말은 어떤 범위에서 참인가? 스케일 아웃(서버 2대 이상) 환경에서 로컬 캐시는 어떤 정합성 문제를 일으키는가?

---

### 로컬 vs 분산 캐시 — Caffeine은 왜 Redis가 필요할까

로컬 캐시는 서버마다 따로라 공유가 안 된다. 여러 서버가 **같은 캐시를 공유**하려면, 각자의 Heap이 아니라 **가운데에 공용 저장소(Redis)** 를 둬야 한다. 그래서 Redis를 **분산 캐시(distributed cache)** 라 부른다.

| | Caffeine (로컬) | Redis (분산) | DB |
|---|---|---|---|
| 위치 | 내 JVM Heap | 별도 서버 | 별도 서버 + 디스크 |
| 속도 | 가장 빠름 | 중간(네트워크) | 가장 느림 |
| 서버 간 공유 | ❌ 서버마다 따로 | ✅ 모든 서버 공유 | ✅ |
| 한계 | 서버 간 stale | 네트워크 의존 | I/O 비용 |

Redis는 네트워크를 한 번 건너야 해서 Caffeine보단 느리지만, **모든 서버가 같은 값을 본다**는 게 핵심 장점. 그래서 실무에선 **Caffeine(빠름) + Redis(공유)를 2단으로** 쓰기도 한다(2-Level Cache): 1차로 로컬에서 찾고, 없으면 Redis, 그래도 없으면 DB.

> **면접 예상 질문:** Caffeine이 Redis보다 빠른데도 분산 캐시(Redis)를 함께 쓰는 이유는 무엇이며, 2-Level Cache는 어떤 구조로 동작하는가?

---

## 학습 정리

- Caffeine 캐시의 본질은 **JVM Heap 위의 `Map<K,V>`** 에 만료·용량 제한·통계·자동 로딩을 더한 것.
- `new` 객체가 Heap에 올라가듯 캐시도 Heap에 있어, 네트워크/디스크 없이 메모리 참조로 바로 꺼내므로 빠르다 → "로컬" 캐시.
- 속도는 로컬(Caffeine) > Redis > DB. 캐시 도입 목적은 외부 I/O 절감.
- Heap 공유는 "한 JVM 안 스레드끼리"만. 서버 2대면 JVM 2개라 각자 Heap → 로컬 캐시는 서버 간 공유 불가, evict도 서버별로 따로 → stale.
- 서버 간 공유가 필요하면 가운데에 Redis(분산 캐시). 실무에선 Caffeine + Redis 2-Level로 속도와 공유를 같이 챙긴다.

## 참고

- (이전 TIL) java/Caffeine 캐시 적용과 stale data 전략 - evict, CacheEvict AOP, Component vs Configuration, 캐시 단위.md
- (이전 TIL) monitoring/Caffeine 캐시 모니터링과 튜닝 - @Component, LoadingCache, recordStats, MeterRegistry, eviction cause.md
- (이전 TIL) redis/Redis 분산 락과 교착 상태.md
