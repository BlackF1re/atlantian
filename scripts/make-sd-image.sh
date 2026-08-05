#!/usr/bin/env bash
# Assemble a removable-SD test image.  It never writes a physical device.
set -euo pipefail

PROJECT=$(cd "$(dirname "$0")/.." && pwd)
. "$PROJECT/config/release.env"
ROOTFS=${ROOTFS:-$PROJECT/out/rootfs}
OUT=${OUT:-$PROJECT/out/${ATLANTIAN_IMAGE_NAME}.img}
SYSTEM_OUT=${SYSTEM_OUT:-${OUT%.img}.system.ext4}
BOOT_BIN=${BOOT_BIN:?set BOOT_BIN to the validated S9 BOOT.bin}
DTB=${DTB:?set DTB to the validated S9 device-tree blob}
UENV=${UENV:-}
# This is only the transport size.  First boot expands p3 (/data) and its
# filesystem to the full capacity of the inserted SD card.  p2 stays fixed
# and is the replaceable system payload for sysupgrade.
# The actual boot payload is about 27 MiB.  A 64-MiB FAT volume leaves a
# substantial margin for a recovery request and avoids shipping 192 MiB of
# permanently empty space.  Partition 2 is sized from the actual payload;
# p3 receives the remaining card capacity on first boot.
SIZE_MIB=${SIZE_MIB:-auto}
DATA_MIB=${DATA_MIB:-16}

if [[ $SIZE_MIB = auto ]]; then
  # Size the transport image from actual rootfs contents. Keep 25%
  # proportional slack and at least 64 MiB absolute slack for ext4 metadata,
  # and first-boot package work, then round to a 16-MiB boundary.  The first
  # data grow service still consumes the entire physical SD card.
  ROOT_USED_KIB=$(du -sk "$ROOTFS" | awk '{print $1}')
  ROOT_USED_MIB=$(((ROOT_USED_KIB + 1023) / 1024))
  ROOT_BY_RATIO=$(((ROOT_USED_MIB * 125 + 99) / 100))
  ROOT_BY_MARGIN=$((ROOT_USED_MIB + 64))
  (( ROOT_BY_RATIO > ROOT_BY_MARGIN )) && ROOT_MIB=$ROOT_BY_RATIO || ROOT_MIB=$ROOT_BY_MARGIN
  ROOT_MIB=$((((ROOT_MIB + 15) / 16) * 16))
  # Keep a small persistent data partition in the initial image.  It is
  # expanded to the end of the physical SD on first boot; system upgrades
  # replace only p2 and never touch p3.
  SIZE_MIB=$((65 + ROOT_MIB + DATA_MIB))
  SIZE_MIB=$((((SIZE_MIB + 15) / 16) * 16))
fi
[[ $SIZE_MIB =~ ^[0-9]+$ && $SIZE_MIB -ge 192 ]] || {
  echo "invalid SIZE_MIB: $SIZE_MIB" >&2; exit 2;
}

[[ -d "$ROOTFS" ]] || { echo "missing ROOTFS: $ROOTFS" >&2; exit 2; }
[[ -f "$BOOT_BIN" && -f "$DTB" ]] || { echo "missing BOOT_BIN or DTB" >&2; exit 2; }
[[ -z "$UENV" || -f "$UENV" ]] || { echo "missing UENV: $UENV" >&2; exit 2; }
ZIMAGE=${ZIMAGE:?set ZIMAGE to the AtlANTian-built zImage}
[[ -f "$ZIMAGE" ]] || { echo "missing ZIMAGE: $ZIMAGE" >&2; exit 2; }
RECOVERY_INITRAMFS=${RECOVERY_INITRAMFS:-$PROJECT/out/boot/atlantian-recovery.cpio.gz}
[[ -f "$RECOVERY_INITRAMFS" ]] || { echo "missing recovery initramfs: $RECOVERY_INITRAMFS" >&2; exit 2; }

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
truncate -s "${SIZE_MIB}M" "$OUT"
parted -s "$OUT" mklabel msdos
parted -s "$OUT" mkpart primary fat32 1MiB 65MiB
parted -s "$OUT" set 1 boot on
SYSTEM_END_MIB=$((65 + ROOT_MIB))
parted -s "$OUT" mkpart primary ext4 65MiB "${SYSTEM_END_MIB}MiB"
parted -s "$OUT" mkpart primary ext4 "${SYSTEM_END_MIB}MiB" 100%

LOOP=$(losetup --find --show --partscan "$OUT")
BOOT_MNT=
ROOT_MNT=
DATA_MNT=
cleanup() {
  set +e
  [[ -n "$ROOT_MNT" ]] && mountpoint -q "$ROOT_MNT" && umount "$ROOT_MNT"
  [[ -n "$BOOT_MNT" ]] && mountpoint -q "$BOOT_MNT" && umount "$BOOT_MNT"
  [[ -n "$ROOT_MNT" ]] && rmdir "$ROOT_MNT"
  [[ -n "$DATA_MNT" ]] && mountpoint -q "$DATA_MNT" && umount "$DATA_MNT"
  [[ -n "$DATA_MNT" ]] && rmdir "$DATA_MNT"
  [[ -n "$BOOT_MNT" ]] && rmdir "$BOOT_MNT"
  losetup -d "$LOOP"
}
trap cleanup EXIT

mkfs.vfat -F 32 -n BOOT "${LOOP}p1"
# This is a single-purpose removable SD rootfs, not a multi-user system disk.
# Do not hide five percent of the card from root behind ext4's historical
# reserved-block policy; recovery still has UART and the separate boot FAT.
mkfs.ext4 -F -m 0 -L atlantian-root "${LOOP}p2"
mkfs.ext4 -F -m 0 -L atlantian-data "${LOOP}p3"
BOOT_MNT=$(mktemp -d /mnt/atlantian-boot.XXXXXX)
ROOT_MNT=$(mktemp -d /mnt/atlantian-root.XXXXXX)
DATA_MNT=$(mktemp -d /mnt/atlantian-data.XXXXXX)
mount "${LOOP}p1" "$BOOT_MNT"
mount "${LOOP}p2" "$ROOT_MNT"
mount "${LOOP}p3" "$DATA_MNT"

rsync -aHAX --numeric-ids "$ROOTFS/" "$ROOT_MNT/"
mkdir -p "$DATA_MNT"/{system,fpga,user}
cp "$BOOT_BIN" "$BOOT_MNT/BOOT.bin"
cp "$DTB" "$BOOT_MNT/devicetree.dtb"
cp "$ZIMAGE" "$BOOT_MNT/zImage"
cp "$RECOVERY_INITRAMFS" "$BOOT_MNT/atlantian-recovery.cpio.gz"
mkimage -A arm -O linux -T kernel -C none -a 0x00008000 -e 0x00008000 \
  -n "AtlANTian ${ATLANTIAN_RELEASE_ID}" -d "$ZIMAGE" "$BOOT_MNT/uImage"
# The recovery environment is loaded by U-Boot, not by Linux.  Keep it in
# legacy uImage form so the stock S9 U-Boot can pass it to bootm directly.
mkimage -A arm -O linux -T ramdisk -C gzip \
  -n 'AtlANTian one-shot SD recovery' -d "$RECOVERY_INITRAMFS" \
  "$BOOT_MNT/uInitrd"
if [[ -n "$UENV" ]]; then
  # Some S9 U-Boot builds import a binary environment rather than a text file.
  # A known-good board-specific environment can be supplied without modifying it.
  cp "$UENV" "$BOOT_MNT/uEnv.txt"
else
cat >"$BOOT_MNT/uEnv.txt" <<'EOF'
# U-Boot consumes a one-shot recovery request, then invalidates it on FAT
# before recovery boots. A failed recovery boot therefore cannot trap the
# board: the next reset takes the normal boot path.
atlantian_normal_bootargs=mem=496M console=ttyPS0,115200n8 root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait
bootcmd=setenv atlantian_update 0; if fatload mmc 0:1 0x01000000 atlantian-update.scr; then source 0x01000000; fi; if test "${atlantian_update}" = "1"; then echo "AtlANTian: one-shot recovery"; mw.b 0x01000000 0 1; fatwrite mmc 0:1 0x01000000 atlantian-update.scr 1; setenv bootargs mem=496M console=ttyPS0,115200n8 root=/dev/ram0 rdinit=/init atlantian.mode=${atlantian_mode} atlantian.flash_url=${atlantian_flash_url} atlantian.sha256=${atlantian_sha} atlantian.blocks=${atlantian_blocks} atlantian.system_url=${atlantian_system_url} atlantian.system_sha256=${atlantian_system_sha256}; if fatload mmc 0:1 0x03000000 uImage && fatload mmc 0:1 0x02000000 uInitrd && fatload mmc 0:1 0x02A00000 devicetree.dtb; then bootm 0x03000000 0x02000000 0x02A00000; fi; fi; setenv bootargs ${atlantian_normal_bootargs}; mmcinfo && fatload mmc 0:1 0x03000000 uImage && fatload mmc 0:1 0x02A00000 devicetree.dtb && bootm 0x03000000 - 0x02A00000
EOF
fi
sync
dd if="${LOOP}p2" of="$SYSTEM_OUT" bs=1M status=none
cp "$ROOTFS/usr/share/atlantian/debian-package-manifest.tsv" "${SYSTEM_OUT%.ext4}.packages.tsv"
cp "$ROOTFS/usr/share/atlantian/debian-snapshot.txt" "${SYSTEM_OUT%.ext4}.snapshot.txt"
echo "Created system payload: $SYSTEM_OUT"
echo "Created test image: $OUT"
