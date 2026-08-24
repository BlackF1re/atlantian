#!/usr/bin/env bash
# Cheap behavioral contracts for the build graph. Keep this focused on boundaries,
# not on the exact spelling of implementation details.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
fail() { printf 'build orchestration contract: %s\n' "$*" >&2; exit 1; }

validate_packages() {
  local file=$1 package count=0
  while IFS= read -r package; do
    [[ $package =~ ^[a-z0-9][a-z0-9+.-]*(:[a-z0-9][a-z0-9-]*)?$ ]] || fail "$file contains invalid token: $package"
    count=$((count + 1))
  done < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$file")
  (( count > 0 )) || fail "$file contains no packages"
}
validate_packages config/packages.base
[[ ! -e config/packages.nand ]] || fail 'NAND package delta profile must not exist'
grep -qx 'busybox-static' < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' config/packages.base) || fail 'build-only BusyBox source package is missing'

scripts/test-release-client.sh
scripts/test-public-release-assets.sh
scripts/test-release-batch.sh

# One debootstrap creates the common userspace. NAND is a storage-policy clone;
# build-only BusyBox is extracted and purged before the clone.
debootstrap_count=$(grep -h '^debootstrap ' scripts/build-rootfs.sh scripts/build-nand-rootfs.sh | wc -l)
[[ $debootstrap_count -eq 1 ]] || fail "rootfs graph must contain exactly one debootstrap, found $debootstrap_count"
! grep -Eq 'apt-get|debootstrap|chroot' scripts/build-nand-rootfs.sh || fail 'NAND rootfs clone performs a second package transaction'
grep -Fq 'extract-nand-busybox.sh' scripts/build-incremental.sh || fail 'build-only BusyBox extraction is not in the rootfs graph'
grep -Fq 'rsync -aHAX --numeric-ids' scripts/build-nand-rootfs.sh || fail 'NAND rootfs is not derived from common rootfs'

# Leaf builders fail on missing prerequisites; they do not recursively invoke an
# upstream stage. The orchestrator owns ordering.
! grep -Fq 'build-rootfs.sh' scripts/build-nand-rootfs.sh || fail 'NAND rootfs builder recursively invokes rootfs build'
grep -Fq 'missing prerequisite' scripts/build-incremental.sh || fail 'orchestrator lacks prerequisite checks'

# SD and NAND U-Boot share exactly one source materialization helper.
for file in scripts/build-uboot.sh scripts/build-uboot-nand.sh; do
  grep -Fq 'prepare-uboot-source.sh' "$file" || fail "$file does not use shared U-Boot source preparation"
  ! grep -Fq 'git -C "$SRC" fetch' "$file" || fail "$file still duplicates U-Boot source fetching"
done

# One public sysupgrade command dispatches by persistent/runtime storage edition.
grep -Fq 'atlantian-sysupgrade-$edition' scripts/atlantian-sysupgrade.sh || fail 'sysupgrade is not a storage dispatcher'
for backend in scripts/atlantian-sysupgrade-sd.sh scripts/atlantian-sysupgrade-nand.sh; do [[ -x $backend ]] || fail "missing executable backend: $backend"; done
! grep -Fq 'install -m 0755 /usr/lib/atlantian/atlantian-sysupgrade-nand' packaging/platform/postinst || fail 'platform postinst still self-replaces sysupgrade'

# NAND destructive flow stays single-layered: no launcher/core wrappers.
for dead in scripts/atlantian-nand-install-launcher.sh scripts/atlantian-nand-upgrade-launcher.sh; do [[ ! -e $dead ]] || fail "legacy launcher survived: $dead"; done
grep -Fq 'pending bundle/release identity mismatch' scripts/atlantian-nand-install.sh || fail 'install lost pending bundle identity verification'
grep -Fq 'prepared payload is' scripts/atlantian-nand-upgrade.sh || fail 'upgrade lost prepared bundle identity verification'

# Integration gates remain independent production stages.
grep -Fq 'scripts/test-release-upgrade.sh artifacts/current' .github/workflows/build-release.yml || fail 'SD cross-release gate is missing'
grep -Fq 'scripts/test-nand-rebase.sh out/rootfs-nand' .github/workflows/build-release.yml || fail 'NAND rebase gate is missing'
[[ ! -e scripts/test-build.sh ]] || fail 'legacy aggregate test survived'
[[ ! -e scripts/test-repository-portability.sh ]] || fail 'repository migration test survived'

# The unified image retains the exact release-matched NAND payload.
grep -Fq 'usr/lib/atlantian/nand' scripts/embed-nand-bundle.sh || fail 'NAND payload embedding is missing'
grep -Fq 'ConditionPathExists=/var/lib/atlantian/nand-install/pending' systemd/atlantian-nand-auto-resume.service || fail 'NAND auto-resume is not marker-gated'

echo 'build graph, update dispatch, NAND transaction and release integration contracts passed'
