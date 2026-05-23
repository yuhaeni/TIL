# Spring Boot 부팅 과정 — JAR vs WAR, 자동 설정, ComponentScan, IoC 컨테이너

> 날짜: 2026-05-22

## 내용

### JAR vs WAR — 패키징 방식과 Tomcat의 위치 변화

둘 다 그냥 ZIP 압축 파일이다. 확장자만 다르고, **내부 구조와 실행 방식** 이 다르다.

| | JAR (Spring Boot 기본) | WAR (전통 방식) |
|---|---|---|
| 풀네임 | **J**ava **AR**chive | **W**eb **A**pplication **AR**chive |
| 내부 구조 | 자유로움 | `WEB-INF/`, `classes/`, `lib/` 강제 |
| **Tomcat** | **내장** (의존성으로 포함) | **외부에 따로 설치** |
| 실행 | `java -jar app.jar` | Tomcat의 `webapps/` 에 배포 |
| 포트 설정 | `application.yml` | Tomcat 설정 파일 |
| 클라우드 친화적 | ✅ Docker/K8s 최적 | ❌ 약함 |

#### 주체가 거꾸로 뒤집힌 게 핵심

```
[WAR 방식 — 옛날]
Tomcat이 "집(컨테이너)" 🏠
WAR은 그 안에 들어가는 "세입자"
→ Tomcat이 주체

[JAR 방식 — Spring Boot]
앱이 "주체" 🦆
Tomcat은 의존성으로 포함된 "부품"
→ JAR 안에 tomcat-embed-core.jar 가 들어있음
```

`my-app.jar` 의 내부 구조 예시:

```
my-app.jar
├─ com/example/MyApplication.class
├─ BOOT-INF/
│   └─ lib/
│       ├─ tomcat-embed-core.jar   ← Tomcat이 라이브러리로 포함!
│       ├─ spring-web.jar
│       └─ ...
└─ ...
```

**자기 완결성(Self-contained)** 덕분에 `java -jar`만으로 어디서든 실행 가능하고, Docker 이미지 만들기도 간단하다.

```dockerfile
FROM openjdk:17
COPY my-app.jar /app/
CMD ["java", "-jar", "/app/my-app.jar"]
```

> **면접 예상 질문:** JAR와 WAR의 차이를 패키징 구조와 실행 방식 관점에서 설명하고, Spring Boot가 JAR + 내장 톰캣 방식을 채택한 이유를 설명해주세요.

---

### Spring Boot 부팅 8단계 — `SpringApplication.run()` 내부에서 일어나는 일

```java
@SpringBootApplication
public class MyApplication {
    public static void main(String[] args) {
        SpringApplication.run(MyApplication.class, args);
        // ↑ 이 한 줄 안에서 아래 단계들이 순차 실행됨
    }
}
```

```
1️⃣  @SpringBootApplication 어노테이션 해석
       ↓
2️⃣  SpringApplication 객체 생성 (웹앱 타입 결정 — Servlet/Reactive/None)
       ↓
3️⃣  Environment 준비 (application.yml, 환경변수, 커맨드라인 인자 통합)
       ↓
4️⃣  ApplicationContext 생성 (IoC 컨테이너 — 보통 AnnotationConfigServletWebServerApplicationContext)
       ↓
5️⃣  자동 설정 (Auto Configuration) 적용
       ↓
6️⃣  ComponentScan으로 사용자 정의 빈 후보 찾기
       ↓
7️⃣  Bean 생성 + 의존성 주입 + @PostConstruct 호출
       ↓
8️⃣  내장 Tomcat 시작 + DispatcherServlet 등록
       ↓
   🎉 8080 포트 대기 시작 (main() 메서드 종료, Tomcat 데몬 스레드 동작)
```

`main()` 은 끝나지만 Tomcat이 **데몬이 아닌 스레드** 로 계속 동작해서 애플리케이션이 종료되지 않는다.

> **면접 예상 질문:** Spring Boot의 `SpringApplication.run()` 한 줄이 호출되면 내부에서 어떤 일들이 일어나는지 순서대로 설명해주세요.

---

### `@SpringBootApplication` — 사실은 3개 어노테이션의 합성

```java
@SpringBootConfiguration  // = @Configuration (설정 클래스 표시)
@EnableAutoConfiguration  // 자동 설정 활성화
@ComponentScan            // 컴포넌트 스캔 시작
public @interface SpringBootApplication {
```

| 합성된 어노테이션 | 역할 |
|----------------|------|
| `@SpringBootConfiguration` | 이 클래스가 빈 설정 정보를 담는다는 표시 (`@Configuration`과 동일) |
| `@EnableAutoConfiguration` | Spring Boot의 자동 설정 메커니즘 활성화 |
| `@ComponentScan` | 이 클래스의 패키지부터 하위 모든 패키지 스캔 |

> **면접 예상 질문:** `@SpringBootApplication`이 내부적으로 어떤 어노테이션들의 조합인지, 각각의 역할은 무엇인지 설명해주세요.

---

### 자동 설정 (Auto Configuration) — Spring Boot의 핵심 마법

#### 메커니즘

`spring-boot-autoconfigure.jar` 안에 자동 설정 후보 클래스들이 등록되어 있다.

```
spring-boot-autoconfigure.jar
└─ META-INF/spring/
   └─ org.springframework.boot.autoconfigure.AutoConfiguration.imports
      (= 자동 설정 후보 클래스 리스트, 수백 개)
```

리스트 예시:
- `DataSourceAutoConfiguration`
- `RedisAutoConfiguration`
- `WebMvcAutoConfiguration`
- `TomcatServletWebServerFactoryAutoConfiguration`
- ...

#### 무조건 다 켜지지 않는다 — `@Conditional` 조건부 활성화

```java
@Configuration
@ConditionalOnClass(DataSource.class)          // ← DataSource 클래스가 클래스패스에 있을 때만
@ConditionalOnMissingBean(DataSource.class)    // ← 내가 직접 만든 게 없을 때만
public class DataSourceAutoConfiguration {
    @Bean
    public DataSource dataSource() {
        // 자동으로 HikariCP DataSource 등록
    }
}
```

#### 실제 예시

```
spring-boot-starter-web 의존성 추가
       ↓
클래스패스에 Tomcat 클래스 존재
       ↓
@ConditionalOnClass(Tomcat.class) 조건 만족
       ↓
TomcatServletWebServerFactory 자동 등록
       ↓
부팅 시 내장 Tomcat 시작 ✅
```

**핵심: "클래스패스에 뭐가 있느냐"에 따라 필요한 빈을 자동으로 등록** 해주는 것이 Auto Configuration의 본질이다.

> **면접 예상 질문:** Spring Boot의 자동 설정(Auto Configuration)이 어떤 메커니즘으로 동작하는지, `@Conditional` 어노테이션과의 관계는 무엇인지 설명해주세요.

---

### 빈 등록 어노테이션 가족 — 본질은 같고 의미적 구분

```
@Component (할아버지) 👴
   ├─ @Service        ("나는 비즈니스 로직!")
   ├─ @Repository     ("나는 데이터 접근!")
   ├─ @Controller     ("나는 웹 진입점!")
   │   └─ @RestController ("나는 REST API!")
   └─ @Configuration  ("나는 설정!")
```

| 어노테이션 | 용도 | 추가 기능 |
|----------|------|---------|
| `@Component` | 부모 어노테이션, 모든 빈의 기본 | 없음 |
| `@Service` | 비즈니스 로직 | 의미적 구분만 |
| `@Repository` | 데이터 접근 | **DB 예외를 Spring `DataAccessException`으로 변환** |
| `@Controller` | 웹 컨트롤러 | Spring MVC가 웹 진입점으로 인식 |
| `@RestController` | REST API 컨트롤러 | `@Controller` + `@ResponseBody` (자동 JSON 변환) |
| `@Configuration` | 빈 설정 클래스 | **`@Bean` 메서드 호출 시 싱글톤 보장** (CGLIB 프록시) |

#### `@Component` vs `@Configuration` vs `@Bean`의 차이

```
@Component         → 내 클래스를 빈으로 ("자기 자신을 등록")
@Configuration     → 내 메서드들이 만드는 객체를 빈으로 ("팩토리 역할")
@Bean              → 메서드 위에 붙여서 반환값을 빈으로 ("외부 라이브러리도 등록 가능")
```

내가 만든 클래스 → `@Component`/`@Service` 등.
외부 라이브러리 객체 (`HikariDataSource`, `RedisClient`) → `@Configuration` 클래스 안에서 `@Bean`.

> **면접 예상 질문:** `@Component`, `@Configuration`, `@Bean`의 차이는 무엇이며, 어떤 상황에서 어떤 것을 사용해야 하나요? `@Repository`만 가진 추가 기능이 있다면 무엇인가요?

---

### `@ComponentScan` — 빈 후보 탐색 메커니즘

#### 정의

**"이 패키지부터 시작해서 하위 모든 패키지를 뒤져서 `@Component` 계열 어노테이션이 붙은 클래스를 다 찾는다."**

#### 기본 스캔 범위

`@SpringBootApplication` 클래스가 위치한 패키지부터 **하위 모든 패키지**.

```
com.example.myapp
├─ MyApplication.java       ← @SpringBootApplication 여기!
├─ controller/
│  └─ UserController.java   ← 스캔됨 ✅
├─ service/
│  └─ UserService.java      ← 스캔됨 ✅
└─ repository/
   └─ UserRepository.java   ← 스캔됨 ✅
```

#### 흔한 실수: 형제 패키지는 스캔 안 됨

```
com.example
├─ myapp/
│  └─ MyApplication.java    ← @SpringBootApplication
└─ external/                ← 형제 패키지 (하위 X)
   └─ ExternalService.java  ← 스캔 안 됨! ❌
```

해결: `@ComponentScan(basePackages = {"com.example.myapp", "com.example.external"})` 명시.

> **면접 예상 질문:** `@ComponentScan`의 기본 스캔 범위는 어떻게 결정되며, 외부 패키지의 빈을 스캔하려면 어떻게 해야 하나요?

---

### IoC 컨테이너 — 정확한 정의와 세 개념 구분

#### 한 문장 정의

> **"객체의 생성, 의존성 연결, 라이프사이클을 개발자 대신 관리해주는 Spring의 핵심 객체."**

#### 세 개념을 구분해야 한다

| 개념 | 정체 | 한 줄 |
|------|------|------|
| **IoC** | 디자인 원칙 | "제어권을 프레임워크에 넘긴다" |
| **DI** | 구현 방법 | "필요한 객체를 외부에서 주입받는다" |
| **IoC 컨테이너** | 실제 객체 | "그 일을 하는 Spring의 실체" |

비유:
- IoC = "고객은 가만히 있고 직원이 서빙해야 한다" (원칙) 📜
- DI = "음식을 테이블로 가져다 주는 행위" (방법) 🍽️
- IoC 컨테이너 = "서빙하는 웨이터" (실체) 👨‍💼

#### IoC 컨테이너의 실체 = ApplicationContext

```java
ApplicationContext context = SpringApplication.run(MyApp.class);
//        ↑
//   이게 IoC 컨테이너의 실체!
//   메모리 어딘가에 떠 있는 "객체 하나"

UserService userService = context.getBean(UserService.class);
```

컨테이너 안엔 빈 저장소(`Map<String, Object>`), 빈 정의 정보(`BeanDefinition`), 환경 정보(`Environment`), 이벤트 발행 기능 등이 들어있다.

#### 컨테이너 안과 밖의 차이

```java
// 🚫 컨테이너 밖 — Spring 혜택 X
UserService service1 = new UserService(new UserRepository());
// @Transactional 무시됨, @Autowired 무시됨

// ✅ 컨테이너 안 — Spring 혜택 O
UserService service2 = context.getBean(UserService.class);
// @Transactional 동작 (프록시 적용), @Autowired 동작, 라이프사이클 콜백 동작
```

> **면접 예상 질문:** IoC와 DI와 IoC 컨테이너의 관계를 설명하고, `ApplicationContext`가 IoC 컨테이너의 실체라는 게 무슨 의미인지 설명해주세요.

---

### `ApplicationContext` 직접 사용은 안티패턴 — Service Locator

#### 일반적으로 직접 호출하지 않는다

```java
// ❌ 안티패턴 (Service Locator 패턴)
@Service
public class OrderService {
    private final ApplicationContext context;

    public void processOrder() {
        UserService userService = context.getBean(UserService.class);  // ← 안 좋음!
        userService.findUser();
    }
}

// ✅ 표준 (Constructor Injection)
@Service
public class OrderService {
    private final UserService userService;

    public OrderService(UserService userService) {  // ← Spring이 주입
        this.userService = userService;
    }
}
```

#### 왜 안티패턴인가? (4가지 이유)

1. **의존성이 숨겨짐** — 생성자만 봐선 뭐가 필요한지 모름
2. **테스트 어려워짐** — `ApplicationContext` 모킹은 매우 복잡
3. **Spring과 강하게 결합** — 코드가 Spring 없이 동작 안 함
4. **IoC 본질 위배** — "내가 컨테이너에서 꺼낸다" = IoC 안 한 거나 마찬가지

#### 정당하게 직접 쓰는 경우 (드물게)

| 사용 케이스 | 더 나은 방법 |
|----------|-----------|
| 동적 빈 선택 (전략 패턴) | `Map<String, Strategy>` 또는 `List<Strategy>` 주입으로 대체 가능 |
| `main` / 부트스트랩 | 그대로 사용 OK |
| 통합 테스트 | 그대로 사용 OK |
| 이벤트 발행 | `ApplicationEventPublisher` 주입 권장 |
| `static` 영역 | 비추, 설계 재고 권장 |

동적 빈 선택도 컨테이너 직접 호출 없이 대체 가능:

```java
@Service
public class PaymentService {
    private final Map<String, PaymentStrategy> strategies;

    // Spring이 빈 이름을 key로 한 Map 자동 주입!
    public PaymentService(Map<String, PaymentStrategy> strategies) {
        this.strategies = strategies;
    }
}
```

> **면접 예상 질문:** `ApplicationContext`를 코드에서 직접 호출해 `getBean()`으로 빈을 꺼내 쓰는 것이 안티패턴으로 분류되는 이유는 무엇이며, 동적으로 빈을 선택해야 하는 경우 어떤 대안이 있나요?

---

### `@PostConstruct` — 빈 초기화 콜백

#### 정의

**빈 생성과 의존성 주입이 모두 끝난 직후, Spring이 자동으로 호출하는 초기화 메서드.**

#### 빈 라이프사이클 흐름

```
1. 인스턴스화 (new UserService())
       ↓
2. 의존성 주입 (생성자/필드/세터)
       ↓
3. @PostConstruct 호출 ⭐ (초기화 작업)
       ↓
4. 빈 사용 가능 (서비스 운영 중)
       ↓
5. 종료 시 @PreDestroy 호출
       ↓
6. 빈 소멸
```

#### 왜 필요한가?

생성자에서는 다른 빈들이 모두 준비됐다는 보장이 없다. `@PostConstruct` 는 **모든 의존성 주입이 끝났다는 시점이 보장** 되므로, 의존성을 활용한 초기화 작업에 적합하다.

```java
@Service
public class CacheService {
    private final UserRepository userRepository;
    private Map<Long, User> cache;

    public CacheService(UserRepository userRepository) {
        this.userRepository = userRepository;
        // ❌ 여기서 userRepository.findAll() 호출은 위험
    }

    @PostConstruct
    public void init() {
        // ✅ 모든 의존성 주입 완료 보장 시점
        this.cache = userRepository.findAll().stream()
            .collect(Collectors.toMap(User::getId, u -> u));
    }
}
```

활용 사례:
- 캐시 미리 로드
- 외부 시스템 연결 초기화 (Redis, Kafka)
- 스케줄러 시작
- 빈 검증 (필수 필드 체크)

> **면접 예상 질문:** `@PostConstruct`는 언제 호출되며, 생성자에서 초기화 작업을 하면 안 되는 이유는 무엇인가요?

---

## 학습 정리

- **JAR vs WAR의 본질적 차이는 Tomcat의 위치** — WAR은 외부 Tomcat이 주체, JAR(Spring Boot)는 앱이 주체이고 Tomcat은 내장된 의존성. 자기 완결성 덕분에 Docker/MSA 시대에 표준이 됐다.
- **`SpringApplication.run()` 한 줄은 8단계 부팅 과정의 시작** — 어노테이션 해석 → SpringApplication 객체 생성 → Environment 준비 → ApplicationContext 생성 → 자동 설정 → ComponentScan → 빈 생성/DI/@PostConstruct → Tomcat 시작 + DispatcherServlet 등록.
- **자동 설정의 핵심은 `@Conditional`** — `spring-boot-autoconfigure.jar` 안의 수백 개 후보 중, 클래스패스에 따라 조건부로 필요한 빈만 자동 등록된다.
- **빈 등록 어노테이션은 본질이 같다** — `@Service`, `@Repository`, `@Controller` 모두 `@Component`의 의미적 확장. `@Configuration`만 CGLIB 프록시로 `@Bean` 메서드의 싱글톤을 보장한다.
- **IoC 컨테이너는 추상 개념이 아니라 메모리에 떠 있는 `ApplicationContext` 객체 하나** — 컨테이너 안의 빈만 `@Transactional`, `@Autowired` 같은 Spring 혜택을 받는다.
- **`ApplicationContext.getBean()` 직접 호출은 Service Locator 안티패턴** — 의존성 숨김, 테스트 곤란, Spring 결합, IoC 본질 위배의 4가지 이유로 피해야 한다.

## 참고

- 이 글은 면접 대비 학습 대화를 정리한 것으로, 외부 자료 인용은 없다.
