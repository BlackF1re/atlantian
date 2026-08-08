# Security policy

## Supported scope

| Layer | Support policy |
|---|---|
| AtlANTian release tooling | newest published release |
| Upgrade compatibility | every release after the first is tested from the latest older published release |
| Debian userspace | follows Debian support for the installed codename |
| Kernel/board support | pinned board kernel until deliberately changed and validated |
| SD boot firmware | pinned upstream U-Boot commit, built from source; low-level changes require board validation |

Older supported releases should move through the newest reachable same-major
AtlANTian release before a Debian-major transition.

## Reporting a vulnerability

Do **not** publish a vulnerability in a public issue before a fix is available.
Use GitHub's private security-advisory mechanism and include:

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
| pinned upstream U-Boot commit | deterministic source for SPL `BOOT.bin` + `u-boot.img` |
| release `SHA256SUMS` | artifact integrity for image/packages |
| version-matched `.deb` set | prevents mixed platform/kernel/release installs |
| GitHub/Sigstore provenance | ties published artifacts to source/workflow/commit |
| previous-release upgrade gate | blocks incompatible package migrations after the initial release |

The previous opaque vendor `BOOT.bin` remains only as a legacy diagnostic
reference. It is not a production release input.

> [!NOTE]
> The on-device updater verifies GitHub HTTPS downloads against the published
> `SHA256SUMS`. It does **not** currently verify the Sigstore attestation locally.

## Initial root access

> [!IMPORTANT]
> Passwordless root access on a fresh image is **intentional by design** for
> appliance-style first provisioning, similar to OpenWrt. It is not a fallback
> password and no shared SSH host private key is embedded in the image.

Factory behavior:

- root exists with an empty password;
- SSH permits initial root provisioning;
- each flash generates a new machine ID and SSH host keys;
- an interactive root shell warns until a password is set.

Keep a fresh board on a trusted network. When authenticated access is desired:

```sh
passwd
```

or install your own root SSH public key.

## Debian repositories

Factory builds use immutable Snapshot metadata. Running systems use live,
codename-pinned Debian HTTPS repositories, including security updates. The moving
`stable` alias is never used on-device, so Debian-major changes occur only via
`atlantian-sysupgrade`.

## Hardware validation boundary

CI can validate source pins, build products, package transitions and software
contracts, but cannot prove physical Zynq BootROM/SPL execution, FPGA routing or
electrical behavior. U-Boot and kernel pin changes therefore remain deliberate
hardware-validation events rather than automatically merged dependency updates.
Unverified or conflicting routes stay disabled/profile-only.

See [Hardware support](docs/hardware-support-matrix.md),
[Boot firmware](boot-candidate/README.md) and
[Release pipeline](docs/PIPELINE.md).
