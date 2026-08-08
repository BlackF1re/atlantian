#!/usr/bin/env bash
# Upgrade-compatibility gate: install the newly built AtlANTian packages into
# the most recent published factory image under armhf emulation and verify that
# ordinary persistent state survives the transition.
set -euo pipefail

ARTIFACT_DIR=${1:?artifact directory}
PROJECT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$PROJECT/config/release.env"
TARGET_VERSION=${ATLANTIAN_VERSION:?}
TARGET_MAJOR=${DEBIAN_MAJOR:?}
TARGET_CODENAME=${DEBIAN_CODENAME:?}
REPO=${ATLANTIAN_UPGRADE_TEST_REPO:-${GITHUB_REPOSITORY:-BlackF1re/atlantian}}
API=${ATLANTIAN_UPGRADE_TEST_API:-https://api.github.com}
EXPAND_MIB=${ATLANTIAN_UPGRADE_TEST_EXPAND_MIB:-2048}

if [[ ${EUID} -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

fail() { printf 'upgrade compatibility: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"; }
for cmd in curl python3 dpkg dpkg-deb sha256sum losetup mount umount mountpoint parted e2fsck resize2fs chroot cmp awk sed truncate update-binfmts; do
  need "$cmd"
done
[[ $TARGET_MAJOR =~ ^[0-9]+$ ]] || fail 'target Debian major is not numeric'
[[ $EXPAND_MIB =~ ^[0-9]+$ ]] && (( EXPAND_MIB >= 1024 )) || fail 'ATLANTIAN_UPGRADE_TEST_EXPAND_MIB must be at least 1024'

platform=$(find "$ARTIFACT_DIR" -maxdepth 1 -name 'atlantian-platform_*.deb' -type f -print -quit)
kernel=$(find "$ARTIFACT_DIR" -maxdepth 1 -name 'atlantian-kernel_*.deb' -type f -print -quit)
release=$(find "$ARTIFACT_DIR" -maxdepth 1 -name 'atlantian-release_*.deb' -type f -print -quit)
[[ -s $platform && -s $kernel && -s $release ]] || fail 'current version-matched package set is incomplete'
for pkg in "$platform" "$kernel" "$release"; do
  [[ $(dpkg-deb -f "$pkg" Version) == "$TARGET_VERSION" ]] || fail "wrong target package version: $pkg"
done

WORK=$(mktemp -d)
ROOTFS=$WORK/rootfs
LOOP=
cleanup() {
  set +e
  for path in "$ROOTFS/dev/pts" "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/boot" "$ROOTFS"; do
    mountpoint -q "$path" && umount -l "$path"
  done
  [[ -n ${LOOP:-} ]] && losetup -d "$LOOP" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$ROOTFS" "$WORK/download"

api_headers=(-H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28')
if [[ -n ${GH_TOKEN:-${GITHUB_TOKEN:-}} ]]; then
  api_headers+=(-H "Authorization: Bearer ${GH_TOKEN:-${GITHUB_TOKEN}}")
fi
curl -fsSL --retry 3 --connect-timeout 20 "${api_headers[@]}" \
  "$API/repos/$REPO/releases?per_page=100" -o "$WORK/releases.json"

mapfile -t tags < <(python3 - "$WORK/releases.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    releases = json.load(f)
for release in releases:
    if release.get('draft') or release.get('prerelease'):
        continue
    tag = release.get('tag_name') or ''
    if tag.startswith('v'):
        print(tag)
PY
)

PREVIOUS_TAG=
PREVIOUS_VERSION=
for tag in "${tags[@]}"; do
  version=${tag#v}
  if dpkg --compare-versions "$version" lt "$TARGET_VERSION" 2>/dev/null; then
    PREVIOUS_TAG=$tag
    PREVIOUS_VERSION=$version
    break
  fi
done
if [[ -z $PREVIOUS_TAG ]]; then
  echo "No older published AtlANTian release exists; previous-release upgrade gate is not applicable yet."
  exit 0
fi

mapfile -t asset_info < <(python3 - "$WORK/releases.json" "$PREVIOUS_TAG" <<'PY'
import json, sys
path, wanted = sys.argv[1:]
with open(path, encoding='utf-8') as f:
    releases = json.load(f)
for release in releases:
    if release.get('tag_name') != wanted:
        continue
    images = [a for a in release.get('assets', []) if (a.get('name') or '').endswith('.img')]
    sums = [a for a in release.get('assets', []) if a.get('name') == 'SHA256SUMS']
    if len(images) != 1 or len(sums) != 1:
        raise SystemExit('previous release must expose exactly one .img and one SHA256SUMS asset')
    print(images[0]['name'] + '\t' + images[0]['browser_download_url'])
    print(sums[0]['name'] + '\t' + sums[0]['browser_download_url'])
    break
else:
    raise SystemExit('selected previous release disappeared from API response')
PY
)
[[ ${#asset_info[@]} -eq 2 ]] || fail "cannot resolve assets for $PREVIOUS_TAG"
IFS=$'\t' read -r image_name image_url <<<"${asset_info[0]}"
IFS=$'\t' read -r sums_name sums_url <<<"${asset_info[1]}"
[[ $sums_name == SHA256SUMS ]] || fail 'unexpected checksum asset name'

IMAGE=$WORK/download/$image_name
SUMS=$WORK/download/SHA256SUMS
echo "Upgrade gate: $PREVIOUS_TAG -> v$TARGET_VERSION"
curl -fL --retry 3 --connect-timeout 20 -o "$IMAGE" "$image_url"
curl -fL --retry 3 --connect-timeout 20 -o "$SUMS" "$sums_url"
expected=$(awk -v name="$image_name" '$2 == name || $2 == "*" name { print $1; exit }' "$SUMS")
[[ $expected =~ ^[0-9a-f]{64}$ ]] || fail "SHA256SUMS has no digest for $image_name"
actual=$(sha256sum "$IMAGE" | awk '{print $1}')
[[ $actual == "$expected" ]] || fail "previous release image checksum mismatch: expected $expected, got $actual"

# A published factory image has only installation-sized slack. Real boards grow
# p2 on first boot, so expand the disposable copy before exercising APT/dpkg.
truncate -s "+${EXPAND_MIB}M" "$IMAGE"
parted -s "$IMAGE" resizepart 2 100%
LOOP=$(losetup --find --show --partscan "$IMAGE")
udevadm settle 2>/dev/null || true
[[ -b ${LOOP}p1 && -b ${LOOP}p2 ]] || fail "partition devices were not created for $LOOP"
set +e
e2fsck -fy "${LOOP}p2" >/dev/null
e2fsck_rc=$?
set -e
(( e2fsck_rc <= 1 )) || fail "e2fsck failed for previous release rootfs (exit $e2fsck_rc)"
resize2fs "${LOOP}p2" >/dev/null
mount "${LOOP}p2" "$ROOTFS"
mkdir -p "$ROOTFS/boot"
mount "${LOOP}p1" "$ROOTFS/boot"

PREVIOUS_INSTALLED=$(cat "$ROOTFS/usr/lib/atlantian/version" 2>/dev/null || true)
[[ -n $PREVIOUS_INSTALLED ]] || fail 'previous image has no AtlANTian version marker'
[[ $PREVIOUS_INSTALLED == "$PREVIOUS_VERSION" ]] || fail "release/image version mismatch: tag $PREVIOUS_VERSION, image $PREVIOUS_INSTALLED"
PREVIOUS_MAJOR=${PREVIOUS_INSTALLED%%.*}
[[ $PREVIOUS_MAJOR =~ ^[0-9]+$ ]] || fail 'previous release Debian major is invalid'
(( TARGET_MAJOR >= PREVIOUS_MAJOR )) || fail "upgrade gate would be a major downgrade: $PREVIOUS_MAJOR -> $TARGET_MAJOR"
(( TARGET_MAJOR <= PREVIOUS_MAJOR + 1 )) || fail "upgrade gate would skip Debian majors: $PREVIOUS_MAJOR -> $TARGET_MAJOR"

# Model a used installation rather than a pristine factory filesystem.
MACHINE_ID=0123456789abcdef0123456789abcdef
printf '%s\n' "$MACHINE_ID" >"$ROOTFS/etc/machine-id"
mkdir -p "$ROOTFS/etc/ssh" "$ROOTFS/root" "$ROOTFS/home/upgrade-ci" "$ROOTFS/var/lib/upgrade-ci" "$ROOTFS/etc/apt/sources.list.d"
printf '%s\n' 'upgrade-ci-private-host-key' >"$ROOTFS/etc/ssh/ssh_host_ed25519_key"
chmod 0600 "$ROOTFS/etc/ssh/ssh_host_ed25519_key"
printf '%s\n' 'root-persistent-state' >"$ROOTFS/root/upgrade-ci-marker"
printf '%s\n' 'home-persistent-state' >"$ROOTFS/home/upgrade-ci/marker"
printf '%s\n' 'var-persistent-state' >"$ROOTFS/var/lib/upgrade-ci/marker"
printf '%s\n' 'etc-persistent-state' >"$ROOTFS/etc/upgrade-ci.conf"
cat >"$ROOTFS/etc/apt/sources.list.d/upgrade-ci.sources" <<'EOF_CUSTOM_SOURCE'
Types: deb
URIs: https://invalid.example.invalid/debian
Suites: stable
Components: main
Enabled: no
EOF_CUSTOM_SOURCE
CUSTOM_SOURCE_SHA=$(sha256sum "$ROOTFS/etc/apt/sources.list.d/upgrade-ci.sources" | awk '{print $1}')
HOST_KEY_SHA=$(sha256sum "$ROOTFS/etc/ssh/ssh_host_ed25519_key" | awk '{print $1}')

mkdir -p "$ROOTFS/tmp/upgrade-ci" "$ROOTFS/run"
cp "$platform" "$ROOTFS/tmp/upgrade-ci/platform.deb"
cp "$kernel" "$ROOTFS/tmp/upgrade-ci/kernel.deb"
cp "$release" "$ROOTFS/tmp/upgrade-ci/release.deb"
dpkg-deb -e "$platform" "$WORK/platform-control"
cp "$WORK/platform-control/preinst" "$ROOTFS/tmp/upgrade-ci/preinst"
chmod 0755 "$ROOTFS/tmp/upgrade-ci/preinst"

# Make DNS usable inside the disposable chroot even when the image's normal
# resolv.conf points at systemd-resolved's runtime stub.
rm -f "$ROOTFS/etc/resolv.conf"
cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
mount --bind /dev "$ROOTFS/dev"
mkdir -p "$ROOTFS/dev/pts" "$ROOTFS/proc" "$ROOTFS/sys"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sys "$ROOTFS/sys"
update-binfmts --enable qemu-arm >/dev/null 2>&1 || true

if ! chroot "$ROOTFS" /bin/true 2>/dev/null; then
  fail 'armhf binfmt is not active after enabling qemu-arm'
fi
run_chroot() { chroot "$ROOTFS" "$@"; }

# Real major upgrades first bring the installed Debian generation fully current.
# Do the same here before target packages switch the repository codename.
if (( TARGET_MAJOR > PREVIOUS_MAJOR )); then
  if grep -q 'snapshot.debian.org' "$ROOTFS/etc/apt/sources.list" 2>/dev/null && \
     [[ -s $ROOTFS/usr/lib/atlantian/runtime-sources.list ]]; then
    install -m 0644 "$ROOTFS/usr/lib/atlantian/runtime-sources.list" "$ROOTFS/etc/apt/sources.list"
  fi
  run_chroot /usr/bin/apt-get -o Acquire::Retries=3 update --allow-releaseinfo-change
  run_chroot /usr/bin/env DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get \
    -o Acquire::Retries=3 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade -y
  PRE_AUDIT=$(run_chroot /usr/bin/dpkg --audit 2>&1 || true)
  [[ -z $PRE_AUDIT ]] || fail "dpkg audit is not clean before Debian-major transition: $PRE_AUDIT"
fi

# Force the legacy immutable-Snapshot layout so every candidate also validates
# migration from the old factory-pinned APT model to its live codename template.
cat >"$ROOTFS/etc/apt/sources.list" <<EOF_LEGACY_APT
# upgrade-ci synthetic legacy AtlANTian layout
deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/20000101T000000Z $TARGET_CODENAME main non-free-firmware
EOF_LEGACY_APT

expect_guard_failure() {
  local simulated=$1 label=$2 rc
  printf '%s\n' "$simulated" >"$ROOTFS/usr/lib/atlantian/version"
  rm -f "$ROOTFS/run/atlantian-major-upgrade-authorized"
  set +e
  run_chroot /bin/sh /tmp/upgrade-ci/preinst >/dev/null 2>&1
  rc=$?
  set -e
  [[ $rc -eq 78 ]] || fail "$label guard returned $rc instead of 78"
}

# Negative package guards are tested against synthetic installed-version markers
# without requiring a historical image for every future Debian generation.
expect_guard_failure "$((TARGET_MAJOR + 1)).0.0+gtest" 'major downgrade'
if (( TARGET_MAJOR >= 2 )); then
  expect_guard_failure "$((TARGET_MAJOR - 2)).0.0+gtest" 'major skip'
fi
if (( TARGET_MAJOR >= 1 )); then
  expect_guard_failure "$((TARGET_MAJOR - 1)).0.0+gtest" 'unauthorized one-major transition'
  printf '%s\n' "$((TARGET_MAJOR - 1)).0.0+gtest" >"$ROOTFS/usr/lib/atlantian/version"
  printf '%s\n' "$TARGET_VERSION" >"$ROOTFS/run/atlantian-major-upgrade-authorized"
  run_chroot /bin/sh /tmp/upgrade-ci/preinst >/dev/null
fi
printf '%s\n' "$PREVIOUS_INSTALLED" >"$ROOTFS/usr/lib/atlantian/version"
rm -f "$ROOTFS/run/atlantian-major-upgrade-authorized"

if (( TARGET_MAJOR > PREVIOUS_MAJOR )); then
  printf '%s\n' "$TARGET_VERSION" >"$ROOTFS/run/atlantian-major-upgrade-authorized"
fi
run_chroot /usr/bin/dpkg -i \
  /tmp/upgrade-ci/platform.deb /tmp/upgrade-ci/kernel.deb /tmp/upgrade-ci/release.deb
rm -f "$ROOTFS/run/atlantian-major-upgrade-authorized"

[[ $(cat "$ROOTFS/usr/lib/atlantian/version") == "$TARGET_VERSION" ]] || fail 'installed version marker was not upgraded'
[[ $(cat "$ROOTFS/usr/lib/atlantian/debian-major") == "$TARGET_MAJOR" ]] || fail 'installed Debian-major marker is wrong'
[[ $(cat "$ROOTFS/usr/lib/atlantian/debian-codename") == "$TARGET_CODENAME" ]] || fail 'installed Debian codename marker is wrong'
[[ $(cat "$ROOTFS/etc/machine-id") == "$MACHINE_ID" ]] || fail 'machine-id changed during package upgrade'
[[ $(sha256sum "$ROOTFS/etc/ssh/ssh_host_ed25519_key" | awk '{print $1}') == "$HOST_KEY_SHA" ]] || fail 'SSH host key changed during package upgrade'
[[ $(cat "$ROOTFS/root/upgrade-ci-marker") == root-persistent-state ]] || fail '/root state was not preserved'
[[ $(cat "$ROOTFS/home/upgrade-ci/marker") == home-persistent-state ]] || fail '/home state was not preserved'
[[ $(cat "$ROOTFS/var/lib/upgrade-ci/marker") == var-persistent-state ]] || fail '/var state was not preserved'
[[ $(cat "$ROOTFS/etc/upgrade-ci.conf") == etc-persistent-state ]] || fail '/etc state was not preserved'
[[ $(sha256sum "$ROOTFS/etc/apt/sources.list.d/upgrade-ci.sources" | awk '{print $1}') == "$CUSTOM_SOURCE_SHA" ]] || fail 'custom APT source was modified by package migration'
[[ -s $ROOTFS/etc/apt/sources.list.atlantian-snapshot.bak ]] || fail 'legacy Snapshot sources were not backed up'
! grep -q 'snapshot.debian.org' "$ROOTFS/etc/apt/sources.list" || fail 'runtime APT remained pinned to Snapshot'
grep -Fq "deb https://deb.debian.org/debian $TARGET_CODENAME main non-free-firmware" "$ROOTFS/etc/apt/sources.list" || fail 'target live Debian source is missing'
grep -Fq "deb https://security.debian.org/debian-security ${TARGET_CODENAME}-security main non-free-firmware" "$ROOTFS/etc/apt/sources.list" || fail 'target security source is missing'
for name in zImage devicetree.dtb uImage; do
  cmp -s "$ROOTFS/boot/$name" "$ROOTFS/usr/lib/atlantian/boot/$name" || fail "/boot/$name does not match the installed kernel package"
done

# Re-running platform postinst must not overwrite an administrator's live base
# source file. This catches future regressions in conffile/source ownership.
cat >"$ROOTFS/etc/apt/sources.list" <<EOF_CUSTOM_BASE
# upgrade-ci administrator-managed live source
deb https://deb.debian.org/debian $TARGET_CODENAME main
EOF_CUSTOM_BASE
CUSTOM_BASE_SHA=$(sha256sum "$ROOTFS/etc/apt/sources.list" | awk '{print $1}')
run_chroot /bin/sh /var/lib/dpkg/info/atlantian-platform.postinst configure "$TARGET_VERSION" >/dev/null
[[ $(sha256sum "$ROOTFS/etc/apt/sources.list" | awk '{print $1}') == "$CUSTOM_BASE_SHA" ]] || fail 'platform postinst overwrote an administrator-managed live sources.list'
install -m 0644 "$ROOTFS/usr/lib/atlantian/runtime-sources.list" "$ROOTFS/etc/apt/sources.list"

# Match atlantian-sysupgrade: after the AtlANTian package transaction, refresh
# the selected live repositories and finish the Debian userspace full-upgrade.
run_chroot /usr/bin/apt-get -o Acquire::Retries=3 update --allow-releaseinfo-change
run_chroot /usr/bin/env DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get \
  -o Acquire::Retries=3 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade -y
AUDIT=$(run_chroot /usr/bin/dpkg --audit 2>&1 || true)
[[ -z $AUDIT ]] || fail "dpkg audit is not clean after upgrade: $AUDIT"
OS_CODENAME=$(sed -n 's/^VERSION_CODENAME=//p' "$ROOTFS/etc/os-release" | tr -d '"')
[[ $OS_CODENAME == "$TARGET_CODENAME" ]] || fail "Debian userspace codename is $OS_CODENAME, expected $TARGET_CODENAME"

for pkg in atlantian-platform atlantian-kernel atlantian-release; do
  installed=$(run_chroot /usr/bin/dpkg-query -W -f='${Version}' "$pkg")
  [[ $installed == "$TARGET_VERSION" ]] || fail "$pkg installed version is $installed, expected $TARGET_VERSION"
done

echo "upgrade compatibility passed: $PREVIOUS_TAG -> v$TARGET_VERSION"
