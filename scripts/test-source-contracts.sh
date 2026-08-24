#!/usr/bin/env bash
# Fast repository invariants. Test externally visible safety contracts, not source formatting.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
fail() { printf 'source contract: %s\n' "$*" >&2; exit 1; }

for file in scripts/*.sh .github/scripts/*.sh; do
  [[ -e $file ]] || continue
  shell=bash; [[ $(head -n1 "$file") == '#!/bin/sh' ]] && shell=dash
  "$shell" -n "$file" || fail "syntax error: $file"
  [[ -x $file ]] || fail "executable helper lacks +x: $file"
done

. config/release.env
. config/debian-snapshot.env
. config/u-boot.env
. config/nand-layout.env
[[ $DEBIAN_MAJOR =~ ^[0-9]+$ ]] || fail 'Debian major is not numeric'
[[ $DEBIAN_SNAPSHOT_TIMESTAMP =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || fail 'invalid Debian snapshot timestamp'
[[ $ATLANTIAN_KERNEL_COMMIT =~ ^[0-9a-f]{40}$ ]] || fail 'kernel source is not pinned by full SHA'
[[ $ATLANTIAN_UBOOT_COMMIT =~ ^[0-9a-f]{40}$ ]] || fail 'U-Boot source is not pinned by full SHA'
[[ $ATLANTIAN_RELEASE_ID == "atlantian-$ATLANTIAN_VERSION" ]] || fail 'release identity drifted'
[[ $ATLANTIAN_IMAGE_NAME == "$ATLANTIAN_RELEASE_ID" ]] || fail 'image identity drifted'

[[ $ATLANTIAN_NAND_TOTAL_MIB -eq 256 ]] || fail 'unexpected NAND capacity policy'
[[ $ATLANTIAN_NAND_BOOT_MIB -eq 16 ]] || fail 'unexpected raw NAND boot reservation'
[[ $ATLANTIAN_NAND_UBI_OFFSET_BYTES -eq 16777216 ]] || fail 'unexpected UBI offset'
[[ $ATLANTIAN_NAND_ROOTFS_FORMAT == squashfs && $ATLANTIAN_NAND_OVERLAY_COMPRESSOR == lzo ]] || fail 'NAND storage model changed'
for dts in board/zynq-bitmain-antminer-s9.dts board/uboot_bitmain-antminer-s9.dts; do
  grep -Fq 'reg = <0x0 0x40000000>;' "$dts" || fail "1 GiB DDR aperture missing from $dts"
done
grep -Fqx 'CONFIG_HIGHMEM=y' config/kernel.fragment || fail 'HIGHMEM is disabled'
! grep -REq '(^|[[:space:]])mem=(496M|512M|1008M|1024M)([[:space:]]|$)' scripts board || fail 'fixed Linux RAM cap returned'

# SD online update is strictly A/B FIT. The finished-package test owns the
# stronger assertion that factory-only BOOT.bin/u-boot.img are absent from the kernel package.
for token in atlantian-A.itb atlantian-B.itb atlantian-slot-B; do grep -Fq "$token" scripts/populate-boot-files.sh || fail "missing SD transaction token: $token"; done
grep -Fq 'hash-1 { algo = "sha256"; };' scripts/populate-boot-files.sh || fail 'FIT SHA-256 verification disappeared'
for token in atlantian-A.itb atlantian-B.itb atlantian-boot-abi; do grep -Fq "$token" packaging/kernel/postinst || fail "kernel postinst lost $token"; done

# NAND backup remains read-only; destructive work stays behind explicit transaction gates.
grep -Fq -- '--noecc --oob --bb=dumpbad' scripts/atlantian-nand-backup.sh || fail 'raw+OOB recovery dump missing'
! grep -Eq 'nandwrite|flash_erase|ubiformat|mtdpart[[:space:]]+add' scripts/atlantian-nand-backup.sh || fail 'backup helper gained NAND writes'
grep -Fq 'type INSTALL' scripts/atlantian-nand-install.sh || fail 'fresh NAND destructive confirmation missing'
grep -Fq 'Type UPGRADE' scripts/atlantian-nand-upgrade.sh || fail 'NAND update destructive confirmation missing'
grep -Fq 'atln-stage.done' scripts/atlantian-nand-install.sh || fail 'U-Boot raw-boot verification marker missing'
grep -Fq 'validate_rebase_snapshot' scripts/atlantian-nand-install.sh || fail 'rebase validation before UBI replacement missing'
grep -Fq 'atlantian-nand-rebase restore' scripts/atlantian-nand-install.sh || fail 'persistent state restore missing'

for file in packaging/platform/preinst packaging/platform/postinst packaging/kernel/preinst packaging/kernel/postinst packaging/release/preinst; do
  [[ -x $file ]] || fail "missing executable maintainer script: $file"
done
! grep -Fq 'DEBIAN/postinst" <<' scripts/build-atlantian-debs.sh || fail 'package builder still embeds postinst heredocs'
! grep -Fq 'DEBIAN/preinst" <<' scripts/build-atlantian-debs.sh || fail 'package builder still embeds preinst heredocs'

[[ -x scripts/atlantian-status-leds.sh ]] || fail 'system status LED service was removed'
[[ -e .github/workflows/image-download-metrics.yml && -x scripts/test-release-metrics.sh ]] || fail 'download/update metrics were removed'

for dead in \
  boot-candidate/BOOT.bin.gitsha config/packages.nand \
  scripts/watch-build.sh scripts/build-board-dtb.sh scripts/catch-uboot-uart.py scripts/atlantian-pl-led-effects.sh \
  scripts/test-build.sh scripts/test-repository-portability.sh \
  scripts/atlantian-nand-install-launcher.sh scripts/atlantian-nand-upgrade-launcher.sh \
  .github/workflows/debian-watch.yml; do
  [[ ! -e $dead ]] || fail "legacy path survived: $dead"
done
[[ -e .github/workflows/upstream-watch.yml ]] || fail 'upstream watcher is missing'

echo 'release pins, board policy, SD/NAND safety, packaging and repository hygiene contracts passed'
