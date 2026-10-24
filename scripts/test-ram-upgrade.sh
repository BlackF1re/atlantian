#!/usr/bin/env bash
# Non-destructive source contract tests: never touch real NAND or SD.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "RAM update contract: $*" >&2; exit 1; }
bash -n scripts/atlantian-ram-upgrade.sh
sh -n scripts/atlantian-ram-upgrade-apply.sh
stage=scripts/atlantian-ram-upgrade.sh
apply=scripts/atlantian-ram-upgrade-apply.sh
grep -Fq 'atlantian-verify-release' "$stage" || fail 'signature verification missing'
grep -Fq 'sha256sum -c SHA256SUMS' "$stage" || fail 'NAND payload checksums missing'
grep -Fq 'systemctl kexec' "$stage" || fail 'kexec handoff missing'
grep -Fq 'mtdparts=pl35x-nand-controller:16m(atlantian-boot),-(atlantian-ubi)' "$stage" || fail 'MTD split missing'
grep -Fq 'udhcpc -i eth0' "$stage" || fail 'RAM DHCP missing'
grep -Fq 'dropbear -B -p 22' "$stage" || fail 'RAM recovery SSH missing'
grep -Fq 'capture-mounted' "$stage" || fail 'live OverlayFS capture missing'
grep -Fq '/dev/mmcblk0p2' "$stage" || fail 'ext4 staging missing'
! grep -Fq 'is-upgrade-card' "$stage" || fail 'old recovery card dependency remains'
python3 - "$stage" "$apply" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a=Path(sys.argv[2]).read_text()
assert s.index('atlantian-verify-release') < s.index('kexec --load')
assert s.index('sha256sum -c SHA256SUMS') < s.index('kexec --load')
assert s.index('capture-mounted') < s.index('kexec --load')
assert s.index('IN-PROGRESS') < s.index('kexec --load')
assert a.index('check_nand\n') < a.index('ubiformat /dev/mtd1')
assert a.index('sha256sum -c /state/signed-internal-sums') < a.index('ubiformat /dev/mtd1')
assert a.index('ubidetach -p /dev/mtd1') < a.index('flash_slot UBOOT_REDUND')
assert a.index('flash_slot UBOOT_REDUND') < a.index('flash_slot UBOOT_MAIN')
assert a.index('flash_slot UBOOT_MAIN') < a.index('flash_slot "SPL_$copy"')
assert 'bad boot PEBs unsupported' in a
assert 'bad UBI PEBs unsupported' in a
assert 'chroot /stage /usr/bin/env DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get' in a
assert a.index('mark refreshing-sd-repositories') < a.index('mark installing-sd-packages')
assert 'previous-upper' in a and 'previous-work' in a
init=s.split("<<'INIT'\n",1)[1].split("\nINIT\n",1)[0]
import subprocess
subprocess.run(['sh','-n'],input=init,text=True,check=True)
PY
echo 'unified RAM SD/NAND update source contracts passed'
