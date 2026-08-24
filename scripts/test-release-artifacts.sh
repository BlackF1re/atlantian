#!/usr/bin/env bash
# Validate the complete sealed release payload. Cross-release SD and NAND rebase
# integration remain separate workflow gates.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR=${1:-$ROOT/artifacts/current}
. "$ROOT/config/release.env"
. "$ROOT/config/debian-snapshot.env"
. "$ROOT/config/atlantian-releases.conf"
. "$ROOT/config/image-layout.env"

IMAGE=$DIR/$ATLANTIAN_IMAGE_NAME.img
COMPRESSED_IMAGE=$IMAGE.xz
NAND_BUNDLE=$DIR/atlantian-nand-$ATLANTIAN_VERSION.tar.zst
SUMS=$DIR/SHA256SUMS
METADATA=$DIR/RELEASE-METADATA.json
fail() { printf 'release artifacts: %s\n' "$*" >&2; exit 1; }

for file in "$IMAGE" "$COMPRESSED_IMAGE" "$NAND_BUNDLE" "$SUMS" "$METADATA" "${IMAGE%.img}.packages.tsv" "${IMAGE%.img}.snapshot.txt"; do
  [[ -s $file ]] || fail "missing release artifact: $file"
done
[[ $(find "$DIR" -maxdepth 1 -name '*.img' -type f | wc -l) -eq 1 ]] || fail 'expected exactly one raw image'
[[ $(find "$DIR" -maxdepth 1 -name '*.img.xz' -type f | wc -l) -eq 1 ]] || fail 'expected exactly one compressed image'
[[ $(find "$DIR" -maxdepth 1 -name '*.tar.zst' -type f | wc -l) -eq 1 ]] || fail 'expected exactly one NAND bundle'
[[ $(find "$DIR" -maxdepth 1 -name '*.deb' -type f | wc -l) -eq 3 ]] || fail 'expected exactly three Debian packages'
(cd "$DIR" && sha256sum -c "$(basename "$SUMS")" >/dev/null) || fail 'release checksum verification failed'
xz -t "$COMPRESSED_IMAGE" || fail 'compressed image XZ integrity failed'
[[ $(xz -dc "$COMPRESSED_IMAGE" | sha256sum | awk '{print $1}') == $(sha256sum "$IMAGE" | awk '{print $1}') ]] || fail 'compressed image does not round-trip to raw image'

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mapfile -t packages < <(find "$DIR" -maxdepth 1 -name '*.deb' -type f | sort)
for file in "${packages[@]}"; do
  dpkg-deb --info "$file" >/dev/null || fail "invalid Debian package: $file"
  [[ $(dpkg-deb -f "$file" Version) == "$ATLANTIAN_DEB_VERSION" ]] || fail "wrong package version: $file"
  control="$work/control-$(basename "$file")"; mkdir -p "$control"; dpkg-deb -e "$file" "$control"
  grep -Fq "target_version='$ATLANTIAN_VERSION'" "$control/preinst" || fail "major guard version missing from $file"
  grep -Fq "target_major='$DEBIAN_MAJOR'" "$control/preinst" || fail "major guard Debian generation missing from $file"
done

kernel_deb=$(find "$DIR" -maxdepth 1 -name 'atlantian-kernel_*.deb' -type f -print -quit)
platform_deb=$(find "$DIR" -maxdepth 1 -name 'atlantian-platform_*.deb' -type f -print -quit)
release_deb=$(find "$DIR" -maxdepth 1 -name 'atlantian-release_*.deb' -type f -print -quit)
[[ -s $kernel_deb && -s $platform_deb && -s $release_deb ]] || fail 'package set is incomplete'
[[ $(dpkg-deb -f "$platform_deb" Homepage) == "https://github.com/$ATLANTIAN_GITHUB_REPO" ]] || fail 'platform Homepage does not match release repository'

dpkg-deb -c "$kernel_deb" >"$work/kernel.list"
! grep -qE ' ./boot/' "$work/kernel.list" || fail 'kernel package owns live /boot paths'
for path in atlantian.itb atlantian-boot-abi boot.scr; do grep -q "usr/lib/atlantian/boot/$path" "$work/kernel.list" || fail "kernel package is missing $path"; done
for path in BOOT.bin u-boot.img; do ! grep -q "usr/lib/atlantian/boot/$path" "$work/kernel.list" || fail "kernel package carries factory-only $path"; done
dpkg-deb -e "$kernel_deb" "$work/kernel-control"
grep -Fq '/usr/lib/atlantian/boot' "$work/kernel-control/postinst" || fail 'kernel postinst does not implement SD FIT transaction'

dpkg-deb -c "$platform_deb" >"$work/platform.list"
for path in \
  usr/local/sbin/atlantian-sysupgrade \
  usr/local/sbin/atlantian-nand-install \
  usr/local/sbin/atlantian-nand-upgrade \
  usr/local/sbin/atlantian-storage \
  usr/local/sbin/atlantian-nand-rebase \
  usr/lib/atlantian/atlantian-sysupgrade-sd \
  usr/lib/atlantian/atlantian-sysupgrade-nand \
  usr/lib/atlantian/version \
  usr/lib/atlantian/package-version \
  usr/lib/atlantian/debian-snapshot \
  usr/lib/atlantian/release-repo \
  usr/lib/atlantian/os-release \
  usr/lib/systemd/system/atlantian-nand-auto-resume.service \
  usr/lib/systemd/system/atlantian-nand-reconcile.service \
  etc/profile.d/10-atlantian-login-info.sh \
  etc/apt/apt.conf.d/10atlantian-volatile \
  usr/lib/systemd/system/run-apt.mount \
  usr/lib/tmpfiles.d/atlantian-apt.conf; do
  grep -q "$path" "$work/platform.list" || fail "platform package is missing $path"
done
! grep -qE ' ./usr/lib/atlantian/storage-edition$' "$work/platform.list" || fail 'platform package must not overwrite storage edition identity'
! grep -qE 'etc/systemd/system/atlantian-.*\.(service|timer)' "$work/platform.list" || fail 'vendor systemd units leaked into /etc'

dpkg-deb -x "$platform_deb" "$work/platform-root"
cmp -s "$ROOT/config/apt-volatile.conf" "$work/platform-root/etc/apt/apt.conf.d/10atlantian-volatile" || fail 'packaged APT runtime policy differs from source'
cmp -s "$ROOT/systemd/run-apt.mount" "$work/platform-root/usr/lib/systemd/system/run-apt.mount" || fail 'packaged APT tmpfs mount differs from source'
cmp -s "$ROOT/systemd/atlantian-apt-tmpfiles.conf" "$work/platform-root/usr/lib/tmpfiles.d/atlantian-apt.conf" || fail 'packaged APT tmpfiles policy differs from source'
[[ $(cat "$work/platform-root/usr/lib/atlantian/version") == "$ATLANTIAN_VERSION" ]] || fail 'packaged semantic version mismatch'
[[ $(cat "$work/platform-root/usr/lib/atlantian/package-version") == "$ATLANTIAN_DEB_VERSION" ]] || fail 'packaged Debian version mismatch'
[[ $(cat "$work/platform-root/usr/lib/atlantian/debian-snapshot") == "$DEBIAN_SNAPSHOT_TIMESTAMP" ]] || fail 'packaged snapshot mismatch'
[[ $(cat "$work/platform-root/usr/lib/atlantian/release-repo") == "$ATLANTIAN_GITHUB_REPO" ]] || fail 'packaged repository identity mismatch'
grep -qx 'ID=debian' "$work/platform-root/usr/lib/atlantian/os-release" || fail 'packaged OS ID is not Debian-compatible'
grep -qx 'VARIANT_ID=atlantian' "$work/platform-root/usr/lib/atlantian/os-release" || fail 'packaged AtlANTian variant identity is missing'

export ATLANTIAN_VERSION ATLANTIAN_RELEASE_ID ATLANTIAN_DEB_VERSION DEBIAN_SNAPSHOT_TIMESTAMP
python3 - "$IMAGE" "$METADATA" "${IMAGE%.img}.packages.tsv" "$ATLANTIAN_BOOT_MIB" <<'PY'
import json, os, subprocess, sys
image, metadata_path, package_manifest, expected_boot_mib = sys.argv[1:]
expected_boot_mib = int(expected_boot_mib)
with open(metadata_path, encoding='utf-8') as f:
    m = json.load(f)
with open(package_manifest, encoding='utf-8') as f:
    package_count = sum(1 for line in f if line.strip())
ptable = json.loads(subprocess.check_output(['sfdisk', '--json', image], text=True))['partitiontable']
parts = ptable['partitions']
assert len(parts) == 2
sector = int(ptable.get('sectorsize', 512))
boot_bytes = int(parts[0]['size']) * sector
root_bytes = int(parts[1]['size']) * sector
image_bytes = os.path.getsize(image)
storage = m['storage']; mib = 1024 * 1024
assert m['schema_version'] == 1
assert m['release'] == os.environ['ATLANTIAN_VERSION']
assert m['release_id'] == os.environ['ATLANTIAN_RELEASE_ID']
assert m['package_version'] == os.environ['ATLANTIAN_DEB_VERSION']
assert m['debian']['snapshot'] == os.environ['DEBIAN_SNAPSHOT_TIMESTAMP']
assert m['debian']['package_count'] == package_count > 0
assert m['platform']['board'] == 'Bitmain Antminer S9'
assert set(m['products']) == {'sd', 'nand'}
assert storage['image_bytes'] == image_bytes
assert storage['boot_bytes'] == boot_bytes
assert storage['root_bytes'] == root_bytes
assert storage['boot_plus_root_bytes'] == boot_bytes + root_bytes
assert storage['layout_overhead_bytes'] == image_bytes - boot_bytes - root_bytes
assert storage['boot_mib'] == expected_boot_mib == boot_bytes // mib
for name in ('boot', 'root'):
    fs = storage['filesystems'][name]
    assert fs['filesystem'] in {'vfat', 'ext4'}
    assert fs['partition_bytes'] > 0 and 0 <= fs['used_bytes'] <= fs['total_bytes'] <= fs['partition_bytes']
nand = m['products']['nand']['installed']
assert nand['schema_version'] == 1
assert nand['compression']['rootfs_squashfs'] == 'zstd'
assert nand['compression']['overlay_ubifs'] == 'lzo'
assert nand['volumes']['rootfs']['type'] == 'static'
assert nand['volumes']['rootfs']['filesystem'] == 'squashfs'
assert nand['volumes']['rootfs']['image_bytes'] <= nand['volumes']['rootfs']['bytes']
assert nand['volumes']['overlay']['type'] == 'dynamic'
assert nand['volumes']['overlay']['filesystem'] == 'ubifs'
assert nand['volumes']['overlay']['minimum_bytes'] > 0
PY

echo 'release inventory, package guards, SD image/storage metadata, NAND metadata and public identity passed'
