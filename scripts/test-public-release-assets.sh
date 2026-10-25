#!/usr/bin/env bash
# Exercise the exact transformation from sealed-build filenames to public release payload.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PREP="$ROOT/scripts/prepare-public-release.sh"
fail() { printf 'public release asset contract: %s\n' "$*" >&2; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
release=13.1.0-beta.1
package_version='13.1.0~beta.1-5'
public_version='13.1.0.beta.1-5'
image=atlantian-13.1.0-beta.1.img
printf 'raw-image-fixture\n' >"$tmp/$image"; xz -c "$tmp/$image" >"$tmp/$image.xz"
printf 'nand-fixture\n' >"$tmp/atlantian-nand-$release.tar.zst"
python3 - "$tmp/RELEASE-METADATA.json" "$release" "$package_version" "$image" <<'PY'
import json, sys
path, release, package_version, image = sys.argv[1:]
with open(path, 'w', encoding='utf-8') as stream:
    json.dump({'release': release, 'package_version': package_version, 'image': image}, stream)
PY
make_deb() {
  local package=$1 arch=$2 root="$tmp/pkg-$1"
  mkdir -p "$root/DEBIAN" "$root/usr/share/$package"
  cat >"$root/DEBIAN/control" <<EOF_CONTROL
Package: $package
Version: $package_version
Architecture: $arch
Maintainer: AtlANTian test <test@example.invalid>
Description: release publication fixture
EOF_CONTROL
  printf 'fixture\n' >"$root/usr/share/$package/payload"
  dpkg-deb --build "$root" "$tmp/${package}_${package_version}_${arch}.deb" >/dev/null
}
make_deb atlantian-platform all; make_deb atlantian-kernel armhf; make_deb atlantian-release all; rm -rf "$tmp"/pkg-*

"$PREP" "$tmp" >/dev/null
"$PREP" "$tmp" >/dev/null
for name in \
  "$image.xz" \
  "atlantian-kernel_${public_version}_armhf.deb" \
  "atlantian-nand-$release.tar.zst" \
  "atlantian-platform_${public_version}_all.deb" \
  "atlantian-release_${public_version}_all.deb" \
  atlantian-update.json RELEASE-METADATA.json SHA256SUMS; do
  [[ -s "$tmp/$name" ]] || fail "missing public payload: $name"
done
! find "$tmp" -maxdepth 1 -type f -name '*~*.deb' -print -quit | grep -q . || fail 'canonical ~ package filename survived public normalization'
for spec in \
  "atlantian-platform_${public_version}_all.deb:atlantian-platform:all" \
  "atlantian-kernel_${public_version}_armhf.deb:atlantian-kernel:armhf" \
  "atlantian-release_${public_version}_all.deb:atlantian-release:all"; do
  IFS=: read -r name package arch <<<"$spec"
  [[ $(dpkg-deb -f "$tmp/$name" Package) == "$package" ]] || fail "$name Package mismatch"
  [[ $(dpkg-deb -f "$tmp/$name" Version) == "$package_version" ]] || fail "$name Version mismatch"
  [[ $(dpkg-deb -f "$tmp/$name" Architecture) == "$arch" ]] || fail "$name Architecture mismatch"
done
(cd "$tmp" && sha256sum -c SHA256SUMS >/dev/null)
[[ $(wc -l <"$tmp/SHA256SUMS") -eq 7 ]] || fail 'public SHA256SUMS must cover exactly seven downloadable payloads'
! grep -Fq '~beta.1' "$tmp/SHA256SUMS" || fail 'public SHA256SUMS contains a canonical-only ~ filename'
jq -e --arg release "$release" '.schema_version == 1 and .kind == "atlantian-system-update" and .release == $release' \
  "$tmp/atlantian-update.json" >/dev/null || fail 'invalid update marker'

# The shipping RAM-only updater must use the public asset names produced above,
# validate their Debian identity and hash against the authenticated manifest,
# and reject content before initiating kexec.
python3 - "$ROOT/scripts/atlantian-ram-upgrade.sh" <<'PY_RAM'
from pathlib import Path
import sys
stage = Path(sys.argv[1]).read_text()
for contract in (
    'atlantian-verify-release',
    'check_public_hash "$archive"',
    'check_public_hash "$name"',
    'dpkg-deb -f "$work/$name" Package',
    'dpkg-deb -f "$work/$name" Version',
    'dpkg-deb -f "$work/$name" Architecture',
):
    assert contract in stage, f'missing signed public asset contract: {contract}'
assert stage.index('atlantian-verify-release') < stage.index('check_public_hash "$archive"') < stage.index('kexec --load')
PY_RAM

echo 'public filename normalization, package metadata, idempotency and checksum contracts passed'
