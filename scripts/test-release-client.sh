#!/usr/bin/env bash
# Exercise release discovery against the current public asset contract.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHECKER="$ROOT/scripts/atlantian-release-check.sh"
fail() { printf 'release client contract: %s\n' "$*" >&2; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"
cat >"$tmp/bin/curl" <<'EOF_CURL'
#!/bin/sh
cat "$ATLANTIAN_TEST_RELEASES_JSON"
EOF_CURL
chmod +x "$tmp/bin/curl"
cat >"$tmp/releases.conf" <<'EOF_CONFIG'
ATLANTIAN_GITHUB_REPO=test-owner/test-repo
ATLANTIAN_RELEASE_API=https://example.invalid
ATLANTIAN_RELEASE_PAGES=1
EOF_CONFIG
asset_json() { jq -cn --arg name "$1" --arg url "https://example.invalid/$1" --argjson size "${2:-123}" '{name:$name,browser_download_url:$url,size:$size}'; }
release_json() {
  local version=$1 prerelease=$2 public=$3 platform kernel release sums marker
  platform=$(asset_json "atlantian-platform_${public}_all.deb")
  kernel=$(asset_json "atlantian-kernel_${public}_armhf.deb")
  release=$(asset_json "atlantian-release_${public}_all.deb")
  sums=$(asset_json SHA256SUMS); marker=$(asset_json atlantian-update.json 81)
  jq -cn --arg tag "v$version" --arg published '2026-08-24T00:00:00Z' --argjson prerelease "$prerelease" \
    --argjson platform "$platform" --argjson kernel "$kernel" --argjson release "$release" --argjson sums "$sums" --argjson marker "$marker" \
    '{tag_name:$tag,draft:false,prerelease:$prerelease,published_at:$published,body:"fixture",assets:[$platform,$kernel,$release,$sums,$marker]}'
}
run_case() {
  local edition=$1 installed=$2 candidate=$3 prerelease=$4 public=$5 expected_deb=$6
  rm -rf "$tmp/state"; mkdir -p "$tmp/state"; printf '%s\n' "$installed" >"$tmp/version"
  release_json "$candidate" "$prerelease" "$public" | jq -s . >"$tmp/releases.json"
  PATH="$tmp/bin:$PATH" ATLANTIAN_TEST_RELEASES_JSON="$tmp/releases.json" ATLANTIAN_RELEASE_CONFIG="$tmp/releases.conf" \
    ATLANTIAN_UPDATE_STATE_DIR="$tmp/state" ATLANTIAN_VERSION_FILE="$tmp/version" ATLANTIAN_STORAGE_EDITION="$edition" sh "$CHECKER" --refresh >/dev/null
  state="$tmp/state/available.env"; [[ -s $state ]] || fail "$edition $installed -> $candidate produced no update state"
  grep -qx "version=$candidate" "$state" || fail 'release version mismatch'
  grep -qx "package_version=$expected_deb" "$state" || fail 'Debian package version mismatch'
  grep -qx "platform_name=atlantian-platform_${public}_all.deb" "$state" || fail 'public platform filename mismatch'
}
run_case sd 13.1.0-alpha.6 13.1.0-alpha.7 true 13.1.0.alpha.7-3 13.1.0~alpha.7-3
run_case sd 13.1.0 13.1.1 false 13.1.1-2 13.1.1-2

# NAND can update only within its Debian major; a next-major release must not be advertised as sysupgrade.
printf '13.1.0\n' >"$tmp/version"
release_json 14.1.0 false 14.1.0-1 | jq -s . >"$tmp/releases.json"
PATH="$tmp/bin:$PATH" ATLANTIAN_TEST_RELEASES_JSON="$tmp/releases.json" ATLANTIAN_RELEASE_CONFIG="$tmp/releases.conf" \
  ATLANTIAN_UPDATE_STATE_DIR="$tmp/state" ATLANTIAN_VERSION_FILE="$tmp/version" ATLANTIAN_STORAGE_EDITION=nand sh "$CHECKER" --refresh >/dev/null
[[ ! -e $tmp/state/available.env ]] || fail 'NAND advertised a cross-major sysupgrade'

echo 'current public filenames and storage-aware release discovery contracts passed'
