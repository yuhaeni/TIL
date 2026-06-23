# 동시성 벌크헤드 — Semaphore, fast-fail vs queue, StreamingResponseBody async 스레드

> 날짜: 2026-06-23

## 내용

> **벌크헤드(Bulkhead)** 라는 이름은 배의 방수 격벽에서 왔다. 한 칸에 물이 차도 격벽이 막아 다른 칸까지 침수되지 않게 하듯, 무거운 요청의 폭주를 그 경로 안에 가둬 시스템 전체가 같이 죽는 것을 막는다.

### Semaphore — 입장권 통, permit은 카운터(스레드 비소유)

벌크헤드의 핵심 구현은 `Semaphore`다. 식당 입구의 **입장권 통**에 비유할 수 있다.

```java
public class Bulkhead {
    private final Semaphore semaphore;

    public Bulkhead(BulkheadProperties props) {
        // fairness=true: 대기 모드에서 도착 순서대로 permit을 받아 기아를 막는다
        this.semaphore = new Semaphore(props.getPermits(), true);
    }

    public boolean tryAcquire() { return semaphore.tryAcquire(); }
    public void release()       { semaphore.release(); }
}
```

- `new Semaphore(8)` → 통 안에 입장권 8장. 들어오려면 `acquire()`로 한 장 집고, 나갈 때 `release()`로 도로 넣는다. 통이 비면 9번째 손님은 못 들어간다.
- **permit은 물리적 객체가 아니라 내부 정수 카운터다.** `acquire()` = 카운터 −1, `release()` = 카운터 +1, 0이면 실패(또는 대기). "입장권"은 사실 *카운터를 1 깎을 권리*다.
- **permit은 특정 스레드 소유가 아니다.** 그래서 A 스레드가 `acquire`하고 B 스레드가 `release`해도 안전하다. (락은 보통 "잠근 스레드만 풀 수 있다"는 점에서 이게 다르다.) 이 성질 덕분에 Tomcat 스레드에서 acquire하고 async 스레드에서 release하는 구조가 성립한다.

> **면접 예상 질문:** Semaphore와 Lock(예: ReentrantLock)의 가장 큰 차이는 무엇이며, "permit은 스레드 소유가 아니다"라는 성질이 어떤 설계를 가능하게 하나요?

---

### fast-fail vs queue — 느린 성공보다 빠른 실패

permit이 없을 때(9번째 손님) 행동은 두 가지 모드로 갈린다. `acquireTimeoutMs` 설정값으로 토글한다.

```java
public boolean tryAcquire() {
    if (acquireTimeoutMs <= 0) {
        return semaphore.tryAcquire();                                   // fast-fail
    }
    return semaphore.tryAcquire(acquireTimeoutMs, TimeUnit.MILLISECONDS); // queue
}
```

- **타임아웃 = 0 (fast-fail)**: "지금 표 있어요? 없으면 바로 가세요." → 즉시 `false`, 안 기다린다.
- **타임아웃 > 0 (queue)**: "그 시간 안에 자리 나면 즉시 드리고, 안 나면 가세요." → 무조건 그 시간을 다 기다리는 게 아니라, **자리가 나는 즉시 획득**하고 안 나면 실패.

**왜 굳이 매정하게 바로 돌려보내나?** 트래픽이 폭주하면 어차피 처리 못 할 요청이 많다. 기다리게 했다가 실패시키는 건 두 배 손해다 — 손님은 오래 기다리고도 쫓겨나 더 화나고, 그동안 서버는 그 대기 요청의 메모리·스레드를 붙들고 있다. **느린 성공보다 빠른 실패가 시스템 전체엔 더 건강하다.** fast-fail은 p95 31초 큐 대기를 0.1초 만의 429로 바꾼다.

거절은 **HTTP 429 (Too Many Requests)** 로 나간다. 500이 아니라 429인 이유:
- **5xx** = "서버가 고장났다" → 재시도 무의미 + 알람.
- **4xx/429** = "요청 쪽 문제, 잠깐 바쁘니 back off 후 재시도하라" → 벌크헤드 거절은 서버 고장이 아니므로 의미상 정확.
- 상태 코드는 사람만 읽는 게 아니라 **클라이언트·로드밸런서(기계)도 읽고 자동으로 행동을 바꾼다.** (`Retry-After` 헤더는 붙이면 좋지만 필수는 아님 — 리뷰에서 blocking이 아닌 nice-to-have로 분류.)

> **면접 예상 질문:** 한정된 자원을 초과하는 요청에 대해 "대기시키기(queue)"와 "즉시 거절(fast-fail)" 중 어느 쪽이 더 나은가요? 어떤 상황에서 각각을 선택하며, 거절 시 상태 코드를 429로 두는 이유는 무엇인가요?

---

### async 스레드 / 람다 정의 vs 실행 — writeTo는 나중에 별도 스레드가

```java
@GetMapping("/sales/details/stream/guarded")
public ResponseEntity<StreamingResponseBody> streamSalesDetailsGuarded(...) {
    if (!heavyQueryBulkhead.tryAcquire()) {                 // ① Tomcat 스레드(동기 구간)에서 acquire
        throw new BulkheadRejectedException("BULKHEAD_REJECTED", "동시 처리 한도 초과");
    }
    StreamingResponseBody body = out -> {                   // ② 람다 "정의"일 뿐, 아직 실행 아님
        try {
            salesManager.streamSalesDetails(from, to, out);
        } finally {
            heavyQueryBulkhead.release();                   // ③ async 스레드(writeTo)에서 release
        }
    };
    return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(body);
}
```

- **일반 MVC**: Tomcat 스레드 한 명이 요청 받기→컨트롤러→응답 쓰기까지 다 하고 풀로 복귀.
- **StreamingResponseBody**: "느린 스트리밍은 Tomcat 스레드를 빨리 풀어주고, 응답 쓰기(`writeTo(out)`)는 별도 **async 스레드**가 나중에 한다." 이유 — 느린 스트리밍이 한정된 Tomcat 풀을 30초씩 붙잡으면 다른 요청 받을 스레드가 고갈되기 때문.
- **람다 정의 vs 실행이 헷갈리는 포인트**: `body = out -> {...}` 줄은 레시피를 적어둔 것(정의)일 뿐 실행이 아니다. 그래서 `streamSalesDetails(...)`의 반환값은 람다 실행 여부와 무관하다(그 호출은 람다 *안*에 있다). 실제 실행은 Spring의 async 장치가 `writeTo`를 호출할 때 일어난다.

이 구조에서 **acquire와 release의 위치가 비대칭**인 게 핵심이다.
- `acquire`는 컨트롤러 동기 구간 → 거절이 응답 커밋 *전*이라 정상 MVC 경로로 깨끗한 429가 나간다.
- `release`는 바디의 `finally` → 바디는 컨트롤러 리턴 후 async 스레드가 실행하므로, permit이 **스트림 마지막 flush까지** 점유돼야 cap이 실효한다. (컨트롤러 finally에 두면 바디 쓰기 전에 반납돼 cap이 무너진다.)
- permit 누수 전제: `tryAcquire` 성공~`return` 사이엔 람다 *정의*만 있어 예외 틈이 없다. 그리고 async executor가 **작업을 거절하지 않아** `writeTo`가 항상 1회 실행 → `finally` 보장. **단 bounded queue + 거절 정책(AbortPolicy) executor를 도입하면** 큐가 꽉 찼을 때 작업이 거절(`RejectedExecutionException`)돼 바디가 안 불려 permit이 샐 수 있다 → release를 async 완료 리스너로 옮기는 보강이 필요하다.

> **⚠️ "기본 executor가 무엇인가"를 정확히 — `SimpleAsyncTaskExecutor`가 아니다 (Spring Boot 3 기준):**
> 흔히 "Spring MVC async 기본 executor = `SimpleAsyncTaskExecutor`(무제한 스레드)"라고 단정하기 쉽지만, 이는 **순수 Spring MVC(부트 없이)** 일 때의 폴백이다. **Spring Boot**를 쓰면 `TaskExecutionAutoConfiguration`이 `applicationTaskExecutor`(`ThreadPoolTaskExecutor`) 빈을 자동 등록하고, `WebMvcAutoConfiguration.configureAsyncSupport`가 그 빈을 MVC async executor로 끼워준다. 즉 실제 기본값은 **`ThreadPoolTaskExecutor` (core=8, max=Integer.MAX_VALUE, queue-capacity=Integer.MAX_VALUE)** — 사실상 **8스레드 + 무한 큐**다.
> - **누수 없다는 결론은 그대로 살아있지만 *이유*가 바뀐다**: "무제한 스레드라 항상 실행"이 아니라 **"무한 큐라 큐가 절대 안 차서 거절 단계에 도달 못 함 → 항상 실행"** 이다.
> - **무한 큐의 진짜 위험은 스레드 증식이 아니라 메모리다**: 거절을 안 하는 대신, 폭주 시 작업이 큐에 끝없이 쌓이다 **OOM**이 날 수 있다. 벌크헤드(admission control)로 *큐에 들어가기 전에* 막아야 하는 이유.

> **면접 예상 질문:** StreamingResponseBody를 쓸 때 Tomcat 스레드와 async 스레드가 어떻게 나뉘며, 세마포어 acquire를 컨트롤러 동기 구간에, release를 바디의 finally에 두는 비대칭 배치가 왜 필요한가요? 이 구성에서 permit이 누수될 수 있는 조건은 무엇인가요?

---

## 학습 정리

- **벌크헤드**는 배의 방수 격벽처럼, 무거운 요청의 동시 진입을 cap 해 공용 자원(커넥션 풀) 고갈로 시스템 전체가 죽는 것을 막는 admission control이다.
- **Semaphore**의 permit은 물리 객체가 아니라 정수 카운터이며, 특정 스레드 소유가 아니라서 A 스레드 acquire / B 스레드 release가 안전하다.
- **fast-fail(즉시 429)** 은 트래픽 폭주 시 "느린 성공보다 빠른 실패"가 더 건강하다는 원칙을 구현한 것으로, p95 31초 큐 대기를 0.1초 거절로 바꾼다. 거절은 "서버 고장(5xx)"이 아니라 "잠깐 바쁨, 재시도하라(429)"의 의미다.
- **StreamingResponseBody**는 Tomcat 스레드를 빨리 풀어주고 `writeTo`(=람다 실행)를 async 스레드에 위임한다. 람다는 "정의"와 "실행" 시점이 다르며, 이 때문에 acquire(동기 구간)와 release(바디 finally)의 비대칭 배치가 cap 실효의 조건이 된다.
- **Spring Boot의 MVC async 기본 executor는 `SimpleAsyncTaskExecutor`가 아니라 `applicationTaskExecutor`(`ThreadPoolTaskExecutor`, 8스레드+무한 큐)** 다. 무한 큐라 작업 거절이 없어 permit 누수가 없지만, 그 대가로 폭주 시 큐 적체 → OOM 위험이 있다. (`SimpleAsyncTaskExecutor`는 부트 없는 순수 MVC의 폴백.)
