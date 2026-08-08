# Upgrading AtlANTian

AtlANTian has **two update paths**. Use the one that matches what you want to
change.

| Goal | Command | Scope |
|---|---|---|
| update Debian packages | `apt update && apt upgrade` | userspace within the installed Debian major |
| update AtlANTian | `atlantian-sysupgrade` | platform package, board kernel and release tooling |
| move to next Debian major | `atlantian-sysupgrade` | staged one-major Debian transition |

> [!NOTE]
> Runtime APT is intentionally pinned to the installed Debian **codename**, not
> the moving `stable` alias. A normal `apt upgrade` therefore cannot silently
> jump to a new Debian major.

## Normal Debian maintenance

```sh
apt update
apt upgrade
```

Install packages normally:

```sh
apt install <package>
```

These commands use Debian's live main, updates and security repositories.

## AtlANTian release update

Check first if desired:

```sh
atlantian-sysupgrade --check
atlantian-sysupgrade --notes
```

Install:

```sh
atlantian-sysupgrade
```

Non-interactive mode:

```sh
atlantian-sysupgrade --yes
```

The updater downloads exactly three version-matched packages, checks their
published SHA-256 values and embedded versions, installs them through APT/dpkg,
refreshes Debian packages and reboots.

## What survives

| Preserved | Updated by AtlANTian |
|---|---|
| `/etc` and normal conffiles | board kernel and modules |
| `/root` and `/home` | DT/boot assets |
| `/var` and package database | AtlANTian platform files |
| machine ID | release/update tooling |
| SSH host keys | managed Debian base template when required |
| user-installed packages | release version markers |

Normal updates do not repartition the card and do not rewrite NAND.

## Debian major transition

A major transition is offered only to the **next** Debian major. AtlANTian will
not perform `N -> N+2` and will not downgrade a major.

```mermaid
flowchart LR
    A[Current AtlANTian] --> B[Finish current-major APT upgrade]
    B --> C[Back up + disable third-party APT sources]
    C --> D[Install next-major AtlANTian packages]
    D --> E[Switch managed Debian base]
    E --> F[Debian full-upgrade]
    F --> G[Reboot]
```

Before the transition, third-party `.list` and `.sources` files are moved to a
backup under `/var/lib/atlantian/update/`. They are **not** automatically
re-enabled against the new Debian major.

> [!IMPORTANT]
> Review third-party repositories after a major upgrade. Re-enable only sources
> that explicitly support the new Debian codename.

## Interrupted major upgrade

Once a major transition reaches the sensitive phase, AtlANTian writes resumable
state to:

```text
/var/lib/atlantian/update/major-upgrade-pending.env
```

If the process is interrupted, run:

```sh
atlantian-sysupgrade
```

The updater detects the pending transition and asks to resume it before offering
another release.

Useful state paths:

| Path | Purpose |
|---|---|
| `/var/lib/atlantian/update/available.env` | selected release metadata |
| `/var/lib/atlantian/update/major-upgrade-pending.env` | resumable major transition |
| `/var/lib/atlantian/update/major-upgrade-sources-backup` | path to saved third-party APT sources |
| `/var/cache/atlantian/update/` | verified staged release packages |

## Recovery checks

If an update stops unexpectedly:

```sh
dpkg --audit
apt-get -f install
atlantian-sysupgrade --check
```

For a recorded major transition, prefer **resuming `atlantian-sysupgrade`**
over manually deleting its state.

## Compatibility assurance

Before GitHub publishes a new AtlANTian release, CI installs the candidate
packages over the latest older published image under `armhf` QEMU/chroot and
checks:

- package guards and checksums;
- APT source migration;
- `/boot` replacement;
- `dpkg --audit`;
- machine ID and SSH host-key preservation;
- representative `/etc`, `/root`, `/home` and `/var` state;
- major-upgrade and downgrade rejection rules.

Hardware-only boot/FPGA behavior remains a real-board validation boundary.

See also [Persistence](PERSISTENCE.md), [Debian lifecycle](DEBIAN-LIFECYCLE.md)
and [Release pipeline](PIPELINE.md).
