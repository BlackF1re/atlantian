# AtlANTian documentation

Each document owns one topic. Operational instructions should live in the owning document and be linked elsewhere instead of copied. Repository configuration, installed scripts and workflow definitions are the executable source of truth; when behavior changes, the owning document must change in the same logical update.

- [QUICKSTART.md](QUICKSTART.md) — write the SD image, boot, find the board, log in and perform first checks.
- [INSTALLATION.md](INSTALLATION.md) — install the current release from SD to the exact supported on-board NAND.
- [UPGRADING.md](UPGRADING.md) — authenticated SD/NAND system updates, prerelease policy and interrupted-update recovery.
- [NAND.md](NAND.md) — exact NAND identity, geometry/ECC, raw boot layout, UBI and maintenance transaction design.
- [PERSISTENCE.md](PERSISTENCE.md) — what is writable and the exact state/rebase boundaries in each storage mode.
- [hardware-support-matrix.md](hardware-support-matrix.md) — implemented hardware interfaces, profiles and electrical/routing boundaries.
- [HARDWARE-VALIDATION.md](HARDWARE-VALIDATION.md) — physical-board acceptance and fault-injection checks that CI cannot prove.
- [PIPELINE.md](PIPELINE.md) — local/CI build graph, protected automation, publication, signing and download metrics.
- [DEBIAN-LIFECYCLE.md](DEBIAN-LIFECYCLE.md) — Debian Snapshot, runtime APT, generation transitions and upstream refresh policy.

Repository-wide project overview: [../README.md](../README.md).

Repository-level policy documents:

- [../SECURITY.md](../SECURITY.md) — security reporting and release/update trust boundaries.
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — change requirements, validation and evidence rules.
- [../CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) — project participation standard.
