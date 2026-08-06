#!/bin/sh
# Find the newest published package set.  Normal updates are APT/dpkg
# transactions: no partition is rewritten and normal Debian state is retained.
set -eu
REPO=${ATLANTIAN_GITHUB_REPO:-}; API=${ATLANTIAN_RELEASE_API:-https://api.github.com}
STATE_DIR=/var/lib/atlantian/update; STATE_FILE=$STATE_DIR/available.env
get(){ sed -n "s/^$1=//p" "$STATE_FILE" 2>/dev/null | head -n1; }
current(){ cat /etc/atlantian-release 2>/dev/null || true; }
is_current(){ [ "$1" = "$2" ] || [ "v$(printf '%s' "$1" | sed 's/^atlantian-//; s/-/./g')" = "$2" ]; }
notice(){
 [ -r "$STATE_FILE" ] || exit 0; tag=$(get tag); release=$(get release_id)
 [ -n "$tag" ] && ! is_current "$(current)" "$tag" || { rm -f "$STATE_FILE"; exit 0; }
 printf '\nUpdate is available!\nRelease: %s (%s)\nTo install it, use:\n  atlantian-sysupgrade --latest %s\n\n' "$release" "$tag" "$release"
}
case "${1:---refresh}" in --notice) notice; exit 0;; --refresh) ;; *) echo 'usage: atlantian-release-check [--refresh|--notice]' >&2; exit 64;; esac
[ -n "$REPO" ] || { echo 'ATLANTIAN_GITHUB_REPO is unset' >&2; exit 64; }
json=$(curl -fsSL --retry 3 "$API/repos/$REPO/releases/latest")
tag=$(printf '%s\n' "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
urls=$(printf '%s\n' "$json" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\.deb\)".*/\1/p')
sums=$(printf '%s\n' "$json" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\/SHA256SUMS\)".*/\1/p' | head -n1)
platform=$(printf '%s\n' "$urls" | grep '/atlantian-platform_' | head -n1 || true)
kernel=$(printf '%s\n' "$urls" | grep '/atlantian-kernel_' | head -n1 || true)
releasepkg=$(printf '%s\n' "$urls" | grep '/atlantian-release_' | head -n1 || true)
[ -n "$tag" ] && [ -n "$platform" ] && [ -n "$kernel" ] && [ -n "$releasepkg" ] && [ -n "$sums" ] || { echo 'latest release has no complete, checksummed package set' >&2; exit 1; }
if is_current "$(current)" "$tag"; then rm -f "$STATE_FILE"; echo "AtlANTian is current: $tag"; exit 0; fi
mkdir -p "$STATE_DIR"; tmp=$(mktemp "$STATE_DIR/.available.XXXXXX"); trap 'rm -f "$tmp"' EXIT
printf 'release_id=%s\ntag=%s\nplatform_url=%s\nkernel_url=%s\nrelease_url=%s\nsums_url=%s\n' "${tag#v}" "$tag" "$platform" "$kernel" "$releasepkg" "$sums" >"$tmp"
mv "$tmp" "$STATE_FILE"; echo "AtlANTian update available: $(current) -> $tag"
