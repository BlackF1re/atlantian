#!/bin/sh
# Login continuation for physical NAND handoff and staged maintenance.
# Ordinary storage status/adoption guidance is emitted only by atlantian-login-info.
set -eu
INSTALL_STATE=/var/lib/atlantian/nand-install

[ -t 0 ] && [ -t 1 ] || exit 0
[ "$(id -u)" -eq 0 ] || exit 0

case "$(findmnt -n -o SOURCE / 2>/dev/null || true)" in
    /dev/mmcblk0p2)
        # Automatic continuation finishes the UBI write without a terminal. The
        # next login reaches the unavoidable physical SD->NAND handoff.
        if [ -s "$INSTALL_STATE/ready-to-handoff" ]; then
            echo
            echo 'AtlANTian finished installing and verifying NAND automatically.'
            exec /usr/local/sbin/atlantian-nand-install --handoff
        fi
        ;;
esac

exit 0
