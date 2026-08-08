#!/usr/bin/env bash
set -euo pipefail

TARGET=${1:-all}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
. config/release.env

DIR=${RELEASE_DIR:-$ROOT/artifacts/current}
IMAGE=${IMAGE:-$DIR/${ATLANTIAN_IMAGE_NAME}.img}
BOOT_BIN=${BOOT_BIN:-$ROOT/out/bootloader/BOOT.bin}
UBOOT_IMG=${UBOOT_IMG:-$ROOT/out/bootloader/u-boot.img}

rootfs() { sudo "$ROOT/scripts/build-rootfs.sh"; }
kernel() { sudo "$ROOT/scripts/build-kernel.sh"; }
bootloader() { "$ROOT/scripts/build-uboot.sh"; }
stamp() { sudo -E bash "$ROOT/scripts/stamp-release.sh" "$ROOT/out/rootfs"; }
packages() { "$ROOT/scripts/build-atlantian-debs.sh"; }
image() {
  mkdir -p "$DIR"
  rm -f "$DIR"/*.img "$DIR"/*.deb "$DIR"/*.packages.tsv "$DIR"/*.snapshot.txt "$DIR"/SHA256SUMS
  [[ -s $BOOT_BIN && -s $UBOOT_IMG ]] || bootloader
  stamp
  packages
  sudo env BOOT_BIN="$BOOT_BIN" UBOOT_IMG="$UBOOT_IMG" \
    DTB="$ROOT/out/boot/devicetree.dtb" ZIMAGE="$ROOT/out/boot/zImage" \
    OUT="$IMAGE" "$ROOT/scripts/make-sd-image.sh"
  (cd "$DIR" && sha256sum *.img *.deb *.packages.tsv *.snapshot.txt >SHA256SUMS)
  sudo chown -R "$(id -u):$(id -g)" "$DIR"
}

case "$TARGET" in
  rootfs) rootfs ;;
  kernel) kernel ;;
  bootloader) bootloader ;;
  image) image ;;
  rootfs-image) rootfs; kernel; image ;;
  kernel-image) kernel; image ;;
  all) rootfs; kernel; bootloader; image ;;
  *) echo 'usage: build-incremental.sh {rootfs|kernel|bootloader|image|rootfs-image|kernel-image|all}' >&2; exit 64 ;;
esac

echo "AtlANTian build completed: $TARGET"
