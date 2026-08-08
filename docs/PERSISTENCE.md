# Persistence

AtlANTian uses a normal Debian root filesystem. There is no overlay filesystem,
hidden data partition or special persistence layer.

| Area | Behavior |
|---|---|
| `/boot` | FAT partition; AtlANTian kernel package refreshes boot assets |
| `/` | ext4; expanded to the microSD card on first boot |
| `/etc` | persistent, normal dpkg conffile semantics |
| `/root` / `/home` | persistent |
| `/var` | persistent, including package/update state |
| SSH host keys | generated per flash, preserved by package upgrades |
| machine ID | generated per flash, preserved by package upgrades |
| user-installed packages | preserved by normal updates |
| NAND | independent from the SD installation |

## First boot

The factory image contains:

```text
p1  FAT   /boot
p2  ext4  /
```

On first boot, `p2` expands to the remaining microSD capacity and the board
reboots once.

## Package upgrades

`atlantian-sysupgrade` uses APT/dpkg rather than replacing the filesystem.
Ordinary Debian state therefore survives as expected.

During a Debian-major transition, third-party APT source files are backed up and
disabled before the base codename changes. The backup location is recorded in:

```text
/var/lib/atlantian/update/major-upgrade-sources-backup
```

It remains visible until the administrator reviews the old repositories.

> [!NOTE]
> Reflashing an image is intentionally different from upgrading packages: a
> reflash creates a new machine ID and new SSH host keys.

See [Upgrading](UPGRADING.md) for the full update flow.
