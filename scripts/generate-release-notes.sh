#!/usr/bin/env bash
set -euo pipefail

TAG=${1:-${GITHUB_REF_NAME:-}}
[[ -n "$TAG" ]] || { echo 'release tag required' >&2; exit 64; }
CURRENT=${TAG#v}
PREVIOUS=$(git tag --sort=-version:refname | awk -v t="$TAG" '$0 != t {print; exit}')
. config/release.env

{
  printf '# AtlANTian %s\n\n' "$CURRENT"
  printf '**AtlANTian GNU/Linux**, based on **Debian GNU/Linux %s**.\n\n' "$DEBIAN_CODENAME"

  if [[ -n "$PREVIOUS" ]]; then
    printf '## Changes since `%s`\n\n' "$PREVIOUS"
    git log --no-merges --format='- %s (%h)' "$PREVIOUS..$TAG" \
      | sed -E 's#^- (feat|feature): #- **Feature:** #; s#^- (fix|bugfix): #- **Fix:** #; s#^- (perf): #- **Performance:** #; s#^- (docs): #- **Documentation:** #; s#^- (refactor): #- **Refactor:** #; s#^- (ci|build|chore): #- **Build/CI:** #'
  else
    printf '%s\n' '- Initial AtlANTian release.'
  fi

  if [[ -z "$PREVIOUS" ]] || git diff --quiet "$PREVIOUS" "$TAG" -- debian-release.sha256 2>/dev/null; then
    :
  else
    printf '\n## Debian base\n\n'
    printf '%s\n' '- Debian repository metadata changed; the root filesystem was rebuilt from the current Debian release.'
    printf '%s\n' '- Official sources: [Debian Release files](https://deb.debian.org/debian/dists/trixie/Release), [Debian package tracker](https://tracker.debian.org/).'
  fi

  printf '\n## Artifacts\n\n'
  printf '%s\n' '- Full SD image and system-only payload are attached to this release.'
  printf '%s\n' '- System-only upgrades are performed with `atlantian-sysupgrade`; `/data` is preserved.'
} > release-notes.md
