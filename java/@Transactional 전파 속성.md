# @Transactional 전파 속성

> 날짜: 2026-04-17

## 내용

### 전파 속성(Propagation)이란?

"메서드에 들어왔을 때, 이미 트랜잭션이 있으면 어떻게 할 거냐"를 결정하는 옵션이다.

```java
@Transactional(propagation = Propagation.REQUIRED) // 기본값
```

| 속성 | 동작 |
|---|---|
| `REQUIRED` (기본값) | 있으면 참여, 없으면 생성 |
| `REQUIRES_NEW` | 항상 새로 생성 (독립적) |
| `SUPPORTS` | 있으면 참여, 없으면 트랜잭션 없이 실행 |
| `NOT_SUPPORTED` | 있으면 일시 중단, 없으면 그냥 실행 |
| `MANDATORY` | 있으면 참여, 없으면 예외 |
| `NEVER` | 있으면 예외, 없으면 실행 |
| `NESTED` | 중첩 트랜잭션 (SAVEPOINT 활용) |

> **면접 예상 질문:** `@Transactional`의 기본 전파 속성은? 전파 속성이란 무엇인가?

---

### REQUIRED vs REQUIRES_NEW

**REQUIRED (기본값):** 트랜잭션이 있으면 기존에 참여, 없으면 새로 생성. 부모가 롤백되면 자식도 함께 롤백된다.

**REQUIRES_NEW:** 기존 트랜잭션과 무관하게 항상 새로운 트랜잭션을 생성한다. 기존 트랜잭션은 일시 중단되고, 독립적으로 커밋/롤백된다.

| | REQUIRED | REQUIRES_NEW |
|---|---|---|
| 트랜잭션 있을 때 | 기존에 참여 | 새로 생성 (기존 중단) |
| 트랜잭션 없을 때 | 새로 생성 | 새로 생성 |
| 롤백 영향 | 부모와 함께 롤백 | 독립적으로 커밋/롤백 |
| 주요 용도 | 일반 비즈니스 로직 | 로그, 감사, 알림 등 |

**REQUIRES_NEW 활용 예시 — 감사 로그:**

```java
@Transactional
public OrderResponse createOrder(...) {
    orderRepository.save(order);
    auditLogService.log("주문 생성"); // 주문이 실패해도 로그는 남아야 함
}

@Transactional(propagation = Propagation.REQUIRES_NEW)
public void log(String message) {
    // 부모와 독립적으로 커밋됨 ✅
}
```

부모 트랜잭션이 롤백되더라도 로그 기록은 남겨야 하는 경우 `REQUIRES_NEW`를 사용한다.

> **면접 예상 질문:** 감사 로그는 왜 `REQUIRES_NEW`를 사용하는가? `REQUIRED`와의 차이는?

---

### NEVER: 방어적 설계

트랜잭션이 있으면 예외(`IllegalTransactionStateException`)를 던지고, 없으면 정상 실행한다.

| | `@Transactional` 없음 | `NEVER` |
|---|---|---|
| 부모 트랜잭션 있을 때 | 그냥 참여해버림 (막을 수 없음) | 예외 던짐 |
| 의미 | 암묵적 | 명시적 강제 + 문서화 |

"이 메서드는 절대 트랜잭션 안에서 실행되면 안 된다!"를 코드로 강제하는 방어적 설계다. `@Transactional`을 단순히 생략하면 부모 트랜잭션에 그대로 참여해버리지만, `NEVER`는 예외로 이를 명시적으로 차단한다.

> **면접 예상 질문:** `@Transactional`을 안 쓰는 것과 `NEVER`는 무엇이 다른가?

---

### 외부 API 호출은 트랜잭션 밖에서

DB 커넥션은 트랜잭션이 시작되면 점유되고, 트랜잭션이 끝나야 반납된다. 외부 API 호출이 트랜잭션 안에 있으면:

```
트랜잭션 시작 → DB 커넥션 점유
    → 외부 API 호출 (느리거나 타임아웃 발생)
    → 그동안 커넥션은 계속 점유됨!
    → 동시 요청 100명 → 커넥션 풀 고갈 → 서비스 전체 마비!
```

```java
// ❌ 나쁜 예: 트랜잭션 안에서 외부 API 호출
@Transactional
public void process() {
    orderRepository.save(order);
    externalApiClient.call(); // 커넥션 점유한 채 대기!
}

// ✅ 좋은 예: 트랜잭션 범위를 최소화
public void process() {
    saveOrder(order);         // 짧은 트랜잭션
    externalApiClient.call(); // 트랜잭션 밖에서 호출
}

@Transactional
public void saveOrder(Order order) {
    orderRepository.save(order);
}
```

> **면접 예상 질문:** 외부 API 호출을 트랜잭션 안에 넣으면 안 되는 이유는?

---

## 학습 정리

- `REQUIRED`(기본값): 있으면 참여, 없으면 생성 → 부모 롤백 시 함께 롤백
- `REQUIRES_NEW`: 항상 독립 트랜잭션 생성 → 감사 로그처럼 부모 실패와 무관하게 커밋해야 할 때 사용
- `NEVER`: 트랜잭션 존재 시 예외 → 단순 미사용과 달리 의도를 명시적으로 강제하는 방어적 설계
- 외부 API 호출은 트랜잭션 밖으로 분리 → 커넥션 풀 고갈 방지

## 참고

- CarrotSettle (Java, Spring Boot 4.0.x) 프로젝트 기반 학습
