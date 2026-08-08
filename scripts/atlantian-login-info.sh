#!/bin/sh
# Dynamic post-authentication half of the SSH banner.
set -eu

release=$(cat /usr/lib/atlantian/version 2>/dev/null || cat /etc/atlantian-release 2>/dev/null || printf unknown)
debian=$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Debian GNU/Linux}" )
uptime=$(awk '{ s=int($1); d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60); if (d) printf "%dd %dh %dm",d,h,m; else if (h) printf "%dh %dm",h,m; else printf "%dm",m }' /proc/uptime)
previous=$(last -F -w -n 2 root 2>/dev/null | awk 'NR==2 && $1=="root" { $1=""; sub(/^ /,""); print; exit }')
[ -n "$previous" ] || previous=never

printf '\nAtlANTian build: %s\nDebian base: %s\n\n' "$release" "$debian"
printf 'Hostname: %s\nUptime: %s\nLast login: %s\n\n' "$(hostname)" "$uptime" "$previous"

pending=/var/lib/atlantian/update/major-upgrade-pending.env
backup_marker=/var/lib/atlantian/update/major-upgrade-sources-backup
if [ -s "$pending" ]; then
  target=$(sed -n 's/^target_version=//p' "$pending" | head -n1)
  printf 'UPDATE WARNING: Debian major upgrade to %s is incomplete.\n' "${target:-unknown}"
  printf 'Run: atlantian-sysupgrade\n\n'
elif [ -n "${SSH_CONNECTION:-}" ]; then
  # Login never performs network I/O; it only displays a release already found
  # by the periodic background checker.
  /usr/local/sbin/atlantian-release-check --notice || true
fi
if [ -s "$backup_marker" ]; then
  printf 'APT note: third-party sources from the last Debian major upgrade are disabled.\n'
  printf 'Review backup: %s\n\n' "$(cat "$backup_marker")"
fi
