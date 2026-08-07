# AtlANTian GNU/Linux

AtlANTian GNU/Linux is a small Debian-based system for the Bitmain Antminer S9 CTRL_C41 control board. The board is built around a Xilinx Zynq-7010, and the project treats it as a useful Zynq development board rather than as a mining appliance.

The goal is simple: boot a lightweight, flexible, and maintainable GNU/Linux system from microSD, expose the hardware that is genuinely wired to the processing system (PS), and leave the programmable logic (PL) available for experiments. The resulting platform can serve as the basis for specialised devices that make use of the FPGA.

It is not a desktop distribution, and it does not try to turn every connector into a permanently enabled interface before its electrical routing has been verified. There are important board-level routing and pin-multiplexing constraints.

## What is supported

The base image supports the parts of the board that can be used safely without loading a custom FPGA design:

- Zynq-7010 Processing System and 512 MiB DDR3.
- microSD boot and root storage (`/dev/mmcblk0`).
- The on-board 256 MiB NAND through MTD (`/dev/mtd*`), including UBI/UBIFS tools and NAND-aware backup tooling. The device tree uses the appropriate software BCH ECC configuration rather than the old one-bit Hamming setup.
- The MACB/GEM Ethernet controller, MDIO PHY access, DHCP, and SSH. The board has no dependable factory MAC address, so AtlANTian assigns a stable locally administered address.
- The 3.3 V UART on `ttyPS0`, with a 115200 8N1 serial console and getty.
- PS GPIO for the two board buttons, D2/D3 LEDs, buzzer, and the hash-board enable signals.
- Zynq XADC through the standard IIO and hwmon interfaces. `sensors` can report the die temperature and supply rails exposed by XADC.
- The Zynq watchdog (`/dev/watchdog0`).
- FPGA Manager and device-tree overlay support. Bitstreams can be loaded at runtime without rebuilding the operating system.
- Standard command-line tools for GPIO, I2C, SPI, MDIO, XADC/IIO, MTD, network inspection, and basic hardware work.

AtlANTian deliberately avoids a desktop environment, PYNQ/Jupyter, and other software that does not help this board boot, communicate, or be developed on. These packages can be installed later if a particular project needs them.

## Board-specific behaviour

The image is root-only by design, as in OpenWrt. Root is allowed to log in over SSH with an empty password on a newly written image so that a fresh board is reachable immediately.
This is convenient on an isolated bench network and very unsafe anywhere else. Set a password before connecting the board to an untrusted network:

```sh
passwd
```

There is no `sudo` account in the base system. The login banner reminds the user until a root password has been set.

ZRAM is configured with the standard `zramswap` package and uses roughly one third of RAM. AtlANTian does not create a disk swap partition or swap file.

The paired user-visible D3 LEDs are handled by a lightweight service:

- red: a two-pulse heartbeat; the interval between pairs gets shorter as total CPU load rises;
- green: microSD read/write activity.

The signals are active-high. D2 is active-low.

The board buttons are exported as `s1_short` and `s2_long`; no action is assigned to either button by default.

D1 is the FPGA `DONE` indicator and D15 is a 3.3 V power-good indicator. They are hardware status lights, not Linux-controlled LEDs.
D9..D14 are not missing LEDs: they are 1N4148 protection diodes on the fan tach inputs.

`reboot`, `halt`, `shutdown`, and `poweroff` use normal systemd paths. `poweroff` halts Linux safely but cannot remove the 12 V supply from the board; the CTRL_C41 has no controllable input power switch, unfortunately.

The board has no battery-backed RTC. Once a network is available, systemd-timesyncd can correct time from NTP; manual time setting works through `timedatectl`.

## Storage layout and first boot

The release image contains two ordinary partitions:

| Partition | Purpose |
| --- | --- |
| `p1` | FAT boot partition |
| `p2` | normal ext4 root filesystem (`/`) |

On its first successful boot, `atlantian-grow-rootfs` enlarges `p2` to fill the inserted card and then reboots once. This means the image can be written directly with Rufus, `dd`, Raspberry Pi Imager, or a similar raw-image writer. No manual partitioning is required.

After that first boot, AtlANTian has a conventional Debian filesystem. `/etc`,
`/root`, `/home`, `/var`, installed packages, logs and APT state live on `/`.
There are no overlays, bind mounts, hidden state directories, or special APT
cache paths. This is deliberately the same persistence model used by Debian
and Ubuntu.

The NAND is separate from the SD installation. AtlANTian exposes it, but does not overwrite it as part of normal booting or updating. A raw NAND backup must retain the bad-block information as well as the contents; copying a mounted filesystem is not a replacement for an MTD-aware backup.

## Interfaces which need an FPGA profile

The FPGA is not a plug-and-play GPIO expander. A PL peripheral is available only when both the active bitstream and its device-tree overlay describe it.


AtlANTian includes the FPGA Manager, firmware loader, overlay support, and the `atlantian-fpga` helper so that profiles can be installed and activated cleanly:

```sh
atlantian-fpga status
atlantian-fpga apply <instance> <overlay.dtbo>
atlantian-fpga remove <instance>
```

The shipped `status-leds` profile exposes the populated PL LEDs D5-D8 as standard Linux LED-class devices and leaves them off by default. They are active-low and are mapped as follows:

| LED | PL pin | AXI GPIO bit |
| --- | --- | --- |
| D5 | M19 | 2 |
| D6 | M17 | 3 |
| D7 | F16 | 0 |
| D8 | L19 | 1 |

That profile is intentionally small. It demonstrates the expected AXI GPIO interface, and another bitstream can retain that interface if it also wants the four LEDs. A completely different bitstream replaces the PL design; separate PL projects are not automatically stacked together.

The six four-wire fan connectors, their shared PWM output, and their independent tachometer inputs also require a fan-control PL profile. The same is true for the hash-board headers and their I2C, SPI, UART, display, camera, audio, SDR, MIDI, or other experimental interfaces. AtlANTian is prepared to host such profiles, but it does not pretend these peripherals exist in the base device tree when no matching FPGA design has been loaded.

USB support is compiled into the kernel, but USB is disabled in the base device tree. On this board the known PS USB pin route overlaps the physical hash-board-enable wiring on MIO28-MIO36, while D3 uses MIO37-MIO38. It should only be enabled by a profile after the intended wiring and conflicts have been checked on the actual board.

The PS I2C and SPI controllers are available in the kernel but intentionally disabled in the base device tree. They can be enabled by a board-specific overlay once the connector routing and electrical level have been confirmed.

## Updating

`atlantian-sysupgrade` updates an installed board from a published AtlANTian
release using normal APT/dpkg transactions. It installs the release's three
AtlANTian packages (platform policy, kernel and release metadata), after
verifying them against the release's `SHA256SUMS`, then runs
`apt full-upgrade` against the pinned Debian Snapshot. It does not rewrite
partitions or use a recovery environment. Local files and normal Debian
configuration persist: `/etc`, SSH keys, `/root`, `/home`, `/var`, package
databases and packages installed by the user remain in place. Modified Debian
conffiles are retained by default.

During the package transaction the normal LED services are stopped and the
update pattern owns the LEDs exclusively: three red flashes, then three green
flashes, repeating.

Run the updater with no arguments. It shows the installed and available release,
publication time, package download size and release notes, then requires the
literal confirmation `UPGRADE`:

```sh
atlantian-sysupgrade
```

`atlantian-release-check` runs after boot and daily. It records a newer release
under `/var/lib/atlantian/update`; SSH logins repeat the simple
`atlantian-sysupgrade` command until that release is installed.
Automatic application is off by default. Its configuration lives in
`/etc/default/atlantian-release-check`.

`atlantian-sysupgrade --check` refreshes and displays the available release,
`--notes` prints its notes, and `--yes` is available for explicitly unattended
operation. The release source is configured in
`/etc/atlantian/releases.conf`; a compatible GitHub fork or API mirror can be
selected there without editing the updater.

## Building locally

Building is done on a Linux host, not on the board. A current Ubuntu host, Internet access, and roughly 20 GiB of free disk space are sensible minimums.

```sh
git clone https://github.com/BlackF1re/atlantian.git
cd atlantian
sudo ./scripts/bootstrap-host.sh
./scripts/build-incremental.sh all
```

The incremental builder has narrower targets when only one part changed:

```sh
./scripts/build-incremental.sh rootfs
./scripts/build-incremental.sh kernel
./scripts/build-incremental.sh image
```

Use `all` when the relationship between changes is unclear. A Debian base update is treated as a full image rebuild. Build and deployment details for the normal network pipeline are in `docs/PIPELINE.md`.

## Releases and automation

Releases are built on GitHub Actions. A commit to `main` and a manual workflow run both create a source-addressed release. The release version follows the Debian major version and AtlANTian build number, with the twelve-character source commit suffix included for traceability, for example `v13.11+g0123456789ab`.

Each release contains the SD image, the three `.deb` packages used by
`atlantian-sysupgrade`, SHA-256 sums, a resolved Debian package manifest,
Debian snapshot metadata, and build metadata. The root filesystem is built
from an explicit Debian Snapshot archive; the scheduled watcher advances that
snapshot only after it verifies the archived `Release` file matches the Debian
update it detected. GitHub Actions are pinned to immutable commit IDs.

The project uses Conventional Commits. Release notes are intentionally concise: they describe the Debian change that triggered an automated rebuild or the commits that have landed since the previous AtlANTian release.

## Useful packages already present

The base image includes `htop`, `pigz`, `gpiod`, `i2c-tools`, `spi-tools`, `lm-sensors`, `libiio-utils`, `alsa-utils`, `v4l-utils`, `usbutils`, `mtd-utils`, `dtc`, `ethtool`, `iproute2`, `nftables`, `curl`, `kmod`, `procps`, `less`, and `nano`, along with the normal systemd, OpenSSH, and network components. These tools are present to make the board practical as a lab, router, or small server platform without making a claim that every optional PL peripheral is already instantiated.

## Project scope

AtlANTian is a board distribution built on Debian, not a replacement for Debian itself or a new upstream kernel. Its value is the board description, sensible defaults, tested image layout, FPGA-profile plumbing, and a reproducible way to build and update the system. Debian remains responsible for the overwhelming majority of user-space software and security maintenance.

For pin assignments, electrical notes, and the current support boundary, see `docs/hardware-support-matrix.md`. For the factory-install and update flow, see `docs/PIPELINE.md`.

## Licensing and rights

AtlANTian-specific source code is licensed under the GNU General Public License, version 2 only (`GPL-2.0-only`). See [`LICENSE`](LICENSE). Debian packages, Linux, U-Boot, FPGA components, and other third-party material remain subject to their respective licences.

If you believe that this repository infringes anyone's rights, please contact the maintainer so that the matter can be reviewed promptly.
