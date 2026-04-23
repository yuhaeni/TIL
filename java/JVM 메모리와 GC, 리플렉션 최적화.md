# JVM 메모리와 GC, 리플렉션 최적화

> 날짜: 2026-04-23

## 내용

### JVM Heap 구조 — Young/Old Generation

JVM Heap은 **Young Generation**과 **Old Generation**으로 나뉜다.

```
┌─────────────────────────────────────┐
│              Heap                   │
│  ┌──────────────┬────────────────┐  │
│  │  Young Gen   │    Old Gen     │  │
│  │ (새 객체)     │  (오래 살아남음) │  │
│  └──────────────┴────────────────┘  │
└─────────────────────────────────────┘
```

- **Young Gen**: 새로 `new`된 객체의 탄생지
- **Old Gen**: Young에서 여러 번 살아남은 객체가 **승격(promotion)** 되는 곳

**왜 나눴나? — Weak Generational Hypothesis**
"대부분의 객체는 금방 죽는다"는 가설. 짧게 사는 애와 오래 사는 애를 분리해서 **GC 효율**을 극대화.

> **면접 예상 질문:** JVM Heap이 Young/Old로 나뉜 이유는? Weak Generational Hypothesis란?

---

### Young Gen 세분화와 Minor GC

Young Gen은 한 덩어리가 아니라 **Eden + Survivor 0 + Survivor 1** 3개 영역으로 쪼개져 있다.

```
┌─────────── Young Gen ───────────┐
│   Eden   │   S0    │    S1      │
│  (탄생)   │(Survivor)│(Survivor) │
└──────────┴─────────┴────────────┘
```

**객체 생애주기:**
1. `new` 객체 생성 → **Eden 입장**
2. Eden 꽉 참 → **Minor GC** 발동, 살아남은 객체 **S0으로 이사**
3. 또 Eden 꽉 참 → Minor GC → Eden+S0 생존자 **S1로 이사** (S0 비움)
4. 이사 반복 → **age 증가** → 일정 횟수(기본 15) 초과 시 **Old Gen 승격**
5. Old Gen도 꽉 참 → **Major/Full GC** → 그래도 못 비우면 **OutOfMemoryError**

| GC 종류 | 대상 | 특징 |
|---|---|---|
| **Minor GC** | Young Gen만 | 빠름, 자주 발생 |
| **Major/Full GC** | Old Gen 포함 전체 | 느림, **Stop-The-World** |

> **면접 예상 질문:** Eden과 Survivor 영역의 역할은? Minor GC와 Full GC의 차이는?

---

### OOM의 본질 — 참조가 살아있으면 GC 불가

대용량 배치에서 `mapper.findAll()`로 10만 건을 한 번에 `List`로 들고 있으면 어떻게 될까?

```
List<SettlementDto> list = mapper.findAll();  // 10만 건
  ↓
list 참조가 살아있음 → GC가 못 치움
  ↓
Eden → S0 → S1 → Old Gen 계속 승격
  ↓
Old Gen 꽉 참 → Full GC → 그래도 list 참조됨
  ↓
💥 OutOfMemoryError: Java heap space
```

**핵심 원칙: "참조가 살아있으면 GC가 못 치운다."**

이 상황은 **Memory Leak이 아니라 Memory Pressure** 문제 — 코드는 정상인데 양이 너무 많아서 터지는 전형적 대용량 배치 OOM 시나리오.

> **면접 예상 질문:** OOM은 언제 발생하는가? Memory Leak과 Memory Pressure의 차이는?

---

### Chunk 단위 처리 — 대용량 OOM 대응

해결책은 **Chunk 단위로 나눠서 처리**하고 **참조를 빨리 끊는 것**이다.

```
❌ 한 번에 10만 건: [10만 건 전부 Old Gen 점유] → OOM
✅ Chunk 1,000건씩:
   [1,000 처리 → 버림] → Minor GC 수거
   [1,000 처리 → 버림] → Minor GC 수거
   ...
```

**핵심:** 참조를 빨리 끊으면 **Eden 단계에서 바로 수거** → Old Gen까지 갈 일이 없다. Weak Generational Hypothesis를 적극 활용하는 설계다.

**Spring Batch의 chunk-oriented processing:**
```
Reader (1,000건 읽음) → Processor (가공) → Writer (저장)
                                              ↓
                                     Chunk 종료, 참조 해제
                                              ↓
                                    다음 Chunk 1,000건 읽음...
```

> **면접 예상 질문:** 대용량 배치에서 OOM을 어떻게 대응하는가? Chunk 처리가 GC에 유리한 이유는?

---

### Chunk 사이즈 트레이드오프

| 사이즈 | 단점 |
|---|---|
| **너무 큼 (예: 10,000)** | OOM 위험 ↑, Old Gen 승격 → Full GC 비용 ↑, 롤백 손실 ↑ |
| **너무 작음 (예: 100)** | DB I/O 부하 ↑, 커밋 빈도 ↑, 네트워크 왕복 ↑ |

**실무 가이드:**
- 보통 **500 ~ 1,000** 선에서 시작
- **측정 후 조정** — GC 로그 + 처리 시간 모니터링
- 면접관이 듣고 싶은 건 숫자 정답이 아닌 **"트레이드오프 인지 + 측정 기반 결정"** 이라는 사고방식

> **면접 예상 질문:** Chunk 사이즈를 결정하는 기준은? 크거나 작을 때 각각 어떤 문제가 생기는가?

---

### Stack vs Heap

| 구분 | **Stack** | **Heap** |
|---|---|---|
| 저장 대상 | 지역변수, 매개변수, 참조 | 객체, 배열 |
| 생성/소멸 | 메서드 호출/종료 시 자동 | GC가 수거 |
| 접근 범위 | **스레드별 독점** | 전체 스레드 공유 |
| 속도 | 매우 빠름 (LIFO) | 상대적으로 느림 |
| 크기 | 작음 (보통 1MB) | 큼 (`-Xmx` 설정) |
| Thread-Safe | 자동 | 동기화 필요 |

```java
public int calculate(int a, int b) {          // a, b → Stack
    int sum = a + b;                           // sum → Stack
    SettlementDto dto = new SettlementDto();   // dto 참조 → Stack, 객체 → Heap
    return sum;
}
// 메서드 종료 → Stack Frame 소멸 (GC 불필요!)
```

**Race Condition은 Heap에서만 발생!** Stack의 지역변수는 자기 스레드 독점이라 자동 Thread-Safe.

> **면접 예상 질문:** Stack과 Heap의 차이는? 지역변수가 자동으로 Thread-Safe한 이유는?

---

### Method Area → Metaspace (Java 8+)

Class 메타데이터, static 변수, 상수 풀, 메서드 바이트코드는 **Method Area**에 저장된다.

**Method Area에 저장되는 것:**
- Class 메타데이터 (`Class<?>`, `Field`, `Method` 정보)
- 어노테이션 정보 (`@Retention(RUNTIME)` 어노테이션)
- static 변수
- 상수 풀 (String literal 등)
- 메서드 바이트코드

**Java 7 → Java 8 변화:**

```
Java 7 이전: Method Area = PermGen (Permanent Generation)
              → Heap 안, 크기 고정 → OOM 자주 발생

Java 8 이후: Method Area = Metaspace
              → Native Memory(OS) 로 이동
              → 크기 자동 확장, OOM 대폭 감소
```

**변경 이유:** 리플렉션을 많이 쓰는 Spring/Hibernate에서 PermGen OOM이 자주 발생.

**@Retention(RUNTIME)과의 연결:**
- `@Retention(RUNTIME)` = **Metaspace에 유지** = 리플렉션으로 읽을 수 있음
- 커스텀 어노테이션 + 리플렉션 기반 엑셀 변환이 이 메커니즘 위에서 동작

> **면접 예상 질문:** Method Area에는 무엇이 저장되는가? Java 8에서 PermGen이 Metaspace로 바뀐 이유는?

---

### 리플렉션이 느린 진짜 이유

리플렉션의 성능 이슈는 **Metaspace 위치 때문이 아니다.** 네 가지 원인이 겹친다.

**1. 이름(String)으로 매번 탐색**
```java
// 일반 호출 (빠름) — 컴파일러가 주소 확정
dto.getName();

// 리플렉션 (느림) — 문자열로 검색
Method m = clazz.getDeclaredMethod("getName");
```

**2. JIT 인라인 최적화 불가**
- JIT(Just-In-Time)는 자주 호출되는 메서드를 네이티브 코드로 컴파일하고 **인라인 최적화**
  ```java
  // 인라인 전: return add(1, 2);
  // 인라인 후: return 1 + 2;  // 호출 오버헤드 0
  ```
- 리플렉션은 런타임에 대상이 결정되어 JIT가 미리 알 수 없음 → 인라인 불가

**3. 접근 권한 체크**
- `setAccessible(true)` 후에도 매 호출마다 보안 체크

**4. 박싱/언박싱 오버헤드**
```java
int value = dto.getAge();              // primitive, 빠름
Object value = method.invoke(dto);     // Object로 박싱!
int v = (Integer) value;               // 언박싱
```

> **면접 예상 질문:** 리플렉션이 느린 이유 네 가지를 설명하라. Metaspace 위치 때문이 맞나?

---

### 리플렉션 최적화 — ConcurrentHashMap 캐싱

초당 수백 건 엑셀 변환에서 매번 리플렉션을 돌리면 병목. 해결책은 **`ConcurrentHashMap<Class<?>, FieldMetadata>` 캐싱**.

```
1️⃣ 첫 호출: CACHE.get(SettlementDto.class) → null
         → 리플렉션 분석 (1회)
         → CACHE.put(SettlementDto.class, 결과)

2️⃣ 이후: CACHE.get(SettlementDto.class) → O(1) 즉시 반환
```

**멀티스레드 고려 — 왜 ConcurrentHashMap?**
```java
// 일반 HashMap → Thread-Safe 아님
static Map<Class<?>, List<FieldMeta>> cache = new HashMap<>();

// ConcurrentHashMap → 동시 접근 안전
static Map<Class<?>, List<FieldMeta>> cache = new ConcurrentHashMap<>();
```

**우아한 구현 — `computeIfAbsent`**
```java
List<FieldMeta> metas = CACHE.computeIfAbsent(
    dto.getClass(),
    clazz -> analyzeFields(clazz)  // 없을 때만 분석, 원자적
);
```

**Spring의 실제 사례:** `AnnotationUtils`, `ReflectionUtils` 내부가 전부 캐시 기반 설계. "Spring이 내부적으로 쓰는 패턴을 따랐다"고 답하면 가산점.

> **면접 예상 질문:** 리플렉션 성능 문제를 어떻게 최적화하는가? `computeIfAbsent`를 쓰는 이유는?

---

## 학습 정리

- **JVM Heap**은 Young Gen(Eden + S0 + S1) + Old Gen으로 구성 — Weak Generational Hypothesis 기반 설계
- **Minor GC**는 Young만, **Full GC**는 Old Gen 포함 전체(Stop-The-World)
- **OOM은 참조가 살아있는 대량 객체** 때문 — Memory Leak이 아닌 Memory Pressure
- 대용량 배치는 **Chunk 단위**로 참조를 빨리 끊어 Young Gen에서 수거 유도
- Chunk 사이즈는 **측정 기반 튜닝** — 정답이 아닌 트레이드오프 사고방식이 핵심
- **Stack**은 스레드별 독점/자동 정리, **Heap**은 공유/GC 관리 → Race Condition은 Heap에서만
- Java 8부터 **Method Area = Metaspace**(Native Memory) — PermGen OOM 문제 해결
- **리플렉션이 느린 이유**: String 탐색 + JIT 인라인 불가 + 접근 체크 + 박싱/언박싱
- **리플렉션 최적화**: `ConcurrentHashMap` + `computeIfAbsent`로 메타데이터 캐싱

## 참고

- 정산예정금·매출금 Manager 모듈, Spring Batch, 커스텀 어노테이션+리플렉션 경험 기반
- JVM Specification — Run-Time Data Areas
- Oracle Java Platform Standard Edition HotSpot Virtual Machine Garbage Collection Tuning Guide
- Spring `ReflectionUtils`, `AnnotationUtils` 소스
