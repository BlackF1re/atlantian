#!/bin/sh
# Prepare a same-major NAND base replacement while booted from the recovery SD.
set -eu

DEFAULT_BUNDLE=${ATLANTIAN_NAND_BUNDLE:-/usr/lib/atlantian/nand}
PREPARED=/var/lib/atlantian/nand-target.env
BUNDLE=$DEFAULT_BUNDLE
MASTER_NAME=pl35x-nand-controller
MASTER= UBI_MTD= ROOT_UBI_VOL= ROOT_BLOCK=
BOOT=/boot
STATE=/var/lib/atlantian/nand-install
PENDING=$STATE/pending
SAVE=/var/cache/atlantian/nand-overlay-preserve
RECOVERY_EXTROOT=/.atlantian-extroot

fatal() { echo "atlantian-nand-upgrade: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fatal "missing required command: $1"; }
major_of() { v=${1%%.*}; case "$v" in ''|*[!0-9]*) return 1;; esac; printf '%s\n' "$v"; }
find_ubi_volume() {
  wanted=$1 found=
  for d in /sys/class/ubi/ubi0_*; do [ -r "$d/name" ] || continue; [ "$(cat "$d/name")" = "$wanted" ] || continue; [ -z "$found" ] || fatal "multiple UBI volumes named $wanted"; found=${d##*/}; done
  [ -n "$found" ] || fatal "UBI volume not found: $wanted"; printf '%s\n' "$found"
}
cleanup() {
  set +e
  for p in /run/atlantian-upgrade-overlay /run/atlantian-upgrade-root; do mountpoint -q "$p" && umount "$p"; done
  [ -n "${ROOT_UBI_VOL:-}" ] && ubiblock --remove "/dev/$ROOT_UBI_VOL" >/dev/null 2>&1 || true
  ROOT_UBI_VOL=; ROOT_BLOCK=
  [ -n "${UBI_MTD:-}" ] && ubidetach -p "$UBI_MTD" >/dev/null 2>&1
  set -e
}
trap cleanup EXIT INT TERM HUP

[ "$(id -u)" -eq 0 ] || fatal 'run as root'
for c in jq sha256sum mtdpart ubiattach ubidetach ubiblock findmnt dpkg mount umount du df atlantian-nand-rebase; do need "$c"; done
case "$(findmnt -n -o SOURCE / 2>/dev/null || true)" in /dev/mmcblk0p2) ;; *) fatal 'boot the AtlANTian recovery microSD first' ;; esac
[ ! -s "$PENDING" ] || fatal 'another NAND transaction is already pending; allow auto-resume to finish or use atlantian-nand-install --resume'

prepared=false
if [ -s "$PREPARED" ]; then
  path=$(sed -n 's/^bundle=//p' "$PREPARED" | head -n1); expected=$(sed -n 's/^target=//p' "$PREPARED" | head -n1)
  case "$path" in /var/cache/atlantian/nand-target/*/bundle) ;; *) fatal 'unsafe prepared bundle path' ;; esac
  [ -n "$expected" ] || fatal 'prepared target identity is missing'; BUNDLE=$path; prepared=true
fi
[ -s "$BUNDLE/NAND-MANIFEST.json" ] && [ -s "$BUNDLE/SHA256SUMS" ] || fatal "target NAND bundle is missing under $BUNDLE"
target=$(jq -r '.release // empty' "$BUNDLE/NAND-MANIFEST.json"); [ -n "$target" ] || fatal 'cannot determine target release identity'
if [ "$prepared" = true ]; then
  [ "$target" = "$expected" ] || fatal "prepared payload is $target, marker expects $expected"
else
  running=$(cat /usr/lib/atlantian/version 2>/dev/null || true); [ -n "$running" ] || fatal 'cannot determine running release identity'
  [ "$running" = "$target" ] || { echo "atlantian-nand-upgrade: embedded payload $target does not match running AtlANTian $running" >&2; echo 'Run atlantian-sysupgrade from NAND to stage the target bundle on this recovery card.' >&2; exit 78; }
fi

(cd "$BUNDLE" && sha256sum -c SHA256SUMS) || fatal 'NAND bundle checksums failed'
[ "$(jq -r .compression.rootfs_squashfs "$BUNDLE/NAND-MANIFEST.json")" = zstd ] || fatal 'target immutable root must be Zstd SquashFS'
[ "$(jq -r .compression.overlay_ubifs "$BUNDLE/NAND-MANIFEST.json")" = lzo ] || fatal 'target writable UBIFS must use LZO'
[ "$(jq -r .volumes.rootfs.type "$BUNDLE/NAND-MANIFEST.json")" = static ] || fatal 'target rootfs volume must be static'
target_major=$(major_of "$target") || fatal "invalid target release: $target"

line=$(awk -F: -v n="\"$MASTER_NAME\"" '$2 ~ n {gsub(/[[:space:]]/,"",$1); print $1; found++} END {if(found!=1) exit 1}' /proc/mtd) || fatal "expected exactly one whole $MASTER_NAME device"
MASTER=/dev/$line; [ "$(cat /sys/class/mtd/$line/size)" = 268435456 ] || fatal 'unexpected NAND capacity'
ubi_offset=$(jq -r .nand.ubi_offset_bytes "$BUNDLE/NAND-MANIFEST.json"); ubi_size=$((268435456 - ubi_offset))
mtdpart add "$MASTER" atlantian-ubi "$ubi_offset" "$ubi_size" 2>/dev/null || true
UBI_MTD=$(awk -F: '$2 ~ /"atlantian-ubi"/ {gsub(/[[:space:]]/,"",$1); print "/dev/"$1; found++} END {if(found!=1) exit 1}' /proc/mtd) || fatal 'atlantian-ubi partition did not appear'
ubiattach -p "$UBI_MTD" || fatal 'installed AtlANTian UBI could not be attached; use recovery/reinstall instead'
mkdir -p /run/atlantian-upgrade-root /run/atlantian-upgrade-overlay

root_vol=$(find_ubi_volume rootfs); [ "$(cat "/sys/class/ubi/$root_vol/type" 2>/dev/null || true)" = static ] || fatal 'installed NAND rootfs must be static'
ROOT_UBI_VOL=$root_vol; ubiblock --create "/dev/$root_vol" || fatal 'cannot expose installed rootfs through ubiblock'
ROOT_BLOCK=/dev/ubiblock${root_vol#ubi}; n=0; while [ ! -b "$ROOT_BLOCK" ] && [ "$n" -lt 20 ]; do sleep 0.1; n=$((n+1)); done; [ -b "$ROOT_BLOCK" ] || fatal "missing $ROOT_BLOCK"
mount -t squashfs -o ro,nodev "$ROOT_BLOCK" /run/atlantian-upgrade-root || fatal 'installed NAND rootfs is not readable SquashFS'
mount -t ubifs -o rw,noatime,compr=lzo ubi0:overlay /run/atlantian-upgrade-overlay || fatal 'installed NAND overlay is unavailable'
[ -d /run/atlantian-upgrade-overlay/upper ] && [ -d /run/atlantian-upgrade-overlay/work ] || fatal 'installed NAND overlay lacks upper/work directories'

current=$(cat /run/atlantian-upgrade-root/usr/lib/atlantian/version 2>/dev/null || true); current_major=$(major_of "$current") || fatal 'installed NAND base has no valid release identity'
[ "$target_major" = "$current_major" ] || fatal "NAND base major transition $current_major -> $target_major requires a clean NAND reinstall"
dpkg --compare-versions "$target" ge "$current" || fatal "refusing NAND base downgrade: $current -> $target"

external_layout=none; external_upper=; external_work=; rm -rf "$SAVE"; mkdir -p "$SAVE"
if [ -s /run/atlantian-upgrade-overlay/.extroot-token ]; then
  cp -a /run/atlantian-upgrade-overlay/.extroot-token "$SAVE/"; token=$(cat /run/atlantian-upgrade-overlay/.extroot-token)
  if [ -s "$RECOVERY_EXTROOT/token" ] && [ "$(cat "$RECOVERY_EXTROOT/token")" = "$token" ] && [ -d "$RECOVERY_EXTROOT/upper" ] && [ -d "$RECOVERY_EXTROOT/work" ]; then
    external_layout=recovery-p2; external_upper=$RECOVERY_EXTROOT/upper; external_work=$RECOVERY_EXTROOT/work
  else fatal 'adopted external upper is missing or token-mismatched; refusing to replace its lower'; fi
fi
internal_used=$(du -sb --apparent-size /run/atlantian-upgrade-overlay/upper | awk '{print $1}'); external_used=0
[ -z "$external_upper" ] || external_used=$(du -sb --apparent-size "$external_upper" | awk '{print $1}')
available=$(df -Pk /var/cache | awk 'NR==2 {print $4*1024}'); required=$((internal_used + external_used + 64*1024*1024))
[ "$available" -ge "$required" ] || fatal "recovery SD lacks temporary rebase space: need $required bytes, have $available"

atlantian-nand-rebase capture /run/atlantian-upgrade-root /run/atlantian-upgrade-overlay/upper /run/atlantian-upgrade-overlay/work "$SAVE/internal"
[ "$external_layout" != recovery-p2 ] || atlantian-nand-rebase capture /run/atlantian-upgrade-root "$external_upper" "$external_work" "$SAVE/external"
printf 'current=%s\ntarget=%s\nexternal_layout=%s\nrebase_schema=1\n' "$current" "$target" "$external_layout" >"$SAVE/TRANSACTION"
sync; cleanup; trap - EXIT INT TERM HUP

printf '\nNAND base upgrade prepared: %s -> %s\n' "$current" "$target"
echo 'Persistent state and package intent are captured; no target NAND data has been written yet.'
printf 'Type UPGRADE to begin the verified raw-boot programming stage: '
IFS= read -r answer
if [ "$answer" != UPGRADE ]; then rm -rf "$SAVE"; echo 'Cancelled before NAND erase.'; exit 0; fi

mountpoint -q "$BOOT" || mount /dev/mmcblk0p1 "$BOOT"
id=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n'); [ ${#id} -eq 32 ] || fatal 'cannot create maintenance identity'
install -m 0644 "$BUNDLE/spl-redundant.bin" "$BOOT/atln-spl.bin"
install -m 0644 "$BUNDLE/u-boot.img" "$BOOT/atln-uboot.img"
install -m 0644 "$BUNDLE/uImage" "$BOOT/atln-kernel.img"
install -m 0644 "$BUNDLE/uInitrd" "$BOOT/atln-initrd.img"
install -m 0644 "$BUNDLE/devicetree.dtb" "$BOOT/atln-dtb.bin"
install -m 0644 "$BUNDLE/nand-stage.scr" "$BOOT/atln-stage.scr"
printf '%s\n' "$id" >"$BOOT/atln-install.id"; rm -f "$BOOT/atln-stage.done"; mkdir -p "$STATE"
printf 'installer_id=%s\nrelease=%s\nmode=upgrade\nbundle=%s\n' "$id" "$target" "$BUNDLE" >"$PENDING"; sync

echo 'Keep the physical jumper in SD mode. Rebooting into verified raw-boot programming.'
systemctl reboot
