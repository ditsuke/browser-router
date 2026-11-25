# Browser Router

A native macOS browser router with separate routing profiles, default destinations, and URL overrides.

## Build and run

Requires macOS 14+ and Swift 6.

```sh
bash scripts/build.sh
open "dist/Browser Router.app"
```

For regular use, put the app in `/Applications` and choose **Make default browser**.

## Nix

Apple Silicon Macs:

```sh
nix run
nix profile add .
```

`nix build` produces `result/Applications/Browser Router.app`. The package is also exposed as `.#browser-router`. Keep Nix-built bundles in the store; they aren't standalone distributions.

Other flakes can use `inputs.browser-router.packages.${system}.default`. Override `browser-router.inputs.nixpkgs.follows` to share a **Swift 6-capable** Nixpkgs input.

## Configuration

`$XDG_CONFIG_HOME/browser-router/config.json`, or `~/.config/browser-router/config.json` when XDG is unset, empty, or relative.

Rules use the first enabled match:

- **Domain:** exact hostname.
- **Domain + subdomains:** the hostname and its subdomains.
- **URL glob:** whole-URL match; `*` is the only wildcard.
- **URL regex:** searches the URL; use `^`/`$` to anchor and `(?i)` to ignore case. No `/…/` delimiters.

Globs and regexes match the percent-encoded URL. Local HTML documents use the active routing profile's default destination.

Browser-profile targeting supports Chrome, Brave, Edge, Chromium (including Ungoogled Chromium), and Vivaldi in their standard data directories. Other browsers use their own current/default profile. Custom user-data directories aren't discovered.

## Development

```sh
swift run RouterCoreChecks
nix flake check
nix develop
```

Bundles are ad-hoc signed; distribution signing and notarization aren't configured.
