#!/bin/sh
# Interactive, Debian-style in-place AtlANTian system updater.
set -eu

STATE=/var/lib/atlantian/update/available.env
NOTES=/var/lib/atlantian/update/available-notes.txt
STAGE=/var/cache/atlantian/update
RELEASE_CONFIG=${ATLANTIAN_RELEASE_CONFIG:-/etc/atlantian/releases.conf}

get() { sed -n "s/^$1=//p" "$STATE" | head -n1; }
human_size() { numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || printf '%s bytes' "$1"; }
usage() {
  cat <<'EOF'
Usage: atlantian-sysupgrade [OPTION]

Without an option, checks GitHub Releases, shows the newest release and asks
for UPGRADE before installing it.

Options:
  --check       Refresh and show whether an update is available.
  --notes       Refresh and print the newest release notes.
  --yes         Install without the interactive UPGRADE confirmation.
  --help        Show this help.

EOF
  printf '\nRelease source configuration: %s\n' "$RELEASE_CONFIG"
  printf '%s\n' 'Override its path for one invocation with ATLANTIAN_RELEASE_CONFIG=/path.'
}
show_release() {
  current=$(cat /etc/atlantian-release 2>/dev/null || printf unknown)
  total=$(( $(get platform_size) + $(get kernel_size) + $(get release_size) ))
  cat <<EOF

AtlANTian update available
  Installed: $current
  Release:   $(get tag)
  Published: $(get published_at)
  Download:  $(human_size "$total") (three verified Debian packages)

Changes:
EOF
  [ -r "$NOTES" ] && sed -n '1,120p' "$NOTES" || echo '  No release notes were published.'
}
download_and_verify() {
  mkdir -p "$STAGE"; rm -f "$STAGE"/*.deb "$STAGE/SHA256SUMS"
  total=$(( $(get platform_size) + $(get kernel_size) + $(get release_size) ))
  available=$(df -Pk "$STAGE" | awk 'NR == 2 { print $4 * 1024 }')
  required=$((total + 32 * 1024 * 1024))
  [ "$available" -ge "$required" ] || {
    echo "not enough free space in $STAGE: need $(human_size "$required") including working space, have $(human_size "$available")" >&2; exit 75;
  }
  for prefix in platform kernel release; do
    url=$(get "${prefix}_url"); name=$(get "${prefix}_name")
    case "$name" in ''|*[!A-Za-z0-9._+~-]*) echo "unsafe release asset name: $name" >&2; exit 65;; esac
    file="$STAGE/$name"
    echo "Downloading $name"
    curl -fL --retry 3 --progress-bar -o "$file" "$url"
  done
  echo "Downloading $(get sums_name)"
  curl -fL --retry 3 --progress-bar -o "$STAGE/SHA256SUMS" "$(get sums_url)"
  echo 'Verifying package checksums'
  for f in "$STAGE"/*.deb; do
    name=$(basename "$f")
    expected=$(awk -v name="$name" '$2 == name { print $1; exit }' "$STAGE/SHA256SUMS")
    [ -n "$expected" ] && [ "$(sha256sum "$f" | awk '{print $1}')" = "$expected" ] || {
      echo "checksum verification failed: $name" >&2; exit 1;
    }
    dpkg-deb --info "$f" >/dev/null
  done
}

[ "$(id -u)" = 0 ] || { echo 'run as root' >&2; exit 77; }
mode=${1:-install}
case "$mode" in --help|-h) usage; exit 0;; install|--check|--notes|--yes) ;; *) usage >&2; exit 64;; esac
[ "$mode" != install ] || [ $# -eq 0 ] || { usage >&2; exit 64; }

echo 'Checking the latest published AtlANTian release...'
/usr/local/sbin/atlantian-release-check --refresh
[ -r "$STATE" ] || { echo 'AtlANTian is already current.'; exit 0; }
show_release
if [ "$mode" = --check ]; then exit 0; fi
if [ "$mode" = --notes ]; then exit 0; fi
if [ "$mode" != --yes ]; then
  cat <<'EOF'

The update keeps ordinary Debian state: /etc, SSH keys, /root, /home, /var,
installed packages and modified Debian conffiles. It will reboot the board.

After verification, the normal LED services will stop. The red/green update
pattern will start, SSH will disconnect during reboot, and the board will
return when the new system has booted.

Type UPGRADE to download and install this release:
EOF
  IFS= read -r answer
  [ "$answer" = UPGRADE ] || { echo 'Update cancelled.'; exit 0; }
fi

download_and_verify
echo 'All packages are verified.'
echo 'Starting package installation; SSH will disconnect when the board reboots.'
: >/run/atlantian-update-leds.lock
systemctl stop atlantian-status-leds.service atlantian-fpga-status-leds.service 2>/dev/null || true
/usr/local/sbin/atlantian-update-leds & ledpid=$!
trap 'kill "$ledpid" 2>/dev/null || true; rm -f /run/atlantian-update-leds.lock' EXIT
export DEBIAN_FRONTEND=noninteractive
echo 'Installing AtlANTian platform, kernel and release packages...'
apt-get -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' install -y "$STAGE"/*.deb
echo 'Refreshing the pinned Debian package index...'
apt-get update
echo 'Applying compatible Debian package updates...'
apt-get -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' full-upgrade -y
sync
echo 'Update complete. Rebooting now; this SSH session will close.'
systemctl reboot
