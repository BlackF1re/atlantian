#!/usr/bin/env bash
set -euo pipefail
[[ ${ATLANTIAN_TRACE_ROOTFS:-0} = 1 ]] && set -x

PROJECT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$PROJECT/config/release.env"
. "$PROJECT/config/debian-snapshot.env"
[ -r "$PROJECT/config/local.env" ] && . "$PROJECT/config/local.env"
ROOT="${ROOT:-$PROJECT/out/rootfs}"
SUITE="${SUITE:-$DEBIAN_CODENAME}"
MIRROR="${MIRROR:-$DEBIAN_SNAPSHOT_MIRROR}"
HOSTNAME=${ATLANTIAN_HOSTNAME:-atlantian}
TIMEZONE=${ATLANTIAN_TIMEZONE:-Etc/UTC}
ARCH="armhf"
CACHE_DIR=${ATLANTIAN_DEBOOTSTRAP_CACHE:-/var/cache/atlantian/debootstrap}

if [[ ${EUID} -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

rm -rf "$ROOT"
mkdir -p "$ROOT" "$CACHE_DIR"
debootstrap --cache-dir="$CACHE_DIR" --arch="$ARCH" --variant=minbase "$SUITE" "$ROOT" "$MIRROR"

# Keep the embedded image lean without removing local licence information.
cat >"$ROOT/etc/dpkg/dpkg.cfg.d/01-atlantian-lean" <<'EOF'
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
path-exclude=/usr/share/man/*
path-exclude=/usr/share/info/*
path-exclude=/usr/share/locale/*
EOF

install -D -m 0644 "$PROJECT/config/packages.base" "$ROOT/usr/local/share/atlantian/packages.base"
install -D -m 0644 "$PROJECT/config/image-layout.env" "$ROOT/usr/local/share/atlantian/image-layout.env"
cat >"$ROOT/etc/apt/sources.list" <<EOF
deb [check-valid-until=no] $MIRROR $SUITE main non-free-firmware
deb [check-valid-until=no] $MIRROR ${SUITE}-updates main non-free-firmware
deb [check-valid-until=no] $DEBIAN_SECURITY_SNAPSHOT_MIRROR ${SUITE}-security main non-free-firmware
EOF

printf '%s\n' "$HOSTNAME" >"$ROOT/etc/hostname"
ln -sfn "/usr/share/zoneinfo/$TIMEZONE" "$ROOT/etc/localtime"
printf '%s\n' "$TIMEZONE" >"$ROOT/etc/timezone"
cat >"$ROOT/etc/default/locale" <<'EOF'
LANG=C.UTF-8
EOF
cat >"$ROOT/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME
EOF
cat >"$ROOT/etc/fstab" <<'EOF'
/dev/mmcblk0p2 / ext4 defaults 0 1
/dev/mmcblk0p1 /boot vfat defaults 0 2
EOF

mkdir -p "$ROOT/etc/atlantian" "$ROOT/etc/systemd/network" \
  "$ROOT/etc/systemd/system/serial-getty@ttyPS0.service.d"
cat >"$ROOT/etc/systemd/network/10-atlantian-ethernet.link" <<'EOF'
[Match]
Driver=macb

[Link]
# The board has no dependable factory MAC. systemd derives a stable,
# locally-administered address from this installation's machine identity.
MACAddressPolicy=persistent
EOF
cat >"$ROOT/etc/systemd/network/20-ethernet.network" <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes
EOF
mkdir -p "$ROOT/etc/systemd/resolved.conf.d"
cat >"$ROOT/etc/systemd/resolved.conf.d/atlantian.conf" <<'EOF'
[Resolve]
FallbackDNS=1.1.1.1 2606:4700:4700::1111
EOF
cat >"$ROOT/etc/systemd/system/serial-getty@ttyPS0.service.d/atlantian.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud 115200,57600,38400 ttyPS0 vt102
EOF

install -d -m 0755 "$ROOT/etc/profile.d" "$ROOT/etc/systemd/logind.conf.d"
cat >>"$ROOT/root/.bashrc" <<'EOF'

if [ -n "${PS1-}" ]; then
    PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]# '
fi
EOF
cat >"$ROOT/root/.profile" <<'EOF'
[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"
EOF
chmod 0644 "$ROOT/root/.profile"

install -D -m 0755 "$PROJECT/scripts/atlantian-login-info.sh" "$ROOT/usr/local/sbin/atlantian-login-info"
install -D -m 0755 "$PROJECT/scripts/atlantian-fpga.sh" "$ROOT/usr/local/sbin/atlantian-fpga"
install -d -m 0755 "$ROOT/lib/firmware/atlantian/status-leds" \
  "$ROOT/etc/atlantian/fpga-profiles.d" "$ROOT/var/lib/atlantian/fpga-profiles"
install -D -m 0644 "$PROJECT/fpga/status-leds/atlantian-status-leds.bin" \
  "$ROOT/lib/firmware/atlantian/status-leds/atlantian-status-leds.bin"
install -D -m 0644 "$PROJECT/fpga/status-leds/atlantian-status-leds.dtbo" \
  "$ROOT/lib/firmware/atlantian/status-leds/atlantian-status-leds.dtbo"
install -D -m 0644 "$PROJECT/fpga/status-leds/manifest.json" \
  "$ROOT/etc/atlantian/fpga-profiles.d/status-leds.json"
cat >"$ROOT/etc/profile.d/10-atlantian-login-info.sh" <<'EOF'
[ -t 1 ] && /usr/local/sbin/atlantian-login-info
EOF
install -D -m 0644 "$PROJECT/systemd/atlantian-power-policy.conf" \
  "$ROOT/etc/systemd/logind.conf.d/atlantian-power-policy.conf"

install -D -m 0755 "$PROJECT/scripts/atlantian-update-leds.sh" "$ROOT/usr/local/sbin/atlantian-update-leds"
install -D -m 0755 "$PROJECT/scripts/atlantian-status-leds.sh" "$ROOT/usr/local/sbin/atlantian-status-leds"
install -D -m 0644 "$PROJECT/systemd/atlantian-status-leds.service" "$ROOT/etc/systemd/system/atlantian-status-leds.service"
install -D -m 0755 "$PROJECT/scripts/atlantian-fpga-status-leds.sh" "$ROOT/usr/local/sbin/atlantian-fpga-status-leds"
install -D -m 0644 "$PROJECT/systemd/atlantian-fpga-status-leds.service" "$ROOT/etc/systemd/system/atlantian-fpga-status-leds.service"
install -D -m 0755 "$PROJECT/scripts/atlantian-grow-rootfs.sh" "$ROOT/usr/local/sbin/atlantian-grow-rootfs"
install -D -m 0644 "$PROJECT/systemd/atlantian-grow-rootfs.service" "$ROOT/etc/systemd/system/atlantian-grow-rootfs.service"
install -D -m 0755 "$PROJECT/scripts/atlantian-sysupgrade.sh" "$ROOT/usr/local/sbin/atlantian-sysupgrade"
install -D -m 0755 "$PROJECT/scripts/atlantian-release-check.sh" "$ROOT/usr/local/sbin/atlantian-release-check"
install -D -m 0644 "$PROJECT/systemd/atlantian-release-check.service" "$ROOT/etc/systemd/system/atlantian-release-check.service"
install -D -m 0644 "$PROJECT/systemd/atlantian-release-check.timer" "$ROOT/etc/systemd/system/atlantian-release-check.timer"
install -D -m 0644 "$PROJECT/config/atlantian-releases.conf" "$ROOT/etc/atlantian/releases.conf"

mount --bind /dev "$ROOT/dev"
mount -t proc proc "$ROOT/proc"
mount -t sysfs sys "$ROOT/sys"
cleanup() { umount -l "$ROOT/sys" "$ROOT/proc" "$ROOT/dev"; }
trap cleanup EXIT

chroot "$ROOT" /bin/bash -eux <<'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update
xargs -r apt-get install -y --no-install-recommends < /usr/local/share/atlantian/packages.base
cat > /etc/default/zramswap <<'ZRAM_EOF'
ALGO=lz4
PERCENT=33
PRIORITY=100
ZRAM_EOF
command -v sfdisk
command -v resize2fs
apt-get clean
rm -rf /var/lib/apt/lists/*
find /usr/share/doc -mindepth 2 -type f ! -name copyright -delete
find /usr/share/doc -depth -type d -empty -delete
rm -rf /usr/share/man/* /usr/share/info/* /usr/share/locale/*
ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl enable ssh systemd-networkd systemd-timesyncd systemd-resolved \
  serial-getty@ttyPS0.service atlantian-status-leds.service \
  atlantian-fpga-status-leds.service atlantian-grow-rootfs.service \
  zramswap.service atlantian-release-check.timer
systemctl set-default multi-user.target
EOF

# The factory image must not clone host identity or server keys across boards.
# systemd creates a machine-id on first boot; the companion provisioning helper
# removes build-time SSH host keys and installs a per-device key generator.
: >"$ROOT/etc/machine-id"
rm -f "$ROOT/var/lib/dbus/machine-id"
"$PROJECT/scripts/configure-rootfs-access.sh" "$ROOT"
"$PROJECT/scripts/stamp-release.sh" "$ROOT"

mkdir -p "$ROOT/usr/share/atlantian"
chroot "$ROOT" /usr/bin/dpkg-query -W -f='${binary:Package}\t${Version}\n' \
  | LC_ALL=C sort >"$ROOT/usr/share/atlantian/debian-package-manifest.tsv"
printf 'snapshot=%s\nmirror=%s\nsecurity_mirror=%s\n' \
  "$DEBIAN_SNAPSHOT_TIMESTAMP" "$MIRROR" "$DEBIAN_SECURITY_SNAPSHOT_MIRROR" \
  >"$ROOT/usr/share/atlantian/debian-snapshot.txt"

# Drop host pseudo-filesystems before image assembly. Package ownership created
# by debootstrap/dpkg is intentionally preserved exactly; never recursively
# chown a root filesystem prepared as root.
cleanup
trap - EXIT

echo "rootfs created: $ROOT"
