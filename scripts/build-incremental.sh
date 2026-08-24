#!/usr/bin/env bash
set -euo pipefail

TARGET=${1:-all}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
. config/release.env

DIR=${RELEASE_DIR:-$ROOT/artifacts/current}
SD_IMAGE=${SD_IMAGE:-$DIR/${ATLANTIAN_IMAGE_NAME}.img}
COMPRESSED_IMAGE=${COMPRESSED_IMAGE:-$SD_IMAGE.xz}
BOOT_BIN=${BOOT_BIN:-$ROOT/out/bootloader/BOOT.bin}
UBOOT_IMG=${UBOOT_IMG:-$ROOT/out/bootloader/u-boot.img}
INITRAMFS=${INITRAMFS:-$ROOT/out/nand/initramfs.cpio.gz}

preflight() {
  "$ROOT/scripts/test-build-orchestration.sh"
  "$ROOT/scripts/test-runtime-policy.sh"
  "$ROOT/scripts/test-source-contracts.sh"
}
need_dir() { [[ -d $1 ]] || { echo "missing prerequisite directory: $1" >&2; exit 2; }; }
need_file() { [[ -s $1 ]] || { echo "missing prerequisite file: $1" >&2; exit 2; }; }

rootfs() {
  sudo -E "$ROOT/scripts/build-rootfs.sh"
  sudo -E "$ROOT/scripts/extract-nand-busybox.sh"
  sudo -E "$ROOT/scripts/build-nand-rootfs.sh"
  sudo "$ROOT/scripts/install-runtime-policy.sh" "$ROOT/out/rootfs"
  sudo "$ROOT/scripts/install-runtime-policy.sh" "$ROOT/out/rootfs-nand"
  sudo "$ROOT/scripts/install-nand-tools.sh" "$ROOT/out/rootfs" sd
  sudo "$ROOT/scripts/install-nand-tools.sh" "$ROOT/out/rootfs-nand" nand
}

kernel() {
  need_dir "$ROOT/out/rootfs"; need_dir "$ROOT/out/rootfs-nand"
  sudo -E "$ROOT/scripts/build-kernel.sh"
  for opt in CONFIG_MTD_NAND_PL35X CONFIG_MTD_NAND_ECC_SW_BCH CONFIG_MTD_UBI CONFIG_MTD_UBI_BLOCK \
    CONFIG_UBIFS_FS CONFIG_SQUASHFS CONFIG_SQUASHFS_ZSTD CONFIG_OVERLAY_FS CONFIG_EXT4_FS; do
    grep -qx "${opt}=y" "$ROOT/out/boot/kernel.config" || { echo "NAND early-root option is not built in: $opt" >&2; exit 3; }
  done
  sudo "$ROOT/scripts/strip-kernel-modules.sh" "$ROOT/out/rootfs"
  sudo rm -rf "$ROOT/out/rootfs-nand/lib/modules"; sudo mkdir -p "$ROOT/out/rootfs-nand/lib/modules"
  sudo rsync -aHAX --numeric-ids "$ROOT/out/rootfs/lib/modules/" "$ROOT/out/rootfs-nand/lib/modules/"
}

stamp() {
  sudo -E "$ROOT/scripts/stamp-release.sh" "$ROOT/out/rootfs"
  sudo -E "$ROOT/scripts/stamp-release.sh" "$ROOT/out/rootfs-nand"
}
nand_initramfs() {
  need_dir "$ROOT/out/rootfs-nand"; need_file "$ROOT/out/build-tools/busybox-static-armhf"
  ROOTFS="$ROOT/out/rootfs-nand" OUT="$INITRAMFS" "$ROOT/scripts/build-nand-initramfs.sh"
}
bootloader() {
  need_file "$ROOT/out/boot/zImage"; need_file "$ROOT/out/boot/devicetree.dtb"; need_dir "$ROOT/out/rootfs-nand"
  stamp; nand_initramfs
  "$ROOT/scripts/build-uboot.sh"
  INITRAMFS="$INITRAMFS" "$ROOT/scripts/build-uboot-nand.sh"
}
packages() { "$ROOT/scripts/build-atlantian-debs.sh"; }
nand_products() {
  need_file "$INITRAMFS"; need_dir "$ROOT/out/rootfs-nand"
  INITRAMFS="$INITRAMFS" ROOTFS="$ROOT/out/rootfs-nand" "$ROOT/scripts/build-nand-bundle.sh"
}
embed_nand() {
  sudo env ROOTFS="$ROOT/out/rootfs" BUNDLE="$ROOT/out/nand/bundle" "$ROOT/scripts/embed-nand-bundle.sh"
}
artifacts() {
  need_dir "$ROOT/out/rootfs"; need_dir "$ROOT/out/rootfs-nand"; need_file "$ROOT/out/boot/zImage"; need_file "$ROOT/out/boot/devicetree.dtb"
  mkdir -p "$DIR"
  rm -f "$DIR"/*.img "$DIR"/*.img.xz "$DIR"/*.deb "$DIR"/*.tar.zst "$DIR"/*.packages.tsv "$DIR"/*.snapshot.txt "$DIR"/RELEASE-METADATA.json "$DIR"/SHA256SUMS
  bootloader; packages; nand_products; embed_nand
  sudo env ROOTFS="$ROOT/out/rootfs" BOOT_BIN="$BOOT_BIN" UBOOT_IMG="$UBOOT_IMG" DTB="$ROOT/out/boot/devicetree.dtb" ZIMAGE="$ROOT/out/boot/zImage" OUT="$SD_IMAGE" "$ROOT/scripts/make-sd-image.sh"
  "$ROOT/scripts/generate-release-metadata.sh" "$SD_IMAGE" "$DIR/RELEASE-METADATA.json" "$ROOT/out/nand/bundle/NAND-MANIFEST.json"
  echo "Compressing $(basename "$SD_IMAGE") -> $(basename "$COMPRESSED_IMAGE")"
  rm -f "$COMPRESSED_IMAGE" "$COMPRESSED_IMAGE.tmp"
  xz -T0 -6 --check=crc64 -c "$SD_IMAGE" >"$COMPRESSED_IMAGE.tmp"; xz -t "$COMPRESSED_IMAGE.tmp"; mv "$COMPRESSED_IMAGE.tmp" "$COMPRESSED_IMAGE"
  raw_sha=$(sha256sum "$SD_IMAGE" | awk '{print $1}'); decoded_sha=$(xz -dc "$COMPRESSED_IMAGE" | sha256sum | awk '{print $1}')
  [[ $decoded_sha == "$raw_sha" ]] || { echo "compressed image round-trip checksum mismatch: $COMPRESSED_IMAGE" >&2; exit 1; }
  (cd "$DIR" && sha256sum *.img *.tar.zst *.deb RELEASE-METADATA.json >SHA256SUMS && sha256sum *.img.xz >>SHA256SUMS)
  sudo chown -R "${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}" "$DIR"
}
full() { rootfs; kernel; artifacts; }

if [[ ${ATLANTIAN_SKIP_PREFLIGHT:-0} != 1 ]]; then preflight; fi
case "$TARGET" in
  rootfs) rootfs ;;
  kernel) kernel ;;
  bootloader) bootloader ;;
  artifacts) artifacts ;;
  all) full ;;
  *) echo 'usage: build-incremental.sh {rootfs|kernel|bootloader|artifacts|all}' >&2; exit 64 ;;
esac
echo "AtlANTian build completed: $TARGET"
