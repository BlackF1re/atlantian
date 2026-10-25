#!/bin/sh
# Install or finish a fresh AtlANTian NAND installation from bootable SD.
# Ordering: verify -> backup -> raw boot program/readback -> UBI write/verify -> handoff.
set -eu

BUNDLE=${ATLANTIAN_NAND_BUNDLE:-/usr/lib/atlantian/nand}
STATE=/var/lib/atlantian/nand-install
PENDING=$STATE/pending
READY=$STATE/ready-to-handoff
# Fresh NAND installation always runs from /dev/mmcblk0p2, so the default
# recovery backup lives explicitly on the recovery microSD root filesystem.
BACKUP_DEFAULT=/var/lib/atlantian/recovery/factory-nand-backup
BOOT=/boot
MASTER_NAME=pl35x-nand-controller
EXPECTED_MANUFACTURER=@ATLANTIAN_NAND_MANUFACTURER_ID@
EXPECTED_DEVICE=@ATLANTIAN_NAND_DEVICE_ID@
MASTER= UBI_MTD= ROOT_UBI_VOL=

usage() {
  cat <<'EOF_USAGE'
Usage:
  atlantian-nand-install [--backup DIR | --no-backup]
  atlantian-nand-install --resume
  atlantian-nand-install --resume-auto
  atlantian-nand-install --handoff
EOF_USAGE
}
fatal() { echo "atlantian-nand-install: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fatal "missing required command: $1"; }
step() { printf '\n==> %s\n' "$*"; }
lock_install() { need flock; mkdir -p /run/lock; exec 9>/run/lock/atlantian-nand-install.lock; flock -n 9 || fatal 'another NAND installation is already running'; }
verify_host() {
  [ "$(id -u)" -eq 0 ] || fatal 'run as root'
  model=$(tr -d '\000' </proc/device-tree/model 2>/dev/null || true); case "$model" in *Antminer*S9*) ;; *) fatal "unsupported board model: $model" ;; esac
  case "$(findmnt -n -o SOURCE / 2>/dev/null || true)" in /dev/mmcblk0p2) ;; *) fatal 'NAND installation must run from a bootable AtlANTian microSD' ;; esac
}
verify_nand_identity() {
  manufacturer=$(printf '%02x' "$((EXPECTED_MANUFACTURER))")
  device=$(printf '%02x' "$((EXPECTED_DEVICE))")
  dmesg_file=${ATLANTIAN_NAND_DMESG_FILE:-}
  if [ -n "$dmesg_file" ]; then
    [ -r "$dmesg_file" ] || fatal "unreadable NAND probe log: $dmesg_file"
    probe_log=$(cat "$dmesg_file")
  else
    need dmesg
    probe_log=$(dmesg 2>/dev/null) || fatal 'cannot read kernel NAND probe log'
  fi
  printf '%s\n' "$probe_log" | grep -Eqi \
    "Manufacturer ID:[[:space:]]*0x${manufacturer},[[:space:]]*Chip ID:[[:space:]]*0x${device}" || {
      fatal "unsupported or unverified NAND identity; expected ${manufacturer}:${device} before any destructive operation"
    }
}
find_master() {
  line=$(awk -F: -v n="\"$MASTER_NAME\"" '$2 ~ n {gsub(/[[:space:]]/,"",$1); print $1; found++} END {if(found!=1) exit 1}' /proc/mtd) || fatal "expected exactly one whole $MASTER_NAME MTD device"
  MASTER=/dev/$line; [ -c "$MASTER" ] || fatal "missing $MASTER"
}
manifest_release() { jq -r '.release // empty' "$BUNDLE/NAND-MANIFEST.json" 2>/dev/null || true; }
verify_fresh_bundle_identity() {
  [ -s "$BUNDLE/NAND-MANIFEST.json" ] || fatal "NAND payload is missing under $BUNDLE"
  running=$(cat /usr/lib/atlantian/version 2>/dev/null || true); target=$(manifest_release)
  [ -n "$running" ] && [ -n "$target" ] || fatal 'cannot determine running/payload release identity'
  [ "$running" = "$target" ] || {
    echo "atlantian-nand-install: embedded NAND payload $target does not match running AtlANTian $running" >&2
    echo 'Use an SD image with the matching AtlANTian release.' >&2
    exit 78
  }
}
verify_platform() {
  verify_host
  verify_nand_identity
  for c in jq sha256sum pigz mtdpart ubiformat ubiattach ubidetach ubimkvol ubiupdatevol ubiblock nanddump mount umount findmnt ; do need "$c"; done
  [ -s "$BUNDLE/NAND-MANIFEST.json" ] && [ -s "$BUNDLE/SHA256SUMS" ] || fatal "NAND payload is missing under $BUNDLE"
  (cd "$BUNDLE" && sha256sum -c SHA256SUMS >/dev/null) || fatal 'NAND payload checksum verification failed'
  [ "$(jq -r .compression.rootfs_squashfs "$BUNDLE/NAND-MANIFEST.json")" = zstd ] || fatal 'unexpected SquashFS compression policy'
  [ "$(jq -r .compression.overlay_ubifs "$BUNDLE/NAND-MANIFEST.json")" = lzo ] || fatal 'unexpected UBIFS compression policy'
  [ "$(jq -r .volumes.rootfs.type "$BUNDLE/NAND-MANIFEST.json")" = static ] || fatal 'rootfs UBI volume must be static'
  [ "$(jq -r .volumes.rootfs.filesystem "$BUNDLE/NAND-MANIFEST.json")" = squashfs ] || fatal 'rootfs filesystem must be SquashFS'
  find_master; mtd=${MASTER##*/}
  [ "$(cat "/sys/class/mtd/$mtd/size")" = 268435456 ] || fatal 'unexpected NAND size'
  [ "$(cat "/sys/class/mtd/$mtd/erasesize")" = 131072 ] || fatal 'unexpected erase size'
  [ "$(cat "/sys/class/mtd/$mtd/writesize")" = 2048 ] || fatal 'unexpected page size'
  [ "$(cat "/sys/class/mtd/$mtd/oobsize")" = 64 ] || fatal 'unexpected OOB size'
  strength=$(cat "/sys/class/mtd/$mtd/ecc_strength" 2>/dev/null || echo 0); ecc_step=$(cat "/sys/class/mtd/$mtd/ecc_step_size" 2>/dev/null || echo 0)
  [ "$strength" -ge 4 ] && [ "$ecc_step" = 512 ] || fatal "Linux NAND data ECC is $strength/$ecc_step; expected BCH >=4/512"
}
valid_backup() {
  d=$1
  [ -s "$d/NAND-INFO.txt" ] && [ -s "$d/SHA256SUMS" ] || return 1
  if [ -s "$d/nand-raw-oob.bin.gz" ]; then
    raw_name=nand-raw-oob.bin.gz
    pigz -t "$d/$raw_name" >/dev/null 2>&1 || return 1
  elif [ -s "$d/nand-raw-oob.bin" ]; then
    # Backward-compatible reuse of a verified pre-compression backup.
    raw_name=nand-raw-oob.bin
  else
    return 1
  fi
  grep -Fq "  $raw_name" "$d/SHA256SUMS" || return 1
  (cd "$d" && sha256sum -c SHA256SUMS >/dev/null 2>&1)
}
ensure_backup() {
  backup=$1; step '[1/4] Backing up the existing NAND to recovery storage'
  if valid_backup "$backup"; then echo "Using verified existing factory backup: $backup"; else atlantian-nand-backup "$backup"; valid_backup "$backup" || fatal 'factory backup did not verify'; fi
  echo "Factory backup verified: $backup"; echo 'Keep a copy on another computer if factory recovery matters.'
}
stage_raw_boot() {
  target=$(manifest_release); id=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n'); [ ${#id} -eq 32 ] || fatal 'cannot create installer identity'
  step '[2/4] Staging the verified raw boot transaction'; mountpoint -q "$BOOT" || mount /dev/mmcblk0p1 "$BOOT"
  install -m 0644 "$BUNDLE/spl-redundant.bin" "$BOOT/atln-spl.bin"
  install -m 0644 "$BUNDLE/u-boot.img" "$BOOT/atln-uboot.img"
  install -m 0644 "$BUNDLE/uImage" "$BOOT/atln-kernel.img"
  install -m 0644 "$BUNDLE/uInitrd" "$BOOT/atln-initrd.img"
  install -m 0644 "$BUNDLE/devicetree.dtb" "$BOOT/atln-dtb.bin"
  install -m 0644 "$BUNDLE/nand-stage.scr" "$BOOT/atln-stage.scr"
  printf '%s\n' "$id" >"$BOOT/atln-install.id"; rm -f "$BOOT/atln-stage.done"; mkdir -p "$STATE"
  printf 'installer_id=%s\nrelease=%s\nmode=fresh\n' "$id" "$target" >"$PENDING"; rm -f "$READY"; sync
  echo 'Rebooting in SD mode. Do not move the boot jumper yet.'; systemctl reboot
}
find_ubi_volume() {
  wanted=$1 found=
  for d in /sys/class/ubi/ubi0_*; do [ -r "$d/name" ] || continue; [ "$(cat "$d/name")" = "$wanted" ] || continue; [ -z "$found" ] || fatal "multiple UBI volumes named $wanted"; found=${d##*/}; done
  [ -n "$found" ] || fatal "UBI volume not found: $wanted"; printf '%s\n' "$found"
}
remove_root_ubiblock() { [ -n "${ROOT_UBI_VOL:-}" ] || return 0; ubiblock --remove "/dev/$ROOT_UBI_VOL" >/dev/null 2>&1 || true; ROOT_UBI_VOL=; }
cleanup_ubi() { set +e; for p in /run/atlantian-install-overlay /run/atlantian-install-root; do mountpoint -q "$p" && umount "$p"; done; remove_root_ubiblock; [ -n "${UBI_MTD:-}" ] && ubidetach -p "$UBI_MTD" >/dev/null 2>&1; set -e; }
create_ubi_partition() {
  existing=$(awk -F: '$2 ~ /"atlantian-ubi"/ {gsub(/[[:space:]]/,"",$1); print "/dev/"$1; found++} END {if(found>1) exit 1}' /proc/mtd) || fatal 'multiple atlantian-ubi partitions exist'
  if [ -n "$existing" ]; then UBI_MTD=$existing; return; fi
  ubi_offset=$(jq -r .nand.ubi_offset_bytes "$BUNDLE/NAND-MANIFEST.json"); ubi_size=$((268435456 - ubi_offset)); mtdpart add "$MASTER" atlantian-ubi "$ubi_offset" "$ubi_size"
  UBI_MTD=$(awk -F: '$2 ~ /"atlantian-ubi"/ {gsub(/[[:space:]]/,"",$1); print "/dev/"$1; found++} END {if(found!=1) exit 1}' /proc/mtd) || fatal 'atlantian-ubi partition did not appear'
}
write_ubi() {
  id=$1; root_bytes=$(jq -r .volumes.rootfs.bytes "$BUNDLE/NAND-MANIFEST.json"); root_image_bytes=$(jq -r .volumes.rootfs.image_bytes "$BUNDLE/NAND-MANIFEST.json")
  min_overlay=$(jq -r .volumes.overlay.minimum_lebs "$BUNDLE/NAND-MANIFEST.json"); leb=$(jq -r .nand.leb_bytes "$BUNDLE/NAND-MANIFEST.json"); target=$(manifest_release)
  step '[3/4] Formatting and writing the UBI data region'; create_ubi_partition; trap cleanup_ubi EXIT INT TERM HUP
  ubidetach -p "$UBI_MTD" >/dev/null 2>&1 || true; ubiformat "$UBI_MTD" -y; ubiattach -p "$UBI_MTD"
  ubimkvol /dev/ubi0 -N rootfs -t static -s "$root_bytes"; root_vol=$(find_ubi_volume rootfs); ubiupdatevol "/dev/$root_vol" "$BUNDLE/rootfs.squashfs"
  [ "$(cat "/sys/class/ubi/$root_vol/type")" = static ] || fatal 'written rootfs volume is not static'
  [ "$(cat "/sys/class/ubi/$root_vol/data_bytes")" = "$root_image_bytes" ] || fatal 'static rootfs data size mismatch'
  ubimkvol /dev/ubi0 -N overlay -m; overlay_vol=$(find_ubi_volume overlay); overlay_bytes=$(cat "/sys/class/ubi/$overlay_vol/data_bytes" 2>/dev/null || true)
  case "$overlay_bytes" in ''|*[!0-9]*) fatal 'cannot determine overlay volume size' ;; esac
  [ "$overlay_bytes" -ge $((min_overlay * leb)) ] || fatal 'actual bad blocks leave less than required overlay reserve'
  mkdir -p /run/atlantian-install-root /run/atlantian-install-overlay; ROOT_UBI_VOL=$root_vol; ubiblock --create "/dev/$root_vol"
  root_block=/dev/ubiblock${root_vol#ubi}; n=0; while [ ! -b "$root_block" ] && [ "$n" -lt 20 ]; do sleep 0.1; n=$((n+1)); done; [ -b "$root_block" ] || fatal "missing $root_block"
  mount -t squashfs -o ro,nodev "$root_block" /run/atlantian-install-root
  [ "$(cat /run/atlantian-install-root/usr/lib/atlantian/version 2>/dev/null || true)" = "$target" ] || fatal 'written rootfs release mismatch'
  mount -t ubifs -o rw,noatime,compr=lzo ubi0:overlay /run/atlantian-install-overlay; mkdir -p /run/atlantian-install-overlay/upper /run/atlantian-install-overlay/work
  mkdir -p /run/atlantian-install-overlay/upper/var/lib/atlantian/nand
  printf '%s\n' "$id" >/run/atlantian-install-overlay/upper/var/lib/atlantian/nand/installer-id
  : >/run/atlantian-install-overlay/upper/var/lib/atlantian/nand/offer-extroot
  sync; umount /run/atlantian-install-overlay; umount /run/atlantian-install-root; remove_root_ubiblock; ubidetach -p "$UBI_MTD"; UBI_MTD=; trap - EXIT INT TERM HUP
  echo "Verified static SquashFS rootfs $target; writable UBIFS overlay bytes: $overlay_bytes"
}
finish_resume() {
  id=$1 target=$2
  rm -f "$BOOT/atln-stage.scr" "$BOOT/atln-stage.done" "$BOOT/atln-spl.bin" "$BOOT/atln-uboot.img" "$BOOT/atln-kernel.img" "$BOOT/atln-initrd.img" "$BOOT/atln-dtb.bin"
  printf 'installer_id=%s\nrelease=%s\nmode=fresh\n' "$id" "$target" >"$READY.new"; mv -f "$READY.new" "$READY"; rm -f "$PENDING"
  sync; step '[4/4] NAND installation is complete and verified'
}
resume() {
  auto=${1:-no}; verify_fresh_bundle_identity; verify_platform
  if [ -s "$READY" ] && [ ! -s "$PENDING" ]; then [ "$auto" = yes ] && exit 0; handoff; return; fi
  [ -s "$PENDING" ] || fatal 'no pending NAND transaction exists'; mountpoint -q "$BOOT" || mount /dev/mmcblk0p1 "$BOOT"
  [ -s "$BOOT/atln-stage.done" ] || fatal 'SD U-Boot did not leave a verified NAND-stage marker; keep jumper in SD mode and inspect UART'
  id=$(sed -n 's/^installer_id=//p' "$PENDING" | head -n1); mode=$(sed -n 's/^mode=//p' "$PENDING" | head -n1); target=$(sed -n 's/^release=//p' "$PENDING" | head -n1)
  [ "$mode" = fresh ] || fatal "unsupported pending NAND transaction mode: $mode"
  [ "$(manifest_release)" = "$target" ] || fatal 'pending NAND bundle/release identity mismatch'
  [ -n "$id" ] && [ -r "$BOOT/atln-install.id" ] && [ "$(cat "$BOOT/atln-install.id")" = "$id" ] || fatal 'installer-card identity mismatch'
  write_ubi "$id"; finish_resume "$id" "$target"; [ "$auto" = yes ] && return; handoff
}
handoff() {
  verify_host; [ -s "$READY" ] || fatal 'NAND has not completed verified installation yet'
  cat <<'EOF_HANDOFF'
NAND is ready and verified.
Fully remove power from the board, move the boot-source jumper from SD to NAND,
then restore power. Do not use reboot: the boot-source straps are sampled only
at power-on reset.
EOF_HANDOFF
  rm -f "$READY"; sync
}

if [ "${ATLANTIAN_NAND_INSTALL_LIBRARY_ONLY:-0}" = 1 ]; then return 0 2>/dev/null || exit 0; fi

mode=install backup=$BACKUP_DEFAULT backup_option=default
while [ $# -gt 0 ]; do
  case "$1" in
    --resume) mode=resume; shift ;;
    --resume-auto) mode=resume-auto; shift ;;
    --handoff) mode=handoff; shift ;;
    --backup)
      [ $# -ge 2 ] || { usage >&2; exit 64; }
      [ "$backup_option" = default ] || { echo 'atlantian-nand-install: --backup and --no-backup are mutually exclusive' >&2; exit 64; }
      backup=$2; backup_option=custom; shift 2 ;;
    --no-backup)
      [ "$backup_option" = default ] || { echo 'atlantian-nand-install: --backup and --no-backup are mutually exclusive' >&2; exit 64; }
      backup_option=skip; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
  esac
done
[ "$mode" = install ] || [ "$backup_option" = default ] || { echo 'atlantian-nand-install: backup options are valid only for a fresh install' >&2; exit 64; }
lock_install
case "$mode" in resume) resume no; exit ;; resume-auto) resume yes; exit ;; handoff) handoff; exit ;; esac
verify_fresh_bundle_identity; verify_platform
if [ -s "$READY" ]; then handoff; exit; fi
[ ! -s "$PENDING" ] || { echo 'A NAND transaction is already pending; use atlantian-nand-install --resume for manual recovery.'; exit 75; }
cat <<'EOF_INTRO'
AtlANTian NAND installer
------------------------
This replaces the on-board NAND with verified raw boot, an immutable SquashFS
base in static UBI, and a writable UBIFS OverlayFS upper. Existing NAND contents
will be destroyed; the recovery microSD remains intact.
EOF_INTRO
if [ "$backup_option" = skip ]; then
  step '[1/4] Skipping NAND backup (--no-backup)'
  echo 'WARNING: the existing NAND will be destroyed without a recovery dump.'
else
  ensure_backup "$backup"
fi
printf '\nFINAL DESTRUCTIVE CONFIRMATION: type INSTALL to replace the on-board NAND: '
IFS= read -r answer; [ "$answer" = INSTALL ] || { echo 'Cancelled; NAND was not modified.'; exit 0; }
stage_raw_boot