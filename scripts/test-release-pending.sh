#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/board"
cp "$ROOT/scripts/release-pending.sh" "$tmp/scripts/"
git -C "$tmp" init -q
git -C "$tmp" config user.name test
git -C "$tmp" config user.email test@example.invalid
printf 'original\n' > "$tmp/board/item"
git -C "$tmp" add . && git -C "$tmp" commit -qm initial
check() { [[ "$(bash "$tmp/scripts/release-pending.sh")" == "$1" ]] || { echo "release eligibility mismatch: expected $1" >&2; exit 1; }; }
check true
git -C "$tmp" tag v13.1.0-alpha.1
check false
printf 'documentation\n' > "$tmp/README.md"
git -C "$tmp" add . && git -C "$tmp" commit -qm docs
check false
printf 'updated\n' > "$tmp/board/item"
git -C "$tmp" add . && git -C "$tmp" commit -qm update
check true
git -C "$tmp" tag v13.1.0-alpha.2
check false
printf 'changed\n' > "$tmp/debian-release.sha256"
git -C "$tmp" add . && git -C "$tmp" commit -qm upstream
check true
echo 'weekly release eligibility contracts passed'
