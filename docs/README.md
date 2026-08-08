# AtlANTian documentation

Most users need only **Quick Start** and **Upgrading**. Maintainers can jump
straight to the subsystem they are changing.

| I want to… | Source of truth |
|---|---|
| flash and boot AtlANTian | [Quick Start](QUICKSTART.md) |
| update packages or AtlANTian | [Upgrading](UPGRADING.md) |
| understand Debian auto-releases | [Debian lifecycle](DEBIAN-LIFECYCLE.md) |
| understand CI/release internals | [Release pipeline](PIPELINE.md) |
| check board/FPGA/electrical support | [Hardware support matrix](hardware-support-matrix.md) |
| understand what survives updates | [Persistence](PERSISTENCE.md) |
| understand/report a security issue | [Security policy](../SECURITY.md) |
| inspect the pinned boot binary boundary | [Boot firmware input](../boot-candidate/README.md) |
| contribute a change | [Contributing](../CONTRIBUTING.md) |
| inspect the base package allow-list | [`config/packages.base`](../config/packages.base) |

> [!TIP]
> Hardware claims and CI claims are deliberately separate. A release can be
> fully CI-validated without implying every physical peripheral was re-tested on
> a real CTRL_C41 for that exact build.

## Document ownership

| Topic | Keep it in |
|---|---|
| installation, first boot, board behavior | `QUICKSTART.md` |
| operator update/recovery steps | `UPGRADING.md` |
| Debian selection and unattended promotion | `DEBIAN-LIFECYCLE.md` |
| build, caches, gates, publication | `PIPELINE.md` |
| pins, electrical constraints, physical evidence | `hardware-support-matrix.md` |
| storage/state guarantees | `PERSISTENCE.md` |
| trust, vulnerability handling, initial root-access security | `SECURITY.md` |

## Design rules

| Rule | Result |
|---|---|
| Debian stays Debian | normal packages come from Debian, not a private mirror |
| Factory builds are reproducible | exact Debian Snapshot metadata is pinned |
| Installed systems stay fresh | runtime APT uses live codename repositories |
| Debian majors are explicit | no moving `stable` alias on the board |
| Updates preserve ordinary state | no overlay or hidden persistence layer |
| Releases fail closed | failed build/upgrade tests block publication |
| Hardware claims need evidence | unsafe or unverified routing stays disabled/profile-only |
