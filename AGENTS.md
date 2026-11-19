# AGENTS.md

Notes for AI agents working on this repo. If you were only asked to **install** Spotify Cupertino on someone's Mac, see "For agents installing it" at the end of this file; you don't need the rest.

## What this is

A Spicetify theme plus two small extensions that make the official Spotify desktop app on macOS look and feel like a native Mac app and use less CPU. `install.sh` is the product: it installs Spotify and Spicetify if they're missing, applies the mod, and can check or uninstall it.

```
install.sh                 the installer (also published as a release asset)
theme/user.css             layout, type, surfaces, player styles
theme/theme.js             sidebar, Home playlist grid, title bar, search-suggestions default
theme/color.ini            the "Glass" colour scheme (Apple system colours)
extensions/spotify-perf.js copy of github.com/alextyhwang/spotify-perf (that repo is the source of truth)
extensions/disable-canvas.js turns off Canvas looping videos
docs/                      README screenshots
.github/workflows/         test.yml (fresh-VM install tests), release.yml (tag → release + smoke test)
```

## Rules

- **Lightweight first.** No `backdrop-filter`, no animation loops, no broad `MutationObserver`s: the player's clock changes every second, so a subtree observer fires constantly. Use `ResizeObserver`, or a short-lived observer that disconnects itself, the way `ensureHomeSoon` does.
- **Never focus or resize the user's Spotify window.** Launch it with `open -g`. The user may be gaming. Capture screenshots with `screencapture -l <windowID>` or CDP `Page.captureScreenshot`, both of which work while the window is in the background.
- **Spotify's own buttons ignore programmatic `.click()`.** Navigate with `Spicetify.Platform.History.push(path)`.
- **Hashed class names** (e.g. `.T0fKO6B7LQSCE_VaSM1P`) only exist in the Spotify version in `TESTED_SPOTIFY` (install.sh). Prefer stable `main-*`, `encore-*` or `data-testid` selectors. When a hashed class is unavoidable, keep it in a commented block so a missing match only loses that detail.
- **Fonts:** use `system-ui`, not `-apple-system`. On Chromium, which Spotify runs on, `-apple-system` is not SF Pro; `system-ui` is, with Apple's optical sizes and tracking applied automatically.
- **Window geometry:** `theme.js` reports a 54 pt title bar through `ControlMessageAPI.setTitlebarHeight`, so the window buttons sit 20 pt from the top and from the left. It also exposes `--gs-titlebar` and `--gs-window-r` (the window's 16 pt corner radius) in CSS px. Corners near the window's corners should be concentric with it: inner radius = window radius − inset.
- **Spacing:** every page starts its content 32 px from the sidebar and 32 px from the top (`--content-spacing`). Check new pages against that.
- **Third-party extras** (Spicy Lyrics, Marketplace, adblock.js) are downloaded from their own repos at install time. Never vendor them.
- **No AI attribution** in commits or PRs (no `Co-Authored-By`, no "Generated with" lines).
- **Privacy:** screenshots must not show the user's library, playlist names, Blend partners, account name or avatar. Use public album, artist or Browse pages, and blur the avatar.

## Testing

Static checks (CI runs these too):

```sh
bash -n install.sh && shellcheck -S warning install.sh
node --check theme/theme.js extensions/*.js
```

Try the installer from a checkout without touching GitHub:

```sh
SPOTIFY_ARGS=--remote-debugging-port=9229 ./install.sh --yes --no-auto-reapply   # uses the local theme/ and extensions/
./install.sh --check
```

To inspect the running app, launch Spotify with `--remote-debugging-port=9229` (the line above does) and drive it over the Chrome DevTools Protocol from Node (`node --experimental-websocket`, `Runtime.evaluate`). `Spicetify.Platform` exposes the app's APIs. To test UI that needs focus, such as the search dropdown, call `Emulation.setFocusEmulationEnabled` first. Measure layouts with `getBoundingClientRect` rather than judging screenshots by eye.

`test.yml` runs on fresh macOS VMs on every push: lint, plus three setups (Homebrew, Spotify DMG without Homebrew, existing Spicetify user). Each one installs with every extra, checks, re-runs, checks again and uninstalls. CI can't log in to Spotify, so it verifies files and config, not rendering.

## Releasing

1. Bump `VERSION` in `install.sh`. Update `TESTED_SPOTIFY` if you tuned on a new Spotify.
2. Make sure `test.yml` is green on `main`.
3. `git tag -a vX.Y.Z -m "Spotify Cupertino X.Y.Z" && git push origin vX.Y.Z`

`release.yml` checks that the tag matches `VERSION`, publishes `install.sh` and `spotify-cupertino.zip`, then installs from the published one-liner on a fresh VM. The installer downloads the zip for its own `VERSION`, so the tag and `VERSION` must match.

## For agents installing it

Run:

```sh
curl -fsSL https://github.com/alextyhwang/spotify-cupertino/releases/latest/download/install.sh | bash -s -- --yes
curl -fsSL https://github.com/alextyhwang/spotify-cupertino/releases/latest/download/install.sh | bash -s -- --check
```

Report the `--check` output. Ask the user before adding `--with-spicy-lyrics`, `--with-marketplace` or `--with-adblock`. Adblock is against Spotify's terms, so say so when you ask. Don't run with `sudo`. If the installer says Spotify's files aren't writable, show the user the `chown` command it prints and let them run it.
