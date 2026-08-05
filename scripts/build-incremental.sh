#!/usr/bin/env bash
# Incremental AtlANTian builder. Run it from anywhere; only requested stages
# are rebuilt.  `all` is for a deliberately complete release rebuild.
set -euo pipefail

TARGET=${1:-all}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../config/release.env
. "$ROOT/config/release.env"
RELEASE_DIR=${RELEASE_DIR:-$ROOT/artifacts/current}
IMAGE=${IMAGE:-$RELEASE_DIR/${ATLANTIAN_IMAGE_NAME}.img}
SYSTEM_IMAGE=${SYSTEM_IMAGE:-$RELEASE_DIR/${ATLANTIAN_IMAGE_NAME}.system.ext4}
BOOT_BIN=${BOOT_BIN:-$ROOT/boot-candidate/BOOT.bin}

notify() {
  local title=$1 body=$2 urgency=${3:-normal}
  XDG_RUNTIME_DIR=/run/user/$(id -u) \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus \
    notify-send --urgency="$urgency" "$title" "$body" 2>/dev/null || true
}

failed() {
  local rc=$?
  notify "AtlANTian build failed" "$TARGET (exit $rc)" critical
  exit "$rc"
}
trap failed ERR

rootfs() {
  sudo env ATLANTIAN_RELEASE="$ATLANTIAN_RELEASE_ID" "$ROOT/scripts/build-rootfs.sh"
  deploy_key=${ATLANTIAN_DEPLOY_KEY_FILE:-$HOME/.ssh/id_universal.pub}
  [[ -r "$deploy_key" ]] || deploy_key=
  sudo env ATLANTIAN_DEPLOY_KEY_FILE="$deploy_key" \
    "$ROOT/scripts/configure-rootfs-access.sh" "$ROOT/out/rootfs"
}

kernel() { sudo "$ROOT/scripts/build-kernel.sh"; }
dtb() { sudo "$ROOT/scripts/build-kernel.sh" dtb; }
recovery() { sudo "$ROOT/scripts/make-recovery-initramfs.sh"; }

image() {
  recovery
  mkdir -p "$RELEASE_DIR"
  sudo env BOOT_BIN="$BOOT_BIN" DTB="$ROOT/out/boot/devicetree.dtb" \
    ZIMAGE="$ROOT/out/boot/zImage" OUT="$IMAGE" SYSTEM_OUT="$SYSTEM_IMAGE" \
    "$ROOT/scripts/make-sd-image.sh"
  # Store portable basenames: the same checksum file is uploaded to GitHub
  # and consumed by atlantian-sysupgrade after downloading into /tmp.
  ( cd "$RELEASE_DIR" && sha256sum "$(basename "$IMAGE")" "$(basename "$SYSTEM_IMAGE")" > SHA256SUMS )
  sudo chown "$(id -u):$(id -g)" "$RELEASE_DIR/SHA256SUMS"
}

case "$TARGET" in
  rootfs) rootfs ;;
  kernel) kernel ;;
  dtb) dtb ;;
  image) image ;;
  recovery) recovery ;;
  all) rootfs; kernel; image ;;
  *) echo "usage: $0 {rootfs|kernel|dtb|recovery|image|all}" >&2; exit 64 ;;
esac

notify "AtlANTian build complete" "$TARGET: $(basename "$IMAGE")"
echo "AtlANTian build completed: $TARGET"
