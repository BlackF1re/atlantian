#!/usr/bin/env bash
# Host-side contract test.  The production script is deliberately tied to the
# board's D3 LEDs, so CI verifies its static, hardware-specific contract.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE=$ROOT/scripts/atlantian-update-leds.sh

sh -n "$SOURCE"
grep -qx "PATTERN='red red red green green green'" "$SOURCE"
grep -qx 'ON_SECONDS=0.05' "$SOURCE"
grep -qx 'OFF_SECONDS=0.05' "$SOURCE"
grep -Fqx 'trap terminate INT TERM HUP' "$SOURCE"
grep -Fqx 'systemctl stop $SERVICES >/dev/null 2>&1 || true' "$SOURCE"
echo 'update LED contract passed'
