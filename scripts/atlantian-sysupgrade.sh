#!/bin/sh
# Both storage editions perform authenticated, offline, kexec RAM maintenance.
set -eu
exec /usr/lib/atlantian/ram-upgrade "$@"
