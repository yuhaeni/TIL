# Kafka DLT 전송 흐름 — DLQ vs DLT, DeadLetterPublishingRecoverer, KafkaTemplate, 재시도 트레이드오프

> 날짜: 2026-07-27

## 내용

### DLQ vs DLT — 같은 개념, 담기는 그릇 이름만 다르다

처리에 실패한 메시지를 그냥 버리지 않고 **따로 모아두는 실패 전용 목적지**를 가리키는 개념은 하나다. 그런데 이름이 두 개라 헷갈린다.

- **DLQ (Dead Letter Queue)**: 원래 RabbitMQ, AWS SQS 같은 **큐(Queue) 기반** 메시징 시스템에서 나온 용어.
- **DLT (Dead Letter Topic)**: 카프카는 저장 단위가 큐가 아니라 **토픽(Topic)** 이라서, 같은 개념을 토픽에 맞춰 부르는 이름.

즉 **개념은 동일**하고, 담기는 그릇(큐냐 토픽이냐)의 이름을 따라간 것뿐이다. 카프카 문맥에서 정확한 표현은 **DLT**이고, 보통 `원본토픽.DLT` 형태로 이름 짓는다. DLT에 쌓인 메시지는 이후 원인 분석·재처리에 쓴다.

> **면접 예상 질문:** DLQ와 DLT는 무엇이 같고 무엇이 다른가? 카프카에서 DLT라고 부르는 이유를 저장 단위 관점에서 설명하라.

---

### DeadLetterPublishingRecoverer — 이름을 뜯어보면 역할이 보인다

이름을 세 조각으로 나누면 역할이 그대로 드러난다: **DeadLetter + Publishing + Recoverer**.

- **DeadLetter**: 실패한 메시지를
- **Publishing(발행)**: DLT로 발행(publish)하는
- **Recoverer(복구자)**: 복구 담당 객체

여기서 핵심은 **"Publishing"** 이다. 카프카에서 토픽으로 메시지를 발행하는 건 원래 **Producer** 담당인데, 이 Recoverer는 **Consumer 쪽에서 동작**한다. 그래서 DLT로 보내려면 내부에 **발행 도구를 하나 품고 있어야** 한다 → 그게 바로 **`KafkaTemplate`** 이다.

`DeadLetterPublishingRecoverer`는 생성될 때 `KafkaTemplate`을 주입받아 들고 있다가, 실패 메시지를 이 템플릿으로 DLT에 다시 발행한다. 즉 **소비(Consumer)하다가 실패하면 다시 생산(Producer)해서 DLT로 보내는** 구조다.

> Producer / Consumer / Listener 3형제 복습:
> - **Producer**: 메시지 발행
> - **Consumer**: 브로커에서 메시지를 당겨오는(poll) 소비하는 쪽 전체
> - **Listener(`@KafkaListener`)**: 가져온 메시지를 받아 처리하는 내 코드. Consumer가 Listener를 불러준다.

> **면접 예상 질문:** DeadLetterPublishingRecoverer는 Consumer 쪽에서 동작하는데 어떻게 DLT로 메시지를 발행할 수 있는가? 내부에 무엇을 품고 있는가?

---

### recoverer 콜백 — DefaultErrorHandler가 "마지막에" 부르는 함수

`recoverer`는 에러 핸들러(`DefaultErrorHandler`)가 **재시도를 다 해봤는데도 끝내 실패하면 마지막에 호출하는 콜백**이다. 스프링 카프카에서 이 콜백 자리는 `ConsumerRecordRecoverer`라는 함수형 인터페이스로 정의돼 있고, `DeadLetterPublishingRecoverer`는 그 자리에 꽂아 넣는 **구현체 중 하나**다.

즉 관계를 정리하면:

- `DefaultErrorHandler` = "재시도할지 / 언제 포기할지"를 관장하는 에러 핸들러
- `recoverer` = 포기 시점에 실행되는 마지막 콜백(인터페이스)
- `DeadLetterPublishingRecoverer` = 그 콜백의 구현체 = "포기하면 DLT로 보내자"

recoverer를 다른 구현으로 바꾸면 "포기 시 로그만 남기기", "DB에 적재" 등으로 뒤처리를 갈아끼울 수 있다 (전략 교체).

> **면접 예상 질문:** DefaultErrorHandler에서 recoverer 콜백은 언제 호출되며, DeadLetterPublishingRecoverer는 이 콜백과 어떤 관계인가?

---

### 전체 전송 흐름 — 역직렬화 실패부터 DLT 적재까지

앞서 배운 ErrorHandlingDeserializer / checkDeser와 이어붙이면 전체 그림이 완성된다.

```
① ErrorHandlingDeserializer → 예외를 헤더에 심음 (value=null, 무한루프 1차 차단)
② checkDeser()             → 리스너 호출 직전, 헤더 보고 예외 되던짐
③ DefaultErrorHandler       → 재시도... 재시도... (BackOff 간격으로)
④ 재시도 소진 → recoverer 호출 → DeadLetterPublishingRecoverer
⑤ 내부 KafkaTemplate으로 원본 메시지를 "원본토픽.DLT"에 발행
⑥ 원본 오프셋 커밋 → 컨슈머는 다음 메시지로 진행 (무한루프 완전 탈출)
```

핵심은 **⑥ 오프셋 커밋**이다. 실패 메시지를 DLT로 안전하게 옮겨두었으니, 원본 파티션의 오프셋을 넘겨도 유실 걱정이 없다. → 파티션이 다시 흐른다.

> **면접 예상 질문:** 역직렬화 실패 메시지가 DLT에 적재되고 원본 오프셋이 커밋되기까지의 전체 컴포넌트 흐름을 순서대로 설명하라.

---

### 재시도 트레이드오프 — 일시적 실패 vs 영구적 실패

recoverer를 부르기 전에 "재시도를 몇 번 할지"가 중요한 설계 포인트다. 실패에는 성격이 다른 두 종류가 있기 때문이다.

| 실패 종류 | 재시도하면? | 예시 |
| --- | --- | --- |
| **일시적(transient)** | 성공 가능성 O → 재시도 가치 있음 | 네트워크 순단, DB 커넥션 일시 부족, 다운스트림 잠깐 다운 |
| **영구적(permanent)** | 몇 번을 해도 100% 또 실패 | 역직렬화 실패(깨진 JSON), 스키마 불일치 |

- **역직렬화 실패(Poison Pill)** 는 대표적인 **영구적 실패**다. 같은 바이트를 100번 다시 읽어도 또 깨진다. 이런 건 재시도가 낭비일 뿐 아니라, 그동안 파티션이 멈춰있어 **오히려 해롭다** → 즉시 DLT로 보내야 한다.
- 반대로 **일시적 오류**는 몇 번 기다렸다(BackOff) 재시도하면 살아날 수 있으니 바로 버리면 손해다.

그래서 `DefaultErrorHandler`는 이를 구분하는 도구를 제공한다:

- **`BackOff`**: 재시도 횟수와 간격 설정 (예: `FixedBackOff(1000L, 3)` = 1초 간격 3회).
- **`addNotRetryableExceptions(...)`**: "이 예외는 재시도하지 말고 바로 recoverer(→DLT)로" 분류. 역직렬화 예외처럼 영구적 실패를 여기에 등록한다.

즉 "일시적 실패는 몇 번 재시도, 영구적 실패는 즉시 DLT"라는 정책을 예외 종류별로 다르게 가져가는 것이 실무 설계다.

> **면접 예상 질문:** 모든 실패를 똑같이 N번 재시도하면 안 되는 이유는 무엇인가? 일시적 실패와 영구적 실패를 어떻게 구분해 다르게 처리하는가?

---

## 학습 정리

- DLQ와 DLT는 "실패 메시지를 버리지 않고 모아두는 목적지"라는 동일 개념이며, 큐 기반은 DLQ, 카프카(토픽)는 DLT라 부른다 (`원본토픽.DLT`).
- `DeadLetterPublishingRecoverer` = DeadLetter를 Publishing하는 Recoverer. 발행은 Producer 담당이므로 내부에 **`KafkaTemplate`** 을 품고 DLT로 다시 발행한다 → 소비하다 실패하면 다시 생산.
- `recoverer`는 `DefaultErrorHandler`가 **재시도를 모두 소진한 뒤 마지막에 부르는 콜백**(`ConsumerRecordRecoverer`)이고, `DeadLetterPublishingRecoverer`는 그 구현체다.
- 전체 흐름: ErrorHandlingDeserializer(헤더) → checkDeser(되던짐) → DefaultErrorHandler(재시도) → recoverer → KafkaTemplate으로 DLT 발행 → **원본 오프셋 커밋**으로 파티션 재개.
- 실패는 일시적(재시도 가치 O) vs 영구적(역직렬화 등, 즉시 DLT)으로 나뉜다. `BackOff`로 재시도 정책을, `addNotRetryableExceptions()`로 즉시 DLT 대상을 지정한다.

## 참고

- (없음)
