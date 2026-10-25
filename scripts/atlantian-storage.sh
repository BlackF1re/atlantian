#!/bin/sh
# Manage AtlANTian NAND writable storage. The preferred external upper lives in
# a hidden directory on the ordinary AtlANTian recovery SD root partition, so
# adopting the card no longer destroys the bootable recovery/install system.
set -eu

RUNTIME=/run/atlantian
INTERNAL=$RUNTIME/internal-overlay
STATE=/var/lib/atlantian/nand
TARGET=/dev/mmcblk0
BOOT_PART=/dev/mmcblk0p1
ROOT_PART=/dev/mmcblk0p2
EXTROOT_DIR=.atlantian-extroot

usage() {
    cat <<'EOF_USAGE'
Usage:
  atlantian-storage status
  atlantian-storage is-installer-card
  atlantian-storage is-recovery-card
  atlantian-storage adopt [ /dev/mmcblk0 ]

`is-recovery-card` checks whether the card can boot manual recovery tools.
An adopted card must match the NAND pairing token.

`adopt` keeps the recovery microSD bootable and uses free space on its
ext4 ROOT partition for the external writable layer. Without the card, NAND
boots using its internal writable layer.
EOF_USAGE
}

require_nand() {
    [ -r "$RUNTIME/storage-edition" ] && [ "$(cat "$RUNTIME/storage-edition")" = nand ] || {
        echo 'this command is available only while actually booted from AtlANTian NAND' >&2
        exit 65
    }
    [ -d "$INTERNAL/upper" ] && [ -d "$INTERNAL/work" ] || {
        echo 'internal NAND overlay runtime mount is unavailable' >&2
        exit 69
    }
}

installer_card_id() {
    [ -r "$STATE/installer-id" ] || return 1
    [ -b "$BOOT_PART" ] || return 1
    tmp=$(mktemp -d /run/atlantian-card.XXXXXX)
    if mount -t vfat -o ro "$BOOT_PART" "$tmp" 2>/dev/null; then
        if [ -r "$tmp/atln-install.id" ] && [ "$(cat "$tmp/atln-install.id")" = "$(cat "$STATE/installer-id")" ]; then
            umount "$tmp"; rmdir "$tmp"; return 0
        fi
        umount "$tmp" || true
    fi
    rmdir "$tmp"
    return 1
}

# Validate a suitable SD manual-recovery environment, not merely the identity
# of the card that happened to install NAND. A card currently providing the
# authenticated external upper is suitable when its adoption token matches the
# internal NAND marker and it still contains a bootable recovery OS.
recovery_card() {
    require_nand
    [ -b "$BOOT_PART" ] && [ -b "$ROOT_PART" ] || {
        echo 'Manual NAND recovery requires both partitions of a bootable AtlANTian SD.' >&2
        return 1
    }

    tmp=$(mktemp -d /run/atlantian-recovery-card.XXXXXX) || return 1
    mkdir -p "$tmp/boot" "$tmp/root"
    boot_mounted=false
    root_mounted=false
    root="$tmp/root"
    if mount -t vfat -o ro "$BOOT_PART" "$tmp/boot"; then
        boot_mounted=true
    else
        echo 'Cannot read the recovery SD boot partition.' >&2
        rmdir "$tmp/boot" "$tmp/root" "$tmp"
        return 1
    fi
    if mountpoint -q "$RUNTIME/external-overlay" &&
       [ "$(findmnt -n -o SOURCE "$RUNTIME/external-overlay" 2>/dev/null || true)" = "$ROOT_PART" ]; then
        root="$RUNTIME/external-overlay"
    elif mount -t ext4 -o ro "$ROOT_PART" "$tmp/root"; then
        root_mounted=true
    else
        echo 'Cannot read the recovery SD root partition.' >&2
        umount "$tmp/boot"
        rmdir "$tmp/boot" "$tmp/root" "$tmp"
        return 1
    fi

    result=0
    /usr/local/sbin/atlantian-validate-recovery-sd "$tmp/boot" "$root" || result=1
    if [ "$result" -eq 0 ]; then
        if [ -s "$INTERNAL/.extroot-token" ]; then
            # Preserve the currently adopted upper; NEVER accept a different
            # card's writable state merely because it has a bootable SD image.
            [ -s "$root/$EXTROOT_DIR/token" ] &&
            [ "$(cat "$root/$EXTROOT_DIR/token")" = "$(cat "$INTERNAL/.extroot-token")" ] &&
            [ -d "$root/$EXTROOT_DIR/upper" ] &&
            [ -d "$root/$EXTROOT_DIR/work" ] || {
                echo 'External OverlayFS adoption token/layout does not match the running NAND.' >&2
                result=1
            }
        else
            installer_card_id || {
                echo 'Card is not paired with NAND and no adopted external upper token exists.' >&2
                result=1
            }
        fi
    fi
    if [ "$root_mounted" = true ]; then umount "$tmp/root" || result=1; fi
    if [ "$boot_mounted" = true ]; then umount "$tmp/boot" || result=1; fi
    rmdir "$tmp/boot" "$tmp/root" "$tmp" || result=1
    return "$result"
}

status() {
    require_nand
    mode=$(cat "$RUNTIME/overlay-mode" 2>/dev/null || printf unknown)
    layout=$(cat "$RUNTIME/external-overlay-layout" 2>/dev/null || printf none)
    echo 'Storage edition: NAND'
    echo "Active writable layer: $mode"
    if [ "$mode" = external ] && mountpoint -q "$RUNTIME/external-overlay"; then
        echo "External layout: $layout"
        df -h "$RUNTIME/external-overlay" | tail -n1
    else
        df -h "$INTERNAL" | tail -n1
    fi
    if [ -s "$INTERNAL/.extroot-token" ]; then
        echo 'External overlay: adopted'
        if [ -b "$ROOT_PART" ] || [ -b "$BOOT_PART" ]; then
            echo 'microSD: present'
        else
            echo 'microSD: absent (internal fallback active)'
        fi
    else
        echo 'External overlay: not adopted'
    fi
    if recovery_card >/dev/null 2>&1; then
        echo 'Recovery microSD: bootable for manual recovery'
    elif installer_card_id; then
        echo 'Recovery microSD: paired; bootability not verified'
    fi
}

adopt() {
    require_nand
    [ "$(id -u)" -eq 0 ] || { echo 'run as root' >&2; exit 77; }
    dev=${1:-$TARGET}
    [ "$dev" = "$TARGET" ] || {
        echo "for safety, extroot adoption accepts only the microSD device $TARGET" >&2
        exit 64
    }
    [ -b "$ROOT_PART" ] || { echo "AtlANTian ROOT partition is not present at $ROOT_PART" >&2; exit 69; }
    case "$(findmnt -n -o SOURCE / 2>/dev/null || true)" in /dev/mmcblk0*) echo 'refusing to modify the current root device' >&2; exit 65 ;; esac
    installer_card_id || {
        echo 'refusing to adopt an unrecognized card: insert the same unified AtlANTian microSD used for this NAND installation' >&2
        exit 65
    }

    echo
    echo 'AtlANTian external writable-layer setup'
    echo '-----------------------------------------'
    echo "Recovery card: $TARGET"
    echo "Writable storage: $ROOT_PART/$EXTROOT_DIR"
    echo
    echo 'The recovery SD partitions and files are preserved. AtlANTian will create a'
    echo 'private upper/work directory on its ext4 ROOT partition and copy the current'
    echo 'internal NAND writable state there. The card remains bootable for maintenance.'
    echo
    printf 'Type ADOPT to enable this recovery card as the external writable layer: '
    IFS= read -r answer
    [ "$answer" = ADOPT ] || { echo 'Cancelled; microSD was not modified.'; exit 0; }

    tmp=$(mktemp -d /run/atlantian-adopt.XXXXXX)
    trap 'umount "$tmp" 2>/dev/null || true; rmdir "$tmp" 2>/dev/null || true' EXIT INT TERM HUP
    mount -t ext4 -o rw,noatime "$ROOT_PART" "$tmp"
    root="$tmp/$EXTROOT_DIR"
    if [ -e "$root/token" ] || [ -d "$root/upper" ] || [ -d "$root/work" ]; then
        umount "$tmp"; rmdir "$tmp"; trap - EXIT INT TERM HUP
        echo 'an external AtlANTian writable layer already exists on this card; refusing to overwrite it' >&2
        exit 65
    fi
    mkdir -p "$root/upper" "$root/work"
    echo 'Copying the current writable state to the recovery microSD...'
    rsync -aHAX --numeric-ids --delete "$INTERNAL/upper/" "$root/upper/"

    token=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
    [ ${#token} -eq 64 ] || { echo 'failed to create extroot adoption token' >&2; exit 1; }
    printf '%s\n' "$token" >"$root/token"
    printf '%s\n' "$token" >"$INTERNAL/.extroot-token.new"
    sync
    mv -f "$INTERNAL/.extroot-token.new" "$INTERNAL/.extroot-token"
    sync
    umount "$tmp"; rmdir "$tmp"; trap - EXIT INT TERM HUP

    rm -f "$STATE/offer-extroot"
    echo
    echo 'microSD adoption completed and verified; the recovery system was preserved.'
    echo 'Rebooting so the external writable layer becomes active.'
    sync
    systemctl reboot
}

cmd=${1:-status}
case "$cmd" in
    status) [ $# -eq 1 ] || { usage >&2; exit 64; }; status ;;
    is-installer-card) [ $# -eq 1 ] || { usage >&2; exit 64; }; require_nand; installer_card_id ;;
    is-recovery-card) [ $# -eq 1 ] || { usage >&2; exit 64; }; recovery_card ;;
    adopt) [ $# -le 2 ] || { usage >&2; exit 64; }; adopt "${2:-$TARGET}" ;;
    --help|-h|help) usage ;;
    *) usage >&2; exit 64 ;;
esac
