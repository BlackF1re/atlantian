#!/bin/bash
# Read-only kexec smoke test for future NAND maintenance without recovery SD.
# This command NEVER programs NAND or modifies the external overlay.
set -euo pipefail

MODE=${1:---check}
case "$MODE" in --check|--probe) ;; *)
  echo 'usage: atlantian-nand-ram-probe [--check|--probe]' >&2; exit 64 ;;
esac
fail() { echo "NAND RAM probe: $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || fail 'run as root'
[ "$(cat /run/atlantian/storage-edition 2>/dev/null || true)" = nand ] ||
  fail 'only available when booted from NAND'
case "$(tr -d '\000' </proc/device-tree/model 2>/dev/null)" in
  *Antminer*S9*) ;; *) fail 'unexpected board model' ;;
esac
[ -r /sys/firmware/fdt ] || fail 'running, RAM-sized board DTB is not available'
# Installed image provides a private copy; legacy alpha installations can
# run the same read-only probe after installing Debian busybox-static manually.
busybox=/usr/lib/atlantian/ram-probe-busybox
if [ ! -s "$busybox" ]; then
  busybox=/usr/bin/busybox
  [ -x "$busybox" ] && file -Lb "$busybox" | grep -Eq 'static|statically linked' ||
    fail 'a static ARM BusyBox is required (install busybox-static)'
fi
for bin in kexec cpio zstd curl jq sha256sum systemctl tar; do
  command -v "$bin" >/dev/null || fail "missing utility: $bin"
done
[[ $(cat /proc/sys/kernel/kexec_load_disabled 2>/dev/null || echo 0) == 0 ]] ||
  fail 'kexec_load is disabled by the running kernel'
available_kib=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
[[ $available_kib =~ ^[0-9]+$ ]] || fail 'cannot read free RAM'
(( available_kib >= 300000 )) ||
  fail "insufficient available RAM for a safe 512 MiB kexec smoke test: ${available_kib} KiB"
echo 'Read-only RAM maintenance prerequisites are present.'
if [[ $MODE == --check ]]; then
  echo 'No download, reboot or NAND write has occurred.'
  exit 0
fi
echo
echo 'This smoke test loads a replacement Linux kernel into RAM, without flashing.'
echo 'SSH will disconnect. UART access is strongly recommended.'
echo 'If kexec cannot start on this board, a physical power cycle may be required.'
read -rp 'Type PROBE to continue: ' answer
[[ $answer == PROBE ]] || { echo 'Cancelled.'; exit 0; }

# The immutable NAND base cannot stage a full target image on its small UBIFS
# upper. Stage on a bounded tmpfs even when an external overlay is present.
work=$(mktemp -d /run/atlantian-ram-probe.XXXXXX)
mounted=false
loaded=false
cleanup() {
  if [[ $loaded == true ]]; then kexec -u >/dev/null 2>&1 || true; fi
  if [[ $mounted == true ]]; then umount "$work" >/dev/null 2>&1 || true; fi
  rmdir "$work" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM HUP
mount -t tmpfs -o size=210m,mode=0700,nosuid,nodev tmpfs "$work"
mounted=true
. /etc/atlantian/releases.conf
repo=${ATLANTIAN_GITHUB_REPO:?}
api=${ATLANTIAN_RELEASE_API:-https://api.github.com}
# A smoke test must work even when the installed firmware is the latest.
# Unlike update discovery this test does not require a newer version.
release_json=$(curl -fsSL --retry 3 "$api/repos/$repo/releases/latest")
tag=$(jq -r '.tag_name // empty' <<<"$release_json")
case "$tag" in v13.*) target=${tag#v} ;; *) fail "unsupported latest-release identity: $tag" ;; esac
[[ $(jq -r '.draft' <<<"$release_json") == false ]] || fail 'latest release is a draft'
bundle="atlantian-nand-$target.tar.zst"
url=$(jq -r --arg name "$bundle" '.assets[] | select(.name==$name) | .browser_download_url' <<<"$release_json" | head -1)
size=$(jq -r --arg name "$bundle" '.assets[] | select(.name==$name) | .size' <<<"$release_json" | head -1)
[[ -n "$url" && $url != null && $size =~ ^[0-9]+$ ]] || fail 'target NAND archive not available'
(( size > 0 && size <= 100*1024*1024 )) || fail 'NAND archive exceeds bounded RAM staging allowance'
curl -fL --retry 3 -o "$work/$bundle" "$url"
sums_url=$(jq -r '.assets[] | select(.name=="SHA256SUMS") | .browser_download_url' <<<"$release_json" | head -1)
signature_url=$(jq -r '.assets[] | select(.name=="SHA256SUMS.sigstore.json") | .browser_download_url' <<<"$release_json" | head -1)
[[ -n "$sums_url" && $sums_url != null && -n "$signature_url" && $signature_url != null ]] ||
  fail 'release signature or checksum manifest is missing'
curl -fL --retry 3 -o "$work/SHA256SUMS" "$sums_url"
curl -fL --retry 3 -o "$work/SHA256SUMS.sigstore.json" "$signature_url"
mkdir -p "$work/trust"
ATLANTIAN_COSIGN_CACHE_DIR="$work/trust" /usr/local/sbin/atlantian-verify-release \
  "$work/SHA256SUMS" "$work/SHA256SUMS.sigstore.json"
(cd "$work" && sha256sum -c SHA256SUMS --ignore-missing | grep -Fx "$bundle: OK") ||
  fail 'the archive is not authenticated by the signed release manifest'
mkdir -p "$work/payload" "$work/ramfs/bin" "$work/ramfs/dev" "$work/ramfs/proc" "$work/ramfs/sys"
tar --zstd -xf "$work/$bundle" -C "$work/payload"
(cd "$work/payload" && sha256sum -c SHA256SUMS) || fail 'NAND bundle integrity check failed'
[[ $(jq -r '.release' "$work/payload/NAND-MANIFEST.json") == "$target" ]] ||
  fail 'NAND bundle identity mismatch'
[[ $(od -An -tx1 -N4 "$work/payload/uImage" | tr -d ' \n') == 27051956 ]] ||
  fail 'target kernel is not a U-Boot legacy kernel image'
dd if="$work/payload/uImage" of="$work/kernel-zImage" bs=64 skip=1 status=none
cp "$busybox" "$work/ramfs/bin/busybox"
chmod 0755 "$work/ramfs/bin/busybox"
cat >"$work/ramfs/init" <<'EOF_INIT'
#!/bin/busybox sh
# This is intentionally a NON-destructive kernel + initramfs test.
export PATH=/bin
/bin/busybox mount -t devtmpfs devtmpfs /dev
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
echo
echo 'AtlANTian RAM MAINTENANCE PROBE BOOTED SUCCESSFULLY.'
echo 'NAND was NOT modified. Attempting a normal NAND-mode software reboot.'
echo
/bin/busybox sync
/bin/busybox sleep 5
/bin/busybox reboot -f
echo 'Automatic reboot failed; use a physical power cycle (jumper stays on NAND).'
exec /bin/busybox sh
EOF_INIT
chmod 0755 "$work/ramfs/init"
(cd "$work/ramfs" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -1 >"$work/maintenance-initramfs.cpio.gz")
cat /sys/firmware/fdt >"$work/live.dtb"
[ -s "$work/live.dtb" ] || fail 'live board DTB could not be copied'
sync
kexec --load --type=zImage --initrd="$work/maintenance-initramfs.cpio.gz" \
  --dtb="$work/live.dtb" --command-line='console=ttyPS0,115200n8 rdinit=/init' \
  "$work/kernel-zImage"
loaded=true
echo 'Kernel accepted by kexec. Requesting clean systemd kexec handoff...'
# The loaded kernel and initramfs have been copied into kexec segments.
# systemd will stop services before handing over; no boot jumper change.
trap - EXIT INT TERM HUP
systemctl kexec || { kexec -u || true; fail 'systemd could not initiate kexec'; }
