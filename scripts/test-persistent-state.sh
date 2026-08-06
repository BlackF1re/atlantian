#!/usr/bin/env bash
# Integration test: run the actual persistence helper in a private mount
# namespace and verify that its overlay and bind mounts retain a real value.
set -euo pipefail

[[ $(id -u) -eq 0 ]] || exec sudo "$(readlink -f "$0")"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
unshare --mount --propagation private bash -eu <<EOF
mount --make-rprivate /
mkdir -p /data /var/local
mount -t tmpfs tmpfs /data
"$ROOT/scripts/atlantian-persist-state.sh"
printf 'retained\n' >/etc/atlantian-persistence-integration-test
printf 'key\n' >/root/.atlantian-persistence-integration-test
"$ROOT/scripts/atlantian-persist-state.sh"
test "\$(cat /etc/atlantian-persistence-integration-test)" = retained
test "\$(cat /root/.atlantian-persistence-integration-test)" = key
test "\$(findmnt -n -o FSTYPE /etc)" = overlay
test "\$(findmnt -n -o SOURCE /root)" = /data/system/atlantian/persist/root
EOF
echo 'persistent-state integration test passed'
