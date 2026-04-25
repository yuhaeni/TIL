# record와 @Valid 동작 원리

> 날짜: 2026-04-25

## 내용

### record가 자동 생성하는 요소

```java
public record CalculateSettlementRequest(@NotNull LocalDate targetDate) {}
```

이 한 줄로 컴파일러가 다음을 자동 생성한다.

| 자동 생성 요소 | 설명 |
|---|---|
| `private final` 필드 | 컴포넌트 = 필드 |
| **Canonical Constructor** | 모든 컴포넌트를 받는 생성자 |
| 접근자 메서드 | `targetDate()` 형태 (get 접두사 없음) |
| `equals()` / `hashCode()` | 모든 컴포넌트 기반 |
| `toString()` | 모든 컴포넌트 출력 |

→ 개발자는 **컴포넌트 한 줄**만 쓰면 됨.

> **면접 예상 질문:** record가 자동 생성하는 요소는? Canonical Constructor란?

---

### record의 어노테이션 전파 메커니즘

`@NotNull` 같은 Bean Validation 어노테이션은 **`@Target`이 여러 위치를 허용**한다.

```java
@Target({ METHOD, FIELD, ANNOTATION_TYPE, CONSTRUCTOR, PARAMETER, TYPE_USE })
public @interface NotNull { ... }
```

record는 컴포넌트에 붙은 어노테이션을 **갈 수 있는 모든 곳에 자동 복사**한다.

- ✅ 자동 생성된 **필드**에 `@NotNull` 부여
- ✅ 자동 생성된 **생성자 파라미터**에 `@NotNull` 부여
- ✅ 자동 생성된 **접근자 메서드**에 `@NotNull` 부여

**핵심:** "파라미터로 받으면 필드는 어차피 자동으로 만들어주니까, **컴포넌트 한 곳에만 붙여도 모든 곳에 전파**된다."

→ 그래서 record는 필드가 아닌 **파라미터(컴포넌트) 위치에 어노테이션을 작성**한다. 다른 곳에 붙이려면 `@field:`, `@param:` 같은 use-site target을 써야 하지만, 보통 컴포넌트 한 곳이면 충분.

> **면접 예상 질문:** record는 왜 필드가 아닌 컴포넌트에 어노테이션을 붙이는가? 어노테이션이 어디까지 전파되는가?

---

### @Valid 동작 흐름 — 전체 그림

```
사용자 요청 (JSON)
  ↓
DispatcherServlet
  ↓
HandlerMapping (URL → Controller 매칭)
  ↓
HandlerAdapter
  ↓
HandlerMethodArgumentResolver
  └─ RequestResponseBodyMethodProcessor (@RequestBody 처리)
      ├─ Jackson: JSON → record 객체 변환 (Canonical Constructor 호출)
      └─ @Valid 발견 → Bean Validator 호출
          ↓ 검증 실패
  MethodArgumentNotValidException 발생
  ↓
HandlerExceptionResolver
  └─ ExceptionHandlerExceptionResolver
      └─ @RestControllerAdvice + @ExceptionHandler 탐색 → 가로챔
  ↓
JSON 에러 응답 반환
```

**핵심 포인트:**
- 검증 시점: **객체 생성 직후** (생성자 파라미터의 어노테이션 검사)
- 던지는 주체: **`RequestResponseBodyMethodProcessor`** (ArgumentResolver 구현체)
- 가로채는 주체: **`ExceptionHandlerExceptionResolver`** → `@RestControllerAdvice`

> **면접 예상 질문:** `@Valid` 검증 실패 시 누가 예외를 던지고 누가 가로채는가? 검증은 어느 시점에 발생하는가?

---

### @Valid vs @Validated

| 구분 | `@Valid` | `@Validated` |
|---|---|---|
| 출신 | Java 표준 (Jakarta) | Spring 전용 |
| 사용 위치 | Controller 파라미터 | 클래스 레벨 (Service 등) |
| 동작 원리 | **ArgumentResolver** | **AOP 프록시** |
| 그룹 검증 | ❌ | ✅ |

`@Validated`가 Service 메서드에서도 동작하는 이유는 Spring이 만든 **AOP 프록시**가 메서드 호출을 가로채서 검증을 수행하기 때문이다. `@Transactional`과 동일한 원리.

```java
@Service
@Validated
public class MyService {
    public void process(@NotNull String value) { ... }  // AOP가 가로채 검증
}
```

> **면접 예상 질문:** `@Valid`와 `@Validated`의 차이는? `@Validated`가 Service에서 동작하는 원리는?

---

### Self-invocation 함정

**비유 — 회사 경비원 🏢**
- **경비원(프록시)**: 외부 손님 신분증 검사
- **김대리(원본 객체)**: 프록시가 감싸는 실제 빈
- 외부 손님(다른 빈) → 경비원 거침 → AOP 동작 ✅
- 김대리가 사무실 안에서 박과장 부르기 → 경비원 안 거침 → AOP 미동작 ❌

**코드로 보면:**
```java
@Service
@Validated
public class MyService {

    public void outer() {
        this.inner(null);  // ❌ 검증 안 됨! this = 원본 객체
    }

    public void inner(@NotNull String value) { ... }
}
```

**원인 4단계:**
1. Spring 빈은 사실 **프록시 객체** (원본을 감싼 껍데기)
2. 외부에서 주입받아 호출 → 프록시 거침 → AOP 동작 ✅
3. `this.method()` → `this`는 **원본 객체 자신**
4. 프록시를 거치지 않으니 검증/트랜잭션/비동기 모두 미동작 ❌

**같은 함정에 빠지는 어노테이션:**
- `@Transactional`
- `@Validated`
- `@Async`
- `@Cacheable`
- 모든 **AOP 기반 어노테이션**

**해결책:**
- 메서드를 **다른 빈으로 분리** (가장 권장)
- `ApplicationContext`로 자기 자신을 다시 조회 (지저분함)
- `AopContext.currentProxy()` 사용 (`@EnableAspectJAutoProxy(exposeProxy = true)` 필요)

> **면접 예상 질문:** Self-invocation 문제란 무엇이며 왜 발생하는가? 같은 클래스 안에서 `@Transactional` 메서드를 호출하면 어떻게 되는가?

---

### 한 문장 정리

> **"record 컴포넌트에 어노테이션 한 번 = 자동 전파. `@Valid`는 ArgumentResolver가 검증, 실패 시 `@RestControllerAdvice`가 가로챔. `@Validated`는 AOP 프록시 기반이라 Self-invocation에 주의."**

> **면접 예상 질문:** record + `@Valid`로 요청을 검증하는 전체 흐름을 설명하라.

---

## 학습 정리

- record는 컴포넌트 한 줄로 **필드/생성자/접근자/equals/hashCode/toString** 자동 생성
- record 컴포넌트의 어노테이션은 `@Target`이 허용하는 **모든 위치(필드/파라미터/메서드)에 자동 전파**
- `@Valid` 검증은 **`RequestResponseBodyMethodProcessor`** (ArgumentResolver)에서 객체 생성 직후 발생
- 검증 실패 시 **`MethodArgumentNotValidException`** → `@RestControllerAdvice`가 가로채 응답
- `@Valid`(Java 표준, ArgumentResolver) vs `@Validated`(Spring, AOP 프록시) — 동작 원리가 다름
- `@Validated`/`@Transactional`/`@Async`/`@Cacheable` 모두 AOP 기반 → **Self-invocation 시 미동작**
- 해결책은 메서드를 **다른 빈으로 분리**하는 것이 가장 깔끔

## 참고

- CarrotSettle 정산 도메인 `CalculateSettlementRequest` 기반 학습
- Java Language Specification — Records
- Spring `RequestResponseBodyMethodProcessor`, `ExceptionHandlerExceptionResolver` 소스
- Spring AOP 프록시 메커니즘 공식 문서
