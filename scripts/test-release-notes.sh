#!/usr/bin/env bash
# Render milestone notes from a minimal release fixture; no network or image build.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
git -C "$tmp" config user.name test
git -C "$tmp" config user.email test@example.invalid
printf 'source\n' >"$tmp/source"
git -C "$tmp" add . && git -C "$tmp" commit -qm initial
revision=$(git -C "$tmp" rev-parse --short=12 HEAD)
mkdir -p "$tmp/assets"

render() {
  local version=$1 package=${1/-beta./~beta.}-1 public=${1/-beta./.beta.}-1
  rm -f "$tmp/assets/"* "$tmp/release-notes.md"
  printf 'fixture\n' >"$tmp/assets/atlantian-$version.img.xz"
  printf 'fixture\n' >"$tmp/assets/atlantian-nand-$version.tar.zst"
  for name in atlantian-platform atlantian-kernel atlantian-release; do
    local arch=all; [[ $name != atlantian-kernel ]] || arch=armhf
    printf 'fixture\n' >"$tmp/assets/${name}_${public}_${arch}.deb"
  done
  printf 'fixture\n' >"$tmp/assets/atlantian-update.json"
  printf 'fixture\n' >"$tmp/assets/SHA256SUMS"
  python3 - "$tmp/assets/RELEASE-METADATA.json" "$version" "$package" "$revision" <<'PY'
import json, sys
path, version, package, revision = sys.argv[1:]
fs = dict(partition_bytes=1024, total_bytes=1024, used_bytes=128, available_bytes=896, used_percent=12.5)
metadata = {
    "release": version, "package_version": package, "source_revision": revision,
    "image": f"atlantian-{version}.img", "debian": {
        "major": 13, "codename": "trixie", "snapshot": "20261024T000000Z", "package_count": 215
    }, "kernel": {"version": "6.12.114-atlantian1"}, "u_boot": {"version": "2026.10"},
    "storage": {"image_bytes": 2048, "filesystems": {"boot": fs, "root": fs}},
    "products": {"nand": {"installed": {
        "volumes": {"rootfs": {"image_bytes": 256, "bytes": 512}, "overlay": {"minimum_bytes": 128}},
        "deployed_base_bytes": 1024
    }}}
}
with open(path, "w", encoding="utf-8") as out:
    json.dump(metadata, out)
PY
  (
    cd "$tmp"
    RELEASE_METADATA="$tmp/assets/RELEASE-METADATA.json" bash "$ROOT/scripts/generate-release-notes.sh" "v$version" HEAD
  )
}
render 13.1.0-beta.1
grep -Fq '# AtlANTian GNU/Linux enters beta' "$tmp/release-notes.md"
grep -Fq 'existing alpha installations remain supported' "$tmp/release-notes.md"
grep -Fq '13.1.0~beta.1-1' "$tmp/release-notes.md"
render 13.1.0-beta.2
! grep -Fq '# AtlANTian GNU/Linux enters beta' "$tmp/release-notes.md"
echo 'first-beta milestone notes and subsequent ordinary notes passed'
