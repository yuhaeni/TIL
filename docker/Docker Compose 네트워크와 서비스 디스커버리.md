# Docker Compose 네트워크와 서비스 디스커버리

> 날짜: 2026-04-29

## 내용

### 포트 매핑 — `ports: '9090:9090'`의 두 숫자

Docker Compose의 `ports: '9090:9090'`은 **호스트 포트 ↔ 컨테이너 포트 사이의 다리(브릿지)** 다.

| 위치 | 의미 |
|---|---|
| **왼쪽 9090** | Host Port — 사용자 노트북(호스트 머신)의 포트 |
| **오른쪽 9090** | Container Port — 컨테이너 내부의 포트 |

컨테이너는 각자 격리된 작은 컴퓨터처럼 동작하며 **자기만의 포트 공간**을 가진다. 외부에서 컨테이너 안으로 들어가려면 이 매핑이 필요.

```
브라우저 → localhost:9090 (내 노트북의 9090)
         ↓ (Docker가 놓아준 다리)
         Prometheus 컨테이너의 9090
```

> **면접 예상 질문:** `ports: '9090:9090'`의 두 숫자는 각각 무엇을 의미하는가?

---

### `localhost`의 진짜 의미 — "이 명령을 실행하는 그 컴퓨터 자기 자신"

`localhost`는 **고정된 어떤 머신**이 아니라 **명령을 실행하는 주체 자기 자신**을 가리킨다.

| 실행 위치 | `localhost`가 가리키는 곳 |
|---|---|
| 호스트 브라우저 | 사용자 노트북 (호스트 머신) |
| Grafana 컨테이너 안 | Grafana 컨테이너 자체 |
| Prometheus 컨테이너 안 | Prometheus 컨테이너 자체 |

**Grafana → Prometheus를 `localhost:9090`으로 부르면 안 되는 이유:**
- Grafana 컨테이너 안에서 `localhost`는 **Grafana 자기 자신**
- Grafana 안에는 9090 포트로 떠있는 Prometheus가 없음 → 연결 실패

> **면접 예상 질문:** 같은 `localhost:9090`인데 호스트에서는 되고 컨테이너에서는 안 되는 이유는?

---

### 서비스 디스커버리 — 컨테이너 이름으로 통신

Docker Compose의 `services:` 아래 적은 이름(예: `prometheus`, `redis`, `grafana`)이 **컨테이너 간 통신용 호스트네임**이 된다.

```yaml
services:
  prometheus:    # ← 호스트네임: prometheus
    ...
  grafana:
    ...
```

→ Grafana는 `http://prometheus:9090`으로 호출.

**왜 IP가 아닌 이름으로?**
- 컨테이너는 **재시작 시 IP가 바뀔 수 있음**
- IP 하드코딩 시 재시작 한 번에 연결 깨짐
- 이름은 변하지 않으므로 DNS가 알아서 새 IP를 찾아 연결

이 메커니즘을 **서비스 디스커버리(Service Discovery)** 라 한다.

> **면접 예상 질문:** Docker Compose에서 IP 대신 서비스명으로 통신하게 만든 이유는?

---

### 내장 DNS 서버 — 127.0.0.11

Docker Compose는 컨테이너들이 모인 네트워크에 **내장 DNS 서버(Embedded DNS Server)** 를 자동으로 띄운다. **고정 IP 127.0.0.11**.

**동작 흐름:**
```
[Grafana 컨테이너]
  └─ http://prometheus:9090 호출
        └─ /etc/resolv.conf의 nameserver 127.0.0.11에게 질의
              └─ 내장 DNS가 "prometheus" → 실제 컨테이너 IP 응답
                    └─ Grafana가 그 IP로 TCP 연결
```

DNS 자체와 동일한 원리(이름 → IP 변환)지만, **사용자 정의 브릿지 네트워크 안에서만** 동작한다.

> **면접 예상 질문:** Docker는 어떻게 서비스명을 IP로 변환하는가? 127.0.0.11은 무엇인가?

---

### 사용자 정의 브릿지 네트워크 vs 기본 브릿지

`docker run`으로 따로 띄우면 기본 브릿지(default bridge)에 들어가는데, **여기서는 DNS가 동작하지 않아 이름 기반 통신 불가**.

| 네트워크 종류 | DNS 이름 통신 | 비고 |
|---|---|---|
| **default bridge** | ❌ | IP로만 통신, 레거시 |
| **사용자 정의 브릿지** | ✅ | 내장 DNS 자동 동작 |
| **host** | — | 호스트 네트워크 그대로 사용 |
| **overlay** | ✅ | 멀티 호스트(Swarm/K8s) |

**이름 기반 통신을 원할 때:**
```bash
docker network create my-net
docker run --network my-net --name prometheus ...
docker run --network my-net --name grafana ...
```

**Docker Compose는 자동으로 사용자 정의 브릿지 네트워크를 생성**해주므로 별도 설정 없이 서비스 이름 통신이 된다.

> **면접 예상 질문:** Docker Compose 없이 두 컨테이너를 이름으로 통신시키려면 어떻게 해야 하는가?

---

### East-West vs North-South 트래픽

네트워크 트래픽 방향을 두 축으로 구분하는 표준 용어.

| 방향 | 의미 | 예시 | 포트 매핑 |
|---|---|---|---|
| **East-West** | 컨테이너 ↔ 컨테이너 (가상 네트워크 내부) | Grafana → Prometheus | ❌ 불필요 |
| **North-South** | 호스트/외부 ↔ 컨테이너 | 브라우저 → Grafana | ✅ 필요 |

**보안 관점:**
- **DB 같은 민감 컨테이너는 포트 매핑을 빼서** 외부 접근 차단
- 내부 East-West 통신만 허용 → 공격 표면(attack surface) 축소
- Compose 운영 환경에서 흔히 적용하는 패턴

> **면접 예상 질문:** East-West/North-South 트래픽이란? 운영 환경에서 DB 컨테이너의 포트 매핑을 빼는 이유는?

---

### 면접 모범 답변 템플릿

> **Q. Docker Compose에서 컨테이너끼리 통신할 때 왜 `localhost`가 아니라 서비스 이름을 써야 하나요?**

> "`localhost`는 명령을 실행하는 주체 자기 자신을 가리킵니다. Grafana 컨테이너 안에서 `localhost:9090`을 호출하면 Grafana 자기 자신을 의미하기 때문에 Prometheus를 찾을 수 없습니다.
>
> 그래서 `prometheus:9090`처럼 서비스명:포트 형식을 써야 합니다. 컨테이너 IP는 재시작 시 변경될 수 있어 서비스명 통신이 더 안정적입니다.
>
> 이게 가능한 이유는 Docker Compose가 사용자 정의 브릿지 네트워크와 내장 DNS 서버(127.0.0.11)를 자동으로 만들어 서비스명 → IP 변환을 처리하기 때문입니다.
>
> Compose 없이 `docker run`으로 띄울 때는 기본 브릿지에서 DNS가 동작하지 않으므로, `docker network create`로 사용자 정의 브릿지 네트워크를 직접 만들어 연결해야 합니다."

---

## 학습 정리

- `ports: 'A:B'`는 **호스트 포트 A ↔ 컨테이너 포트 B** 다리(포트 매핑)
- `localhost` = **명령 실행 주체 자기 자신** — 컨테이너 안에선 그 컨테이너를 의미
- Compose는 **사용자 정의 브릿지 네트워크**를 자동 생성, 서비스명이 호스트네임이 됨
- **내장 DNS 서버(127.0.0.11)** 가 서비스명 → IP 변환을 담당 (서비스 디스커버리)
- 컨테이너 IP는 재시작 시 변경 가능 → **서비스명 통신이 안정적**
- 기본 브릿지에서는 DNS 동작 X → 이름 통신 원하면 사용자 정의 브릿지 생성 필요
- **East-West(컨테이너↔컨테이너)** 는 포트 매핑 불필요, **North-South(호스트↔컨테이너)** 는 필요
- 운영에서는 DB 등 민감 컨테이너의 포트 매핑을 빼서 공격 표면 축소

## 참고

- Docker 공식 문서 — Networking overview, Embedded DNS server
- Docker Compose Networking — User-defined bridge network
- Prometheus + Grafana 모니터링 인프라 구성 실습 기반
