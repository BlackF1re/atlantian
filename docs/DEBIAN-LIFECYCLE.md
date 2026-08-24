# Debian lifecycle

This document owns AtlANTian's Debian-generation, factory Snapshot and runtime APT policy. Operator update steps are in [UPGRADING.md](UPGRADING.md); automation is in [PIPELINE.md](PIPELINE.md).

## Factory versus runtime

AtlANTian deliberately separates reproducible image construction from maintenance of an installed Debian system.

| Factory build | Installed board |
|---|---|
| exact Debian Snapshot timestamp and Release-file checksums | live repositories for the installed codename |
| reproducible package baseline | normal `apt update`, `apt upgrade`, `apt install` |
| `armhf` availability is validated | moving `stable` aliases are not used |
| snapshot recorded in release metadata | ordinary Debian updates do not change AtlANTian release identity |

A factory Snapshot refresh therefore does not need to publish an image every day. Installed boards continue receiving normal Debian updates from the configured codename while Snapshot changes accumulate under the release batching policy.

APT indexes live in a bounded 96 MiB tmpfs. Downloaded package archives use storage-backed APT staging and are configured not to be retained after installation.

## Supported generation

`config/release.env` defines the Debian major and codename. Automation verifies that the configured main, updates and security suites still publish `armhf`.

If the runner's `debootstrap` package does not yet contain a script named after the configured codename, the build uses Debian's generic bootstrap script while still targeting the exact configured codename and pinned Snapshot.

If Debian stops publishing the required architecture, AtlANTian fails closed instead of silently selecting another architecture or generation.

## Snapshot refresh

The daily [Upstream Base Watch](PIPELINE.md#upstream-base-watch):

1. reads the current live Debian Release metadata for the configured suites;
2. compares it with the stored checksums;
3. waits for Debian Snapshot to contain those exact metadata bytes;
4. freezes the new Snapshot timestamp/checksums;
5. validates the complete changed input set;
6. merges the combined upstream transaction through protected `main`.

Debian-only changes join the normal five-release-input batch. If the same transaction also contains an accepted Linux or U-Boot update, the combined transaction becomes immediately release-eligible.

## Debian-major transition

Availability of Debian `N+1` may be reported automatically, but automation never edits the configured Debian major/codename merely because a new stable release exists.

A transition is explicit because it changes the AtlANTian release line and compatibility boundary.

- **SD:** `atlantian-sysupgrade` supports only `N → N+1`, with source backup, resumable state and controlled replacement of AtlANTian-managed APT sources.
- **NAND:** cross-major immutable-base rebase is not supported. Boot the target-generation SD image and perform a clean NAND installation.

The updater never skips Debian generations or performs a Debian-major downgrade.

## Board-specific packages

The custom AtlANTian kernel, DT, boot payload and platform policy are release-controlled rather than replaced by a generic Debian kernel package. This keeps the board-specific boot/update contract testable as one product.

Ordinary Debian application/library packages remain ordinary Debian state. See [PERSISTENCE.md](PERSISTENCE.md) for how that state is represented on SD and NAND.
