#!/bin/sh
# Expand only p3 (/data) once, and retain the completion marker on p3 itself.
# p2 is the fixed, replaceable system partition and is never grown here.
set -eu

disk=/dev/mmcblk0
part=/dev/mmcblk0p3
state=/data/system/atlantian/grow

mountpoint -q /data || exit 0
install -d -m 0755 "$state"
[ -b "$part" ] || exit 0

sector_size=$(blockdev --getss "$disk")
disk_bytes=$(blockdev --getsize64 "$disk")
part_start=$(cat /sys/class/block/mmcblk0p3/start)
part_sectors=$(cat /sys/class/block/mmcblk0p3/size)
part_end=$(( (part_start + part_sectors) * sector_size ))

if [ "$part_end" -lt "$disk_bytes" ]; then
    # The kernel cannot reread a mounted partition table safely.  Change the
    # table, remember why, and reboot once; the next boot grows the filesystem.
    printf ',+\n' | sfdisk --no-reread --force -N 3 "$disk"
    : >"$state/partition-resize-pending"
    sync
    systemctl --no-block reboot
    exit 0
fi

if [ ! -e "$state/filesystem-expanded" ] || [ -e "$state/partition-resize-pending" ]; then
    resize2fs "$part"
    rm -f "$state/partition-resize-pending"
    : >"$state/filesystem-expanded"
fi
