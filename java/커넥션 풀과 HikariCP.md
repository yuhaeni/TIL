# 커넥션 풀과 HikariCP

> 날짜: 2026-04-17

## 내용

### 커넥션 풀(Connection Pool)이란?

DB 연결(Connection)을 미리 만들어놓고 재사용하는 기법이다.

DB 커넥션 생성은 TCP 핸드셰이크, 인증 등의 과정이 필요한 **비용이 큰 작업**이다. 매 요청마다 새 연결을 만들면 성능이 저하되므로, 미리 연결을 만들어두고 재사용하면 응답 시간이 단축된다.

```
트랜잭션 시작 = 커넥션 1개 점유
트랜잭션 종료 = 커넥션 반납 (풀로 돌아감)
```

**커넥션 풀 고갈 시나리오:**
```
풀 크기 = 10개
요청 1~10 → 각각 커넥션 대여 (풀: 0개 남음)
요청 11   → 대기... (반납될 때까지)

만약 요청 1~10이 외부 API 호출로 10초씩 걸린다면?
→ 10초 동안 나머지 요청들이 전부 대기
→ 타임아웃 시 전체 서비스 장애!
```

> **면접 예상 질문:** 커넥션 풀이 필요한 이유는? 커넥션 풀이 고갈되면 어떤 일이 발생하는가?

---

### 트랜잭션 범위와 커넥션 점유

트랜잭션 범위 = 커넥션 점유 범위이므로, **트랜잭션 범위를 짧게 유지**하면 커넥션 점유 시간이 짧아지고 처리량이 늘어난다.

**위험한 패턴: 트랜잭션 안에서 외부 API 호출**

```java
// ❌ 외부 API가 느려지면 커넥션이 묶여있음
@Transactional
public void processOrder() {
    orderRepository.save(order);    // 커넥션 점유 시작
    externalPgApi.call();           // 10초 걸림 (커넥션 점유 유지!)
    settlementRepository.save(...); // 커넥션 반납
}
```

**안전한 패턴: 트랜잭션 범위 분리**

```java
// ✅ 외부 API 호출은 트랜잭션 밖으로
public void processOrder() {
    Order savedOrder = saveOrder(order);      // 짧은 트랜잭션
    PgResult result = externalPgApi.call();   // 트랜잭션 밖!
    updateOrderStatus(savedOrder.getId(), result); // 짧은 트랜잭션
}

@Transactional
public Order saveOrder(Order order) {
    return orderRepository.save(order);
}
```

**실무 원칙:**
- 트랜잭션 안에 외부 API 호출 넣지 않기
- 트랜잭션 안에 긴 배치 작업 넣지 않기
- 트랜잭션 안에 사용자 입력 대기 금지

> **면접 예상 질문:** 외부 API 호출을 트랜잭션 안에 넣으면 왜 안 되는가?

---

### HikariCP 설정

Spring Boot의 기본 커넥션 풀은 **HikariCP**이다.

```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 10      # 최대 커넥션 수
      minimum-idle: 10           # 최소 유휴 커넥션 수
      connection-timeout: 30000  # 커넥션 대여 대기 시간 (ms)
      idle-timeout: 600000       # 유휴 커넥션 제거 시간 (ms)
      max-lifetime: 1800000      # 커넥션 최대 수명 (ms)
```

- `idle-timeout` / `max-lifetime`: 유휴/오래된 커넥션을 주기적으로 교체하여 장기 실행 환경에서의 메모리 누수나 DB 측 연결 끊김에 대응

**풀 크기 설정 가이드:**

| 상황 | 결과 |
|---|---|
| 너무 크면 | 메모리 낭비, DB 부담 |
| 너무 작으면 | 대기 발생, 처리량 저하 |

일반적 시작점: **CPU 코어 수 × 2 + 1** (PostgreSQL 공식 가이드)  
실무에서는 k6 같은 도구로 TPS와 P95 응답 시간을 측정하면서 최적값을 도출한다.

> **면접 예상 질문:** 커넥션 풀 크기는 어떻게 정하는가? HikariCP의 주요 설정 항목은?

---

## 학습 정리

- 커넥션 풀은 비용이 큰 DB 연결을 미리 만들어 재사용하는 기법
- 트랜잭션 범위 = 커넥션 점유 범위 → 트랜잭션을 짧게 유지해야 처리량 증가
- 외부 API 호출은 반드시 트랜잭션 밖으로 분리 → 커넥션 풀 고갈 방지
- HikariCP: Spring Boot 기본 커넥션 풀, `maximum-pool-size`와 타임아웃 설정이 핵심
- 풀 크기는 CPU × 2 + 1을 시작점으로 부하 테스트로 최적값 도출

## 참고

- CarrotSettle (Java, Spring Boot 4.0.x) 프로젝트 기반 학습
