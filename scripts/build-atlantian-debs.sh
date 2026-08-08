#!/usr/bin/env bash
# Package AtlANTian-owned files. Debian userspace remains maintained by normal
# live APT repositories; the immutable Snapshot is only a factory-build input.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/config/release.env"
OUT=${OUT:-$ROOT/artifacts/current}
RFS=${RFS:-$ROOT/out/rootfs}
VERSION=${ATLANTIAN_VERSION:?}

mkdir -p "$OUT"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

control() {
  mkdir -p "$1/DEBIAN"
  cat >"$1/DEBIAN/control" <<EOF_CONTROL
Package: $2
Version: $VERSION
Architecture: $3
Section: admin
Priority: optional
Maintainer: AtlANTian
Homepage: https://github.com/BlackF1re/atlantian
Description: $4
EOF_CONTROL
}
conffiles() {
  [ -d "$1/etc" ] && find "$1/etc" -type f -printf '/etc/%P\n' >"$1/DEBIAN/conffiles" || true
}
copy() {
  local path=$1 target=$2
  mkdir -p "$target/$(dirname "$path")"
  cp -a "$RFS/$path" "$target/$path"
}

# Cross-major package installation is an explicit transaction. This preinst
# gate is embedded in every AtlANTian package so even a pre-lifecycle updater
# cannot accidentally install a Debian 14 package set directly over Debian 13.
major_guard() {
  local package_root=$1
  cat >"$package_root/DEBIAN/preinst" <<'EOF_GUARD'
#!/bin/sh
set -eu
target_version='@TARGET_VERSION@'
target_major='@TARGET_MAJOR@'
authorization=/run/atlantian-major-upgrade-authorized

installed_version=$(cat /usr/lib/atlantian/version 2>/dev/null || cat /etc/atlantian-release 2>/dev/null || true)
installed_major=${installed_version%%.*}
case "$installed_major" in
  ''|*[!0-9]*) exit 0 ;;
esac

if [ "$target_major" -lt "$installed_major" ]; then
  echo "refusing AtlANTian Debian-major downgrade: $installed_major -> $target_major" >&2
  exit 78
fi
if [ "$target_major" -gt "$installed_major" ]; then
  [ "$target_major" -eq $((installed_major + 1)) ] || {
    echo "refusing AtlANTian Debian-major skip: $installed_major -> $target_major" >&2
    exit 78
  }
  [ -r "$authorization" ] && [ "$(cat "$authorization")" = "$target_version" ] || {
    echo "Debian-major package transition to $target_version requires atlantian-sysupgrade" >&2
    exit 78
  }
fi
exit 0
EOF_GUARD
  sed -i \
    -e "s/@TARGET_VERSION@/$VERSION/g" \
    -e "s/@TARGET_MAJOR@/$DEBIAN_MAJOR/g" \
    "$package_root/DEBIAN/preinst"
  chmod 0755 "$package_root/DEBIAN/preinst"
}

p="$work/platform"
mkdir -p "$p"
control "$p" atlantian-platform all 'AtlANTian board policy and tooling'
printf '%s\n' 'Depends: zram-tools' >>"$p/DEBIAN/control"

# /etc/apt/sources.list intentionally is not package-owned. The factory image
# contains it, and the managed template lives in /usr/lib/atlantian. This keeps
# ordinary user edits out of dpkg conffile churn while still allowing the
# lifecycle-aware updater to switch Debian codenames explicitly.
for f in \
  etc/atlantian-release \
  etc/atlantian/releases.conf \
  etc/ssh/sshd_config.d/10-atlantian-access.conf \
  etc/systemd/network/10-atlantian-ethernet.link \
  etc/systemd/network/20-ethernet.network \
  etc/systemd/resolved.conf.d/atlantian.conf \
  etc/systemd/logind.conf.d/atlantian-power-policy.conf; do
  copy "$f" "$p"
done
for source in "$RFS"/usr/local/sbin/atlantian-*; do
  f=${source#"$RFS"/}
  copy "$f" "$p"
done
mkdir -p "$p/etc/systemd/system"
cp -a "$RFS/etc/systemd/system/atlantian-"*.service "$p/etc/systemd/system/"
cp -a "$RFS/etc/systemd/system/atlantian-"*.timer "$p/etc/systemd/system/"
mkdir -p "$p/lib/firmware/atlantian" "$p/etc/atlantian" \
  "$p/usr/share/atlantian" "$p/usr/lib/atlantian"
cp -a "$RFS/lib/firmware/atlantian/." "$p/lib/firmware/atlantian/"
cp -a "$RFS/etc/atlantian/." "$p/etc/atlantian/"
cp -a "$RFS/usr/share/atlantian/." "$p/usr/share/atlantian/"
for f in version source-revision debian-codename debian-major runtime-sources.list; do
  copy "usr/lib/atlantian/$f" "$p"
done

conffiles "$p"
# Release identity is package-owned state, not user configuration.
sed -i '\#^/etc/atlantian-release$#d' "$p/DEBIAN/conffiles"
major_guard "$p"
cat >"$p/DEBIAN/postinst" <<'EOF_POSTINST'
#!/bin/sh
set -e
systemctl daemon-reload || true
install -d -m 0755 /etc/systemd/system/ssh.service.wants
ln -sfn ../atlantian-ssh-hostkeys.service \
  /etc/systemd/system/ssh.service.wants/atlantian-ssh-hostkeys.service
systemctl enable atlantian-grow-rootfs.service atlantian-status-leds.service \
  atlantian-fpga-status-leds.service atlantian-release-check.timer || true

# `/etc/apt/sources.list` became user-owned when AtlANTian stopped shipping it
# as a dpkg conffile. The factory image contains it, and the managed template
# lives in /usr/lib/atlantian.
template=/usr/lib/atlantian/runtime-sources.list
if [ -s "$template" ]; then
  if [ ! -s /etc/apt/sources.list ]; then
    install -d -m 0755 /etc/apt
    install -m 0644 "$template" /etc/apt/sources.list
  elif grep -q 'snapshot\.debian\.org' /etc/apt/sources.list 2>/dev/null; then
    backup=/etc/apt/sources.list.atlantian-snapshot.bak
    [ -e "$backup" ] || cp -a /etc/apt/sources.list "$backup"
    install -m 0644 "$template" /etc/apt/sources.list
  fi
fi
EOF_POSTINST
chmod 0755 "$p/DEBIAN/postinst"
dpkg-deb --build --root-owner-group "$p" "$OUT/atlantian-platform_${VERSION}_all.deb"

k="$work/kernel"
mkdir -p "$k"
control "$k" atlantian-kernel armhf 'AtlANTian CTRL_C41 kernel and boot firmware'
major_guard "$k"
mkdir -p "$k/usr/lib/atlantian/boot" "$k/lib/modules"
cp -a "$RFS/lib/modules/." "$k/lib/modules/"
BOOT_BIN="$ROOT/out/bootloader/BOOT.bin" \
UBOOT_IMG="$ROOT/out/bootloader/u-boot.img" \
DTB="$ROOT/out/boot/devicetree.dtb" \
ZIMAGE="$ROOT/out/boot/zImage" \
  "$ROOT/scripts/populate-boot-files.sh" "$k/usr/lib/atlantian/boot"
cat >"$k/DEBIAN/postinst" <<'EOF_KERNEL_POST'
#!/bin/sh
set -eu
source=/usr/lib/atlantian/boot
target=/boot
[ -d "$target" ] || { echo 'AtlANTian boot partition is not mounted at /boot' >&2; exit 1; }

# Install the second stage, boot policy and Linux payload first. BOOT.bin (SPL)
# is committed last so a power loss cannot expose a new first stage without its
# matching u-boot.img already present on FAT.
for name in u-boot.img boot.scr uEnv.txt zImage devicetree.dtb uImage; do
  install -m 0644 "$source/$name" "$target/.$name.new"
  mv -f "$target/.$name.new" "$target/$name"
done
install -m 0644 "$source/BOOT.bin" "$target/.BOOT.bin.new"
mv -f "$target/.BOOT.bin.new" "$target/BOOT.bin"
sync
EOF_KERNEL_POST
chmod 0755 "$k/DEBIAN/postinst"
dpkg-deb --build --root-owner-group "$k" "$OUT/atlantian-kernel_${VERSION}_armhf.deb"

r="$work/release"
mkdir -p "$r"
control "$r" atlantian-release all 'AtlANTian release meta-package'
major_guard "$r"
printf 'Depends: atlantian-platform (= %s), atlantian-kernel (= %s)\n' \
  "$VERSION" "$VERSION" >>"$r/DEBIAN/control"
dpkg-deb --build --root-owner-group "$r" "$OUT/atlantian-release_${VERSION}_all.deb"
