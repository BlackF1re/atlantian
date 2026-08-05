#!/usr/bin/env bash
# The only supported entry point for post-bootstrap releases on grey-subdevice.
# It rebuilds the smallest valid set of artifacts, then deploys and waits for PASS.
# userspace: rootfs + image; dtb: DTB + image; kernel: kernel + image;
# boot/layout: image only.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo 'usage: build-and-deploy.sh {userspace|dtb|kernel|boot|layout|all|deploy} [board-ip]' >&2
  exit 64
fi
CHANGE=$1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/config/release.env"
IMAGE="$ROOT/artifacts/current/${ATLANTIAN_IMAGE_NAME}.img"
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

case "$CHANGE" in
  userspace) "$ROOT/scripts/build-incremental.sh" rootfs; "$ROOT/scripts/build-incremental.sh" image ;;
  dtb)       "$ROOT/scripts/build-incremental.sh" dtb; "$ROOT/scripts/build-incremental.sh" image ;;
  kernel)    "$ROOT/scripts/build-incremental.sh" kernel; "$ROOT/scripts/build-incremental.sh" image ;;
  boot|layout) "$ROOT/scripts/build-incremental.sh" image ;;
  all)       "$ROOT/scripts/build-incremental.sh" all ;;
  deploy)    : ;; # re-deploy the already verified current image
  *) echo "unknown change class: $CHANGE" >&2; exit 64 ;;
esac

[[ -f "$STATE/autodeploy.enabled" ]] || {
  echo "autodeploy is locked until the first baseline boot passes" >&2
  exit 75
}
# Standard route: a static tmpfs flasher runs over SSH, verifies the SD by
# direct read-back and resets the PS. UART/U-Boot is emergency-only when the
# installed system cannot be reached.
exec "$ROOT/scripts/deploy-via-network.sh" "$IMAGE" "$BOARD"
