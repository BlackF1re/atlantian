#!/bin/sh
# Verify an AtlANTian public checksum manifest against the pinned Sigstore signer.
set -eu

TRUST=${ATLANTIAN_RELEASE_TRUST_CONFIG:-/usr/lib/atlantian/release-trust.env}
CACHE=${ATLANTIAN_COSIGN_CACHE_DIR:-/var/lib/atlantian/release-trust}

fatal() { echo "atlantian-verify-release: $*" >&2; exit 1; }
[ -r "$TRUST" ] || fatal "missing release trust config: $TRUST"
# shellcheck disable=SC1090
. "$TRUST"

for var in ATLANTIAN_COSIGN_VERSION ATLANTIAN_COSIGN_ARM_URL ATLANTIAN_COSIGN_ARM_SHA256 \
  ATLANTIAN_COSIGN_ARM_SIZE ATLANTIAN_RELEASE_SIGNING_IDENTITY ATLANTIAN_RELEASE_SIGNING_ISSUER; do
  eval "value=\${$var:-}"
  [ -n "$value" ] || fatal "missing trust value: $var"
done
case "$ATLANTIAN_COSIGN_ARM_SHA256" in *[!0-9a-f]*|'') fatal 'invalid pinned Cosign SHA-256' ;; esac
[ "${#ATLANTIAN_COSIGN_ARM_SHA256}" -eq 64 ] || fatal 'invalid pinned Cosign SHA-256 length'
case "$ATLANTIAN_COSIGN_ARM_SIZE" in ''|*[!0-9]*) fatal 'invalid pinned Cosign size' ;; esac

cosign_path() { printf '%s/cosign-%s-linux-arm\n' "$CACHE" "$ATLANTIAN_COSIGN_VERSION"; }
valid_cosign() {
  file=$1
  [ -f "$file" ] && [ ! -L "$file" ] && [ -x "$file" ] || return 1
  [ "$(sha256sum "$file" | awk '{print $1}')" = "$ATLANTIAN_COSIGN_ARM_SHA256" ]
}

if [ "${1:-}" = --cache-bytes-needed ]; then
  if [ -n "${ATLANTIAN_COSIGN_BIN:-}" ] || valid_cosign "$(cosign_path)"; then printf '0\n'; else printf '%s\n' "$ATLANTIAN_COSIGN_ARM_SIZE"; fi
  exit 0
fi

[ "$#" -eq 2 ] || fatal 'usage: atlantian-verify-release SHA256SUMS SIGNATURE_BUNDLE'
SUMS=$1
BUNDLE=$2
[ -s "$SUMS" ] || fatal "missing checksum manifest: $SUMS"
[ -s "$BUNDLE" ] || fatal "missing Sigstore bundle: $BUNDLE"
command -v sha256sum >/dev/null 2>&1 || fatal 'sha256sum is required'

if [ -n "${ATLANTIAN_COSIGN_BIN:-}" ]; then
  COSIGN=$ATLANTIAN_COSIGN_BIN
  [ -x "$COSIGN" ] || fatal "test/override Cosign is not executable: $COSIGN"
else
  command -v curl >/dev/null 2>&1 || fatal 'curl is required to fetch the pinned verifier'
  install -d -m 0755 "$CACHE"
  COSIGN=$(cosign_path)
  if ! valid_cosign "$COSIGN"; then
    rm -f "$COSIGN"
    tmp=$(mktemp "$CACHE/.cosign.XXXXXX")
    trap 'rm -f "$tmp"' EXIT HUP INT TERM
    curl -fL --retry 3 --connect-timeout 20 --progress-bar -o "$tmp" "$ATLANTIAN_COSIGN_ARM_URL"
    [ "$(stat -c %s "$tmp")" = "$ATLANTIAN_COSIGN_ARM_SIZE" ] || fatal 'pinned Cosign download size mismatch'
    [ "$(sha256sum "$tmp" | awk '{print $1}')" = "$ATLANTIAN_COSIGN_ARM_SHA256" ] || fatal 'pinned Cosign download checksum mismatch'
    chmod 0755 "$tmp"
    mv -f "$tmp" "$COSIGN"
    trap - EXIT HUP INT TERM
  fi
fi

"$COSIGN" verify-blob "$SUMS" \
  --bundle "$BUNDLE" \
  --certificate-identity "$ATLANTIAN_RELEASE_SIGNING_IDENTITY" \
  --certificate-oidc-issuer "$ATLANTIAN_RELEASE_SIGNING_ISSUER" >/dev/null \
  || fatal 'release checksum signature verification failed'
printf 'Authenticated AtlANTian release manifest: %s\n' "$(sha256sum "$SUMS" | awk '{print $1}')"
