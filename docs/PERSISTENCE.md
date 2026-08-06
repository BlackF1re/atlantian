# Persistent state

AtlANTian uses a normal Debian root filesystem. The factory image has a FAT
boot partition (`p1`) and an ext4 root filesystem (`p2`). On first boot, `p2`
is expanded to the remaining SD-card capacity and the board reboots once.

There is no data partition, overlay filesystem, bind mount or special APT
cache path. `/etc`, `/root`, `/home`, `/var`, logs, SSH keys, package metadata
and locally installed packages all persist exactly as on an ordinary Debian
installation. `atlantian-sysupgrade` uses APT/dpkg and follows Debian conffile
rules: locally modified configuration is retained by default.
