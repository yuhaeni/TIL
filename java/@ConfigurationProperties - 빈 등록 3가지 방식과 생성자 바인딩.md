# @ConfigurationProperties — 빈 등록 3가지 방식과 생성자 바인딩

> 날짜: 2026-06-02

## 내용

### @ConfigurationProperties의 진짜 역할 — 빈 등록이 아니라 "바인딩 설명서"

`@ConfigurationProperties` 어노테이션 단독으로는 빈이 등록되지 않는다. IDE도 친절하게 경고를 띄운다.

```
Not registered via @EnableConfigurationProperties,
marked as Spring component,
or scanned via @ConfigurationPropertiesScan
```

`@ConfigurationProperties`가 하는 일은 두 가지뿐이다.

1. *"이 클래스는 yml/properties 값을 담는 그릇이다"* 라고 표시
2. *"prefix가 `google.oauth2`로 시작하는 키들을 이 필드에 매핑하라"* 는 바인딩 규칙 정의

→ **빈 등록은 별도 어노테이션이 담당.** `@ConfigurationProperties`는 *바인딩 설명서*일 뿐이다.

비유:
- `@ConfigurationProperties` = *"이 그릇에 이런 재료를 담아주세요"* (레시피)
- 빈 등록 어노테이션 = *"이 그릇을 식탁에 올려주세요"*

레시피만 있고 식탁에 올라가지 않으면 음식을 못 먹는다.

> **면접 예상 질문:** `@ConfigurationProperties`만 붙인 클래스가 동작하지 않는 이유는 무엇이며, 동작시키려면 어떤 추가 어노테이션 중 하나가 필요한가?

---

### 빈 등록 3가지 방법 — @Component, @EnableConfigurationProperties, @ConfigurationPropertiesScan

`@ConfigurationProperties` 클래스를 빈으로 등록하는 방법은 세 가지가 있다.

| 방법 | 어디에 붙여? | 언제 써? |
|---|---|---|
| `@Component` | 프로퍼티 클래스 본인 | 간단하지만 *의도(intent)* 가 모호 |
| `@EnableConfigurationProperties(X::class)` | 외부 `@Configuration` 클래스 | 소규모, 명시적 등록 |
| `@ConfigurationPropertiesScan` | 외부 `@Configuration` 클래스 | 대규모, 자동 스캔 |

**3가지 모두 동작은 한다.** 단, IDE가 `@EnableConfigurationProperties` 또는 `@ConfigurationPropertiesScan`을 권장하는 이유는 *코드를 읽는 사람에게 의도가 명확하기 때문*이다.

- `@Component`: 너무 두루뭉술 — *"이게 서비스인가? 유틸인가? 프로퍼티인가?"* 추측해야 함
- `@EnableConfigurationProperties` / `@ConfigurationPropertiesScan`: *"아, 이건 프로퍼티 바인딩 전용 클래스구나"* 즉시 파악 가능

> **면접 예상 질문:** `@ConfigurationProperties` 클래스를 빈으로 등록하는 3가지 방법은 무엇이며, 각각의 트레이드오프와 권장되는 방식은?

---

### @EnableConfigurationProperties는 어디에 붙여야 하는가 — 외부 Config 클래스

`@EnableConfigurationProperties(GoogleProperties::class)`를 *프로퍼티 클래스 본인*에 붙이는 건 잘못된 사용이다. *"내가 나를 채용해주세요"* 라고 자기 이력서에 적는 것과 비슷하다.

**잘못된 예 (자기 자신을 등록 지시):**
```kotlin
@EnableConfigurationProperties(GoogleProperties::class)  // ❌ 본인한테 붙임
@ConfigurationProperties(prefix = "google.oauth2")
data class GoogleProperties(...)
```

**올바른 예 (외부 클래스가 등록 지시):**
```kotlin
// 1) 프로퍼티 클래스 - @ConfigurationProperties만!
@ConfigurationProperties(prefix = "google.oauth2")
data class GoogleProperties(
    val webClientId: String = "",
    val iosClientId: String = "",
    val playground: String? = null,
)

// 2) 외부 @Configuration 클래스(또는 메인 앱)에서 등록 지시
@SpringBootApplication
@EnableConfigurationProperties(GoogleProperties::class)
class UsagiAppApiApplication
```

또한 괄호 안에 *반드시 클래스를 명시*해야 한다. 비워두면 Spring이 어떤 클래스를 등록해야 할지 알 수 없다.

> **면접 예상 질문:** `@EnableConfigurationProperties`를 프로퍼티 클래스 자기 자신에 붙이지 말아야 하는 이유는 무엇이며, 어디에 붙이는 것이 자연스러운가?

---

### @Configuration vs @Component — 자기 자신이 빈 vs 빈을 만드는 공장

| 어노테이션 | 비유 | 역할 |
|---|---|---|
| `@Component` | *"나 자신이 직원이에요!"* | 본인이 빈으로 등록됨 |
| `@Configuration` | *"나는 직원을 채용하는 부서장이에요!"* | 안에 `@Bean` 메서드로 *다른 빈들을 만듦* |

```kotlin
// @Component: 본인이 빈
@Component
class UserService { ... }  // UserService 자체가 빈

// @Configuration: 빈을 만드는 공장
@Configuration
class AppConfig {
    @Bean fun userService() = UserService()   // 여기서 빈을 만들어줌
    @Bean fun emailService() = EmailService()
}
```

`@EnableConfigurationProperties`는 그 자체로는 *지시문(directive)* 이다. 이 지시문을 읽고 실행해줄 *공장(=`@Configuration` 클래스)* 이 있어야 효력이 있다. 작업 지시서를 길에다 붙여놓으면 아무도 안 보는 것과 같다.

그래서 `@Configuration` + `@EnableConfigurationProperties`는 함께 쓴다:
- `@Configuration` = "여기서 빈을 만들어요" (지시문을 읽을 장소)
- `@EnableConfigurationProperties(X::class)` = "X를 빈으로 만들어줘!" (구체적 지시)

> **면접 예상 질문:** `@Configuration`과 `@Component`의 차이는 무엇이며, `@EnableConfigurationProperties`가 왜 `@Configuration` 클래스 위에 붙어야 하는가?

---

### @ConfigurationPropertiesScan — 자동 스캔으로 수십 개 프로퍼티 클래스 관리

프로퍼티 클래스가 수십 개인 프로젝트에서 `@EnableConfigurationProperties`로 일일이 나열하는 것은 비효율적이다.

```kotlin
// 수동 등록 — 클래스 늘어날 때마다 추가해야 함 😩
@EnableConfigurationProperties(
    GoogleProperties::class,
    KakaoProperties::class,
    NaverProperties::class,
    // ... 수십 개
)
```

`@ConfigurationPropertiesScan`은 `@Component`에 대응되는 `@ComponentScan`처럼, `@ConfigurationProperties`가 붙은 클래스를 *자동 스캔*한다.

```kotlin
@SpringBootApplication
@ConfigurationPropertiesScan  // ⭐ 메인 클래스에 하나만 붙이면 끝
class UsagiAppApiApplication
```

동작 원리:
- 메인 클래스가 있는 패키지부터 *하위 모든 패키지*를 자동 스캔
- `@ConfigurationProperties`가 붙은 클래스를 *모두 자동 빈 등록*
- 패키지 지정도 가능: `@ConfigurationPropertiesScan("com.kou.config")`

이후 새 프로퍼티 클래스를 추가할 때는 `@ConfigurationProperties`만 붙이면 끝. 메인 클래스를 다시 수정할 필요가 없다.

> **면접 예상 질문:** `@EnableConfigurationProperties`와 `@ConfigurationPropertiesScan`의 차이는 무엇이며, 어떤 규모/상황에 어느 쪽이 더 적합한가?

---

### 생성자 바인딩 — val로 불변 프로퍼티 클래스 만들기

Spring Boot 2.2+ 부터는 **생성자 바인딩(Constructor Binding)** 을 지원한다. setter 없이 *생성자에 값을 넣어주는 방식*이라, 모든 필드를 `val`(불변)로 선언할 수 있다.

```kotlin
@ConfigurationProperties(prefix = "google.oauth2")
data class GoogleProperties(
    val webClientId: String,    // ✅ val OK
    val iosClientId: String,    // ✅ val OK
    val playground: String,     // ✅ val OK
)
```

| 방식 | 객체 생성 흐름 | 필드 키워드 |
|---|---|---|
| setter 주입 | 빈 상자(객체) 생성 → setter로 값 주입 | `var` 필수 |
| 생성자 바인딩 | 처음부터 값을 채운 채로 생성 | `val` 가능 |

Spring Boot 3.x에서는 **단일 생성자라면 자동으로 생성자 바인딩**을 쓴다. 그래서 `val`만으로 안전한 *불변 객체*를 만들 수 있다.

설정값은 애플리케이션 실행 후 바뀌면 안 되는 값이므로 *불변으로 관리하는 것이 안전*하다. 누군가 실수로 setter를 호출해 런타임에 값을 바꿔버리는 사고를 원천 차단할 수 있다.

> **면접 예상 질문:** Spring Boot의 생성자 바인딩이란 무엇이며, 프로퍼티 클래스를 불변(`val`)으로 만들면 어떤 이점이 있는가?

---

## 학습 정리

- `@ConfigurationProperties`는 빈 등록 어노테이션이 아니라 *바인딩 규칙 설명서*다. 단독으로는 동작하지 않는다.
- 빈 등록 방법은 3가지 — `@Component`(자기 등록), `@EnableConfigurationProperties`(외부 명시 등록), `@ConfigurationPropertiesScan`(외부 자동 스캔).
- `@EnableConfigurationProperties`는 *프로퍼티 클래스 본인이 아니라* 외부 `@Configuration` / `@SpringBootApplication` 클래스에 붙여야 한다.
- `@Configuration`은 *빈을 만드는 공장*, `@Component`는 *본인이 빈*. `@EnableConfigurationProperties`는 지시문이라 공장(`@Configuration`) 위에 붙어야 동작한다.
- Spring Boot 2.2+ 의 생성자 바인딩 덕분에 `val`만 사용해 불변 프로퍼티 클래스를 만들 수 있다. 설정값은 불변이 안전하다.
- 대규모 프로젝트는 `@ConfigurationPropertiesScan`로 자동 스캔하는 것이 *의도가 명확*하고 *유지보수도 쉽다*.
