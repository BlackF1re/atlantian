#!/bin/sh
# Fetch a GitHub release over HTTPS, verify it in the normal system, then
# hand the local file to RAM recovery. Recovery never needs Internet/TLS.
set -eu

REPO=${ATLANTIAN_GITHUB_REPO:-}
API=${ATLANTIAN_RELEASE_API:-https://api.github.com}
APPLY=${ATLANTIAN_AUTO_APPLY:-0}
[ "${1:-}" = --apply ] && APPLY=1
[ -n "$REPO" ] || { echo "set ATLANTIAN_GITHUB_REPO=OWNER/REPOSITORY" >&2; exit 64; }
CURRENT=$(cat /etc/atlantian-release 2>/dev/null || true)
JSON=$(curl -fsSL --retry 3 "$API/repos/$REPO/releases/latest")
TAG=$(printf '%s\n' "$JSON" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
BUNDLE=$(printf '%s\n' "$JSON" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\.update\.bundle\)".*/\1/p' | head -n1)
SUMS=$(printf '%s\n' "$JSON" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*SHA256SUMS\)".*/\1/p' | head -n1)
[ -n "$TAG" ] && [ -n "$BUNDLE" ] && [ -n "$SUMS" ] || { echo 'latest release has no complete update bundle' >&2; exit 1; }
VERSION=${TAG#v}
RELEASE_ID=$(printf '%s' "$VERSION" | sed 's/\./-/g; s/^/atlantian-/')
{ [ "$CURRENT" = "$TAG" ] || [ "$CURRENT" = "$VERSION" ] || [ "$CURRENT" = "$RELEASE_ID" ]; } && { echo "AtlANTian is current: $CURRENT"; exit 0; }
echo "AtlANTian update available: ${CURRENT:-unknown} -> $TAG"
[ "$APPLY" = 1 ] || exit 0
STAGE=/data/system/atlantian/stage
mkdir -p "$STAGE"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
curl -fsSL --retry 3 "$SUMS" | awk -v n="$(basename "$BUNDLE")" '$2==n {print $1}' >"$TMP"
EXPECTED=$(cat "$TMP")
[ "${#EXPECTED}" -eq 64 ] || { echo 'release bundle checksum missing' >&2; exit 1; }
BUNDLE_FILE="$STAGE/$(basename "$BUNDLE")"
echo 'Downloading verified release bundle to persistent staging…'
curl -fL --retry 3 -o "$BUNDLE_FILE" "$BUNDLE"
[ "$(sha256sum "$BUNDLE_FILE" | awk '{print $1}')" = "$EXPECTED" ] || { rm -f "$BUNDLE_FILE"; echo 'release bundle checksum mismatch' >&2; exit 1; }
exec /usr/local/sbin/atlantian-sysupgrade "$BUNDLE_FILE" "$EXPECTED"
