# 추상화 — 본질 vs 세부사항, 정보 은닉과의 차이, 추상화의 단점과 Rule of Three

> 날짜: 2026-05-21

## 내용

### 추상화 (Abstraction) — 본질만 남기고 세부는 감춘다

추상화는 **"본질적인 것만 골라서 모델로 만들고, 불필요한 세부사항은 제거하는 행위"** 이다.

#### 일상 비유: 자동차 운전

운전자는 **핸들, 액셀, 브레이크**만 알면 운전할 수 있다. 엔진 내부에서 연료가 어떻게 폭발하고, 피스톤이 어떻게 움직이는지 몰라도 된다.

자동차 설계자가 한 일:
- "운전에 필요한 핵심"만 골라서 **인터페이스(핸들/액셀/브레이크)로 노출**
- 나머지 복잡한 메커니즘은 안쪽에 숨김

> **면접 예상 질문:** 추상화를 한 줄로 정의해보고, 일상 속 예시(자동차, 리모컨 등)로 설명해보세요.

---

### 추상화 vs 정보 은닉 — 같이 쓰이지만 다른 작업

자주 혼동되는 두 개념. 처음에는 "내부 구현을 몰라도 쓸 수 있다"라고 추상화를 설명하기 쉬운데, 그건 사실 **정보 은닉(Information Hiding)** 에 더 가깝다.

| 개념 | 관점 | 던지는 질문 |
|---|---|---|
| **정보 은닉** | 접근 통제 | "이걸 외부에 공개할까, 숨길까?" |
| **추상화** | 모델링 | "무엇이 본질이고, 무엇이 세부사항인가?" |

**작업 순서**: 추상화로 먼저 **본질을 결정** → 정보 은닉으로 **세부를 숨김**.

> **면접 예상 질문:** 추상화와 정보 은닉은 어떻게 다른가요? 두 개념이 같이 적용되는 순서를 설명해보세요.

---

### 결제 시스템 예시 — 본질 추출

카드 결제, 계좌 이체, 카카오페이, 네이버페이는 내부 동작이 모두 다르지만, **모든 결제 수단의 공통 본질**은 "결제를 처리한다" 하나로 환원된다.

```java
interface PaymentMethod {
    PaymentResult pay(int amount);  // 본질적인 행위 하나!
}

class CardPayment implements PaymentMethod {
    public PaymentResult pay(int amount) {
        // 카드사 API 호출, 승인 번호 받기, 한도 체크... 복잡함
    }
}

class KakaoPayPayment implements PaymentMethod {
    public PaymentResult pay(int amount) {
        // OAuth 토큰, QR 생성, 푸시 알림... 또 다름
    }
}

class BankTransferPayment implements PaymentMethod {
    public PaymentResult pay(int amount) {
        // 계좌 검증, 이체 한도, 영업시간 체크... 또 다름
    }
}
```

- **본질 (남긴 것)**: "결제를 처리한다" = `pay(int amount)` 메서드 하나
- **세부사항 (감춘 것)**: 카드 승인, QR, 계좌 검증 같은 구현의 차이

사용처(Service 레이어)는 `paymentMethod.pay(10000)` 한 줄만 호출하면 끝. 각 결제 수단의 복잡함을 신경 쓸 필요가 없다.

> **면접 예상 질문:** 결제 시스템처럼 내부 구현이 다른 여러 모듈을 추상화할 때, 인터페이스에 어떤 메서드를 둘지 어떻게 결정하나요?

---

### 잘못된 추상화 신호 — 인터페이스로 세부사항이 새어 나옴

```java
interface PaymentMethod {
    PaymentResult pay(int amount);
    String getCardCompanyName();        // ❌ 카드 결제에만 의미 있음
    String generateQRCode();            // ❌ 카카오페이/네이버페이에만 의미 있음
    boolean checkBankBusinessHours();   // ❌ 계좌이체에만 의미 있음
}
```

`BankTransferPayment`에게 `getCardCompanyName()`을 물으면 카드사가 아닌데 뭘 반환해야 할까? `null`? 예외? 어느 쪽이든 어색하다.

이게 바로 **"추상화가 깨졌다"** 는 신호. 인터페이스에는 **모든 구현체가 공통으로 가져야 하는 본질**만 두고, **특정 구현체에만 의미 있는 세부사항**은 각 클래스 내부에 private으로 숨겨야 한다.

```java
interface PaymentMethod {
    PaymentResult pay(int amount);  // 본질만 노출
}

class CardPayment implements PaymentMethod {
    private String cardCompany;  // 세부사항은 내부 필드

    public PaymentResult pay(int amount) {
        callCardCompanyAPI(cardCompany, amount);  // 내부에서 활용
    }

    private void callCardCompanyAPI(String company, int amount) { ... }
}
```

> **면접 예상 질문:** 인터페이스 설계 시 어떤 메서드는 인터페이스에 두고 어떤 메서드는 구현체 내부에 둬야 하나요? 잘못된 추상화의 신호는 무엇인가요?

---

### Animal 예시 — 공통은 부모로, 개별은 자식으로

요구사항:
- `Dog`, `Cat`, `Fish`, `Bird` 등이 있음
- 모든 동물 공통: 먹기(eat), 자기(sleep), 이름(name)
- 개별 행동: 짖기(bark, Dog), 헤엄(swim, Fish), 날기(fly, Bird)

#### 1차 설계: 추상 클래스만 사용

```java
abstract class Animal {
    protected String name;  // 모든 동물의 공통 본질

    public Animal(String name) { this.name = name; }

    public void eat() { System.out.println(name + " 먹는다"); }   // 공통
    public void sleep() { System.out.println(name + " 잔다"); }   // 공통
}

class Dog extends Animal {
    public Dog(String name) { super(name); }
    public void bark() { System.out.println("멍멍!"); }  // Dog만의 것
}

class Fish extends Animal {
    public Fish(String name) { super(name); }
    public void swim() { System.out.println("헤엄친다"); }  // Fish만의 것
}

class Bird extends Animal {
    public Bird(String name) { super(name); }
    public void fly() { System.out.println("난다"); }  // Bird만의 것
}
```

> **면접 예상 질문:** 추상화 설계 시 "공통은 부모로, 개별은 자식으로"라는 원칙을 어떤 기준으로 적용하나요?

---

### Duck/Penguin 확장 — "이다"는 추상 클래스, "할 수 있다"는 인터페이스

요구사항 추가:
- 오리(Duck) — 헤엄도 치고 날기도 함
- 펭귄(Penguin) — 헤엄은 치지만 못 남

만약 `Penguin extends Bird`로 설계하면? `Bird`에 `fly()`가 있으니 펭귄도 날아야 하는 모순이 생긴다.

**해결책**: **능력(can-do)을 인터페이스로 분리**해서 다중 구현으로 조합한다.

```java
// 능력(can-do)을 인터페이스로 분리
interface Swimmable {
    void swim();
}

interface Flyable {
    void fly();
}

// Animal은 "이다(is-a)" → 추상 클래스 그대로
abstract class Animal {
    protected String name;
    public Animal(String name) { this.name = name; }
    public void eat() { ... }
    public void sleep() { ... }
}

class Fish extends Animal implements Swimmable { ... }
class Bird extends Animal implements Flyable { ... }
class Duck extends Animal implements Swimmable, Flyable { ... }  // 둘 다!
class Penguin extends Animal implements Swimmable { ... }        // 헤엄만!
```

#### 추상화 설계의 황금률

| 구분 | 의미 | 도구 |
|---|---|---|
| **본질 (~이다)** | Animal | 추상 클래스 (`extends`, 단일) |
| **능력 (~할 수 있다)** | Swimmable, Flyable | 인터페이스 (`implements`, 다중) |

> **면접 예상 질문:** 펭귄이 새지만 날지 못하는 경우처럼 일부 자식만 특정 행동을 못 할 때, 상속만으로 풀면 어떤 문제가 생기고 어떻게 해결하나요?

---

### 추상화의 단점 — Over-engineering과 Rule of Three

5년차 면접관이 가장 좋아하는 질문: *"그럼 추상화의 단점은?"*

#### 1. 코드 복잡도 증가 (Over-engineering)

```java
// 구현체 하나뿐인 인터페이스
interface UserService {
    User findById(Long id);
}
class UserServiceImpl implements UserService { ... }
```

코드 읽는 사람: "어? 구현체가 하나뿐인데 왜 인터페이스를 만들었지?" → 파일 두 개를 왔다 갔다 해야 함. **추적 비용 ↑**

#### 2. 추상화 누수 (Leaky Abstraction)

"본질만 노출"하려 했는데 세부사항이 새어 나오는 경우. 예: `PaymentMethod.pay()`가 카드 결제일 때만 던지는 `CardLimitException`을 호출부에서 알아야 한다면 → 추상화가 깨진 것.

#### 3. 잘못된 추상화 (Premature Abstraction)

미래를 예측해서 "나중에 확장할 수도 있으니까 일단 추상화하자!" 했는데 **결국 그 확장이 안 일어남**. 그동안 추가된 복잡도만 부채로 남는다.

#### 실무 격언: Rule of Three

> **"추상화는 구체적인 케이스가 3번 반복될 때 시작하라"**

- 1번째: 그냥 구현
- 2번째: 비슷한 거 또 나옴. 일단 참기
- 3번째: 패턴이 명확. 이때 추상화

#### 추상화의 장단점 요약

| 장점 | 단점 |
|---|---|
| 응집도 ↑, 결합도 ↓ | 코드 복잡도 ↑ (파일/계층 증가) |
| OCP 만족 → 확장 유연 | 추상화 누수 위험 |
| 본질에만 집중 가능 | 잘못된 추상화는 부채 |

> **면접 예상 질문:** 추상화의 단점은 무엇이며, 언제 추상화를 도입해야 한다고 생각하나요? 모든 클래스를 인터페이스로 분리하는 게 좋을까요?

---

### 면접 답변 종합

> "추상화의 원칙은 공통적인 본질을 인터페이스나 추상 클래스에 선언하고, 구현체별 세부사항은 각 내부에 숨기는 것입니다. 공통 기능이 부모 클래스 내부에 있어 응집도가 높아지고, 호출부는 부모 타입만 의존하므로 결합도가 낮으며, 결과적으로 확장에는 열려 있고 변경에는 닫혀 있는 OCP를 준수하는 구조가 됩니다.
>
> 다만 추상화에는 비용이 있어서, **구현체가 하나뿐일 때나 미래 확장이 불확실할 때는 오히려 코드 복잡도만 늘리는 부채**가 될 수 있습니다. 그래서 저는 **Rule of Three** — 같은 패턴이 3번 반복될 때 추상화를 도입하는 편입니다."

> **면접 예상 질문:** 추상화의 장단점을 모두 포함해서 30초 안에 답변해보세요. (정의 → 효과 → 한계 → 본인의 적용 기준)

---

## 학습 정리

- **추상화는 "본질만 남기고 세부는 감추는" 모델링 행위**이며, "보여줄 것/숨길 것을 결정하는" 정보 은닉과는 관점이 다르다.
- **공통 본질만 인터페이스/추상 클래스에 선언**하고, 특정 구현체에만 의미 있는 메서드가 부모로 새어 나오면 추상화가 깨진 신호다.
- **"~이다(is-a)"는 추상 클래스로, "~할 수 있다(can-do)"는 인터페이스로** 분리하면 Penguin/Duck 같은 변종도 자연스럽게 표현할 수 있다.
- 추상화는 응집도↑·결합도↓·OCP 만족이라는 효과를 가져오지만, **Over-engineering·Leaky Abstraction·Premature Abstraction**이라는 비용도 따른다.
- 실무에서는 **Rule of Three** — 같은 패턴이 3번 반복될 때 추상화를 도입하는 보수적 접근이 권장된다.

## 참고

- `_template.md` 구조 준수
- 선행 학습: `객체 지향 설계 기초 - 캡슐화, 상속·합성, 다형성, OCP, 인터페이스 vs 추상 클래스.md`
- 메모리 학습 기록: `project_oop_design_study.md`
