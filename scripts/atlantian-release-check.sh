#!/bin/sh
set -eu

# Check the project's GitHub Releases feed.  By default this is advisory only;
# pass --apply (or set ATLANTIAN_AUTO_APPLY=1) to invoke the system-only updater.
REPO=${ATLANTIAN_GITHUB_REPO:-}
API=${ATLANTIAN_RELEASE_API:-https://api.github.com}
APPLY=${ATLANTIAN_AUTO_APPLY:-0}
[ "${1:-}" = --apply ] && APPLY=1
[ -n "$REPO" ] || { echo "set ATLANTIAN_GITHUB_REPO=OWNER/REPOSITORY" >&2; exit 64; }
CURRENT=$(cat /etc/atlantian-release 2>/dev/null || true)
JSON=$(curl -fsSL --retry 3 "$API/repos/$REPO/releases/latest")
TAG=$(printf '%s\n' "$JSON" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
IMG=$(printf '%s\n' "$JSON" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\.system\.ext4\)".*/\1/p' | head -n1)
BOOT=$(printf '%s\n' "$JSON" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\.boot\.vfat\)".*/\1/p' | head -n1)
SHA=$(printf '%s\n' "$JSON" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*SHA256SUMS\)".*/\1/p' | head -n1)
[ -n "$TAG" ] && [ -n "$IMG" ] && [ -n "$BOOT" ] || { echo 'latest release has no complete boot/system payload' >&2; exit 1; }
VERSION=${TAG#v}
RELEASE_ID=$(printf '%s' "$VERSION" | sed 's/\./-/g; s/^/atlantian-/')
if [ "$CURRENT" = "$RELEASE_ID" ] || [ "$CURRENT" = "$VERSION" ] || [ "$CURRENT" = "$TAG" ]; then
  echo "AtlANTian is current: $CURRENT"
  exit 0
fi
echo "AtlANTian update available: ${CURRENT:-unknown} -> $TAG"
[ "$APPLY" = 1 ] || exit 0
TMP=$(mktemp)
STAGE=/data/system/atlantian/stage
trap 'rm -f "$TMP"' EXIT
curl -fsSL --retry 3 "$SHA" | awk -v n="$(basename "$IMG")" '$2==n {print $1}' >"$TMP"
EXPECTED=$(cat "$TMP")
[ "${#EXPECTED}" -eq 64 ] || { echo 'release checksum missing' >&2; exit 1; }
curl -fsSL --retry 3 "$SHA" | awk -v n="$(basename "$BOOT")" '$2==n {print $1}' >"$TMP"
BOOT_EXPECTED=$(cat "$TMP")
[ "${#BOOT_EXPECTED}" -eq 64 ] || { echo 'release boot checksum missing' >&2; exit 1; }
mkdir -p "$STAGE"
SYSTEM_FILE="$STAGE/$(basename "$IMG")"
BOOT_FILE="$STAGE/$(basename "$BOOT")"
echo 'Downloading verified release payloads to persistent staging…'
curl -fL --retry 3 -o "$SYSTEM_FILE" "$IMG"
curl -fL --retry 3 -o "$BOOT_FILE" "$BOOT"
[ "$(sha256sum "$SYSTEM_FILE" | awk '{print $1}')" = "$EXPECTED" ] || { rm -f "$SYSTEM_FILE"; echo 'system payload checksum mismatch' >&2; exit 1; }
[ "$(sha256sum "$BOOT_FILE" | awk '{print $1}')" = "$BOOT_EXPECTED" ] || { rm -f "$BOOT_FILE"; echo 'boot payload checksum mismatch' >&2; exit 1; }
exec /usr/local/sbin/atlantian-sysupgrade "$SYSTEM_FILE" "$EXPECTED" "$BOOT_FILE" "$BOOT_EXPECTED"
