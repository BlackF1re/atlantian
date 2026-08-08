# Hardware support: CTRL_C41 V1.30

This matrix separates **physical evidence** from **software availability**.

| Status | Meaning |
|---|---|
| **Ready** | available through the base image and backed by board/runtime evidence |
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
| 512 MiB DDR3 | Ready | ~496 MiB usable by boot contract; no ECC |
| microSD / SDHCI0 | Ready | `/dev/mmcblk0`; boot-critical FAT + ext4 root |
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

- Zynq ARMv7 SMP, IRQ/timer/clock/reset/pinctrl/GPIO;
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
| Board | CTRL_C41 V1.30 |
| Bench baseline | pre-genesis development image |
| Recorded audit | 2026-08-03 |
| Access | Ethernet + UART |

Verified observations include:

- SD boot from `/dev/mmcblk0p2`;
- working FPGA Manager/Region path;
- XADC temperature and rail telemetry;
- D3 MIO37/MIO38 electrical behavior;
- D5-D8 profile apply/remove/reapply and independent LED control;
- disabled PS I2C/SPI/USB nodes matching the base DT safety policy;
- `systemctl reboot` as the tested restart path;
- `poweroff` halting Linux without removing external 12 V.

A current release is not labelled "physically re-tested" merely because build
and upgrade gates pass.

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
