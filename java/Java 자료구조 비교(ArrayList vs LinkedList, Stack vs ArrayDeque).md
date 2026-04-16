# Java 자료구조 비교

> 날짜: 2026-04-15

## 내용

### ArrayList vs LinkedList
<img width="439" height="427" alt="image" src="https://github.com/user-attachments/assets/d76dcbfc-ae49-4c06-b399-372035a493d4" />

실무에서 리스트가 필요할 때 대부분의 경우 `ArrayList`를 선택한다. 이론상 시간복잡도뿐 아니라 **CPU 캐시 지역성**까지 고려해야 실무 성능을 제대로 이해할 수 있다.

| | ArrayList | LinkedList |
|---|---|---|
| 내부 구조 | 동적 배열 | 이중 연결 리스트 |
| 메모리 배치 | 순차적(연속) | 비순차적(흩어짐) |
| 인덱스 접근 `get(i)` | O(1) | O(n) |
| 맨 뒤 추가 `add()` | O(1) amortized | O(1) |
| 중간 삽입/삭제 | O(n) (요소 이동) | O(1) (단, 탐색 O(n)) |

**CPU 캐시 지역성 관점:**
- `ArrayList`: 메모리에 연속적으로 저장 → 공간 지역성 활용 → **캐시 히트율 높음**
- `LinkedList`: 노드들이 메모리 여기저기 흩어짐 → **캐시 미스 빈번**

**"LinkedList가 삽입/삭제에 유리하다"는 반만 맞는 이유:**
- 삽입/삭제 연산 자체는 O(1) (노드 포인터만 변경)
- 하지만 **그 위치를 찾는 탐색이 O(n)**
- 결국 실무 대부분의 상황에서 `ArrayList`가 더 빠름

> **면접 예상 질문:** `ArrayList`와 `LinkedList`의 차이는? 실무에서 어떤 걸 선택하고 이유는?

---

### Stack vs ArrayDeque

`Stack` 클래스는 `Vector`를 상속받는다. `Vector`는 모든 메서드에 `synchronized`가 적용되어 있어, 단일 스레드 환경에서도 매번 불필요한 잠금/해제 비용이 발생한다.

```java
// Vector 클래스 주석
// "Unlike the new collection implementations, Vector is synchronized.
//  If a thread-safe implementation is not needed, it is recommended
//  to use ArrayList in place of Vector."
```

`synchronized`는 한 번에 한 스레드만 접근할 수 있도록 잠그는 메커니즘이다. 잠금/해제 과정 자체가 CPU 자원을 소비하므로, 단일 스레드 환경에서는 불필요한 오버헤드다.

**멀티스레드 환경에서의 선택:**

| 환경 | 권장 자료구조 |
|---|---|
| 단일 스레드 | `ArrayDeque` (빠르고 가벼움) |
| 멀티스레드 | `ConcurrentLinkedQueue`, `BlockingQueue` (`java.util.concurrent`) |

**Race Condition vs Deadlock:**
- **Race Condition**: 여러 스레드가 동시 접근하여 데이터가 꼬이는 상태
- **Deadlock**: 서로 자원을 기다리며 멈추는 상태

> **면접 예상 질문:** Java에서 Stack 대신 ArrayDeque를 권장하는 이유는? synchronized의 단점은?

---

### remove() vs poll()

둘 다 요소를 꺼내는(제거하는) 동작은 동일하지만, **빈 컬렉션일 때의 동작이 다르다.**

```java
// poll() - 빈 경우 null 반환
public E poll() {
    final Node<E> f = first;
    return (f == null) ? null : unlinkFirst(f);
}

// remove() - 빈 경우 예외 발생
public E remove() {
    return removeFirst();  // throws NoSuchElementException
}
```

**메서드 그룹별 정리:**

| 메서드 그룹 | 빈 컬렉션 시 동작 |
|---|---|
| `offer()` / `poll()` / `peek()` | null 반환 (안전, null 체크 필요) |
| `add()` / `remove()` / `element()` | 예외 발생 (예외 처리 필요) |

**실무 선택 기준:**
- 컬렉션이 비어있을 수 있는 상황 → `poll()` + null 체크
- 비어있으면 절대 안 되는(예상치 못한) 상황 → `remove()`로 빠른 실패(Fail-Fast)

즉, **예외가 예상된 흐름인지 vs 비정상 상황인지**에 따라 선택한다. `remove()`를 사용할 때는 전제 조건(precondition)을 반드시 보장해야 한다.

> **면접 예상 질문:** `remove()`와 `poll()`의 차이는? 각각 어떤 상황에서 사용하는가?

---

## 학습 정리

- 자료구조 선택 시 이론적 시간복잡도뿐 아니라 CPU 캐시 지역성까지 고려해야 실무 성능 이해 가능
- LinkedList의 삽입/삭제 O(1)은 탐색 O(n)을 포함하지 않아 실제론 느릴 수 있음
- `Stack`은 `Vector` 상속으로 단일 스레드에서도 불필요한 동기화 오버헤드 발생 → `ArrayDeque` 권장
- `poll()`은 null 반환, `remove()`는 예외 발생 → 상황에 따라 선택, 예외 사용 시 전제 조건 보장 필수

## 참고

- Java 공식 소스코드 (`LinkedList`, `Vector`, `ArrayDeque`)
