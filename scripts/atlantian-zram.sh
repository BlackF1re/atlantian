#!/bin/sh
# One compressed swap device sized to one third of physical RAM.  This avoids
# any SD/NAND swap traffic while retaining an OOM safety margin on 512 MiB S9.
set -eu

case "${1:-start}" in
  start)
    modprobe zram
    bytes=$(awk '/MemTotal:/ { print int($2 * 1024 / 3); exit }' /proc/meminfo)
    [ "${bytes:-0}" -gt 0 ] || exit 1
    # lz4 is low-latency on Cortex-A9; fall back to the kernel default if a
    # future kernel omits it.
    printf 'lz4\n' >/sys/block/zram0/comp_algorithm 2>/dev/null || true
    printf '%s\n' "$bytes" >/sys/block/zram0/disksize
    mkswap -f /dev/zram0 >/dev/null
    swapon --priority 100 /dev/zram0
    ;;
  stop)
    swapoff /dev/zram0 2>/dev/null || true
    [ -e /sys/block/zram0/reset ] && printf '1\n' >/sys/block/zram0/reset || true
    ;;
  *) echo "usage: $0 {start|stop}" >&2; exit 64 ;;
esac
