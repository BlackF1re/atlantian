#!/bin/sh
# Dynamic post-authentication half of the SSH banner.
set -eu

release=$(cat /etc/atlantian-release 2>/dev/null || printf unknown)
debian=$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Debian GNU/Linux}" )
uptime=$(awk '{ s=int($1); d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60); if (d) printf "%dd %dh %dm",d,h,m; else if (h) printf "%dh %dm",h,m; else printf "%dm",m }' /proc/uptime)
# sshd/PAM has already recorded this session.  The second entry is therefore
# the previous login; if none exists, state that truthfully.
previous=$(last -F -w -n 2 root 2>/dev/null | awk 'NR==2 && $1=="root" { $1=""; sub(/^ /,""); print; exit }')
[ -n "$previous" ] || previous=never

printf '\nAtlANTian build: %s\nDebian base: %s\n\n' "$release" "$debian"
printf 'Hostname: %s\nUptime: %s\nLast login: %s\n\n' "$(hostname)" "$uptime" "$previous"

# A login never performs network I/O. It only repeats a previously discovered
# release from persistent state until that release has been installed.
if [ -n "${SSH_CONNECTION:-}" ]; then
    /usr/local/sbin/atlantian-release-check --notice || true
fi
