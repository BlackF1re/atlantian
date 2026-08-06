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
fdtget "$BOOT/devicetree.dtb" / compatible | tr ' ' '\n' | grep -qx 'bitmain,antminer-s9' || {
  echo 'device-tree is not for bitmain,antminer-s9' >&2; exit 3;
}

# Rootfs must expose the boot-critical board interfaces and upgrade ABI.
for path in \
  etc/atlantian-release etc/fstab etc/ssh/sshd_config.d/10-atlantian-root.conf \
  usr/local/sbin/atlantian-fpga usr/local/sbin/atlantian-sysupgrade \
  usr/local/sbin/atlantian-status-leds usr/local/sbin/atlantian-update-leds \
  usr/local/sbin/atlantian-persist-state usr/local/sbin/atlantian-grow-data \
  usr/share/atlantian/debian-package-manifest.tsv usr/share/atlantian/debian-snapshot.txt \
  lib/firmware/atlantian/status-leds/atlantian-status-leds.bin; do
  [[ -e $ROOT/$path ]] || { echo "rootfs contract missing: $path" >&2; exit 3; }
done
for unit in ssh.service systemd-networkd.service atlantian-status-leds.service \
  atlantian-fpga-status-leds.service atlantian-grow-data.service zramswap.service; do
  # Unit links may point to an absolute /usr/lib path. Test the link itself:
  # resolving it on the build host would incorrectly resolve outside $ROOT.
  link="$ROOT/etc/systemd/system/multi-user.target.wants/$unit"
  [[ -L $link && $(readlink "$link") == */"$unit" ]] || {
    echo "required enabled unit missing: $unit" >&2; exit 3;
  }
done
link="$ROOT/etc/systemd/system/local-fs.target.wants/atlantian-persist-state.service"
[[ -L $link && $(readlink "$link") == */atlantian-persist-state.service ]] || {
  echo 'required early persistent-state unit missing' >&2; exit 3;
}
grep -qx '/dev/mmcblk0p3 /data ext4 defaults,nofail 0 2' "$ROOT/etc/fstab" || {
  echo 'persistent /data mount missing from fstab' >&2; exit 3;
}
[[ -d $DATA/system && -d $DATA/fpga && -d $DATA/user ]] || {
  echo 'initial persistent-data layout missing' >&2; exit 3;
}
grep -q 'lowerdir=/etc' "$ROOT/usr/local/sbin/atlantian-persist-state" || {
  echo 'persistent /etc overlay contract missing' >&2; exit 3;
}
grep -q '^state=\$data/system/atlantian/persist$' "$ROOT/usr/local/sbin/atlantian-persist-state" || {
  echo 'persistent-state location contract missing' >&2; exit 3;
}
grep -q 'atlantian-persist-state.service' "$ROOT/usr/local/sbin/atlantian-sysupgrade" || {
  echo 'updater does not flush persistent state' >&2; exit 3;
}
grep -q 'atlantian.boot_url' "$ROOT/usr/local/sbin/atlantian-sysupgrade" || {
  echo 'updater cannot deliver boot artefacts' >&2; exit 3;
}
grep -q 'atlantian.system_file' "$ROOT/usr/local/sbin/atlantian-sysupgrade" || {
  echo 'updater cannot use verified persistent staging' >&2; exit 3;
}

# Recovery must contain the updater and every applet its documented route needs.
gzip -cd "$BOOT/atlantian-recovery.cpio.gz" | cpio -it 2>/dev/null >"$WORK/recovery.list"
for path in init bin/busybox bin/wget bin/dd bin/sha256sum bin/mkdir usr/local/sbin/atlantian-update-leds; do
  grep -qx "$path" "$WORK/recovery.list" || { echo "recovery contract missing: $path" >&2; exit 3; }
done
mkdir -p "$WORK/recovery"
gzip -cd "$BOOT/atlantian-recovery.cpio.gz" | cpio -i --quiet -D "$WORK/recovery" init
grep -q 'atlantian.boot_url' "$WORK/recovery/init" || { echo 'recovery cannot update boot partition' >&2; exit 3; }
grep -q 'atlantian.system_file' "$WORK/recovery/init" || { echo 'recovery cannot use staged payload' >&2; exit 3; }

echo "image layout and boot/rootfs/recovery contracts passed"
