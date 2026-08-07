# Build and update pipeline

GitHub Actions builds a factory SD image and three packages: `atlantian-platform`,
`atlantian-kernel`, and `atlantian-release`. The image is for a clean install:
write it with any raw-image writer, boot once, and let `atlantian-grow-rootfs`
expand the root filesystem to the full card.

An installed board checks GitHub Releases. `atlantian-sysupgrade` discovers the
latest complete release, displays its metadata and requires `UPGRADE`; it then
downloads those packages over HTTPS, verifies them against the release's
`SHA256SUMS`, installs
them with APT/dpkg, runs `apt full-upgrade`, and reboots. It never overwrites a
partition. The updater preserves ordinary user and Debian state; it warns before
the SSH session is intentionally disconnected for reboot.

Rewriting an SD card is a factory/recovery operation performed with a raw-image
writer. Normal release updates use the package path above.
