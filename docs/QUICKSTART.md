# Quick start: microSD

This is the normal first-boot and recovery path for AtlANTian.

## 1. Write the image

Download the versioned `atlantian-<version>.img.xz` from the GitHub Release. Write it directly with an imaging tool that supports XZ, or decompress it first and write the raw `.img`.

The image contains exactly two normal partitions:

- partition 1: 48 MiB FAT BOOT;
- partition 2: ext4 root filesystem.

There is no hidden update/state partition. Do not copy the image file onto an existing filesystem; write it as a disk image.

## 2. Select SD boot

Power the board off, set the physical boot-source jumper to **SD**, insert the microSD and power on.

UART console is `115200 8N1` on `ttyPS0`. Normal boot loads `boot.scr`, selects the active A/B FIT and starts Linux from partition 2.

## 3. First boot

The default hostname is `atlantian`.

`atlantian-grow-rootfs.service` expands partition 2 and its ext4 filesystem to the available card capacity. If the partition table must be extended, AtlANTian automatically reboots once and completes `resize2fs` on the following boot; this reboot is part of normal first-boot provisioning.

Ethernet is configured by `systemd-networkd` for DHCP with IPv6 RA support. To discover the assigned address, check your DHCP server/router or use the UART console:

```sh
ip address show
ip route
```

## 4. Login

SSH is enabled. A fresh published image deliberately enables `root` with an empty password for first provisioning:

```sh
ssh root@<board-ip>
```

If the SSH client prompts for a password, submit an empty password by pressing Enter. Set a real root password or install an SSH public key before exposing the board to an untrusted network:

```sh
passwd
```

SSH host keys are generated uniquely on the installed system; the image does not ship a shared host private key.

After login, verify the running identity:

```sh
cat /etc/os-release
cat /usr/lib/atlantian/version
cat /usr/lib/atlantian/storage-edition
uname -a
```

A normal microSD boot reports storage edition `sd`.

## 5. Check hardware

A compact first check of interfaces enabled by the base system:

```sh
ip link
ls /sys/class/leds
atlantian-fpga status
sensors
systemctl --failed
```

The packaged D5-D8 `status-leds` FPGA profile is loaded at boot on a best-effort basis. It is deliberately non-fatal and will not replace another active administrator-selected FPGA overlay. The PS-side LEDs, Ethernet, UART and the rest of Linux do not depend on that optional PL profile succeeding.

For the full board checklist, use [HARDWARE-VALIDATION.md](HARDWARE-VALIDATION.md). Exact support and routing boundaries, including interfaces that are intentionally unavailable or profile-only, are in [hardware-support-matrix.md](hardware-support-matrix.md).

## Next steps

- Keep running from SD for development and easiest recovery.
- Check for a newer authenticated release with `atlantian-sysupgrade --check`.
- To install to raw NAND, follow [INSTALLATION.md](INSTALLATION.md).
- To update an existing installation, use [UPGRADING.md](UPGRADING.md).
- Storage/persistence behavior is documented in [PERSISTENCE.md](PERSISTENCE.md).
