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
# The old hardware RAM run failed before NAND erase: missing mountpoint in
# the sealed initramfs, even though the old rootfs carried the executable.
# Verify the full rebase dependency set is staged and preflighted before kexec.
tool_block = s.split('ram_tools=(\n', 1)[1].split('\n)', 1)[0]
for tool in ('mountpoint', 'rsync', 'chroot', 'sort', 'comm', 'awk',
             'sed', 'grep', 'mktemp', 'find', 'install'):
    assert tool in tool_block.split(), f'RAM rebase tool not staged: {tool}'
assert 'copy_elf "$(command -v "$tool")"' in s
assert 'chroot "$work/ramfs" /bin/sh -c' in s
# The staging tmpfs is nodev. An older preflight redirected to /dev/null
# *inside* chroot before the device node existed, creating a regular file.
# The subsequent mknod failed before kexec. Ensure both nodes are prepared
# first and all probe output goes through the host's /dev/null instead.
assert s.count('mknod -m 0666 "$work/ramfs/dev/null" c 1 3') == 1
assert s.count('mknod -m 0600 "$work/ramfs/dev/console" c 5 1') == 1
assert s.index('mknod -m 0666 "$work/ramfs/dev/null"') < s.index('chroot "$work/ramfs" /bin/sh -c')
assert s.index('mknod -m 0600 "$work/ramfs/dev/console"') < s.index('chroot "$work/ramfs" /bin/sh -c')
preflight = s.split("chroot \"$work/ramfs\" /bin/sh -c '", 1)[1].split("' >/dev/null || fail", 1)[0]
assert '>/dev/null' not in preflight, 'the chroot must not redirect into staging nodev /dev/null'
assert "' >/dev/null || fail 'sealed RAM initramfs userspace preflight failed'" in s
assert s.index('chroot "$work/ramfs" /bin/sh -c') < s.index('kexec --load')
assert s.index('mountpoint --help') < s.index('kexec --load')

# CLI UX: the old release checker printed its own line before the updater
# printed another; success also dumped nine checksum lines and bare curl bars.
assert 'atlantian-release-check --refresh >/dev/null' in s
assert "printf 'Update available: %s -> %s (%s)" in s
assert "Downloading %s: %s" in s
assert "fetch SHA256SUMS 'release checksums'" in s
assert "fetch SHA256SUMS.sigstore.json 'release signature'" in s
assert "fetch \"$archive\" 'NAND system bundle'" in s
assert 'fetch "$name" "$kind package"' in s
assert s.index("printf '\\nDownloading %s: %s") < s.index('curl -fL --retry 3 --progress-bar')
assert 'sha256sum -c SHA256SUMS >"$work/bundle-check.log" 2>&1' in s
assert 'Preparing isolated RAM maintenance system...' in s
assert 'SSH will disconnect' in s
# Machine-readable phase files stay stable, but humans see descriptive labels.
assert "log \"phase=$1\"" not in a
assert "old-state-captured) label='NAND: existing settings saved in RAM'" in a
assert "formatting-ubi) label='NAND: writing new filesystem (do not power off)'" in a
assert "installing-signed-platform) label='SD: installing authenticated AtlANTian packages'" in a
assert "printf 'phase=%s\\ntarget=%s\\n'" in a
assert 'sha256sum -c /state/signed-internal-sums >/run/upgrade/payload-check.log' in a

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
# An on-device SD test reached the signed-package step, but apt reported
# "Unsupported file" for all .debs: the bind mount existed in the RAM /run,
# not in the chroot-visible /stage/run following a non-recursive /run bind.
assert 'mount --bind /debs /stage/run/atlantian-debs' in a
assert 'mount --bind /debs /run/atlantian-debs' not in a
assert 'chroot /stage /usr/bin/test -s "/run/atlantian-debs/$name"' in a
assert a.index('chroot /stage /usr/bin/test -s "/run/atlantian-debs/$name"') < a.index('mark installing-signed-platform')
assert 'umount /stage/run/atlantian-debs /stage/run' in a
assert 'umount /run/atlantian-debs /stage/run' not in a
assert 'mount --bind /debs' in a and 'signed-public-sums' in a
assert 'oldmajor" != "$newmajor' in a
assert 'apt-sources-before-' in a
assert 'atlantian-major-upgrade-authorized' in a
# Exercise the exact staging fragment, not merely its shell syntax. A binary
# installed as ram-upgrade-busybox rejects --list unless its argv[0] is busybox.
import os, tempfile
from pathlib import Path
with tempfile.TemporaryDirectory() as temp:
    work = Path(temp)
    bb = work / 'ramfs/bin/busybox'
    bb.parent.mkdir(parents=True)
    bb.write_text('''#!/bin/sh
[ "${0##*/}" = busybox ] && [ "${1:-}" = --list ] || exit 127
[ "${STUB_APPLETS_EMPTY:-0}" = 1 ] && exit 0
printf 'sh\\nmount\\nmkdir\\ncat\\nsleep\\nreboot\\n'
''')
    bb.chmod(0o755)
    start = s.index('applets=$("$work/ramfs/bin/busybox" --list)')
    end = s.index('\n# Preserve the executable', start)
    snippet = s[start:end]
    script = 'fail() { printf "%s\\n" "$*" >&2; exit 9; }\n' + snippet
    env = dict(os.environ, work=str(work))
    subprocess.run(['bash', '-euo', 'pipefail', '-c', script], env=env, check=True)
    for applet in ('sh', 'mount', 'mkdir', 'cat', 'sleep', 'reboot'):
        link = work / 'ramfs/bin' / applet
        assert link.is_symlink() and link.resolve() == bb, f'missing applet {applet}'
    env['STUB_APPLETS_EMPTY'] = '1'
    assert subprocess.run(['bash', '-euo', 'pipefail', '-c', script], env=env,
                          capture_output=True).returncode != 0, 'empty --list was accepted'

print('RAM-only SD/NAND updater and cross-major fail-closed source contracts passed')
PY
