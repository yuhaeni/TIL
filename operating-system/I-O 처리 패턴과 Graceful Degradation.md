# I/O 처리 패턴과 Graceful Degradation

> 날짜: 2026-04-24

## 내용

### 시스템 콜(System Call)과 버퍼링

자바 프로그램은 디스크/네트워크에 직접 접근할 권한이 없다. 반드시 OS 커널에 요청해야 하는데, 이게 **시스템 콜**이다.

**비용:** 시스템 콜마다 **사용자 모드 ↔ 커널 모드 전환**이 발생 → 횟수가 많을수록 누적 비용 큼.

```
FileInputStream.read()  →  매 호출마다 시스템 콜
BufferedInputStream     →  내부 8KB 버퍼에 한 번에 읽고 거기서 꺼냄
```

| 방식 | 1MB 파일 1바이트씩 읽기 | 시스템 콜 횟수 |
|---|---|---|
| `FileInputStream` | 직접 1바이트씩 | **1,000,000회** |
| `BufferedInputStream` (8KB) | 8KB 단위 읽고 내부 버퍼에서 꺼냄 | **약 128회** |

**비유:** 도서관에서 1000페이지 필사할 때 — 한 글자마다 사서한테 책 빌리는 vs 책을 통째로 빌려와서 옮겨 적는 차이.

> **면접 예상 질문:** `BufferedInputStream`이 빠른 이유는? 시스템 콜 비용은 왜 큰가?

---

### 블로킹 I/O와 스레드 풀 고갈

블로킹 I/O에서 스레드는 응답이 올 때까지 **`TIMED_WAITING` 상태로 멈춤** — CPU도 안 쓰고 다른 일도 못 하면서 자리만 점유한다.

**스레드 상태:**
- `RUNNABLE` — 실행 중
- `BLOCKED` — 락 대기
- `WAITING` — 무한 대기
- **`TIMED_WAITING`** — 일정 시간 대기 (I/O 응답 대기 포함)

**스레드 풀 고갈(Thread Pool Exhaustion) 시나리오:**

톰캣 기본 200 스레드 / 외부 사이트 응답 30초 지연 / 동시 250명 요청

```
200 스레드 모두 외부 응답 대기로 점유 → 일은 안 하지만 자리는 잡힘
201번째 요청 → 큐 대기
acceptCount 초과 → Connection Refused
→ 내 서버는 멀쩡한데 외부 사이트가 느려서 내 서버가 죽음 💀
```

**해결책 — Kafka 비동기 처리:**
스크래핑 요청 받으면 **Kafka에 메시지만 던지고 즉시 응답**(스레드 반환). 별도 컨슈머가 백그라운드에서 처리 → API 서버 스레드풀이 외부 사이트에 의해 고갈되지 않음.

> **면접 예상 질문:** 블로킹 I/O에서 스레드는 어떤 상태가 되는가? 스레드 풀 고갈은 왜 발생하며 어떻게 방지하는가?

---

### 논블로킹 I/O와 I/O 멀티플렉싱

**논블로킹 I/O:** 스레드가 I/O 요청을 던지고 멈추지 않음 → 다른 일을 하다가 나중에 결과 확인.

**I/O 멀티플렉싱 (Java NIO `Selector`):** "계속 물어보는 것도 비효율" → 진화된 방식. 여러 I/O 채널을 한꺼번에 모니터링하고 **준비된 것만 처리** → 스레드 1~2개로 수천 연결 처리 가능.

| 구분 | 블로킹 (`java.io`) | 논블로킹 (`java.nio`) |
|---|---|---|
| 스레드 | 응답 올 때까지 멈춤 | 멈추지 않고 다른 일 |
| 대표 API | `Socket`, `FileInputStream` | `Channel`, `Selector` |
| 프레임워크 | Spring MVC | Netty, Spring WebFlux |
| 스레드당 처리 | 1 요청 | 수천 요청 |

**비유:** 바리스타가 커피 머신에 원두 넣고 — 다른 손님 주문 받으러 가다가 — 완성되면 처리. 한 명이 여러 주문 동시 처리.

> **면접 예상 질문:** 논블로킹 I/O와 I/O 멀티플렉싱의 차이는? `Selector`는 어떻게 동작하는가?

---

### Polling vs WebSocket과 TCP 3-way Handshake

**Ajax Polling의 낭비:**
- 클라이언트 100명이 5초마다 요청 → 분당 1,200건
- 대부분 "새 데이터 없음" 응답 → 헛수고
- 매 요청마다 **TCP 핸드셰이크 + HTTP 헤더 오버헤드**

**TCP 3-way Handshake:**

| 단계 | 방향 | 플래그 | 의미 |
|---|---|---|---|
| 1 | Client → Server | **SYN** | "연결하고 싶어!" |
| 2 | Server → Client | **SYN + ACK** | "응, 나도 준비됐어!" |
| 3 | Client → Server | **ACK** | "좋아, 시작하자!" |

→ **네트워크 왕복(RTT) 1.5회** + HTTPS는 **TLS 핸드셰이크** 추가.

**WebSocket의 해결:**
- **최초 1회 핸드셰이크** 후 TCP 연결 유지 (Persistent Connection)
- 서버가 데이터 생기면 **Push** → 클라이언트는 조용히 대기
- 불필요 요청 0건, 헤더 오버헤드 0건, **양방향 통신**
- 보통 **NIO Selector 기반** — 적은 스레드로 수천 연결 감시

> **면접 예상 질문:** TCP 3-way 핸드셰이크의 단계와 비용은? Polling 대신 WebSocket이 유리한 이유는?

---

### 대용량 파일 스트리밍 — XSSF vs SXSSF

대용량 전문 파일을 엑셀로 변환할 때 두 가지 선택지.

**A안 — 전체 메모리 로드 (`XSSFWorkbook`):**
```java
List<String> lines = Files.readAllLines(path);  // 100MB 전부 Heap
try (XSSFWorkbook workbook = new XSSFWorkbook()) { // 시트 전체도 메모리
    // ...
}
```
- 10만 건 × 1KB = 100MB Heap 점유
- 동시 5명 요청 = 500MB → **OOM 💥**
- GC가 대용량 객체 정리하느라 **Stop-The-World 길어짐**

**B안 — 스트리밍 (`SXSSFWorkbook`):**
```java
try (BufferedReader reader = Files.newBufferedReader(path);
     SXSSFWorkbook workbook = new SXSSFWorkbook(100); // 메모리엔 100행만
     FileOutputStream fos = new FileOutputStream("output.xlsx")) {
    Sheet sheet = workbook.createSheet("전문");
    int rowNum = 0;
    String line;
    while ((line = reader.readLine()) != null) {
        Row row = sheet.createRow(rowNum++);
        row.createCell(0).setCellValue(line);
    }
    workbook.write(fos);
    workbook.dispose(); // 임시 파일 정리 필수!
}
```

**`SXSSFWorkbook(100)` 동작:** 최근 100행만 메모리 유지, 초과분은 **임시 디스크 파일로 flush**. 최종 `write()` 시 디스크+메모리 합쳐 완성. **`dispose()` 필수** — 안 하면 임시 파일 잔존.

| 포인트 | A안 (`XSSF`) | B안 (`SXSSF`) |
|---|---|---|
| 메모리 | 파일 크기 비례 📈 | 상수 유지 📊 |
| OOM 위험 | 대용량에서 터짐 | 안전 |
| 트레이드오프 | 코드 단순 | **디스크 I/O 증가** |

> **면접 예상 질문:** `XSSFWorkbook`과 `SXSSFWorkbook`의 차이는? 스트리밍 처리의 트레이드오프는?

---

### Exception vs Error — JVM이 죽는 사고

```
Throwable
├── Error           ← "JVM/시스템 레벨, 못 고쳐"
│   ├── OutOfMemoryError
│   └── StackOverflowError
└── Exception       ← "애플리케이션 레벨, 처리 가능"
    ├── RuntimeException (Unchecked) — NPE, IllegalArgument
    └── IOException, SQLException... (Checked)
```

| 구분 | Exception | Error |
|---|---|---|
| 의미 | 애플리케이션 문제 | **JVM/시스템 문제** |
| 복구 가능성 | 가능 | **불가능** |
| 처리 방식 | `try-catch` | **잡지 말 것** |
| 예시 | NPE, IOException | **OOM**, StackOverflow |

**OOM이 터지면:**
- JVM이 "더 이상 못해" 선언 — 메모리 꽉 차서 GC도 실패, 로그도 못 남길 수 있음
- 최악의 경우 JVM 프로세스 전체 종료 → **같은 JVM에서 돌던 다른 요청 100개도 전부 죽음**

> **면접 예상 질문:** `Exception`과 `Error`의 차이는? 왜 `Error`는 잡지 말아야 하는가?

---

### Graceful Degradation — "느려지는 건 OK, 죽는 건 절대 안 돼"

**OOM vs 디스크 I/O 증가 비교:**

| 구분 | OOM 발생 | 디스크 I/O 증가 |
|---|---|---|
| 영향 범위 | **JVM 전체 사망** 💀 | 해당 요청만 느려짐 🐢 |
| 다른 요청 | 전부 죽음 | 영향 없음 |
| 복구 | **서버 재시작** 필요 | 자동 회복 |
| 사용자 경험 | 전체 서비스 중단 | "어? 좀 느리네?" |
| 장애 등급 | **P1** | P3 |

**핵심 원칙:**
- **성능 저하(degradation)** = 복구 가능
- **시스템 다운(crash)** = 복구 불가능한 재앙

**실무 적용 패턴:**

| 상황 | 죽는 선택 ❌ | 느려지는 선택 ✅ |
|---|---|---|
| 대용량 파일 | 전체 메모리 로드 → OOM | 스트리밍 → 디스크 I/O 증가 |
| DB 커넥션 | 무한 생성 → 서버 다운 | 커넥션 풀 + 대기 큐 |
| 외부 API | 동기 호출 → 스레드 고갈 | Kafka 비동기 → 처리 지연 |
| 트래픽 폭주 | 전부 처리 시도 → 장애 | Rate Limiting → 일부 대기 |

**면접 답변 템플릿:**
> "메모리 부족은 JVM 전체를 죽이기 때문에 영향 범위가 크고 복구가 어렵지만, 디스크 I/O 증가는 해당 요청만 느려질 뿐 시스템 전체는 안정적입니다. 백엔드는 **'죽지 않는 것'이 '빠른 것'보다 중요**하기 때문에 트레이드오프가 발생하면 메모리 안정성을 우선합니다. 이것이 **Graceful Degradation** 원칙입니다."

> **면접 예상 질문:** Graceful Degradation이란 무엇인가? 실무에서 어떻게 적용하는가?

---

### 전체 흐름 정리

```
시스템 콜 (비싸다)
  ↓ 호출 줄이기
BufferedInputStream (버퍼링)
  ↓ 대용량은 메모리 적게 쓰기
SXSSFWorkbook 스트리밍
  ↓ 왜 메모리를 아껴야 하나?
OOM = Error = JVM 사망
  ↓ 그래서 선택하는 원칙
Graceful Degradation
  ↓ 실무 적용
블로킹 I/O → Kafka 비동기 (스레드 고갈 방지)
Polling → WebSocket (불필요 요청 제거)
```

---

## 학습 정리

- **시스템 콜**은 사용자↔커널 모드 전환 비용이 큼 → `BufferedInputStream`으로 횟수 감소
- **블로킹 I/O**에서 스레드는 `TIMED_WAITING`으로 점유만 됨 → 스레드 풀 고갈로 장애 발생
- **논블로킹 I/O + Selector**는 적은 스레드로 수천 연결 처리 가능
- **TCP 3-way 핸드셰이크**는 RTT 1.5회 비용 → WebSocket은 1회만 하고 연결 유지
- **`SXSSFWorkbook`** 은 N행만 메모리 유지, 나머지 디스크 flush → OOM 방지 (단 `dispose()` 필수)
- **Error**는 JVM 레벨 문제로 복구 불가 → 잡지 말 것
- **Graceful Degradation**: "느려지는 건 OK, 죽는 건 절대 안 돼" — 메모리 안정성 > 성능
- 실무 패턴: Kafka 비동기, 커넥션 풀, Rate Limiting 모두 **죽지 않기 위한 지연 선택**

## 참고

- 에이젠 글로벌 전문 파일 엑셀 변환 (SXSSFWorkbook), 스크래핑 시스템(Kafka 비동기), 두타위즈(WebSocket 전환) 경험 기반
- Apache POI 공식 문서 — `XSSFWorkbook`, `SXSSFWorkbook`
- Java NIO Tutorial — `Channel`, `Selector`
- RFC 793 — TCP 3-way Handshake
