#!/usr/bin/env bash
# Select the newest reachable Debian release for AtlANTian, freeze exact
# repository metadata in snapshot.debian.org, and update release.env atomically.
set -euo pipefail

PROJECT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PROJECT"
. config/release.env

ARCH=${DEBIAN_ARCH:-armhf}
CURRENT_CODENAME=$DEBIAN_CODENAME
CURRENT_MAJOR=$DEBIAN_MAJOR
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail() { printf 'Debian refresh: %s\n' "$*" >&2; exit 1; }
field() { awk -F': ' -v key="$2" '$1 == key { print $2; exit }' "$1"; }
has_arch() {
  local arches
  arches=$(field "$1" Architectures)
  [[ " $arches " == *" $ARCH "* ]]
}
major_of_release() {
  local version
  version=$(field "$1" Version)
  [[ $version =~ ^[0-9]+([.][0-9]+)*$ ]] || return 1
  printf '%s\n' "${version%%.*}"
}
fetch() {
  curl -fsSL --retry 3 --connect-timeout 20 "$1" -o "$2"
}
emit() {
  printf '%s=%s\n' "$1" "$2"
  if [[ -n ${GITHUB_OUTPUT:-} ]]; then
    printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
  fi
}

[[ $CURRENT_CODENAME =~ ^[a-z0-9][a-z0-9-]*$ ]] || fail 'configured Debian codename is invalid'
[[ $CURRENT_MAJOR =~ ^[0-9]+$ ]] || fail 'configured Debian major is invalid'
[[ $ARCH =~ ^[a-z0-9][a-z0-9-]*$ ]] || fail 'configured Debian architecture is invalid'

# Debian exposes stable aliases. Looking at oldstable/oldoldstable as well makes
# the workflow recover after a long period in which scheduled Actions did not
# run: promotion still happens one Debian major at a time, never by skipping a
# supported release.
TARGET_CODENAME=$CURRENT_CODENAME
TARGET_MAJOR=$CURRENT_MAJOR
PROMOTED=false
NEXT_MAJOR=$((CURRENT_MAJOR + 1))
for alias in stable oldstable oldoldstable; do
  alias_file="$WORK/$alias"
  fetch "https://deb.debian.org/debian/dists/$alias/Release" "$alias_file" 2>/dev/null || continue
  candidate_major=$(major_of_release "$alias_file" 2>/dev/null || true)
  candidate_codename=$(field "$alias_file" Codename)
  [[ $candidate_major == "$NEXT_MAJOR" ]] || continue
  [[ $candidate_codename =~ ^[a-z0-9][a-z0-9-]*$ ]] || continue
  if ! has_arch "$alias_file"; then
    echo "Debian $candidate_major ($candidate_codename) does not publish $ARCH; keeping $CURRENT_CODENAME."
    continue
  fi
  TARGET_MAJOR=$candidate_major
  TARGET_CODENAME=$candidate_codename
  PROMOTED=true
  break
done

main_suite=$TARGET_CODENAME
updates_suite=${TARGET_CODENAME}-updates
security_suite=${TARGET_CODENAME}-security
main_live="$WORK/live-main"
updates_live="$WORK/live-updates"
security_live="$WORK/live-security"

# During a new Debian release, aliases can move a little before every archive
# and security endpoint is ready. A promotion therefore waits quietly and
# retries on the next scheduled run instead of publishing a partial base.
if ! fetch "https://deb.debian.org/debian/dists/$main_suite/Release" "$main_live" || \
   ! fetch "https://deb.debian.org/debian/dists/$updates_suite/Release" "$updates_live" || \
   ! fetch "https://security.debian.org/debian-security/dists/$security_suite/Release" "$security_live"; then
  if [[ $PROMOTED == true ]]; then
    echo "Debian $TARGET_MAJOR ($TARGET_CODENAME) is not fully published yet; retrying later."
    emit changed false
    exit 0
  fi
  fail "cannot fetch the configured Debian $CURRENT_CODENAME repositories"
fi

[[ $(field "$main_live" Codename) == "$main_suite" ]] || fail 'main Release codename mismatch'
[[ $(major_of_release "$main_live") == "$TARGET_MAJOR" ]] || fail 'main Release version mismatch'
[[ $(field "$updates_live" Codename) == "$updates_suite" ]] || fail 'updates Release codename mismatch'
[[ $(field "$security_live" Codename) == "$security_suite" ]] || fail 'security Release codename mismatch'
for file in "$main_live" "$updates_live" "$security_live"; do
  has_arch "$file" || {
    if [[ $PROMOTED == true ]]; then
      echo "Debian $TARGET_MAJOR ($TARGET_CODENAME) is missing $ARCH in one required suite; keeping $CURRENT_CODENAME."
      emit changed false
      exit 0
    fi
    fail "configured Debian suite stopped publishing $ARCH"
  }
done

for tuple in \
  "https://deb.debian.org/debian/dists/$main_suite/main/binary-$ARCH/Release $WORK/arch-main" \
  "https://deb.debian.org/debian/dists/$updates_suite/main/binary-$ARCH/Release $WORK/arch-updates" \
  "https://security.debian.org/debian-security/dists/$security_suite/main/binary-$ARCH/Release $WORK/arch-security"; do
  set -- $tuple
  if ! fetch "$1" "$2"; then
    if [[ $PROMOTED == true ]]; then
      echo "Debian $TARGET_MAJOR ($TARGET_CODENAME) has no complete binary-$ARCH archive yet; retrying later."
      emit changed false
      exit 0
    fi
    fail "binary-$ARCH archive is unavailable for configured Debian"
  fi
done

current_main_sha=$(sha256sum "$main_live" | awk '{print $1}')
current_updates_sha=$(sha256sum "$updates_live" | awk '{print $1}')
current_security_sha=$(sha256sum "$security_live" | awk '{print $1}')
old_main_sha=$(tr -d '\r\n' < debian-release.sha256)
old_updates_sha=$(tr -d '\r\n' < debian-updates-release.sha256)
old_security_sha=$(tr -d '\r\n' < debian-security-release.sha256)
if [[ $PROMOTED == false && \
      $current_main_sha == "$old_main_sha" && \
      $current_updates_sha == "$old_updates_sha" && \
      $current_security_sha == "$old_security_sha" ]]; then
  emit changed false
  exit 0
fi

# Never build a published image from moving mirrors. Wait for Snapshot to
# contain the exact Release metadata that was just observed live.
timestamps=$(curl -fsSL --retry 3 --connect-timeout 20 https://snapshot.debian.org/mr/timestamp/)
main_timestamp=$(printf '%s' "$timestamps" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["debian"][-1])')
security_timestamp=$(printf '%s' "$timestamps" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["debian-security"][-1])')
snapshot_url="https://snapshot.debian.org/archive/debian/${main_timestamp}"
security_snapshot_url="https://snapshot.debian.org/archive/debian-security/${security_timestamp}"

fetch "$snapshot_url/dists/$main_suite/Release" "$WORK/snapshot-main" || { emit changed false; exit 0; }
fetch "$snapshot_url/dists/$updates_suite/Release" "$WORK/snapshot-updates" || { emit changed false; exit 0; }
fetch "$security_snapshot_url/dists/$security_suite/Release" "$WORK/snapshot-security" || { emit changed false; exit 0; }

snapshot_main_sha=$(sha256sum "$WORK/snapshot-main" | awk '{print $1}')
snapshot_updates_sha=$(sha256sum "$WORK/snapshot-updates" | awk '{print $1}')
snapshot_security_sha=$(sha256sum "$WORK/snapshot-security" | awk '{print $1}')
if [[ $snapshot_main_sha != "$current_main_sha" || \
      $snapshot_updates_sha != "$current_updates_sha" || \
      $snapshot_security_sha != "$current_security_sha" ]]; then
  echo 'Debian Snapshot has not caught up with the observed repositories; retrying on the next run.'
  emit changed false
  exit 0
fi

printf '%s\n' "$snapshot_main_sha" > debian-release.sha256
printf '%s\n' "$snapshot_updates_sha" > debian-updates-release.sha256
printf '%s\n' "$snapshot_security_sha" > debian-security-release.sha256
cat > config/debian-snapshot.env <<EOF_SNAPSHOT
# Reproducible Debian rootfs input. Updated only after Snapshot contains the
# exact live repository metadata selected by refresh-debian-base.sh.
DEBIAN_SNAPSHOT_TIMESTAMP=$main_timestamp
DEBIAN_SNAPSHOT_MIRROR=$snapshot_url
DEBIAN_SECURITY_SNAPSHOT_MIRROR=$security_snapshot_url
EOF_SNAPSHOT

if [[ $PROMOTED == true ]]; then
  next_build=1
else
  next_build=$((ATLANTIAN_BUILD + 1))
fi
sed -i -E "s/^DEBIAN_CODENAME=.*/DEBIAN_CODENAME=$TARGET_CODENAME/" config/release.env
sed -i -E "s/^DEBIAN_MAJOR=.*/DEBIAN_MAJOR=$TARGET_MAJOR/" config/release.env
sed -i -E "s/^ATLANTIAN_BUILD=.*/ATLANTIAN_BUILD=$next_build/" config/release.env

emit changed true
emit promoted "$PROMOTED"
emit codename "$TARGET_CODENAME"
emit major "$TARGET_MAJOR"
emit build "$next_build"
echo "Frozen Debian $TARGET_MAJOR ($TARGET_CODENAME) / $ARCH at $main_timestamp."
