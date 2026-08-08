# AtlANTian Quick Start

This is the shortest practical path from a released image to a usable
CTRL_C41 board.

## 1. What you need

- Bitmain Antminer S9 CTRL_C41 control board.
- microSD card large enough for the released image; 4 GiB or larger is a
  convenient minimum for normal use.
- 12 V power for the control board.
- Ethernet with DHCP **or** a 3.3 V USB-UART adapter.
- The newest AtlANTian `.img` from
  [GitHub Releases](https://github.com/BlackF1re/atlantian/releases/latest).

Do not connect a 5 V UART directly to the board's 3.3 V serial pins.

## 2. Write the image

### Windows

Use Rufus, Raspberry Pi Imager or another raw-image writer:

1. Select the released AtlANTian `.img`.
2. Select the microSD card.
3. Write the image in raw/DD mode if the program asks.
4. Safely eject the card.

### Linux

First identify the whole microSD device with `lsblk`, then write the image.
Replace `/dev/sdX` with the **whole card**, not a partition such as `/dev/sdX1`:

```sh
sudo dd if=atlantian-*.img of=/dev/sdX bs=8M status=progress conv=fsync
sync
```

Double-check the target device before pressing Enter; `dd` will overwrite it.

## 3. Boot CTRL_C41

1. Power the board off.
2. Set the CTRL_C41 boot selector/jumpers to **SD boot**.
3. Insert the written microSD card.
4. Connect Ethernet and/or UART.
5. Apply 12 V power.

UART settings:

```text
115200 baud
8 data bits
no parity
1 stop bit
no flow control
```

The first boot expands `/dev/mmcblk0p2` to the remaining card capacity and then
reboots once. This automatic reboot is expected. The following boot finishes
`resize2fs` and continues normally.

## 4. Connect

### Ethernet

AtlANTian uses DHCP through systemd-networkd. Find the assigned address in your
router/DHCP lease table and connect:

```sh
ssh root@BOARD_IP
```

The default hostname is:

```text
atlantian
```

mDNS is not assumed, so `ssh root@atlantian` is not guaranteed to resolve on
every network.

### UART

Use any serial terminal at `115200 8N1`. The kernel console and root getty are
on `ttyPS0`.

UART is the best fallback when Ethernet configuration is unknown.

## 5. First login

A fresh factory image initially permits root login with an empty password so a
new board is reachable immediately on an isolated bench network.

Set a password before using an untrusted network:

```sh
passwd
```

There is no default non-root user and no need for `sudo` in the base image.

Each flashed installation creates its own machine identity and OpenSSH host
keys on first boot. Reflashing the same board therefore produces a new SSH host
key by design.

If your workstation warns about the old key after a deliberate reflash:

```sh
ssh-keygen -R BOARD_IP
```

Then reconnect and verify the newly presented key as usual.

## 6. Verify the installation

Run:

```sh
cat /etc/os-release
uname -a
lsblk
networkctl
ip address
free -h
```

Expected high-level state:

- Debian 13 `trixie` based AtlANTian userspace;
- Linux 6.12.100 with the AtlANTian local version;
- about 512 MiB physical RAM;
- `p1` as the FAT boot partition;
- `p2` as the ext4 root filesystem using the rest of the card after first boot.

Useful hardware checks:

```sh
gpiodetect
ls -l /dev/mtd*
iio_info
ls -l /dev/watchdog0
atlantian-fpga status
```

The on-board NAND is exposed separately through MTD. The normal SD image does
not install itself into NAND and normal AtlANTian updates do not overwrite it.

## 7. Basic system setup

Set a hostname if desired:

```sh
hostnamectl set-hostname my-c41
```

Set the timezone:

```sh
timedatectl set-timezone Asia/Tomsk
```

Check time synchronisation:

```sh
timedatectl status
```

CTRL_C41 has no battery-backed RTC, so network time is important after a cold
power-off.

Install and update normal Debian packages as usual:

```sh
apt update
apt upgrade
apt install git python3 tmux
```

Published systems use the normal live Debian stable repositories for `trixie`,
`trixie-updates` and `trixie-security`. Therefore an installation does not have
to wait for a newer AtlANTian image before Debian publishes a newer package or
security fix.

The **factory build** is still produced from an immutable Debian Snapshot. That
Snapshot records exactly which Debian package versions were used to create the
image; it does not restrict APT after the image is installed.

## 8. Update AtlANTian

Check whether a newer release exists:

```sh
atlantian-sysupgrade --check
```

Show its release notes:

```sh
atlantian-sysupgrade --notes
```

Install it:

```sh
atlantian-sysupgrade
```

The updater displays the selected release, publication time and download size,
then requires the literal confirmation:

```text
UPGRADE
```

It then:

1. downloads the exact three AtlANTian packages for one newer release;
2. verifies checksums and package versions;
3. installs the platform, kernel and release packages;
4. refreshes the configured Debian repositories and runs `apt full-upgrade`;
5. reboots the board.

D3 shows three red flashes followed by three green flashes during the confirmed
update lifecycle.

For explicitly unattended use:

```sh
atlantian-sysupgrade --yes
```

The normal daily release checker only **notifies**; it does not automatically
install releases.

## 9. FPGA basics

Check the current PL state:

```sh
atlantian-fpga status
```

Apply a compatible overlay/profile instance:

```sh
atlantian-fpga apply <instance> <overlay.dtbo>
```

Remove it:

```sh
atlantian-fpga remove <instance>
```

A device-tree overlay describes hardware; it does not create FPGA logic by
itself. The loaded full bitstream must contain the peripheral described by the
overlay.

The shipped status profile exposes D5-D8 through AXI GPIO. Other PL-connected
interfaces require a matching validated bitstream and overlay.

## 10. Things that are intentionally different from a generic SBC

### `poweroff` does not remove 12 V

```sh
poweroff
```

halts Linux safely, but the control board has no software-controlled input
power switch. External 12 V remains present until it is physically removed.

### USB is disabled in the base device tree

USB support exists in the kernel, but the known PS USB route overlaps CTRL_C41
MIO wiring used by other board functions. AtlANTian does not enable it blindly.
Use USB only with a board/profile configuration whose pin ownership has been
validated.

### NAND is not the root filesystem

The standard installation boots and runs from microSD. NAND remains a separate
MTD device for experiments, backups or future layouts.

### Builds are snapshot-pinned; runtime APT is not

AtlANTian's release automation checks Debian main, updates and security every
day and freezes a matching Snapshot for reproducible factory builds. The image
records that Snapshot as build provenance.

After assembly, however, `/etc/apt/sources.list` points at the normal live
Debian stable mirrors. `apt update` therefore follows current Debian stable,
updates and security repositories even on an older AtlANTian installation.

Use `atlantian-sysupgrade` for AtlANTian-owned changes such as the board kernel,
platform policy, FPGA plumbing and release tooling; use normal APT for ordinary
Debian userspace maintenance.

## 11. Troubleshooting

### The board rebooted during first boot

Expected. Partition 2 is expanded once, followed by an automatic reboot.

### Ethernet did not get an address

Use UART and inspect:

```sh
networkctl
ip link
ip address
journalctl -u systemd-networkd --no-pager
```

Also verify physical link and DHCP on the connected network.

### SSH says the host key changed after reflashing

Expected after a deliberate reflash because every factory installation creates
new host keys. Remove only the stale entry that belongs to this board/address:

```sh
ssh-keygen -R BOARD_IP
```

### The system time is wrong after power removal

There is no RTC. Check network connectivity and:

```sh
timedatectl status
systemctl status systemd-timesyncd --no-pager
```

### `poweroff` leaves LEDs/power present

Expected. Linux is halted, but 12 V cannot be switched off in software on the
stock CTRL_C41 power path.

### A Zynq peripheral exists in the datasheet but not in Linux

That does not mean it is safely routed on this board. Check the
[hardware support matrix](hardware-support-matrix.md) before enabling additional
PS or PL interfaces.

## Next documents

- [README](../README.md) — project overview and day-to-day commands.
- [Hardware support matrix](hardware-support-matrix.md) — known routing and
  support boundary.
- [Release pipeline](PIPELINE.md) — how images, packages and automated Debian
  updates are produced.
- [Persistence](PERSISTENCE.md) — storage model and update persistence.
- [Security](../SECURITY.md) — initial-access model and security reporting.
