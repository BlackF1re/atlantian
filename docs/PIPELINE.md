# Build and release pipeline

AtlANTian produces one factory SD image and three version-matched Debian
packages: `atlantian-platform`, `atlantian-kernel` and `atlantian-release`.

```mermaid
flowchart LR
    A[Pinned source inputs] --> B[Build rootfs + kernel]
    B --> C[Assemble image + .deb set]
    C --> D[Static/image contracts]
    D --> E[Upgrade previous release in QEMU]
    E --> F[Verify main tip]
    F --> G[Attest + publish]
```

## Release identity

Example: `13.3.184+g0123456789ab`

| Field | Meaning |
|---|---|
| `13` | Debian major |
| `3` | AtlANTian Debian-base generation |
| `184` | monotonic source revision |
| `g0123456789ab` | source commit suffix |

The Debian watcher resets the base generation to `1` on a Debian-major promotion
and increments it whenever frozen Debian repository metadata changes within the
same major.

## Debian automation

The scheduled watcher runs daily at **06:00 Asia/Tomsk** and delegates policy to
`scripts/refresh-debian-base.sh`.

| Check | Rule |
|---|---|
| Current base | refresh only after Snapshot matches live Release metadata |
| Next Debian major | exactly `current + 1` |
| Architecture | required suites must still publish `armhf` |
| New codename | generic debootstrap fallback is available |
| Failed release | watcher retries while the frozen generation has no release |
| Quiet repository | monthly heartbeat keeps scheduled Actions active |

A commit created with `GITHUB_TOKEN` does not recursively trigger another push
workflow, so the watcher explicitly dispatches the production build after it
freezes a new Debian base.

## Factory rootfs vs runtime APT

| Stage | Repository policy |
|---|---|
| Factory build | immutable `snapshot.debian.org` input |
| Published metadata | exact Snapshot timestamp + Release hashes + package manifest |
| Running board | live repositories for the installed Debian codename |

This keeps the factory baseline reproducible without turning an installed board
into a package time capsule.

## Kernel and boot

- Linux source is pinned to an immutable upstream stable commit.
- Board kernel config is checked for required Zynq/FPGA interfaces.
- `BOOT.bin` is a separately pinned external vendor trust boundary.
- `atlantian-kernel` stores boot assets under `/usr/lib/atlantian/boot`.
- Package post-install copies `zImage`, `uImage` and DTB to the FAT `/boot`.

## Publication gates

| Gate | What it prevents |
|---|---|
| immutable input validation | drifting Debian/kernel/BOOT inputs |
| source and shell contracts | accidental lifecycle/build regressions |
| image-layout tests | broken partitions, ownership or identity |
| package identity checks | mixed or incorrectly versioned `.deb` files |
| updater/LED contract | broken update-state behavior |
| previous-release upgrade test | publishing a release that cannot replace the prior release safely |
| final `main` tip check | superseded builds publishing after newer source exists |
| SHA-256 + provenance attestation | unverifiable release artifacts |

### Previous-release upgrade gate

The production gate downloads the newest published AtlANTian image older than
the candidate, verifies it with its published `SHA256SUMS`, expands its root
partition and mounts FAT `/boot` + ext4 root.

Under `armhf` QEMU/binfmt chroot it then checks:

- installation of the new three-package set;
- downgrade, skipped-major and unauthorized-major rejection;
- legacy Snapshot-to-live-APT migration;
- `/boot` replacement and package/version markers;
- `dpkg --audit` and repository reachability;
- machine ID, SSH host key and representative persistent-state preservation.

For a real one-major transition, the gate also performs the Debian
`full-upgrade` and verifies the resulting codename.

> [!NOTE]
> QEMU validates userspace/package transitions. Zynq boot, FPGA configuration,
> Ethernet PHY and physical I/O remain real-board validation boundaries.

## Caches

| Cache | Safety property |
|---|---|
| Linux source/build | key includes kernel and board inputs |
| rootfs archive | numeric owners, modes, xattrs and ACLs are preserved |
| boot artifacts | invalidated by kernel/board inputs |

Cached rootfs state is restamped with the current release identity before
packaging.

## Dependency maintenance

Dependabot checks GitHub Actions monthly and groups routine Action updates into
one PR. PR CI validates workflow YAML and repository contracts before such
infrastructure changes are merged. Dependabot configuration has no Debian or
AtlANTian version pin and should not require routine editing.

## Installed updates

`atlantian-release-check` selects only reachable releases.
`atlantian-sysupgrade` verifies exact package names, SHA-256 values and package
versions before installation.

See [Upgrading](UPGRADING.md) for administrator-facing behavior and
[Debian lifecycle](DEBIAN-LIFECYCLE.md) for automatic base selection.
