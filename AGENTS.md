# Repository instructions

Use Conventional Commits for commit messages: `<type>(<optional scope>): <description>`.
For example, `feat: add regex URL matching` or `fix: discover Ungoogled Chromium profiles`.

When publishing a changed app bundle, increment `CFBundleVersion` and keep
`CFBundleShortVersionString` in sync with the Nix package version. macOS uses
bundle versions to choose between registered app copies.
