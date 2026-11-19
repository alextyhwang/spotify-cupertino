#!/usr/bin/env bash
# Spotify Cupertino installer: makes the Spotify desktop app on macOS look and feel like a native
# Mac app, and run lighter. Works whether or not you already have Spotify and Spicetify.
#
#   curl -fsSL https://github.com/alextyhwang/spotify-cupertino/releases/latest/download/install.sh | bash
#
# Run with --help for options. Safe to run again: it only changes what is out of date.
set -euo pipefail

VERSION="1.0.0"
REPO="alextyhwang/spotify-cupertino"
TESTED_SPOTIFY="1.2.71"          # the Spotify version this release was tuned on
THEME="SpotifyCupertino"
SCHEME="Glass"
OUR_EXTENSIONS=(spotify-perf.js disable-canvas.js)
STATE_DIR="$HOME/.spotify-cupertino"
AGENT_LABEL="com.github.alextyhwang.spotify-cupertino"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

# Optional extras, fetched from their own projects (never bundled here).
ADBLOCK_URL="https://raw.githubusercontent.com/rxri/spicetify-extensions/main/adblock/adblock.js"
SPICY_LYRICS_URL="https://raw.githubusercontent.com/Spikerko/spicy-lyrics/main/builds/spicy-lyrics.mjs"

# ── Options ──────────────────────────────────────────────────────────────────
ACTION="install"; ASSUME_YES=0; LAUNCH=1; AUTO_REAPPLY=1; BLOCK_UPDATES=0
WANT_ADBLOCK=""; WANT_LYRICS=""; WANT_MARKETPLACE=""
SOURCE_DIR="${SPOTIFY_CUPERTINO_SOURCE:-}"

usage() {
  cat <<EOF
Spotify Cupertino $VERSION: a native-feeling, lighter Spotify for macOS.

Usage: install.sh [options]

  (no options)          Install or update. Asks about optional extras if run in a terminal.
  --yes, -y             Don't ask anything; extras stay off unless their flag is given.
  --with-spicy-lyrics   Also install Spicy Lyrics (word-by-word lyrics, from Spikerko/spicy-lyrics).
  --with-marketplace    Also install the Spicetify Marketplace (browse more themes/extensions).
  --with-adblock        Also install adblock.js (from rxri/spicetify-extensions). Blocking ads
                        is against Spotify's terms of service; use at your own risk.
  --block-updates       Stop Spotify from updating itself (keeps the mod pinned).
  --no-auto-reapply     Don't install the helper that re-applies the mod after Spotify updates.
  --no-launch           Don't open Spotify when done.
  --check               Verify the install and print a status report (exit 1 if broken).
  --uninstall           Remove Spotify Cupertino and restore Spotify's own look.
  --version             Print the installer version.
  --help, -h            Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    --with-spicy-lyrics) WANT_LYRICS=1 ;;
    --with-marketplace) WANT_MARKETPLACE=1 ;;
    --with-adblock) WANT_ADBLOCK=1 ;;
    --without-spicy-lyrics) WANT_LYRICS=0 ;;
    --without-marketplace) WANT_MARKETPLACE=0 ;;
    --without-adblock) WANT_ADBLOCK=0 ;;
    --block-updates) BLOCK_UPDATES=1 ;;
    --no-auto-reapply) AUTO_REAPPLY=0 ;;
    --no-launch) LAUNCH=0 ;;
    --check) ACTION="check" ;;
    --uninstall) ACTION="uninstall" ;;
    --reapply) ACTION="reapply" ;;     # used by the update helper
    --source) SOURCE_DIR="$2"; shift ;;
    --version) echo "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

# ── Output ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'; else B=; G=; Y=; R=; D=; N=; fi
step() { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '%sError:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
note() { printf '  %s%s%s\n' "$D" "$*" "$N"; }

# Ask a yes/no question on the terminal, even when the script itself is piped into bash.
ask() {
  local prompt="$1" default="${2:-n}" reply=""
  [ "$ASSUME_YES" = 1 ] && { [ "$default" = y ]; return; }
  [ -r /dev/tty ] && [ -w /dev/tty ] || { [ "$default" = y ]; return; }
  printf '  %s [%s] ' "$prompt" "$([ "$default" = y ] && echo Y/n || echo y/N)" > /dev/tty
  read -r reply < /dev/tty || reply=""
  reply="${reply:-$default}"
  case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# ── Spotify ──────────────────────────────────────────────────────────────────
find_spotify() {
  for app in "/Applications/Spotify.app" "$HOME/Applications/Spotify.app"; do
    [ -d "$app" ] && { echo "$app"; return 0; }
  done
  return 1
}
spotify_version() { defaults read "$1/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown"; }
spotify_running() { pgrep -x Spotify >/dev/null 2>&1; }
quit_spotify() {
  spotify_running || return 0
  osascript -e 'quit app "Spotify"' >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do spotify_running || return 0; sleep 0.5; done
  pkill -x Spotify >/dev/null 2>&1 || true; sleep 1
}
# -g: don't bring Spotify to the front (never steal focus, e.g. from a game).
# open can block (e.g. behind a Gatekeeper prompt), so never wait on it.
# shellcheck disable=SC2086  # SPOTIFY_ARGS is a list of flags
launch_spotify() { (open -g -a "$SPOTIFY_APP" --args ${SPOTIFY_ARGS:-} >/dev/null 2>&1 &) ; }

install_spotify() {
  step "Installing Spotify"
  if command -v brew >/dev/null 2>&1; then
    if brew install --cask spotify; then
      # Homebrew marks downloads as quarantined, so macOS would stop Spotify's first launch to ask
      # "downloaded from the Internet, open it?". The user just asked us to install it, and the
      # direct download below isn't quarantined either, so clear the flag on the app we installed.
      local app; app="$(find_spotify || true)"
      [ -n "$app" ] && xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
      return 0
    fi
    warn "Homebrew install failed; downloading from Spotify instead."
  fi
  local dmg url tmp mnt dest="/Applications"
  case "$(uname -m)" in arm64) url="https://download.scdn.co/SpotifyARM64.dmg" ;; *) url="https://download.scdn.co/Spotify.dmg" ;; esac
  tmp="$(mktemp -d)"; dmg="$tmp/Spotify.dmg"
  curl -fL --progress-bar -o "$dmg" "$url" || die "Couldn't download Spotify from $url"
  mnt="$(hdiutil attach -nobrowse -readonly -noautoopen "$dmg" | awk -F'\t' '/\/Volumes\//{print $NF; exit}')"
  [ -n "$mnt" ] || die "Couldn't open the Spotify disk image."
  [ -w "$dest" ] || dest="$HOME/Applications"
  mkdir -p "$dest"
  ditto "$mnt/Spotify.app" "$dest/Spotify.app"
  hdiutil detach -quiet "$mnt" || true
  rm -rf "$tmp"
  ok "Spotify installed in $dest"
}

# Spicetify needs Spotify's prefs file, which Spotify writes on its first launch.
ensure_prefs() {
  local prefs="$HOME/Library/Application Support/Spotify/prefs"
  [ -f "$prefs" ] && return 0
  step "Starting Spotify once so it can create its settings"
  note "If macOS asks whether to open Spotify, click Open."
  launch_spotify
  for _ in $(seq 1 90); do [ -f "$prefs" ] && break; sleep 1; done
  [ -f "$prefs" ] || die "Spotify didn't create its settings file. Open Spotify once, then run this again."
  sleep 3
  quit_spotify
  ok "Spotify settings created"
}

# ── Spicetify ────────────────────────────────────────────────────────────────
find_spicetify() {
  if command -v spicetify >/dev/null 2>&1; then command -v spicetify; return 0; fi
  for p in "$HOME/.spicetify/spicetify" "/opt/homebrew/bin/spicetify" "/usr/local/bin/spicetify"; do
    [ -x "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

install_spicetify() {
  step "Installing Spicetify (the tool that lets Spotify load themes)"
  local tag ver arch tmp
  tag="$(curl -fsSIL -o /dev/null -w '%{url_effective}' https://github.com/spicetify/cli/releases/latest)"
  tag="${tag##*/}"; ver="${tag#v}"
  [ -n "$ver" ] || die "Couldn't find the latest Spicetify release."
  case "$(uname -m)" in arm64) arch="arm64" ;; *) arch="amd64" ;; esac
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/spicetify.tar.gz" "https://github.com/spicetify/cli/releases/download/$tag/spicetify-$ver-darwin-$arch.tar.gz" \
    || die "Couldn't download Spicetify $ver."
  mkdir -p "$HOME/.spicetify"
  tar -xzf "$tmp/spicetify.tar.gz" -C "$HOME/.spicetify"
  chmod +x "$HOME/.spicetify/spicetify"
  rm -rf "$tmp"
  ok "Spicetify $ver installed in ~/.spicetify"
  note "To use it yourself, add this to your shell profile: export PATH=\"\$HOME/.spicetify:\$PATH\""
}

sp() { "$SPICETIFY" "$@"; }
spice_cfg() { sp -c 2>/dev/null; }
spice_dir() { dirname "$(spice_cfg)"; }
cfg_get() { sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" "$(spice_cfg)" 2>/dev/null | head -1; }
ext_list() { cfg_get extensions | tr '|' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' || true; }
has_ext() { ext_list | grep -qx "$1"; }
add_ext() { has_ext "$1" || sp config extensions "$1" >/dev/null; }
del_ext() { if has_ext "$1"; then sp config extensions "$1-" >/dev/null; fi; }

# ── Theme files (from this folder, or from the matching GitHub release) ──────
fetch_sources() {
  if [ -z "$SOURCE_DIR" ]; then
    local here; here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
    [ -n "$here" ] && [ -f "$here/theme/user.css" ] && SOURCE_DIR="$here"
  fi
  if [ -z "$SOURCE_DIR" ]; then
    local tmp; tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/sc.zip" "https://github.com/$REPO/releases/download/v$VERSION/spotify-cupertino.zip" \
      || die "Couldn't download Spotify Cupertino $VERSION."
    unzip -q "$tmp/sc.zip" -d "$tmp"
    SOURCE_DIR="$tmp/spotify-cupertino"
  fi
  [ -f "$SOURCE_DIR/theme/user.css" ] || die "Theme files not found in $SOURCE_DIR"
}

# ── Install ──────────────────────────────────────────────────────────────────
do_install() {
  [ "$(uname -s)" = "Darwin" ] || die "Spotify Cupertino is for macOS."
  printf '%sSpotify Cupertino %s%s\n' "$B" "$VERSION" "$N"

  SPOTIFY_APP="$(find_spotify || true)"
  if [ -z "$SPOTIFY_APP" ]; then
    ask "Spotify isn't installed. Install it now?" y || die "Spotify is required."
    install_spotify
    SPOTIFY_APP="$(find_spotify)" || die "Spotify still not found after installing."
  fi
  local sv; sv="$(spotify_version "$SPOTIFY_APP")"
  ok "Spotify $sv ($SPOTIFY_APP)"
  [ -w "$SPOTIFY_APP/Contents/Resources" ] || die "Spotify's files aren't writable by you. Run: sudo chown -R \"$USER\" \"$SPOTIFY_APP\"  then run this again."
  if [ "${sv#"$TESTED_SPOTIFY"}" = "$sv" ]; then
    note "Tuned on Spotify $TESTED_SPOTIFY. On $sv the layout still applies; a few spacing details may differ."
  fi

  local was_running=0; spotify_running && was_running=1
  ensure_prefs

  SPICETIFY="$(find_spicetify || true)"
  [ -n "$SPICETIFY" ] || { install_spicetify; SPICETIFY="$(find_spicetify)"; }
  ok "Spicetify $(sp -v 2>/dev/null) ($SPICETIFY)"
  sp config >/dev/null 2>&1 || true   # creates the config on first run
  sp config spotify_path "$SPOTIFY_APP/Contents/Resources" prefs_path "$HOME/Library/Application Support/Spotify/prefs" >/dev/null

  # Optional extras
  [ -n "$WANT_LYRICS" ] || { ask "Add Spicy Lyrics (word-by-word lyrics)?" n && WANT_LYRICS=1 || WANT_LYRICS=0; }
  [ -n "$WANT_MARKETPLACE" ] || { ask "Add the Spicetify Marketplace (more themes and extensions)?" n && WANT_MARKETPLACE=1 || WANT_MARKETPLACE=0; }
  [ -n "$WANT_ADBLOCK" ] || { ask "Add adblock.js? (against Spotify's terms; at your own risk)" n && WANT_ADBLOCK=1 || WANT_ADBLOCK=0; }

  fetch_sources
  local sdir; sdir="$(spice_dir)"
  mkdir -p "$STATE_DIR" "$sdir/Themes/$THEME" "$sdir/Extensions"

  # Remember what was there before, so --uninstall can put it back.
  if [ ! -f "$STATE_DIR/previous" ]; then
    { echo "theme=$(cfg_get current_theme)"; echo "scheme=$(cfg_get color_scheme)"; echo "inject_theme_js=$(cfg_get inject_theme_js)"; } > "$STATE_DIR/previous"
  fi

  step "Installing the theme and extensions"
  cp "$SOURCE_DIR/theme/user.css" "$SOURCE_DIR/theme/theme.js" "$SOURCE_DIR/theme/color.ini" "$sdir/Themes/$THEME/"
  sp config current_theme "$THEME" color_scheme "$SCHEME" inject_css 1 inject_theme_js 1 replace_colors 1 experimental_features 1 >/dev/null
  ok "Theme: $THEME"
  for e in "${OUR_EXTENSIONS[@]}"; do cp "$SOURCE_DIR/extensions/$e" "$sdir/Extensions/$e"; add_ext "$e"; done
  ok "Extensions: ${OUR_EXTENSIONS[*]}"

  if [ "$WANT_LYRICS" = 1 ]; then
    if ext_list | grep -qi 'spicy-lyrics' && ! has_ext spicy-lyrics.mjs; then
      ok "Spicy Lyrics: already installed ($(ext_list | grep -i spicy-lyrics | head -1)), leaving it as is"
    else
      curl -fsSL -o "$sdir/Extensions/spicy-lyrics.mjs" "$SPICY_LYRICS_URL" || die "Couldn't download Spicy Lyrics."
      add_ext spicy-lyrics.mjs; ok "Spicy Lyrics (Spikerko/spicy-lyrics; updates itself)"
    fi
  fi
  if [ "$WANT_ADBLOCK" = 1 ]; then
    curl -fsSL -o "$sdir/Extensions/adblock.js" "$ADBLOCK_URL" || die "Couldn't download adblock.js."
    add_ext adblock.js; ok "adblock.js (rxri/spicetify-extensions)"
  fi
  if [ "$WANT_MARKETPLACE" = 1 ]; then
    if [ -d "$sdir/CustomApps/marketplace" ]; then ok "Marketplace: already installed"
    else
      local tmp; tmp="$(mktemp -d)"
      curl -fsSL -o "$tmp/m.zip" "https://github.com/spicetify/marketplace/releases/latest/download/marketplace.zip" || die "Couldn't download the Marketplace."
      unzip -q "$tmp/m.zip" -d "$tmp"; mkdir -p "$sdir/CustomApps"
      rm -rf "$sdir/CustomApps/marketplace"; mv "$tmp/marketplace-dist" "$sdir/CustomApps/marketplace"; rm -rf "$tmp"
      ok "Marketplace (spicetify/marketplace)"
    fi
    cfg_get custom_apps | tr '|' '\n' | sed 's/^ *//;s/ *$//' | grep -qx marketplace || sp config custom_apps marketplace >/dev/null
  fi

  # Liquid Glass window buttons: Spotify is built with an older macOS SDK, which keeps the old
  # style. This per-app default opts it in (macOS 26 and later; harmless before).
  defaults write com.spotify.client com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck -bool YES

  step "Applying to Spotify"
  quit_spotify
  apply_mod || die "Spicetify couldn't apply the mod. Run '$SPICETIFY restore backup apply' and try again."
  ok "Applied"

  if [ "$BLOCK_UPDATES" = 1 ]; then
    sp spotify-updates block >/dev/null 2>&1 && ok "Spotify updates blocked (undo: $SPICETIFY spotify-updates unblock)" || warn "Couldn't block updates."
    touch "$STATE_DIR/blocked-updates"
  fi
  if [ "$AUTO_REAPPLY" = 1 ]; then install_agent; else remove_agent; fi

  echo "$VERSION" > "$STATE_DIR/version"
  spotify_version "$SPOTIFY_APP" > "$STATE_DIR/spotify-version"
  printf '%s\n' "$SPICETIFY" > "$STATE_DIR/spicetify-path"

  if [ "$LAUNCH" = 1 ] || [ "$was_running" = 1 ]; then launch_spotify; ok "Spotify opened in the background"; fi
  printf '\n%sDone.%s Spotify now looks like a Mac app. Pick a player style from your avatar menu → Player style.\n' "$G" "$N"
  note "Check: bash install.sh --check   Remove: bash install.sh --uninstall"
}

# Spicetify keeps a backup of Spotify's own UI; after a Spotify update it must be retaken.
apply_mod() {
  local out
  if out="$(sp backup apply -n 2>&1)"; then return 0; fi
  if echo "$out" | grep -qiE "already|available backup|backup.*exist"; then
    sp apply -n >/dev/null 2>&1 && return 0
  fi
  sp restore backup apply -n >/dev/null 2>&1 && return 0
  echo "$out" >&2; return 1
}

# ── Re-apply after Spotify updates ───────────────────────────────────────────
install_agent() {
  local script="$STATE_DIR/reapply.sh"
  cat > "$script" <<EOF
#!/usr/bin/env bash
# Re-applies Spotify Cupertino when Spotify updates itself (launchd runs this when Spotify's
# Info.plist changes). Installed by spotify-cupertino $VERSION.
export PATH="\$HOME/.spicetify:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
APP="$SPOTIFY_APP"; STATE="$STATE_DIR"; SP="\$(cat "\$STATE/spicetify-path" 2>/dev/null || echo spicetify)"
sleep 20   # let the update finish writing
new="\$(defaults read "\$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)"
[ -n "\$new" ] && [ "\$new" != "\$(cat "\$STATE/spotify-version" 2>/dev/null)" ] || exit 0
if "\$SP" backup apply -n >/dev/null 2>&1 || "\$SP" restore backup apply -n >/dev/null 2>&1; then
  echo "\$new" > "\$STATE/spotify-version"
  osascript -e 'display notification "Re-applied after Spotify updated. Restart Spotify to see it." with title "Spotify Cupertino"' >/dev/null 2>&1 || true
fi
EOF
  chmod +x "$script"
  mkdir -p "$(dirname "$AGENT_PLIST")"
  cat > "$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$AGENT_LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$script</string></array>
  <key>WatchPaths</key><array><string>$SPOTIFY_APP/Contents/Info.plist</string></array>
  <key>RunAtLoad</key><false/>
  <key>StandardOutPath</key><string>$STATE_DIR/reapply.log</string>
  <key>StandardErrorPath</key><string>$STATE_DIR/reapply.log</string>
</dict></plist>
EOF
  launchctl bootout "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST" >/dev/null 2>&1 || launchctl load "$AGENT_PLIST" >/dev/null 2>&1 || true
  ok "Re-applies itself after Spotify updates"
}
remove_agent() {
  launchctl bootout "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || launchctl unload "$AGENT_PLIST" >/dev/null 2>&1 || true
  rm -f "$AGENT_PLIST" "$STATE_DIR/reapply.sh"
}

# ── Check ────────────────────────────────────────────────────────────────────
do_check() {
  # shellcheck disable=SC2034  # sdir/xpui are used inside the eval'd check expressions
  local bad=0 sdir xpui
  check() { if eval "$2"; then ok "$1"; else printf '  %s✗%s %s\n' "$R" "$N" "$1"; bad=1; fi; }
  printf '%sSpotify Cupertino %s: check%s\n' "$B" "$VERSION" "$N"
  SPOTIFY_APP="$(find_spotify || true)"
  check "Spotify installed${SPOTIFY_APP:+ ($(spotify_version "$SPOTIFY_APP"))}" '[ -n "$SPOTIFY_APP" ]'
  SPICETIFY="$(find_spicetify || true)"
  check "Spicetify installed" '[ -n "$SPICETIFY" ]'
  if [ -n "$SPICETIFY" ] && [ -n "$SPOTIFY_APP" ]; then
    # shellcheck disable=SC2034  # used inside the eval'd check expressions below
    sdir="$(spice_dir)"; xpui="$SPOTIFY_APP/Contents/Resources/Apps/xpui"
    check "Theme selected ($THEME)" '[ "$(cfg_get current_theme)" = "$THEME" ]'
    check "Theme files present" '[ -f "$sdir/Themes/$THEME/user.css" ] && [ -f "$sdir/Themes/$THEME/theme.js" ]'
    for e in "${OUR_EXTENSIONS[@]}"; do check "Extension enabled: $e" 'has_ext "$e" && [ -f "$sdir/Extensions/$e" ]'; done
    check "Theme applied to Spotify" '[ -f "$xpui/extensions/theme.js" ] && grep -q "extensions/theme.js" "$xpui/index.html" && grep -q "gs-sidebar" "$xpui/extensions/theme.js"'
    check "Extensions applied to Spotify" 'grep -q "extensions/spotify-perf.js" "$xpui/index.html"'
  fi
  if [ -f "$AGENT_PLIST" ]; then check "Update helper loaded" 'launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1'; else note "Update helper: off"; fi
  if [ -n "${SPICETIFY:-}" ]; then note "Extensions: $(ext_list | tr '\n' ' ')"; fi
  [ "$bad" = 0 ] && printf '%sAll good.%s\n' "$G" "$N" || printf '%sSomething is off; run the installer again.%s\n' "$R" "$N"
  return "$bad"
}

# ── Uninstall ────────────────────────────────────────────────────────────────
do_uninstall() {
  step "Removing Spotify Cupertino"
  SPOTIFY_APP="$(find_spotify || true)"
  SPICETIFY="$(find_spicetify || true)"
  remove_agent; ok "Update helper removed"
  defaults delete com.spotify.client com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck >/dev/null 2>&1 || true
  if [ -n "$SPICETIFY" ]; then
    local sdir prev_theme="" prev_scheme="" prev_js=""
    sdir="$(spice_dir)"
    [ -f "$STATE_DIR/blocked-updates" ] && { sp spotify-updates unblock >/dev/null 2>&1 || true; ok "Spotify updates unblocked"; }
    for e in "${OUR_EXTENSIONS[@]}"; do del_ext "$e"; rm -f "$sdir/Extensions/$e"; done
    rm -rf "$sdir/Themes/$THEME"
    if [ -f "$STATE_DIR/previous" ]; then
      prev_theme="$(sed -n 's/^theme=//p' "$STATE_DIR/previous")"; prev_scheme="$(sed -n 's/^scheme=//p' "$STATE_DIR/previous")"; prev_js="$(sed -n 's/^inject_theme_js=//p' "$STATE_DIR/previous")"
    fi
    if [ -n "$prev_theme" ] && [ "$prev_theme" != "$THEME" ] && [ -d "$sdir/Themes/$prev_theme" ]; then
      sp config current_theme "$prev_theme" color_scheme "$prev_scheme" inject_theme_js "${prev_js:-0}" >/dev/null
      quit_spotify; sp apply -n >/dev/null 2>&1 || true
      ok "Restored your previous theme ($prev_theme)"
    else
      sp config current_theme "" inject_theme_js 0 >/dev/null 2>&1 || true
      quit_spotify
      if [ -n "$(ext_list)" ]; then sp apply -n >/dev/null 2>&1 || true; ok "Theme removed; your other extensions are still applied"
      else sp restore >/dev/null 2>&1 || true; ok "Spotify restored to its original look"; fi
    fi
    note "Spicetify itself and any extras (Spicy Lyrics, Marketplace, adblock) were left installed."
  fi
  rm -rf "$STATE_DIR"
  [ -n "$SPOTIFY_APP" ] && { launch_spotify; ok "Spotify reopened in the background"; }
}

case "$ACTION" in
  install) do_install ;;
  check) do_check ;;
  uninstall) do_uninstall ;;
  reapply) SPICETIFY="$(find_spicetify)" || die "Spicetify not found"; apply_mod ;;
esac
