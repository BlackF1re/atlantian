# Hardware support matrix

Target: Bitmain Antminer S9 control board with Xilinx Zynq-7010. A SoC/PL peripheral is not considered supported merely because a driver or IP block exists: the PCB route, voltage, ownership, safe idle state and physical behavior must also be known.

Status meanings: **Ready** = implemented and exercised; **Validation** = implemented but specific physical fault/edge testing remains; **Profile** = shipped FPGA bitstream/DT-overlay pair; **Candidate** = practical future extension; **Investigate** = PCB/electrical route not proved; **External** = outside normal Linux control; **Unavailable** = blocked by known routing/design constraints.

## Compute, boot and storage

| Capability | Status | Interface / boundary |
|---|---|---|
| Zynq-7010 dual Cortex-A9 | Ready | Debian `armhf`, SMP, NEON/VFP |
| 512 MiB / 1 GiB DDR3 variants | Ready | 1 GiB is the DT/U-Boot probe ceiling, not a fixed installed size; U-Boot fixes `/memory` to the detected bank before Linux; HIGHMEM enabled; no `mem=` cap |
| microSD boot/root | Ready | 48 MiB FAT BOOT + ext4 ROOT; ROOT expands to the card remainder on first boot |
| SD A/B kernel+DT FIT | Validation | two SHA-256 FIT slots; inactive write/verify/sync then marker switch; remaining fault tests in [HARDWARE-VALIDATION.md](HARDWARE-VALIDATION.md) |
| stock 256 MiB raw NAND | Ready | Micron `MT29F2G08ABAEAWP`, exact ID `2c:da`, PL35X MTD, on-die BCH 4/512, verified raw+OOB backup |
| NAND installation/boot | Ready | exact-ID guard + geometry/ECC checks; 16 MiB raw boot + 240 MiB UBI static SquashFS/UBIFS OverlayFS |
| NAND bad-block edge cases | Validation | bad-block-aware layout/software; broader real bad-block placement coverage remains |
| interrupted NAND recovery | Validation | marker/resume/refusal paths implemented; controlled power-loss/fault testing remains |
| recovery-SD external upper | Validation | only the paired install/recovery card can be adopted; token-authorized fallback implemented |
| SD/NAND boot jumper | External | physical BootROM source selection |
| persistent U-Boot environment | Unavailable | deliberately `ENV_IS_NOWHERE` |

## Board I/O

| Capability | Status | Linux / electrical boundary |
|---|---|---|
| Gigabit Ethernet | Ready | GEM0/MACB, DHCP/IPv6-RA capable |
| UART1 / J12 | Ready | `ttyPS0`, `115200 8N1`, 3.3 V logic |
| D2 / D3 LEDs | Ready | PS MIO, Linux LED class |
| S1 / S2 buttons | Ready | Linux input (`KEY_PROG1/2`); no destructive default action |
| buzzer line | Ready | named GPIO, unclaimed by default |
| J1-J9 hashboard-enable lines | Ready | named GPIO; input/high-Z unless deliberately claimed |
| XADC die sensors | Ready | IIO plus hwmon/sensors exposure |
| Zynq watchdog | Ready | `/dev/watchdog0`; reset-on-timeout; U-Boot does not auto-arm it |
| RTC | Unavailable | no battery-backed RTC fitted |
| JTAG | External | development/recovery interface; respect I/O voltage |
| 12 V input/power stages | External | Linux `poweroff` cannot remove board input power |

## FPGA

| Capability | Status | Boundary |
|---|---|---|
| PCAP / FPGA Manager | Ready | full bitstream programming through Linux FPGA framework |
| configfs FPGA overlays | Ready | overlay and bitstream must represent the same full PL design |
| D5-D8 status LEDs | Profile | shipped `status-leds` `.bin` + DT overlay; boot loader is best-effort and will not replace another active overlay |
| profile management | Ready | `atlantian-fpga status/apply/remove`; safe relative firmware paths only |
| fan PWM/tach capture | Candidate | requires a versioned PL profile and fail-safe policy |
| header I2C/SPI/UART/GPIO | Candidate | requires verified pins, voltage, idle state and ownership |
| AXI registers/DMA/interrupt blocks | Candidate | define ABI, reset/error handling and DT binding |
| partial reconfiguration | Investigate | requires isolation, compatibility and rollback design |

A Zynq full bitstream replaces the active PL design. Unrelated full designs cannot be stacked as if they were independent kernel modules. The packaged D5-D8 profile is optional convenience, not a prerequisite for base Linux boot or administration.

## Pin reference

| Signal | Mapping | Note |
|---|---|---|
| D2 | MIO15 | active-low |
| D3 red | MIO37 | active-high |
| D3 green | MIO38 | active-high |
| S1 | MIO47 | active-low |
| S2 | MIO51 | active-low |
| buzzer | MIO39 | unclaimed by default |
| J1-J9 enables | MIO28-MIO36 | input/high-Z until deliberately claimed |
| D5 | PL M19 / AXI GPIO bit 2 | Bank 35, 3.3 V, active-low |
| D6 | PL M17 / AXI GPIO bit 3 | Bank 35, 3.3 V, active-low |
| D7 | PL F16 / AXI GPIO bit 0 | Bank 35, 3.3 V, active-low |
| D8 | PL L19 / AXI GPIO bit 1 | Bank 35, 3.3 V, active-low |
| fan PWM | PL J18 | shared across six fan headers |
| fan tach 1-6 | PL F19/F20/G17/G18/J20/H20 | independent inputs |

## Important routing boundaries

- PS USB0 is not available through the known MIO route because MIO28-39 are already used by board functions.
- Reusing a MIO pin requires changing its mux and proving that the board function currently attached to it is safe to release.
- High-speed interfaces such as PCIe, HDMI/display, camera or RF links have no documented ready-to-use route on this board and should be treated as carrier/FPGA hardware projects, not base-system features.
- Suspend/hibernate are not advertised as recoverable board states.
- `poweroff` halts Linux but does not remove external 12 V.

## NAND evidence boundary

The production NAND contract is the exact stock Micron part/ID above, not “any 256 MiB NAND”. Its required geometry is 2048-byte pages, 64-byte OOB and 128 KiB eraseblocks, with Micron on-die BCH 4/512. Exact raw offsets, SPL behavior, UBI reserve and transaction ordering are owned by [NAND.md](NAND.md).

Physical validation requirements are owned by [HARDWARE-VALIDATION.md](HARDWARE-VALIDATION.md). Generic Debian applications are not listed here unless they require AtlANTian-specific hardware integration.
