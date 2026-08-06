#!/bin/sh
# Debian-style in-place AtlANTian update.  /etc, /root, /home, /var and
# installed packages remain ordinary files on the root filesystem.
set -eu
STATE=/var/lib/atlantian/update/available.env; STAGE=/var/cache/atlantian/update
get(){ sed -n "s/^$1=//p" "$STATE" | head -n1; }
[ "$(id -u)" = 0 ] || { echo 'run as root' >&2; exit 77; }
[ "${1:-}" = --latest ] && [ $# -eq 2 ] || { echo 'usage: atlantian-sysupgrade --latest RELEASE' >&2; exit 64; }
/usr/local/sbin/atlantian-release-check --refresh
release=$(get release_id); tag=$(get tag)
[ "$release" = "$2" ] || { echo "requested release is not available: $2" >&2; exit 65; }
cat <<EOF
AtlANTian will install $tag using normal APT/dpkg package transactions.
Your files, SSH keys, /etc configuration, /root, /home, /var and installed
packages are retained. Package conffiles keep local changes by default.
The board will reboot and SSH will disconnect when installation completes.
Type UPDATE to continue:
EOF
IFS= read -r answer; [ "$answer" = UPDATE ] || { echo 'update cancelled'; exit 0; }
mkdir -p "$STAGE"; rm -f "$STAGE"/*.deb
for key in platform_url kernel_url release_url; do
 url=$(get "$key"); file="$STAGE/$(basename "$url")"; echo "Downloading $(basename "$url")"; curl -fL --retry 3 --progress-bar -o "$file" "$url"; done
curl -fL --retry 3 --progress-bar -o "$STAGE/SHA256SUMS" "$(get sums_url)"
for f in "$STAGE"/*.deb; do
  name=$(basename "$f"); expected=$(awk -v name="$name" '$2 == name { print $1; exit }' "$STAGE/SHA256SUMS")
  [ -n "$expected" ] && [ "$(sha256sum "$f" | awk '{print $1}')" = "$expected" ] || { echo "checksum verification failed: $name" >&2; exit 1; }
done
for f in "$STAGE"/*.deb; do dpkg-deb --info "$f" >/dev/null; done
: >/run/atlantian-update-leds.lock
systemctl stop atlantian-status-leds.service atlantian-fpga-status-leds.service 2>/dev/null || true
/usr/local/sbin/atlantian-update-leds & ledpid=$!
trap 'kill "$ledpid" 2>/dev/null || true; rm -f /run/atlantian-update-leds.lock' EXIT
export DEBIAN_FRONTEND=noninteractive
apt-get -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' install -y "$STAGE"/*.deb
apt-get update
apt-get -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' full-upgrade -y
sync; echo 'Installation complete; SSH will disconnect while the board reboots.'
systemctl reboot
