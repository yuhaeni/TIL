# Java record vs Kotlin data class

> 날짜: 2026-04-24

## 내용

### 불변성(Immutability) 차이

| 구분 | Java `record` | Kotlin `data class` |
|---|---|---|
| 필드 선언 | 자동으로 `private final` | `val` / `var` 선택 |
| 불변 여부 | **무조건 불변** | `val`이면 불변, `var`이면 가변 |

```java
// Java record — 모든 필드 private final, 재할당 불가
public record Person(String name, int age) {}
```

```kotlin
// Kotlin data class — val/var로 가변성 선택
data class PersonImmutable(val name: String, val age: Int)  // 불변
data class PersonMutable(var name: String, var age: Int)    // 가변 (setter 생성)
```

**핵심:** `record`는 언어 차원에서 불변성을 강제, `data class`는 개발자가 선택.

> **면접 예상 질문:** `record`와 `data class`의 가변성 차이는? 어느 쪽이 더 엄격한 불변성을 보장하는가?

---

### 자동 생성 메서드

| 메서드 | Java `record` | Kotlin `data class` |
|---|---|---|
| `equals()` | ✅ | ✅ |
| `hashCode()` | ✅ | ✅ |
| `toString()` | ✅ | ✅ |
| `copy()` | ❌ | ✅ |

**`copy()` 차이 — 필드 일부 변경 시 편의성:**

```kotlin
// Kotlin — 한 줄
val newPerson = oldPerson.copy(age = 30)
```

```java
// Java — 모든 필드 직접 나열
Person newPerson = new Person(oldPerson.name(), 30);
```

필드가 많아질수록 격차가 커진다. Kotlin의 명명 인자(named argument) + `copy()` 조합이 불변 객체 업데이트 UX를 크게 개선.

> **면접 예상 질문:** Kotlin `data class`의 `copy()`가 해결하는 문제는? Java `record`로 같은 효과를 내려면?

---

### 상속 관련

| 구분 | Java `record` | Kotlin `data class` |
|---|---|---|
| 암묵적 `final` | ✅ | ✅ |
| 상속 받기 | ❌ (상속 불가) | ❌ (상속 불가) |
| 인터페이스 구현 | ✅ | ✅ |

두 언어 모두 **상속 불가능**한 `final` 클래스로 강제한다. 값 기반 객체의 의미 보호(equals/hashCode 일관성)를 위해서다.

> **면접 예상 질문:** 값 객체(Value Object)를 `final`로 강제하는 이유는?

---

### JPA Entity를 data class로 만들면 안 되는 이유

Kotlin 프로젝트에서 `data class` + `@Entity` 조합은 **지뢰밭**이다. 두 가지 중대 문제가 있다.

**이유 1 — `final`이라 프록시 상속 불가**

JPA의 LAZY 로딩은 **프록시 객체**를 통해 동작한다. 프록시는 엔티티 클래스를 **상속**해서 생성되는데, `data class`는 `final`이라 상속이 불가능하다.

```
LAZY 로딩 → 프록시 생성 시도 → 상속 불가 → 프록시 생성 실패 → LAZY 작동 안 함
```

Kotlin에서는 `kotlin-allopen` 플러그인 + `kotlin-jpa` 플러그인으로 `@Entity`에 자동 `open`을 붙여 우회할 수 있지만, `data class` 자체는 여전히 권장되지 않는다.

**이유 2 — `equals`/`hashCode`/`toString`이 모든 필드 사용**

**문제 A — N+1 쿼리 폭발:**
```kotlin
entities.forEach { println(it.toString()) }
// toString() 내부에서 LAZY 컬렉션 접근
// → 엔티티마다 추가 SELECT → N+1 발생
```

**문제 B — `LazyInitializationException`:**
```kotlin
val entity = repository.findById(1L)  // 트랜잭션 종료
println(entity.toString())            // LAZY 컬렉션 접근
// → 세션 없음 → LazyInitializationException!
```

**결론: JPA 엔티티는 일반 `class`로 선언.** `equals`/`hashCode`는 식별자(`id`) 기반으로 직접 오버라이드하고, `toString`에서 LAZY 필드 접근을 피한다.

> **면접 예상 질문:** Kotlin `data class`를 JPA 엔티티로 쓰면 생기는 문제 두 가지는? `toString()`이 왜 위험한가?

---

### N+1 문제와 LazyInitializationException 짝 이해하기

두 문제는 **"자동 생성 메서드가 LAZY 필드를 건드린다"** 는 공통 원인에서 출발한다.

| 문제 | 발생 시점 | 원인 |
|---|---|---|
| **N+1** | 트랜잭션 **안** | LAZY 컬렉션 접근 시마다 SELECT 발생 |
| **LazyInitializationException** | 트랜잭션 **밖** | 세션이 닫혀 LAZY 초기화 불가 |

`toString()`/`equals()`/`hashCode()`가 **모든 필드를 순회**하므로, LAZY 컬렉션이 섞여 있으면 둘 다 의도치 않게 튀어나온다. 그래서 JPA 엔티티는 자동 생성 메서드에 의존하지 않는 것이 안전하다.

> **면접 예상 질문:** N+1과 `LazyInitializationException`의 공통 원인과 차이점은?

---

### 선택 가이드 — 언제 뭘 쓸까?

| 상황 | 추천 |
|---|---|
| Java DTO (응답 객체, 불변) | **Java `record`** |
| Kotlin DTO (불변) | **`data class`(val)** |
| Kotlin DTO (가변이 필요) | `data class`(var) — 드물게만 |
| **JPA 엔티티** | **일반 `class`** (data class 금지) |
| Builder 패턴 필요한 복잡 객체 | 일반 `class` + `@Builder` (Lombok) |

**원칙:**
- **값 기반(Value)** → `record` / `data class`
- **식별자 기반(Entity)** → 일반 `class` + 식별자 기반 `equals`/`hashCode`

> **면접 예상 질문:** DTO와 Entity의 설계 원칙이 다른 이유는? 각각에 어울리는 Kotlin/Java 구조는?

---

## 학습 정리

- `record`는 **무조건 불변**, `data class`는 `val`/`var`로 가변성 선택 가능
- `data class`는 `copy()`로 일부 필드만 변경한 새 객체 생성이 쉬움, `record`는 모든 필드 직접 나열 필요
- 두 타입 모두 **`final`이라 상속 불가** — 값 객체의 의미 보호
- **JPA 엔티티에 `data class` 금지** — `final` 때문에 프록시 생성 실패 + 자동 메서드가 LAZY 필드 건드림
- `toString`/`equals`/`hashCode`가 LAZY 필드 접근 시 트랜잭션 안에선 **N+1**, 밖에선 **`LazyInitializationException`**
- JPA 엔티티는 일반 `class`로 선언하고 `equals`/`hashCode`는 **식별자(`id`) 기반**으로 직접 정의
- 값 기반(Value)은 `record`/`data class`, 식별자 기반(Entity)은 일반 `class` — 설계 원칙 분리

## 참고

- Java Language Specification — Records
- Kotlin 공식 문서 — Data classes
- Hibernate 프록시와 LAZY 로딩 메커니즘
- `kotlin-allopen`, `kotlin-jpa` 플러그인 문서
