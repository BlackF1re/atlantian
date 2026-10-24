#!/bin/sh
# Read-only structural check of a bootable AtlANTian recovery SD.
# A writable external upper alone is not sufficient for NAND maintenance.
set -eu
[ "$#" -eq 2 ] || { echo 'usage: atlantian-validate-recovery-sd BOOT_ROOT SD_ROOT' >&2; exit 64; }
boot=$1 root=$2
fail() { echo "unsuitable recovery SD: $*" >&2; exit 65; }
[ -d "$boot" ] && [ -d "$root" ] || fail 'missing mounted SD partitions'
for f in BOOT.bin u-boot.img boot.scr atlantian-A.itb atlantian-B.itb atlantian-boot-abi; do
  [ -s "$boot/$f" ] || fail "SD boot partition is missing $f"
done
# The U-Boot boot script must support the verified raw-NAND programming handoff.
grep -aq 'atln-stage.scr' "$boot/boot.scr" || fail 'SD boot script lacks NAND maintenance handoff'
[ -r "$root/usr/lib/atlantian/storage-edition" ] &&
  [ "$(cat "$root/usr/lib/atlantian/storage-edition")" = sd ] ||
  fail 'SD root is not an AtlANTian SD edition'
[ -s "$root/usr/lib/atlantian/version" ] || fail 'SD recovery release identity is missing'
for f in atlantian-nand-upgrade atlantian-nand-install atlantian-nand-firstboot atlantian-nand-rebase; do
  [ -x "$root/usr/local/sbin/$f" ] || fail "SD recovery root lacks $f"
done
[ -s "$root/etc/profile.d/20-atlantian-nand-firstboot.sh" ] ||
  fail 'SD root cannot resume a prepared NAND update at login'
{ [ -L "$root/etc/systemd/system/multi-user.target.wants/atlantian-nand-auto-resume.service" ] ||
  [ -e "$root/etc/systemd/system/multi-user.target.wants/atlantian-nand-auto-resume.service" ]; } ||
  fail 'SD root does not enable automatic NAND maintenance continuation'
