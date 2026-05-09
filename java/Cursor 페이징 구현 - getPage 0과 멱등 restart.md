# Cursor 페이징 구현 — `getPage()=0`과 멱등 restart

> 날짜: 2026-05-09

## 내용

### Cursor 페이징 = "책갈피", OFFSET = "처음부터 N개 건너뛰기"

두꺼운 책을 며칠에 걸쳐 나눠 읽는 비유가 두 페이징 방식의 차이를 정확히 보여준다.

| 방식 | 비유 | 동작 |
|---|---|---|
| **cursor** | 책갈피 끼워두기 | 다음 날 책갈피 자리를 펼쳐 거기서부터 (**절대 위치**) |
| **OFFSET** | 책갈피 없이 매번 처음부터 N개 건너뛰기 | "어제 12p 읽었으니 처음부터 12개 넘기고 시작" (**상대 위치**) |

→ cursor = "내가 마지막으로 읽은 **그 자리(id)**"를 기억하는 방식.

> **면접 예상 질문:** Cursor 페이징과 OFFSET 페이징의 본질적 차이는? 절대 위치와 상대 위치가 무슨 뜻인가?

---

### 왜 cursor는 누락이 없는가 — "페이지 찢기" 비유

**filter set** = WHERE 조건에 매치되는 row들의 집합 = 내가 읽는 책의 남은 페이지들.

**시나리오: 누군가 내가 이미 읽은 페이지를 계속 찢어낸다** 😱
(정산 배치가 `INCOMPLETED → COMPLETED`로 바꿔 다음 조회에서 사라지게 만드는 것과 동일)

**OFFSET이 깨지는 이유:**
- 앞 페이지가 찢기면 "맨 처음" 기준 자체가 **매번 달라짐**
- 어제 12p 읽었다 → 처음부터 12개 건너뛴 자리 ≠ 오늘 읽으려던 자리
- → row가 페이지 사이로 누락

**cursor가 안전한 이유:**
- 책갈피(id)는 페이지가 찢겨도 **그 자리 그대로**
- "id > X" — id 자체가 변하지 않으니 **누락 불가능**

> **면접 예상 질문:** filter set이 변하는 환경에서 OFFSET이 깨지는 메커니즘은? cursor가 누락을 어떻게 방지하는가?

---

### `getPage() = 0` override — OFFSET 이중 누적 차단

`JpaPagingItemReader` 기본 동작:
```
page 0 → firstResult = 0  × pageSize = 0
page 1 → firstResult = 1  × pageSize = 10
page 2 → firstResult = 2  × pageSize = 20
```
→ `firstResult = page × pageSize` 공식으로 **OFFSET 자동 누적**.

**cursor와 OFFSET이 동시에 작동하면 무엇이 깨지는가:**
```sql
WHERE id > 10 ORDER BY id LIMIT 10 OFFSET 10
```
"id가 10보다 큰 것들 중에서, **또** 10개 건너뛰고" → 원하는 건 id 11~20인데 실제로는 id 21~30부터 → **이중 누락**.

**해결:** `getPage()=0` 강제 override
- `firstResult = 0 × pageSize = 0`
- OFFSET이 항상 0
- **위치 진행은 lastId 단독 담당**

```java
JpaPagingItemReader<Settlement> reader = new JpaPagingItemReader<>() {
    @Override public int getPage() { return 0; }   // 항상 0
};
reader.setSaveState(false);
```

> **면접 예상 질문:** `JpaPagingItemReader`에서 cursor 페이징을 도입할 때 `getPage()`를 0으로 override 하는 이유는?

---

### `setSaveState(false)` — ExecutionContext에 저장 안 함

**`saveState`** = Spring Batch가 reader 진행 상태(page 번호, lastId 등)를 **`ExecutionContext`** 에 DB로 저장하는 옵션 (기본 `true`).

→ Job이 죽으면 재시작 시 그 값을 읽어 이어 시작 (일반적 restart 패턴).

**`setSaveState(false)`의 의미:**
- 진행 상태를 저장하지 않음
- 재시작 시 **lastId = 0부터 다시 시작**

**"그럼 처음부터 다시 읽으면 이미 처리한 row를 또 처리하는 거 아닌가?"** → **아니다.**

> **면접 예상 질문:** `saveState`는 무엇을 저장하는가? `setSaveState(false)`로 두면 어떤 트레이드오프가 생기는가?

---

### 멱등(idempotent) restart — WHERE 조건이 진행도 추적까지 겸함

`setSaveState(false)`여도 안전한 비밀은 **WHERE 절**에 있다.

```sql
WHERE s.status = :status       -- 'INCOMPLETED'
  AND s.id > :lastId           -- lastId = 0 부터 다시 시작
  ORDER BY s.id
```

**작동 원리:**
- 어제 처리된 1~500번 row의 status는 이미 **`COMPLETED`** ✅
- 재시작 시 lastId=0부터 다시 스캔해도 **`status='INCOMPLETED'` 조건이 처리된 row를 자연 제외**
- 결과: id 501부터 자연스럽게 처리 시작

**이것이 멱등 restart:**
- "몇 번을 재실행해도 결과는 동일하다"
- **WHERE 조건이 작업 진행도를 추적하는 역할까지 겸함**
- 그래서 굳이 `lastId`를 `ExecutionContext`에 저장할 필요 없음

**일반 restart vs 멱등 restart 비교:**

| 구분 | 일반 restart (saveState=true) | 멱등 restart (saveState=false) |
|---|---|---|
| 진행 상태 저장 | `BATCH_STEP_EXECUTION_CONTEXT`에 저장 | 저장 X |
| 재시작 위치 | 저장된 lastId부터 | lastId=0부터 (WHERE가 자연 필터) |
| 의존성 | DB 메타데이터 신뢰성 | **도메인 컬럼(status) 신뢰성** |
| 단순성 | 약간 복잡 | **매우 단순** |

> **면접 예상 질문:** 멱등 restart란 무엇인가? `ExecutionContext` 없이도 안전한 재시작이 가능한 조건은?

---

### 비유로 정리 — "이름표"와 "줄 번호"

| OFFSET 방식 | cursor 방식 |
|---|---|
| 줄에 사람이 빠지면 **번호가 밀림** | **이름표(id) 기준**이라 사람이 빠져도 번호 안 밀림 |
| filter set 변동에 취약 | filter set 변동에 무관 |

**4줄 요약:**

| 질문 | 핵심 한 줄 |
|---|---|
| cursor가 뭐야? | 책갈피 — 마지막으로 읽은 **절대 위치(id)** 를 기억 |
| filter set? | WHERE 조건에 매치되는 **row들의 집합** (매 chunk마다 줄어듦) |
| `getPage()=0` 왜? | `firstResult = page × pageSize` → page=0이면 OFFSET=0 → cursor 위에 OFFSET 이중 누적 차단 |
| `setSaveState(false)`? | `WHERE status=INCOMPLETED`가 처리된 row를 자동 필터링 → 재시작해도 이미 COMPLETED는 자연 제외 |

> **면접 예상 질문:** OFFSET vs cursor 페이징을 한 문장 비유로 설명해보라.

---

## 학습 정리

- **Cursor 페이징** = "책갈피"(절대 위치) — id로 다음 시작점을 찍는 방식, **OFFSET**은 "처음부터 N개 건너뛰기"(상대 위치)
- filter set이 매 chunk마다 줄어드는 환경(state-mutating Processor)에서 **OFFSET은 누락**, **cursor는 안전**
- `JpaPagingItemReader`의 `firstResult = page × pageSize` 자동 누적 → cursor와 함께 쓰면 **이중 OFFSET 누락** 발생 → `getPage()=0` override로 차단
- `setSaveState(false)` = `ExecutionContext`에 진행 상태 저장 X → 재시작 시 lastId=0
- **멱등 restart** = `WHERE status='INCOMPLETED'`가 진행도 추적까지 겸하기 때문에 lastId=0부터 다시 시작해도 이미 COMPLETED는 자연 제외
- 도메인 컬럼이 신뢰 가능하면 **메타데이터 의존을 줄여 단순화** 가능

## 참고

- Spring Batch Reference — `JpaPagingItemReader`, `ExecutionContext`, `saveState`
- "키셋(Keyset/Cursor) 페이지네이션" 패턴
- CarrotSettle 정산 배치 cursor 페이징 도입 트러블슈팅 일지 기반
