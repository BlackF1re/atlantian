#!/usr/bin/env bash
# Materialize the exact pinned U-Boot source tree shared by SD and NAND builds.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/config/u-boot.env"
SRC=${UBOOT_SRC:-$ROOT/out/u-boot-src}

fail() { printf 'U-Boot source: %s\n' "$*" >&2; exit 1; }
[[ $ATLANTIAN_UBOOT_COMMIT =~ ^[0-9a-f]{40}$ ]] || fail 'ATLANTIAN_UBOOT_COMMIT must be a 40-character commit ID'
command -v git >/dev/null || fail 'git is required'
mkdir -p "$(dirname "$SRC")"
if [[ ! -d $SRC/.git ]]; then
  rm -rf "$SRC"
  git init -q "$SRC"
  git -C "$SRC" remote add origin "$ATLANTIAN_UBOOT_REPOSITORY"
else
  git -C "$SRC" remote set-url origin "$ATLANTIAN_UBOOT_REPOSITORY"
fi
current=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)
if [[ $current == "$ATLANTIAN_UBOOT_COMMIT" ]]; then
  git -C "$SRC" reset --quiet --hard "$ATLANTIAN_UBOOT_COMMIT"
else
  git -C "$SRC" fetch --quiet --depth 1 origin "$ATLANTIAN_UBOOT_COMMIT"
  git -C "$SRC" checkout --quiet --detach --force FETCH_HEAD
fi
git -C "$SRC" clean -ffdqx
[[ $(git -C "$SRC" rev-parse HEAD) == "$ATLANTIAN_UBOOT_COMMIT" ]] || fail 'checked-out U-Boot commit does not match the pin'
printf 'Prepared U-Boot source %s at %s\n' "$ATLANTIAN_UBOOT_COMMIT" "$SRC"
