# Spring Batch chunk size와 lock 보유 시간

> 날짜: 2026-05-02

## 내용

### 측정 결과 — chunk size별 트레이드오프

정산 배치 chunk size를 10/100/500으로 바꿔가며 측정한 결과 요약.

| 데이터 | chunk size | (a) step 시간 | (b) heap 피크 | (c) chunk write 평균 | 상대 step 시간 |
|---|---|---|---|---|---|
| 1K | 10 | 1,895 ms | 121 MB | 18 ms | 1.34× |
| 1K | 100 | 1,412 ms | 80.8 MB | 141 ms | 1.0× |
| 1K | 500 | 1,375 ms | 74.6 MB | 687 ms | 0.97× |
| 10K | 100 | 13,034 ms | 74.6 MB | 130 ms | 1.0× |
| 10K | 500 | 11,561 ms | 86.1 MB | 578 ms | 0.89× |
| 100K | 100 | 135,685 ms | 119 MB | 135 ms | 1.0× |
| 100K | 500 | 126,387 ms | 128 MB | 631 ms | 0.93× |

**관찰:**
- chunk 500이 step 시간 7~11% 빠름
- 그러나 chunk write 평균이 **×5** 길어짐 → 곧 lock 보유 시간

> **면접 예상 질문:** chunk size를 늘리면 step 시간이 줄어드는 이유는? 단순히 "큰 게 좋다"고 결론낼 수 없는 이유는?

---

### `(c) 평균 chunk write 시간 = 트랜잭션 lock 보유 시간`

**핵심 연결 고리:**
- UPDATE/INSERT 실행 시점에 **row lock 획득**
- **commit 시점에 lock 해제**
- 한 chunk = 한 트랜잭션 → chunk 안의 모든 row lock이 commit까지 보유

→ **(c) chunk write 시간 = 트랜잭션 시작~commit 시간 = lock 보유 시간**

| chunk size | (c) chunk write | 의미 |
|---|---|---|
| 10 | 17 ms | 락 17ms 잡았다 풀고 반복 |
| 100 | 130 ms | 락 130ms 보유 |
| 500 | 687 ms | 락 **687ms** 동안 계속 보유 (×5) |

다른 트랜잭션이 같은 row를 UPDATE 하려 들어오면 **이미 걸린 락 때문에 대기 상태**로 빠짐.

> **lock 보유 시간 = 다른 트랜잭션의 wait time**

> **면접 예상 질문:** 평균 chunk write 시간과 lock 보유 시간이 같은 이유는? 다른 트랜잭션이 받는 영향은?

---

### 종합 비교 — 4가지 차원

| 차원 | chunk 10 | chunk 100 | chunk 500 |
|---|---|---|---|
| (a) step 시간 | 30~40% 느림 | baseline | 3~11% 빠름 |
| (b) heap | +20% | **가장 안정** | +8~15% |
| (c) lock 보유 | 17~19 ms | 130~141 ms | **578~687 ms (×4.7)** |
| 복구 비용 | 10건 재처리 | 100건 재처리 | **500건 재처리** |

**결론:** chunk 500의 시간 절약(3~11%)이 lock 보유 ×5 cost를 정당화하지 못함 → **chunk 100이 균형점**.

> **면접 예상 질문:** chunk size 선택 시 어떤 4가지 차원을 함께 봐야 하는가?

---

### `.faultTolerant().skip()` — Single-item 재처리 비용 폭증

**Spring Batch skip 동작:**
1. chunk 도중 skippable 예외 발생 → 그 chunk **롤백** (chunk size 만큼 일단 다 날아감)
2. 다시 read → **1건씩** processor → writer → commit 반복
3. 문제의 1건만 skip, 나머지는 결국 commit

**chunk size별 비용 비교 (1건 실패):**

| chunk size | 롤백 후 재처리 | commit 횟수 |
|---|---|---|
| 100 | 100건 1건씩 | 100번 commit |
| 500 | **500건 1건씩** | **500번 commit** (×5) |

→ 원래 1번 commit으로 끝날 것이 **롤백 + N번 read + N번 commit**으로 변환됨.

**도메인 시사점:** skip 가능 예외가 잦은 시스템이라면 chunk 500의 시간 절약은 **단 한 번의 실패로 다 까먹을 수 있음**.

> **면접 예상 질문:** Spring Batch skip 모드의 single-item 재처리는 어떻게 동작하는가? chunk size가 클수록 복구 비용이 어떻게 커지는가?

---

### 면접 답변 템플릿

> "step 시간만 보면 chunk size 500이 가장 빠르지만, **평균 write 시간이 길수록 그만큼 lock 보유 시간이 길어** 다른 트랜잭션이 대기 상태에 빠지는 영향을 줍니다.
>
> 또한 chunk 단위가 클수록 **장애 발생 시 복구 비용**이 크기 때문에(skip 모드에서 rollback 후 단건 재처리), chunk size 100을 선택하는 게 적합합니다.
>
> 정량적으로는 chunk 500이 step 시간 7~11% 빠르지만 lock 보유 시간이 ×5 길고, 1건 실패 시 500번 재처리 비용이 발생합니다."

---

### 동적 vs 정적 chunk size 설정

**chunk size를 외부에서 주입하는 두 가지 방식:**

| 방식 | 장점 | 단점 | 적합 케이스 |
|---|---|---|---|
| `application.yml` + `@Value("${batch.settlement.chunk-size}")` | 단순, 환경별 분리 | 변경 시 **앱 재시작 필요** | 거의 안 바뀌는 값 |
| `@StepScope` + `@Value("#{jobParameters['chunkSize']}")` | 실행마다 override 가능 | 복잡도 ↑ | 매 실행 다른 값 |

**판단 기준:**
- chunkSize처럼 **자주 안 바뀌는 값** → yml로 충분
- targetDate / tenantId처럼 **매 실행 다른 값** → jobParameter 필수
- 모든 걸 동적으로 만들면 오히려 **복잡도만 증가**

> **면접 예상 질문:** Spring Batch에서 설정값을 yml과 jobParameter 중 어떻게 선택하는가?

---

### `@StepScope` 필수 이유 — Late Binding 재확인

`#{jobParameters[...]}` 같은 SpEL은 **Step 실행 시점에야 평가**된다. 일반 싱글톤 빈은 부팅 시점에 생성되므로 그때는 `jobParameters`가 존재하지 않아 SpEL 파싱 실패.

```
일반 @Bean       : 부팅 시 생성 → jobParameters 없음 → 에러 ❌
@StepScope @Bean : Step 실행 시 lazy 생성 → jobParameters 사용 가능 ✅
```

→ jobParameters를 SpEL로 받으려면 **`@StepScope` 필수**.

> **면접 예상 질문:** `jobParameters`를 SpEL로 받을 때 `@StepScope`가 왜 필수인가?

---

## 학습 정리

- (c) chunk write 평균 시간 = **트랜잭션 lock 보유 시간** = 다른 트랜잭션 wait time
- chunk 500은 step 시간 7~11% 빠르지만 **lock 보유가 ×5** → 동시성 cost가 정당화 안 됨
- chunk size 선택은 **(a) 시간 / (b) heap / (c) lock 보유 / (d) 복구 비용** 4차원 종합
- `.faultTolerant().skip()`은 chunk 롤백 후 **single-item 재처리** → chunk 클수록 복구 비용 ×N
- 정산 도메인에선 **chunk 100**이 균형점 (시간·메모리·동시성·복구)
- chunk size처럼 **자주 안 바뀌는 값**은 yml, **매 실행 다른 값**은 jobParameters
- jobParameters SpEL은 Step 실행 시점에 평가 → **`@StepScope` 필수**(Late Binding)

## 참고

- Spring Batch Reference — Chunk-oriented Processing, Skip & Retry
- 정산 배치 chunk size 1K/10K/100K × 10/100/500 측정 결과 기반
- DB row lock & 트랜잭션 — 격리 수준과 잠금 보유 모델
