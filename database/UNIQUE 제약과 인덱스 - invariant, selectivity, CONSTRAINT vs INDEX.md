# UNIQUE 제약과 인덱스 — invariant, selectivity, CONSTRAINT vs INDEX

> 날짜: 2026-05-22

## 내용

### invariant — 코드 시그니처와 DB 제약의 약속

**invariant(불변 조건)** 는 코드나 데이터가 어떻게 변하든 절대 깨지면 안 되는 약속이다.

JWT refresh token 예시:

```kotlin
fun findByTokenHash(tokenHash: String): RefreshToken?
```

- 반환 타입이 `RefreshToken?` (단일 nullable) → 호출자에게 **"token_hash 하나당 RefreshToken은 0개 또는 1개"** 라는 약속을 한다.
- 만약 DB에 동일한 `token_hash` 가 2건 이상 들어가는 순간 → Spring Data 가 `IncorrectResultSizeDataAccessException` 을 던진다.
- 즉, **코드가 가정하는 invariant 를 DB가 강제(enforce) 해주는 게 UNIQUE 제약**이다.

JWT 특성상 충돌 가능성은 거의 0이지만, **그렇기 때문에** DB 레벨에서 명시적으로 강제하는 게 invariant 와 더 잘 맞는다. "확률적으로 안 일어남" 과 "구조적으로 못 일어남" 은 다른 차원의 보장이다.

> **면접 예상 질문:** 단일 nullable 반환을 보장하는 메서드 시그니처에 대응하는 DB invariant를 어떻게 강제하나요? 그 강제를 코드 레벨(예: validation)에 두는 것과 DB 레벨에 두는 것의 차이는?

---

### UNIQUE 제약 vs UNIQUE 인덱스 — PostgreSQL 내부 동일성

**PostgreSQL에서 둘은 사실상 같은 객체다.**

| 방법 | 결과 |
|---|---|
| `ALTER TABLE refresh_token ADD CONSTRAINT uk_token_hash UNIQUE (token_hash);` | UNIQUE 인덱스가 자동 생성됨 |
| `CREATE UNIQUE INDEX idx_refresh_token_token_hash ON refresh_token (token_hash);` | 인덱스 자체가 UNIQUE 제약 역할을 수행 |

UNIQUE 제약을 만들면 PostgreSQL이 내부적으로 **중복 체크용 B+Tree 인덱스를 자동 생성**한다. 매번 INSERT마다 100만 행을 풀스캔해서 중복 검사하는 건 비현실적이기 때문.

**미세한 차이:**

- **CONSTRAINT 방식**: `information_schema.table_constraints` + `pg_constraint` 에 등록 → **외래 키(FK) 참조 대상**이 될 수 있음
- **UNIQUE INDEX 방식**: `pg_indexes` 에만 등록 → FK 참조 대상 불가

refresh_token 의 token_hash 같이 FK 대상이 될 일이 없는 컬럼이라면, 둘은 실질적으로 동일하게 작동한다.

> **면접 예상 질문:** PostgreSQL에서 UNIQUE 제약을 걸면 내부적으로 어떤 자료구조가 만들어지나요? 그 자료구조가 INSERT 성능에 미치는 영향은?

---

### selectivity와 planner 통계 — n_distinct, 실행 계획 정확도

**selectivity(선택도)** = 조건을 적용했을 때 전체 행 중 몇 %가 남는가 (0.0 ~ 1.0).

예시 — `refresh_token` 100만 행:

| 조건 | 결과 행 | selectivity | planner 선택 |
|---|---|---|---|
| `WHERE user_id = 5` | 평균 10행 | 0.00001 (매우 선택적) | Index Scan |
| `WHERE is_active = true` | 50만 행 | 0.5 (선택적 X) | Seq Scan |

selectivity가 낮을수록 인덱스 스캔이 유리하고, 높을수록 어차피 대부분 읽어야 하니 Seq Scan 이 더 빠를 수 있다.

**UNIQUE 인덱스가 planner 에 유리한 이유:**

PostgreSQL planner는 `pg_statistic` 에 저장된 `n_distinct` (컬럼의 고유 값 개수) 통계로 selectivity 를 추정한다.

| | 일반 인덱스 (token_hash) | UNIQUE 인덱스 (token_hash) |
|---|---|---|
| selectivity 추정 | 통계 샘플링 기반 → "평균 1.2행" (부정확 가능) | **"무조건 1행"으로 확정** |
| 결과 행 수 추정 | 가변적 | 정확히 1 |

JOIN 시나리오:

```sql
SELECT u.* FROM users u
JOIN refresh_token rt ON rt.user_id = u.id
WHERE rt.token_hash = 'abc...';
```

- **UNIQUE 인덱스 有**: planner가 "rt에서 정확히 1행 → JOIN 결과도 최대 1행" 으로 확신 → 더 공격적인 JOIN 알고리즘/순서 선택
- **일반 인덱스 만**: "평균 1.2행? 5행? 잘 모름" → 보수적인 실행 계획

즉, UNIQUE 는 planner 에게 **"이 컬럼의 selectivity 는 정확히 1/N 이다"** 라는 확정적 정보를 제공한다.

> **면접 예상 질문:** 같은 컬럼에 일반 인덱스를 걸 때와 UNIQUE 인덱스를 걸 때, PostgreSQL 쿼리 플래너 입장에서 어떤 차이가 생기나요? 그게 JOIN 쿼리의 실행 계획에 어떻게 영향을 주나요?

---

### CONSTRAINT 방식 vs CREATE UNIQUE INDEX 방식 — 의도 명시성

PostgreSQL 에서 결과 객체는 동일하지만, **의도(intent) 표현이 다르다.**

```sql
-- 의도 명확: "이건 비즈니스 규칙상 UNIQUE 제약이야"
ALTER TABLE refresh_token 
  ADD CONSTRAINT uk_refresh_token_token_hash UNIQUE (token_hash);

-- 의도 묻힘: "인덱스인 척 하지만 사실 제약도 겸함"
CREATE UNIQUE INDEX idx_refresh_token_token_hash 
  ON refresh_token (token_hash);
```

**판단 기준:**

- **CONSTRAINT 권장**: 비즈니스 규칙으로서의 UNIQUE 를 강조하고 싶을 때. `\d refresh_token` 으로 스키마를 봤을 때 한눈에 "UNIQUE 제약" 으로 보인다.
- **CREATE UNIQUE INDEX 권장**: 마이그레이션 파일이 인덱스 추가 패턴으로 통일되어 있을 때 (예: `V3__add_hotpath_indexes.sql`), 한 줄로 끝나는 간결함이 필요할 때.

리뷰 받았을 때 "마이그레이션 두 단계로 나누는 것도 방법" 이라는 코멘트가 따라온 이유:
- 기존 데이터에 이미 중복이 있으면 `CREATE UNIQUE INDEX` 자체가 실패한다.
- 단계 1: 중복 데이터 정리 (DELETE 또는 DEDUP)
- 단계 2: UNIQUE 인덱스/제약 추가

> **면접 예상 질문:** `ADD CONSTRAINT ... UNIQUE` 와 `CREATE UNIQUE INDEX` 중 무엇을 선호하고 왜 그렇게 선택하나요? 기존 데이터에 중복이 있을 가능성이 있다면 마이그레이션을 어떻게 설계하겠어요?

---

## 학습 정리

- **invariant** = 코드 시그니처가 호출자에게 하는 약속. DB UNIQUE 제약은 그 약속을 구조적으로 강제하는 장치다.
- PostgreSQL 에서 **UNIQUE 제약과 UNIQUE 인덱스는 사실상 동일한 객체**다. 차이는 메타데이터 등록 위치(`pg_constraint` vs `pg_indexes`)와 FK 참조 가능 여부.
- **selectivity** 는 planner 가 실행 계획을 짤 때 사용하는 핵심 통계. UNIQUE 인덱스는 selectivity 를 "정확히 1행" 으로 확정해주므로 JOIN 등에서 더 정확한 실행 계획이 가능하다.
- **CONSTRAINT vs CREATE UNIQUE INDEX** 선택은 효과 동일, **의도 명시성** 의 차이. 비즈니스 규칙 강조면 CONSTRAINT, 인덱스 추가 맥락 통일이면 INDEX.
- 기존 데이터에 중복 가능성이 있으면 **"중복 정리 → UNIQUE 인덱스 추가"** 두 단계 마이그레이션 권장.

## 참고

- [PostgreSQL 인덱스와 B+Tree](PostgreSQL%20인덱스와%20B+Tree.md)
- [카디널리티와 복합 인덱스 - pg_stats, n_distinct, ANALYZE](카디널리티와%20복합%20인덱스%20-%20pg_stats,%20n_distinct,%20ANALYZE.md)
