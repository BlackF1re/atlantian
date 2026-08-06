# Contributing

Use Conventional Commits in the comprehensive style, for example
`fix(storage): reject an oversized release bundle`. Keep changes narrow and
include a test when changing image layout, persistence, boot, or update logic.

Pull requests run read-only CI. Releases are created only from `main` after
the release workflow completes. Do not commit board addresses, SSH keys,
personal host names, or local timezone preferences; use `config/local.env`.
