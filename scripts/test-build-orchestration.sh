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

# Kernel compilation must be independent of Debian userspace. Modules are built
# into a private staging root, then joined into both runtime rootfs editions.
grep -Fq 'KERNEL_ROOTFS=${KERNEL_ROOTFS:-$ROOT/out/kernel-rootfs}' scripts/build-incremental.sh || fail 'kernel module staging root is missing'
grep -Fq 'env ROOTFS="$KERNEL_ROOTFS" "$ROOT/scripts/build-kernel.sh"' scripts/build-incremental.sh || fail 'kernel build still targets runtime rootfs directly'
grep -Fq 'join_kernel()' scripts/build-incremental.sh || fail 'kernel/rootfs join stage is missing'
grep -Fq 'join_kernel' scripts/build-incremental.sh || fail 'artifact graph does not join staged kernel modules'
grep -Fq 'rootfs & rootfs_pid=$!' scripts/build-incremental.sh || fail 'local full build does not start rootfs asynchronously'
grep -Fq 'kernel & kernel_pid=$!' scripts/build-incremental.sh || fail 'local full build does not start kernel asynchronously'

# Production CI must expose rootfs and kernel as independent jobs with live logs.
grep -Eq '^  rootfs:$' .github/workflows/build-release.yml || fail 'release workflow has no dedicated rootfs job'
grep -Eq '^  kernel:$' .github/workflows/build-release.yml || fail 'release workflow has no dedicated kernel job'
grep -Eq '^  assemble:$' .github/workflows/build-release.yml || fail 'release workflow has no explicit assembly job'
grep -Fq 'run: sudo -E ./scripts/build-incremental.sh rootfs' .github/workflows/build-release.yml || fail 'rootfs job does not stream the real build command'
grep -Fq 'run: sudo -E ./scripts/build-incremental.sh kernel' .github/workflows/build-release.yml || fail 'kernel job does not stream the real build command'
! grep -Fq 'out/build-logs/rootfs.log' .github/workflows/build-release.yml || fail 'release workflow still buffers rootfs stdout'
! grep -Fq 'out/build-logs/kernel.log' .github/workflows/build-release.yml || fail 'release workflow still buffers kernel stdout'
! grep -Fq 'actions/cache@' .github/workflows/build-release.yml || fail 'release workflow exposes shared cache state to manual release builds'
[[ $(grep -Fc "github.ref == 'refs/heads/main'" .github/workflows/build-release.yml) -ge 12 ]] || fail 'release DAG is not explicitly confined to protected main'
for digest in ROOTFS_SHA256 KERNEL_SHA256 CANDIDATE_SHA256 REBASE_SHA256; do grep -Fq "$digest" .github/workflows/build-release.yml || fail "release handoff is missing digest verification: $digest"; done
! grep -Fq 'tar -I zstd -xf handoff/release-candidate.tar.zst' .github/workflows/build-release.yml || fail 'release candidate extraction can overwrite the checkout workspace'
grep -Fq -- '-C "$candidate_root" -xf handoff/release-candidate.tar.zst' .github/workflows/build-release.yml || fail 'release candidate is not isolated under RUNNER_TEMP'
grep -Fq 'ATLANTIAN_CANDIDATE_DIR=$candidate_root/artifacts/current' .github/workflows/build-release.yml || fail 'isolated candidate root is not exported to validation jobs'

# The package builder must not expand a nounset local while declaring the
# variables it depends on; with set -u this assignment must stay ordered.
! grep -Eq 'local[[:space:]]+package=.*source=.*\$package' scripts/build-atlantian-debs.sh || fail 'maintainer-script path reintroduces nounset local expansion'

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
grep -Fq 'scripts/test-release-upgrade.sh "$ATLANTIAN_CANDIDATE_DIR"' .github/workflows/build-release.yml || fail 'SD cross-release gate is missing'
grep -Fq 'scripts/test-nand-rebase.sh "$ATLANTIAN_NAND_REBASE_ROOT"' .github/workflows/build-release.yml || fail 'NAND rebase gate is missing'
[[ ! -e scripts/test-build.sh ]] || fail 'legacy aggregate test survived'
[[ ! -e scripts/test-repository-portability.sh ]] || fail 'repository migration test survived'

# The unified image retains the exact release-matched NAND payload.
grep -Fq 'usr/lib/atlantian/nand' scripts/embed-nand-bundle.sh || fail 'NAND payload embedding is missing'
grep -Fq 'ConditionPathExists=/var/lib/atlantian/nand-install/pending' systemd/atlantian-nand-auto-resume.service || fail 'NAND auto-resume is not marker-gated'

echo 'build graph, update dispatch, NAND transaction and release integration contracts passed'
