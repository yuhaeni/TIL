# @Transactional 심화

> 날짜: 2026-04-17

## 내용

### readOnly = true 설계 패턴과 성능 이점

클래스 레벨에 `readOnly = true`를 기본값으로 두고, 쓰기 메서드만 `@Transactional`로 오버라이드하는 패턴이다.

```java
@Service
@Transactional(readOnly = true)  // 클래스 레벨: 기본값
public class OrderService {

    @Transactional  // 쓰기 메서드만 오버라이드
    public OrderResponse createOrder(CreateOrderRequest request) { ... }
}
```

- 기본값 `readOnly = true` → 실수로 쓰기 누락 방지 (안전장치)
- 쓰기 메서드에서만 명시적으로 트랜잭션 선언

**readOnly = true의 성능 이점 (Dirty Checking 최적화):**

JPA는 조회한 엔티티의 스냅샷을 영속성 컨텍스트에 저장해두고, 트랜잭션 종료 시 변경 여부를 비교해 UPDATE 쿼리를 자동 발행한다.  
`readOnly = true`는 "어차피 변경 안 할 거야"를 미리 알리므로:
- **스냅샷 생성 생략** → 메모리 절약
- **변경 비교 연산 생략** → CPU 부담 감소
- 조회 메서드가 많을수록 누적 효과가 커짐

> **면접 예상 질문:** `@Transactional(readOnly = true)`의 성능 이점은?

---

### 트랜잭션 전파: ThreadLocal

스프링은 트랜잭션 시작 시 **현재 스레드의 ThreadLocal**에 트랜잭션 정보를 저장한다. 같은 스레드 내에서 호출되는 메서드들은 이 ThreadLocal을 공유하므로 같은 트랜잭션에 참여한다.

```java
@Transactional
public OrderResponse createOrder(...) {
    // 프록시가 트랜잭션 시작 → ThreadLocal에 저장
    someMethod();  // 같은 스레드 → ThreadLocal의 트랜잭션 그대로 참조 ✅
}
```

다른 스레드면 별개의 ThreadLocal → 별개의 트랜잭션이다.

> **면접 예상 질문:** 트랜잭션이 메서드 간에 어떻게 전파되는가?

---

### Self-invocation 문제 (프록시 AOP의 함정)

스프링 컨테이너에는 실제 객체가 아닌 **프록시 객체**가 등록된다. `@Transactional`은 외부에서 프록시를 통해 호출될 때만 적용된다.

```
[외부 호출] ✅
손님 → OrderServiceProxy → OrderService
              ↑ 여기서 트랜잭션 시작!

[Self-invocation] ❌
OrderService → this.createOrder()
              ↑ this = 프록시가 아닌 자기 자신
              → 프록시를 완전히 건너뜀!
              → ThreadLocal에 트랜잭션 없음!
```

| 호출 방식 | 프록시 거침? | 트랜잭션 적용 |
|---|---|---|
| 외부에서 `orderService.createOrder()` | O | O |
| 내부 `createOrder()` → `this.someMethod()` | X (두 번째는) | O (이미 ThreadLocal에 존재) |
| 내부 `someMethod()` → `this.createOrder()` | X | X (ThreadLocal 비어있음) |

처음 진입 시점에 **프록시를 거쳤는지 여부**로 ThreadLocal에 트랜잭션이 담기느냐가 결정된다.

> **면접 예상 질문:** Self-invocation 문제란 무엇이고 왜 발생하는가?

---

### Self-invocation 해결 방법

| 방법 | 단점 |
|---|---|
| `@Autowired self` (자기 자신 주입) | 순환 의존성 냄새 |
| `ApplicationContext.getBean()` | 스프링 내부 구조 의존 → 단일 책임 원칙 위배 |
| `AopContext.currentProxy()` | 별도 설정 필요, 단일 책임 위배 |
| **클래스 분리 (권장)** | 없음 |

```java
// ✅ 권장: 클래스 분리
@Service
public class OrderService {
    private final OrderCreateService orderCreateService;

    public void someMethod() {
        orderCreateService.createOrder(request);  // 외부 호출 → 프록시 거침!
    }
}

@Service
public class OrderCreateService {
    @Transactional
    public OrderResponse createOrder(...) { ... }
}
```

**Self-invocation이 발생한다는 건 설계 신호다.**  
"이 두 메서드가 정말 같은 클래스에 있어야 할까?"를 스스로 물어봐야 한다. 1~3번은 임시방편이고, 가장 좋은 해결책은 **책임 분리 설계**다.

> **면접 예상 질문:** Self-invocation 해결 방법은? 가장 권장되는 방법과 이유는?

---

### 스프링이 프록시를 사용하는 이유

트랜잭션, 로깅, 보안 같은 **횡단 관심사(Cross-cutting Concern)** 를 비즈니스 로직과 분리하기 위해 AOP 프록시를 사용한다.

프록시 없이 직접 작성한다면:
```java
public OrderResponse createOrder(...) {
    transaction.begin();   // 메서드마다 반복
    // 비즈니스 로직
    transaction.commit();
}
```
메서드 100개면 100번 반복해야 한다. 프록시가 이 부가 기능을 대신 처리해주므로 개발자는 `@Transactional`만 붙이면 된다.

> **면접 예상 질문:** 스프링이 프록시를 사용하는 이유는? AOP와 어떤 관계인가?

---

## 학습 정리

- 클래스 레벨 `readOnly = true` + 쓰기 메서드만 오버라이드 → 안전하고 성능 효율적인 설계
- `readOnly = true`는 Dirty Checking(스냅샷 생성 + 변경 비교)을 생략하여 메모리/CPU 절약
- 트랜잭션은 ThreadLocal에 저장되어 같은 스레드 내 메서드 간에 전파됨
- Self-invocation 시 프록시를 건너뛰어 `@Transactional` 무시 → 클래스 분리로 근본 해결
- 프록시는 횡단 관심사를 비즈니스 로직에서 분리하기 위한 AOP 구현 방식

## 참고

- CarrotSettle (Java, Spring Boot 4.0.x) 프로젝트 기반 학습
