#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
source_commit=$(git rev-parse "${1:-HEAD}^{commit}")
last_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$source_commit" 2>/dev/null || true)
if [[ -z "$last_tag" ]]; then
  echo true
elif git diff --quiet "$last_tag" "$source_commit" -- board config debian-release.sha256 debian-security-release.sha256 debian-updates-release.sha256 fpga kernel-overlay packaging scripts systemd ':(exclude)scripts/generate-release-notes.sh' ':(exclude)scripts/release-pending.sh' ':(exclude)scripts/test-release-pending.sh'; then
  echo false
else
  rc=$?
  (( rc == 1 )) || exit "$rc"
  echo true
fi
