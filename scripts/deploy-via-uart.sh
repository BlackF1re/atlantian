#!/usr/bin/env bash
# Safely replace the active SD image through U-Boot RAM recovery.
#
# Unlike an in-place raw write, the root filesystem is never mounted while the
# whole SD is being written.  This requires the board's UART to be connected to
# the build host as /dev/ttyUSB0.
set -euo pipefail

[[ $# -ge 1 && $# -le 2 ]] || { echo 'usage: deploy-via-uart.sh <image> [board-ip]' >&2; exit 64; }
IMAGE=$(readlink -f "$1")
BOARD=${2:-$(<"$(cd "$(dirname "$0")/.." && pwd)/state/board.address")}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TTY=${ATLANTIAN_UART:-/dev/ttyUSB0}
USER=${ATLANTIAN_USER:-root}
PORT=${ATLANTIAN_HTTP_PORT:-18082}
# A verified 768-MiB stream to a low-power Zynq can take several minutes.
# This is a total post-write boot deadline; the RAM-copy stage has its own
# longer bounded deadline below.
TIMEOUT=${ATLANTIAN_BOOT_TIMEOUT:-720}
[[ -f $IMAGE && -c $TTY ]] || { echo 'image or UART is unavailable' >&2; exit 2; }

# A previous failed recovery server may still own the default port.  Pick a
# private free port rather than treating that harmless stale process as a
# deployment failure.
if [[ -z ${ATLANTIAN_HTTP_PORT:-} ]]; then
  for candidate in $(seq 18082 18099); do
    if ! ss -ltn "sport = :$candidate" | grep -q LISTEN; then
      PORT=$candidate
      break
    fi
  done
fi
ss -ltn "sport = :$PORT" | grep -q LISTEN && { echo "no free HTTP port in recovery range" >&2; exit 4; }

SHA=$(sha256sum "$IMAGE" | awk '{print $1}')
SIZE=$(stat -c %s "$IMAGE")
(( SIZE > 0 && SIZE % 1048576 == 0 )) || { echo 'image must be MiB-aligned for direct-I/O recovery' >&2; exit 2; }
BLOCKS=$((SIZE / 1048576))
NAME=$(basename "$IMAGE")
DIR=$(dirname "$IMAGE")
LOCAL_IP=$(ip route get "$BOARD" | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}')
[[ -n $LOCAL_IP ]] || { echo 'cannot determine LAN address' >&2; exit 3; }

python3 -m http.server "$PORT" --bind "$LOCAL_IP" --directory "$DIR" >/tmp/atlantian-recovery-http.log 2>&1 &
HTTP_PID=$!
cleanup(){ kill "$HTTP_PID" 2>/dev/null || true; wait "$HTTP_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 1
kill -0 "$HTTP_PID" || { cat /tmp/atlantian-recovery-http.log >&2; exit 4; }

# The Python controller gives every state a bounded timeout.  A failed flash
# remains in RAM recovery instead of rebooting into an unknown SD state.
export ATL_UART="$TTY" ATL_BOARD="$BOARD" ATL_USER="$USER" ATL_URL="http://$LOCAL_IP:$PORT/$NAME" ATL_SHA="$SHA" ATL_BLOCKS="$BLOCKS" ATL_TIMEOUT="$TIMEOUT" ATL_UBOOT_TIMEOUT="${ATLANTIAN_UBOOT_TIMEOUT:-180}"
python3 - <<'PY'
import os,re,serial,subprocess,sys,threading,time
tty=os.environ['ATL_UART']; board=os.environ['ATL_BOARD']; user=os.environ['ATL_USER']
url=os.environ['ATL_URL']; sha=os.environ['ATL_SHA']; blocks=os.environ['ATL_BLOCKS']; timeout=int(os.environ['ATL_TIMEOUT'])
uboot_timeout=int(os.environ['ATL_UBOOT_TIMEOUT'])
force_uboot=os.environ.get('ATLANTIAN_FORCE_UBOOT') == '1'
log=[]
s=serial.Serial(tty,115200,timeout=.15)
s.reset_input_buffer()
# U-Boot prompt varies between the vendor and upstream configurations
# (``antminer>``, ``Zynq>``, sometimes simply ``=>``).  Accept a prompt only
# at the beginning of a console line; do not bake a board-brand string into
# the deployment protocol.
uboot_prompt=r'(?m)^(?:(?:[A-Za-z0-9_. -]*>)|=>)[ ]*$'
def tx(line):
    s.write((line+'\r').encode()); s.flush(); log.append('>> '+line)
def read_until(pattern,limit):
    end=time.monotonic()+limit; data=''
    rx=re.compile(pattern,re.S)
    while time.monotonic()<end:
        chunk=s.read(4096).decode('utf-8','replace')
        if chunk:
            data+=chunk; log.append(chunk)
            if rx.search(data): return data
    raise RuntimeError('timeout waiting for '+pattern)
def run_uboot(command,limit=15):
    tx(command)
    return read_until(uboot_prompt,limit)
try:
    # Open and arm UART *before* Linux reboots.  U-Boot gives only a very short
    # abort window; the vendor U-Boot accepts a literal space more reliably
    # than CR.  A space is harmless at both a U-Boot prompt and Linux getty.
    stop_spam=threading.Event()
    def spam_cr():
        while not stop_spam.is_set():
            try:
                s.write(b' '); s.flush()
            except serial.SerialException:
                return
            time.sleep(.08)
    spam=threading.Thread(target=spam_cr,daemon=True)
    spam.start()
    if force_uboot:
        # Emergency/migration path for an image that cannot accept SSH yet.
        # Operator power-cycles the board; CR spam catches U-Boot, then the
        # normal RAM-recovery protocol takes over.  It never writes a mounted
        # SD filesystem.
        try:
            out=read_until(uboot_prompt,uboot_timeout)
        finally:
            stop_spam.set(); spam.join(timeout=2)
    else:
        # During the root-only migration the currently running board may still be
        # the older `paul` image.  Probe first; only then issue reboot.  All later
        # deployments use root and never depend on sudo.
        probe=['ssh','-o','BatchMode=yes','-o','ConnectTimeout=5',f'{user}@{board}','true']
        if subprocess.run(probe, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            reboot_cmd=['ssh','-o','BatchMode=yes','-o','ConnectTimeout=5',f'{user}@{board}','/usr/sbin/reboot']
        else:
            legacy=['ssh','-o','BatchMode=yes','-o','ConnectTimeout=5',f'paul@{board}','true']
            if subprocess.run(legacy, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
                raise RuntimeError('neither root nor legacy paul SSH access is available')
            reboot_cmd=['ssh','-o','BatchMode=yes','-o','ConnectTimeout=5',f'paul@{board}','sudo -n /usr/sbin/reboot']
        legacy_password=os.environ.get('ATLANTIAN_LEGACY_SUDO_PASSWORD')
        if reboot_cmd[-1].startswith('sudo -n') and legacy_password:
            reboot_cmd[-1]='sudo -S -p "" /usr/sbin/reboot'
            reboot=subprocess.Popen(reboot_cmd, stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True)
            reboot.stdin.write(legacy_password+'\n'); reboot.stdin.flush(); reboot.stdin.close()
        else:
            reboot=subprocess.Popen(reboot_cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            out=read_until(uboot_prompt,60)
        finally:
            stop_spam.set(); spam.join(timeout=2)
        try:
            reboot.wait(timeout=30)
        except subprocess.TimeoutExpired:
            reboot.terminate()
        if reboot.returncode not in (0,255):
            raise RuntimeError('reboot request failed')
    run_uboot('setenv bootargs mem=496M console=ttyPS0,115200n8 root=/dev/ram0 rdinit=/init atlantian.flash_url='+url+' atlantian.sha256='+sha+' atlantian.blocks='+blocks)
    run_uboot('fatload mmc 0:1 0x03000000 uImage',30)
    run_uboot('fatload mmc 0:1 0x02000000 uInitrd',30)
    run_uboot('fatload mmc 0:1 0x02A00000 devicetree.dtb',30)
    tx('bootm 0x03000000 0x02000000 0x02A00000')
    # New recovery images reset through the Zynq hardware watchdog; normal
    # Linux reboot is retained only for compatibility with the original one.
    out=read_until(r'(verified; (?:rebooting|forcing PS-watchdog reset)|FATAL:)',720)
    if not re.search(r'verified; (?:rebooting|forcing PS-watchdog reset)', out):
        # Compatibility with the first recovery image: its udhcpc call obtains
        # a lease but does not install it.  It drops to a RAM shell instead of
        # touching the SD; give that shell a temporary address and repeat the
        # verified stream.  Subsequent images carry udhcpc.script and never
        # take this branch.
        if 'Network is unreachable' not in out:
            raise RuntimeError('RAM recovery reported failure')
        tx('ip addr add '+board+'/24 dev eth0 || ip addr add '+board+'/24 dev end0')
        tx('ip route add default via 192.168.2.1')
        tx('wget -q -O - '+url+' | tee /dev/mmcblk0 | sha256sum')
        out=read_until(sha+r'  -',720)
        # The legacy recovery image lacks the DHCP hook.  Its ordinary reboot
        # can hang after a successful raw write, so take the same PS-watchdog
        # path as the current recovery image instead of using reboot -f.
        tx('sync; /bin/busybox watchdog -F -t 200ms -T 3 /dev/watchdog & p=$!; sleep 1; kill -STOP $p; sleep 10')
finally:
    s.close()
    open('/tmp/atlantian-uart-deploy.log','w').write(''.join(log))
PY

deadline=$((SECONDS + TIMEOUT))
while ((SECONDS < deadline)); do
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$USER@$BOARD" \
      'findmnt -no SOURCE / | grep -qx /dev/mmcblk0p2 && systemctl is-active --quiet ssh'; then
    echo "DEPLOY PASS: $BOARD booted verified image $SHA"
    exit 0
  fi
  sleep 3
done
echo 'DEPLOY FAIL: image was written, but SSH post-boot check timed out' >&2
exit 1
