# AtlANTian GNU/Linux

[![Latest Release](https://img.shields.io/github/v/release/BlackF1re/atlantian?include_prereleases&sort=semver&label=release)](https://github.com/BlackF1re/atlantian/releases) [![Release Pipeline](https://img.shields.io/github/actions/workflow/status/BlackF1re/atlantian/build-release.yml?branch=main&label=release%20pipeline)](https://github.com/BlackF1re/atlantian/actions/workflows/build-release.yml) [![Image Downloads](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fblackf1re.github.io%2Fatlantian%2Fimage-downloads.json&query=%24.imageDownloads&label=image%20downloads&cacheSeconds=3600)](https://github.com/BlackF1re/atlantian/releases) [![System Updates](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fblackf1re.github.io%2Fatlantian%2Fimage-downloads.json&query=%24.systemUpdates&label=system%20updates&cacheSeconds=3600)](docs/UPGRADING.md)

AtlANTian is a Debian-based Linux distribution for the Bitmain Antminer S9 control board built around Xilinx Zynq-7000. It turns the board into a general-purpose embedded Linux/FPGA platform while keeping boot, update and raw-NAND operations reproducible and recoverable.

## What is supported

- Debian `armhf` userspace with normal APT repositories at runtime.
- Pinned Linux 6.12 LTS and pinned U-Boot sources.
- 1 GiB Zynq DDR aperture with Linux HIGHMEM support.
- Ethernet, UART console and the board interfaces described in the [hardware support matrix](docs/hardware-support-matrix.md).
- FPGA Manager plus the packaged status-LED FPGA profile.
- SD boot with transactional A/B FIT kernel+DTB updates.
- Optional installation to the on-board 256 MiB raw NAND.
- Same-Debian-major NAND base upgrades through the paired recovery microSD.
- Release checks, SSH update notices and one user command: `atlantian-sysupgrade`.

## Start here

Download `atlantian-<release>.img.xz` from the latest GitHub Release and follow [Quick start](docs/QUICKSTART.md). The image can be written directly by tools that understand `.img.xz`, including Rufus, Raspberry Pi Imager and Etcher.

Default access policy, first login and network discovery are documented there. UART remains available at `115200 8N1` on `ttyPS0`.

## Storage modes

**SD** is the normal development and recovery mode. The image contains a FAT boot partition and an ext4 root filesystem. The root partition grows to the card on first boot. Online kernel updates write only the inactive FIT slot and then switch a small slot marker; early `BOOT.bin` and `u-boot.img` are not rewritten by package updates.

**NAND** uses the board's 256 MiB raw NAND as a compact installed system. The first 16 MiB are reserved for raw boot payloads. The remaining NAND is UBI with a static Zstd SquashFS lower and an LZO UBIFS writable OverlayFS upper. Installation and upgrade use the SD image as recovery media. See [NAND architecture](docs/NAND.md) and [installation](docs/INSTALLATION.md).

## Updates

```sh
atlantian-sysupgrade --check
atlantian-sysupgrade
```

The same command works in both storage modes. It dispatches to the SD or NAND backend from the installed storage identity.

- SD supports same-major releases and an explicit next-Debian-major transition.
- NAND supports same-major immutable-base upgrades. A Debian-major transition requires a clean NAND reinstall.
- SSH login displays a cached release notice when a compatible update is available.

Full behavior and recovery rules are in [UPGRADING.md](docs/UPGRADING.md).

## Build and release model

Factory builds use immutable Debian Snapshot metadata plus pinned Linux and U-Boot commits. Runtime Debian packages come from the configured Debian codename repositories; the snapshot is a reproducible factory input, not a frozen runtime mirror.

The production pipeline builds the common rootfs once, derives the NAND rootfs without a second package transaction, builds both boot chains, packages release-owned files, creates the SD image and NAND bundle, then validates release inventory, SD layout, NAND geometry, cross-release SD update, NAND state rebase, checksums and provenance.

See [PIPELINE.md](docs/PIPELINE.md) and [DEBIAN-LIFECYCLE.md](docs/DEBIAN-LIFECYCLE.md).

## Repository layout

- `board/` — Linux and U-Boot device trees.
- `config/` — release pins, NAND/image layout and package profile.
- `fpga/` — packaged FPGA profiles.
- `kernel-overlay/` — board kernel additions.
- `packaging/` — Debian maintainer scripts.
- `scripts/` — build, runtime and validation tools.
- `systemd/` — packaged units and runtime policy.
- `docs/` — user and engineering documentation.
- `.github/workflows/` — CI, release, upstream refresh and download metrics.

## Documentation

The documentation index is [docs/README.md](docs/README.md). Each topic has one primary owner to avoid duplicated operational instructions.

## Project status

AtlANTian targets the Bitmain Antminer S9 Zynq control board. Raw NAND operations are intentionally board-specific and fail closed on unexpected geometry or release identity. Before destructive NAND work, keep a verified raw+OOB backup outside the board.

## License

See [LICENSE](LICENSE). Security reporting guidance is in [SECURITY.md](SECURITY.md), and development workflow is in [CONTRIBUTING.md](CONTRIBUTING.md).
