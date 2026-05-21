# 카디널리티와 복합 인덱스 — pg_stats, n_distinct, ANALYZE

> 날짜: 2026-05-21

## 내용

### 카디널리티(Cardinality) — 컬럼 값의 다양성

**카디널리티**는 한 컬럼에 적재된 값들이 **얼마나 다양한지**(고유 값의 개수)를 나타낸다.

- **카디널리티 높음**: 주민등록번호, PK, 이메일 → 거의 모든 행이 서로 다른 값
- **카디널리티 낮음**: 성별, 국가, 상태값(enum) → 같은 값이 반복

인덱스 효율과 직결되는 이유:

| 검색 조건 | 결과 행 수 | 인덱스 효과 |
|---|---|---|
| `WHERE 성별 = '여'` (카디널리티 낮음) | 100만 중 50만 건 | 거의 풀스캔과 다름없음 |
| `WHERE 주민번호 = 'xxx'` (카디널리티 높음) | 100만 중 1건 | 인덱스 한 번 타고 끝 |

도서관 비유: "표지가 파란 책 주세요" → 50만 권 꺼내서 다시 골라야 함 / "제목이 '해리포터' 책 주세요" → 1권 바로 찾음.

> **면접 예상 질문:** 카디널리티가 낮은 컬럼에 인덱스를 거는 게 비효율적인 이유를 설명해주세요.

---

### 복합 인덱스 순서 — "user_id니까 카디널리티 높겠지"의 함정

다음 두 인덱스를 비교 실험한 결과 **`(date, user_id)` 순서가 더 빨랐다**:

```sql
-- 1번 (더 빠름)
CREATE INDEX idx_date_user_id ON diary (date, user_id);

-- 2번
CREATE INDEX idx_user_id_date ON diary (user_id, date);
```

직관적으로는 `user_id`가 카디널리티가 높아 보이지만, **실제 테이블 분포**에서는 그렇지 않을 수 있다.

```sql
SELECT COUNT(DISTINCT user_id), COUNT(DISTINCT date) FROM diary;
-- user_id: 100
-- date:    365
```

이 다이어리 테이블에서는 **date의 카디널리티(365)가 user_id(100)보다 높았다**. 그래서 카디널리티가 높은 컬럼을 앞에 둔 `(date, user_id)`가 더 빨랐던 것.

핵심 교훈: **카디널리티는 "일반적 직관"이 아니라 "실제 데이터 분포"로 판단해야 한다.** 같은 컬럼명도 테이블마다 카디널리티가 다르다 (개인 일기 앱 vs 대규모 SNS의 user_id).

WHERE 절이 둘 다 등호(`=`) 조건일 때의 일반 규칙: **카디널리티 높은 컬럼이 앞쪽**.

> **면접 예상 질문:** 복합 인덱스 `(A, B)`와 `(B, A)` 중 어떤 걸 선택할지 어떤 기준으로 판단하나요?

---

### pg_stats — PostgreSQL 통계 시스템 카탈로그 뷰

`pg_stats`는 **테이블이 아닌 뷰(view)** 다. PostgreSQL이 `ANALYZE`로 수집한 통계를 노출하는 시스템 카탈로그.

```sql
SELECT * FROM pg_stats WHERE tablename = 'diary';
```

주요 컬럼:

| 컬럼 | 의미 |
|---|---|
| `tablename` | 테이블 이름 |
| `attname` | 컬럼 이름 |
| `n_distinct` | 고유 값 추정치 (양수/음수 의미 다름) |
| `null_frac` | NULL 비율 |
| `most_common_vals` | 가장 자주 등장하는 값들 (MCV) |
| `most_common_freqs` | MCV의 빈도 |

`COUNT(DISTINCT column)`을 실제로 돌리지 않고도 카디널리티를 추정할 수 있게 해주는 장치.

> **면접 예상 질문:** pg_stats는 어디서 데이터를 가져오나요? 일반 사용자 테이블과 무엇이 다른가요?

---

### n_distinct — 양수와 음수의 의미가 다르다

`n_distinct`는 **부호에 따라 단위가 다르다**:

- **양수**: 컬럼의 **고유 값 개수 그 자체** (예: `365` → 365개 고유 값)
- **음수**: -1 ~ 0 사이의 **비율** (전체 행 수 대비)
  - `-1`   → 100% 모든 행이 고유 (PK/Unique 후보)
  - `-0.5` → 50%가 고유
  - `-0.01` → 1%가 고유

**왜 부호로 나눠 저장하는가?**

| 컬럼 유형 | 행 수 증가 시 | 저장 방식 |
|---|---|---|
| 성별, 국가, 상태값 | 고유 값 수 **불변** | 양수 (절대 개수) |
| user_id, order_id | 행 수에 **비례 증가** | 음수 (비율) |

비례 증가하는 컬럼을 절대 개수로 저장해두면 테이블이 커질 때마다 통계가 stale해진다. **비율로 저장하면 row_count만 곱해도 항상 최신 추정치**가 나온다.

**비교 시 단위 통일 필요** — 절댓값만 비교하면 틀린다:

```
n_distinct = 200  → 그대로 200개
n_distinct = -1   → 36,500 × 1.0 = 36,500개 (이게 더 높음!)
```

| 컬럼 | n_distinct | 실제 고유값 (행 36,500개 기준) |
|---|---|---|
| A | 200 | 200 |
| B | -1 | 36,500 |
| C | -0.01 | 365 |

> **면접 예상 질문:** `n_distinct = 200`인 컬럼과 `n_distinct = -0.5`인 컬럼 중 어느 쪽이 카디널리티가 높나요?

---

### ANALYZE — 통계를 언제 갱신하는가

`pg_stats`의 통계는 자동 또는 수동으로 갱신된다.

**자동 갱신**: `autovacuum` 데몬이 주기적으로 ANALYZE를 실행한다. 변경 행 수 기준:
- `autovacuum_analyze_threshold` (기본 50)
- `autovacuum_analyze_scale_factor` (기본 0.1 → 테이블 크기의 10%)

**수동 갱신**: 통계가 stale하다고 의심되면 직접 돌린다.

```sql
ANALYZE diary;        -- 특정 테이블
ANALYZE;              -- 전체 DB
ANALYZE diary (date); -- 특정 컬럼만
```

**언제 수동 ANALYZE가 필요한가:**
- 대량 INSERT/UPDATE/DELETE 직후 (autovacuum 도래 전)
- 인덱스 설계 직전 — 최신 카디널리티로 결정하고 싶을 때
- `n_distinct`가 0이거나 비현실적인 값으로 나올 때

**ANALYZE 자체는 비용이 큰가?**
- 전체 테이블이 아닌 **샘플링 기반**(기본 300 × default_statistics_target 행)이라 가볍다.
- 잠금도 `ShareUpdateExclusiveLock` 수준 — DML과 동시 실행 가능.

> **면접 예상 질문:** 대량 INSERT 직후 인덱스를 설계하려는데 pg_stats의 n_distinct가 0으로 나와요. 어떻게 대응하시겠어요?

---

## 학습 정리

- 카디널리티 = 컬럼 값의 다양성. 높을수록 인덱스 효율이 좋다 (결과 행이 적어지므로).
- 복합 인덱스 순서는 "일반적 직관"이 아닌 **실제 테이블의 카디널리티**로 결정해야 한다 — 같은 컬럼명도 도메인마다 다르다.
- PostgreSQL은 `pg_stats` 뷰의 `n_distinct` 컬럼으로 카디널리티를 노출한다. **테이블이 아니라 뷰**.
- `n_distinct`는 부호로 단위가 갈린다: 양수 = 절대 개수, 음수 = 전체 대비 비율. 비교할 때는 단위 통일 필요.
- 음수 저장의 이유: PK/외래키처럼 행 수에 비례 증가하는 컬럼은 비율로 저장해야 테이블이 커져도 통계가 stale해지지 않는다.
- 통계는 `autovacuum`이 자동 갱신하지만, 대량 변경 직후엔 `ANALYZE 테이블명;`으로 수동 갱신할 수 있다.

## 참고

- [PostgreSQL Documentation — pg_stats](https://www.postgresql.org/docs/current/view-pg-stats.html)
- [PostgreSQL Documentation — ANALYZE](https://www.postgresql.org/docs/current/sql-analyze.html)
