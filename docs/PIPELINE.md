# Build and network deployment

This is the normal, reproducible deployment procedure. It writes only the SD
card currently used by the board (`/dev/mmcblk0`); it never writes NAND or
changes the boot jumpers. UART/U-Boot is an emergency recovery route, not part
of a normal update.

## Persistent state and update boundary

`p2` is the replaceable system partition.  `p3` is `/data` and is never
rewritten by `atlantian-sysupgrade`.  During boot,
`atlantian-persist-state.service` mounts `/etc` as an overlay whose writable
upper layer is under `/data/system/atlantian/persist`; it bind-mounts the
persistent `/root`, `/home`, and `/var/local` trees from the same location.
This preserves administrator configuration, SSH keys, user files, and local
data while allowing fresh release defaults to remain visible underneath.

The dpkg database, `/usr`, and `/var/lib` are deliberately not persistent:
retaining them while replacing the system payload could combine incompatible
package state with a new Debian base.  Treat `apt` package additions as system
customisation and declare or reinstall them after an image-level update.

On first boot, `atlantian-grow-data.service` expands p3 rather than p2 to the
end of the inserted card.  Its completion markers are stored on p3, so a
system update does not run the partition-growth procedure again.

## One-time host setup

```bash
cd /path/to/atlantian
sudo ./scripts/bootstrap-host.sh
printf '%s\n' 192.168.2.112 > state/board.address
touch state/autodeploy.enabled
```

Use the board's current Ethernet address in `state/board.address`. The host
must be able to SSH as `root`; credentials are intentionally not stored here.
After a clean image is written, CTRL_C41 may acquire both a new DHCP address
and a new locally administered MAC address. The deployment job first tries the
recorded MAC, then discovers an AtlANTian SD-root system over SSH, and stores
the successful address back in `state/board.address`.

## Build only what changed

```bash
./scripts/run-pipeline-job.sh userspace  # rootfs/services/packages
./scripts/run-pipeline-job.sh dtb        # board device tree only
./scripts/run-pipeline-job.sh kernel     # kernel, modules and DTB
./scripts/run-pipeline-job.sh boot       # image layout or boot payload only
./scripts/run-pipeline-job.sh all        # intentional full rebuild
./scripts/run-pipeline-job.sh deploy     # re-deploy current image unchanged
```

The resulting image is always `artifacts/current/atlantian-<debian>-<build>.img`.
The active name and version are read from `config/release.env`, not duplicated
in scripts or documentation.

## What a deployment does

1. The host hashes the image and serves it over the local network.
2. It copies a small flasher to the board's tmpfs, so nothing needed for the
   write is read from the SD card being replaced.
3. The flasher streams the image to `/dev/mmcblk0`, reads the exact byte range
   back, and compares SHA-256.
4. Only after a match does it reset the PS. The host waits for the new SSH
   service and verifies that `/` is `/dev/mmcblk0p2`.
5. `DEPLOY PASS` is the sole success condition. It normally takes 4–5 minutes.

Follow its journal rather than guessing from a disconnected SSH session:

```bash
systemctl status atlantian-pipeline.service
journalctl -fu atlantian-pipeline.service
```

If a write or verification fails, the job reports `DEPLOY FAIL` and does not
claim success. Recover through UART/U-Boot or write a known-good image to the
SD card externally. Do not interrupt the board once writing has started.
