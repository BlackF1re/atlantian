# Build and release pipeline

This document owns repository build, CI, upstream refresh and publication behavior. Debian generation policy is in [DEBIAN-LIFECYCLE.md](DEBIAN-LIFECYCLE.md).

## Build graph

`scripts/build-incremental.sh` is the production orchestrator. Leaf builders validate prerequisites and do not recursively rebuild earlier stages.

```text
rootfs                                      kernel
  ├─ build common Debian rootfs once          ├─ build pinned Linux + board DTB
  ├─ extract static BusyBox for NAND initramfs│
  ├─ purge build-only BusyBox                 └─ stage stripped modules in
  ├─ clone common runtime rootfs for NAND        out/kernel-rootfs
  └─ apply SD/NAND runtime storage policy
                 \                         /
                  \── wait for both ──────/
                            ↓
                  join staged modules into
                    SD and NAND rootfs
                            ↓
                        artifacts
  ├─ stamp release identity and build NAND initramfs
  ├─ build SD/recovery U-Boot and NAND SPL/U-Boot
  ├─ build three AtlANTian Debian packages
  ├─ build and embed the NAND bundle
  ├─ create the unified SD/recovery image
  ├─ create the compressed public image
  └─ generate release metadata/checksums
```

The rootfs and kernel branches are intentionally independent. Production release CI starts them concurrently, waits for both return codes, then joins the kernel modules before artifact assembly. `build-incremental.sh all` uses the same parallel core build locally, and the artifact stage reasserts the module join before packaging.

The common Debian userspace is installed once. NAND does not run a second `debootstrap` or package transaction merely to build early userspace.

## Source identity

Factory inputs are immutable:

- Debian Snapshot timestamp plus Release-file checksums;
- exact Linux stable commit inside the configured LTS series;
- exact U-Boot stable commit.

Linux and U-Boot source-preparation helpers verify the configured full SHA. A discovered tag is only candidate metadata; production builds consume the pinned commit.

## Pull-request CI

`CI / Validate` is the required check for protected `main`. It validates:

- workflow structure and immutable Action pins;
- repository-local Markdown links;
- shell syntax/shellcheck;
- build/update/NAND safety contracts;
- release versioning and public asset naming;
- retained release/download metrics contracts;
- frozen release inputs when relevant;
- kernel configuration smoke build when kernel inputs change.

The fast contracts intentionally check externally meaningful boundaries rather than exact implementation wording, so safe refactoring does not require preserving stale source strings.

## Build & Release

`.github/workflows/build-release.yml` has one manual input: `publish`.

- `publish=false`: build/verify only.
- `publish=true`: build or reuse a matching verified artifact, then publish.
- qualifying pushes to `main`: release planner applies the configured five-input batching policy.

The workflow refuses to publish a build if `main` moved after the source revision was selected.

A full build validates:

1. source contracts and frozen inputs;
2. the parallel common SD/NAND userspace and Linux-kernel build, followed by the staged-module join;
3. SD/recovery and NAND U-Boot payloads;
4. release package inventory;
5. SD image layout and A/B FIT structure;
6. NAND bundle geometry and exact raw read lengths;
7. upgrade from the newest eligible published SD release using its private verified Actions artifact;
8. NAND persistent-state rebase;
9. source-tree cleanliness;
10. SHA-256 manifests and GitHub build provenance.

The sealed Actions artifact records `VERIFIED-SOURCE-SHA` and `VERIFIED-VERSION`. Publication may reuse only a non-expired artifact for the exact source SHA.

## Public release payload

`prepare-public-release.sh` performs publication-only normalization exactly once before release notes are generated:

- keeps the user image as `atlantian-<release>.img.xz`;
- converts prerelease `.deb` filenames from Debian's internal `~` notation to GitHub-safe dotted filenames without modifying package metadata;
- creates the anonymous `atlantian-update.json` accounting marker;
- regenerates public `SHA256SUMS` over downloadable assets only.

The raw `.img` stays private in the verified Actions artifact so integration tests do not inflate public download counters.

## Upstream Base Watch

`.github/workflows/upstream-watch.yml` runs daily at 06:17 Asia/Tomsk and tracks:

- Debian Snapshot state for the configured codename;
- stable patch releases inside the selected Linux LTS series;
- official stable U-Boot releases.

Changed inputs are combined into one maintenance transaction. The watcher never pushes directly through protected `main`; it uses `.github/scripts/merge-protected-main.sh`, which validates the exact GitHub merge candidate through the required CI path before squash merge.

Debian-only refreshes participate in the normal release batch. An accepted Linux/U-Boot change makes the combined upstream transaction release-eligible immediately. Eligible watcher transactions invoke the ordinary `Build & Release` interface with `publish=true`; there is no private alternate publication origin.

A later no-change run can recover a missed release dispatch. A 45-day empty maintenance heartbeat is retained because GitHub may disable scheduled workflows after prolonged public-repository inactivity; the heartbeat changes no release input and does not itself publish an image.

## Download metrics

`.github/workflows/image-download-metrics.yml` is intentionally retained. It publishes aggregate image/system-update counts and per-asset `Downloads` data through GitHub Pages, then idempotently backfills release-note artifact tables when necessary.

Runtime update accounting is anonymous and best-effort: fetching `atlantian-update.json` never gates a real update. CI consumes private verified artifacts instead of public release assets where a test download would distort counters.

## Release identity

Public release versions are:

```text
<Debian major>.<AtlANTian minor>.<AtlANTian patch>[-prerelease]
```

For prereleases, Debian package metadata uses native Debian ordering, for example `13.1.0~alpha.20-1`, while the public release remains `13.1.0-alpha.20` and its GitHub asset filename uses dots.

Debian-major and Linux-LTS-series transitions are explicit policy changes; routine Snapshot, Linux patch and stable U-Boot refreshes remain automated within the configured generation/series.
