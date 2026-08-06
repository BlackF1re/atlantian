#!/bin/sh
# Release updater.  It replaces p2 and, when supplied, p1 so kernel/DTB
# changes are delivered too.  It never touches p3 (/data).
set -eu

URL=${1:-}
SHA=${2:-}
BOOT_URL=${3:-}
BOOT_SHA=${4:-}
BOOT=/run/atlantian-boot
KERNEL=/mnt/atlantian-boot
LOCK=/run/atlantian-update-leds.lock
if [ -z "$URL" ] || [ -z "$SHA" ]; then
    echo "usage: atlantian-sysupgrade SYSTEM_EXT4_URL SYSTEM_EXT4_SHA256 [BOOT_VFAT_URL BOOT_VFAT_SHA256]" >&2
    exit 64
fi
case "$URL" in http://*|/data/system/atlantian/stage/*) ;; *) echo 'use an http:// URL or a staged /data system payload' >&2; exit 65;; esac
case "$SHA" in *[!0-9a-fA-F]*|'') echo 'invalid SHA256' >&2; exit 65;; esac
[ "${#SHA}" -eq 64 ] || { echo 'invalid SHA256 length' >&2; exit 65; }
if [ -n "$BOOT_URL$BOOT_SHA" ]; then
    [ -n "$BOOT_URL" ] && [ -n "$BOOT_SHA" ] || { echo 'boot URL and SHA256 must be supplied together' >&2; exit 65; }
    case "$BOOT_URL" in http://*|/data/system/atlantian/stage/*) ;; *) echo 'use an http:// URL or a staged /data boot payload' >&2; exit 65;; esac
    case "$BOOT_SHA" in *[!0-9a-fA-F]*|'') echo 'invalid boot SHA256' >&2; exit 65;; esac
    [ "${#BOOT_SHA}" -eq 64 ] || { echo 'invalid boot SHA256 length' >&2; exit 65; }
fi
[ -f "$URL" ] && [ "$(sha256sum "$URL" | awk '{print $1}')" = "$SHA" ] || [ ! -f "$URL" ] || {
    echo 'staged system payload checksum mismatch' >&2; exit 65;
}
if [ -n "$BOOT_URL" ] && [ -f "$BOOT_URL" ]; then
    [ "$(sha256sum "$BOOT_URL" | awk '{print $1}')" = "$BOOT_SHA" ] || {
        echo 'staged boot payload checksum mismatch' >&2; exit 65;
    }
fi
[ "$(id -u)" -eq 0 ] || { echo 'run as root' >&2; exit 77; }
# Materialise p3-backed administrator state before RAM recovery replaces p2.
systemctl start atlantian-persist-state.service >/dev/null 2>&1 || true
mkdir -p "$BOOT" "$KERNEL"
mountpoint -q "$KERNEL" || mount /dev/mmcblk0p1 "$KERNEL"
mkdir -p /run
: >"$LOCK"
systemctl stop atlantian-status-leds.service atlantian-fpga-status-leds.service >/dev/null 2>&1 || true

# The factory U-Boot environment on CTRL_C41 is persistent in NAND and does
# not reliably consume uEnv.txt.  Therefore use kexec as the primary path:
# recovery runs entirely from RAM and can safely overwrite p1/p2.
if command -v kexec >/dev/null 2>&1 &&
   [ -r "$KERNEL/zImage" ] && [ -r "$KERNEL/atlantian-recovery.cpio.gz" ] &&
   [ -r "$KERNEL/devicetree.dtb" ]; then
    case "$URL" in /data/*) SYSTEM_ARG="atlantian.system_file=$URL";; *) SYSTEM_ARG="atlantian.system_url=$URL";; esac
    case "$BOOT_URL" in /data/*) BOOT_ARG="atlantian.boot_file=$BOOT_URL";; *) BOOT_ARG="atlantian.boot_url=$BOOT_URL";; esac
    CMDLINE="mem=496M console=ttyPS0,115200n8 root=/dev/ram0 rdinit=/init atlantian.mode=system $SYSTEM_ARG atlantian.system_sha256=$SHA $BOOT_ARG atlantian.boot_sha256=$BOOT_SHA"
    kexec -l "$KERNEL/zImage" --initrd="$KERNEL/atlantian-recovery.cpio.gz" \
        --dtb="$KERNEL/devicetree.dtb" --command-line="$CMDLINE"
    sync
    echo "AtlANTian: entering RAM recovery; /data will be preserved"
    kexec -e
    exit 0
fi

# Fallback for systems without kexec; retained for recovery/debug images.
cat >"$KERNEL/atlantian-update.scr" <<EOF
setenv atlantian_update 1
setenv atlantian_mode system
setenv atlantian_system_url $URL
setenv atlantian_system_sha256 $SHA
setenv atlantian_boot_url $BOOT_URL
setenv atlantian_boot_sha256 $BOOT_SHA
EOF
sync
echo "AtlANTian: scheduled release upgrade via bootloader; /data will be preserved"
systemctl reboot
