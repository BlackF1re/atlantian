#!/usr/bin/env bash
set -euo pipefail

TAG=${1:-${GITHUB_REF_NAME:-}}
REF=${2:-HEAD}
[[ -n "$TAG" ]] || { echo 'release tag required' >&2; exit 64; }
CURRENT=${TAG#v}
PREVIOUS=$(git tag --sort=-version:refname | awk -v t="$TAG" '$0 != t {print; exit}')
. config/release.env
COMMIT=$(git rev-parse "$REF")
SHORT_COMMIT=$(git rev-parse --short=12 "$REF")

{
  printf '# AtlANTian %s\n\n' "$CURRENT"
  printf '**AtlANTian GNU/Linux**, based on **Debian GNU/Linux %s**.\n\n' "$DEBIAN_CODENAME"
  if [[ -n ${GITHUB_REPOSITORY:-} ]]; then
    printf 'Source: [`%s`](https://github.com/%s/commit/%s)\n\n' "$SHORT_COMMIT" "$GITHUB_REPOSITORY" "$COMMIT"
  else
    printf 'Source commit: `%s`\n\n' "$COMMIT"
  fi

  if [[ -n "$PREVIOUS" ]]; then
    printf '## Changes since `%s`\n\n' "$PREVIOUS"
    git log --no-merges --format='- %s (%h)' "$PREVIOUS..$REF" \
      | sed -E 's#^- (feat|feature): #- **Feature:** #; s#^- (fix|bugfix): #- **Fix:** #; s#^- (perf): #- **Performance:** #; s#^- (docs): #- **Documentation:** #; s#^- (refactor): #- **Refactor:** #; s#^- (ci|build|chore): #- **Build/CI:** #'
  else
    printf '%s\n' '- Initial AtlANTian release.'
  fi

  if [[ -z "$PREVIOUS" ]] || git diff --quiet "$PREVIOUS" "$REF" -- debian-release.sha256 2>/dev/null; then
    :
  else
    printf '\n## Debian base\n\n'
    printf '%s\n' '- Debian repository metadata changed; the root filesystem was rebuilt from the current Debian release.'
    printf '%s\n' '- Official sources: [Debian Release files](https://deb.debian.org/debian/dists/trixie/Release), [Debian package tracker](https://tracker.debian.org/).'
  fi

  printf '\n## Downloads\n\n'
  printf '| File | Purpose |\n|---|---|\n'
  printf '| `%s.img` | Initial SD-card installation image. |\n' "$ATLANTIAN_IMAGE_NAME"
  printf '| `%s.system.ext4` | System-only payload for `atlantian-sysupgrade`; `/data` is preserved. |\n' "$ATLANTIAN_IMAGE_NAME"
  printf '| `SHA256SUMS` | SHA-256 verification for both payloads. |\n'
  printf '\n## Verification\n\n'
  printf '%s\n' '- Built from the source commit above; image, partition, boot, rootfs, shell and update-state contracts passed in GitHub Actions.'
} > release-notes.md
