#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

for file in scripts/*.sh; do
  case $(head -n1 "$file") in
    '#!/bin/sh') dash -n "$file" ;;
    *) bash -n "$file" ;;
  esac
done

. config/release.env
[[ $ATLANTIAN_REVISION =~ ^[0-9]+$ ]]
[[ $ATLANTIAN_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+\+g[0-9A-Za-z]+$ ]]
[[ $ATLANTIAN_RELEASE_ID == atlantian-*+g* ]]
dpkg --compare-versions "${DEBIAN_MAJOR}.${ATLANTIAN_BUILD}.1+ga" gt "${DEBIAN_MAJOR}.${ATLANTIAN_BUILD}+gz"

grep -q 'dpkg --compare-versions' scripts/atlantian-release-check.sh
! grep -q -- '--allow-downgrades' scripts/atlantian-sysupgrade.sh
grep -q 'package version mismatch' scripts/atlantian-sysupgrade.sh
grep -Fq 'sudo -E bash "$ROOT/scripts/stamp-release.sh"' scripts/build-incremental.sh
grep -Fq 'bash "$PROJECT/scripts/stamp-release.sh" "$ROOT"' scripts/build-rootfs.sh
grep -Fq 'exec sudo -E bash "$0" "$ROOT"' scripts/stamp-release.sh
grep -q 'configure-rootfs-access.sh' scripts/build-rootfs.sh
! grep -q 'chown -hR 0:0' scripts/build-rootfs.sh
grep -q 'MACAddressPolicy=persistent' scripts/build-rootfs.sh
grep -q 'atlantian-ssh-hostkeys.service' scripts/configure-rootfs-access.sh

test ! -e config/zynq-bitmain-antminer-s9.dts
! grep -R -q --exclude=test-source-contracts.sh 'ATLANTIAN_AUTO_APPLY' config scripts systemd README.md docs || {
  echo 'obsolete ATLANTIAN_AUTO_APPLY contract remains' >&2
  exit 1
}

test "$(git hash-object boot-candidate/BOOT.bin)" = "$(awk 'NR==1 {print $1}' boot-candidate/BOOT.bin.gitsha)"
grep -Fq "cron: '0 23 * * *'" .github/workflows/debian-watch.yml
grep -q 'security_suite=' .github/workflows/debian-watch.yml
grep -q '^concurrency:' .github/workflows/build-release.yml
grep -q 'superseded by a newer main commit' .github/workflows/build-release.yml
grep -q 'actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8' .github/workflows/build-release.yml
! grep -q 'chown -R.* out artifacts' .github/workflows/build-release.yml

echo 'source and release contracts passed'
