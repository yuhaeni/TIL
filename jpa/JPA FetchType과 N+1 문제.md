# JPA FetchType과 N+1 문제

> 날짜: 2026-04-19

## 내용

### FetchType 기본값과 LAZY 프록시

JPA 연관관계 애노테이션의 기본 FetchType:

| 애노테이션 | 기본값 |
|---|---|
| `@OneToMany` | `FetchType.LAZY` |
| `@ManyToOne` | `FetchType.EAGER` |

**LAZY 프록시 동작 원리:**
- `getProduct()` → 프록시(껍데기) 반환, 쿼리 발생 안 함
- `getName()` → 실제 데이터 필요 시점, **그때 DB 조회 발생**
- 프록시는 `id`만 가진 껍데기 객체

LAZY는 쿼리 발생 **시점만 늦출 뿐**, N+1 문제를 근본적으로 해결하지는 않는다.

> **면접 예상 질문:** LAZY 프록시는 어떻게 동작하는가? `@OneToMany`와 `@ManyToOne`의 기본 FetchType이 다른 이유는?

---

### N+1 문제 발생 원리

`OrderItem` 100개를 조회하고 각 `OrderItem`의 `Order`를 조회하면:
- `OrderItem` 전체 조회: **1번**
- 각 `OrderItem`의 `Order` 개별 조회: **100번**
- 총 **101번** 쿼리 발생 → N+1 문제

**EAGER가 JOIN을 항상 보장하지 않는 이유:**
- `findById()` → `EntityManager.find()` → EAGER 반영됨
- `findAll()` / JPQL → 개발자가 작성한 쿼리 그대로 SQL로 변환, **EAGER 무시!**

JPQL은 테이블명 대신 **엔티티 클래스명**을 사용하며, 개발자가 명시적으로 쓴 것만 쿼리에 반영된다. 그래서 EAGER로 설정했어도 JPQL에서는 연관 엔티티를 추가 쿼리로 불러오게 된다.

> **면접 예상 질문:** N+1 문제는 왜 발생하는가? EAGER로 설정해도 N+1이 발생하는 경우는?

---

### Hibernate 6 배치 최적화

Hibernate 6부터는 `@ManyToOne` lazy 로딩 시 자동으로 IN 절로 묶어서 조회한다.

```sql
-- 전통적 N+1: WHERE id = 1, WHERE id = 2, ... (100번)
-- Hibernate 6: WHERE id = any (?) = WHERE id IN (1, 2, 3, ...) (1번)
```

전통적인 N+1이 **1번 쿼리로 최적화**되므로, 단순 lazy 로딩만으로도 어느 정도 성능이 개선된다.

> **면접 예상 질문:** Hibernate 6의 N+1 자동 최적화는 어떻게 동작하는가?

---

### JOIN vs JOIN FETCH

일반 `JOIN`과 `JOIN FETCH`는 목적이 다르다.

| | 일반 JOIN | JOIN FETCH |
|---|---|---|
| 조인 | 수행 | 수행 |
| 연관 객체 영속성 컨텍스트 로딩 | 안 함 | 함 |
| 추가 쿼리 | 발생 | 없음 |

```java
@Query(
    "SELECT DISTINCT o FROM Order o"
        + " JOIN FETCH o.orderItems oi"
        + " JOIN FETCH oi.product"
        + " WHERE o.id = :id")
Optional<Order> findByIdWithItems(@Param("id") Long id);
```

**DISTINCT가 필요한 이유:** 1:N JOIN 시 Order가 OrderItem 개수만큼 중복된 행으로 뻥튀기된다. `DISTINCT`로 중복을 제거해야 한다.

> **면접 예상 질문:** `JOIN`과 `JOIN FETCH`의 차이는? `JOIN FETCH`에서 `DISTINCT`를 붙이는 이유는?

---

### N+1 해결책 비교

| 해결책 | 동작 방식 | 결과 |
|---|---|---|
| `JOIN FETCH` | JOIN으로 한 번에 조회 | SELECT 1번 |
| `@BatchSize(size = N)` | IN 절로 N개씩 묶음 | 실행 횟수 제어 (예: size=50, 100개 → 2번) |
| `@EntityGraph` | 내부적으로 Fetch Join 활용 | `attributePaths`로 편리하게 사용 |

**JOIN FETCH vs @BatchSize 트레이드오프:**

| 관계 | 권장 방식 | 이유 |
|---|---|---|
| 1:N (`@OneToMany`) | `@BatchSize` | JOIN FETCH 시 Order 1개 × OrderItem 100개 = 100행 뻥튀기 |
| N:1 (`@ManyToOne`) | `JOIN FETCH` | 단건 조인이라 뻥튀기 적음 |

**다단계 주의:** Order → OrderItem → Product를 모두 JOIN FETCH하면 **기하급수적 뻥튀기**가 발생한다.

`@BatchSize`는 Repository가 아닌 **엔티티 필드**에 붙인다.

```java
@BatchSize(size = 100)
@OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
private List<OrderItem> orderItems = new ArrayList<>();
```

> **면접 예상 질문:** N+1 해결책으로 JOIN FETCH와 @BatchSize 중 무엇을 선택할 것인가? 1:N과 N:1에서 선택 기준이 다른 이유는?

---

## 학습 정리

- `@OneToMany` 기본은 LAZY, `@ManyToOne` 기본은 EAGER
- LAZY 프록시는 실제 필드 접근 시점에 쿼리가 발생 → N+1 문제 원인
- EAGER도 JPQL/`findAll()`에서는 무시됨 → 개발자가 명시한 쿼리만 그대로 SQL 변환
- Hibernate 6는 `@ManyToOne` lazy 로딩 시 IN 절로 자동 최적화
- `JOIN FETCH`: 단건/N:1에 유리, `@BatchSize`: 1:N에서 뻥튀기 방지
- `JOIN FETCH` + 1:N은 중복 행이 생기므로 `DISTINCT` 필수
- 다단계 JOIN FETCH는 기하급수적 뻥튀기 주의

## 참고

- CarrotSettle (Java, Spring Boot 4.0.x) 프로젝트 기반 학습
