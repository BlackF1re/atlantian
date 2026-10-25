#!/bin/sh
# Autonomous offline SD / NAND updater, executed only from kexec RAM initramfs.
set -eu
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
fail() { echo "RAM upgrader: $*" >&2; exit 1; }
log() { echo "RAM upgrader: $*"; }
need() { command -v "$1" >/dev/null 2>&1 || fail "missing $1"; }
[ -s /state/edition ] && [ -s /state/signed-internal-sums ] || fail 'not a prepared RAM image'
edition=$(cat /state/edition)
target=$(cat /state/target)
overlay_mode=$(cat /state/overlay-mode)
oldmajor=$(cat /state/old-major)
newmajor=$(cat /state/new-major)
case "$edition:$overlay_mode" in sd:sd|nand:internal|nand:external) ;; *) fail 'invalid edition/overlay' ;; esac
cd /payload
if ! sha256sum -c /state/signed-internal-sums >/run/upgrade/payload-check.log 2>&1; then
  cat /run/upgrade/payload-check.log >&2
  fail 'RAM payload checksum mismatch'
fi
[ "$(jq -r .release NAND-MANIFEST.json)" = "$target" ] || fail 'target mismatch'
mark() {
  case "$1" in
    old-state-captured) label='NAND: existing settings saved in RAM' ;;
    formatting-ubi) label='NAND: writing new filesystem (do not power off)' ;;
    restoring-internal) label='NAND: restoring internal settings' ;;
    restoring-external) label='NAND: restoring external settings' ;;
    upgrading-old-debian) label='SD: updating existing Debian packages' ;;
    switching-debian-major) label='SD: migrating Debian release' ;;
    refreshing-sd-repositories) label='SD: refreshing package lists' ;;
    installing-signed-platform) label='SD: installing authenticated AtlANTian packages' ;;
    upgrading-debian-packages) label='SD: updating Debian packages' ;;
    verified) label="Update verified: $target" ;;
    *) label=$1 ;;
  esac
  log "$label"
  printf 'phase=%s\ntarget=%s\n' "$1" "$target" >/run/upgrade/status.new
  mv -f /run/upgrade/status.new /run/upgrade/status
  sync
}
find_vol() {
 wanted=$1; found=
 for d in /sys/class/ubi/ubi0_*; do
   [ -r "$d/name" ] || continue
   [ "$(cat "$d/name")" = "$wanted" ] || continue
   [ -z "$found" ] || fail "duplicate UBI $wanted"
   found=${d##*/}
 done
 [ -n "$found" ] || fail "UBI volume $wanted missing"
 echo "$found"
}
check_nand() {
 [ "$(cat /sys/class/mtd/mtd0/name)" = atlantian-boot ] || fail 'no expected boot MTD'
 [ "$(cat /sys/class/mtd/mtd1/name)" = atlantian-ubi ] || fail 'no expected UBI MTD'
 [ "$(cat /sys/class/mtd/mtd0/size)" = 16777216 ] || fail 'unexpected boot size'
 [ "$(cat /sys/class/mtd/mtd1/size)" = 251658240 ] || fail 'unexpected UBI size'
 [ "$(cat /sys/class/mtd/mtd0/erasesize)" = 131072 ] || fail 'unexpected erase size'
 [ "$(cat /sys/class/mtd/mtd0/writesize)" = 2048 ] || fail 'unexpected page size'
 [ "$(cat /sys/class/mtd/mtd0/oobsize)" = 64 ] || fail 'unexpected OOB size'
 [ "$(cat /sys/class/mtd/mtd0/ecc_strength)" = 4 ] || fail 'unexpected ECC strength'
 [ "$(cat /sys/class/mtd/mtd0/ecc_step_size)" = 512 ] || fail 'unexpected ECC step'
 [ "$(cat /sys/class/mtd/mtd0/bad_blocks)" = 0 ] || fail 'bad boot PEBs unsupported'
 [ "$(cat /sys/class/mtd/mtd1/bad_blocks)" = 0 ] || fail 'bad UBI PEBs unsupported'
 [ -c /dev/mtd0 ] && [ -c /dev/mtd1 ] || fail 'no MTD character devices'
 grep -Eq 'Manufacturer ID: 0x2c, Chip ID: 0xda' /run/nand-dmesg || fail 'Micron chip identity mismatch'
 [ "$(jq -r .nand.ubi_offset_bytes NAND-MANIFEST.json)" = 16777216 ] || fail 'incorrect UBI offset'
}
compare_boot() {
 name=$1; offset=$2; image=$3
 size=$(wc -c <"$image")
 nanddump -q --bb=skipbad --omitoob -s "$offset" -l "$size" \
   -f /run/upgrade/boot-readback.bin /dev/mtd0 || fail "readback failed for $name"
 cmp -n "$size" "$image" /run/upgrade/boot-readback.bin || fail "written $name differs"
 rm -f /run/upgrade/boot-readback.bin
 log "$name: verified"
}
flash_slot() {
 name=$1; off=$2; slot=$3; image=$4
 size=$(wc -c <"$image")
 [ "$size" -gt 0 ] && [ "$size" -le "$slot" ] || fail "$name exceeds slot"
 [ $((off % 131072)) -eq 0 ] || fail "unaligned $name"
 blocks=$(((size + 131071) / 131072))
 [ $((off + blocks * 131072)) -le $((off + slot)) ] || fail "$name spans adjacent slot"
 # Already installed files are left untouched. This is particularly important
 # for the BootROM SPL copies when target bytes have not changed.
 if nanddump -q --bb=skipbad --omitoob -s "$off" -l "$size" \
   -f /run/upgrade/slot-before.bin /dev/mtd0 && cmp -s -n "$size" "$image" /run/upgrade/slot-before.bin; then
   rm -f /run/upgrade/slot-before.bin
   log "$name: unchanged"
   return
 fi
 rm -f /run/upgrade/slot-before.bin
 log "programming $name at $off ($blocks eraseblocks)"
 flash_erase /dev/mtd0 "$off" "$blocks" || fail "erase failed for $name"
 nandwrite -p -s "$off" /dev/mtd0 "$image" || fail "write failed for $name"
 compare_boot "$name" "$off" "$image"
}
old_ubi_mount() {
  mkdir -p /run/upgrade/old-lower /run/upgrade/old-internal /run/upgrade/old-root /run/upgrade/old-external
  ubiattach -d 0 -p /dev/mtd1 || fail 'original UBI attach failed'
  mdev -s
  oldroot=$(find_vol rootfs)
  ubiblock --create "/dev/$oldroot" || fail 'original ubiblock failed'
  mdev -s
  oldblock=/dev/ubiblock$(printf '%s' "$oldroot" | sed 's/^ubi//')
  mount -t squashfs -o ro "$oldblock" /run/upgrade/old-lower || fail 'old SquashFS mount failed'
  mount -t ubifs -o rw,noatime,compr=lzo ubi0:overlay /run/upgrade/old-internal || fail 'old UBIFS mount failed'
  oldupper=/run/upgrade/old-internal/upper; oldwork=/run/upgrade/old-internal/work
  if [ "$overlay_mode" = external ]; then
    [ -b /dev/mmcblk0p2 ] || fail 'active adopted upper SD is absent'
    mount -t ext4 -o rw,noatime /dev/mmcblk0p2 /run/upgrade/old-external || fail 'adopted ext4 mount failed'
    ext=/run/upgrade/old-external/.atlantian-extroot
    [ -s "$ext/token" ] && [ -s /run/upgrade/old-internal/.extroot-token ] || fail 'external token absent'
    cmp "$ext/token" /run/upgrade/old-internal/.extroot-token || fail 'external token changed'
    [ -d "$ext/upper" ] && [ -d "$ext/work" ] || fail 'external upper/work absent'
  fi
}
read_old_state() {
  old_ubi_mount
  snap=/run/upgrade/snapshot
  mkdir -p "$snap"
  if [ "$overlay_mode" = external ]; then
    mount -t overlay overlay -o "lowerdir=/run/upgrade/old-lower,upperdir=$oldupper,workdir=$oldwork" /run/upgrade/old-root ||
      fail 'internal merged view mount failed'
    /sbin/atlantian-nand-rebase capture-mounted /run/upgrade/old-lower /run/upgrade/old-root "$snap/internal" ||
      fail 'internal capture failed'
    umount /run/upgrade/old-root || fail 'old internal merged view busy'
    cp /run/upgrade/old-internal/.extroot-token /run/upgrade/extroot-token
    oldupper=$ext/upper; oldwork=$ext/work
  fi
  mount -t overlay overlay -o "lowerdir=/run/upgrade/old-lower,upperdir=$oldupper,workdir=$oldwork" /run/upgrade/old-root ||
    fail 'merged old root mount failed'
  if [ "$overlay_mode" = external ]; then
    /sbin/atlantian-nand-rebase capture-mounted /run/upgrade/old-lower /run/upgrade/old-root "$snap/external" ||
      fail 'external capture failed'
  else
    /sbin/atlantian-nand-rebase capture-mounted /run/upgrade/old-lower /run/upgrade/old-root "$snap/internal" ||
      fail 'internal capture failed'
  fi
  umount /run/upgrade/old-root || fail 'old merged view busy'
  free_kib=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  [ "$free_kib" -ge 160000 ] || fail 'RAM headroom insufficient after state snapshot'
  free_snapshot=$(df -Pk /run | awk 'NR==2 {print $4}')
  [ "$free_snapshot" -ge 32768 ] || fail 'RAM snapshot near capacity'
  mark old-state-captured
  umount /run/upgrade/old-internal || fail 'old UBIFS still mounted'
  umount /run/upgrade/old-lower || fail 'old SquashFS still mounted'
  ubiblock --remove "/dev/$oldroot" || fail 'old ubiblock busy'
  ubidetach -p /dev/mtd1 || fail 'original UBI still attached'
}
nand_apply() {
  for cmd in flash_erase nandwrite nanddump ubiformat ubiattach ubidetach ubimkvol ubiupdatevol ubiblock rsync jq; do need "$cmd"; done
  check_nand
  [ "$(wc -c <spl-redundant.bin)" = 524288 ] || fail 'SPL copy size mismatch'
  check_size() { size=$(wc -c <"$1"); [ "$size" -gt 0 ] && [ "$size" -le "$2" ] || fail "$1 exceeds boot slot"; }
  check_size u-boot.img 1048576
  check_size uImage 9437184
  check_size uInitrd 3145728
  check_size devicetree.dtb 1048576
  [ "$(jq -r .compression.rootfs_squashfs NAND-MANIFEST.json)" = zstd ] || fail 'invalid rootfs compression'
  [ "$(jq -r .volumes.rootfs.type NAND-MANIFEST.json)" = static ] || fail 'invalid rootfs type'
  [ "$(wc -c <rootfs.squashfs)" = "$(jq -r .volumes.rootfs.image_bytes NAND-MANIFEST.json)" ] || fail 'rootfs size mismatch'
  read_old_state
  root_bytes=$(jq -er .volumes.rootfs.bytes NAND-MANIFEST.json)
  image_bytes=$(jq -er .volumes.rootfs.image_bytes NAND-MANIFEST.json)
  min_overlay=$(jq -er .volumes.overlay.minimum_lebs NAND-MANIFEST.json)
  # First destructive operation: no old UBI mount, payload and snapshot in RAM.
  mark formatting-ubi
  ubiformat /dev/mtd1 -y || fail 'UBI format failed'
  ubiattach -d 0 -p /dev/mtd1 || fail 'new UBI attach failed'
  mdev -s
  ubimkvol /dev/ubi0 -N rootfs -t static -s "$root_bytes" || fail 'rootfs create failed'
  mdev -s
  rootvol=$(find_vol rootfs)
  ubiupdatevol "/dev/$rootvol" rootfs.squashfs || fail 'rootfs write failed'
  [ "$(cat "/sys/class/ubi/$rootvol/data_bytes")" = "$image_bytes" ] || fail 'new UBI size mismatch'
  ubimkvol /dev/ubi0 -N overlay -m || fail 'overlay volume create failed'
  overlayvol=$(find_vol overlay)
  [ "$(cat "/sys/class/ubi/$overlayvol/reserved_ebs")" -ge "$min_overlay" ] || fail 'insufficient overlay reserve'
  mkdir -p /run/upgrade/new-lower /run/upgrade/new-internal
  ubiblock --create "/dev/$rootvol" || fail 'new ubiblock create failed'
  mdev -s
  rootblock=/dev/ubiblock$(printf '%s' "$rootvol" | sed 's/^ubi//')
  [ -b "$rootblock" ] || fail 'new ubiblock missing'
  cmp -n "$image_bytes" rootfs.squashfs "$rootblock" || fail 'rootfs readback mismatch'
  mount -t squashfs -o ro "$rootblock" /run/upgrade/new-lower || fail 'new SquashFS mount failed'
  [ "$(cat /run/upgrade/new-lower/usr/lib/atlantian/version)" = "$target" ] || fail 'target version not in rootfs'
  mount -t ubifs -o rw,noatime,compr=lzo ubi0:overlay /run/upgrade/new-internal || fail 'new UBIFS mount failed'
  mkdir -p /run/upgrade/new-internal/upper /run/upgrade/new-internal/work
  if [ "$overlay_mode" = external ]; then cp /run/upgrade/extroot-token /run/upgrade/new-internal/.extroot-token; fi
  mark restoring-internal
  /sbin/atlantian-nand-rebase restore "$snap/internal" /run/upgrade/new-lower /run/upgrade/new-internal/upper /run/upgrade/new-internal/work "$target" ||
    fail 'internal state restore failed'
  if [ "$overlay_mode" = external ]; then
    mark restoring-external
    next="$ext/.upgrade-new-$target"
    previous="$ext/.upgrade-previous-$target"
    [ ! -e "$next" ] && [ ! -e "$previous" ] || fail 'external transaction directories already exist'
    mkdir -p "$next/upper" "$next/work"
    /sbin/atlantian-nand-rebase restore "$snap/external" /run/upgrade/new-lower "$next/upper" "$next/work" "$target" ||
      fail 'external state restore failed'
    sync
    mkdir -p "$previous"
    mv "$ext/upper" "$previous/upper"
    mv "$ext/work" "$previous/work"
    mv "$next/upper" "$ext/upper"
    mv "$next/work" "$ext/work"
    rmdir "$next"
    sync
  fi
  umount /run/upgrade/new-internal || fail 'new UBIFS still mounted'
  umount /run/upgrade/new-lower || fail 'new SquashFS still mounted'
  ubiblock --remove "/dev/$rootvol" || fail 'new ubiblock busy'
  ubidetach -p /dev/mtd1 || fail 'new UBI detach failed'
  for copy in 0 1 2 3; do
    dd if=spl-redundant.bin of="/run/upgrade/spl-$copy.bin" bs=131072 skip="$copy" count=1 2>/dev/null
  done
  flash_slot UBOOT_REDUND 2097152 1048576 u-boot.img
  flash_slot UBOOT_MAIN 1048576 1048576 u-boot.img
  flash_slot KERNEL 3145728 9437184 uImage
  flash_slot INITRAMFS 12582912 3145728 uInitrd
  flash_slot DTB 15728640 1048576 devicetree.dtb
  for copy in 3 2 1 0; do
    off=$((copy * 131072))
    flash_slot "SPL_$copy" "$off" 131072 "/run/upgrade/spl-$copy.bin"
  done
  mark verified
  log 'NAND rootfs, state and required raw slots verified'
}
public_package_hash() {
  name=$1
  expected=$(awk -v n="$name" '$2==n || $2=="*"n {print $1; exit}' /state/signed-public-sums)
  [ -n "$expected" ] || fail "package $name is not in signed manifest"
  actual=$(sha256sum "/debs/$name" | awk '{print $1}')
  [ "$actual" = "$expected" ] || fail "signed Debian package $name differs"
}
sd_chroot() { chroot /stage /usr/bin/env DEBIAN_FRONTEND=noninteractive "$@"; }
sd_apply() {
  [ -b /dev/mmcblk0p2 ] && [ -b /dev/mmcblk0p1 ] || fail 'SD media absent'
  mkdir -p /stage
  mount -t ext4 -o rw,noatime /dev/mmcblk0p2 /stage || fail 'SD ext4 root mount failed'
  [ "$(cat /stage/usr/lib/atlantian/storage-edition)" = sd ] || fail 'SD root identity mismatch'
  [ "$(cut -d. -f1 /stage/usr/lib/atlantian/version)" = "$oldmajor" ] || fail 'SD Debian major mismatch'
  free_kib=$(df -Pk /stage | awk 'NR==2 {print $4}')
  if [ "$oldmajor" != "$newmajor" ]; then min_kib=524288; else min_kib=262144; fi
  [ "$free_kib" -ge "$min_kib" ] || fail 'not enough free SD root space'
  mkdir -p /stage/boot /stage/proc /stage/sys /stage/dev /stage/run
  mount -t vfat /dev/mmcblk0p1 /stage/boot || fail 'SD FAT mount failed'
  [ -s /stage/boot/atlantian-A.itb ] && [ -s /stage/boot/atlantian-B.itb ] || fail 'SD FIT A/B missing'
  mount --bind /proc /stage/proc || fail 'proc bind failed'
  mount --bind /sys /stage/sys || fail 'sys bind failed'
  mount --bind /dev /stage/dev || fail 'dev bind failed'
  mount --bind /run /stage/run || fail 'run bind failed'
  mkdir -p /run/systemd/resolve /run/apt/lists/partial /run/apt/archives/partial /run/atlantian-debs
  cp /run/resolv.conf /run/systemd/resolve/stub-resolv.conf || fail 'DHCP DNS unavailable'
  # /stage/run is a non-recursive bind mount of /run. A nested mount
  # added later under /run is not guaranteed to appear in /stage/run.
  # Bind the signed payload directly beneath the chroot-visible target.
  mount --bind /debs /stage/run/atlantian-debs || fail 'signed .deb bind mount failed'
  set --
  for kind in platform kernel release; do
    name=$(sed -n "s/^$kind=//p" /state/packages.list)
    [ -n "$name" ] && [ -s "/debs/$name" ] || fail "missing signed $kind package"
    public_package_hash "$name"
    # Fail before apt starts modifying SD if the signed .deb is not visible
    # through the chroot at the exact filename apt-get will receive.
    chroot /stage /usr/bin/test -s "/run/atlantian-debs/$name" ||
      fail "signed $kind package missing inside SD chroot: $name"
    set -- "$@" "/run/atlantian-debs/$name"
    [ "$kind" = platform ] && platform=$name
  done
  if [ "$oldmajor" != "$newmajor" ]; then
    mark upgrading-old-debian
    sd_chroot /usr/bin/apt-get update || fail 'old Debian apt update failed'
    sd_chroot /usr/bin/apt-get -y full-upgrade || fail 'old Debian full-upgrade failed'
    backup=/stage/var/lib/atlantian/update/apt-sources-before-$target
    [ ! -e "$backup" ] || fail 'existing migration backup; ambiguous retry'
    mkdir -p "$backup/sources.list.d" /run/upgrade/target-platform
    [ ! -e /stage/etc/apt/sources.list ] || cp -a /stage/etc/apt/sources.list "$backup/sources.list"
    for f in /stage/etc/apt/sources.list.d/*.list /stage/etc/apt/sources.list.d/*.sources; do
      [ -e "$f" ] || continue
      mv "$f" "$backup/sources.list.d/"
    done
    sd_chroot /usr/bin/dpkg-deb -x "/run/atlantian-debs/$platform" /run/upgrade/target-platform || fail 'cannot inspect signed platform'
    template=/run/upgrade/target-platform/usr/lib/atlantian/runtime-sources.list
    [ -s "$template" ] || fail 'target Debian sources absent'
    [ "$(cat /run/upgrade/target-platform/usr/lib/atlantian/debian-major)" = "$newmajor" ] || fail 'signed target Debian major mismatch'
    cp "$template" /stage/etc/apt/sources.list
    printf '%s\n' "$target" >/run/atlantian-major-upgrade-authorized
    mark switching-debian-major
    sd_chroot /usr/bin/apt-get update || fail 'target Debian apt update failed'
    sd_chroot /usr/bin/apt-get -y upgrade --without-new-pkgs || fail 'target Debian minimal upgrade failed'
    sd_chroot /usr/bin/apt-get -y full-upgrade || fail 'target Debian full-upgrade failed'
  fi
  mark refreshing-sd-repositories
  sd_chroot /usr/bin/apt-get update || fail 'SD apt metadata refresh failed'
  mark installing-signed-platform
  sd_chroot /usr/bin/apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install "$@" ||
    fail 'signed AtlANTian packages failed to install'
  mark upgrading-debian-packages
  sd_chroot /usr/bin/apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade ||
    fail 'Debian full-upgrade failed'
  [ -z "$(chroot /stage /usr/bin/dpkg --audit)" ] || fail 'SD dpkg audit failed'
  [ "$(cat /stage/usr/lib/atlantian/version)" = "$target" ] || fail 'SD release mismatch'
  sync
  umount /stage/run/atlantian-debs /stage/run /stage/dev /stage/sys /stage/proc /stage/boot || fail 'SD subordinate unmount failed'
  umount /stage || fail 'updated SD still mounted'
  mark verified
}
case "$edition" in nand) nand_apply ;; sd) sd_apply ;; *) fail 'unexpected edition' ;; esac
sync
