# Persistent state

AtlANTian uses a normal Debian root filesystem. The factory image has a FAT
boot partition (`p1`) and an ext4 root filesystem (`p2`). On first boot, `p2`
is expanded to the remaining SD-card capacity and the board reboots once.

There is no data partition, overlay filesystem, bind mount or special APT cache
path. `/etc`, `/root`, `/home`, `/var`, logs, SSH keys, package metadata and
locally installed packages persist as on an ordinary Debian installation.

`atlantian-sysupgrade` uses APT/dpkg and normal Debian conffile semantics. During
a Debian major transition it deliberately backs up and disables third-party APT
source files before changing the base codename. The backup path is recorded in
`/var/lib/atlantian/update/major-upgrade-sources-backup` and is shown at login
until the administrator has reviewed it.

The on-board NAND is independent from the SD installation. Normal package and
AtlANTian updates do not rewrite NAND.
