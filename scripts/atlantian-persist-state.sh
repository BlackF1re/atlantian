#!/bin/sh
# Install the writable, update-surviving layer.  p2 is intentionally replaced
# by sysupgrade; p3 is never written by it.  /etc is an overlay so new release
# defaults remain visible, while administrator changes stay in p3.  /root and
# /home and /var/local are bind-mounted persistent trees for keys and user
# files.  Package databases deliberately remain part of the replaceable
# system, so an update never combines a new rootfs with an old dpkg database.
set -eu

data=/data
state=$data/system/atlantian/persist

mountpoint -q "$data" || {
    echo 'AtlANTian persistence: /data is not mounted' >&2
    exit 1
}

install -d -m 0755 "$state/etc.upper" "$state/etc.work" "$state/root" "$state/home" "$state/var-local"
# APT indices and downloaded packages are deliberately transient, but too
# large for the fixed-size immutable p2 partition.  They belong on p3, unlike
# dpkg's database, which remains in the release rootfs by design.
install -d -m 0755 "$data/system/atlantian/apt/lists/partial" \
    "$data/system/atlantian/apt/archives/partial"

seed_tree() {
    source=$1 target=$2 marker=$3
    [ -e "$marker" ] && return 0
    # cp -a preserves dotfiles and ownership while keeping the initial image
    # defaults.  Later boots never overwrite the administrator's state.
    cp -a "$source"/. "$target"/
    : >"$marker"
}

seed_tree /root "$state/root" "$state/.root-seeded"
seed_tree /home "$state/home" "$state/.home-seeded"
seed_tree /var/local "$state/var-local" "$state/.var-local-seeded"

if [ "$(findmnt -n -o FSTYPE /etc 2>/dev/null || true)" != overlay ]; then
    mount -t overlay overlay -o "lowerdir=/etc,upperdir=$state/etc.upper,workdir=$state/etc.work" /etc
fi

for tree in root home var-local; do
    [ "$tree" = var-local ] && target=/var/local || target=/$tree
    source=$state/$tree
    if [ "$(findmnt -n -o SOURCE "$target" 2>/dev/null || true)" != "$source" ]; then
        mount --bind "$source" "$target"
    fi
done
