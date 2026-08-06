#!/bin/sh
# Discover the latest GitHub release over HTTPS and persist a small notice on
# /data.  Downloading and recovery are deliberately separate: the interactive
# updater owns confirmation and visible progress.
set -eu

REPO=${ATLANTIAN_GITHUB_REPO:-}
API=${ATLANTIAN_RELEASE_API:-https://api.github.com}
STATE_DIR=/data/system/atlantian/update
STATE_FILE=$STATE_DIR/available.env

usage() {
    echo 'usage: atlantian-release-check [--refresh|--notice]' >&2
    exit 64
}

state_get() {
    key=$1
    sed -n "s/^${key}=//p" "$STATE_FILE" | head -n1
}

current_release() {
    cat /etc/atlantian-release 2>/dev/null || true
}

is_current() {
    current=$1
    tag=$2
    version=${tag#v}
    release_id=$(printf '%s' "$version" | sed 's/\./-/g; s/^/atlantian-/')
    [ "$current" = "$tag" ] || [ "$current" = "$version" ] || [ "$current" = "$release_id" ]
}

notice() {
    [ -r "$STATE_FILE" ] || exit 0
    release_id=$(state_get release_id)
    tag=$(state_get tag)
    [ -n "$release_id" ] && [ -n "$tag" ] || { rm -f "$STATE_FILE"; exit 0; }
    if is_current "$(current_release)" "$tag"; then
        rm -f "$STATE_FILE"
        exit 0
    fi
    printf '\nUpdate is available!\nRelease: %s (%s)\nTo install it, use:\n  atlantian-sysupgrade --latest %s\n\n' \
        "$release_id" "$tag" "$release_id"
}

[ $# -le 1 ] || usage
case "${1:---refresh}" in
    --notice) notice; exit 0 ;;
    --refresh) ;;
    *) usage ;;
esac

[ -n "$REPO" ] || { echo 'set ATLANTIAN_GITHUB_REPO=OWNER/REPOSITORY' >&2; exit 64; }
CURRENT=$(current_release)
JSON=$(curl -fsSL --retry 3 "$API/repos/$REPO/releases/latest")
TAG=$(printf '%s\n' "$JSON" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
BUNDLE=$(printf '%s\n' "$JSON" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\.update\.bundle\)".*/\1/p' | head -n1)
SUMS=$(printf '%s\n' "$JSON" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*SHA256SUMS\)".*/\1/p' | head -n1)
[ -n "$TAG" ] && [ -n "$BUNDLE" ] && [ -n "$SUMS" ] || { echo 'latest release has no complete update bundle' >&2; exit 1; }
VERSION=${TAG#v}
RELEASE_ID=$(printf '%s' "$VERSION" | sed 's/\./-/g; s/^/atlantian-/')
if is_current "$CURRENT" "$TAG"; then
    rm -f "$STATE_FILE"
    echo "AtlANTian is current: $CURRENT"
    exit 0
fi

EXPECTED=$(curl -fsSL --retry 3 "$SUMS" | awk -v n="$(basename "$BUNDLE")" '$2==n {print $1}')
[ "${#EXPECTED}" -eq 64 ] || { echo 'release bundle checksum missing' >&2; exit 1; }
mkdir -p "$STATE_DIR"
TMP=$(mktemp "$STATE_DIR/.available.XXXXXX")
trap 'rm -f "$TMP"' EXIT
{
    printf 'release_id=%s\n' "$RELEASE_ID"
    printf 'tag=%s\n' "$TAG"
    printf 'bundle_url=%s\n' "$BUNDLE"
    printf 'sha256=%s\n' "$EXPECTED"
} >"$TMP"
mv "$TMP" "$STATE_FILE"
echo "AtlANTian update available: ${CURRENT:-unknown} -> $TAG"
