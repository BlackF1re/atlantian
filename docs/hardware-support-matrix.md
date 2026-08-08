# Hardware support: CTRL_C41 V1.30

This matrix separates **physical evidence** from **software availability**.

| Status | Meaning |
|---|---|
| **Ready** | available through the base image and backed by board/runtime evidence |
| **Validation** | implementation exists, but this exact low-level revision still needs cold-boot confirmation |
| **Profile** | framework is present; a matching FPGA bitstream/DT overlay owns the pins |
| **External** | board function exists but is not a Linux-controlled peripheral |
| **Not fitted** | expected device/function is not populated on CTRL_C41 |
| **Disabled** | intentionally not enabled until routing/electrical safety is proven |

> [!NOTE]
> CI validates every current release candidate, but that does not imply every
> physical peripheral is bench-tested again for every build. Bench evidence is
> recorded separately below.

## Support matrix

| Hardware / function | Status | Linux interface / decision |
|---|---|---|
| XC7Z010 PS, dual Cortex-A9 | Ready | ARM/Zynq SMP platform, timers, PMU, reset/SLCR |
| 512 MiB / 1 GiB DDR3 | Ready | Linux + DT validated on both capacities; no `mem=` cap; HIGHMEM enabled |
| source-built SD first stage | Validation | mainline S9 U-Boot SPL + `u-boot.img`; exact new revision needs 512 MiB + 1 GiB cold-boot confirmation |
| microSD root | Ready | `/dev/mmcblk0`; FAT boot + ext4 root; first boot expands ext4 |
| 256 MiB Micron MT29F2G08 NAND | Ready | MTD + UBI/UBIFS; software BCH 4-bit/512-byte ECC |
| Gigabit Ethernet GEM0/RGMII-ID | Ready | MACB, PHY address 1, MDIO, `ethtool`, DHCP, persistent local MAC |
| UART1 on J12 | Ready | `ttyPS0`, console/getty `115200 8N1` |
| D2 / D3 status LEDs | Ready | Linux LED class; D3 red heartbeat, green SD activity |
| S1 / S2 buttons | Ready | Linux input; no destructive default action |
| buzzer / J1-J9 enables | Ready | named GPIO lines; intentionally left input/high-Z until claimed |
| XADC | Ready | IIO/hwmon: die temperature and Zynq rails |
| Zynq watchdog | Ready | `/dev/watchdog0`; automatic recovery policy remains conservative |
| FPGA DevCfg/PCAP | Ready | FPGA Manager/Region + firmware loader + configfs overlays |
| PL LEDs D5-D8 | Profile | shipped `status-leds` AXI GPIO profile |
| six 4-wire fan headers | Profile | shared PWM + six tach inputs; safe profile must default full-speed |
| nine hashboard headers | Profile | profile-specific GPIO/serdev/mining protocol |
| header I2C/SPI/PL UART | Profile | `/dev/i2c-*`, `spidev`, UART only with verified profile |
| I2S/PDM/audio | Profile | ALSA/ASoC framework; conflicts must be declared |
| HDMI/VGA/TFT | Profile | DRM/KMS or fbdev; **no GPU** is claimed |
| camera/video capture | Profile | V4L2/media framework + matching PL design |
| PS USB0 | Disabled | known MIO28-39 collision with hashboard enables/D3 |
| RTC | Not fitted | no battery-backed RTC; use network time |
| D1 / D15 | External | FPGA DONE / regulator power-good indicators |
| D9-D14 | External | 1N4148 tach-input protection diodes, not LEDs |
| JTAG / boot jumper / 12 V power | External | recovery/power facilities, not Linux devices |
| unused PS QSPI/I2C/SPI/CAN/etc. | Disabled | no base DT claim until populated/routed hardware is verified |

## Memory sizing

AtlANTian deliberately has **no fixed Linux RAM limit**. Mainline U-Boot's
Antminer S9 target uses a 1 GiB maximum probe window and `get_ram_size()` to
discover the physically installed DDR. During ARM `bootm`, U-Boot fixes the
`/memory` node passed to Linux to the detected bank size.

The AtlANTian boot contract therefore is:

| Layer | Memory policy |
|---|---|
| U-Boot / DT ceiling | 1 GiB maximum probe range; not a claim of installed capacity |
| 512 MiB board | bootloader reports the detected 512 MiB bank |
| 1 GiB board | bootloader reports the detected 1 GiB bank |
| Kernel command line | no `mem=` parameter |
| ARM kernel | `CONFIG_HIGHMEM=y` is mandatory so upper 1 GiB-board RAM remains usable |
| Reserved regions | 16 MiB FPGA window at `0x0f000000` + 16-byte bootcount area |

Physical 1 GiB evidence from 2026-08-09:

```text
factory U-Boot: DRAM: 1008 MiB
Linux: Memory: 934920K/1048572K available
/proc/meminfo: MemTotal: 1004312 kB
free -h: Mem: 980Mi
```

This Linux boot used the current AtlANTian 6.12.100 kernel, DT and ext4 rootfs,
started manually from the factory NAND U-Boot. It proves the Linux-side dynamic
memory design; it does **not** by itself validate a newly built SD SPL.

> [!NOTE]
> `free`, `/proc/meminfo` and similar tools show **less than the nominal fitted
> capacity**. Reserved-memory regions and normal kernel bookkeeping are excluded;
> that difference is expected and is not an AtlANTian artificial cap.

The source and image tests reject a reintroduced `mem=` boot argument, a DT
probe ceiling below 1 GiB, or a kernel configuration without HIGHMEM.

## SD boot-chain evidence

The previous opaque SD `BOOT.bin` was physically isolated as the 1 GiB failure:

1. one AtlANTian SD card cold-boots the known 512 MiB board;
2. the same card is completely silent on UART on **two** 1 GiB boards in SD mode;
3. both 1 GiB boards boot their factory NAND firmware normally;
4. the factory U-Boot reports 1 GiB DDR and reads the same SD/FAT files normally;
5. loading AtlANTian `uImage` + `devicetree.dtb` from that SD and running `bootm`
   starts AtlANTian successfully with the full 1 GiB address range.

The production design therefore replaces the opaque first stage with the
source-built mainline `bitmain_antminer_s9_defconfig` chain:

```text
BootROM -> SPL BOOT.bin -> u-boot.img -> boot.scr -> uImage + DTB -> ext4 root
```

The upstream S9 board support explicitly targets 256/512/1024 MiB variants and
uses runtime DDR probing. The new AtlANTian first stage remains marked
**Validation** until its exact release artifact is cold-booted on both 512 MiB
and 1 GiB hardware.

## Pin reference

| Signal | Board/Zynq mapping | Electrical note |
|---|---|---|
| D2 | MIO15 | active-low |
| D3 red | MIO37 | active-high |
| D3 green | MIO38 | active-high |
| S1 | MIO47 | active-low |
| S2 | MIO51 | active-low |
| buzzer | MIO39 | base image leaves it unclaimed |
| J1-J9 enables | MIO28-MIO36 | base image leaves lines input/high-Z |
| D5 | PL M19 / AXI GPIO bit 2 | Bank 35, 3.3 V, active-low |
| D6 | PL M17 / AXI GPIO bit 3 | Bank 35, 3.3 V, active-low |
| D7 | PL F16 / AXI GPIO bit 0 | Bank 35, 3.3 V, active-low |
| D8 | PL L19 / AXI GPIO bit 1 | Bank 35, 3.3 V, active-low |
| fan PWM | PL J18 | shared by all six fan headers |
| fan tach 1-6 | PL F19/F20/G17/G18/J20/H20 | independent tach inputs |

## Power and electrical behavior

| Topic | Behavior |
|---|---|
| Board power | external 12 V supply |
| `reboot` | tested restart path |
| `poweroff` | halts Linux; cannot disconnect external 12 V |
| suspend/hibernate | not advertised; reliable resume is not validated |

- **USB0 is not safe as a default feature.** The known Astra-style PS route uses
  MIO28-39, colliding with hashboard enables (28-36) and D3 (37/38).
- PL profiles must declare bank voltage, pin ownership and conflicts.
- Fan profile reset/reload behavior must fail safe to full-speed.
- A full FPGA bitstream replaces the current PL design; independent full
  bitstreams cannot be stacked.

> [!CAUTION]
> A driver existing in Linux or the Zynq datasheet does **not** prove a safe
> physical route on CTRL_C41.

## NAND policy

The source DT selects software BCH because the NAND requires stronger ECC than
the PL353 driver's legacy 1-bit Hamming mode.

> [!WARNING]
> Preserve raw backups and bad-block information before repurposing NAND.
> BCH-formatted storage is not OOB-compatible with the old Hamming layout.

<details>
<summary><strong>Kernel support policy</strong></summary>

### Built in: cold-boot/recovery critical

- Zynq ARMv7 SMP, IRQ/timer/clock/reset/pinctrl/GPIO + HIGHMEM;
- MMC block + Arasan SDHCI + FAT/ext4;
- MACB/GEM + PHYLIB + IPv4/IPv6;
- UARTPS console;
- PL353 NAND/MTD + UBI/UBIFS;
- XADC/IIO/hwmon and Zynq watchdog;
- FPGA Manager, bridge/region, firmware loader and OF/configfs overlays.

### Modules/frameworks kept for profiles

- ChipIdea USB host/gadget helpers, HID, storage and selected USB serial/network
  functions;
- Xilinx AXI GPIO/I2C/SPI/UART/DMA/PWM/hwmon;
- Cadence PS I2C/SPI framework;
- DRM/KMS + selected Xilinx display/DMA helpers;
- ALSA/ASoC and I2S/PDM helpers;
- V4L2/media/videobuf2 + AXI video-DMA helpers;
- TUN, bridge, VLAN, bonding, nftables/conntrack/NAT;
- zram with LZ4.

### Deliberately absent

No desktop, GPU userspace, PYNQ/Jupyter, Docker, Samba, Wi-Fi/BT stack, PCI/PCIe,
printer stack, generic vendor firmware collection or random USB/media device
catalogue. Small frameworks required by declared PL profiles remain available.

The kernel starts from upstream `multi_v7_defconfig` plus the CTRL_C41 board
fragment. A smaller board-only defconfig is a size optimization, not a support
requirement.

</details>

<details>
<summary><strong>Bench-validation record</strong></summary>

| Record | Value |
|---|---|
| Board family | CTRL_C41 V1.30 |
| 512 MiB SD baseline | current AtlANTian 13.1.2 image cold-boots successfully |
| 1 GiB Linux validation | 2026-08-09, AtlANTian 13.1.2 manually launched from factory NAND U-Boot |
| 1 GiB observed RAM | `MemTotal: 1004312 kB`, `free`: 980 MiB |
| legacy SD first stage | fails before UART on two 1 GiB boards; same card works on 512 MiB |
| source-built U-Boot first stage | pending exact-release cold-boot confirmation |
| Access | Ethernet + UART |

Other verified observations include:

- working FPGA Manager/Region path;
- XADC temperature and rail telemetry;
- D3 MIO37/MIO38 electrical behavior;
- D5-D8 profile apply/remove/reapply and independent LED control;
- disabled PS I2C/SPI/USB nodes matching the base DT safety policy;
- `systemctl reboot` as the tested restart path;
- `poweroff` halting Linux without removing external 12 V.

</details>

<details>
<summary><strong>PL profile contract</strong></summary>

A publishable FPGA profile should contain:

1. versioned bitstream;
2. matching DTBO;
3. pin/bank/voltage map;
4. declared conflicts and external wiring;
5. dependencies;
6. non-destructive smoke test;
7. safe reset/reload state where relevant.

A larger custom design may preserve existing AXI ABIs while adding peripherals.

</details>

The base userspace package allow-list lives in
[`config/packages.base`](../config/packages.base); this document intentionally
tracks hardware support rather than duplicating the package manifest.

See [Quick Start](QUICKSTART.md) for first boot and [Documentation index](README.md)
for the rest of the project documentation.
