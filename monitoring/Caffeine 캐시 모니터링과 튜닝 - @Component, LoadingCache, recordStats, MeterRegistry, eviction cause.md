# Caffeine 캐시 모니터링과 튜닝 — @Component, LoadingCache, recordStats, MeterRegistry, eviction cause

> 날짜: 2026-06-13

## 내용

아래 `LoanProductCache` 코드 한 개를 뜯어보며, 빈 어노테이션 선택부터 캐시 메트릭 모니터링·튜닝까지 흐름을 정리한다.

```java
@Component
public class LoanProductCache {

    private final LoanProductMapper mapper;
    private final LoadingCache<Long, LoanProduct> cache;

    public LoanProductCache(LoanProductMapper mapper, MeterRegistry meterRegistry) {
        this.mapper = mapper;
        this.cache = Caffeine.newBuilder()
                .maximumSize(500)
                .expireAfterWrite(Duration.ofMinutes(10))
                .recordStats()
                .build(this::loadFromDb);
        CaffeineCacheMetrics.monitor(meterRegistry, cache, "loan_product");
    }

    public LoanProduct get(Long productId) {
        return cache.get(productId);
    }

    public void evict(Long productId) {
        cache.invalidate(productId);
    }

    public void evictAll() {
        cache.invalidateAll();
    }

    private LoanProduct loadFromDb(Long productId) {
        return mapper.findById(productId)
                .orElseThrow(() -> new IllegalArgumentException("Product not found: " + productId));
    }
}
```

---

### @Component 선택 근거 — 왜 @Service/@Repository가 아닌가

`@Component`가 붙으면 스프링이 이 객체를 **빈으로 등록해서 생성·관리(싱글턴)**한다. 싱글턴으로 관리하는 이유는 재사용성 — 이 객체 안의 `cache` 필드(500개 상품을 담는 상태)는 앱이 사는 동안 **하나만 존재하며 공유**되어야 의미가 있다. 요청마다 새로 만들어지면 어렵게 채운 캐시가 매번 비어버린다.

그런데 빈으로 등록되는 어노테이션은 여러 개다. 핵심은 **대부분이 내부적으로 `@Component`를 메타 어노테이션으로 품고 있어서, 빈 등록 효과는 똑같다**는 점. 차이는 "이름이 드러내는 역할(계층)"이다.

| 어노테이션 | 의미하는 계층 |
|---|---|
| `@Controller` | 웹 요청 처리 계층 |
| `@Service` | 비즈니스 로직 계층 |
| `@Repository` | 데이터 접근 계층 (+ DB 예외 → 스프링 예외 변환 부가 기능) |
| `@Configuration` | `@Bean` 메서드로 빈을 정의하는 설정 클래스 |
| `@Component` | 위 어디에도 딱 안 맞는 **범용 컴포넌트** |

`LoanProductCache`는 DB를 다녀오긴 하지만 직접 쿼리를 짜지 않고 `mapper`에 위임만 하며, 진짜 역할은 "캐싱"이다. 특정 계층 라벨을 붙이기 애매하다. 이럴 때 억지로 `@Service`를 붙이면 "비즈니스 로직 객체"라고 거짓말하는 셈 → **의미를 흐리지 않으려면 `@Component`가 가장 정직한 선택**이다.

> **면접 예상 질문:** `@Component`, `@Service`, `@Repository`는 빈 등록 효과가 동일한데도 구분해서 쓰는 이유는 무엇이며, 어떤 클래스에 `@Component`를 쓰는 것이 적절한가?

---

### LoadingCache 동작 — 캐시 미스 시 자동 로딩

`LoadingCache`는 `Loading` + `Cache`다. 일반 캐시는 `get(key)` 했을 때 값이 없으면 `null`을 돌려주지만, `LoadingCache`는 **값이 없으면 등록해 둔 로더(`loadFromDb`)를 자동 호출해 채운 뒤 리턴**한다.

- **캐시 히트** → 캐시에 있는 값을 그대로 리턴
- **캐시 미스** → `loadFromDb` 호출 → DB에서 직접 조회 → 캐시에 채우고 리턴

로더는 생성자의 `.build(this::loadFromDb)`로 연결된다.

```java
private LoanProduct loadFromDb(Long productId) {
    return mapper.findById(productId)
            .orElseThrow(() -> new IllegalArgumentException("Product not found: " + productId));
}
```

> 비유: 도서관에서 책이 서가에 없을 때 "없네요" 하고 끝내는 사서(일반 캐시)가 아니라, 창고에서 알아서 꺼내 꽂아주는 사서(LoadingCache).

> **면접 예상 질문:** 일반 캐시와 `LoadingCache`의 차이는 무엇이며, 캐시 미스가 발생했을 때 `LoadingCache`는 어떻게 동작하는가?

---

### recordStats + MeterRegistry + CaffeineCacheMetrics.monitor — 메트릭을 잇는 세 조각

캐시를 관찰 가능하게 만드는 건 세 조각의 조합이다.

1. **`.recordStats()`** — 캐시가 히트/미스/로딩 시간/eviction 같은 **통계를 세기 시작**한다. 이게 없으면 셀 게 없다.
2. **`MeterRegistry`** — 애플리케이션의 계량기(meter)들을 모아두는 **보관함**. 단순 보관을 넘어, 모아둔 값을 외부로 내보내는 출구 역할도 한다. 관리 포인트가 하나로 모인다.
3. **`CaffeineCacheMetrics.monitor(meterRegistry, cache, "loan_product")`** — 1번이 세고 있던 통계를 2번 보관함에 **계량기 형태로 등록해 주는 다리**. 세 번째 인자 `"loan_product"`는 계량기 이름에 붙는 **접두사/태그**라, 나중에 `loan_product`로 이 캐시 메트릭만 골라볼 수 있다.

> **면접 예상 질문:** Caffeine 캐시의 통계가 모니터링 도구에 노출되기까지 `recordStats()`, `MeterRegistry`, `CaffeineCacheMetrics.monitor()`는 각각 어떤 역할을 하는가?

---

### Prometheus → Grafana — 메트릭이 화면에 뜨기까지의 다리

`CaffeineCacheMetrics.monitor(...)` **한 줄만으로는 Grafana에 데이터가 뜨지 않는다.** 이 줄은 "보관함(MeterRegistry)에 계량기를 넣는 것"까지만 한다. 보관함과 Grafana 사이에 수집 도구가 더 필요하다.

```
캐시(recordStats)
  → CaffeineCacheMetrics.monitor (계량기로 등록)
  → MeterRegistry (보관함)
  → [Prometheus가 주기적으로 긁어감 scrape]
  → Grafana (화면에 시각화)
```

스프링 부트에서는 보통 다음이 더 필요하다:
- `micrometer-registry-prometheus` 의존성 추가 → `MeterRegistry`의 실제 구현체가 `PrometheusMeterRegistry`가 되도록
- `/actuator/prometheus` 엔드포인트 노출 → Prometheus가 이 주소를 긁어(scrape) 저장 → Grafana가 조회

> **헷갈렸던 포인트:** `monitor(...)` 한 줄이 곧바로 Grafana로 전송하는 게 아니다. 등록은 "보관함에 넣기"까지고, 수집·저장은 Prometheus, 시각화는 Grafana가 담당한다.

> **면접 예상 질문:** Micrometer로 등록한 메트릭이 Grafana 대시보드에 나타나기까지의 경로를 설명하고, `CaffeineCacheMetrics.monitor()` 호출만으로 부족한 이유는 무엇인가?

---

### eviction cause 기반 튜닝 — 추측이 아니라 지표로 진단

캐시 히트율이 낮다 = 자주 조회되는 데이터가 캐시에 안 남아 있다는 뜻. 데이터가 쫓겨나는(evict) 원인은 빌더의 두 줄과 관련 있다.

```java
.maximumSize(500)                         // 그릇 크기
.expireAfterWrite(Duration.ofMinutes(10)) // 데이터 수명(TTL)
```

문제는 **"크기가 작아서 생긴 미스"인지 "너무 빨리 만료돼서 생긴 미스"인지 어떻게 구분하느냐**다. → `recordStats()`는 eviction을 셀 때 **원인(cause)까지** 카운트한다. 메트릭 `cache_evictions_total`에는 `cause` 라벨이 붙는다.

| 관측 지표 | 진단 | 조치 |
|---|---|---|
| `cache_evictions_total{cause="SIZE"}` ↑ | 그릇이 꽉 차서 쫓겨남 | `.maximumSize(...)` 키우기 |
| `cache_evictions_total{cause="EXPIRED"}` ↑ | 수명이 짧아 만료됨 | `.expireAfterWrite(...)` 늘리기 |

> 핵심: "캐시 히트율이 낮으면 어떻게 하느냐"에 대한 좋은 답은 *"먼저 eviction cause를 측정하고, SIZE면 용량을, EXPIRED면 TTL을 조정한다"* — 추측이 아니라 측정 기반 튜닝.

> **면접 예상 질문:** 캐시 히트율이 낮을 때, `maximumSize`를 키워야 할 상황과 `expireAfterWrite`를 늘려야 할 상황을 어떤 지표로 구분해 판단하겠는가?

---

## 학습 정리

- `@Component`/`@Service`/`@Repository`는 대부분 메타 어노테이션으로 `@Component`를 품어 빈 등록 효과가 같다. 차이는 "계층 의미" — 어느 계층에도 안 맞는 범용 컴포넌트엔 `@Component`가 가장 정직하다.
- `LoadingCache`는 캐시 미스 시 등록된 로더(`loadFromDb`)를 자동 호출해 DB에서 채운 뒤 리턴한다.
- 캐시 관찰은 세 조각의 조합: `recordStats()`(통계 수집) + `MeterRegistry`(보관·출구) + `CaffeineCacheMetrics.monitor()`(둘을 잇는 다리).
- `monitor()` 한 줄은 "보관함에 등록"까지만. Grafana에 뜨려면 Prometheus가 `/actuator/prometheus`를 scrape하고 Grafana가 조회하는 다리가 필요하다.
- 캐시 튜닝은 추측이 아니라 `cache_evictions_total`의 `cause` 라벨(SIZE/EXPIRED)을 보고 `maximumSize`/`expireAfterWrite` 중 무엇을 조정할지 진단한다.

## 참고

- (이전 TIL) monitoring/Spring Batch 성능 측정 PromQL과 Grafana.md
- (이전 TIL) java/OOM 진단과 메모리 누수 해결 - GC Roots, 참조, Caffeine.md
