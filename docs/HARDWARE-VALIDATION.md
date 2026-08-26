# Hardware validation

CI proves source/artifact contracts; physical behavior must be proved on an Antminer S9 control board. Record board/RAM variant, NAND identity where relevant, release/source revision, relevant UART log and pass/fail result for each bench run.

## Established baseline

The current source-built SD and NAND paths have been exercised on 512 MiB and 1 GiB boards for:

- SD cold boot and reboot;
- UART login at `115200 8N1`;
- Ethernet/DHCP and package-network access;
- verified raw+OOB NAND backup;
- NAND installation;
- NAND cold boot and reboot;
- writable OverlayFS and normal multi-user services;
- recovery-SD handoff and same-major NAND base rebase.

The 1 GiB value in the base DT is only the memory probe ceiling. For memory-sensitive changes, record the actual board population and confirm Linux sees the expected detected bank rather than treating the DT ceiling as evidence of installed RAM.

Low-level changes should repeat the affected part of this baseline.

## Basic board evidence

Useful evidence to save with a bench result:

```sh
cat /usr/lib/atlantian/version
cat /usr/lib/atlantian/storage-edition
uname -a
grep -E 'MemTotal|HighTotal' /proc/meminfo
ip link
systemctl --failed
atlantian-fpga status
```

For NAND-capable tests also record the probe identity:

```sh
dmesg | grep -Ei 'Manufacturer ID|Chip ID'
```

The production destructive path must see Micron Manufacturer ID `0x2c` and Device ID `0xda`. A same-geometry chip with another ID is not a passing NAND test for the current boot/install contract.

## Transactional SD FIT

CI validates both A/B FIT slots, SHA-256 FIT structure, package staging and boot-script fallback. Physical validation should additionally cover:

- [ ] cold boot from slot A on both RAM variants;
- [ ] deliberate selection and boot of slot B;
- [ ] corruption of the selected FIT with automatic fallback to the other complete slot;
- [ ] updater refusal when either required A/B slot is missing;
- [ ] power interruption while the inactive FIT is being written, before the marker switch;
- [ ] power interruption after the marker switch.

The live package updater intentionally does not rewrite early SD `BOOT.bin`/`u-boot.img`; these tests validate the transaction boundary AtlANTian actually provides.

## NAND/recovery

Before destructive NAND testing, confirm all of these independently:

- exact probe identity `2c:da`;
- 256 MiB total size, 128 KiB eraseblocks, 2048-byte pages and 64-byte OOB;
- Linux-reported data ECC at least BCH 4/512;
- a verified raw+OOB backup copied somewhere outside the target NAND.

The following cases still require destructive or fault-injection bench work:

- [ ] exercise a real factory-bad eraseblock through raw boot programming and UBI creation;
- [ ] adopt the paired recovery SD as external upper, then verify activation;
- [ ] remove the adopted card and verify internal-UBIFS fallback; reinsert and verify token-authorized activation;
- [ ] interrupt NAND install/update at controlled stages and verify resume/refusal behavior;
- [ ] perform controlled power-loss tests around raw boot programming and UBI replacement;
- [ ] validate a raw+OOB factory restore procedure on sacrificial hardware.

The repository provides a verified backup tool, not a generic raw-NAND restore command. Do not substitute `dd` for a raw-NAND restore procedure.

## FPGA/profile validation

For any shipped or proposed PL profile, record the exact bitstream/DT-overlay pair and verify:

- FPGA Manager reaches the expected state;
- overlay creation binds only the intended AXI devices;
- package pins, I/O standard/voltage and active polarity match the PCB route;
- reset/idle state is electrically safe;
- applying/removing the profile does not claim a conflicting PS/PL function;
- a full profile is not silently stacked on top of another full design.

For the packaged D5-D8 `status-leds` profile, also verify that the boot service leaves another active administrator-selected overlay untouched and that failure to load the optional profile does not block normal Linux boot/admin access.

## Recurring low-level checklist

After changes to boot firmware, kernel board support, NAND tooling, FPGA routing or power policy:

1. cold boot and reboot from SD;
2. verify UART through userspace login;
3. verify Ethernet/DHCP and package access;
4. verify actual DDR detection on each affected RAM variant;
5. for SD boot/kernel changes, exercise both FIT slots and fallback;
6. inspect storage/boot state with `atlantian-storage status` where applicable;
7. for NAND changes, record exact `2c:da` probe identity, verify backup, install/update transaction and NAND cold boot;
8. for FPGA/pin changes, verify voltage, idle state, ownership/conflicts and the exact bitstream/DT-overlay pair;
9. for power-policy changes, distinguish Linux halt/reboot behavior from actual external 12 V removal.

Do not promote a hardware capability to **Ready** solely because a driver builds or CI passes. Current support status and pin mappings live in [hardware-support-matrix.md](hardware-support-matrix.md); exact NAND architecture lives in [NAND.md](NAND.md).
