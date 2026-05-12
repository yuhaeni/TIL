# JPA LAZY 프록시 함정 — diary.user.id 추가 쿼리, Kotlin getter, findByIdAndUserId

> 날짜: 2026-05-12

## 내용

### 상황 — LAZY인데 왜 쿼리가 2번?

소유권 검증 로직에서 `diary.user.id`로 접근만 했는데 쿼리가 두 번 나갔다.

```kotlin
private fun getValidatedDiary(
    userId: Long,
    diaryId: Long,
): Diary {
    val diary = diaryRepository.findByIdOrNull(diaryId) ?: throw DiaryNotFoundException()
    if (diary.user.id != userId) {
        throw NotDiaryOwnerException()
    }
    return diary
}
```

실행 시 발생한 쿼리:

```sql
-- (1) diary 조회 (여기엔 이미 user_id 컬럼이 포함됨)
SELECT d1_0.id, d1_0.content, ..., d1_0.user_id FROM diary d1_0 WHERE d1_0.id=?

-- (2) users 전체 컬럼 추가 조회 ← 왜?
SELECT u1_0.id, u1_0.created_at, ..., u1_0.role FROM users u1_0 WHERE u1_0.id=?
```

`@ManyToOne(fetch = FetchType.LAZY)` 인데도 두 번째 쿼리가 나간 게 핵심 의문.

> **면접 예상 질문:** LAZY 로딩이 설정되어 있는데도 추가 쿼리가 발생하는 대표적인 케이스를 설명해보세요.

---

### LAZY 프록시 동작 원리 — "어떤 속성이든 접근하면 초기화"

`diary.user`는 진짜 `User` 객체가 아니라 **프록시(proxy)** 객체가 들어있다. 일종의 "택배 상자"처럼, 겉면에는 정보가 없고 열어봐야(=쿼리 실행) 내용물을 알 수 있는 구조.

**핵심:** 프록시는 `.id`든 `.name`이든 **어떤 속성에 접근하는 순간 무조건 초기화**된다. "id만 필요한가?" 같은 스마트 판단을 하지 않고 통째로 SELECT를 날린다.

이론적으로 **`@Id`가 필드 위에 붙어 있고 필드 접근 방식**이면 프록시가 id 값을 미리 들고 있어서 `.id`만으로는 초기화가 안 일어나야 한다. 하지만 Kotlin 환경에서는 자동 생성되는 getter 메서드 때문에 종종 깨진다.

> **면접 예상 질문:** Hibernate 프록시 객체에서 `.id` 접근만으로 초기화 없이 식별자를 얻을 수 있는 조건은 무엇인가요?

---

### Kotlin + JPA 함정 — val이 만드는 getter

Kotlin의 `val user: User` 선언은 자동으로 `getUser()` getter를 만든다. 마찬가지로 `User` 엔티티의 `val id: Long`도 `getId()`를 생성한다.

```kotlin
@Entity
class User(
    ...
) : BaseEntity() {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long = 0L
}
```

`diary.user.id`는 실제로 `diary.getUser().getId()` 호출로 컴파일된다. Hibernate 프록시는 이 getter 호출을 프로퍼티 접근으로 처리하면서 초기화를 트리거하는 경우가 많다 (Kotlin + JPA 의 유명한 함정).

> **면접 예상 질문:** Kotlin으로 JPA 엔티티를 작성할 때 발생하는 프록시 관련 함정에는 어떤 것들이 있나요?

---

### 해결 — 애초에 프록시를 거치지 않기

"이 diary가 내 거 맞아?"를 검증하려고 User 엔티티 전체를 조회하는 건 낭비다. `diary` 테이블에 이미 `user_id` 외래키가 있으므로 **WHERE 조건으로 한 번에 거르면 된다.**

```kotlin
diaryRepository.findByIdAndUserId(diaryId, userId)
```

생성되는 쿼리:

```sql
SELECT * FROM diary WHERE id = ? AND user_id = ?
```

- 쿼리는 단 1번 (User 테이블 조회 없음)
- 다이어리가 없거나 내 게 아니면 `null` 반환
- 프록시 초기화 자체가 일어나지 않으니 Kotlin 함정도 피해감

JOIN이 아니라 **단일 테이블 WHERE 필터**라는 점이 포인트.

> **면접 예상 질문:** 연관 엔티티의 소유권을 검증할 때 `entity.parent.id` 비교 방식과 `findByIdAndParentId` 방식의 차이를 설명해보세요.

---

### LAZY는 여전히 좋은 default

이번 케이스에서는 LAZY가 오히려 함정처럼 보였지만, LAZY의 본질은 **"불필요한 데이터 조회를 막아주는 것"** 이다.

- 다이어리 정보만 반환하고 작성자 정보를 안 보여주는 API → User 쿼리 자체가 안 나감
- 다이어리 목록 100개를 EAGER로 조회하면 User도 100번 함께 로딩 → N+1
- LAZY는 "필요할 때만" 가져온다는 정확한 의도를 표현하는 default

문제는 LAZY 자체가 아니라, **프록시의 동작 방식을 모른 채 접근하는 습관** 이다.

> **면접 예상 질문:** LAZY 로딩과 EAGER 로딩의 선택 기준은 무엇이며, LAZY를 default로 권장하는 이유는 무엇인가요?

---

## 학습 정리

- `diary.user.id`처럼 연관 엔티티의 id 하나만 필요해도 프록시 초기화가 일어나 추가 SELECT가 발생할 수 있다.
- 프록시는 어떤 속성 접근이든 통째로 초기화한다. `@Id` 필드 접근 방식이면 예외적으로 초기화를 피할 수 있지만, Kotlin의 자동 getter 때문에 이 최적화가 깨지는 경우가 많다.
- 소유권 검증처럼 "id만 비교" 하면 되는 시나리오에서는 `findByIdAndUserId` 같은 단일 쿼리 메서드로 프록시 자체를 우회하는 게 깔끔하다.
- LAZY는 N+1과 불필요한 조회를 막아주는 좋은 default이며, 함정은 LAZY가 아니라 프록시 동작을 모르는 코드 습관에서 나온다.

## 참고

- 대화 컨텍스트 (러버덕 디버깅 세션, 2026-05-12)
