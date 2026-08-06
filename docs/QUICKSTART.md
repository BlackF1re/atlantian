# Quick start

1. Write the released `.img` to an SD card with a raw-image writer.
2. Select SD boot on the CTRL_C41 board and boot it.
3. Log in on `ttyPS0` or SSH as `root`, then immediately run `passwd`.
4. The first boot expands only `/data` (`mmcblk0p3`) to the remaining card
   capacity. The immutable system is `mmcblk0p2`; boot files are `mmcblk0p1`.

To check for releases use `atlantian-release-check`. To install one, run
`atlantian-release-check --apply`. It downloads an HTTPS-verified
`*.update.bundle` into `/data`, then replaces `p1` and `p2` in RAM recovery.
It never formats or writes `p3`.

`scripts/deploy-via-network.sh` is not an update mechanism. It is an explicit
factory reset and requires the `--factory-reset` confirmation argument.
