#!/usr/bin/env bash
# Fail-closed, non-destructive source-level contracts for RAM updater.
set -euo pipefail
cd "$(dirname "$0")/.."
stage=scripts/atlantian-ram-upgrade.sh
apply=scripts/atlantian-ram-upgrade-apply.sh
bash -n "$stage"
sh -n "$apply"
grep -Fq 'atlantian-verify-release' "$stage"
grep -Fq 'systemctl kexec' "$stage"
grep -Fq 'size=650m' "$stage"
grep -Fq 'cp -a "$work/payload/." "$work/ramfs/payload/"' "$stage"
grep -Fq 'cp "$work/SHA256SUMS" "$work/ramfs/state/signed-public-sums"' "$stage"
grep -Fq 'mtdparts=pl35x-nand-controller:16m(atlantian-boot),-(atlantian-ubi)' "$stage"
grep -Fq 'udhcpc -i eth0' "$stage"
grep -Fq '/usr/sbin/dropbear -B' "$stage"
grep -Fq 'capture-mounted' "$apply"
grep -Fq 'ubiformat /dev/mtd1' "$apply"
grep -Fq 'atlantian-major-upgrade-authorized' "$apply"
python3 - "$stage" "$apply" <<'PY'
from pathlib import Path
import subprocess, sys
s,a=[Path(p).read_text() for p in sys.argv[1:]]
init=s.split("<<'INIT'\n",1)[1].split("\nINIT\n",1)[0]
subprocess.run(['sh','-n'],input=init,text=True,check=True)
assert s.index('atlantian-verify-release') < s.index('kexec --load')
assert s.index("check_public_hash \"$archive\"") < s.index('kexec --load')
assert s.index('cp -a "$work/payload/."') < s.index('kexec --load')
assert 'mtdparts=pl35x-nand-controller:16m(atlantian-boot),-(atlantian-ubi)' in s
assert 'date -u -s' in init
assert 'mount -t ext4 -o rw,noatime /dev/mmcblk0p2 /stage' not in init
assert 'size=650m' in s and 'size=400m' in init
assert 'overlay_mode=$(cat /run/atlantian/overlay-mode)' in s
assert 'external)' in s and 'internal)' in s
assert a.index('sha256sum -c /state/signed-internal-sums') < a.index('ubiformat /dev/mtd1')
assert a.index('check_nand\n') < a.index('ubiformat /dev/mtd1')
assert a.index('read_old_state\n') < a.index('ubiformat /dev/mtd1')
assert a.index('free_kib=$(awk') < a.index('ubiformat /dev/mtd1')
assert a.index('ubidetach -p /dev/mtd1') < a.index('ubiformat /dev/mtd1')
assert a.index('ubiformat /dev/mtd1') < a.index('flash_slot UBOOT_REDUND')
assert a.index('flash_slot UBOOT_REDUND') < a.index('flash_slot UBOOT_MAIN')
assert a.index('flash_slot UBOOT_MAIN') < a.index('flash_slot "SPL_$copy"')
assert 'bad boot PEBs unsupported' in a
assert 'bad UBI PEBs unsupported' in a
assert 'mount -t ext4 -o rw,noatime /dev/mmcblk0p2 /stage' in a
assert 'mount --bind /debs' in a and 'signed-public-sums' in a
assert 'oldmajor" != "$newmajor' in a
assert 'apt-sources-before-' in a
assert 'atlantian-major-upgrade-authorized' in a
print('RAM-only SD/NAND updater and cross-major fail-closed source contracts passed')
PY
