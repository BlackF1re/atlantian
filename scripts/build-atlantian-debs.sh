#!/usr/bin/env bash
# Assemble AtlANTian-owned Debian packages from explicit payload and maintainer files.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/config/release.env"
. "$ROOT/config/atlantian-releases.conf"
OUT=${OUT:-$ROOT/artifacts/current}; RFS=${RFS:-$ROOT/out/rootfs}
RELEASE_VERSION=${ATLANTIAN_VERSION:?}; PACKAGE_VERSION=${ATLANTIAN_DEB_VERSION:?}; RELEASE_REPOSITORY=${ATLANTIAN_GITHUB_REPO:?}
mkdir -p "$OUT"; work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

control() {
  mkdir -p "$1/DEBIAN"
  cat >"$1/DEBIAN/control" <<EOF_CONTROL
Package: $2
Version: $PACKAGE_VERSION
Architecture: $3
Section: admin
Priority: optional
Maintainer: AtlANTian
Homepage: https://github.com/$RELEASE_REPOSITORY
Description: $4
EOF_CONTROL
}
copy() { local path=$1 target=$2; mkdir -p "$target/$(dirname "$path")"; cp -a "$RFS/$path" "$target/$path"; }
conffiles() { [ -d "$1/etc" ] && find "$1/etc" -type f -printf '/etc/%P\n' >"$1/DEBIAN/conffiles" || true; }
install_maintainer() {
  local package=$1 name=$2 target=$3 source="$ROOT/packaging/$package/$name"
  [[ -f $source ]] || { echo "missing maintainer script: $source" >&2; exit 2; }
  install -m 0755 "$source" "$target/DEBIAN/$name"
  sed -i -e "s/@TARGET_VERSION@/$RELEASE_VERSION/g" -e "s/@TARGET_MAJOR@/$DEBIAN_MAJOR/g" "$target/DEBIAN/$name"
}

p="$work/platform"; mkdir -p "$p"; control "$p" atlantian-platform all 'AtlANTian platform policy and tooling'
printf '%s\n' 'Depends: zram-tools' >>"$p/DEBIAN/control"
for f in \
  etc/atlantian/releases.conf \
  etc/apt/apt.conf.d/10atlantian-volatile \
  etc/ssh/sshd_config.d/10-atlantian-access.conf \
  etc/systemd/network/10-atlantian-ethernet.link \
  etc/systemd/network/20-ethernet.network \
  etc/systemd/resolved.conf.d/atlantian.conf \
  etc/systemd/logind.conf.d/atlantian-power-policy.conf \
  etc/profile.d/10-atlantian-login-info.sh \
  etc/profile.d/20-atlantian-nand-firstboot.sh; do copy "$f" "$p"; done
for source in "$RFS"/usr/local/sbin/atlantian-*; do f=${source#"$RFS"/}; copy "$f" "$p"; done
mkdir -p "$p/usr/lib/systemd/system"; cp -a "$RFS/usr/lib/systemd/system/atlantian-"*.service "$p/usr/lib/systemd/system/"; cp -a "$RFS/usr/lib/systemd/system/atlantian-"*.timer "$p/usr/lib/systemd/system/"
copy usr/lib/systemd/system/run-apt.mount "$p"; copy usr/lib/tmpfiles.d/atlantian-apt.conf "$p"
mkdir -p "$p/lib/firmware/atlantian" "$p/etc/atlantian" "$p/usr/share/atlantian" "$p/usr/lib/atlantian"
cp -a "$RFS/lib/firmware/atlantian/." "$p/lib/firmware/atlantian/"; cp -a "$RFS/etc/atlantian/." "$p/etc/atlantian/"; cp -a "$RFS/usr/share/atlantian/." "$p/usr/share/atlantian/"
for f in version package-version source-revision debian-codename debian-major debian-snapshot release-repo os-release runtime-sources.list atlantian-sysupgrade-sd atlantian-sysupgrade-nand; do
  [[ -e $RFS/usr/lib/atlantian/$f ]] && copy "usr/lib/atlantian/$f" "$p"
done
conffiles "$p"; install_maintainer platform preinst "$p"; install_maintainer platform postinst "$p"
dpkg-deb --build --root-owner-group "$p" "$OUT/atlantian-platform_${PACKAGE_VERSION}_all.deb"

k="$work/kernel"; mkdir -p "$k"; control "$k" atlantian-kernel armhf 'AtlANTian kernel and transactional SD boot payload'
install_maintainer kernel preinst "$k"
mkdir -p "$k/usr/lib/atlantian/boot" "$k/lib/modules"; cp -a "$RFS/lib/modules/." "$k/lib/modules/"
BOOT_BIN="$ROOT/out/bootloader/BOOT.bin" UBOOT_IMG="$ROOT/out/bootloader/u-boot.img" DTB="$ROOT/out/boot/devicetree.dtb" ZIMAGE="$ROOT/out/boot/zImage" \
  "$ROOT/scripts/populate-boot-files.sh" "$k/usr/lib/atlantian/boot" package
install_maintainer kernel postinst "$k"
dpkg-deb --build --root-owner-group "$k" "$OUT/atlantian-kernel_${PACKAGE_VERSION}_armhf.deb"

r="$work/release"; mkdir -p "$r"; control "$r" atlantian-release all 'AtlANTian release meta-package'
install_maintainer release preinst "$r"
printf 'Depends: atlantian-platform (= %s), atlantian-kernel (= %s)\n' "$PACKAGE_VERSION" "$PACKAGE_VERSION" >>"$r/DEBIAN/control"
dpkg-deb --build --root-owner-group "$r" "$OUT/atlantian-release_${PACKAGE_VERSION}_all.deb"
