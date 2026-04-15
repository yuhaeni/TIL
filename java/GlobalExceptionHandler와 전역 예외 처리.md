# GlobalExceptionHandler와 전역 예외 처리

> 날짜: 2026-04-15

## 내용

### @RestControllerAdvice와 전역 예외 처리

`@RestControllerAdvice`가 없으면 각 컨트롤러마다 try-catch를 직접 작성해야 한다. Advice는 전체 컨트롤러에서 던져진 예외를 잡아채는 **전역 예외 처리(Global Exception Handling)** 역할을 한다.

**`@ControllerAdvice` vs `@RestControllerAdvice`:**

| | `@ControllerAdvice` | `@RestControllerAdvice` |
|---|---|---|
| 반환 방식 | 뷰 이름 (템플릿 렌더링) | JSON 응답 바디 |
| 구성 | - | `@ControllerAdvice` + `@ResponseBody` |
| 적합한 상황 | MVC 뷰 기반 | REST API |

`@ResponseBody`가 붙으면 반환 객체가 `HttpMessageConverter`를 통해 **JSON으로 직렬화**되어 응답 바디에 담긴다.

`@RestControllerAdvice`는 예외 처리라는 **횡단 관심사(Cross-cutting Concern)** 를 모든 컨트롤러에서 분리하여 한 곳에 모은 **AOP** 적용 사례이다.

```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(BusinessException.class)
    public ResponseEntity<ErrorResponse> handle(BusinessException e) {
        return ResponseEntity.status(e.getStatus()).body(ErrorResponse.of(e.getErrorCode()));
    }
}
```

> **면접 예상 질문:** `@RestControllerAdvice`와 `@ControllerAdvice`의 차이는? AOP와 어떤 관계인가?

---

### BusinessException 설계와 OCP

`BusinessException`에 `status`/`errorCode`를 직접 담는 설계는 **OCP(Open-Closed Principle)** 를 적용한 것이다.

- 예외 객체 스스로 자신의 HTTP 상태코드를 알고 있음
- ExceptionHandler에서 if-else 분기 제거
- 새로운 예외가 추가되어도 핸들러 코드 수정 불필요 (확장에 열려있고, 수정에 닫혀있음)

**ErrorCode를 enum으로 만드는 이유:**

- `ErrorCode.NOT_FOUND`: 정의되지 않으면 **컴파일 에러** → 오타를 컴파일 타임에 감지
- `"NOT_FOUND"` (String): 오타는 **런타임에만** 발견 → 장애로 이어질 수 있음

> **면접 예상 질문:** `BusinessException`에 `status`와 `errorCode`를 직접 넣은 설계 이유는? ErrorCode를 enum으로 만드는 이유는?

---

### @Valid 검증 실패 시 전체 흐름

```
사용자 요청
  → DispatcherServlet
  → HandlerMapping (URL에 해당하는 Controller 찾기)
  → HandlerAdapter (DTO 바인딩 + @Valid 유효성 검사)
  → 검증 실패 시 MethodArgumentNotValidException 발생
  → DispatcherServlet으로 전파
  → @RestControllerAdvice가 가로챔
  → ErrorResponse JSON 반환
```

`MethodArgumentNotValidException` 처리 시 `BindingResult`에서 첫 번째 필드 에러 메시지를 꺼내 응답에 담는다.

```java
@ExceptionHandler(MethodArgumentNotValidException.class)
public ResponseEntity<ErrorResponse> handle(MethodArgumentNotValidException e) {
    String message = e.getBindingResult().getFieldErrors().stream()
        .map(fe -> fe.getField() + ": " + fe.getDefaultMessage())
        .findFirst()
        .orElse(ErrorCode.INVALID_INPUT.getMessage());
    return ResponseEntity.badRequest().body(ErrorResponse.of(ErrorCode.INVALID_INPUT, message));
}
```

> **면접 예상 질문:** `@Valid` 검증 실패 시 Spring 내부에서 어떤 흐름으로 처리되는가?

---

### @Valid vs @Validated

| | `@Valid` | `@Validated` |
|---|---|---|
| 출처 | Java 표준 (Jakarta Bean Validation) | Spring 전용 |
| 사용 위치 | Controller 파라미터 | 모든 레이어 (Service 등) |
| 그룹 검증 | 불가 | 가능 |

`@Validated`가 Service 레이어에서도 동작하는 이유: **AOP 프록시**가 메서드 호출을 가로채서 검증을 수행하기 때문이다.

> **면접 예상 질문:** `@Valid`와 `@Validated`의 차이는? `@Validated`가 Service 레이어에서도 동작하는 이유는?

---

## 학습 정리

- `@RestControllerAdvice` = `@ControllerAdvice` + `@ResponseBody`, REST API 전역 예외 처리에 적합
- 횡단 관심사(예외 처리)를 컨트롤러에서 분리한 AOP 적용 사례
- `BusinessException`에 status/errorCode를 담아 OCP 준수, ErrorCode enum으로 컴파일 타임 오타 감지
- `@Valid` 실패 시 `MethodArgumentNotValidException` 발생 → `@RestControllerAdvice`가 가로챔
- `@Validated`는 AOP 프록시 기반으로 Service 레이어 등 모든 레이어에서 사용 가능

## 참고

- Spring Boot `GlobalExceptionHandler` 코드 기반 학습
