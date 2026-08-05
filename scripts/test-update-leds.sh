#!/usr/bin/env bash
# Host-side contract test for the updater indicator.  It uses regular files as
# LED-class brightness endpoints, so it is suitable for GitHub Actions.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
cleanup() {
  if [[ -n ${PID:-} ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

red=$WORK/red
green=$WORK/green
lock=$WORK/update.lock
: >"$red"
: >"$green"

ATLANTIAN_UPDATE_RED_LED=$red \
ATLANTIAN_UPDATE_GREEN_LED=$green \
ATLANTIAN_UPDATE_LOCK=$lock \
ATLANTIAN_UPDATE_PULSE_TIME=0.01 \
ATLANTIAN_UPDATE_GAP_TIME=0.01 \
  bash "$ROOT/scripts/atlantian-update-leds.sh" &
PID=$!

# Within one 80-ms cycle both LEDs must have been actively driven.  Sampling
# frequently avoids treating a final off state as a failed pulse.
seen_red=0
seen_green=0
for _ in $(seq 1 30); do
  [[ $(<"$red") == 1 ]] && seen_red=1
  [[ $(<"$green") == 1 ]] && seen_green=1
  sleep 0.01
done

[[ $seen_red == 1 && $seen_green == 1 ]]
[[ -e $lock ]]
kill -TERM "$PID"
wait "$PID" || true
unset PID

# The writer owns its lock and leaves both GPIO LEDs in the safe off state.
[[ ! -e $lock ]]
[[ $(<"$red") == 0 ]]
[[ $(<"$green") == 0 ]]
echo 'update LED contract passed'
