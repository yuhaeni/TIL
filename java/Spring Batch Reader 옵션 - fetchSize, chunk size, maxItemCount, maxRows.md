# Spring Batch Reader 옵션 — fetchSize, chunk size, maxItemCount, maxRows

> 날짜: 2026-05-29

## 내용

`JdbcCursorItemReader` 빌더를 보면 비슷해 보이는 옵션이 여러 개 있다.

```kotlin
JdbcCursorItemReaderBuilder<DiaryReminderResult>()
    .fetchSize(10)            // ← 이거랑
    .maxItemCount(...)        // ← 이거랑
    .maxRows(...)             // ← 이거 뭐가 다르지?
    .build()
```

거기에 Step에서 따로 잡는 `chunk size` 까지 더하면 — 다 *"몇 개씩"* 처럼 들려서 헷갈리기 쉽다. 핵심은 **각 옵션이 *어느 레이어*에서 *무엇을* 결정하는가**.

---

### fetchSize — JDBC 네트워크 왕복(roundtrip) 단위

`fetchSize` 는 **JDBC 드라이버 레이어**의 옵션이다. *"한 번의 네트워크 왕복에 몇 행씩 실어 올지"* 를 결정한다.

```
총 1만 행을 처리할 때 fetchSize=10 이라면?
→ 어플리케이션 ↔ DB 네트워크 왕복: 1000번
→ 한 번 왕복마다 10행씩 받음
```

**핵심: 총량 제한이 아니다.** `fetchSize(10)` 이어도 1만 행이면 1만 행 다 읽고 끝난다. 단지 *받아오는 단위*만 작아질 뿐.

**튜닝 관점:**
- fetchSize↑ → 네트워크 왕복↓ but 한 번에 받는 메모리↑
- fetchSize↓ → 메모리 효율적이지만 왕복 횟수↑ (오버헤드)

**자주 보이는 권장:** *`fetchSize` 와 `chunk size` 를 같게* 맞춘다.
- fetchSize > chunk size: 한 chunk 처리 전 *over-fetch* → 메모리 낭비
- fetchSize < chunk size: 한 chunk 채우려고 *여러 번 왕복* → 비효율
- 같으면: 1 roundtrip → 1 chunk → 1 commit 이 깔끔하게 정렬

> **면접 예상 질문:** `fetchSize` 는 총 처리량에 영향을 주는가? `fetchSize` 와 `chunk size` 를 같게 맞추는 이유는?

---

### chunk size — Spring Batch 트랜잭션 commit 단위

`chunk size` 는 **Spring Batch 레이어**의 옵션이다. *"몇 개마다 트랜잭션을 commit 할지"* 를 결정한다.

```
chunk size = 100 일 때:
  read 1 → ... → read 100 → process 100 → write 100 → COMMIT
                                                       ↓
  read 101 → ... → read 200 → process 200 → write 200 → COMMIT
                                                          ↓
  ...
```

**자주 하는 오해 — "chunk size로 총량도 제어되는 거 아닌가?"**

❌ 아니다. chunk size는 *흐름의 단위*(commit 주기)이지 *총 한도* 가 아니다. 1만 명 데이터에 chunk size = 100 이어도 → 100개씩 100번 반복하다 1만 명 다 처리하고 끝.

> **면접 예상 질문:** chunk size는 무엇을 끊는 단위인가? chunk size만으로 "총 100건만 처리" 가 가능한가?

---

### maxItemCount — Spring Batch 총 한도 (restart 호환)

`maxItemCount(N)` = Spring Batch가 *자기 카운터*로 *총 N개 읽고 Reader를 종료* 시키는 옵션.

```
maxItemCount(100), 데이터 1만 행:
  read 1 → 2 → 3 → ... → 100 → [Reader 종료]
  → 나머지 9900은 아예 안 읽음
```

**왜 "Item" 인가?** Spring Batch 도메인 용어. Reader의 `read()` 호출 한 번이 1 Item.

**핵심 강점 — restart 호환성:**
- Spring Batch가 `currentItemCount` 를 *step execution context에 저장*
- 50번째 Item 처리 중 배치가 죽고 restart → "51번째부터 다시" 가 가능
- Reader 종류 무관 (JDBC/JPA/File/Kafka 모두 지원)

**use case:**
- 테스트/디버깅 — "운영 DB 1만 명을 갑자기 다 돌리기 무서우니 100명만"
- 비즈니스 요구 — "상위 N건만 처리"
- 안전장치 — 폭주 방지 cap

> **면접 예상 질문:** `maxItemCount` 가 `maxRows` 와 달리 *restart에 안전*한 이유는?

---

### maxRows — JDBC ResultSet 총 한도 (DB 차원 효율)

`maxRows(N)` = JDBC `Statement.setMaxRows(N)` 호출. *DB 드라이버 레이어*에서 ResultSet이 최대 N행만 반환하도록 cap.

```
maxRows(100), 데이터 1만 행:
  DB → "100행까지만 반환" (JDBC 차원)
  → 네트워크로 100행만 흐름 → 효율적
```

**`maxRows` vs `maxItemCount` — 어디서 자르느냐의 차이:**

| 비교 | `maxRows` | `maxItemCount` |
|---|---|---|
| 레이어 | JDBC 드라이버 | Spring Batch |
| 자르는 위치 | DB ResultSet | Reader 카운터 |
| 네트워크 트래픽 | 적음 (DB가 미리 자름) | 많음 (받고 나서 cap) |
| restart 호환 | ❌ (Spring Batch는 cap을 모름) | ✅ (currentItemCount 저장) |
| Reader 종류 | JDBC 전용 | 모든 Reader |

**그럼 왜 둘 다 존재할까?** 트레이드오프가 달라서.
- 일회성·테스트·sanity cap → `maxRows` 도 OK
- 운영·restart 가능성 있는 배치 → `maxItemCount`

**실무 권장:** 보통 `maxItemCount` 가 무난. restart 안 다칠 보장 + Reader 종류 무관.

> **면접 예상 질문:** `maxRows` 가 더 효율적인데도 Spring Batch가 `maxItemCount` 를 권장하는 이유는?

---

### 네 옵션을 한 표로 — "*몇 개씩*" vs "*몇 개까지*"

| 옵션 | 의미 | 레이어 | 역할 축 |
|---|---|---|---|
| `fetchSize` | 한 번에 *N행 네트워크 전송* | JDBC 드라이버 | **흐름/주기** (총량 X) |
| `chunk size` | *N개마다 트랜잭션 commit* | Spring Batch | **흐름/주기** (총량 X) |
| `maxItemCount` | *총 N Item* 읽고 종료 | Spring Batch | **총 한도** (restart ✅) |
| `maxRows` | ResultSet *총 N행*만 받음 | JDBC 드라이버 | **총 한도** (DB 차원 효율) |

**헷갈림의 정체:** 네 옵션 모두 "*몇 개*" 라는 단어가 들어가서 같은 축으로 보이지만, 실제로는 **흐름의 단위(주기)** 와 **총 한도(cap)** 라는 *서로 다른 축* 에 놓인다.

> **면접 예상 질문:** Spring Batch Reader의 fetchSize / chunk size / maxItemCount / maxRows 네 옵션의 *축*과 *레이어*를 비교 설명하라.

---

## 학습 정리

- **`fetchSize`** 는 *한 번의 네트워크 왕복에 몇 행* — JDBC 드라이버의 성능 튜닝 옵션. 총량을 제한하지 않는다.
- **`chunk size`** 는 *몇 개마다 트랜잭션 commit* — Spring Batch의 흐름 단위. 역시 총량을 제한하지 않는다. *권장: fetchSize 와 같게* 맞춰 over/under-fetch 제거.
- **`maxItemCount`** 는 *총 N Item 후 Reader 종료* — Spring Batch가 카운터 관리 → restart 호환 ✅ Reader 종류 무관.
- **`maxRows`** 는 *ResultSet에 최대 N행* — JDBC 드라이버 차원 cap. DB가 미리 잘라줘서 효율적이지만 Spring Batch는 그 사실을 모름 → restart 미호환.
- 헷갈림의 본질: 네 옵션 모두 "몇 개"가 들어가지만 **흐름의 단위(주기)** vs **총 한도(cap)** 두 축으로 갈라진다. 실무에선 일반적으로 `maxItemCount` 권장.
