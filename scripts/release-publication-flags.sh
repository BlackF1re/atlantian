#!/usr/bin/env bash
# GitHub presentation is independent of SemVer update-channel ordering.
set -euo pipefail
version=${1:?usage: release-publication-flags.sh VERSION}
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-([a-z]+)\.([1-9][0-9]*))?$ ]]; then
  echo "invalid AtlANTian release version: $version" >&2
  exit 64
fi

case ${BASH_REMATCH[2]:-} in
  ''|beta) printf '%s\n' --latest ;;
  alpha|rc) printf '%s\n' --prerelease ;;
  *) echo "unsupported release channel in $version" >&2; exit 64 ;;
esac
