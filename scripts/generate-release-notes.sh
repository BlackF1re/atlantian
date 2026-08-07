#!/usr/bin/env bash
set -euo pipefail

TAG=${1:-${GITHUB_REF_NAME:-}}
REF=${2:-HEAD}
[[ -n "$TAG" ]] || { echo 'release tag required' >&2; exit 64; }
CURRENT=${TAG#v}
PREVIOUS=$(git describe --tags --abbrev=0 "$REF^" 2>/dev/null || true)
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
      | sed -E \
        -e 's#^- (feat|feature)(\([^)]*\))?!?: #- **Feature:** #' \
        -e 's#^- (fix|bugfix)(\([^)]*\))?!?: #- **Fix:** #' \
        -e 's#^- perf(\([^)]*\))?!?: #- **Performance:** #' \
        -e 's#^- docs(\([^)]*\))?!?: #- **Documentation:** #' \
        -e 's#^- refactor(\([^)]*\))?!?: #- **Refactor:** #' \
        -e 's#^- (ci|build|chore)(\([^)]*\))?!?: #- **Build/CI:** #'
  else
    printf '%s\n' '- Initial AtlANTian release.'
  fi

  if [[ -n "$PREVIOUS" ]] && ! git diff --quiet "$PREVIOUS" "$REF" -- debian-release.sha256 2>/dev/null; then
    printf '\n## Debian base\n\n'
    . config/debian-snapshot.env
    printf '%s\n' "- Debian repository metadata changed; the root filesystem was rebuilt from snapshot \`${DEBIAN_SNAPSHOT_TIMESTAMP}\`."
    printf '%s\n' "- Source archive: [Debian Snapshot](${DEBIAN_SNAPSHOT_MIRROR}/dists/${DEBIAN_CODENAME}/Release); resolved package versions are attached to this release."
  fi

  printf '\n## Downloads\n\n'
  printf '| File | Purpose |\n|---|---|\n'
  printf '| `%s.img` | Initial SD-card installation image. |\n' "$ATLANTIAN_IMAGE_NAME"
  printf '| `atlantian-platform_*.deb` | Board policy, tools and release configuration. |\n'
  printf '| `atlantian-kernel_*.deb` | Kernel, device tree and modules. |\n'
  printf '| `atlantian-release_*.deb` | Exact release meta-package. |\n'
  printf '| `SHA256SUMS` | SHA-256 verification for image and packages. |\n'
  printf '\n## Verification\n\n'
  printf '%s\n' '- Built from the source commit above; image, partition, rootfs, shell and update contracts passed in GitHub Actions.'
  printf '%s\n' '- GitHub Actions publishes a Sigstore-backed build-provenance attestation for the checksummed release artifacts.'
} > release-notes.md
