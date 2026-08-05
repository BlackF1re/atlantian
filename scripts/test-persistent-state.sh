#!/usr/bin/env bash
# Fast source-level contract test for the state which survives replacement of
# p2.  Image-layout testing verifies installation; this catches a semantic
# regression before the expensive image test is even relevant.
set -euo pipefail

grep -q 'state=\$data/system/atlantian/persist' scripts/atlantian-persist-state.sh
grep -q 'lowerdir=/etc' scripts/atlantian-persist-state.sh
grep -q 'seed_tree /root' scripts/atlantian-persist-state.sh
grep -q 'seed_tree /home' scripts/atlantian-persist-state.sh
grep -q 'seed_tree /var/local' scripts/atlantian-persist-state.sh
grep -q 'Requires=data.mount' systemd/atlantian-persist-state.service
grep -q 'atlantian-persist-state.service' scripts/build-rootfs.sh
grep -q 'atlantian-persist-state.service' scripts/atlantian-sysupgrade.sh
grep -q 'state=/data/system/atlantian/grow' scripts/atlantian-grow-data.sh
! test -e scripts/atlantian-grow-rootfs.sh
! test -e systemd/atlantian-grow-rootfs.service
echo 'persistent-state contract passed'
