# Security policy

Do not report vulnerabilities in public issues before a fix is available. Use
GitHub's private security-advisory mechanism for this repository and include the
affected release tag, reproduction steps and impact.

AtlANTian release packages are version-matched and checked against the published
`SHA256SUMS` before installation. Release artifacts also receive a
Sigstore-backed GitHub Actions build-provenance attestation tied to the source
repository, workflow and commit. The lightweight on-device updater currently
trusts GitHub HTTPS plus `SHA256SUMS`; it does **not** claim to verify that
Sigstore attestation locally.

Factory builds use immutable Debian Snapshot metadata, while installed systems
receive ordinary security/package updates from codename-pinned Debian HTTPS
repositories. Debian major changes are staged explicitly by
`atlantian-sysupgrade`; the moving `stable` alias is never used on-device.

The factory image intentionally permits passwordless root login for initial
bench setup. Each flashed installation generates a unique machine identity and
SSH host keys on first boot; no build-time SSH server private keys are shipped.
Set a root password with `passwd` before exposing a board to an untrusted
network.

`boot-candidate/BOOT.bin` is a pinned external binary firmware input and is not
claimed to be reproducible from this repository. CI checks its pinned Git object
ID before producing a release.
