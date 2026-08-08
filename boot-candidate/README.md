# Boot firmware input

`BOOT.bin` is the board boot-firmware input used by the factory image. It is
kept as a pinned binary because the current AtlANTian build does not recreate
the vendor FSBL/U-Boot bundle from source.

Production CI verifies its Git object ID against `BOOT.bin.gitsha` before any
release is built. Replacing the file therefore requires an explicit update of
the pin and hardware validation on CTRL_C41.

## DDR handoff contract

AtlANTian relies on the Antminer S9 U-Boot memory model: **1 GiB is the maximum
probe window, not a fixed installed size**. U-Boot discovers the populated DDR
bank and ARM `bootm` fixes the `/memory` node passed to Linux. The factory
`uEnv.txt` therefore deliberately contains no Linux `mem=` limit.

This lets the same image use 512 MiB and 1 GiB CTRL_C41 variants. Linux reports
less than the nominal fitted capacity because reserved-memory and kernel
bookkeeping are excluded; that is expected.

> [!IMPORTANT]
> A replacement boot firmware must preserve runtime DDR sizing. A binary that
> hard-codes one DRAM capacity would break AtlANTian's single-image memory
> contract even if the Linux kernel and DT remain unchanged.

AtlANTian does not claim that this binary itself is reproducible from this
repository. The Debian root filesystem, Linux kernel, device tree, packages and
image assembly remain source-controlled build inputs around this pinned boot
component.
