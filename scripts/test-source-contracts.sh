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
. config/release-trust.env
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
[[ $ATLANTIAN_NAND_MANUFACTURER_ID == 0x2c && $ATLANTIAN_NAND_DEVICE_ID == 0xda ]] || fail 'stock NAND identity contract changed'
grep -Fq 'if (maf != 0x2c || dev != 0xda)' scripts/uboot-zynq-spl-reader.inc || fail 'NAND SPL identity contract drifted from configured stock NAND'
grep -Fq 'EXPECTED_MANUFACTURER=@ATLANTIAN_NAND_MANUFACTURER_ID@' scripts/atlantian-nand-install-guard.sh || fail 'NAND installer guard lost manufacturer identity injection'
grep -Fq 'EXPECTED_DEVICE=@ATLANTIAN_NAND_DEVICE_ID@' scripts/atlantian-nand-install-guard.sh || fail 'NAND installer guard lost device identity injection'
grep -Fq 'atlantian-nand-install.real' scripts/install-nand-tools.sh || fail 'destructive NAND installer is no longer behind the identity guard'
for dts in board/zynq-bitmain-antminer-s9.dts board/uboot_bitmain-antminer-s9.dts; do
  grep -Fq 'reg = <0x0 0x40000000>;' "$dts" || fail "1 GiB DDR aperture missing from $dts"
done
grep -Fqx 'CONFIG_HIGHMEM=y' config/kernel.fragment || fail 'HIGHMEM is disabled'
! grep -REq '(^|[[:space:]])mem=(496M|512M|1008M|1024M)([[:space:]]|$)' scripts board || fail 'fixed Linux RAM cap returned'

# Public release checksums are accepted only after exact keyless signer verification.
[[ $ATLANTIAN_RELEASE_SIGNATURE_ASSET == SHA256SUMS.sigstore.json ]] || fail 'release signature asset contract changed'
[[ $ATLANTIAN_RELEASE_SIGNING_IDENTITY == 'https://github.com/BlackF1re/atlantian/.github/workflows/release-sign.yml@refs/heads/main' ]] || fail 'release signer identity changed'
[[ $ATLANTIAN_RELEASE_SIGNING_ISSUER == 'https://token.actions.githubusercontent.com' ]] || fail 'release signer issuer changed'
[[ $ATLANTIAN_COSIGN_ARM_SHA256 =~ ^[0-9a-f]{64}$ && $ATLANTIAN_COSIGN_AMD64_SHA256 =~ ^[0-9a-f]{64}$ ]] || fail 'Cosign verifier pins are malformed'
grep -Fq 'SHA256SUMS.sigstore.json' scripts/atlantian-release-check.sh || fail 'release discovery no longer requires a signature asset'
grep -Fq 'atlantian-verify-release.sh' scripts/install-nand-tools.sh || fail 'release verifier is not installed into runtime images'
grep -Fq 'release-trust.env' scripts/install-nand-tools.sh || fail 'release trust root is not installed into runtime images'
grep -Fq 'release-trust.env' scripts/build-atlantian-debs.sh || fail 'platform package does not carry the release trust root'
python3 - <<'PY_AUTH_ORDER'
from pathlib import Path

def body(path, start, end):
    text = Path(path).read_text(encoding="utf-8")
    return text[text.index(start):text.index(end, text.index(start))]

sd = body("scripts/atlantian-sysupgrade-sd.sh", "download_and_verify() {", "ensure_pending_packages() {")
assert sd.index("atlantian-verify-release") < sd.index("verify_staged_version"), "SD checksum use precedes signature verification"
nand = body("scripts/atlantian-sysupgrade-nand.sh", "stage_release() {", "[ \"$(id -u)\" -eq 0 ]")
assert nand.index("atlantian-verify-release") < nand.index("expected=$(awk"), "NAND checksum use precedes signature verification"
PY_AUTH_ORDER
scripts/test-release-auth.sh

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
[[ -e .github/workflows/release-sign.yml ]] || fail 'release signer workflow is missing'

echo 'release pins, signed update trust, board policy, SD/NAND safety, packaging and repository hygiene contracts passed'
