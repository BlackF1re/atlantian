#!/bin/bash
# Shared SD/NAND updater: authenticate and package authenticated payload in RAM, then kexec.
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
[[ $mem =~ ^[0-9]+$ && $mem -ge 700000 ]] || fail 'insufficient RAM'
/usr/local/sbin/atlantian-release-check --refresh
[[ -s /var/lib/atlantian/update/available.env ]] || { echo 'No newer compatible release.'; exit 0; }
target=$(get version); tag=$(get tag); current=$(cat /usr/lib/atlantian/version)
[[ $target =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]] || fail 'unsafe target version'
[[ $tag == "v$target" ]] || fail 'release tag differs from target'
oldmajor=$(major "$current"); newmajor=$(major "$target")
(( newmajor == oldmajor || newmajor == oldmajor + 1 )) || fail 'adjacent Debian major required'
echo "AtlANTian $edition: $current -> $target"
if [[ $mode == --notes ]]; then cat /var/lib/atlantian/update/available-notes.txt; exit 0; fi
[[ $mode != --check ]] || exit 0
if [[ $mode != --yes ]]; then
 read -rp 'Type UPGRADE to stage autonomous RAM maintenance: ' answer
 [[ $answer == UPGRADE ]] || { echo 'Cancelled.'; exit 0; }
fi
# The signed payload lives in RAM: SD is not required for internal NAND.
if [[ $edition == sd ]]; then
  [[ $(findmnt -n -o SOURCE /) == /dev/mmcblk0p2 ]] || fail 'SD root must be mmcblk0p2'
  [[ -s /boot/atlantian-A.itb && -s /boot/atlantian-B.itb && -s /boot/atlantian-boot-abi ]] || fail 'SD boot missing'
  overlay_mode=sd
else
  [[ -d /run/atlantian/lower && -d /run/atlantian/internal-overlay/upper ]] || fail 'NAND mounts absent'
  overlay_mode=$(cat /run/atlantian/overlay-mode)
  case "$overlay_mode" in
    internal) ;;
    external)
      ext=/run/atlantian/external-overlay
      [[ $(findmnt -n -o SOURCE "$ext") == /dev/mmcblk0p2 ]] || fail 'active external upper card missing'
      [[ -s $ext/.atlantian-extroot/token && -s /run/atlantian/internal-overlay/.extroot-token ]] || fail 'token absent'
      cmp "$ext/.atlantian-extroot/token" /run/atlantian/internal-overlay/.extroot-token || fail 'token mismatch' ;;
    *) fail 'unknown NAND upper layout' ;;
  esac
  for b in flash_erase nandwrite nanddump ubiformat ubiattach ubidetach ubimkvol ubiupdatevol ubiblock; do need "$b"; done
fi
work=$(mktemp -d /run/atlantian-ram-upgrade.XXXXXX)
mounted=false
cleanup() {
  [[ $mounted != true ]] || umount "$work" >/dev/null 2>&1 || true
  rmdir "$work" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM HUP
mount -t tmpfs -o size=650m,mode=0700,nosuid,nodev tmpfs "$work"
mounted=true
mkdir -p "$work/payload" "$work/ramfs" "$work/trust" "$work/debs"
. /etc/atlantian/releases.conf
repo=${ATLANTIAN_GITHUB_REPO:?}
api=${ATLANTIAN_RELEASE_API:-https://api.github.com}
release=$(curl -fsSL --retry 3 "$api/repos/$repo/releases/tags/$tag")
asset_url() { jq -r --arg n "$1" '.assets[] | select(.name==$n) | .browser_download_url' <<<"$release" | head -n1; }
fetch() {
 local n=$1 u
 u=$(asset_url "$n")
 [[ $u == https://* ]] || fail "release asset absent: $n"
 curl -fL --retry 3 --progress-bar -o "$work/$n.new" "$u"
 mv -f "$work/$n.new" "$work/$n"
}
check_public_hash() {
 local n=$1 expected actual
 expected=$(awk -v n="$n" '$2==n || $2=="*"n {print $1; exit}' "$work/SHA256SUMS")
 [[ $expected =~ ^[a-f0-9]{64}$ ]] || fail "unsigned artifact: $n"
 actual=$(sha256sum "$work/$n" | awk '{print $1}')
 [[ $actual == "$expected" ]] || fail "hash mismatch: $n"
}
fetch SHA256SUMS
fetch SHA256SUMS.sigstore.json
ATLANTIAN_COSIGN_CACHE_DIR="$work/trust" \
 /usr/local/sbin/atlantian-verify-release "$work/SHA256SUMS" "$work/SHA256SUMS.sigstore.json"
archive="atlantian-nand-$target.tar.zst"
fetch "$archive"
check_public_hash "$archive"
# Only the signed NAND payload is used by the RAM NAND writer and kexec.
tar --zstd -xf "$work/$archive" -C "$work/payload"
(cd "$work/payload" && sha256sum -c SHA256SUMS) || fail 'invalid NAND payload'
[[ $(jq -r .release "$work/payload/NAND-MANIFEST.json") == "$target" ]] || fail 'bundle identity mismatch'
[[ $(od -An -tx1 -N4 "$work/payload/uImage" | tr -d ' \n') == 27051956 ]] || fail 'invalid legacy uImage'
if [[ $edition == sd ]]; then
 : >"$work/packages.list"
 for kind in platform kernel release; do
   name=$(get "${kind}_name")
   [[ $name =~ ^atlantian-(platform|kernel|release)_[a-zA-Z0-9.+~-]+_(all|armhf)\.deb$ ]] || fail 'unsafe package filename'
   fetch "$name"
   check_public_hash "$name"
   [[ $(dpkg-deb -f "$work/$name" Package) == "atlantian-$kind" ]] ||
     fail "Debian package identity mismatch: $name"
   [[ $(dpkg-deb -f "$work/$name" Version) == "$(get package_version)" ]] ||
     fail "Debian package version mismatch: $name"
   case "$kind" in kernel) expected_arch=armhf ;; *) expected_arch=all ;; esac
   [[ $(dpkg-deb -f "$work/$name" Architecture) == "$expected_arch" ]] ||
     fail "Debian package architecture mismatch: $name"
   printf '%s=%s\n' "$kind" "$name" >>"$work/packages.list"
 done
 [[ -s /boot/atlantian-boot-abi ]] || fail 'SD boot ABI missing'
else
  : # NAND state capture follows kexec, before UBI format.
fi
if [[ $edition == sd ]]; then
  for kind in platform kernel release; do
    name=$(sed -n "s/^${kind}=//p" "$work/packages.list")
    mv "$work/$name" "$work/debs/$name"
  done
fi
# The entire authenticated release must persist inside the new initramfs.
rm -rf "$work/trust" "$work/$archive"
mkdir -p "$work/ramfs"/{bin,sbin,usr/bin,usr/sbin,etc/dropbear,dev,dev/pts,proc,sys,run,tmp,state,root,payload,debs}
cp /usr/lib/atlantian/ram-upgrade-busybox "$work/ramfs/bin/busybox"
chmod 755 "$work/ramfs/bin/busybox"
# BusyBox dispatches by argv[0]: invoke the staged copy as "busybox", not
# "ram-upgrade-busybox". A failed --list must abort before kexec, otherwise the
# initramfs can lack /bin/sh and the kernel will panic/reboot.
applets=$("$work/ramfs/bin/busybox" --list) || fail 'cannot list staged RAM BusyBox applets'
[[ -n $applets ]] || fail 'staged RAM BusyBox returned no applets'
while IFS= read -r cmd; do
 case "$cmd" in ''|'['|'[[') continue ;; esac
 [[ -e $work/ramfs/bin/$cmd ]] || ln -s busybox "$work/ramfs/bin/$cmd"
done <<<"$applets"
# Fail in the original OS instead of discovering a missing PID 1 interpreter
# only after committing to systemd kexec.
for cmd in sh mount mkdir cat sleep reboot; do
 [[ -x "$work/ramfs/bin/$cmd" ]] || fail "RAM initramfs missing essential applet: $cmd"
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
cp -a "$work/payload/." "$work/ramfs/payload/"
cp -a "$work/debs/." "$work/ramfs/debs/"
[ ! -s "$work/packages.list" ] || cp "$work/packages.list" "$work/ramfs/state/packages.list"
cp "$work/payload/SHA256SUMS" "$work/ramfs/state/signed-internal-sums"
cp "$work/SHA256SUMS" "$work/ramfs/state/signed-public-sums"
printf '%s\n' "$edition" >"$work/ramfs/state/edition"
printf '%s\n' "$overlay_mode" >"$work/ramfs/state/overlay-mode"
printf '%s\n' "$target" >"$work/ramfs/state/target"
printf '%s\n' "$oldmajor" >"$work/ramfs/state/old-major"
printf '%s\n' "$newmajor" >"$work/ramfs/state/new-major"
date -u +%s >"$work/ramfs/state/epoch"
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
mkdir -p /dev/pts /run /root
mount -t devpts devpts /dev/pts || true
mount -t tmpfs -o mode=0755,size=400m tmpfs /run || exec sh
mkdir -p /run/upgrade
date -u -s "@$(cat /state/epoch)" >/dev/null 2>&1 || true
ip link set lo up
ip link set eth0 up
udhcpc -i eth0 -n -q -t 6 -T 3 -s /sbin/dhcp.script || true
/usr/sbin/dropbear -B -p 22 -r /etc/dropbear/host_ed25519 -P /run/dropbear.pid || true
dmesg >/run/nand-dmesg
/sbin/ram-upgrade-apply >/run/upgrade/upgrade.log 2>&1
result=$?
sync
if [ "$result" -eq 0 ]; then
  echo 'RAM update verified; rebooting.' >/dev/console
  reboot -f
else
  echo 'RAM update failed; SSH rescue active: /run/upgrade/upgrade.log' >/dev/console
fi
while :; do sleep 60; done
INIT
chmod 755 "$work/ramfs/init"
mknod -m 0600 "$work/ramfs/dev/console" c 5 1
mknod -m 0666 "$work/ramfs/dev/null" c 1 3
(cd "$work/ramfs" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -1 >"$work/initramfs.cpio.gz")
dd if="$work/payload/uImage" of="$work/zImage" bs=64 skip=1 status=none
cat /sys/firmware/fdt >"$work/live.dtb"
[[ -s $work/live.dtb ]] || fail 'live DTB missing'
image_kib=$((($(stat -c %s "$work/initramfs.cpio.gz") + 1023) / 1024))
remaining=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
(( remaining >= 130000 + image_kib * 2 )) || fail 'insufficient kexec headroom'
kexec --load --type=zImage --initrd="$work/initramfs.cpio.gz" --dtb="$work/live.dtb" \
 --command-line='console=ttyPS0,115200n8 mtdparts=pl35x-nand-controller:16m(atlantian-boot),-(atlantian-ubi) rdinit=/init panic=10' "$work/zImage"
echo 'Authenticated image resident in RAM. Starting systemd kexec...'
trap - EXIT
systemctl kexec || { kexec -u || true; fail 'systemd kexec failed'; }
