# NAND architecture

AtlANTian's NAND edition targets the stock Micron `MT29F2G08ABAEAWP` 256 MiB raw NAND used on the supported Antminer S9 control board. Raw-flash code is intentionally board/chip-specific; a part is not considered compatible merely because its capacity and page geometry match.

## Device identity, geometry and ECC

Repository policy is defined by `config/nand-layout.env`. The supported operator entry point checks the probed chip identity first, and the destructive implementation verifies the live MTD geometry/ECC again before erase/program work.

Supported device contract:

| Property | Required value |
|---|---:|
| Part | Micron `MT29F2G08ABAEAWP` |
| Manufacturer ID | `0x2c` |
| Device ID | `0xda` |
| Total size | 256 MiB |
| Eraseblock | 128 KiB |
| Page | 2048 bytes |
| OOB | 64 bytes |
| ECC engine | Micron on-die |
| ECC algorithm | BCH |
| ECC strength / step | 4 bits / 512 bytes |

`atlantian-nand-install` is the supported guard around the destructive implementation. It refuses to proceed unless the kernel NAND probe log contains the exact `2c:da` identity. The NAND SPL accepts the same ID pair; source-contract tests keep the supported installer/SPL policy aligned. Geometry-compatible replacement parts therefore require an explicit boot-chain/policy change and fresh hardware validation.

The guard is not a privilege boundary against `root`: `/usr/local/sbin/atlantian-nand-install.real` remains executable as the underlying implementation, and root can access MTD tooling directly. The `.real` implementation rechecks board, release payload, geometry and ECC, but does not repeat the wrapper's dmesg-based exact-ID test. Invoking it directly is outside the supported installation path and can bypass that early identity safety check.

The Zynq controller's 1-bit ECC is not the active data path for this stock part. Linux, U-Boot and the NAND boot policy use the NAND's Micron on-die BCH capability. Factory bad-block markers must be preserved. Recovery-grade backup reads therefore retain OOB bytes instead of treating the NAND like a block device.

## Raw boot and UBI layout

The first 16 MiB are a raw boot region because BootROM/SPL/U-Boot need fixed-address payloads. The remaining 240 MiB form the Linux UBI region.

| Region | Offset | Reserved size | Purpose |
|---|---:|---:|---|
| SPL area | 0 MiB | 1 MiB | four redundant SPL copies |
| U-Boot primary | 1 MiB | 1 MiB | primary U-Boot image |
| U-Boot redundant | 2 MiB | 1 MiB | fallback U-Boot image |
| Kernel | 3 MiB | 9 MiB | fixed logical kernel slot |
| Initramfs | 12 MiB | 3 MiB | fixed logical initramfs slot |
| DTB | 15 MiB | 1 MiB | fixed logical device-tree slot |
| UBI | 16 MiB | 240 MiB | immutable root + writable overlay |

Raw slot reservations deliberately include slack for factory-bad eraseblocks. U-Boot NAND operations skip bad blocks while preserving the logical byte stream, and the generated boot script reads the exact release-specific payload length rather than blindly consuming a complete slot.

For the configured 128 KiB PEB / 2 KiB minimum-I/O geometry, UBI leaves 126,976 bytes per logical eraseblock after EC/VID headers. A release is rejected unless it can still provide at least 32 MiB of writable overlay capacity under the repository's pessimistic CI bad-PEB reserve.

## UBI root

The Linux data region is formatted as UBI only after raw boot has been programmed and read-back verified.

- `rootfs`: static UBI volume containing a Zstd-compressed SquashFS immutable base (256 KiB SquashFS blocks, configured Zstd level 15).
- `overlay`: dynamic UBI volume formatted as LZO-compressed UBIFS using the remaining space.

Early `/init` attaches UBI, exposes the static root through `ubiblock`, mounts SquashFS read-only, mounts the UBIFS upper and assembles OverlayFS before `switch_root`.

The initramfs uses a build-only static BusyBox binary. `busybox-static` is extracted during the build and purged before either normal runtime rootfs is cloned; it is not retained in the running system merely for early NAND boot.

## Recovery microSD

The ordinary SD image is also the NAND recovery/maintenance medium. It contains the release-matched NAND bundle under `/usr/lib/atlantian/nand`.

A NAND install records an installer/card identity. Later NAND base updates require that paired recovery SD. If it is inserted while NAND is running, it can also be explicitly adopted as the writable OverlayFS upper. Adoption keeps both SD partitions bootable and stores the external upper under the ext4 ROOT partition; token matching prevents a random ext4 card from silently becoming system state. Without the adopted card, boot falls back to the internal UBIFS upper.

## Install transaction

The supported destructive path is deliberately split:

1. The public guard verifies exact NAND identity before handing off to the destructive implementation.
2. Linux verifies board, release payload, geometry and ECC, then creates/reuses a verified raw+OOB backup.
3. Linux stages the raw boot payload on the recovery SD.
4. SD U-Boot programs and read-back verifies raw boot.
5. Only after the U-Boot verification marker exists does SD Linux replace the UBI region.
6. The new static root is read back through `ubiblock` and its AtlANTian release identity is checked.
7. A fresh writable upper is created (or preserved state is rebased during an upgrade).
8. The board is handed back to NAND boot only after the complete transaction verifies.

This ordering keeps the old UBI untouched until raw boot is known-good and keeps the board on recovery SD until the new UBI is known-good. It does not make the raw boot update power-loss atomic; those physical fault cases remain part of [HARDWARE-VALIDATION.md](HARDWARE-VALIDATION.md).

## Same-major base upgrade

NAND does not install the SD-oriented `atlantian-kernel` package into the live immutable base. `atlantian-sysupgrade` downloads the target NAND bundle plus authenticated public checksum manifest/signature to the paired recovery SD. After booting that SD, the prepared maintenance transaction:

- verifies the prepared bundle path, authenticated checksums and release identity;
- mounts the current immutable lower and active upper;
- captures the explicitly supported persistent deltas, extra manual package intent and holds;
- requires the target to stay within the current Debian major;
- stages the same verified raw-boot transaction used by installation;
- rebuilds UBI with the target SquashFS;
- restores selected state against the new lower rather than copying the previous upper wholesale.

A Debian-major NAND transition requires a clean reinstall from the target-generation SD image. It is intentionally not advertised as a compatible NAND `sysupgrade`.

## Backup

`atlantian-nand-backup` is read-only and creates the recovery-critical raw+OOB dump by default. `--inspection-copy` adds a second padded main-area dump for offline analysis only.

Never restore raw NAND with `dd`. Raw NAND restore must respect OOB, factory bad blocks, ECC and the board's boot layout. AtlANTian currently provides the verified backup path, not a generic automated raw-NAND restore command.

User-facing installation steps are in [INSTALLATION.md](INSTALLATION.md); exact persistence/rebase rules are in [PERSISTENCE.md](PERSISTENCE.md); update authentication is in [UPGRADING.md](UPGRADING.md).
