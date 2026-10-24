#!/bin/bash
# Shared SD/NAND updater: authenticate and stage on ext4, then kexec to RAM.
set -euo pipefail
export LC_ALL=C
fail() { printf 'atlantian-sysupgrade: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || fail "missing utility $1"; }
get() { sed -n "s/^$1=//p" /var/lib/atlantian/update/available.env | head -n1; }
major() { local n=${1%%.*}; [[ $n =~ ^[0-9]+$ ]] || return 1; echo "$n"; }
edition=$(cat /run/atlantian/storage-edition 2>/dev/null || cat /usr/lib/atlantian/storage-edition)
[[ $edition == sd || $edition == nand ]] || fail 'unsupported storage edition'
mode=${1:---install}
case "$mode" in
 --help|-h) echo 'Usage: atlantian-sysupgrade [--check|--notes|--yes]'; exit 0 ;;
 --install|--check|--notes|--yes) ;;
 *) fail 'unknown option' ;;
esac
[[ $(id -u) == 0 ]] || fail 'run as root'
for bin in curl jq kexec cpio zstd tar sha256sum systemctl ldd dropbearconvert \
  dropbear rsync chroot; do need "$bin"; done
[[ -s /etc/ssh/ssh_host_ed25519_key ]] || fail 'no SSH host key'
[[ -s /usr/lib/atlantian/ram-upgrade-busybox ]] || fail 'static RAM BusyBox missing'
[[ -r /sys/firmware/fdt ]] || fail 'live FDT missing'
[[ $(cat /proc/sys/kernel/kexec_load_disabled) == 0 ]] || fail 'kexec disabled'
case "$(tr -d '\000' </proc/device-tree/model)" in *Antminer*S9*) ;; *) fail 'unsupported board' ;; esac
mem=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
[[ $mem =~ ^[0-9]+$ && $mem -ge 400000 ]] || fail 'insufficient RAM'
/usr/local/sbin/atlantian-release-check --refresh
[[ -s /var/lib/atlantian/update/available.env ]] || { echo 'No newer compatible release.'; exit 0; }
target=$(get version); tag=$(get tag); current=$(cat /usr/lib/atlantian/version)
[[ $target =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]] || fail 'unsafe target version'
[[ $tag == "v$target" ]] || fail 'release tag differs from target'
[[ $(major "$target") == "$(major "$current")" ]] ||
 fail 'Debian-major changes are not supported by RAM updates; use migration/reinstallation'
echo "AtlANTian $edition: $current -> $target"
if [[ $mode == --notes ]]; then cat /var/lib/atlantian/update/available-notes.txt; exit 0; fi
[[ $mode != --check ]] || exit 0
if [[ $mode != --yes ]]; then
 read -rp 'Type UPGRADE to stage autonomous RAM maintenance: ' answer
 [[ $answer == UPGRADE ]] || { echo 'Cancelled.'; exit 0; }
fi
# Stage on ext4 p2. On NAND this is NOT the SD boot partition, and may
# be an adopted external OverlayFS medium with invalid/absent FAT p1.
if [[ $edition == sd ]]; then
 [[ $(findmnt -n -o SOURCE /) == /dev/mmcblk0p2 ]] || fail 'SD root must be mmcblk0p2'
 [[ -s /boot/atlantian-A.itb && -s /boot/atlantian-B.itb ]] || fail 'SD A/B FIT missing'
 root=/
else
 root=/run/atlantian/external-overlay
 [[ $(cat /run/atlantian/overlay-mode) == external ]] ||
   fail 'NAND currently requires adopted external OverlayFS p2 for staging'
 [[ $(findmnt -n -o SOURCE "$root") == /dev/mmcblk0p2 ]] || fail 'external p2 not mounted'
 [[ -d $root/.atlantian-extroot/upper && -d $root/.atlantian-extroot/work ]] ||
   fail 'external upper/work absent'
 for b in flash_erase nandwrite nanddump ubiformat ubiattach ubidetach \
   ubimkvol ubiupdatevol ubiblock; do need "$b"; done
fi
relative="var/cache/atlantian/ram-upgrade/$target"
stage="$root/$relative"
[[ ! -e $stage/IN-PROGRESS ]] || fail "unfinished previous transaction: $stage"
mkdir -p "$stage/payload"
chmod 700 "$stage"
. /etc/atlantian/releases.conf
repo=${ATLANTIAN_GITHUB_REPO:?}
api=${ATLANTIAN_RELEASE_API:-https://api.github.com}
release=$(curl -fsSL --retry 3 "$api/repos/$repo/releases/tags/$tag")
asset_url() { jq -r --arg n "$1" '.assets[] | select(.name==$n) | .browser_download_url' <<<"$release" | head -n1; }
fetch() {
 local n=$1 u
 u=$(asset_url "$n")
 [[ $u == https://* ]] || fail "release asset absent: $n"
 curl -fL --retry 3 --progress-bar -o "$stage/$n.new" "$u"
 mv -f "$stage/$n.new" "$stage/$n"
}
check_public_hash() {
 local n=$1 expected actual
 expected=$(awk -v n="$n" '$2==n || $2=="*"n {print $1; exit}' "$stage/SHA256SUMS")
 [[ $expected =~ ^[a-f0-9]{64}$ ]] || fail "unsigned artifact: $n"
 actual=$(sha256sum "$stage/$n" | awk '{print $1}')
 [[ $actual == "$expected" ]] || fail "hash mismatch: $n"
}
fetch SHA256SUMS
fetch SHA256SUMS.sigstore.json
ATLANTIAN_COSIGN_CACHE_DIR="$stage/trust" \
 /usr/local/sbin/atlantian-verify-release "$stage/SHA256SUMS" "$stage/SHA256SUMS.sigstore.json"
archive="atlantian-nand-$target.tar.zst"
fetch "$archive"
check_public_hash "$archive"
# Only the signed NAND payload is used by the RAM NAND writer and kexec.
tar --zstd -xf "$stage/$archive" -C "$stage/payload"
(cd "$stage/payload" && sha256sum -c SHA256SUMS) || fail 'invalid NAND payload'
[[ $(jq -r .release "$stage/payload/NAND-MANIFEST.json") == "$target" ]] || fail 'bundle identity mismatch'
[[ $(od -An -tx1 -N4 "$stage/payload/uImage" | tr -d ' \n') == 27051956 ]] || fail 'invalid legacy uImage'
if [[ $edition == sd ]]; then
 : >"$stage/packages.list"
 for kind in platform kernel release; do
   name=$(get "${kind}_name")
   [[ $name =~ ^atlantian-(platform|kernel|release)_[a-zA-Z0-9.+~-]+_(all|armhf)\.deb$ ]] || fail 'unsafe package filename'
   fetch "$name"
   check_public_hash "$name"
   [[ $(dpkg-deb -f "$stage/$name" Package) == "atlantian-$kind" ]] ||
     fail "Debian package identity mismatch: $name"
   [[ $(dpkg-deb -f "$stage/$name" Version) == "$(get package_version)" ]] ||
     fail "Debian package version mismatch: $name"
   case "$kind" in kernel) expected_arch=armhf ;; *) expected_arch=all ;; esac
   [[ $(dpkg-deb -f "$stage/$name" Architecture) == "$expected_arch" ]] ||
     fail "Debian package architecture mismatch: $name"
   printf '%s=%s\n' "$kind" "$name" >>"$stage/packages.list"
 done
 [[ -s /boot/atlantian-boot-abi ]] || fail 'SD boot ABI missing'
else
 # Preserve the inactive internal upper independently and the *active* merged
 # external root without attempting to mount its busy upper a second time.
 [[ -d /run/atlantian/lower && -d /run/atlantian/internal-overlay/upper ]] || fail 'NAND mounts absent'
 snap="$stage/snapshot"; mkdir -p "$snap"
 /usr/local/sbin/atlantian-nand-rebase capture /run/atlantian/lower \
   /run/atlantian/internal-overlay/upper /run/atlantian/internal-overlay/work "$snap/internal"
 /usr/local/sbin/atlantian-nand-rebase capture-mounted /run/atlantian/lower / "$snap/external"
 [[ -s $root/.atlantian-extroot/token && -s /run/atlantian/internal-overlay/.extroot-token ]] ||
   fail 'external adoption token missing'
 cmp "$root/.atlantian-extroot/token" /run/atlantian/internal-overlay/.extroot-token ||
   fail 'external adoption token mismatch'
 cp /run/atlantian/internal-overlay/.extroot-token "$stage/extroot-token"
fi
# All authentication is complete. Free the large ARM Cosign download before kexec.
rm -rf "$stage/trust"
work=$(mktemp -d /run/atlantian-ram-upgrade.XXXXXX)
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT
mkdir -p "$work/ramfs"/{bin,sbin,usr/bin,usr/sbin,etc/dropbear,dev,dev/pts,proc,sys,run,tmp,state,stage,root}
cp /usr/lib/atlantian/ram-upgrade-busybox "$work/ramfs/bin/busybox"
chmod 755 "$work/ramfs/bin/busybox"
for cmd in $(/usr/lib/atlantian/ram-upgrade-busybox --list); do
 case "$cmd" in '['|'[[') continue ;; esac
 [[ -e $work/ramfs/bin/$cmd ]] || ln -s busybox "$work/ramfs/bin/$cmd"
done
# Preserve the executable and all ELF shared objects; these are read from
# the running installation *before* it is dismantled by systemd kexec.
copy_elf() {
 local path=$1 lib
 [[ $path == /* && -f $path ]] || fail "not an executable: $path"
 mkdir -p "$work/ramfs$(dirname "$path")"
 cp -L "$path" "$work/ramfs$path"
 while IFS= read -r lib; do
   [[ -f $lib ]] || fail "missing library: $lib"
   mkdir -p "$work/ramfs$(dirname "$lib")"
   cp -L "$lib" "$work/ramfs$lib"
 done < <(ldd "$path" | awk '$2 == "=>" && $3 ~ /^\// {print $3} $1 ~ /^\// {print $1}')
 ! ldd "$path" | grep -q 'not found' || fail "unresolved libraries: $path"
}
for b in dropbear jq rsync; do copy_elf "$(command -v "$b")"; done
if [[ $edition == nand ]]; then
 for b in flash_erase nandwrite nanddump ubiformat ubiattach ubidetach \
  ubimkvol ubiupdatevol ubiblock; do copy_elf "$(command -v "$b")"; done
fi
for lib in /lib/arm-linux-gnueabihf/libnss_files.so.2 /usr/lib/arm-linux-gnueabihf/libnss_files.so.2; do
 if [[ -f $lib ]]; then mkdir -p "$work/ramfs$(dirname "$lib")"; cp -L "$lib" "$work/ramfs$lib"; fi
done
dropbearconvert openssh dropbear /etc/ssh/ssh_host_ed25519_key "$work/ramfs/etc/dropbear/host_ed25519"
chmod 600 "$work/ramfs/etc/dropbear/host_ed25519"
printf 'root:x:0:0:root:/root:/bin/sh\n' >"$work/ramfs/etc/passwd"
printf 'root::19000:0:99999:7:::\n' >"$work/ramfs/etc/shadow"
printf 'root:x:0:\n' >"$work/ramfs/etc/group"
printf 'passwd: files\nshadow: files\ngroup: files\n' >"$work/ramfs/etc/nsswitch.conf"
chmod 600 "$work/ramfs/etc/shadow"
cp /usr/lib/atlantian/ram-upgrade-apply "$work/ramfs/sbin/ram-upgrade-apply"
cp /usr/local/sbin/atlantian-nand-rebase "$work/ramfs/sbin/atlantian-nand-rebase"
cp "$stage/payload/SHA256SUMS" "$work/ramfs/state/signed-internal-sums"
printf '%s\n' "$edition" >"$work/ramfs/state/edition"
printf '%s\n' "$target" >"$work/ramfs/state/target"
printf '%s\n' "$relative" >"$work/ramfs/state/stage-relative"
cat >"$work/ramfs/sbin/dhcp.script" <<'DHCP'
#!/bin/sh
case "$1" in
 deconfig) ifconfig "$interface" 0.0.0.0 ;;
 bound|renew)
  ifconfig "$interface" "$ip" netmask "${subnet:-255.255.255.0}" up
  route del default 2>/dev/null || true
  set -- $router
  [ "$#" -eq 0 ] || route add default gw "$1" "$interface" || true
  printf '%s\n' "$ip" >/run/dhcp-address
  : >/run/resolv.conf
  for d in $dns; do printf 'nameserver %s\n' "$d" >>/run/resolv.conf; done ;;
esac
DHCP
chmod 755 "$work/ramfs/sbin/dhcp.script"
cat >"$work/ramfs/init" <<'INIT'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
mount -t devtmpfs devtmpfs /dev || exec sh
mount -t proc proc /proc || exec sh
mount -t sysfs sysfs /sys || exec sh
mkdir -p /dev/pts /run /tmp /state /stage /root
mount -t devpts devpts /dev/pts || true
ip link set lo up
ip link set eth0 up
udhcpc -i eth0 -n -q -t 6 -T 3 -s /sbin/dhcp.script || true
/usr/sbin/dropbear -B -p 22 -r /etc/dropbear/host_ed25519 -P /run/dropbear.pid
mount -t ext4 -o rw,noatime /dev/mmcblk0p2 /stage || {
 echo 'Cannot mount ext4 stage; SSH rescue remains available.' >/dev/console
 exec sh
}
dmesg >/run/nand-dmesg
/sbin/ram-upgrade-apply >/stage/var/cache/atlantian/ram-upgrade-last.log 2>&1
result=$?
sync
if [ "$result" -eq 0 ]; then
 echo 'RAM update verified; rebooting to existing boot source.' >/dev/console
 umount /stage || true
 reboot -f
else
 echo 'RAM update FAILED. SSH rescue remains available.' >/dev/console
 echo 'Review /stage/var/cache/atlantian/ram-upgrade-last.log' >/dev/console
fi
while :; do sleep 60; done
INIT
chmod 755 "$work/ramfs/init"
mknod -m 0600 "$work/ramfs/dev/console" c 5 1
mknod -m 0666 "$work/ramfs/dev/null" c 1 3
(cd "$work/ramfs" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -1 >"$work/initramfs.cpio.gz")
dd if="$stage/payload/uImage" of="$work/zImage" bs=64 skip=1 status=none
cat /sys/firmware/fdt >"$work/live.dtb"
[[ -s $work/live.dtb ]] || fail 'live DTB missing'
printf 'edition=%s\ntarget=%s\n' "$edition" "$target" >"$stage/IN-PROGRESS"
sync
kexec --load --type=zImage --initrd="$work/initramfs.cpio.gz" --dtb="$work/live.dtb" \
 --command-line='console=ttyPS0,115200n8 mtdparts=pl35x-nand-controller:16m(atlantian-boot),-(atlantian-ubi) rdinit=/init panic=10' "$work/zImage"
echo 'Verified RAM maintenance is loaded. Starting systemd kexec...'
trap - EXIT
systemctl kexec || { kexec -u || true; fail 'systemd kexec failed'; }
