# 상태 전이 설계와 Enum 활용

> 날짜: 2026-04-13

## 내용

### 상태 전이 규칙을 enum 내부에 정의하는 이유

상태와 전이 규칙을 한 곳에 모아 **응집도(Cohesion)** 를 높이기 위함이다. `canTransitionTo()`가 enum 안에 있으면 `PAID`라는 상태가 스스로 자신이 어디로 전이할 수 있는지 알 수 있다.

```java
public enum OrderStatus {
    PENDING {
        @Override
        public boolean canTransitionTo(OrderStatus next) {
            return EnumSet.of(PAID, CANCELLED).contains(next);
        }
    },
    PAID {
        @Override
        public boolean canTransitionTo(OrderStatus next) {
            return EnumSet.of(SHIPPED, CANCELLED).contains(next);
        }
    };

    public abstract boolean canTransitionTo(OrderStatus next);
}
```

**트레이드오프: 응집도 vs 유연성**

| | enum 내부 | 외부 서비스 |
|---|---|---|
| 응집도 | 높음 | 낮음 |
| 유연성 | 규칙이 고정됨 | 환경마다 다른 규칙 적용 가능 |
| 적합한 상황 | 규칙이 단순하고 변하지 않을 때 | 일반 주문 vs 구독 주문처럼 규칙이 달라질 때 |

> **면접 예상 질문:** 상태 전이 규칙을 enum 내부에 정의한 이유와 트레이드오프는?

---

### EnumSet의 비트마스크 동작 원리

EnumSet은 enum의 선언 순서(`ordinal`)를 비트 자릿수로 매핑한다. 각 상태의 포함 여부를 0/1로 나타낸다.

```
CREATED  = 0 → 00001
PAID     = 1 → 00010
CONFIRMED= 2 → 00100
SETTLED  = 3 → 01000
REFUNDED = 4 → 10000
```

`contains()` 동작 원리: `EnumSet.of(CONFIRMED, REFUNDED)` → `10100`

```
  10100  (EnumSet)
AND 00100  (CONFIRMED)
= 00100  → 0이 아니므로 포함됨!
```

비트 AND 연산 하나로 포함 여부를 확인하므로 HashSet보다 훨씬 빠르다.

> **면접 예상 질문:** EnumSet의 비트마스크 동작 원리를 설명하시오.

---

### HashSet 내부 구조와 contains() 동작 과정

HashSet은 내부적으로 `HashMap<E, Object>`을 갖고 있다. 값을 Key로, 더미 객체(`PRESENT`)를 Value로 저장하며, `contains()`는 결국 `HashMap.containsKey()`를 호출한다.

```java
public class HashSet<E> extends AbstractSet<E> implements Set<E> {
    transient HashMap<E, Object> map;
    static final Object PRESENT = new Object();

    public boolean contains(Object o) {
        return this.map.containsKey(o);
    }
}
```

`HashSet.contains()` → `HashMap.containsKey()` → 해시값 계산 → 버킷 찾기 → equals 비교

**EnumSet vs HashSet 비교**

| | EnumSet | HashSet |
|---|---|---|
| 내부 구조 | 비트마스크 (long) | HashMap |
| `contains()` | 비트 AND 연산 하나 | 해시 계산 → 버킷 탐색 → equals 비교 |
| 메모리 | long 하나 (64비트) | HashMap 전체 구조 |
| 타입 제한 | Enum 전용 | 아무 객체나 가능 |

> **면접 예상 질문:** HashSet의 내부 구조는? `contains()`가 동작하는 과정은?

---

### Set.of() vs EnumSet.of()

| | `Set.of()` | `EnumSet.of()` |
|---|---|---|
| 수정 가능 여부 | 불변 (`add` 시 `UnsupportedOperationException`) | 수정 가능 |
| 타입 제한 | 제네릭 (아무 타입) | Enum 전용 |
| 의도 표현 | 범용 Set | "이것은 Enum 집합이다" 명시 |
| 성능 | 일반적 | 비트 연산 기반으로 빠름 |

`TRANSITIONS`가 `static final`이라 초기화 후 변경이 없으면 `Set.of()`도 기능상 문제없다. 그럼에도 `EnumSet`을 선택하는 이유는 **Self-documenting Code** (Enum 전용 집합이라는 의도 표현) + 성능이다.

상태 전이 가능 목록은 순서도 없고 중복도 의미 없으므로 개념적으로 집합(Set)이 맞는 표현이다. 자료구조 선택 자체로 의도를 표현하는 것이 클린 코드 관점에서 중요하다.

> **면접 예상 질문:** `Set.of()`와 `EnumSet.of()`의 차이는? EnumSet을 선택하는 이유는?

---

### boolean 반환 vs 예외 던지기

`canTransitionTo()`의 반환 타입 설계는 호출 목적에 따라 달라진다.

| | boolean 반환 | 예외 던지기 |
|---|---|---|
| 장점 | 호출부가 유연하게 처리 가능 | 잘못된 전이를 강제로 차단 |
| 단점 | 검증을 빠뜨릴 위험 | try-catch 필요 |
| 적합한 상황 | UI 버튼 활성화 여부 표시 등 조회용 | 상태 변경 로직 (변경용) |

- **UI가 있는 경우**: `canTransitionTo()` (boolean, 조회용) + `transitionTo()` (예외, 변경용)로 분리
- **백엔드 파이프라인만 있는 경우**: 잘못된 전이는 무조건 막아야 하므로 예외 던지기가 적절

핵심: **기획(요구사항)이 설계를 결정한다.**

> **면접 예상 질문:** `canTransitionTo()`가 boolean을 반환하는 설계의 트레이드오프는? 어떤 상황에서 예외를 던지는 설계가 더 적합한가?

---

## 학습 정리

- 상태 전이 규칙을 enum 내부에 두면 응집도가 높아지지만, 비즈니스 규칙이 다양해지면 외부로 빼는 게 유리
- EnumSet은 ordinal 기반 비트마스크로 동작하여 `contains()`가 비트 AND 연산 하나로 끝남
- HashSet은 내부적으로 `HashMap`을 사용하므로 해시 계산 + 버킷 탐색 + equals 비교 과정이 필요
- `Set.of()`는 불변, `EnumSet`은 수정 가능 + Enum 전용으로 의도 표현에 유리
- boolean 반환(조회용)과 예외 던지기(변경용)를 분리하는 설계가 UI가 있는 경우 적합

## 참고

- `OrderStatus` enum의 상태 전이(Transition) 설계 기반
