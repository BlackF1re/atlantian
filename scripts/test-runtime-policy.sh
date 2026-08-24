#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
fail() { printf 'runtime policy contract: %s\n' "$*" >&2; exit 1; }
require() { grep -Fq -- "$1" "$2" || fail "$2 is missing: $1"; }
reject() { ! grep -Fq -- "$1" "$2" || fail "$2 must not contain: $1"; }

APT_CONF=config/apt-volatile.conf
MOUNT=systemd/run-apt.mount
TMPFILES=systemd/atlantian-apt-tmpfiles.conf
INSTALLER=scripts/install-runtime-policy.sh
POSTINST=packaging/platform/postinst

require 'Dir::State::Lists "/run/apt/lists/";' "$APT_CONF"
require 'APT::Keep-Downloaded-Packages "false";' "$APT_CONF"
reject 'Dir::Cache::archives "/run/apt/archives/";' "$APT_CONF"
require 'Dir::Cache::pkgcache "";' "$APT_CONF"
require 'Acquire::Languages "none";' "$APT_CONF"
require 'Where=/run/apt' "$MOUNT"
require 'Type=tmpfs' "$MOUNT"
require 'size=96M' "$MOUNT"
reject 'size=50%' "$MOUNT"
require 'd /run/apt/lists/partial 0700 _apt root -' "$TMPFILES"
require '10atlantian-volatile' "$INSTALLER"
require 'local-fs.target.wants/run-apt.mount' "$INSTALLER"
require 'systemctl enable --now run-apt.mount' "$POSTINST"
require 'systemd-tmpfiles --create /usr/lib/tmpfiles.d/atlantian-apt.conf' "$POSTINST"

echo 'bounded volatile APT index policy passed'
