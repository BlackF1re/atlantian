# Security policy

Do not report vulnerabilities in public issues before a fix is available.
Use GitHub's private security-advisory mechanism for this repository and
include the affected release tag, reproduction steps, and impact.

AtlANTian verifies release payload hashes before writing them. The default
image intentionally permits passwordless root login for first boot; owners
must run `passwd` before exposing a board outside a trusted network.
