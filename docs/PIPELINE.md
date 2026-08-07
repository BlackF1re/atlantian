# Build and update pipeline

GitHub Actions builds a factory SD image and three packages: `atlantian-platform`,
`atlantian-kernel`, and `atlantian-release`. The image is for a clean install:
write it with any raw-image writer, boot once, and let `atlantian-grow-rootfs`
expand the root filesystem to the full card.

An installed board checks GitHub Releases. `atlantian-sysupgrade` discovers the
latest complete release, displays its metadata and requires `UPGRADE`. After
confirmation it starts the D3 update pattern before downloading the release
assets, verifies the packages against the release's `SHA256SUMS`, installs them
with APT/dpkg, runs `apt full-upgrade`, and requests a reboot. The update pattern
stays active throughout that download/verify/install lifecycle until system
shutdown begins. The updater never overwrites a partition and preserves ordinary
user and Debian state; it warns before the SSH session is intentionally
disconnected for reboot.

The boot partition is FAT32, so `atlantian-kernel` deliberately stores its
package payload under `/usr/lib/atlantian/boot` on the ext4 root filesystem.
Its post-install script copies the three boot files to `/boot`; this avoids
dpkg's unsupported FAT hard-link backup operation. `zram-tools` remains the
owner of `/etc/default/zramswap`, so platform updates never replace its Debian
configuration file.

Rewriting an SD card is a factory reinstallation operation performed with a
raw-image writer. Normal release updates use the package path above.

The release endpoint is a small, explicit configuration file:
`/etc/atlantian/releases.conf`. It supplies the GitHub owner/repository and API
base URL; the updater itself contains no board- or account-specific URL.
