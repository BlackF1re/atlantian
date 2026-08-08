# Build and release pipeline

AtlANTian produces one factory SD image and three version-matched Debian
packages: `atlantian-platform`, `atlantian-kernel` and `atlantian-release`.

```mermaid
flowchart LR
    A[Pinned Debian + Linux + U-Boot] --> B[Build rootfs + kernel + S9 U-Boot]
    B --> C[Assemble image + .deb set]
    C --> D[Static + image contracts]
    D --> E[Upgrade previous release in QEMU]
    E --> F[Verify main tip]
    F --> G[Attest + publish]
```

## Release identity

Format:

```text
<Debian major>.<base generation>.<source revision>+g<source commit>
```

Example: `13.1.1+g0123456789ab`.

| Field | Meaning |
|---|---|
| `13` | Debian major |
| first `1` | AtlANTian Debian-base generation |
| second `1` | monotonic Git source revision |
| `g0123456789ab` | exact source commit suffix |

The source revision is the commit count of the release commit. The Debian
watcher resets the **base generation** to `1` on a Debian-major promotion and
increments it when newly frozen Debian repository metadata changes within that
major.

## Debian automation

The scheduled watcher runs daily and delegates selection policy to
`scripts/refresh-debian-base.sh`.

| Check | Rule |
|---|---|
| Current base | freeze a change only after Snapshot matches live Release metadata |
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
| Published provenance | Snapshot timestamp + Release hashes + resolved package manifest |
| Running board | live repositories for the installed Debian codename |

This keeps factory images reproducible without turning an installed board into a
package time capsule.

## Kernel and SD boot firmware

AtlANTian no longer treats a vendor `BOOT.bin` as an opaque production input.
The complete SD first stage is built from the immutable upstream U-Boot commit
in `config/u-boot.env` using `bitmain_antminer_s9_defconfig`.

```text
Zynq BootROM
   -> BOOT.bin        (U-Boot SPL, built as spl/boot.bin)
   -> u-boot.img      (U-Boot proper, FAT p1)
   -> boot.scr        (AtlANTian SD policy)
   -> uImage + DTB
   -> /dev/mmcblk0p2
```

The Antminer S9 target has a 1 GiB maximum DDR probe window and uses runtime
`get_ram_size()` detection. The Linux command line therefore carries no fixed
`mem=` limit, and ARM `CONFIG_HIGHMEM=y` remains mandatory for 1 GiB boards.

`atlantian-kernel` owns both the Linux and SD boot-chain payloads under
`/usr/lib/atlantian/boot`. Its post-install step copies `u-boot.img`, `boot.scr`,
`uEnv.txt`, kernel and DT first, and replaces `BOOT.bin` last. This ordering
avoids exposing a new SPL while its matching second stage is still absent.

The old binary under `boot-candidate/` is retained only as a diagnostic/legacy
reference. Real-board testing showed that it cold-boots a 512 MiB board but is
silent on two 1 GiB boards, while the same kernel/DT/rootfs boots correctly on a
1 GiB board when launched through its factory NAND U-Boot.

> [!IMPORTANT]
> CI validates the source pin, generated boot artifacts, FAT layout and boot
> script, but cannot prove Zynq cold boot. Any change of the U-Boot pin still
> requires physical cold-boot testing on both 512 MiB and 1 GiB CTRL_C41 before
> the boot path should be described as hardware-validated.

## Publication gates

| Gate | What it protects |
|---|---|
| immutable input validation | Debian/Linux/U-Boot source inputs cannot drift silently |
| source and shell contracts | lifecycle/build invariants remain present |
| source-built first stage | SPL `BOOT.bin`, `u-boot.img` and `boot.scr` are present and coherent |
| dynamic-memory contract | no Linux RAM cap; 1 GiB probe ceiling and HIGHMEM remain intact |
| image-layout tests | partitions, boot memory contract, ownership and first-boot identity stay valid |
| package identity checks | the three `.deb` files cannot be mixed/mis-versioned |
| updater/LED contract | update-state behavior remains coherent |
| previous-release upgrade test | candidate can replace the prior release safely, including boot files |
| final `main` tip check | a superseded build cannot publish |
| SHA-256 + provenance | release bytes and build origin are independently inspectable |

Release publication uses the GitHub-hosted runner's `gh release` command rather
than a third-party release Action. Build provenance remains produced by GitHub's
official attestation Action.

<details>
<summary><strong>Previous-release upgrade gate</strong></summary>

For every release after the first, production CI downloads the newest published
AtlANTian image older than the candidate and verifies it with the release's
`SHA256SUMS`. It expands the disposable image, mounts FAT `/boot` + ext4 root and
runs the package transition under `armhf` QEMU/binfmt chroot.

The gate checks:

- installation of the exact three-package candidate set;
- downgrade, skipped-major and unauthorized-major rejection;
- legacy Snapshot-to-live-APT migration;
- `/boot` replacement and package/version markers;
- `dpkg --audit` and repository reachability;
- machine ID, SSH host key and representative persistent-state preservation.

For a one-major Debian transition it also performs the target Debian
`full-upgrade` and verifies the resulting codename.

> [!NOTE]
> QEMU validates userspace/package transitions. Zynq BootROM/SPL execution,
> FPGA configuration, Ethernet PHY and physical I/O remain real-board validation
> boundaries.

</details>

## Caches

| Cache | Safety property |
|---|---|
| Linux source/build | key includes kernel and board inputs |
| rootfs archive | numeric owners, modes, xattrs and ACLs are preserved |
| kernel boot artifacts | invalidated by kernel/board inputs |
| U-Boot | rebuilt from the exact pinned commit when an image is assembled |

Cached rootfs state is restamped with the current release identity before
packaging.

## GitHub Actions maintenance

GitHub Actions infrastructure is designed to maintain itself without routine
operator work.

```mermaid
flowchart LR
    A[Dependabot daily check] --> B[Grouped Actions PR]
    B --> C[Read-only PR CI + action smoke test]
    C --> D[Pin-only trusted policy]
    D --> E[Automatic squash merge]
    E --> F[Post-merge trusted canary]
    F -->|pass| G[Keep update]
    F -->|fail once| H[Retry]
    H -->|fail again| I[Auto-revert Dependabot merge]
```

| Control | Policy |
|---|---|
| ecosystem | only `github-actions`; Debian is never managed by Dependabot |
| cadence | daily version check; available updates are grouped |
| allowed external Actions | `actions/checkout`, `actions/cache`, `actions/upload-artifact`, `actions/attest-build-provenance` |
| pinning | every external Action must use a full 40-hex immutable commit SHA |
| PR permissions | normal Dependabot PR CI is read-only |
| auto-merge | only a successful Dependabot PR that changes Action pins and optional version comments, nothing else |
| trusted merge gate | `workflow_run`; validates API diff and never executes PR code with a write token |
| post-merge canary | checkout, cache save/restore, artifact upload, GitHub API and provenance attestation |
| recovery | retry once; a second failure on the current Dependabot merge is automatically reverted |

> [!IMPORTANT]
> Automatic dependency merging is deliberately narrower than normal contributor
> merging. A structural workflow edit, a new third-party Action or a floating
> `@vN` reference cannot pass the trusted pin-only gate.

The policy implementation is `.github/scripts/actions-policy.py`. The canary and
recovery workflows are intentionally separate from the production release path,
so routine infrastructure maintenance does not create a new AtlANTian image.

U-Boot and Linux pins are deliberately **not** Dependabot-managed because a CI
build cannot prove that a changed low-level firmware/kernel still cold-boots the
physical board.

## Installed updates

`atlantian-release-check` selects only reachable releases.
`atlantian-sysupgrade` verifies exact package names, SHA-256 values and embedded
versions before installation.

See [Upgrading](UPGRADING.md) for administrator behavior and
[Debian lifecycle](DEBIAN-LIFECYCLE.md) for automatic base selection.
