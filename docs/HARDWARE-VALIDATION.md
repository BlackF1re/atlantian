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

## RAM-only SD/NAND upgrade bench matrix (13.1.0-beta.2 baseline)

All cases require a **strictly newer, complete and signed GitHub Release** as
the upgrade target. A GitHub Actions artifact or an annotated Git tag alone is
not discovered by `atlantian-sysupgrade`. Record target release, checksum
manifest authentication, actual board RAM, SSH/UART recovery access and results
of a power-off cold boot. No storage mode is certified by the others' success.

Before each run, create distinct persistence markers in `/etc`, `/root`,
and `/var/lib/atlantian/test`. Record their exact contents before the run.
Use `atlantian-sysupgrade --check` and `--notes` to confirm the target
version; a successful check is only discovery, **not** a signature verification
or an update. During an actual upgrade the old SSH session will disconnect at
`kexec`; on error, inspect `/run/upgrade/upgrade.log` and
`/run/upgrade/status` via RAM recovery SSH **before rebooting or power-cycling**.
Those RAM-only logs vanish after shutdown.

### NAND, internal UBIFS upper, no SD (first destructive RAM-writer test)

- [ ] Cold boot from NAND with the SD card removed and confirm
      `storage-edition=nand`, `overlay-mode=internal`, and functioning SSH.
- [ ] Run the read-only `atlantian-nand-ram-probe --check` preflight.
- [ ] Confirm an independently usable recovery path before first experimental
      Linux raw-NAND writes. Factory installation from SD is not proof that
      the new Linux RAM writer is correct.
- [ ] Update via `atlantian-sysupgrade` and record the release authenticator,
      kexec boot, old-state snapshot, UBI replacement, slot readback and reboot.
- [ ] Confirm the new version, preserved markers, internal UBIFS upper,
      unchanged boot media and an error-free cold boot without an SD card.

### NAND, adopted external microSD upper

- [ ] Begin with a known source NAND release and the *paired* installer card.
      Save a distinct internal-state marker **before** adopting the SD.
- [ ] Run `atlantian-storage adopt`, reboot, and confirm
      `overlay-mode=external`. Change the marker's value in the external view.
- [ ] Confirm that the external adoption token matches the internal token,
      and that the SD ext4 partition remains available throughout the upgrade.
- [ ] Upgrade to a strictly newer signed release. Verify both internal fallback
      capture/restore and external-state capture/restore in the RAM log.
- [ ] With the adopted SD inserted, confirm the new release and the external
      marker. Power off, remove the card, cold boot and confirm the internal
      marker; power off, reinsert the card and confirm the external marker again.
      Never hot-remove the active external upper.

### Native SD ext4 root and FAT A/B FIT boot

- [ ] Boot a source-version SD with both FIT slots and the correct boot ABI;
      record the running release and persistence markers.
- [ ] Update through the same authenticated RAM-kexec path; inspect the
      signed Debian packages, chroot APT upgrade and A/B FIT transaction.
- [ ] Confirm the target release, preserved files and SSH keys, functioning
      network, successful `dpkg --audit`, both boot files, and cold reboot.

For comparable results use the same source and target versions in all three
tests; reinstall the baseline from the saved SD image between destructive NAND
runs if necessary. Alternatively, use separate strictly increasing releases
for the later scenarios. A same-version reinstall does **not** exercise the
release-discovery/updater path.

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
