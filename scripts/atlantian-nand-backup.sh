#!/usr/bin/env bash
# Create a verified read-only forensic backup of the Antminer S9 raw NAND.
set -euo pipefail

usage() {
  cat <<'EOF_USAGE'
Usage: atlantian-nand-backup [--inspection-copy] [DIRECTORY]

The default recovery set contains a pigz-compressed raw+OOB physical dump.
--inspection-copy also creates a compressed padded main-area image for analysis;
it is not needed for restore.
EOF_USAGE
}
inspection=false
out_arg=
while [ $# -gt 0 ]; do
  case "$1" in
    --inspection-copy) inspection=true; shift ;;
    --help|-h) usage; exit 0 ;;
    --*) usage >&2; exit 64 ;;
    *) [ -z "$out_arg" ] || { usage >&2; exit 64; }; out_arg=$1; shift ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo 'run as root' >&2; exit 77; }
for cmd in nanddump pigz sha256sum awk date; do command -v "$cmd" >/dev/null 2>&1 || { echo "missing required command: $cmd" >&2; exit 69; }; done
[ -r /proc/mtd ] || { echo '/proc/mtd is unavailable' >&2; exit 69; }

line=$(awk -F: '$2 ~ /"pl35x-nand-controller"/ {print; n++} END {if (n != 1) exit 1}' /proc/mtd) || {
  echo 'expected exactly one MTD device named pl35x-nand-controller' >&2; cat /proc/mtd >&2; exit 65;
}
name=${line%%:*}; set -- $line; size_hex=$2; erase_hex=$3
case "$name" in mtd[0-9]*) ;; *) echo "unexpected MTD name: $name" >&2; exit 65 ;; esac
[ "$size_hex" = 10000000 ] || { echo "unexpected NAND size 0x$size_hex; expected 0x10000000" >&2; exit 65; }
[ "$erase_hex" = 00020000 ] || { echo "unexpected erase size 0x$erase_hex; expected 0x00020000" >&2; exit 65; }
dev=/dev/$name; [ -c "$dev" ] || { echo "missing character MTD device: $dev" >&2; exit 69; }

stamp=$(date -u +%Y%m%dT%H%M%SZ); out=${out_arg:-"$PWD/atlantian-nand-backup-$stamp"}
umask 077; mkdir -p "$out"
{
  echo 'AtlANTian Antminer S9 NAND backup'
  echo "created_utc=$stamp"; echo "device=$dev"; echo 'mtd_name=pl35x-nand-controller'
  echo "size_hex=$size_hex"; echo "erase_hex=$erase_hex"
  echo 'raw_oob_file=nand-raw-oob.bin.gz'; echo 'raw_oob_compression=gzip-pigz'; echo
  cat /proc/mtd; echo
  for attr in name size erasesize writesize oobsize ecc_strength ecc_step_size; do
    path="/sys/class/mtd/$name/$attr"; [ -r "$path" ] && printf '%s=%s\n' "$attr" "$(cat "$path")"
  done
} >"$out/NAND-INFO.txt"

raw_tmp="$out/.nand-raw-oob.bin.gz.tmp"
inspection_tmp="$out/.nand-main-padded.bin.gz.tmp"
cleanup() { rm -f "$raw_tmp" "$inspection_tmp"; }
trap cleanup EXIT HUP INT TERM

echo "Creating pigz-compressed raw+OOB forensic dump from $dev ..."
nanddump --quiet --noecc --oob --bb=dumpbad "$dev" | pigz -1 >"$raw_tmp"
pigz -t "$raw_tmp"
mv -f "$raw_tmp" "$out/nand-raw-oob.bin.gz"

if [ "$inspection" = true ]; then
  echo 'Creating optional pigz-compressed padded main-area inspection copy ...'
  if nanddump --quiet --noecc --omitoob --bb=padbad "$dev" | pigz -1 >"$inspection_tmp" && pigz -t "$inspection_tmp"; then
    mv -f "$inspection_tmp" "$out/nand-main-padded.bin.gz"
    printf 'inspection_copy=complete\n' >>"$out/NAND-INFO.txt"
  else
    rm -f "$inspection_tmp"
    printf 'inspection_copy=failed\n' >>"$out/NAND-INFO.txt"
    echo 'warning: optional inspection copy failed; raw+OOB recovery set is intact' >&2
  fi
else
  printf 'inspection_copy=not-requested\n' >>"$out/NAND-INFO.txt"
fi

(
  cd "$out"
  set -- NAND-INFO.txt nand-raw-oob.bin.gz
  [ ! -s nand-main-padded.bin.gz ] || set -- "$@" nand-main-padded.bin.gz
  sha256sum "$@" >SHA256SUMS
  sha256sum -c SHA256SUMS
  pigz -t nand-raw-oob.bin.gz
  [ ! -s nand-main-padded.bin.gz ] || pigz -t nand-main-padded.bin.gz
)
trap - EXIT HUP INT TERM
echo "NAND backup completed: $out"
echo 'Keep NAND-INFO.txt, nand-raw-oob.bin.gz and SHA256SUMS together.'
echo 'Do not use dd to restore a raw NAND device.'
