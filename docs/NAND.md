# NAND architecture

> **Update path (2026-10):** System upgrades use the authenticated RAM kexec maintainer in both SD and NAND modes. No boot-source jumper change and no bootable recovery microSD are required for routine upgrades. The entire verified update and the preserved user-state snapshot reside in RAM; internal-only NAND installations require no SD card. The SD-U-Boot raw-stage procedure documented below applies **only to fresh NAND installation**, not to `atlantian-sysupgrade`. See [UPGRADING.md](UPGRADING.md).


AtlANTian's NAND edition targets the stock Micron `MT29F2G08ABAEAWP` 256 MiB raw NAND used on the supported Antminer S9 control board. Raw-flash code is intentionally board/chip-specific; a part is not considered compatible merely because its capacity and page geometry match.

## Device identity, geometry and ECC

Repository policy is defined by `config/nand-layout.env`. The public operator entry point checks the probed chip identity first, and the destructive implementation repeats that identity check before verifying the live MTD geometry/ECC and proceeding toward erase/program work.

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

`atlantian-nand-install` refuses to proceed unless the kernel NAND probe log contains the exact `2c:da` identity. `/usr/local/sbin/atlantian-nand-install.real` independently repeats the same check, so direct invocation of the destructive implementation no longer skips chip identity validation. The NAND SPL accepts the same ID pair; source-contract tests keep the wrapper, implementation and SPL policy aligned. Geometry-compatible replacement parts therefore require an explicit boot-chain/policy change and fresh hardware validation.

The repeated checks are not a privilege boundary against a malicious `root`: an administrator can control process inputs and access lower-level MTD tooling directly. They are fail-closed operator safety for both normal and accidental direct installer entry paths.

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

## SD recovery and factory installation

A bootable AtlANTian SD image remains useful for first-time NAND installation
and disaster recovery. The SD-U-Boot raw-boot programming procedure
described below is for factory installation or historical releases, not the
current system-upgrade path.

Routine firmware updates stage signed files and user snapshots in RAM. They
require no bootable recovery card, no working SD FAT partition, and no inserted
card for an internal UBIFS upper. An *adopted external SD OverlayFS upper*
must remain present to preserve that active user state, not to stage firmware.

## Install transaction

The supported destructive path is deliberately split:

1. The public guard verifies exact NAND identity before handing off to the destructive implementation.
2. The destructive implementation repeats exact NAND identity validation, then verifies board, release payload, geometry and ECC and, by default, creates/reuses a verified pigz-compressed raw+OOB backup on the recovery SD. An explicit fresh-install `--no-backup` opt-out skips only this recovery copy.
3. Linux stages the raw boot payload on the recovery SD.
4. SD U-Boot programs and read-back verifies raw boot.
5. Only after the U-Boot verification marker exists does SD Linux replace the UBI region.
6. The new static root is read back through `ubiblock` and its AtlANTian release identity is checked.
7. A fresh writable upper is created (or preserved state is rebased during an upgrade).
8. Only after the complete transaction verifies does the operator fully remove power, switch the boot-source jumper to NAND and restore power.

This ordering keeps the old UBI untouched until raw boot is known-good and keeps the board on recovery SD until the new UBI is known-good. It does not make the raw boot update power-loss atomic; those physical fault cases remain part of [HARDWARE-VALIDATION.md](HARDWARE-VALIDATION.md).

## NAND base upgrades via RAM

The system updater never boots recovery SD. It fetches and verifies the signed
target release while running, then packages the full image and maintenance tools
into a self-contained `kexec` initramfs. The RAM kernel mounts the old UBI
only to copy supported persistent user state into a bounded RAM tmpfs, checks
that the snapshot and firmware fit, detaches the old UBI, formats the data
region, writes SquashFS/UBIFS and verifies the raw boot slots. An external SD
overlay is optional; if it is adopted, its token and state are handled explicitly.

Same-major and *adjacent* Debian-major upgrades are supported. The target
Debian rootfs is a newly built immutable image, not a live `apt dist-upgrade`
of the old NAND base. Local state and package intent are captured by
`atlantian-nand-rebase` and subsequently reconciled against the target
Debian generation. Cross-major compatibility of third-party packages is not
promised. Downgrades and skipping a major need separate explicit migration.

Power loss during NAND programming can still make the device unbootable; a
RAM-only snapshot is necessarily volatile. Linux raw-boot writes have passed an initial NAND `beta.2 → beta.3` RAM-only hardware upgrade, followed by a separate card-free cold boot and preserved-state checks. Card-free *updating*, adopted external-upper updates and power-loss recovery are not yet physically verified.

## Backup

`atlantian-nand-backup` is read-only and creates the recovery-critical raw+OOB dump as `nand-raw-oob.bin.gz`. The dump is streamed through `pigz`, avoiding a full uncompressed temporary file on the recovery SD. `--inspection-copy` adds a compressed padded main-area dump for offline analysis only.

Fresh installation stores its default backup under `/var/lib/atlantian/recovery/factory-nand-backup` on the SD root filesystem. `atlantian-nand-install --no-backup` explicitly skips the backup when the operator accepts losing the original NAND recovery copy; all hardware/payload verification and the literal `INSTALL` destructive confirmation remain in force.

Never restore raw NAND with `dd`. Raw NAND restore must respect OOB, factory bad blocks, ECC and the board's boot layout. AtlANTian currently provides the verified backup path, not a generic automated raw-NAND restore command.

User-facing installation steps are in [INSTALLATION.md](INSTALLATION.md); exact persistence/rebase rules are in [PERSISTENCE.md](PERSISTENCE.md); update authentication is in [UPGRADING.md](UPGRADING.md).
