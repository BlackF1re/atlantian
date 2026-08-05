#!/usr/bin/env bash
# Make the tiny, self-contained environment used to overwrite the active SD.
# It receives only an HTTP URL and an expected SHA-256 in the kexec commandline.
set -euo pipefail

ROOTFS=${ROOTFS:-$PWD/out/rootfs}
OUT=${OUT:-$PWD/out/boot/atlantian-recovery.cpio.gz}
BUSYBOX=${BUSYBOX:-$ROOTFS/bin/busybox}

[[ -x "$BUSYBOX" ]] || { echo "missing static BusyBox: $BUSYBOX" >&2; exit 2; }

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$WORK"/{bin,dev,proc,sys,newroot}
install -m 0755 "$BUSYBOX" "$WORK/bin/busybox"
# Keep every external command used by /init and atlantian-update-leds in the
# recovery image.  In particular, the indicator creates /run itself: recovery
# starts before the ordinary tmpfs mounts and cannot rely on coreutils.
for applet in sh mount umount sleep ip ifconfig route udhcpc wget dd sha256sum sync watchdog dmesg sed head awk rm mkdir reboot; do
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
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

arg() { sed -n "s/.*$1=\\([^ ]*\\).*/\\1/p" /proc/cmdline | head -n1; }
URL=$(arg atlantian.flash_url)
EXPECTED=$(arg atlantian.sha256)
BLOCKS=$(arg atlantian.blocks)
MODE=$(arg atlantian.mode)
SYSTEM_URL=$(arg atlantian.system_url)
SYSTEM_EXPECTED=$(arg atlantian.system_sha256)
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
  case "$SYSTEM_URL" in http://*) ;; *) fail "missing or unsafe system URL" ;; esac
  case "$SYSTEM_EXPECTED" in *[!0-9a-fA-F]*|'') fail "invalid system SHA-256" ;; esac
  [ "${#SYSTEM_EXPECTED}" -eq 64 ] || fail "invalid system SHA-256 length"
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

if [ "$MODE" = system ]; then
  say "writing system partition only; /data is preserved"
  start_leds
  wget -q -O - "$SYSTEM_URL" | dd of=/dev/mmcblk0p2 bs=1M oflag=direct conv=fsync || fail "download or system write failed"
  ACTUAL=$(dd if=/dev/mmcblk0p2 bs=1M iflag=direct 2>/dev/null | sha256sum | awk '{print $1}') || fail "system read-back failed"
  [ "$ACTUAL" = "$SYSTEM_EXPECTED" ] || fail "system SHA-256 mismatch: $ACTUAL"
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
mkdir -p "$(dirname "$OUT")"
(cd "$WORK" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9) >"$OUT"
echo "Recovery initramfs created: $OUT"
