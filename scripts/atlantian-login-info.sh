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

# Login never performs network I/O; it only displays a release already found
# by the periodic background check.
if [ -n "${SSH_CONNECTION:-}" ]; then
    /usr/local/sbin/atlantian-release-check --notice || true
fi
