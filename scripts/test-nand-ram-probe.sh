#!/usr/bin/env bash
# Source-level fail-closed contracts for the non-destructive NAND kexec probe.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
script=scripts/atlantian-nand-ram-probe.sh
fail() { echo "NAND RAM probe contract: $*" >&2; exit 1; }
bash -n "$script"
grep -Fq 'MODE=${1:---check}' "$script" || fail 'read-only check must be the default'
grep -Fq 'Type PROBE to continue:' "$script" || fail 'hardware handoff lacks explicit confirmation'
grep -Fq 'atlantian-verify-release' "$script" || fail 'release authentication missing'
grep -Fq 'sha256sum -c SHA256SUMS' "$script" || fail 'internal bundle authentication missing'
grep -Fq 'cat /sys/firmware/fdt' "$script" || fail 'live DDR-sized FDT is not used'
grep -Fq 'kexec --load --type=zImage' "$script" || fail 'kexec image staging missing'
grep -Fq 'systemctl kexec' "$script" || fail 'safe userspace shutdown missing'
grep -Fq 'NAND was NOT modified' "$script" || fail 'non-destructive probe does not identify itself'
# Flash operations have no place in a non-destructive smoke test.
if grep -Eiq '(^|[[:space:]])(nandwrite|flash_erase|ubiformat|ubiupdatevol|mtdpart[[:space:]]+add)([[:space:]]|$)' "$script"; then
  fail 'probe includes a raw NAND mutation'
fi
python3 - "$script" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
assert source.index('atlantian-verify-release') < source.index('kexec --load')
assert source.index('sha256sum -c SHA256SUMS') < source.index('kexec --load')
assert source.index('read -rp') < source.index('kexec --load')
assert source.index('if [[ $MODE == --check ]]') < source.index('mount -t tmpfs')
PY
grep -Fxq kexec-tools config/packages.base || fail 'missing kexec-tools package'
grep -Fxq cpio config/packages.base || fail 'missing cpio package'
grep -Fq 'ram-probe-busybox' scripts/build-nand-rootfs.sh || fail 'static BusyBox omitted'
echo 'non-destructive NAND RAM probe contracts passed'
