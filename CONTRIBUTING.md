# Contributing

AtlANTian is deliberately small. Prefer narrow changes, explicit evidence and a
failing test/contract for every regression you fix.

## Before changing code

| Area | Requirement |
|---|---|
| Debian lifecycle | keep immutable build Snapshot and live runtime APT separate |
| Debian major logic | never permit automatic multi-major jumps |
| DT/kernel | preserve cold-boot-critical interfaces and board pin safety |
| FPGA profile | document bitstream, DT overlay, pins, voltage and conflicts |
| persistence/update | preserve ordinary Debian state unless the change explicitly says otherwise |
| initial access | passwordless root provisioning is deliberate appliance policy, not an accidental default |
| release tooling | fail closed; a failed validation must block publication |

Use the [README contributor fast path](README.md#contributor-fast-path) to find
the subsystem documentation before editing it.

## Local checks

Run the relevant fast checks before pushing:

```sh
bash scripts/validate-release-inputs.sh
bash scripts/test-source-contracts.sh
bash scripts/test-update-leds.sh
```

For a complete local build:

```sh
sudo ./scripts/bootstrap-host.sh
./scripts/build-incremental.sh all
```

The heavy previous-release compatibility test normally runs in production
GitHub Actions. To opt in locally:

```sh
ATLANTIAN_UPGRADE_COMPAT_TEST=true ./scripts/test-build.sh \
  artifacts/current/atlantian-*.img artifacts/current/SHA256SUMS
```

## Hardware evidence

A hardware claim should state what proves it.

| Claim | Good evidence |
|---|---|
| pin/routing | schematic + board revision + measured/live confirmation |
| DT peripheral | boot log, sysfs/device node and functional test |
| FPGA profile | bitstream + DTBO + pin map + apply/remove smoke test |
| electrical safety | voltage/bank/pull/conflict analysis and bench validation |

Do not promote an unverified route from **Profile** to **Ready** merely because a
Zynq driver exists.

## Repository hygiene

- Use Conventional Commits, e.g. `fix(storage): reject oversized release bundle`.
- Do not commit SSH keys, board addresses, personal hostnames or local paths.
- Put installation-specific overrides in `config/local.env`.
- Keep documentation concise; prefer tables, short sections, `<details>` and
  GitHub alerts over long prose blocks.
- Put information in the document that owns the topic; cross-link instead of
  duplicating unrelated behavior.
- Update documentation when behavior changes.
- Treat `config/packages.base` as the base userspace allow-list rather than
  duplicating package inventories in prose.

## Pull requests

External contributions should use pull requests. PR CI is read-only and checks
workflow/dependency YAML, Markdown links, shell/source contracts, immutable
inputs, APT separation and package/image contract sources.

Dependabot maintains GitHub Actions only. Routine version updates are grouped in
one monthly PR; a relevant security update may appear outside that cadence.
These are infrastructure changes, not part of the automatic Debian-base release
cycle.

Published releases are produced only from `main` after all production gates
pass.
