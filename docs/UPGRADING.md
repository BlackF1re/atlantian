# Updating AtlANTian

The user-facing entry point is the same for SD and NAND installations:

```sh
atlantian-sysupgrade --check
atlantian-sysupgrade --notes
atlantian-sysupgrade
atlantian-sysupgrade --yes
```

All system releases use a **signed, offline kexec RAM-maintenance transaction**.
The earlier SD online-update backend and NAND recovery-SD/jumper upgrade handoff
are no longer invoked or installed by the new image. Ordinary `apt update` and
`apt upgrade` remain available for Debian packages.

## Authentication and RAM handoff

1. Discover the newest published compatible release, with the authenticated
   release manifest and a NAND bundle required for **both** storage editions.
2. Confirm `UPGRADE`, unless `--yes` was selected.
3. Authenticate `SHA256SUMS.sigstore.json` with the pinned AtlANTian signer;
   verify downloaded assets and the NAND bundle's own checksums.
4. Stage verified assets on **ext4 partition `/dev/mmcblk0p2`**, not on the
   FAT boot partition. An adopted NAND external-overlay card does not need a
   bootable FAT partition.
5. Prepare a replacement Linux kernel from the signed NAND `uImage`, with a
   private static BusyBox initramfs, staged utilities and their libraries.
   Bring up Ethernet using DHCP and an unauthenticated `root` Dropbear SSH
   server on port 22 (maintenance mode only). The SSH session on the live
   operating system disconnects at the kexec handoff.
6. Systemd stops running userspace and executes `kexec`. The RAM kernel
   receives the correct MTD partition split and mounts ext4 p2 for staging.
7. Recheck the internal checksums sealed inside the initramfs **before**
   modifying the target storage. On failure the RAM maintenance system remains
   available over SSH; logs are written to
   `/var/cache/atlantian/ram-upgrade-last.log` on p2.
8. After verifying the update, issue a normal software reboot into the
   selected physical boot source. No jumper change or power cycling is
   involved in the normal update transaction.

## SD maintenance

The SD root on p2 is not mounted as the running system in RAM. The maintainer
bind-mounts `/proc`, `/sys`, `/dev`, `/run`, mounts the existing FAT p1
and uses `chroot` to apply the **authenticated AtlANTian package set** and
same-major Debian full upgrade. The kernel package's existing verified A/B FIT
post-install transaction switches only the inactive FIT slot.

The original SD SPL and U-Boot are not rewritten by this path. Their boot ABI
must remain compatible.

## NAND maintenance

This first RAM writer requires a **mounted, explicitly adopted external ext4
overlay** on p2 to stage the authenticated bundle and state snapshots. It does
**not** need the p1 recovery FAT filesystem, a bootable recovery SD image,
or a jumper switch. An internal-overlay-only NAND installation is rejected
until a separately verified staging/backup layout is implemented.

The old internal OverlayFS state is captured independently; the active external
OverlayFS state is captured from the live merged root (its busy upper is **not**
mounted again). Persistent paths, deletions and package intent follow the
existing [persistence contract](PERSISTENCE.md).

RAM maintenance revalidates the Micron 2c:da chip, 256 MiB capacity, exact MTD
partition offsets, 128 KiB eraseblocks, 2 KiB pages, 64-byte OOB, ECC 4/512
and zero bad blocks. An unsupported chip or bad-block layout fails before erase.

The maintainer formats the UBI data region, writes a static SquashFS rootfs and
UBIFS overlay, checks the rootfs byte-for-byte through ubiblock, mounts both
filesystems and restores the two separate state snapshots. The previous external
upper/work trees are retained for diagnosis instead of being silently deleted.

Only after UBI rebase and verification does the writer update changed raw boot
slots. The redundant U-Boot slot is written before the primary U-Boot slot.
Kernel, initramfs and DTB slots are verified after each write. SPL is written
**last**, in reverse copy order (3, 2, 1, 0), with individual readback checks.

Raw NAND updates **cannot guarantee recovery from power loss** during boot
programming. Keep a verified external backup or a recovery method available.
The hardware tests to date verified read equivalence and a successful RAM kexec
cycle; actual Linux raw-boot write compatibility has **not yet been physically
tested**, so treat the NAND write mode as experimental.

## Limitations

- Only **same Debian-major** system updates are supported. Major upgrades
  require separately planned migration or reinstall.
- The initial NAND writer fails closed if factory bad blocks are present.
- RAM maintenance permits passwordless root SSH by design. Any device on the
  same network may connect while that environment is active.
- Logs and snapshots are retained on ext4 p2 for inspection. Do not discard
  them before verifying the new system.

## Ordinary Debian packages

```sh
apt update
apt upgrade
```

These operations remain distinct from immutable NAND base and raw-boot
updates. They are not a substitute for `atlantian-sysupgrade`.
