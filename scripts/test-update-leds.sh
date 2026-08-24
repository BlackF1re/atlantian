#!/usr/bin/env bash
# Host-side contract for the board-specific D3 update indicator and SD updater lifecycle.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE=$ROOT/scripts/atlantian-update-leds.sh
UPGRADER=$ROOT/scripts/atlantian-sysupgrade-sd.sh
sh -n "$SOURCE"; sh -n "$UPGRADER"
grep -qx "PATTERN='red red red green green green'" "$SOURCE"
grep -qx 'ON_SECONDS=0.05' "$SOURCE"
grep -qx 'OFF_SECONDS=0.05' "$SOURCE"
grep -Fqx 'trap terminate INT TERM HUP' "$SOURCE"
grep -Fqx 'RESTART_SERVICES=${ATLANTIAN_UPDATE_RESTART_SERVICES:-1}' "$SOURCE"
grep -Fq 'systemctl stop $SERVICES >/dev/null 2>&1 || true' "$SOURCE"
! grep -qi 'recovery' "$SOURCE"

grep -Fq 'ATLANTIAN_UPDATE_RESTART_SERVICES=0 "$LED_HELPER" &' "$UPGRADER"
grep -Fq 'trap restore_update_leds EXIT' "$UPGRADER"
grep -Fq 'trap - EXIT INT TERM HUP' "$UPGRADER"
grep -Fq 'wait "$ledpid" || true' "$UPGRADER"
# The indicator must start before any release payload download begins. Match the
# actual call sequence rather than source line numbers/formatting.
grep -Fq 'start_update_leds; download_and_verify' "$UPGRADER"

echo 'update LED contract passed'
