#!/usr/bin/env bash
# Fast contracts for retained download/update metrics without coupling to prose layout.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
fail() { printf 'release metrics contract: %s\n' "$*" >&2; exit 1; }
require() { grep -Fq -- "$1" "$2" || fail "$2 is missing: $1"; }
reject() { ! grep -Fq -- "$1" "$2" || fail "$2 contains forbidden text: $1"; }

workflow=.github/workflows/build-release.yml
metrics=.github/workflows/image-download-metrics.yml
build=scripts/build-incremental.sh
upgrade=scripts/test-release-upgrade.sh
checker=scripts/atlantian-release-check.sh
sd=scripts/atlantian-sysupgrade-sd.sh
nand=scripts/atlantian-sysupgrade-nand.sh
notes=scripts/generate-release-notes.sh
readme=README.md
pipeline=docs/PIPELINE.md

# Public image remains versioned/compressed; raw image remains inside the sealed Actions artifact.
require 'artifacts/current/*.img.xz' "$workflow"
require '"artifacts/current/$ATLANTIAN_IMAGE_NAME.img.xz"' "$workflow"
require 'COMPRESSED_IMAGE=${COMPRESSED_IMAGE:-$SD_IMAGE.xz}' "$build"
require 'xz -T0 -6 --check=crc64 -c "$SD_IMAGE"' "$build"
require 'decoded_sha=$(xz -dc "$COMPRESSED_IMAGE" | sha256sum' "$build"
require 'retention-days: 90' "$workflow"

block=$(mktemp); trap 'rm -f "$block"' EXIT
awk '/release_assets=\(/ {capture=1} capture {print} capture && /^[[:space:]]*\)[[:space:]]*$/ {exit}' "$workflow" >"$block"
for item in \
  '"artifacts/current/$ATLANTIAN_IMAGE_NAME.img.xz"' \
  'artifacts/current/atlantian-kernel_*.deb' \
  '"artifacts/current/atlantian-nand-$ATLANTIAN_VERSION.tar.zst"' \
  'artifacts/current/atlantian-platform_*.deb' \
  'artifacts/current/atlantian-release_*.deb' \
  'artifacts/current/atlantian-update.json' \
  'artifacts/current/RELEASE-METADATA.json' \
  'artifacts/current/SHA256SUMS'; do require "$item" "$block"; done
reject '$ATLANTIAN_IMAGE_NAME.img"' "$block"

# CI upgrade testing must use the private SHA-sealed Actions artifact, not public downloads.
require 'gh run download "$SOURCE_RUN_ID"' "$upgrade"
require 'atlantian-verified-${source_sha}' "$upgrade"
reject 'browser_download_url' "$upgrade"

# Anonymous system-update accounting stays best-effort in both storage backends.
require 'atlantian-update.json' "$checker"
require 'record_update_download' "$sd"
require 'record_update_download' "$nand"
require 'atlantian-update.json' scripts/prepare-public-release.sh
require 'blackf1re.github.io%2Fatlantian%2Fimage-downloads.json' "$readme"
require 'query=%24.imageDownloads&label=image%20downloads' "$readme"
require 'query=%24.systemUpdates&label=system%20updates' "$readme"

# Initial per-asset badges read GitHub directly so release publication cannot cache a
# missing Pages key. The metrics workflow still owns aggregate data and post-deploy backfill.
require 'contents: write' "$metrics"
require 'workflow_run:' "$metrics"
require 'workflows: [Build & Release]' "$metrics"
require '"schemaVersion": 3' "$metrics"
require '"assetDownloads"' "$metrics"
require '"assetIndex"' "$metrics"
require 'Backfill artifact download columns' "$metrics"
require 'gh api --method PATCH "repos/$GITHUB_REPOSITORY/releases/$release_id"' "$metrics"
require '| Artifact | Size | Downloads |' "$notes"
require 'img.shields.io/github/downloads/' "$notes"
require 'displayAssetName' "$notes"
reject '$.assetDownloads.' "$notes"
require 'per-asset' "$pipeline"
require 'Downloads' "$pipeline"

echo 'versioned XZ image, anonymous update accounting and retained download metrics contracts passed'
