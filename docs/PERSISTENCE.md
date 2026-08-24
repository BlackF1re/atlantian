# Persistence and writable state

AtlANTian has two storage models. The user-visible filesystem is writable in both, but update mechanics differ.

## SD

SD uses a conventional ext4 root filesystem. Ordinary Debian state is persistent, including:

- `/etc` and SSH host keys;
- `/root` and `/home`;
- `/var`;
- installed packages and local package configuration;
- `/usr/local`, `/opt` and `/srv` when modified by the administrator.

The boot partition is separate FAT storage. Online AtlANTian kernel updates replace only the inactive FIT slot and then commit a slot marker.

## NAND

NAND presents a writable OverlayFS root:

- immutable lower: static UBI volume with Zstd SquashFS;
- writable upper: internal LZO UBIFS, or an explicitly adopted recovery-SD upper.

Normal Debian/package writes land in the active upper. `/tmp` and the system journal are deliberately volatile to reduce raw-flash write amplification.

## NAND base upgrades

A full NAND base upgrade does **not** preserve the previous upper directory as an opaque filesystem image. Before replacing UBI, AtlANTian compares the merged current system against its immutable lower and captures selected persistent/admin state plus package intent.

The rebase set covers administrator/user state under locations such as:

- `/etc`;
- `/root`;
- `/home`;
- `/usr/local`;
- `/opt`;
- `/srv`;
- persistent areas under `/var`.

Package-manager payload/database state that belongs to the immutable base is excluded. Manually requested packages and holds are captured separately and reconciled after the new base is active.

During restore, AtlANTian creates fresh `upper`/`work` directories above the verified target SquashFS and replays the selected deltas. This avoids carrying obsolete package files and whiteouts from one immutable base into another.

## External writable layer

The paired recovery SD can be adopted as the NAND writable layer through `atlantian-storage`. Adoption uses a generated token stored on both sides. Early boot uses the external upper only when the token and expected recovery-card layout match; otherwise it falls back to internal NAND state.

An adopted external upper is included in the same rebase transaction during a NAND base upgrade. If the card/token is missing or mismatched, the upgrade fails closed before replacing its lower layer.

## What is not persistent

- `/tmp` on NAND is tmpfs.
- NAND journal storage is volatile.
- A fresh NAND reinstall creates a new immutable base and writable layer; treat it as a reinstall unless state is explicitly restored by the administrator.
- Build-time Debian Snapshot state is not a runtime persistence mechanism.

Update procedure: [UPGRADING.md](UPGRADING.md). NAND design: [NAND.md](NAND.md).
