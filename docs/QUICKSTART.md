# Quick start: microSD

This is the normal first boot and recovery path for AtlANTian.

## 1. Write the image

Download the versioned `atlantian-<version>.img.xz` from the GitHub Release. Write it directly with an imaging tool that supports XZ, or decompress it first and write the raw image.

The image contains:

- partition 1: FAT BOOT;
- partition 2: ext4 root filesystem.

Do not copy the image file onto an existing filesystem; write it as a disk image.

## 2. Select SD boot

Power the board off, set the physical boot-source jumper to SD, insert the microSD and power on.

UART console is `115200 8N1` on `ttyPS0`. Normal boot loads `boot.scr`, selects the active A/B FIT and starts Linux from partition 2.

## 3. First boot

The SD root filesystem grows to the available partition/card capacity through `atlantian-grow-rootfs.service`. Ethernet is configured by `systemd-networkd` for DHCP with IPv6 RA support.

To discover the assigned address, check your DHCP server/router or use the UART console:

```sh
ip address show
ip route
```

## 4. Login

SSH is enabled. Use the credentials/access policy shipped by the current image. On interactive login, AtlANTian prints release, kernel, storage and update information.

After login, verify the running identity:

```sh
cat /etc/os-release
cat /usr/lib/atlantian/version
uname -a
```

## 5. Check hardware

A compact first check:

```sh
ip link
lsusb
ls /sys/class/fpga_manager
systemctl --failed
```

For the full board checklist, use [HARDWARE-VALIDATION.md](HARDWARE-VALIDATION.md).

## Next steps

- Keep running from SD for development and easiest recovery.
- To install to raw NAND, follow [INSTALLATION.md](INSTALLATION.md).
- To update an existing installation, use [UPGRADING.md](UPGRADING.md).
- Storage/persistence behavior is documented in [PERSISTENCE.md](PERSISTENCE.md).
