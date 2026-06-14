# Caffeine 캐시 적용과 stale data 전략 — evict, @CacheEvict AOP, @Component vs @Configuration, 캐시 단위

> 날짜: 2026-06-14

## 내용

대출 한도 계산 서비스에서 상품 조회를 DB 직접 조회 → Caffeine 로컬 캐시로 바꾸면서, 코드 변화 너머의 "행동 변화"와 그에 따른 설계 결정을 정리한다.

```java
// 이전: 매 호출마다 DB 직접 조회
LoanProduct product = productMapper.findById(productId)
        .orElseThrow(() -> new IllegalArgumentException("Product not found: " + productId));

// 이후: 로컬 캐시 경유
LoanProduct product = loanProductCache.get(productId);
```

---

### 코드 변화 vs 행동 변화 — 한 줄 교체가 만든 차이

텍스트상 바뀐 건 `mapper.findById(...).orElseThrow(...)` → `cache.get(productId)` **한 줄**뿐이다. 하지만 **실행 시 행동**은 달라진다.

- **이전**: `calculate` 호출마다 **항상 DB 1회 접근**
- **이후**: 같은 `productId` 재호출 시
  - 캐시 히트 → **DB 접근 안 함**
  - 캐시 미스 → DB 1회 접근 후 캐시에 채움

즉 같은 코드 모양이라도, 캐시 도입은 "DB를 매번 안 본다"는 행동 변화를 만든다. 코드 diff만 보면 놓치기 쉬운 부분.

> **면접 예상 질문:** 메서드 한 줄을 캐시 조회로 바꿨을 때 코드상 변화는 작지만 런타임 동작은 어떻게 달라지며, 이때 새로 고려해야 할 문제는 무엇인가?

---

### stale data — DB는 바뀌었는데 캐시는 옛날 값

캐시 히트 시 DB를 안 보기 때문에, **DB의 상품 정보가 수정되면 DB와 캐시 내용이 어긋난다.** 캐시가 옛날 값을 들고 있는 이 상태를 **stale data(오래된 데이터)** 라고 부른다. (`detach`는 영속성 컨텍스트에서 엔티티를 떼어내는 별개 개념 — 헷갈리지 말 것.)

해결의 핵심은 캐시를 비우는 것. `LoanProductCache`에 이미 메서드가 있다.

```java
public void evict(Long productId) {
    cache.invalidate(productId);   // 해당 키만 캐시에서 비움
}
public void evictAll() {
    cache.invalidateAll();         // 전체 비움
}
```

`invalidate`로 비우면 → 다음 `get(productId)`는 캐시 미스 → `loadFromDb`로 최신값 재로딩 → stale 해소. **상품을 수정·저장하는 로직이 성공한 직후 `evict(productId)`를 호출**하면 된다. 이 패턴을 "쓰기 시 무효화(cache eviction on update)"라 한다.

> **면접 예상 질문:** 로컬 캐시 도입 후 DB와 캐시가 어긋나는 stale data 문제는 왜 생기며, 어느 시점에 무엇을 호출해 해결하는가?

---

### evict + TTL — 정확성과 안전망의 조합

캐시 빌더의 `expireAfterWrite(Duration.ofMinutes(10))`는 stale의 **안전망**이다. `evict()` 호출을 깜빡해도 최대 10분 뒤엔 자동 만료되어 stale이 풀린다. 하지만 TTL만 믿으면 안 되는 이유:

- **그 10분 사이에 DB가 수정되면**, 최대 10분 동안 고객에게 옛날 한도/요율이 나갈 수 있다. 대출 한도처럼 **돈이 걸린 도메인**에서 10분 stale은 위험하다.

그래서 두 개를 같이 쓴다:
- **수정 즉시 `evict()`** — 정확하지만 호출을 챙겨야 함
- **`expireAfterWrite` TTL** — 깜빡해도 막아주는 최후 보루

TTL 길이 자체가 trade-off다. 짧게 → stale 위험 ↓, 히트율 ↓(DB 부하 ↑). 길게 → 히트율 ↑, stale 위험 ↑.

> **면접 예상 질문:** `evict()`를 호출하는데도 `expireAfterWrite` TTL을 함께 두는 이유는 무엇이며, TTL을 짧게/길게 잡을 때의 trade-off는?

---

### @CacheEvict AOP — evict 호출을 선언적으로

매 수정 로직마다 `evict()`를 손으로 넣으면 빠뜨리기 쉽고 중복된다. 더 객체지향다운 방법은 **AOP**다. `@Transactional`이 트랜잭션 코드를 메서드마다 안 쓰고 어노테이션 하나로 처리하듯, 캐시 비우기도 선언적으로 할 수 있다.

```java
@CacheEvict(value = "loan_product", key = "#productId")
public void updateProduct(Long productId, ...) {
    // DB 수정 로직만. 캐시 비우기는 AOP가 처리
}
```

비즈니스 로직과 캐시 관리가 분리되어, 빠뜨림·중복이 준다. (단, `@Cacheable`/`@CacheEvict`를 쓰려면 `@EnableCaching` + `CacheManager`로 Caffeine을 스프링 캐시 추상화에 연결해야 한다. 지금처럼 `LoadingCache`를 직접 다루면 수동 `evict()`다.)

> **면접 예상 질문:** 수정 로직마다 `evict()`를 호출하는 방식의 단점은 무엇이고, `@CacheEvict`(AOP)는 어떤 기술로 이를 개선하는가?

---

### (A) 직접 제어 vs (B) 스프링 캐시 추상화 — trade-off

캐시를 다루는 두 갈래가 있고, 이건 **택1(갈림길)** 이다.

| | (A) 직접 방식 | (B) 추상화 방식 |
|---|---|---|
| 구현 | `@Component LoanProductCache` + `cache.get()`/`evict()` 수동 | `@Configuration`+`@Bean CacheManager` + `@Cacheable`/`@CacheEvict` |
| 장점 | `maximumSize`/`expireAfterWrite` 직접 통제, `recordStats`+`CaffeineCacheMetrics`로 이 캐시만 메트릭, 로딩/무효화 로직 결합 | 어노테이션으로 간결, 캐시 여러 개를 매니저 하나로 이름표 관리 |
| 적합 | 정밀 튜닝·모니터링이 중요한 **핵심 캐시** | 단순 캐시가 다수일 때 |

**같은 데이터를 (A)와 (B)로 동시에 캐싱하면 안 된다** — 캐시가 두 군데 생겨 한쪽만 evict되면 **데이터 정합성이 깨진다(stale 2배)**. 한 데이터엔 캐시 하나가 원칙.

> **헷갈렸던 포인트:** "(A) 클래스를 그대로 두고 (B) CacheManager를 얹는다"가 아니다. `@Configuration+@Bean CacheManager`는 **(B)로 갈아탈 때** 쓰는 것. (B)로 가면 별도 `LoanProductCache` 클래스는 불필요(`@Cacheable`이 대신함).

> **면접 예상 질문:** Caffeine을 직접 들고 쓰는 방식과 스프링 캐시 추상화(`@Cacheable`) 방식의 trade-off는 무엇이며, 같은 데이터를 두 방식으로 동시에 캐싱하면 왜 위험한가?

---

### @Component vs @Configuration — 빈 등록 기준

`CacheManager`(정확히는 `CaffeineCacheManager`)를 빈으로 만들 때 왜 `@Component`가 아니라 `@Configuration`+`@Bean`인가?

- **`@Component`** → **내가 만든 클래스**에 붙여 "이 클래스를 빈으로 등록". `LoanProductCache`는 내 클래스라 가능.
- **`@Configuration` + `@Bean`** → **남이 만든 라이브러리 클래스**(`CaffeineCacheManager`)는 그 위에 내가 어노테이션을 못 붙인다. 그래서 `@Bean` 메서드 안에서 직접 `new` 해 설정을 주입하고 반환해 등록한다.

```java
@Configuration
public class CacheConfig {
    @Bean
    public CacheManager cacheManager() {
        // CaffeineCacheManager를 new 하고 maximumSize/expireAfterWrite 주입 후 반환
    }
}
```

**기준 한 문장**: 내가 만든 클래스면 `@Component`, 남이 만든 라이브러리 객체를 내가 설정·커스텀해서 등록하면 `@Configuration`+`@Bean`.

> **면접 예상 질문:** 라이브러리가 제공하는 클래스(예: `CaffeineCacheManager`)를 빈으로 등록할 때 `@Component`를 못 쓰고 `@Configuration`+`@Bean`을 쓰는 이유는?

---

### 캐시 단위 — 테이블이 아니라 "용도"

캐시는 **DB 테이블 하나당 하나**가 아니다. 기준은 테이블이 아니라 **"캐싱하고 싶은 데이터 묶음(용도)"**. `LoanProductCache`는 "loan_product 테이블이라서"가 아니라 **"자주 조회되는데 잘 안 바뀌는 대출 상품 데이터"** 라서 캐싱한다. 자주 바뀌거나 거의 안 읽는 데이터는 캐싱 대상이 아니다.

캐시가 여러 개로 늘 때:
- **(A)** 데이터 종류마다 `@Component` 캐시 클래스 하나씩 → 개수 늘면 관리 부담 ↑
- **(B)** 매니저 하나가 이름표로 여러 캐시 관리 → **다수일 때 더 편함**

그럼 (A) 별도 클래스는 언제? → **이 캐시 하나가 시스템에 민감/핵심**이라 히트율을 따로 모니터링하고 stale을 정밀 통제해야 할 때. 평범한 데이터에 (A)를 쓰면 **오버 엔지니어링**이지만, 대출 한도처럼 **돈 걸린 핵심 도메인**에 쓰면 **필요한 만큼 투자한 합당한 선택**이다. 즉 "오버 엔지니어링이냐"는 **대상의 중요도**가 가른다.

> **면접 예상 질문:** 캐시는 테이블 단위로 만드는가? 핵심 도메인에 전용 캐시 클래스를 두는 것이 오버 엔지니어링인지 합당한 선택인지는 무엇으로 판단하는가?

---

## 학습 정리

- 캐시 도입은 코드상 한 줄 변화지만, "히트 시 DB 미접근"이라는 행동 변화 → **stale data** 문제를 새로 부른다.
- stale 해결은 수정 성공 직후 `evict()`(쓰기 시 무효화) + `expireAfterWrite` TTL(안전망)의 조합. 돈 걸린 도메인에선 TTL만 믿으면 위험.
- `evict()` 산재의 번거로움은 **AOP** `@CacheEvict`로 선언적 처리(`@Transactional`과 같은 원리).
- (A) Caffeine 직접 제어 vs (B) 스프링 캐시 추상화는 택1. 같은 데이터를 둘 다 캐싱하면 정합성이 깨진다.
- 라이브러리 객체(`CacheManager`) 등록은 `@Component` 불가 → `@Configuration`+`@Bean`. 기준: 내 클래스=@Component, 남의 객체 커스텀=@Configuration.
- 캐시 단위는 테이블이 아니라 용도. 전용 클래스(A)는 핵심/민감 도메인일 때 합당, 평범한 데이터엔 오버 엔지니어링.

## 참고

- (이전 TIL) monitoring/Caffeine 캐시 모니터링과 튜닝 - @Component, LoadingCache, recordStats, MeterRegistry, eviction cause.md
- (이전 TIL) java/OOM 진단과 메모리 누수 해결 - GC Roots, 참조, Caffeine.md
