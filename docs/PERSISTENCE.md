# Persistent state boundary

`/data` (`mmcblk0p3`) is the only partition never overwritten by a normal
release update. AtlANTian mounts an overlay for `/etc` and bind mounts for
`/root`, `/home`, and `/var/local` from `/data/system/atlantian/persist`.

The persistent mount is activated before normal local filesystems, networking,
SSH, and host-key generation. It is not an initramfs overlay: settings consumed
by PID 1 before `atlantian-persist-state.service` starts are release defaults.
That limitation is deliberate and documented until an initramfs-based overlay
is introduced.
