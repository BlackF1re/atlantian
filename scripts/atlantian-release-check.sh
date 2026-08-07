#!/bin/sh
# Discover the newest complete AtlANTian release and cache display metadata.
set -eu

REPO=${ATLANTIAN_GITHUB_REPO:-}
API=${ATLANTIAN_RELEASE_API:-https://api.github.com}
STATE_DIR=/var/lib/atlantian/update
STATE_FILE=$STATE_DIR/available.env
NOTES_FILE=$STATE_DIR/available-notes.txt

get() { sed -n "s/^$1=//p" "$STATE_FILE" 2>/dev/null | head -n1; }
current() { cat /etc/atlantian-release 2>/dev/null || true; }
is_current() { [ "$1" = "$2" ] || [ "v$(printf '%s' "$1" | sed 's/^atlantian-//; s/-/./g')" = "$2" ]; }

notice() {
  [ -r "$STATE_FILE" ] || exit 0
  tag=$(get tag); release=$(get release_id)
  [ -n "$tag" ] && ! is_current "$(current)" "$tag" || { rm -f "$STATE_FILE" "$NOTES_FILE"; exit 0; }
  printf '\nUpdate is available: %s (%s)\nRun: atlantian-sysupgrade\n\n' "$release" "$tag"
}

case "${1:---refresh}" in
  --notice) notice; exit 0 ;;
  --refresh) ;;
  *) echo 'usage: atlantian-release-check [--refresh|--notice]' >&2; exit 64 ;;
esac

[ -n "$REPO" ] || { echo 'ATLANTIAN_GITHUB_REPO is unset' >&2; exit 64; }
command -v jq >/dev/null || { echo 'jq is required for release metadata parsing' >&2; exit 69; }
json=$(curl -fsSL --retry 3 "$API/repos/$REPO/releases/latest")
tag=$(printf '%s' "$json" | jq -r '.tag_name // empty')
published=$(printf '%s' "$json" | jq -r '.published_at // empty')
notes=$(printf '%s' "$json" | jq -r '.body // "No release notes were published."')
asset() {
  printf '%s' "$json" | jq -r --arg prefix "$1" \
    '.assets[] | select(.name | startswith($prefix)) | [.browser_download_url, .size] | @tsv' | head -n1
}
platform=$(asset 'atlantian-platform_')
kernel=$(asset 'atlantian-kernel_')
releasepkg=$(asset 'atlantian-release_')
sums=$(asset 'SHA256SUMS')
[ -n "$tag" ] && [ -n "$platform" ] && [ -n "$kernel" ] && [ -n "$releasepkg" ] && [ -n "$sums" ] || {
  echo 'latest release has no complete, checksummed package set' >&2; exit 1;
}
if is_current "$(current)" "$tag"; then
  rm -f "$STATE_FILE" "$NOTES_FILE"
  echo "AtlANTian is current: $tag"
  exit 0
fi

set -- $platform; platform_url=$1; platform_size=$2
set -- $kernel; kernel_url=$1; kernel_size=$2
set -- $releasepkg; release_url=$1; release_size=$2
set -- $sums; sums_url=$1
mkdir -p "$STATE_DIR"
tmp=$(mktemp "$STATE_DIR/.available.XXXXXX")
notes_tmp=$(mktemp "$STATE_DIR/.notes.XXXXXX")
trap 'rm -f "$tmp" "$notes_tmp"' EXIT
printf '%s\n' "$notes" >"$notes_tmp"
printf 'release_id=%s\ntag=%s\npublished_at=%s\nplatform_url=%s\nplatform_size=%s\nkernel_url=%s\nkernel_size=%s\nrelease_url=%s\nrelease_size=%s\nsums_url=%s\n' \
  "${tag#v}" "$tag" "$published" "$platform_url" "$platform_size" "$kernel_url" "$kernel_size" "$release_url" "$release_size" "$sums_url" >"$tmp"
mv "$tmp" "$STATE_FILE"
mv "$notes_tmp" "$NOTES_FILE"
echo "AtlANTian update available: $(current) -> $tag"
