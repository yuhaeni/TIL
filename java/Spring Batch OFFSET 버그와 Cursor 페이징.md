# Spring Batch OFFSET 버그와 Cursor 페이징

> 날짜: 2026-04-30

## 내용

### 문제 — OFFSET 페이징 + state-mutating Filter 충돌

`JpaPagingItemReader`로 `WHERE status = 'INCOMPLETED'` 조건을 걸고 Processor에서 `INCOMPLETED → COMPLETED`로 상태 전이하면 **데이터의 절반만 처리되는 누락 버그**가 발생한다.

**현상:**
- 정산 batch 응답: `COMPLETED`
- 그러나 일부 row는 `INCOMPLETED`로 잔존
- chunk size 10 + 100건 → **정확히 50건만** 처리, 11-20 / 31-40 / 51-60 / 71-80 / 91-100번 영구 누락

**왜 발생하는가:**

```
초기            : INCOMPLETED = {1..100}
page 0 (OFFSET 0)  → rows 1~10 처리 → COMPLETED
commit 후       : INCOMPLETED = {11..100}  (90건으로 줄어듦)
page 1 (OFFSET 10) → 줄어든 집합에 OFFSET 10 적용 → rows 21~30 (11~20 누락 ❌)
commit 후       : INCOMPLETED = {11..20, 31..100}
page 2 (OFFSET 20) → rows 41~50 (11~20, 31~40 누락 ❌)
...
```

**발현 조건 (3가지 모두 충족):**
1. 데이터 건수 > chunk_size (다중 페이지 필요)
2. Reader filter가 mutating 컬럼 사용 (`WHERE status = INCOMPLETED`)
3. Processor가 그 컬럼을 변경 (COMPLETED 전이)

> **면접 예상 질문:** OFFSET 페이징 + 상태 변경 Processor 조합에서 누락이 발생하는 메커니즘은? 발현 조건 3가지는?

---

### 본질 — OFFSET 페이징은 시간에 따라 변하는 데이터에 약하다

**OFFSET의 한계:**
- OFFSET은 **현재 결과 집합 기준**의 N번째 — 집합이 줄면 같은 OFFSET이 다른 row를 가리킴
- 컬럼 설계가 잘못된 게 아니라 **OFFSET 메커니즘 자체의 한계**
- "안정 정렬 + 변하지 않는 결과 집합"을 가정한 페이징 모델

**실무 일반화:** 게시판 페이징도 사용자가 새 글 쓰는 동안 OFFSET 잘못 가리킬 수 있음 (커서 기반 페이징이 권장되는 이유).

> **면접 예상 질문:** OFFSET 페이징의 본질적 한계는? 어떤 환경에서 안전하지 않은가?

---

### Fix 옵션 비교 — 3가지

| 항목 | (1) `getPage()=0` override | (2) **Cursor 페이징** | (3) `JpaCursorItemReader` |
|---|---|---|---|
| 동작 원리 | OFFSET 항상 0 (filter 변화에 의존) | `WHERE id > :lastId LIMIT N` | DB cursor streaming |
| 변경 범위 | 1줄 (anonymous subclass) | ~30줄 + 쿼리 수정 | Reader Bean 정의 교체 |
| fetch 비용 | O(N) OFFSET 스캔 | **O(log N)** index seek | DB cursor (driver fetch size) |
| 트랜잭션 | chunk마다 commit | chunk마다 commit | **단일 장기 트랜잭션** |
| restart 지원 | saveState 무의미 | lastId를 ExecutionContext 저장 | 처음부터 재실행 |
| 운영 가시성 | page 카운터 무의미 | lastId 추적 명확 | cursor 위치 추적 X |
| 본질 | Spring Batch 한정 hack | **표준 패턴** | 페이징 회피 패러다임 |

> **면접 예상 질문:** 같은 OFFSET 버그를 푸는 3가지 옵션의 본질적 차이는?

---

### 의사결정 — Production 안전 우선 → Cursor 페이징

**Step 1. 우선순위:** production 안전 > 측정 마무리 속도
- 잘못 배포되면 락/복제/유실 영향이 측정 지연보다 훨씬 큼

**Step 2. 옵션 3 제외:**
- `JpaCursorItemReader` = 단일 장기 트랜잭션
- 운영 중 락 점유 시간 길어짐 + 복제 지연 가능성
- 기존 batch 설계 의도(`transacted=false`, chunk마다 commit)와 어긋남

**Step 3. 옵션 1 vs 2:**
- 옵션 1: 6개월 뒤 동료가 "왜 page=0?" 갸우뚱 → 답이 "filter mutation 의존 trick"이라 숨은 맥락 필요
- 옵션 2: `id > :lastId ORDER BY id` → **SQL 자체로 의도가 읽힘**

→ 결론: **옵션 2 Cursor 페이징** (안전 ✓ / restart ✓ / 가독성 ✓ / 성능 O(log N) ✓)

> **면접 예상 질문:** 여러 fix 옵션 중 production 환경에서 어떤 기준으로 선택하는가?

---

### Cursor 두 종류 — "북마크" vs "DB 스트리밍 통로"

같은 "cursor"라는 단어지만 옵션 2와 3에서 **완전히 다른 개념**.

**도서관 비유:**

| 옵션 2 cursor — 북마크 | 옵션 3 cursor — DB 스트리밍 통로 |
|---|---|
| "지난 마지막 책 다음부터 10권 주세요" | 사서가 카트에 100권 실어놓고 한 권씩 건네줌 |
| 매 chunk마다 새 query, chunk마다 commit | 커넥션이 step 끝까지 유지 |
| `lastId` = application-level 위치 표시 | DB가 server-side cursor를 열어둠 |
| 짧은 트랜잭션 여러 번 | 단일 장기 트랜잭션 |

**실무 핵심:** 단어 `cursor`만 보고 동일시하면 안 됨 — **트랜잭션 모델이 다르다**.

> **면접 예상 질문:** Cursor 페이징(키셋)과 `JpaCursorItemReader`의 cursor는 어떻게 다른가?

---

### 구현 흐름 — Listener 조합과 ExecutionContext

```
[Reader가 item 읽음]
   ↓
ItemReadListener.afterRead(item) → lastId = item.getId() 갱신
   ↓
[chunk 처리 + commit]
   ↓
ChunkListener.afterChunk(context) → ExecutionContext.put("lastId", lastId)
   ↓
[다음 chunk fetch] Reader가 ExecutionContext에서 lastId 꺼내 쿼리 주입
   ↓
WHERE status = 'INCOMPLETED' AND id > :lastId ORDER BY id LIMIT N
```

**핵심 컴포넌트:**

| 컴포넌트 | 역할 | 호출 시점 |
|---|---|---|
| **`ItemReadListener.afterRead`** | item 단위 lastId 갱신 | Reader가 item 읽을 때마다 |
| **`ChunkListener.afterChunk`** | chunk 단위 lastId 영속화 | chunk commit 직후 |
| **`ExecutionContext`** | restart용 Map 저장소 | `BATCH_STEP_EXECUTION_CONTEXT` 테이블 자동 저장 |

**Listener의 묘미 — 흐름의 "어디에 끼어들지"가 핵심:**
- item 단위 갱신 + chunk 단위 영속화 조합으로 **기존 Reader/Writer 코드 변경 없이** cursor 페이징 구현

**lastId 초기값:** ExecutionContext에 없으면 **0** → `id > 0`이 모든 row 매칭(자연수 id 가정)

> **면접 예상 질문:** Spring Batch에서 cursor 페이징을 어떻게 구현하는가? `ItemReadListener`와 `ChunkListener`를 어떻게 조합하는가?

---

### `ExecutionContext` — Spring Batch가 제공하는 restart 인프라

**`ExecutionContext`** = Spring Batch가 `BATCH_STEP_EXECUTION_CONTEXT` 테이블에 자동 저장하는 Map 저장소.

**특징:**
- chunk commit 시점마다 함께 영속화
- restart 시 자동 복구 → 마지막 lastId부터 이어감
- **외부 캐시(Redis 등) 도입 불필요**

**실행 시나리오 — 장애 복구:**
```
chunk 1: id 1~10 처리 → afterChunk: lastId=10 저장
chunk 2: id 11~20 처리 → lastId=20
chunk 3: id 21~30 처리 → lastId=30
   ⚠️ 서버 다운
[재시작]
chunk 4: ExecutionContext에서 lastId=30 복구 → id > 30부터 이어감 ✅
```

**Step vs Job ExecutionContext:**
- `StepExecutionContext` — Step 단위 (다른 Step에 영향 X)
- `JobExecutionContext` — Job 전체 공유 (Step 간 데이터 전달)

> **면접 예상 질문:** `ExecutionContext`는 어떤 역할을 하는가? Redis 없이 restart가 가능한 이유는?

---

### 인덱스 검토 — `(status, id)` 복합 인덱스

cursor 페이징 쿼리:
```sql
WHERE status = 'INCOMPLETED' AND id > :lastId ORDER BY id LIMIT 10
```

**인덱스 선택 — 컬럼 순서가 핵심:**
- `(status, id)` ✅ — equality(`status`) 먼저 + range(`id`) 나중 (B+Tree 키 순서 활용)
- `(id, status)` ❌ — `id > :lastId`가 range라 status 필터링 비효율

**EXPLAIN ANALYZE로 검증할 포인트:**
- `Index Scan using idx_status_id` 사용 여부
- `Rows Removed by Filter`가 0에 가까운지
- 시퀀셜 스캔 회피 확인

> **면접 예상 질문:** cursor 페이징 쿼리에 어떤 인덱스를 어떤 순서로 만드는가? equality vs range 컬럼 배치 원칙은?

---

## 학습 정리

- **OFFSET 페이징 + state-mutating Processor = 누락 버그** — chunk마다 결과 집합이 줄어 OFFSET이 다른 row를 가리킴
- 발현 조건: ① 다중 페이지 ② mutating 컬럼 filter ③ Processor가 그 컬럼 변경
- 본질은 **OFFSET이 변하는 결과 집합에 약하다**는 것 — 컬럼 설계 문제 아님
- 3가지 fix 옵션: ① `getPage()=0` hack ② **cursor 페이징** ③ `JpaCursorItemReader`
- production 안전 우선 → 장기 트랜잭션(③) 제외 → 가독성으로 ②(cursor 페이징) 선택
- 같은 "cursor"여도 **키셋 페이징(북마크) vs DB 서버사이드 커서(스트리밍)** 는 트랜잭션 모델이 다름
- 구현은 **`ItemReadListener.afterRead`(item단위 갱신) + `ChunkListener.afterChunk`(commit 후 영속화)** 조합
- **`ExecutionContext`** 가 restart 인프라 — Redis 등 외부 캐시 불필요
- 인덱스는 **`(status, id)`** 순서 — equality 먼저, range 나중 (B+Tree 키 순서 원칙)

## 참고

- Spring Batch Reference — `JpaPagingItemReader`, `JpaCursorItemReader`, `ExecutionContext`
- Spring Batch Listener — `ItemReadListener`, `ChunkListener`
- "Faster Pagination in Mysql — Why Order By with Limit and Offset is Slow"
- CarrotSettle 정산 batch OFFSET 누락 버그 분석 기반
