# OOP 추상화와 디자인 패턴

> 날짜: 2026-04-09

## 내용

### Strategy 패턴

전체 흐름은 동일하지만 세부 구현이 다를 때, 알고리즘(전략)을 인터페이스로 분리하여 런타임에 교체 가능하도록 만드는 패턴이다.

- **적용 기준**: 큰 흐름은 같고, 세부 계산 방식만 다른 경우
- **구현 방식**: 전략을 인터페이스로 정의하고, 각 구현체가 세부 로직을 담당
- **Context**는 전략 구현체에 의존하며, 전략을 직접 알 필요 없이 인터페이스 메서드만 호출

```java
public interface LimitStrategy {
    long calculate(LimitRequest request);
}

public class RateBasedLimitStrategy implements LimitStrategy {
    public long calculate(LimitRequest request) { ... }
}

public class AmountBasedLimitStrategy implements LimitStrategy {
    public long calculate(LimitRequest request) { ... }
}
```

> **면접 예상 질문:** Strategy 패턴을 선택한 설계적 근거는? if-else 제거 외에 어떤 이점이 있는가?

---

### Strategy vs Template Method 트레이드오프

두 패턴 모두 "공통 흐름 + 세부 구현 분리" 문제를 해결하지만 방식이 다르다.

| | Strategy | Template Method |
|---|---|---|
| 구현 방식 | 인터페이스 (조합) | 추상 클래스 (상속) |
| 다중 상속 | 가능 | 불가능 |
| 유연성 | 런타임 교체 가능 | 컴파일 타임에 결정 |
| 적합한 상황 | 전략이 자주 바뀌는 경우 | 전체 흐름이 고정된 경우 |

로직이 자주 바뀔 가능성이 있는 경우 인터페이스 기반의 Strategy 패턴이 더 유연한 설계를 가능하게 한다.

> **면접 예상 질문:** Strategy 패턴과 Template Method 패턴의 트레이드오프를 설명하고, 각각 어떤 상황에 적합한가?

---

### OCP (Open-Closed Principle)

> "확장에는 열려 있고, 기존 코드 수정에는 닫혀 있어야 한다."

Strategy 패턴은 OCP를 자연스럽게 충족한다. 새로운 계산 방식이 추가될 때 기존 코드를 수정하지 않고 새로운 전략 클래스만 추가하면 된다.

단, 전략을 선택하는 Context(분기 코드) 쪽은 수정이 필요할 수 있으므로, OCP를 완전히 준수한다고 단정하지 않는 것이 정확하다.

> **면접 예상 질문:** OCP를 실무에서 적용한 경험이 있나요? 새로운 요구사항 추가 시 기존 코드를 수정하지 않을 수 있었나요?

---

### 캡슐화 (Encapsulation)

캡슐화는 단순히 `private`을 쓰는 것 이상이다. **내부 구현은 숨기고, 외부에는 인터페이스(메서드)만 노출**하는 것이 핵심이다.

- Strategy 패턴에서 각 전략의 내부 계산 로직은 외부에서 직접 접근 불가
- 외부(Context)는 인터페이스 메서드만 호출하므로, 구현이 바뀌어도 호출부는 변경 불필요
- **포트폴리오 표현**: "Strategy 패턴 적용으로 계산 로직을 캡슐화하여 외부 의존성 차단"

> **면접 예상 질문:** 캡슐화를 의식하며 설계한 경험이 있나요? private 필드 선언 외에 어떤 방식으로 적용했나요?

---

### GC와 Stop-The-World

GC는 Heap 영역에서 참조되지 않는 객체를 제거하는 역할을 하는데, 이 과정에서 애플리케이션 실행을 잠시 멈추는 현상을 **Stop-The-World(STW)** 라고 한다.

금융 서비스처럼 응답 속도가 중요한 환경에서 STW가 발생하면:

1. 응답 지연 발생
2. 사용자가 에러로 오해하여 재시도
3. 재시도로 인한 트래픽 폭증
4. 성능 악화 악순환

GC 종류별로 STW 시간이 다르며, G1GC, ZGC 등은 STW를 최소화하도록 설계되었다.

> **면접 예상 질문:** JVM의 Stop-The-World란 무엇이고, 대용량 트래픽 환경에서 어떤 문제를 일으킬 수 있는가?

---

## 학습 정리

- Strategy 패턴은 동일한 흐름에서 세부 구현이 다를 때 인터페이스로 전략을 분리하는 패턴
- Template Method(상속)보다 Strategy(조합)가 다중 구현과 유연성 면에서 유리한 경우가 많음
- OCP 적용 시 Context의 분기 코드 수정 여부까지 함께 검토해야 완전한 준수 여부를 말할 수 있음
- 캡슐화의 핵심은 내부 구현 은닉 + 인터페이스만 노출
- STW는 응답 지연 → 재시도 → 트래픽 폭증의 악순환으로 이어질 수 있음

## 참고

- 혼자 공부하는 컴퓨터 구조 + 운영체제 (강민철 저)
