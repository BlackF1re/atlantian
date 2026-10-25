#!/usr/bin/env bash
# D3 update indicator contracts for the installed unified RAM updater.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE=$ROOT/scripts/atlantian-update-leds.sh
UPGRADER=$ROOT/scripts/atlantian-ram-upgrade.sh
sh -n "$SOURCE"; bash -n "$UPGRADER"
grep -qx "PATTERN='red red red green green green'" "$SOURCE"
grep -qx 'ON_SECONDS=0.05' "$SOURCE"
grep -qx 'OFF_SECONDS=0.05' "$SOURCE"
grep -Fqx 'trap terminate INT TERM HUP' "$SOURCE"
grep -Fqx 'RESTART_SERVICES=${ATLANTIAN_UPDATE_RESTART_SERVICES:-1}' "$SOURCE"
grep -Fq 'systemctl stop $SERVICES >/dev/null 2>&1 || true' "$SOURCE"
! grep -qi 'recovery' "$SOURCE"

grep -Fq 'start_update_leds() {' "$UPGRADER"
grep -Fq 'stop_update_leds() {' "$UPGRADER"
grep -Fq 'ATLANTIAN_UPDATE_RESTART_SERVICES=0 /usr/local/sbin/atlantian-update-leds' "$UPGRADER"
grep -Fq 'stop_update_leds' "$UPGRADER"
grep -Fq "systemctl kexec || { kexec -u || true; cleanup; fail 'systemd kexec failed'; }" "$UPGRADER"
grep -Fq 'systemctl start atlantian-status-leds.service atlantian-fpga-status-leds.service' "$UPGRADER"
# Indicator starts during preparation, before authenticated artifact downloads.
python3 - "$UPGRADER" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
assert s.index('start_update_leds\n. /etc/atlantian/releases.conf') < s.index("fetch SHA256SUMS 'release checksums'")
assert s.index('stop_update_leds\n') < s.index('mount -t tmpfs')
PY

echo 'RAM-only system-update LED contract passed'
