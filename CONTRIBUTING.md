# Contributing

Use Conventional Commits, for example `fix(storage): reject an oversized release
bundle`. Keep changes narrow and include a test when changing image layout,
persistence, boot, Debian lifecycle or update logic.

Pull requests run read-only CI. Releases are created only from `main` after the
production workflow completes. Changes to Debian base selection must preserve
the separation between immutable build Snapshot inputs and codename-pinned live
runtime APT sources, and must never permit an automatic multi-major jump.

Do not commit board addresses, SSH keys, personal host names, local paths or
local timezone preferences; use `config/local.env` for installation-specific
overrides.
