# infra

OCI(Oracle Cloud) VM 한 대에 여러 서비스를 올릴 때 쓰는 인프라 스크립트 모음.
Caddy가 80/443을 맡고, 서비스는 Docker 컨테이너로 같은 네트워크(`dnm`) 뒤에 둔다.

```
인터넷 ─▶ Caddy(80/443, 자동 HTTPS) ─▶ dnm 네트워크 ─▶ 서비스 컨테이너들
```

## 스크립트

| 파일 | 하는 일 |
|---|---|
| [`host-init.sh`](host-init.sh) | Docker 설치, 80/443 방화벽(iptables), `dnm` 네트워크, Caddy 기동. 멱등이라 여러 번 실행해도 안전하다. |
| [`add-site.sh`](add-site.sh) | 도메인 하나를 컨테이너에 연결하는 사이트 블록을 만들고 Caddy를 reload한다. |
| [`doctor.sh`](doctor.sh) | 서버 점검(읽기 전용): NTP·디스크·Docker·방화벽·재시작 정책, 사이트별 네트워크 연결·DNS·HTTPS, env 파일 권한, 백업 cron. 신규 서버와 이전 직후에 실행한다. |

## 사용 순서

```bash
# 1) 서버 기반 (VM당 1회)
./host-init.sh

# 2) 서비스를 컨테이너로 띄운 뒤 dnm 네트워크에 붙인다 (compose 서비스도 동일)
docker network connect dnm <컨테이너>

# 3) 도메인 연결 — 인증서 발급·갱신과 80→443 리다이렉트는 Caddy가 자동 처리
./add-site.sh app.example.com <컨테이너>:<포트>
```

사이트를 빼려면 `~/caddy/sites/<도메인>.caddy`를 지우고 `docker exec caddy caddy reload --config /etc/caddy/Caddyfile`.

## 동작 원칙

- **기존 설정을 덮어쓰지 않는다.** 이미 있는 `~/caddy/Caddyfile`은 `import sites/*.caddy` 한 줄만 보장하고, 떠 있는 Caddy 컨테이너는 그대로 둔다.
- **인증서는 `caddy_data` 볼륨에 보존한다.** 지우면 재발급이 반복되어 Let's Encrypt 한도에 걸린다.
- **OCI는 방화벽이 두 겹이다.** 이 스크립트는 OS(iptables)만 연다. 콘솔의 보안 목록(Security List)에서 80/443 인바운드는 따로 열어야 한다.
- 비밀 값(API 키, 토큰)은 이 저장소에 두지 않는다. 서비스별 env 파일은 서버의 홈 디렉터리에 `chmod 600`으로 둔다.

## 브랜치·커밋 규정

- 브랜치: `<타입>/<kebab-case-요약>` — 예: `feat/doctor-script`, `fix/caddy-reload`
- 타입: `feat` · `fix` · `docs` · `chore` · `refactor` · `test` (커밋 접두어와 동일)
- 커밋: `<타입>: <한국어 요약>` — 예: `feat: 서버 점검 스크립트 추가`
- `main`에는 직접 커밋하지 않고 PR로 머지한다. 머지 전에 새 VM이나 로컬 `bash -n`으로 동작을 확인한다.

## 요구 사항

Ubuntu 22.04/24.04 (aarch64·x86_64 모두), sudo 권한.
