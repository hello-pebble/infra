#!/usr/bin/env bash
# 서버 점검(읽기 전용). 신규 서버 세팅 직후와 이전 직후에 돌린다. FAIL이 하나라도 있으면 종료코드 1.
#   ./doctor.sh
# 한계: OCI 콘솔 보안 목록(Security List)은 VM 안에서 읽을 수 없다. 아래 HTTPS 항목이 통과하면 열린 것이다.
fail=0
ok()   { echo "  ok   $1"; }
bad()  { echo "  FAIL $1"; fail=1; }
warn() { echo "  warn $1"; }
chk()  { local m="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$m"; else bad "$m"; fi; }

echo "[시스템]"
echo "  $(. /etc/os-release; echo "${PRETTY_NAME}") / $(uname -m) / $(nproc) CPU / $(free -g | awk '/Mem/{print $2}')GB RAM"
chk "시간 동기화(NTP) — 틀어지면 인증서 발급이 실패한다" bash -c 'timedatectl show -p NTPSynchronized --value | grep -qx yes'
used=$(df --output=pcent / | tail -1 | tr -dc 0-9)
if [ "${used}" -lt 80 ]; then ok "디스크 사용 ${used}%"; else warn "디스크 사용 ${used}% — docker image prune 고려"; fi
[ "$(free -m | awk '/Swap/{print $2}')" -gt 0 ] && ok "스왑 있음" || warn "스왑 없음 — JVM 앱 여러 개면 OOM 방어용으로 권장"

echo "[Docker·방화벽]"
chk "docker 동작" sudo docker info
chk "dnm 네트워크" sudo docker network inspect dnm
chk "caddy 실행 중" bash -c "[ -n \"\$(sudo docker ps -q -f name='^caddy\$')\" ]"
for p in 80 443; do chk "iptables ${p}/tcp 허용" sudo iptables -C INPUT -p tcp --dport "${p}" -j ACCEPT; done
sudo docker ps -q | xargs -r sudo docker inspect -f '{{.Name}} {{.HostConfig.RestartPolicy.Name}}' \
  | awk '$2!="always" && $2!="unless-stopped"{print "  warn 재시작 정책 없음: "$1}'

echo "[사이트] (~/caddy/sites/*.caddy)"
myip=$(curl -s -m 5 https://ifconfig.me)
for f in ~/caddy/sites/*.caddy; do
  [ -e "${f}" ] || { warn "등록된 사이트 없음"; break; }
  d=$(basename "${f}" .caddy); c=$(awk '/reverse_proxy/{print $2}' "${f}"); c=${c%%:*}
  chk "${d}: 컨테이너 ${c}가 dnm에 연결" bash -c "sudo docker inspect -f '{{json .NetworkSettings.Networks}}' '${c}' | grep -q '\"dnm\"'"
  dns=$(getent hosts "${d}" | awk '{print $1; exit}')
  [ "${dns}" = "${myip}" ] && ok "${d}: DNS가 이 서버(${myip})를 가리킴" || bad "${d}: DNS=${dns:-없음}, 이 서버=${myip}"
  [ "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://${d}")" != "000" ] && ok "${d}: HTTPS 응답" || bad "${d}: HTTPS 응답 없음(보안 목록 443·인증서 확인)"
done

echo "[비밀 파일]"
for f in ~/.*.env; do
  [ -e "${f}" ] || continue
  [ "$(stat -c %a "${f}")" = "600" ] && ok "${f} 권한 600" || bad "${f} 권한 $(stat -c %a "${f}") — chmod 600"
done
crontab -l 2>/dev/null | grep -q backup && ok "백업 cron 등록됨" || warn "백업 cron 없음"

exit "${fail}"
