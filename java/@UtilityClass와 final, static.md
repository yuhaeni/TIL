# @UtilityClass와 final, static

> 날짜: 2026-04-20

## 내용

### @UtilityClass (Lombok)

Lombok의 `@UtilityClass`는 "상태 없는 유틸리티 클래스" 패턴을 한 번에 적용해준다.

**자동 처리 내용:**
- 클래스에 `final` 부여 → **상속 방지**
- `private` 기본 생성자 자동 생성 → **인스턴스화 방지**
- 모든 필드/메서드를 **`static`으로 자동 변환**

**Before (수동 작성):**
```java
public final class MoneyUtil {
    private static final int SCALE = 0;
    private static final RoundingMode ROUNDING_MODE = RoundingMode.HALF_UP;

    private MoneyUtil() {} // 인스턴스화 방지

    public static BigDecimal multiply(BigDecimal amount, BigDecimal rate) {
        return amount.multiply(rate).setScale(SCALE, ROUNDING_MODE);
    }
}
```

**After (`@UtilityClass`):**
```java
@UtilityClass
public class MoneyUtil {
    private final int SCALE = 0;  // static이 자동 부여됨
    private final RoundingMode ROUNDING_MODE = RoundingMode.HALF_UP;

    public BigDecimal multiply(BigDecimal amount, BigDecimal rate) {
        return amount.multiply(rate).setScale(SCALE, ROUNDING_MODE);
    }
}
```

| 구분 | 장점 | 단점 |
|---|---|---|
| `@UtilityClass` | 간편, `final`/`private 생성자`/`static` 누락 방지 | Lombok 내부 동작이 보이지 않아 학습/디버깅 부담 |
| 직접 작성 | 동작이 명시적, 가독성·학습 친화적 | 매번 반복 작성 → 실수 가능성 |

**선택 기준:**
- 팀이 Lombok에 익숙하고 유틸 클래스가 많다 → `@UtilityClass`
- 학습용/신규 팀원 많음 → 직접 작성

> **면접 예상 질문:** `@UtilityClass`가 자동으로 해주는 일은 무엇인가? 직접 작성과 비교한 트레이드오프는?

---

### final 키워드 — 위치별 의미

`final`은 붙는 위치에 따라 완전히 다른 의미를 갖는다.

| 위치 | 의미 |
|---|---|
| 변수 앞 | 값 변경 불가 (상수화) |
| **클래스 앞** | **상속 불가 (`extends` 금지)** |
| 메서드 앞 | 오버라이딩 불가 |

**유틸리티 클래스에 `final`을 붙이는 이유:**

`private` 생성자만으로는 인스턴스화를 완전히 막지 못한다. 누군가 상속하면 자식 클래스에서 **public 생성자를 열어버릴 수 있기 때문**이다.

```java
public class MoneyUtil {
    private MoneyUtil() {}  // 인스턴스화 방지? 아직 부족!
}

// 상속으로 우회 가능
public class MoneyUtilHack extends MoneyUtil {
    public MoneyUtilHack() {}  // public 생성자 열어버림!
}
```

→ `final`로 **상속 자체를 차단**해야 완전한 유틸리티 클래스가 된다.

> **면접 예상 질문:** 유틸리티 클래스에 `private` 생성자만 있으면 왜 부족한가? `final`이 왜 필요한가?

---

### static 키워드

`static`은 "인스턴스가 아닌 **클래스 자체**에 속한다"는 의미다.

**특징:**
- 클래스가 **로딩되는 시점**에 메모리에 올라감 (`new`보다 먼저)
- 인스턴스 없이 `클래스명.메서드()` 형태로 호출 가능
- 프로그램 종료 시까지 메모리에 유지

**유틸리티 클래스에서 `static`을 쓰는 이유:**
- 상태(state)가 없고 단순 계산만 하므로 인스턴스를 만들 필요 없음
- 호출부가 깔끔: `MoneyUtil.multiply(amount, rate)`
- 이미 Method Area에 올라가 있어 **추가 메모리 낭비 없음**

**단점:**
- 프로그램 종료까지 메모리 점유 → 무거운 객체라면 부담
- 하지만 `MoneyUtil`처럼 필드 2~3개 수준이면 **영향 미미**

> **면접 예상 질문:** `static` 메서드는 언제 메모리에 올라가는가? 유틸리티 클래스에서 `static`을 쓰는 이유는?

---

### JVM 메모리 영역 — Method Area vs Heap

`static`과 `new`의 차이를 이해하려면 JVM 메모리 구조를 알아야 한다.

| 영역 | 저장 대상 | 생성 시점 | 공유 여부 |
|---|---|---|---|
| **Method Area** | 클래스 메타데이터, **`static` 필드/메서드**, 상수 풀 | 클래스 로딩 시 | 모든 스레드 공유 |
| **Heap** | `new`로 만든 **인스턴스**, 배열 | 런타임(`new` 시점) | 모든 스레드 공유 (GC 대상) |
| **Stack** | 지역 변수, 메서드 호출 프레임 | 메서드 호출 시 | 스레드별 독립 |
| **PC Register** | 현재 실행 중인 JVM 명령어 주소 | 스레드 생성 시 | 스레드별 독립 |
| **Native Method Stack** | 네이티브 메서드 호출 정보 | 네이티브 호출 시 | 스레드별 독립 |

```
[클래스 로딩 시]
MoneyUtil.class의 메타데이터 + static 필드/메서드 → Method Area

[런타임]
new Order(...) → Heap
order 참조 변수 → Stack
```

**핵심 차이:**
- `static` 멤버는 **클래스당 1벌** → Method Area에 로딩 시 1회 생성
- 인스턴스 멤버는 **객체당 1벌** → `new` 할 때마다 Heap에 생성

> **면접 예상 질문:** JVM 메모리 영역에는 무엇이 있는가? `static` 필드와 인스턴스 필드는 각각 어디에 저장되는가?

---

### @UtilityClass의 세 요소가 모두 필요한 이유

유틸리티 클래스는 `final` + `private 생성자` + `static`이 **모두** 필요하다. 하나라도 빠지면 의도가 훼손된다.

| 요소 | 빠졌을 때 문제 |
|---|---|
| `final` | 상속으로 public 생성자 우회 → 인스턴스화 가능 |
| `private` 생성자 | 외부에서 `new MoneyUtil()` 가능 |
| `static` | 인스턴스 없이 호출 불가 → 애초에 "유틸"이 아님 |

세 요소가 함께 작동해야 **"인스턴스 없이 호출만 가능한 클래스"** 라는 유틸리티 패턴이 완성된다. `@UtilityClass`는 이 세 요소를 한 번에 챙겨주는 장치다.

> **면접 예상 질문:** 유틸리티 클래스 설계 시 `final`, `private 생성자`, `static` 중 하나를 뺀다면 어떤 문제가 생기는가?

---

## 학습 정리

- `@UtilityClass`는 **`final` + `private 생성자` + 모든 멤버 `static`** 을 자동 적용하는 Lombok 어노테이션
- `final`은 위치별 의미가 다름 — 클래스에 붙으면 **상속 차단**, 유틸 클래스에 필수
- `private` 생성자만으로는 상속 우회가 가능하므로 `final`과 함께 써야 인스턴스화를 완전 차단
- `static` 멤버는 **Method Area**에 로딩 시 1회 생성되어 모든 인스턴스가 공유
- `new`로 만든 인스턴스는 **Heap**에 생성되고 GC 대상이 됨
- 유틸리티 클래스의 세 요소(`final`/`private 생성자`/`static`)는 **서로 보완**하는 관계 — 하나만 빠져도 패턴 성립 안 함

## 참고

- CarrotSettle (Java, Spring Boot 4.0.x) `MoneyUtil` 설계 기반 학습
- Lombok `@UtilityClass` 공식 문서
- JVM Specification — Run-Time Data Areas
