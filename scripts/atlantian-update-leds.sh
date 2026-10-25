#!/bin/sh
# D3 update pattern for signed, autonomous RAM maintenance upgrades.
# The unified updater starts this helper during staging. systemd shuts it down
# during kexec; manual invocation restores normal LED services on exit.
PATTERN='red red red green green green'
ON_SECONDS=0.05
OFF_SECONDS=0.05

set -eu

RED_LED=/sys/class/leds/atlantian:red:status/brightness
GREEN_LED=/sys/class/leds/atlantian:green:activity/brightness
LOCK=/run/atlantian-update-leds.lock
SERVICES='atlantian-status-leds.service atlantian-fpga-status-leds.service'
RESTART_SERVICES=${ATLANTIAN_UPDATE_RESTART_SERVICES:-1}

die() { echo "atlantian-update-leds: $*" >&2; exit 2; }
write() { printf '%s\n' "$2" >"$1"; }
off() { write "$RED_LED" 0; write "$GREEN_LED" 0; }

case "$RESTART_SERVICES" in 0|1) ;; *) die 'ATLANTIAN_UPDATE_RESTART_SERVICES must be 0 or 1' ;; esac
[ -w "$RED_LED" ] && [ -w "$GREEN_LED" ] || die 'D3 LED sysfs endpoints are unavailable'

cleanup() {
    off 2>/dev/null || true
    rm -f "$LOCK"
    if [ "$RESTART_SERVICES" = 1 ]; then
        systemctl start $SERVICES >/dev/null 2>&1 || true
    fi
}
terminate() { cleanup; exit 0; }
trap cleanup EXIT
trap terminate INT TERM HUP

: >"$LOCK"
systemctl stop $SERVICES >/dev/null 2>&1 || true
off

while :; do
    for item in $PATTERN; do
        off
        case "$item" in
            red|r|R) write "$RED_LED" 1 ;;
            green|g|G) write "$GREEN_LED" 1 ;;
            off|0|-) ;;
            *) die "unknown pattern element: $item" ;;
        esac
        sleep "$ON_SECONDS"
        off
        sleep "$OFF_SECONDS"
    done
done
