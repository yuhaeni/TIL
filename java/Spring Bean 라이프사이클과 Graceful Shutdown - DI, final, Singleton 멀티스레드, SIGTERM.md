# Spring Bean 라이프사이클과 Graceful Shutdown — DI 3가지, final, Singleton 멀티스레드, SIGTERM

> 날짜: 2026-05-22

## 내용

### 빈 라이프사이클 전체 흐름 — 6단계

Spring Bean이 생성되어 사용되고 소멸되기까지의 전체 흐름.

```
1. 🌱 인스턴스화        — JVM Heap에 객체 할당, 의존성은 아직 null
       ↓
2. 💉 의존성 주입 (DI)   — Spring이 필요한 빈을 주입
       ↓
3. ⏰ @PostConstruct    — 초기화 콜백 (모든 의존성 준비 완료 시점)
       ↓
4. 🏃 빈 사용            — 실제 서비스 운영 중
       ↓
5. 🛑 @PreDestroy       — 소멸 직전 정리 콜백
       ↓
6. ☠️ 빈 소멸           — 컨테이너에서 제거
```

- 인스턴스화는 **Spring이 리플렉션으로 `new MyService()`를 대신 호출**한다.
- 인스턴스화 직후엔 의존성 필드가 모두 `null` 상태 ("속이 빈 깡통")
- `@PostConstruct`는 의존성 주입이 완료된 후 실행되므로, **의존성을 활용한 초기화 작업의 안전한 시점**이다.

> **면접 예상 질문:** Spring Bean이 생성되어 소멸되기까지의 전체 라이프사이클을 단계별로 설명하고, 각 단계에서 개발자가 개입할 수 있는 콜백 지점은 어디인지 설명해주세요.

---

### 의존성 주입(DI) 3가지 방식 — 생성자 주입이 권장되는 4가지 이유

#### 3가지 DI 방식

```java
// 1. 생성자 주입 (Constructor Injection) — 권장 ⭐
@Service
public class UserService {
    private final UserRepository userRepository;

    public UserService(UserRepository userRepository) {
        this.userRepository = userRepository;
    }
}

// 2. 필드 주입 (Field Injection) — 비추
@Service
public class UserService {
    @Autowired
    private UserRepository userRepository;
}

// 3. 세터 주입 (Setter Injection) — 거의 안 씀
@Service
public class UserService {
    private UserRepository userRepository;

    @Autowired
    public void setUserRepository(UserRepository repo) { this.userRepository = repo; }
}
```

Spring 4.3+ 부터 생성자가 1개면 `@Autowired` 생략 가능. Lombok의 `@RequiredArgsConstructor` 와 `final` 필드 조합이 사실상 표준.

#### 생성자 주입이 권장되는 4가지 이유

| 이유 | 생성자 주입 🟢 | 필드 주입 🔴 |
|------|------------|-----------|
| **1. final 필드** | ✅ 가능 (불변성, Thread-safe) | ❌ 불가능 |
| **2. 순환 참조 발견** | ✅ 시작 시점 즉시 발견 (Fail Fast) | ❌ 운영 중 NPE로 터짐 |
| **3. 단위 테스트** | ✅ Spring 없이 `new` 로 생성 가능 | ❌ 리플렉션/@SpringBootTest 필요 |
| **4. 필수 의존성** | ✅ 컴파일러가 강제 (NPE 원천 차단) | ❌ Spring 외부에서 `new` 시 영원히 null |

특히 **순환 참조** 의 경우 차이가 크다:

- 생성자 주입: 애플리케이션 시작 시 `BeanCurrentlyInCreationException` 즉시 발생 → 배포 전 발견
- 필드 주입: 시작은 멀쩡, 실제 메서드 호출 시점에 NPE → 운영 장애

> **면접 예상 질문:** 생성자 주입과 필드 주입의 차이, 그리고 생성자 주입이 권장되는 4가지 이유를 설명해주세요.

---

### `final` 키워드의 정확한 의미와 필드 주입 충돌

#### `final` 의 정확한 의미

흔한 오해: "변경 불가"
정확한 의미: **"정확히 한 번만 할당 가능 (Assign Exactly Once)"**

합법적인 초기화 시점은 **두 곳뿐**:
1. 선언과 동시에 (`private final String name = "철수";`)
2. 생성자 안에서 (`this.name = "철수";`)

생성자가 끝나는 순간이 "객체가 완성되는 순간"이고, 그 이후엔 final 필드가 **"잠긴" 상태** 가 되어 변경 불가.

```java
public class A {
    private final String name;   // 1단계: 선언만

    public A() {
        this.name = "철수";       // ✅ 첫 번째 할당
        // this.name = "영희";   // ❌ 두 번째 할당 시도 → 컴파일 에러
    }                            // 2단계: 생성자 종료 — final 잠김

    public void rename(String newName) {
        this.name = newName;     // ❌ 컴파일 에러 — 이미 잠겼음
    }
}
```

#### 필드 주입에서 final이 안 되는 이유

```java
public class UserService {
    @Autowired
    private final UserRepository userRepository;  // 컴파일 에러!
    //              ↑
    //   선언 시 초기화 X (= 없음)
    //   생성자에서 초기화 X (생성자 없음, 또는 기본 생성자)
    //   → final 규칙 위반
    //
    //   @Autowired는 생성자 끝난 후 리플렉션으로 주입
    //   → 이미 final 잠긴 상태 → 또 충돌
}
```

#### 필드 주입의 null 위험 메커니즘

**객체 생성 시점 ≠ 의존성 주입 시점** 이 핵심.

| 방식 | 객체 생성 시점 | 의존성 주입 시점 | null 구간 |
|------|------------|-------------|---------|
| **생성자 주입** | 의존성과 함께 동시 | 동시 | 없음 |
| **필드 주입** | 빈 객체 먼저 생성 | 리플렉션으로 나중 주입 | 잠깐 존재 |

진짜 위험한 시나리오: **Spring 컨테이너 밖에서 `new UserService()` 호출 시 영원히 null** → NPE.

> **면접 예상 질문:** `@Autowired` 필드 주입에서 `final` 키워드를 쓸 수 없는 이유와, 필드 주입이 null 위험을 가지는 메커니즘을 설명해주세요.

---

### 빈 스코프 — Singleton vs Prototype

| 스코프 | 인스턴스 개수 | 컨테이너의 소멸 관리 |
|-------|------------|---------------|
| **`singleton`** ⭐ | 컨테이너 당 1개 (기본값) | ✅ 끝까지 책임 (`@PreDestroy` 호출) |
| **`prototype`** | 요청마다 새 인스턴스 | ❌ 생성만 하고 손 뗌 (`@PreDestroy` 호출 X) |
| `request` / `session` / `application` / `websocket` | 웹 컨텍스트별 | 컨텍스트 따라감 |

#### 흔한 오해

```
❌ "Singleton = JVM 전체에서 1개"
✅ "Singleton = Spring 컨테이너 당 1개" (컨테이너 2개면 빈도 2개)
```

#### Prototype의 함정

```java
@Component
@Scope("prototype")
public class ReportGenerator {
    @PreDestroy
    public void cleanup() {  // ❌ 절대 호출 안 됨!
        // ...
    }
}
```

Prototype 빈은 **컨테이너가 생성만 해주고 그 이후는 개발자 책임**. GC가 알아서 정리할 때까지 기다리거나 직접 정리 호출 필요.

> **면접 예상 질문:** Spring Bean의 기본 스코프는 무엇이며, Singleton과 Prototype의 차이를 설명해주세요. Prototype 빈에서 주의할 점은 무엇인가요?

---

### Singleton + Prototype 트랩 — 5년차 단골 함정 질문

```java
@Service  // Singleton
public class OrderService {
    @Autowired
    private ReportGenerator reportGenerator;  // Prototype 빈!

    public void createOrder() {
        reportGenerator.generate();  // 매번 새 인스턴스일까?
    }
}
```

**결과: Singleton처럼 작동한다!** Prototype의 의미가 무효화됨.

#### 왜 그런가?

```
[애플리케이션 시작 시점]
1. OrderService 생성
   ↓
2. ReportGenerator 한 번 주입
   → orderService.reportGenerator = ReportGenerator@1234 (고정)

[이후 운영 중]
createOrder() 1번째 호출 → ReportGenerator@1234
createOrder() 100번째 호출 → ReportGenerator@1234  ← 같은 객체!
```

DI는 **주입 시점에 한 번만** 일어난다. Singleton은 시작 시 한 번 생성되며 의존성도 그때 고정됨.

#### 해결책 4가지

| 해결책 | 코드 | 추천도 |
|--------|------|--------|
| `ApplicationContext.getBean()` | `context.getBean(Prototype.class)` | ❌ Service Locator 안티패턴 |
| `ObjectFactory<T>` / `Provider<T>` | `factory.getObject()` | ⭐⭐⭐ 명시적 |
| `@Scope(proxyMode = TARGET_CLASS)` | 프록시가 매번 새 객체로 위임 | ⭐⭐⭐ 코드 변경 없음 |
| `@Lookup` | 추상 메서드를 Spring이 구현 | ⭐⭐ |

```java
// ObjectFactory 방식 (가장 명시적)
@Service
public class OrderService {
    private final ObjectFactory<ReportGenerator> factory;

    public OrderService(ObjectFactory<ReportGenerator> factory) {
        this.factory = factory;
    }

    public void createOrder() {
        ReportGenerator generator = factory.getObject();  // 매번 새 객체
    }
}
```

> **면접 예상 질문:** Singleton 빈에 Prototype 빈을 직접 주입하면 어떤 현상이 발생하며, 어떻게 해결할 수 있나요?

---

### GoF Singleton vs Spring Singleton — 본질적 차이

| 비교 | GoF Singleton | Spring Singleton |
|------|--------------|------------------|
| **범위** | JVM 당 1개 (전역) | 컨테이너 당 1개 |
| **강제 방식** | 클래스 자체가 강제 (private 생성자) | 컨테이너가 관리 (생성자 자유) |
| **접근 방법** | `Singleton.getInstance()` | `@Autowired` / `getBean()` |
| **결합도** | 강함 (Singleton 클래스에 종속) | 약함 (DI 받음) |
| **테스트** | 어려움 (대체 불가) | 쉬움 (Mock 주입 가능) |
| **인스턴스 가변성** | 절대 1개 | 컨테이너 여러 개면 가능 |

```java
// GoF 방식 — 강한 결합
public class MyService {
    private static final MyService INSTANCE = new MyService();
    private MyService() {}
    public static MyService getInstance() { return INSTANCE; }
}
MyService service = MyService.getInstance();  // 클래스에 강결합, 테스트 어려움

// Spring 방식 — 약한 결합
@Service
public class MyService {
    public MyService() {}  // 생성자 자유
}
@Autowired private MyService service;  // Mock 주입 가능, 테스트 쉬움
```

**Spring은 Singleton의 효과(인스턴스 통제)는 가져오되 단점(강결합, 테스트 곤란)은 제거** 했다.

#### Java에서 Singleton 패턴 구현 방법

1. **Eager Initialization**: 클래스 로딩 시 생성, Thread-safe, 메모리 낭비 가능
2. **Lazy + synchronized**: Thread-safe, 성능 저하
3. **Double-Checked Locking (DCL)**: Thread-safe + 락 최소화, `volatile` 필수
4. **Bill Pugh (Holder)**: Lazy + Thread-safe + 락 없음 (정적 내부 클래스 활용)
5. **Enum Singleton**: Effective Java 권장. Thread-safe, 직렬화/리플렉션 공격 방어, 가장 간결

> **면접 예상 질문:** GoF의 Singleton 패턴과 Spring의 Singleton 빈은 어떻게 다른가요? Java에서 Singleton을 구현하는 가장 좋은 방법은 무엇인가요?

---

### Singleton 빈에서 상태를 가지면 안 되는 이유 — 멀티스레드의 함정

Tomcat은 요청마다 다른 스레드가 처리한다 (Thread per Request). Singleton 빈은 컨테이너에 1개만 존재하므로 **200개 스레드가 같은 객체를 공유** 한다.

#### 시나리오 1: 사용자 정보 섞임 (운영 장애 단골)

```java
@Service
public class OrderService {
    private User currentUser;  // ❌ 인스턴스 필드 (상태)

    public Order createOrder(Long userId, Product product) {
        this.currentUser = userRepository.findById(userId);
        validateUser();
        return new Order(currentUser, product);
    }

    private void validateUser() {
        if (currentUser.isBlocked()) throw new BlockedUserException();
    }
}
```

```
시간  김철수 요청 (스레드1)        이영희 요청 (스레드2)
────  ──────────────────         ──────────────────
T1   currentUser = 김철수
T2                              currentUser = 이영희   ← 덮어씀!
T3   validateUser()
     → 이영희를 검증!            ← 💥
T4   new Order(이영희, A)       ← 김철수 주문에 이영희 정보!
```

#### 시나리오 2: Race Condition (`count++` 가 원자적이지 않음)

```java
private int count = 0;
public void record() { count++; }
```

`count++` 는 사실 READ → MODIFY → WRITE 3단계. 두 스레드가 동시에 READ하면 같은 값을 읽어서 같은 값을 쓰게 됨 → 카운트 누락.

#### 시나리오 3: 메모리 가시성 (CPU 캐시 문제)

```java
private boolean ready = false;
public void init() { ready = true; }     // 스레드 1
public boolean isReady() { return ready; }  // 스레드 2 — 영원히 false일 수 있음
```

스레드 1이 자기 L1 캐시의 `ready` 만 갱신하고 메인 메모리에 반영 안 되면, 스레드 2는 자기 캐시의 `false` 만 본다. `volatile` 키워드로 해결.

#### 올바른 설계 — 무상태(Stateless)

```java
@Service
public class OrderService {
    private final UserRepository userRepository;  // 의존성만 (final, 불변)

    public Order createOrder(Long userId, Product product) {
        User user = userRepository.findById(userId);  // 지역변수
        validateUser(user);                            // 파라미터로 전달
        return new Order(user, product);
    }

    private void validateUser(User user) {  // 파라미터로 받음
        if (user.isBlocked()) throw new BlockedUserException();
    }
}
```

**지역변수는 스레드마다 별도의 스택에 저장** 되므로 안전.

#### 진짜 상태가 필요할 때

| 상황 | 도구 |
|------|------|
| 단순 카운터 | `AtomicInteger` (Lock-free, 빠름) |
| Map/List 공유 | `ConcurrentHashMap`, `CopyOnWriteArrayList` |
| 복잡한 로직 락 | `synchronized` 또는 `ReentrantLock` |
| 스레드별 독립 데이터 | `ThreadLocal` (⚠️ `remove()` 필수 — 메모리 누수 방지) |

> **면접 예상 질문:** Spring의 Singleton 빈에서 인스턴스 필드를 가지면 안 되는 이유를 멀티스레드 관점에서 설명하고, 공유 상태가 진짜로 필요한 경우 어떤 도구들이 있는지 설명해주세요.

---

### `@PreDestroy` 와 빈 소멸 단계

빈이 소멸되기 직전 컨테이너가 자동으로 호출하는 콜백. `@PostConstruct` 의 정반대.

```java
@Service
public class CacheService {
    private Connection redisConnection;

    @PostConstruct
    public void init() {
        this.redisConnection = redisPool.getConnection();
    }

    @PreDestroy
    public void cleanup() {
        if (redisConnection != null) redisConnection.close();
        log.info("Cache cleanup 완료");
    }
}
```

활용 사례:
- DB/Redis/Kafka 연결 종료
- 스레드 풀 shutdown
- 임시 파일 삭제
- 캐시 flush (메모리 → 디스크)

⚠️ **Prototype 빈에서는 호출되지 않음** — 위 스코프 섹션 참고.

> **면접 예상 질문:** `@PreDestroy` 는 언제 호출되며, Prototype 스코프 빈에서는 어떻게 동작하나요?

---

### Graceful Shutdown — SIGTERM과 우아한 종료

운영 환경에서 배포 시 진행 중인 요청을 안전하게 끝낸 후 종료하는 방식.

#### 강제 종료의 위험 (SIGKILL)

```
[결제 처리 중 강제 종료 시]
- DB 트랜잭션: 중간에 끊김 → 일부 commit / 일부 rollback
- 외부 PG사: 돈은 빠져나갔는데 우리 DB엔 주문 없음 💀
- 사용자: 결제 실패 화면 보고 재시도 → 이중 결제!
```

#### SIGTERM vs SIGKILL

| 신호 | 설명 | 동작 |
|------|------|------|
| **SIGTERM** (kill -15) | 정중한 종료 요청 | 프로세스가 받아 정리 가능 |
| **SIGKILL** (kill -9) | 즉시 죽어! | 커널이 강제 종료, 정리 불가 |

K8s는 Pod 종료 시 먼저 SIGTERM → `terminationGracePeriodSeconds` 동안 대기 → 안 죽으면 SIGKILL.

#### Graceful Shutdown 4단계

```
[T+0초]  SIGTERM 수신
   ↓
[T+0초]  Tomcat: 새 요청 거부 시작 (503 또는 Connection Refused)
   ↓
[T+0~N초] 진행 중인 요청 처리 (최대 timeout-per-shutdown-phase 까지)
   ↓
[T+N초]  빈 소멸 시작 (@PreDestroy 호출)
   ↓
[T+N초]  ApplicationContext 닫힘 → JVM 종료
```

#### Spring Boot 설정 (2.3+)

```yaml
server:
  shutdown: graceful                    # 핵심 (기본값: immediate)

spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s     # 진행 중 요청 대기 시간 (기본 30초)
```

두 줄로 적용 완료.

> **면접 예상 질문:** 운영 중인 Spring Boot 서버를 배포로 재시작할 때 진행 중인 요청이 끊기지 않게 하려면 어떻게 해야 하나요? Graceful Shutdown 의 동작 단계를 설명해주세요.

---

### Kubernetes 환경에서 Graceful Shutdown 통합

#### timeout 함정

```yaml
# Pod 설정
terminationGracePeriodSeconds: 30   # K8s 기본 30초

# Spring 설정
spring.lifecycle.timeout-per-shutdown-phase: 60s   # Spring은 60초 기다림
```

⚠️ K8s가 30초 후 SIGKILL을 보내므로 **결국 30초에 강제 종료**. Spring timeout이 무의미해짐.

**원칙: K8s timeout ≥ Spring timeout + 여유**

```yaml
terminationGracePeriodSeconds: 60   # K8s가 더 길게
spring.lifecycle.timeout-per-shutdown-phase: 30s
```

#### preStop 훅 — 로드밸런서 갱신 시간 확보

```yaml
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 10"]   # SIGTERM 전 10초 대기
```

왜 필요?

```
K8s 종료 절차:
1. 로드밸런서에서 Pod 제거 (시간 걸림 — 몇 초)
2. 동시에 SIGTERM 전송 (즉시)

→ 문제: 아직 로드밸런서 갱신 안 됐는데 Pod는 이미 종료 중
→ 일부 트래픽이 죽어가는 Pod로 갈 위험

preStop으로 10초 대기 → 로드밸런서 갱신 시간 확보 → SIGTERM 전송
```

> **면접 예상 질문:** Kubernetes 환경에서 Spring Boot의 Graceful Shutdown 을 안전하게 운영하려면 어떤 설정을 고려해야 하나요? preStop 훅은 왜 필요한가요?

---

## 학습 정리

- **빈 라이프사이클은 6단계** — 인스턴스화 → DI → `@PostConstruct` → 사용 → `@PreDestroy` → 소멸. Singleton 빈만 컨테이너가 끝까지 책임지고, Prototype은 생성 후 손 뗀다.
- **생성자 주입이 권장되는 4가지 이유** — `final` 필드 가능(불변성), 순환 참조를 시작 시점에 발견, 단위 테스트 쉬움, 필수 의존성을 컴파일러가 강제. Spring 4.3+ 부터 생성자 1개면 `@Autowired` 생략 가능하므로 `@RequiredArgsConstructor` + `final` 필드가 표준.
- **`final` 은 "변경 불가"가 아니라 "정확히 한 번만 할당 가능"** — 합법적 시점은 선언 시와 생성자 안 두 곳뿐. 필드 주입은 생성자 후 리플렉션 주입이라 `final` 과 충돌하고, 컨테이너 밖에서 `new` 호출 시 영원히 null이 되는 위험이 있다.
- **Singleton 빈에 Prototype을 직접 주입하면 Singleton처럼 작동** — 주입은 한 번만 일어나기 때문. `ObjectFactory<T>` 나 `@Scope(proxyMode = TARGET_CLASS)` 로 해결.
- **Singleton 빈에 인스턴스 필드(상태)를 가지면 멀티스레드 환경에서 Race Condition 발생** — 사용자 정보 섞임, 카운트 누락, 메모리 가시성 문제. 무상태(Stateless) 설계가 원칙이며, 진짜 상태가 필요하면 `AtomicInteger` / `ConcurrentHashMap` / `synchronized` / `ThreadLocal` 을 상황에 맞게.
- **Graceful Shutdown은 SIGTERM 수신 시 새 요청 거부 → 진행 중 요청 처리 → 빈 소멸 → JVM 종료의 4단계** — Spring Boot 2.3+ 에서 `server.shutdown=graceful` + `spring.lifecycle.timeout-per-shutdown-phase` 두 줄로 적용. K8s 환경에선 `terminationGracePeriodSeconds` 가 Spring timeout 보다 커야 하며, `preStop` 훅으로 로드밸런서 갱신 시간을 확보해야 안전하다.

## 참고

- 이 글은 면접 대비 학습 대화를 정리한 것으로, 외부 자료 인용은 없다.
