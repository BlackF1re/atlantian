# Security policy

## Supported scope

Security fixes target the newest published AtlANTian release. Debian userspace follows Debian support for the installed codename through live runtime repositories; board kernel/boot support follows the pinned AtlANTian release inputs.

## Reporting

Do not publish an unpatched vulnerability in a public issue. Prefer GitHub's private **Report a vulnerability** flow when available; otherwise contact the maintainer privately through the [BlackF1re GitHub profile](https://github.com/BlackF1re).

Include the affected release, reproduction, required access, impact and any known mitigation. Do not send credentials or unrelated private data.

## Release trust model

AtlANTian relies on layered verification:

- immutable Debian Snapshot metadata for the factory package baseline;
- exact Linux and U-Boot source commits;
- version-matched `atlantian-platform`, `atlantian-kernel` and `atlantian-release` packages;
- SHA-256 over public release assets;
- transactional SD A/B FIT kernel+DT update;
- recovery-SD staging and raw-boot read-back verification for NAND;
- cross-release SD update and NAND rebase integration gates;
- GitHub build provenance for sealed build outputs.

The board verifies release package/bundle checksums locally. Build provenance is currently a release/audit property and is not verified on-device.

`atlantian-update.json` exists only for anonymous aggregate update metrics. Failure to fetch or validate that optional accounting marker does not weaken or block the actual update transaction.

## Factory baseline and runtime maintenance

Factory images use an exact Debian Snapshot. Installed systems use live repositories for their fixed Debian codename, so ordinary Debian security maintenance does not wait for a new AtlANTian image.

The custom kernel, DT and boot/platform policy remain AtlANTian release-controlled because they are validated together as a board-specific product.

APT indexes are disposable and bounded to a 96 MiB tmpfs. Package archives use storage-backed APT staging and are not retained after successful installation.

## SD update boundary

Online SD kernel updates do not rewrite early `BOOT.bin` or `u-boot.img`. They require two complete FIT slots and a matching boot ABI, write/verify/sync the inactive FIT, then commit the active-slot marker. U-Boot can fall back to the other complete slot.

An incompatible early-boot ABI requires a fresh image rather than an unsafe in-place bootloader rewrite.

## NAND update boundary

NAND destructive operations require the supported board geometry and verified release identity. Installation creates or reuses a verified raw+OOB backup before erase/program operations.

Raw boot is staged from the recovery SD, programmed and read-back verified by U-Boot before Linux replaces UBI. Same-major base upgrades capture persistent state before UBI replacement and restore it against the verified new immutable lower. Debian-major NAND transitions require a clean reinstall.

## Initial root access

A fresh image intentionally permits first provisioning as root without a pre-shared password. No shared SSH host private key is embedded; machine identity and host keys are generated per installation.

Before exposing a board to an untrusted network, set a root password or install an SSH public key.

## Hardware boundary

CI cannot prove BootROM/SPL electrical behavior, real NAND bad blocks, physical FPGA routing or connector voltage. Keep unverified/conflicting routes disabled or profile-only until the bench evidence in [docs/HARDWARE-VALIDATION.md](docs/HARDWARE-VALIDATION.md) exists.

See [docs/UPGRADING.md](docs/UPGRADING.md), [docs/NAND.md](docs/NAND.md) and [docs/PIPELINE.md](docs/PIPELINE.md) for the owning technical contracts.
