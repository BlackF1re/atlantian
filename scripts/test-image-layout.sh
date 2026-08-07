#!/usr/bin/env bash
set -euo pipefail

IMAGE=${1:?image path required}
PROJECT=$(cd "$(dirname "$0")/.." && pwd)
. "$PROJECT/config/image-layout.env"
. "$PROJECT/config/release.env"
LOOP= BOOT= ROOT= WORK=$(mktemp -d)
cleanup() {
  set +e
  [ -n "${BOOT:-}" ] && mountpoint -q "$BOOT" && umount "$BOOT"
  [ -n "${ROOT:-}" ] && mountpoint -q "$ROOT" && umount "$ROOT"
  [ -n "${LOOP:-}" ] && losetup -d "$LOOP"
  rm -rf "$WORK"
}
trap cleanup EXIT

sfdisk -d "$IMAGE" | grep -q 'label: dos'
[ "$(sfdisk -d "$IMAGE" | grep -Ec '^.*\.img[0-9]+')" = 2 ]
LOOP=$(losetup --find --show --partscan "$IMAGE")
sleep 1
[ -b "${LOOP}p1" ] && [ -b "${LOOP}p2" ] && [ ! -b "${LOOP}p3" ]
[ "$(blkid -o value -s TYPE "${LOOP}p1")" = vfat ]
[ "$(blkid -o value -s TYPE "${LOOP}p2")" = ext4 ]
[ "$(blkid -o value -s LABEL "${LOOP}p1")" = BOOT ]
[ "$(blkid -o value -s LABEL "${LOOP}p2")" = atlantian-root ]
[ "$(blockdev --getsize64 "${LOOP}p1")" = $((ATLANTIAN_BOOT_MIB * 1024 * 1024)) ]

BOOT=$WORK/boot
ROOT=$WORK/root
mkdir -p "$BOOT" "$ROOT"
mount -o ro "${LOOP}p1" "$BOOT"
mount -o ro "${LOOP}p2" "$ROOT"

for f in BOOT.bin devicetree.dtb zImage uImage uEnv.txt; do
  [ -s "$BOOT/$f" ] || { echo "missing boot asset: $f" >&2; exit 3; }
done
for f in \
  etc/atlantian-release \
  etc/fstab \
  etc/systemd/network/10-atlantian-ethernet.link \
  usr/lib/atlantian/version \
  usr/local/sbin/atlantian-grow-rootfs \
  usr/local/sbin/atlantian-sysupgrade \
  usr/local/sbin/atlantian-release-check; do
  [ -e "$ROOT/$f" ] || { echo "missing root contract: $f" >&2; exit 3; }
done

grep -qx '/dev/mmcblk0p2 / ext4 defaults 0 1' "$ROOT/etc/fstab"
grep -qx '/dev/mmcblk0p1 /boot vfat defaults 0 2' "$ROOT/etc/fstab"
! grep -q mmcblk0p3 "$ROOT/etc/fstab"
[ "$(cat "$ROOT/etc/atlantian-release")" = "$ATLANTIAN_VERSION" ]
[ "$(cat "$ROOT/usr/lib/atlantian/version")" = "$ATLANTIAN_VERSION" ]
grep -qx 'MACAddressPolicy=persistent' "$ROOT/etc/systemd/network/10-atlantian-ethernet.link"

# Every flashed card must create its own machine and SSH server identity.
[ -e "$ROOT/etc/machine-id" ] && [ ! -s "$ROOT/etc/machine-id" ]
! find "$ROOT/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*_key' -print -quit | grep -q .
[ -e "$ROOT/etc/systemd/system/atlantian-ssh-hostkeys.service" ]
[ -L "$ROOT/etc/systemd/system/ssh.service.wants/atlantian-ssh-hostkeys.service" ]
[ -L "$ROOT/etc/systemd/system/multi-user.target.wants/atlantian-grow-rootfs.service" ]

# Detect the two ownership regressions which previously made cached images
# unsafe: recursive rootfs chown and runner-owned cached files.
[ "$(stat -c %u "$ROOT")" = 0 ]
[ "$(stat -c %u "$ROOT/etc/shadow")" = 0 ]
if [ -n "${SUDO_UID:-}" ] && [ "$SUDO_UID" != 0 ]; then
  ! find "$ROOT" -xdev -uid "$SUDO_UID" -print -quit | grep -q .
fi

! [ -e "$ROOT/usr/local/sbin/atlantian-persist-state" ]
! [ -e "$ROOT/usr/local/sbin/atlantian-grow-data" ]
echo 'two-partition factory-image, identity and ownership contracts passed'
