# AtlANTian GNU/Linux

[![Latest Release](https://img.shields.io/github/v/release/BlackF1re/atlantian?include_prereleases&sort=semver&label=release)](https://github.com/BlackF1re/atlantian/releases) [![Latest Release Date](https://img.shields.io/github/release-date-pre/BlackF1re/atlantian?display_date=published_at&label=latest%20release)](https://github.com/BlackF1re/atlantian/releases) [![Release Pipeline](https://img.shields.io/github/actions/workflow/status/BlackF1re/atlantian/build-release.yml?branch=main&event=push&label=release%20pipeline)](https://github.com/BlackF1re/atlantian/actions/workflows/build-release.yml) [![Image Downloads](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fblackf1re.github.io%2Fatlantian%2Fimage-downloads.json&query=%24.imageDownloads&label=image%20downloads&cacheSeconds=3600)](https://github.com/BlackF1re/atlantian/releases) [![System Updates](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fblackf1re.github.io%2Fatlantian%2Fimage-downloads.json&query=%24.systemUpdates&label=system%20updates&cacheSeconds=3600)](docs/UPGRADING.md)

AtlANTian is a Debian-based GNU/Linux distribution for the Bitmain Antminer S9 control board built around Xilinx Zynq-7000. It turns the board into a general-purpose embedded Linux/FPGA platform while keeping boot, update and raw-NAND operations reproducible, recoverable and fail-closed at their destructive boundaries.

## What is supported

- Debian `armhf` userspace with normal live APT repositories for the installed Debian codename.
- Reproducible factory images from an exact Debian Snapshot, a pinned Linux 6.12 LTS commit and a pinned U-Boot stable commit.
- Runtime DDR sizing for both 512 MiB and 1 GiB S9 board variants. The 1 GiB DT memory node is only the probe ceiling; U-Boot fixes it to the detected bank size before Linux starts, and Linux is built with HIGHMEM support.
- Gigabit Ethernet, `ttyPS0` UART, microSD, board LEDs/buttons/GPIO naming, XADC/hwmon and the Zynq watchdog.
- Linux FPGA Manager/configfs overlays plus the packaged `status-leds` PL profile. Its boot-time loader is best-effort and does not overwrite another administrator-selected active FPGA profile.
- Transactional SD kernel/DT updates with two SHA-256 FIT slots and fallback.
- Optional NAND edition for the stock 256 MiB Micron `MT29F2G08ABAEAWP` raw NAND (`Manufacturer ID 0x2c`, `Device ID 0xda`), with raw+OOB backup, fixed raw boot, static SquashFS root and writable UBIFS OverlayFS.
- Same-Debian-major NAND base upgrades through the paired recovery microSD, including selected persistent-state/package-intent rebase.
- Authenticated AtlANTian system updates: release discovery requires the Sigstore bundle asset, and SD/NAND installation refuses to trust `SHA256SUMS` unless that bundle verifies against the pinned AtlANTian release-signing workflow identity.

The exact readiness and electrical boundaries of individual interfaces are tracked in [docs/hardware-support-matrix.md](docs/hardware-support-matrix.md). Physical/fault-injection requirements are tracked separately in [docs/HARDWARE-VALIDATION.md](docs/HARDWARE-VALIDATION.md).

## Start here

Download the versioned `atlantian-<version>.img.xz` from [GitHub Releases](https://github.com/BlackF1re/atlantian/releases). Write it as a disk image with an imaging tool that supports XZ, or decompress it first and write the raw `.img`; do not copy the image file onto an existing filesystem.

Then:

1. power the board off;
2. select **SD** with the physical boot-source jumper;
3. insert the microSD and power on;
4. use UART at `115200 8N1` or find the DHCP address on Ethernet;
5. follow [docs/QUICKSTART.md](docs/QUICKSTART.md).

The default hostname is `atlantian`. A fresh image intentionally permits initial `root` provisioning with an empty password; set a password or SSH key before connecting the board to an untrusted network. See [SECURITY.md](SECURITY.md).

## Storage models

### SD

The public image contains:

- a 48 MiB FAT BOOT partition;
- an ext4 root partition that expands to the remainder of the card on first boot.

Online AtlANTian kernel updates write and verify only the inactive FIT slot before switching the active-slot marker. They do **not** rewrite SD `BOOT.bin` or `u-boot.img`; a boot-ABI incompatibility requires reflashing a current image.

### NAND

NAND installation is destructive and deliberately board/chip-specific. The supported `atlantian-nand-install` entry point refuses to hand control to the destructive implementation unless the kernel probe log identifies the exact supported `2c:da` NAND; the implementation then rechecks board, release payload, geometry and ECC before erase/program operations.

The first 16 MiB of NAND are reserved for raw boot payloads. The remaining 240 MiB are UBI with:

- a static Zstd SquashFS `rootfs` volume;
- a dynamic LZO UBIFS `overlay` volume.

A verified raw+OOB backup is mandatory before installation. The SD used for installation becomes the paired recovery/maintenance medium for later NAND base upgrades and can optionally be adopted as the NAND writable upper without destroying its recovery image.

See [docs/INSTALLATION.md](docs/INSTALLATION.md), [docs/NAND.md](docs/NAND.md) and [docs/PERSISTENCE.md](docs/PERSISTENCE.md).

## Updates

Use the same command in either storage mode:

```sh
atlantian-sysupgrade --check
atlantian-sysupgrade --notes
atlantian-sysupgrade
```

SD supports compatible same-major releases and an explicit immediate-next-Debian-major transition. NAND advertises same-major base releases only; a Debian-major NAND transition is a clean reinstall from the target SD image.

Stable installations do not automatically opt into prereleases. An installation already on a prerelease line may follow compatible prerelease or stable releases. Release discovery prefers a newer release in the currently installed Debian major before offering the immediate next major on SD.

Release discovery, signed-manifest verification, recovery behavior and the noninteractive `--yes` option are documented in [docs/UPGRADING.md](docs/UPGRADING.md).

## Build and release model

A complete local build is:

```sh
sudo scripts/bootstrap-host.sh
sudo -E scripts/build-incremental.sh all
```

The rootfs and kernel branches build independently and join before artifact assembly. Production GitHub Actions exposes the same boundary as separate parallel jobs, then fans release validation out into artifact, SD image, NAND bundle, cross-release SD update and NAND rebase gates. Only a fully verified candidate is sealed and eligible for publication.

A separate post-publication `Release Signature` workflow signs the exact public `SHA256SUMS`; release-write permission and OIDC signing permission are intentionally split across different jobs. Release discovery ignores a publication until `SHA256SUMS.sigstore.json` exists; the SD/NAND transaction then fails closed unless that bundle cryptographically verifies against the installed trust root.

See [docs/PIPELINE.md](docs/PIPELINE.md) for the complete DAG, source identity, upstream watcher and release-signing trust boundaries.

## Repository layout

- `board/` — Linux/U-Boot device trees and board boot policy.
- `config/` — release, Debian Snapshot, kernel, U-Boot, image, NAND and release-trust inputs.
- `fpga/` — versioned FPGA profile assets and manifests.
- `kernel-overlay/` — AtlANTian kernel-side source overlays.
- `packaging/` — Debian package metadata and maintainer scripts.
- `scripts/` — builders, validators and installed runtime/maintenance tools.
- `systemd/` — runtime services/mount policy.
- `docs/` — operator and engineering documentation.
- `.github/workflows/` — PR CI, production build/release, post-release signing, upstream refresh and download metrics.

## Documentation

Start with [docs/README.md](docs/README.md). Each operational topic has one owning document so procedures are not duplicated with slightly different semantics.

Repository-level policies are in [SECURITY.md](SECURITY.md), [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Project status

AtlANTian is board-specific. CI proves source contracts, reproducible inputs, image/package structure and simulated update/rebase transactions; it cannot replace electrical or destructive bench validation.

In particular, the supported NAND installer path fail-closes on exact stock-chip identity before the underlying implementation rechecks geometry/ECC/release constraints; FPGA claims distinguish implemented profiles from unproved routes; and `poweroff` only halts Linux because external 12 V remains present. The NAND identity wrapper is an operator-safety guard, not containment against a root user deliberately invoking internal raw-flash tools.

License: [GPL-2.0](LICENSE).
