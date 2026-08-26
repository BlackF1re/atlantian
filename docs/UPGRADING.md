# Updating AtlANTian

`atlantian-sysupgrade` is the stable user command in both storage modes. It reads the installed storage identity and dispatches to the SD or NAND backend.

## Check for an update

```sh
atlantian-sysupgrade --check
```

To read release notes:

```sh
atlantian-sysupgrade --notes
```

Interactive SSH login also shows a cached notice when a compatible newer release has already been discovered by `atlantian-release-check.timer`.

A release is eligible for AtlANTian system update only after the release-signing workflow has attached `SHA256SUMS.sigstore.json`. The update transaction verifies that bundle against the pinned AtlANTian GitHub Actions signer identity before trusting any checksum in `SHA256SUMS`.

The verifier is pinned by version, exact byte size and SHA-256 in the installed OS. The first authenticated update may download the ARM Cosign verifier; later SD updates reuse the cached verifier. NAND updates keep that cache on the paired recovery microSD rather than consuming NAND overlay space.

## SD updates

Run:

```sh
atlantian-sysupgrade
```

The SD backend:

1. queries published GitHub Releases;
2. selects the newest complete, signed release reachable from the installed Debian generation;
3. downloads exactly `atlantian-platform`, `atlantian-kernel`, `atlantian-release`, `SHA256SUMS` and `SHA256SUMS.sigstore.json`;
4. authenticates the checksum manifest with the pinned Sigstore signer identity;
5. verifies public filenames, Debian package metadata, common package revision and SHA-256;
6. installs the package set through APT;
7. runs a normal Debian `full-upgrade` for the configured codename;
8. audits dpkg state and reboots.

The kernel package is an A/B FIT transaction. It requires both FIT slots and a matching boot ABI, writes only the inactive slot, verifies it, syncs it, and then changes the active-slot marker. `BOOT.bin` and `u-boot.img` are not replaced online.

If the package's `boot.scr` is semantically incompatible, or the boot ABI changes, the online update fails with a reflash requirement. U-Boot legacy header CRC/timestamp bytes are ignored when comparing otherwise identical scripts because they are build-time metadata, not boot semantics.

### Debian-major transition on SD

The SD updater supports the immediate next Debian major only. It requires additional free space, backs up and disables third-party APT sources, fully upgrades the current Debian generation, records a resumable marker, installs the authorized AtlANTian target package set, switches to the packaged target-codename repositories, completes the target `full-upgrade`, audits dpkg and reboots.

If interrupted after the major-upgrade marker is written, run:

```sh
atlantian-sysupgrade
```

AtlANTian resumes the recorded target instead of selecting a different release.

## NAND updates

The same command is used while booted from NAND:

```sh
atlantian-sysupgrade
```

The NAND backend advertises **same-Debian-major signed releases only**. It requires the paired recovery microSD, downloads the exact `atlantian-nand-<version>.tar.zst` bundle, public checksum manifest and Sigstore bundle onto that card, authenticates `SHA256SUMS`, verifies the archive and its internal checksums/manifest, then records a prepared target.

After staging:

1. move the physical boot-source jumper from NAND to SD when prompted;
2. reboot from the paired recovery card;
3. root login starts the prepared `atlantian-nand-upgrade` transaction;
4. current persistent state/package intent is captured;
5. SD U-Boot programs and verifies raw boot;
6. SD Linux rebuilds/verifies UBI and rebases persistent state;
7. move the jumper back to NAND only after verified handoff is offered.

The prepared bundle path and release identity are checked again by the NAND maintenance script before destructive work.

### Debian-major transition on NAND

A NAND immutable-base transition to another Debian major is a **clean reinstall**, not an in-place sysupgrade. Write/boot the target SD release and follow [INSTALLATION.md](INSTALLATION.md).

## Ordinary Debian updates

AtlANTian runtime APT sources track the configured Debian codename. Normal package maintenance remains ordinary Debian administration:

```sh
apt update
apt upgrade
```

On NAND these writes go to the active OverlayFS upper. AtlANTian immutable base/raw boot is changed only through `atlantian-sysupgrade`.

## Release discovery and metrics

The release checker requires a complete version-matched package set, `SHA256SUMS` and `SHA256SUMS.sigstore.json`. Prerelease `.deb` assets use GitHub-safe dotted public filenames while the package's internal Debian version retains `~` ordering.

When a real update transaction begins, the updater best-effort downloads the release's small `atlantian-update.json` marker for anonymous aggregate update/download metrics. Failure of that marker never blocks the actual authenticated update.

## Recovery rule

Do not bypass failed verification by deleting markers or manually copying boot files. SD and NAND update markers are transaction state. Diagnose the reported failing invariant, then resume or reflash/reinstall as instructed.
