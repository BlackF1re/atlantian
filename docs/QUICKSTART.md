# Quick start

1. Write the released `.img` to a microSD card with Rufus, Raspberry Pi Imager
   or `dd`.
2. Set the board jumper for SD boot and power it on.
3. The first boot expands `/dev/mmcblk0p2` to the rest of the card, reboots
   once, and then starts SSH and the UART getty.
4. Log in as `root`, set a password with `passwd`, and configure the board as
   ordinary Debian GNU/Linux.

To apply a newer AtlANTian release, run the command printed at SSH login:

```sh
atlantian-sysupgrade --latest <release-id>
```

It installs the published AtlANTian packages and performs a normal
`apt full-upgrade`; it preserves the conventional Debian filesystem and then
reboots the board.
