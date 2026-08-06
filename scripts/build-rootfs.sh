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
ATLANTIAN_RELEASE=${ATLANTIAN_RELEASE:-$ATLANTIAN_RELEASE_ID}
CACHE_DIR=${ATLANTIAN_DEBOOTSTRAP_CACHE:-/var/cache/atlantian/debootstrap}

if [[ ${EUID} -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

rm -rf "$ROOT"
mkdir -p "$ROOT"
mkdir -p "$CACHE_DIR"
debootstrap --cache-dir="$CACHE_DIR" --arch="$ARCH" --variant=minbase "$SUITE" "$ROOT" "$MIRROR"

# Do not unpack material that is not useful on a 256/512-MiB embedded target.
# Licences remain locally available. Manuals can be restored later by removing
# these exclusions and reinstalling the relevant Debian package.
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
# p2 is intentionally a compact, replaceable root filesystem.  APT's index
# files are transient but can exceed the available free space on it (notably
# the English translation index).  Keep those files and downloaded packages on
# persistent p3 instead.  This configuration is read only after
# atlantian-persist-state mounts /data, which happens before SSH is started.
install -D -m 0644 "$PROJECT/config/apt/10-atlantian-persistent-cache" \
  "$ROOT/etc/apt/apt.conf.d/10-atlantian-persistent-cache"

printf '%s\n' "$HOSTNAME" >"$ROOT/etc/hostname"
printf '%s\n' "$ATLANTIAN_RELEASE" >"$ROOT/etc/atlantian-release"
cat >"$ROOT/etc/os-release" <<EOF
PRETTY_NAME="AtlANTian GNU/Linux $ATLANTIAN_RELEASE"
NAME="AtlANTian GNU/Linux"
ID=atlantian
VERSION_ID="$ATLANTIAN_RELEASE"
VERSION="$ATLANTIAN_RELEASE (based on Debian GNU/Linux $SUITE)"
HOME_URL="https://github.com/"
SUPPORT_URL="https://github.com/"
BUG_REPORT_URL="https://github.com/"
EOF
ln -sfn "/usr/share/zoneinfo/$TIMEZONE" "$ROOT/etc/localtime"
printf '%s\n' "$TIMEZONE" >"$ROOT/etc/timezone"
cat >"$ROOT/etc/default/locale" <<'EOF'
LANG=C.UTF-8
EOF
cat >"$ROOT/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME
EOF
# Debian's minbase deliberately leaves fstab unconfigured.  Without an entry
# for /, systemd-remount-fs has nothing to remount and root remains read-only
# after the Zynq boot loader's initial mount.
cat >"$ROOT/etc/fstab" <<'EOF'
/dev/mmcblk0p2 / ext4 defaults 0 1
/dev/mmcblk0p3 /data ext4 defaults,nofail 0 2
EOF
mkdir -p "$ROOT/data" "$ROOT/etc/atlantian"
mkdir -p "$ROOT/etc/systemd/network" "$ROOT/etc/systemd/system/serial-getty@ttyPS0.service.d"
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
# DHCP-provided DNS takes precedence.  These make a direct connection through
# an otherwise minimally configured router usable for apt and Tailscale too.
FallbackDNS=1.1.1.1 2606:4700:4700::1111
EOF
cat >"$ROOT/etc/systemd/system/serial-getty@ttyPS0.service.d/atlantian.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud 115200,57600,38400 ttyPS0 vt102
EOF

cat >"$ROOT/etc/issue.net" <<EOF
Welcome to AtlANTian GNU/Linux!
$ATLANTIAN_RELEASE (based on Debian GNU/Linux $SUITE)

AtlANTian based on Debian GNU/Linux, so:

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.

You can change this banner at any time there: /etc/issue.net
EOF
install -d -m 0755 "$ROOT/etc/profile.d" "$ROOT/etc/systemd/logind.conf.d"
# Keep the root console recognisable on both SSH and UART.  Do this in the
# image source rather than relying on an interactive, post-install edit.
cat >>"$ROOT/root/.bashrc" <<'EOF'

# AtlANTian interactive root prompt: green identity, blue working directory.
if [ -n "${PS1-}" ]; then
    PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]# '
fi
EOF
# `debootstrap --variant=minbase` does not guarantee a root login profile.
# Bash already sources /etc/profile for a login shell; this file adds only the
# root prompt and must not source /etc/profile a second time (which would make
# the AtlANTian banner appear twice).
cat >"$ROOT/root/.profile" <<'EOF'
[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"
EOF
chmod 0644 "$ROOT/root/.profile"
install -D -m 0755 "$PROJECT/scripts/atlantian-login-info.sh" "$ROOT/usr/local/sbin/atlantian-login-info"
install -D -m 0755 "$PROJECT/scripts/atlantian-fpga.sh" "$ROOT/usr/local/sbin/atlantian-fpga"
# Keep the generic FPGA profile ABI, and embed only the small, board-safe
# status-LED profile.  Other PL designs remain externally installable so a
# future full design can replace this profile without a kernel rebuild.
install -d -m 0755 "$ROOT/lib/firmware/atlantian/status-leds" \
  "$ROOT/etc/atlantian/fpga-profiles.d" \
  "$ROOT/var/lib/atlantian/fpga-profiles"
install -D -m 0644 "$PROJECT/fpga/status-leds/atlantian-status-leds.bin" \
  "$ROOT/lib/firmware/atlantian/status-leds/atlantian-status-leds.bin"
install -D -m 0644 "$PROJECT/fpga/status-leds/atlantian-status-leds.dtbo" \
  "$ROOT/lib/firmware/atlantian/status-leds/atlantian-status-leds.dtbo"
install -D -m 0644 "$PROJECT/fpga/status-leds/manifest.json" \
  "$ROOT/etc/atlantian/fpga-profiles.d/status-leds.json"
cat >"$ROOT/etc/profile.d/10-atlantian-login-info.sh" <<'EOF'
[ -t 1 ] && /usr/local/sbin/atlantian-login-info
EOF
install -D -m 0644 "$PROJECT/systemd/atlantian-power-policy.conf" "$ROOT/etc/systemd/logind.conf.d/atlantian-power-policy.conf"

# D3 is a PS-GPIO bicolour LED.  The daemon uses only standard LED-class
# sysfs: red emits an atomic double-pulse heartbeat whose inter-pair pause
# tracks aggregate CPU utilisation; green briefly pulses on real mmcblk0 I/O.
install -D -m 0755 "$PROJECT/scripts/atlantian-update-leds.sh" \
  "$ROOT/usr/local/sbin/atlantian-update-leds"
# The update blinker is a standalone utility used by both recovery and
# network-driven update paths.  It must be present in the rootfs so the
# recovery initramfs can carry the exact same logic.
install -D -m 0755 "$PROJECT/scripts/atlantian-status-leds.sh" \
  "$ROOT/usr/local/sbin/atlantian-status-leds"
install -D -m 0644 "$PROJECT/systemd/atlantian-status-leds.service" \
  "$ROOT/etc/systemd/system/atlantian-status-leds.service"
install -D -m 0755 "$PROJECT/scripts/atlantian-fpga-status-leds.sh" \
  "$ROOT/usr/local/sbin/atlantian-fpga-status-leds"
install -D -m 0644 "$PROJECT/systemd/atlantian-fpga-status-leds.service" \
  "$ROOT/etc/systemd/system/atlantian-fpga-status-leds.service"
install -D -m 0755 "$PROJECT/scripts/atlantian-persist-state.sh" \
  "$ROOT/usr/local/sbin/atlantian-persist-state"
install -D -m 0644 "$PROJECT/systemd/atlantian-persist-state.service" \
  "$ROOT/etc/systemd/system/atlantian-persist-state.service"
install -D -m 0755 "$PROJECT/scripts/atlantian-grow-data.sh" \
  "$ROOT/usr/local/sbin/atlantian-grow-data"
install -D -m 0644 "$PROJECT/systemd/atlantian-grow-data.service" \
  "$ROOT/etc/systemd/system/atlantian-grow-data.service"
install -D -m 0755 "$PROJECT/scripts/atlantian-sysupgrade.sh" \
  "$ROOT/usr/local/sbin/atlantian-sysupgrade"
install -D -m 0755 "$PROJECT/scripts/atlantian-release-check.sh" \
  "$ROOT/usr/local/sbin/atlantian-release-check"
install -D -m 0644 "$PROJECT/systemd/atlantian-release-check.service" \
  "$ROOT/etc/systemd/system/atlantian-release-check.service"
install -D -m 0644 "$PROJECT/systemd/atlantian-release-check.timer" \
  "$ROOT/etc/systemd/system/atlantian-release-check.timer"
install -D -m 0644 "$PROJECT/config/atlantian-release-check.default" \
  "$ROOT/etc/default/atlantian-release-check"

mount --bind /dev "$ROOT/dev"
mount -t proc proc "$ROOT/proc"
mount -t sysfs sys "$ROOT/sys"
cleanup() { umount -l "$ROOT/sys" "$ROOT/proc" "$ROOT/dev"; }
trap cleanup EXIT

chroot "$ROOT" /bin/bash -eux <<'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update
xargs -r apt-get install -y --no-install-recommends < /usr/local/share/atlantian/packages.base
# Use Debian's maintained zram-tools integration.  Write our policy after
# package installation so dpkg never prompts about a locally-created conffile.
# One third of RAM is configured; no disk-backed swap exists.
cat > /etc/default/zramswap <<'ZRAM_EOF'
ALGO=lz4
PERCENT=33
PRIORITY=100
ZRAM_EOF
command -v sfdisk
command -v resize2fs
command -v mkimage
apt-get clean
rm -rf /var/lib/apt/lists/*
# debootstrap populated part of /usr/share before the exclusions existed.
# Apply the same policy to that initial package set, preserving copyright.
find /usr/share/doc -mindepth 2 -type f ! -name copyright -delete
find /usr/share/doc -depth -type d -empty -delete
rm -rf /usr/share/man/* /usr/share/info/* /usr/share/locale/*
ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl enable ssh systemd-networkd systemd-timesyncd systemd-resolved serial-getty@ttyPS0.service atlantian-status-leds.service atlantian-fpga-status-leds.service atlantian-persist-state.service atlantian-grow-data.service zramswap.service atlantian-release-check.timer
systemctl set-default multi-user.target
EOF

# AtlANTian deliberately starts as an appliance-style root-only system: the
# first UART/SSH login must work without a password, then the login banner
# instructs the owner to run `passwd`.  Debian's debootstrap leaves root
# locked, so make this policy explicit instead of relying on a host default.
chroot "$ROOT" /usr/bin/passwd -d root
mkdir -p "$ROOT/etc/ssh/sshd_config.d"
cat >"$ROOT/etc/ssh/sshd_config.d/10-atlantian-root.conf" <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords yes
EOF
chmod 0644 "$ROOT/etc/ssh/sshd_config.d/10-atlantian-root.conf"

# The Debian snapshot pins the package universe; this sorted manifest records
# the exact resolved package set embedded in a release for independent audit.
mkdir -p "$ROOT/usr/share/atlantian"
chroot "$ROOT" /usr/bin/dpkg-query -W -f='${binary:Package}\t${Version}\n' \
  | LC_ALL=C sort >"$ROOT/usr/share/atlantian/debian-package-manifest.tsv"
printf 'snapshot=%s\nmirror=%s\nsecurity_mirror=%s\n' "$DEBIAN_SNAPSHOT_TIMESTAMP" "$MIRROR" "$DEBIAN_SECURITY_SNAPSHOT_MIRROR" \
  >"$ROOT/usr/share/atlantian/debian-snapshot.txt"

# The bind mounts expose host-owned pseudo-filesystems.  Drop them before
# walking the target tree; otherwise chown would both touch host state and
# fail on read-only kernel objects.
cleanup
trap - EXIT

# Prevent host-side image assembly from silently stripping package ownership.
# AtlANTian intentionally has no sudo: its console and SSH are root-only.
chown -hR 0:0 "$ROOT"

echo "rootfs created: $ROOT"
