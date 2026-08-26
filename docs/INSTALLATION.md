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

The supported operator command, `atlantian-nand-install`, checks the kernel NAND probe log for the exact `2c:da` identity **before** it hands control to the destructive implementation. That implementation then independently verifies board model, running/payload release identity, geometry and ECC. A replacement chip that merely has the same capacity/page/OOB geometry is not supported unless the boot chain and policy are explicitly updated and revalidated.

The wrapper is an operator-safety boundary, not privilege containment. Its underlying helper, `/usr/local/sbin/atlantian-nand-install.real`, is installed for internal transaction plumbing and remains executable by `root`; invoking it directly bypasses the wrapper's exact-ID check. A root user can also access MTD tools directly. Supported installations must therefore use `atlantian-nand-install`, not the `.real` helper.

## Before starting

Write and boot the target `atlantian-<release>.img.xz` from microSD with the physical jumper in **SD** position. Keep stable power and UART access available.

You can confirm the kernel probe before starting:

```sh
dmesg | grep -Ei 'Manufacturer ID|Chip ID'
```

Do not proceed if the board does not report the exact supported identity above.

The operation destroys existing NAND contents. A verified raw+OOB factory backup is created before the destructive stage. Copy that backup to another computer if factory recovery matters.

## Install

As root:

```sh
atlantian-nand-install
```

By default, a new/reused verified backup lives at:

```text
/root/atlantian-factory-nand-backup
```

To choose another backup directory:

```sh
atlantian-nand-install --backup /path/to/backup
```

The normal transaction is:

1. Verify exact NAND identity at the supported entry point, then independently verify board, release payload, NAND geometry and ECC in the destructive implementation.
2. Reuse or create a verified raw+OOB NAND backup.
3. Ask for the literal `INSTALL` confirmation.
4. Stage SPL, U-Boot, kernel, initramfs, DTB and the one-shot NAND U-Boot script on the recovery SD.
5. Reboot once while the jumper remains in **SD** position.
6. SD U-Boot programs the raw 16 MiB boot region and read-back verifies it.
7. SD Linux resumes automatically, formats only the UBI data region, writes/verifies the immutable SquashFS root and creates the writable UBIFS overlay.
8. AtlANTian marks the NAND transaction ready for handoff.
9. Move the jumper from **SD** to **NAND** only when prompted, then reboot.

Do not move the jumper during steps 4–7.

## Backup options

The mandatory backup contains `NAND-INFO.txt`, `nand-raw-oob.bin` and `SHA256SUMS`. The raw+OOB representation is the recovery-grade copy; OOB is retained deliberately because the stock NAND/boot path uses on-die ECC and factory bad-block information must not be discarded.

To additionally create a padded main-area copy for offline inspection:

```sh
atlantian-nand-backup --inspection-copy /root/nand-backup
```

The inspection copy is optional and is not required by the installer or recovery contract. The repository does not provide a generic raw-NAND restore command; keep the verified backup off-board if factory recovery matters.

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
