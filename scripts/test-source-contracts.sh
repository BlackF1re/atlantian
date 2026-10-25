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
grep -Fq 'EXPECTED_MANUFACTURER=@ATLANTIAN_NAND_MANUFACTURER_ID@' scripts/atlantian-nand-install.sh || fail 'destructive NAND installer lost manufacturer identity injection'
grep -Fq 'EXPECTED_DEVICE=@ATLANTIAN_NAND_DEVICE_ID@' scripts/atlantian-nand-install.sh || fail 'destructive NAND installer lost device identity injection'
grep -Fq 'verify_nand_identity' scripts/atlantian-nand-install.sh || fail 'destructive NAND installer no longer rechecks chip identity'
grep -Fq 'atlantian-nand-install.real' scripts/install-nand-tools.sh || fail 'destructive NAND installer is no longer behind the identity guard'
scripts/test-nand-identity.sh
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
grep -Fq 'atlantian-validate-recovery-sd atlantian-nand-firstboot' scripts/install-nand-tools.sh || fail 'recovery SD validator is not installed'
! grep -Fq 'atlantian-storage is-upgrade-card' scripts/atlantian-ram-upgrade.sh || fail 'RAM updates must not require a recovery SD'
grep -Fq '.extroot-token' scripts/atlantian-storage.sh || fail 'external overlay token validation disappeared'
scripts/test-ram-upgrade.sh
scripts/test-recovery-sd-layout.sh
grep -Fq 'release-trust.env' scripts/install-nand-tools.sh || fail 'release trust root is not installed into runtime images'
grep -Fq 'release-trust.env' scripts/build-atlantian-debs.sh || fail 'platform package does not carry the release trust root'
python3 - <<'PY_AUTH_ORDER'
from pathlib import Path
stage = Path("scripts/atlantian-ram-upgrade.sh").read_text()
apply = Path("scripts/atlantian-ram-upgrade-apply.sh").read_text()
assert stage.index('atlantian-verify-release') < stage.index('check_public_hash "$archive"') < stage.index('kexec --load'), "RAM staging must authenticate before accepting content or executing kexec"
assert apply.index('sha256sum -c /state/signed-internal-sums') < apply.index('ubiformat /dev/mtd1'), "RAM writer must validate payload before altering NAND"
assert apply.index('read_old_state\n') < apply.index('ubiformat /dev/mtd1'), "RAM writer must save old state before altering NAND"
PY_AUTH_ORDER
scripts/test-release-auth.sh
# User-facing output should be brief, consistently labelled, and accurate.
storage_help=$(scripts/atlantian-storage.sh --help)
[[ $storage_help == *'adopt'* && $storage_help == *'manual recovery'* ]] ||
  fail 'storage help does not explain adoption and manual recovery'
[[ $storage_help != *'\\n'* ]] || fail 'storage help renders literal backslash-n tokens'
grep -Fq "grep -q '^AtlANTian GNU/Linux '" packaging/platform/postinst ||
  fail 'SD package upgrade does not refresh factory SSH banner'
# The board remains a general-purpose Zynq Linux development system: user
# interfaces are available as drivers without claiming unverified PCB routes.
for config in CONFIG_I2C_CADENCE CONFIG_I2C_CHARDEV CONFIG_SPI_CADENCE CONFIG_SPI_SPIDEV CONFIG_CAN_XILINXCAN CONFIG_GPIO_XILINX CONFIG_FPGA_MGR_ZYNQ_FPGA; do
  grep -q "^$config=y" config/kernel.fragment || fail "universal Linux hardware interface was removed: $config"
done
for file in atlantian-status-leds.bit atlantian-status-leds.hwh atlantian-status-leds.dtso; do
  [[ -s "fpga/status-leds/$file" ]] || fail "FPGA design/reference artifact absent from repository: $file"
  ! grep -Fq "fpga/status-leds/$file" scripts/build-rootfs.sh || fail "development FPGA artifact is copied into runtime rootfs: $file"
done
grep -Fq 'atlantian-status-leds.bin' scripts/build-rootfs.sh || fail 'FPGA runtime bitstream missing'
grep -Fq 'atlantian-status-leds.dtbo' scripts/build-rootfs.sh || fail 'FPGA runtime overlay missing'
grep -Fq 'is-recovery-card' scripts/atlantian-storage.sh || fail 'manual SD recovery interface missing'
! grep -Fq 'is-upgrade-card' scripts/atlantian-storage.sh || fail 'retired SD-based updater identity check remains'
! grep -Fq 'mode=upgrade' scripts/atlantian-nand-install.sh || fail 'fresh NAND installer retains legacy NAND upgrade mode'

python3 - <<'PY_UI'
from pathlib import Path
stamp = Path('scripts/stamp-release.sh').read_text()
start = stamp.index('cat >"$ROOT/etc/issue.net" <<EOF_ISSUE')
body = stamp[start:].split('\n',1)[1].split('\nEOF_ISSUE',1)[0]
assert body.splitlines() == [
    'AtlANTian GNU/Linux $ATLANTIAN_VERSION',
    'Debian $DEBIAN_MAJOR ($DEBIAN_CODENAME)',
], 'SSH issue.net template must contain two concise identity lines'
PY_UI


# SD RAM update retains A/B FIT boot integrity. The finished-package test owns the
# stronger assertion that factory-only BOOT.bin/u-boot.img are absent from the kernel package.
for token in atlantian-A.itb atlantian-B.itb atlantian-slot-B; do grep -Fq "$token" scripts/populate-boot-files.sh || fail "missing SD transaction token: $token"; done
grep -Fq 'hash-1 { algo = "sha256"; };' scripts/populate-boot-files.sh || fail 'FIT SHA-256 verification disappeared'
for token in atlantian-A.itb atlantian-B.itb atlantian-boot-abi; do grep -Fq "$token" packaging/kernel/postinst || fail "kernel postinst lost $token"; done

# NAND backup remains read-only; destructive work stays behind explicit transaction gates.
grep -Fq -- '--noecc --oob --bb=dumpbad' scripts/atlantian-nand-backup.sh || fail 'raw+OOB recovery dump missing'
grep -Fq 'nand-raw-oob.bin.gz' scripts/atlantian-nand-backup.sh || fail 'raw+OOB recovery dump is not stored compressed'
grep -Fq '| pigz -1' scripts/atlantian-nand-backup.sh || fail 'NAND backup is not streamed through pigz'
! grep -Eq 'nandwrite|flash_erase|ubiformat|mtdpart[[:space:]]+add' scripts/atlantian-nand-backup.sh || fail 'backup helper gained NAND writes'
grep -Fq 'BACKUP_DEFAULT=/var/lib/atlantian/recovery/factory-nand-backup' scripts/atlantian-nand-install.sh || fail 'fresh NAND backup is not anchored on the recovery SD root'
grep -Fq -- '--no-backup' scripts/atlantian-nand-install.sh || fail 'explicit fresh-install backup opt-out missing'
grep -Fq 'type INSTALL' scripts/atlantian-nand-install.sh || fail 'fresh NAND destructive confirmation missing'
grep -Fq 'Type UPGRADE' scripts/atlantian-ram-upgrade.sh || fail 'RAM system update confirmation missing'
grep -Fq 'atln-stage.done' scripts/atlantian-nand-install.sh || fail 'U-Boot raw-boot verification marker missing'
grep -Fq 'read_old_state' scripts/atlantian-ram-upgrade-apply.sh || fail 'RAM NAND updater no longer captures old user state'
grep -Fq '/sbin/atlantian-nand-rebase restore' scripts/atlantian-ram-upgrade-apply.sh || fail 'RAM NAND updater no longer restores persistent state'
python3 - <<'PY_NAND_HANDOFF'
from pathlib import Path

install = Path("scripts/atlantian-nand-install.sh").read_text(encoding="utf-8")
start = install.index("handoff() {")
end = install.index("\n}\n\nif [", start)
handoff = install[start:end]
assert "read -r" not in handoff, "SD->NAND handoff must not wait for Enter"
assert "systemctl reboot" not in handoff, "SD->NAND handoff must not use software reboot"
for token in ("remove power", "SD to NAND", "power-on reset"):
    assert token in handoff, f"SD->NAND handoff missing {token!r}"

# System upgrades use a kexec handoff, not a physical boot-source swap.
ram = Path("scripts/atlantian-ram-upgrade.sh").read_text(encoding="utf-8")
assert "systemctl kexec" in ram, "RAM maintainer handoff missing"
assert "Type UPGRADE" in ram, "upgrade confirmation missing"
PY_NAND_HANDOFF

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
