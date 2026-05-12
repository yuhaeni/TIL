# JPA LAZY 프록시 함정 — Kotlin val/final, Hibernate 프록시 불가, kotlin-allopen

> 날짜: 2026-05-12

## 내용

### 상황 — LAZY인데 왜 users 쿼리가 항상 같이 나가나?

소유권 검증 로직에서 시작했다.

```kotlin
private fun getValidatedDiary(userId: Long, diaryId: Long): Diary {
    val diary = diaryRepository.findByIdOrNull(diaryId) ?: throw DiaryNotFoundException()
    if (diary.user.id != userId) {
        throw NotDiaryOwnerException()
    }
    return diary
}
```

실행 시 두 개의 쿼리:

```sql
SELECT ... FROM diary WHERE d.id=?
SELECT ... FROM users WHERE u.id=?
```

처음엔 "`diary.user.id` 접근이 프록시 초기화를 트리거해서 user 쿼리가 나간다" 고 가정하고 `findByIdAndUserId`로 검증 쿼리를 한 번으로 합쳤다. 그런데 **여전히 users 쿼리가 사라지지 않았다.**

```kotlin
private fun getValidatedDiary(userId: Long, diaryId: Long): Diary =
    diaryRepository.findByIdAndUserId(diaryId, userId) ?: throw DiaryNotFoundException()
```

```sql
SELECT ... FROM diary WHERE id=? AND user_id=?   -- ① 합쳐짐 ✅
SELECT ... FROM users WHERE id=?                 -- ② 그대로 ❌
```

전체 SQL 로그를 보니 `users` 쿼리가 `diary.diaryActivityCategories` 접근보다 **먼저** 발생했다. 즉 `.user.id` 같은 접근 코드 없이도 User가 로드되고 있었다. 진짜 원인은 따로 있다.

> **면접 예상 질문:** `@ManyToOne(fetch = FetchType.LAZY)`를 명시했는데도 LAZY가 동작하지 않는 대표적 원인을 코틀린/자바 환경에서 비교해 설명해보세요.

---

### 진짜 원인 — Kotlin val은 Java final로 컴파일된다

```kotlin
@Entity
class Diary(
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    val user: User,   // ← 핵심
    ...
)
```

`val user: User` 의 Kotlin 컴파일 결과:

```java
private final User user;
public final User getUser() { return this.user; }
```

게다가 **Kotlin은 클래스 자체도 기본이 `final`** 이다. 그래서 `Diary` 클래스도, `getUser()` 메서드도 둘 다 `final`.

> **면접 예상 질문:** Kotlin의 `val`/`var`와 `final`/`open`은 어떤 차원의 키워드인지 비교해서 설명해보세요.

---

### Hibernate LAZY 프록시의 원리 — 자식 클래스로 getter 오버라이드

Hibernate의 LAZY 프록시는 마법이 아니라 **런타임에 자식 클래스를 만들어 끼워넣는** 방식이다.

```
[User 클래스]
       ↓ 상속 (extends)
[User$HibernateProxy] ← Hibernate가 런타임에 만든 자식
       └ override getId()   { 필요할 때 DB SELECT }
       └ override getName() { 필요할 때 DB SELECT }
```

`diary.user` 자리에 들어가는 객체는 진짜 User가 아니라 이 자식 프록시. 어떤 getter를 호출하든 "그때 가서 DB 조회" 로직이 끼어든다.

핵심: **이 동작은 부모 메서드를 오버라이드할 수 있어야** 성립한다.

> **면접 예상 질문:** Hibernate가 LAZY 프록시를 만들 때 내부적으로 어떤 메커니즘을 사용하나요?

---

### 충돌 — final이면 오버라이드 불가 → 프록시 자체를 못 만든다

Java/Kotlin의 기본 규칙: **`final` 클래스/메서드는 상속도 오버라이드도 불가능.**

따라서 Hibernate가 `Diary`와 `User`의 프록시를 만들려고 해도, 클래스가 `final`이라 상속 자체가 안 되고, 메서드도 `final`이라 오버라이드도 안 된다.

이 경우 Hibernate가 선택하는 fallback:
1. LAZY 프록시를 못 만든다.
2. 그래서 **Diary를 로드하는 시점에 User도 즉시 SELECT해서 박아넣는다.**
3. 결과: `@ManyToOne(fetch = LAZY)` 라고 적어놨지만 **실질적으로 EAGER처럼 동작.**

이래서 `findByIdAndUserId` 로 코드 레벨의 `.user.id` 접근을 모두 제거해도 user 쿼리가 사라지지 않은 것이다.

> **면접 예상 질문:** Kotlin 엔티티에서 `@ManyToOne(fetch = LAZY)`가 EAGER처럼 동작하게 되는 메커니즘을 단계별로 설명해보세요.

---

### final이 왜 존재하는가 — 다형성으로 인한 보안/안정성 보호

자식 클래스에서 메서드를 오버라이드해도 부모 클래스 자체는 안 바뀐다. 그런데 문제는 **다형성(Polymorphism)** 이다.

```java
void process(String s) {
    if (s.equals("admin")) {
        // 관리자 권한 부여!
    }
}
```

만약 `String`이 final이 아니었다면, 누가 `EvilString extends String` 을 만들어 `equals()`를 "무조건 true 반환"으로 오버라이드 후 `process(EvilString())` 으로 넘기면 관리자 권한이 탈취된다. `process` 함수 입장에선 그냥 String이 들어왔다고 믿었을 뿐이다.

Java 설계자들은 이런 위험 때문에 `String`, `Integer`, `LocalDateTime` 같은 핵심 클래스를 `final`로 막아뒀다. **final = "이 클래스의 동작을 상속으로 깨뜨리지 마세요"** 라는 선언.

> **면접 예상 질문:** `final` 키워드가 제공하는 보안적/설계적 이점은 무엇이며, 다형성이라는 개념과 어떻게 연결되나요?

---

### Kotlin은 왜 기본이 final인가 — Fragile Base Class Problem

Java는 기본이 "상속 가능", `final`을 명시해야 막을 수 있다. Kotlin은 정반대로 기본이 `final`, `open`을 명시해야 상속이 열린다.

Kotlin이 이 방향을 택한 이유는 **Fragile Base Class Problem(취약한 부모 클래스 문제)** 때문.

- 누군가 `Calculator.add()`를 상속해서 자식이 부모의 내부 동작에 의존하는 방식으로 오버라이드한다.
- 나중에 내가 `Calculator`의 구현을 바꾸면, 자식 클래스가 **나도 모르게 깨진다.**
- 즉 부모 변경 → 자식 망가짐. 부모는 "취약해진다."

Joshua Bloch는 『Effective Java』 에서 "**상속을 위해 설계하고 문서화하라, 아니면 막아라**"(Design for inheritance or prohibit it)는 원칙을 강조했다. Java는 권고만 했지만 **Kotlin은 이를 언어 차원에서 강제**한 셈.

| 키워드 | 다루는 것 | 기본값(Kotlin) |
|--------|----------|-----------------|
| `val` / `var` | 재할당 가능 여부 | 선택 |
| `final` / `open` | 상속/오버라이드 가능 여부 | **final** |

`var`로 바꿔도 `final`은 그대로다. `val` ↔ `var` 와 `final` ↔ `open`은 다른 차원의 키워드.

> **면접 예상 질문:** Kotlin이 클래스/메서드의 기본값을 `final`로 설정한 설계 의도는 무엇이며, 이로 인해 JPA/Spring 같은 프레임워크와 발생하는 충돌은 어떻게 해결하나요?

---

### 해결 — kotlin-allopen 플러그인

엔티티마다 `open` 키워드를 일일이 붙이는 건 너무 번거롭다. Gradle 플러그인이 자동으로 처리해준다.

```kotlin
plugins {
    kotlin("plugin.spring") version "2.2.21"     // @Component 등 자동 open
    kotlin("plugin.jpa") version "2.2.21"        // @Entity 등 no-arg 생성자 자동 생성
    kotlin("plugin.allopen") version "2.2.21"    // 지정한 어노테이션 클래스 자동 open
}

allOpen {
    annotation("jakarta.persistence.Entity")
    annotation("jakarta.persistence.MappedSuperclass")
    annotation("jakarta.persistence.Embeddable")
}
```

오해 주의: `allopen`이라는 이름 때문에 "모든 클래스가 open이 되는 것" 처럼 보이지만, 실제로는 **지정한 어노테이션이 붙은 클래스만** open으로 만든다. 일반 Service/Util 클래스는 그대로 final로 남아 안전.

`plugin.spring`도 내부적으로 `plugin.allopen` 위에서 동작하면서 `@Component`, `@Configuration`, `@Service`, `@Repository`, `@Controller`, `@Async` 등을 자동 열어주는 사전 설정일 뿐이다.

이 설정 후에는 `Diary`/`User` 가 진짜 open이 되므로 Hibernate가 프록시를 만들 수 있고, `@ManyToOne(fetch = LAZY)`이 의도대로 동작한다.

> **면접 예상 질문:** `kotlin-allopen` 플러그인의 동작 원리와 `plugin.spring` / `plugin.jpa` 와의 관계를 설명해보세요.

---

### 보너스 — findByIdAndUserId는 그래도 가치 있다

`kotlin-allopen`을 적용해 LAZY가 제대로 동작하더라도, 소유권 검증을 위해 user를 따로 조회할 필요는 없다. `findByIdAndUserId`는 여전히 다음 이유로 더 낫다.

- 쿼리 의도가 명확: "내 거인 다이어리"를 한 번에 찾는다는 의미가 메서드명에 그대로 드러난다.
- DB가 인덱스(user_id)로 한 번에 필터링하므로 권한 없는 다이어리는 결과 단계에서 제외된다.
- 검증 분기 로직(`if (diary.user.id != userId)`)이 사라져 서비스 코드가 단순해진다.

즉 `findByIdAndUserId` = "프록시 함정 우회"가 아니라 **소유권 검증 패턴의 정답형 쿼리**로 보는 게 맞다.

> **면접 예상 질문:** 연관 엔티티의 소유권을 검증할 때 `entity.parent.id` 비교 방식과 `findByIdAndParentId` 방식의 차이를 설명해보세요.

---

## 학습 정리

- 같은 증상(LAZY인데 user 쿼리 발생)에도 원인은 두 가지가 겹쳐 있다: (1) 코드 레벨의 `.user.id` 접근, (2) Kotlin `val`이 `final`로 컴파일돼 Hibernate가 LAZY 프록시 자체를 못 만들어 EAGER처럼 동작.
- `findByIdAndUserId` 같은 단일 쿼리 메서드는 (1)을 우회할 뿐, (2)는 해결되지 않는다. 진짜 해결은 엔티티 클래스를 **`open`** 으로 만드는 것.
- Kotlin의 `val`/`var`는 재할당, `final`/`open`은 상속 가능성을 다루는 별개의 축이다. `var`로 바꿔도 `final`은 그대로 유지된다.
- Java는 기본 open, Kotlin은 기본 final. Kotlin은 Fragile Base Class Problem을 언어 차원에서 막기 위해 정반대 선택을 했다. JPA/Spring과 충돌하는 부분은 `kotlin-allopen` 플러그인으로 어노테이션 기반으로만 선택적으로 연다.
- 같은 LAZY 트러블슈팅이라도 "코드에서 .user 접근을 지우면 끝" 인지, "엔티티 자체가 final이라 EAGER 동작" 인지 SQL 로그의 발생 시점과 순서로 구분해야 한다.

## 참고

- 대화 컨텍스트 (러버덕 디버깅 세션, 2026-05-12)
