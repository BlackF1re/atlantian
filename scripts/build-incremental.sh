#!/usr/bin/env bash
set -euo pipefail

TARGET=${1:-all}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
. config/release.env

DIR=${RELEASE_DIR:-$ROOT/artifacts/current}
IMAGE=${IMAGE:-$DIR/${ATLANTIAN_IMAGE_NAME}.img}
BOOT_BIN=${BOOT_BIN:-$ROOT/boot-candidate/BOOT.bin}

rootfs() { sudo "$ROOT/scripts/build-rootfs.sh"; }
kernel() { sudo "$ROOT/scripts/build-kernel.sh"; }
stamp() { sudo -E "$ROOT/scripts/stamp-release.sh" "$ROOT/out/rootfs"; }
packages() { "$ROOT/scripts/build-atlantian-debs.sh"; }
image() {
  mkdir -p "$DIR"
  rm -f "$DIR"/*.img "$DIR"/*.deb "$DIR"/*.packages.tsv "$DIR"/*.snapshot.txt "$DIR"/SHA256SUMS
  stamp
  packages
  sudo env BOOT_BIN="$BOOT_BIN" DTB="$ROOT/out/boot/devicetree.dtb" \
    ZIMAGE="$ROOT/out/boot/zImage" OUT="$IMAGE" "$ROOT/scripts/make-sd-image.sh"
  (cd "$DIR" && sha256sum *.img *.deb *.packages.tsv *.snapshot.txt >SHA256SUMS)
  sudo chown -R "$(id -u):$(id -g)" "$DIR"
}

case "$TARGET" in
  rootfs) rootfs ;;
  kernel) kernel ;;
  image) image ;;
  rootfs-image) rootfs; kernel; image ;;
  kernel-image) kernel; image ;;
  all) rootfs; kernel; image ;;
  *) echo 'usage: build-incremental.sh {rootfs|kernel|image|rootfs-image|kernel-image|all}' >&2; exit 64 ;;
esac

echo "AtlANTian build completed: $TARGET"
