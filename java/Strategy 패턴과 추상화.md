# Strategy 패턴과 추상화

> 날짜: 2026-04-10

## 내용

### 추상 클래스 vs 인터페이스

| 항목 | 추상 클래스 | 인터페이스 |
|---|---|---|
| 상속/구현 | 단일 상속 (`extends`) | 다중 구현 (`implements`) |
| 필드 | 일반 인스턴스 필드 가능 | 자동 `public static final` (상수) |
| 메서드 구현 | 일반 메서드 + 추상 메서드 | `default` 메서드 + `abstract` 메서드 |
| 인스턴스화 | 불가능 | 불가능 |

추상 클래스가 인스턴스화 불가능한 이유: 구현부가 없는 추상 메서드가 최소 하나 이상 존재하는데, 추상 메서드를 호출하면 에러가 나므로 컴파일 시점에 인스턴스화 자체를 막아버린다.

Strategy 패턴에서 인터페이스를 선택하는 이유는 "기능 추가"가 아니라 **설계 방식의 선택**이다. 향후 `Loggable`, `Auditable` 같은 다른 인터페이스와 함께 구현해야 하는 상황이 생겼을 때, 추상 클래스였으면 단일 상속 제약 때문에 구조 자체를 뜯어고쳐야 하는 리스크가 있다. 인터페이스는 비용 없이 유연성을 확보하는 선택이다.

> **면접 예상 질문:** Strategy 패턴 구현 시 추상 클래스 대신 인터페이스를 선택한 결정적인 이유는?

---

### `abstract` 메서드와 `default` 메서드 구분 기준

| 종류 | 역할 | 기준 |
|---|---|---|
| `abstract` 메서드 | 전략마다 달라지는 상세 계산 | 구현체마다 다를 때 |
| `default` 메서드 | 모든 Strategy가 공유하는 공통 로직 | 변하지 않는 공통 흐름일 때 |

`default` 메서드는 다중 구현이 가능한 인터페이스에 구현부를 넣을 수 있다는 점이 추상 클래스 일반 메서드와의 차이다. 추상 클래스는 단일 상속이라 하나만 재사용 가능하지만, `default` 메서드는 여러 인터페이스의 공통 로직을 동시에 재사용할 수 있다.

```java
public interface LimitStrategy {
    // 전략마다 달라지는 로직 → abstract
    long calculateRate(LimitRequest request);
    long calculateAmount(LimitRequest request);

    // 공통 계산 흐름 → default
    default long calculateBase(LimitRequest request) {
        return request.getSalary() * 12;
    }
}
```

> **면접 예상 질문:** 인터페이스의 `abstract` 메서드와 `default` 메서드를 어떤 기준으로 구분하는가?

---

### 인터페이스의 규격 역할

인터페이스는 `implements`를 강제하여 팀원이 새로운 Strategy 클래스를 추가할 때 기존 규격에 맞는 개발을 하도록 유도한다. 컴파일 시점에 IDE가 미구현 메서드를 바로 잡아주기 때문에 런타임 버그를 예방할 수 있다.

- 추상 클래스 → **상속 (extends)**
- 인터페이스 → **구현 (implements)**

> **면접 예상 질문:** 인터페이스가 팀 개발에서 어떤 "규격" 역할을 하는가?

---

### Constant Interface 안티패턴과 상수 관리

인터페이스에 상수만 모아두는 **Constant Interface 패턴은 안티패턴**이다. 인터페이스 본래 목적인 '구현 강제 규격'을 벗어나 단순 상수 저장소로 오용되기 때문이다.

올바른 상수 관리 방법:

| 방법 | 사용 시점 |
|---|---|
| `enum` | 관련된 상수들을 타입 안전하게 묶을 때 |
| `final class` + `private 생성자` | 단순 상수 모음일 때 |

```java
// ❌ Constant Interface 안티패턴
public interface LimitConstants {
    int MAX_LIMIT = 100_000_000;
}

// ✅ enum 활용
public enum LimitType {
    RATE, AMOUNT;
}

// ✅ final class 활용
public final class LimitConstants {
    private LimitConstants() {}
    public static final int MAX_LIMIT = 100_000_000;
}
```

> **면접 예상 질문:** 공통 상수값을 인터페이스에 두는 것이 왜 안티패턴인가? 대안은?

---

## 학습 정리

- 추상 클래스(단일 상속)보다 인터페이스(다중 구현)가 Strategy 패턴에 적합한 이유 이해
- `abstract`는 구현체마다 다른 로직, `default`는 공통 로직에 사용하는 기준 파악
- 인터페이스가 컴파일 시점에 팀 개발의 규격을 강제하는 역할 이해
- Constant Interface 안티패턴과 enum / final class 대안 정리

## 추가 학습 필요

- `final class` 개념 및 활용
- Template Method 패턴과 Strategy 패턴의 차이 심화 학습
- 테스트 없는 레거시 코드 리팩토링 안전 전략

## 참고

- 이력서 "가독성 향상을 위해 Strategy 패턴을 활용한 대출 한도 계산 로직 리팩토링" 항목 기반
