#!/bin/sh
set -eu

IMAGE=${1:?image path required}
PAYLOAD=${2:?system payload path required}
SUMS=${3:?checksum file required}
[ -s "$IMAGE" ] && [ -s "$PAYLOAD" ] && [ -s "$SUMS" ]
sha256sum -c "$SUMS"
command -v sfdisk >/dev/null
command -v file >/dev/null
file "$IMAGE" | grep -qi 'DOS/MBR\|boot sector'
PAYLOAD_BYTES=$(wc -c < "$PAYLOAD")
[ "$PAYLOAD_BYTES" -gt 1048576 ]
grep -q "$(basename "$PAYLOAD")" "$SUMS"
echo "build checks passed: image=$(basename "$IMAGE") payload=${PAYLOAD_BYTES}B"
