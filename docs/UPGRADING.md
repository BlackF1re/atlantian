# Updating AtlANTian

`atlantian-sysupgrade` is the stable user command in both storage modes. It reads the installed storage identity and dispatches to the SD or NAND backend.

## User commands

```sh
atlantian-sysupgrade --check
atlantian-sysupgrade --notes
atlantian-sysupgrade
atlantian-sysupgrade --yes
```

- `--check` refreshes release discovery and reports a compatible update without installing it.
- `--notes` refreshes discovery and prints the selected release notes.
- no option performs the normal interactive transaction and requires the literal `UPGRADE` confirmation.
- `--yes` installs/stages without that confirmation. It does **not** disable any signature, checksum, compatibility, free-space or NAND safety check.

Interactive SSH login also shows a cached notice when a compatible newer release has already been discovered by `atlantian-release-check.timer`.

## Which release is selected

Release discovery scans published, non-draft GitHub Releases and considers only complete version-matched package sets that already have both `SHA256SUMS` and `SHA256SUMS.sigstore.json`.

Selection policy is deliberate:

- an installation on a **stable** AtlANTian release ignores prereleases;
- an installation already on a **prerelease** may follow newer compatible prereleases or a later stable release;
- a newer release in the **currently installed Debian major** is preferred when one exists;
- only SD can then consider the **immediate next Debian major** (`N -> N+1`);
- NAND never advertises a cross-major in-place base update.

This means release ordering is not simply “highest tag wins”: current-generation maintenance is completed before an SD installation is offered a Debian-major transition.

## Release authentication

A release is eligible for AtlANTian system update only after the release-signing workflow has attached `SHA256SUMS.sigstore.json`. Existence of that asset makes the release discoverable; the installation transaction then downloads and cryptographically verifies the bundle before trusting any checksum in `SHA256SUMS`.

The installed trust root pins:

- the Cosign version used on ARM;
- the exact expected Cosign executable size and SHA-256;
- the exact GitHub Actions workflow identity allowed to sign AtlANTian release manifests;
- the GitHub Actions OIDC issuer.

If the verifier is not cached, `atlantian-verify-release` downloads that pinned ARM Cosign binary and validates its size/hash before executing it. SD caches it in local persistent storage. NAND update staging caches it on the paired recovery microSD instead of consuming the small NAND overlay.

This policy is enforced only by images that contain the signed-update client/trust root. An older image from before that client existed cannot retroactively authenticate the first update that installs it; see [../SECURITY.md](../SECURITY.md).

`atlantian-update.json` is separate, optional telemetry. Failure to fetch or validate it never weakens or blocks release authentication.

## SD updates

Run:

```sh
atlantian-sysupgrade
```

The SD backend:

1. refreshes published release discovery using the policy above;
2. advertises only a complete release that has the signed-manifest asset;
3. best-effort records the optional `atlantian-update.json` activity marker;
4. downloads the three AtlANTian Debian packages plus `SHA256SUMS` and `SHA256SUMS.sigstore.json`;
5. authenticates the checksum manifest against the pinned Sigstore signer identity/issuer;
6. verifies public filenames, Debian package metadata, common package revision and payload SHA-256;
7. installs the package set through APT;
8. runs a normal Debian `full-upgrade` for the configured codename;
9. audits dpkg state and reboots.

The downloaded AtlANTian package set is exactly one `atlantian-platform` (`all`), one `atlantian-kernel` (`armhf`) and one `atlantian-release` (`all`) package whose internal Debian versions correspond to the selected public release. Mixed revisions are rejected.

### SD boot transaction

The kernel package is an A/B FIT transaction. It requires both complete FIT slots and a matching SD boot ABI, writes only the inactive slot, verifies it, syncs it, and only then changes the active-slot marker. U-Boot can fall back to the other complete slot.

Online updates do **not** replace SD `BOOT.bin` or `u-boot.img`. If the target changes the early-boot contract/ABI in an incompatible way, the safe path is a fresh current image rather than an in-place bootloader rewrite.

When comparing generated `boot.scr` content, U-Boot legacy header CRC/timestamp bytes are treated as build metadata rather than semantic script differences.

### Debian-major transition on SD

The SD updater supports only the immediate next Debian major. Before crossing the boundary it:

1. requires additional free space;
2. backs up the existing APT source configuration;
3. disables third-party `.list`/`.sources` entries for the transition;
4. fully upgrades the current Debian generation;
5. records a resumable target marker;
6. installs the authenticated target AtlANTian package set under explicit major-upgrade authorization;
7. switches to the packaged target-codename Debian repositories;
8. completes the target `full-upgrade`, audits dpkg state and reboots.

If interrupted after the major-upgrade marker is written, run:

```sh
atlantian-sysupgrade
```

AtlANTian resumes the recorded target rather than selecting a different release. The updater deliberately does not skip a Debian major.

## NAND updates

The same command is used while booted from NAND:

```sh
atlantian-sysupgrade
```

The NAND backend advertises **same-Debian-major authenticated releases only**. It requires the recovery microSD paired during NAND installation and refuses an unrelated card.

Staging performs these checks before handoff:

1. locate the exact `atlantian-nand-<version>.tar.zst` asset for the selected release;
2. best-effort record the optional update metric marker;
3. download the NAND bundle, public `SHA256SUMS` and `SHA256SUMS.sigstore.json` to the recovery SD;
4. authenticate `SHA256SUMS` with the pinned release signer;
5. verify the bundle against that authenticated public checksum;
6. extract it and verify the bundle's internal `SHA256SUMS` and `NAND-MANIFEST.json` release identity;
7. record the prepared target on the recovery SD.

After staging:

1. move the physical boot-source jumper from NAND to SD when prompted;
2. reboot from the paired recovery card;
3. root login opens the prepared NAND maintenance transaction;
4. current supported persistent state/package intent is captured;
5. SD U-Boot programs and read-back verifies raw boot;
6. SD Linux rebuilds/verifies UBI and rebases supported persistent state;
7. move the jumper back to NAND only after verified handoff is offered.

The maintenance side checks the prepared bundle path and release identity again before destructive work. The exact persisted/rebased state is documented in [PERSISTENCE.md](PERSISTENCE.md), not “the whole previous upper”.

### Debian-major transition on NAND

A NAND immutable-base transition to another Debian major is a **clean reinstall**, not an in-place sysupgrade. Write/boot the target-generation SD release and follow [INSTALLATION.md](INSTALLATION.md).

## Ordinary Debian updates

AtlANTian runtime APT sources track the configured Debian codename. Normal package maintenance remains ordinary Debian administration:

```sh
apt update
apt upgrade
```

APT repository indexes are stored in a bounded 96 MiB tmpfs under `/run/apt`; package archives use normal storage-backed staging and are not retained after successful installation.

On NAND ordinary package/configuration writes go to the active OverlayFS upper. AtlANTian's immutable NAND base and raw boot are changed only through `atlantian-sysupgrade`/the paired recovery transaction.

## Release filenames and metrics

Prerelease `.deb` **asset filenames** use GitHub-safe dotted versions such as `13.1.0.alpha.20-1`, while the package's internal Debian version retains native `~` ordering such as `13.1.0~alpha.20-1`.

GitHub Release artifact download badges are presentation only. Runtime update accounting is anonymous and best-effort through the small `atlantian-update.json` asset; it is not part of the authenticated payload and never gates a transaction.

## Recovery rule

Do not bypass failed verification by deleting markers, editing `available.env`, replacing the signed manifest, or manually copying boot files. SD and NAND update markers are transaction state. Diagnose the reported failing invariant, then resume or reflash/reinstall as instructed.
