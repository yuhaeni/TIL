# Spring Boot 동작 원리 — HTTP 요청 처리, DispatcherServlet, Filter/Interceptor/AOP, Thread per Request

> 날짜: 2026-05-22

## 내용

### Spring MVC 요청 처리 흐름 — 전체 그림

<img width="659" height="333" alt="image" src="https://github.com/user-attachments/assets/2fd63b67-7385-4e00-a6e4-086820d399d7" />


클라이언트가 `GET /api/users/1` 같은 요청을 보냈을 때, Spring Boot 내부에서 일어나는 일을 시간 순으로 정리하면 다음과 같다.

```
1. 클라이언트 요청 (HTTP)
       ↓
2. Tomcat이 TCP 연결 수립 (3-way handshake)
       ↓
3. Tomcat 스레드 풀에서 스레드 하나 할당 (Thread per Request)
       ↓
4. Filter 체인 통과 (서블릿 컨테이너 레벨)
       ↓
5. DispatcherServlet에 전달 (Front Controller)
       ↓
6. HandlerMapping이 "이 URL은 누가 처리?" 찾음
       ↓
7. Interceptor preHandle 통과 (Spring MVC 레벨)
       ↓
8. HandlerAdapter가 Controller 메서드 호출
       ↓
9. (AOP 적용된 경우) 프록시가 가로채서 부가 기능 실행
       ↓
10. Controller 비즈니스 로직 실행
       ↓
11. (역순으로) AOP → Interceptor postHandle → Filter → 클라이언트 응답
```

이 흐름 전체가 **하나의 스레드** 에서 처리되며, 요청이 끝나면 스레드는 풀로 반납된다.

> **면접 예상 질문:** 클라이언트가 `GET /api/users/1` 요청을 보냈을 때, Tomcat이 요청을 받는 순간부터 Controller가 응답을 반환하기까지 Spring Boot 내부에서 일어나는 일을 흐름대로 설명해주세요.

---

### DispatcherServlet — Front Controller 패턴

Spring MVC의 핵심 진입점. **모든 HTTP 요청을 단 하나의 서블릿이 받아서** 적절한 Controller로 분배(dispatch)한다.

만약 DispatcherServlet이 없다면, URL마다 서블릿을 따로 만들고 `web.xml`에 매핑해야 한다. DispatcherServlet은 이 역할을 **Front Controller 패턴** 으로 통합한다.

DispatcherServlet 자체는 **요청을 누구에게 위임할지** 직접 알지 않는다. 다음 두 협력자에게 위임한다.

- `HandlerMapping` — 어떤 Controller가 처리할지 **찾기**
- `HandlerAdapter` — 그 Controller를 어떻게 **호출** 할지

> **면접 예상 질문:** DispatcherServlet의 역할을 Front Controller 패턴 관점에서 설명해주세요.

---

### HandlerMapping vs HandlerAdapter — "찾기"와 "호출"의 분리

많이 헷갈리는 두 친구의 책임 차이.

| 구분 | HandlerMapping | HandlerAdapter |
|------|---------------|----------------|
| 역할 | **찾기 (Finding)** | **호출하기 (Invoking)** |
| 답하는 질문 | "이 URL은 **누가** 처리해?" | "그 핸들러를 **어떻게** 실행해?" |
| 결과 | Controller 메서드 정보 반환 | 메서드 실제 실행 → 결과 반환 |

#### 음식점 비유

- **HandlerMapping** = 호스트(안내원) — "이 손님은 7번 테이블 김셰프 담당!" (누가만 알려줌)
- **HandlerAdapter** = 주방 통역사 — 주문서를 김셰프 방식으로 전달하고 결과를 받아옴 (실제 호출)

#### 왜 굳이 분리했나? (Adapter 패턴)

Spring은 Controller 종류가 여러 개다.

- `@Controller` / `@RestController` (가장 흔함)
- `HttpRequestHandler` (서블릿 스타일)
- `Servlet` 자체
- 함수형 엔드포인트 (`RouterFunction`)

각 종류마다 호출 방식이 다르다. HandlerMapping은 "타입 무관, 그냥 누가 처리할지" 찾아주고, **HandlerAdapter는 각 타입별로 다르게 호출**해준다. 이게 **Adapter 디자인 패턴** 의 적용이다.

```
@RestController         → RequestMappingHandlerAdapter
HttpRequestHandler      → HttpRequestHandlerAdapter
Servlet                 → SimpleServletHandlerAdapter
```

> **면접 예상 질문:** HandlerMapping과 HandlerAdapter의 차이는 무엇이며, 왜 두 역할을 분리했는지 설명해주세요.

---

### Tomcat 스레드 풀과 Thread per Request 모델

Tomcat은 동시 요청을 처리하기 위해 미리 일정 개수의 스레드를 만들어 두는 **스레드 풀(Thread Pool)** 을 사용한다. 요청이 오면 풀에서 스레드 하나를 빌려 처리하고, 끝나면 다시 반납한다. 이걸 **Thread per Request** 모델이라고 한다.

#### Spring Boot 기본 설정

```yaml
server:
  tomcat:
    threads:
      max: 200          # 최대 스레드 수 (기본 200)
      min-spare: 10     # 최소 유지 스레드
    accept-count: 100   # 대기 큐 크기
```

#### 풀이 가득 차면?

```
[요청 1~200] → 스레드 풀 200개 다 사용 중
[요청 201~] → accept-count 큐(기본 100)에 대기
[큐도 가득 참] → TCP Connection Refused (HTTP 응답조차 못 나감!)
```

**중요한 디테일**: 큐까지 가득 차면 클라이언트가 받는 것은 503 같은 HTTP 응답이 아니다. Tomcat이 **TCP 연결 자체를 거부** 하기 때문에, HTTP 요청을 보낼 기회도 없이 OS 레벨에서 `Connection refused` 에러가 발생한다.

503은 보통 **로드밸런서(Nginx, ALB)** 가 백엔드 다운을 판단했거나, Spring이 명시적으로 거부할 때 발생한다.

> **면접 예상 질문:** Tomcat 스레드 풀이 가득 차고 accept-count 큐도 가득 찼을 때, 클라이언트는 어떤 응답을 받게 되나요? 그 이유는 무엇인가요?

---

### TCP 3-way handshake — SYN/ACK 신호의 의미

HTTP는 TCP 위에서 동작하므로, HTTP 요청 전에 항상 TCP 연결 수립 단계가 있다.

#### TCP가 필요한 이유

인터넷은 데이터를 작은 **패킷** 단위로 쪼개서 보낸다. 이 과정에서 발생할 수 있는 문제들:

| 문제 | 예시 |
|------|------|
| 패킷 분실 | 중간에 사라짐 |
| 순서 뒤바뀜 | 늦게 출발한 패킷이 먼저 도착 |
| 중복 | 같은 패킷이 두 번 도착 |
| 변조 | 데이터 깨짐 |

TCP는 **패킷마다 순서 번호를 매기고, 손실 시 재전송하며, 도착 확인(ACK)** 까지 받아서 데이터 정확성을 보장한다. 그래서 신뢰성이 중요한 HTTP/이메일/파일 전송은 TCP, 속도가 중요한 게임/영상통화는 UDP를 쓴다.

#### 3-way handshake


<img width="659" height="333" alt="image" src="https://github.com/user-attachments/assets/6360102f-22f1-4ce1-98f0-d6630f1f2bfc" />



```
클라이언트 → SYN          → 서버    ("연결하고 싶어요!")
클라이언트 ← SYN+ACK     ← 서버    ("좋아요, 저도 연결할게요!")
클라이언트 → ACK          → 서버    ("잘 받았어요!")
→ 이제 HTTP 데이터 주고받기 시작!
```

- **SYN** = Synchronize (씬) — 연결 시작 요청
- **ACK** = Acknowledge (액) — 잘 받았다는 확인 응답

SYN과 ACK은 TCP 패킷 헤더의 **플래그(깃발)** 다. 켜져있다(1) / 꺼져있다(0)로 표시된다.

#### 왜 3번이나 주고받나?

**양방향(클라이언트 ↔ 서버) 모두에서 송수신이 가능한지를 검증** 하려면 최소 3번이 필요하다. 1, 2번은 서버가 클라이언트의 능력을 확인하고, 3번에서 클라이언트가 서버의 능력을 확인 완료한다.

> **면접 예상 질문:** TCP 3-way handshake가 왜 3번 주고받는지, 그리고 SYN/ACK이 정확히 어떤 신호인지 설명해주세요.

---

### Blocking I/O 한계 — OS 관점 vs Tomcat 관점

Thread per Request 모델의 가장 큰 한계. 헷갈리기 쉬운 부분이다.

#### 상황

```java
@GetMapping("/users/{id}")
public User getUser(@PathVariable Long id) {
    User user = externalApiClient.fetch(id);  // 외부 API 호출 (5초 소요)
    return user;
}
```

이 5초 동안, 스레드는 어떤 상태인가?

#### 같은 스레드, 다른 관점

**같은 스레드를 두 관점에서 봐야 한다.**

| | OS 관점 (CPU) | Tomcat 관점 (스레드 풀) |
|---|---|---|
| **상태** | 스레드가 WAITING → CPU 안 씀 | 스레드가 요청에 묶여 있음 |
| **공유?** | ✅ CPU는 다른 스레드한테 양보 (Context Switching) | ❌ 스레드는 그 요청에 고정 |

```
[OS 관점]
"#42는 socket.read()에서 멈춰있네. WAITING 상태!
 CPU는 다른 스레드(#1, #2, #3...)한테 줘야지."
→ CPU 자원은 효율적으로 활용됨 ✅

[Tomcat 관점]
"#42는 GET /users/1 요청을 처리 중이야.
 요청의 컨텍스트(헤더, 세션, 트랜잭션...)를 다 들고 있어.
 다른 요청이 #42를 가져다 쓰면 컨텍스트가 꼬여!"
→ #42는 요청 A에 묶여 있음 🔒
```

#### 회사원 비유

회사원 김철수가 점심을 먹으러 갔다.

- **인사팀 관점** — 김철수는 출근해 있고 프로젝트 A 담당이므로, **다른 직원이 김철수 자리에 와서 김철수 일을 대신할 수 없음**
- **회사 빌딩 관점** — 김철수가 점심 먹는 동안 엘리베이터(CPU)는 다른 직원들이 잘 쓰고 있음

#### 그래서 뭐가 문제?

CPU는 한가한데, **스레드 풀(200개)이 다 I/O 대기 중이면 새 요청을 못 받는** 역설적인 상황이 발생한다. 자원은 멀쩡한데 서버가 다운된 것처럼 보인다.

이걸 해결하려고 등장한 게 **WebFlux (Non-Blocking I/O)** 다. 스레드를 요청에 묶지 않고, I/O 대기 시 즉시 풀려나서 다른 요청을 처리할 수 있게 한다 (이벤트 루프 방식).

> **면접 예상 질문:** Thread per Request 모델에서 Blocking I/O가 발생했을 때, OS 관점과 Tomcat 관점에서 스레드의 상태는 어떻게 다른가요? 이 한계를 극복하기 위해 등장한 모델은 무엇인가요?

---

### Filter vs Interceptor vs AOP — 동작 시점과 레이어


<img width="659" height="333" alt="image" src="https://github.com/user-attachments/assets/5d8e5e3b-e6d8-4c8c-9589-e19d05f19ad3" />


셋 다 요청을 가로채는 역할이지만, **동작하는 레이어와 시점** 이 다르다.

```
[클라이언트 요청]
       ↓
🔵 ────── Filter ────── 🔵   ← 서블릿 컨테이너 (Tomcat) 영역
       ↓
[DispatcherServlet]
       ↓
🟢 ──── Interceptor ──── 🟢  ← Spring MVC 영역
       ↓
[Controller 메서드 진입]
       ↓
🟣 ────── AOP ────── 🟣      ← Spring Bean 메서드 영역
       ↓
[비즈니스 로직 실행]
```

| | Filter | Interceptor | AOP |
|---|---|---|---|
| **레이어** | 서블릿 컨테이너 (Tomcat) | Spring MVC | Spring Bean |
| **언제 동작?** | DispatcherServlet 전/후 | DispatcherServlet 후, Controller 전/후 | 메서드 호출 전/후 |
| **Spring 빈?** | ❌ (원래는 아님) | ✅ | ✅ |
| **대상** | 모든 요청 (정적 리소스 포함) | DispatcherServlet 거치는 요청만 | 특정 메서드 (지정한) |
| **예시 용도** | 인코딩, CORS, JWT 인증 | 로그인 체크, 권한 검증 | 로깅, 트랜잭션, 캐싱 |

#### 한 줄 비유

- **Filter** = 회사 정문 보안 (모든 사람 검문)
- **Interceptor** = 사무실 입구 출입증 (해당 부서 직원만 검문)
- **AOP** = 책상 옆 보조 (특정 사람만 옆에서 도와줌)

> **면접 예상 질문:** Filter, Interceptor, AOP는 모두 요청을 가로채는 역할인데, 인증 처리는 어디에 두는 게 좋을지 각각의 장단점과 함께 설명해주세요.

---

### Spring AOP — 프록시 패턴과 Self-Invocation 문제

#### AOP는 무엇인가

AOP(Aspect-Oriented Programming, 관점 지향 프로그래밍)는 **공통 관심사(Cross-cutting Concerns)** 를 비즈니스 로직과 분리하는 패러다임이다.

```java
// AOP 없이
public User getUser(Long id) {
    log.info("getUser 시작");
    long start = System.currentTimeMillis();
    User user = userRepository.findById(id);
    log.info("getUser 종료: " + (System.currentTimeMillis() - start) + "ms");
    return user;
}

// AOP 적용 후 — 비즈니스 로직만 깔끔
public User getUser(Long id) {
    return userRepository.findById(id);
}
```

#### 동작 원리 — 프록시 패턴

Spring AOP는 **프록시 객체** 를 통해 동작한다. `@Transactional` 이 붙은 메서드를 호출하면, 우리가 만든 객체가 직접 호출되는 게 아니라 **Spring이 몰래 만든 프록시 객체** 가 가로챈다.

```
[당신이 호출] userService.updateUser(1L)
       ↓
[프록시 객체가 가로챔]  ← Spring이 자동 생성
       ↓
🟢 트랜잭션 시작 (BEGIN TRANSACTION)
       ↓
[진짜 UserService.updateUser() 실행]
       ↓
🟢 트랜잭션 커밋 (COMMIT) — 예외 시 ROLLBACK
       ↓
[당신에게 결과 반환]
```

비즈니스 로직 **앞뒤로** 부가 기능이 끼어드는 이 패턴이 정확히 AOP다. 그래서 `@Transactional`, `@Async`, `@Cacheable`, `@Secured` 같은 어노테이션은 모두 AOP로 구현되어 있다.

#### Self-Invocation 문제

프록시는 **빈 외부에서 호출할 때만 가로챈다**. 같은 클래스 내부에서 `this.method()` 형태로 호출하면 프록시를 우회한다.

```java
@Service
public class UserService {
    public void outerMethod() {
        innerMethod();  // ← this.innerMethod() — 프록시 우회!
    }
    
    @Transactional
    public void innerMethod() {
        // 트랜잭션이 동작하지 않음 💥
    }
}
```

```
[외부 호출] ✅ AOP 동작
client → 프록시 → outerMethod()
                  → this.innerMethod()  ← 진짜 객체 직접 호출
                  → @Transactional 무시됨 💥
```

#### 해결책

1. **메서드를 별도 빈으로 분리** (가장 권장 — 책임 분리에도 부합)
2. **자기 자신을 빈으로 주입** (`@Autowired private UserService self;`)
3. AspectJ 컴파일타임 위빙 (드물게 사용)

> **면접 예상 질문:** `@Transactional`이 같은 클래스 내부 호출에서 동작하지 않는 이유를 프록시 패턴 관점에서 설명하고, 해결 방법을 제시해주세요.

---

## 학습 정리

- Spring Boot의 HTTP 요청 처리 흐름은 **Tomcat → Filter → DispatcherServlet → HandlerMapping(찾기) → Interceptor → HandlerAdapter(호출) → AOP → Controller** 순서로 이루어진다.
- `HandlerMapping`과 `HandlerAdapter`는 **"누가"와 "어떻게"** 의 책임을 분리한 Adapter 디자인 패턴의 적용이다.
- Tomcat은 Thread per Request 모델을 사용하며, 스레드 풀이 가득 차면 `accept-count` 큐에 쌓이고, 큐까지 가득 차면 **TCP Connection Refused** 가 발생한다 (HTTP 응답이 아니다).
- Blocking I/O 시 같은 스레드라도 **OS 관점에선 CPU를 양보** 하지만 **Tomcat 관점에선 요청에 묶여 있어** 다른 요청이 그 슬롯을 쓸 수 없다. 이게 Thread per Request의 한계이며, WebFlux 등장 배경이다.
- Filter / Interceptor / AOP는 각각 **서블릿 컨테이너 / Spring MVC / Spring Bean 메서드** 레이어에서 동작한다.
- Spring AOP는 프록시 객체로 동작하므로, **같은 클래스 내부 호출 시 프록시를 우회** 하여 `@Transactional` 같은 부가 기능이 적용되지 않는다 (Self-Invocation 문제).

## 참고

- 이 글은 면접 대비 학습 대화를 정리한 것으로, 외부 자료 인용은 없다.
