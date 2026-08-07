#!/usr/bin/env bash
set -euo pipefail

IMAGE=${1:?image}
SUMS=${2:?sums}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/config/release.env"
DIR=$(dirname "$IMAGE")

[ -s "$IMAGE" ] && [ -s "$SUMS" ]
(cd "$DIR" && sha256sum -c "$(basename "$SUMS")")

mapfile -t packages < <(find "$DIR" -maxdepth 1 -name '*.deb' -type f | sort)
[ "${#packages[@]}" -eq 3 ]
for file in "${packages[@]}"; do
  dpkg-deb --info "$file" >/dev/null
  [ "$(dpkg-deb -f "$file" Version)" = "$ATLANTIAN_VERSION" ] || {
    echo "wrong package version: $file" >&2
    exit 1
  }
done

platform=$(find "$DIR" -maxdepth 1 -name 'atlantian-platform_*.deb' -type f -print -quit)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
dpkg-deb -x "$platform" "$work/root"
dpkg-deb -e "$platform" "$work/control"
[ "$(cat "$work/root/usr/lib/atlantian/version")" = "$ATLANTIAN_VERSION" ]
[ "$(cat "$work/root/etc/atlantian-release")" = "$ATLANTIAN_VERSION" ]
! grep -qx '/etc/atlantian-release' "$work/control/conffiles"

echo 'release image, package checksums and identity passed'
