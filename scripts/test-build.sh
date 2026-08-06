#!/bin/sh
set -eu
IMAGE=${1:?image}; SUMS=${2:?sums}; DIR=$(dirname "$IMAGE")
[ -s "$IMAGE" ] && [ -s "$SUMS" ]; (cd "$DIR" && sha256sum -c "$(basename "$SUMS")")
set -- "$DIR"/*.deb; [ -s "$1" ] && [ $# -eq 3 ]
for f in "$@"; do dpkg-deb --info "$f" >/dev/null; done
echo 'release image and package checks passed'
