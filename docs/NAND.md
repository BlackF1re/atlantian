# NAND architecture

AtlANTian's NAND edition targets the stock 256 MiB raw NAND used on the supported Antminer S9 control board. Raw-flash code is intentionally board-specific and rejects unexpected geometry.

## Geometry and ECC

Repository policy is defined by `config/nand-layout.env` and verified again against the live MTD device before destructive work.

Expected geometry:

- total: 256 MiB;
- eraseblock: 128 KiB;
- page: 2 KiB;
- OOB: 64 bytes;
- ECC contract: BCH strength at least 4 bits per 512-byte step for the Linux data path.

The supported stock Micron part uses its on-die BCH engine. Factory bad-block markers must be preserved. Backup reads therefore bypass the running ECC interpretation and retain OOB bytes.

## Physical layout

The first 16 MiB are a raw boot region because BootROM/SPL/U-Boot need fixed-address payloads. The remaining 240 MiB form the Linux UBI region.

The raw region contains redundant SPL/U-Boot placement and fixed logical slots for kernel, initramfs and DTB. Slot sizes include bad-block headroom; U-Boot reads exact release-specific payload lengths rather than consuming an entire slot.

## UBI root

The Linux data region is formatted as UBI after raw boot has been programmed and read-back verified.

- `rootfs`: static UBI volume containing a Zstd SquashFS immutable base.
- `overlay`: dynamic UBI volume formatted as LZO UBIFS.

Early `/init` attaches UBI, exposes the static root through `ubiblock`, mounts SquashFS read-only, mounts the UBIFS upper and assembles OverlayFS before `switch_root`.

The initramfs uses a build-only static BusyBox binary. `busybox-static` is not retained in either normal runtime rootfs solely for early NAND boot.

## Recovery microSD

The SD image is both the ordinary SD product and the NAND recovery/maintenance medium. It contains the release-matched NAND bundle under `/usr/lib/atlantian/nand`.

A NAND install records a board/card identity. Later NAND base updates require that paired recovery SD. If it is inserted while NAND is running, it can also be explicitly adopted as the writable OverlayFS upper; token matching prevents a random ext4 card from silently becoming system state.

## Install transaction

The destructive boundary is deliberately split:

1. Linux verifies the target and creates a raw+OOB backup.
2. Linux stages the raw boot payload on SD.
3. SD U-Boot programs and read-back verifies raw boot.
4. Only after the U-Boot verification marker exists does SD Linux replace UBI.
5. The new static root is read back through `ubiblock` and its AtlANTian release identity is checked.
6. A fresh writable upper is created.
7. The board is handed back to NAND boot only after the complete transaction verifies.

This ordering keeps the old UBI untouched until raw boot is known-good and keeps the board on recovery SD until the new UBI is known-good.

## Same-major upgrade

NAND does not install the SD-oriented `atlantian-kernel` package into the live immutable base. `atlantian-sysupgrade` downloads the target NAND bundle to the paired recovery SD. After booting that SD, `atlantian-nand-upgrade`:

- verifies the prepared bundle path and release identity;
- mounts the current immutable lower and active upper;
- captures selected persistent deltas and manual package intent;
- requires the target to stay within the current Debian major;
- stages the same verified raw-boot transaction used by installation;
- rebuilds UBI with the target SquashFS;
- restores selected state against the new lower rather than copying the previous upper wholesale.

A Debian-major NAND transition requires a clean reinstall. It is intentionally not advertised as a compatible NAND `sysupgrade`.

## Backup

`atlantian-nand-backup` is read-only and creates the recovery-critical raw+OOB dump by default. `--inspection-copy` adds a second padded main-area dump for analysis only.

Never restore raw NAND with `dd`. Raw NAND restore must respect OOB, bad blocks, ECC and the board's boot layout.

User-facing installation steps are in [INSTALLATION.md](INSTALLATION.md); persistence rules are in [PERSISTENCE.md](PERSISTENCE.md).
