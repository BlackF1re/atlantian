#!/bin/sh
set -eu

IMAGE=${1:?image path required}
PAYLOAD=${2:?system payload path required}
SUMS=${3:?checksum file required}
BOOT_PAYLOAD=${PAYLOAD%.system.ext4}.boot.vfat
BUNDLE=${PAYLOAD%.system.ext4}.update.bundle
[ "$BOOT_PAYLOAD" != "$PAYLOAD" ] || { echo "invalid system payload name: $PAYLOAD" >&2; exit 2; }
[ -s "$IMAGE" ] && [ -s "$PAYLOAD" ] && [ -s "$BOOT_PAYLOAD" ] && [ -s "$BUNDLE" ] && [ -s "$SUMS" ]
SUM_DIR=$(cd "$(dirname "$SUMS")" && pwd)
( cd "$SUM_DIR" && sha256sum -c "$(basename "$SUMS")" )
command -v sfdisk >/dev/null
command -v file >/dev/null
file "$IMAGE" | grep -qi 'DOS/MBR\|boot sector'
PAYLOAD_BYTES=$(wc -c < "$PAYLOAD")
[ "$PAYLOAD_BYTES" -gt 1048576 ]
grep -q "$(basename "$PAYLOAD")" "$SUMS"
grep -q "$(basename "$BOOT_PAYLOAD")" "$SUMS"
grep -q "$(basename "$BUNDLE")" "$SUMS"
echo "build checks passed: image=$(basename "$IMAGE") payload=${PAYLOAD_BYTES}B boot=$(basename "$BOOT_PAYLOAD")"
