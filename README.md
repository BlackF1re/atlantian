# AtlANTian GNU/Linux

[![Build and release](https://github.com/BlackF1re/atlantian/actions/workflows/build-release.yml/badge.svg)](https://github.com/BlackF1re/atlantian/actions/workflows/build-release.yml)
[![Debian base](https://github.com/BlackF1re/atlantian/actions/workflows/debian-watch.yml/badge.svg)](https://github.com/BlackF1re/atlantian/actions/workflows/debian-watch.yml)
[![PR CI](https://github.com/BlackF1re/atlantian/actions/workflows/ci.yml/badge.svg)](https://github.com/BlackF1re/atlantian/actions/workflows/ci.yml)

**AtlANTian** is a compact Debian GNU/Linux distribution for the Bitmain
Antminer S9 **CTRL_C41** control board. It turns the Xilinx Zynq-7010 board into
a general-purpose Linux/FPGA platform instead of a mining appliance.

| | |
|---|---|
| Board | Bitmain Antminer S9 CTRL_C41 |
| SoC | Xilinx Zynq-7010, dual Cortex-A9 + programmable logic |
| RAM | 512 MiB DDR3 |
| Debian base | Debian stable, `armhf`, selected automatically |
| Kernel | Pinned Linux 6.12 LTS board kernel |
| System storage | microSD, FAT boot + ext4 root |
| FPGA | FPGA Manager/Region + DT overlays |

AtlANTian stays deliberately close to Debian. Debian owns almost all userspace
and package maintenance; this repository owns the board description, kernel
policy, FPGA plumbing, factory image and AtlANTian release tooling.

## Quick start

1. Open [GitHub Releases](https://github.com/BlackF1re/atlantian/releases) and download the newest `.img`.
2. Write it to a microSD card with Rufus, Raspberry Pi Imager, Etcher or `dd`.
3. Select SD boot on CTRL_C41, insert the card and power the board.
4. The first boot expands the root partition and reboots once.
5. Connect over DHCP Ethernet or 3.3 V UART (`115200 8N1`).
6. Log in as `root` and immediately set a password with `passwd`.

Then verify:

```sh
cat /etc/os-release
uname -a
lsblk
networkctl
atlantian-fpga status
```

See [Quick Start](docs/QUICKSTART.md) for the full first-boot procedure.

> **Security:** a fresh image intentionally permits an empty root password for
> initial bench access. Use only a trusted isolated network until `passwd` has
> been set. Every flashed image generates unique machine and SSH host keys.

## Hardware support

| Function | Status | Notes |
|---|---|---|
| Zynq-7010 + 512 MiB DDR3 | Ready | Main PS platform |
| microSD | Ready | Boot + ext4 root filesystem |
| Gigabit Ethernet | Ready | MACB/GEM, DHCP, persistent local MAC |
| UART | Ready | `ttyPS0`, console/getty at 115200 |
| NAND | Ready | 256 MiB MTD, UBI/UBIFS, software BCH ECC |
| D2/D3 + S1/S2 | Ready | Linux LED/input plumbing |
| XADC | Ready | IIO + hwmon |
| Watchdog | Ready | `/dev/watchdog0` |
| FPGA configuration | Ready | FPGA Manager/Region + configfs overlays |
| D5-D8 | Profile | Shipped `status-leds` FPGA profile |
| PS USB | Disabled by default | Known MIO conflict; requires validated routing/profile |
| Other PL I/O | Profile-dependent | Matching bitstream + DT overlay required |
| RTC | Not fitted | Network time via systemd-timesyncd |

The pin-level boundary and evidence are documented in
[hardware-support-matrix.md](docs/hardware-support-matrix.md).

## Debian package model

A published image uses two deliberately different Debian sources:

**Build time:** the root filesystem is assembled from an immutable
`snapshot.debian.org` point. The exact Release hashes, Snapshot timestamp and
resolved package manifest are published with the image. This makes the factory
baseline reproducible.

**Runtime:** the flashed board uses the normal live Debian repositories for its
selected codename:

```text
deb https://deb.debian.org/debian <codename> main non-free-firmware
deb https://deb.debian.org/debian <codename>-updates main non-free-firmware
deb https://security.debian.org/debian-security <codename>-security main non-free-firmware
```

Therefore an old AtlANTian image does **not** become a package time capsule:

```sh
apt update
apt upgrade
apt install git python3 tmux
```

continues to receive current packages and security fixes for that Debian major.
The codename is used rather than the moving `stable` alias so an installed board
never performs an unplanned Debian major upgrade merely because Debian released
a new stable version.

## Automatic Debian lifecycle

The repository is designed to keep releasing images without routine manual
maintenance.

Every day at **06:00 Asia/Tomsk (23:00 UTC)** the `Daily Debian base update
check` workflow:

1. checks the configured Debian release plus Debian `stable`, `oldstable` and
   `oldoldstable` aliases;
2. promotes AtlANTian by **at most one Debian major at a time**;
3. promotes only if the next release officially publishes `armhf` in main,
   updates and security repositories;
4. waits until `snapshot.debian.org` contains the exact Release metadata seen
   on the live mirrors;
5. freezes that Snapshot, advances the AtlANTian Debian build generation and
   commits the new base to `main`;
6. dispatches the normal production release workflow.

A small monthly `.github/debian-watch-heartbeat` commit is made when Debian is
otherwise completely quiet. GitHub documents that scheduled workflows in public
repositories may be disabled after 60 days without repository activity; the
heartbeat prevents a genuinely unattended repository from silently losing its
daily watcher.

This means that when the Debian release after the current one becomes stable,
AtlANTian automatically starts building from it **if `armhf` is still an
officially published architecture**. If Debian drops `armhf`, the automation
keeps the last compatible base instead of producing a broken image.

The build also uses a generic Debian debootstrap script when the runner's
installed `debootstrap` package does not yet know a newly released codename.
See [Debian lifecycle](docs/DEBIAN-LIFECYCLE.md) for the complete policy.

## Updating an installed board

Normal Debian userspace maintenance uses APT. AtlANTian-specific releases carry
the board kernel, device tree, FPGA support and AtlANTian-owned tooling.

```sh
atlantian-sysupgrade --check
atlantian-sysupgrade --notes
atlantian-sysupgrade
```

The updater verifies one exact set of `atlantian-platform`, `atlantian-kernel`
and `atlantian-release` packages against `SHA256SUMS` and rejects downgrades or
mixed release versions.

Across a Debian major transition it additionally:

- refuses to skip a Debian major;
- prefers a newer same-major AtlANTian bridge release before offering the next
  major;
- disables and backs up third-party APT source files;
- fully upgrades the current Debian major first;
- installs the next AtlANTian release and its managed base repository template;
- runs the Debian `full-upgrade` into the next major;
- reboots normally.

Third-party repositories disabled for a major transition are preserved under
`/var/lib/atlantian/update/`; they are not silently re-enabled against a new
Debian major.

## Storage and persistence

The factory image has only two partitions:

| Partition | Filesystem | Purpose |
|---|---|---|
| `p1` | FAT | 64 MiB boot partition |
| `p2` | ext4 | Root filesystem, expanded on first boot |

There is no overlay filesystem or hidden persistence volume. `/etc`, `/root`,
`/home`, `/var`, package databases, SSH keys and user-installed packages are
ordinary persistent Debian state. The on-board NAND is separate and is not
overwritten by normal SD boot or `atlantian-sysupgrade`.

See [Persistence](docs/PERSISTENCE.md).

## FPGA use

```sh
atlantian-fpga status
atlantian-fpga apply <instance> <overlay.dtbo>
atlantian-fpga remove <instance>
```

The shipped `status-leds` profile exports D5-D8 through AXI GPIO. A full FPGA
bitstream replaces the current PL design; independent full bitstreams cannot be
stacked. A custom larger design can retain the same AXI ABI while adding more
peripherals.

## Building locally

Use a current Debian/Ubuntu Linux host with Internet access and roughly 20 GiB
free space:

```sh
git clone https://github.com/BlackF1re/atlantian.git
cd atlantian
sudo ./scripts/bootstrap-host.sh
./scripts/validate-release-inputs.sh
./scripts/build-incremental.sh all
```

Useful incremental targets:

```sh
./scripts/build-incremental.sh rootfs
./scripts/build-incremental.sh kernel
./scripts/build-incremental.sh image
```

Published releases are produced only from `main` by GitHub Actions.

## Release safety

Production releases are serialized. Before publication a build verifies that
its source commit is still the tip of `main`, so a superseded slow run cannot
publish over a newer source state.

CI checks include:

- shell/YAML and source lifecycle contracts;
- immutable Debian Snapshot, Linux and BOOT.bin inputs;
- exact package/release version identity;
- live-runtime-APT vs frozen-build-APT separation;
- partition, boot asset and rootfs ownership contracts;
- absence of factory SSH private host keys;
- first-boot identity behavior;
- update LED and updater lifecycle invariants.

GitHub Actions dependencies are pinned to commit IDs. Checksummed release
artifacts receive GitHub/Sigstore build-provenance attestations. The runtime
updater currently trusts GitHub HTTPS plus the release `SHA256SUMS`; it does not
claim to verify the Sigstore attestation on-device.

`boot-candidate/BOOT.bin` is a pinned external vendor binary input and is not
claimed to be reproducible from this repository. See
[boot-candidate/README.md](boot-candidate/README.md).

## Repository layout

| Path | Purpose |
|---|---|
| `board/` | Canonical CTRL_C41 device tree |
| `config/` | Debian/kernel/package/image policy |
| `kernel-overlay/` | Kernel-side OF/configfs support |
| `fpga/` | Shipped FPGA profiles/firmware |
| `systemd/` | Board services and first-boot policy |
| `scripts/` | Build, package, update and validation tooling |
| `boot-candidate/` | Pinned external boot firmware |
| `docs/` | Operational and hardware documentation |
| `.github/workflows/` | PR CI, Debian watcher and production release automation |

## Important behavior

- `poweroff` halts Linux but cannot disconnect external 12 V.
- There is no battery-backed RTC; network time matters after cold power loss.
- USB support in the kernel does not imply safe physical USB routing on this
  board; the base DT intentionally keeps the conflicted route disabled.
- PL peripherals require both FPGA logic and a matching DT overlay.
- Reflashing deliberately creates a new SSH host identity.

## Documentation

- [Quick Start](docs/QUICKSTART.md)
- [Debian lifecycle](docs/DEBIAN-LIFECYCLE.md)
- [Release pipeline](docs/PIPELINE.md)
- [Hardware support matrix](docs/hardware-support-matrix.md)
- [Persistence](docs/PERSISTENCE.md)
- [Security policy](SECURITY.md)

## License

AtlANTian-specific source code is licensed under **GPL-2.0-only**. Debian,
Linux, U-Boot, FPGA components and other third-party material remain under their
respective licenses.
