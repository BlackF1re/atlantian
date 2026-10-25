# Antminer S9 status-LED FPGA profile

The `status-leds` profile provides the D5–D8 LED outputs through the Zynq programmable logic. The board interface, pin assignment, AXI address and hashes are recorded in [manifest.json](manifest.json).

## Repository artifacts (not installed)

- `atlantian-status-leds.bit`: Vivado-format reference bitstream for further FPGA design/integration.
- `atlantian-status-leds.hwh`: hardware handoff metadata describing the implemented AXI hardware.
- `atlantian-status-leds.dtso`: human-editable Device Tree overlay source.
- `manifest.json`: versioned profile metadata and integrity hashes.

These are **development/reference artifacts kept in Git**, not runtime firmware. The directory currently does **not** contain a complete reproducible Vivado HDL/block-design project; the `.bit` file must not be mistaken for HDL source. If such a project is added later, keep it under a clearly named `source/` or `vivado/` directory, with its tool version and deterministic regeneration instructions.

## Runtime allowlist

The only files from this directory that may be copied into SD/NAND root filesystems are:

- `atlantian-status-leds.bin` — bitstream consumed by the Linux FPGA Manager;
- `atlantian-status-leds.dtbo` — compiled overlay consumed by configfs;
- `manifest.json` — the published profile description.

`scripts/build-rootfs.sh` explicitly copies only these three files to their respective runtime destinations. Never recursively copy `fpga/status-leds/` into a root filesystem, Debian package or NAND image. The build/test contracts reject development-only `.bit`, `.hwh` and `.dtso` content in generated release payloads.

A full Zynq bitstream replaces the active PL configuration. Do not attempt to stack unrelated full designs; merge the profile into another bitstream and update the accompanying overlay and manifest together.
