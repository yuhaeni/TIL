# 스레드 동기화 — Race Condition, synchronized, 분산 환경

> 날짜: 2026-05-15

## 내용

### 프로세스와 스레드의 메모리 구조 차이

스레드끼리 무엇을 공유하고 무엇을 따로 가지는지가 동기화 문제의 출발점이다.

| 영역 | 공유 여부 | 내용 |
|---|---|---|
| **Code(Text)** | ✅ 공유 | CPU 명령어 |
| **Data** | ✅ 공유 | 전역/static 변수 |
| **Heap** | ✅ 공유 | `new`로 동적 할당된 객체 |
| **Stack** | ❌ 스레드별 | 지역변수, 함수 호출 정보(매개변수, 리턴 주소) |
| **Register / PC** | ❌ 스레드별 | CPU 작업 상태값 (스레드별 실행 흐름) |

**핵심:** Heap을 공유한다는 것 = 여러 스레드가 같은 객체를 동시에 만질 수 있다 = Race Condition의 원천.

> **면접 예상 질문:** 같은 프로세스 내 스레드들이 공유하는 영역과 공유하지 않는 영역은? 스택이 스레드별로 분리되어야 하는 이유는?

---

### 프로세스 vs 스레드 — 생성/전환 비용

스레드가 가벼운 이유는 **공유 영역을 재사용**하기 때문이다.

#### 생성 비용

| 작업 | 프로세스 | 스레드 |
|---|---|---|
| PCB / TCB 생성 | 새 PCB | 같은 PCB 안에 TCB만 추가 |
| 메모리 공간 | Code/Data/Heap/Stack 전부 새로 | **Stack만 새로 할당** |
| 페이지 테이블 | 새로 생성 | 기존 페이지 테이블 공유 |
| 파일 디스크립터 | 복사 | 공유 |
| **시간** | 수 ms ~ 수십 ms | 수십 μs (약 100~1000배 차이) |

#### 컨텍스트 스위칭 비용

| 단계 | 프로세스 전환 | 스레드 전환 |
|---|---|---|
| 1. 레지스터 저장/복원 | ✅ | ✅ |
| 2. 메모리 맵(페이지 테이블) 전환 | ✅ | ❌ 같은 프로세스라 그대로 |
| 3. **TLB 플러시** | ✅ 발생 | ❌ 발생 안 함 |
| 4. 캐시 적중률 | 떨어짐 (콜드) | 유지 |

**TLB(Translation Lookaside Buffer):** 가상 주소 → 물리 주소 변환을 캐싱하는 곳. 프로세스가 바뀌면 매핑이 통째로 바뀌므로 TLB를 비워야 한다. 비운 직후에는 모든 메모리 접근이 느려져 캐시 미스가 폭증한다.

→ 스레드 전환은 같은 페이지 테이블을 쓰므로 TLB가 유지되어 훨씬 빠르다.

> **면접 예상 질문:** 스레드의 컨텍스트 스위칭이 프로세스보다 빠른 이유는? TLB 플러시가 왜 비용이 큰가?

---

### 멀티스레드의 장단점

같은 자원을 공유한다는 성질이 장점인 동시에 단점이 된다 — **동전의 양면**.

| 항목 | 내용 |
|---|---|
| **장점 1 — 효율성** | 생성/전환 비용 ↓ (TLB 플러시 X, 스택만 할당) |
| **장점 2 — 통신 효율** | 같은 Heap 공유 → 변수로 주고받음, IPC 불필요 |
| **장점 3 — 응답성** | 한 스레드가 I/O로 막혀도 다른 스레드는 즉시 응답 가능 (Tomcat 스레드 풀이 이래서 멀티스레드) |
| **단점 — 동기화 필요** | 공유 자원 동시 접근 → Race Condition, Deadlock 위험 |

#### IPC가 비싼 이유 (멀티프로세스의 통신 비용)

프로세스끼리는 메모리 공간이 분리되어 있어 데이터를 **OS 커널을 거쳐 두 번 복사**해야 한다.

```
프로세스 A → [메모리 복사 1] → OS 커널 → [메모리 복사 2] → 프로세스 B
```

IPC 수단: 파이프, 소켓, 공유 메모리, 메시지 큐, 시그널.

→ 멀티스레드는 같은 Heap을 직접 참조하므로 **메모리 복사 0번**. 통신 비용이 거의 공짜.

> **면접 예상 질문:** 멀티스레드의 장점 3가지와 단점은? IPC와 비교했을 때 스레드 간 통신이 빠른 이유는?

---

### Race Condition — `count++`는 왜 위험한가

`count++`는 코드 한 줄로 보이지만 CPU 입장에서 **3단계**로 쪼개진다.

#### 폰 노이만 구조 한계: ALU는 메모리 값을 직접 못 만짐

```
[CPU 내부]
├─ 제어장치 (Control Unit): 모든 동작을 지휘
├─ ALU: 산술/논리 연산 (레지스터 값만 계산 가능)
├─ 범용 레지스터: 임시 저장
├─ MAR (Memory Address Register): 접근할 주소 보관
└─ MBR (Memory Buffer Register): 메모리와 주고받을 값 보관
        ↕ 버스
[메모리(RAM)]
```

ALU는 **레지스터 안의 값만** 계산할 수 있다. 메모리 값을 수정하려면:

#### Read-Modify-Write 3단계

```java
count++;
```
↓ CPU 단계

```
1️⃣ READ (LOAD):   메모리 0x1000번지 값 → 레지스터로 복사
                  (제어장치가 MAR 세팅 → 메모리에 읽기 신호 → MBR → 레지스터)
2️⃣ MODIFY (ADD):  레지스터 값 + 1
                  (제어장치가 ALU에게 명령)
3️⃣ WRITE (STORE): 레지스터 값 → 메모리 0x1000번지에 저장
                  (제어장치가 MAR/MBR 세팅 → 메모리에 쓰기 신호)
```

이 3단계 **사이에 다른 스레드가 끼어들 수 있다**.

#### 어떤 연산이 비원자적인가?

| Java 코드 | 단계 | 원자성 |
|---|---|---|
| `int x = count;` | READ만 (1단계) | ✅ |
| `count = 5;` (상수 쓰기) | WRITE만 (1단계, 32bit 한정) | ✅ |
| `count++` | READ + MODIFY + WRITE | ❌ |
| `count += 5` | READ + MODIFY + WRITE | ❌ |
| `count = count * 2` | READ + MODIFY + WRITE | ❌ |
| `long balance = 100;` | 32bit 시스템에서 2번 WRITE | ❌ (`volatile` 필요) |

**핵심 규칙:** "현재 값을 기반으로 새 값을 계산해서 다시 저장하는 모든 연산"은 비원자적이다.

#### Race Condition 실제 시나리오 (count = 0 시작)

```
[시간] [스레드 A]              [스레드 B]              [메모리]
  t1   READ → 0                                          0
  t2                            READ → 0                 0  ← B도 0 읽음
  t3   MODIFY: 0+1=1                                     0
  t4                            MODIFY: 0+1=1            0
  t5   WRITE 1                                           1
  t6                            WRITE 1                  1  ← Lost Update
```

→ 두 번 증가시켰는데 결과는 1. 한 스레드의 결과가 사라지는 **Lost Update** 발생.

> **면접 예상 질문:** `count++`가 왜 원자적이지 않은가? Read-Modify-Write 사이클을 설명하라. Lost Update란?

---

### synchronized 동작 원리 — 모니터 락

Java에서 가장 기본적인 동기화 도구. **모든 Java 객체는 헤더에 락 정보**를 가지고 있다.

#### Java 객체 헤더 구조

```
┌─────────────────────────┐
│  Object Header           │
│  ├─ Mark Word           │ ← 🔒 락 상태, 락 보유 스레드 ID
│  └─ Class Pointer       │
├─────────────────────────┤
│  Instance Data          │ ← 실제 필드값
└─────────────────────────┘
```

이 `Mark Word`에 들어가는 락을 **모니터 락(Monitor Lock) / Intrinsic Lock**이라 한다.

#### synchronized 바이트코드

```java
public synchronized void increment() { count++; }
```
↓ JVM이 바이트코드에 삽입

```
monitorenter   ← 락 잡기
... count++ ...
monitorexit    ← 락 풀기
```

#### 동작 시나리오

```
[시간] [스레드 A]                [스레드 B]              [객체 락]
  t1   monitorenter
       "비어있음 → 내 ID 표시"                            🔒 (A 소유)
  t2                              monitorenter
                                  "A가 가지고 있음"        🔒 (A 소유)
                                  → BLOCKED 상태로 대기
  t3   count++ 실행                                       🔒 (A 소유)
  t4   monitorexit                                       🔓
  t5                              깨어남 → monitorenter
                                  내 ID 표시              🔒 (B 소유)
  t6                              count++ → monitorexit  🔓
```

→ **한 번에 한 스레드만** 임계 영역에 진입 가능.

#### synchronized 사용법 4가지

```java
// 1. 인스턴스 메서드 (this 객체의 락)
public synchronized void foo() { ... }

// 2. 코드 블록 (this 객체의 락)
synchronized(this) { ... }

// 3. 특정 객체의 락 (락 분리)
private final Object lockA = new Object();
synchronized(lockA) { ... }

// 4. 정적 메서드 (Class 객체의 락)
public static synchronized void bar() { ... }
```

#### JVM의 락 최적화

JVM은 상황에 따라 락 형태를 바꾼다:

| 단계 | 상황 | 비용 |
|---|---|---|
| Biased Locking | 한 스레드만 계속 사용 | 매우 가벼움 (ID 비교만) |
| Lightweight Locking | 가끔 경쟁 | 가벼움 (CAS) |
| Heavyweight Locking | 경쟁 심함 | 무거움 (OS 모니터, BLOCKED) |

> **면접 예상 질문:** synchronized는 어떻게 안전성을 보장하는가? Mark Word는 무엇이고 어디에 있는가? monitorenter/monitorexit 바이트코드는 언제 삽입되는가?

---

### synchronized의 5가지 한계와 대안

synchronized 하나로 모두 해결되지 않아서 다른 도구들이 만들어졌다.

#### 1. 성능 비용

- 락 경합 시 BLOCKED → RUNNABLE 전환 비용 (컨텍스트 스위칭)
- 단순 카운터 증가에는 락 비용이 작업 비용보다 큼

**대안 — `AtomicInteger` (CAS 기반):**
```java
private AtomicInteger count = new AtomicInteger(0);
count.incrementAndGet();  // 락 없이 원자적
```

CAS(Compare-And-Swap)는 하드웨어 명령어로, "기대값과 메모리 값이 같으면 새 값으로 바꿔라"를 한 번에 처리한다.

#### 2. 유연성 부족 — 타임아웃/포기/인터럽트 불가

```java
public synchronized void doWork() {
    // 락 못 잡으면 무한 대기, 타임아웃 X, interrupt 응답 X
}
```

**대안 — `ReentrantLock`:**
```java
private ReentrantLock lock = new ReentrantLock();

if (lock.tryLock(5, TimeUnit.SECONDS)) {
    try {
        // ...
    } finally {
        lock.unlock();
    }
} else {
    // 락 못 잡으면 즉시 다른 일
}
```

`tryLock(timeout)`, `lockInterruptibly()`, 명시적 `unlock()` 지원.

#### 3. 락 범위 = 한 JVM 안에서만

수평 확장된 환경에서 synchronized는 무용지물.

```
[서버 A의 JVM]                [서버 B의 JVM]
synchronized 진입 ✅          synchronized 진입 ✅  (서로 모름)
        ↓                            ↓
   같은 DB row 수정 → Race Condition 발생
```

**대안 — Redis 분산 락:**
```java
RLock lock = redissonClient.getLock("user:" + userId);
try {
    lock.lock();
    // ...
} finally {
    lock.unlock();
}
```

Redis는 모든 서버가 공유하는 외부 자원이라 **여러 JVM을 가로지르는 동기화** 가능.

#### 4. 데드락 위험

여러 락을 잡을 때 순서가 어긋나면 데드락 발생.

```
[스레드 A] lockA → lockB 시도
[스레드 B] lockB → lockA 시도
                ↓
        서로 무한 대기 (데드락)
```

**대안:** `tryLock(timeout)`으로 타임아웃 + 락 획득 순서 일관성 유지.

#### 5. 공정성(Fairness) 없음

대기 중인 스레드 중 누가 락을 잡을지 OS 마음대로. 운 없는 스레드는 **기아 현상(Starvation)** 발생 가능.

**대안:** `new ReentrantLock(true)` — FIFO 공정 모드.

#### 정리표

| 단점 | synchronized | 대안 |
|---|---|---|
| 1. 성능 비용 | 큼 | `AtomicInteger` (CAS) |
| 2. 타임아웃 X | 무한 대기 | `ReentrantLock.tryLock(timeout)` |
| 3. 분산 환경 X | JVM 내부만 | **Redis 분산 락** |
| 4. 데드락 위험 | 명시적 해제 X | `tryLock` + 순서 일관성 |
| 5. 공정성 X | OS 마음 | `ReentrantLock(true)` |

> **면접 예상 질문:** synchronized의 한계는? 단순 카운터에 synchronized 대신 AtomicInteger를 쓰는 이유는? 분산 환경에서 synchronized가 안 되는 이유는?

---

### 수평 확장과 분산 환경의 조율 도구

#### 수직 확장 vs 수평 확장

| 방식 | 설명 | JVM 수 |
|---|---|---|
| **수직 확장 (Scale-Up)** | 한 서버의 사양을 키움 (CPU, RAM 증가) | 1개 (synchronized OK) |
| **수평 확장 (Scale-Out)** | 서버 대수를 늘림 (복제) | 여러 개 (synchronized 무용지물) |

클라우드 시대에는 **수평 확장이 기본**. K8s `HorizontalPodAutoscaler`로 트래픽에 따라 자동 확장.

#### 분산 환경 구조

```
              [클라이언트]
                   ↓
            [로드 밸런서]
        ┌──────┼──────┐
        ↓      ↓      ↓
     [서버1] [서버2] [서버3]   ← 수평 확장된 JVM들
        └──────┼──────┘
               ↓
        [공유 DB / Redis / Kafka]   ← 조율 인프라
```

처리는 분산하되 **데이터는 한 곳**에 모아 일관성 유지.

#### 분산 환경에서 가운데 두는 도구들

| 용도 | 도구 | 특징 |
|---|---|---|
| **분산 락** | Redis (Redisson), Zookeeper, Etcd, DB `SELECT FOR UPDATE` | "한 번에 한 서버만" 보장 |
| **분산 캐시** | Redis, Memcached | 빈번한 데이터 공유 |
| **메시지 큐** | Kafka, RabbitMQ, SQS | 서버 간 비동기 통신 |
| **서비스 디스커버리** | Eureka, Consul, K8s DNS | 서버끼리 위치 찾기 |

#### Redis가 분산 락에서 인기 있는 이유

| 이유 | 설명 |
|---|---|
| 빠름 | 인메모리, μs 단위 응답 |
| 단일 스레드 처리 | Redis 자체가 명령을 순차 처리 → 원자성 자연스럽게 보장 |
| TTL 지원 | 락 자동 해제 (서버 죽어도 데드락 방지) |
| 간단한 API | `SET key value NX PX 5000` 한 줄 |

> **면접 예상 질문:** 수직 확장과 수평 확장의 차이는? 분산 환경에서 synchronized가 안 되는 이유와 대안은? Redis가 분산 락에 적합한 이유는?

---

## 학습 정리

- 같은 프로세스 내 스레드는 Code/Data/Heap을 공유하고, Stack/Register/PC는 분리 → **Heap 공유가 Race Condition의 원천**
- 스레드 생성/전환이 프로세스보다 100~1000배 빠른 이유는 **스택만 할당**하고 **TLB 플러시가 없기** 때문
- 멀티스레드의 장점은 효율성·통신(IPC 불필요)·응답성이고, 단점은 동기화 필요성 — **공유의 양면성**
- `count++`는 CPU 입장에서 **READ-MODIFY-WRITE 3단계**라 원자적이지 않음 → ALU는 레지스터 값만 계산 가능한 폰 노이만 구조 한계 때문
- synchronized는 객체 헤더의 **모니터 락(Mark Word)** 을 사용하며 `monitorenter/monitorexit` 바이트코드로 구현됨
- synchronized의 5가지 한계(성능·타임아웃·분산·데드락·공정성)는 각각 `AtomicInteger` / `ReentrantLock` / Redis 분산 락 등으로 보완
- 수평 확장된 환경(여러 JVM)에서는 synchronized 무용지물 → 공유 인프라(Redis, DB 락, Zookeeper)로 동기화

## 참고

- [ALU와 제어장치](ALU와%20제어장치.md)
- [레지스터 (PC, MAR, MBR, IR)](레지스터%20(PC,%20MAR,%20MBR,%20IR).md)
- [스레드와 멀티스레드](스레드와%20멀티스레드.md)
- [Redis 분산 락과 교착 상태](../redis/Redis%20분산%20락과%20교착%20상태.md)
- [LRU 캐시와 멀티스레드 동시성](../java/LRU%20캐시와%20멀티스레드%20동시성.md)
- [@Transactional 격리 수준](../java/@Transactional%20격리%20수준.md)
- [Kafka 파티션과 컨슈머 모델](../kafka/Kafka%20파티션과%20컨슈머%20모델.md)
