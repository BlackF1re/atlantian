# Persistence

AtlANTian uses a normal Debian root filesystem. There is no overlay filesystem,
hidden data partition or special persistence layer.

| Area | Behavior |
|---|---|
| `/boot` | FAT partition; AtlANTian kernel package refreshes boot assets |
| `/` | ext4; expanded to the microSD card on first boot |
| `/etc` | persistent; normal config remains, while the managed Debian base source may change during a major transition |
| `/root` / `/home` | persistent |
| `/var` | persistent, including package/update state |
| SSH host keys | generated per flash, preserved by package upgrades |
| machine ID | generated per flash, preserved by package upgrades |
| user-installed packages | retained normally; a Debian major `full-upgrade` may replace/remove obsolete packages |
| NAND | independent from the SD installation |

## First boot

The factory image contains only:

```text
p1  FAT   /boot
p2  ext4  /
```

On first boot, `p2` expands to the remaining microSD capacity and the board
reboots once.

## Package upgrades

`atlantian-sysupgrade` uses APT/dpkg instead of replacing the filesystem.
Ordinary Debian state therefore persists through AtlANTian updates.

During a Debian-major transition:

- the managed base repository switches to the new Debian codename;
- third-party APT source files are backed up and disabled first;
- Debian performs a normal `full-upgrade`, so obsolete packages can legitimately
  be removed or replaced.

The third-party source backup location is recorded in:

```text
/var/lib/atlantian/update/major-upgrade-sources-backup
```

It remains visible until the administrator reviews the old repositories.

> [!NOTE]
> Reflashing is intentionally different from upgrading packages: a reflash
> creates a new machine ID and new SSH host keys.

See [Upgrading](UPGRADING.md) for operator steps.
