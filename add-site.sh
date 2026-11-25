#!/usr/bin/env bash
# 도메인 하나를 컨테이너에 연결한다(멱등). 사용법:
#   ./deploy/add-site.sh <도메인> <컨테이너:포트>
#   ./deploy/add-site.sh delaynomoreapp.duckdns.org delaynomore:8080
#   ./deploy/add-site.sh n8n.duckdns.org n8n:5678
# 사전: ./deploy/host-init.sh 1회 실행, 대상 컨테이너가 dnm 네트워크에 있어야 한다
#   (compose 서비스는 `docker network connect dnm <컨테이너>` 한 줄이면 된다).
# 제거: rm ~/caddy/sites/<도메인>.caddy 후 아래 reload 명령.
set -euo pipefail

[ $# -eq 2 ] || { echo "사용법: $0 <도메인> <컨테이너:포트>" >&2; exit 1; }
domain="$1"; upstream="$2"

mkdir -p ~/caddy/sites
printf '%s {\n\treverse_proxy %s\n}\n' "${domain}" "${upstream}" > ~/caddy/sites/"${domain}".caddy

sudo docker exec caddy caddy reload --config /etc/caddy/Caddyfile
echo "==> ${domain} → ${upstream}"
