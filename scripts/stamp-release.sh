#!/usr/bin/env bash
# Stamp source-addressed release metadata into an already-built root filesystem.
set -euo pipefail

PROJECT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$PROJECT/config/release.env"
ROOT=${1:?usage: stamp-release.sh ROOTFS}

[[ -d "$ROOT/etc" ]] || { echo "not a root filesystem: $ROOT" >&2; exit 2; }
[[ $EUID -eq 0 ]] || exec sudo -E "$0" "$ROOT"

install -d -m 0755 "$ROOT/usr/lib/atlantian"
printf '%s\n' "$ATLANTIAN_VERSION" >"$ROOT/usr/lib/atlantian/version"
printf '%s\n' "$ATLANTIAN_SOURCE_REVISION" >"$ROOT/usr/lib/atlantian/source-revision"
printf '%s\n' "$ATLANTIAN_VERSION" >"$ROOT/etc/atlantian-release"

cat >"$ROOT/etc/os-release" <<EOF
PRETTY_NAME="AtlANTian GNU/Linux $ATLANTIAN_VERSION"
NAME="AtlANTian GNU/Linux"
ID=atlantian
VERSION_ID="$ATLANTIAN_VERSION"
VERSION="$ATLANTIAN_VERSION (based on Debian GNU/Linux $DEBIAN_CODENAME)"
HOME_URL="https://github.com/BlackF1re/atlantian"
SUPPORT_URL="https://github.com/BlackF1re/atlantian/issues"
BUG_REPORT_URL="https://github.com/BlackF1re/atlantian/issues"
EOF

cat >"$ROOT/etc/issue.net" <<EOF
Welcome to AtlANTian GNU/Linux!
$ATLANTIAN_VERSION (based on Debian GNU/Linux $DEBIAN_CODENAME)

AtlANTian is based on Debian GNU/Linux. The programs included with Debian are
free software; their distribution terms are described in the corresponding
copyright files under /usr/share/doc.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent permitted by
applicable law.
EOF
