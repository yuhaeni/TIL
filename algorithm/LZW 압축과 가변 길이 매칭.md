# LZW 압축과 가변 길이 매칭

> 날짜: 2026-04-27

## 내용

### LZW 알고리즘 핵심 — 가변 길이 매칭

LZW(Lempel-Ziv-Welch) 압축은 **반복되는 패턴을 사전(dictionary)에 등록**해 색인으로 치환하는 방식이다. 카카오 2018 블라인드 3차 "압축" 문제의 본질.

**알고리즘 흐름:**
1. 길이 1 단어로 사전 초기화 (A=1, B=2, ..., Z=26)
2. **사전에 있는 가장 긴 w** 찾기 (한 글자씩 늘려가며)
3. w의 색인 출력, `w+c`를 사전에 등록
4. 다음 시작 위치는 `i += w.length()` (소비된 만큼 점프)
5. 마지막 글자는 더 늘릴 수 없으니 그냥 출력하고 종료

**핵심 패턴 — 안쪽 while로 가변 확장:**
```java
int i = 0;
while (i < msg.length()) {
    String w = msg.substring(i, i + 1);
    int j = 1;
    while (dict.get(w) != null) {
        if (i + j >= msg.length()) {
            out.add(dict.get(w));
            break;
        }
        String c = msg.substring(i + j, i + j + 1);
        if (dict.get(w + c) == null) {
            out.add(dict.get(w));
            dict.put(w + c, dict.size() + 1);
            break;
        }
        w = w + c;
        j++;
    }
    i += w.length();
}
```

**왜 가변 길이인가?**
- `substring(i, i+2)` 같은 **고정 길이 접근 ❌**
- 변수 분리: `w`(매칭된 부분), `c`(다음 글자)
- 종료 조건 두 가지:
  - `w+c가 사전에 없음` → w 출력 + `w+c` 등록
  - `i+j >= msg.length()` → 더 늘릴 수 없음, w만 출력

**시간 복잡도:** N=1000, 사전 조회 O(1) → 전체 O(N) 수준.

> **면접 예상 질문:** LZW는 어떻게 동작하는가? 가변 길이 매칭 패턴은 어떻게 구현하는가?

---

### ASCII / char 산술 연산

`char`는 사실상 **2바이트 unsigned 정수** (UTF-16 code unit) — 산술 연산이 자유롭다.

```java
char c = 'A';
int code = c;            // 65 (자동 형변환)
int idx  = c - 'A' + 1;  // 1 (A=1) ✅ 권장
int idx2 = c - 64;       // 1 (매직 넘버, 비추천)
```

**외워둘 값:**
- `'A' = 65`, `'Z' = 90`, `'a' = 97`

**활용:**
```java
for (char c = 'A'; c <= 'Z'; c++) { ... }  // 알파벳 순회
String s = "hello";
char[] arr = s.toCharArray();              // String → char[]
String back = new String(arr);             // char[] → String
```

**`c - 'A' + 1` 표기 권장 이유:** 매직 넘버 64를 안 쓰고 의도가 명확. "A부터 시작해서 1씩"이 그대로 코드에 드러남.

**char vs byte:**
| 타입 | 크기 | 부호 | 용도 |
|---|---|---|---|
| `byte` | 1바이트 | 부호 있음 (-128~127) | 이진 데이터 |
| `char` | 2바이트 | 부호 없음 (0~65535) | 유니코드 문자 |

> **면접 예상 질문:** `char`와 `byte`의 차이는? `c - 'A' + 1` 표기를 권장하는 이유는?

---

### HashMap vs LinkedHashMap vs TreeMap

| 종류 | 순서 | 시간 복잡도 | 메모리 |
|---|---|---|---|
| **HashMap** | 보장 X | O(1) avg | 적음 |
| **LinkedHashMap** | 삽입 순서 | O(1) avg | 더 많음 (이중 연결 리스트) |
| **TreeMap** | 키 정렬 | O(log N) | 적음 (Red-Black Tree) |

**LZW 문제는 HashMap만으로 충분** — 출력 순서는 별도 `List`로 관리.

**HashMap 내부 구조 심화:**
- 배열 + LinkedList → **Java 8부터 버킷 8개 이상이면 Red-Black Tree로 전환** (Treeify)
- 동시성: `HashMap`은 thread-safe ❌ → `ConcurrentHashMap` 사용
- Java 8 `ConcurrentHashMap`은 **CAS + synchronized 버킷 단위** (이전 Segment 락에서 진화)
- `null` 키/값: HashMap 허용, ConcurrentHashMap 둘 다 ❌

> **면접 예상 질문:** HashMap의 내부 구조와 Java 8 변화는? `ConcurrentHashMap`은 동시성을 어떻게 보장하는가?

---

### Map.get()과 Boxing 함정

```java
Map<String, Integer> m = new HashMap<>();
if (m.get(s) != null) { ... }   // ✅ 안전
int v = m.get(s);                // ❌ 키 없으면 NullPointerException!
```

**원인:** `m.get(s)`가 `null`을 반환할 때 `int`로 언박싱하면 NPE.

**안전 패턴:**
```java
Integer v = m.get(s);                   // null 가능
int v2 = m.getOrDefault(s, 0);          // 기본값 제공
boolean exists = m.containsKey(s);       // 존재 확인
Optional.ofNullable(m.get(s)).ifPresent(...); // 함수형
```

**Auto-boxing 비용:**
- `int → Integer`는 **객체 생성**
- 루프 내 무심코 사용 시 GC 압박
- 성능 민감 코드는 `int[]` 등 primitive 배열 활용

> **면접 예상 질문:** `Map.get()` 사용 시 NPE는 왜 발생하는가? Auto-boxing의 성능 영향은?

---

### String.substring() 경계 처리

```java
msg.substring(start, end);  // [start, end), end는 포함 X
```

**주의:**
- `end > msg.length()` → `StringIndexOutOfBoundsException`
- **항상 `start, end` 모두 검증** 필요
- LZW에서는 `i+j >= msg.length()` 체크로 마지막 글자 안전 처리

**Java 7u6 변경점 (인터뷰 깊이):**
- Java 6까지: `substring`이 원본 `char[]`를 **공유** (offset, count 필드)
  → 큰 문자열의 작은 부분만 보유해도 **원본 통째로 GC 못 됨** = 메모리 누수
- Java 7u6+: **복사**로 변경, 메모리 누수 방지 (단 substring 자체 비용은 ↑)

> **면접 예상 질문:** `substring`의 경계 조건과 예외는? Java 7에서 substring 동작이 바뀐 이유는?

---

### Java 지역변수 Shadowing 금지

```java
void method() {
    int i = 0;
    while (i < n) {
        for (int i = 0; i < m; i++) { ... }  // ❌ 컴파일 에러!
    }
}
```

**규칙 (JLS 6.4.1):** 같은 메서드 내 **중첩 블록에서 지역변수 shadowing 불가**.

**다른 언어와 비교:**
- C++/JavaScript — shadowing 허용
- Java — 명시적 금지 (의도 모호함 방지)

**예외:**
- **클래스 멤버 변수는 shadowing 가능** (지역이 멤버를 가림 → `this.field`로 접근)
- 람다/익명 클래스 내부에서도 외부 지역변수 shadowing 불가

**해결책:**
- 의미 있는 변수명 사용 (`i` 대신 `msgIdx`, `outIdx` 등)
- 외부 변수를 가리는 패턴은 의도 모호 → **리네이밍이 정답**

> **면접 예상 질문:** Java가 지역변수 shadowing을 금지하는 이유는? 멤버 변수와는 왜 다른가?

---

### List\<Integer\> → int[] 변환

```java
// 방법 1: 루프 (가장 빠름)
int[] answer = new int[list.size()];
for (int k = 0; k < list.size(); k++) answer[k] = list.get(k);

// 방법 2: Stream + IntStream (가독성, 박싱 비용)
int[] answer = list.stream().mapToInt(Integer::intValue).toArray();

// 방법 3: Stream + 람다
int[] answer = list.stream().mapToInt(i -> i).toArray();
```

| 방식 | 성능 | 가독성 |
|---|---|---|
| 루프 | 최고 | 보통 |
| `mapToInt(Integer::intValue)` | 박싱/언박싱 + 람다 오버헤드 | 좋음 |

**선택 기준:** 코테에서는 둘 다 OK. 실무에서는 데이터 크기와 성능 요구를 보고 결정.

> **면접 예상 질문:** `List<Integer>`를 `int[]`로 변환하는 방법과 성능 차이는?

---

### 디버깅 사고 흐름

LZW 같은 문자열 처리 문제를 풀 때 좋은 사고 순서.

1. **문제 분해** — "A=1로 매핑" → ASCII 도메인 지식 연결
2. **자료구조 선택** — "사전 조회/삽입 모두 빠르게" → HashMap
3. **반복 구조 설계** — "고정 길이 X" → 안쪽 while + 종료 조건
4. **변수명 리팩토링** — 헷갈리면 즉시 의미 있는 이름으로 분리
5. **경계 케이스** — 마지막 글자, 빈 문자열, 길이 1 입력
6. **트레이스 디버깅** — 종이/주석으로 한 단계씩 검증
7. **컴파일 에러 메시지 정독** — "variable i is already defined" → 스코프 규칙 복기

> **면접 예상 질문:** 처음 보는 알고리즘 문제를 어떻게 분해해서 접근하는가?

---

### LZW 심화 — 면접 꼬리 질문 대비

**LZW의 단점:**
- 사전이 무한히 커질 수 있음 → 실무에선 **사전 크기 제한 + 리셋**
- 예: GIF는 12비트(4096개) 한계

**압축률:**
- 반복 패턴 多 → 좋음 (예: `AAAAAA...`)
- 랜덤 데이터 → 오히려 커질 수 있음 (사전 오버헤드)

**Trie로 풀 수 있을까?**
- 사전을 Trie로 구성하면 **prefix 매칭이 더 자연스러움**
- HashMap은 문자열 해싱 비용 있음 (긴 문자열에 불리)

**스트리밍 데이터:**
- 입력이 매우 길면 chunk 단위 + 사전 리셋 전략

**멀티스레드 압축:**
- 입력 분할 → 각 스레드 독립 사전 → 사전도 같이 전달해야 복원 가능
- Snappy, LZ4 등이 이런 변형 적용

> **면접 예상 질문:** LZW의 한계와 실무 적용 시 고려할 점은? Trie와 HashMap 중 어느 자료구조가 더 적합한가?

---

## 학습 정리

- **LZW**는 가변 길이 매칭 — 안쪽 while로 "사전에 있는 동안 확장" 패턴이 핵심
- 종료 조건 두 가지: `w+c 미존재` / `i+j >= length` (마지막 글자 처리)
- `char`는 **2바이트 unsigned 정수** — `c - 'A' + 1` 표기로 의도를 명확히
- HashMap/LinkedHashMap/TreeMap 트레이드오프 이해 — 본 문제는 HashMap으로 충분
- **`Map.get()` 결과를 `int`로 받으면 NPE 위험** → `containsKey`/`getOrDefault`/`Integer` 변수
- `substring(start, end)` 경계 검증 필수, Java 7u6에서 **공유 → 복사**로 변경되어 메모리 누수 방지
- Java는 **지역변수 shadowing 금지** (JLS 6.4.1) — 의미 있는 변수명으로 해결
- `List<Integer>` → `int[]`는 **루프가 최고 성능**, Stream은 가독성 트레이드오프
- 알고리즘 문제는 **분해 → 자료구조 선택 → 반복 구조 → 변수명 → 경계 → 트레이스** 순서로 접근

## 참고

- 카카오 2018 블라인드 3차 "압축(LZW)"
- Lempel–Ziv–Welch 알고리즘 (RFC 기반 GIF/TIFF 압축)
- JLS 6.4.1 — Shadowing
- Java 7 update 6 String 변경 사항 (substring 동작 변화)
