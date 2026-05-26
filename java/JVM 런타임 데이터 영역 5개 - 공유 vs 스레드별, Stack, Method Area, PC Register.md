# JVM 런타임 데이터 영역 5개 — 공유 vs 스레드별, Stack, Method Area, PC Register

> 날짜: 2026-05-22

## 내용

### JVM 런타임 데이터 영역 — 전체 5개 구조

JVM은 실행 시 메모리를 5개 영역으로 나눠서 관리한다. 핵심은 **어떤 영역이 모든 스레드 공유고, 어떤 영역이 스레드별로 분리되는지** 다.

| 영역 | 공유? | 저장 내용 |
|------|------|---------|
| **Heap** | 🌐 공유 | 모든 객체 인스턴스 (`new` 로 만든 것) |
| **Method Area** | 🌐 공유 | 클래스 메타데이터, static 변수, 상수, 메서드 바이트코드 |
| **Stack** | 🧵 스레드별 | 지역변수, 메서드 호출 정보 (Stack Frame) |
| **PC Register** | 🧵 스레드별 | 현재 실행 중인 명령어 주소 |
| **Native Method Stack** | 🧵 스레드별 | JNI (C/C++ 호출 시 사용) |

```
┌─────────────────────────────────────────────────┐
│              JVM 메모리                          │
│                                                 │
│  ┌──────────────┐   ┌──────────────────────┐  │
│  │   🌐 공유     │   │   🧵 스레드별         │  │
│  │  (모든 스레드)  │   │   (스레드마다 1개)     │  │
│  ├──────────────┤   ├──────────────────────┤  │
│  │   Heap        │   │   Stack              │  │
│  │   (객체)       │   │   (지역변수, 호출)     │  │
│  ├──────────────┤   ├──────────────────────┤  │
│  │  Method Area  │   │   PC Register        │  │
│  │  (클래스 정보)  │   │   (실행 위치)         │  │
│  └──────────────┘   ├──────────────────────┤  │
│                     │  Native Method Stack │  │
│                     │  (JNI 호출용)         │  │
│                     └──────────────────────┘  │
└─────────────────────────────────────────────────┘
```

이 구분이 중요한 이유: **공유 영역은 동시성 이슈 위험, 스레드별 영역은 자동으로 안전.**

> **면접 예상 질문:** JVM의 런타임 데이터 영역을 5개로 분류하고, 모든 스레드가 공유하는 영역과 스레드별로 분리되는 영역을 각각 설명해주세요.

---

### Stack — 메서드 호출과 지역변수 (스레드별)

#### 저장되는 것

```java
public void myMethod() {
    int count = 10;            // 1. primitive 값 직접 저장 (Stack)
    String name = "철수";       // 2. 객체 주소 저장 (실제 객체는 Heap)
    User user = new User();    // 3. 객체 주소 저장 (실제 객체는 Heap)
    anotherMethod();           // 4. 메서드 호출 시 새 Stack Frame 쌓임
}
```

```
[Stack 메모리 - myMethod 실행 중]
┌─────────────────────────┐
│  Stack Frame: myMethod  │
│  ┌───────────────────┐  │
│  │ count = 10        │  │ ← primitive는 값 자체
│  │ name  = 0x1234    │  │ ← Heap의 String 주소
│  │ user  = 0x5678    │  │ ← Heap의 User 주소
│  └───────────────────┘  │
└─────────────────────────┘
        ↓ (anotherMethod 호출 시)
┌─────────────────────────┐
│  Stack Frame: another   │ ← 새 Frame이 위에 쌓임
└─────────────────────────┘
```

#### 메서드 호출 = Stack Frame 쌓이고 빠지기

```java
public void A() { B(); }
public void B() { C(); }
public void C() { int x = 10; }

// C 실행 중 Stack 상태:
// ┌─────────────────────┐
// │  Frame: C (x=10)    │ ← 가장 위 (현재)
// ├─────────────────────┤
// │  Frame: B           │
// ├─────────────────────┤
// │  Frame: A           │ ← 가장 아래
// └─────────────────────┘
```

C 끝나면 Frame: C 제거 → B로 복귀 → 마지막 A 끝나면 스레드 종료.

#### 스레드별 분리 — 멀티스레드 안전성의 핵심

```
스레드 1                    스레드 2
   ↓                          ↓
[자기만의 Stack]          [자기만의 Stack]
- 다른 스레드는 못 봄        - 다른 스레드는 못 봄
- 지역변수 안전 ✅           - 지역변수 안전 ✅
```

이것이 **"지역변수는 스레드 안전" 의 근본 이유** — Stack은 스레드별로 분리된 메모리이기 때문. 그래서 Singleton 빈에서 무상태(Stateless) 설계 시 데이터를 메서드 파라미터/지역변수로 처리하면 안전하다.

#### StackOverflowError

```java
public void infinite() {
    infinite();  // 자기 자신 무한 호출
}
// → Frame 무한 쌓임 → 💥 StackOverflowError
```

JVM 시작 시 Stack 크기는 한정 (보통 512KB~1MB per thread). 너무 깊은 재귀 = Stack 가득 참 = `StackOverflowError`.

> **면접 예상 질문:** Stack 영역에 저장되는 것은 무엇이며, 멀티스레드 환경에서 지역변수가 스레드 안전한 이유는 무엇인가요?

---

### Method Area — 클래스의 "설계도" (공유)

#### 저장되는 것

```
[Method Area]
├─ 클래스 메타데이터
│  ├─ 클래스 이름, 부모 클래스
│  ├─ 필드 목록 (어떤 필드가 있는지)
│  ├─ 메서드 목록 (어떤 메서드가 있는지)
│  └─ 어노테이션 정보 (@Retention RUNTIME 어노테이션들!)
│
├─ 메서드의 바이트코드 (실제 실행 코드)
│
├─ static 변수
│  ├─ public static final int MAX = 100;
│  └─ private static Logger log = ...;
│
└─ 상수 풀 (Constant Pool)
   └─ 코드에 나오는 문자열, 숫자 리터럴
```

#### 리플렉션이 정보를 읽는 곳!

```java
UserService.class.getMethods();             // ← Method Area에서 메서드 목록
UserService.class.getDeclaredFields();      // ← Method Area에서 필드 목록
UserService.class.getAnnotation(Service.class);  // ← Method Area에서 어노테이션
```

`@Retention(RUNTIME)` 어노테이션은 **Method Area에 저장되어 런타임에 살아있고**, 그래서 리플렉션으로 읽을 수 있다.

#### Java 버전별 변천사 — PermGen → Metaspace

```
[Java 7 이전]
Method Area = PermGen (Permanent Generation)
  ↓ JVM 메모리 안에 있음
  ↓ 크기 고정 → OutOfMemoryError: PermGen space 😱

[Java 8 이후]
Method Area = Metaspace
  ↓ 네이티브 메모리 사용 (JVM Heap 밖)
  ↓ 동적 확장 가능 → PermGen OOM 거의 없음 ✅
```

Spring/Hibernate 같은 **리플렉션 무거운 프레임워크에서 PermGen OOM이 자주 났던 게** Java 8에서 Metaspace로 변경된 핵심 이유.

> **면접 예상 질문:** Method Area에는 무엇이 저장되며, Java 8에서 PermGen이 Metaspace로 변경된 이유는 무엇인가요? 리플렉션과의 관계는?

---

### PC Register — 현재 실행 위치 (스레드별)

#### 정의

> **"이 스레드가 지금 어디까지 코드를 실행했는지 기록하는 작은 메모리"**

#### 왜 필요한가? — 컨텍스트 스위칭

```
멀티스레드 환경:
- CPU는 한 번에 한 스레드만 실행
- Context Switching: 스레드 A → B → A → C → A ...
- A로 돌아왔을 때, "어디까지 했더라?" 알아야 함!
- → PC Register에 기록되어 있음
```

```
[스레드 A] 명령어 10번 실행 중 → CPU 양보
   PC Register: "Line 10번"
       ↓
[스레드 B] 실행...
       ↓
[스레드 A] 다시 CPU 받음
   PC Register 확인: "Line 10번이었지!"
   → Line 11번부터 실행
```

각 스레드마다 자기만의 PC Register가 있어서 어디까지 실행했는지 정확히 추적할 수 있다. 컨텍스트 스위칭의 핵심 메커니즘.

> **면접 예상 질문:** PC Register는 어떤 역할을 하며, 왜 스레드별로 분리되어야 하나요?

---

### Native Method Stack — JNI 호출용 (스레드별)

#### 정의

자바가 **C/C++ 같은 네이티브 코드를 호출할 때 쓰는 Stack** (JNI: Java Native Interface).

```java
// Object.hashCode() 같은 native 메서드
public native int hashCode();

String s = "hello";
s.hashCode();  // ← 내부적으로 native 코드 실행 → Native Method Stack 사용
```

실무에선 거의 신경 안 씀:
- 우리가 직접 JNI 코드 짤 일 거의 없음
- 자바 표준 라이브러리(Object, Thread 등)의 native 메서드만 사용
- 면접에선 **"5개 영역 중 하나로 존재한다"** 정도만 알면 됨

> **면접 예상 질문:** Native Method Stack은 어떤 용도로 사용되며, 일반적인 자바 애플리케이션에서 신경 써야 하는 영역인가요?

---

### 공유 영역 vs 스레드별 영역 — 동시성 처리의 핵심

#### 한눈에 비교

| | 공유 영역 (Heap, Method Area) | 스레드별 영역 (Stack, PC Register, Native Stack) |
|---|---|---|
| **접근** | 모든 스레드가 동시 접근 가능 | 자기 스레드만 접근 |
| **동시성 이슈** | Race Condition 발생 가능 | 자동으로 안전 |
| **고려 사항** | 동기화 필요 (synchronized, Atomic 등) | 별도 처리 불필요 |
| **예시** | Singleton 빈의 인스턴스 필드 | 메서드의 지역변수 |

#### 실전 코드와 연결

```java
@Service
public class UserService {
    private User currentUser;  // ❌ Heap에 저장 → 모든 스레드 공유 → 위험!

    public User process(Long id) {
        User user = userRepository.findById(id);  // ✅ Stack에 저장 → 스레드별 → 안전!
        return user;
    }
}
```

- `currentUser` 같은 인스턴스 필드 → **Heap** → 모든 스레드 공유 → Race Condition
- 메서드 안의 `user` 같은 지역변수 → **Stack** → 스레드별 격리 → 안전

**무상태(Stateless) 설계** 의 근본 이유가 바로 이 메모리 구조에 있다.

> **면접 예상 질문:** Spring의 Singleton 빈에서 인스턴스 필드는 위험하지만 메서드의 지역변수는 안전한 이유를, JVM 메모리 구조 관점에서 설명해주세요.

---

### 종합 예시 — 코드와 메모리 영역 매핑

```java
public class MyApp {
    private static final int MAX = 100;       // 📍 Method Area (static + final)

    public static void main(String[] args) {  // 📍 Stack: Frame 생성
        int count = 10;                       // 📍 Stack: count = 10
        User user = new User("철수");          // 📍 Stack: user = 주소
                                              // 📍 Heap: User 객체 생성
        process(user);                        // 📍 Stack: 새 Frame
    }

    public static void process(User u) {      // 📍 Stack: Frame 생성
        String name = u.getName();            // 📍 Stack: name = 주소
                                              // 📍 Heap: String 객체
    }
}
```

```
[메모리 스냅샷]

🌐 Method Area:
  - MyApp 클래스 메타데이터
  - User 클래스 메타데이터
  - MAX = 100 (static final)

🌐 Heap:
  - User 객체 (name="철수")
  - String 객체 ("철수")

🧵 Stack (main 스레드):
  ┌──────────────────┐
  │ Frame: process   │
  │   u    = 0xABC   │ ← User 주소
  │   name = 0xDEF   │ ← String 주소
  ├──────────────────┤
  │ Frame: main      │
  │   args  = ...    │
  │   count = 10     │
  │   user  = 0xABC  │
  └──────────────────┘

🧵 PC Register (main 스레드):
  - "현재 실행 중인 명령어 주소"
```

> **면접 예상 질문:** `User user = new User("철수");` 한 줄이 실행될 때 Heap, Stack, Method Area 각각에 무엇이 저장되는지 설명해주세요.

---

### 4세션 통합 정리 — 모든 개념이 연결된다

면접 대비 학습한 개념들이 JVM 메모리 구조 위에서 어떻게 맞물리는지:

```
🌱 Singleton 빈 (3세션)
    ↓ 어디에 저장?
    → Heap (공유) — 그래서 인스턴스 필드 위험

💉 지역변수 (3세션)
    ↓ 어디에 저장?
    → Stack (스레드별) — 그래서 안전

🪞 리플렉션 (4세션)
    ↓ 클래스 정보 어디서 읽나?
    → Method Area — 그래서 @Retention(RUNTIME) 필요

⚡ 컨텍스트 스위칭 (4세션 + 기존 I/O 학습)
    ↓ 어디까지 했는지 어떻게 기억?
    → PC Register — 그래서 스레드별 필요

🚀 static 변수 / @Configuration 빈
    ↓ 어디에 저장?
    → Method Area — 클래스 단위 데이터
```

JVM 메모리 구조는 단순한 메모리 분리가 아니라, **객체지향, 동시성, 리플렉션, 라이프사이클** 등 자바의 핵심 개념이 모두 맞물리는 기반이다.

> **면접 예상 질문:** Spring의 Singleton 빈, 지역변수의 스레드 안전성, 리플렉션의 어노테이션 읽기, 컨텍스트 스위칭이 JVM 메모리의 어느 영역과 각각 연관되는지 설명해주세요.

---

## 학습 정리

- **JVM 런타임 데이터 영역은 5개 — Heap, Method Area, Stack, PC Register, Native Method Stack**. 공유 영역(Heap, Method Area)은 동시성 처리가 필요하고, 스레드별 영역(Stack, PC Register, Native Method Stack)은 자동으로 안전하다.
- **Stack은 지역변수와 메서드 호출 정보(Stack Frame)를 저장하며 스레드별로 분리** 된다. 이것이 "지역변수는 멀티스레드에서 안전" 의 근본 이유이며, Singleton 빈의 무상태 설계 원칙과 직결된다.
- **Method Area는 클래스 메타데이터, static 변수, 메서드 바이트코드, 어노테이션을 저장** 한다. 리플렉션이 정보를 읽는 곳이며, `@Retention(RUNTIME)` 어노테이션이 살아있는 곳이다.
- **PC Register는 스레드가 현재 어디까지 실행했는지 추적** 한다. 컨텍스트 스위칭 시 정확한 복귀를 가능하게 하는 핵심 메커니즘.
- **Java 8에서 Method Area를 PermGen에서 Metaspace로 변경** 했다. PermGen은 JVM 메모리 안 고정 크기라 리플렉션 무거운 프레임워크에서 OOM이 자주 났지만, Metaspace는 네이티브 메모리를 동적으로 사용해 이 문제를 해결했다.
- **JVM 메모리 구조는 객체지향, 동시성, 리플렉션 등 자바 핵심 개념들이 맞물리는 기반** — Singleton 멀티스레드 위험, 리플렉션 동작, 컨텍스트 스위칭이 모두 이 메모리 구조 위에서 설명된다.

## 참고

- 이 글은 면접 대비 학습 대화를 정리한 것으로, 외부 자료 인용은 없다.
