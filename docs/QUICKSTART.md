# Quick start

1. Write the released `.img` to a microSD card with Rufus, Raspberry Pi Imager
   or `dd`.
2. Set the board jumper for SD boot and power it on.
3. The first boot expands `/dev/mmcblk0p2` to the rest of the card, reboots
   once, and then starts SSH and the UART getty.
4. Log in as `root`, set a password with `passwd`, and configure the board as
   ordinary Debian GNU/Linux.

To inspect and apply a newer AtlANTian release, run:

```sh
atlantian-sysupgrade
```

It displays the release, publication time, changes and download size, then
requires `UPGRADE`. It installs the published AtlANTian packages, performs a
normal `apt full-upgrade`, preserves the conventional Debian filesystem and
then reboots the board.
