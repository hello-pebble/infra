#!/usr/bin/env bash
# 한 VM에 여러 서비스를 올리기 위한 공용 기반(1회, 멱등): Docker + 80/443 방화벽 + dnm 네트워크 + Caddy.
# Caddy는 ~/caddy/sites/*.caddy 를 모두 읽는다 — 서비스는 ./deploy/add-site.sh 로 파일 하나씩 추가하고,
# 이미 떠 있는 Caddy·인증서(caddy_data 볼륨)는 건드리지 않는다.
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo systemctl enable --now docker
fi

# OCI 우분투 이미지는 기본 iptables가 인바운드를 막는다(콘솔 보안 목록과 별개로 OS에서도 열어야 한다).
for port in 80 443; do
  if ! sudo iptables -C INPUT -p tcp --dport "${port}" -j ACCEPT 2>/dev/null; then
    sudo iptables -I INPUT 1 -p tcp --dport "${port}" -j ACCEPT
    if command -v netfilter-persistent >/dev/null 2>&1; then sudo netfilter-persistent save || true; fi
  fi
done

sudo docker network create dnm 2>/dev/null || true

mkdir -p ~/caddy/sites
# 기존 Caddyfile(직접 쓴 사이트 블록 포함)은 덮어쓰지 않는다. import 줄만 보장한다.
grep -qs '^import sites/' ~/caddy/Caddyfile || echo 'import sites/*.caddy' >> ~/caddy/Caddyfile

if [ -z "$(sudo docker ps -q -f name='^caddy$')" ]; then
  sudo docker rm -f caddy 2>/dev/null || true
  # caddy_data 볼륨은 인증서 보존용 — 지우면 재발급이 반복돼 Let's Encrypt 한도에 걸린다.
  sudo docker run -d --name caddy --restart unless-stopped --network dnm \
    -p 80:80 -p 443:443 \
    -v ~/caddy:/etc/caddy:ro -v caddy_data:/data \
    caddy:2
else
  echo "==> caddy 실행 중 — 그대로 둠"
fi
