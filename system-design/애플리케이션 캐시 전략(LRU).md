# 애플리케이션 캐시 전략(LRU)

> 날짜: 2026-04-15

## 내용

### LRU 캐시 구현: LinkedList vs LinkedHashMap

LRU(Least Recently Used) 캐시를 구현할 때 자료구조 선택이 핵심이다.

| | `LinkedList` | `LinkedHashMap` |
|---|---|---|
| `contains()` / `containsKey()` | **O(n)** (first부터 순차 탐색) | **평균 O(1)** (해시로 배열 인덱스 바로 접근) |
| 순서 제어 | 직접 관리 | `accessOrder=true`로 자동 제어 |

**LinkedList가 O(n)인 이유:**
```java
// LinkedList.contains() - first부터 next로 순차 탐색
for (Node<E> x = first; x != null; x = x.next) {
    if (o.equals(x.item)) return index;
}
```

**LinkedHashMap이 평균 O(1)인 이유:**
```java
// HashMap.getNode() - 해시 계산 후 배열 인덱스로 바로 접근
first = tab[(n - 1) & hash(key)];  // O(1) 배열 접근
```

`accessOrder=true`로 설정하면 `get()`/`put()` 시 접근한 엔트리가 **맨 뒤(tail)** 로 이동한다. 맨 앞(head)이 가장 오래 사용하지 않은 것 → LRU 정책에 그대로 부합한다.

```java
LinkedHashMap<String, String> cache = new LinkedHashMap<>(capacity, 0.75f, true) {
    @Override
    protected boolean removeEldestEntry(Map.Entry<String, String> eldest) {
        return size() > capacity; // 용량 초과 시 가장 오래된 엔트리 자동 제거
    }
};
```

> **면접 예상 질문:** LRU 캐시를 `LinkedList`와 `LinkedHashMap` 중 어떤 자료구조로 구현할 것인가? 이유는?

---

### 캐시 쓰기 전략과 데이터 정합성

캐시를 도입하면 캐시 데이터와 DB 데이터가 달라지는 **데이터 정합성(일관성) 문제**가 발생할 수 있다. 원본(DB)이 바뀌었는데 캐시가 업데이트되지 않으면, 사용자는 **오래된 데이터(Stale Data)** 를 보게 된다.

#### Write-Through (동기 쓰기)

DB와 캐시를 **동시에** 업데이트한다.

- **장점**: 데이터 정합성이 항상 보장됨
- **단점**: 매 쓰기마다 두 곳이 모두 완료될 때까지 대기 → **쓰기 지연(Write Latency)** 발생
- **적합한 상황**: 정합성이 최우선인 금융, 결제 시스템

#### Write-Behind (비동기 쓰기, Write-Back)

캐시에만 먼저 저장하고, DB는 **나중에 비동기**로 반영한다.

- **장점**: 쓰기 성능이 매우 빠름
- **단점**: DB 반영 전에 서버가 죽으면 **데이터 유실** 위험
- **적합한 상황**: 쓰기 성능이 최우선이고 일부 데이터 유실을 허용할 수 있는 경우

#### Cache-Aside (Lazy Loading)

애플리케이션이 직접 캐시를 관리한다.

- **읽기**: 캐시 확인 → 없으면 DB 조회 → 캐시에 저장 → 반환
- **쓰기**: DB 업데이트 + 캐시 무효화(Invalidate)
- **장점**: 구현이 단순, 캐시 장애가 DB에 전파되지 않음
- **단점**: 초기엔 캐시가 비어있어 miss가 많고 DB 부하가 커지는 **Cold Start 문제**

**트레이드오프 비교:**

| 전략 | 쓰기 성능 | 정합성 | 위험 |
|---|---|---|---|
| Write-Through | 느림 | 강함 | 쓰기 지연 |
| Write-Behind | 빠름 | 약함 | 데이터 유실 |
| Cache-Aside | 보통 | 보통 | Cold Start |

캐시 전략은 "무엇이 최선"이 아니라 **서비스 특성에 따른 트레이드오프**의 문제다.

> **면접 예상 질문:** 캐시 도입 시 발생할 수 있는 문제는? Write-Through, Write-Behind, Cache-Aside의 트레이드오프를 비교하시오.

---

## 학습 정리

- LRU 구현 시 `containsKey()` O(1)을 활용하려면 `LinkedHashMap` (accessOrder=true) 선택
- `LinkedHashMap`은 해시 기반 O(1) 접근 + 접근 순서 자동 관리로 LRU에 최적
- Write-Through: 정합성 강함, 쓰기 느림 / Write-Behind: 쓰기 빠름, 유실 위험 / Cache-Aside: 단순하지만 Cold Start
- 면접에서는 전략 선택의 이유 + 대안 검토 과정을 설명할 수 있어야 함

## 참고

- LRU 캐시 구현 문제 풀이 기반 학습
