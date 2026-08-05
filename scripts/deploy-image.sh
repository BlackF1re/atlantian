#!/usr/bin/env bash
# Deprecated deliberately: replacing the active SD from Linux is unsafe.
# Use deploy-via-network.sh for normal deployment.  UART is emergency-only.
set -euo pipefail

echo 'deploy-image.sh is disabled: use deploy-via-network.sh for normal deployment' >&2
exit 64

if [[ $# -lt 1 ]]; then
  echo 'usage: deploy-image.sh <image> [board-ip]' >&2
  exit 64
fi
IMAGE=$1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STATE=${ATLANTIAN_STATE_DIR:-$ROOT/state}
if [[ $# -ge 2 ]]; then
  BOARD=$2
elif [[ -n ${ATLANTIAN_BOARD:-} ]]; then
  BOARD=$ATLANTIAN_BOARD
elif [[ -r $STATE/board.address ]]; then
  BOARD=$(<"$STATE/board.address")
else
  BOARD=192.168.2.112
fi
USER=${ATLANTIAN_USER:-paul}
PORT=${ATLANTIAN_HTTP_PORT:-18080}
TIMEOUT=${ATLANTIAN_BOOT_TIMEOUT:-240}
[[ -f $IMAGE ]] || { echo "image not found: $IMAGE" >&2; exit 2; }
[[ $BOARD =~ ^[0-9a-fA-F:.]+$ ]] || { echo "invalid board address: $BOARD" >&2; exit 2; }
if [[ -z ${ATLANTIAN_HTTP_PORT:-} ]]; then
  for candidate in $(seq 18080 18099); do
    if ! ss -ltn "sport = :$candidate" | grep -q LISTEN; then
      PORT=$candidate
      break
    fi
  done
fi
ss -ltn "sport = :$PORT" | grep -q LISTEN && {
  echo "HTTP port $PORT is already in use" >&2
  exit 4
}
SHA=$(sha256sum "$IMAGE" | awk '{print $1}')
DIR=$(dirname "$(readlink -f "$IMAGE")")
NAME=$(basename "$IMAGE")
KERNEL_VERSION=$(basename "$IMAGE" | sed -n 's/^atlantian-s9-\(.*\)\.img$/\1/p')
RELEASE_ID=${ATLANTIAN_RELEASE_ID:-development-${KERNEL_VERSION}}
LOCAL_IP=$(ip route get "$BOARD" | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
[[ -n $LOCAL_IP ]] || { echo "cannot determine LAN address for $BOARD" >&2; exit 3; }
PREVIOUS_BOOT_ID=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
  "$USER@$BOARD" 'cat /proc/sys/kernel/random/boot_id') || {
  echo "cannot read board boot ID before deployment" >&2
  exit 3
}

python3 -m http.server "$PORT" --bind "$LOCAL_IP" --directory "$DIR" >/tmp/atlantian-http.log 2>&1 &
HTTP_PID=$!
cleanup() { kill "$HTTP_PID" 2>/dev/null || true; wait "$HTTP_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 1
kill -0 "$HTTP_PID" || { cat /tmp/atlantian-http.log >&2; exit 4; }

set +e
ARM_OUTPUT=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$USER@$BOARD" \
  "sudo -n /usr/local/sbin/atlantian-ramflash http://$LOCAL_IP:$PORT/$NAME $SHA" 2>&1)
ARM_RC=$?
set -e
printf '%s\n' "$ARM_OUTPUT"
# A successful raw flasher intentionally drops SSH when it reboots.  Reject
# only commands which failed before acknowledging that hand-over.
[[ $ARM_OUTPUT == *'SD rewrite armed in RAM'* ]] || {
  echo "DEPLOY FAIL: updater was not armed (ssh rc=$ARM_RC)" >&2
  exit 5
}

deadline=$((SECONDS + TIMEOUT))
while (( SECONDS < deadline )); do
  if ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new "$USER@$BOARD" \
    "test \"\$(cat /proc/sys/kernel/random/boot_id)\" != \"$PREVIOUS_BOOT_ID\" && \
     test \"\$(cat /etc/atlantian-release)\" = \"$RELEASE_ID\" && \
     findmnt -no OPTIONS / | grep -qw rw && \
     systemctl is-active --quiet ssh && systemctl is-active --quiet systemd-networkd && \
     systemctl is-active --quiet atlantian-status-leds"; then
    echo "DEPLOY PASS: $BOARD booted deployed image"
    exit 0
  fi
  sleep 3
done
echo "DEPLOY FAIL: board did not pass post-boot checks within ${TIMEOUT}s" >&2
exit 1
