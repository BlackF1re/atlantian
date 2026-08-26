# Persistence and writable state

AtlANTian has two storage models. The user-visible filesystem is writable in both, but the persistence/update mechanics are intentionally different.

## SD

SD uses a conventional ext4 root filesystem. Ordinary Debian state is persistent, including:

- `/etc` and generated SSH host keys;
- `/root` and `/home`;
- `/var`;
- installed packages and local package configuration;
- `/usr/local`, `/opt` and `/srv` when modified by the administrator.

The boot partition is separate FAT storage. Online AtlANTian kernel updates replace only the inactive FIT slot and then commit the active-slot marker; they do not rewrite early SD `BOOT.bin`/`u-boot.img`.

## NAND

NAND presents a writable OverlayFS root:

- immutable lower: static UBI volume with Zstd SquashFS;
- writable upper: internal LZO UBIFS, or an explicitly adopted recovery-SD upper.

Normal Debian/package writes land in whichever upper is active. `/tmp` and the system journal are deliberately volatile to reduce raw-flash write amplification.

## Exact NAND rebase set

A NAND base upgrade does **not** preserve the previous upper directory as an opaque filesystem image. Before replacing UBI, `atlantian-nand-rebase` assembles the old merged OverlayFS view and captures only the supported administrator/application state relative to the old immutable lower.

The exact top-level rebase roots are:

```text
/etc
/root
/home
/usr/local
/opt
/srv
/var/local
/var/lib
/var/spool
/var/www
```

Within `/var/lib`, these base/package-manager namespaces are explicitly excluded from the copied delta:

```text
apt/
dpkg/
systemd/
ucf/
initramfs-tools/
```

AtlANTian's own transient rebase/reconcile bookkeeping is excluded as well. Package-manager database/payload state therefore comes from the new immutable base instead of being copied from the old upper.

The capture records additional manual package intent and user package holds separately. After the new lower is active, the NAND reconcile service can restore that intent against the new base. An installed-package inventory is captured for transaction evidence, but the old package filesystem/database is not transplanted wholesale.

Deletions inside the supported roots are recorded explicitly. During restore, AtlANTian creates fresh `upper`/`work` directories above the verified target SquashFS, replays the selected deltas/deletions and writes the package-reconcile intent. This avoids carrying obsolete packaged files, stale dpkg state and unrelated OverlayFS whiteouts across immutable bases.

Anything outside the roots listed above is **not** promised by the automated NAND rebase contract. If an application keeps important state elsewhere, move/configure that state into a supported persistent location or back it up separately before a base update.

## External writable layer

The same microSD used to install/recover NAND can be adopted as the NAND writable layer:

```sh
atlantian-storage status
atlantian-storage adopt
```

Adoption does not repartition or erase the recovery card. It creates a private `.atlantian-extroot` upper/work tree inside the existing ext4 ROOT partition, copies the current internal writable state there and records a generated token on both sides. The card remains bootable as the recovery/maintenance SD.

Early NAND boot uses the external upper only when the expected recovery-card identity/layout and token match. If the adopted card is absent, normal boot falls back to the internal UBIFS upper. A random ext4 card cannot silently become system state.

An adopted external upper is captured/restored by the same supported rebase policy during a same-major NAND base upgrade. Token/layout mismatch during a prepared update fails closed rather than rebasing state onto an unrelated card.

## What is not persistent

- `/tmp` on NAND is tmpfs.
- NAND journal storage is volatile.
- The volatile APT index workspace under `/run/apt` is reconstructed as needed; downloaded package archives are not retained after successful installation.
- A fresh NAND reinstall creates a new immutable base and writable layer; treat it as a reinstall unless state is explicitly restored by the administrator.
- Build-time Debian Snapshot state is a reproducible factory-build input, not a runtime persistence mechanism.

Update procedure: [UPGRADING.md](UPGRADING.md). NAND design: [NAND.md](NAND.md).
