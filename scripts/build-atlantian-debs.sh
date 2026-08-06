#!/usr/bin/env bash
# Package AtlANTian-owned files.  Debian itself remains updated by apt from the
# snapshot configured by atlantian-platform.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); . "$ROOT/config/release.env"
OUT=${OUT:-$ROOT/artifacts/current}; RFS=${RFS:-$ROOT/out/rootfs}; VERSION=${ATLANTIAN_VERSION:?}
mkdir -p "$OUT"; work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
control(){ mkdir -p "$1/DEBIAN"; printf 'Package: %s\nVersion: %s\nArchitecture: %s\nMaintainer: AtlANTian\nDescription: %s\n' "$2" "$VERSION" "$3" "$4" >"$1/DEBIAN/control"; }
conffiles(){ [ -d "$1/etc" ] && find "$1/etc" -type f -printf '/%P\n' >"$1/DEBIAN/conffiles" || true; }
copy(){ local p=$1; mkdir -p "$2/$(dirname "$p")"; cp -a "$RFS/$p" "$2/$p"; }
p="$work/platform"; mkdir -p "$p"; control "$p" atlantian-platform all 'AtlANTian board policy and tooling'
for f in etc/apt/sources.list etc/atlantian-release etc/os-release etc/issue.net etc/default/zramswap etc/default/atlantian-release-check etc/ssh/sshd_config.d/10-atlantian-root.conf etc/systemd/network/20-ethernet.network etc/systemd/resolved.conf.d/atlantian.conf etc/systemd/logind.conf.d/atlantian-power-policy.conf; do copy "$f" "$p"; done
for source in "$RFS"/usr/local/sbin/atlantian-*; do
  f=${source#"$RFS"/}
  copy "$f" "$p"
done
mkdir -p "$p/etc/systemd/system"; cp -a "$RFS/etc/systemd/system/atlantian-"*.service "$p/etc/systemd/system/"; cp -a "$RFS/etc/systemd/system/atlantian-"*.timer "$p/etc/systemd/system/"
mkdir -p "$p/lib/firmware/atlantian" "$p/etc/atlantian" "$p/usr/share/atlantian"; cp -a "$RFS/lib/firmware/atlantian/." "$p/lib/firmware/atlantian/"; cp -a "$RFS/etc/atlantian/." "$p/etc/atlantian/"; cp -a "$RFS/usr/share/atlantian/." "$p/usr/share/atlantian/"
conffiles "$p"; cat >"$p/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
systemctl daemon-reload || true
systemctl enable atlantian-grow-rootfs.service atlantian-status-leds.service atlantian-fpga-status-leds.service atlantian-release-check.timer || true
EOF
chmod 0755 "$p/DEBIAN/postinst"; dpkg-deb --build --root-owner-group "$p" "$OUT/atlantian-platform_${VERSION}_all.deb"
k="$work/kernel"; mkdir -p "$k"; control "$k" atlantian-kernel armhf 'AtlANTian CTRL_C41 kernel and modules'
mkdir -p "$k/boot" "$k/lib/modules"; cp -a "$RFS/lib/modules/." "$k/lib/modules/"; cp "$ROOT/out/boot/zImage" "$k/boot/zImage"; cp "$ROOT/out/boot/devicetree.dtb" "$k/boot/devicetree.dtb"
mkimage -A arm -O linux -T kernel -C none -a 0x00008000 -e 0x00008000 -n "AtlANTian ${ATLANTIAN_RELEASE_ID}" -d "$ROOT/out/boot/zImage" "$k/boot/uImage"
dpkg-deb --build --root-owner-group "$k" "$OUT/atlantian-kernel_${VERSION}_armhf.deb"
r="$work/release"; mkdir -p "$r"; control "$r" atlantian-release all 'AtlANTian release meta-package'; printf 'Depends: atlantian-platform (= %s), atlantian-kernel (= %s)\n' "$VERSION" "$VERSION" >>"$r/DEBIAN/control"; dpkg-deb --build --root-owner-group "$r" "$OUT/atlantian-release_${VERSION}_all.deb"
