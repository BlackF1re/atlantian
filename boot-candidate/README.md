# Boot firmware input

`BOOT.bin` is the board boot-firmware input used by the factory image. It is
kept as a pinned binary because the current AtlANTian build does not recreate
the vendor FSBL/U-Boot bundle from source.

Production CI verifies its Git object ID against `BOOT.bin.gitsha` before any
release is built. Replacing the file therefore requires an explicit update of
the pin and hardware validation on CTRL_C41.

AtlANTian does not claim that this binary itself is reproducible from this
repository. The Debian root filesystem, Linux kernel, device tree, packages and
image assembly remain source-controlled build inputs around this pinned boot
component.
