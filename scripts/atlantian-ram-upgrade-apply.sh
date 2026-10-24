#!/bin/sh
# Autonomous offline SD / NAND updater, executed only from kexec RAM initramfs.
set -eu
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
fail() { echo "RAM upgrader: $*" >&2; exit 1; }
log() { echo "RAM upgrader: $*"; }
need() { command -v "$1" >/dev/null 2>&1 || fail "missing $1"; }
[ -f /state/edition ] && [ -d /stage ] || fail 'not inside RAM upgrader'
edition=$(cat /state/edition)
target=$(cat /state/target)
relative=$(cat /state/stage-relative)
case "$relative" in var/cache/atlantian/ram-upgrade/*) ;; *) fail 'invalid staging path' ;; esac
stage=/stage/$relative
payload=$stage/payload
[ -s "$stage/IN-PROGRESS" ] || fail 'no authorized update transaction'
[ -s "$payload/NAND-MANIFEST.json" ] || fail 'no NAND payload'
[ -s /state/signed-internal-sums ] || fail 'authenticated checksum set missing'
cd "$payload"
# The signed internal SHA256SUMS was copied into the RAM kernel before kexec,
# and cannot be replaced by altered SD storage after the handoff.
sha256sum -c /state/signed-internal-sums || fail 'authenticated payload was modified'
[ "$(jq -r .release NAND-MANIFEST.json)" = "$target" ] || fail 'target release mismatch'
mark() {
 printf 'phase=%s\nedition=%s\ntarget=%s\n' "$1" "$edition" "$target" >"$stage/STATUS.new"
 mv -f "$stage/STATUS.new" "$stage/STATUS"
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
   -f /run/boot-readback.bin /dev/mtd0 || fail "readback failed for $name"
 cmp -n "$size" "$image" /run/boot-readback.bin || fail "written $name differs"
 rm -f /run/boot-readback.bin
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
   -f /run/slot-before.bin /dev/mtd0 && cmp -s -n "$size" "$image" /run/slot-before.bin; then
   rm -f /run/slot-before.bin
   log "$name: unchanged"
   return
 fi
 rm -f /run/slot-before.bin
 log "programming $name at $off ($blocks eraseblocks)"
 flash_erase /dev/mtd0 "$off" "$blocks" || fail "erase failed for $name"
 nandwrite -p -s "$off" /dev/mtd0 "$image" || fail "write failed for $name"
 compare_boot "$name" "$off" "$image"
}
nand_apply() {
 for b in flash_erase nandwrite nanddump ubiformat ubiattach ubidetach \
   ubimkvol ubiupdatevol ubiblock rsync jq; do need "$b"; done
 check_nand
 snap="$stage/snapshot"
 [ -s "$snap/internal/METADATA" ] && [ -s "$snap/external/METADATA" ] || fail 'missing rebase snapshot'
 [ -d "$snap/internal/delta" ] && [ -d "$snap/external/delta" ] || fail 'invalid snapshot delta'
 [ -s "$stage/extroot-token" ] || fail 'missing extroot token'
 cmp "$stage/extroot-token" /stage/.atlantian-extroot/token || fail 'extroot changed'
 [ -d /stage/.atlantian-extroot/upper ] && [ -d /stage/.atlantian-extroot/work ] || fail 'extroot directories missing'
 root_bytes=$(jq -er .volumes.rootfs.bytes NAND-MANIFEST.json)
 image_bytes=$(jq -er .volumes.rootfs.image_bytes NAND-MANIFEST.json)
 min_overlay=$(jq -er .volumes.overlay.minimum_lebs NAND-MANIFEST.json)
 [ "$(wc -c <rootfs.squashfs)" = "$image_bytes" ] || fail 'rootfs squashfs size mismatch'
 [ "$(wc -c <spl-redundant.bin)" = 524288 ] || fail 'SPL redundancy mismatch'
 size_limit() {
   size=$(wc -c <"$1")
   [ "$size" -gt 0 ] && [ "$size" -le "$2" ] || fail "$1 exceeds raw slot"
 }
 size_limit u-boot.img 1048576
 size_limit uImage 9437184
 size_limit uInitrd 3145728
 size_limit devicetree.dtb 1048576
 # Preflight must have completed before the first destructive command.
 mark formatting-ubi
 ubiformat /dev/mtd1 -y || fail 'UBI format failed'
 ubiattach -p /dev/mtd1 || fail 'UBI attach failed'
 ubimkvol /dev/ubi0 -N rootfs -t static -s "$root_bytes" || fail 'rootfs create failed'
 vol=$(find_vol rootfs)
 ubiupdatevol "/dev/$vol" rootfs.squashfs || fail 'rootfs write failed'
 [ "$(cat "/sys/class/ubi/$vol/data_bytes")" = "$image_bytes" ] || fail 'rootfs volume size mismatch'
 ubimkvol /dev/ubi0 -N overlay -m || fail 'overlay create failed'
 ov=$(find_vol overlay)
 reserved=$(cat "/sys/class/ubi/$ov/reserved_ebs")
 [ "$reserved" -ge "$min_overlay" ] || fail 'insufficient overlay reserve'
 mkdir -p /run/new-lower /run/new-internal
 ubiblock --create "/dev/$vol" || fail 'ubiblock creation failed'
 mdev -s
 block=/dev/ubiblock${vol#ubi}
 [ -b "$block" ] || fail 'new ubiblock missing'
 cmp -n "$image_bytes" rootfs.squashfs "$block" || fail 'UBI rootfs content verification failed'
 mount -t squashfs -o ro "$block" /run/new-lower || fail 'new SquashFS cannot mount'
 [ "$(cat /run/new-lower/usr/lib/atlantian/version)" = "$target" ] || fail 'new lower is not target release'
 mount -t ubifs -o rw,noatime,compr=lzo ubi0:overlay /run/new-internal || fail 'new UBIFS cannot mount'
 mkdir -p /run/new-internal/upper /run/new-internal/work
 cp "$stage/extroot-token" /run/new-internal/.extroot-token
 mark restoring-internal
 /sbin/atlantian-nand-rebase restore "$snap/internal" /run/new-lower \
   /run/new-internal/upper /run/new-internal/work "$target" || fail 'internal restore failed'
 mark restoring-external
 [ ! -e "$stage/previous-upper" ] && [ ! -e "$stage/previous-work" ] || fail 'previous extroot backup already exists'
 mv /stage/.atlantian-extroot/upper "$stage/previous-upper"
 mv /stage/.atlantian-extroot/work "$stage/previous-work"
 mkdir -p /stage/.atlantian-extroot/upper /stage/.atlantian-extroot/work
 /sbin/atlantian-nand-rebase restore "$snap/external" /run/new-lower \
   /stage/.atlantian-extroot/upper /stage/.atlantian-extroot/work "$target" || fail 'external restore failed'
 sync
 umount /run/new-internal || fail 'cannot unmount new UBIFS'
 umount /run/new-lower || fail 'cannot unmount new SquashFS'
 ubiblock --remove "/dev/$vol" || fail 'ubiblock cleanup failed'
 ubidetach -p /dev/mtd1 || fail 'UBI detach failed'
 mark flashing-boot
 # Keep original SPL copies intact until last. A power cut is not recoverable
 # in every phase, but alternating redundant slots reduces the exposure.
 for copy in 0 1 2 3; do
   dd if=spl-redundant.bin of="/run/spl-$copy.bin" bs=131072 skip="$copy" count=1 2>/dev/null
 done
 flash_slot UBOOT_REDUND 2097152 1048576 u-boot.img
 flash_slot UBOOT_MAIN 1048576 1048576 u-boot.img
 flash_slot KERNEL 3145728 9437184 uImage
 flash_slot INITRAMFS 12582912 3145728 uInitrd
 flash_slot DTB 15728640 1048576 devicetree.dtb
 for copy in 3 2 1 0; do
   offset=$((copy * 131072))
   flash_slot "SPL_$copy" "$offset" 131072 "/run/spl-$copy.bin"
 done
 mark verified
 log 'NAND rootfs, user state, boot slots verified'
}
sd_apply() {
 # The SD root must be unmounted as / before package hooks write to it.
 [ "$(cat /stage/usr/lib/atlantian/storage-edition)" = sd ] || fail 'not an SD rootfs'
 [ -b /dev/mmcblk0p1 ] || fail 'SD boot partition absent'
 mkdir -p /stage/boot /stage/proc /stage/sys /stage/dev /stage/run
 mount /dev/mmcblk0p1 /stage/boot || fail 'cannot mount FAT boot'
 [ -s /stage/boot/atlantian-A.itb ] && [ -s /stage/boot/atlantian-B.itb ] || fail 'FIT slots missing'
 mount --bind /proc /stage/proc || fail 'bind proc failed'
 mount --bind /sys /stage/sys || fail 'bind sys failed'
 mount --bind /dev /stage/dev || fail 'bind dev failed'
 mount --bind /run /stage/run || fail 'bind run failed'
 mkdir -p /stage/run/systemd/resolve /stage/run/apt/lists/partial /stage/run/apt/archives/partial
 cp /run/resolv.conf /stage/run/systemd/resolve/stub-resolv.conf || fail 'no DNS supplied by DHCP'
 mark installing-sd-packages
 set --
 for kind in platform kernel release; do
   name=$(sed -n "s/^${kind}=//p" "$stage/packages.list")
   [ -n "$name" ] && [ -s "$stage/$name" ] || fail "missing signed $kind deb"
   set -- "$@" "/$relative/$name"
 done
 # Existing package maintainer hooks handle the A/B FIT verification and
 # switch only the inactive image. apt processes dependencies on the SD root.
 chroot /stage /usr/bin/apt-get -y -o Dpkg::Options::=--force-confdef \
   -o Dpkg::Options::=--force-confold install "$@" || fail 'SD package installation failed'
 mark upgrading-debian
 chroot /stage /usr/bin/apt-get update || fail 'SD apt update failed'
 chroot /stage /usr/bin/apt-get -y -o Dpkg::Options::=--force-confdef \
   -o Dpkg::Options::=--force-confold full-upgrade || fail 'SD Debian upgrade failed'
 [ -z "$(chroot /stage /usr/bin/dpkg --audit)" ] || fail 'dpkg audit nonempty'
 [ "$(cat /stage/usr/lib/atlantian/version)" = "$target" ] || fail 'SD version marker mismatch'
 sync
 umount /stage/run /stage/dev /stage/sys /stage/proc /stage/boot || fail 'SD cleanup failed'
 mark verified
}
case "$edition" in nand) nand_apply ;; sd) sd_apply ;; *) fail 'unexpected edition' ;; esac
rm -f "$stage/IN-PROGRESS"
sync
