# AtlANTian: complete hardware-support matrix for CTRL_C41 V1.30

This is the production checklist. **Included** means available after a cold
boot from the base image. **Profile** means the image has the driver framework
but a versioned FPGA bitstream plus DT overlay owns the pins. **External** is
real board capability but not a Linux peripheral.

| Hardware / function | Evidence | Linux export | Image decision |
|---|---|---|---|
| XC7Z010 PS, dual Cortex-A9, GIC, OCM, timers, PMU, reset and SLCR | live DT | normal ARM/Zynq kernel, SMP, cpuidle/cpufreq, perf | Included, no special package. |
| 512 MiB DDR3 (496 MiB usable by boot contract), no ECC | live DT/dmesg | ordinary RAM; EDAC reports no ECC | Included; no fake ECC or 128-MiB PYNQ CMA reservation. |
| microSD, SDHCI0, card-detect and write-protect | working current system | `/dev/mmcblk0`, partitions, hotplug | Included and boot-critical. |
| 256-MiB Micron MT29F2G08 parallel NAND via PL353 SMC | schematic + live DT/dmesg | `/dev/mtd*`, `/dev/mtdblock*`, UBI/UBIFS and `mtd-utils` | Included. Full raw visibility. The source DT now selects software BCH, 4-bit/512-byte ECC because the chip requires more than the PL353 driver's legacy 1-bit Hamming mode. Preserve the raw backup/bad-block data; BCH-formatted storage is not OOB-compatible with the old layout. |
| Gigabit Ethernet, GEM0/RGMII-ID, PHY address 1 | live DT/link | `end0`/`macb`, MDIO, ethtool | Included; DHCP and persistent locally-administered MAC policy. Firmware does not provide a valid factory MAC, so the address is stable for this installation but is not a vendor-assigned globally unique identity. |
| Future USB connector and Zynq ChipIdea controller | Astra PS design; no fitted CTRL_C41 USB routing verified | USB host/gadget, `lsusb`, HID, mass storage, CDC ACM/serial | Framework included, but not enabled in the base DT: the available Astra PS design routes USB0 through MIO28--39, which collides with physical hashboard enables (28--36) and D3 (37/38). It must be an electrically verified, mutually-exclusive pinmux profile, never an unsafe base claim. |
| PS UART1 on J12 | live system + schematic | `ttyPS0`, early console, serial getty 115200 8N1 | Included, always on. |
| PS GPIO: D2, D3 bicolour status LED, S1/S2 keys, buzzer, J1--J9 enables | schematic + live tests: D2=MIO15 active-low; D3 red=MIO37 and green=MIO38 active-high; S1=MIO47 and S2=MIO51 active-low; buzzer=MIO39; enables=MIO28--36 | D2/D3: LED class; S1/S2: Linux input (`s1_short`, `s2_long`); remaining lines visible by name through `gpiod` | D2 and D3 included and off at boot. D3 red is aggregate-CPU double-pulse heartbeat; green observes SD I/O. Enable/buzzer lines are put in GPIO mux but remain input/high-Z until a deliberate consumer claims them. No default action is assigned to either key. |
| Fixed indicators D1 and D15 | schematic | none | External indicators: D1 follows FPGA `DONE`; D15 is 3.3-V regulator power-good. Neither is a Linux-controllable LED. |
| XADC: die temperature and rails | live DT | IIO + hwmon; `sensors` | Included. Export temperature, VCCINT, VCCAUX, VCCBRAM, VCCPINT, VCCPAUX and VCCODDR. |
| Zynq watchdog | live DT | `/dev/watchdog0`, systemd watchdog | Included; service activation remains opt-in until recovery behaviour is tested. |
| FPGA DevCfg/PCAP and AXI interconnect | live `fpga0` and `region0` | FPGA Manager, FPGA Region, firmware loader, OF overlay configfs and `atlantian-fpga` | Included and live-tested on AtlANTian 13-2. `atlantian-fpga apply` attaches a DTBO; its `firmware-name` programs PCAP through the FPGA Region. Apply, remove and reapply were exercised with the D5--D8 profile. |
| PL board LEDs D5--D8 | schematic/XDC: D5=M19/bit2, D6=M17/bit3, D7=F16/bit0, D8=L19/bit1; Bank 35 at 3.3 V; active-low | `status-leds` profile exports `atlantian:pl:d5` ... `d8` through LED class | Verified live on AtlANTian 13-2: FPGA Manager load, overlay apply/remove, `gpio-xilinx` autoload, default-off state and independent toggling all pass. An arbitrary full bitstream must retain the same AXI GPIO ABI to keep these LEDs; compiled full bitstreams cannot be stacked. |
| D9--D14 footprints near fans | schematic | none | These are 1N4148 clamp/protection diodes on the six tachometer inputs, not LEDs and not independently controllable. |
| Six 4-wire fan headers | schematic/XDC: shared PWM J18; tach F19/F20/G17/G18/J20/H20 | profile hwmon: `pwm1`, `fan1_input` ... `fan6_input` | PL profile required. All headers share one PWM duty cycle but have six independent tach inputs. Safe profile reset/reload state must be full-speed. |
| Nine hashboard headers | board map/schematic | profile-specific GPIO, serdev or mining protocol | Profile only; pin ownership and 3.3-V constraints declared per profile. |
| Header I2C, SPI and PL UART candidates | schematic/XDC/Astra sources | `/dev/i2c-*`, `/dev/spidev*`, `ttyUL*` | Profile only; no fictitious base devices or unsafe pull-up assumptions. |
| I2S/PDM microphone, I2S line audio and PWM stereo audio (some pins alternate with fans) | Astra source-backed | ALSA/ASoC card, PCM/MIDI controls and standard `arecord`/`aplay` | Profile only and mutually exclusive with `fan-hwmon` where pins overlap. ALSA framework and tools are in the base image. |
| HDMI/VGA, parallel TFT or another PL display controller | Astra source-backed | DRM/KMS framebuffer (`/dev/dri/card*`) or profile-declared fbdev | Profile only. DRM is a display API, **not a GPU**; no GPU or desktop in base. |
| Camera/video capture via a PL profile | Astra/PYNQ source-backed | standard V4L2 (`/dev/video*`), media controls and DMA buffers | Profile only. V4L2/videobuf2 framework is included, with no unrelated USB/DVB camera drivers. |
| JTAG, boot-mode jumper, 12-V input and regulators | board/schematic | external recovery/power facilities | Documented; no invented Linux device. |
| QSPI/NOR, second Ethernet/CAN, unused PS I2C/SPI | PS capability only; no populated/routed device confirmed | none until verified | Kernel framework available where small; no base DT node or userspace claim. |

## Kernel requirements

### Built in: required to recover a cold boot

- Zynq ARMv7 SMP, interrupt/timer/clock/reset, devtmpfs and proc/sysfs;
- MMC block + Arasan SDHCI + ext4, FAT/VFAT, partition support;
- MACB/GEM, PHYLIB and the detected RGMII PHY; IPv4/IPv6, DHCP support;
- UARTPS and console; Zynq GPIO/pinctrl needed by the base DT;
- PL353 SMC/NAND/MTD, UBI and UBIFS; XADC/IIO/hwmon; Zynq watchdog;
- FPGA Manager for Zynq DevCfg, firmware loader, FPGA bridge/region and OF
  overlay/configfs support. The vendored 6.12 configfs attachment code builds
  and its complete programming/overlay path is live-validated on AtlANTian 13-2.

### Modules installed in the image: make later use possible without a kernel rebuild

- USB ChipIdea host+gadget, ULPI/PHY helpers, HID, storage, CDC ACM,
  USB serial and the selected generic Ethernet gadget/device functions;
- Xilinx AXI GPIO, I2C, SPI, UART Lite/AXI UART, DMA, PWM and hwmon support;
- PS Cadence I2C/SPI (only overlays instantiate a routed bus);
- DRM/KMS core, fbdev emulation and selected Xilinx display/AXI-DMA helpers
  required by a verified PL profile — no GPU driver;
- ALSA core/ASoC, I2S/PDM and DMA helpers for FPGA audio or microphone
  profiles; V4L2/media-controller/videobuf2 plus AXI video-DMA helpers for
  FPGA capture profiles;
- router/server primitives: TUN (for Tailscale), bridge, VLAN, bonding,
  netfilter/nftables, conntrack and IPv4/IPv6 NAT;
- `zram` with LZ4, compressed swap only in RAM.

### Explicitly absent

The current kernel build starts from upstream `multi_v7_defconfig` and then
applies the board fragment. That is functionally safe but carries avoidable
generic ARM drivers; producing a measured CTRL_C41 defconfig is a later size
optimization and must not remove the frameworks listed above. The rootfs has
no GPU, Intel/AMD/ARM graphics userspace,
generic DVB/media/camera device drivers, Wi-Fi/BT, PCI/PCIe, printer or random
USB-dongle drivers, PYNQ/Jupyter, Docker, Samba, Tailscale daemon, FPGA
bitstreams or vendor firmware collection. The small generic frameworks needed
by declared PL profiles (DRM, ALSA, V4L2) are deliberately retained; device
drivers appear only through a matching profile.

## Base userspace allow-list

`systemd`, `systemd-networkd`, OpenSSH, CA certificates, `iproute2`,
`ethtool`, `can-utils`, `nftables`, `curl`, `pigz`, `gpiod`, `i2c-tools`, `spi-tools`,
`lm-sensors`, `libiio-utils`, `alsa-utils`, `v4l-utils`, `usbutils`,
`mtd-utils`, `dtc`, `kmod`,
`procps`, `htop`, `less` and `nano`.  The image deliberately has no `sudo`:
it is a root-only appliance. There is no desktop, Samba, PYNQ, Jupyter,
generic kernel package, `pciutils`, `flash-kernel`, `rsync` or duplicate
downloader.

## Historical runtime audit: 2026-08-03 predecessor image

The running reference image was interrogated over Ethernet and UART.  It
booted from `/dev/mmcblk0p2`; `fpga0` and the GPIO/LED class entries exist;
and `sensors` reports XADC die temperature plus VCCINT, VCCAUX, VCCBRAM,
VCCPINT, VCCPAUX and VCCODDR.  D3 was electrically verified: the boot DTB
left MIO37/MIO38 in USB mux mode (`0x1404`), while moving them to GPIO mux
(`0x1400`) made the active-high red and green MOSFET-gate outputs work.  The
source DTB now contains that pinctrl state; it is included and live-tested in
AtlANTian 13-2.

The live DT explicitly marks both PS I2C nodes, all PS SPI nodes and both USB
controllers `disabled`; consequently no `/dev/i2c-*`, `/dev/spidev*` or USB
host exists.  Their drivers are present, but that does not make the electrical
routing safe. That predecessor had `configfs` mounted but no device-tree
overlay endpoint. AtlANTian 13-2 now supplies and live-validates the endpoint.
Camera/display/audio/fan profiles still require their own bitstream, overlay
and physical-interface validation before being published as working profiles.

`systemctl reboot` is supported and is the tested restart path.  `poweroff`
halts Linux but cannot disconnect the external 12-V source: CTRL_C41 has no
Linux-controllable PMIC/load switch.  Suspend and hibernate are intentionally
not advertised as a recoverable feature.  There is no battery-backed RTC;
users may set time with `timedatectl set-time` and `systemd-timesyncd` corrects
it from NTP once networking is available after every cold boot.

## Required profile registry contents

Every independent FPGA capability is a package containing a bitstream, DTBO,
pin/bank/voltage map, conflicts, external wiring, dependencies and a
non-destructive smoke test.  It becomes installable only after the profile
attachment route is implemented and hardware-tested; until then it can still
be programmed directly through `atlantian-fpga` for development.  The first
registry must define `safe-base`,
`fan-hwmon`, `gpio-header`, `i2c-spi-uart`, `mining-header`, and the
source-backed Astra profiles `display-hdmi-vga`, `display-tft`,
`audio-i2s-pwm`, `microphone`, `camera-v4l2`, `sdr` and `midi` where the exact
bitstream and wiring are supplied. The installer rejects overlapping profiles.
