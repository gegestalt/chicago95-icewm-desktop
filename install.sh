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
# Usage:
#   git clone <this repo> ~/chicago95-icewm-desktop
#   cd ~/chicago95-icewm-desktop
#   ./install.sh
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
if [ ! -d "$HOME/.themes/Chicago95" ] || [ ! -d "$HOME/.icons/Chicago95-tux" ]; then
  cat >&2 <<'EOF'
The base Chicago95 GTK/icon theme isn't installed yet. This repo builds on
top of it rather than vendoring a copy. Install it first:

  git clone https://github.com/grassmunk/Chicago95.git ~/Chicago95
  cd ~/Chicago95
  python3 installer.py

Then re-run this script.
EOF
  exit 1
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
  imagemagick

# ---------------------------------------------------------------------------
# 3. Detect display DPI and pick the matching theme-asset scale
# ---------------------------------------------------------------------------
DPI=96
if command -v xdpyinfo >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  DETECTED=$(xdpyinfo 2>/dev/null | sed -n 's/^ *resolution: *\([0-9]*\)x.*/\1/p' | head -1)
  [ -n "${DETECTED:-}" ] && DPI="$DETECTED"
fi
if [ "$DPI" -ge 120 ]; then
  SCALE=2x
else
  SCALE=1x
fi
echo "-- Detected ${DPI} DPI -> using $SCALE theme assets --"

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
for f in menu toolbar preferences startup theme; do
  track "$HOME/.icewm/$f"
  cp "$REPO_DIR/dotfiles/icewm/$f" "$HOME/.icewm/$f"
done
track "$HOME/.icewm/prefoverride"
cp "$REPO_DIR/dotfiles/icewm/prefoverride-$SCALE" "$HOME/.icewm/prefoverride"
track "$HOME/.icewm/themes/Chicago"
rm -rf "$HOME/.icewm/themes/Chicago"
cp -a "$REPO_DIR/dotfiles/icewm/themes-$SCALE/Chicago" "$HOME/.icewm/themes/Chicago"
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
  map_sound restart.wav     desktop-logout.wav
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
  dconf write /desktop/ibus/general/preload-engines "['$IBUS_ENGINE']"
  dconf write /desktop/ibus/general/engines-order "['$IBUS_ENGINE']"
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
# 12. Hot-reload if IceWM is already running in this session
# ---------------------------------------------------------------------------
if pgrep -x icewm >/dev/null 2>&1; then
  killall -SIGHUP icewm || true
  pkill -f 'pcmanfm --desktop' 2>/dev/null || true
  ( setsid nohup pcmanfm --desktop --profile=icewm >/dev/null 2>&1 < /dev/null & ) 2>/dev/null || true
  echo "-- IceWM reloaded live --"
fi

echo
echo "Done. Log out and pick the 'IceWM Chicago95' session for a clean start."
if [ "${PLYMOUTH_INSTALLED:-0}" = "1" ]; then
  echo "The Plymouth boot theme is staged — reboot to see it."
fi
echo
echo "Everything this script overwrote is backed up at:"
echo "  $BACKUP_ROOT"
echo "Run ./uninstall.sh to revert this run."
echo
echo "Optional next step: run optional/migrate-firefox-to-deb.sh to replace a"
echo "snap-installed Firefox with the real .deb — snap sandboxing means Firefox"
echo "otherwise cannot see this theme at all."
