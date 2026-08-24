# Contributing

Prefer narrow changes, explicit evidence and tests for behavioral contracts. Start with the topic index in [docs/README.md](docs/README.md).

## Rules by area

| Area | Requirement |
|---|---|
| Debian lifecycle | keep reproducible factory Snapshot inputs separate from live runtime APT; never skip Debian majors |
| DT/kernel | preserve boot-critical interfaces, DDR policy and verified pin safety |
| FPGA profile | document bitstream, DT overlay, pins, voltage and conflicts |
| SD update | preserve A/B FIT and boot-ABI fail-closed behavior |
| NAND | preserve raw+OOB backup, recovery-SD staging, read-back verification and rebase ordering |
| release tooling | verify version-matched assets/checksums and keep same-source publication idempotent |
| GitHub Actions | use allow-listed Actions pinned to immutable 40-hex commits |

Passwordless root on a fresh image is deliberate first-provisioning policy. Do not silently alter that behavior as unrelated cleanup.

## Fast validation

```sh
python3 .github/scripts/validate-automation.py
python3 .github/scripts/actions-policy.py scan .github/workflows
python3 .github/scripts/check-doc-links.py
scripts/test-build-orchestration.sh
scripts/test-runtime-policy.sh
scripts/test-release-versioning.sh
scripts/test-source-contracts.sh
scripts/test-update-leds.sh
scripts/test-release-metrics.sh
```

CI additionally runs shellcheck and scope-specific release/kernel checks.

Complete build:

```sh
sudo scripts/bootstrap-host.sh
sudo -E scripts/build-incremental.sh all
```

Production `Build & Release` additionally validates the finished release inventory, SD image layout, NAND bundle, a real cross-release SD package update and NAND state rebase before sealing the artifact.

## Repository structure

- Executable shell helpers are committed executable and can be invoked directly.
- `scripts/` contains build/runtime/test commands, not abandoned bench utilities.
- Debian maintainer scripts live under `packaging/`, not embedded as heredocs in the package builder.
- One orchestrator owns build ordering; leaf builders fail on missing prerequisites rather than recursively starting earlier stages.
- Put local build overrides in `config/local.env`; do not commit developer-specific paths or credentials.
- Use Conventional Commits.

## Documentation

Each behavior has one primary document. Update that document and link to it elsewhere instead of copying operational instructions. Historical implementation notes should remain only when they are required to explain a current compatibility boundary.

## Hardware evidence

A hardware claim needs evidence appropriate to the layer: PCB/schematic route, voltage and ownership for pins; boot/functional logs for peripherals; exact bitstream/DT-overlay pair for FPGA profiles; destructive/fault-injection bench evidence for NAND/boot recovery claims.

Do not promote an item in [hardware-support-matrix.md](docs/hardware-support-matrix.md) to **Ready** solely because a driver compiles.

## Pull requests and publication

`main` is protected by the required `Validate` check. Production releases are published only from the current `main` source revision after the gates described in [docs/PIPELINE.md](docs/PIPELINE.md).
