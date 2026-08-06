#!/usr/bin/env bash
# Make the tiny, self-contained environment used to overwrite the active SD.
# It receives only an HTTP URL and an expected SHA-256 in the kexec commandline.
set -euo pipefail

ROOTFS=${ROOTFS:-$PWD/out/rootfs}
OUT=${OUT:-$PWD/out/boot/atlantian-recovery.cpio.gz}
BUSYBOX=${BUSYBOX:-$ROOTFS/bin/busybox}
PROJECT=$(cd "$(dirname "$0")/.." && pwd)
. "$PROJECT/config/image-layout.env"

[[ -x "$BUSYBOX" ]] || { echo "missing static BusyBox: $BUSYBOX" >&2; exit 2; }

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$WORK"/{bin,dev,proc,sys,newroot}
install -m 0755 "$BUSYBOX" "$WORK/bin/busybox"
# Keep every external command used by /init and atlantian-update-leds in the
# recovery image.  In particular, the indicator creates /run itself: recovery
# starts before the ordinary tmpfs mounts and cannot rely on coreutils.
for applet in sh mount umount sleep ip ifconfig route udhcpc wget dd sha256sum sync watchdog dmesg sed head awk rm mkdir reboot wc cat; do
  ln -s busybox "$WORK/bin/$applet"
done

# BusyBox's udhcpc deliberately delegates address and route configuration to
# this script.  Without it a lease is acquired but the recovery environment
# has neither an IPv4 address nor a default route.
cat >"$WORK/udhcpc.script" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
  bound|renew)
    /bin/ifconfig "$interface" "$ip" netmask "$subnet"
    /bin/route del default 2>/dev/null || true
    [ -n "${router:-}" ] && /bin/route add default gw "${router%% *}" "$interface"
    ;;
esac
EOF
chmod 0755 "$WORK/udhcpc.script"

install -D -m 0755 "$ROOTFS/usr/local/sbin/atlantian-update-leds" \
  "$WORK/usr/local/sbin/atlantian-update-leds"

cat >"$WORK/init" <<'EOF'
#!/bin/sh
set -eu
set -o pipefail
PATH=/bin
BOOT_MIB=@ATLANTIAN_BOOT_MIB@
SYSTEM_MIB=@ATLANTIAN_SYSTEM_MIB@
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

arg() { sed -n "s/.*$1=\\([^ ]*\\).*/\\1/p" /proc/cmdline | head -n1; }
URL=$(arg atlantian.flash_url)
EXPECTED=$(arg atlantian.sha256)
BLOCKS=$(arg atlantian.blocks)
MODE=$(arg atlantian.mode)
BUNDLE_URL=$(arg atlantian.bundle_url)
BUNDLE_EXPECTED=$(arg atlantian.bundle_sha256)
BUNDLE_FILE=$(arg atlantian.bundle_file)
BUNDLE_BYTES=$(arg atlantian.bundle_bytes)
say() { echo "[atlantian-recovery] $*"; }
fail() { say "FATAL: $*"; exec sh; }
LED_PID=
start_leds() {
  if [ -x /usr/local/sbin/atlantian-update-leds ]; then
    /usr/local/sbin/atlantian-update-leds >/dev/null 2>&1 &
    LED_PID=$!
  fi
}
stop_leds() {
  if [ -n "${LED_PID:-}" ]; then
    kill "$LED_PID" 2>/dev/null || true
    wait "$LED_PID" 2>/dev/null || true
    LED_PID=
  fi
}
trap 'stop_leds' INT TERM EXIT

if [ "$MODE" = system ]; then
  [ -n "$BUNDLE_FILE" ] && [ -z "$BUNDLE_URL" ] || fail "a local staged release bundle is required"
  case "$BUNDLE_FILE" in /data/system/atlantian/stage/*.update.bundle) ;; *) fail "unsafe staged bundle path" ;; esac
  case "$BUNDLE_EXPECTED" in *[!0-9a-fA-F]*|'') fail "invalid bundle SHA-256" ;; esac
  [ "${#BUNDLE_EXPECTED}" -eq 64 ] || fail "invalid bundle SHA-256 length"
  case "$BUNDLE_BYTES" in *[!0-9]*|'') fail "invalid bundle size" ;; esac
  [ "$BUNDLE_BYTES" -gt 0 ] || fail "invalid bundle size"
else
  case "$URL" in http://*) ;; *) fail "missing or unsafe image URL" ;; esac
  case "$EXPECTED" in *[!0-9a-fA-F]*|'') fail "invalid SHA-256" ;; esac
  [ "${#EXPECTED}" -eq 64 ] || fail "invalid SHA-256 length"
  case "$BLOCKS" in *[!0-9]*|'') fail "invalid image block count" ;; esac
  [ "$BLOCKS" -gt 0 ] || fail "invalid image block count"
fi

# Zynq MAC drivers may expose the interface as end0 rather than eth0.
IFACE=
for node in /sys/class/net/*; do
  name=${node##*/}
  [ "$name" = lo ] || { IFACE=$name; break; }
done
[ -n "$IFACE" ] || fail "no Ethernet interface"
ip link set "$IFACE" up || fail "cannot enable $IFACE"
udhcpc -i "$IFACE" -s /udhcpc.script -n -q -t 8 -T 3 || fail "DHCP failed on $IFACE"
test -b /dev/mmcblk0 || fail "SD device not found"

# Refuse before any write when the physical card does not match this release's
# fixed p1+p2 ABI.  A blind dd to a smaller p2 can leave a syntactically valid
# but unbootable, truncated ext4 filesystem.
partition_bytes() {
  sectors=$(cat "/sys/class/block/$1/size") || return 1
  echo $((sectors * 512))
}
EXPECTED_BOOT_BYTES=$((BOOT_MIB * 1024 * 1024))
EXPECTED_SYSTEM_BYTES=$((SYSTEM_MIB * 1024 * 1024))
[ "$(partition_bytes mmcblk0p1)" -eq "$EXPECTED_BOOT_BYTES" ] || fail "boot partition layout mismatch; use explicit recovery migration"
[ "$(partition_bytes mmcblk0p2)" -eq "$EXPECTED_SYSTEM_BYTES" ] || fail "system partition layout mismatch; refusing a truncating update"

if [ "$MODE" = system ]; then
  say "writing verified p1+p2 release bundle; /data is preserved"
  if [ -n "$BUNDLE_FILE" ]; then
    mkdir -p /data
    mount -o ro /dev/mmcblk0p3 /data || fail "cannot mount staged /data"
    [ -r "$BUNDLE_FILE" ] || fail "staged release bundle is unavailable"
  fi
  start_leds
  if [ -n "$BUNDLE_FILE" ]; then
    [ "$(wc -c <"$BUNDLE_FILE" | tr -d ' ')" = "$BUNDLE_BYTES" ] || fail "staged bundle size mismatch"
    [ "$(sha256sum "$BUNDLE_FILE" | awk '{print $1}')" = "$BUNDLE_EXPECTED" ] || fail "staged bundle checksum mismatch"
    dd if="$BUNDLE_FILE" of=/dev/mmcblk0p1 bs=1M count="$BOOT_MIB" oflag=direct conv=fsync || fail "boot write failed"
    dd if="$BUNDLE_FILE" of=/dev/mmcblk0p2 bs=1M skip="$BOOT_MIB" count="$SYSTEM_MIB" oflag=direct conv=fsync || fail "system write failed"
  fi
  ACTUAL=$( (dd if=/dev/mmcblk0p1 bs=1M count="$BOOT_MIB" iflag=direct 2>/dev/null; dd if=/dev/mmcblk0p2 bs=1M count="$SYSTEM_MIB" iflag=direct 2>/dev/null) | sha256sum | awk '{print $1}') || fail "bundle read-back failed"
  [ "$ACTUAL" = "$BUNDLE_EXPECTED" ] || fail "bundle SHA-256 mismatch: $ACTUAL"
  stop_leds
else
say "writing image to SD with direct I/O; do not remove power"
# Writing via tee fills the recovery kernel's page cache until 496 MiB RAM is
# exhausted; that can corrupt a successfully downloaded image.  The fixed-size
# AtlANTian image is MiB-aligned, so direct I/O keeps it out of page cache.
  start_leds
  wget -q -O - "$URL" | dd of=/dev/mmcblk0 bs=1M oflag=direct conv=fsync || fail "download or direct SD write failed"
  ACTUAL=$(dd if=/dev/mmcblk0 bs=1M count="$BLOCKS" iflag=direct 2>/dev/null | sha256sum | awk '{print $1}') || fail "SD read-back failed"
  [ "$ACTUAL" = "$EXPECTED" ] || fail "SHA-256 mismatch: $ACTUAL"
  stop_leds
fi
say "verified; rebooting into deployed system"
# A normal reboot from the RAM-only recovery kernel intermittently leaves this
# CTRL_C41 at a dead Zynq reset boundary: the image is sound, but neither ROM
# nor U-Boot restarts.  Keep /dev/watchdog open, then stop its feeder.  The PS
# watchdog asserts a real hardware reset after three seconds and has proven
# independent of the broken recovery reboot path.  Do not close the descriptor:
# closing a Linux watchdog can disarm it on drivers without nowayout.
if [ -c /dev/watchdog ]; then
  say "verified; forcing PS-watchdog reset into deployed system"
  watchdog -F -t 200ms -T 3 /dev/watchdog &
  WD_PID=$!
  sleep 1
  kill -STOP "$WD_PID" || fail "cannot arm PS watchdog"
  sleep 10
  fail "PS watchdog failed to reset the board"
else
  # Some minimal DTBs do not expose the watchdog node in the recovery
  # environment.  A forced reboot is still safe here: p2 is fully synced and
  # p1/p3 were never written.  The board's boot ROM/U-Boot then starts Linux.
  say "watchdog unavailable; using forced PS reboot"
  sync
  reboot -f
  sleep 10
  fail "forced reboot failed"
fi
EOF
chmod 0755 "$WORK/init"
sed -i "s/@ATLANTIAN_BOOT_MIB@/$ATLANTIAN_BOOT_MIB/g; s/@ATLANTIAN_SYSTEM_MIB@/$ATLANTIAN_SYSTEM_MIB/g" "$WORK/init"
mkdir -p "$(dirname "$OUT")"
(cd "$WORK" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9) >"$OUT"
echo "Recovery initramfs created: $OUT"
