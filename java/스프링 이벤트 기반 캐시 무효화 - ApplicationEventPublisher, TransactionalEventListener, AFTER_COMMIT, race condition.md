# 스프링 이벤트 기반 캐시 무효화 — ApplicationEventPublisher, @TransactionalEventListener, AFTER_COMMIT, race condition

> 날짜: 2026-06-15

## 내용

상품 수정·삭제 시 Caffeine 로컬 캐시를 비우는(evict) 로직을, 서비스에 직접 박지 않고 **스프링 이벤트**로 분리한 설계를 뜯어본다.

```java
@Slf4j @Service @Transactional @RequiredArgsConstructor
public class LoanProductService {
    private final LoanProductMapper productMapper;
    private final LoanProductTargetMallMapper targetMallMapper;
    private final ApplicationEventPublisher events;

    public LoanProduct update(Long productId, LoanProductUpdateRequest req) {
        if (productMapper.update(req.toEntity(productId)) == 0)
            throw new IllegalArgumentException("Product not found: " + productId);
        targetMallMapper.deleteAllByProductId(productId);
        if (!req.getTargetMallCodes().isEmpty()) {
            targetMallMapper.bulkInsert(productId, req.getTargetMallCodes());
        }
        events.publishEvent(new ProductChangedEvent(productId));  // 캐시 비우라고 "방송"
        return productMapper.findById(productId).orElseThrow(...);
    }
    // create 는 evict 불필요 (캐시에 아직 없는 새 id)
}
```

---

### bulkInsert와 @Mapper — MyBatis (JPA 아님)

`bulkInsert`는 `bulk`(대량) + `insert`. `List<String> mallCodes`처럼 여러 값을 받아 **여러 행을 한 번의 INSERT로 묶어** 날린다. 10건을 INSERT 10번이 아니라 1번으로 처리 → **네트워크 왕복(I/O) 절감**.

주의: 이건 **Spring Data JPA가 아니라 MyBatis**다. 인터페이스에 `@Repository`가 아니라 `@Mapper`가 붙고, 이름도 `...Mapper`다. JPA처럼 메서드 이름을 파싱해 쿼리를 자동 생성하는 게 아니라, **XML/어노테이션에 SQL을 직접 작성**한다(보통 `<foreach>`로 값들을 한 INSERT에 묶음). 그래서 `bulkInsert`의 동작은 메서드 이름이 아니라 **그 SQL이 결정**한다.

```java
@Mapper
public interface LoanProductTargetMallMapper {
    int deleteAllByProductId(@Param("productId") Long productId);
    void bulkInsert(@Param("productId") Long productId,
                    @Param("mallCodes") List<String> mallCodes);
}
```

> **헷갈렸던 포인트:** `bulkInsert`는 메서드명만으로 자동 bulk가 되는 게 아니다. `@Mapper`/`Mapper` 네이밍은 MyBatis 신호 — JPA와 혼동 주의.

> **면접 예상 질문:** bulk insert가 단건 insert 반복보다 효율적인 이유는 무엇이며, MyBatis와 Spring Data JPA에서 이런 쿼리가 만들어지는 방식은 어떻게 다른가?

---

### ApplicationEventPublisher & 이벤트 record — 스프링 내장 Pub-Sub

`ApplicationEventPublisher`는 스프링이 제공하는 **이벤트 발행 창구**다. `publishEvent(...)`를 호출하면 "이런 일이 일어났다!"고 **방송**하고, 그 이벤트를 구독(`@EventListener` / `@TransactionalEventListener`)하는 쪽이 받아서 처리한다. Kafka의 **Pub-Sub(발행-구독)** 과 같은 구조인데, **같은 JVM 프로세스 안에서** 동작하는 가벼운 버전이다.

`ProductChangedEvent`는 그 방송에 실리는 **메신저(편지)** 다. `productId` 하나를 담아 "어떤 상품이 바뀌었는지"를 구독자에게 전달한다.

```java
public record ProductChangedEvent(Long productId) {}
```

> **면접 예상 질문:** `ApplicationEventPublisher` 기반 스프링 이벤트와 Kafka의 Pub-Sub은 무엇이 같고 무엇이 다른가? (프로세스 경계, 영속성, 장애 복구 관점)

---

### 이벤트 기반 설계 = 낮은 결합도 — 왜 객체지향적인가

이벤트를 안 쓰면, `update()` 안에서 `LoanProductService`가 `loanProductCache.evict(...)`를 **직접 호출**해야 한다. 그러면 서비스는 "상품 저장"뿐 아니라 "캐시 비우기"라는 일까지 **알고 직접 의존**하게 된다.

이벤트로 분리하면:
- `LoanProductService`는 자기 책임(상품 저장/수정/삭제)만 하고, "캐시 비워라"고 **방송만** 던진다.
- 실제 evict는 구독자 `ProductCacheEvictor`가 처리한다.
- 서비스는 **캐시의 존재 자체를 몰라도 된다** → 직접 의존이 사라져 **결합도가 낮아짐**.

이는 객체지향의 **단일 책임 원칙(SRP)** 과 **느슨한 결합(loose coupling)** 에 부합한다. 캐시 무효화 방식이 바뀌어도(또는 캐시를 걷어내도) 서비스 코드는 그대로 → 변경 파급이 작다.

```java
@Slf4j @Component @RequiredArgsConstructor
public class ProductCacheEvictor {
    private final LoanProductCache cache;

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void on(ProductChangedEvent event) {
        cache.evict(event.productId());
    }
}
```

> **면접 예상 질문:** 캐시 무효화를 서비스에서 직접 호출하지 않고 이벤트로 분리하면 결합도/SRP 측면에서 무엇이 좋아지는가? 단점은 없는가?

---

### @TransactionalEventListener(AFTER_COMMIT) — race condition 차단

리스너는 `@EventListener`가 아니라 `@TransactionalEventListener(phase = AFTER_COMMIT)`를 쓴다. 둘의 차이:
- `@EventListener` → `publishEvent` 호출 **즉시 동기 실행** (트랜잭션 커밋 여부 무관)
- `@TransactionalEventListener` → 트랜잭션의 특정 시점(phase)에 실행. phase: `BEFORE_COMMIT`, **`AFTER_COMMIT`(기본값)**, `AFTER_ROLLBACK`, `AFTER_COMPLETION`

> 주의: `AFTER_COMMIT`(이벤트 리스너 phase)과 `READ COMMITTED`(트랜잭션 격리 수준)는 **다른 개념**이다. 전자는 "리스너가 언제 실행되나", 후자는 "다른 트랜잭션의 변경을 언제 보나". 헷갈리기 쉬움.

**왜 커밋 후에 비워야 하나? — race condition.** 커밋 전에 evict하면 "캐시 비우기"와 "커밋"의 순서가 꼬일 수 있다. 단, 이건 **동시 요청이 있을 때**만 터진다(혼자선 멀쩡 → 그래서 "race", 경쟁).

```
[커밋 전 evict 시나리오]
A: evict (캐시 비움)            ← 아직 커밋 안 됨, DB는 옛날 값
B: get → 캐시 미스 → DB 조회 → [옛날 값]을 캐시에 채움
A: 커밋!                        ← 이제 DB는 새 값
결과: DB=새 값, 캐시=옛날 값 → stale! 😱
```

`AFTER_COMMIT`은 evict를 **커밋이 끝난 뒤로 미뤄서**, B가 끼어들 빈틈 자체를 없앤다. → "DB 확정(커밋) → 그 다음 캐시 비우기(evict)" 순서 강제.

> **칠판 비유:** 칠판(캐시)에 "1000원". 사장(트랜잭션 A)이 2000원으로 바꾼다. 커밋 전에 칠판을 지우면, 그 찰나에 손님(요청 B)이 와서 장부(DB)의 옛날 1000원을 다시 칠판에 적는다 → 사장이 장부를 2000원으로 확정 → 칠판(1000)≠장부(2000). 한가한 가게(동시 요청 없음)면 손님이 안 와서 티가 안 나지만, 트래픽이 몰리면 반드시 터지는 "어쩌다 한 번" 버그.

> **면접 예상 질문:** `@EventListener` 대신 `@TransactionalEventListener(AFTER_COMMIT)`를 쓰는 이유를 race condition 관점에서 설명하라. 동시 요청이 없으면 왜 이 문제가 드러나지 않는가?

---

## 학습 정리

- `bulkInsert`는 여러 행을 한 INSERT로 묶어 I/O를 줄인다. `@Mapper`는 **MyBatis** 신호 — SQL을 직접 작성하며 JPA의 메서드명 자동 생성과 다르다.
- `ApplicationEventPublisher`는 스프링 내장 Pub-Sub 발행 창구, 이벤트 `record`는 변경 정보(productId)를 실어 나르는 메신저. Kafka Pub-Sub의 단일 프로세스 경량 버전.
- 캐시 evict를 서비스에 직접 박지 않고 이벤트로 분리 → 서비스가 캐시를 몰라도 됨 → **결합도 ↓, SRP, 느슨한 결합**(객체지향적).
- `@TransactionalEventListener(AFTER_COMMIT)`는 커밋 이후에만 evict 실행. `@EventListener`(즉시 실행)와 다르고, phase는 격리 수준과 별개 개념.
- 커밋 전 evict는 동시 요청 시 "옛날 값 재적재" race condition을 부른다. AFTER_COMMIT이 빈틈을 없애 stale을 차단. 혼자일 땐 안 터지는 게 race의 본질.

## 참고

- (이전 TIL) java/Caffeine 캐시 적용과 stale data 전략 - evict, CacheEvict AOP, Component vs Configuration, 캐시 단위.md
- (이전 TIL) redis/Redis 분산 락과 교착 상태.md
- (이전 TIL) java/@Transactional 심화.md
