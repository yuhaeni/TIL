# ResponseEntity와 ApiResponse 트레이드오프

> 날짜: 2026-04-17

## 내용

### ResponseEntity vs ApiResponse\<T\>

**ResponseEntity**: Spring에서 HTTP 응답의 status code, header, body를 직접 제어하는 객체  
**ApiResponse\<T\>**: 응답 포맷을 일관되게 만들기 위한 커스텀 제네릭 래퍼 클래스

```kotlin
data class ApiResponse<T>(
    val success: Boolean,
    val data: T? = null,
    val message: String? = null,
    val errorCode: String? = null,
)
```

| 관점 | ApiResponse\<T\>만 사용 | ResponseEntity 사용 |
|---|---|---|
| HTTP status 제어 | 200으로 통일됨 | 엔드포인트마다 세밀하게 제어 가능 |
| 응답 포맷 일관성 | 껍데기 통일 | 직접 감싸야 함 |
| 코드 간결성 | 짧고 깔끔 | 장황함 (보일러플레이트) |
| REST 의미 표현 | body 의존 | status로 표현 |
| 프론트 처리 편의성 | 인터셉터 일괄 처리 가능 | 응답 구조 제각각 |

> **면접 예상 질문:** ResponseEntity와 커스텀 응답 래퍼(ApiResponse)의 차이는? 각각 어떤 상황에 적합한가?

---

### 조합 패턴: ResponseEntity\<ApiResponse\<T\>\>

두 방식의 장점을 모두 챙기는 실무 패턴이다. HTTP status는 ResponseEntity로 제어하고, 응답 포맷은 ApiResponse로 통일한다.

```kotlin
ResponseEntity
    .status(HttpStatus.CREATED)
    .body(ApiResponse.success(data))
```

단점: 모든 컨트롤러 메서드에서 반복 작성 → 보일러플레이트 증가

**프로젝트 성격에 따른 선택 기준:**

| 상황 | 적합한 방식 |
|---|---|
| 사내 서비스, MVP, 단일 프론트엔드 | ApiResponse\<T\>만 사용 |
| 외부 파트너/공개 API | ResponseEntity (HTTP 표준 준수) |
| Swagger UI가 주요 소비자 | ResponseEntity (201, 204 세분화) |
| 다양한 클라이언트(모바일, 서드파티) | ResponseEntity |

> **면접 예상 질문:** `ResponseEntity<ApiResponse<T>>` 조합 패턴을 쓰는 이유는?

---

### 에러 응답에서 status code가 중요한 이유

에러 응답에는 반드시 올바른 HTTP status code를 함께 반환해야 한다.

```kotlin
@ExceptionHandler(GlobalException::class)
fun handleGlobalException(e: GlobalException): ResponseEntity<ApiResponse<Unit>> {
    return ResponseEntity
        .status(e.status)
        .body(ApiResponse.failure(message = e.message ?: "Server error"))
}
```

**status 200 + `success: false`만 반환하면 생기는 문제:**
- 프론트의 `axios`/`fetch`는 HTTP status 4xx/5xx일 때만 catch 블록으로 떨어짐
- status 200이면 성공으로 인식 → 매번 body의 `success` 필드를 수동 체크 필요
- 글로벌 인터셉터로 에러를 일괄 처리하는 패턴도 불가능

에러 응답에서만큼은 `ResponseEntity<ApiResponse<T>>` 조합이 사실상 필수다.

> **면접 예상 질문:** 에러 응답에서 HTTP status code를 200으로 주면 어떤 문제가 생기는가?

---

## 학습 정리

- ResponseEntity는 HTTP 프로토콜 레벨 제어, ApiResponse는 애플리케이션 레벨 응답 포맷 통일
- 단일 프론트엔드 사내 서비스는 ApiResponse만으로 충분, 외부 API/Swagger 중심은 ResponseEntity 권장
- `ResponseEntity<ApiResponse<T>>` 조합으로 두 장점을 모두 챙길 수 있지만 보일러플레이트 증가
- 에러 응답에는 반드시 4xx/5xx status를 함께 반환해야 프론트 인터셉터 일괄 처리가 가능

## 참고

- usagi-app-api (Kotlin), CarrotSettle (Java) 프로젝트 의사결정 기반 학습
