# Install AtlANTian to NAND

AtlANTian can install the current release from its normal microSD image to the stock 256 MiB raw NAND on the Antminer S9 control board. The same microSD becomes the paired recovery medium used by later NAND base upgrades.

## Supported NAND boundary

The NAND installer is intentionally **not** a generic geometry-compatible flasher. The supported stock device is Micron `MT29F2G08ABAEAWP` with:

- Manufacturer ID: `0x2c`;
- Device ID: `0xda`;
- size: 256 MiB;
- eraseblock: 128 KiB;
- page: 2048 bytes;
- OOB: 64 bytes;
- data ECC: Micron on-die BCH, at least 4 bits per 512-byte step.

The supported operator command, `atlantian-nand-install`, checks the kernel NAND probe log for the exact `2c:da` identity **before** it hands control to the destructive implementation. `/usr/local/sbin/atlantian-nand-install.real` repeats that exact-ID check and then independently verifies board model, running/payload release identity, geometry and ECC. A replacement chip that merely has the same capacity/page/OOB geometry is not supported unless the boot chain and policy are explicitly updated and revalidated.

The repeated check prevents accidental/direct use of `.real` from skipping chip identity validation. It is still operator safety rather than privilege containment: a root user can control process inputs and invoke MTD tools directly. Normal and supported installations should use `atlantian-nand-install`.

## Before starting

Write and boot the target `atlantian-<release>.img.xz` from microSD with the physical jumper in **SD** position. Keep stable power and UART access available.

You can confirm the kernel probe before starting:

```sh
dmesg | grep -Ei 'Manufacturer ID|Chip ID'
```

Do not proceed if the board does not report the exact supported identity above.

The operation destroys existing NAND contents. By default, a verified pigz-compressed raw+OOB factory backup is created on the recovery microSD before the destructive stage. Copy that backup to another computer if factory recovery matters. An explicit `--no-backup` option exists for operators who intentionally accept losing that recovery copy.

## Install

As root:

```sh
atlantian-nand-install
```

By default, a new/reused verified backup lives on the recovery microSD root filesystem at:

```text
/var/lib/atlantian/recovery/factory-nand-backup
```

Fresh installation already requires `/` to be mounted from `/dev/mmcblk0p2`, so the default backup is stored on the SD card, not in the NAND being replaced.

To choose another backup directory:

```sh
atlantian-nand-install --backup /path/to/backup
```

To deliberately skip the factory backup:

```sh
atlantian-nand-install --no-backup
```

`--backup` and `--no-backup` are mutually exclusive. Skipping the backup does not bypass board, NAND identity, geometry/ECC, payload or read-back verification; it only removes the recovery copy of the original NAND.

The normal transaction is:

1. Verify exact NAND identity at the public entry point and repeat that identity check inside the destructive implementation; then verify board, release payload, NAND geometry and ECC.
2. Reuse or create a verified compressed raw+OOB NAND backup on recovery storage, unless `--no-backup` was explicitly requested.
3. Ask for the literal `INSTALL` confirmation.
4. Stage SPL, U-Boot, kernel, initramfs, DTB and the one-shot NAND U-Boot script on the recovery SD.
5. Reboot once while the jumper remains in **SD** position.
6. SD U-Boot programs the raw 16 MiB boot region and read-back verifies it.
7. SD Linux resumes automatically, formats only the UBI data region, writes/verifies the immutable SquashFS root and creates the writable UBIFS overlay.
8. AtlANTian marks the NAND transaction ready for handoff.
9. Move the jumper from **SD** to **NAND** only when prompted, then reboot.

Do not move the jumper during steps 4–7.

## Backup options

The default backup contains `NAND-INFO.txt`, `nand-raw-oob.bin.gz` and `SHA256SUMS`. The recovery-grade raw+OOB stream is compressed directly with `pigz`; no full uncompressed dump is staged on the SD card. OOB is retained deliberately because the stock NAND/boot path uses on-die ECC and factory bad-block information must not be discarded.

To additionally create a compressed padded main-area copy for offline inspection:

```sh
atlantian-nand-backup --inspection-copy /var/lib/atlantian/recovery/nand-backup
```

The inspection copy is optional and is not required by the installer or recovery contract. Previously created verified `nand-raw-oob.bin` backups remain acceptable for reuse. The repository does not provide a generic raw-NAND restore command; keep the verified backup off-board if factory recovery matters.

## Interrupted installation

The SD system has a marker-gated auto-resume service. If the board returns to SD Linux with a pending verified transaction, it resumes the UBI stage automatically.

Manual recovery commands are:

```sh
atlantian-nand-install --resume
atlantian-nand-install --handoff
```

`--resume-auto` exists for the installed auto-resume service and is not the normal operator entry point.

Do not delete transaction markers or installer files merely to bypass an error. Resolve the reported verification failure first.

## After NAND boot

```sh
cat /run/atlantian/storage-edition
findmnt /
cat /run/atlantian/overlay-mode
atlantian-storage status
systemctl --failed
```

The storage edition must report `nand`. The root is an OverlayFS assembled from the immutable SquashFS lower plus an internal UBIFS upper, or the explicitly adopted recovery-SD upper.

Architecture and raw layout details are in [NAND.md](NAND.md). Persistence is in [PERSISTENCE.md](PERSISTENCE.md). Update behavior is in [UPGRADING.md](UPGRADING.md).
