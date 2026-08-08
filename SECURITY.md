# Security policy

## Supported scope

| Layer | Support policy |
|---|---|
| AtlANTian release tooling | newest published release |
| Upgrade compatibility | each candidate is tested from the latest older published release |
| Debian userspace | follows Debian support for the installed codename |
| Kernel/board support | pinned AtlANTian board kernel until deliberately changed/tested |
| `BOOT.bin` | pinned external vendor binary trust boundary |

Older AtlANTian releases should update to the newest reachable same-major release
before a Debian-major transition.

## Reporting a vulnerability

Do **not** publish a vulnerability in a public issue before a fix is available.
Use GitHub's private security-advisory mechanism for this repository and include:

- affected release/tag;
- reproduction steps;
- expected vs actual behavior;
- impact and required privileges/access;
- any suggested mitigation.

## Release trust model

| Control | Purpose |
|---|---|
| immutable Debian Snapshot metadata | reproducible factory package baseline |
| pinned Linux commit | deterministic kernel source |
| pinned `BOOT.bin` Git object | detects accidental vendor-binary drift |
| release `SHA256SUMS` | artifact integrity for image/packages |
| version-matched `.deb` set | prevents mixed platform/kernel/release installs |
| GitHub/Sigstore provenance | ties published artifacts to source/workflow/commit |
| previous-release upgrade gate | blocks incompatible package migrations |

The lightweight on-device updater currently trusts GitHub HTTPS plus the
published `SHA256SUMS`. It does **not** claim to verify the Sigstore attestation
locally.

## Initial root access

> [!IMPORTANT]
> Passwordless root access on a fresh image is **intentional by design** for
> appliance-style first provisioning, similar to OpenWrt. It is not a fallback
> password and no shared SSH host private key is embedded in the image.

Factory behavior:

- root account exists with an empty password;
- SSH permits initial root provisioning;
- each flash generates a unique machine ID and SSH host keys;
- an interactive root shell warns until a password is set.

Keep a fresh board on a trusted network. When authenticated access is desired:

```sh
passwd
```

or install your own root SSH public key.

## Debian repositories

Factory builds use immutable Snapshot metadata. Running systems use live,
codename-pinned Debian HTTPS repositories, including security updates. The moving
`stable` alias is never used on-device, so Debian-major changes only occur via
`atlantian-sysupgrade`.

## Hardware trust boundaries

- Zynq/FPGA and physical pin behavior cannot be fully proven by QEMU CI.
- Unverified/conflicting routes stay disabled or profile-only.
- `BOOT.bin` is external and is not claimed to be reproducible from this repo.
- `poweroff` cannot physically remove the external 12 V rail.

See [Hardware support](docs/hardware-support-matrix.md) and
[Release pipeline](docs/PIPELINE.md) for the validation boundary.
