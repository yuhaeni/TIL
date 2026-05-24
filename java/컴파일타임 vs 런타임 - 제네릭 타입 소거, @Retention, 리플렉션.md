# 컴파일타임 vs 런타임 — 제네릭 타입 소거, @Retention, 리플렉션

> 날짜: 2026-05-22

## 내용

### 컴파일타임 vs 런타임 — 시점과 발견되는 에러의 차이

| | 컴파일타임 (Compile Time) | 런타임 (Run Time) |
|---|---|---|
| **시점** | `javac` 가 `.java` → `.class` 변환 | JVM이 `.class` 를 실행 |
| **발견 시점** | 코드 작성 즉시 (IDE 빨간줄) | **해당 코드가 실제로 실행되는 순간** |
| **장점** | 빨리 발견 = 빨리 수정 | 동적 동작 가능 |
| **단점** | 정적 분석 한계 | 운영 중 터질 위험 |

#### 5가지 에러 분류

| 에러 | 시점 | 이유 |
|------|------|------|
| 세미콜론 빠뜨림 | **컴파일** | 문법 오류 |
| import 누락 | **컴파일** | 심볼 해결 실패 |
| 변수 타입 안 맞음 (`int s = "abc"`) | **컴파일** | 정적 타입 검사 |
| `NullPointerException` | **런타임** | null 참조 실행 시점에 발견 |
| `ClassCastException` | **런타임** | 선언된 타입과 실제 타입 불일치 (실행 시점에 확인) |

#### 런타임 에러는 "앱 시작 후"가 아니라 "해당 코드 실행 시점"

```java
public void something() {
    String s = null;
    s.length();   // 💥 이 줄이 실행되는 순간만 NPE
                  //    호출 안 하면 영원히 안 터짐
}
```

런타임 에러는 다음 두 부류로 나뉜다.
- **앱 시작 시 터지는 것**: 빈 등록 실패, 자동 설정 충돌 (앱 부팅 중 실행되는 코드)
- **메서드 호출 시점에 터지는 것**: NPE, ClassCastException (그 줄 실행 시)

> **면접 예상 질문:** 컴파일타임 에러와 런타임 에러의 차이는 무엇이며, `NullPointerException`이 런타임 에러인 이유는 무엇인가요?

---

### `ClassCastException` 이 런타임 에러인 이유 — 선언된 타입 vs 실제 타입

```java
Object obj = "Hello";         // 선언된 타입: Object, 실제 타입: String
Integer num = (Integer) obj;  // 💥 ClassCastException!
```

#### 컴파일러의 시야 — 변수의 "선언된 타입"만 봄

```
컴파일러: "obj는 Object 타입. Object의 자식이라면 무엇이든 들어있을 수 있어.
         캐스팅이 진짜 가능한지는 내가 알 수 없어. 일단 통과!"
```

#### JVM의 시야 — 메모리에 올라간 "실제 타입" 확인

```
JVM: "잠깐, 실제 객체 타입을 보니까... 진짜 타입은 String인데?
     Integer로 캐스팅? → ClassCastException 💥"
```

#### 비유: 택배 상자

```
컴파일러 = 상자 겉면(라벨)만 봄 → 라벨: "전자제품"
JVM     = 상자 열어봄 → 실제: 신발 들어있음
```

라벨에 "전자제품"이라고 적혀있다고 컴파일러가 캐스팅을 허용해도, 실제 열어보면 다른 게 들어있을 수 있다. **변수의 선언된 타입과 객체의 실제 타입은 다를 수 있고, 실제 타입은 런타임에만 확인 가능**.

> **면접 예상 질문:** `ClassCastException` 이 컴파일 시점에 잡히지 않고 런타임에 발생하는 이유를 설명해주세요.

---

### 제네릭 타입 소거 (Type Erasure) — 런타임엔 정보가 사라진다

#### 핵심 메커니즘

```java
// 우리가 작성한 코드
List<String> list1 = new ArrayList<>();
List<Integer> list2 = new ArrayList<>();
```

```java
// 컴파일 후 (런타임에서 보이는 모습)
List list1 = new ArrayList();    // <String> 사라짐!
List list2 = new ArrayList();    // <Integer> 사라짐!
```

```java
list1.getClass() == list2.getClass();  // ✅ true
// 런타임에 둘 다 그냥 ArrayList!
```

> **"제네릭 타입 정보는 컴파일 시점에만 존재하고, 런타임에는 사라진다."** → 이것이 타입 소거.

#### 왜 자바는 이렇게 만들었나? — 하위 호환성

- **Java 5 (2004)**: 제네릭이 처음 도입됨
- **Java 4 이전**: 제네릭 없음, 모든 컬렉션이 raw type (`List`, `Map`)

만약 제네릭 도입 시 런타임에도 타입을 보존했다면, **Java 5 이전 코드와의 호환이 깨졌을 것**. 자바는 "**런타임엔 옛날 코드와 똑같이 보이게 하자**" 로 결정.

#### 타입 소거의 부작용 5가지

```java
// 1. instanceof 로 제네릭 타입 검사 불가
if (list instanceof List<String>) { }  // ❌ 컴파일 에러

// 2. 제네릭 타입으로 배열 생성 불가
T[] array = new T[10];  // ❌ 컴파일 에러

// 3. 제네릭 타입의 .class 접근 불가
Class<?> c = List<String>.class;  // ❌ 컴파일 에러

// 4. 제네릭 타입만 다른 메서드 오버로딩 불가
void process(List<String> list) { }
void process(List<Integer> list) { }  // ❌ 컴파일 에러 (시그니처 충돌)

// 5. catch 블록에서 제네릭 예외 사용 불가
try { } catch (MyException<String> e) { }  // ❌ 컴파일 에러
```

#### 타입 안전성은 어떻게 보장? — 컴파일러가 캐스팅 자동 삽입

```java
// 우리가 쓴 코드
List<String> list = new ArrayList<>();
list.add("Hello");
String s = list.get(0);

// 컴파일러가 만든 실제 코드 (대략)
List list = new ArrayList();
list.add("Hello");
String s = (String) list.get(0);   // ← 캐스팅 자동 추가!
```

컴파일러가 제네릭 타입을 검증하고 (`list.add(123)` 같은 호출은 컴파일 에러), 검증 통과 시 캐스팅을 자동 삽입해 타입 안전성을 보장한다. 런타임엔 일반 raw type 코드처럼 보일 뿐.

#### Kotlin의 reified type — 자바의 한계 극복

```kotlin
inline fun <reified T> isInstance(value: Any): Boolean {
    return value is T   // ✅ 가능! T의 실제 타입 알 수 있음
}

isInstance<String>("Hello")  // true
isInstance<Int>("Hello")     // false
```

Kotlin은 `inline + reified` 키워드로 런타임에도 타입 정보를 유지할 수 있다. 자바와 Kotlin을 함께 다루는 면접에서 가끔 등장.

> **면접 예상 질문:** 제네릭 타입 소거가 무엇이며 자바가 이 메커니즘을 채택한 이유는 무엇인가요? 부작용으로 어떤 것들이 있나요?

---

### `@Retention` 어노테이션 — 3가지 정책

#### 정의

어노테이션이 **언제까지 살아남는지** 결정하는 메타 어노테이션.

```java
public enum RetentionPolicy {
    SOURCE,   // 1. 소스 코드에만 (컴파일 시 사라짐)
    CLASS,    // 2. .class 파일까지 (JVM 로딩 시 사라짐) — 기본값!
    RUNTIME   // 3. JVM 메모리까지 (런타임에도 살아남음)
}
```

#### 시각화

```
[코드 작성]            [컴파일]          [JVM 실행]
.java 파일  →  javac  →  .class 파일  →  JVM 로딩  →  JVM 메모리

🔴 SOURCE   ━━━━ 여기까지만 (컴파일 후 사라짐)

🟡 CLASS    ━━━━━━━━━━━━━━━━━━━━━ 여기까지 (JVM 로딩 시 사라짐)

🟢 RUNTIME  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 끝까지 (리플렉션으로 읽기 가능!)
```

#### SOURCE — 컴파일러에게만 의미 있는 어노테이션

```java
@Override                       // 컴파일러: 부모에 진짜 있는지 검사 → 검사 끝나면 버림
@SuppressWarnings("unchecked")  // 컴파일러: 이 경고 무시 → 버림
```

**Lombok의 `@Getter` / `@Setter` 도 SOURCE 정책** — 컴파일 타임에 어노테이션 프로세서가 메서드를 생성한 뒤 어노테이션 정보는 사라진다. 그래서 **Lombok은 런타임 비용이 0**.

#### CLASS — 기본값 (거의 안 씀)

`.class` 파일까지만 살아남고 JVM 로딩 시 버려진다. 바이트코드 조작 도구(ASM, ByteBuddy 등) 가 사용.

⚠️ **`@Retention` 을 명시하지 않으면 기본값이 CLASS** → 리플렉션으로 못 읽힘!

```java
public @interface MyAnnotation { }   // @Retention 없음 → 기본 CLASS

@MyAnnotation
public class Service { }

Service.class.getAnnotation(MyAnnotation.class);  // null! 😱
```

→ **커스텀 어노테이션 만들 땐 거의 항상 `@Retention(RUNTIME)` 명시 필수**.

#### RUNTIME — Spring/JPA 동작의 기반

```java
@Deprecated      → RUNTIME (실행 중 경고)
@Service         → RUNTIME (Spring이 런타임 스캔)
@RestController  → RUNTIME
@Autowired       → RUNTIME
@Transactional   → RUNTIME
@Entity          → RUNTIME (JPA)
@Column          → RUNTIME
```

**Spring/JPA는 리플렉션 + RUNTIME 어노테이션의 거대한 활용체** — 컴포넌트 스캔, 의존성 주입, 트랜잭션 적용, 엔티티 매핑이 모두 이 조합으로 동작.

> **면접 예상 질문:** `@Retention` 의 3가지 정책의 차이를 설명하고, 커스텀 어노테이션을 만들 때 어떤 정책을 사용해야 하는지 그 이유와 함께 답해주세요.

---

### 리플렉션 (Reflection) — 런타임 메타 처리

#### 정의

> **"런타임에 클래스의 메서드, 필드, 어노테이션 같은 정보를 조사(inspect)하고 동적으로 조작(manipulate)할 수 있게 해주는 자바 API"**

이름의 의미: "Reflection = 반사, 거울" — 실행 중인 자바 객체가 **자기 자신의 정보를 들여다보는 것**.

#### 4가지 능력

```java
// 1. 조사 — 클래스 정보 탐색
Class<?> clazz = UserService.class;
Method[] methods = clazz.getMethods();
Field[] fields = clazz.getDeclaredFields();
Service annotation = clazz.getAnnotation(Service.class);

// 2. 객체 생성 — new 없이!
Object instance = clazz.getDeclaredConstructor().newInstance();

// 3. 메서드 호출 — 이름만 알면!
Method method = clazz.getMethod("findUser", Long.class);
Object result = method.invoke(instance, 1L);

// 4. private 필드 강제 변경
Field field = clazz.getDeclaredField("password");
field.setAccessible(true);          // private 접근 허용
field.set(instance, "hacked!");     // 💀 private 필드 변경
```

#### `@Retention(RUNTIME)` 과의 관계

```java
@Retention(RetentionPolicy.RUNTIME)  // ← RUNTIME이어야
@Target(ElementType.TYPE)
public @interface MyComponent {
    String value() default "";
}

@MyComponent("userService")
public class UserService { }

// 런타임에 리플렉션으로 읽기 가능
MyComponent annotation = UserService.class.getAnnotation(MyComponent.class);
String name = annotation.value();  // "userService" ✅
```

`@Retention(SOURCE)` 였다면 `getAnnotation()` 호출 시 `null` 반환. **리플렉션으로 어노테이션을 읽으려면 반드시 `@Retention(RUNTIME)`**.

#### 실무 사용처 — 모든 프레임워크의 기반

| 프레임워크 | 리플렉션 사용처 |
|----------|--------------|
| **Spring** | `@Component` 스캔, 의존성 주입, `@Transactional` 프록시, `@Autowired` 처리 |
| **JPA / Hibernate** | `@Entity` 스캔, 필드 값 읽기/쓰기, `@Column` 매핑 |
| **Jackson** | JSON ↔ 객체 변환 (필드/getter 호출) |
| **JUnit** | `@Test` 메서드 자동 실행 |
| **Lombok** | ❌ 사용 안 함 (컴파일 타임 어노테이션 프로세서) |

#### 단점 3가지

1. **성능 비용** — 일반 호출의 수십 배. 메서드 검색(String 탐색), 접근 권한 검사, 인자 박싱/언박싱, JIT 인라인 최적화 불가.
2. **컴파일 타임 안전성 깨짐** — 메서드 이름에 오타가 있어도 컴파일 통과. 런타임에 `NoSuchMethodException`.
3. **캡슐화 위반** — `setAccessible(true)` 로 `private` 접근 가능. Java 9+ 모듈 시스템에서 제한 강화.

#### 성능 보완 — 캐싱

프레임워크는 한 번 분석한 결과를 캐싱한다.

```java
// 매번 검색하면 느림
Method method = clazz.getMethod("findUser", Long.class);  // 매번 검색

// 한 번 가져와서 캐싱
private static final Method FIND_USER_METHOD;
static {
    FIND_USER_METHOD = clazz.getMethod("findUser", Long.class);
}
```

Spring도 빈 등록 시 한 번 리플렉션으로 분석한 뒤, 그 결과를 **`BeanDefinition` 으로 캐싱** 한다.

> **면접 예상 질문:** 리플렉션이 무엇이며, Spring/JPA 같은 프레임워크가 어떻게 활용하는지 설명해주세요. 리플렉션의 단점과 그 해결 방법은 무엇인가요?

---

## 학습 정리

- **컴파일타임 에러는 `javac` 가 `.java` → `.class` 변환 시 발견되고, IDE에서 빨간줄로 즉시 확인 가능**. 런타임 에러는 해당 코드가 실제로 실행되는 순간 발생하며, NPE/ClassCastException 등이 대표적이다.
- **`ClassCastException` 이 런타임인 이유는 컴파일러가 "선언된 타입"만 보고 "실제 타입"은 JVM 메모리에 올라가야 확인 가능하기 때문**. `Object` 같은 부모 타입엔 자식 타입의 어떤 객체든 들어갈 수 있어 컴파일러가 미리 검증 불가.
- **제네릭 타입 소거는 컴파일 시점에만 타입을 검증하고 런타임에는 정보를 제거하는 자바의 메커니즘** — Java 5 도입 시 이전 raw type 코드와의 하위 호환성을 위해 채택. `instanceof List<String>`, `new T[]`, 제네릭 타입만 다른 메서드 오버로딩 등이 불가능한 부작용이 있다.
- **`@Retention` 의 3가지 정책 — SOURCE / CLASS / RUNTIME — 은 어노테이션이 언제까지 살아남는지 결정한다**. Lombok은 SOURCE, Spring/JPA 어노테이션은 RUNTIME. 커스텀 어노테이션은 거의 항상 `@Retention(RUNTIME)` 명시가 필요하며, 안 붙이면 기본값 CLASS라서 리플렉션으로 못 읽는다.
- **리플렉션은 런타임에 클래스 정보를 조사하고 객체 생성·메서드 호출·private 필드 변경까지 가능한 자바 API**. Spring, JPA, Jackson, JUnit이 모두 리플렉션 기반이다. 단점은 성능 비용, 컴파일 타임 안전성 손실, 캡슐화 위반이며, 프레임워크는 캐싱으로 성능을 보완한다.
- **`@Retention(RUNTIME)` + 리플렉션 조합이 Spring/JPA의 동작 핵심** — 어노테이션이 런타임에 살아있어야 리플렉션으로 읽을 수 있고, 이를 통해 컴포넌트 스캔/DI/트랜잭션 적용이 가능해진다.

## 참고

- 이 글은 면접 대비 학습 대화를 정리한 것으로, 외부 자료 인용은 없다.
