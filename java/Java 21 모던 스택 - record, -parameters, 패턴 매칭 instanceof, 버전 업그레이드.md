# Java 21 모던 스택 — record, -parameters, 패턴 매칭 instanceof, 버전 업그레이드 트레이드오프

> 날짜: 2026-06-12

## 내용

`mall-scraper`(11개 판매몰 스크래핑 시스템)는 Java 21 + Gradle Kotlin DSL 기반이다. 코드를 읽기 전 표면에 깔린 모던 문법 도구들 — `record`, `-parameters`, 패턴 매칭 `instanceof` — 과 11 → 21 버전 업그레이드의 의미를 정리한다.

---

### record — 불변 데이터 캐리어 (Java 16+)

`MallCredentials`, `MallDataItem`, `ScrapeRequest` 등 도메인 모델이 전부 `record`로 선언돼 있다.

```java
public record MallCredentials(String userId, String password) { }
```

- **Kotlin `data class`와 닮은 꼴**: `equals()`, `hashCode()`, `toString()`, 생성자, 접근자(`userId()`)를 컴파일러가 자동 생성 → 보일러플레이트 제거.
- **결정적 차이 — 불변**: Kotlin은 `var`/`val`을 개발자가 고를 수 있지만, `record`는 **선택권 없이 모든 필드를 강제로 `final`**(= Kotlin의 `val`)로 만든다. 한번 생성하면 값 변경 불가.
- **헷갈렸던 포인트**: "`var`/`val` 개념이 없으니 값을 바꿀 수 있지 않나?" → 반대다. 개념이 없는 게 아니라 **`val`로 고정**된 것.

**불변 객체의 실무 이점 (스크래핑 시스템 맥락)**
멀티스레드로 여러 판매몰을 동시에 긁을 때, `MallCredentials`·`ScrapeRequest`가 불변이면:
- 여러 스레드가 같은 객체를 공유해도 값이 안 바뀜 → **경쟁 상태(Race Condition)** 가 원천적으로 발생 불가.
- 따라서 `synchronized`·락 없이도 안전 → **스레드 세이프(thread-safe)**.
- *스레드 세이프란*: 여러 스레드가 동시에 같은 자원에 접근해도 문제가 안 생기는 상태. (비유: 도서관 책이 "읽기 전용"이면 여러 명이 동시에 봐도 내용이 안 바뀜)

> **면접 예상 질문:** `record`와 일반 클래스의 차이는 무엇이며, 왜 도메인 모델을 `record`로 선언하면 멀티스레드 환경에서 유리한가요?

---

### -parameters 컴파일 옵션 — 파라미터 이름 보존

`build.gradle.kts`에 아래 설정이 있다.

```kotlin
tasks.withType<JavaCompile> {
    options.compilerArgs.add("-parameters")
}
```

- 의미: "자바 소스를 `.class`로 컴파일하는 모든 작업에 `-parameters` 옵션을 추가하라."
- **기본 동작**: 컴파일하면 메서드 파라미터 **이름**(`mallType` 등)이 `.class`에서 `arg0`, `arg1`로 사라진다. 이름은 실행에 영향이 없어 **`.class` 크기를 줄이려고** 컴파일러가 지우는 것.
- **문제**: Spring은 실행 중(런타임)에 파라미터 이름이 필요할 때가 있다.

```java
@GetMapping("/scrape")
public void scrape(@RequestParam String mallType) { ... }
// URL의 ?mallType=naver 를 mallType 파라미터에 매핑하려면
// 런타임에 파라미터 이름이 "mallType"인 걸 알아야 함
```

- **해결**: `-parameters`를 꽂으면 이름이 `.class`에 **보존**되고, Spring이 **리플렉션(Reflection)** 으로 그 이름을 읽어 `@RequestParam` 등을 매핑한다.
- 연결 고리: `record` → `-parameters` → **리플렉션** (런타임에 클래스의 메서드·필드·파라미터 정보를 들여다보는 기술).

> **면접 예상 질문:** `-parameters` 옵션은 왜 필요한가요? 이 옵션이 없으면 Spring의 어떤 기능이 동작하지 않나요?

---

### 패턴 매칭 instanceof — 검사 + 바인딩을 한 번에 (Java 16+)

`HandleOnExceptionAspect.resolveMallType()`에서 사용.

```java
private MallTypeCd resolveMallType(final Object[] args) {
    for (final Object arg : args) {
        if (arg instanceof MallScrapeCommand command) {  // 검사 + 변수 바인딩
            return command.mallType();
        }
        if (arg instanceof MallSession session) {
            return session.mallType();
        }
    }
    return null;
}
```

**옛날 방식 (Java 16 이전)** — 한 가지 일을 3단계로:
```java
if (obj instanceof MallCredentials) {            // ① 타입 검사
    MallCredentials cred = (MallCredentials) obj;  // ② 형변환 (또!)
    cred.userId();                                  // ③ 사용
}
```
- `instanceof`로 타입을 이미 확인했는데 다음 줄에서 **또 형변환**해야 하는 중복.

**새 방식** — `instanceof MallScrapeCommand command`:
- 검사에 성공하는 순간 `command` 변수가 **형변환까지 끝난 채로** 바인딩됨 → 형변환 줄 제거.

**버그 측면 이점**
- 옛날 방식은 검사 타입과 형변환 타입을 **손으로 두 번** 적어야 함 → 실수로 다르게 적으면 런타임에 `ClassCastException`.
- 패턴 매칭은 검사 타입과 바인딩 타입이 **하나로 묶여** 이 실수가 원천 차단됨.

> **면접 예상 질문:** 패턴 매칭 `instanceof`는 기존 방식 대비 어떤 안전성을 제공하나요? 코드가 짧아지는 것 외의 이점은?

---

### Java 11 → 21 업그레이드 — 신기능과 트레이드오프

이 프로젝트는 **11 → 21**(LTS) 점프다. 위 세 기능 모두 11엔 없던 것:

| 기능 | 정식 도입 | Java 11에 있었나? |
|------|----------|------------------|
| `record` | Java 16 | ❌ |
| 패턴 매칭 `instanceof` | Java 16 | ❌ |
| 텍스트 블록 (`"""`) | Java 15 | ❌ |

즉 11에 머물렀다면 `MallCredentials`를 `record`로 못 만들고 필드+생성자+getter+`equals`/`hashCode`를 손으로 다 작성해야 했다.

**Java 21 주요 신기능**

| 기능 | 한 줄 설명 |
|------|----------|
| **가상 스레드 (Virtual Threads)** | 수백만 개의 경량 스레드. I/O 많은 작업(스크래핑)에 적합 |
| **switch 패턴 매칭** | `switch`에서도 타입별 분기 + 바인딩 |
| **레코드 패턴 (Record Patterns)** | `if (obj instanceof MallCredentials(String id, String pw))` 분해까지 |
| **Sequenced Collections** | `getFirst()`, `getLast()` 순서 컬렉션 표준화 |

**업그레이드 트레이드오프 (단점/비용)**
- **호환성 깨짐**: 11에서 잘 돌던 라이브러리/문법이 deprecated·제거됨 (예: 일부 `javax` 패키지).
- **의존성 줄줄이 업그레이드**: Spring·빌드 도구·라이브러리 버전 동반 상승.
- **테스트 비용**: 전체 회귀 테스트로 "안 깨졌나" 검증 필요.
- **운영 리스크**: JVM 동작(GC 등)이 미묘하게 달라져 성능 특성 변화 가능.

> **면접 예상 질문:** Java 메이저 버전 업그레이드(11 → 21)의 이점과 감수해야 할 비용·리스크를 트레이드오프 관점에서 설명해 보세요.

---

## 학습 정리

- `record`는 모든 필드를 강제로 `final`(Kotlin `val`)로 만드는 **불변 데이터 캐리어** → 멀티스레드에서 경쟁 상태 없이 스레드 세이프.
- `-parameters`는 컴파일 시 파라미터 **이름을 `.class`에 보존** → Spring이 **리플렉션**으로 읽어 `@RequestParam` 등을 매핑.
- 패턴 매칭 `instanceof`는 **타입 검사 + 변수 바인딩을 한 번에** 처리 → 코드 간결 + 검사/형변환 타입 불일치 버그(`ClassCastException`) 원천 차단.
- `record`·패턴 매칭·텍스트 블록은 모두 Java 16 전후 도입 → **11 → 21 업그레이드**로 비로소 사용 가능해진 기능.
- 업그레이드는 간결한 문법·성능 이점이 크지만, **호환성 검증·의존성 상승·회귀 테스트·운영 리스크**라는 트레이드오프를 동반.
