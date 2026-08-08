# Debian lifecycle policy

AtlANTian follows Debian stable automatically while keeping factory images
reproducible and installed systems safe from accidental major upgrades.

## Build baseline

`config/release.env` records the selected Debian codename, major version and
architecture. `config/debian-snapshot.env` plus the three `debian-*.sha256`
files record the exact immutable Debian repository metadata used by a release.

`scripts/refresh-debian-base.sh` is the single implementation of base
selection. The scheduled workflow is intentionally thin and calls that script.

## Daily selection

At 06:00 Asia/Tomsk the watcher checks Debian release metadata. It considers
`stable`, `oldstable` and `oldoldstable` so it can recover after a long period
without scheduled workflow execution. It will only select a release whose major
version is exactly one greater than the configured major and whose main,
updates and security repositories all publish `DEBIAN_ARCH` (`armhf`).

A new major is not accepted until all required live repositories and their
`binary-armhf` indexes exist. It is then not committed until Debian Snapshot
contains byte-for-byte matching Release files. A partial Debian publication can
therefore delay AtlANTian by one or more watcher runs, but cannot create a mixed
or unreproducible factory image.

If the next Debian stable drops `armhf`, AtlANTian deliberately remains on the
last compatible Debian release instead of switching to an unusable base.

## Future codenames

The build does not assume that the host's `debootstrap` package already knows a
new codename. If `/usr/share/debootstrap/scripts/<codename>` is absent,
`build-rootfs.sh` supplies the generic Debian `sid` bootstrap script explicitly
while still using the selected codename and immutable Snapshot mirror.

## Runtime repositories

Factory package selection uses Snapshot. Before the image is assembled,
`/etc/apt/sources.list` is replaced by a codename-pinned live Debian template.
The same template is stored at `/usr/lib/atlantian/runtime-sources.list` and the
installed Debian major/codename are recorded under `/usr/lib/atlantian/`.

The moving `stable` alias is never used on a running board. This allows ordinary
APT security/package updates while preventing an implicit major upgrade.

## Installed-system major upgrades

`atlantian-release-check` scans published releases rather than relying on the
single GitHub `/releases/latest` endpoint. A newer release in the currently
installed Debian major always wins over a release in the next major. This makes
the lifecycle-aware updater deploy itself before a major transition whenever a
same-major bridge release exists.

`atlantian-sysupgrade` refuses downgrades and refuses to skip a Debian major.
For a one-major transition it backs up and disables third-party APT source files,
fully upgrades the current Debian base, installs the next AtlANTian package set,
switches to the packaged next-codename Debian sources, performs `full-upgrade`,
and reboots. Disabled third-party source files remain in the update-state backup
for manual review after the transition.

No software already shipped on an old image can be retroactively changed. Very
old releases predating the lifecycle-aware updater should first install the
newest available same-major AtlANTian release before a Debian-major transition.

## GitHub schedule liveness

GitHub may automatically disable scheduled workflows in a public repository after
60 days without repository activity. When no Debian metadata change has produced a
real release commit, the watcher updates `.github/debian-watch-heartbeat` once per
calendar month. That path is outside the production build trigger, so it keeps the
schedule alive without creating a release.
