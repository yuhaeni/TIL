# ErrorHandlingDeserializer와 Poison Pill — 역직렬화, Consumer/Listener, checkDeser, DefaultErrorHandler, DLQ

> 날짜: 2026-07-27

## 내용

### 직렬화/역직렬화 — Kafka는 메시지를 byte[]로 저장한다

Kafka 브로커는 메시지를 byte[]로 저장한다. 내용이 JSON이든 이미지든 브로커는 신경 쓰지 않는다. 그래서 컨슈머는 받은 바이트를 다시 Java 객체로 바꿔야 하는데, 이 변환을 담당하는 게 Deserializer다.

- 직렬화(serialize): Java 객체 → byte[]
- 역직렬화(deserialize): byte[] → Java 객체

Deserializer 구현체로는 `StringDeserializer`, `JsonDeserializer` 등이 있다. **역직렬화는 `poll()` 시점에 일어난다** — 브로커에서 byte[]를 당겨오면서 바로 객체로 바꾼다. 즉 리스너 메서드에 도착하기 **전** 단계다.

> **면접 예상 질문:** Kafka 브로커는 메시지를 어떤 형태로 저장하며, 직렬화/역직렬화는 각각 어느 시점에 일어나는가?

---

### Consumer vs Listener vs ListenerConsumer — 이름이 헷갈리는 3형제

Producer, Consumer, Listener를 헷갈리기 쉽고, 여기에 `ListenerConsumer`까지 끼면 더 헷갈린다. 역할이 전부 다르다.

| 이름 | 역할 |
| --- | --- |
| Producer | 메시지 발행 |
| Consumer(`KafkaConsumer`) | 브로커랑 실제로 통신하며 메시지를 당겨오는 카프카 클라이언트 객체 |
| `ListenerConsumer` | Spring Kafka가 내부에서 자동 생성하는 **관리자**. poll·역직렬화·checkDeser·리스너 호출·오프셋 커밋을 지휘 |
| `@KafkaListener` | 내가 짠 코드. "메시지 하나 오면 뭘 할지"만 담당하는 비즈니스 로직 |

핵심은 **리스너(내 코드)와 리스너 컨슈머(관리자)는 다른 객체**라는 점이다. 비유하면 리스너는 재료가 오면 요리만 하는 **요리사**, `ListenerConsumer`는 재료를 날라다 주고 상한 재료를 걸러내고 다음 주문을 받는 **홀 매니저**다.

```
ListenerConsumer (매니저: poll · 역직렬화 · checkDeser · 커밋)
        │  나를 대신 호출해줌
        ▼
@KafkaListener consume()   (요리사: 내 코드, 비즈니스 로직만)
```

`ListenerConsumer`는 컨테이너가 시작되면 **자기 전용 스레드**에서 무한 루프(`run()`)를 돌린다.

```
while (실행 중) {
    records = consumer.poll(timeout);   // ← 브로커에서 당겨옴 (역직렬화도 여기서!)
    for (record : records) {
        checkDeser(record);             // ← 헤더 검문소
        invokeListener(record);         // ← @KafkaListener 메서드 호출
    }
    commitOffsets();                    // ← 오프셋 커밋
}
```

> **면접 예상 질문:** `@KafkaListener`(리스너)와 `ListenerConsumer`는 각각 무슨 역할이며, `poll()`을 실제로 호출하는 주체는 누구인가?

---

### Poison Pill — 역직렬화 예외는 리스너가 잡지 못한다

처리 순서는 `poll()` → 역직렬화 → 리스너 호출이다. 역직렬화 예외는 리스너에 도착하기 전 단계(poll 시점)에서 발생하므로, 리스너 안의 `try-catch`로는 잡을 수 없다. **요리사(리스너)는 재료(메시지)를 받아보지도 못했기 때문**이다.

더 큰 문제는 오프셋이다. Consumer는 처리한 위치를 오프셋으로 커밋하는데, 역직렬화가 계속 실패하면 오프셋이 넘어가지 못한다. 그러면 같은 메시지를 다시 읽고 또 실패하는 무한 재시도에 빠진다.

```
같은 오프셋 읽기 → 역직렬화 실패 → 재시도 → 또 실패 → ...
```

이렇게 Consumer를 멈추게 만드는 깨진 메시지를 Poison Pill이라고 부른다. 이 메시지 하나 때문에 파티션 전체가 멈추고, 뒤에 쌓인 정상 메시지들도 처리되지 못한다.

> **면접 예상 질문:** 역직렬화 예외를 리스너의 try-catch로 잡을 수 없는 이유는 무엇이며, Poison Pill이 컨슈머를 마비시키는 과정을 오프셋 관점에서 설명하라.

---

### ErrorHandlingDeserializer — 예외를 "삼켜서" 헤더에 지연시킨다

`ErrorHandlingDeserializer`는 Spring Kafka가 제공하는 클래스라 직접 구현할 필요가 없다. 직접 역직렬화하는 게 아니라, 실제 Deserializer(`JsonDeserializer` 등)를 감싸는 **wrapper**다 (데코레이터 패턴). 그래서 설정할 때 "실제 일꾼이 누구인지"를 위임 대상으로 지정해줘야 한다 (`VALUE_DESERIALIZER_CLASS`).

`deserialize()` 내부에서 일어나는 일을 코드 흐름으로 보면:

1. 내부 위임 대상(`delegate`)의 `deserialize()`를 **try 블록** 안에서 호출한다.
2. 예외가 나면 **catch**로 잡는다 → 밖으로 전파 X → **무한루프 1차 차단**.
3. 리스너로 넘어갈 value는 **`null`로 반환**한다.
4. 대신 잡은 예외 객체를 `ConsumerRecord`의 **헤더(header)** 에 심어둔다 (`ErrorHandlingDeserializer.VALUE_DESERIALIZER_EXCEPTION_HEADER` 같은 키).

즉 "다른 값"의 정체는 → **value=null + 예외 정보는 헤더에 백업**이다. 그냥 null만 넘기면 리스너 입장에서 "원래 null 데이터인지, 역직렬화 실패로 null인지" 구분할 수 없고 실패 원인(어떤 예외가, 어떤 원본에서)이 사라진다. 그래서 원인을 헤더에 실어 다음 단계로 배달하는 것이다.

> **면접 예상 질문:** ErrorHandlingDeserializer는 예외를 잡은 뒤 value와 예외 정보를 각각 어떻게 처리하는가? 왜 value를 그냥 null로만 넘기지 않고 예외를 헤더에 담는가?

---

### checkDeser() — 안전지점에서 예외를 되살리는 검문소

value=null·헤더에 예외만 실린 record가 흘러가면, 누군가 이걸 리스너 도착 직전에 "예외 헤더가 있네? 다시 던져!" 하고 되살려야 한다. 이 역할이 `ListenerConsumer` 내부 메서드 **`checkDeser()`** 다.

1. 컨테이너가 `poll()`로 record들을 받음 (`ErrorHandlingDeserializer`가 예외를 헤더에 심어둔 상태).
2. 리스너 호출 **직전**, record마다 `checkDeser()`를 돈다.
3. `checkDeser()`는 `SerializationUtils.getExceptionFromHeader()`로 예외 헤더가 있는지 확인한다.
4. 있으면 → 그 자리에서 예외를 **다시 던진다(re-throw)**.
5. 던져진 예외 → 리스너는 호출조차 안 되고 → **`DefaultErrorHandler`가 발동**.

**핵심 통찰 — "예외를 없애는 게 아니라 던지는 위치를 재배치한다".**

| 시나리오 | 예외가 터지는 위치 | 결과 |
| --- | --- | --- |
| `ErrorHandlingDeserializer` **없음** | `poll()` 그 자리 (raw) | `DefaultErrorHandler` 관리 범위 **밖** → 오프셋 못 넘김 → **무한루프** |
| `ErrorHandlingDeserializer` **있음** | 지연됐다가 `checkDeser()`에서 재던짐 | `DefaultErrorHandler` 관리 범위 **안** → 실패 처리·오프셋 진행 → **탈출** |

`ErrorHandlingDeserializer`가 하는 일의 본질은 → **관리 범위 밖(poll)에서 터질 예외를, 관리 범위 안(checkDeser 직전)에서 터지도록 위치를 옮겨주는 것**이다.

> **면접 예상 질문:** ErrorHandlingDeserializer가 예외를 헤더에 담아 지연시키는 이유를, "예외가 터지는 위치"와 "그 예외를 잡을 수 있는 주체" 관점에서 설명하라.

---

### DefaultErrorHandler & DLQ/DLT — 실패한 메시지를 버리기 전에 보관한다

`checkDeser()`가 예외를 되살리면 리스너 컨테이너에 꽂힌 **에러 핸들러(`CommonErrorHandler`, 기본 구현 `DefaultErrorHandler`)** 가 문제 record를 넘겨받아 **재시도 / 버림 / DLQ 전송**을 결정한다. 즉 `ErrorHandlingDeserializer`(헤더에 심기) → `checkDeser()`(되던지기) → `DefaultErrorHandler`(뒤처리)로 이어지는 **릴레이 짝꿍** 관계다. 둘은 바꾸는 관계가 아니라 서로를 보완한다.

깨진 메시지를 그냥 버리면 나중에 추적이 불가능하다. 정산처럼 유실이 곧 사고인 도메인에서는 특히 위험하다. 그래서 실패 원본 메시지를 별도 토픽에 보관하는데, 이 전용 토픽이 **DLQ(Dead Letter Queue) / DLT(Dead Letter Topic)** 다. 보통 `원본토픽.DLT` 형태로 이름 짓고, Spring Kafka에서는 `DeadLetterPublishingRecoverer`가 실패 메시지를 DLT로 보낸다. DLT에 쌓인 메시지는 이후 원인 분석·재처리에 쓴다.

전체 그림:

```
브로커 ─poll()─▶ ListenerConsumer (매니저)
                     │
                     ├─ 역직렬화: ErrorHandlingDeserializer
                     │     ├─ 성공 → 정상 객체
                     │     └─ 실패 → value=null + 예외를 헤더에 백업 (무한루프 1차 차단)
                     │
                     ├─ checkDeser(): 헤더에 예외 있으면 → 다시 던짐
                     │
                     ├─ (예외 없으면) @KafkaListener 호출  ← 내 코드
                     │
                     └─ 실패 record → DefaultErrorHandler → 재시도 / DLQ(DLT) 전송
```

> **면접 예상 질문:** ErrorHandlingDeserializer와 DefaultErrorHandler는 각각 어느 단계에서 무슨 일을 하며, 왜 둘이 함께 있어야 Poison Pill이 DLT까지 안전하게 도달하는가?

---

## 학습 정리

- Kafka 브로커는 메시지를 byte[]로 저장하고, 역직렬화는 `poll()` 시점(리스너 도착 전)에 일어난다.
- 역직렬화 예외는 리스너 도착 전에 터지므로 리스너 try-catch로 못 잡고, 오프셋이 안 넘어가 무한 재시도에 빠지는 깨진 메시지가 Poison Pill이다.
- `ListenerConsumer`(스프링이 만드는 관리자)와 `@KafkaListener`(내 코드)는 다른 객체다. poll을 돌리고 오프셋을 커밋하는 건 `ListenerConsumer`다.
- `ErrorHandlingDeserializer`는 실제 Deserializer를 감싸(wrapper) 예외를 catch하고, value=null + 예외를 헤더에 백업해 무한루프를 1차 차단한다.
- `checkDeser()`가 리스너 직전에 헤더를 검사해 예외를 되던지고, 그때서야 `DefaultErrorHandler` 관리 범위 안으로 들어와 DLQ/DLT 전송이 가능해진다. → 본질은 "예외를 없애는 게 아니라 던지는 위치를 안전지점으로 재배치".
- 실패 원본은 `DeadLetterPublishingRecoverer`가 DLT(`원본토픽.DLT`)로 보내 이후 분석·재처리한다.

## 참고

- (없음)
