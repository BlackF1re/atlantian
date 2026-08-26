# Contributing

Prefer narrow changes, explicit evidence and tests for behavioral contracts. Start with the topic index in [docs/README.md](docs/README.md).

## Rules by area

| Area | Requirement |
|---|---|
| Debian lifecycle | keep reproducible factory Snapshot inputs separate from live runtime APT; never skip Debian majors |
| DT/kernel | preserve boot-critical interfaces, runtime DDR detection policy and verified pin safety |
| FPGA profile | document the exact bitstream/DT overlay, pins, voltage, reset/idle state and conflicts |
| SD update | preserve A/B FIT, inactive-slot write/verify ordering and boot-ABI fail-closed behavior |
| NAND | preserve exact `2c:da` stock-chip boundary, raw+OOB backup, recovery-SD staging, read-back verification and rebase ordering |
| release tooling | preserve version-matched assets, authenticated `SHA256SUMS`, exact signer identity and same-source publication idempotency |
| GitHub Actions | use allow-listed Actions pinned to immutable 40-hex commits and keep untrusted/new upstream execution separated from write privileges |

Passwordless root on a fresh image is deliberate first-provisioning policy. Do not silently alter that behavior as unrelated cleanup.

The packaged D5-D8 FPGA status profile is also an explicit current product choice. Do not silently replace its prebuilt bitstream/DT-overlay contract or make optional PL loading fatal as unrelated cleanup.

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

`CI / Validate` always checks automation policy and local Markdown links. For implementation changes it additionally runs shellcheck/source contracts. Relevant input changes also trigger frozen release-input validation, Linux smoke compilation, or **both SD and NAND U-Boot smoke builds**. Workflow/policy changes additionally exercise the selected cache/upload Actions.

Complete build:

```sh
sudo scripts/bootstrap-host.sh
sudo -E scripts/build-incremental.sh all
```

Production `Build & Release` additionally validates the finished release inventory, SD image layout, NAND bundle, a real cross-release SD package update and NAND state rebase before sealing the artifact. A published release is not updater-eligible until the separate Release Signature workflow has attached a valid `SHA256SUMS.sigstore.json`.

## Repository structure

- Executable shell helpers are committed executable and can be invoked directly.
- `scripts/` contains build/runtime/test commands, not abandoned bench utilities.
- Debian maintainer scripts live under `packaging/`, not embedded as heredocs in the package builder.
- One orchestrator owns build ordering; leaf builders fail on missing prerequisites rather than recursively starting earlier stages.
- Put local build overrides in `config/local.env`; do not commit developer-specific paths or credentials.
- Use Conventional Commits.

## Documentation

Each behavior has one primary document. Update that document in the same logical change as the behavior and link to it elsewhere instead of copying operational instructions. Historical implementation notes should remain only when they explain a current compatibility/recovery boundary.

Do not copy mutable patch versions, asset lists or hardware claims into multiple documents without a reason. Prefer the owning `config/`, workflow or runtime script for machine-enforced values and explain the stable contract in prose.

## Hardware evidence

A hardware claim needs evidence appropriate to the layer: PCB/schematic route, voltage and ownership for pins; boot/functional logs for peripherals; exact bitstream/DT-overlay pair for FPGA profiles; destructive/fault-injection bench evidence for NAND/boot recovery claims.

Do not promote an item in [hardware-support-matrix.md](docs/hardware-support-matrix.md) to **Ready** solely because a driver compiles or CI passes. Exact physical/fault evidence belongs in [HARDWARE-VALIDATION.md](docs/HARDWARE-VALIDATION.md).

## Pull requests and publication

`main` is protected by the required `Validate` check. Production releases are published only from the current protected `main` source revision after the gates described in [docs/PIPELINE.md](docs/PIPELINE.md).

Keep one logical change coherent. If a code/workflow change changes user-visible behavior, safety boundaries, artifact names or trust assumptions, update the owning documentation in the same pull request.
