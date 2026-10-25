# Updating AtlANTian

The same supported command updates both SD and NAND installations:

```sh
atlantian-sysupgrade --check
atlantian-sysupgrade --notes
atlantian-sysupgrade
atlantian-sysupgrade --yes
```

AtlANTian system releases are installed through a **signed, offline kexec RAM-maintenance system**. `--check` discovers a newer eligible release; it does **not** verify all downloaded payloads. Full Sigstore and SHA-256 authentication occurs during the actual upgrade, before kexec or any storage modification. Regular Debian application updates via APT are separate from AtlANTian system releases.

## How the RAM upgrade works

1. Discover the newest complete release eligible for the installed stable/prerelease channel and Debian generation. The release must publish a signed checksum manifest, a NAND system bundle and, for SD, matching Debian packages.
2. Download into a bounded RAM tmpfs. Validate the Sigstore signing identity and issuer, signed file hashes, NAND manifest and, when applicable, Debian package metadata.
3. Construct an autonomous Linux initramfs holding the verified payload and all maintenance utilities. Load the target kernel and the **live board device tree** with kexec.
4. Boot RAM Linux with DHCP and temporary SSH access, independent of the old installed root. Recheck the payload and collect state **before** destructive work.
5. Update the original SD or NAND, verify the result, then reboot with the **same physical boot-source jumper setting**. There is no SD/NAND jumper handoff for upgrades.

At least 700 MiB of available RAM is required before staging. RAM Linux reserves a bounded 400 MiB runtime tmpfs and checks memory again before overwriting NAND. A normal NAND update using its internal UBIFS layer does not need an inserted SD; an **adopted external upper** does require its own card because that card holds active user data, not update files.

If an upgrade fails, the RAM maintainer stays running for diagnosis. Connect via SSH on the trusted maintenance network and inspect:

```sh
cat /run/upgrade/status
tail -n 100 /run/upgrade/upgrade.log
```

Do **not** reboot or power off before collecting diagnostic information: the log and any RAM snapshots are volatile.

## SD edition

RAM Linux mounts the existing `/dev/mmcblk0p2` ext4 root and `/dev/mmcblk0p1` FAT boot partition. It mounts the required pseudo-filesystems inside the target and uses APT through a chroot. The authenticated `atlantian-platform`, `atlantian-kernel` and `atlantian-release` packages are supplied from RAM.

For a same-major release it installs signed AtlANTian packages and upgrades Debian packages. For an **adjacent Debian-major release** it backs up the old APT sources, temporarily disables third-party repositories, migrates to the signed target Debian repository template, and audits the resulting dpkg state. The boot transaction updates the A/B FIT kernel and device-tree payloads without rewriting SD `BOOT.bin` or `u-boot.img`; incompatible bootloader ABIs still require a new SD image.

The target ext4 filesystem must have adequate free space and working network connectivity for Debian packages. External packages may require manual attention across Debian-major boundaries.

## NAND edition

For internal UBIFS, RAM Linux mounts the original static SquashFS and UBIFS upper to capture supported user configuration/data and package intent into a bounded RAM snapshot. It then detaches old UBI, recreates the data partition, writes and verifies the new SquashFS and UBIFS, and rebases preserved state. Boot-slot writes are read-back verified; redundant U-Boot precedes the main copy, and SPL copies go last.

With an adopted external ext4 writable layer, RAM Linux verifies the pairing token, separately captures the internal fallback state and external active state, and restores both. The external SD must remain inserted during the update. See [PERSISTENCE.md](PERSISTENCE.md).

A same-major or **immediately adjacent Debian-major** NAND upgrade installs the new immutable root, not a live NAND APT upgrade. Only supported persistent paths and compatible package intent are preserved; installed third-party binaries from the old immutable root are not blindly copied.

NAND checks enforce the supported Micron identity `2c:da`, geometry, ECC and zero detected bad blocks. These checks and payload verification run before any erase.

**Hardware evidence:** on an Antminer S9, `13.1.0-beta.2 → 13.1.0-beta.3` completed through RAM Linux on NAND (internal UBIFS) and on SD (ext4). Both retained three independent persistence hashes; SD installed all three `beta.3` packages with a clean dpkg audit, and NAND cold-booted without an SD. The NAND update itself was performed with an *unadopted* SD inserted; fully card-absent NAND upgrade and **adopted external-upper** upgrades remain separate pending tests.

**Power-loss boundary:** overwriting the NAND UBI region and raw boot slots is not an atomic transaction. Interruption can leave NAND unbootable, and a RAM snapshot will not survive loss of power. Keep an independent recovery option. The first NAND trial confirmed the success path, **not** power-loss rollback.

## Release eligibility

Same-major and immediately next-major releases are eligible on SD and NAND within the installed release channel. A downgrade or skipped Debian major is not an automatic upgrade path. For initial NAND installation or manual disaster recovery from bootable SD, see [INSTALLATION.md](INSTALLATION.md); these are **not** system-update procedures.
