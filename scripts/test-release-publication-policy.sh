#!/usr/bin/env bash
# The public beta channel is visible on GitHub without weakening update safety.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FLAGS="$ROOT/scripts/release-publication-flags.sh"
fail() { printf 'publication policy: %s\n' "$*" >&2; exit 1; }
check() {
  [[ $(bash "$FLAGS" "$1") == "$2" ]] || fail "$1 did not produce the expected GitHub flags"
}
check 13.1.0-alpha.65 --prerelease
check 13.1.0-beta.1 --latest
check 13.1.0-beta.2 --latest
check 13.1.0-rc.1 --prerelease
check 13.1.0 --latest
for invalid in 13.1.0-nightly.1 13.1.0-beta.0 13.1.0-beta.bad 13.1.0-alpha.1+source; do
  if bash "$FLAGS" "$invalid" >/dev/null 2>&1; then fail "invalid release was accepted: $invalid"; fi
done
echo 'GitHub release channel and Latest presentation contracts passed'
