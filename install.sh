#!/usr/bin/env bash
# Chicago95 IceWM Desktop — installer
#
# Applies the full IceWM + Chicago95 desktop setup on top of an existing
# Ubuntu install: a Start menu with every installed app, a taskbar
# "Applications" button that opens a flat one-page app grid (like Ubuntu's
# app grid or macOS Launchpad), HiDPI-correct window chrome, theme-consistent
# default apps, and a synced GTK3/GTK4/icon-theme setup.
#
# Every file this script overwrites is backed up first, and every gsettings
# key it changes has its old value recorded — see uninstall.sh to revert.
#
# Usage (fresh Ubuntu 26.04, nothing else needed first):
#   git clone https://github.com/gegestalt/chicago95-icewm-desktop ~/chicago95-icewm-desktop
#   cd ~/chicago95-icewm-desktop
#   ./install.sh
#   reboot
#
# One run takes a stock Ubuntu desktop to the finished Chicago OS:
# system setup (system-setup.sh: X11 + LightDM + IceWM session, VS Code,
# Ghostty, dev tools), the upstream Chicago95 theme, every config in this
# repo, Claude Code, then removes what Chicago OS doesn't use
# (system/slim-down.sh). Skip parts with CHICAGO_SKIP_SYSTEM=1 or
# CHICAGO_SKIP_SLIM=1.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not root — it will sudo when it needs to." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This installer targets Ubuntu/Debian (apt-get not found)." >&2
  exit 1
fi

echo "== Chicago95 IceWM Desktop installer =="
echo

if [ -z "${CHICAGO_SKIP_SYSTEM:-}" ]; then
  echo "-- System setup (sudo required) --"
  "$REPO_DIR/system-setup.sh"
fi

# ---------------------------------------------------------------------------
# 0. Backup tracking. Every destination path this script writes to is passed
#    through track() first: if it already exists, it's copied into this
#    run's backup dir and marked EXISTED; otherwise it's marked NEW. Every
#    gsettings key it changes goes through track_gsetting() the same way.
#    uninstall.sh replays this manifest in reverse.
# ---------------------------------------------------------------------------
STATE_DIR="$HOME/.chicago95-icewm-desktop"
TS="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo run)"
BACKUP_ROOT="$STATE_DIR/backups/$TS"
MANIFEST="$BACKUP_ROOT/manifest.txt"
GSETTINGS_RESTORE="$BACKUP_ROOT/gsettings-restore.sh"
XFCONF_RESTORE="$BACKUP_ROOT/xfconf-restore.sh"
DCONF_RESTORE="$BACKUP_ROOT/dconf-restore.sh"
mkdir -p "$BACKUP_ROOT/existed"
: > "$MANIFEST"
echo "#!/bin/sh" > "$GSETTINGS_RESTORE"
echo "#!/bin/sh" > "$XFCONF_RESTORE"
echo "#!/bin/sh" > "$DCONF_RESTORE"

track() {
  local path="$1"
  local rel="${path#/}"
  if [ -e "$path" ] || [ -L "$path" ]; then
    mkdir -p "$(dirname "$BACKUP_ROOT/existed/$rel")"
    cp -a "$path" "$BACKUP_ROOT/existed/$rel"
    echo "EXISTED $path" >> "$MANIFEST"
  else
    echo "NEW $path" >> "$MANIFEST"
  fi
}

track_gsetting() {
  local schema="$1" key="$2"
  local old
  old="$(gsettings get "$schema" "$key" 2>/dev/null || true)"
  if [ -n "$old" ]; then
    echo "gsettings set $schema $key $old" >> "$GSETTINGS_RESTORE"
  fi
}

track_xfconf() {
  local channel="$1" prop="$2"
  local old
  old="$(xfconf-query -c "$channel" -p "$prop" 2>/dev/null || true)"
  if [ -n "$old" ]; then
    printf 'xfconf-query -c %s -p %s -s %q\n' "$channel" "$prop" "$old" >> "$XFCONF_RESTORE"
  else
    printf 'xfconf-query -c %s -p %s -r 2>/dev/null || true\n' "$channel" "$prop" >> "$XFCONF_RESTORE"
  fi
}

track_dconf() {
  local key="$1"
  local old
  old="$(dconf read "$key" 2>/dev/null || true)"
  if [ -n "$old" ]; then
    printf 'dconf write %s %q\n' "$key" "$old" >> "$DCONF_RESTORE"
  else
    printf 'dconf reset %s\n' "$key" >> "$DCONF_RESTORE"
  fi
}

echo "$TS" > "$STATE_DIR/last-backup"
echo "-- Backups for this run: $BACKUP_ROOT --"

# ---------------------------------------------------------------------------
# 1. Prerequisite: the upstream Chicago95 GTK/icon/cursor theme
# ---------------------------------------------------------------------------
# Pinned to the upstream commit Chicago OS was built and tested with, so
# a fresh install looks exactly the same. Copies what upstream's GUI
# installer.py would (theme, icons, cursors, fonts) without its dialogs.
CHICAGO95_UPSTREAM=https://github.com/grassmunk/Chicago95.git
CHICAGO95_COMMIT=5da19b8
if [ ! -d "$HOME/.themes/Chicago95" ] || [ ! -d "$HOME/.icons/Chicago95-tux" ]; then
  echo "-- Installing the upstream Chicago95 theme ($CHICAGO95_COMMIT) --"
  command -v git >/dev/null 2>&1 || sudo apt-get install -y git
  if [ ! -d "$HOME/Chicago95/.git" ]; then
    git clone -q "$CHICAGO95_UPSTREAM" "$HOME/Chicago95"
  fi
  git -C "$HOME/Chicago95" checkout -q "$CHICAGO95_COMMIT"
  mkdir -p "$HOME/.themes" "$HOME/.icons" "$HOME/.fonts"
  cp -a "$HOME/Chicago95/Theme/Chicago95" "$HOME/.themes/"
  cp -a "$HOME/Chicago95/Icons/." "$HOME/.icons/"
  cp -a "$HOME/Chicago95/Cursors/." "$HOME/.icons/"
  cp -a "$HOME/Chicago95/Fonts/." "$HOME/.fonts/"
fi

# ---------------------------------------------------------------------------
# 2. Packages (nothing to back up here — apt tracks its own state, and this
#    installer never removes a package on its own).
# ---------------------------------------------------------------------------
echo "-- Installing packages (sudo required) --"
sudo apt-get update -qq
sudo apt-get install -y \
  icewm icewm-common \
  xfce4-settings \
  gpicview evince mpv \
  dunst pcmanfm libfm-modules \
  network-manager-gnome \
  yad arandr \
  blueman pavucontrol xfce4-power-manager hardinfo2 \
  python3-gi python3-cairo gir1.2-gtk-3.0 \
  imagemagick \
  xdotool picom x11-utils mesa-utils tint2 jgmenu fonts-ubuntu fonts-jetbrains-mono

# ---------------------------------------------------------------------------
# 3. Detect display DPI and pick the matching theme-asset scale
#
#    Re-detected on every run, this isn't actually idempotent: on at least
#    one VM (VMware guest tools auto-fitting the display to the host
#    window), the X server's own reported DPI has been observed to drift
#    from 144 down to 96 on its own, between logins, with no user action.
#    A plain re-run of install.sh then "detects" 96, silently downgrades a
#    HiDPI setup to 1x theme assets, and the fonts/taskbar shrink for no
#    reason the user did anything to cause. So: detect once, then reuse
#    that value on every later run. Pass CHICAGO95_REDETECT_DPI=1 to force
#    a fresh probe (e.g. after actually changing monitors).
# ---------------------------------------------------------------------------
DPI_STATE_FILE="$STATE_DIR/dpi"
if [ -f "$DPI_STATE_FILE" ] && [ -z "${CHICAGO95_REDETECT_DPI:-}" ]; then
  DPI="$(cat "$DPI_STATE_FILE")"
  echo "-- Using previously-detected ${DPI} DPI from $DPI_STATE_FILE --"
  echo "   (set CHICAGO95_REDETECT_DPI=1 to re-detect, e.g. after a real monitor change)"
else
  DPI=96
  if command -v xdpyinfo >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    DETECTED=$(xdpyinfo 2>/dev/null | sed -n 's/^ *resolution: *\([0-9]*\)x.*/\1/p' | head -1)
    [ -n "${DETECTED:-}" ] && DPI="$DETECTED"
  fi
  mkdir -p "$STATE_DIR"
  echo "$DPI" > "$DPI_STATE_FILE"
  echo "-- Detected ${DPI} DPI, saved to $DPI_STATE_FILE for future runs --"
fi
if [ "$DPI" -ge 120 ]; then
  SCALE=2x
else
  SCALE=1x
fi
echo "-- Using $SCALE theme assets --"

# ---------------------------------------------------------------------------
# 3b. Xft.dpi via ~/.Xresources — this is what actually makes GTK/Xft apps
#    (Firefox included) render at the correct size. It's auto-loaded at
#    login by the standard /etc/X11/Xsession.d/30x11-common_xresources
#    hook, so nothing else needs to reference it. Do NOT also set
#    GDK_SCALE for GTK apps — it compounds with this and over-scales
#    (this bit us: Firefox's toolbar rendered oversized until we removed
#    a GDK_SCALE=2 override that seemed reasonable at 144 DPI but was
#    redundant on top of Xft.dpi already handling it).
track "$HOME/.Xresources"
if [ -f "$HOME/.Xresources" ]; then
  grep -v '^Xft\.dpi:' "$HOME/.Xresources" > "$HOME/.Xresources.tmp" || true
  mv "$HOME/.Xresources.tmp" "$HOME/.Xresources"
fi
echo "Xft.dpi: $DPI" >> "$HOME/.Xresources"
if command -v xrdb >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  xrdb -merge "$HOME/.Xresources" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 4. IceWM dotfiles
# ---------------------------------------------------------------------------
echo "-- Installing IceWM config --"
mkdir -p "$HOME/.icewm/themes"
for f in menu toolbar preferences startup theme winoptions; do
  track "$HOME/.icewm/$f"
  cp "$REPO_DIR/dotfiles/icewm/$f" "$HOME/.icewm/$f"
done
track "$HOME/.icewm/prefoverride"
cp "$REPO_DIR/dotfiles/icewm/prefoverride-$SCALE" "$HOME/.icewm/prefoverride"
track "$HOME/.icewm/themes/Chicago"
rm -rf "$HOME/.icewm/themes/Chicago"
cp -a "$REPO_DIR/dotfiles/icewm/themes-$SCALE/Chicago" "$HOME/.icewm/themes/Chicago"
# Default window theme (round red/amber/green buttons). Scaled copies for
# HiDPI are made at login by chicago-display-adapt.
track "$HOME/.icewm/themes/ChicagoModernXP"
rm -rf "$HOME/.icewm/themes/ChicagoModernXP"
cp -a "$REPO_DIR/dotfiles/icewm/themes-modern/ChicagoModernXP" "$HOME/.icewm/themes/ChicagoModernXP"

# VS Code: use the IceWM frame (traffic-light buttons, rounded corners).
# Merged into existing settings so the user's own keys are kept.
if [ -d "$HOME/.config/Code" ] || command -v code >/dev/null 2>&1; then
  vsc="$HOME/.config/Code/User/settings.json"
  mkdir -p "$(dirname "$vsc")"; track "$vsc"
  python3 - "$vsc" <<'PY'
import json, re, sys
p = sys.argv[1]
try:
    txt = open(p).read()
    txt = re.sub(r'^\s*//.*$', '', txt, flags=re.M)
    txt = re.sub(r',(\s*[}\]])', r'\1', txt)
    cfg = json.loads(txt) if txt.strip() else {}
except FileNotFoundError:
    cfg = {}
cfg.update({
    "window.titleBarStyle": "native",
    "window.customTitleBarVisibility": "auto",
    "window.menuStyle": "custom",
    "window.menuBarVisibility": "classic",
    "editor.fontFamily": "'JetBrains Mono', monospace",
    "terminal.integrated.fontFamily": "'JetBrains Mono'",
    "terminal.external.linuxExec": "ghostty",
    "workbench.colorTheme": "Default Dark Modern",
    "explorer.compactFolders": False,
    "accessibility.signalOptions.volume": 0,
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
})
open(p, "w").write(json.dumps(cfg, indent=4) + "\n")
PY
fi
chmod +x "$HOME/.icewm/startup"

# Fill in the real home directory (IceWM config files don't expand $HOME).
sed -i "s#__HOME__#$HOME#g" "$HOME/.icewm/menu" "$HOME/.icewm/toolbar"
track "$HOME/.icewm/dots6.png"
cp "$REPO_DIR/icons/chicago95-applications/48.png" "$HOME/.icewm/dots6.png"

# ---------------------------------------------------------------------------
# 5. GTK3 / GTK4 / mimeapps / dunst
# ---------------------------------------------------------------------------
echo "-- Installing GTK / app-default config --"
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" "$HOME/.config/dunst"
track "$HOME/.config/gtk-3.0/settings.ini"
cp "$REPO_DIR/dotfiles/config/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
track "$HOME/.config/gtk-4.0/settings.ini"
cp "$REPO_DIR/dotfiles/config/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
# Menus, popovers and tooltips styled to match the Start menu.
for v in gtk-3.0 gtk-4.0; do
  track "$HOME/.config/$v/gtk.css"
  cp "$REPO_DIR/dotfiles/config/$v/gtk.css" "$HOME/.config/$v/gtk.css"
done
track "$HOME/.local/bin/ghostty-modern"
cp "$REPO_DIR/dotfiles/local/bin/ghostty-modern" "$HOME/.local/bin/ghostty-modern"
chmod +x "$HOME/.local/bin/ghostty-modern"
track "$HOME/.config/mimeapps.list"
cp "$REPO_DIR/dotfiles/config/mimeapps.list" "$HOME/.config/mimeapps.list"
track "$HOME/.config/dunst/dunstrc"
cp "$REPO_DIR/dotfiles/config/dunst/dunstrc" "$HOME/.config/dunst/dunstrc"

# ---------------------------------------------------------------------------
# 6. Custom "Applications" grid icon (3x3 glyph), into the icon theme and
#    the user hicolor fallback (IceWM's own icon lookup is unreliable by
#    name, but every other consumer — GTK, the desktop icon — uses this).
# ---------------------------------------------------------------------------
echo "-- Installing the Applications icon --"
for sz in 16 22 24 32 48 256; do
  mkdir -p "$HOME/.icons/Chicago95-tux/apps/$sz" "$HOME/.local/share/icons/hicolor/${sz}x${sz}/apps"
  track "$HOME/.icons/Chicago95-tux/apps/$sz/chicago95-applications.png"
  cp "$REPO_DIR/icons/chicago95-applications/$sz.png" "$HOME/.icons/Chicago95-tux/apps/$sz/chicago95-applications.png"
  track "$HOME/.local/share/icons/hicolor/${sz}x${sz}/apps/chicago95-applications.png"
  cp "$REPO_DIR/icons/chicago95-applications/$sz.png" "$HOME/.local/share/icons/hicolor/${sz}x${sz}/apps/chicago95-applications.png"
done
# Firefox: the theme's "firefox" icon is a ship's wheel; its fox logo is
# "firefox_2". Firefox looks its window icon up by name (taskbar, Alt+Tab,
# title bar), so make "firefox" the fox in every size.
FF_ICONS="$HOME/.icons/Chicago95-tux/apps"
if [ -f "$FF_ICONS/scalable/firefox_2.svg" ]; then
  for sz in 16 22 24 32 48; do
    [ -f "$FF_ICONS/$sz/firefox.png" ] || continue
    track "$FF_ICONS/$sz/firefox.png"
    if [ -f "$FF_ICONS/$sz/firefox_2.png" ]; then
      cp "$FF_ICONS/$sz/firefox_2.png" "$FF_ICONS/$sz/firefox.png"
    else
      convert -background none -resize "${sz}x${sz}" "$FF_ICONS/scalable/firefox_2.svg" "$FF_ICONS/$sz/firefox.png"
    fi
  done
  track "$FF_ICONS/scalable/firefox.svg"
  cp "$FF_ICONS/scalable/firefox_2.svg" "$FF_ICONS/scalable/firefox.svg"
fi
gtk-update-icon-cache -f "$HOME/.icons/Chicago95-tux" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 7. The flat "Applications" grid folder (~/Applications), kept in sync
#    automatically on every login via .icewm/startup. build-app-grid only
#    ever touches symlinks it created itself, so it's safe even if you
#    already have a real ~/Applications directory — nothing there is backed
#    up or removed by uninstall.sh.
# ---------------------------------------------------------------------------
echo "-- Building the Applications grid (~/Applications) --"
mkdir -p "$HOME/.local/bin"
track "$HOME/.local/bin/build-app-grid"
cp "$REPO_DIR/dotfiles/local/bin/build-app-grid" "$HOME/.local/bin/build-app-grid"
chmod +x "$HOME/.local/bin/build-app-grid"
"$HOME/.local/bin/build-app-grid"

# ---------------------------------------------------------------------------
# 7b. Desktop-icon repaint watcher (works around issue #19: pcmanfm doesn't
#    repaint a desktop icon after you drag it to a new spot until some
#    unrelated screen event forces it to). Runs for the life of the
#    session; started from .icewm/startup.
# ---------------------------------------------------------------------------
echo "-- Installing the desktop-icon repaint watcher --"
track "$HOME/.local/bin/desktop-icon-repaint-watch"
cp "$REPO_DIR/dotfiles/local/bin/desktop-icon-repaint-watch" "$HOME/.local/bin/desktop-icon-repaint-watch"
chmod +x "$HOME/.local/bin/desktop-icon-repaint-watch"

# ---------------------------------------------------------------------------
# 7b2. Display adapter + compositor. chicago-display-adapt runs for the
#    whole session and re-sizes fonts, window chrome, icons and cursor on
#    every resolution change (e.g. resizing the VM window). picom adds
#    shadows/rounded corners with damage tracking so Xorg stays near idle.
# ---------------------------------------------------------------------------
echo "-- Installing the display adapter and compositor config --"
track "$HOME/.local/bin/chicago-display-adapt"
cp "$REPO_DIR/dotfiles/local/bin/chicago-display-adapt" "$HOME/.local/bin/chicago-display-adapt"
chmod +x "$HOME/.local/bin/chicago-display-adapt"
track "$HOME/.local/bin/chicago-app-grid"
cp "$REPO_DIR/dotfiles/local/bin/chicago-app-grid" "$HOME/.local/bin/chicago-app-grid"
chmod +x "$HOME/.local/bin/chicago-app-grid"
track "$HOME/.local/bin/chicago-start-menu"
cp "$REPO_DIR/dotfiles/local/bin/chicago-start-menu" "$HOME/.local/bin/chicago-start-menu"
chmod +x "$HOME/.local/bin/chicago-start-menu"
track "$HOME/.local/bin/chicago-desktop-layout"
cp "$REPO_DIR/dotfiles/local/bin/chicago-desktop-layout" "$HOME/.local/bin/chicago-desktop-layout"
chmod +x "$HOME/.local/bin/chicago-desktop-layout"
track "$HOME/.config/pcmanfm/icewm/desktop-items-0.conf"
"$HOME/.local/bin/chicago-desktop-layout"
mkdir -p "$HOME/.config/picom"
track "$HOME/.config/picom/picom.conf"
cp "$REPO_DIR/dotfiles/config/picom/picom.conf" "$HOME/.config/picom/picom.conf"

# Dock (tint2), Start menu (jgmenu), fonts, terminal look, Firefox defaults.
echo "-- Installing dock, Start menu, fonts and app look --"
for f in tint2/tint2rc.base jgmenu/jgmenurc.base jgmenu/start-pinned.csv jgmenu/start-footer.csv \
         fontconfig/fonts.conf ghostty/config chicago-os/display.conf; do
  mkdir -p "$HOME/.config/$(dirname "$f")"
  track "$HOME/.config/$f"
  cp "$REPO_DIR/dotfiles/config/$f" "$HOME/.config/$f"
done
mkdir -p "$HOME/.local/share/applications"
track "$HOME/.local/share/applications/chicago-app-grid.desktop"
cp "$REPO_DIR/dotfiles/local/share/applications/chicago-app-grid.desktop" "$HOME/.local/share/applications/"
fc-cache -f >/dev/null 2>&1 || true
# A fresh install has no Firefox profile until Firefox first runs; start
# it once headless so the profile (and user.js below) exists right away.
if command -v firefox >/dev/null 2>&1 \
   && ! ls -d "$HOME"/snap/firefox/common/.mozilla/firefox/*.default* "$HOME"/.mozilla/firefox/*.default* >/dev/null 2>&1; then
  echo "-- Creating the Firefox profile --"
  (cd /tmp && timeout 60 firefox --headless --screenshot about:blank >/dev/null 2>&1) || true
fi
# The theme's plain "firefox" icon is a ship's wheel; firefox_2 is its
# retro rendition of the real fox logo (dock, Start menu, app grid).
if [ -f /usr/share/applications/firefox.desktop ]; then
  track "$HOME/.local/share/applications/firefox.desktop"
  sed 's/^Icon=.*/Icon=firefox_2/' /usr/share/applications/firefox.desktop \
    > "$HOME/.local/share/applications/firefox.desktop"
fi
for prof in "$HOME"/snap/firefox/common/.mozilla/firefox/*.default* "$HOME"/.mozilla/firefox/*.default*; do
  [ -d "$prof" ] || continue
  track "$prof/user.js"
  cp "$REPO_DIR/dotfiles/firefox/user.js" "$prof/user.js"
done

# VS Code extensions.
if command -v code >/dev/null 2>&1; then
  while read -r ext; do
    [ -n "$ext" ] && code --install-extension "$ext" >/dev/null 2>&1 || true
  done < "$REPO_DIR/dotfiles/vscode/extensions.txt"
fi

# Claude Code (official native installer; lands in ~/.local/bin/claude).
if [ ! -x "$HOME/.local/bin/claude" ] && ! command -v claude >/dev/null 2>&1; then
  echo "-- Installing Claude Code --"
  curl -fsSL https://claude.ai/install.sh | bash || echo "   (Claude Code install failed; rerun: curl -fsSL https://claude.ai/install.sh | bash)"
fi

# ---------------------------------------------------------------------------
# 7c. Chicago95 Control Panel — the single "Settings" entry in the app grid
#    and Start menu (fixes #28: without this, gnome-control-center's own
#    org.gnome.Settings.desktop is the only "Settings" entry build-app-grid
#    finds, and it's broken under IceWM — its Display panel depends on
#    org.gnome.Mutter.DisplayConfig, a D-Bus service only Mutter/GNOME
#    Shell provides, so every control in it silently does nothing here).
#    This installs a yad-based picker fronting the individual panels
#    instead, with Display routed to arandr (talks to X11 RandR directly,
#    so it actually works) rather than gnome-control-center.
# ---------------------------------------------------------------------------
echo "-- Installing the Chicago95 Control Panel (Settings) --"
track "$HOME/.local/bin/chicago95-settings"
cp "$REPO_DIR/dotfiles/local/bin/chicago95-settings" "$HOME/.local/bin/chicago95-settings"
chmod +x "$HOME/.local/bin/chicago95-settings"
mkdir -p "$HOME/.local/share/applications"
track "$HOME/.local/share/applications/chicago95-settings.desktop"
cp "$REPO_DIR/dotfiles/local/share/applications/chicago95-settings.desktop" "$HOME/.local/share/applications/chicago95-settings.desktop"
"$HOME/.local/bin/build-app-grid"

# ---------------------------------------------------------------------------
# 7d. En/Tr keyboard-layout indicator and switcher, bottom-right of the
#    taskbar tray (fixes #25: xxkb only supported a plain toggle/cycle on
#    click, with no way to show a list of layouts with the current one
#    highlighted, which is what was actually asked for — no packaged tool
#    combines a themable Win95-style tray icon with a real picker menu, so
#    this is a small custom GTK3 status icon instead). Runs for the life
#    of the session; started from .icewm/startup.
# ---------------------------------------------------------------------------
echo "-- Installing the keyboard-layout picker --"
track "$HOME/.local/bin/keyboard-layout-picker"
cp "$REPO_DIR/dotfiles/local/bin/keyboard-layout-picker" "$HOME/.local/bin/keyboard-layout-picker"
chmod +x "$HOME/.local/bin/keyboard-layout-picker"

# ---------------------------------------------------------------------------
# 8. Desktop launcher icon
# ---------------------------------------------------------------------------
mkdir -p "$HOME/Desktop"
track "$HOME/Desktop/Applications.desktop"
cat > "$HOME/Desktop/Applications.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Applications
Comment=Browse all installed applications
Exec=pcmanfm "$HOME/Applications"
Icon=chicago95-applications
Terminal=false
StartupNotify=true
Categories=System;
EOF
chmod +x "$HOME/Desktop/Applications.desktop"
gio set "$HOME/Desktop/Applications.desktop" metadata::trusted true >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 9. Games — clacktype, a from-scratch typing-speed test, runs as a local
#    HTML file in Firefox, no server needed.
# ---------------------------------------------------------------------------
echo "-- Installing games --"
GAMES_DIR="$HOME/.local/share/chicago95-icewm-desktop/games/clacktype"
mkdir -p "$GAMES_DIR"
track "$GAMES_DIR"
cp -a "$REPO_DIR/games/clacktype/." "$GAMES_DIR/"
track "$HOME/Desktop/ClackType.desktop"
cat > "$HOME/Desktop/ClackType.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=ClackType
Comment=A from-scratch typing-speed test
Exec=firefox --new-window "file://$GAMES_DIR/index.html"
Icon=$GAMES_DIR/icon.png
Terminal=false
StartupNotify=true
Categories=Game;
EOF
chmod +x "$HOME/Desktop/ClackType.desktop"
gio set "$HOME/Desktop/ClackType.desktop" metadata::trusted true >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 9b. Sound theme — a full XDG sound theme (not just the login chime),
#    vendored from upstream Chicago95 since its own installer doesn't wire
#    this up. User-level install, no sudo needed.
# ---------------------------------------------------------------------------
echo "-- Installing the Chicago95 sound theme --"
SOUNDS_DIR="$HOME/.local/share/sounds/Chicago95"
mkdir -p "$SOUNDS_DIR"
track "$SOUNDS_DIR"
cp -a "$REPO_DIR/system/sounds/Chicago95/." "$SOUNDS_DIR/"

# ---------------------------------------------------------------------------
# 9c. Wire the sound theme up to something that actually plays it. IceWM
#    has no session component that reads the XDG sound theme (that's a
#    GNOME/gnome-settings-daemon thing) — the GSettings key set below just
#    tells GTK4/portal apps which theme *would* apply, it doesn't make
#    anything audible on its own. IceWM's own sound daemon is `icesound`:
#    it watches IceWM's GUI-event root-window property and plays
#    event-named .wav files from ~/.icewm/sounds/. It only starts if
#    icewm-session is launched with --sound (see the xsessions entry).
# ---------------------------------------------------------------------------
if command -v icesound >/dev/null 2>&1; then
  echo "-- Wiring IceWM GUI events to Chicago95 sounds (icesound) --"
  ICEWM_SOUNDS_DIR="$HOME/.icewm/sounds"
  mkdir -p "$ICEWM_SOUNDS_DIR"
  track "$ICEWM_SOUNDS_DIR"
  map_sound() {
    track "$ICEWM_SOUNDS_DIR/$1"
    cp -a "$SOUNDS_DIR/stereo/$2" "$ICEWM_SOUNDS_DIR/$1"
  }
  map_sound startup.wav     desktop-login.wav
  map_sound shutdown.wav    desktop-logout.wav
  # No restart.wav: IceWM restarts on every display change (full screen,
  # resizing), so a restart sound would play constantly.
  map_sound dialogOpen.wav  dialog-information.wav
  map_sound dialogClose.wav window-inactive-click.wav
fi

# ---------------------------------------------------------------------------
# 10. GSettings (affects GTK4/portal-aware apps and anything reading the
#    freedesktop interface schema, independent of IceWM's own config files)
# ---------------------------------------------------------------------------
if command -v gsettings >/dev/null 2>&1; then
  echo "-- Syncing GSettings to Chicago95 --"
  for key in gtk-theme icon-theme color-scheme font-name document-font-name; do
    track_gsetting org.gnome.desktop.interface "$key"
  done
  gsettings set org.gnome.desktop.interface gtk-theme 'Chicago95' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme 'Chicago95-tux' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme 'default' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface font-name 'Adwaita Sans 15' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface document-font-name 'Adwaita Sans 15' 2>/dev/null || true
  track_gsetting org.gnome.desktop.sound theme-name
  gsettings set org.gnome.desktop.sound theme-name 'Chicago95' 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 10b. xfconf "xsettings" channel. IceWM has no XSETTINGS provider of its
#    own, so .icewm/startup now runs xfsettingsd for that (see the startup
#    dotfile). xfsettingsd broadcasts whatever is in this channel to every
#    GTK app — and it broadcasts that on top of the GSettings values above,
#    not instead of them. Left unconfigured, it broadcasts stale/upstream
#    defaults (we saw Greybird/elementary-xfce-dark/Sans 10/96dpi on a test
#    machine) and silently overwrites the Chicago95 GSettings on the very
#    next login. This is the root cause of "the icons/taskbar/fonts are
#    huge again after I log back in": nothing was wrong with the install,
#    xfsettingsd just had never been given Chicago95 values to broadcast.
# ---------------------------------------------------------------------------
if command -v xfconf-query >/dev/null 2>&1; then
  echo "-- Syncing the xfsettingsd XSETTINGS channel to Chicago95 --"
  set_xfconf() {
    local prop="$1" type="$2" value="$3"
    track_xfconf xsettings "$prop"
    xfconf-query -c xsettings -p "$prop" -s "$value" 2>/dev/null \
      || xfconf-query -c xsettings -p "$prop" -n -t "$type" -s "$value" 2>/dev/null || true
  }
  set_xfconf /Net/ThemeName     string Chicago95
  set_xfconf /Net/IconThemeName string Chicago95-tux
  set_xfconf /Gtk/FontName      string "Adwaita Sans 15"
  set_xfconf /Xft/DPI           int    "$DPI"
fi

# ---------------------------------------------------------------------------
# 10c. Pin ibus to the system's actual keyboard layout. This has nothing to
#    do with Chicago95 itself, but it's the other half of the "settings
#    don't survive a fresh login" complaint: a per-user dconf value at
#    /desktop/ibus/general/preload-engines (left over from an earlier
#    locale/keyboard choice — not shipped by ibus, whose own upstream
#    default is empty) silently overrides /etc/default/keyboard's XKBLAYOUT
#    every time ibus restarts at login, e.g. always coming back up in
#    Turkish on a machine configured for "us". Pinning it here to whatever
#    XKBLAYOUT is actually configured makes it deterministic.
#
#    use-system-keyboard-layout also has to be turned on here, or ibus
#    fights keyboard-layout-picker (the taskbar's En/Tr switcher): with it
#    off (ibus's own default), ibus reapplies its single pinned engine's
#    layout to the X server via its own XKB engine every time it
#    (re)starts, silently reverting a manual switch to Turkish back to
#    English moments later. With it on, ibus leaves whatever setxkbmap
#    already configured alone. Verified by restarting ibus-daemon with
#    each setting and checking `setxkbmap -query` after.
# ---------------------------------------------------------------------------
if command -v dconf >/dev/null 2>&1 && [ -f /etc/default/keyboard ]; then
  echo "-- Pinning ibus to the system keyboard layout --"
  SYS_LAYOUT="$(sed -n 's/^XKBLAYOUT="\(.*\)"/\1/p' /etc/default/keyboard | head -1)"
  [ -z "$SYS_LAYOUT" ] && SYS_LAYOUT=us
  case "$SYS_LAYOUT" in
    us) IBUS_ENGINE=xkb:us::eng ;;
    tr) IBUS_ENGINE=xkb:tr::tur ;;
    *)  IBUS_ENGINE="xkb:${SYS_LAYOUT}::" ;;
  esac
  track_dconf /desktop/ibus/general/preload-engines
  track_dconf /desktop/ibus/general/engines-order
  track_dconf /desktop/ibus/general/use-system-keyboard-layout
  dconf write /desktop/ibus/general/preload-engines "['$IBUS_ENGINE']"
  dconf write /desktop/ibus/general/engines-order "['$IBUS_ENGINE']"
  dconf write /desktop/ibus/general/use-system-keyboard-layout true

  # ibus's own panel also puts an "EN" indicator in the tray — a plain
  # text label with no click-to-switch behavior (verified: left-clicking
  # it doesn't change the active engine). Redundant now that
  # keyboard-layout-picker is the actual clickable switcher; without
  # this, both would show side by side in the tray.
  track_dconf /desktop/ibus/panel/show-icon-on-systray
  dconf write /desktop/ibus/panel/show-icon-on-systray false
fi

# ---------------------------------------------------------------------------
# 11. LightDM greeter (only if LightDM is already the display manager)
# ---------------------------------------------------------------------------
if [ -d /etc/lightdm ]; then
  echo "-- Configuring LightDM greeter (sudo required) --"
  sudo mkdir -p /etc/lightdm/lightdm-gtk-greeter.conf.d
  track /etc/lightdm/lightdm-gtk-greeter.conf.d/50-chicago95-dpi.conf
  sudo tee /etc/lightdm/lightdm-gtk-greeter.conf.d/50-chicago95-dpi.conf >/dev/null <<EOF
[greeter]
theme-name=Chicago95
icon-theme-name=Chicago95-tux
xft-antialias=false
xft-dpi=$DPI
xft-hintstyle=hintfull
xft-rgba=none
EOF
  track /usr/share/xsessions/icewm-chicago95.desktop
  sudo cp "$REPO_DIR/system/icewm-chicago95.desktop" /usr/share/xsessions/icewm-chicago95.desktop
fi

# ---------------------------------------------------------------------------
# 11b. Plymouth boot theme (only if Plymouth is installed). This needs a
#    reboot to actually see — installing it now only stages it for the
#    next boot, it does not reboot you.
# ---------------------------------------------------------------------------
if command -v plymouth >/dev/null 2>&1 && [ -d /usr/share/plymouth/themes ]; then
  echo "-- Installing the Plymouth boot theme (sudo required) --"
  track /usr/share/plymouth/themes/Chicago95
  sudo rm -rf /usr/share/plymouth/themes/Chicago95
  sudo cp -a "$REPO_DIR/system/plymouth/Chicago95" /usr/share/plymouth/themes/Chicago95
  track /etc/alternatives/default.plymouth
  sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth \
    /usr/share/plymouth/themes/Chicago95/Chicago95.plymouth 100 >/dev/null
  sudo update-alternatives --set default.plymouth \
    /usr/share/plymouth/themes/Chicago95/Chicago95.plymouth >/dev/null
  echo "-- Rebuilding initramfs (this can take a little while) --"
  sudo update-initramfs -u
  PLYMOUTH_INSTALLED=1
fi

# ---------------------------------------------------------------------------
# 11c. Firefox's own bundled taskbar/window icon (sudo required)
#
#    Firefox doesn't look up its window icon through the icon theme — it
#    ships its own bundled PNGs and sets them directly via _NET_WM_ICON,
#    and keeps re-asserting them for a while after each window maps
#    (confirmed: dozens of property updates within the first second), which
#    stomps a plain winoptions icon override almost immediately. The only
#    way to actually change what shows up in the taskbar/quickswitch/alt-tab
#    is to replace Firefox's own icon files. This is undone by the next
#    Firefox package upgrade — re-run install.sh to reapply.
# ---------------------------------------------------------------------------
FIREFOX_ICON_DIR="/usr/lib/firefox/browser/chrome/icons/default"
CHICAGO95_FIREFOX_SVG="$HOME/.icons/Chicago95-tux/apps/scalable/firefox_2.svg"
if [ -d "$FIREFOX_ICON_DIR" ] && [ -f "$CHICAGO95_FIREFOX_SVG" ] && command -v convert >/dev/null 2>&1; then
  echo "-- Replacing Firefox's bundled icon with the classic Chicago95 one (sudo required) --"
  for size in 16 32 48 64 128; do
    target="$FIREFOX_ICON_DIR/default${size}.png"
    [ -f "$target" ] || continue
    track "$target"
    convert -background none -resize "${size}x${size}" "$CHICAGO95_FIREFOX_SVG" "$STATE_DIR/firefox-icon-$size.png"
    sudo cp "$STATE_DIR/firefox-icon-$size.png" "$target"
    rm -f "$STATE_DIR/firefox-icon-$size.png"
  done
  echo "   (a Firefox package upgrade may restore the stock icon later — re-run install.sh to reapply)"
  echo "   (quit Firefox completely — not just close the window — for this to take effect)"
fi

# ---------------------------------------------------------------------------
# 12. Hot-reload if IceWM is already running in this session
# ---------------------------------------------------------------------------
if pgrep -x icewm >/dev/null 2>&1; then
  killall -SIGHUP icewm || true
  pkill -f 'pcmanfm --desktop' 2>/dev/null || true
  ( setsid nohup pcmanfm --desktop --profile=icewm >/dev/null 2>&1 < /dev/null & ) 2>/dev/null || true
  echo "-- IceWM reloaded live --"
fi

# ---------------------------------------------------------------------------
# 13. Remove what Chicago OS doesn't use (GNOME session, unused apps,
#    telemetry, printing...). Last, so everything above is in place and
#    protected first. See system/slim-down.sh for the exact lists.
# ---------------------------------------------------------------------------
if [ -z "${CHICAGO_SKIP_SLIM:-}" ]; then
  "$REPO_DIR/system/slim-down.sh"
fi

echo
echo "Done. Reboot: LightDM starts straight into the IceWM Chicago95 session."
echo
echo "Still manual (accounts and host settings can't be scripted):"
echo "  gh auth login            GitHub CLI"
echo "  claude                   sign in to Claude Code"
echo "  VMware Fusion: Settings > Display > 'Use full resolution for Retina display'"
echo "                 (without it the guest is 1280x800 and the 2x scale won't fit)"
echo "  VMware Fusion: Settings > Display > 'Accelerate 3D Graphics' (else the browser"
echo "                 and desktop are drawn by the CPU and scrolling stutters); 4 CPUs, 8 GB RAM"
if [ "${PLYMOUTH_INSTALLED:-0}" = "1" ]; then
  echo "The Plymouth boot theme is staged — reboot to see it."
fi
echo
echo "Everything this script overwrote is backed up at:"
echo "  $BACKUP_ROOT"
echo "Run ./uninstall.sh to revert this run."
