#!/usr/bin/env bash
# Only a real SD recovery filesystem is eligible for fresh NAND installation.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERIFY="$ROOT/scripts/atlantian-validate-recovery-sd.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
boot="$tmp/boot"; sdroot="$tmp/root"
mkdir -p "$boot" "$sdroot/usr/lib/atlantian" "$sdroot/usr/local/sbin" \
  "$sdroot/etc/profile.d" "$sdroot/etc/systemd/system/multi-user.target.wants"
for file in BOOT.bin u-boot.img atlantian-A.itb atlantian-B.itb atlantian-boot-abi; do
  printf 'fixture\n' >"$boot/$file"
done
printf 'NAND maintenance atln-stage.scr supported\n' >"$boot/boot.scr"
printf 'sd\n' >"$sdroot/usr/lib/atlantian/storage-edition"
printf '13.1.0-alpha.63\n' >"$sdroot/usr/lib/atlantian/version"
for tool in atlantian-nand-install atlantian-nand-firstboot; do
  printf '#!/bin/sh\n' >"$sdroot/usr/local/sbin/$tool"
  chmod +x "$sdroot/usr/local/sbin/$tool"
done
printf 'atlantian-nand-firstboot\n' >"$sdroot/etc/profile.d/20-atlantian-nand-firstboot.sh"
ln -s /usr/lib/systemd/system/atlantian-nand-auto-resume.service \
  "$sdroot/etc/systemd/system/multi-user.target.wants/atlantian-nand-auto-resume.service"
bash "$VERIFY" "$boot" "$sdroot" || { echo 'complete recovery layout was rejected' >&2; exit 1; }
for missing in BOOT.bin atlantian-A.itb atlantian-B.itb boot.scr; do
  mv "$boot/$missing" "$boot/$missing.saved"
  if bash "$VERIFY" "$boot" "$sdroot" >/dev/null 2>&1; then
    echo "missing recovery boot file was accepted: $missing" >&2
    exit 1
  fi
  mv "$boot/$missing.saved" "$boot/$missing"
done
mv "$sdroot/usr/local/sbin/atlantian-nand-install" "$tmp/installer.saved"
if bash "$VERIFY" "$boot" "$sdroot" >/dev/null 2>&1; then
  echo 'recovery SD lacking maintenance tool was accepted' >&2
  exit 1
fi
mv "$tmp/installer.saved" "$sdroot/usr/local/sbin/atlantian-nand-install"
printf 'ordinary overlay contents\n' >"$tmp/overlay-only"
if bash "$VERIFY" "$boot" "$tmp" >/dev/null 2>&1; then
  echo 'overlay-only SD root was accepted' >&2
  exit 1
fi
echo 'bootable recovery layout checks passed'
