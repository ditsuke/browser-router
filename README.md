# Browser Router

A small native macOS browser dispatcher. Set it as your default browser, choose a real browser as the fallback, and add ordered URL overrides. No server, account, dependencies, or telemetry. Requires macOS 14+ and Swift 6 to build.

## Build and run

```sh
bash scripts/build.sh
open "dist/Browser Router.app"
```

For permanent use, copy the app to `/Applications` before opening it and choosing **Make default browser**. macOS may ask you to confirm the change. You can also select Browser Router in System Settings → Desktop & Dock → Default web browser.

The menu bar branch icon opens settings. Closing the settings window leaves routing active. macOS launches the app when a web link is opened, so a login item is unnecessary. Quitting does not change the system's default browser; choose another browser in System Settings to stop using the router.

## Routing

### Routing profiles

Create profiles such as **Personal** and **Work**, each with its own default destination and ordered overrides. Choose a profile card in the router window, press **⌘1–⌘9** for the first nine profiles, or switch from the menu bar menu. Switching takes effect immediately for future links and the active profile is remembered across restarts. Shortcuts apply while the router window is focused; they are not global hotkeys.

Use **Manage** to create, duplicate, rename, or delete a profile. New profiles start with Safari and no overrides; duplicates copy the current profile’s destinations and rules. Deleting requires confirmation, and the last profile cannot be deleted. These routing profiles are separate from browser profiles such as Chromium’s Work profile, which remain available as destinations within any routing profile.

Existing settings become a **Personal** profile automatically. Before the app saves the new format, it preserves the original file as `config.before-profiles.json` next to `config.json`.

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
| ⌘L | Focus the test URL field |
| Return in the test URL field | Open the test URL |
| ⌘R | Refresh browsers and browser profiles |

### Override rules

- Choose a default destination, including a profile where supported.
- Overrides start collapsed, showing configured and enabled rule counts for the active profile. Expand to add or edit rules and reorder them with the arrows. Switching profiles collapses the section again. The first enabled match wins.
- **Domain** matches only `example.com`.
- **Domain + subdomains** matches `example.com` and `work.example.com`, never `notexample.com`.
- **URL glob** matches the whole URL. `*` means any sequence of characters; everything else is literal and case sensitive. Matching uses the URL’s percent-encoded representation. Example: `https://github.com/my-org/*`.
- **URL regex** searches the percent-encoded URL with Foundation regular expressions. Use `^` and `$` to anchor the match, or `(?i)` for case-insensitive matching. Example: `^https://(www\.)?example\.com/(work|admin)(/|$)`. Enter the expression directly without `/…/` delimiters. Invalid and empty expressions show an inline error and are skipped.
- Use the test field to preview the destination or open the link explicitly.

Only HTTP(S) links are handled. Browsers are opened explicitly, preventing default-browser recursion. Missing destinations produce a visible error rather than silently opening another profile. Links opened inside a browser generally stay there; Browser Router handles links sent to the system default browser.

## Browser and profile discovery

Installed HTTP(S) handlers are discovered through Launch Services. **Refresh browsers** picks up changes. Chrome (including Beta/Dev/Canary), Brave (stable/Beta), Edge (stable/Beta), Chromium (including Ungoogled Chromium), and Vivaldi profiles are read from their standard `Local State` files under `~/Library/Application Support`. Profile folders must exist. A browser may need to be launched once before profiles appear.

Profile routes invoke the browser executable with `--profile-directory` and the URL as separate arguments, including when the browser is already running. No shell is involved. Custom user-data directories are not discovered. Safari, Firefox, Arc, and other browsers are offered as browser-level destinations only; their profile/space selection is not implemented. Browser-level routes use the browser's own current/default profile behavior.

Settings save atomically to `~/Library/Application Support/BrowserRouter/config.json`. Browser history, cookies, and passwords are never read. If the configuration cannot be decoded, the app shows an error and preserves the file without overwriting it. Quit, repair or move the file, and relaunch to recover.

## Development

```sh
swift run RouterCoreChecks
```

Tests cover rule ordering, disabled rules, domain boundaries, literal/anchored glob matching, configuration round trips, and profile metadata parsing. The build script creates an ad-hoc signed local app; distribution signing and notarization are not configured.

Manual integration checks: open the built app, select a browser/profile, test with that browser both closed and running, then set the router as default and open a link from another app. Verify overrides and the fallback. The build does not change your default browser automatically.
