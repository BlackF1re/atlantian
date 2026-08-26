#!/bin/sh
# Fail closed before the destructive NAND installer if the probed chip identity
# is not the exact device that the fixed-geometry NAND SPL accepts.
set -eu

EXPECTED_MANUFACTURER=@ATLANTIAN_NAND_MANUFACTURER_ID@
EXPECTED_DEVICE=@ATLANTIAN_NAND_DEVICE_ID@
REAL=${ATLANTIAN_NAND_INSTALL_REAL:-/usr/local/sbin/atlantian-nand-install.real}
DMESG_FILE=${ATLANTIAN_NAND_DMESG_FILE:-}

fatal() { echo "atlantian-nand-install: $*" >&2; exit 1; }

case "${1-}" in --help|-h) exec "$REAL" "$@" ;; esac
[ -x "$REAL" ] || fatal "missing guarded installer payload: $REAL"

manufacturer=$(printf '%02x' "$((EXPECTED_MANUFACTURER))")
device=$(printf '%02x' "$((EXPECTED_DEVICE))")
if [ -n "$DMESG_FILE" ]; then
  [ -r "$DMESG_FILE" ] || fatal "unreadable NAND probe log: $DMESG_FILE"
  probe_log=$(cat "$DMESG_FILE")
else
  command -v dmesg >/dev/null 2>&1 || fatal 'dmesg is required to verify NAND identity'
  probe_log=$(dmesg 2>/dev/null) || fatal 'cannot read kernel NAND probe log'
fi

printf '%s\n' "$probe_log" | grep -Eqi \
  "Manufacturer ID:[[:space:]]*0x${manufacturer},[[:space:]]*Chip ID:[[:space:]]*0x${device}" || {
    fatal "unsupported or unverified NAND identity; expected ${manufacturer}:${device} before any destructive operation"
  }

exec "$REAL" "$@"
