# 객체 지향 설계 기초 — 캡슐화, 상속·합성, 다형성, OCP, 인터페이스 vs 추상 클래스

> 날짜: 2026-05-21

## 내용

### 캡슐화 (Encapsulation) — 정보 은닉

캡슐화는 단순히 "숨기기"가 아니라 **두 가지가 묶여 있는 개념**이다.

1. **데이터(필드)와 그걸 다루는 로직(메서드)을 한 클래스 안에 같이 둔다**
2. **외부에는 필요한 것만 공개하고, 내부 구현은 숨긴다** → **정보 은닉(Information Hiding)**

#### 왜 데이터와 로직을 묶어야 하는가?

`BankAccount` 클래스가 `balance` 필드만 가지고, 잔액 변경 로직은 `TransferService`, `WithdrawService`, `DepositService` 등 여러 클래스에 흩어져 있다고 가정해보자.

```java
// ❌ 나쁜 예: 로직이 흩어져 있음
class BankAccount {
    public int balance;
}

class TransferService {
    void transfer(BankAccount account, int amount) {
        account.balance -= amount;  // 직접 조작
    }
}
```

이 상태에서 "잔액은 절대 음수가 되면 안 된다"는 규칙이 새로 생기면? **N개 파일을 다 찾아다니며 수정**해야 하고, 한 곳이라도 빠뜨리면 버그가 된다.

반면에 `BankAccount.withdraw()` 안에 로직이 모여 있으면, 규칙이 바뀌어도 **한 곳만** 고치면 끝난다. 이게 **응집도(Cohesion)**가 높다는 의미이다.

#### 정보 은닉의 위력 — 내부 구현 변경에 강함

처음엔 잔액을 원 단위로 저장했다가, 다국가 통화 지원을 위해 내부를 `Map`으로 바꿔야 한다면:

```java
class BankAccount {
    private Map<Currency, Long> balances;  // 통화별로 저장
    public int getBalance() {
        return balances.get(Currency.KRW).intValue();  // 외부엔 똑같이 보임
    }
}
```

`getBalance()`의 시그니처(`int` 반환)만 유지하면 호출부는 한 줄도 안 고쳐도 된다. 만약 `balance`가 `public int`였다면 모든 호출부에서 컴파일 에러가 났을 것이다.

> **면접 예상 질문:** 캡슐화의 장점을 두 가지 키워드(응집도, 정보 은닉)와 함께 설명하고, 정보 은닉이 깨졌을 때 어떤 문제가 발생하는지 구체적인 예시로 답해보세요.

---

### 응집도 (Cohesion) vs 결합도 (Coupling)

좋은 객체 지향 설계의 핵심 원칙: **"High Cohesion, Low Coupling"**

| 개념 | 의미 | 좋은 방향 |
|---|---|---|
| 응집도 (Cohesion) | 한 클래스 안의 것들이 얼마나 관련 있는가 | ↑ 높을수록 좋다 |
| 결합도 (Coupling) | 클래스끼리 얼마나 단단히 묶여 있는가 | ↓ 낮을수록 좋다 |

캡슐화와 응집도/결합도는 **인과 관계**이다 — 캡슐화를 잘 하면 자연스럽게 응집도가 높아지고 결합도가 낮아진다.

> **면접 예상 질문:** 응집도와 결합도는 캡슐화와 어떤 관계인가요? "캡슐화 = 응집도" 라고 말해도 되는지 본인의 답변으로 설명해보세요.

---

### 상속 (Inheritance) — 코드 재사용성과 위험성

**장점**: 코드 재사용성(Reusability) — `Dog extends Animal` 하면 `eat()`, `sleep()` 같은 부모 메서드를 자동으로 획득한다.

**위험성**:
1. 부모의 모든 public 메서드가 자식에게 그대로 노출된다 (원치 않는 것까지)
2. 부모가 바뀌면 자식도 영향받는다 → 강한 결합
3. "is-a" 관계가 진짜로 맞는지 항상 의심해야 한다

#### 안티패턴: Stack extends ArrayList

```java
class Stack<E> extends ArrayList<E> {
    public void push(E item) { add(item); }
    public E pop() { return remove(size() - 1); }
}

Stack<Integer> s = new Stack<>();
s.push(1);
s.push(2);
s.get(0);     // ✅ 쓸 수 있음 — Stack의 LIFO 깨짐
s.remove(0);  // ✅ 쓸 수 있음 — Stack의 LIFO 깨짐
```

Stack은 **LIFO(Last In First Out)** — `push`/`pop`으로만 접근해야 한다. 그런데 `ArrayList`를 상속받는 순간 `get(int)`, `remove(int)` 같은 중간 접근 메서드가 그대로 노출되어 **Stack의 불변식(invariant)이 깨진다**.

그래서 객체 지향에서는 **"상속보다 합성을 선호하라(Composition over Inheritance)"**는 격언이 유명하다.

> **면접 예상 질문:** Stack을 ArrayList로 상속받아 구현하면 어떤 문제가 생기나요? 그리고 그 문제를 어떻게 해결할 수 있나요?

---

### 합성 (Composition) — has-a 관계와 외부 노출 통제

**정의**: 다른 클래스를 **필드로 가지고**, 기능을 빌려 쓰되 **외부 노출은 내가 통제**하는 방식이다.

```java
class Stack<E> {
    private ArrayList<E> list = new ArrayList<>();  // 안에 숨겨둠

    public void push(E item) { list.add(item); }
    public E pop() { return list.remove(list.size() - 1); }
    // get()이나 remove(int)는 내가 안 만들었으니까 외부에서 못 씀!
}
```

상속과 달리, **내가 공개할 메서드만 골라서 만들 수 있다**. ArrayList의 메서드가 자동으로 노출되지 않는다.

#### 합성을 쓰는 3가지 이유

1. **일부 기능만 노출하고 싶을 때** (Stack 예시)
2. **여러 클래스의 기능을 조합하고 싶을 때** — Java는 다중 상속이 안 되지만, 합성은 여러 개 가질 수 있다
3. **"is-a"가 아니라 "has-a" 관계일 때**

#### BankAccount + TransactionLogger 예시

"BankAccount는 TransactionLogger**이다**"? 어색하다. "BankAccount는 TransactionLogger를 **가지고 있다**" — 자연스럽다.

```java
class BankAccount {
    private int balance;
    private TransactionLogger logger;  // 로거를 가지고 있음

    public BankAccount(TransactionLogger logger) {
        this.logger = logger;
    }

    public void deposit(int amount) {
        balance += amount;
        logger.log("ACC-123", "DEPOSIT", amount);
    }
}
```

#### 상속 vs 합성 비교표

| 구분 | 상속 (extends) | 합성 (Composition) |
|---|---|---|
| 관계 | is-a (~이다) | has-a (~를 가지고 있다) |
| 결합도 | 강함 | 약함 |
| 유연성 | 컴파일 타임 고정 | 런타임에 교체 가능 |
| Java 제약 | 단일 상속만 | 여러 개 가질 수 있음 |

> **면접 예상 질문:** 상속과 합성 중 어느 쪽을 우선 고려해야 하나요? "is-a"와 "has-a" 관계로 판단하는 기준을 본인의 예시와 함께 설명해보세요.

---

### 다형성 (Polymorphism) — 업캐스팅과 동적 디스패치

**어원**: poly(여러) + morph(형태) — "여러 형태"

#### 다형성이 없다면?

```java
// 로거 구현체마다 생성자가 따로 필요
public BankAccount(DatabaseLogger logger) { ... }
public BankAccount(ConsoleLogger logger) { ... }
public BankAccount(NoOpLogger logger) { ... }
// 새 로거 추가될 때마다 생성자도 추가해야 함
```

#### 다형성이 있다면?

```java
public BankAccount(TransactionLogger logger) {  // 부모 타입 하나로 다 받음!
    this.logger = logger;
}
```

**업캐스팅(Upcasting)**: 자식 타입을 부모 타입 변수에 담는 것 (자동, 안전) — 다형성의 시작점이다.

```java
TransactionLogger logger = new DatabaseLogger();  // ✅ OK
TransactionLogger logger = new ConsoleLogger();   // ✅ OK
TransactionLogger logger = new NoOpLogger();      // ✅ OK
```

#### 작동 원리 — Dynamic Dispatch (동적 디스패치)

```java
TransactionLogger logger = new DatabaseLogger();  // 변수 타입: 부모, 실제 객체: 자식
logger.log("test");  // 어떤 log()가 호출될까?
```

- **컴파일 타임**: 컴파일러는 "`TransactionLogger`에 `log()` 메서드가 있다"는 것만 확인
- **런타임**: JVM이 **실제 객체(`DatabaseLogger`)**를 보고 → 그 클래스의 `log()`를 호출

한 줄 정리: **"변수의 타입이 아니라, 실제 객체의 타입에 따라 메서드가 결정된다."**

#### 다운캐스팅은 다형성의 원리가 아니다

```java
DatabaseLogger db = (DatabaseLogger) logger;  // 다운캐스팅 (위험)
```

다운캐스팅은 오히려 **다형성을 깨는 경우가 많다**. "이 객체가 진짜로 무슨 타입이지?" 하고 캐스팅하면 다형성의 의미가 없어진다.

#### 동적 디스패치 vs 리플렉션

둘 다 런타임에 동작하지만:
- **동적 디스패치**: JVM이 자동, 가벼움 (다형성의 기본 원리)
- **리플렉션**: 개발자가 명시적으로 `Class.forName()`, `getMethod()` 같은 API로 조회/호출, 무겁고 느림

#### 런타임 개념 정리

- **컴파일 타임**: `.java` → `.class` 변환 시점 (javac)
- **런타임**: JVM이 `.class`를 실행시키는 모든 시점
  - Spring Boot 앱 시작 → 종료까지 **전부 런타임**
  - 앱 시작은 런타임의 시작점일 뿐

> **면접 예상 질문:** 다형성의 작동 원리(동적 디스패치)를 컴파일 타임과 런타임의 차이로 설명해보세요. 그리고 다형성과 리플렉션의 차이는 무엇인가요?

---

### OCP (Open-Closed Principle) — 다형성의 실전 활용

**확장에는 열려 있고, 변경에는 닫혀 있다** (Open for extension, Closed for modification)

새로운 로거 `SlackLogger`를 추가한다고 하면, `BankAccount` 코드는 한 줄도 수정할 필요가 없다:

```java
class SlackLogger implements TransactionLogger {  // 새 자식 클래스만 추가
    public void log(...) { /* Slack에 전송 */ }
}

// 사용처에서 끼워 넣기만 하면 끝
new BankAccount(new SlackLogger());
```

**다형성 → OCP 달성하는 기술적 기반**:
- 업캐스팅 덕분에 부모 타입 하나로 모든 자식을 받을 수 있음
- 동적 디스패치 덕분에 실제 객체에 맞는 메서드가 자동 호출됨
- 결과적으로 기존 코드 변경 없이 새 기능 추가 가능

> **면접 예상 질문:** OCP를 만족시키기 위해 다형성이 어떻게 활용되나요? `TransactionLogger` 같은 부모 타입을 두는 설계가 왜 OCP에 부합하는지 설명해보세요.

---

### 인터페이스 vs 추상 클래스 — 선택 기준

| 항목 | 인터페이스 | 추상 클래스 |
|---|---|---|
| 다중 상속 | ✅ 가능 (`implements A, B, C`) | ❌ 불가 (`extends` 하나만) |
| 인스턴스 필드 | ❌ (상수만 `public static final`) | ✅ 가능 |
| 생성자 | ❌ | ✅ |
| 메서드 구현 | default 메서드만 (Java 8+) | 일반 + 추상 메서드 |
| 관계 의미 | "할 수 있다 (can-do)" | "~이다 (is-a)" |

#### 다이아몬드 문제 — 클래스 다중 상속을 금지하는 이유

```java
class A { void hello() { ... } }
class B { void hello() { ... } }

// 만약 Java가 다중 상속을 허용한다면?
class C extends A, B {
    // c.hello() 호출 시 → A의 hello? B의 hello? 모호함
}
```

클래스는 "구현"을 가지고 있어서 다중 상속하면 충돌이 난다. 인터페이스는 (전통적으로) "구현이 없고 명세만 있어서" 다중 구현해도 충돌이 없다.

#### abstract 키워드

```java
abstract class Account {
    protected int balance;  // 공통 필드

    public void deposit(int amount) { balance += amount; }  // 공통 구현
    public void withdraw(int amount) { balance -= amount; }

    public abstract double calculateInterest();  // 자식이 반드시 구현
}

class SavingsAccount extends Account {
    public double calculateInterest() { return balance * 0.03; }  // 적금: 3%
}

class CheckingAccount extends Account {
    public double calculateInterest() { return balance * 0.001; }  // 입출금: 0.1%
}
```

- **abstract 클래스**: 인스턴스화 불가 (`new Account()` 컴파일 에러), 자식만 인스턴스화 가능
- **abstract 메서드**: 선언만 있고 구현 없음 → 자식이 반드시 구현
- **추상 메서드가 하나라도 있으면 클래스도 abstract여야 함**

#### 선택 기준

| 상황 | 선택 |
|---|---|
| 자식들이 공통 상태(필드)/생성자/공통 로직을 공유 | 추상 클래스 |
| 단순히 "이 기능을 할 수 있다"는 계약만 강제 | 인터페이스 |
| 여러 능력을 조합 (다중 구현) | 인터페이스 |

#### 실전 예시 조합

```java
// "Animal이다" (is-a) + "헤엄칠 수 있다 / 날 수 있다" (can-do)
class Duck extends Animal implements Swimmable, Flyable {
    public Duck(String name) { super(name); }
    void makeSound() { System.out.println("꽥꽥!"); }
    public void swim() { ... }
    public void fly() { ... }
}
```

`Duck`은 `Animal`"이다"(단일 상속) → 추상 클래스 + 그 위에 "헤엄친다", "난다"는 능력을 인터페이스로 **여러 개** 붙였다.

> **면접 예상 질문:** 인터페이스와 추상 클래스의 차이를 다중 상속, 필드 보유, 다이아몬드 문제 관점에서 설명하고, 두 가지 중 어느 것을 선택할지 판단하는 기준을 본인의 예시와 함께 답해보세요.

---

## 학습 정리

- **캡슐화**는 데이터+로직 묶기 + 정보 은닉의 두 축이며, 응집도↑ 결합도↓의 인과 관계로 이어진다.
- **상속**은 코드 재사용에 유리하지만 부모의 모든 메서드가 노출되고 강한 결합을 만든다 — Stack extends ArrayList가 대표적 안티패턴이다.
- **합성**은 "has-a" 관계에서 외부 노출을 통제할 수 있고 다중 사용·런타임 교체가 가능해 일반적으로 상속보다 우선시된다.
- **다형성**은 업캐스팅 + 동적 디스패치로 "부모 타입 하나로 자식 여러 개를 받기" — OCP를 달성하는 기술적 기반이 된다.
- **인터페이스 vs 추상 클래스**는 다중 상속/필드 보유/관계 의미(is-a vs can-do)로 구분하며, 공통 상태가 있으면 추상 클래스 + 능력 조합이 필요하면 인터페이스를 함께 쓴다.

## 참고

- `_template.md` 구조 준수
- 메모리 학습 기록: `project_oop_design_study.md`
