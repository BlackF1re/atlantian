# Quick Start

## What you need

| Item | Requirement |
|---|---|
| Board | Bitmain Antminer S9 CTRL_C41 |
| Storage | microSD, 4 GiB or larger recommended |
| Power | external 12 V board supply |
| Network | Ethernet with DHCP |
| Console | optional 3.3 V USB-UART, `115200 8N1` |
| Image | newest AtlANTian `.img` + `SHA256SUMS` from GitHub Releases |

> [!CAUTION]
> The board UART is **3.3 V logic**. Do not connect 5 V UART logic.

## 1. Verify the download

From the directory containing the image and `SHA256SUMS`:

```sh
sha256sum -c SHA256SUMS --ignore-missing
```

Expected result for the image is `OK`.

Optional provenance verification with GitHub CLI:

```sh
gh attestation verify atlantian-*.img --repo BlackF1re/atlantian
```

`BUILD-INFO.txt` records the source commit, Debian Snapshot and kernel identity
used for the release.

## 2. Write the image

**Windows:** use Rufus, Raspberry Pi Imager or Etcher in raw/DD mode.

**Linux:**

```sh
sudo dd if=atlantian-*.img of=/dev/sdX bs=8M status=progress conv=fsync
sync
```

> [!WARNING]
> Use the whole card device, not a partition, and verify `/dev/sdX` carefully.

## 3. First boot

1. Power the board off and select SD boot.
2. Insert the microSD card.
3. Connect Ethernet and/or UART.
4. Apply 12 V.
5. Wait for automatic root-filesystem expansion and one reboot.
6. Connect over DHCP or UART.

| Default | Value |
|---|---|
| Hostname | `atlantian` |
| User | `root` |
| Password | empty by design for initial provisioning |
| UART | `115200 8N1` |

> [!IMPORTANT]
> Passwordless root provisioning is intentional appliance-style behavior,
> similar to OpenWrt. Keep a fresh board on a trusted network. Run `passwd` or
> install your SSH public key when you want authenticated access.

Every flash generates a new machine ID and SSH host keys. After reflashing, an
SSH client may need the old key removed:

```sh
ssh-keygen -R BOARD_IP
```

## 4. Verify the system

```sh
cat /etc/os-release
uname -a
lsblk
networkctl
ip address
free -h
atlantian-fpga status
```

Expected high-level state:

- current AtlANTian-selected Debian stable, `armhf` userspace;
- pinned CTRL_C41 board kernel;
- FAT boot partition + ext4 root partition;
- root filesystem expanded to the microSD card;
- live Debian runtime repositories.

## 5. Install packages

```sh
apt update
apt upgrade
apt install git python3 tmux
```

The factory image is built from an immutable Debian Snapshot; the running board
uses live repositories for its installed codename.

## AtlANTian updates

```sh
atlantian-sysupgrade --check
atlantian-sysupgrade --notes
atlantian-sysupgrade
```

For normal APT maintenance, AtlANTian releases and Debian-major transitions,
see **[Upgrading](UPGRADING.md)**.

## FPGA basics

```sh
atlantian-fpga status
atlantian-fpga apply <instance> <overlay.dtbo>
atlantian-fpga remove <instance>
```

A DT overlay describes hardware; it does not create FPGA logic. The loaded
bitstream must implement the peripheral described by the overlay.

## Board behavior

| Topic | Behavior |
|---|---|
| `reboot` | supported restart path |
| `poweroff` | halts Linux; external 12 V remains present |
| suspend/hibernate | intentionally not advertised; reliable resume is not validated |
| RTC | none fitted; network time matters after cold boot |
| USB | conflicted PS route is disabled in the base DT |
| NAND | separate MTD device; normal SD updates do not overwrite it |
| PL peripherals | require a matching bitstream + DT overlay |

Electrical and pin-level detail belongs in the
**[Hardware support matrix](hardware-support-matrix.md)**.

## Troubleshooting

| Symptom | Check |
|---|---|
| no Ethernet address | `networkctl`, `ip link`, `ip address` |
| network service issue | `journalctl -u systemd-networkd --no-pager` |
| wrong time | `timedatectl status` |
| NTP issue | `systemctl status systemd-timesyncd --no-pager` |
| one reboot on first boot | expected rootfs expansion behavior |
| SSH host-key warning after reflash | `ssh-keygen -R BOARD_IP` |

Further reading: [documentation index](README.md), [persistence](PERSISTENCE.md)
and [security](../SECURITY.md).
