#!/bin/sh
# AtlANTian update indicator for D3 LEDs.
# Pattern: red, red, green, green with equal gaps between flashes.

set -eu

RED_LED=${ATLANTIAN_UPDATE_RED_LED:-/sys/class/leds/atlantian:red:status/brightness}
GREEN_LED=${ATLANTIAN_UPDATE_GREEN_LED:-/sys/class/leds/atlantian:green:activity/brightness}
PULSE_TIME=${ATLANTIAN_UPDATE_PULSE_TIME:-0.15}
GAP_TIME=${ATLANTIAN_UPDATE_GAP_TIME:-0.15}
LOCK=${ATLANTIAN_UPDATE_LOCK:-/run/atlantian-update-leds.lock}

write_led() {
    led=$1
    value=$2
    printf '%s\n' "$value" > "$led"
}

cleanup() {
    write_led "$RED_LED" 0 2>/dev/null || true
    write_led "$GREEN_LED" 0 2>/dev/null || true
    rm -f "$LOCK" 2>/dev/null || true
}

trap cleanup INT TERM EXIT

mkdir -p /run 2>/dev/null || true
: >"$LOCK"

for led in "$RED_LED" "$GREEN_LED"; do
    [ -w "$led" ] || {
        printf '%s\n' "missing or unwritable LED path: $led" >&2
        exit 1
    }
done

while :; do
    [ -e "$LOCK" ] || exit 0

    write_led "$RED_LED" 1
    sleep "$PULSE_TIME"
    write_led "$RED_LED" 0
    sleep "$GAP_TIME"

    write_led "$RED_LED" 1
    sleep "$PULSE_TIME"
    write_led "$RED_LED" 0
    sleep "$GAP_TIME"

    write_led "$GREEN_LED" 1
    sleep "$PULSE_TIME"
    write_led "$GREEN_LED" 0
    sleep "$GAP_TIME"

    write_led "$GREEN_LED" 1
    sleep "$PULSE_TIME"
    write_led "$GREEN_LED" 0
    sleep "$GAP_TIME"
done
