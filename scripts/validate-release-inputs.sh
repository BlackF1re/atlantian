#!/usr/bin/env bash
# Validate every immutable input used to assemble a published AtlANTian release.
set -euo pipefail

PROJECT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PROJECT"

. config/release.env
. config/debian-snapshot.env

fail() {
  printf 'release-input validation: %s\n' "$*" >&2
  exit 1
}

read_sha256_pin() {
  local file=$1 value
  [[ -s $file ]] || fail "$file is missing or empty"
  value=$(cat "$file")
  [[ $value =~ ^[0-9a-f]{64}$ ]] || \
    fail "$file must contain exactly one lowercase SHA-256 value"
  printf '%s' "$value"
}

verify_release_file() {
  local label=$1 url=$2 pin_file=$3 destination=$4 expected actual
  expected=$(read_sha256_pin "$pin_file")
  curl -fsSL --retry 3 --connect-timeout 20 "$url" -o "$destination" || \
    fail "cannot download $label Release file from $url"
  actual=$(sha256sum "$destination" | awk '{print $1}')
  [[ $actual == "$expected" ]] || \
    fail "$label Release SHA-256 mismatch: expected $expected, got $actual"
  printf 'validated %-16s %s\n' "$label" "$expected"
}

[[ $ATLANTIAN_KERNEL_COMMIT =~ ^[0-9a-f]{40}$ ]] || \
  fail 'ATLANTIAN_KERNEL_COMMIT must be an immutable 40-character commit ID'

boot_line=$(cat boot-candidate/BOOT.bin.gitsha)
if [[ $boot_line =~ ^([0-9a-f]{40})[[:space:]]+BOOT\.bin$ ]]; then
  boot_expected=${BASH_REMATCH[1]}
else
  fail 'boot-candidate/BOOT.bin.gitsha must contain: <git-object-id>  BOOT.bin'
fi
boot_actual=$(git hash-object boot-candidate/BOOT.bin)
[[ $boot_actual == "$boot_expected" ]] || \
  fail "BOOT.bin Git object mismatch: expected $boot_expected, got $boot_actual"
printf 'validated %-16s %s\n' 'BOOT.bin' "$boot_expected"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

verify_release_file \
  "$DEBIAN_CODENAME" \
  "$DEBIAN_SNAPSHOT_MIRROR/dists/$DEBIAN_CODENAME/Release" \
  debian-release.sha256 \
  "$tmpdir/debian-release"
verify_release_file \
  "$DEBIAN_CODENAME-updates" \
  "$DEBIAN_SNAPSHOT_MIRROR/dists/${DEBIAN_CODENAME}-updates/Release" \
  debian-updates-release.sha256 \
  "$tmpdir/debian-updates-release"
verify_release_file \
  "$DEBIAN_CODENAME-security" \
  "$DEBIAN_SECURITY_SNAPSHOT_MIRROR/dists/${DEBIAN_CODENAME}-security/Release" \
  debian-security-release.sha256 \
  "$tmpdir/debian-security-release"

echo 'release inputs validated'
