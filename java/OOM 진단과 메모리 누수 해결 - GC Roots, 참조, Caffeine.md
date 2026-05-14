# OOM 진단과 메모리 누수 해결 — GC Roots, 참조, Caffeine

> 날짜: 2026-05-14

## 내용

### OOM 발생 본질 — "GC를 돌렸는데도 회수할 메모리가 없는 상태"

`OutOfMemoryError: Java heap space`는 단순히 "메모리가 부족"한 게 아니다.

**정확한 정의**: GC가 정상 동작했는데도, **참조가 살아있어 회수 불가능한 객체들로 Heap이 가득 찬 상태**.

```
❌ 오해: "Heap이 꽉 차면 OOM"
✅ 정확: "GC를 돌려도 회수 가능한 메모리가 없으면 OOM"
```

**흔한 원인**:
- 메모리 누수 (의도치 않게 객체 참조 유지) — static 컬렉션, Listener 미해제, ThreadLocal 미정리
- 너무 큰 워크로드 (Spring Batch chunk size 과다, 한 번에 너무 많은 객체 로딩)
- 힙 사이즈 자체 부족 (`-Xmx` 부족)

> **면접 예상 질문:** OOM은 "메모리 부족"과 어떻게 다른가? 발생하는 정확한 메커니즘은?

---

### Young → Old 영역 승격 — age threshold와 Major GC

객체가 계속 살아남으면 Young에서 끝까지 머무는 게 아니라 **Old로 승격**된다.

```
🆕 Young 영역 (Eden + Survivor)
   ↓ Minor GC 시 살아남으면
🆕 Survivor From → Survivor To 이동 (age++)
   ↓ age threshold (보통 15회) 이상 살아남으면
🏛️ Old 영역으로 승격 (Promotion)
   ↓ Old도 가득 차면
🚨 Major GC (Full GC) → 그래도 회수 못 하면 OOM
```

**5년차 답변 포인트**:
- "참조가 살아있어 회수 안 됨" ≠ "Young에서만 머묾"
- 정확히는: 계속 살아남는 객체는 Old로 승격 → Old 가득 → Major GC 실패 → OOM
- Major GC (Full GC)는 Stop-The-World가 길어 응답 시간 폭증의 원인

> **면접 예상 질문:** Young 영역에서 살아남은 객체는 어떻게 되는가? Major GC가 자주 발생하면 어떤 문제가 생기는가?

---

### JVM 메모리 진단 3단계 — Grafana → GC 로그 → 힙 덤프

운영 환경에서 OOM 장애를 진단할 때 5년차의 표준 흐름.

| 단계 | 도구 | 무엇을 볼 수 있나? | 비유 |
|---|---|---|---|
| 1️⃣ 거시 추세 | **Grafana + Prometheus** | 메모리/GC 트렌드, 알람 | 🎥 CCTV 패턴 |
| 2️⃣ 시간별 상세 | **GC 로그** | 매 GC마다 회수량/시간 | 📋 출입 기록부 |
| 3️⃣ 결정적 증거 | **힙 덤프 (.hprof)** | 지금 메모리에 어떤 객체가 얼마나 있나 | 📸 현장 스냅샷 |

**1️⃣ Grafana — 1차 의심**

```
📊 핵심 지표:
  - jvm_memory_used_bytes        (Heap 사용량 추세)
  - jvm_gc_pause_seconds_sum     (GC 시간 누적)
  - jvm_gc_pause_seconds_count   (GC 발생 횟수)

💡 위험 신호 패턴:
  - "톱니파 봉우리가 점점 우상향" → 메모리 누수 의심 🚨
  - "Major GC 비정상적으로 자주 발생" → Old 영역 부족 🚨
  - "GC time이 응답 시간의 큰 비중" → STW 영향 🚨
```

**2️⃣ GC 로그 — 시간별 정밀 분석**

JVM 시작 옵션으로 활성화 (운영 표준 셋업):

```bash
java -Xlog:gc*:file=gc.log:time:filecount=10,filesize=10M -jar app.jar
```

기록 예시:

```
[14:23:01.123] GC(42) Pause Young (Allocation Failure)
[14:23:01.123] GC(42) Eden: 256M -> 0M
[14:23:01.123] GC(42) Old:  1024M -> 1280M  ← 점점 증가! 누수 신호 🚨
[14:23:01.123] GC(42) Pause: 0.234s
```

**진단 포인트**: "Old 영역이 GC 후에도 계속 증가" → **메모리 누수 확정**.

분석 도구: GCEasy(웹 무료), GCViewer.

**3️⃣ 힙 덤프 — 범인 객체 식별**

```bash
# 운영 표준 옵션 (OOM 발생 시 자동 덤프)
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/logs/heap-dump.hprof

# 또는 수동 덤프
jmap -dump:format=b,file=heap.hprof <PID>
```

**분석 도구**: **Eclipse MAT (Memory Analyzer Tool)** — 5년차 단골 키워드.

MAT에서 보는 것:
- **Histogram**: 클래스별 인스턴스 개수/크기 → "Template 객체가 1억 개?? 누수!"
- **Dominator Tree**: 메모리를 가장 많이 점유하는 객체 트리 → "이 HashMap이 힙의 80%"
- **GC Roots Path**: 왜 GC 안 되는지 참조 사슬 추적 → "static 캐시 → HashMap → Template 1억 개"

> **면접 예상 질문:** OOM 장애가 발생했을 때 어떤 도구로 어떻게 진단할 것인가? 운영 표준으로 켜둬야 할 JVM 옵션은?

---

### 메모리 누수의 본질 — GC Roots와 static 필드

GC가 "이 객체 살아있나? 죽었나?" 판단할 때 **GC Roots**에서 참조를 따라간다. GC Roots에서 도달 가능 = 살아있는 객체.

**GC Roots의 대표적 종류**:

1. **클래스의 static 필드** ⭐ — 가장 흔한 누수 원인
2. 스택 프레임의 지역 변수 (실행 중인 메서드의 로컬 변수)
3. JNI 참조
4. 활성 스레드

**static 컬렉션 누수 메커니즘**:

```java
public class Cache {
    public static HashMap<Long, Template> CACHE = new HashMap<>();
    //   ↑ static 필드 = Method Area (Metaspace), JVM 종료까지 영원
}

// CACHE.put(1L, new Template())
// → static 필드가 Template 객체를 강하게 참조
// → GC: "GC Root(static)에서 도달 가능하니 살아있는 객체!" → 회수 불가 ❌
// → put 누적 → Old 영역 가득 → OOM
```

**비유** 🏛️:

```
회사 게시판(Method Area)에 VIP 명단(static 필드) 붙어있음
→ 명단에 적힌 사람들은 "영원히 VIP"
→ VIP의 친구도 모두 VIP 자격
→ GC: "VIP니까 청소 안 함"
→ 1억 명 적어두면 → 1억 명 모두 영원히 VIP → 회사(Heap) 가득
```

> **면접 예상 질문:** GC Roots란 무엇인가? static 컬렉션이 메모리 누수의 단골 원인인 이유는?

---

### 참조(Reference) 개념 — 객체 주소를 가리키는 손가락

Java 변수는 두 종류로 나뉜다.

**1. 원시 타입(Primitive)** — 값 자체를 변수에 저장

```java
int age = 25;  // age 변수 안에 '25' 값 직접 저장
```

**2. 참조 타입(Reference)** — **값의 *주소*를 저장**

```java
Template t = new Template();
```

이 한 줄에서 일어나는 일:

```
1. new Template() → Heap에 객체 생성 (예: 주소 0x1234)
2. 변수 t에 *객체 자체가 아니라 주소(0x1234)*만 저장

   변수 t (스택)         Heap (객체 실물)
   ┌──────────┐         ┌────────────────┐
   │ 0x1234   │ ──────→ │ Template 객체  │
   └──────────┘         └────────────────┘
        ↑                  (주소: 0x1234)
   주소만 저장 (= "참조")
```

→ **변수 `t`는 객체 자체가 아니라, 객체를 *가리키는 손가락***

**핵심 특성 — 여러 변수가 같은 객체를 참조 가능**:

```java
Template t1 = new Template();   // 객체 생성 + t1이 주소 저장
Template t2 = t1;               // t2도 같은 주소 저장
// 📝(t1) → 🏠(0x1234)
// 📝(t2) → 🏠(0x1234)  ← 같은 객체!
```

**참조와 GC의 관계**:

```java
// 🟢 정상 (참조 자연 소멸)
public void process() {
    Template t = new Template();
    doSomething(t);
}  // 메서드 끝 → 지역변수 t 소멸 → 아무도 객체 주소 모름 → GC 회수 ✅

// 🔴 누수 (참조 영원 유지)
static Map<Long, Template> CACHE = new HashMap<>();
CACHE.put(1L, new Template());
// → static이 영원히 객체 주소 보관 → GC 회수 불가 ❌
```

> 💡 **흔한 오해**: "참조가 끊긴다 = 메모리 누수". **반대다!** 참조가 끊기면 GC가 회수 가능 → 정상. 참조가 *안 끊겨야* 누수.

> **면접 예상 질문:** Java의 참조 타입과 원시 타입의 차이는? 메모리 누수의 본질을 "참조" 관점에서 설명하라.

---

### Java의 4가지 참조 종류 — Strong, Soft, Weak, Phantom

| 참조 종류 | GC 동작 | 사용 예시 |
|---|---|---|
| **Strong Reference (강한 참조)** | GC 절대 회수 ❌ | 일반 변수 — `Template t = new Template()` |
| **Soft Reference** | **메모리 부족 시**에만 회수 | 메모리 민감한 캐시 |
| **Weak Reference** | **다음 GC 때 무조건** 회수 ✅ | `WeakHashMap`, 임시 캐시 |
| Phantom Reference | 거의 안 씀 (cleanup용) | 실무 거의 없음 |

**비유** 🏢:

```
강한 참조: "VIP 명단" — 회사 망할 때까지 영원히 보호 (static 필드 등)
약한 참조: "후보 명단" — 청소부 지나가다 그냥 지워도 됨 (다음 GC 때 회수)
소프트 참조: "준 VIP" — 평소엔 보호, 회사 망할 위기(메모리 부족) 시에만 청소
```

**WeakHashMap 예시**:

```java
WeakHashMap<User, Session> sessions = new WeakHashMap<>();
sessions.put(user, session);
// → user 변수에 대한 강한 참조가 모두 사라지면
// → 다음 GC 때 WeakHashMap에서 자동으로 entry 제거
```

**단점**: 동작 시점이 GC 타이밍에 의존해서 디버깅 어려움 → 실무에선 Caffeine 같은 명시적 캐시 라이브러리가 더 흔함.

> **면접 예상 질문:** Strong/Soft/Weak Reference의 차이는? WeakHashMap은 어떤 상황에 적합한가?

---

### 메모리 누수 해결 패턴 — Caffeine, WeakHashMap, 명시적 lifecycle

**1️⃣ Caffeine 캐시 — 가장 흔한 실무 해결책**

```java
Cache<Long, Template> cache = Caffeine.newBuilder()
    .maximumSize(10_000)                          // ✅ 크기 제한
    .expireAfterWrite(Duration.ofMinutes(10))     // ✅ TTL
    .expireAfterAccess(Duration.ofMinutes(5))     // ✅ 접근 후 TTL
    .recordStats()                                // 모니터링
    .build();
```

핵심: 무한 증가 자체를 차단 + 시간 기반 정리 + W-TinyLFU evict 정책.

**2️⃣ WeakHashMap — 약한 참조 기반 자동 정리**

키에 대한 외부 강한 참조가 사라지면 entry 자동 제거.

**3️⃣ 명시적 Lifecycle 관리**

```java
cache.put(id, template);
try {
    process(template);
} finally {
    cache.remove(id);  // ✅ 사용 끝나면 명시적 정리
}
```

→ Listener 등록/제거, ThreadLocal `remove()` 등이 대표 패턴. 가장 단순하고 가장 안전.

> **면접 예상 질문:** 메모리 누수를 막는 실무 패턴 3가지는? 각각의 트레이드오프는?

---

### Caffeine이 누수를 막는 진짜 원리 — 컨테이너는 OK, entry만 정리

5년차 면접에서 자주 헷갈리는 부분: **"static 변수를 안 쓰는 게 아니라, static 안의 데이터를 알아서 정리하게 만드는 것"**.

```java
public class Cache {
    // ✅ static 필드 자체는 살아있어도 OK!
    public static Cache<Long, Template> CACHE = Caffeine.newBuilder()
        .maximumSize(10_000)
        .build();
}
```

```
🏛️ static 필드 'CACHE'       → JVM 종료까지 영원히 살아있음 ✅ (정상)
   ↓ 가리킴
📦 Caffeine 컨테이너          → static이 들고 있어서 살아있음 ✅ (정상)
   ↓ 안에 보관
📋 entry들 (Template 객체)   → 여기가 누수의 핵심!
```

**static `HashMap` vs static `Caffeine Cache`**:

| | static `HashMap` | static `Caffeine Cache` |
|---|---|---|
| 컨테이너 자체 | 영원히 살아있음 (OK) | 영원히 살아있음 (OK) |
| **컨테이너 안 entry** | 영원히 누적 ❌ | **maxSize/TTL로 자동 evict** ✅ |
| 결과 | 누수 💥 | 누수 방지 ✨ |

**Caffeine과 GC의 협력 흐름**:

```
[1] Caffeine.put(id, template)
    → Caffeine 내부 자료구조가 template을 *강하게* 참조 🔗

[2] maxSize 초과 또는 TTL 만료 시:
    → Caffeine이 entry 자체를 자기 자료구조에서 제거
    → template에 대한 *Caffeine의 강한 참조가 사라짐* ✂️

[3] 다른 곳에서도 template을 참조하지 않는다면:
    → GC Roots에서 도달 불가능
    → GC가 회수 가능! ✅
```

→ **Caffeine은 "쥐고 있던 참조를 놓아주는" 역할, 실제 메모리 회수는 GC가 함**. 둘이 협력!

> **면접 예상 질문:** Caffeine이 메모리 누수를 막는 원리는? static 변수로 캐시를 보유해도 괜찮은 이유는?

---

## 학습 정리

- **OOM은 단순한 메모리 부족이 아니라 "GC가 회수할 수 없는 객체로 Heap이 가득 찬 상태"**. 흔한 원인은 메모리 누수 / 워크로드 과다 / 힙 사이즈 부족.
- **운영 표준 진단 흐름**: Grafana(추세) → GC 로그(시간별) → 힙 덤프(`.hprof`) + Eclipse MAT(범인 객체). `-XX:+HeapDumpOnOutOfMemoryError`는 운영 필수 셋업.
- **메모리 누수의 본질은 "참조"**. GC Roots(특히 static 필드)에서 도달 가능한 객체는 GC가 회수 못 함. 참조가 *안 끊겨야* 누수, 끊기면 정상.
- **참조(Reference) = 객체의 메모리 주소를 가리키는 손가락**. Java는 Strong/Soft/Weak/Phantom 4가지 참조 종류로 GC 동작을 조절 가능.
- **누수 해결 3가지 패턴**: Caffeine 캐시(maxSize+TTL), WeakHashMap(약한 참조), 명시적 lifecycle 관리(remove). 가장 흔한 건 Caffeine.
- **Caffeine은 static 변수로 보유해도 OK**. 컨테이너 자체는 살아있어도 그 안의 entry를 자동 evict해서 참조를 끊어주고, 실제 회수는 GC가 하는 협력 구조.

## 참고

- Eclipse MAT (Memory Analyzer Tool) — 힙 덤프 분석 도구
- GCEasy / GCViewer — GC 로그 분석 도구
- Caffeine: W-TinyLFU 기반 고성능 캐시 라이브러리
- 미리디 면접 대비 Q5 (JVM 메모리/GC 튜닝) 모의 면접 기반 학습
