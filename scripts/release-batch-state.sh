#!/usr/bin/env bash
# Count release-input commits since the latest AtlANTian release.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
SOURCE_SHA=${1:-HEAD}
source_commit=$(git rev-parse "${SOURCE_SHA}^{commit}")
last_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$source_commit" 2>/dev/null || true)
BATCH_THRESHOLD=5
paths=(
  board config debian-release.sha256 debian-security-release.sha256 debian-updates-release.sha256
  fpga kernel-overlay packaging scripts systemd
  ':(exclude)scripts/generate-release-notes.sh'
)
if [[ -n "$last_tag" ]]; then
  git rev-list --count "${last_tag}..${source_commit}" -- "${paths[@]}"
else
  printf '%s\n' "$BATCH_THRESHOLD"
fi
