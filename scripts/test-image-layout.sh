#!/usr/bin/env bash
# Structural integration test for the deployable SD image. It validates the
# actual partition/filesystem layout and contracts needed before first boot.
set -euo pipefail

IMAGE=${1:?image path required}
[[ -s $IMAGE ]] || { echo "image is empty: $IMAGE" >&2; exit 2; }

LOOP=
BOOT=
ROOT=
DATA=
WORK=$(mktemp -d)
cleanup() {
  set +e
  for mountpoint in "$BOOT" "$ROOT" "$DATA"; do
    [[ -n $mountpoint ]] && mountpoint -q "$mountpoint" && umount "$mountpoint"
  done
  [[ -n $LOOP ]] && losetup -d "$LOOP"
  rm -rf "$WORK"
}
trap cleanup EXIT

# The full image must stay a three-partition initial-install medium: BOOT,
# replaceable system, and persistent /data.
sfdisk -d "$IMAGE" | grep -q 'label: dos'
[[ $(sfdisk -d "$IMAGE" | grep -Ec '^.*\.img[0-9]+') -eq 3 ]]

LOOP=$(losetup --find --show --partscan "$IMAGE")
sleep 1
[[ -b ${LOOP}p1 && -b ${LOOP}p2 && -b ${LOOP}p3 ]]
[[ $(blkid -o value -s TYPE "${LOOP}p1") == vfat ]]
[[ $(blkid -o value -s TYPE "${LOOP}p2") == ext4 ]]
[[ $(blkid -o value -s TYPE "${LOOP}p3") == ext4 ]]
[[ $(blkid -o value -s LABEL "${LOOP}p1") == BOOT ]]
[[ $(blkid -o value -s LABEL "${LOOP}p2") == atlantian-root ]]
[[ $(blkid -o value -s LABEL "${LOOP}p3") == atlantian-data ]]

BOOT=$WORK/boot
ROOT=$WORK/root
DATA=$WORK/data
mkdir -p "$BOOT" "$ROOT" "$DATA"
mount -o ro "${LOOP}p1" "$BOOT"
mount -o ro "${LOOP}p2" "$ROOT"
mount -o ro "${LOOP}p3" "$DATA"

for file in BOOT.bin devicetree.dtb zImage uImage atlantian-recovery.cpio.gz uInitrd uEnv.txt; do
  [[ -s $BOOT/$file ]] || { echo "boot artifact missing: $file" >&2; exit 3; }
done
fdtget "$BOOT/devicetree.dtb" / compatible | tr ' ' '\n' | grep -qx 'bitmain,antminer-s9'

# Rootfs must expose the boot-critical board interfaces and upgrade ABI.
for path in \
  etc/atlantian-release etc/fstab etc/ssh/sshd_config.d/10-atlantian-root.conf \
  usr/local/sbin/atlantian-fpga usr/local/sbin/atlantian-sysupgrade \
  usr/local/sbin/atlantian-status-leds usr/local/sbin/atlantian-update-leds \
  lib/firmware/atlantian/status-leds/atlantian-status-leds.bin; do
  [[ -e $ROOT/$path ]] || { echo "rootfs contract missing: $path" >&2; exit 3; }
done
for unit in ssh.service systemd-networkd.service atlantian-status-leds.service \
  atlantian-fpga-status-leds.service zramswap.service; do
  [[ -e $ROOT/etc/systemd/system/multi-user.target.wants/$unit ]] || {
    echo "required enabled unit missing: $unit" >&2; exit 3;
  }
done
grep -qx '/dev/mmcblk0p3 /data ext4 defaults,nofail 0 2' "$ROOT/etc/fstab"
[[ -d $DATA/home && -d $DATA/etc && -d $DATA/var && -d $DATA/fpga && -d $DATA/user ]]

# Recovery must contain the updater and every applet its documented route needs.
gzip -cd "$BOOT/atlantian-recovery.cpio.gz" | cpio -it 2>/dev/null >"$WORK/recovery.list"
for path in init bin/busybox bin/wget bin/dd bin/sha256sum bin/mkdir usr/local/sbin/atlantian-update-leds; do
  grep -qx "$path" "$WORK/recovery.list" || { echo "recovery contract missing: $path" >&2; exit 3; }
done

echo "image layout and boot/rootfs/recovery contracts passed"
