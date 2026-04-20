# LinkedHashMap과 Map.merge()

> 날짜: 2026-04-20

## 내용

### LinkedHashMap vs HashMap

`HashMap`과 `LinkedHashMap`의 결정적 차이는 **삽입 순서 보장 여부**다.

| | HashMap | LinkedHashMap |
|---|---|---|
| 삽입 순서 | 보장 X | 보장 O |
| 내부 구조 | 해시 버킷(배열 + 체이닝) | 해시 버킷 + **이중 연결 리스트** |
| 메모리 오버헤드 | 낮음 | prev/next 포인터만큼 증가 |

`LinkedHashMap`은 `HashMap`의 해시 버킷 위에 **이중 연결 리스트(doubly linked list)** 를 얹어서 삽입 순서를 별도로 기억한다. 해시 조회 성능은 그대로 유지하면서 iteration 시 삽입 순서를 보장한다.

> **면접 예상 질문:** `HashMap`과 `LinkedHashMap`의 차이는? `LinkedHashMap`은 어떤 원리로 삽입 순서를 보장하는가?

---

### HashMap 순서가 보장되지 않는 이유

`HashMap`에서 key의 저장 위치는 다음 공식으로 결정된다.

```
index = hashCode() % 배열크기  (실제로는 비트 마스킹 사용)
```

**순서가 불안정한 이유:**
- 요소가 늘어나면 내부 배열이 **리사이징(resizing)** 됨 (기본 부하율 0.75)
- 리사이징 시 모든 요소가 새 배열 크기에 맞게 재배치됨
- **같은 key라도 배열 크기에 따라 저장 위치가 달라짐** → iteration 순서 변동

Java 8 이후 특정 버킷의 체인이 길어지면 트리(Red-Black Tree)로 변환되는 최적화도 있어, 단순히 해시 순서로 도는 것도 아니다.

> **면접 예상 질문:** `HashMap`은 왜 삽입 순서가 보장되지 않는가? 리사이징이 순서에 어떤 영향을 주는가?

---

### accessOrder: 삽입 순서 vs 최근 사용 순서

`LinkedHashMap`은 `accessOrder` 플래그로 **순서 정책**을 선택할 수 있다.

```java
public LinkedHashMap() {
    super();
    accessOrder = false;  // 기본: 삽입 순서
}

// LRU 캐시용 생성자
public LinkedHashMap(int initialCapacity, float loadFactor, boolean accessOrder) {
    super(initialCapacity, loadFactor);
    this.accessOrder = accessOrder;
}
```

| accessOrder | 의미 |
|---|---|
| `false` (기본값) | **삽입 순서** — put한 순서대로 iteration |
| `true` | **접근 순서** — 최근 `get`/`put`된 것이 **가장 뒤로** 이동 → LRU 캐시 구현에 활용 |

`accessOrder = true`와 `removeEldestEntry()` 오버라이드를 조합하면 **LRU 캐시**를 손쉽게 만들 수 있다.

> **면접 예상 질문:** `LinkedHashMap`의 `accessOrder`는 무엇인가? LRU 캐시는 어떻게 구현하는가?

---

### Map.merge() 동작 원리

`Map.merge(key, value, remappingFunction)`는 **"키가 없으면 초기값, 있으면 누적"** 패턴을 한 줄로 표현한다.

**내부 구현:**
```java
default V merge(K key, V value, BiFunction<...> remappingFunction) {
    V oldValue = get(key);
    V newValue = (oldValue == null) ? value
                                    : remappingFunction.apply(oldValue, value);
    if (newValue == null) {
        remove(key);
    } else {
        put(key, newValue);
    }
    return newValue;
}
```

**동작 흐름:**
1. 기존 값이 `null`(키 없음) → 새 value를 그대로 put
2. 기존 값이 있으면 → `remappingFunction.apply(oldValue, value)` 결과로 덮어씀
3. 결과가 `null`이면 → 해당 key 제거

**활용 예시 — 정산 금액 집계:**
```java
Map<Seller, BigDecimal> amountBySeller = new LinkedHashMap<>();
for (OrderItem item : order.getOrderItems()) {
    Seller seller = item.getProduct().getSeller();
    amountBySeller.merge(seller, item.getSubtotal(), BigDecimal::add);
}
```

같은 seller의 여러 OrderItem 금액을 **누적 합산**한다.

> **면접 예상 질문:** `Map.merge()`는 어떻게 동작하는가? 언제 `null`을 반환하거나 key를 제거하는가?

---

### merge() vs getOrDefault() + put()

동일 로직을 두 방식으로 비교하면 가독성 차이가 뚜렷하다.

```java
// ❌ 장황한 방식
BigDecimal old = amountBySeller.getOrDefault(seller, BigDecimal.ZERO);
amountBySeller.put(seller, old.add(item.getSubtotal()));

// ✅ merge 방식 — "없으면 초기값, 있으면 누적" 패턴이 한눈에
amountBySeller.merge(seller, item.getSubtotal(), BigDecimal::add);
```

| 방식 | 코드 길이 | 가독성 | 초기값 분기 |
|---|---|---|---|
| `getOrDefault` + `put` | 2~3줄 | 낮음 | 명시 필요 |
| `merge` | 1줄 | 높음 | 자동 처리 |

실무에서 **카운팅(`merge(key, 1, Integer::sum)`) / 누적 합산** 같은 패턴에 자주 쓰인다.

> **면접 예상 질문:** `getOrDefault`보다 `merge`를 쓰면 좋은 이유는?

---

### 정산 코드에서 LinkedHashMap을 쓴 이유

```java
Map<Seller, BigDecimal> amountBySeller = new LinkedHashMap<>();
```

정산 로직에서 `HashMap`이 아닌 `LinkedHashMap`을 선택한 이유:

- **결과의 일관성(reproducibility)** — 같은 주문으로 `buildSettlements()`를 여러 번 호출해도 결과 리스트 순서가 동일
- **테스트 안정성** — 순서 기반 assertion(`assertThat(settlements).containsExactly(...)`)이 환경에 관계없이 성공
- **디버깅 용이성** — 로그에 찍히는 순서가 일관되어 추적 쉬움

성능이 조금 손해더라도, **결정적인(deterministic) 출력**이 더 중요한 비즈니스 로직에서는 `LinkedHashMap`이 안전한 선택이다.

> **면접 예상 질문:** 비즈니스 로직에서 `HashMap` 대신 `LinkedHashMap`을 선택하는 기준은?

---

## 학습 정리

- `LinkedHashMap`은 **HashMap + 이중 연결 리스트**로 삽입 순서 보장, 해시 조회 성능은 그대로
- `HashMap`은 `hashCode() % 배열크기` + 리사이징 때문에 같은 key라도 위치가 달라져 순서 불안정
- `accessOrder = true` + `removeEldestEntry()` 조합으로 LRU 캐시 구현 가능
- `Map.merge()`는 "없으면 초기값, 있으면 누적" 패턴을 한 줄로 표현 — 카운팅/합산에 유용
- 테스트 안정성과 재현 가능성이 중요한 로직에서는 `LinkedHashMap`이 안전한 기본 선택

## 참고

- CarrotSettle (Java, Spring Boot 4.0.x) 정산 로직 기반 학습
- Java `java.util.LinkedHashMap` 공식 문서
- Java `java.util.Map#merge` 공식 문서
