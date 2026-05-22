# SOLID 원칙 — SRP, LSP, ISP, DIP (스크래핑 시스템·Spring DI 예시)

> 날짜: 2026-05-21

## 내용

### SOLID 전체 그림

| 글자 | 원칙 | 한 줄 요약 |
|---|---|---|
| **S** | Single Responsibility | 한 클래스는 하나의 책임만 |
| **O** | Open-Closed | 확장에 열고, 변경에 닫기 (별도 학습 완료) |
| **L** | Liskov Substitution | 자식은 부모를 안전하게 대체할 수 있어야 |
| **I** | Interface Segregation | 쓰지 않는 메서드에 의존하지 마라 |
| **D** | Dependency Inversion | 구체가 아니라 추상에 의존하라 |

> **면접 예상 질문:** SOLID 5원칙을 한 호흡에 설명하고, 각 원칙이 서로 어떻게 연결되는지 본인 말로 답해보세요.

---

### SRP (Single Responsibility Principle) — 변경 이유가 단 하나

#### 핵심 정의

> **"클래스는 변경의 이유가 단 하나여야 한다"** — 로버트 마틴

"책임"의 진짜 기준은 **"누가 이 코드를 변경하라고 요구하는가"** 이다.

```java
// ❌ SRP 위반: 책임 3개 섞임
class UserService {
    public User register(User user) { ... }       // 회원가입 정책 (기획팀)
    public void saveToDatabase(User user) { ... } // DB 영속화 (DBA)
    public void sendWelcomeEmail(User user) { ... } // 알림 (마케팅팀)
}

// ✅ 책임 분리
class UserService {
    private UserRepository userRepository;
    private EmailService emailService;

    public User register(User user) {
        userRepository.save(user);
        emailService.sendWelcomeEmail(user);
        return user;
    }
}
```

#### SRP 위반을 알아보는 실전 신호

1. **클래스 파일이 너무 김** — 500~1000줄 → "God Class" 안티패턴
2. **메서드 이름의 동사 종류가 다양함** — `save*`, `send*`, `validate*`, `render*`... 5종류 이상이면 의심
3. **클래스 이름에 `And`, `Or`, `Manager`, `Util`, `Helper`** 들어가면 의심
4. **import 문이 너무 다양함** — DB/이메일/HTTP/파일IO... 다 엮여 있음
5. **테스트 코드가 어려움** — mock 5개 깔아야 한다면 책임이 5개라는 신호 (가장 강력)

#### 실전 적용: 스크래핑 시스템

```java
// ❌ SRP 위반
class ScrapingService {
    public Data fetchFromMall(String mallName) {
        // 1. HTTP 요청 (세션/쿠키/리다이렉트)
        // 2. HTML 파싱
        // 3. 데이터 정제/변환
        // 4. DB 저장
        // 5. Kafka 메시지 발행
        // 6. 실패 시 Slack 알림
    }
}

// ✅ SRP 적용 — 5개 책임으로 분리
// 1. MallHttpClient        — 판매몰 인증 방식이 바뀔 때
// 2. HtmlParser + Extractor — 판매몰 HTML 구조가 바뀔 때
// 3. ScrapingRepository    — DB 스키마/기술이 바뀔 때
// 4. ScrapingEventPublisher — 메시지 포맷/토픽이 바뀔 때
// 5. AlertService          — 알림 채널이 바뀔 때 (Slack→Discord)
```

> **면접 예상 질문:** SRP에서 말하는 "책임"의 단위를 어떻게 판단하나요? 본인이 작업한 실제 모듈 예시로 어떻게 분리했는지 설명해보세요.

---

### LSP (Liskov Substitution Principle) — 자식은 부모를 안전하게 대체

#### 핵심 정의

> **"부모 타입을 사용하는 코드는 자식 타입을 받아도 동일하게 동작해야 한다"**

호출부가 부모에 대해 기대하는 "약속(행동)"을 자식이 깨지 말아야 한다.

#### LSP 위반 3가지 대표 신호

**1. 자식이 부모 메서드를 "지원 안 함"으로 처리 (Penguin 케이스)**
```java
class Bird { public void fly() { ... } }

class Penguin extends Bird {
    @Override
    public void fly() {
        throw new UnsupportedOperationException("펭귄은 못 날아요!"); // ❌
    }
}

void makeBirdFly(Bird bird) { bird.fly(); }
makeBirdFly(new Penguin());  // 💥 런타임 예외
```

**2. 자식이 더 엄격한 입력 검증 (사전 조건 강화)**
```java
class Bird { public void eat(Food food) { ... } }      // 어떤 음식이든 OK
class Eagle extends Bird {
    @Override
    public void eat(Food food) {
        if (!(food instanceof Meat)) throw new RuntimeException();  // ❌ 더 엄격
    }
}
```

**3. 자식이 부모와 다른 결과 반환 (사후 조건 약화)**
```java
class List { public int size() { return ...; } }
class WeirdList extends List {
    @Override
    public int size() { return 0; }  // ❌ 부모의 약속 깸
}
```

#### 고전 함정: Square extends Rectangle

```java
class Rectangle {
    protected int width, height;
    public void setWidth(int w) { this.width = w; }
    public void setHeight(int h) { this.height = h; }
    public int area() { return width * height; }
}

class Square extends Rectangle {
    @Override
    public void setWidth(int w) { this.width = w; this.height = w; }
    @Override
    public void setHeight(int h) { this.width = h; this.height = h; }
}

void resize(Rectangle r) {
    r.setWidth(5);
    r.setHeight(10);
    assert r.area() == 50;  // Rectangle이라면 당연한 가정
}
resize(new Square());  // 💥 area() == 100, assert 실패!
```

**핵심 통찰**: **"수학적 is-a 관계 ≠ 코드의 is-a 관계"**. 코드의 상속은 "행동"을 물려받는 것이라, Rectangle의 "가로/세로를 독립적으로 변경할 수 있다"는 행동 약속을 Square는 지킬 수 없음.

#### 해결 패턴 3가지

1. **상속 대신 합성** — Square는 Square, Rectangle은 Rectangle. 따로 가기
2. **공통 부모를 더 추상화** — `Shape.area()` 까지만 공통 본질로
3. **불변 객체** — 가로/세로를 바꿀 수 없으면 LSP 깨질 일 자체가 없음

#### 실전 적용: 스크래핑 시스템

```java
// ❌ LSP 위반 — login()이 모든 자식에 강제됨
abstract class MallScraper {
    public abstract Product fetchProduct(String productId);
    public abstract void login(String id, String password);  // 일부만 필요
}

class OpenMarketScraper extends MallScraper {
    public void login(String id, String pw) { /* no-op */ }  // ❌ 약속 위반
}

// ✅ 해결 — 능력을 인터페이스로 분리
abstract class MallScraper {
    public abstract Product fetchProduct(String productId);
}
interface Loginable { void login(String id, String password); }

class CoupangScraper extends MallScraper implements Loginable { ... }
class OpenMarketScraper extends MallScraper { ... }  // Loginable 안 함
```

> **면접 예상 질문:** LSP를 위반하는 코드의 신호 3가지를 들고, Square-Rectangle처럼 수학적으로는 is-a인데 코드에서는 LSP 위반이 되는 이유를 설명해보세요.

---

### ISP (Interface Segregation Principle) — 인터페이스를 작게 쪼개라

#### 핵심 정의

> **"클라이언트가 사용하지 않는 메서드에 의존하도록 강제하지 마라"**

LSP와 ISP는 짝꿍처럼 같이 움직인다:
- **ISP 위반** → 자식이 안 쓰는 메서드를 억지 구현 (`UnsupportedOperationException` or no-op)
- **LSP 위반** → 그 결과 자식이 부모를 안전하게 대체 못 함
- **해결책 동일** → 인터페이스를 작게 쪼개라!

#### 안티패턴: 큰 인터페이스 하나

```java
interface Worker {
    void work();
    void eat();
    void sleep();
}

class HumanWorker implements Worker {
    public void work()  { ... }
    public void eat()   { ... }
    public void sleep() { ... }
}

class RobotWorker implements Worker {
    public void work()  { ... }
    public void eat()   { throw new UnsupportedOperationException(); }  // 🚨
    public void sleep() { throw new UnsupportedOperationException(); }  // 🚨
}
```

#### 해결: 능력별 인터페이스 분리

```java
interface Workable  { void work(); }
interface Eatable   { void eat(); }
interface Sleepable { void sleep(); }

class HumanWorker implements Workable, Eatable, Sleepable { ... }
class RobotWorker implements Workable { ... }  // 강제 구현/예외 X
```

#### ISP 위반 신호

1. `UnsupportedOperationException` 또는 빈 메서드(no-op) 자주 등장
2. "구현하려면 안 쓰는 메서드까지 다 만들어야 해" 라는 짜증
3. 인터페이스 메서드가 10개 넘어가면 의심

#### Java 표준 라이브러리의 ISP 사례

작은 능력 단위로 잘 쪼개져 있음:
- `Comparable` (정렬 가능), `Iterable` (순회 가능), `Closeable` (닫기 가능), `Serializable` (직렬화 가능)

> **면접 예상 질문:** ISP를 만족시키기 위해 인터페이스를 어떻게 설계해야 하나요? `UnsupportedOperationException`이 자주 등장한다면 어떤 신호인가요?

---

### DIP (Dependency Inversion Principle) — 추상에 의존하라

#### 핵심 정의

> **1. 고수준 모듈은 저수준 모듈에 의존하면 안 된다. 둘 다 추상에 의존해야 한다.**
> **2. 추상은 세부사항에 의존하면 안 된다. 세부사항이 추상에 의존해야 한다.**

#### 용어가 헷갈리는 포인트

이름 때문에 "고수준 = 위, 저수준 = 아래" 같은 계층으로 헷갈리기 쉬운데, 실제 의미는 추상화 정도가 아니다:

| 용어 | 진짜 의미 | 다른 표현 |
|---|---|---|
| **고수준** (High-level) | **무엇을** 할지 결정 (정책, 비즈니스) | "정책 레이어" |
| **저수준** (Low-level) | **어떻게** 할지 구현 (기술, 도구) | "구현 레이어", "인프라" |

쉽게:
- **고수준** = "주문을 처리한다" (비즈니스 의도)
- **저수준** = "INSERT INTO orders VALUES (...)" (실제 DB INSERT)

#### 의존 역전 — 화살표가 뒤집힘

```java
// ❌ DIP 위반 — 고수준이 저수준을 직접 의존
class ScrapingService {
    private SlackClient slack = new SlackClient();  // 구체 의존
    public void scrape() {
        try { ... } catch (Exception e) {
            slack.send("실패!");
        }
    }
}
// 의존 방향: ScrapingService ───▶ SlackClient
//           (고수준)              (저수준)
```

```java
// ✅ DIP 적용 — 둘 다 추상에 의존
interface AlertSender { void send(String msg); }

class ScrapingService {                          // 고수준
    private final AlertSender alertSender;       // 추상에 의존
    public ScrapingService(AlertSender s) { this.alertSender = s; }
}

class SlackAlertSender implements AlertSender { ... }    // 저수준
class DiscordAlertSender implements AlertSender { ... }  // 저수준

// 의존 방향:
// ScrapingService ───▶ AlertSender ◀─── SlackAlertSender
//   (고수준)            (추상)           (저수준)
//                                  ◀─── DiscordAlertSender
```

#### 사용처에서 끼워넣기

```java
new ScrapingService(new SlackAlertSender());     // 운영
new ScrapingService(new DiscordAlertSender());   // 마이그레이션
new ScrapingService(new MockAlertSender());      // 테스트
```

→ `ScrapingService`는 한 줄도 안 바뀜 = OCP 자동 만족.

#### 한 줄 판별법

| 키워드 | 정체 |
|---|---|
| `interface` 키워드로 선언된 명세 | **추상** |
| `implements`로 인터페이스를 구현하는 구체 클래스 | **저수준 (구체 구현)** |
| 그 인터페이스를 필드로 가지고 비즈니스 로직을 하는 클래스 | **고수준** |

#### Spring DI = DIP의 실현 도구

```java
@Service
class CheckoutService {                            // ① 고수준
    private final PaymentGateway paymentGateway;
    public CheckoutService(PaymentGateway pg) { ... }
}

interface PaymentGateway {                          // ② 추상
    PaymentResult charge(int amount);
}

class TossPaymentGateway                            // ③ 저수준 (실제 Toss API 호출)
    implements PaymentGateway { ... }

class StripePaymentGateway                          // ③ 저수준 (실제 Stripe API 호출)
    implements PaymentGateway { ... }
```

`@Autowired` / 생성자 주입을 쓸 때마다 이미 DIP를 적용하고 있는 셈.

#### Spring Data JPA의 함정

```java
@Service
class OrderService {                                // 고수준
    private final OrderRepository orderRepository;
}

public interface OrderRepository                    // 추상 (interface!)
    extends JpaRepository<Order, Long> { }

// 저수준 = Spring Data JPA가 런타임에 자동으로 만들어주는 프록시
//        + 내부적으로 활용되는 SimpleJpaRepository
//        → 본인이 직접 만들지 않아서 "안 보임" → 헷갈리는 포인트
```

JPA에서는 저수준을 본인이 만들지 않고 Spring이 자동 생성하기 때문에 **저수준이 눈에 안 보여** 헷갈리기 쉽다. PaymentGateway 예시처럼 `implements`로 직접 구체 클래스를 만드는 케이스가 더 직관적이다.

> **면접 예상 질문:** DIP의 "의존 역전"이 무엇을 역전시킨다는 뜻인가요? Spring의 생성자 주입이 DIP를 어떻게 만족시키는지, 고수준/추상/저수준을 각각 짚어서 설명해보세요.

---

## 학습 정리

- **SRP**: "변경 이유가 단 하나여야 한다"가 핵심. 책임의 단위는 "누가 이 코드를 바꾸라고 할까"로 판단하며, God class·메서드 동사 다양성·테스트 어려움이 위반 신호다.
- **LSP**: 부모 타입 자리에 자식을 넣어도 호출부의 약속이 깨지지 않아야 한다. "수학적 is-a"가 아니라 "행동 is-a"로 판단해야 하며, 위반 시 능력을 인터페이스로 분리하는 패턴이 유효하다.
- **ISP**: 큰 인터페이스 하나보다 작은 능력 단위 인터페이스 여러 개. `UnsupportedOperationException`이 등장하면 ISP 위반 신호다.
- **LSP와 ISP는 짝꿍** — ISP를 잘 지키면 LSP 위반 가능성 자체가 사라진다.
- **DIP**: 고수준(비즈니스 정책)과 저수준(구체 구현) 모두 추상(인터페이스)에 의존하게 만든다. Spring의 생성자 주입이 DIP의 실현 도구이며, 인터페이스에 `implements`로 붙는 구체 클래스가 저수준임을 기억하면 헷갈리지 않는다.

## 참고

- `_template.md` 구조 준수
- 선행 학습:
  - `객체 지향 설계 기초 - 캡슐화, 상속·합성, 다형성, OCP, 인터페이스 vs 추상 클래스.md`
  - `추상화 - 본질 vs 세부사항, 정보 은닉과의 차이, 추상화의 단점과 Rule of Three.md`
- 메모리 학습 기록: `project_oop_design_study.md`
