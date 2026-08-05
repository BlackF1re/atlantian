#!/bin/sh
# System-only updater. It writes the next release to mmcblk0p2 and never
# touches p1 (boot) or p3 (/data). Recovery performs the write from RAM.
set -eu

URL=${1:-}
SHA=${2:-}
BOOT=/run/atlantian-boot
KERNEL=/mnt/atlantian-boot
LOCK=/run/atlantian-update-leds.lock
if [ -z "$URL" ] || [ -z "$SHA" ]; then
    echo "usage: atlantian-sysupgrade SYSTEM_EXT4_URL SYSTEM_EXT4_SHA256" >&2
    exit 64
fi
case "$URL" in http://*) ;; *) echo 'only http:// URLs are accepted' >&2; exit 65;; esac
case "$SHA" in *[!0-9a-fA-F]*|'') echo 'invalid SHA256' >&2; exit 65;; esac
[ "${#SHA}" -eq 64 ] || { echo 'invalid SHA256 length' >&2; exit 65; }
[ "$(id -u)" -eq 0 ] || { echo 'run as root' >&2; exit 77; }
mkdir -p "$BOOT" "$KERNEL"
mountpoint -q "$KERNEL" || mount /dev/mmcblk0p1 "$KERNEL"
mkdir -p /run
: >"$LOCK"
systemctl stop atlantian-status-leds.service atlantian-fpga-status-leds.service >/dev/null 2>&1 || true

# The factory U-Boot environment on CTRL_C41 is persistent in NAND and does
# not reliably consume uEnv.txt.  Therefore use kexec as the primary path:
# recovery runs entirely from RAM and can safely overwrite only p2.
if command -v kexec >/dev/null 2>&1 &&
   [ -r "$KERNEL/zImage" ] && [ -r "$KERNEL/atlantian-recovery.cpio.gz" ] &&
   [ -r "$KERNEL/devicetree.dtb" ]; then
    CMDLINE="mem=496M console=ttyPS0,115200n8 root=/dev/ram0 rdinit=/init atlantian.mode=system atlantian.system_url=$URL atlantian.system_sha256=$SHA"
    kexec -l "$KERNEL/zImage" --initrd="$KERNEL/atlantian-recovery.cpio.gz" \
        --dtb="$KERNEL/devicetree.dtb" --command-line="$CMDLINE"
    sync
    echo "AtlANTian: entering RAM recovery for system-only upgrade; /data will be preserved"
    kexec -e
    exit 0
fi

# Fallback for systems without kexec; retained for recovery/debug images.
cat >"$KERNEL/atlantian-update.scr" <<EOF
setenv atlantian_update 1
setenv atlantian_mode system
setenv atlantian_system_url $URL
setenv atlantian_system_sha256 $SHA
EOF
sync
echo "AtlANTian: scheduled system-only upgrade via bootloader; /data will be preserved"
systemctl reboot
