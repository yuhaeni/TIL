# DIP 심화 — 의존의 의미, 추상의 안정성, 인터페이스 이름 짓기, Mock 주입

> 날짜: 2026-05-21

## 내용

### "의존한다"의 진짜 의미

코드에서 클래스 A가 클래스 B를 **"의존한다"** 는 건 쉽게 말해:

> **"A의 코드 안에 B의 이름이 적혀 있다"**

A의 코드를 컴파일하려면 B가 존재해야 한다. B가 사라지면 A는 컴파일 에러.

```java
class NotificationService {
    private final GmailSender gmailSender = new GmailSender();
    //          ^^^^^^^^^^^                  ^^^^^^^^^^^
    //          여기에 'GmailSender'라는 이름이 박혀있음 → 의존!
}
```

> **면접 예상 질문:** 코드에서 "A가 B에 의존한다"는 게 정확히 어떤 의미인가요? 컴파일 관점에서 설명해보세요.

---

### 인터페이스 의존도 "의존"이다 — 의존 대상이 핵심

DIP가 **"의존을 없애라"가 아니라 "의존 대상을 잘 골라라"** 라는 점이 중요하다.

```java
// 버전 A — DIP 위반: GmailSender 이름이 박혀있음 (의존 대상 = 구체)
class NotificationService {
    private final GmailSender gmailSender = new GmailSender();
}

// 버전 B — DIP 준수: EmailSender(interface) 이름만 박혀있음 (의존 대상 = 추상)
class NotificationService {
    private final EmailSender emailSender;
    public NotificationService(EmailSender emailSender) {
        this.emailSender = emailSender;
    }
}
```

🔑 둘 다 이름이 박혀있고 둘 다 "의존"이다. 차이는 **무엇에 의존하는가**.

#### 비유 — 사람 vs 직무

| 의존 형태 | 비유 |
|---|---|
| **구체 클래스 의존** | "**김철수가** 메일 보내줘야 해" |
| **인터페이스 의존** | "**메일 보낼 수 있는 사람**이 필요해" |

김철수가 회사를 그만두면? "메일 보낼 수 있는 사람"이라고 했으면 → 박영희를 데려오면 됨. 근데 "김철수가 필요해"라고 했으면 → 회사 망함.

> **면접 예상 질문:** 인터페이스에 의존하는 것도 의존인데, 왜 DIP에서는 추상에 의존하는 것이 좋다고 하나요?

---

### 안정성 차이 — 무엇이 자주 바뀌는가

DIP의 핵심은 **"안정적인 것에 의존하라"** 다.

| 의존 대상 | 변화 빈도 | 영향 |
|---|---|---|
| **인터페이스(추상)** | 거의 안 바뀜 — "메일을 보낸다"는 본질은 그대로 | 안전 |
| **구체 클래스(저수준)** | 자주 바뀜 — Gmail → Naver → AWS SES... 도구는 계속 갈아끼움 | 위험 |

- **인터페이스 = "약속/계약"** → 안정적
- **구체 클래스 = "도구/구현 디테일"** → 변화 많음

**DIP의 진짜 의미**:
> "의존을 없애라"가 아니라 → **"의존을 안정적인 추상으로 옮겨라"**

> **면접 예상 질문:** 왜 추상은 "안정적"이고 구체 클래스는 "불안정"한가요? 본인이 작업했던 시스템에서 비슷한 사례가 있나요?

---

### 변경 비교 — DIP 위반 vs 준수

요구사항: *"Gmail이 비싸서 NaverMail로 갈아탑시다"*

#### 버전 A (DIP 위반): 고수준 코드 수정 필요

```java
class NotificationService {
    private final NaverSender naverSender = new NaverSender();  // 1. 필드 타입 수정
    public void notifyUser(String userId, String message) {
        naverSender.send(userId, message);  // 2. 메서드 안 호출부 수정
    }
}
```

→ `NotificationService`(고수준 비즈니스) 코드를 직접 수정. **2~3군데 변경**.

#### 버전 B (DIP 준수): 고수준 코드 한 줄도 안 바뀜

```java
// NotificationService — 그대로
class NotificationService {
    private final EmailSender emailSender;
    public NotificationService(EmailSender emailSender) { ... }
    public void notifyUser(String userId, String message) {
        emailSender.send(userId, message);
    }
}

// 새 구현체 NaverMailSender만 추가 → 외부에서 끼워넣기
new NotificationService(new NaverMailSender());
```

→ **고수준 코드 변경 0**. OCP 자동 만족.

> **면접 예상 질문:** DIP를 적용하지 않은 코드에서 의존 대상을 변경할 때 어떤 비용이 발생하나요?

---

### 외부에서 주입하는 3가지 방법

"인터페이스에만 의존하면 실제 구현체는 어디서 결정되나?"의 답은 **"고수준 코드 밖에서 외부가 결정"** 이다.

#### 방법 1: 순수 Java로 직접 끼워넣기

```java
public static void main(String[] args) {
    EmailSender sender = new NaverMailSender();           // 여기서 결정
    NotificationService service = new NotificationService(sender);  // 주입
    service.notifyUser("user1", "안녕!");
}
```

#### 방법 2: Spring (실무 표준)

```java
@Service
class NotificationService {
    private final EmailSender emailSender;
    public NotificationService(EmailSender emailSender) {  // Spring 자동 주입
        this.emailSender = emailSender;
    }
}

@Component
class NaverMailSender implements EmailSender { ... }
```

Spring이 시작될 때 `EmailSender` 타입의 빈을 찾아서 생성자에 자동으로 끼워넣어준다. **`@Service`, `@Component`, 생성자 주입 — 이게 다 DIP를 실현하는 도구**.

#### 방법 3: 환경별로 다르게 끼워넣기 (Spring Profile)

```java
@Component
@Profile("prod")
class NaverMailSender implements EmailSender { ... }

@Component
@Profile("dev")
class MockEmailSender implements EmailSender {
    public void send(String to, String content) {
        System.out.println("[DEV] " + to + ": " + content);  // 실제 발송 X
    }
}
```

`application.yml`의 `spring.profiles.active`만 바꾸면 같은 코드가 환경별로 다른 구현체로 동작. 고수준은 그대로.

> **면접 예상 질문:** Spring DI 없이도 DIP를 지킬 수 있나요? main() 안에서 직접 조립하는 방식과 Spring 방식의 차이는 무엇인가요?

---

### 테스트 용이성 — Mock 주입

DIP의 가장 실질적인 이점 중 하나. 실제로 메일을 보내지 않고 테스트하려면?

```java
@Test
void notifyUser_테스트() {
    // 1. 가짜 EmailSender
    EmailSender mockSender = new EmailSender() {
        public void send(String to, String content) {
            System.out.println("[가짜] " + to + "에게 " + content);
            // 실제로 안 보냄!
        }
    };

    // 2. 가짜를 주입
    NotificationService service = new NotificationService(mockSender);

    // 3. 안전한 테스트
    service.notifyUser("user1", "테스트");
}
```

또는 Mockito로 더 간단하게:

```java
@Test
void notifyUser_테스트() {
    EmailSender mockSender = mock(EmailSender.class);
    NotificationService service = new NotificationService(mockSender);

    service.notifyUser("user1", "테스트");

    verify(mockSender).send("user1", "테스트");  // 호출됐는지 검증
}
```

→ 만약 `GmailSender`를 직접 `new`로 박아놨다면 테스트할 때마다 진짜 Gmail에 메일이 가서 사고. DIP가 이를 방지.

> **면접 예상 질문:** DIP를 지키지 않으면 테스트 작성이 왜 어려워지나요? Mock 객체를 활용하는 패턴을 예시로 설명해보세요.

---

### 인터페이스 이름 짓기 — 도메인 언어 vs 기술 이름

DIP를 적용하면서 자주 하는 실수: **추상의 이름에 구현 도구를 노출**.

```java
// ❌ 안티패턴 — 도구 이름이 추상에 박혀있음
interface KafkaProducer {
    void send(String topic, String message);
}
```

🚨 문제: 나중에 RabbitMQ로 바꾸면? `class RabbitMqClient implements KafkaProducer { ... }` — 이름이 모순. 추상화가 깨진다.

```java
// ✅ 도메인 언어로 — "무엇을 하는가(WHAT)"만 표현
interface OrderEventPublisher {
    void publish(OrderEvent event);
}

class KafkaOrderEventPublisher implements OrderEventPublisher { ... }
class RabbitMqOrderEventPublisher implements OrderEventPublisher { ... }
```

#### 이름 짓기 비교

| 이름 | 의미 | 평가 |
|---|---|---|
| `KafkaProducer` | "Kafka 라이브러리를 쓴다" (HOW/WHO) | ❌ 구현 노출 |
| `MessageSender` | "메시지를 보낸다" (WHAT) | ✅ 본질만 |
| `EventPublisher` | "이벤트를 발행한다" (WHAT) | ✅ 본질만 |
| `OrderEventPublisher` | "주문 이벤트를 발행한다" (WHAT, 도메인 한정) | ✅ 가장 좋음 |

#### 핵심 원칙

> **"추상의 이름은 도메인 언어로, 구현체의 이름은 기술 이름으로"**

- 추상: `OrderEventPublisher` (비즈니스 관점)
- 구현: `KafkaOrderEventPublisher`, `RabbitMqOrderEventPublisher` (기술 관점)

> **면접 예상 질문:** `KafkaProducer`라는 이름의 인터페이스를 보면 어떤 점이 우려되나요? 더 나은 이름을 제안해보세요.

---

### 실전 적용 — 스크래핑 시스템 (11개 판매몰)

본인이 실제로 작업한 시스템에 DIP를 어떻게 적용했는지 풀어보면:

```java
// 추상: 도메인 언어로 — "판매몰을 스크래핑한다"
interface MallScraper {
    Product fetchProduct(String productId);
    List<Product> fetchAllProducts();
}

// 고수준: 추상에만 의존, 어떤 판매몰인지 모름
@Service
class ProductSyncService {
    private final List<MallScraper> scrapers;  // Spring이 모든 빈을 List로 주입!

    public ProductSyncService(List<MallScraper> scrapers) {
        this.scrapers = scrapers;
    }

    public void syncAllMalls() {
        for (MallScraper scraper : scrapers) {
            List<Product> products = scraper.fetchAllProducts();
            // 저장/이벤트 발행...
        }
    }
}

// 저수준: 판매몰별 구체 구현
@Component
class NaverScraper implements MallScraper { /* 네이버 HTML 파싱 */ }

@Component
class CoupangScraper implements MallScraper { /* 쿠팡 로직 */ }

@Component
class GmarketScraper implements MallScraper { /* 지마켓 로직 */ }
// ... 11개 판매몰
```

#### 효과

- 새 판매몰 추가? → 클래스 하나 만들면 끝. `ProductSyncService` 무수정 (**OCP 자동 만족**)
- 특정 판매몰만 비활성? → `@Component` 어노테이션만 제거
- 테스트? → `FakeMallScraper`로 가짜 데이터 반환

> **면접 예상 질문:** Spring의 `List<인터페이스>` 자동 주입은 DIP/OCP와 어떻게 연결되나요? 본인 경력에서 비슷한 패턴을 적용한 사례가 있나요?

---

### 종합 답변 (5년차 면접 완성형)

> "DIP(의존 역전 원칙)는 고수준 클래스가 구체적인 저수준 클래스에 의존하지 않고, 추상(인터페이스)에 의존해야 함을 의미합니다.
>
> 저수준 클래스에 직접 의존하는 경우 의존하는 클래스를 다른 클래스로 변경할 때 코드 수정점이 많아집니다. 추상에 의존하는 경우에는 기존 코드를 변경하지 않고 기능을 확장할 수 있습니다.
>
> DIP를 위반하지 않은 클래스는 테스트 클래스에도 용이합니다. 이메일 전송을 예로 들면 가짜 Mock 객체를 만들어 주입하면 테스트 단계에서 메일이 전송되는 현상을 방지할 수 있습니다.
>
> 저도 이전 회사에서 11개 판매몰 스크래핑 시스템을 만들 때 `MallScraper` 인터페이스로 추상화하고 판매몰별 구현체로 분리했는데, 덕분에 새 판매몰 추가할 때마다 기존 코드를 수정하지 않을 수 있었습니다."

#### 5단 구조 분석

| # | 영역 | 본인 답변에서 |
|---|---|---|
| 1 | 정의 | "고수준이 구체적 저수준 대신 추상(인터페이스)에 의존" |
| 2 | 문제 진단 | "변경 시 수정점이 많아짐" |
| 3 | 해결 효과 (OCP) | "기존 코드 변경 없이 기능 확장" |
| 4 | 실무 효과 (테스트) | "Mock 객체 주입, 메일 전송 방지" |
| 5 | 본인 경력 사례 | "11개 판매몰 + MallScraper + 새 판매몰 무수정" |

#### 꼬리 질문 대비

- **"DIP의 단점이나 비용은?"** → "구현체가 하나뿐이면 부채. **Rule of Three** — 같은 패턴이 3번 반복될 때 추상화 도입."
- **"Spring DI 없이도 DIP를 지킬 수 있나요?"** → "네, main()이나 Factory 패턴으로 외부에서 조립하면 됩니다. Spring은 자동화 도구."
- **"11개 판매몰 추가하면서 어려웠던 점은?"** → 본인 실제 경험 기반 답변 준비.

> **면접 예상 질문:** DIP를 30초 안에 설명하면서 본인 경력 사례를 한 줄 녹여 답변해보세요. (정의 → 문제 → 효과 → 본인 경험 5단 구조)

---

## 학습 정리

- **"의존한다" = 코드에 그 이름이 적혀있다**. DIP는 의존을 없애라는 게 아니라 **의존 대상을 안정적인 추상으로 옮기라**는 원칙이다.
- **인터페이스(약속)는 거의 안 바뀌고, 구체 클래스(도구)는 자주 바뀐다.** 안정적인 것에 의존해야 변화에 흔들리지 않는다.
- 실제 구현체를 결정하는 시점은 고수준 코드 **밖**(main/Spring/Profile)이며, 이로 인해 환경별 교체와 Mock 주입 테스트가 자유로워진다.
- 추상의 이름은 **도메인 언어(WHAT)**로 짓고, 구현체의 이름은 **기술 이름(HOW)**으로 짓는 게 추상화 누수를 막는다. (`KafkaProducer ❌` → `OrderEventPublisher ✅`)
- 5년차 면접 답변은 **정의 → 문제 → 효과(OCP) → 실무 효과(테스트) → 본인 경력 사례**의 5단 구조로 한 호흡에 풀면 강력하다.

## 참고

- `_template.md` 구조 준수
- 선행 학습:
  - `객체 지향 설계 기초 - 캡슐화, 상속·합성, 다형성, OCP, 인터페이스 vs 추상 클래스.md`
  - `추상화 - 본질 vs 세부사항, 정보 은닉과의 차이, 추상화의 단점과 Rule of Three.md`
  - `SOLID 원칙 - SRP, LSP, ISP, DIP (스크래핑 시스템·Spring DI 예시).md`
- 메모리 학습 기록: `project_oop_design_study.md`
