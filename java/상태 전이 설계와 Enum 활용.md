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

### EnumSet vs HashSet

상태 전이 가능 목록을 표현할 때 `HashSet` 대신 `EnumSet`을 사용하는 이유:

- **성능**: EnumSet은 내부적으로 비트마스크로 구현되어 `contains()` 연산이 비트 AND 하나로 끝남. HashSet은 해시값을 계산해야 하므로 EnumSet이 더 빠르고 메모리도 효율적
- **타입 안전성**: Enum 상수만 받으므로 컴파일 타임에 잘못된 값 삽입을 방지
- **의도 표현(Self-documenting Code)**: "이 Set은 Enum 값들의 집합이다"라는 의도가 코드에서 명확히 드러남

**Set vs List 선택 이유:**

상태 전이 가능 목록은 순서도 없고 중복도 의미 없으므로 개념적으로 집합(Set)이 맞는 표현이다. 클린 코드 관점에서 자료구조 선택 자체로 의도를 표현할 수 있다.

> **면접 예상 질문:** EnumSet을 사용한 이유는? Set.of()나 HashSet과의 차이는?

---

### boolean 반환 vs 예외 던지기

`canTransitionTo()`의 반환 타입을 어떻게 설계할지는 호출 목적에 따라 달라진다.

| | boolean 반환 | 예외 던지기 |
|---|---|---|
| 장점 | 호출부가 유연하게 처리 가능 | 잘못된 전이를 강제로 차단 |
| 단점 | 검증을 빠뜨릴 위험 | try-catch 필요 |
| 적합한 상황 | UI 버튼 활성화 여부 표시 등 조회용 | 상태 변경 로직 (변경용) |

**설계 판단 기준:**

- **UI가 있는 경우**: `canTransitionTo()` (boolean, 조회용) + `transitionTo()` (예외, 변경용)로 두 메서드를 분리
- **백엔드 파이프라인만 있는 경우**: 잘못된 전이는 무조건 막아야 하므로 예외 던지기가 적절

핵심: **기획(요구사항)이 설계를 결정한다.**

> **면접 예상 질문:** `canTransitionTo()`가 boolean을 반환하는 설계의 트레이드오프는? 어떤 상황에서 예외를 던지는 설계가 더 적합한가?

---

## 학습 정리

- 상태 전이 규칙을 enum 내부에 두면 응집도가 높아지지만, 비즈니스 규칙이 다양해지면 외부로 빼는 게 유리
- EnumSet은 비트마스크 기반으로 HashSet보다 빠르고, 코드의 의도를 명확하게 표현
- boolean 반환(조회용)과 예외 던지기(변경용)를 분리하는 설계가 UI가 있는 경우 적합
- 자료구조와 반환 타입 선택도 요구사항에서 출발하는 설계 결정

## 참고

- `OrderStatus` enum의 상태 전이(Transition) 설계 기반
