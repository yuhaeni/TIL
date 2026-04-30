# Spring Batch 성능 측정 — PromQL과 Grafana

> 날짜: 2026-04-30

## 내용

### Cumulative Counter — 누적 우상향 메트릭

Prometheus의 카운터형 메트릭은 **단조 증가(monotonically increasing)** 한다. 시간이 흘러도 값이 줄지 않고 **계속 우상향**.

| 종류 | 특징 | 예시 |
|---|---|---|
| **Counter** | 누적, 줄지 않음 | `_sum`, `_count`, `http_requests_total` |
| **Gauge** | 현재값, 오르락내리락 | `jvm_memory_used_bytes` |
| **Histogram** | 분포 + 누적 카운터 | 응답시간 버킷별 카운트 |

**의미:** "지금까지 step이 총 얼마나 시간을 썼는가" / "총 몇 번 끝났는가" 같은 **누적량**을 표현. 변화율을 보려면 `rate()` / `increase()`를 씌운다.

> **면접 예상 질문:** Prometheus의 Counter와 Gauge의 차이는? 카운터에서 변화율을 보려면 어떻게 하는가?

---

### `_sum / _count` — 한 번당 평균 추출 만능 공식

```promql
spring_batch_step_seconds_sum / spring_batch_step_seconds_count
```

**식당 비유:**
- 오늘 총 조리 시간 = 600분 (`_sum`)
- 총 만든 음식 수 = 20개 (`_count`)
- → 음식 하나당 평균 = 30분

**용어 정정 (흔한 오해):**
- ❌ `_seconds_sum` = "초당 합계"
- ✅ `_seconds_sum` = "합계인데 **단위가 초(seconds)**"

| 메트릭 | 의미 |
|---|---|
| `_seconds_sum` | 누적된 총 **시간** (단위: 초) |
| `_count` | 누적된 총 **실행/관측 횟수** |

**왜 만능 공식인가?**
- step (count=1)이든 chunk write (count=100)든 **같은 공식**으로 평균 추출
- 측정 횟수에 무관하게 일관된 PromQL → 대시보드 쿼리 통일

> **면접 예상 질문:** Prometheus에서 `_sum / _count`가 평균을 의미하는 이유는?

---

### Spring Batch 카운트 단위 — Step은 1번, Chunk Write는 N번

```java
@Bean
public Step settlementStep(...) {
  return new StepBuilder(STEP_NAME, jobRepository)
      .<Settlement, Settlement>chunk(chunkSize)
      .reader(...).processor(...).writer(...)
      .build();
}
```

**Q: 한 Job 실행에서 step은 몇 번 카운트되는가?**
**A: 1번.** chunk 단위로 여러 번 도는 건 **step *내부*의 reader/processor/writer 반복**이지, step 자체가 여러 번 도는 게 아님.

| 메트릭 | 한 Job당 count 증가량 |
|---|---|
| `spring_batch_step_seconds_count` | **1** (step 종료 시 1↑) |
| `spring_batch_chunk_write_seconds_count` | 데이터량 / chunk size (예: 1000/10 = **100**) |

**식당 비유:** "오늘 영업 1번"이지만 그 안에서 음식은 여러 개 만드는 것.

→ step `_sum / _count`는 결국 `_sum`과 동일값(count=1), chunk write는 **100번 평균**이 의미를 가짐.

> **면접 예상 질문:** Spring Batch에서 step과 chunk write의 카운트 증가 단위는 어떻게 다른가?

---

### `sum()` 함수 — JVM Heap 3개 Pool 합산

```promql
sum(jvm_memory_used_bytes{area="heap"})
```

JVM Heap은 **여러 pool**로 분리되어 있어 Prometheus가 **여러 시계열**을 따로 반환한다.

```
{id="G1 Eden Space",     area="heap"} → 30 MB
{id="G1 Survivor Space", area="heap"} → 5 MB
{id="G1 Old Gen",        area="heap"} → 100 MB
```

**`sum()` 없이 Reducer "Max"를 걸면** → 가장 큰 단일 pool(보통 Old Gen)만 잡혀 **chunk size 차이가 안 보인다**.

| pool | chunk size 변화 민감도 |
|---|---|
| Eden | ✅ 매우 민감 (단기 객체 할당지) |
| Survivor | ✅ minor GC 후 이주 객체 |
| Old Gen | ❌ 거의 무관 (장기 생존 객체) |

**chunk 처리는 영속성 컨텍스트가 Eden에 단기 할당** → Eden+Survivor 합쳐야 진짜 chunk 부하가 보임. Old Gen만 보면 "chunk 10이나 500이나 똑같네?" 하는 헛다리.

> **면접 예상 질문:** PromQL에서 `sum()`을 씌우는 이유는? JVM heap을 측정할 때 단일 pool만 보면 안 되는 이유는?

---

### Eden + Survivor — Minor GC 이주 패턴

**Eden만 보면 안 되는 이유:**

```
chunk 처리 중 Eden 꽉 참 (450 MB)
  ↓ minor GC 발동
Eden 객체 중 살아있는 애들 → Survivor로 이동
  ↓
Eden    : 450 → 50 MB ⬇️
Survivor: 5   → 200 MB ⬆️
```

Eden 그래프만 보면 "메모리 떨어졌네 chunk 가벼운가봐~" 라고 오해할 수 있지만, **객체는 사라진 게 아니라 Survivor로 이사 간 것**. 진짜 chunk가 잡고 있는 메모리는 **Eden + Survivor 합산**.

> **면접 예상 질문:** Minor GC 발생 시 Eden과 Survivor 사용량은 어떻게 변하는가? Eden 단독 측정의 위험은?

---

### 톱니파(Saw-Tooth) — chunk size 비교의 진짜 신호

GC가 한 사이클이라도 일어나야 **톱니파**가 그려지고, **주기/진폭**으로 chunk size 차이가 드러난다.

**A) 배치가 길어 GC 여러 번 발동 (예: 10K건):**
```
Eden 사용량
 ↑     ╱╲    ╱╲    ╱╲    ← 톱니파!
 │    ╱  ╲  ╱  ╲  ╱  ╲
 └────────────────────→ 시간
```
→ chunk 10 vs 500 비교 시 **톱니 주기/진폭이 확연**

**B) 배치가 너무 짧아 GC 한 번도 안 일어남 (예: 1K건, 660ms):**
```
Eden 사용량
 ↑   ╱─────  ← 살짝 올라가다 끝
 │  ╱
 └────────→ 시간
```
→ chunk size 차이가 JVM 베이스라인 노이즈에 묻힘 → **비교 무의미**

**측정 데이터 크기 가이드:**
| 데이터량 | 비교 가능 메트릭 |
|---|---|
| 1K (짧음) | (a) step 시간, (c) chunk write 시간 위주 |
| 10K+ (충분히 김) | (a) (c) + **(b) heap 비교 본격** |

> **면접 예상 질문:** chunk size 비교 측정 시 데이터량을 충분히 키워야 하는 이유는? 톱니파가 신호인 이유는?

---

### 메트릭별 함정 정리

| 메트릭 | 핵심 패턴 | 핵심 함정 |
|---|---|---|
| **(a) step 시간** | `_sum / _count` | step은 1번 실행이라 `_sum`과 동일값 |
| **(b) heap peak** | `sum()`으로 3 pool 합산 | GC 한 번도 안 터지면 비교 무의미 (1K 데이터 주의) |
| **(c) chunk write** | `_sum / _count` | 100번 실행되니 **평균 추출이 핵심** |

**측정 설계 체크리스트:**
- [ ] cumulative counter는 `rate()`/`increase()`로 변화율 보기
- [ ] 평균은 `_sum / _count` 공식 통일
- [ ] heap은 항상 `sum(... area="heap")`
- [ ] chunk size 비교는 GC가 여러 번 일어날 만큼 데이터량 충분히 확보
- [ ] scrape interval(15s 기본)보다 짧은 배치는 샘플 부족 주의

> **면접 예상 질문:** Spring Batch 성능 비교 측정 시 PromQL/Grafana 대시보드를 어떻게 설계하는가?

---

## 학습 정리

- Prometheus **Counter는 누적 우상향** (`_sum`, `_count`), Gauge는 현재값 (`heap_used`)
- **`_sum / _count` = 한 번당 평균** — 측정 횟수 무관하게 동작하는 만능 공식
- `_seconds_sum`은 "초당 합계"가 아니라 "**합계, 단위는 초**"
- Spring Batch에서 **step은 Job당 count=1**, chunk write는 (데이터량/chunk size)만큼 증가
- JVM Heap은 **Eden / Survivor / Old Gen** 분리 → PromQL `sum()`으로 합산 필요
- chunk 부하는 **Eden + Survivor**에 나타남 — Old Gen만 보면 chunk size 차이 안 보임
- Minor GC 시 Eden→Survivor **이주**하므로 Eden 단독 관측은 오해 유발
- 데이터량이 작아 **GC 1사이클이 안 돌면 heap 비교 무의미** — 1K는 시간 위주, 10K+에서 heap 본격 비교
- Grafana Reducer "Max"는 단일 시계열만 잡으므로 다중 pool 합산엔 부적합

## 참고

- Prometheus Documentation — Metric types (Counter, Gauge, Histogram)
- Micrometer — Spring Batch metrics (`spring_batch_step_seconds`, `spring_batch_chunk_write_seconds`)
- Grafana — Stat panel Reducer 옵션
- HotSpot JVM G1GC — Eden/Survivor/Old Generation 동작
- 정산 배치 chunk size 비교 측정 가이드 작성 기반
