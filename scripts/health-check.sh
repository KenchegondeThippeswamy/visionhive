#!/usr/bin/env bash
# Simple server health check. Exit code 0 = healthy, 1 = problem (so cron/CI can alert).
# Usage: DISK_MAX=80 MEM_MAX=85 SERVICES="ssh cron docker" URL="http://localhost:8080/health" ./health-check.sh
set -uo pipefail

DISK_MAX=${DISK_MAX:-80}
MEM_MAX=${MEM_MAX:-85}
SERVICES=${SERVICES:-"ssh cron"}
URL=${URL:-""}
problems=0

log() { echo "$(date '+%F %T') $*"; }
fail() { log "FAIL: $*"; problems=$((problems + 1)); }
ok() { log "OK:   $*"; }

# Disk usage of /
disk=$(df / --output=pcent | tail -1 | tr -dc '0-9')
if (( disk >= DISK_MAX )); then fail "disk ${disk}% (limit ${DISK_MAX}%)"; else ok "disk ${disk}%"; fi

# Memory usage
mem=$(free | awk '/Mem:/ {printf "%d", $3/$2*100}')
if (( mem >= MEM_MAX )); then fail "memory ${mem}% (limit ${MEM_MAX}%)"; else ok "memory ${mem}%"; fi

# Load average vs CPU count
load=$(awk '{print $1}' /proc/loadavg)
cpus=$(nproc)
if awk -v l="$load" -v c="$cpus" 'BEGIN{exit !(l > c*2)}'; then fail "load $load on $cpus CPUs"; else ok "load $load on $cpus CPUs"; fi

# Services
for s in $SERVICES; do
  if systemctl is-active --quiet "$s"; then ok "service $s active"; else fail "service $s NOT active"; fi
done

# Optional HTTP check
if [[ -n "$URL" ]]; then
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$URL" || true)
  if [[ "$code" == "200" ]]; then ok "$URL returned 200"; else fail "$URL returned ${code:-none}"; fi
fi

if (( problems > 0 )); then log "RESULT: $problems problem(s)"; exit 1; fi
log "RESULT: healthy"
