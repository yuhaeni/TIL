# AWS Lightsail Container Service에 Prometheus·Grafana 배포 — docker-compose 패턴 변환

> 날짜: 2026-05-31

## 내용

로컬 개발에서 docker-compose로 잘 띄우던 Prometheus/Grafana를, GitHub Actions + AWS Lightsail Container Service로 배포되는 운영 환경에 추가하려 할 때 막히는 5가지 지점과 변환 패턴 정리.

---

### 키워드 1 — docker-compose vs Lightsail Container Service: 누가 오케스트레이션하느냐

같은 "여러 컨테이너 묶어서 띄우기"인데, **그 일을 누가 해주느냐**가 다르다.

| 구분 | 로컬 docker-compose | AWS Lightsail Container Service |
|---|---|---|
| 오케스트레이터 | 내 PC의 Docker 엔진 | AWS 매니지드 서비스 |
| 선언 파일 | `docker-compose.yml` | `deployment.json` |
| 실행 | `docker compose up` | `aws lightsail create-container-service-deployment` |
| compose 사용? | ✅ | ❌ 자체 포맷 |

즉 **`deployment.json`이 docker-compose.yml의 클라우드(매니지드) 버전**이다. 형식만 다르고 역할은 같다.

> 클라우드 배포라고 docker-compose를 안 쓰는 건 아니다. EC2/Lightsail 인스턴스(그냥 리눅스 VM)를 빌려서 `docker compose up` 하는 패턴도 흔하다. **매니지드 컨테이너 서비스**(Lightsail Container Service / ECS / Cloud Run)를 쓸 때만 compose 대신 그 플랫폼 전용 포맷을 쓴다.

> **면접 예상 질문:** AWS에 컨테이너를 배포할 때 EC2 + docker-compose 방식과 Lightsail Container Service / ECS 같은 매니지드 컨테이너 서비스 방식의 트레이드오프는 무엇인가요?

---

### 키워드 2 — `volumes:` 마운트가 안 된다: Dockerfile에 `COPY`로 굽기

docker-compose의 prometheus 설정에서 핵심 줄:

```yaml
prometheus:
  image: 'prom/prometheus:latest'
  volumes:
    - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
```

`./monitoring/prometheus.yml`을 컨테이너 안 `/etc/prometheus/prometheus.yml`로 **런타임에 마운트**하는 방식. **Lightsail Container Service는 호스트 파일 마운트를 지원하지 않는다.**

→ 해결: 설정 파일을 **이미지 빌드 타임에 구워 넣는다.** 기존 app/nginx와 똑같은 패턴.

```dockerfile
# monitoring/Dockerfile.prometheus
FROM prom/prometheus:latest
COPY ./monitoring/prometheus.yml /etc/prometheus/prometheus.yml
```

- `FROM`에는 docker-compose `image:`에 적던 값 그대로
- `COPY`의 왼쪽 = 내 PC 파일 경로(=volumes 콜론 왼쪽), 오른쪽 = 컨테이너 안 경로(=volumes 콜론 오른쪽)
- `WORKDIR` / `ENTRYPOINT` 불필요: `prom/prometheus` 이미지가 이미 기본 실행 명령을 들고 있음

Grafana도 같은 패턴. `./monitoring/grafana/provisioning`을 `COPY`로 구워 넣으면 데이터소스/대시보드를 자동 설정 가능.

이미지를 만들었으면 그다음은 기존 app/nginx 흐름 그대로:

1. GitHub Actions에 빌드 스텝(`docker/build-push-action`) + 푸시 스텝(`aws lightsail push-container-image`) 추가
2. `deployment.json`의 `containers:` 블록에 `prometheus`, `grafana` 키 추가

> **면접 예상 질문:** 매니지드 컨테이너 서비스가 호스트 파일 마운트를 막아둔 이유는 무엇이고, 그로 인해 어떤 설계 변화가 강제되나요?

---

### 키워드 3 — `host.docker.internal` → `localhost:포트`: 같은 서비스 내 컨테이너 통신

로컬 docker-compose의 prometheus.yml에는 보통 이런 줄이 있다.

```yaml
scrape_configs:
  - job_name: 'spring-boot'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['host.docker.internal:8080']
```

`host.docker.internal`은 컨테이너 안에서 **"내 컨테이너 바깥의 호스트 머신"**을 가리키는 별명. 로컬에서는 prometheus는 컨테이너 안, Spring Boot 앱은 IntelliJ로 컨테이너 밖에서 띄우기 때문에 필요했다.

**Lightsail Container Service**에서는 같은 서비스 안 컨테이너끼리 **`localhost:<포트>`**로 부른다 (한 네트워크 네임스페이스 공유). 기존 `deployment.json`이 이미 그렇게 쓰고 있다:

```json
app: {
  environment: {
    USAGI_DEV_REDIS_HOST: "localhost",  // redis 컨테이너를 localhost로 부른다
  }
}
```

그래서 Lightsail용 prometheus.yml:

```yaml
scrape_configs:
  - job_name: 'spring-boot'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['localhost:8080']   # app 컨테이너의 포트
```

#### 헷갈리지 말 것 — Prometheus는 포트가 2개다

| 포트 | 누구의 포트? | 무슨 역할? |
|---|---|---|
| **9090** | Prometheus 자신 | "내 사무실 주소" — 웹 UI / 쿼리 받는 곳 |
| **8080** | Spring Boot 앱 | "내가 찾아가서 메트릭 긁어올 집 주소" |

- docker-compose의 `ports: '9090:9090'` = "내 사무실(9090)을 외부에 열어줘" (UI 접속용)
- `targets: ['localhost:8080']` = "앱(8080)으로 긁으러 다녀와" (수집 대상)

전혀 다른 일이라서 둘을 섞으면 "내가 나한테 메트릭 달라고 한다"가 되어버린다.

Grafana → Prometheus 데이터소스 URL도 같은 패턴: **`http://localhost:9090`**.

> **면접 예상 질문:** Lightsail Container Service / ECS Fargate Task / Kubernetes Pod에서 같은 그룹 내 컨테이너끼리는 어떤 네트워크 모델을 공유하나요? docker-compose의 서비스 이름 기반 DNS와 어떻게 다른가요?

---

### 키워드 4 — `environment:`는 그대로 옮기되, 비밀번호는 GitHub Secrets로

Grafana는 로그인 화면이 있어서 관리자 비밀번호 환경변수가 필수다.

```yaml
# docker-compose
grafana:
  environment:
    - 'GF_SECURITY_ADMIN_USER=${GRAFANA_USER:-admin}'
    - 'GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-admin}'
```

기존 `deployment.json`이 DB 비밀번호를 GitHub Secrets에서 받는 패턴 그대로 적용:

```json
grafana: {
  image: $grafana_image,
  environment: {
    GF_SECURITY_ADMIN_USER: "admin",
    GF_SECURITY_ADMIN_PASSWORD: $grafana_pass,   // GitHub Secrets에서 주입
    GF_USERS_ALLOW_SIGN_UP: "false"
  },
  ports: { "3000": "HTTP" }
}
```

`jq -n` 블록에 `--arg grafana_pass "${{ secrets.GRAFANA_PASSWORD }}"` 한 줄 추가하면 끝.

> **면접 예상 질문:** 컨테이너에 시크릿(DB 비번, API Key 등)을 주입하는 방법으로 환경변수, 시크릿 매니저(AWS Secrets Manager / SSM Parameter Store), 마운트 파일 방식이 있는데 각각의 장단점은 무엇인가요?

---

### 키워드 5 — `publicEndpoint`는 단 1개: Grafana는 nginx reverse proxy로 노출

Prometheus는 내부 전용이라 외부 노출이 필요 없지만, **Grafana는 브라우저로 대시보드를 봐야 하니까 외부 접근이 필요**하다. 여기서 함정:

```json
publicEndpoint: {
  containerName: "nginx",   // 이미 nginx가 차지 중
  containerPort: 80
}
```

**Lightsail Container Service는 publicEndpoint를 하나만 가질 수 있다.** Grafana 컨테이너를 직접 노출할 수 없다.

#### 두 가지 선택지

| 옵션 | 설명 | 트레이드오프 |
|---|---|---|
| **A. nginx에 `/grafana/` reverse proxy** | 기존 nginx 설정에 location 블록 추가 | 인프라 추가 없음. nginx의 basic auth(`.htpasswd`)로 한 겹 더 보호 가능 |
| **B. Grafana 별도 EC2/서비스에 띄우기** | 완전히 분리 | 새 인스턴스, 보안 그룹, 도메인 설정 등 인프라 증가 |

→ 보통 **옵션 A가 간단**하다. nginx Dockerfile + basic auth가 이미 갖춰져 있으면 location 한 블록 추가가 끝.

#### subpath 함정

nginx에서 `/grafana/`로 프록시하면, Grafana는 자기 진짜 주소가 루트가 아니라 `/grafana/`로 시작한다는 걸 모른 채 CSS/JS 링크를 `/public/...`로 뱉어서 다 깨진다. 환경변수로 알려줘야 한다.

```
GF_SERVER_ROOT_URL=https://your-domain/grafana/
GF_SERVER_SERVE_FROM_SUB_PATH=true
```

> **면접 예상 질문:** 단일 public endpoint만 허용하는 환경에서 여러 내부 서비스(API, 어드민, 모니터링 UI)를 외부에 노출하려면 어떤 아키텍처 패턴이 있나요? 각각의 보안·운영 관점 차이는?

---

## 학습 정리

- **docker-compose vs Lightsail Container Service**는 본질적으로 같은 일(여러 컨테이너 오케스트레이션)을 하지만, **누가 그 일을 해주는지**가 다르다. 매니지드 서비스를 쓰면 그 플랫폼 전용 선언 포맷(`deployment.json`)을 따라야 한다.
- 매니지드 컨테이너 서비스에서는 **호스트 파일 마운트가 막혀 있다.** 설정 파일은 **Dockerfile에 `COPY`로 굽는 패턴**으로 변환한다 (`volumes:` → 이미지 빌드 타임 포함).
- 같은 서비스 안 컨테이너끼리는 **`localhost:<포트>`로 통신**한다. `host.docker.internal`이나 docker-compose 서비스명 DNS와는 다른 모델.
- 시크릿은 GitHub Secrets → Actions에서 `jq --arg`로 deployment.json에 주입하는 기존 패턴을 그대로 재사용한다.
- **`publicEndpoint`는 1개 제약**이 있어서, UI를 가진 추가 컨테이너(Grafana 등)는 reverse proxy(nginx) 뒤에 두는 게 가장 단순한 해법. 단, subpath로 프록시할 때 Grafana의 `GF_SERVER_ROOT_URL` / `GF_SERVER_SERVE_FROM_SUB_PATH` 설정을 빠뜨리면 정적 자원 링크가 깨진다.

## 참고

- [Docker Compose 네트워크와 서비스 디스커버리](../docker/Docker%20Compose%20네트워크와%20서비스%20디스커버리.md)
- [Docker Compose로 로컬 개발 환경 구성하기](../docker/Docker%20Compose로%20로컬%20개발%20환경%20구성하기.md)
- [Spring Batch 성능 측정 PromQL과 Grafana](Spring%20Batch%20성능%20측정%20PromQL과%20Grafana.md)
