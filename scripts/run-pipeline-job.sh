#!/usr/bin/env bash
# Launch a build/deploy as a systemd transient unit so terminal disconnects
# cannot interrupt SD deployment.  The unit journal is the authoritative log.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo 'usage: run-pipeline-job.sh {userspace|dtb|kernel|boot|layout|all|deploy} [board-ip]' >&2
  exit 64
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHANGE=$1
BOARD=${2:-}
UNIT=atlantian-pipeline

if systemctl is-active --quiet "$UNIT.service"; then
  echo "$UNIT is already running; follow it with: journalctl -fu $UNIT.service" >&2
  exit 75
fi

ARGS=("$ROOT/scripts/build-and-deploy.sh" "$CHANGE")
[[ -n $BOARD ]] && ARGS+=("$BOARD")
printf -v COMMAND '%q ' "${ARGS[@]}"

exec sudo systemd-run --unit="$UNIT" --collect \
  --uid="$(id -un)" --gid="$(id -gn)" \
  --property=WorkingDirectory="$ROOT" \
  --property=TimeoutStartSec=30min --property=TimeoutStopSec=30s \
  /bin/bash -lc "exec $COMMAND"
