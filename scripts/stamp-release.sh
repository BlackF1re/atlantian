#!/usr/bin/env bash
set -euo pipefail

PROJECT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$PROJECT/config/release.env"
ROOT=${1:?usage: stamp-release.sh ROOTFS}
[[ -d "$ROOT/etc" ]] || { echo "not a root filesystem: $ROOT" >&2; exit 2; }
[[ $EUID -eq 0 ]] || exec sudo -E bash "$0" "$ROOT"

install -d -m 0755 "$ROOT/usr/lib/atlantian"
printf '%s\n' "$ATLANTIAN_VERSION" >"$ROOT/usr/lib/atlantian/version"
printf '%s\n' "$ATLANTIAN_SOURCE_REVISION" >"$ROOT/usr/lib/atlantian/source-revision"
printf '%s\n' "$DEBIAN_CODENAME" >"$ROOT/usr/lib/atlantian/debian-codename"
printf '%s\n' "$DEBIAN_MAJOR" >"$ROOT/usr/lib/atlantian/debian-major"
printf '%s\n' "$ATLANTIAN_VERSION" >"$ROOT/etc/atlantian-release"

cat >"$ROOT/etc/os-release" <<EOF_OS
PRETTY_NAME="AtlANTian GNU/Linux (Debian GNU/Linux $DEBIAN_CODENAME)"
NAME="AtlANTian GNU/Linux"
ID=atlantian
ID_LIKE=debian
VERSION_ID="$DEBIAN_MAJOR"
VERSION="$DEBIAN_MAJOR (based on Debian GNU/Linux $DEBIAN_CODENAME)"
VERSION_CODENAME="$DEBIAN_CODENAME"
BUILD_ID="$ATLANTIAN_VERSION"
HOME_URL="https://github.com/BlackF1re/atlantian"
DOCUMENTATION_URL="https://github.com/BlackF1re/atlantian#readme"
SUPPORT_URL="https://github.com/BlackF1re/atlantian/issues"
BUG_REPORT_URL="https://github.com/BlackF1re/atlantian/issues"
EOF_OS
cat >"$ROOT/etc/issue.net" <<EOF_ISSUE
Welcome to AtlANTian GNU/Linux!
Based on Debian GNU/Linux $DEBIAN_CODENAME.

The programs included with Debian are free software; their distribution terms
are described in the corresponding copyright files under /usr/share/doc.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent permitted by
applicable law.
EOF_ISSUE
