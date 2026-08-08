# Build and update pipeline

GitHub Actions builds one factory SD image and three version-matched packages:
`atlantian-platform`, `atlantian-kernel` and `atlantian-release`.

## Release identity

A version such as `13.3.184+g0123456789ab` contains:

- Debian major (`13`);
- AtlANTian Debian-base generation (`3`);
- monotonic source revision (`184`);
- exact source commit suffix.

The Debian watcher resets the base generation to `1` when it promotes to the
next Debian major and increments it whenever repository metadata changes within
that major. Debian version ordering therefore remains monotonic across both
normal and major upgrades.

## Debian automation

The scheduled workflow runs every day at 06:00 Asia/Tomsk. The actual policy is
implemented in `scripts/refresh-debian-base.sh`, not embedded in workflow YAML.
It can promote by only one Debian major, requires `armhf`, and freezes a release
only after Snapshot exactly matches live main/updates/security metadata.

A `GITHUB_TOKEN` commit does not recursively trigger a push workflow, so the
watcher explicitly dispatches the production build after committing the frozen
base.

## Root filesystem

`debootstrap` and initial package installation use the frozen Snapshot. The
resolved package manifest and Snapshot metadata are attached to the release.
Before image assembly, runtime APT is changed to codename-pinned live Debian
repositories. The immutable Snapshot is therefore provenance for the factory
baseline rather than a permanent package restriction on installed systems.

The root filesystem cache is a root-created compressed archive with numeric
ownership, modes, ACLs and xattrs preserved. Cached root filesystems are stamped
with the current source-addressed release identity before packaging.

## Kernel and boot

The Linux source is pinned to an immutable upstream stable commit. Board kernel
configuration is validated for required boot/FPGA interfaces and forbidden
unrelated drivers. `BOOT.bin` is a separately pinned vendor binary trust
boundary; CI verifies its Git object ID.

The FAT boot partition is not owned directly by dpkg. `atlantian-kernel` stores
`zImage`, `uImage` and the DTB under `/usr/lib/atlantian/boot` on ext4 and its
post-install script copies them atomically to `/boot`.

## Publication safety

Release builds are serialized. Immediately before publication the workflow
fetches `main` and publishes only if its own commit is still the branch tip.
Artifacts are checksum-verified and receive GitHub/Sigstore build-provenance
attestations. Superseded builds may finish but cannot become the newest release.

## Installed updates

`atlantian-release-check` scans complete GitHub releases and enforces staged
Debian-major reachability. `atlantian-sysupgrade` verifies exact package names,
SHA-256 digests and embedded Debian package versions before installation.

Within one Debian major it installs the AtlANTian package set and runs normal
APT `full-upgrade`. Across one Debian major it first brings the current major
fully up to date, disables/backups third-party repositories, installs the target
AtlANTian package set and managed target-codename source template, then performs
the Debian major `full-upgrade` and reboots.

Normal updates do not rewrite partitions. `/etc`, SSH keys, `/root`, `/home`,
`/var`, package databases and user-installed packages remain ordinary Debian
state.
