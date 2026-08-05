#!/usr/bin/env bash
# Replace the SD image without UART once AtlANTian itself is reachable.
#
# A static BusyBox flasher is copied to tmpfs, then the running root filesystem
# is frozen.  The RAM-only flasher streams the image, verifies a direct-I/O
# read-back SHA-256, then forces a PS reset via SysRq.  NAND is never
# opened or written.  This avoids the CTRL_C41's unreliable software-reset
# boundary and does not require UART or U-Boot interaction.
set -euo pipefail

[[ $# -ge 1 && $# -le 2 ]] || { echo 'usage: deploy-via-network.sh <image> [board-ip]' >&2; exit 64; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=$(readlink -f "$1")
BOARD=${2:-$(<"$ROOT/state/board.address")}
USER=${ATLANTIAN_USER:-root}
PORT=${ATLANTIAN_HTTP_PORT:-18082}
TIMEOUT=${ATLANTIAN_BOOT_TIMEOUT:-720}
[[ -f $IMAGE ]] || { echo 'image is unavailable' >&2; exit 2; }

SHA=$(sha256sum "$IMAGE" | awk '{print $1}')
SIZE=$(stat -c %s "$IMAGE")
(( SIZE > 0 && SIZE % 1048576 == 0 )) || { echo 'image must be MiB-aligned' >&2; exit 2; }
BLOCKS=$((SIZE / 1048576))
LOCAL_IP=$(ip route get "$BOARD" | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
LOCAL_DEV=$(ip route get "$BOARD" | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[[ -n $LOCAL_IP ]] || { echo 'cannot determine recovery-server address' >&2; exit 3; }
[[ -n $LOCAL_DEV ]] || { echo 'cannot determine recovery-server interface' >&2; exit 3; }

# DHCP is intentionally authoritative in AtlANTian, so a clean image may get a
# different address after reboot.  Remember the physical board, not merely its
# pre-flash lease, and rediscover it on the directly connected subnet.
BOARD_MAC=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$USER@$BOARD" \
  "cat /sys/class/net/\$(ip route show default | awk 'NR==1 {print \$5}')/address" | tr -d '\r\n')
[[ $BOARD_MAC =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || {
  echo 'cannot determine board Ethernet MAC address' >&2
  exit 3
}
LOCAL_CIDR=$(ip -o -4 addr show dev "$LOCAL_DEV" scope global | awk 'NR==1 {print $4}')

discover_board() {
  local found candidate
  # Populate the neighbour table actively when nmap is available.  Falling
  # back to the existing ARP/NDP cache still supports minimal build hosts.
  if [[ -n $LOCAL_CIDR ]] && command -v nmap >/dev/null 2>&1; then
    nmap -sn -e "$LOCAL_DEV" "$LOCAL_CIDR" >/dev/null 2>&1 || true
  fi
  found=$(ip neigh show dev "$LOCAL_DEV" | awk -v mac="${BOARD_MAC,,}" \
    'tolower($5)==mac && $1 ~ /^[0-9]+\./ {print $1; exit}')
  # A missing neighbour is normal while the board is resetting or waiting for
  # DHCP.  Always return success here: with `set -e`, the old short-circuit
  # expression aborted the whole recovery loop on its very first empty scan.
  if [[ -n $found ]]; then
    BOARD=$found
    return 0
  fi

  # CTRL_C41 has no guaranteed factory Ethernet address.  A freshly written
  # image can therefore come back with a new locally administered MAC, making
  # MAC-only discovery insufficient.  Fall back to SSH discovery and accept
  # only a fully booted AtlANTian system whose root is the SD card.
  if [[ -n $LOCAL_CIDR ]] && command -v nmap >/dev/null 2>&1; then
    while read -r candidate; do
      [[ -n $candidate && $candidate != "$LOCAL_IP" ]] || continue
      if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
          -o ServerAliveInterval=2 -o ServerAliveCountMax=1 "$USER@$candidate" \
          'grep -q "^atlantian-" /etc/atlantian-release 2>/dev/null &&
           findmnt -no SOURCE / | grep -qx /dev/mmcblk0p2' \
          </dev/null >/dev/null 2>&1; then
        BOARD=$candidate
        return 0
      fi
    done < <(nmap -n -p22 --open -oG - "$LOCAL_CIDR" 2>/dev/null |
      awk '/22\/open/ {print $2}')
  fi
  return 0
}

if [[ -z ${ATLANTIAN_HTTP_PORT:-} ]]; then
  for candidate in $(seq 18082 18099); do
    if ! ss -ltn "sport = :$candidate" | grep -q LISTEN; then PORT=$candidate; break; fi
  done
fi
ss -ltn "sport = :$PORT" | grep -q LISTEN && { echo 'no free recovery HTTP port' >&2; exit 4; }

python3 -m http.server "$PORT" --bind "$LOCAL_IP" --directory "$(dirname "$IMAGE")" \
  >/tmp/atlantian-recovery-http.log 2>&1 &
HTTP_PID=$!
cleanup() { kill "$HTTP_PID" 2>/dev/null || true; wait "$HTTP_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 1
kill -0 "$HTTP_PID" || { cat /tmp/atlantian-recovery-http.log >&2; exit 4; }

URL="http://$LOCAL_IP:$PORT/$(basename "$IMAGE")"
# This is deliberately the SSH command's direct child.  It switches to a
# static binary before freezing '/', so no subsequently executed code or data
# is read from the SD that is about to be replaced.
# A forced SysRq reset can leave the old TCP session half-open on the switch.
# Keepalives make that expected disconnect deterministic instead of waiting for
# the kernel's long default TCP timeout.
ssh -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=3 -o ServerAliveCountMax=3 "$USER@$BOARD" \
  "URL='$URL' EXPECTED='$SHA' BLOCKS='$BLOCKS' /bin/busybox sh -s" <<'REMOTE' || {
set -eu
R=/run/atlantian-netflash
FSFREEZE=/usr/sbin/fsfreeze
[ -x /bin/busybox ] && [ -x "$FSFREEZE" ] && [ -w /proc/sysrq-trigger ]
mkdir -p "$R"
cp /bin/busybox "$R/busybox"
LED_SCRIPT=/usr/local/sbin/atlantian-update-leds
[ -x /root/atlantian-update-leds.sh ] && LED_SCRIPT=/root/atlantian-update-leds.sh
export LED_SCRIPT
cat >"$R/flash" <<'FLASH'
#!/run/atlantian-netflash/busybox sh
set -eu
set -o pipefail
R=/run/atlantian-netflash
bb() { "$R/busybox" "$@"; }
bb sleep 3
bb sync
touch /run/atlantian-update-leds.lock
systemctl stop atlantian-status-leds.service atlantian-fpga-status-leds.service >/dev/null 2>&1 || true
"$FSFREEZE" -f /
# Everything below is a static BusyBox process in tmpfs.  Direct I/O keeps the
# 576-MiB image out of the board's 512-MiB RAM page cache.
LED_PID=
"$LED_SCRIPT" >/dev/null 2>&1 &
LED_PID=$!
cleanup() {
  if [ -n "${LED_PID:-}" ]; then
    kill "$LED_PID" 2>/dev/null || true
    wait "$LED_PID" 2>/dev/null || true
  fi
  rm -f /run/atlantian-update-leds.lock 2>/dev/null || true
  "$FSFREEZE" -u / 2>/dev/null || true
}
trap cleanup EXIT INT TERM
bb wget -q -O - "$URL" | bb dd of=/dev/mmcblk0 bs=1M oflag=direct conv=fsync
ACTUAL=$(bb dd if=/dev/mmcblk0 bs=1M count="$BLOCKS" iflag=direct 2>/dev/null | bb sha256sum | bb awk '{print $1}')
[ "$ACTUAL" = "$EXPECTED" ] || exit 91
cleanup
bb sync
# CTRL_C41 sometimes hangs after a normal Linux reboot.  SysRq-b bypasses
# userspace shutdown and resets the PS immediately; the next boot comes from
# the verified SD image.  This is deliberately the final operation.
echo b > /proc/sysrq-trigger
exit 92
FLASH
chmod 700 "$R/flash"
export FSFREEZE
exec "$R/busybox" sh "$R/flash"
REMOTE
  rc=$?
  # The forced PS reset intentionally tears down the SSH transport.
  [[ $rc -eq 255 ]] || exit "$rc"
}

deadline=$((SECONDS + TIMEOUT))
while ((SECONDS < deadline)); do
  discover_board
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=3 -o ServerAliveCountMax=2 "$USER@$BOARD" \
      'findmnt -no SOURCE / | grep -qx /dev/mmcblk0p2 && systemctl is-active --quiet ssh'; then
    printf '%s\n' "$BOARD" >"$ROOT/state/board.address"
    echo "DEPLOY PASS: $BOARD booted verified image $SHA"
    exit 0
  fi
  sleep 3
done
echo 'DEPLOY FAIL: recovery was started, but the verified post-boot check timed out' >&2
exit 1
