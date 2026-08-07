#!/bin/sh
# Discover the newest complete AtlANTian release and cache display metadata.
set -eu

RELEASE_CONFIG=${ATLANTIAN_RELEASE_CONFIG:-/etc/atlantian/releases.conf}
[ -r "$RELEASE_CONFIG" ] && . "$RELEASE_CONFIG"
REPO=${ATLANTIAN_GITHUB_REPO:-}
API=${ATLANTIAN_RELEASE_API:-https://api.github.com}
STATE_DIR=/var/lib/atlantian/update
STATE_FILE=$STATE_DIR/available.env
NOTES_FILE=$STATE_DIR/available-notes.txt

get() { sed -n "s/^$1=//p" "$STATE_FILE" 2>/dev/null | head -n1; }
current() {
  if [ -s /usr/lib/atlantian/version ]; then
    cat /usr/lib/atlantian/version
    return
  fi
  value=$(cat /etc/atlantian-release 2>/dev/null || true)
  case "$value" in
    atlantian-*) printf '%s\n' "${value#atlantian-}" | tr '-' '.' ;;
    *) printf '%s\n' "$value" ;;
  esac
}
newer() { dpkg --compare-versions "$1" gt "$2"; }
clear_state() { rm -f "$STATE_FILE" "$NOTES_FILE"; }

notice() {
  [ -r "$STATE_FILE" ] || exit 0
  version=$(get version)
  tag=$(get tag)
  installed=$(current)
  [ -n "$version" ] && [ -n "$installed" ] && newer "$version" "$installed" || {
    clear_state
    exit 0
  }
  printf '\nUpdate is available: %s\nRun: atlantian-sysupgrade\n\n' "$tag"
}

case "${1:---refresh}" in
  --notice) notice; exit 0 ;;
  --refresh) ;;
  *) echo 'usage: atlantian-release-check [--refresh|--notice]' >&2; exit 64 ;;
esac

[ -n "$REPO" ] || { echo "ATLANTIAN_GITHUB_REPO is unset; set it in $RELEASE_CONFIG" >&2; exit 64; }
command -v jq >/dev/null || { echo 'jq is required for release metadata parsing' >&2; exit 69; }
command -v dpkg >/dev/null || { echo 'dpkg is required for release version comparison' >&2; exit 69; }

json=$(curl -fsSL --retry 3 "$API/repos/$REPO/releases/latest")
tag=$(printf '%s' "$json" | jq -r '.tag_name // empty')
published=$(printf '%s' "$json" | jq -r '.published_at // empty')
notes=$(printf '%s' "$json" | jq -r '.body // "No release notes were published."')
case "$tag" in v*) version=${tag#v} ;; *) echo "invalid AtlANTian release tag: $tag" >&2; exit 1 ;; esac
dpkg --compare-versions "$version" ge 0 2>/dev/null || { echo "invalid Debian version: $version" >&2; exit 1; }

asset() {
  printf '%s' "$json" | jq -r --arg name "$1" \
    '.assets[] | select(.name == $name) | [.name, .browser_download_url, .size] | @tsv' | head -n1
}
platform=$(asset "atlantian-platform_${version}_all.deb")
kernel=$(asset "atlantian-kernel_${version}_armhf.deb")
releasepkg=$(asset "atlantian-release_${version}_all.deb")
sums=$(asset 'SHA256SUMS')
[ -n "$platform" ] && [ -n "$kernel" ] && [ -n "$releasepkg" ] && [ -n "$sums" ] || {
  echo 'latest release has no complete, version-matched package set' >&2
  exit 1
}

installed=$(current)
if [ -n "$installed" ] && ! newer "$version" "$installed"; then
  clear_state
  if [ "$version" = "$installed" ]; then
    echo "AtlANTian is current: $tag"
  else
    echo "Ignoring older AtlANTian release $tag; installed version is $installed"
  fi
  exit 0
fi

tab=$(printf '\t')
IFS="$tab" read -r platform_name platform_url platform_size <<EOF
$platform
EOF
IFS="$tab" read -r kernel_name kernel_url kernel_size <<EOF
$kernel
EOF
IFS="$tab" read -r release_name release_url release_size <<EOF
$releasepkg
EOF
IFS="$tab" read -r sums_name sums_url sums_size <<EOF
$sums
EOF

mkdir -p "$STATE_DIR"
tmp=$(mktemp "$STATE_DIR/.available.XXXXXX")
notes_tmp=$(mktemp "$STATE_DIR/.notes.XXXXXX")
trap 'rm -f "$tmp" "$notes_tmp"' EXIT
printf '%s\n' "$notes" >"$notes_tmp"
printf 'version=%s\nrelease_id=%s\ntag=%s\npublished_at=%s\nplatform_name=%s\nplatform_url=%s\nplatform_size=%s\nkernel_name=%s\nkernel_url=%s\nkernel_size=%s\nrelease_name=%s\nrelease_url=%s\nrelease_size=%s\nsums_name=%s\nsums_url=%s\n' \
  "$version" "$version" "$tag" "$published" \
  "$platform_name" "$platform_url" "$platform_size" \
  "$kernel_name" "$kernel_url" "$kernel_size" \
  "$release_name" "$release_url" "$release_size" \
  "$sums_name" "$sums_url" >"$tmp"
mv "$tmp" "$STATE_FILE"
mv "$notes_tmp" "$NOTES_FILE"
echo "AtlANTian update available: ${installed:-unknown} -> $tag"
