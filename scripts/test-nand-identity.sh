#!/usr/bin/env bash
# Verify that both installed NAND entry points carry the exact chip policy and
# that the destructive implementation rejects a mismatched probe identity.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
fail() { printf 'NAND identity test: %s\n' "$*" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/root"
scripts/install-nand-tools.sh "$tmp/root" sd

for installer in \
  "$tmp/root/usr/local/sbin/atlantian-nand-install" \
  "$tmp/root/usr/local/sbin/atlantian-nand-install.real"; do
  grep -Fq 'EXPECTED_MANUFACTURER=0x2c' "$installer" || fail "manufacturer ID was not resolved in $installer"
  grep -Fq 'EXPECTED_DEVICE=0xda' "$installer" || fail "device ID was not resolved in $installer"
  ! grep -Eq '@ATLANTIAN_NAND_(MANUFACTURER|DEVICE)_ID@' "$installer" || fail "unresolved identity placeholder survived in $installer"
done

printf '%s\n' 'nand: Manufacturer ID: 0x2c, Chip ID: 0xda (Micron)' >"$tmp/good-dmesg"
printf '%s\n' 'nand: Manufacturer ID: 0xec, Chip ID: 0xda (other)' >"$tmp/bad-dmesg"
cat >"$tmp/check-real.sh" <<'EOF_CHECK'
#!/usr/bin/env bash
set -euo pipefail
real=$1
probe=$2
export ATLANTIAN_NAND_INSTALL_LIBRARY_ONLY=1
. "$real"
export ATLANTIAN_NAND_DMESG_FILE=$probe
verify_nand_identity
EOF_CHECK
chmod +x "$tmp/check-real.sh"

real="$tmp/root/usr/local/sbin/atlantian-nand-install.real"
"$tmp/check-real.sh" "$real" "$tmp/good-dmesg" || fail 'destructive installer rejected supported 2c:da NAND'
if "$tmp/check-real.sh" "$real" "$tmp/bad-dmesg" >/dev/null 2>&1; then
  fail 'destructive installer accepted a non-2c:da NAND identity'
fi

echo 'public and direct destructive NAND identity guards passed'
