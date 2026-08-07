# AtlANTian GNU/Linux

AtlANTian GNU/Linux is a small Debian-based system for the Bitmain Antminer S9
CTRL_C41 control board. The board is built around a Xilinx Zynq-7010, and the
project treats it as a useful Zynq development board rather than as a mining
appliance.

The goal is to boot a lightweight, flexible and maintainable GNU/Linux system
from microSD, expose the hardware genuinely wired to the Processing System
(PS), and leave the Programmable Logic (PL) available for experiments and
specialised devices.

AtlANTian is not a desktop distribution and does not pretend that every Zynq
peripheral is electrically available on this PCB. Interfaces are enabled only
when their routing and pin ownership are understood.

## What is supported

The base image supports the hardware which is safe without loading a custom PL
design:

- Zynq-7010 Processing System and 512 MiB DDR3.
- microSD boot and root storage (`/dev/mmcblk0`).
- The on-board 256 MiB NAND through MTD (`/dev/mtd*`), including UBI/UBIFS and
  software BCH ECC appropriate for the fitted NAND.
- MACB/GEM Ethernet, MDIO PHY access, DHCP and SSH. Because the board has no
  dependable factory MAC address, systemd derives a stable locally-administered
  address from the unique machine identity generated for each installation.
- The 3.3 V UART on `ttyPS0`, with a 115200 8N1 serial console and getty.
- PS GPIO for the two board buttons, D2/D3 LEDs, buzzer and hash-board enable
  signals.
- Zynq XADC through the standard IIO and hwmon interfaces.
- The Zynq watchdog (`/dev/watchdog0`).
- FPGA Manager, FPGA Region and device-tree overlay support.
- Standard command-line tools for GPIO, I2C, SPI, MDIO, XADC/IIO, MTD,
  networking and basic hardware work.

AtlANTian deliberately avoids a desktop environment, PYNQ/Jupyter and other
large software which is not needed to boot, communicate with, or develop on
the board. Normal Debian packages can be installed later with APT.

## Board-specific behaviour

The image is root-only by design, similar to OpenWrt. A newly written image
allows root SSH login with an empty password so the board is immediately
reachable on an isolated bench network. Set a password before connecting the
board to an untrusted network:

```sh
passwd
```

Every flashed card generates its own system machine identity and SSH host keys
on first boot. No SSH server private key from the build environment is shipped
inside the factory image.

There is no `sudo` account in the base system. ZRAM uses roughly one third of
RAM through Debian's `zram-tools`; no disk swap partition or swap file is
created.

The paired user-visible D3 LEDs are handled by a lightweight service:

- red: a two-pulse heartbeat whose interval becomes shorter as CPU load rises;
- green: microSD read/write activity.

D2 is active-low. D1 is the FPGA `DONE` indicator and D15 is the 3.3 V
power-good indicator; neither is Linux-controlled. D9..D14 are protection
diodes on the six fan tachometer inputs, not LEDs.

The board buttons are exported as `s1_short` and `s2_long`; no default action is
assigned to either one.

`reboot`, `halt`, `shutdown` and `poweroff` use normal systemd paths. `poweroff`
halts Linux safely but cannot remove the external 12 V supply because CTRL_C41
has no software-controlled input power switch.

There is no battery-backed RTC. `systemd-timesyncd` corrects time once network
access is available; manual time setting works through `timedatectl`.

## Storage layout and first boot

The factory image contains two ordinary partitions:

| Partition | Purpose |
| --- | --- |
| `p1` | 64 MiB FAT boot partition |
| `p2` | ext4 root filesystem (`/`) |

On first boot, `atlantian-grow-rootfs` extends `p2` to the rest of the inserted
card and reboots once so the kernel sees the new partition size. The following
boot runs `resize2fs` and proceeds normally.

Afterwards AtlANTian is a conventional Debian filesystem. `/etc`, `/root`,
`/home`, `/var`, installed packages, logs and APT state all live on `/`. There
are no overlays, hidden state partitions or special package-cache paths.

The NAND is separate from the SD installation. Normal boot and release updates
do not overwrite it. Raw NAND backups must preserve bad-block information and
OOB/ECC assumptions.

## FPGA profiles

The PL is not a plug-and-play GPIO expander. A PL peripheral exists only when a
matching full bitstream and device-tree overlay describe it.

AtlANTian provides the control plane:

```sh
atlantian-fpga status
atlantian-fpga apply <instance> <overlay.dtbo>
atlantian-fpga remove <instance>
```

The shipped `status-leds` profile exposes D5-D8 as normal Linux LED-class
devices:

| LED | PL pin | AXI GPIO bit |
| --- | --- | --- |
| D5 | M19 | 2 |
| D6 | M17 | 3 |
| D7 | F16 | 0 |
| D8 | L19 | 1 |

The profile is intentionally small. A different full bitstream replaces the PL
design; independent full bitstreams cannot be stacked. A larger design can
retain the same AXI GPIO ABI and include the LED block alongside other logic.

The six fan connectors, hash-board headers, PL I2C/SPI/UART, displays, cameras,
audio, SDR and similar interfaces require their own validated profiles.

USB support is compiled into the kernel but USB is disabled in the base device
tree. The known PS USB route overlaps physical MIO wiring used by hash-board
enables and D3, so it must only be enabled by an explicitly verified profile.
The same principle applies to unused PS I2C/SPI controllers.

## Updating

`atlantian-sysupgrade` updates an installed board from published AtlANTian
releases with normal APT/dpkg transactions. It downloads the exact three
packages belonging to one release, verifies them against `SHA256SUMS`, verifies
that every package carries the selected release version, installs them, then
runs `apt full-upgrade` against that release's pinned Debian Snapshot.

Release versions are monotonic and source-addressed, for example:

```text
13.2.184+g0123456789ab
```

The Debian build number (`13.2`) advances when the frozen Debian base changes;
the next component is the source position in the repository history, and the
Git suffix identifies the exact source commit. The updater uses Debian version
comparison and will not offer or install an older release as an update.

Run:

```sh
atlantian-sysupgrade
```

The command shows the installed and available version, publication time,
download size and release notes, then requires the literal confirmation
`UPGRADE`. `--check`, `--notes` and explicit unattended `--yes` modes are also
available.

After confirmation the normal D3 services stop and the update pattern starts:
three red flashes followed by three green flashes. It remains active during
download, verification, package installation, `apt full-upgrade` and the
transition to reboot.

`atlantian-release-check` runs after boot and once per day. It records a newer
release under `/var/lib/atlantian/update`; SSH logins then display a short
notice until that release is installed. Updates are not applied automatically.

The release endpoint is configured in `/etc/atlantian/releases.conf`, so a
compatible fork or API mirror can be selected without editing the updater.

## Building locally

Build on a current Linux host with Internet access and roughly 20 GiB of free
disk space:

```sh
git clone https://github.com/BlackF1re/atlantian.git
cd atlantian
sudo ./scripts/bootstrap-host.sh
./scripts/build-incremental.sh all
```

Narrower targets are available for development:

```sh
./scripts/build-incremental.sh rootfs
./scripts/build-incremental.sh kernel
./scripts/build-incremental.sh image
```

Use `all` whenever the relationship between changes is uncertain.

## Releases and automation

GitHub Actions builds releases from `main`. Builds are serialised and a run is
allowed to publish only if its commit is still the current `main` tip, so an
older slow build cannot become the newest release after a newer commit.

Every day at **06:00 Tomsk time (UTC+7)** the Debian watcher checks the selected
Debian stable suite, its `-updates` suite and `-security`. If repository metadata
changed, it waits until `snapshot.debian.org` contains exactly the observed
Release files, freezes that snapshot, advances the AtlANTian Debian build number
and starts a normal release build automatically.

Each published release contains:

- the factory SD image;
- `atlantian-platform`, `atlantian-kernel` and `atlantian-release` packages;
- SHA-256 sums;
- the resolved Debian package manifest;
- Debian Snapshot metadata;
- build metadata.

GitHub Actions are pinned to immutable commit IDs. Release artifacts covered by
`SHA256SUMS` also receive a Sigstore-backed GitHub Actions build-provenance
attestation, giving an independently verifiable record of which repository,
workflow and commit produced them.

The root filesystem is cached only as a root-created compressed archive which
preserves numeric UID/GID, ACL and xattr metadata. Cached trees are restamped
with the current release identity before packaging, so an incremental build
cannot inherit an older version marker.

`boot-candidate/BOOT.bin` remains a pinned external binary boot-firmware input;
its Git object ID is checked by CI and its limitation is documented in
`boot-candidate/README.md`. AtlANTian does not claim that this vendor boot bundle
is reproducible from this repository.

Pull requests run a read-only CI contract: workflow YAML parsing, shell syntax
and ShellCheck errors, release/update invariants, boot-input pinning and image
layout source checks. The PR template asks contributors to state hardware impact
and validation explicitly.

## Useful packages already present

The base image includes `htop`, `pigz`, `gpiod`, `i2c-tools`, `spi-tools`,
`can-utils`, `lm-sensors`, `libiio-utils`, `alsa-utils`, `v4l-utils`, `usbutils`,
`mtd-utils`, `dtc`, `ethtool`, `iproute2`, `nftables`, `curl`, `jq`, `kmod`,
`procps`, `less` and `nano`, together with the normal systemd, OpenSSH and
network components.

## Project scope

AtlANTian is a board distribution built on Debian, not a replacement for
Debian or a new upstream kernel. Debian supplies the overwhelming majority of
userspace and security maintenance. AtlANTian supplies the board description,
small policy layer, FPGA-profile plumbing, tested factory image and a controlled
way to build and update it.

For pin assignments and the current support boundary, see
`docs/hardware-support-matrix.md`. For the release/update flow, see
`docs/PIPELINE.md`.

## Licensing and rights

AtlANTian-specific source code is licensed under GNU GPL version 2 only
(`GPL-2.0-only`). Debian packages, Linux, U-Boot, FPGA components and other
third-party material remain subject to their respective licences.
