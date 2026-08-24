# Hardware validation

CI proves source/artifact contracts; physical behavior must be proved on an Antminer S9 control board. Record board/RAM variant, release, relevant UART log and pass/fail result for each bench run.

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

Low-level changes should repeat the affected part of this baseline.

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

The following cases require destructive or fault-injection bench work:

- [ ] exercise a real factory-bad eraseblock through raw boot programming and UBI creation;
- [ ] adopt the paired recovery SD as external upper, then verify activation;
- [ ] remove the adopted card and verify internal-UBIFS fallback; reinsert and verify token-authorized activation;
- [ ] interrupt NAND install/update at controlled stages and verify resume/refusal behavior;
- [ ] perform controlled power-loss tests around raw boot and UBI replacement;
- [ ] validate a raw+OOB factory restore procedure on sacrificial hardware.

The repository provides a verified backup tool, not a generic raw-NAND restore command.

## Recurring low-level checklist

After changes to boot firmware, kernel board support, NAND tooling, FPGA routing or power policy:

1. cold boot and reboot from SD;
2. verify UART through userspace login;
3. verify Ethernet/DHCP and package access;
4. for SD boot/kernel changes, exercise both FIT slots and fallback;
5. inspect storage/boot state with `atlantian-storage status` where applicable;
6. for NAND changes, verify backup, install/update transaction and NAND cold boot;
7. for FPGA/pin changes, verify voltage, idle state, ownership/conflicts and the exact bitstream/DT-overlay pair.

Do not promote a hardware capability to **Ready** solely because a driver builds or CI passes. Current support status and pin mappings live in [hardware-support-matrix.md](hardware-support-matrix.md).
