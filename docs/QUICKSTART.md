# AtlANTian Quick Start

## Requirements

- Bitmain Antminer S9 CTRL_C41 control board;
- microSD card (4 GiB or larger recommended);
- 12 V board power;
- Ethernet with DHCP and/or a **3.3 V** USB-UART adapter;
- the newest AtlANTian `.img` from GitHub Releases.

Do not connect 5 V logic to the board UART.

## Write the image

On Windows use Rufus, Raspberry Pi Imager or Etcher in raw/DD mode. On Linux:

```sh
sudo dd if=atlantian-*.img of=/dev/sdX bs=8M status=progress conv=fsync
sync
```

Use the whole card device, not a partition, and verify `/dev/sdX` carefully.

## First boot

1. Power the board off and select SD boot.
2. Insert the microSD card and connect Ethernet/UART.
3. Apply 12 V.
4. The first boot expands `/dev/mmcblk0p2` and reboots once.
5. Connect over DHCP or UART (`115200 8N1`).

The default hostname is `atlantian`. A fresh image permits root access with an
empty password for initial bench provisioning. Immediately run:

```sh
passwd
```

Do not expose an unconfigured image to an untrusted network.

Each flash creates a new machine ID and OpenSSH host keys. After reflashing, an
SSH client may need the deliberately stale host key removed with
`ssh-keygen -R BOARD_IP`.

## Verify

```sh
cat /etc/os-release
uname -a
lsblk
networkctl
ip address
free -h
atlantian-fpga status
```

Expected high-level state is the current Debian stable release selected by the
AtlANTian release automation, `armhf` userspace, the pinned board kernel, a FAT
boot partition and an ext4 root partition expanded to the card.

## Packages

Runtime APT uses live Debian repositories for the installed codename, not the
factory Snapshot:

```sh
apt update
apt upgrade
apt install git python3 tmux
```

The codename is intentionally fixed for the lifetime of that Debian major.
When Debian publishes a new stable release, AtlANTian's repository automation
builds a new major only if `armhf` remains supported; an installed board changes
major only through `atlantian-sysupgrade`.

## AtlANTian updates

```sh
atlantian-sysupgrade --check
atlantian-sysupgrade --notes
atlantian-sysupgrade
```

The updater verifies all three AtlANTian packages and checksums. A Debian major
upgrade is staged one major at a time. Third-party files under
`/etc/apt/sources.list.d/` are backed up and disabled during that transition so
an old external repository cannot contaminate the new Debian base. The backup
location is recorded under `/var/lib/atlantian/update/`.

The periodic on-board checker only notifies; it does not install releases
without an explicit `atlantian-sysupgrade` (or `--yes`).

## FPGA basics

```sh
atlantian-fpga status
atlantian-fpga apply <instance> <overlay.dtbo>
atlantian-fpga remove <instance>
```

A DT overlay describes hardware but does not create FPGA logic. The loaded
bitstream must implement the peripheral described by the overlay.

## Board-specific notes

- `poweroff` halts Linux but does not remove external 12 V.
- CTRL_C41 has no battery-backed RTC; network time is important after cold boot.
- The base DT keeps the conflicted PS USB route disabled.
- NAND is a separate MTD device; normal SD updates do not overwrite it.
- Not every peripheral present in the Zynq datasheet is safely routed on this
  PCB. Consult [hardware-support-matrix.md](hardware-support-matrix.md).

## Troubleshooting

If Ethernet has no address, use UART and inspect:

```sh
networkctl
ip link
ip address
journalctl -u systemd-networkd --no-pager
```

If time is wrong:

```sh
timedatectl status
systemctl status systemd-timesyncd --no-pager
```

If the board rebooted once on the first boot, that is expected root-filesystem
expansion behavior.

Further reading: [README](../README.md), [Debian lifecycle](DEBIAN-LIFECYCLE.md),
[release pipeline](PIPELINE.md), [persistence](PERSISTENCE.md), and
[security policy](../SECURITY.md).
