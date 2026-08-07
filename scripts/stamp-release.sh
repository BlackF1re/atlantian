#!/usr/bin/env bash
# Stamp source-addressed release metadata into an already-built root filesystem.
set -euo pipefail

PROJECT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$PROJECT/config/release.env"
ROOT=${1:?usage: stamp-release.sh ROOTFS}

[[ -d "$ROOT/etc" ]] || { echo "not a root filesystem: $ROOT" >&2; exit 2; }
[[ $EUID -eq 0 ]] || exec sudo -E bash "$0" "$ROOT"

install -d -m 0755 "$ROOT/usr/lib/atlantian"
printf '%s\n' "$ATLANTIAN_VERSION" >"$ROOT/usr/lib/atlantian/version"
printf '%s\n' "$ATLANTIAN_SOURCE_REVISION" >"$ROOT/usr/lib/atlantian/source-revision"
printf '%s\n' "$ATLANTIAN_VERSION" >"$ROOT/etc/atlantian-release"

# base-files owns /etc/os-release and /etc/issue.net on installed systems, so
# factory branding is deliberately release-neutral. The authoritative dynamic
# AtlANTian version lives in /usr/lib/atlantian/version.
cat >"$ROOT/etc/os-release" <<EOF
PRETTY_NAME="AtlANTian GNU/Linux (Debian GNU/Linux $DEBIAN_CODENAME)"
NAME="AtlANTian GNU/Linux"
ID=atlantian
VERSION_ID="$DEBIAN_MAJOR"
VERSION="$DEBIAN_MAJOR (based on Debian GNU/Linux $DEBIAN_CODENAME)"
HOME_URL="https://github.com/BlackF1re/atlantian"
SUPPORT_URL="https://github.com/BlackF1re/atlantian/issues"
BUG_REPORT_URL="https://github.com/BlackF1re/atlantian/issues"
EOF

cat >"$ROOT/etc/issue.net" <<EOF
Welcome to AtlANTian GNU/Linux!
Based on Debian GNU/Linux $DEBIAN_CODENAME.

The programs included with Debian are free software; their distribution terms
are described in the corresponding copyright files under /usr/share/doc.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent permitted by
applicable law.
EOF
