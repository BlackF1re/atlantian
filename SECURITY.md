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
- a Sigstore keyless signature over the public `SHA256SUMS` manifest;
- transactional SD A/B FIT kernel+DT update;
- recovery-SD staging and raw-boot read-back verification for NAND;
- cross-release SD update and NAND rebase integration gates;
- GitHub build provenance for sealed build outputs.

Public checksum authentication is a separate trust boundary from GitHub Release mutation. After a successful `Build & Release`, `.github/workflows/release-sign.yml` locates the exact published release for that source SHA and signs its public `SHA256SUMS` in a job with `id-token: write` but no release-write permission. A second job can upload the sealed `SHA256SUMS.sigstore.json` bundle but has no OIDC permission. Before upload it rechecks the release source, re-downloads the current checksum manifest, verifies its digest did not change and refuses to overwrite a concurrently appearing signature.

Release discovery does not advertise a candidate until `SHA256SUMS.sigstore.json` exists. The SD/NAND installation transaction then downloads the manifest and Sigstore bundle and verifies them against the exact expected AtlANTian GitHub Actions workflow identity and GitHub OIDC issuer before using any checksum from the manifest. Thus mere presence of a bundle is enough for discovery, but not enough for installation.

The verifier itself is a pinned Cosign release whose version, executable byte size and SHA-256 are stored in the installed OS, outside the mutable GitHub Release being verified. SD systems cache the verifier locally; NAND base updates cache it on the paired recovery microSD so the small NAND overlay is not consumed.

GitHub build provenance remains an additional release/audit property; the public checksum signature is the authentication property enforced directly by `atlantian-sysupgrade`.

Images from before the signed-update client existed cannot retroactively authenticate the first upgrade that installs this trust policy. Fresh images and systems already running a release containing this policy refuse to install subsequent unsigned or incorrectly signed AtlANTian system releases.

`atlantian-update.json` exists only for anonymous aggregate update metrics. It is covered by the signed public checksum manifest as an ordinary release asset, but fetching/validating the marker is best-effort and does not decide whether the actual update is trusted or succeeds.

## Upstream automation trust boundary

The scheduled upstream watcher is split so the job that compiles newly discovered upstream Linux/U-Boot code is not the job that can write repository state.

- `candidate` has repository read permission only, checks out without persisted credentials, refreshes candidate metadata, validates inputs and compiles changed Linux/U-Boot sources. It allows only the known release-input files to differ and seals the exact binary diff with SHA-256.
- `apply` has protected-main write capability but **does not compile the candidate upstream source**. It reruns only trusted repository refresh scripts and accepts the change only if the allowed paths, boot-change classification and diff digest reproduce exactly.
- Git credentials are configured only after reproduction/validation, immediately before the protected-main merge helper is used.

This does not make upstream source intrinsically trusted; it prevents newly fetched build inputs/code from executing inside the same job that holds repository write privileges. The resulting protected merge still has to satisfy required `CI / Validate`.

## Factory baseline and runtime maintenance

Factory images use an exact Debian Snapshot. Installed systems use live repositories for their fixed Debian codename, so ordinary Debian security maintenance does not wait for a new AtlANTian image.

The custom kernel, DT and boot/platform policy remain AtlANTian release-controlled because they are validated together as a board-specific product.

APT indexes are disposable and bounded to a 96 MiB tmpfs. Package archives use storage-backed APT staging and are not retained after successful installation.

## SD update boundary

Online SD kernel updates do not rewrite early `BOOT.bin` or `u-boot.img`. They require two complete FIT slots and a matching boot ABI, write/verify/sync the inactive FIT, then commit the active-slot marker. U-Boot can fall back to the other complete slot.

An incompatible early-boot ABI requires a fresh image rather than an unsafe in-place bootloader rewrite.

## NAND safety boundary

The supported NAND installation path targets the stock Micron `MT29F2G08ABAEAWP`: Manufacturer ID `0x2c`, Device ID `0xda`, 256 MiB, 128 KiB eraseblocks, 2048-byte pages, 64-byte OOB and Micron on-die BCH 4/512.

The public `atlantian-nand-install` wrapper checks the kernel probe log for the exact `2c:da` identity before handing control to the destructive implementation. `/usr/local/sbin/atlantian-nand-install.real` now repeats the same exact-ID check before its board, running/payload release, geometry and ECC checks, so invoking that implementation path directly no longer skips chip identity validation. The NAND SPL enforces the same chip ID pair. A geometry-compatible but differently identified part is therefore not part of the supported installer/boot contract.

These checks are **operator safety, not containment against a malicious root user**. Root can control process inputs and invoke lower-level MTD tooling directly, so the threat model does not claim to protect raw NAND from a deliberately hostile or unsafe administrator. The supported entry point remains `atlantian-nand-install`.

The supported installation path creates or reuses a verified raw+OOB backup before erase/program operations. Raw boot is staged from the paired recovery SD, programmed and read-back verified by U-Boot before Linux replaces UBI. Same-major base upgrades capture only the documented persistent/rebase set before UBI replacement and restore it against the verified new immutable lower. Debian-major NAND transitions require a clean reinstall.

## Initial root access

A fresh image intentionally permits first provisioning as root without a pre-shared password. No shared SSH host private key is embedded; SSH host keys are generated per installation.

Before exposing a board to an untrusted network, set a root password or install an SSH public key. This is an explicit appliance-provisioning policy, not a claim that an unconfigured fresh image is safe on an untrusted LAN.

## Hardware boundary

CI cannot prove BootROM/SPL electrical behavior, real NAND bad blocks, physical FPGA routing or connector voltage. Keep unverified/conflicting routes disabled or profile-only until the bench evidence in [docs/HARDWARE-VALIDATION.md](docs/HARDWARE-VALIDATION.md) exists.

See [docs/UPGRADING.md](docs/UPGRADING.md), [docs/NAND.md](docs/NAND.md) and [docs/PIPELINE.md](docs/PIPELINE.md) for the owning technical contracts.
