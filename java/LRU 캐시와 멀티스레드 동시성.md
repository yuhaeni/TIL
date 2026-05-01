# LRU 캐시와 멀티스레드 동시성

> 날짜: 2026-05-01

## 내용

### 출발 — `LinkedHashMap` LRU의 한계

`LinkedHashMap(accessOrder=true)` + `removeEldestEntry()` 오버라이드는 LRU 캐시의 교과서 구현이다. 그러나 **초당 수만 read/write가 들어오는 멀티스레드 환경**에서는 그대로 못 쓴다.

**이유:** `LinkedHashMap`은 thread-safe ❌
- `get()`이 내부 양방향 연결 리스트의 노드를 tail로 이동시키는 **mutation**
- 두 스레드가 동시에 `get()` 하면 노드 포인터가 깨질 수 있음 → `NullPointerException`, 무한 루프 등

> **면접 예상 질문:** `LinkedHashMap`의 `accessOrder=true`는 왜 thread-safe하지 않은가?

---

### Thread-safe의 정확한 의미

**Thread-safe = 여러 스레드가 동시에 접근해도 데이터 무결성이 깨지지 않도록 보장.**

**비유 — 공용 화장실 🚻:**
- 잠금장치 없으면 → 두 사람 동시 진입 → 난리
- 잠금장치 있으면 → 한 명씩 안전하게 사용

**보장 수준 구분:**
- **race condition 없음** — 동시 수정에서도 일관성 유지
- **memory visibility** — 한 스레드의 변경이 다른 스레드에 보임
- **atomicity** — 복합 연산도 원자적

> **면접 예상 질문:** Thread-safe하다는 것은 정확히 무엇을 보장하는가?

---

### `Collections.synchronizedMap` — 전체 락의 함정

```java
Map<K, V> map = Collections.synchronizedMap(new LinkedHashMap<>(16, 0.75f, true));
```

**동작:** 모든 메서드에 `synchronized` 키워드를 붙여 **인스턴스 전체에 단일 모니터 락**을 건다.

**문제 — 락 경합(Lock Contention):**
- 1만 개 스레드 동시 접근 → **9,999개가 문 앞에서 대기**
- 락을 잡은 1개만 진행, 나머지는 직렬화됨
- → **병목(Bottleneck)** 발생, 처리량이 단일 스레드 수준으로 떨어짐

**언제 쓰나:** 동시성 빈도가 매우 낮거나 단순 임시 방편일 때만.

> **면접 예상 질문:** `Collections.synchronizedMap`이 락 경합을 일으키는 이유는? "병목"의 정체는?

---

### `ConcurrentHashMap` — 세그먼트 단위 락의 트레이드오프

`ConcurrentHashMap`은 **버킷 단위로 락을 잘게 쪼개** 락 경합을 최소화한다.

**Java 8 이후 동작:**
- **CAS(Compare-And-Swap)** + **버킷 단위 `synchronized`** 조합
- 다른 버킷에 접근하는 스레드끼리는 서로 대기 X
- Java 7까지의 Segment 락 방식에서 더 진화

**그러나 LRU엔 부적합 — 순서 보장 X:**
- `ConcurrentHashMap`은 **엔트리 순서를 모름**
- "가장 오래 안 쓴 것"을 찾을 수 없음 → LRU의 핵심 능력 상실
- 동시성은 얻었지만 LRU 의미를 잃은 **트레이드오프**

> **면접 예상 질문:** `ConcurrentHashMap`이 어떻게 락 경합을 줄이는가? 왜 LRU 캐시로 직접 쓰기엔 부족한가?

---

### Caffeine — 동시성 + LRU(W-TinyLFU)

**Caffeine** = Spring Boot의 기본 캐시 구현체로도 흔히 쓰이는 고성능 인메모리 캐시.

**핵심 특징:**
- 내부적으로 **`ConcurrentHashMap` 기반** → 동시성 안전
- 세그먼트 단위 락으로 락 경합 최소화
- 단순 LRU보다 똑똑한 **W-TinyLFU 알고리즘**
  - **W-TinyLFU = "최근성(Recency) + 빈도(Frequency)" 동시 고려**
  - "최근에 한 번만 썼지만 평소엔 안 쓰는 것"보다 "자주 쓰면서 최근에도 쓴 것"을 보존
  - Frequency Sketch(Count-Min Sketch)로 메모리 효율적 빈도 추적

**Spring Boot 사용 예:**
```java
@Bean
public CacheManager cacheManager() {
    CaffeineCacheManager mgr = new CaffeineCacheManager("settlements");
    mgr.setCaffeine(Caffeine.newBuilder()
        .maximumSize(10_000)
        .expireAfterWrite(Duration.ofMinutes(10)));
    return mgr;
}
```

> **면접 예상 질문:** Caffeine이 멀티스레드 환경에서 LRU에 적합한 이유는? W-TinyLFU는 일반 LRU와 어떻게 다른가?

---

### 자료구조 선택 비교표

| 선택지 | 동시성 | LRU 순서 | 비고 |
|---|---|---|---|
| `LinkedHashMap` | ❌ | ✅ | 단일 스레드 전용 |
| `Collections.synchronizedMap(LinkedHashMap)` | ⚠️ | ✅ | 전체 락 → 심한 경합 |
| `ConcurrentHashMap` | ✅ | ❌ | 순서 보장 X |
| **Caffeine** | ✅ | ✅ + 빈도까지 | W-TinyLFU + 버킷 락 |

**선택 기준:**
- 단일 스레드 / 학습용 → `LinkedHashMap`
- 동시성 거의 없음 / 임시 방편 → `synchronizedMap`
- 순서 무관한 단순 캐시 → `ConcurrentHashMap`
- **프로덕션 LRU 캐시 → Caffeine** (사실상 표준)

> **면접 예상 질문:** 4가지 선택지를 어떤 기준으로 비교하는가? 프로덕션에서는 무엇을 권장하는가?

---

### 면접 모범 답변 템플릿

> "`LinkedHashMap`은 LRU 순서를 보장하지만 thread-safe하지 않아 멀티스레드 환경에서는 사용할 수 없습니다.
>
> `Collections.synchronizedMap()`은 모든 메서드에 `synchronized` 키워드를 붙여 한 스레드가 객체를 사용하는 동안 나머지 스레드가 모두 대기하므로 **락 경합**이 발생합니다.
>
> `ConcurrentHashMap`은 버킷 단위로 락을 잘게 쪼개 락 경합을 최소화하지만, 엔트리 순서를 보장하지 않아 LRU 자체에는 부족합니다.
>
> 따라서 동시성과 LRU 순서를 모두 만족하려면 **Caffeine**을 사용합니다. Caffeine은 내부적으로 `ConcurrentHashMap`을 기반으로 동시성을 확보하고, **W-TinyLFU 알고리즘**으로 최근성과 빈도를 함께 고려해 단순 LRU보다 더 높은 적중률을 냅니다."

---

## 학습 정리

- `LinkedHashMap(accessOrder=true)`는 단일 스레드용 LRU — 동시 `get()`이 내부 연결 리스트를 깰 수 있음
- **Thread-safe** = 여러 스레드 동시 접근 시 데이터 무결성 보장 (race / visibility / atomicity)
- `Collections.synchronizedMap`은 **전체 락**으로 락 경합·병목 유발 → 처리량이 단일 스레드 수준
- `ConcurrentHashMap`은 **버킷 단위 락 + CAS**(Java 8)로 경합 최소화하지만 **순서 보장 X**
- **Caffeine** = ConcurrentHashMap 기반 동시성 + **W-TinyLFU**(최근성 + 빈도) → 프로덕션 LRU 사실상 표준
- **락 경합(Lock Contention)** 은 동시성 자료구조 선택의 핵심 평가 기준
- 자료구조 선택은 **"동시성 ↔ 순서 ↔ 적중률"** 트레이드오프

## 참고

- Caffeine 공식 문서 — W-TinyLFU
- Java Concurrency in Practice — Brian Goetz
- `java.util.concurrent.ConcurrentHashMap` 소스 (Java 8 CAS + bucket synchronized)
- 애플리케이션 캐시 전략(LRU) 학습 노트 후속
