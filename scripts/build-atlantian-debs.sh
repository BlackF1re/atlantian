#!/usr/bin/env bash
# Package AtlANTian-owned files. Debian itself remains updated by apt from the
# snapshot configured by atlantian-platform.
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
  printf 'Package: %s\nVersion: %s\nArchitecture: %s\nMaintainer: AtlANTian\nDescription: %s\n' \
    "$2" "$VERSION" "$3" "$4" >"$1/DEBIAN/control"
}
conffiles() {
  [ -d "$1/etc" ] && find "$1/etc" -type f -printf '/etc/%P\n' >"$1/DEBIAN/conffiles" || true
}
copy() {
  local path=$1
  mkdir -p "$2/$(dirname "$path")"
  cp -a "$RFS/$path" "$2/$path"
}

p="$work/platform"
mkdir -p "$p"
control "$p" atlantian-platform all 'AtlANTian board policy and tooling'
printf '%s\n' 'Depends: zram-tools' >>"$p/DEBIAN/control"

# base-files owns /etc/os-release and /etc/issue.net. They are branded in the
# factory image but remain Debian-owned on an installed system.
for f in \
  etc/apt/sources.list \
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
cp -a "$RFS/usr/lib/atlantian/version" "$RFS/usr/lib/atlantian/source-revision" \
  "$p/usr/lib/atlantian/"

conffiles "$p"
# Release identity is package-owned state, not user configuration.
sed -i '\#^/etc/atlantian-release$#d' "$p/DEBIAN/conffiles"
cat >"$p/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
systemctl daemon-reload || true
install -d -m 0755 /etc/systemd/system/ssh.service.wants
ln -sfn ../atlantian-ssh-hostkeys.service \
  /etc/systemd/system/ssh.service.wants/atlantian-ssh-hostkeys.service
systemctl enable atlantian-grow-rootfs.service atlantian-status-leds.service \
  atlantian-fpga-status-leds.service atlantian-release-check.timer || true
EOF
chmod 0755 "$p/DEBIAN/postinst"
dpkg-deb --build --root-owner-group "$p" "$OUT/atlantian-platform_${VERSION}_all.deb"

k="$work/kernel"
mkdir -p "$k"
control "$k" atlantian-kernel armhf 'AtlANTian CTRL_C41 kernel and modules'
# /boot is FAT32. Keep dpkg payloads on ext4 and copy them to the boot
# partition from postinst so dpkg never needs FAT hard-link backup semantics.
mkdir -p "$k/usr/lib/atlantian/boot" "$k/lib/modules"
cp -a "$RFS/lib/modules/." "$k/lib/modules/"
cp "$ROOT/out/boot/zImage" "$k/usr/lib/atlantian/boot/zImage"
cp "$ROOT/out/boot/devicetree.dtb" "$k/usr/lib/atlantian/boot/devicetree.dtb"
mkimage -A arm -O linux -T kernel -C none -a 0x00008000 -e 0x00008000 \
  -n "AtlANTian ${ATLANTIAN_RELEASE_ID}" -d "$ROOT/out/boot/zImage" \
  "$k/usr/lib/atlantian/boot/uImage"
cat >"$k/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -eu
source=/usr/lib/atlantian/boot
target=/boot
[ -d "$target" ] || { echo 'AtlANTian boot partition is not mounted at /boot' >&2; exit 1; }
for name in zImage devicetree.dtb uImage; do
  install -m 0644 "$source/$name" "$target/.$name.new"
  mv -f "$target/.$name.new" "$target/$name"
done
sync
EOF
chmod 0755 "$k/DEBIAN/postinst"
dpkg-deb --build --root-owner-group "$k" "$OUT/atlantian-kernel_${VERSION}_armhf.deb"

r="$work/release"
mkdir -p "$r"
control "$r" atlantian-release all 'AtlANTian release meta-package'
printf 'Depends: atlantian-platform (= %s), atlantian-kernel (= %s)\n' \
  "$VERSION" "$VERSION" >>"$r/DEBIAN/control"
dpkg-deb --build --root-owner-group "$r" "$OUT/atlantian-release_${VERSION}_all.deb"
