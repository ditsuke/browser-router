# Browser Router

A small native macOS browser dispatcher. Set it as your default browser, choose a real browser as the fallback, and add ordered URL overrides. No server, account, dependencies, or telemetry. Requires macOS 14+ and Swift 6 to build.

## Build and run

```sh
bash scripts/build.sh
open "dist/Browser Router.app"
```

For permanent use, copy the app to `/Applications` before opening it and choosing **Make default browser**. macOS may ask you to confirm the change. You can also select Browser Router in System Settings → Desktop & Dock → Default web browser.

## Nix

The flake provides a package and development shell for Apple Silicon Macs. Its lock file reuses the Swift 6-capable Nixpkgs revision already pinned as a secondary input in the author's dotfiles; it has no dependency on that local checkout. This Nixpkgs revision no longer supports Intel Macs; the local Swift build remains available there.

```sh
nix build
open "result/Applications/Browser Router.app"
# Or build and launch in one step:
nix run

# Build the app and run its routing/configuration checks:
nix flake check

# Enter the pinned Swift development environment:
nix develop
```

The default package is also available as `.#browser-router`. It installs the app under `Applications/Browser Router.app` and a `browser-router` launcher under `bin`. `nix profile add .` keeps the package installed and makes the launcher available. Nix-built apps depend on their Nix store closure; use the profile or your Nix configuration to retain it instead of copying the bundle out as a standalone distribution.

To include it in another flake, add this repository as an input and use `inputs.browser-router.packages.${system}.default`. For example, put that package in nix-darwin's `environment.systemPackages`. No system or default-browser settings are changed by building or installing it.

The menu bar branch icon opens settings. Closing the settings window leaves routing active. macOS launches the app when a web link is opened, so a login item is unnecessary. Quitting does not change the system's default browser; choose another browser in System Settings to stop using the router.

## Routing

### Routing profiles

Create profiles such as **Personal** and **Work**, each with its own default destination and ordered overrides. Choose a profile card in the router window, press **⌘1–⌘9** for the first nine profiles, or switch from the menu bar menu. Switching takes effect immediately for future links and the active profile is remembered across restarts. Shortcuts apply while the router window is focused; they are not global hotkeys.

Use **Manage** to create, duplicate, rename, or delete a profile. New profiles start with Safari and no overrides; duplicates copy the current profile’s destinations and rules. Deleting requires confirmation, and the last profile cannot be deleted. These routing profiles are separate from browser profiles such as Chromium’s Work profile, which remain available as destinations within any routing profile.

### Keyboard shortcuts

These work while the router window is focused. Profile dialogs keep their normal Return/Escape behavior.
The **Shortcuts** menu in the router window lists commands with native shortcut labels. The macOS menu bar icon offers the same commands. Buttons show shortcut tooltips on hover; Refresh, profile cards, and the overrides header also show their shortcuts inline.

| Shortcut | Action |
| --- | --- |
| ⌘1–⌘9 | Activate a routing profile |
| ⌘N | Create a routing profile |
| ⌘D | Duplicate the active routing profile |
| ⌘O | Expand or collapse overrides |
| ⇧⌘N | Add an override and expand the section |
| ⌘L | Open the URL tester popover and focus its field |
| Return in the test URL field | Open the test URL |
| ⌘R | Refresh browsers and browser profiles |

### Override rules

- Choose a default destination, including a profile where supported.
- Overrides start collapsed, showing configured and enabled rule counts for the active profile. Expand to add or edit rules and reorder them with the arrows. Switching profiles collapses the section again. The first enabled match wins.
- **Domain** matches only `example.com`.
- **Domain + subdomains** matches `example.com` and `work.example.com`, never `notexample.com`.
- **URL glob** matches the whole URL. `*` means any sequence of characters; everything else is literal and case sensitive. Matching uses the URL’s percent-encoded representation. Example: `https://github.com/my-org/*`.
- **URL regex** searches the percent-encoded URL with Foundation regular expressions. Use `^` and `$` to anchor the match, or `(?i)` for case-insensitive matching. Example: `^https://(www\.)?example\.com/(work|admin)(/|$)`. Enter the expression directly without `/…/` delimiters. Invalid and empty expressions show an inline error and are skipped.
- Use **Test URL** beside the default destination (⌘L) to open the tester popover. It previews the destination and matched override, or explains that the default applies. Return opens the link; Escape closes the popover.

HTTP(S) links follow the active routing profile's overrides. Local HTML/XHTML documents use that profile's default destination. The app declares both web schemes and HTML document handling, which macOS requires to classify it as an eligible default browser. Browsers are opened explicitly, preventing default-browser recursion. Missing destinations produce a visible error rather than silently opening another profile. Links opened inside a browser generally stay there; Browser Router handles links sent to the system default browser.

## Browser and profile discovery

Installed HTTP(S) handlers are discovered through Launch Services. **Refresh browsers** picks up changes. Chrome (including Beta/Dev/Canary), Brave (stable/Beta), Edge (stable/Beta), Chromium (including Ungoogled Chromium), and Vivaldi profiles are read from their standard `Local State` files under `~/Library/Application Support`. Profile folders must exist. A browser may need to be launched once before profiles appear.

Profile routes invoke the browser executable with `--profile-directory` and the URL as separate arguments, including when the browser is already running. No shell is involved. Custom user-data directories are not discovered. Safari, Firefox, Arc, and other browsers are offered as browser-level destinations only; their profile/space selection is not implemented. Browser-level routes use the browser's own current/default profile behavior.

Settings save atomically to `$XDG_CONFIG_HOME/browser-router/config.json` when `XDG_CONFIG_HOME` is an absolute path, otherwise `~/.config/browser-router/config.json`. Empty or relative XDG paths use the fallback. Browser history, cookies, and passwords are never read. If the configuration cannot be decoded, the app shows an error and preserves the file without overwriting it. Quit, repair or move the file, and relaunch to recover.

## Development

```sh
swift run RouterCoreChecks
```

Tests cover rule ordering, disabled rules, domain boundaries, literal/anchored glob matching, configuration round trips, and profile metadata parsing. The build script creates an ad-hoc signed local app; distribution signing and notarization are not configured.

Manual integration checks: open the built app, select a browser/profile, test with that browser both closed and running, then set the router as default and open a link from another app. Verify overrides and the fallback. The build does not change your default browser automatically.
