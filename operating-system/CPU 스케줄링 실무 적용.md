# CPU 스케줄링 실무 적용

> 날짜: 2026-04-24

## 내용

### 프로세스/스레드/코어와 Ready 큐

```
🏢 컴퓨터
 └─ 🧠 CPU
     ├─ 💪 코어 1~8  (물리적 하드웨어)
 📦 프로세스 (Spring Boot 앱)
     └─ 🧵 스레드 1, 2, 3, ... (여러 개 가능)
```

- **프로세스**: 실행 중인 프로그램 (Spring Boot 앱, Chrome)
- **스레드**: 프로세스 내 실행 단위 (Tomcat 워커 스레드)
- **코어**: 실제 연산 하드웨어

**핵심 규칙:**
- 같은 프로세스 내 스레드들은 **Heap 공유** → 동기화 필요
- 다른 프로세스끼리는 **메모리 격리**
- OS는 **스레드 단위**로 스케줄링
- **1코어 = 동시 1개 스레드 실행**

**스레드 4가지 상태:**
- 🏃 **RUNNING** — 코어에서 실행 중
- ⏳ **READY** — 대기 중 (**스케줄러 관리 대상**)
- 💤 **BLOCKED** — I/O 대기 (런큐에서 빠짐)
- ☠️ **TERMINATED** — 종료

```
READY → (스케줄러 선택) → RUNNING
RUNNING → (Quantum 소진) → READY
RUNNING → (I/O 요청) → BLOCKED
BLOCKED → (I/O 완료) → READY
```

**핵심:** CPU 스케줄링 = **"Ready 큐에서 어떤 스레드를 뽑아 어느 코어에 배치할지"** 결정.

> **면접 예상 질문:** 프로세스와 스레드의 차이는? CPU 스케줄러가 관리하는 스레드 상태는 무엇인가?

---

### 동시성(Concurrency) vs 병렬성(Parallelism)

| 개념 | 정의 | 조건 |
|---|---|---|
| **동시성** | 번갈아 실행 (시분할) | 1코어에서도 가능 |
| **병렬성** | 물리적으로 동시 실행 | 멀티코어 필수 |

```
1코어 + 스레드 100개 → 동시성 ✅ / 병렬성 ❌
8코어 + 스레드 100개 → 동시성 ✅ / 병렬성 ✅ (최대 8개)
```

> **면접 예상 질문:** 동시성과 병렬성은 어떻게 다른가? 1코어에서도 멀티스레드가 유효한 이유는?

---

### 스케줄링 알고리즘과 워크로드 매칭

| 알고리즘 | 특징 | 약점 |
|---|---|---|
| **FCFS** | 도착 순 처리 | **Convoy Effect** — 긴 작업이 뒤를 막음 |
| **SJF** | 짧은 작업 우선, 평균 대기 최소 | **예측 불가 + Starvation** |
| **Priority** | 우선순위 높은 것 먼저 | 저우선순위 기아 |
| **Round Robin** | Time Quantum 만큼 공정 분배 | Quantum 튜닝 민감 |
| **MLFQ** | RR + Priority + Aging 결합 | Gaming 취약 → Priority Boost로 해결 |

**워크로드별 선택:**

| 워크로드 | 알고리즘 | 근거 |
|---|---|---|
| **배치** (대출 한도 계산) | FCFS + Priority | 처리량·총 완료 시간 중심, 새벽 실행 → Convoy 무관 |
| **실시간 스크래핑** | **MLFQ** | 응답성 + I/O 친화 + 공정성. I/O 대기가 많아 자동 상위 큐 유지 |

**Linux CFS는 실제로 MLFQ 변형.**

> **면접 예상 질문:** 각 스케줄링 알고리즘의 트레이드오프는? 배치와 실시간 서비스에 어울리는 전략은 왜 다른가?

---

### Convoy Effect와 실무 스레드 풀 분리

**정의:** FCFS에서 긴 작업 하나가 뒤의 짧은 작업들을 전부 막는 현상.

**실무 예시:**
- 하나의 스레드 풀에서 **10초짜리 리포트** 요청이 스레드 점유
- 뒤의 1ms 요청들이 무한 대기 → API 전체 응답성 붕괴

**해결:** 무거운 작업은 **별도 스레드 풀 / 비동기 큐로 분리**.

> **면접 예상 질문:** Convoy Effect란? 실무에서 어떻게 방지하는가?

---

### Round Robin과 Time Quantum 트레이드오프

| Quantum | 문제 |
|---|---|
| **너무 짧음** (1ms) | **컨텍스트 스위칭 오버헤드** > 실제 작업 (레지스터 저장, CPU 캐시 무효화, TLB 초기화) |
| **너무 김** (10s) | 사실상 FCFS로 퇴화 → Convoy Effect |

Linux CFS는 **1~10ms 동적 조절**.

> **면접 예상 질문:** Round Robin의 Time Quantum을 짧게/길게 잡을 때 각각의 문제는?

---

### SJF의 두 가지 치명적 문제

1. **예측 불가** — 프로세스가 CPU를 얼마나 쓸지 미리 알 수 없음 (지수 평균으로 추정하지만 부정확)
2. **Starvation (기아)** — 긴 작업이 영원히 CPU 못 받음

**해결책: Aging** — 오래 대기한 프로세스의 우선순위를 점진적으로 상승시켜 결국 실행되게 함.

> **면접 예상 질문:** SJF가 이론적으로 최적인데 실무에서 잘 안 쓰이는 이유는?

---

### CPU Bound vs I/O Bound와 스레드 풀 사이징

| 구분 | 특징 | 예시 | 스레드 수 |
|---|---|---|---|
| **CPU Bound** | CPU가 계속 바쁨 | 암호화, 이미지 처리, 한도 계산 | **코어 수 + 1** |
| **I/O Bound** | 외부 자원 대기 많음 | 스크래핑, PG 호출, DB 쿼리 | **훨씬 많이** |

구분 팁: "CPU가 바빠?" → CPU Bound / "뭔가를 기다려?" → I/O Bound.

**백엔드 서비스 대부분 I/O Bound.**

**브라이언 괴츠 공식 (Java Concurrency in Practice):**
```
최적 스레드 수 = CPU 코어 × (1 + 대기시간 / CPU시간)
```

**스크래핑 시스템 (8코어):** 네트워크 2초 / CPU 0.01초
```
8 × (1 + 2/0.01) = 8 × 201 = 1,608개
```

**현실적 한계:**
- 스레드당 Stack 기본 1MB → **10,000개면 10GB**
- 컨텍스트 스위칭 폭증 → 실제로는 **수백 개 수준**에서 운용

**황금률:**
- **너무 적음** → CPU 놀음 → 처리량 ↓
- **너무 많음** → 스위칭 비용 + Stack 메모리 고갈 → 성능 ↓

> **면접 예상 질문:** CPU Bound와 I/O Bound를 어떻게 구분하고, 스레드 풀 크기를 어떻게 산정하는가?

---

### 우선순위 역전 (Priority Inversion)

**시나리오:**
1. L(낮음)이 락 획득 후 작업 중
2. H(높음)가 같은 락 요청 → L 대기
3. M(중간)이 도착 → L 밀어냄 → L이 락 못 품
4. 결과: **최고 우선순위 H가 M 때문에 무한 대기**

**실제 사례:** 1997년 NASA 화성 탐사선 Pathfinder — 미션 중단 직전까지 감.

**OS 레벨 해결:**
- **우선순위 상속(Priority Inheritance)** — L이 H의 락 대기 중이면 L을 H만큼 일시 승급
- **우선순위 천장(Priority Ceiling)** — 락 자체에 최고 우선순위 강제 승급 규칙

**Java/Spring 실무 해결** (우선순위 상속 기본 미지원):
```yaml
hikari.connection-timeout: 3000  # DB 커넥션 타임아웃
```
```java
@Transactional(timeout = 10)     // 트랜잭션 타임아웃
```
- **커넥션 풀 분리** — 실시간용 / 배치용 격리

**핵심 철학:** "**자원을 오래 붙잡는 걸 강제 차단**" — 타임아웃 + 자원 격리 + 재시도.

> **면접 예상 질문:** Priority Inversion이 무엇이며 어떻게 발생하는가? Java에서는 어떻게 대응하는가?

---

### Preemptive vs Non-Preemptive

| 구분 | 설명 | 장단 |
|---|---|---|
| **Preemptive (선점형)** | OS가 언제든 CPU 강제 회수 | 응답성·안정성 ↑ |
| **Non-Preemptive (비선점형)** | 스레드가 스스로 놓을 때까지 유지 | 무한 루프 시 전체 정지 |

**현대 OS(Linux/macOS/Windows)는 전부 Preemptive** — 긴 배치 중에도 급한 작업 즉시 처리 가능.

**특이 케이스:** JavaScript 이벤트 루프, Kotlin 코루틴 → **Cooperative** (스스로 yield).

> **면접 예상 질문:** Preemptive와 Non-Preemptive의 차이는? 현대 OS가 선점형인 이유는?

---

### Kafka에서 우선순위 구현 — 토픽 분리 + poll 순서

Kafka 자체에는 메시지 우선순위 개념이 없다. **토픽을 분리하고 `poll()` 순서를 제어**해서 해결.

```java
while (true) {
    var vipRecords = vipConsumer.poll(Duration.ofMillis(100));
    if (!vipRecords.isEmpty()) {
        process(vipRecords);
    } else {
        var normalRecords = normalConsumer.poll(Duration.ofMillis(100));
        process(normalRecords);
    }
}
```

**함정: Starvation** — VIP가 계속 들어오면 일반 토픽은 영원히 대기.

**완화: Weighted Fair Queuing** — VIP 3건 처리 후 일반 1건 강제 처리.

- `subscribe()` = "이 토픽 관심 있음" 등록
- `poll()` = "메시지 주세요" **Pull 요청**
- `@KafkaListener`는 이 poll 루프를 프레임워크가 대신 돌리는 것

> **면접 예상 질문:** Kafka에서 메시지 우선순위는 어떻게 구현하는가? Starvation은 어떻게 방지하는가?

---

### 대규모 트래픽 대응 — 20,000 TPS 시나리오

**상황:** 평소 1,000 TPS → 블랙프라이데이 20,000 TPS / 8코어 / 스레드 200 / Ready 큐 1,000

**예상 문제:**
1. **컨텍스트 스위칭 폭증** → 200개 스레드가 8코어에서 번갈아 → CPU가 스위칭에 시간 낭비
2. **Ready 큐 오버플로우** → `Connection Refused` / `RejectedExecutionException`
3. **기아** → 긴 결제 건이 스레드 점유 시 짧은 건 무한 대기
4. **GC Pause** → 메모리 급증 → Stop-The-World 전체 스레드 정지

**실무 대응 조합:**

| 우선순위 | 대응 | 효과 |
|---|---|---|
| **근본** | 서버 수평 확장 | 1대 한계 초과 불가 |
| 1 | **Kafka 버퍼링** | peak shaving(피크 평탄화) + 유실 방지 |
| 2 | **Circuit Breaker** (Resilience4j) | 장애 전파 차단, 빠른 실패 |
| 3 | **WebFlux** 비동기 | 외부 API 호출 시 스레드 즉시 반납 |
| 4 | 스레드 풀 튜닝 | I/O Bound에서만 효과 |
| 5 | GC 튜닝 (G1GC, ZGC) | STW 최소화 |

**통찰:** 수직 확장(스펙 증설)은 한계 → **20,000 TPS는 수평 확장 필수.**

> **면접 예상 질문:** 트래픽 폭증 시 CPU 스케줄링 관점의 문제와 대응책은?

---

### WebFlux가 스레드 풀 한계를 극복하는 이유

**Spring MVC (Blocking):**
```
요청 1개 = 스레드 1개가 끝까지 물고 있음
외부 API 응답 대기 중에도 스레드 점유 → 스레드 풀 금방 고갈
```

**WebFlux (Non-Blocking):**
```
요청 도착 → 외부 API 호출 → 스레드 즉시 반납!
응답 오면 → 놀고 있던 스레드가 마무리 처리
```

**결과:** **스레드 8~16개로 수천 TPS** 가능 (이벤트 루프).

**트레이드오프:**
- 학습 곡선 가파름 (Reactive 프로그래밍)
- 스택 트레이스 복잡 → 디버깅 어려움
- **전체 스택이 비동기**여야 효과 (JDBC → R2DBC 교체 필요)

> **면접 예상 질문:** WebFlux는 왜 적은 스레드로 높은 TPS를 낼 수 있는가? 트레이드오프는?

---

### MLFQ와 Priority Boost

**약점 — Gaming the Scheduler:**
- Quantum 직전에 의미 없는 I/O를 섞어 넣어 **대화형 작업으로 오판 유도**
- 계속 최상위 큐에 머무름 → 다른 작업 기아

**해결 — Priority Boost:**
- 일정 주기(예: 1초)마다 **모든 프로세스를 강제로 최상위 큐로 리셋**
- Gaming 무력화 + Aging 효과(오래 강등된 작업도 기회)

> **면접 예상 질문:** MLFQ의 약점과 Priority Boost의 역할은?

---

## 학습 정리

- CPU 스케줄링의 본질은 **Ready 큐에서 어떤 스레드를 뽑아 어느 코어에 배치할지** 결정
- **동시성**(1코어에서도 가능)과 **병렬성**(멀티코어 필수)은 다른 개념
- **FCFS/SJF/Priority/RR/MLFQ** 각각 트레이드오프 존재 — 배치는 FCFS+Priority, 실시간은 MLFQ
- **Convoy Effect** 방지를 위해 무거운 작업은 별도 스레드 풀/비동기 큐로 분리
- Round Robin Quantum: 짧으면 **스위칭 오버헤드**, 길면 **FCFS 퇴화**
- SJF의 **예측 불가 + Starvation** → Aging으로 완화
- **I/O Bound 백엔드는 스레드 풀을 크게**, 브라이언 괴츠 공식으로 산정하되 Stack 메모리 한계 고려
- **Priority Inversion**은 우선순위 상속/천장으로 해결, Java에서는 **타임아웃 + 커넥션 풀 분리**
- 현대 OS는 전부 **Preemptive**, JS 이벤트 루프/코루틴은 Cooperative
- Kafka 우선순위는 **토픽 분리 + poll 순서 제어**, Starvation 방지용 Weighted Fair Queuing
- **20,000 TPS는 수평 확장 필수** + Kafka 버퍼링 + Circuit Breaker + WebFlux 조합
- WebFlux는 외부 API 대기 중 **스레드 즉시 반납**으로 적은 스레드로 수천 TPS
- MLFQ의 Gaming 취약점 → **Priority Boost**로 주기적 리셋

## 참고

- 에이젠글로벌 Kafka 스크래핑 시스템, Spring Batch 대출 한도 계산 경험 기반
- Brian Goetz — *Java Concurrency in Practice* (스레드 풀 사이징 공식)
- OSTEP (Operating Systems: Three Easy Pieces) — MLFQ, Priority Boost
- Linux CFS (Completely Fair Scheduler) 문서
