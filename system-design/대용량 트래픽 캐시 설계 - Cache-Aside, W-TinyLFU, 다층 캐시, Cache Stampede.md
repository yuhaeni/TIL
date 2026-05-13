# 대용량 트래픽 캐시 설계 — Cache-Aside, W-TinyLFU, 다층 캐시, Cache Stampede

> 날짜: 2026-05-13

## 내용

### Cache-Aside 패턴 — 가장 흔한 캐시 전략과 자기조직화

대용량 트래픽 환경에서 DB 부하를 줄이기 위해 자주 호출되는 데이터를 캐시(Redis 등)에 두는 가장 기본 패턴.

```
조회 흐름 (Cache-Aside / Look-Aside):
  1. App → Redis 확인
  2. 있으면(HIT) → 즉시 반환
  3. 없으면(MISS) → DB 조회 → Redis 저장 → 반환
```

Spring에서는 `@Cacheable` 어노테이션이 이 흐름을 자동으로 구현해준다.

**자기조직화의 핵심**: "자주 호출되는 데이터인지 어떻게 판단하는가?" → 명시적으로 카운트할 필요 없음. 캐시 크기가 한정적이라 evict 정책(LRU 등)이 자주 안 쓰는 걸 자동으로 골라낸다. 결과적으로 살아남는 게 = 자주 쓰는 데이터.

> 📚 도서관 비유: 책상에 책 10권만 올릴 수 있음. 손님이 책 찾을 때 책상에 없으면 서가 가서 가져와 책상에 둠. 책상 꽉 차면 가장 오래 안 본 책을 서가로 돌려보냄(LRU). → 책상에 살아남는 책 = 최근에 자주 찾은 책

> **면접 예상 질문:** Cache-Aside 패턴의 동작 흐름은? 캐시는 어떻게 "자주 호출되는 데이터"를 자동으로 식별하는가?

---

### LRU의 한계 — 바이럴 트래픽이 인기 데이터를 밀어내는 시나리오

LRU는 "최근에 봤느냐"만 본다. 일회성 폭발 트래픽(바이럴)에 약점이 있다.

**시나리오**:

```
📅 평소: 캐시에 인기 템플릿 TOP 100이 살아있음 → HIT율 높음 😊

🚨 바이럴 발생: 신규 템플릿 1개가 SNS에서 떠서 5분간 100만 명이 조회
   → LRU는 "최근에 자주 본 책"으로 판단 → 기존 TOP 100을 모두 evict 💀
   → 캐시에는 바이럴 1개만 가득

⏰ 바이럴 식음: 사람들이 다시 TOP 100을 조회
   → 캐시에 없음 → 모두 DB로 직행 → DB 부하 폭증 💥
```

**중요한 통찰**: LRU는 시간이 지나면 결국 다시 TOP 100이 채워져 자기조직화로 복구된다. 문제는 **"채워지는 그 짧은 순간"**. 1억 건의 캐시 미스가 수 초 내에 몰리면 DB가 먼저 죽는다.

이게 바로 **Cache Stampede** 문제로 이어진다.

> **면접 예상 질문:** LRU 정책의 약점은? 바이럴/일회성 폭발 트래픽 상황에서 어떤 문제가 발생하는가?

---

### W-TinyLFU와 Caffeine — 빈도 기반 정책으로 LRU 보완

**W-TinyLFU** = **Window** (최근성) + **Tiny LFU** (소형 빈도 추적)

LRU vs W-TinyLFU:

| | LRU | W-TinyLFU |
|---|---|---|
| 판단 기준 | "최근에 봤느냐?" | "최근 + **누적 빈도**" |
| 빈도 추적 | ❌ | ✅ Count-Min Sketch (소형 메모리) |
| 바이럴 시나리오 | 신규 1개에 기존 100개 밀려남 | 누적 빈도 압승으로 기존 100개 보존 |
| 사용처 | 단순 LRU 캐시 | **Caffeine 라이브러리** |

**핵심 동작**:

```
신규 바이럴 1번: 평생 5분간 100만 번 = 누적 100만
기존 인기 1번:  1년간 매일 1만 번 = 누적 36억

W-TinyLFU 사서: "기존이 압승! 신규 1번 넌 캐시 입성 거절!"
```

**Caffeine 구현 예시**:

```java
Cache<Long, Template> cache = Caffeine.newBuilder()
    .maximumSize(10_000)                       // 최대 1만 개
    .expireAfterWrite(Duration.ofMinutes(10))  // TTL 10분
    .recordStats()                             // hit rate 등 통계 수집
    .build();
```

Caffeine은 W-TinyLFU를 내부적으로 채택해서 자동 적용. 개발자는 `Caffeine.newBuilder()`만 호출하면 됨.

> **면접 예상 질문:** LRU 대신 W-TinyLFU를 쓰면 어떤 문제가 해결되는가? Caffeine 라이브러리가 이걸 어떻게 구현하는가?

---

### @Cacheable과 CacheManager — Spring Cache Abstraction

`@Cacheable`은 **추상화 어노테이션**. "캐시해줘"라고 선언만 할 뿐 어디에 저장할지는 `CacheManager` Bean이 결정한다.

```
@Cacheable (추상화 계층)
       ↓
  CacheManager (실제 저장소 결정)
       ↓
  ├─ ConcurrentMapCache (기본 — JVM 내장 HashMap)
  ├─ RedisCacheManager
  ├─ CaffeineCacheManager
  └─ EhCache, Hazelcast 등
```

**Redis로 연동하는 셋업**:

```gradle
implementation 'org.springframework.boot:spring-boot-starter-cache'
implementation 'org.springframework.boot:spring-boot-starter-data-redis'
```

```java
@Configuration
@EnableCaching
public class CacheConfig {
    @Bean
    public CacheManager cacheManager(RedisConnectionFactory cf) {
        return RedisCacheManager.builder(cf)
            .cacheDefaults(
                RedisCacheConfiguration.defaultCacheConfig()
                    .entryTtl(Duration.ofMinutes(10))  // TTL
            )
            .build();
    }
}

@Cacheable(value = "templates", key = "#id")
public Template findTemplate(Long id) { ... }
```

⚠️ `CacheManager` Bean 설정을 안 하면 기본값은 **`ConcurrentMapCache`** — JVM 메모리에 저장돼 서버 재시작 시 다 날아가고, 여러 서버 띄우면 동기화 안 된다. **분산 환경에선 무조건 외부 저장소(Redis 등)로 설정 필수**.

> **면접 예상 질문:** `@Cacheable`만 붙이면 Redis에 자동으로 저장되는가? `CacheManager` Bean의 역할은?

---

### 다층 캐시 (Multi-level Cache) — L1 Caffeine + L2 Redis

Caffeine은 JVM 내장 로컬 캐시라 빠르지만 **서버마다 독립적**이다. 분산 환경에선 한계가 있다. 이걸 보완하기 위해 **다층(Tiered) 캐시**를 구성한다.

```
┌──────────┐   ┌──────────────────────┐   ┌────────────────┐   ┌──────────┐
│ 클라이언트 │ → │ App 서버 + Caffeine  │ → │ Redis (분산 캐시)│ → │ PostgreSQL │
└──────────┘   │     (L1, 로컬)       │   │   (L2, 공유)     │   │   (DB)   │
                └──────────────────────┘   └────────────────┘   └──────────┘
                       ↑ ns 단위              ↑ ms 단위           ↑ 10~100ms
                       (JVM 메모리)           (네트워크 호출)        (진실의 원천)
```

**조회 흐름**:

```
1. L1 (Caffeine) 확인 → 있으면 즉시 반환 (수십 ns)
2. 없으면 L2 (Redis) 확인 → 있으면 반환 + L1에 저장 (네트워크 1ms)
3. 없으면 DB 조회 → L2 + L1에 저장 후 반환 (10~100ms)
```

**트레이드오프**:

| | L1 (Caffeine) | L2 (Redis) |
|---|---|---|
| 속도 | 초고속 (ns) | 빠름 (ms, 네트워크 호출) |
| 공유 | ❌ 서버별 독립 | ✅ 모든 서버 공유 |
| 일관성 | ❌ 서버마다 다를 수 있음 | ✅ 단일 진실 |
| 용량 | 작음 (JVM 힙 제한) | 큼 (Redis 클러스터) |

> **면접 예상 질문:** 다층 캐시 구조에서 L1과 L2의 역할은? 미리디 같은 분산 환경에서 왜 다층 캐시가 필요한가?

---

### 다층 캐시의 일관성 문제와 Pub/Sub 무효화

L1 (Caffeine)이 서버별 독립이라는 게 단순히 hit rate 차이가 아니라 **데이터 일관성 문제**로 번진다.

**일관성 깨지는 시나리오**:

```
🖥️ 서버 A, B, C의 Caffeine: 모두 템플릿 1번 = "예전 제목" 캐시 보유

✏️ 사용자가 서버 A에서 템플릿 1번 제목 수정
   → 서버 A: DB 업데이트 + Caffeine 갱신 ("새 제목")
   → 서버 A의 Caffeine: "새 제목" ✅
   → 서버 B, C의 Caffeine: 여전히 "예전 제목" ❌

😱 다음 요청이 서버 B로 가면 "예전 제목"이 응답됨
```

**해결책: Pub/Sub 기반 캐시 무효화(Cache Invalidation)**

```
✏️ 서버 A: 템플릿 1번 수정
   1. DB 업데이트
   2. "템플릿 1번 갱신됨!" 메시지를 채널에 Publish 📢

🖥️ 서버 B, C: 채널을 Subscribe 중 → 메시지 수신
   → 자기 Caffeine의 템플릿 1번 evict 🗑️
   → 다음 조회 시 L2(Redis)나 DB에서 새로 가져옴 ✅
```

**구현 도구 선택**:

| 도구 | 특징 |
|---|---|
| **Redis Pub/Sub** | 이미 Redis 쓰면 무료 추가, 가벼움, 메시지 영속성 ❌ |
| **Kafka** | 메시지 영속성 ✅, 재처리 가능, 인프라 비용 ↑ |

미리디처럼 Redis가 이미 스택에 있으면 **Redis Pub/Sub**이 1순위.

**차선책: TTL 짧게 잡기 (Eventual Consistency 허용 시)**: Pub/Sub 인프라 없이도 L1 TTL을 30초~1분으로 짧게 잡으면 최대 1분 후 stale 데이터가 사라진다. "사용자가 1분 정도는 옛 데이터 봐도 되는가?"라는 **비즈니스 트레이드오프**가 따라붙는다.

> **면접 예상 질문:** L1 로컬 캐시(Caffeine)의 일관성 문제를 분산 환경에서 어떻게 해결하는가? Pub/Sub과 짧은 TTL의 트레이드오프는?

---

### Cache Stampede / Thundering Herd — 캐시 미스 폭주

**정의**:
- **Cache Stampede**: 캐시가 비어있는 상태에서 동일 데이터 요청이 폭주 → 모든 요청이 DB로 직행
- **Thundering Herd**: "천둥 치니 소떼가 한 방향으로 미친 듯이 달려가는" 비유. 동일 자원에 대량 요청 동시 충돌.

**결과**:
- DB 부하 폭증 → 응답 시간 폭발
- 같은 데이터를 동시에 1만 명이 요청 → DB에 같은 쿼리가 1만 번 동시 날아감 (진짜 Stampede!)
- 최악의 경우 **DB 커넥션 풀 고갈 → DB 다운**
- 대용량 서비스 장애 1순위 원인

> **면접 예상 질문:** Cache Stampede / Thundering Herd 현상이 발생하는 이유는? 어떤 장애로 이어지는가?

---

### Redis 분산 락으로 Cache Stampede 막기

**정공법**: 동일 캐시 미스가 동시에 발생하면, **첫 번째 요청만 DB로 보내고 나머지는 대기**하게 만든다 (Single-flight 패턴).

```
🚨 상황: 1만 명이 동시에 캐시 미스로 DB 직행하려 함

🔐 분산 락 도입 후:
   1. 첫 번째 요청: SETNX로 락 획득 시도 → 성공! 🥇
      → DB 조회 → 캐시 저장 → 락 해제
   2~10,000번째 요청: SETNX 실패 (이미 락 있음) ❌
      → 짧게 대기 후 재시도
      → 첫 번째가 캐시 저장하면 → 캐시 HIT! ✅
   → DB 부하 = 1만 건이 아니라 단 1건!
```

**Redisson 구현 예시 (Watchdog 자동 갱신)**:

```java
RLock lock = redisson.getLock("template:1:lock");
try {
    if (lock.tryLock(3, 10, TimeUnit.SECONDS)) {  // Watchdog 활성화
        // Double-Checked Locking — 락 획득 후 캐시 재확인
        Template cached = cache.get(1L);
        if (cached != null) return cached;

        // 진짜 캐시 미스면 DB 조회 + 캐시 저장
        Template t = repository.findById(1L);
        cache.put(1L, t);
        return t;
    }
} finally {
    lock.unlock();
}
```

**핵심 포인트**:
- `tryLock` 안에서 **캐시 재확인(Double-Checked Locking)** 필수 — 락 기다리는 동안 다른 요청이 이미 채웠을 수 있음
- Redisson **Watchdog**이 락 만료 전 자동으로 TTL 연장 → 작업 도중 락 풀려서 다른 요청이 침범하는 사고 방지

> **면접 예상 질문:** Cache Stampede를 막기 위해 분산 락(Mutex)을 어떻게 활용하는가? Double-Checked Locking이 왜 필요한가?

---

### TTL Jittering — 동시 만료 분산

같은 시점에 캐시된 데이터들이 **동시에 만료**되면 그 직후 Cache Stampede가 발생한다. 만료 시간에 **랜덤 노이즈(Jitter)**를 더해 분산시킨다.

```java
// 단순 TTL: 모든 키가 정확히 10분 후 동시 만료 → 위험 ⚠️
.entryTtl(Duration.ofMinutes(10))

// Jittering 적용: 10분 ± 0~60초 랜덤 → 만료 시점 분산 ✅
long jitter = ThreadLocalRandom.current().nextLong(0, 60_000);
.entryTtl(Duration.ofMillis(600_000 + jitter))
```

**왜 중요한가**: 캐시 워밍업(서버 시작 시 미리 채우기) 직후 모든 키가 동일 TTL이면 정확히 10분 뒤 한꺼번에 만료되어 Stampede 발생. Jittering으로 만료 시점을 흩뿌려 DB 부하 spike를 평탄화한다.

> **면접 예상 질문:** TTL Jittering이 왜 필요한가? 캐시 워밍업과 어떻게 연결되는가?

---

## 학습 정리

- **Cache-Aside** 패턴은 가장 흔한 캐시 전략. 캐시는 evict 정책으로 자기조직화되어 "자주 쓰는 데이터"가 자연스럽게 살아남는다.
- **LRU의 약점**은 일회성 폭발 트래픽(바이럴)에 인기 데이터가 밀려나는 것. **W-TinyLFU**는 최근성 + 누적 빈도를 함께 봐서 이 문제를 해결하고, **Caffeine** 라이브러리가 채택.
- `@Cacheable`은 추상화. 실제 저장소는 `CacheManager` Bean이 결정 — Redis 쓰려면 `RedisCacheManager` Bean 명시 설정 필수.
- 분산 환경에선 **다층 캐시(L1 Caffeine + L2 Redis)**로 속도와 일관성을 동시에 잡되, L1의 일관성 문제는 **Redis Pub/Sub 캐시 무효화**로 해결 (또는 짧은 TTL로 Eventual Consistency 허용).
- **Cache Stampede**는 동일 키 미스 폭주로 DB 다운까지 가는 장애 1순위 원인. **Redis 분산 락(Redisson Watchdog) + Double-Checked Locking**으로 첫 요청만 DB 보내는 Single-flight 패턴으로 방어.
- **TTL Jittering**으로 동시 만료를 분산시켜 만료 직후의 Stampede를 완화.

## 참고

- Caffeine: W-TinyLFU 정책 채택한 고성능 Java 캐시 라이브러리
- Spring Cache Abstraction: `@Cacheable`, `CacheManager` Bean 기반
- Redisson: Redis 기반 분산 락 + Watchdog 자동 갱신
- 미리디 면접 대비 Q2 (대용량 트래픽 캐시 전략) 모의 면접 기반 학습
