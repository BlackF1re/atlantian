# AtlANTian GNU/Linux

[![Build and release](https://github.com/BlackF1re/atlantian/actions/workflows/build-release.yml/badge.svg)](https://github.com/BlackF1re/atlantian/actions/workflows/build-release.yml)
[![PR CI](https://github.com/BlackF1re/atlantian/actions/workflows/ci.yml/badge.svg)](https://github.com/BlackF1re/atlantian/actions/workflows/ci.yml)

**AtlANTian** is a small Debian GNU/Linux distribution for the Bitmain Antminer S9
**CTRL_C41** control board. It turns the board into a general-purpose Xilinx Zynq
platform instead of treating it as a mining appliance.

| | |
| --- | --- |
| Board | Bitmain Antminer S9 CTRL_C41 |
| SoC | Xilinx Zynq-7010 |
| RAM | 512 MiB DDR3 |
| Base | Debian 13 `trixie` |
| Kernel | Linux 6.12.100 |
| System storage | microSD, two-partition image |
| PL support | FPGA Manager + FPGA Region + DT overlays |

AtlANTian deliberately stays close to Debian: Debian supplies almost all
userspace and security maintenance, while this repository supplies the board
description, kernel policy, FPGA plumbing, factory image and release/update
logic needed by CTRL_C41.

## Quick start

1. Download the newest `.img` from [GitHub Releases](https://github.com/BlackF1re/atlantian/releases/latest).
2. Write it to a microSD card with Rufus, Raspberry Pi Imager, Etcher or `dd`.
3. Set CTRL_C41 to **SD boot**, insert the card and power the board.
4. Wait through the first automatic reboot while AtlANTian expands the root
   partition to the card.
5. Connect by Ethernet/DHCP or the 3.3 V UART (`115200 8N1`).
6. Log in as `root`. A fresh image initially permits an empty root password on
   the local bench network.
7. Immediately set a password:

```sh
passwd
```

Then verify the system:

```sh
cat /etc/os-release
uname -a
lsblk
networkctl
atlantian-fpga status
```

For flashing examples, first-login checks and troubleshooting, see
**[Quick Start](docs/QUICKSTART.md)**.

> **Security:** the empty initial root password is for first access on an
> isolated trusted network. Set `passwd` before exposing the board to an
> untrusted LAN.

## What works in the base image

The base image enables only hardware whose routing and ownership are understood.
It does not assume that every peripheral present inside the Zynq package is
actually usable on this PCB.

| Function | Status | Notes |
| --- | --- | --- |
| Zynq-7010 + 512 MiB DDR3 | Ready | Main PS platform |
| microSD | Ready | Boot + ext4 root filesystem |
| Ethernet | Ready | MACB/GEM, MDIO, DHCP, stable local MAC |
| UART | Ready | `ttyPS0`, console + getty at 115200 8N1 |
| NAND | Ready | 256 MiB MTD, UBI/UBIFS, software BCH ECC |
| D2/D3 + buttons | Ready | Linux GPIO/LED/input plumbing |
| XADC | Ready | IIO + hwmon |
| Watchdog | Ready | `/dev/watchdog0` |
| FPGA configuration | Ready | FPGA Manager/Region + configfs overlays |
| D5-D8 | Profile | Shipped `status-leds` PL profile |
| PS USB | Disabled by default | Known MIO conflict; enable only with validated routing/profile |
| Unused PS I2C/SPI | Disabled by default | Avoids claiming conflicted or unverified pins |
| Fan/hash-board/extra PL I/O | Profile-dependent | Requires matching bitstream + DT overlay |
| RTC | Not fitted | Network time via `systemd-timesyncd` |
| Software power cut | Not available | `poweroff` halts Linux but cannot remove external 12 V |

The detailed pin-level boundary lives in
[`docs/hardware-support-matrix.md`](docs/hardware-support-matrix.md).

## Design principles

AtlANTian follows a few simple rules:

- **Debian-native:** normal APT/dpkg, systemd and ordinary filesystem layout.
- **Board-specific, not board-fiction:** hardware is enabled only when the
  CTRL_C41 routing is understood.
- **Small base image:** no desktop, PYNQ/Jupyter or large convenience stacks.
- **PL remains useful:** FPGA infrastructure is present without forcing one
  monolithic bitstream on every use case.
- **Releases are reproducible from pinned inputs:** Debian Snapshot metadata,
  Linux source commit and boot firmware input are fixed for each source release.
- **Normal user state survives updates:** `/etc`, `/root`, `/home`, `/var`, APT
  state and user-installed packages remain ordinary Debian state.

## First boot and identity

The factory image contains no reusable SSH private host key or pre-generated
machine identity.

On each newly flashed installation:

- systemd creates a unique machine identity;
- OpenSSH generates unique host keys;
- systemd derives a stable locally-administered Ethernet MAC from that machine
  identity;
- `atlantian-grow-rootfs` expands partition 2 to the remaining microSD capacity.

The expansion requires one automatic reboot. After that the card behaves like a
normal two-partition Debian installation.

If you reflash the same board, its SSH host key will intentionally change. Your
client may require removal of the old `known_hosts` entry.

## Storage

The factory image is intentionally simple:

| Partition | Filesystem | Purpose |
| --- | --- | --- |
| `p1` | FAT | 64 MiB boot partition |
| `p2` | ext4 | Root filesystem, expanded on first boot |

There is no overlay filesystem, hidden persistence partition or special data
volume. Everything you normally expect to persist on Debian persists on `/`.

The on-board NAND is **separate** from the microSD installation. Normal boot,
package updates and `atlantian-sysupgrade` do not overwrite it. Treat raw NAND
backups carefully: bad-block and OOB/ECC assumptions matter.

More detail: [`docs/PERSISTENCE.md`](docs/PERSISTENCE.md).

## Networking and access

The default hostname is `atlantian`. Ethernet uses systemd-networkd with DHCP.
The serial console is always available on `ttyPS0` at `115200 8N1`.

Useful first commands:

```sh
hostnamectl
networkctl
ip address
ip route
```

The base system is root-only, similar in spirit to OpenWrt. There is no default
`sudo` user.

A local build can override non-release installation defaults in
`config/local.env`; copy `config/local.env.example` and edit it. That file is
ignored by Git and does not change the identity of published releases.

## Installing software

AtlANTian is ordinary Debian, so package installation is normal:

```sh
apt update
apt install git python3 tmux
```

Published images intentionally point APT at a **frozen Debian Snapshot** rather
than a moving mirror. This makes a release internally consistent and
reproducible. A newer AtlANTian release moves the default system to a newer
verified Debian snapshot.

The base image already contains practical board/debugging tools including:

`gpiod`, `i2c-tools`, `spi-tools`, `can-utils`, `lm-sensors`, `libiio-utils`,
`mtd-utils`, `dtc`, `ethtool`, `iproute2`, `nftables`, `usbutils`, `v4l-utils`,
`alsa-utils`, `curl`, `jq`, `kmod`, `htop`, `pigz`, `less` and `nano`.

ZRAM uses roughly one third of RAM through Debian `zram-tools`; AtlANTian does
not create disk swap by default.

## Updating AtlANTian

Check for a release without installing it:

```sh
atlantian-sysupgrade --check
```

Read the available release notes:

```sh
atlantian-sysupgrade --notes
```

Install the newest release interactively:

```sh
atlantian-sysupgrade
```

The updater:

1. selects a release that is strictly newer according to Debian version rules;
2. downloads exactly `atlantian-platform`, `atlantian-kernel` and
   `atlantian-release` for that version;
3. verifies `SHA256SUMS` and the version embedded in every package;
4. installs the AtlANTian packages with normal APT/dpkg;
5. runs `apt full-upgrade` against that release's pinned Debian Snapshot;
6. reboots normally.

During the confirmed update D3 shows three red flashes followed by three green
flashes until the reboot transition.

The daily on-board release checker **does not install updates automatically**.
It only records a newer release and shows a short notice on later SSH logins.
Explicit unattended installation is available with `atlantian-sysupgrade --yes`
for users who deliberately want it.

The release endpoint can be redirected to a compatible repository or API mirror
through `/etc/atlantian/releases.conf`.

## How releases stay current with Debian

AtlANTian tracks Debian stable without building directly from moving mirrors:

```text
Debian trixie / trixie-updates / trixie-security
                    │
          daily check at 06:00 Tomsk
                    │
                    ▼
        exact Release metadata observed
                    │
        wait for snapshot.debian.org
                    │
                    ▼
           immutable Debian Snapshot
                    │
       AtlANTian source + pinned kernel
                    │
                    ▼
          tested image + .deb packages
                    │
                    ▼
               GitHub Release
```

The watcher runs every day at **06:00 Asia/Tomsk (UTC+7)**. If main, updates or
security metadata changed, it waits until Debian Snapshot contains the exact
observed `Release` files. Only then does it freeze the new snapshot, advance the
AtlANTian Debian build number and start the normal release workflow.

This gives the project two properties at once: published AtlANTian follows
Debian closely, while each individual release remains tied to immutable Debian
metadata.

Version example:

```text
13.2.184+g0123456789ab
│  │ │     └─ exact source commit
│  │ └─────── monotonic source revision
│  └───────── AtlANTian build of the Debian base
└──────────── Debian major version
```

Older source-addressed versions are never treated as upgrades merely because
their Git hash sorts differently.

## FPGA use

AtlANTian provides the Linux control plane for programmable logic:

```sh
atlantian-fpga status
atlantian-fpga apply <instance> <overlay.dtbo>
atlantian-fpga remove <instance>
```

The shipped `status-leds` profile exposes D5-D8 through AXI GPIO:

| LED | PL pin | AXI GPIO bit |
| --- | --- | --- |
| D5 | M19 | 2 |
| D6 | M17 | 3 |
| D7 | F16 | 0 |
| D8 | L19 | 1 |

A full bitstream replaces the current PL design; unrelated full bitstreams are
not stackable. A larger custom design can preserve the existing AXI GPIO ABI and
include additional peripherals alongside the LED block.

## Building locally

Use a current Linux host with Internet access and roughly 20 GiB of free space:

```sh
git clone https://github.com/BlackF1re/atlantian.git
cd atlantian
sudo ./scripts/bootstrap-host.sh
./scripts/build-incremental.sh all
```

Development targets:

```sh
./scripts/build-incremental.sh rootfs
./scripts/build-incremental.sh kernel
./scripts/build-incremental.sh image
```

Use `all` when in doubt. Published releases are built by GitHub Actions from
`main` rather than from arbitrary local state.

Before working on a release, immutable external inputs can be checked directly:

```sh
./scripts/validate-release-inputs.sh
```

## CI and release guarantees

Pull requests run read-only CI before merge. It checks workflow YAML, shell
syntax/ShellCheck, release/update invariants, immutable release inputs and image
layout contracts.

A `main` build additionally checks the assembled image and packages, including:

- exactly three AtlANTian release packages;
- package/release version identity;
- boot partition and root partition layout;
- correct rootfs ownership and mode handling;
- absence of factory SSH private host keys;
- first-boot identity contract;
- package checksums and release metadata.

Release builds are serialised. Before publishing, a run verifies that its commit
is still the current `main` tip, preventing an older slow build from becoming
the newest release after a newer commit.

GitHub Actions dependencies are pinned to immutable commit IDs. Published
artifacts covered by `SHA256SUMS` also receive GitHub/Sigstore build-provenance
attestation.

`boot-candidate/BOOT.bin` is a pinned external binary input, not source-built in
this repository. Its Git object ID is checked by CI; provenance and limitations
are documented in [`boot-candidate/README.md`](boot-candidate/README.md).

## Repository map

| Path | Purpose |
| --- | --- |
| `board/` | Canonical CTRL_C41 Linux device tree |
| `config/` | Debian, kernel, package and image policy |
| `kernel-overlay/` | Kernel-side OF/configfs support used by AtlANTian |
| `fpga/` | Shipped FPGA profiles and firmware |
| `systemd/` | Board-specific services and first-boot policy |
| `scripts/` | Build, package, update and validation tooling |
| `boot-candidate/` | Pinned external boot firmware input |
| `docs/` | Hardware, persistence, pipeline and operational docs |
| `.github/workflows/` | PR CI, Debian watcher and release automation |

## Important non-obvious behaviour

- **`poweroff` does not cut 12 V.** Linux halts safely; CTRL_C41 has no
  software-controlled input power switch.
- **There is no battery-backed RTC.** Time becomes accurate after network time
  synchronisation or manual `timedatectl` configuration.
- **USB being compiled into Linux does not mean the board USB route is safe.**
  Base DT keeps it disabled because of known MIO overlap.
- **PL peripherals require both hardware logic and a matching DT overlay.** A
  device tree entry cannot create logic that is absent from the bitstream.
- **APT is intentionally snapshot-pinned.** `atlantian-sysupgrade` is the normal
  path for moving an installed board to the next AtlANTian/Debian snapshot.
- **Reflashing creates a new SSH identity.** A host-key warning from your SSH
  client after a deliberate reflash is expected.

## Documentation

- [Quick Start](docs/QUICKSTART.md) — flash, boot, login and first commands.
- [Hardware support matrix](docs/hardware-support-matrix.md) — pin ownership and
  supported/conditional interfaces.
- [Release pipeline](docs/PIPELINE.md) — image/package/update architecture.
- [Persistence](docs/PERSISTENCE.md) — storage and what survives updates.
- [Security](SECURITY.md) — security model and reporting.
- [BOOT.bin notes](boot-candidate/README.md) — external boot firmware boundary.

## License

AtlANTian-specific source code is licensed under **GPL-2.0-only**. Debian,
Linux, U-Boot, FPGA components and other third-party material remain under their
respective licences.
