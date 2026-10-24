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

## One RAM path for both SD and NAND

1. The running AtlANTian checks published releases, respecting the stable vs.
   prerelease channel. Both storage editions require a full NAND bundle and the
   matching Debian packages in the release.
2. The target is downloaded into a bounded temporary RAM filesystem. The
   Sigstore identity, signing issuer, public SHA256SUMS, NAND bundle checksums
   and (for SD) Debian package identities and checksums are verified.
3. The complete verified NAND bundle, target kernel, and any SD Debian packages
   are copied into a self-contained kexec initramfs **before** the previous
   kernel exits. The original RAM filesystem itself does not survive kexec.
4. A separate Linux boots with the live board device tree, an explicit MTD
   partition layout, DHCP, preserved pre-kexec clock time, and SSH access.
   No existing system root is running or mounted as the updater root.
5. Only this new RAM system reads the old storage and performs the target
   operation. A failed check stops the transaction, leaving RAM recovery SSH.
   Once the target verifies, it software-reboots into the same physical boot
   source. No jumper movement is needed.

Normal operation requires **no bootable recovery SD** and no external storage
for payload staging. Before kexec at least 700 MiB RAM must be available; the
standalone RAM system has a bounded 400 MiB runtime tmpfs for snapshots and
checks memory reserves before erasing NAND. If the snapshot is too large, the
transaction fails *before* erasing. SSH on the RAM rescue system intentionally
allows passwordless root access and must only be used on a trusted network.

The update log lives at /run/upgrade/upgrade.log and status at
/run/upgrade/status in the RAM rescue system. These logs and RAM snapshots are
lost on power-off. If a transaction fails, do not reboot before investigating.

## SD

The RAM OS mounts the card's ext4 partition (mmcblk0p2) as a target, with
the FAT partition (mmcblk0p1) for the existing A/B FIT kernel transaction.
It mounts /proc, /sys, /dev and /run within the target and runs Debian
APT through a chroot. The authenticated AtlANTian Debian packages are
read from RAM, not downloaded to or executed from the running root.

On the same Debian major, the signed packages and full Debian upgrade are
installed. On an **adjacent Debian-major transition** (e.g. Debian 13 to
Debian 14), the updater upgrades the source generation, backs up its APT
sources and disables third-party repositories, obtains the target codename's
repository template from the signed target platform package, migrates target
Debian packages, installs the signed AtlANTian packages with the explicit
major-upgrade authorization, and audits dpkg. Errors stop in RAM rather
than rebooting a partially upgraded target.

SD early BOOT.bin and U-Boot are not rewritten by this update; the bootloader
ABI and the transactional A/B FIT layout still must be compatible. On-card
filesystem capacity and network connectivity are essential to a Debian-major
APT transition. Third-party package compatibility across majors is not assured.

## NAND, with or without SD card

For an internal UBIFS upper, **no card is needed at all**. The RAM OS attaches
the old NAND UBI, mounts the old immutable SquashFS lower and active merged
OverlayFS view, and captures the supported user/admin state and package intent
to its own RAM tmpfs. It then unmounts and detaches the old UBI, rechecks
available memory, formats the 240 MiB UBI data partition, writes and reads
back the new static SquashFS, recreates UBIFS, rebases user state and verifies
the new root. Only then are the changed fixed-address raw-boot slots written
and verified individually. Redundant U-Boot goes first; SPL copies go last,
in reverse order, to reduce the unbootable window.

If the system actually uses an **adopted external ext4 OverlayFS upper**, that
card must remain present: the RAM OS verifies its adoption token, takes a
separate snapshot of the internal fallback state and the active external
state, then restores the external upper into a side directory. The old
external upper/work are retained on that card. The card is needed because
it holds live user data, *not* because of firmware staging.

A NAND update between Debian major generations is also supported: unlike SD,
the target rootfs is a fresh immutable image; the snapshot/rebase and
post-boot package reconciliation adapt the retained state to the new base.
Only supported persistence paths and compatible package intent are retained;
see [PERSISTENCE.md](PERSISTENCE.md).

NAND safety guards verify the Micron chip ID, exact capacity/partitions,
128 KiB eraseblocks, 2 KiB pages, 64-byte OOB, ECC 4/512, zero reported
bad blocks, signed image sizes, and enough memory **before any erase**.
The initial writer rejects NAND with detected bad blocks.

**Experimental hardware warning:** raw NAND *writes* using Linux have not yet
been physically validated, although the RAM kexec+SSH+reboot cycle and raw
NAND readback were. A power failure while replacing UBI/SPL can destroy the
only bootable system and the volatile backup. Have an independent verified
backup and a recovery path for the first hardware trial.

## Debian major version policy

Same-major **and immediately next-major** releases are eligible on both SD
and NAND. The updater chooses the newest complete signed release allowed by
the stable/prerelease channel, including a next-major release where present.
Downgrades and skipping multiple Debian majors in one step still require a
separately tested migration. Ordinary apt package maintenance is not a
replacement for immutable NAND system updates.

The old online SD update backend and the old SD-recovery/jumper NAND-update
backend are no longer installed or called by atlantian-sysupgrade. The
separate first-time NAND factory installer remains available for installation
and disaster recovery, not normal system updates.
