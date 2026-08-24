# Install AtlANTian to NAND

AtlANTian can install the current release from its normal microSD image to the 256 MiB raw NAND on the Antminer S9 control board. The same microSD becomes the paired recovery medium used by later NAND base upgrades.

## Before starting

Write and boot the target `atlantian-<release>.img.xz` from microSD with the physical jumper in **SD** position. Keep stable power and UART access available.

The installer refuses unexpected board/NAND geometry and requires the embedded NAND payload to match the running release.

The operation destroys existing NAND contents. A verified raw+OOB factory backup is created before the destructive stage. Copy that backup to another computer if factory recovery matters.

## Install

As root:

```sh
atlantian-nand-install
```

The normal transaction is:

1. Verify board, release payload, NAND geometry and ECC contract.
2. Reuse or create a raw+OOB NAND backup.
3. Ask for the literal `INSTALL` confirmation.
4. Stage SPL, U-Boot, kernel, initramfs, DTB and the one-shot NAND U-Boot script on the recovery SD.
5. Reboot once while the jumper remains in **SD** position.
6. SD U-Boot programs the raw 16 MiB boot region and read-back verifies it.
7. SD Linux resumes automatically, formats only the UBI data region, writes/verifies the immutable SquashFS root and creates the writable UBIFS overlay.
8. AtlANTian marks the NAND transaction ready for handoff.
9. Move the jumper from **SD** to **NAND** only when prompted, then reboot.

Do not move the jumper during steps 4–7.

## Backup options

The mandatory backup contains `NAND-INFO.txt`, `nand-raw-oob.bin` and `SHA256SUMS`.

To additionally create a padded main-area copy for offline inspection:

```sh
atlantian-nand-backup --inspection-copy /root/nand-backup
```

The inspection copy is optional and is not required by the installer or recovery contract.

## Interrupted installation

The SD system has a marker-gated auto-resume service. If the board returns to SD Linux with a pending verified transaction, it resumes the UBI stage automatically.

Manual recovery commands are:

```sh
atlantian-nand-install --resume
atlantian-nand-install --handoff
```

Do not delete transaction markers or installer files merely to bypass an error. Resolve the reported verification failure first.

## After NAND boot

```sh
cat /run/atlantian/storage-edition
findmnt /
cat /run/atlantian/overlay-mode
systemctl --failed
```

The storage edition must report `nand`. The root is an OverlayFS assembled from the immutable SquashFS lower plus an internal UBIFS upper, or the explicitly adopted recovery-SD upper.

Architecture details are in [NAND.md](NAND.md). Update behavior is in [UPGRADING.md](UPGRADING.md).
