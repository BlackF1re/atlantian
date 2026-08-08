# Build and update pipeline

GitHub Actions builds a factory SD image and three packages:
`atlantian-platform`, `atlantian-kernel` and `atlantian-release`.

The factory image is a clean installation image. Write it with a raw-image
writer, boot once, and `atlantian-grow-rootfs` expands the ext4 root filesystem
to the full card. Each installation creates its own machine identity and SSH
host keys; build-time server keys are never shipped in the image.

## Release identity

A release version has three ordered numeric components plus its source hash,
for example `13.2.184+g0123456789ab`:

- `13` is the Debian major release;
- `2` is the AtlANTian Debian-snapshot generation;
- `184` is the monotonic source revision in repository history;
- the Git suffix identifies the exact source commit.

The source revision gives dpkg a real ordering while the hash keeps exact
traceability. An installed board only offers a strictly newer version.

## Debian base automation

Every day at 06:00 Tomsk time (23:00 UTC), the Debian watcher checks the main,
updates and security Release metadata for the selected Debian suite. A change
is accepted only after `snapshot.debian.org` contains the exact Release files
observed on the live mirrors. The watcher then commits the frozen snapshot,
advances the Debian build generation and dispatches the normal release build.

The immutable Snapshot is a **build input**, not a lifetime APT pin for an
installed board. Factory package selection is performed against that exact
Snapshot so a released image can be reproduced later. After the root filesystem
has been assembled, AtlANTian writes normal live Debian stable repositories into
`/etc/apt/sources.list` before the image and `atlantian-platform` package are
created.

This means an old installed image can continue to receive current Debian stable,
`trixie-updates` and `trixie-security` packages with ordinary APT even if no new
AtlANTian image has been flashed.

## Build safety

Release builds are serialised. Before publication, a build fetches `main` again
and publishes only if its own commit is still the branch tip. A slow older run
therefore cannot replace a newer release.

The root filesystem is cached as a root-created compressed archive rather than
as a runner-owned directory tree. Numeric ownership, modes, ACLs and xattrs are
preserved. Before packages or images are assembled, `stamp-release.sh` writes
the current source-addressed identity so cached content cannot retain an older
release marker.

`BOOT.bin` is an explicitly pinned external binary boot input. CI verifies its
Git object ID; its provenance boundary is documented under `boot-candidate/`.

Release artifacts covered by `SHA256SUMS` receive a GitHub Actions
Sigstore-backed build-provenance attestation in addition to checksum
verification.

## Installed-system update

`atlantian-sysupgrade` discovers the newest complete GitHub release, requires
an exact version-matched set of the three AtlANTian packages, verifies their
SHA-256 digests and Debian package versions, and installs them with APT/dpkg.
It then refreshes the configured APT repositories and performs a normal
`apt full-upgrade`.

The default runtime repositories are the live Debian stable mirrors for
`trixie`, `trixie-updates` and `trixie-security`. They are intentionally not
bound to the Snapshot used to build the image. A user who deliberately edits
APT sources keeps ordinary Debian conffile semantics; AtlANTian does not need a
private package mirror to keep Debian userspace current.

The boot partition is FAT32, so `atlantian-kernel` stores its dpkg payload under
`/usr/lib/atlantian/boot` on ext4. Its post-install script atomically copies
`zImage`, `uImage` and `devicetree.dtb` to `/boot`; dpkg never owns files on the
FAT filesystem directly.

The update does not rewrite partitions. Ordinary Debian state persists:
`/etc`, SSH keys, `/root`, `/home`, `/var`, package databases and locally
installed packages. Modified Debian conffiles are retained by default.

Rewriting the SD card is a factory reinstall operation. Normal updates use the
package path above.

The release endpoint is configured in `/etc/atlantian/releases.conf`; a
compatible fork or API mirror can be selected without changing the updater.
