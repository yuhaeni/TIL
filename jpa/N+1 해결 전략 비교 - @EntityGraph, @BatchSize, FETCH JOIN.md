# N+1 해결 전략 비교 — @EntityGraph, @BatchSize, FETCH JOIN

> 날짜: 2026-05-13

## 내용

### N+1 발견 — 컬렉션 순회 중 LAZY 프록시 깨우기

다음 코드에서 `it.activityCategory` 에 접근할 때마다 SELECT 쿼리가 한 번씩 추가로 나갔다.

```kotlin
fun getDiary(userId: Long, diaryId: Long): GetDiaryResponseDto {
    val diary = getValidatedDiary(userId, diaryId)
    val diaryActivityCategories =
        diary.diaryActivityCategories
            .map { it.activityCategory }   // ← 여기서 쿼리 폭발
            .toResponseDto()
    ...
}
```

```
Hibernate: select ... from diary_activity_category where diary_id=?       -- 컬렉션 LAZY 1번
Hibernate: select ... from activity_category where id=?                   -- 6번 반복
Hibernate: select ... from activity_category where id=?
...
```

엔티티 매핑이 `@ManyToOne(fetch = FetchType.LAZY)` 라 `diary.diaryActivityCategories` 안의 각 `DiaryActivityCategory.activityCategory` 는 **프록시 껍데기**. 컬렉션을 순회하면서 실제 필드에 접근하는 순간 프록시가 깨어나고, 그때마다 `WHERE id = ?` 쿼리가 하나씩 추가된다. 1(부모) + N(자식)의 전형적인 N+1 시그니처.

여기서 헷갈리기 쉬운 포인트: **컬렉션 자체의 LAZY 깨우기**는 `WHERE diary_id = ?` 한 번으로 6개를 다 가져온다. 반면 **그 안의 단일 필드 LAZY**는 객체마다 따로 깨어난다.

> **면접 예상 질문:** 컬렉션 연관관계의 LAZY 로딩과 단일 연관관계의 LAZY 로딩이 만들어내는 쿼리 패턴이 다른 이유는? `@ManyToOne` 의 기본 FetchType이 EAGER 인데도 LAZY 로 바꾸는 이유는?

---

### @EntityGraph — 어노테이션으로 fetch 그래프 선언

`@EntityGraph(attributePaths = [...])` 를 Repository 메서드 위에 붙이면, Hibernate가 해당 메서드 호출 시 **LEFT OUTER JOIN** 으로 지정된 연관 엔티티를 함께 가져온다. 기존 쿼리(메서드 이름 기반)는 그대로 두고 fetch 힌트만 얹는 방식.

```kotlin
@EntityGraph(
    attributePaths = [
        "diaryActivityCategories",
        "diaryActivityCategories.activityCategory",
    ],
)
fun findByIdAndUserId(id: Long, userId: Long): Diary?
```

- 결과 쿼리: **1번** (LEFT JOIN 한 방)
- Spring Data JPA 의 `findByXxx` 메서드 그대로 재사용 가능
- JOIN 타입은 **LEFT OUTER 로 고정**, WHERE/ORDER BY 같은 조건 커스터마이즈는 불가
- 컬렉션을 fetch 하면 카르테시안 곱이 발생 — `diary 1건 × 카테고리 6건 = 6행`. Hibernate가 중복 행을 하나의 객체로 정리해주지만, 데이터 전송량은 그만큼 늘어남
- 컬렉션을 **두 개 이상** fetch 하면 `MultipleBagFetchException` 발생 (Bag 의 카르테시안 폭발 방지)

> **면접 예상 질문:** `@EntityGraph` 가 만들어내는 SQL 의 JOIN 타입은? 컬렉션을 두 개 이상 attributePaths 에 넣었을 때 발생하는 예외와 그 이유는?

---

### @BatchSize — LAZY는 유지하되 IN 절로 묶어 깨우기

`@BatchSize(size = N)` 은 LAZY 자체는 그대로 둔다. 다만 같은 종류의 프록시 여러 개를 동시에 깨워야 할 때, **`WHERE id IN (?, ?, ?, ...)` 한 방으로 묶어서** 가져온다.

```kotlin
@Entity
class ActivityCategory(...) : BaseEntity() {
    // 또는 @BatchSize 를 필드에 직접
}
```

이번 케이스 적용 시 쿼리 흐름:

| 단계 | 쿼리 | 횟수 |
|---|---|---|
| 1 | `diary` 본체 SELECT | 1 |
| 2 | `diary_activity_category` 컬렉션 LAZY 깨움 (`WHERE diary_id = ?`) | 1 |
| 3 | `activity_category` 프록시 6개를 IN 절로 한 번에 (`WHERE id IN (1,2,3,4,5,6)`) | 1 |

총 **3번**. `@EntityGraph` 의 1번보다는 많지만, 다음 상황에서 강점이 있다.

- **다건 조회**: diary 10건을 한 번에 조회하면서 각 diary 의 카테고리들을 IN 절로 묶을 수 있음
- **깊은 LAZY 그래프**: 두 단계 이상 LAZY 가 이어질 때 JOIN 하나로 묶기 어려운 경우
- **카르테시안 곱 회피**: JOIN 으로 행이 폭발하는 상황에서 데이터 전송량을 줄여줌

> **면접 예상 질문:** `@BatchSize` 가 `@EntityGraph` 보다 쿼리 수는 많은데도 선택되는 상황은? 단건 조회와 다건 조회에서 효용 차이가 나는 이유는?

---

### JPQL FETCH JOIN — 직접 쿼리 작성으로 최대 유연성

`@Query` 안에 JPQL 로 `JOIN FETCH` 를 직접 적는 방식. 결과 SQL 은 `@EntityGraph` 와 비슷하지만 **쿼리 자체를 손으로 짠다**는 게 다르다.

```kotlin
@Query(
    """
    SELECT d FROM Diary d
    JOIN FETCH d.diaryActivityCategories dac
    JOIN FETCH dac.activityCategory ac
    WHERE d.id = :id AND d.userId = :userId AND ac.name LIKE :keyword
    """
)
fun findWithCategories(id: Long, userId: Long, keyword: String): Diary?
```

- **WHERE / ORDER BY / GROUP BY 를 자유롭게** 결합할 수 있음
- JOIN 타입을 INNER / LEFT 선택 가능
- 그 대신 Spring Data 메서드 이름 쿼리의 편의는 잃고, JPQL 문자열을 직접 관리해야 함

> **면접 예상 질문:** `@EntityGraph` 와 JPQL `FETCH JOIN` 이 같은 SQL 을 만들 수 있는데도 둘 다 존재하는 이유는? FETCH JOIN 이 더 자연스러운 케이스를 예로 들어보면?

---

### 세 방식 비교표 & 선택 기준

| 비교 항목 | `@EntityGraph` | `@BatchSize` | JPQL `FETCH JOIN` |
|---|---|---|---|
| 선언 위치 | 메서드 위 어노테이션 | 엔티티/필드 어노테이션 | JPQL 쿼리 문자열 |
| Spring Data 메서드 쿼리 재사용 | ✅ | ✅ (직교) | ❌ |
| JOIN 타입 제어 | LEFT OUTER 고정 | — (JOIN 안 함) | INNER / LEFT 선택 |
| WHERE 등 조건 커스터마이즈 | ❌ | — | ✅ 자유 |
| 결과 쿼리 수 (단건 + 컬렉션 1개) | 1 | 3 (부모 1 + 컬렉션 1 + IN 1) | 1 |
| 카르테시안 곱 발생 | ⭕ | ❌ (분리 쿼리) | ⭕ |
| `MultipleBagFetchException` 위험 | ⭕ | ❌ | ⭕ |

**선택 기준 정리:**

- **단건 + 단일 컬렉션 + 단순 fetch** → `@EntityGraph` (가장 깔끔)
- **다건 조회 / 깊은 LAZY 그래프 / 카르테시안 곱 회피** → `@BatchSize`
- **복잡한 WHERE 조건과 fetch 를 결합** → JPQL `FETCH JOIN`

> **면접 예상 질문:** 세 방식을 모두 알고 있다고 가정할 때, 실무에서 어떤 기준으로 선택하는가? 트래픽이 늘어나 컬렉션 사이즈가 커지면 전략을 어떻게 바꿔야 하는가?

---

## 학습 정리

- 컬렉션 LAZY 는 `WHERE 부모_id = ?` 한 번에 자식들을 다 가져오지만, 그 안의 단일 필드 LAZY 는 객체마다 따로 깨어나 N+1 이 발생한다.
- `@EntityGraph` 는 LEFT JOIN 한 방으로 가장 적은 쿼리를 만들지만, 카르테시안 곱과 `MultipleBagFetchException` 위험을 떠안는다.
- `@BatchSize` 는 LAZY 를 유지한 채 IN 절로 묶어 가져오므로, 다건 조회나 깊은 그래프에서 데이터 전송량이 유리하다.
- `FETCH JOIN` 은 JPQL 직접 작성의 자유도(WHERE/ORDER BY/JOIN 타입)가 핵심 강점이다.
- 단건/다건, 컬렉션 개수, 조건 결합 여부에 따라 세 전략을 의식적으로 갈아 끼울 수 있어야 한다.

## 참고

- [JPA FetchType과 N+1 문제](JPA%20FetchType%EA%B3%BC%20N%2B1%20%EB%AC%B8%EC%A0%9C.md)
