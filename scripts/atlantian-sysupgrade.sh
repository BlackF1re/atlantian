#!/bin/sh
# Stable user-facing updater. Storage-specific behavior lives in edition backends.
set -eu

edition=${ATLANTIAN_STORAGE_EDITION:-}
[ -n "$edition" ] || edition=$(cat /run/atlantian/storage-edition 2>/dev/null || true)
[ -n "$edition" ] || edition=$(cat /usr/lib/atlantian/storage-edition 2>/dev/null || true)
[ -n "$edition" ] || edition=sd

case "$edition" in
  sd|nand) ;;
  *) echo "atlantian-sysupgrade: unknown storage edition: $edition" >&2; exit 65 ;;
esac
backend="/usr/lib/atlantian/atlantian-sysupgrade-$edition"
[ -x "$backend" ] || { echo "atlantian-sysupgrade: missing $edition backend: $backend" >&2; exit 69; }
exec "$backend" "$@"
