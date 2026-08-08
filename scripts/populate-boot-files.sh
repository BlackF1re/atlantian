#!/usr/bin/env bash
# Populate one FAT boot tree from the source-built bootloader + kernel assets.
set -euo pipefail

TARGET=${1:?usage: populate-boot-files.sh TARGET_DIR}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/config/release.env"

BOOT_BIN=${BOOT_BIN:-$ROOT/out/bootloader/BOOT.bin}
UBOOT_IMG=${UBOOT_IMG:-$ROOT/out/bootloader/u-boot.img}
DTB=${DTB:-$ROOT/out/boot/devicetree.dtb}
ZIMAGE=${ZIMAGE:-$ROOT/out/boot/zImage}

for f in "$BOOT_BIN" "$UBOOT_IMG" "$DTB" "$ZIMAGE"; do
  [[ -s $f ]] || { echo "missing boot input: $f" >&2; exit 2; }
done
mkdir -p "$TARGET"

install -m 0644 "$BOOT_BIN" "$TARGET/BOOT.bin"
install -m 0644 "$UBOOT_IMG" "$TARGET/u-boot.img"
install -m 0644 "$DTB" "$TARGET/devicetree.dtb"
install -m 0644 "$ZIMAGE" "$TARGET/zImage"

mkimage -A arm -O linux -T kernel -C none \
  -a 0x00008000 -e 0x00008000 \
  -n "AtlANTian ${ATLANTIAN_RELEASE_ID}" \
  -d "$ZIMAGE" "$TARGET/uImage"

cat >"$TARGET/uEnv.txt" <<'EOF_UENV'
atlantian_normal_bootargs=console=ttyPS0,115200n8 root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait
bootcmd=setenv bootargs ${atlantian_normal_bootargs}; fatload mmc 0:1 0x02000000 uImage && fatload mmc 0:1 0x01F00000 devicetree.dtb && bootm 0x02000000 - 0x01F00000
EOF_UENV

cmd=$(mktemp)
trap 'rm -f "$cmd"' EXIT
cat >"$cmd" <<'EOF_BOOT'
echo Booting AtlANTian from microSD...
setenv bootargs console=ttyPS0,115200n8 root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait
if fatload mmc 0:1 0x02000000 uImage && fatload mmc 0:1 0x01F00000 devicetree.dtb; then
    bootm 0x02000000 - 0x01F00000
fi
echo AtlANTian boot failed; returning to U-Boot
EOF_BOOT
mkimage -A arm -T script -C none -n 'AtlANTian microSD boot' -d "$cmd" "$TARGET/boot.scr"

# There must never be a Linux-side fixed RAM cap. DDR size is detected by the
# Antminer S9 U-Boot target on every cold boot and then fixed into the Linux DT.
! grep -Eq '(^|[[:space:]])mem=[^[:space:]]+' "$TARGET/uEnv.txt"
! strings "$TARGET/boot.scr" | grep -Eq '(^|[[:space:]])mem=[^[:space:]]+'
