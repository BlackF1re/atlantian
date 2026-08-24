#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ROOTFS=${ROOTFS:-$ROOT/out/rootfs}
OUT=${OUT:-$ROOT/out/build-tools/busybox-static-armhf}
[[ ${EUID} -eq 0 ]] || exec sudo -E "$0" "$@"
[[ -x $ROOTFS/usr/bin/busybox ]] || { echo 'busybox-static is missing from common factory rootfs' >&2; exit 2; }
if readelf -l "$ROOTFS/usr/bin/busybox" | grep -q 'Requesting program interpreter'; then
  echo 'factory BusyBox is not static' >&2; exit 2
fi
mkdir -p "$(dirname "$OUT")"
install -m 0755 "$ROOTFS/usr/bin/busybox" "$OUT"
chroot "$ROOTFS" dpkg --purge busybox-static >/dev/null
chroot "$ROOTFS" /usr/bin/dpkg-query -W -f='${binary:Package}\t${Version}\n' \
  | LC_ALL=C sort >"$ROOTFS/usr/share/atlantian/debian-package-manifest.tsv"
[[ -x $OUT ]] || { echo 'failed to preserve build-only BusyBox' >&2; exit 2; }
[[ ! -e $ROOTFS/usr/bin/busybox ]] || { echo 'busybox-static leaked into runtime rootfs' >&2; exit 2; }
