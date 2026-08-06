#!/bin/sh
# Release updater.  It replaces p1+p2 from one verified bundle and never
# touches p3 (/data).
set -eu
. /usr/local/share/atlantian/image-layout.env

STATE_FILE=/data/system/atlantian/update/available.env
STAGE=/data/system/atlantian/stage
BOOT=/run/atlantian-boot
KERNEL=/mnt/atlantian-boot
LOCK=/run/atlantian-update-leds.lock

usage() {
    echo 'usage: atlantian-sysupgrade --latest RELEASE_ID' >&2
    exit 64
}

state_get() {
    key=$1
    sed -n "s/^${key}=//p" "$STATE_FILE" | head -n1
}

if [ "${1:-}" = --latest ]; then
    [ $# -eq 2 ] || usage
    requested=$2
    echo 'Checking the published AtlANTian release…'
    /usr/local/sbin/atlantian-release-check --refresh
    [ -r "$STATE_FILE" ] || { echo 'no newer AtlANTian release is available'; exit 0; }
    release_id=$(state_get release_id)
    bundle_url=$(state_get bundle_url)
    expected_sha=$(state_get sha256)
    [ "$requested" = "$release_id" ] || {
        echo "requested release is no longer current: $requested" >&2
        echo "available release: $release_id" >&2
        exit 65
    }
    [ -n "$bundle_url" ] && [ "${#expected_sha}" -eq 64 ] || {
        echo 'stored release metadata is incomplete' >&2; exit 65;
    }

    cat <<EOF

AtlANTian system update: $release_id

This replaces the boot partition (p1) and immutable system partition (p2).
It preserves /data (p3), including persistent /etc, /root, /home and
/var/local state. Packages or changes outside that persistent state are lost.

Type UPDATE to download, verify and install this release:
EOF
    IFS= read -r confirmation
    [ "$confirmation" = UPDATE ] || { echo 'update cancelled'; exit 0; }

    mkdir -p "$STAGE"
    URL="$STAGE/${release_id}.update.bundle"
    PART="$URL.part"
    rm -f "$PART"
    echo '[1/3] Downloading the release bundle to persistent staging…'
    curl -fL --retry 3 --progress-bar -o "$PART" "$bundle_url"
    echo '[2/3] Verifying SHA-256…'
    [ "$(sha256sum "$PART" | awk '{print $1}')" = "$expected_sha" ] || {
        rm -f "$PART"; echo 'release bundle checksum mismatch' >&2; exit 65;
    }
    mv "$PART" "$URL"
    SHA=$expected_sha
    echo '[3/3] Preparing RAM recovery…'
else
    URL=${1:-}
    SHA=${2:-}
    [ $# -eq 2 ] || usage
fi

case "$URL" in /data/system/atlantian/stage/*.update.bundle) ;; *) echo 'use a verified staged .update.bundle' >&2; exit 65;; esac
case "$SHA" in *[!0-9a-fA-F]*|'') echo 'invalid SHA256' >&2; exit 65;; esac
[ "${#SHA}" -eq 64 ] || { echo 'invalid SHA256 length' >&2; exit 65; }
[ -f "$URL" ] && [ "$(sha256sum "$URL" | awk '{print $1}')" = "$SHA" ] || [ ! -f "$URL" ] || {
    echo 'staged system payload checksum mismatch' >&2; exit 65;
}
[ "$(wc -c <"$URL" | tr -d ' ')" -eq $(((ATLANTIAN_BOOT_MIB + ATLANTIAN_SYSTEM_MIB) * 1024 * 1024)) ] || {
    echo 'unexpected release bundle size' >&2; exit 65;
}
[ "$(id -u)" -eq 0 ] || { echo 'run as root' >&2; exit 77; }

# A release payload must never be written to a differently sized partition.
# In particular, this protects legacy 336-MiB p2 cards from a future image
# layout change: dd would otherwise silently truncate an ext4 filesystem.
partition_bytes() {
    sectors=$(cat "/sys/class/block/$1/size") || return 1
    echo $((sectors * 512))
}
EXPECTED_BOOT_BYTES=$((ATLANTIAN_BOOT_MIB * 1024 * 1024))
EXPECTED_SYSTEM_BYTES=$((ATLANTIAN_SYSTEM_MIB * 1024 * 1024))
[ "$(partition_bytes mmcblk0p1)" -eq "$EXPECTED_BOOT_BYTES" ] || {
    echo 'boot partition layout mismatch; use explicit recovery migration' >&2; exit 66;
}
[ "$(partition_bytes mmcblk0p2)" -eq "$EXPECTED_SYSTEM_BYTES" ] || {
    echo 'system partition layout mismatch; refusing a truncating update' >&2; exit 66;
}

# Materialise p3-backed administrator state before RAM recovery replaces p2.
systemctl start atlantian-persist-state.service >/dev/null 2>&1 || true
mkdir -p "$BOOT" "$KERNEL"
mountpoint -q "$KERNEL" || mount /dev/mmcblk0p1 "$KERNEL"
mkdir -p /run
: >"$LOCK"
systemctl stop atlantian-status-leds.service atlantian-fpga-status-leds.service >/dev/null 2>&1 || true

# The factory U-Boot environment on CTRL_C41 is persistent in NAND and does
# not reliably consume uEnv.txt. Therefore use kexec as the primary path:
# recovery runs entirely from RAM and can safely overwrite p1/p2.
if command -v kexec >/dev/null 2>&1 &&
   [ -r "$KERNEL/zImage" ] && [ -r "$KERNEL/atlantian-recovery.cpio.gz" ] &&
   [ -r "$KERNEL/devicetree.dtb" ]; then
    CMDLINE="mem=496M console=ttyPS0,115200n8 root=/dev/ram0 rdinit=/init atlantian.mode=system atlantian.bundle_file=$URL atlantian.bundle_sha256=$SHA atlantian.bundle_bytes=$(((ATLANTIAN_BOOT_MIB + ATLANTIAN_SYSTEM_MIB) * 1024 * 1024))"
    kexec -l "$KERNEL/zImage" --initrd="$KERNEL/atlantian-recovery.cpio.gz" \
        --dtb="$KERNEL/devicetree.dtb" --command-line="$CMDLINE"
    sync
    echo 'SSH will disconnect now. Do not remove power: RAM recovery verifies'
    echo 'the write, preserves /data, and restarts the board automatically.'
    kexec -e
    exit 0
fi

echo 'kexec recovery is unavailable; refusing an unsafe update' >&2
exit 69
