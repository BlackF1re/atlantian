#!/bin/sh
# Expand the removable-SD root partition once, without reserving card space.
# The partition table change needs a reboot before resize2fs can see it.
set -eu

state=/var/lib/atlantian
mkdir -p "$state"

rootdev=$(findmnt -n -o SOURCE / 2>/dev/null || true)
[ "$rootdev" = /dev/mmcblk0p2 ] || exit 0

if [ ! -e "$state/mmc-partition-expanded" ]; then
    # Preserve p1/p2 and extend only the persistent data partition p3.
    printf ',+\n' | sfdisk --no-reread --force -N 3 /dev/mmcblk0
    touch "$state/mmc-partition-expanded"
    sync
    systemctl --no-block reboot
    exit 0
fi

if [ ! -e "$state/mmc-filesystem-expanded" ]; then
    resize2fs /dev/mmcblk0p3
    touch "$state/mmc-filesystem-expanded"
fi
