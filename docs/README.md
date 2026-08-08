# AtlANTian documentation

Use this page as the documentation map. Most users only need **Quick Start** and
**Upgrading**.

| I want to… | Read |
|---|---|
| flash and boot AtlANTian | [Quick Start](QUICKSTART.md) |
| update packages or AtlANTian | [Upgrading](UPGRADING.md) |
| understand Debian auto-releases | [Debian lifecycle](DEBIAN-LIFECYCLE.md) |
| understand CI/release internals | [Release pipeline](PIPELINE.md) |
| check board/FPGA support | [Hardware support matrix](hardware-support-matrix.md) |
| understand what survives updates | [Persistence](PERSISTENCE.md) |
| report or assess a security issue | [Security policy](../SECURITY.md) |
| contribute a change | [Contributing](../CONTRIBUTING.md) |

> [!TIP]
> Hardware claims and CI claims are deliberately separated. A current release
> can be fully CI-validated without implying that every physical peripheral was
> re-tested on a real CTRL_C41 for that exact build.

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
