# Spring Batch chunk size 성능 트레이드오프 — commit overhead, WAL fsync, lock 보유

> 날짜: 2026-05-10

## 내용

### chunk size — 3차원 트레이드오프의 시작

Spring Batch 의 `chunk(N)` 은 **N 건마다 한 번 트랜잭션 commit** 한다는 뜻. 같은 1,000건을 처리해도 chunk 크기에 따라 commit 횟수가 달라진다.

| chunk size | commit 횟수 (1,000건 기준) | 한 번에 잡는 row |
|---|---|---|
| 10 | 100회 | 10개 |
| 100 | 10회 | 100개 |
| 500 | 2회 | 500개 |

직관적으로 "commit 횟수 줄이면 빠르겠네!" 라고 생각하기 쉽지만, **chunk 가 커질수록 다른 비용이 따라 올라온다**. 실측 결과 chunk size 는 다음 3개 차원의 트레이드오프를 만든다:

| 차원 | chunk ↓ (작게) | chunk ↑ (크게) |
|---|---|---|
| **(a) 시간** | commit overhead 누적 → **느려짐** | commit 횟수 적음 → 빠름 |
| **(b) heap** | 한 번에 적은 entity 보유 → 낮음 | 영속성 컨텍스트에 많이 누적 → **높음** |
| **(c) lock 보유** | 짧음 | **길어짐** → 동시성 저하 |

이 트레이드오프 때문에 chunk size 는 무조건 작거나 무조건 큰 게 답이 아니라 **3차원 균형점** 을 찾아야 한다. CarrotSettle 정산 배치 실측에서 chunk 100 이 모든 데이터 규모(1K/10K/100K) 에서 robust 한 sweet spot 으로 확인됐다.

> **면접 예상 질문:** Spring Batch 에서 chunk size 가 성능에 영향을 주는 이유를 3가지 차원으로 설명해보라.

---

### commit overhead — 건수에 비례하지 않는 고정 비용

**commit overhead = DB commit 한 번을 처리할 때마다 *무조건* 드는 고정 비용**. 처리 건수에 거의 비례하지 않는다는 게 핵심.

CarrotSettle 실측 (PostgreSQL 16):

| 데이터 | chunk 10 commit 횟수 | per-commit 시간 (c) |
|---|---|---|
| 1K | 100회 | 18ms |
| 10K | 1,000회 | 17ms |
| 100K | 10,000회 | 19ms |

→ 데이터량과 무관하게 **per-commit 17~19ms 고정**. 환경 결정 상수.

이 17ms 안에 들어있는 비용을 분해하면:

```
commit 1회 = JPA flush + JDBC commit + WAL fsync
            ───────────  ───────────  ────────────
            메모리/네트워크   네트워크    디스크 I/O (가장 비쌈)
```

**왜 chunk 10 이 30~40% 느린가?** → 1건당 처리는 빠르지만, *총 commit 횟수* 가 100회 (chunk 100 의 10배) 라 17ms × 100 = 1,700ms 가 commit overhead 만으로 누적된다. **fsync 가 100번 일어나는 게 본질적 cost**.

> **면접 예상 질문:** "commit overhead" 가 정확히 무엇이며, 왜 처리 건수가 아니라 commit 횟수에 비례하는가?

---

### commit 3단계 분해 — JPA flush vs JDBC commit vs WAL fsync

세 단어가 비슷해 보이지만 **각자 하는 일과 비용 위치가 다르다**.

| 단계 | 하는 일 | 비용 |
|---|---|---|
| **JPA flush** | 영속성 컨텍스트의 dirty entity → UPDATE/INSERT SQL 변환 + DB 전송 | 메모리 작업 + 네트워크 |
| **JDBC commit** | DB 에 "이 트랜잭션 확정!" 신호 전송 | 네트워크 |
| **WAL fsync** | OS page cache 의 WAL 데이터 → 디스크 platter 강제 쓰기 | **디스크 I/O (가장 비쌈)** |

**flush 방향 주의** — 헷갈리기 쉬운 포인트:
- **fetch** = DB → 메모리 (가져오기)
- **flush** = 메모리 → DB (보내기) ← 화장실 변기 flush 의 어감 ("모아둔 걸 한꺼번에 내보낸다")

flush 는 영속성 컨텍스트에 모아둔 변경사항을 **SQL 로 만들어 DB 로 보내는 것** 이지, DB 에서 가져오는 게 아니다.

**flush ≠ commit:**
- flush 후에도 트랜잭션은 아직 안 끝남 → 롤백 가능
- commit 이 일어나야 비로소 트랜잭션 확정

> **면접 예상 질문:** JPA flush, JDBC commit, WAL fsync 가 각각 무엇을 하는지 설명하고, 셋 중 가장 비싼 비용이 어디에 있는지 답해보라.

---

### WAL fsync — 왜 단순 commit 으로 끝나지 않는가

**핵심 질문:** DB 가 애플리케이션에 "commit 됐어요!" 라고 응답할 때, 데이터가 *진짜로* 디스크 platter 에 새겨졌을까?

→ 아니다. **OS 메모리(page cache)** 에 잠깐 머물러 있다. 그래서 추가로 `fsync` 시스템 콜이 필요하다.

**page cache vs 디스크 platter 비유:**

| 공간 | 비유 | 속도 | 영속성 |
|---|---|---|---|
| **OS page cache (RAM)** | 책상 위 메모지 📝 | 빠름 | **전원 꺼지면 날아감** 💨 |
| **디스크 platter (SSD/HDD)** | 책장의 책 📚 | 느림 (RAM 보다 ~1000배) | **전원 꺼져도 영원** |

OS 는 효율을 위해 일단 메모지(page cache) 에 써두고 *나중에* 책(디스크) 에 옮겨 적는다. 만약 DB 가 commit 응답 직후 정전이 일어났는데 데이터가 page cache 에만 있었다면? → **실제 디스크에 반영 안 된 상태로 영원히 사라짐**. 이러면 ACID 의 D(durability) 가 깨진다.

**fsync = OS 에게 "메모지 내용 진짜 책에 옮겨 적을 때까지 기다려!" 강제하는 시스템 콜.** PostgreSQL 은 commit 응답을 보내기 *전에* WAL 파일에 대해 반드시 fsync 를 호출해 영속성을 보장한다.

→ **commit overhead 17ms 의 대부분이 이 fsync** 다. 디스크 platter 가 RAM 보다 1000배 느리니까.

> **면접 예상 질문:** PostgreSQL 이 commit 응답을 보내기 전에 fsync 를 강제하는 이유는? page cache 와 disk platter 의 차이로 설명해보라.

---

### lock 보유 시간 — chunk 가 커질 때의 동시성 cost

chunk 가 커지면 commit 횟수는 줄지만, **한 번의 commit 이 처리하는 row 수가 늘어난다**. 트랜잭션이 열려있는 동안 그 row 들에 대해 **row-level lock** 을 보유한다.

CarrotSettle 실측 — (c) chunk write 시간 = 사실상 **단일 트랜잭션 lock 보유 시간**:

| 데이터 | chunk 100 (c) | chunk 500 (c) | 배수 |
|---|---|---|---|
| 1K | 141ms | 687ms | **×4.9** |
| 10K | 130ms | 578ms | **×4.5** |
| 100K | 135ms | 631ms | **×4.7** |

→ chunk 500 은 한 번에 lock 을 약 5배 더 오래 잡는다. 다중 사용자 환경에서 같은 row 에 접근하려는 다른 트랜잭션의 wait time 이 비례 증가.

**chunk 500 의 절대 시간 우세를 정당화 못 하는 이유:**
- (a) 시간: chunk 100 대비 3~11% 빠름 → 절대 이득은 작음
- (c) lock 보유 ×4.7 → **단일 사용자 측정엔 안 보이지만 운영 환경 동시성 cost** 가 큼
- (b) heap +8~15% (1K 제외) → 메모리도 더 씀
- chunk 도중 예외 시 500건 전체 롤백 → skip/재처리 비용 ×5
- WAL fsync 단일 commit 크기 ×5 → DB 부하 비대칭

> **면접 예상 질문:** chunk size 를 무한정 키우면 commit overhead 가 줄어들텐데, 왜 그러지 않는가? lock 보유 시간 관점에서 설명해보라.

---

### 결론 — chunk 100 sweet spot 채택 근거 (면접 답변 포맷)

3개 차원 종합:

| 차원 | chunk 10 | chunk 100 | chunk 500 |
|---|---|---|---|
| (a) 시간 | 30~40% 느림 | baseline | 3~11% 빠름 |
| (b) heap | 안정화 후 +20% | 가장 안정 | +8~15% |
| (c) lock 보유 | 17~19ms (×0.13) | 130~141ms | **578~687ms (×4.7)** |

**핵심 결론:**
- chunk 10 은 commit overhead (fsync × 만회) 로 30%+ 손실 — 100K = 191초 vs chunk 100 의 135초 (+56초)
- chunk 500 의 시간 절약 (3~11%) 은 lock 보유 ×5 cost 를 정당화 못 함 → 운영 환경 동시성 안정성 우선
- **chunk 100 이 시간/메모리/동시성 3차원에서 가장 robust** — 1K~100K 어느 규모에서도 acceptable

**면접 답변 예시:**
> "정산 배치 chunk size 를 1K, 10K, 100K × chunk 10/100/500 조합으로 9가지 케이스를 실측했습니다. chunk 10 은 fsync 가 commit 횟수만큼 누적돼 30~40% 느렸고, chunk 500 은 절대 시간은 3~11% 빨랐지만 단일 트랜잭션 lock 보유 시간이 ×4.7 로 길어져 다중 사용자 동시성 cost 가 컸습니다. chunk 100 이 시간/메모리/lock 보유 3차원 모두에서 균형점이라 production default 로 채택했습니다."

> **면접 예상 질문:** chunk size 를 100 으로 결정한 근거를 실측 수치로 설명해보라. chunk 100 의 단점은 없는가?

---

## 학습 정리

- **chunk size 는 3차원 트레이드오프** — (a) 시간 / (b) heap / (c) lock 보유. 무조건 작거나 큰 게 답이 아님
- **commit overhead** = 처리 건수가 아닌 **commit 횟수에 비례** 하는 고정 비용 (CarrotSettle 환경 17~19ms/commit)
- **commit 1회 = JPA flush + JDBC commit + WAL fsync** — 셋 중 fsync 가 가장 비쌈 (디스크 I/O)
- **flush 방향 주의** — fetch(DB→메모리) 와 반대. flush 는 **메모리→DB** 로 dirty entity 를 SQL 로 보내는 동작
- **WAL fsync 가 비싼 이유** — OS page cache(RAM, 휘발) → 디스크 platter(영속) 강제 쓰기. RAM 보다 ~1000배 느림. ACID 의 D 보장 cost
- **chunk 가 커지면 lock 보유 시간이 비례 증가** — chunk 500 은 chunk 100 대비 ×4.7 lock 보유 → 운영 환경 동시성 cost
- **chunk 100 이 sweet spot** — 시간 절약(chunk 500) 도 메모리 절약(chunk 10) 도 극단으로 가지 않고 3차원 균형

## 참고

- CarrotSettle `docs/load-test/chunk-size-benchmark.md` — 1K/10K/100K × chunk 10/100/500 9 케이스 실측 데이터
- PostgreSQL 16 documentation — Write-Ahead Logging (WAL), `fsync` parameter
- Spring Batch Reference — chunk-oriented processing
- JPA Specification — flush modes, persistence context
