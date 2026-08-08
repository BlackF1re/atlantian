#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

for file in scripts/*.sh; do
  case $(head -n1 "$file") in '#!/bin/sh') dash -n "$file" ;; *) bash -n "$file" ;; esac
done

. config/release.env
[[ $DEBIAN_CODENAME =~ ^[a-z0-9][a-z0-9-]*$ ]]
[[ $DEBIAN_MAJOR =~ ^[0-9]+$ ]]
[[ ${DEBIAN_ARCH:-} == armhf ]]
[[ $ATLANTIAN_REVISION =~ ^[0-9]+$ ]]
[[ $ATLANTIAN_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+\+g[0-9A-Za-z]+$ ]]
[[ $ATLANTIAN_RELEASE_ID == atlantian-*+g* ]]
dpkg --compare-versions "${DEBIAN_MAJOR}.${ATLANTIAN_BUILD}.1+ga" gt "${DEBIAN_MAJOR}.${ATLANTIAN_BUILD}+gz"

# Debian lifecycle: architecture-gated, one-major-at-a-time promotion and a
# generic debootstrap script for future codenames.
grep -q 'for alias in stable oldstable oldoldstable' scripts/refresh-debian-base.sh
grep -q 'NEXT_MAJOR=$((CURRENT_MAJOR + 1))' scripts/refresh-debian-base.sh
grep -q 'does not publish $ARCH' scripts/refresh-debian-base.sh
grep -q 'DEBOOTSTRAP_SCRIPT=/usr/share/debootstrap/scripts/sid' scripts/build-rootfs.sh
grep -q 'same-major bridge release' scripts/atlantian-release-check.sh
grep -q 'best_same' scripts/atlantian-release-check.sh
grep -q 'refusing to skip Debian majors' scripts/atlantian-sysupgrade.sh
grep -q 'major-upgrade-sources-backup' scripts/atlantian-sysupgrade.sh

# Runtime APT is live, codename-pinned and separated from immutable build input.
grep -Fq 'deb [check-valid-until=no] $MIRROR $SUITE main non-free-firmware' scripts/build-rootfs.sh
grep -Fq 'deb https://deb.debian.org/debian $SUITE main non-free-firmware' scripts/build-rootfs.sh
grep -Fq 'Managed by AtlANTian' scripts/build-rootfs.sh
grep -Fq 'runtime-sources.list' scripts/build-atlantian-debs.sh
grep -Fq '[ ! -s /etc/apt/sources.list ]' scripts/build-atlantian-debs.sh
grep -q 'sources.list.atlantian-snapshot.bak' scripts/build-atlantian-debs.sh
grep -q 'atlantian-major-upgrade-authorized' scripts/build-atlantian-debs.sh
grep -q 'atlantian-major-upgrade-authorized' scripts/atlantian-sysupgrade.sh
grep -q 'major-upgrade-pending.env' scripts/atlantian-sysupgrade.sh
grep -q 'resume_major_upgrade' scripts/atlantian-sysupgrade.sh
grep -q 'major-upgrade-pending.env' scripts/atlantian-login-info.sh
! grep -qE '^[[:space:]]+etc/apt/sources\.list' scripts/build-atlantian-debs.sh
! grep -q 'snapshot configured by atlantian-platform' scripts/build-atlantian-debs.sh

# Upgrade compatibility is a production publication gate. It must exercise a
# checksummed previous image under armhf emulation rather than merely inspecting
# package metadata.
grep -q 'test-upgrade-from-release.sh' scripts/test-build.sh
grep -q 'GITHUB_ACTIONS' scripts/test-build.sh
grep -q 'losetup --find --show --partscan' scripts/test-upgrade-from-release.sh
grep -q 'previous release image checksum mismatch' scripts/test-upgrade-from-release.sh
grep -q 'atlantian-major-upgrade-authorized' scripts/test-upgrade-from-release.sh
grep -q 'machine-id changed during package upgrade' scripts/test-upgrade-from-release.sh
grep -q 'sources.list.atlantian-snapshot.bak' scripts/test-upgrade-from-release.sh
grep -q 'dpkg --audit' scripts/test-upgrade-from-release.sh
grep -q 'full-upgrade -y' scripts/test-upgrade-from-release.sh

# Update and release integrity.
grep -q 'dpkg --compare-versions' scripts/atlantian-release-check.sh
! grep -q -- '--allow-downgrades' scripts/atlantian-sysupgrade.sh
grep -q 'dpkg-deb -f' scripts/atlantian-sysupgrade.sh
grep -Fq 'sudo -E bash "$ROOT/scripts/stamp-release.sh"' scripts/build-incremental.sh
grep -Fq 'bash "$PROJECT/scripts/stamp-release.sh" "$ROOT"' scripts/build-rootfs.sh
grep -Fq 'exec sudo -E bash "$0" "$ROOT"' scripts/stamp-release.sh
grep -q 'configure-rootfs-access.sh' scripts/build-rootfs.sh
! grep -q 'chown -hR 0:0' scripts/build-rootfs.sh
grep -q 'MACAddressPolicy=persistent' scripts/build-rootfs.sh
grep -q 'atlantian-ssh-hostkeys.service' scripts/configure-rootfs-access.sh
grep -q '^ProtectSystem=strict$' systemd/atlantian-release-check.service
grep -q '^StateDirectory=atlantian$' systemd/atlantian-release-check.service

test ! -e config/zynq-bitmain-antminer-s9.dts
! grep -R -q --exclude=test-source-contracts.sh 'ATLANTIAN_AUTO_APPLY' config scripts systemd README.md docs || { echo 'obsolete ATLANTIAN_AUTO_APPLY contract remains' >&2; exit 1; }
test "$(git hash-object boot-candidate/BOOT.bin)" = "$(awk 'NR==1 {print $1}' boot-candidate/BOOT.bin.gitsha)"
grep -Fq "cron: '0 23 * * *'" .github/workflows/debian-watch.yml
grep -q 'refresh-debian-base.sh' .github/workflows/debian-watch.yml
grep -q 'Preflight a new Debian major root filesystem' .github/workflows/debian-watch.yml
grep -q 'Ensure the current Debian generation has a release' .github/workflows/debian-watch.yml
grep -q '^concurrency:' .github/workflows/build-release.yml
grep -q 'superseded by a newer main commit' .github/workflows/build-release.yml
grep -q 'actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8' .github/workflows/build-release.yml
! grep -q 'chown -R.* out artifacts' .github/workflows/build-release.yml

# Repository hygiene: no developer-specific checkout paths or obsolete local
# board-address state is allowed in source-controlled project files.
! grep -R -nE --exclude=test-source-contracts.sh '/home/[^/[:space:]]+/atlantian' scripts config .github README.md docs .gitignore
! test -e state/board.address.example

echo 'source, lifecycle and release contracts passed'
