# Legacy boot firmware reference

The binary in this directory is retained only as a **legacy comparison input**.
It is no longer used to assemble AtlANTian factory images.

Real-board testing on 2026-08-09 established the failure boundary precisely:

- the same AtlANTian SD card boots a 512 MiB CTRL_C41;
- on two 1 GiB CTRL_C41 boards the legacy SD `BOOT.bin` produces no UART output;
- the factory NAND FSBL/U-Boot on a 1 GiB board detects `1008 MiB` correctly;
- that NAND U-Boot can read the AtlANTian FAT partition and manually boot the
  AtlANTian kernel + DT + ext4 rootfs;
- Linux 6.12.100 then reports the full 1 GiB physical address range and about
  980 MiB usable RAM.

That isolates the old SD first-stage bundle rather than Linux, the DT, the SD
slot, or the root filesystem.

## Production boot chain

AtlANTian now builds the SD boot firmware from pinned upstream **mainline
U-Boot** using `bitmain_antminer_s9_defconfig`:

```text
Zynq BootROM
   -> spl/boot.bin (copied as BOOT.bin)
   -> u-boot.img from FAT partition 1
   -> boot.scr
   -> AtlANTian uImage + devicetree.dtb
   -> /dev/mmcblk0p2
```

The pinned version/commit lives in [`config/u-boot.env`](../config/u-boot.env)
and is built by [`scripts/build-uboot.sh`](../scripts/build-uboot.sh).

Upstream Antminer S9 support was introduced specifically for the 256 MiB,
512 MiB and 1 GiB board variants and uses `get_ram_size()` against a 1 GiB
maximum probe window. AtlANTian therefore keeps one image for 512 MiB and 1 GiB
boards and does not pass a Linux `mem=` limit.

> [!IMPORTANT]
> CI can prove the source pin, generated SPL/U-Boot artifacts, FAT boot layout,
> boot script and dynamic-memory contracts. A new boot-firmware revision still
> requires real-board cold-boot validation on both 512 MiB and 1 GiB CTRL_C41.
