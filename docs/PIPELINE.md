# Build and release pipeline

This document owns repository build, CI, upstream refresh, publication, post-publication authentication and metrics behavior. Debian generation policy is in [DEBIAN-LIFECYCLE.md](DEBIAN-LIFECYCLE.md).

## Build graph

`scripts/build-incremental.sh` remains the production orchestrator for a complete local build. Leaf builders validate prerequisites and do not recursively rebuild earlier stages.

```text
local build:
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

The rootfs and kernel branches are intentionally independent. `build-incremental.sh all` starts both concurrently on the local host and joins staged kernel modules before artifact assembly.

Production GitHub Actions exposes the same boundary as a real job DAG instead of hiding both builders inside one runner:

```text
Plan release
     ↓
Validate source
   ↙     ↘
Build     Build Linux
rootfs    kernel
   ↘     ↙
Assemble release
  ├───────────────┬───────────────┬───────────────┬───────────────┐
  ↓               ↓               ↓               ↓               ↓
Validate       Validate         Validate        Test SD         Test NAND
artifacts      SD image         NAND bundle     upgrade         rebase
  └───────────────┴───────────────┴───────────────┴───────────────┘
                                  ↓
                         Seal verified build
                                  ↓
                         Publish release
                          (when requested)
                                  ↓
                    Release Signature workflow
                                  ↓
                      updater-eligible release
```

The final two boxes are separate workflows/trust domains. A GitHub Release can exist briefly before its signature asset is attached; devices deliberately ignore it until the signature exists.

### Runner handoffs

`Build rootfs` and `Build Linux kernel` run on separate `ubuntu-24.04` runners and therefore have independent CPU, memory and live stdout. Their filesystem state crosses the runner boundary only through short-lived compressed handoff artifacts.

Rootfs handoffs are tarred as root with numeric owners, ACLs and xattrs so Unix metadata survives the GitHub artifact transport. Every handoff is SHA-256 hashed by its producing job; consumers receive that digest through job outputs and verify the downloaded archive before extraction. Downloaded archives are extracted only below the runner temporary directory, never over the checked-out source tree; trusted validation scripts receive isolated paths explicitly.

The release workflow deliberately does not use cross-run `actions/cache` state, so manually dispatched build code cannot become a cache-poisoning path into a later privileged release. Assembly restores both authenticated handoffs from isolated scratch roots, reasserts the module join, and emits the release candidate.

Release validation fans out after assembly: package/inventory validation, SD image validation, NAND validation, cross-release SD upgrade and NAND rebase are independent jobs. Only when every gate succeeds does `Seal verified build` add source/version seals, recheck checksums, issue GitHub build provenance and upload the long-lived verified Actions artifact. Publication depends on that seal when a fresh build was required.

The common Debian userspace is installed once. NAND does not run a second `debootstrap` or full package transaction merely to build early userspace.

## Source identity

Factory inputs are immutable:

- Debian Snapshot timestamp plus Release-file checksums;
- exact Linux stable commit inside the configured LTS series;
- exact U-Boot stable commit.

Linux and U-Boot source-preparation helpers verify the configured full SHA. A discovered tag/version is candidate metadata; production builds consume the pinned commit recorded in repository configuration.

## Pull-request CI

`CI / Validate` is the required check for protected `main`. It always validates automation policy and repository-local Markdown links, then enables heavier scopes according to the changed paths.

The check covers:

- workflow structure, least-privilege contracts and immutable Action pins;
- the explicit release DAG, authenticated handoff boundaries and no-cache release policy;
- repository-local Markdown links;
- shellcheck plus build/runtime/update/NAND/source contracts when non-documentation implementation files change;
- release versioning, public asset naming and retained metrics contracts;
- frozen release inputs when relevant;
- Linux `zImage`, modules and board-DTB smoke compilation when kernel inputs change;
- **both SD and NAND U-Boot smoke targets** when U-Boot/NAND boot-policy inputs change;
- selected cache/upload Action smoke calls when workflow/action policy changes.

A documentation-only PR still runs the required automation-policy and Markdown-link checks; implementation shell/build smoke is intentionally scope-gated.

The fast contracts check externally meaningful boundaries rather than exact prose/implementation wording, so safe refactoring does not require preserving stale source strings.

## Build & Release

`.github/workflows/build-release.yml` has one manual input: `publish`. The release DAG is explicitly restricted to protected `main`; manually selecting another ref does not enter the build/release trust domain. Feature branches and pull requests are validated by `CI / Validate`.

- `publish=false` on `main`: build/verify only.
- `publish=true` on `main`: build or reuse a matching verified artifact, then publish.
- qualifying pushes to `main`: the release planner applies the configured release-input batching policy.

The workflow refuses to publish a build if `main` moved after the source revision was selected.

A full build validates:

1. source contracts and frozen inputs;
2. common SD/NAND userspace and Linux kernel in parallel on separate runners;
3. metadata-preserving handoff and staged-module join;
4. SD/recovery and NAND U-Boot payloads;
5. release package inventory;
6. SD image layout and A/B FIT structure;
7. NAND bundle geometry and exact raw read lengths;
8. upgrade from the newest eligible published SD release using its private verified Actions artifact;
9. NAND persistent-state rebase;
10. source-tree cleanliness;
11. SHA-256 manifests and GitHub build provenance.

The sealed Actions artifact records `VERIFIED-SOURCE-SHA` and `VERIFIED-VERSION`. Publication may reuse only a non-expired artifact for the exact source SHA.

## Public release payload

`prepare-public-release.sh` performs publication-only normalization before release notes are generated:

- keeps the user image as `atlantian-<release>.img.xz`;
- converts prerelease `.deb` **filenames** from Debian's internal `~` notation to GitHub-safe dotted filenames without modifying package metadata;
- creates the anonymous `atlantian-update.json` accounting marker;
- regenerates public `SHA256SUMS` over the public payload assets only.

The base publication contains the compressed image, three AtlANTian `.deb` packages, NAND bundle, update marker, `RELEASE-METADATA.json` and public `SHA256SUMS`. The raw `.img` stays private in the verified Actions artifact so integration tests do not inflate public download counters.

`SHA256SUMS.sigstore.json` is **not** part of `SHA256SUMS` (a manifest cannot recursively checksum its own signature). It is attached afterward by the separate Release Signature workflow.

## Release Signature

`.github/workflows/release-sign.yml` is triggered by completion of `Build & Release`. It proceeds only for a successful run from this repository's `main` and locates a published release whose `target_commitish` is the exact successful build SHA. If that build produced no release (for example a build-only run), the signer exits without publishing anything.

The signing flow deliberately separates capabilities:

### `sign` job

- permissions: release contents **read**, OIDC `id-token: write`;
- no release-write permission;
- checks out trusted signing policy without persisted Git credentials;
- downloads the exact published `SHA256SUMS`;
- installs the pinned Cosign binary and verifies its repository-pinned checksum;
- keylessly signs the manifest through GitHub Actions OIDC;
- immediately verifies the generated bundle against the exact AtlANTian workflow identity and issuer;
- seals the signature, release tag, source SHA and manifest digest into a short-lived handoff artifact.

### `publish_signature` job

- permissions: Actions **read** and release contents **write**;
- **no OIDC signing permission**;
- downloads the sealed handoff;
- rechecks tag, source SHA and manifest digest;
- re-downloads the current release `SHA256SUMS` and refuses publication if it changed;
- refuses to overwrite a signature that appeared concurrently;
- uploads `SHA256SUMS.sigstore.json`.

Thus the job able to obtain the signing identity cannot mutate a release, and the job able to mutate the release cannot obtain a signing identity. Runtime clients pin the exact workflow identity/issuer in the installed trust root and fail closed if the bundle does not verify.

GitHub build provenance and the Sigstore public-manifest signature serve different purposes: provenance records the sealed build outputs; the Sigstore bundle is the independent authenticity gate the installed updater actually verifies before trusting the public checksum manifest.

## Upstream Base Watch

`.github/workflows/upstream-watch.yml` runs daily at 06:17 Asia/Tomsk and tracks:

- Debian Snapshot state for the configured codename;
- stable patch releases inside the selected Linux LTS series;
- official stable U-Boot releases.

It has a deliberate privilege boundary rather than one write-capable job that executes newly discovered upstream code.

### `candidate` job

The candidate job has `contents: read` only and checks out without persisted credentials. It refreshes metadata, validates changed release inputs and, when Linux/U-Boot changes, actually compiles the candidate source. It then allows only the known release-input files to differ and seals the exact binary Git diff with SHA-256.

### `apply` job

The write-capable apply job **does not build the candidate Linux/U-Boot source**. It reruns only the trusted repository refresh scripts, verifies the same allowed path set, validates the release inputs and requires the reproduced diff digest/classification to exactly equal the read-only candidate job. Only then does it obtain Git credentials for the protected-main merge helper.

Changed inputs are combined into one maintenance transaction. The watcher never pushes directly through protected `main`; `.github/scripts/merge-protected-main.sh` validates the exact merge candidate through the required CI path before squash merge.

Debian-only refreshes participate in the normal release batch. An accepted Linux/U-Boot change makes the combined upstream transaction release-eligible immediately. Eligible watcher transactions invoke the ordinary `Build & Release` interface with `publish=true`; there is no private alternate publication origin.

A later no-change run can recover a missed release dispatch. A 45-day empty maintenance heartbeat is retained because GitHub may disable scheduled workflows after prolonged public-repository inactivity; the heartbeat changes no release input and does not itself publish an image.

## Download metrics

`.github/workflows/image-download-metrics.yml` provides presentation/anonymous accounting; it is not in the update trust chain.

It:

- reads the complete published GitHub Release inventory and validates IDs, names, sizes and `download_count` values;
- publishes aggregate `imageDownloads` and `systemUpdates` through GitHub Pages;
- publishes a per-release/per-asset index/mirror used by the retained backfill path;
- can idempotently rewrite release-note artifact tables after the Pages payload has been deployed;
- prunes superseded retained release-build artifacts while preserving the newest verified release artifact.

Initial release notes no longer depend on a not-yet-deployed Pages key: `generate-release-notes.sh` uses Shields' native exact-tag/exact-asset GitHub download endpoint for the first artifact table. The later metrics backfill runs from a validated release snapshot after the Pages deployment, so the aggregate/per-asset mirror remains useful without being a prerequisite for initial release rendering.

Runtime update accounting is anonymous and best-effort: fetching `atlantian-update.json` never gates a real update. CI consumes private verified artifacts instead of public release assets where a test download would distort counters.

## Release identity

Public release versions are:

```text
<Debian major>.<AtlANTian minor>.<AtlANTian patch>[-prerelease]
```

For prereleases, Debian package metadata uses native Debian ordering, for example `13.1.0~alpha.20-1`, while the public release remains `13.1.0-alpha.20` and its GitHub asset filename uses dots.

Debian-major and Linux-LTS-series transitions are explicit policy changes; routine Snapshot, Linux patch and stable U-Boot refreshes remain automated within the configured generation/series.
