#!/usr/bin/env bash
# Exercise the on-device Sigstore verification boundary without network access.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERIFY="$ROOT/scripts/atlantian-verify-release.sh"
TRUST="$ROOT/config/release-trust.env"
fail() { printf 'release auth contract: %s\n' "$*" >&2; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf 'deadbeef  payload\n' >"$tmp/SHA256SUMS"
printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}\n' >"$tmp/SHA256SUMS.sigstore.json"
cat >"$tmp/cosign" <<'EOF_COSIGN'
#!/bin/sh
printf '%s\n' "$*" >"$ATLANTIAN_TEST_COSIGN_ARGS"
exit "${ATLANTIAN_TEST_COSIGN_RC:-0}"
EOF_COSIGN
chmod +x "$tmp/cosign"

args="$tmp/args"
ATLANTIAN_RELEASE_TRUST_CONFIG="$TRUST" ATLANTIAN_COSIGN_BIN="$tmp/cosign" ATLANTIAN_TEST_COSIGN_ARGS="$args" \
  "$VERIFY" "$tmp/SHA256SUMS" "$tmp/SHA256SUMS.sigstore.json" >/dev/null
. "$TRUST"
grep -Fq 'verify-blob' "$args" || fail 'Cosign verify-blob was not requested'
grep -Fq "$tmp/SHA256SUMS" "$args" || fail 'checksum manifest was not bound to verification'
grep -Fq -- "--bundle $tmp/SHA256SUMS.sigstore.json" "$args" || fail 'Sigstore bundle was not supplied'
grep -Fq -- "--certificate-identity $ATLANTIAN_RELEASE_SIGNING_IDENTITY" "$args" || fail 'signer identity policy was not supplied'
grep -Fq -- "--certificate-oidc-issuer $ATLANTIAN_RELEASE_SIGNING_ISSUER" "$args" || fail 'OIDC issuer policy was not supplied'
[[ $(ATLANTIAN_RELEASE_TRUST_CONFIG="$TRUST" ATLANTIAN_COSIGN_BIN="$tmp/cosign" "$VERIFY" --cache-bytes-needed) == 0 ]] || fail 'explicit verifier override still reserves a download'

if ATLANTIAN_RELEASE_TRUST_CONFIG="$TRUST" ATLANTIAN_COSIGN_BIN="$tmp/cosign" ATLANTIAN_TEST_COSIGN_ARGS="$args" ATLANTIAN_TEST_COSIGN_RC=1 \
  "$VERIFY" "$tmp/SHA256SUMS" "$tmp/SHA256SUMS.sigstore.json" >/dev/null 2>&1; then
  fail 'failed Sigstore verification was accepted'
fi

[[ $ATLANTIAN_COSIGN_VERSION == 3.1.3 ]] || fail 'unexpected pinned Cosign version'
[[ $ATLANTIAN_COSIGN_ARM_SHA256 == 3275e61b43a45aa56a6242b49475d8a01874a07469c08fc32d027ba554996e4c ]] || fail 'unexpected ARM verifier digest'
[[ $ATLANTIAN_COSIGN_AMD64_SHA256 == 4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71 ]] || fail 'unexpected CI signer verifier digest'
[[ $ATLANTIAN_RELEASE_SIGNING_IDENTITY == 'https://github.com/BlackF1re/atlantian/.github/workflows/release-sign.yml@refs/heads/main' ]] || fail 'unexpected release signer identity'
[[ $ATLANTIAN_RELEASE_SIGNING_ISSUER == 'https://token.actions.githubusercontent.com' ]] || fail 'unexpected release signer issuer'

echo 'pinned Cosign and exact keyless release signer verification contracts passed'
