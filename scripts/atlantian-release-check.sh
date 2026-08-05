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
SHA=$(printf '%s\n' "$JSON" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*SHA256SUMS\)".*/\1/p' | head -n1)
[ -n "$TAG" ] && [ -n "$IMG" ] || { echo 'latest release has no system payload' >&2; exit 1; }
VERSION=${TAG#v}
RELEASE_ID=$(printf '%s' "$VERSION" | sed 's/\./-/g; s/^/atlantian-/')
if [ "$CURRENT" = "$RELEASE_ID" ] || [ "$CURRENT" = "$VERSION" ] || [ "$CURRENT" = "$TAG" ]; then
  echo "AtlANTian is current: $CURRENT"
  exit 0
fi
echo "AtlANTian update available: ${CURRENT:-unknown} -> $TAG"
[ "$APPLY" = 1 ] || exit 0
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
curl -fsSL --retry 3 "$SHA" | awk -v n="$(basename "$IMG")" '$2==n {print $1}' >"$TMP"
EXPECTED=$(cat "$TMP")
[ "${#EXPECTED}" -eq 64 ] || { echo 'release checksum missing' >&2; exit 1; }
exec /usr/local/sbin/atlantian-sysupgrade "$IMG" "$EXPECTED"
