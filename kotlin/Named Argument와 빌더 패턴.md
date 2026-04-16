# Named Argument와 빌더 패턴

> 날짜: 2026-04-16

## 내용

### Java vs Kotlin Named Argument

Java에는 **named argument(이름 지정 인자)** 문법이 없어서 파라미터를 순서대로 모두 넘겨야 한다.

```java
// Java - 파라미터 순서대로 모두 넘겨야 함
new LinkedHashMap<>(16, 0.75f, true);
// (initialCapacity, loadFactor, accessOrder) 순서 — 순서를 잘못 넘길 위험 있음
```

```kotlin
// Kotlin - named argument 가능
LinkedHashMap<String, Int>(accessOrder = true)
// 필요한 파라미터만 이름으로 지정 가능
```

Kotlin의 named argument 장점:
- 필요한 파라미터만 선택적으로 지정 가능
- 파라미터 순서를 잘못 넘길 위험 없음
- 코드 가독성 향상

> **면접 예상 질문:** Java와 Kotlin의 named argument 차이는? Java에서 이 불편함을 해결하는 방법은?

---

### 빌더 패턴 (Builder Pattern)

파라미터가 많은 객체 생성 시 가독성과 안전성을 높이기 위한 패턴이다.

| 패턴 | 방식 | 적합한 상황 |
|---|---|---|
| 팩토리 메서드 | 한 번에 객체를 만들어 반환 | 파라미터가 적고 단순한 경우 |
| 빌더 패턴 | 단계적으로 설정을 쌓아가다가 `build()`로 생성 | 파라미터가 많고 복잡한 경우 |

```java
// 빌더 패턴 적용 예시
new LinkedHashMapBuilder<String, Integer>()
    .accessOrder(true)
    .build();
```

Java 기본 `LinkedHashMap`에는 빌더가 없으므로, 직접 래퍼 클래스를 만들어야 한다. 내부에서 `new LinkedHashMap<>(capacity, loadFactor, accessOrder)`를 호출하는 `build()` 메서드를 구현하는 방식이다.

**코딩 테스트 vs 실무:**
- 코딩 테스트 → 일반 생성자로 충분 (`new LinkedHashMap<>(16, 0.75f, true)`)
- 실무 → 파라미터가 많고 복잡할 때 빌더 패턴으로 가독성과 안전성 확보

> **면접 예상 질문:** 빌더 패턴과 팩토리 메서드 패턴의 차이는? 빌더 패턴을 사용하는 이유는?

---

## 학습 정리

- Java는 named argument 미지원 → 생성자 파라미터 순서 실수 위험, Kotlin은 named argument로 해결
- 빌더 패턴은 파라미터가 많은 객체 생성 시 단계적으로 설정을 쌓고 `build()`로 생성
- 팩토리 메서드는 단순한 경우, 빌더 패턴은 복잡한 경우에 적합
- 코딩 테스트에서는 일반 생성자, 실무에서는 빌더 패턴 활용

## 참고

- Java `LinkedHashMap` 생성자 파라미터 학습 중 파생
