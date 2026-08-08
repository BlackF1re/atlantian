#!/usr/bin/env bash
# Build the complete SD first-stage boot chain from pinned upstream U-Boot.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
. config/u-boot.env

SRC=${UBOOT_SRC:-$ROOT/out/u-boot-src}
BUILD=${UBOOT_BUILD:-$ROOT/out/u-boot-build}
OUT=${UBOOT_OUT:-$ROOT/out/bootloader}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
CROSS_COMPILE=${CROSS_COMPILE:-arm-linux-gnueabihf-}

fail() { printf 'U-Boot build: %s\n' "$*" >&2; exit 1; }
[[ $ATLANTIAN_UBOOT_COMMIT =~ ^[0-9a-f]{40}$ ]] || fail 'ATLANTIAN_UBOOT_COMMIT must be a 40-character commit ID'
[[ $ATLANTIAN_UBOOT_DEFCONFIG == bitmain_antminer_s9_defconfig ]] || fail 'unexpected U-Boot board defconfig'
command -v "${CROSS_COMPILE}gcc" >/dev/null || fail "missing ${CROSS_COMPILE}gcc"

mkdir -p "$ROOT/out"
if [[ ! -d $SRC/.git ]]; then
  rm -rf "$SRC"
  git init -q "$SRC"
  git -C "$SRC" remote add origin "$ATLANTIAN_UBOOT_REPOSITORY"
else
  git -C "$SRC" remote set-url origin "$ATLANTIAN_UBOOT_REPOSITORY"
fi

git -C "$SRC" fetch --quiet --depth 1 origin "$ATLANTIAN_UBOOT_COMMIT"
git -C "$SRC" checkout --quiet --detach --force FETCH_HEAD
git -C "$SRC" clean -ffdqx
test "$(git -C "$SRC" rev-parse HEAD)" = "$ATLANTIAN_UBOOT_COMMIT" || fail 'checked-out U-Boot commit does not match the pin'

rm -rf "$BUILD"
mkdir -p "$BUILD"
make -C "$SRC" O="$BUILD" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" "$ATLANTIAN_UBOOT_DEFCONFIG"

# The upstream Antminer S9 target already has SPL/MMC support. Keep the payload
# name explicit so a future upstream default cannot silently change the FAT boot
# contract used by AtlANTian.
"$SRC/scripts/config" --file "$BUILD/.config" \
  --enable SPL \
  --enable SPL_MMC \
  --enable SPL_FS_FAT \
  --set-str SPL_FS_LOAD_PAYLOAD_NAME 'u-boot.img'
make -C "$SRC" O="$BUILD" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" olddefconfig

for contract in \
  'CONFIG_ARCH_ZYNQ=y' \
  'CONFIG_SPL=y' \
  'CONFIG_SPL_MMC=y' \
  'CONFIG_SPL_FS_FAT=y' \
  'CONFIG_SPL_FS_LOAD_PAYLOAD_NAME="u-boot.img"' \
  'CONFIG_DEFAULT_DEVICE_TREE="bitmain-antminer-s9"'; do
  grep -Fqx "$contract" "$BUILD/.config" || fail "missing generated config contract: $contract"
done

make -C "$SRC" O="$BUILD" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS"

test -s "$BUILD/spl/boot.bin" || fail 'SPL Zynq boot.bin was not produced'
test -s "$BUILD/u-boot.img" || fail 'u-boot.img was not produced'

rm -rf "$OUT"
mkdir -p "$OUT"
install -m 0644 "$BUILD/spl/boot.bin" "$OUT/BOOT.bin"
install -m 0644 "$BUILD/u-boot.img" "$OUT/u-boot.img"
printf '%s\n' "$ATLANTIAN_UBOOT_COMMIT" > "$OUT/u-boot.commit"
printf '%s\n' "$ATLANTIAN_UBOOT_VERSION" > "$OUT/u-boot.version"

printf 'Built U-Boot %s (%s) for CTRL_C41: %s + %s\n' \
  "$ATLANTIAN_UBOOT_VERSION" "$ATLANTIAN_UBOOT_COMMIT" "$OUT/BOOT.bin" "$OUT/u-boot.img"
