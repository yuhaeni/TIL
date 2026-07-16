# TIL (Today I Learned)

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
- [동시성 벌크헤드 — Semaphore, fast-fail vs queue, StreamingResponseBody async 스레드](system-design/동시성%20벌크헤드%20-%20Semaphore,%20fast-fail%20vs%20queue,%20StreamingResponseBody%20async%20스레드.md)
- [메세지 큐](system-design/메세지%20큐.md)
- [무상태(Stateless) 웹 계층](system-design/무상태(Stateless)%20웹%20계층.md)
- [부하 테스트 측정 용어 — Tomcat busy·current·max, pcpu·scpu, 블로킹 vs 논블로킹](system-design/부하%20테스트%20측정%20용어%20-%20스레드%20풀,%20CPU,%20블로킹.md)
- [분산 환경 동시성 제어 — DB 락 vs Redis 분산 락, Redlock, Fencing Token](system-design/분산%20환경%20동시성%20제어%20-%20DB%20락%20vs%20Redis%20분산%20락,%20Redlock,%20Fencing%20Token.md)
- [애플리케이션 캐시 전략(LRU)](system-design/애플리케이션%20캐시%20전략(LRU).md)
- [헥사고널 아키텍처 — Ports & Adapters, DIP, 다형성, Template Method, OCP](system-design/헥사고널%20아키텍처%20-%20Ports%20&%20Adapters,%20DIP,%20다형성,%20Template%20Method,%20OCP.md)

### 🐳 Docker

- [Docker Compose 네트워크와 서비스 디스커버리](docker/Docker%20Compose%20네트워크와%20서비스%20디스커버리.md)
- [Docker Compose로 로컬 개발 환경 구성하기](docker/Docker%20Compose로%20로컬%20개발%20환경%20구성하기.md)

### ☕ Java

- [@ConfigurationProperties — 빈 등록 3가지 방식과 생성자 바인딩](java/@ConfigurationProperties%20-%20빈%20등록%203가지%20방식과%20생성자%20바인딩.md)
- [@StepScope와 Late Binding](java/@StepScope와%20Late%20Binding.md)
- [@Transactional 격리 수준](java/@Transactional%20격리%20수준.md)
- [@Transactional 심화](java/@Transactional%20심화.md)
- [@Transactional 전파 속성](java/@Transactional%20전파%20속성.md)
- [@UtilityClass와 final, static](java/@UtilityClass와%20final,%20static.md)
- [Arrays.sort() 내부 동작](java/Arrays.sort()%20내부%20동작.md)
- [Caffeine 로컬 캐시의 정체 — JVM Heap, HashMap, 로컬 vs 분산 캐시](java/Caffeine%20로컬%20캐시의%20정체%20-%20JVM%20Heap,%20HashMap,%20로컬%20vs%20분산%20캐시.md)
- [Caffeine 캐시 적용과 stale data 전략 — evict, @CacheEvict AOP, @Component vs @Configuration, 캐시 단위](java/Caffeine%20캐시%20적용과%20stale%20data%20전략%20-%20evict,%20CacheEvict%20AOP,%20Component%20vs%20Configuration,%20캐시%20단위.md)
- [Cursor 페이징 구현 — `getPage()=0`과 멱등 restart](java/Cursor%20페이징%20구현%20-%20getPage%200과%20멱등%20restart.md)
- [DIP 심화 — 의존의 의미, 추상의 안정성, 인터페이스 이름 짓기, Mock 주입](java/DIP%20심화%20-%20의존의%20의미,%20추상의%20안정성,%20인터페이스%20이름%20짓기,%20Mock%20주입.md)
- [DTO 패턴, 관심사 분리와 OCP](java/DTO%20패턴,%20관심사%20분리와%20OCP.md)
- [DataSource 주입과 Reader 자원 관리 — JdbcCursorItemReader, 커넥션 풀, @Qualifier](java/DataSource%20주입과%20Reader%20자원%20관리%20-%20JdbcCursorItemReader,%20커넥션%20풀,%20@Qualifier.md)
- [GC 컬렉터 비교 — Parallel, G1, ZGC, Allocation Stall, live 객체](java/GC%20컬렉터%20비교%20-%20Parallel,%20G1,%20ZGC,%20Allocation%20Stall,%20live%20객체.md)
- [GlobalExceptionHandler와 전역 예외 처리](java/GlobalExceptionHandler와%20전역%20예외%20처리.md)
- [JVM 런타임 데이터 영역 5개 — 공유 vs 스레드별, Stack, Method Area, PC Register](java/JVM%20런타임%20데이터%20영역%205개%20-%20공유%20vs%20스레드별,%20Stack,%20Method%20Area,%20PC%20Register.md)
- [JVM 메모리와 GC, 리플렉션 최적화](java/JVM%20메모리와%20GC,%20리플렉션%20최적화.md)
- [Java 21 모던 스택 — record, -parameters, 패턴 매칭 instanceof, 버전 업그레이드 트레이드오프](java/Java%2021%20모던%20스택%20-%20record,%20-parameters,%20패턴%20매칭%20instanceof,%20버전%20업그레이드.md)
- [Java 자료구조 비교(ArrayList vs LinkedList, Stack vs ArrayDeque)](java/Java%20자료구조%20비교(ArrayList%20vs%20LinkedList,%20Stack%20vs%20ArrayDeque).md)
- [JpaPagingItemReader `transacted` 함정과 영속성 컨텍스트](java/JpaPagingItemReader%20transacted%20함정과%20영속성%20컨텍스트.md)
- [LRU 캐시와 멀티스레드 동시성](java/LRU%20캐시와%20멀티스레드%20동시성.md)
- [LinkedHashMap과 Map.merge()](java/LinkedHashMap과%20Map.merge().md)
- [OOM 면접 답변 — 그래프 패턴 진단, Stack-Heap 참조, STW 비즈니스 임팩트](java/OOM%20면접%20답변%20-%20그래프%20패턴%20진단,%20Stack-Heap%20참조,%20STW%20비즈니스%20임팩트.md)
- [OOM 진단과 메모리 누수 해결 — GC Roots, 참조, Caffeine](java/OOM%20진단과%20메모리%20누수%20해결%20-%20GC%20Roots,%20참조,%20Caffeine.md)
- [OOP 추상화와 디자인 패턴](java/OOP%20추상화와%20디자인%20패턴.md)
- [Quartz Job DI와 JobLauncher — 기본 생성자, lateinit, createBean, JobInstance 재실행, JobOperator 전환](java/Quartz%20Job%20DI와%20JobLauncher%20-%20기본%20생성자,%20lateinit,%20JobInstance%20재실행,%20JobOperator%20전환.md)
- [REQUIRES_NEW 커넥션 풀 데드락과 Outbox 패턴 — phase별 이벤트 분리, HikariCP 메트릭](java/REQUIRES_NEW%20커넥션%20풀%20데드락과%20Outbox%20패턴%20-%20phase별%20이벤트%20분리,%20HikariCP%20메트릭.md)
- [ResponseEntity와 ApiResponse 트레이드오프](java/ResponseEntity와%20ApiResponse%20트레이드오프.md)
- [SOLID 원칙 — SRP, LSP, ISP, DIP (스크래핑 시스템·Spring DI 예시)](java/SOLID%20원칙%20-%20SRP,%20LSP,%20ISP,%20DIP%20(스크래핑%20시스템·Spring%20DI%20예시).md)
- [Spring Batch OFFSET 버그와 Cursor 페이징](java/Spring%20Batch%20OFFSET%20버그와%20Cursor%20페이징.md)
- [Spring Batch Reader 옵션 — fetchSize, chunk size, maxItemCount, maxRows](java/Spring%20Batch%20Reader%20옵션%20-%20fetchSize,%20chunk%20size,%20maxItemCount,%20maxRows.md)
- [Spring Batch Step 구성요소 — Reader/Processor/Writer 작성 패턴과 filter vs skip](java/Spring%20Batch%20Step%20구성요소%20-%20Reader,%20Processor,%20Writer%20작성%20패턴과%20filter%20vs%20skip.md)
- [Spring Batch chunk size와 lock 보유 시간](java/Spring%20Batch%20chunk%20size와%20lock%20보유%20시간.md)
- [Spring Batch 핵심 빈 — JobRepository, PlatformTransactionManager, 메타데이터 테이블](java/Spring%20Batch%20핵심%20빈%20-%20JobRepository,%20PlatformTransactionManager,%20메타데이터%20테이블.md)
- [Spring Bean 라이프사이클과 Graceful Shutdown — DI 3가지, final, Singleton 멀티스레드, SIGTERM](java/Spring%20Bean%20라이프사이클과%20Graceful%20Shutdown%20-%20DI,%20final,%20Singleton%20멀티스레드,%20SIGTERM.md)
- [Spring Boot 동작 원리 — HTTP 요청 처리, DispatcherServlet, Filter/Interceptor/AOP, Thread per Request](java/Spring%20Boot%20동작%20원리%20-%20HTTP%20요청%20처리,%20DispatcherServlet,%20Filter%20Interceptor%20AOP,%20Thread%20per%20Request.md)
- [Spring Boot 부팅 과정 — JAR vs WAR, 자동 설정, ComponentScan, IoC 컨테이너](java/Spring%20Boot%20부팅%20과정%20-%20JAR%20WAR,%20자동%20설정,%20ComponentScan,%20IoC%20컨테이너.md)
- [Spring DI/IoC와 Bean 생성 순서](java/Spring%20DI%20IoC와%20Bean%20생성%20순서.md)
- [Spring 이벤트 리스너와 옵저버 패턴](java/Spring%20이벤트%20리스너와%20옵저버%20패턴.md)
- [Strategy vs Template Method와 결합도](java/Strategy%20vs%20Template%20Method와%20결합도.md)
- [Strategy 패턴과 추상화](java/Strategy%20패턴과%20추상화.md)
- [record와 @Valid 동작 원리](java/record와%20@Valid%20동작%20원리.md)
- [객체 지향 설계 기초 — 캡슐화, 상속·합성, 다형성, OCP, 인터페이스 vs 추상 클래스](java/객체%20지향%20설계%20기초%20-%20캡슐화,%20상속·합성,%20다형성,%20OCP,%20인터페이스%20vs%20추상%20클래스.md)
- [대용량 처리 OOM 구조 분석 — 살아있는 객체 누적, String 객체 오버헤드, G1 Full GC, SXSSF 스트리밍](java/대용량%20처리%20OOM%20구조%20분석%20-%20살아있는%20객체%20누적,%20String%20객체%20오버헤드,%20G1%20Full%20GC,%20SXSSF%20스트리밍.md)
- [상태 전이 설계와 Enum 활용](java/상태%20전이%20설계와%20Enum%20활용.md)
- [스프링 이벤트 기반 캐시 무효화 — ApplicationEventPublisher, @TransactionalEventListener, AFTER_COMMIT, race condition](java/스프링%20이벤트%20기반%20캐시%20무효화%20-%20ApplicationEventPublisher,%20TransactionalEventListener,%20AFTER_COMMIT,%20race%20condition.md)
- [인스턴스화와 프로세스 메모리 구조](java/인스턴스화와%20프로세스%20메모리%20구조.md)
- [추상화 — 본질 vs 세부사항, 정보 은닉과의 차이, 추상화의 단점과 Rule of Three](java/추상화%20-%20본질%20vs%20세부사항,%20정보%20은닉과의%20차이,%20추상화의%20단점과%20Rule%20of%20Three.md)
- [커넥션 풀과 HikariCP](java/커넥션%20풀과%20HikariCP.md)
- [컴파일타임 vs 런타임 — 제네릭 타입 소거, @Retention, 리플렉션](java/컴파일타임%20vs%20런타임%20-%20제네릭%20타입%20소거,%20@Retention,%20리플렉션.md)

### 🧮 알고리즘

- [LZW 압축과 가변 길이 매칭](algorithm/LZW%20압축과%20가변%20길이%20매칭.md)
- [백트래킹과 방어적 복사](algorithm/백트래킹과%20방어적%20복사.md)
- [자연 정렬과 상태 머신 문자열 파싱](algorithm/자연%20정렬과%20상태%20머신%20문자열%20파싱.md)
- [탐욕법과 투 포인터](algorithm/탐욕법과%20투%20포인터.md)

### 📨 Kafka

- [ErrorHandlingDeserializer와 Poison Pill — 역직렬화, Consumer/Listener, DLQ](kafka/ErrorHandlingDeserializer와%20Poison%20Pill%20-%20역직렬화,%20DLQ.md)
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

- [NOT EXISTS 최적화 — Anti Join, Short-circuit, NULL 3치 논리, SELECT 1](database/NOT%20EXISTS%20최적화%20—%20Anti%20Join,%20Short-circuit,%20NULL%203치%20논리,%20SELECT%201.md)
- [PostgreSQL Advisory Lock — check-then-act race, xact vs session, hashtext 충돌, Redis 분산 락 비교](database/PostgreSQL%20Advisory%20Lock%20-%20check-then-act%20race,%20xact%20vs%20session,%20hashtext%20충돌,%20Redis%20분산%20락%20비교.md)
- [PostgreSQL EXPLAIN ANALYZE 읽기 — Index Only Scan, Materialize, 옵티마이저 전략 변화](database/PostgreSQL%20EXPLAIN%20ANALYZE%20읽기%20-%20Index%20Only%20Scan,%20Materialize,%20옵티마이저%20전략%20변화.md)
- [PostgreSQL vs MySQL InnoDB — MVCC, UNDO LOG, WAL, VACUUM](database/PostgreSQL%20vs%20MySQL%20InnoDB%20-%20MVCC,%20UNDO,%20WAL,%20VACUUM.md)
- [PostgreSQL 인덱스와 B+Tree](database/PostgreSQL%20인덱스와%20B+Tree.md)
- [Spring Batch chunk size 성능 트레이드오프 — commit overhead, WAL fsync, lock 보유](database/Spring%20Batch%20chunk%20size%20성능%20트레이드오프%20-%20commit%20overhead,%20WAL%20fsync,%20lock%20보유.md)
- [UNIQUE 제약과 인덱스 — invariant, selectivity, CONSTRAINT vs INDEX](database/UNIQUE%20제약과%20인덱스%20-%20invariant,%20selectivity,%20CONSTRAINT%20vs%20INDEX.md)
- [카디널리티와 복합 인덱스 — pg_stats, n_distinct, ANALYZE](database/카디널리티와%20복합%20인덱스%20-%20pg_stats,%20n_distinct,%20ANALYZE.md)

### 📊 Monitoring

- [AWS Lightsail Container Service에 Prometheus·Grafana 배포 — docker-compose 패턴 변환](monitoring/AWS%20Lightsail%20Container%20Service에%20Prometheus,%20Grafana%20배포%20-%20docker-compose%20패턴%20변환.md)
- [Caffeine 캐시 모니터링과 튜닝 — @Component, LoadingCache, recordStats, MeterRegistry, eviction cause](monitoring/Caffeine%20캐시%20모니터링과%20튜닝%20-%20@Component,%20LoadingCache,%20recordStats,%20MeterRegistry,%20eviction%20cause.md)
- [Spring Batch 성능 측정 — PromQL과 Grafana](monitoring/Spring%20Batch%20성능%20측정%20PromQL과%20Grafana.md)

<!-- TIL_END -->
