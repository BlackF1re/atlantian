#!/bin/sh
# Install or finish AtlANTian NAND maintenance from the paired recovery SD.
# Ordering: verify -> backup -> raw boot program/readback -> UBI write/verify -> handoff.
set -eu

BUNDLE=${ATLANTIAN_NAND_BUNDLE:-/usr/lib/atlantian/nand}
STATE=/var/lib/atlantian/nand-install
PENDING=$STATE/pending
READY=$STATE/ready-to-handoff
UPGRADE_SAVE=/var/cache/atlantian/nand-overlay-preserve
BACKUP_DEFAULT=/root/atlantian-factory-nand-backup
BOOT=/boot
MASTER_NAME=pl35x-nand-controller
MASTER= UBI_MTD= ROOT_UBI_VOL=

usage() {
  cat <<'EOF_USAGE'
Usage:
  atlantian-nand-install [--backup DIR]
  atlantian-nand-install --resume
  atlantian-nand-install --resume-auto
  atlantian-nand-install --handoff
EOF_USAGE
}
fatal() { echo "atlantian-nand-install: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fatal "missing required command: $1"; }
step() { printf '\n==> %s\n' "$*"; }
lock_install() { need flock; mkdir -p /run/lock; exec 9>/run/lock/atlantian-nand-install.lock; flock -n 9 || fatal 'another NAND install/upgrade process is already running'; }
verify_host() {
  [ "$(id -u)" -eq 0 ] || fatal 'run as root'
  model=$(tr -d '\000' </proc/device-tree/model 2>/dev/null || true); case "$model" in *Antminer*S9*) ;; *) fatal "unsupported board model: $model" ;; esac
  case "$(findmnt -n -o SOURCE / 2>/dev/null || true)" in /dev/mmcblk0p2) ;; *) fatal 'NAND maintenance must run from the AtlANTian recovery microSD' ;; esac
}
find_master() {
  line=$(awk -F: -v n="\"$MASTER_NAME\"" '$2 ~ n {gsub(/[[:space:]]/,"",$1); print $1; found++} END {if(found!=1) exit 1}' /proc/mtd) || fatal "expected exactly one whole $MASTER_NAME MTD device"
  MASTER=/dev/$line; [ -c "$MASTER" ] || fatal "missing $MASTER"
}
manifest_release() { jq -r '.release // empty' "$BUNDLE/NAND-MANIFEST.json" 2>/dev/null || true; }
select_pending_bundle() {
  [ -s "$PENDING" ] || return 0
  path=$(sed -n 's/^bundle=//p' "$PENDING" | head -n1); [ -n "$path" ] || return 0
  case "$path" in /var/cache/atlantian/nand-target/*/bundle) ;; *) fatal 'unsafe pending NAND bundle path' ;; esac
  BUNDLE=$path
  [ -s "$BUNDLE/NAND-MANIFEST.json" ] || fatal "pending bundle disappeared: $BUNDLE"
  expected=$(sed -n 's/^release=//p' "$PENDING" | head -n1); actual=$(manifest_release)
  [ -n "$expected" ] && [ "$actual" = "$expected" ] || fatal 'pending bundle/release identity mismatch'
}
verify_fresh_bundle_identity() {
  [ -s "$BUNDLE/NAND-MANIFEST.json" ] || fatal "NAND payload is missing under $BUNDLE"
  running=$(cat /usr/lib/atlantian/version 2>/dev/null || true); target=$(manifest_release)
  [ -n "$running" ] && [ -n "$target" ] || fatal 'cannot determine running/payload release identity'
  [ "$running" = "$target" ] || {
    echo "atlantian-nand-install: embedded NAND payload $target does not match running AtlANTian $running" >&2
    echo 'Use the matching release image, or stage a NAND base update from NAND with atlantian-sysupgrade.' >&2
    exit 78
  }
}
verify_platform() {
  verify_host
  for c in jq sha256sum mtdpart ubiformat ubiattach ubidetach ubimkvol ubiupdatevol ubiblock nanddump mount umount findmnt rsync atlantian-nand-rebase; do need "$c"; done
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
valid_backup() { d=$1; [ -s "$d/NAND-INFO.txt" ] && [ -s "$d/nand-raw-oob.bin" ] && [ -s "$d/SHA256SUMS" ] && (cd "$d" && sha256sum -c SHA256SUMS >/dev/null 2>&1); }
ensure_backup() {
  backup=$1; step '[1/4] Backing up the existing NAND'
  if valid_backup "$backup"; then echo "Using verified existing factory backup: $backup"; else atlantian-nand-backup "$backup"; valid_backup "$backup" || fatal 'factory backup did not verify'; fi
  echo "Factory backup verified: $backup"; echo 'Keep a copy on another computer if factory recovery matters.'
}
stage_raw_boot() {
  mode=$1; target=$(manifest_release); id=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n'); [ ${#id} -eq 32 ] || fatal 'cannot create installer identity'
  step '[2/4] Staging the verified raw boot transaction'; mountpoint -q "$BOOT" || mount /dev/mmcblk0p1 "$BOOT"
  install -m 0644 "$BUNDLE/spl-redundant.bin" "$BOOT/atln-spl.bin"
  install -m 0644 "$BUNDLE/u-boot.img" "$BOOT/atln-uboot.img"
  install -m 0644 "$BUNDLE/uImage" "$BOOT/atln-kernel.img"
  install -m 0644 "$BUNDLE/uInitrd" "$BOOT/atln-initrd.img"
  install -m 0644 "$BUNDLE/devicetree.dtb" "$BOOT/atln-dtb.bin"
  install -m 0644 "$BUNDLE/nand-stage.scr" "$BOOT/atln-stage.scr"
  printf '%s\n' "$id" >"$BOOT/atln-install.id"; rm -f "$BOOT/atln-stage.done"; mkdir -p "$STATE"
  printf 'installer_id=%s\nrelease=%s\nmode=%s\n' "$id" "$target" "$mode" >"$PENDING"; rm -f "$READY"; sync
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
validate_rebase_snapshot() {
  [ -s "$UPGRADE_SAVE/TRANSACTION" ] || fatal 'preserved upgrade metadata is missing'
  [ "$(sed -n 's/^rebase_schema=//p' "$UPGRADE_SAVE/TRANSACTION" | head -n1)" = 1 ] || fatal 'unsupported rebase schema'
  [ -s "$UPGRADE_SAVE/internal/METADATA" ] && [ -d "$UPGRADE_SAVE/internal/delta" ] || fatal 'internal rebase snapshot is incomplete'
  external_layout=$(sed -n 's/^external_layout=//p' "$UPGRADE_SAVE/TRANSACTION" | head -n1)
  case "$external_layout" in
    none|'') ;;
    recovery-p2)
      [ -s "$UPGRADE_SAVE/external/METADATA" ] && [ -d "$UPGRADE_SAVE/external/delta" ] || fatal 'external rebase snapshot is incomplete'
      [ -s "$UPGRADE_SAVE/.extroot-token" ] && [ -s /.atlantian-extroot/token ] || fatal 'external adoption token is missing'
      [ "$(cat /.atlantian-extroot/token)" = "$(cat "$UPGRADE_SAVE/.extroot-token")" ] || fatal 'external recovery-card token changed during upgrade' ;;
    *) fatal "unsupported preserved external overlay layout: $external_layout" ;;
  esac
}
write_ubi() {
  mode=$1 id=$2; root_bytes=$(jq -r .volumes.rootfs.bytes "$BUNDLE/NAND-MANIFEST.json"); root_image_bytes=$(jq -r .volumes.rootfs.image_bytes "$BUNDLE/NAND-MANIFEST.json")
  min_overlay=$(jq -r .volumes.overlay.minimum_lebs "$BUNDLE/NAND-MANIFEST.json"); leb=$(jq -r .nand.leb_bytes "$BUNDLE/NAND-MANIFEST.json"); target=$(manifest_release)
  [ "$mode" != upgrade ] || validate_rebase_snapshot
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
  if [ "$mode" = upgrade ]; then
    atlantian-nand-rebase restore "$UPGRADE_SAVE/internal" /run/atlantian-install-root /run/atlantian-install-overlay/upper /run/atlantian-install-overlay/work "$target"
    [ ! -s "$UPGRADE_SAVE/.extroot-token" ] || cp -a "$UPGRADE_SAVE/.extroot-token" /run/atlantian-install-overlay/.extroot-token
    external_layout=$(sed -n 's/^external_layout=//p' "$UPGRADE_SAVE/TRANSACTION" | head -n1)
    case "$external_layout" in
      none|'') ;;
      recovery-p2)
        [ -s /.atlantian-extroot/token ] && [ "$(cat /.atlantian-extroot/token)" = "$(cat "$UPGRADE_SAVE/.extroot-token")" ] || fatal 'external recovery-card token changed during upgrade'
        rm -rf /.atlantian-extroot/upper /.atlantian-extroot/work; mkdir -p /.atlantian-extroot/upper /.atlantian-extroot/work
        atlantian-nand-rebase restore "$UPGRADE_SAVE/external" /run/atlantian-install-root /.atlantian-extroot/upper /.atlantian-extroot/work "$target" ;;
      *) fatal "unsupported preserved external overlay layout: $external_layout" ;;
    esac
  else
    mkdir -p /run/atlantian-install-overlay/upper/var/lib/atlantian/nand
    printf '%s\n' "$id" >/run/atlantian-install-overlay/upper/var/lib/atlantian/nand/installer-id
    : >/run/atlantian-install-overlay/upper/var/lib/atlantian/nand/offer-extroot
  fi
  sync; umount /run/atlantian-install-overlay; umount /run/atlantian-install-root; remove_root_ubiblock; ubidetach -p "$UBI_MTD"; UBI_MTD=; trap - EXIT INT TERM HUP
  [ "$mode" != upgrade ] || rm -rf "$UPGRADE_SAVE"
  echo "Verified static SquashFS rootfs $target; writable UBIFS overlay bytes: $overlay_bytes"
}
finish_resume() {
  mode=$1 id=$2 target=$3
  rm -f "$BOOT/atln-stage.scr" "$BOOT/atln-stage.done" "$BOOT/atln-spl.bin" "$BOOT/atln-uboot.img" "$BOOT/atln-kernel.img" "$BOOT/atln-initrd.img" "$BOOT/atln-dtb.bin"
  printf 'installer_id=%s\nrelease=%s\nmode=%s\n' "$id" "$target" "$mode" >"$READY.new"; mv -f "$READY.new" "$READY"; rm -f "$PENDING"
  [ "$mode" != upgrade ] || rm -f /var/lib/atlantian/nand-target.env; sync; step '[4/4] NAND installation is complete and verified'
}
resume() {
  auto=${1:-no}; select_pending_bundle; verify_platform
  if [ -s "$READY" ] && [ ! -s "$PENDING" ]; then [ "$auto" = yes ] && exit 0; handoff; return; fi
  [ -s "$PENDING" ] || fatal 'no pending NAND transaction exists'; mountpoint -q "$BOOT" || mount /dev/mmcblk0p1 "$BOOT"
  [ -s "$BOOT/atln-stage.done" ] || fatal 'SD U-Boot did not leave a verified NAND-stage marker; keep jumper in SD mode and inspect UART'
  id=$(sed -n 's/^installer_id=//p' "$PENDING" | head -n1); mode=$(sed -n 's/^mode=//p' "$PENDING" | head -n1); target=$(sed -n 's/^release=//p' "$PENDING" | head -n1)
  case "$mode" in fresh|upgrade) ;; *) fatal "invalid pending NAND mode: $mode" ;; esac
  [ "$(manifest_release)" = "$target" ] || fatal 'pending NAND bundle/release identity mismatch'
  [ -n "$id" ] && [ -r "$BOOT/atln-install.id" ] && [ "$(cat "$BOOT/atln-install.id")" = "$id" ] || fatal 'installer-card identity mismatch'
  write_ubi "$mode" "$id"; finish_resume "$mode" "$id" "$target"; [ "$auto" = yes ] && return; handoff
}
handoff() {
  verify_host; [ -s "$READY" ] || fatal 'NAND has not completed verified installation yet'
  cat <<'EOF_HANDOFF'
NAND is ready. Leave the recovery microSD inserted, move the boot-source jumper
from SD to NAND, then press Enter. The jumper is sampled by hardware at reset.
EOF_HANDOFF
  if ! IFS= read -r _; then echo 'Handoff postponed. Run atlantian-nand-install --handoff when ready.'; return 0; fi
  rm -f "$READY"; sync; if ! systemctl reboot; then : >"$READY"; sync; fatal 'reboot request failed; handoff state restored'; fi
}

mode=install backup=$BACKUP_DEFAULT
while [ $# -gt 0 ]; do
  case "$1" in --resume) mode=resume; shift ;; --resume-auto) mode=resume-auto; shift ;; --handoff) mode=handoff; shift ;; --backup) [ $# -ge 2 ] || { usage >&2; exit 64; }; backup=$2; shift 2 ;; --help|-h) usage; exit 0 ;; *) usage >&2; exit 64 ;; esac
done
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
ensure_backup "$backup"
printf '\nFINAL DESTRUCTIVE CONFIRMATION: type INSTALL to replace the on-board NAND: '
IFS= read -r answer; [ "$answer" = INSTALL ] || { echo 'Cancelled; NAND was not modified.'; exit 0; }
stage_raw_boot fresh
