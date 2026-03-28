# Docker Compose로 로컬 개발 환경 구성하기

> 날짜: 2026-03-28

## 내용

### 1. 왜 Docker Compose인가?

로컬 개발 환경에서 PostgreSQL, Redis 같은 인프라를 직접 설치하면 **"내 컴퓨터에서는 되는데?"** 문제가 생긴다.

Docker Compose를 사용하면 `docker compose up` 한 줄로 **누가, 언제 세팅해도 동일한 환경**이 만들어진다.

### 2. 환경 분리: 로컬 vs 프로덕션

| 구분 | 도구 | 목적 |
|------|------|------|
| 로컬 개발 환경 | `compose.yaml` | 개발자가 빠르게 인프라를 띄우고 테스트 |
| 프로덕션/배포 환경 | `Dockerfile` + GitHub Actions | 빌드 → 테스트 → 배포 자동화 |

compose.yaml은 **개발 편의를 위한 도구**이고, 프로덕션 배포와는 역할이 다르다.

### 3. 이미지 버전 고정

```yaml
# Bad - 시점마다 환경이 달라질 수 있음
image: 'postgres:latest'

# Good - 버전을 고정해서 일관된 환경 보장
image: 'postgres:16'
```

`latest`를 사용하면 어제와 오늘 빌드한 환경이 달라질 수 있다. **버전을 고정**해야 팀원 모두 같은 환경에서 개발할 수 있다.

### 4. healthcheck: 컨테이너가 "진짜" 준비됐는지 확인

컨테이너가 뜨는 것과 서비스가 요청을 받을 준비가 되는 것은 다르다.
healthcheck를 설정하면 **컨테이너가 진짜 준비됐을 때만 앱이 연결되도록 보장**할 수 있다.

```yaml
# PostgreSQL - 쿼리를 받을 준비가 됐는지 확인
healthcheck:
  test: [ "CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-carrot} -d ${POSTGRES_DB:-carrot_settle}" ]
  interval: 10s
  timeout: 5s
  retries: 5

# Redis - PING에 PONG으로 응답하는지 확인
healthcheck:
  test: [ "CMD", "redis-cli", "ping" ]
  interval: 10s
  timeout: 5s
  retries: 5
```

- **interval**: 10초마다 체크
- **timeout**: 5초 안에 응답이 없으면 실패
- **retries**: 5번 연속 실패하면 unhealthy 상태

### 5. 전체 compose.yaml 구성

```yaml
services:
  postgres:
    image: 'postgres:16'
    environment:
      - 'POSTGRES_DB=${POSTGRES_DB:-carrot_settle}'
      - 'POSTGRES_USER=${POSTGRES_USER:-carrot}'
      - 'POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-carrot1234}'
    ports:
      - '5432:5432'
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: [ "CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-carrot} -d ${POSTGRES_DB:-carrot_settle}" ]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: 'redis:7'
    ports:
      - '6379:6379'
    volumes:
      - redis_data:/data
    healthcheck:
      test: [ "CMD", "redis-cli", "ping" ]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
  redis_data:
```

**포인트 정리:**
- `${POSTGRES_DB:-carrot_settle}` → 환경변수가 없으면 기본값 사용
- `volumes` → 컨테이너를 내려도 데이터 유지 (named volume)
- `ports` → 호스트에서 직접 접근 가능하도록 포트 매핑

## 참고

- [Docker Compose 공식 문서](https://docs.docker.com/compose/)
