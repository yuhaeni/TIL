# 헥사고널 아키텍처 — Ports & Adapters, DIP, 다형성, Template Method, OCP

> 날짜: 2026-06-10

## 내용

실제 스크래핑 시스템(11개 판매몰) 코드를 따라가며 헥사고널 아키텍처가 무엇인지,
그리고 그 구조가 어떤 객체지향 원칙 위에 서 있는지 정리했다.

---

### 헥사고널 아키텍처 — "구조" 이야기 (DDD와의 차이)

헥사고널 아키텍처(= Ports & Adapters)의 한 줄 핵심은 다음과 같다.

> **도메인이 외부 기술(HTTP, Kafka, DB)을 모른다.**
> 모든 외부 의존은 인터페이스(Port)로만 표현되고, 구현(Adapter)은 도메인 바깥에 있다.

자주 헷갈리는 지점: **DDD와 비슷한 개념인가?**
- **헥사고널 = 코드를 어떤 "모양(구조)"으로 배치하고 의존성을 어느 방향으로 흐르게 할지**에 대한 이야기.
- **DDD = 그 안에 담길 "도메인 모델(내용)"을 어떻게 그릴지**에 집중.
- 둘은 충돌하는 게 아니라 **같이 쓰면 시너지**가 나는 단짝.

검증 방법(말로만이 아니라 `import`로 증명):
```bash
# 도메인이 adapter를 모른다 → 0건이어야 정상
grep -rE "import com\.example\.mallscraper\.adapter\." .../domain/
# 도메인이 Spring을 모른다 → 0건이어야 정상 (순수 JUnit 단위 테스트 가능)
grep -rE "import org\.springframework\." .../domain/
```

> **면접 예상 질문:** 헥사고널 아키텍처와 전통 Layered Architecture의 차이는 무엇이며, "도메인이 외부 기술을 모른다"는 말을 어떻게 코드로 증명할 수 있나요?

---

### Port & Adapter와 의존 방향 — DIP + 다형성

의존 방향 그림:
```
Processor → Repository(인터페이스) → MallFetcher(인터페이스) ← NaverPaySimulatedFetcher(어댑터)
```

핵심은 화살표 방향이다. 도메인(`Processor`)도, 어댑터(`NaverPaySimulatedFetcher`)도
**둘 다 가운데 있는 인터페이스(Port)를 향한다.** 모든 인터페이스는 `domain/` 패키지 안에 있다.

이 구조가 기대는 두 가지 객체지향 개념:
- **다형성(Polymorphism)**: `Processor`는 `MallFetcher` **인터페이스 타입으로만** 호출하고,
  실제 어떤 구현체(네이버페이/쿠팡)가 들어올지는 런타임에 결정된다.
- **DIP(의존성 역전 원칙)**: 원래라면 고수준 모듈(`Processor`)이 저수준 모듈(`Fetcher`)에
  의존할 텐데, 인터페이스를 끼워서 화살표를 **거꾸로(`←`)** 뒤집었다. 그래서 이름이 "역전".

효과: HTTP 클라이언트를 OkHttp → WebClient로 바꿔도 **Fetcher 어댑터만** 수정.
도메인(`Processor`)은 한 글자도 안 고친다.

> **면접 예상 질문:** `Processor`가 `NaverPaySimulatedFetcher`를 직접 참조하지 않고 `MallFetcher` 인터페이스에만 의존하면 어떤 이점이 생기나요? 이를 DIP와 다형성 관점에서 각각 설명해 보세요.

---

### Inbound Port(in) vs Outbound Port(out) — 호출의 주도권

같은 인터페이스인데 패키지를 `in`/`out`으로 나눈 기준은 **"누가 호출을 시작하는가(주도권)"**.

도메인(육각형)을 하나의 **집**이라고 보면:
- **Inbound Port** (`domain/port/in/MallScraper`): **바깥(Controller)이 초인종을 눌러** 집 안으로
  들어온다. 호출 시작점 = 바깥. → 도메인으로 들어오는 방향.
- **Outbound Port** (`domain/port/out/MallFetcher`): **집 안(도메인 Processor)에서 바깥으로**
  전화를 건다("네이버페이야 데이터 줘"). 호출 시작점 = 도메인. → 도메인에서 나가는 방향.

| 구분 | 호출 시작 | 예시 |
|------|-----------|------|
| Inbound Port (in) | 바깥(Controller) | `MallScraper`, `MallScraperVerifier` |
| Outbound Port (out) | 도메인(Processor) | `MallFetcher`, `MallDataPublisher`, `MallEventPublisher` |

"요청 vs 응답"이 아니라 **"호출의 시작점이 안이냐 밖이냐"**가 기준인 점이 포인트.

> **면접 예상 질문:** Inbound Port와 Outbound Port를 가르는 기준은 무엇인가요? "요청/응답"이 아니라 다른 기준으로 설명해 보세요.

---

### Dispatcher — 구현체가 아니라 "고르는 애" (Collection DI + Strategy)

`DefaultMallScraperDispatcher`는 이름이 비슷해서 헷갈리지만 `MallScraper`를 구현하지 않는다.
`implements MallScraperDispatcher`이고, `List<MallScraper>`를 **주입받아 고를 뿐**이다.

```java
@Component
public class DefaultMallScraperDispatcher implements MallScraperDispatcher {
    private final List<MallScraper> scrapers;   // 모든 구현체를 리스트로 주입

    public void dispatch(MallScrapeCommand command) {
        resolve(command.mallType()).execute(command);  // 지원하는 놈 골라 실행
    }
    private MallScraper resolve(MallTypeCd mallType) {
        return scrapers.stream()
                .filter(scraper -> scraper.supports(mallType))  // supports로 필터
                .findFirst()
                .orElseThrow(() -> new NoSuchElementException(...));
    }
}
```

`List<인터페이스>` 자동 주입 + `supports()` 필터 = 예전에 본 **Collection DI + Strategy 패턴**과
같은 그림. 새 판매몰이 빈으로 등록되면 리스트에 자동 합류한다.

> **면접 예상 질문:** Spring이 `List<MallScraper>`에 주입하는 빈은 어떤 것들인가요? 이 구조에서 새 구현체를 추가할 때 Dispatcher 코드를 수정하지 않아도 되는 이유는?

---

### AbstractMallScraper — execute() 오케스트레이션과 Template Method

`AbstractMallScraper`가 `MallScraper`(in Port)의 실제 구현이며, 11개 판매몰 구현체가 이를 상속한다.
`execute()`는 직접 인증/수집을 하지 않고 **"인증 → 수집 → 발행"의 순서를 지휘하는 대본**이다.

```java
public abstract class AbstractMallScraper implements MallScraper {
    @Override
    public void execute(MallScrapeCommand command) {
        eventPublisher.publish(... SCRAPING_STARTED ...);          // ① 시작 알림
        MallSession session = credentialsProcessor.process(command); // ② 로그인/인증
        MallData data = dataProcessor.process(session, command);     // ③ 데이터 수집
        dataPublisher.publish(data);                                 // ④ 발행
        eventPublisher.publish(... SCRAPING_COMPLETED ...);          // ⑤ 완료 알림
    }
}
```

택배 비유: ① 배송 시작 알림 → ② 문 열기(인증) → ③ 물건 꺼내기(수집) → ④ 전달(발행) → ⑤ 완료 알림.
`execute()`는 각 담당자에게 "시키기만" 한다.

**왜 인터페이스(`MallScraper`) + 추상 클래스(`AbstractMallScraper`)를 둘 다 두나?**
- 인터페이스 = **"약속(계약)"** — Dispatcher가 이것만 보고 의존(DIP).
- 추상 클래스 = **"공통 대본"** — `execute()` 흐름을 한 번만 작성(중복 제거).
- 추상 클래스가 없으면 11개 구현체가 `execute()` 흐름을 **복붙 11번** 해야 하고,
  "발행 전 로그 추가" 같은 요구가 생기면 11곳을 고쳐야 한다.

이렇게 **뼈대(흐름)는 부모, 세부 단계는 자식**이 나눠 갖는 패턴이 **Template Method 패턴**.

> **면접 예상 질문:** 인터페이스 하나로 충분해 보이는데 왜 추상 클래스(AbstractMallScraper)를 따로 두었나요? Template Method 패턴이 여기서 해결하는 문제는 무엇인가요?

---

### 추상 클래스 vs 인터페이스 — "구현한 것 + 빈칸"을 섞을 수 있다

흔한 오해: "추상 클래스에는 구현을 안 한다." → 틀림.
`AbstractMallScraper`의 `execute()`는 몸통이 **꽉 차 있는 구현된 메서드**다.

- **인터페이스 = 메뉴 주문서**: "로그인/수집/발행 할 것"이라는 **할 일 목록(약속)만** 나열. 방법은 안 적음.
- **추상 클래스 = 반쯤 채워진 레시피**: 어떤 단계는 미리 적어두고(`execute()` 흐름),
  어떤 단계는 빈칸으로 남겨둔다(판매몰별 차이). **구현 + 빈칸을 섞을 수 있는 것**이 핵심 차이.

빈칸(자식이 채울 부분) = `execute()` 전체 흐름이 아니라 **"네이버는 이렇게 로그인" 같은 판매몰별 세부 단계**.

> **면접 예상 질문:** 추상 클래스와 인터페이스의 핵심 차이는 무엇인가요? "추상 클래스는 구현을 안 한다"는 말이 왜 부정확한지 설명해 보세요.

---

### super()와 생성자 체이닝 — 자식이 부모의 재료를 건넨다

`NaverPayScraper extends AbstractMallScraper`. 그런데 부모 생성자는 4개의 재료를 **반드시** 요구한다
(기본 생성자가 없음). 그래서 자식은 `super(...)`로 그 재료를 건네야 컴파일된다.

`super()` = **부모의 생성자를 호출하는 것.** 자식이 태어나려면 부모가 먼저 셋팅돼야 하므로,
자식 생성자는 부모에게 "재료 드릴 테니 먼저 준비하세요"라고 말한다.

```java
public class NaverPayScraper extends AbstractMallScraper implements MallScraperVerifier {
    public NaverPayScraper(List<MallCredentialsProcessor> credentialsProcessors, ...) {
        super(
            resolve(credentialsProcessors, p -> p.supports(NaverPayHelper.MALL_TYPE), ...), // 네이버용만 골라
            resolve(dataProcessors, ...),
            dataPublisher, eventPublisher);   // 부모에게 건넴
    }
}
```

`resolve()` = 여러 부품 중 `supports(NaverPay)`인 것 **하나만 골라주는 필터**
(`filter → findFirst → orElseThrow`). Dispatcher의 패턴과 동일하게, 같은 구조가 **양파처럼 겹겹이** 반복된다.

> **면접 예상 질문:** `super(...)` 호출이 왜 필수인가요? 부모 클래스에 기본 생성자가 없을 때 자식 생성자에서 어떤 일이 일어나야 하나요?

---

### 차이를 표현하는 법 — 상속(오버라이드)이 아니라 부품 조립(주입) + OCP

`NaverPayScraper`는 `execute()`나 인증 메서드를 **오버라이드하지 않는다.**
대신 **"네이버용 Processor 부품을 골라서 부모에게 끼워넣는다"** — 즉 차이를 **상속이 아니라 조립(주입/Composition)** 으로 표현한다.

실제 네이버 인증 로직은 `NaverPayCredentialsProcessor`가 담당하며,
이 클래스도 내부에서 `Repository`와 `MfaProcessor`를 다시 `resolve()`로 골라 쓴다
(입력 처리 → 필요 시 MFA → 검증 → 세션 생성 오케스트레이션).

**OCP(개방-폐쇄 원칙) 달성:**
- 새 판매몰(11번가) 추가 → `ElevenStScraper`, `ElevenStCredentialsProcessor`를 새로 만들고
  `@Component`로 **빈 등록만** 하면 끝.
- `List<...>`에 자동 합류 → `resolve()`가 알아서 선택.
- 부모 `AbstractMallScraper`도, `Dispatcher`도 **수정 0건.**
- → **확장에는 열려있고(추가 OK), 수정에는 닫혀있다(기존 코드 불변).**

> **면접 예상 질문:** 판매몰별 차이를 상속(메서드 오버라이드) 대신 주입(Composition)으로 표현했을 때의 장단점은? 이 설계가 OCP를 어떻게 만족시키는지 새 판매몰 추가 시나리오로 설명해 보세요.

---

## 학습 정리

- 헥사고널 아키텍처는 "도메인이 외부 기술을 모르게" 만드는 **구조** 패턴이고, DDD(내용)와 함께 쓰면 시너지가 난다. `import` grep으로 의존 0건을 증명할 수 있다.
- Port는 화살표가 가운데 인터페이스를 향하게 해 **DIP + 다형성**을 실현하고, **호출 주도권**에 따라 Inbound(in)/Outbound(out)으로 나뉜다.
- `Dispatcher`는 구현체가 아니라 `List<인터페이스>` + `supports()` 필터로 **고르는 역할**(Collection DI + Strategy).
- 인터페이스(약속) + 추상 클래스(공통 대본=Template Method)를 함께 둬서 흐름 중복을 제거한다. 추상 클래스는 "구현된 메서드 + 빈칸(추상 메서드)"을 섞을 수 있다.
- 판매몰별 차이는 오버라이드가 아니라 **부품 조립(주입)**으로 표현 → 새 판매몰은 빈 등록만으로 추가되어 **OCP**를 만족한다.
