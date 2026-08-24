#!/usr/bin/env bash
# Derive the NAND edition from the completed common runtime rootfs.
set -euo pipefail
PROJECT=$(cd "$(dirname "$0")/.." && pwd)
ROOT=${ROOT:-$PROJECT/out/rootfs-nand}
BASE_ROOT=${ATLANTIAN_BASE_ROOTFS:-$PROJECT/out/rootfs}
[[ ${EUID} -eq 0 ]] || exec sudo -E "$0" "$@"
[[ -d $BASE_ROOT/etc && -x $BASE_ROOT/bin/sh ]] || { echo "common rootfs is missing: $BASE_ROOT" >&2; exit 2; }
[[ $(readlink -m "$BASE_ROOT") != $(readlink -m "$ROOT") ]] || { echo 'NAND rootfs destination must differ from common rootfs' >&2; exit 2; }
[[ ! -e $BASE_ROOT/usr/bin/busybox ]] || { echo 'build-only busybox-static was not removed before NAND clone' >&2; exit 2; }

rm -rf "$ROOT"; mkdir -p "$ROOT"
rsync -aHAX --numeric-ids "$BASE_ROOT/" "$ROOT/"
install -d -m 0755 "$ROOT/usr/lib/atlantian"
printf 'nand\n' >"$ROOT/usr/lib/atlantian/storage-edition"

cat >"$ROOT/etc/fstab" <<'EOF_FSTAB'
# / is assembled by initramfs from SquashFS + OverlayFS.
tmpfs /tmp tmpfs rw,nosuid,nodev,noatime,mode=1777,size=64M 0 0
EOF_FSTAB
rm -f "$ROOT/etc/systemd/system/multi-user.target.wants/atlantian-grow-rootfs.service"

install -d -m 0755 "$ROOT/etc/systemd/journald.conf.d"
cat >"$ROOT/etc/systemd/journald.conf.d/atlantian-nand.conf" <<'EOF_JOURNAL'
[Journal]
Storage=volatile
RuntimeMaxUse=16M
EOF_JOURNAL

echo "NAND rootfs cloned from common runtime rootfs: $ROOT"
