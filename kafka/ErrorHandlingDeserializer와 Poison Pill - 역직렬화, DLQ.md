# ErrorHandlingDeserializer와 Poison Pill — 역직렬화, Consumer/Listener, DLQ

> 날짜: 2026-07-15

## 내용

### 직렬화/역직렬화 — Kafka는 메시지를 byte[]로 저장한다

Kafka 브로커는 메시지를 byte[]로 저장한다. 내용이 JSON이든 이미지든 브로커는 신경 쓰지 않는다. 그래서 컨슈머는 받은 바이트를 다시 Java 객체로 바꿔야 하는데, 이 변환을 담당하는 게 Deserializer다.

- 직렬화(serialize): Java 객체 → byte[]
- 역직렬화(deserialize): byte[] → Java 객체

Deserializer 구현체로는 `StringDeserializer`, `JsonDeserializer` 등이 있다.

> **면접 예상 질문:** Kafka 브로커는 메시지를 어떤 형태로 저장하며, 직렬화/역직렬화는 각각 어느 시점에 일어나는가?

---

### Consumer vs Listener

Producer, Consumer, Listener를 헷갈리기 쉬운데 역할이 다르다.

| 이름 | 역할 |
| --- | --- |
| Producer | 메시지 발행 |
| Consumer | 브로커에서 메시지를 가져와 소비 |
| `@KafkaListener` | Consumer가 넘겨준 메시지를 처리하는 우리 코드 |

Consumer가 `poll()`로 바이트를 가져오고, 역직렬화한 뒤, `@KafkaListener` 메서드를 호출한다. 즉 Consumer가 Listener를 감싸는 구조다. Consumer는 메시지를 발행하는 쪽이 아니라 소비하는 쪽이라는 점만 확실히 하면 된다.

> **면접 예상 질문:** Producer, Consumer, `@KafkaListener`는 각각 어떤 역할을 하며 서로 어떤 포함 관계인가?

---

### Poison Pill — 역직렬화 예외는 리스너가 잡지 못한다

처리 순서는 `poll()` → 역직렬화 → 리스너 호출이다. 역직렬화 예외는 리스너에 도착하기 전 단계에서 발생하므로, 리스너 안의 `try-catch`로는 잡을 수 없다.

더 큰 문제는 오프셋이다. Consumer는 처리한 위치를 오프셋으로 커밋하는데, 역직렬화가 계속 실패하면 오프셋이 넘어가지 못한다. 그러면 같은 메시지를 다시 읽고 또 실패하는 무한 재시도에 빠진다.

```
같은 오프셋 읽기 → 역직렬화 실패 → 재시도 → 또 실패 → ...
```

이렇게 Consumer를 멈추게 만드는 깨진 메시지를 Poison Pill이라고 부른다. 이 메시지 하나 때문에 뒤에 쌓인 정상 메시지들도 처리되지 못한다.

> **면접 예상 질문:** 역직렬화 예외를 리스너의 try-catch로 잡을 수 없는 이유는 무엇이며, Poison Pill이 컨슈머를 마비시키는 과정을 오프셋 관점에서 설명하라.

---

### ErrorHandlingDeserializer — 실제 Deserializer를 감싸는 wrapper

`ErrorHandlingDeserializer`는 Spring Kafka가 제공하는 클래스라 직접 구현할 필요가 없다. 직접 역직렬화하는 게 아니라, 실제 Deserializer(`JsonDeserializer` 등)를 감싸는 wrapper다.

설정에서 "실제 Deserializer는 JsonDeserializer를 쓰고, 그걸 ErrorHandlingDeserializer로 감싼다"고 지정하면 된다. 동작은 다음과 같다.

- 안쪽 Deserializer가 예외를 던지면 ErrorHandlingDeserializer가 대신 잡는다
- 예외를 다시 던지지 않고, 리스너에는 `null`을 넘긴다
- Consumer는 멈추지 않고 오프셋을 넘겨 다음 메시지를 계속 처리한다

> **면접 예상 질문:** ErrorHandlingDeserializer는 직접 구현하는가? 내부적으로 예외를 어떻게 처리해서 컨슈머가 멈추지 않게 하는가?

---

### DLQ / DLT — 실패한 메시지를 버리기 전에 보관한다

깨진 메시지를 그냥 버리면 나중에 추적이 불가능하다. 정산처럼 유실이 곧 사고인 도메인에서는 특히 위험하다. 그래서 보통 두 단계로 나눈다.

1. 예외를 다시 던지지 않아 Consumer는 계속 진행한다
2. 실패한 원본 메시지는 별도 토픽에 보관한다

이 실패 메시지 전용 토픽이 DLQ(Dead Letter Queue) 또는 DLT(Dead Letter Topic)다. 보통 `원본토픽.DLT` 형태로 이름을 짓고, Spring Kafka에서는 `DeadLetterPublishingRecoverer`가 실패 메시지를 DLT로 보내주는 역할을 한다. DLT에 쌓인 메시지는 이후에 원인 분석이나 재처리에 쓴다.

> **면접 예상 질문:** 처리 실패한 메시지를 그냥 버리지 않고 DLT로 보내는 이유는 무엇이며, Spring Kafka에서 이를 담당하는 컴포넌트는 무엇인가?

---

## 학습 정리

- Kafka 브로커는 메시지를 byte[]로 저장하고, 컨슈머가 이를 Java 객체로 바꾸는 게 역직렬화(Deserializer)다.
- 처리 순서는 `poll → 역직렬화 → 리스너`라서, 역직렬화 예외는 리스너 도착 전에 발생해 리스너 try-catch로 잡지 못한다.
- 오프셋이 넘어가지 못해 무한 재시도로 컨슈머를 멈추게 하는 깨진 메시지가 Poison Pill이다.
- ErrorHandlingDeserializer(Spring 제공)는 실제 Deserializer를 감싸 예외를 대신 잡고, 리스너에 null을 넘겨 컨슈머를 계속 진행시킨다.
- 실패 원본은 DLQ/DLT로 보내 이후 분석·재처리한다 (`DeadLetterPublishingRecoverer`).

## 참고

- (없음)
