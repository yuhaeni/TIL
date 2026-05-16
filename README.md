# TIL (Today I Learned)
- 공부한 내용을 글로 남기면 매일 작은 성취감을 느낄 수 있어서 시작했습니다.
- 완벽하지 않아도 스스로 설명하듯 정리하는 것 자체가 학습이라고 생각합니다.
- [이전 TIL 보러가기](https://dev-haeni.tistory.com/category/Today%20I%20Learned%20%F0%9F%A7%90)


## Categories

<!-- TIL_START -->
### 🖥️ 운영체제

- [ALU와 제어장치](operating-system/ALU와%20제어장치.md)
- [CPU 스케줄링 실무 적용](operating-system/CPU%20스케줄링%20실무%20적용.md)
- [CPU 스케줄링 알고리즘](operating-system/CPU%20스케줄링%20알고리즘.md)
- [CPU 스케줄링](operating-system/CPU%20스케줄링.md)
- [I/O 처리 패턴과 Graceful Degradation](operating-system/I-O%20처리%20패턴과%20Graceful%20Degradation.md)
- [RAM](operating-system/RAM.md)
- [교착 상태](operating-system/교착%20상태.md)
- [동기화 기법](operating-system/동기화%20기법.md)
- [레지스터 종류](operating-system/레지스터%20(PC,%20MAR,%20MBR,%20IR).md)
- [메모리 주소 공간](operating-system/메모리%20주소%20공간.md)
- [스레드와 멀티스레드](operating-system/스레드와%20멀티스레드.md)
- [연속 메모리 할당](operating-system/연속%20메모리%20할당.md)
- [캐시 메모리](operating-system/캐시%20메모리.md)
- [특정 레지스터를 이용한 주소 지정 방식](operating-system/특정%20레지스터를%20이용한%20주소%20지정%20방식.md)
- [페이징을 통한 가상 메모리 관리](operating-system/페이징을%20통한%20가상%20메모리%20관리.md)
- [프로세스 동기화](operating-system/프로세스%20동기화.md)
- [프로세스와 PCB](operating-system/프로세스와%20PCB.md)

### ⚙️ 시스템 설계

- [대용량 트래픽 캐시 설계 — Cache-Aside, W-TinyLFU, 다층 캐시, Cache Stampede](system-design/대용량%20트래픽%20캐시%20설계%20-%20Cache-Aside,%20W-TinyLFU,%20다층%20캐시,%20Cache%20Stampede.md)
- [메세지 큐](system-design/메세지%20큐.md)
- [무상태(Stateless) 웹 계층](system-design/무상태(Stateless)%20웹%20계층.md)
- [분산 환경 동시성 제어 — DB 락 vs Redis 분산 락, Redlock, Fencing Token](system-design/분산%20환경%20동시성%20제어%20-%20DB%20락%20vs%20Redis%20분산%20락,%20Redlock,%20Fencing%20Token.md)
- [애플리케이션 캐시 전략(LRU)](system-design/애플리케이션%20캐시%20전략(LRU).md)

### 🐳 Docker

- [Docker Compose 네트워크와 서비스 디스커버리](docker/Docker%20Compose%20네트워크와%20서비스%20디스커버리.md)
- [Docker Compose로 로컬 개발 환경 구성하기](docker/Docker%20Compose로%20로컬%20개발%20환경%20구성하기.md)

### ☕ Java

- [@StepScope와 Late Binding](java/@StepScope와%20Late%20Binding.md)
- [@Transactional 격리 수준](java/@Transactional%20격리%20수준.md)
- [@Transactional 심화](java/@Transactional%20심화.md)
- [@Transactional 전파 속성](java/@Transactional%20전파%20속성.md)
- [@UtilityClass와 final, static](java/@UtilityClass와%20final,%20static.md)
- [Arrays.sort() 내부 동작](java/Arrays.sort()%20내부%20동작.md)
- [Cursor 페이징 구현 — `getPage()=0`과 멱등 restart](java/Cursor%20페이징%20구현%20-%20getPage%200과%20멱등%20restart.md)
- [DTO 패턴, 관심사 분리와 OCP](java/DTO%20패턴,%20관심사%20분리와%20OCP.md)
- [GlobalExceptionHandler와 전역 예외 처리](java/GlobalExceptionHandler와%20전역%20예외%20처리.md)
- [JVM 메모리와 GC, 리플렉션 최적화](java/JVM%20메모리와%20GC,%20리플렉션%20최적화.md)
- [Java 자료구조 비교(ArrayList vs LinkedList, Stack vs ArrayDeque)](java/Java%20자료구조%20비교(ArrayList%20vs%20LinkedList,%20Stack%20vs%20ArrayDeque).md)
- [JpaPagingItemReader `transacted` 함정과 영속성 컨텍스트](java/JpaPagingItemReader%20transacted%20함정과%20영속성%20컨텍스트.md)
- [LRU 캐시와 멀티스레드 동시성](java/LRU%20캐시와%20멀티스레드%20동시성.md)
- [LinkedHashMap과 Map.merge()](java/LinkedHashMap과%20Map.merge().md)
- [OOM 진단과 메모리 누수 해결 — GC Roots, 참조, Caffeine](java/OOM%20진단과%20메모리%20누수%20해결%20-%20GC%20Roots,%20참조,%20Caffeine.md)
- [OOP 추상화와 디자인 패턴](java/OOP%20추상화와%20디자인%20패턴.md)
- [REQUIRES_NEW 커넥션 풀 데드락과 Outbox 패턴 — phase별 이벤트 분리, HikariCP 메트릭](java/REQUIRES_NEW%20커넥션%20풀%20데드락과%20Outbox%20패턴%20-%20phase별%20이벤트%20분리,%20HikariCP%20메트릭.md)
- [ResponseEntity와 ApiResponse 트레이드오프](java/ResponseEntity와%20ApiResponse%20트레이드오프.md)
- [Spring Batch OFFSET 버그와 Cursor 페이징](java/Spring%20Batch%20OFFSET%20버그와%20Cursor%20페이징.md)
- [Spring Batch chunk size와 lock 보유 시간](java/Spring%20Batch%20chunk%20size와%20lock%20보유%20시간.md)
- [Spring DI/IoC와 Bean 생성 순서](java/Spring%20DI%20IoC와%20Bean%20생성%20순서.md)
- [Spring 이벤트 리스너와 옵저버 패턴](java/Spring%20이벤트%20리스너와%20옵저버%20패턴.md)
- [Strategy vs Template Method와 결합도](java/Strategy%20vs%20Template%20Method와%20결합도.md)
- [Strategy 패턴과 추상화](java/Strategy%20패턴과%20추상화.md)
- [record와 @Valid 동작 원리](java/record와%20@Valid%20동작%20원리.md)
- [상태 전이 설계와 Enum 활용](java/상태%20전이%20설계와%20Enum%20활용.md)
- [인스턴스화와 프로세스 메모리 구조](java/인스턴스화와%20프로세스%20메모리%20구조.md)
- [커넥션 풀과 HikariCP](java/커넥션%20풀과%20HikariCP.md)

### 🧮 알고리즘

- [LZW 압축과 가변 길이 매칭](algorithm/LZW%20압축과%20가변%20길이%20매칭.md)
- [백트래킹과 방어적 복사](algorithm/백트래킹과%20방어적%20복사.md)
- [자연 정렬과 상태 머신 문자열 파싱](algorithm/자연%20정렬과%20상태%20머신%20문자열%20파싱.md)
- [탐욕법과 투 포인터](algorithm/탐욕법과%20투%20포인터.md)

### 📨 Kafka

- [Kafka 멱등성과 Consumer Group](kafka/Kafka%20멱등성과%20Consumer%20Group.md)
- [Kafka 파티션과 컨슈머 모델](kafka/Kafka%20파티션과%20컨슈머%20모델.md)

### 🟣 Kotlin

- [Java record vs Kotlin data class](kotlin/Java%20record%20vs%20Kotlin%20data%20class.md)
- [Named Argument와 빌더 패턴](kotlin/Named%20Argument와%20빌더%20패턴.md)

### 🗄️ JPA

- [JPA FetchType과 N+1 문제](jpa/JPA%20FetchType과%20N+1%20문제.md)
- [JPA LAZY 프록시 함정 — Kotlin val/final, Hibernate 프록시 불가, kotlin-allopen](jpa/JPA%20LAZY%20프록시%20함정%20-%20Kotlin%20val%20final%20프록시%20불가,%20kotlin-allopen%20플러그인.md)
- [JPA 핵심 용어 — fetch, dirty, flush, version, auto-flush, stale](jpa/JPA%20핵심%20용어%20-%20fetch,%20dirty,%20flush,%20version,%20auto-flush.md)

### 🔴 Redis

- [Redis 분산 락과 교착 상태](redis/Redis%20분산%20락과%20교착%20상태.md)

### 🛢️ Database

- [PostgreSQL 인덱스와 B+Tree](database/PostgreSQL%20인덱스와%20B+Tree.md)
- [Spring Batch chunk size 성능 트레이드오프 — commit overhead, WAL fsync, lock 보유](database/Spring%20Batch%20chunk%20size%20성능%20트레이드오프%20-%20commit%20overhead,%20WAL%20fsync,%20lock%20보유.md)

### 📊 Monitoring

- [Spring Batch 성능 측정 — PromQL과 Grafana](monitoring/Spring%20Batch%20성능%20측정%20PromQL과%20Grafana.md)

<!-- TIL_END -->
