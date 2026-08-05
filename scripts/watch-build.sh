#!/usr/bin/env bash
set -euo pipefail

LOG=/home/paul/atlantian/rootfs-build.log
clear
printf 'AtlANTian build monitor\n'
printf 'Log: %s\n\n' "$LOG"
tail -n 80 -F "$LOG"
