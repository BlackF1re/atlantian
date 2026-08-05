#!/usr/bin/env bash
# Deprecated deliberately: even a RAM-resident process must not overwrite the
# SD containing the mounted root filesystem.  Use U-Boot RAM recovery instead.
set -euo pipefail

echo 'atlantian-ramflash is disabled: deploy via deploy-via-network.sh; UART/U-Boot is emergency-only' >&2
exit 64

URL=${1:?usage: atlantian-ramflash <http-url> <sha256>}
SHA256=${2:?usage: atlantian-ramflash <http-url> <sha256>}
DEVICE=${ATLANTIAN_SD_DEVICE:-/dev/mmcblk0}
RUNDIR=/run/atlantian-ramflash
BUSYBOX=/bin/busybox
FSFREEZE=${ATLANTIAN_FSFREEZE:-}

[[ $EUID -eq 0 ]] || { echo 'run with sudo' >&2; exit 77; }
[[ $URL =~ ^http:// ]] || { echo 'only local HTTP URLs are allowed' >&2; exit 64; }
[[ $SHA256 =~ ^[0-9a-fA-F]{64}$ ]] || { echo 'invalid SHA-256' >&2; exit 64; }
[[ -b $DEVICE ]] || { echo "SD device not found: $DEVICE" >&2; exit 2; }
[[ -x $BUSYBOX ]] || { echo 'static BusyBox is required at /bin/busybox' >&2; exit 2; }
if [[ -z $FSFREEZE ]]; then
  FSFREEZE=$(command -v fsfreeze || true)
fi
[[ -n $FSFREEZE && -x $FSFREEZE ]] || {
  echo 'fsfreeze from util-linux is required for safe live SD replacement' >&2
  exit 2
}

install -d -m 0700 "$RUNDIR"
install -m 0755 "$BUSYBOX" "$RUNDIR/busybox"
cat >"$RUNDIR/flash" <<EOF
#!/run/atlantian-ramflash/busybox sh
set -eu
set -o pipefail
URL='$URL'
EXPECTED='${SHA256,,}'
DEVICE='$DEVICE'
FSFREEZE='$FSFREEZE'
LOG=/run/atlantian-ramflash/flash.log
bb() { /run/atlantian-ramflash/busybox "\$@"; }
say() { echo "[atlantian-ramflash] \$*" >>"\$LOG"; }
die() { say "FATAL: \$*"; exit 1; }
FROZEN=0
cleanup() {
  rc=\$?
  if [ "\$FROZEN" = 1 ]; then
    "\$FSFREEZE" -u / >/dev/null 2>&1 || true
  fi
  exit "\$rc"
}
trap cleanup EXIT HUP INT TERM
bb sleep 4
say 'moving flasher into RAM and freezing root filesystem'
bb sync
# fsfreeze flushes the mounted ext4 filesystem and blocks any further VFS
# writes.  The flasher itself is already entirely in tmpfs and uses static
# BusyBox thereafter, so it can safely replace the underlying whole SD device.
# This avoids the unreliable remount/SysRq route and does not touch NAND.
"\$FSFREEZE" -f / || die 'cannot freeze root filesystem'
FROZEN=1
say 'streaming image to SD; do not remove power'
ACTUAL=\$(bb wget -q -O - "\$URL" | bb tee "\$DEVICE" | bb sha256sum | bb awk '{print \$1}') || die 'download or SD write failed'
bb sync
[ "\$ACTUAL" = "\$EXPECTED" ] || die "SHA-256 mismatch: \$ACTUAL"
say 'stream verified; rebooting into deployed image'
trap - EXIT HUP INT TERM
bb reboot -f
EOF
chmod 0700 "$RUNDIR/flash"

# Keep the flasher as the SSH command's direct child.  On this image PAM cleans
# detached session children, whereas this process survives until it deliberately
# reboots the board.  The RAM script itself pauses before touching rootfs.
sync
echo 'AtlANTian SD rewrite armed in RAM; board will reboot automatically. Do not remove power.'
exec "$RUNDIR/busybox" sh "$RUNDIR/flash"
