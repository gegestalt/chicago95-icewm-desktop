#!/usr/bin/env bash
# Chicago95 IceWM Desktop — installer
#
# Applies the full IceWM + Chicago95 desktop setup on top of an existing
# Ubuntu install: a Start menu with every installed app, a taskbar
# "Applications" button that opens a flat one-page app grid (like Ubuntu's
# app grid or macOS Launchpad), HiDPI-correct window chrome, theme-consistent
# default apps, and a synced GTK3/GTK4/icon-theme setup.
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
# 2. Packages
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
  DETECTED=$(xdpyinfo 2>/dev/null | awk -F'[x ]+' '/resolution:/{print $2}')
  [ -n "${DETECTED:-}" ] && DPI="$DETECTED"
fi
if [ "$DPI" -ge 120 ]; then
  SCALE=2x
else
  SCALE=1x
fi
echo "-- Detected ${DPI} DPI -> using $SCALE theme assets --"

# ---------------------------------------------------------------------------
# 4. IceWM dotfiles
# ---------------------------------------------------------------------------
echo "-- Installing IceWM config --"
mkdir -p "$HOME/.icewm/themes"
cp "$REPO_DIR/dotfiles/icewm/menu" \
   "$REPO_DIR/dotfiles/icewm/toolbar" \
   "$REPO_DIR/dotfiles/icewm/preferences" \
   "$REPO_DIR/dotfiles/icewm/startup" \
   "$REPO_DIR/dotfiles/icewm/theme" \
   "$HOME/.icewm/"
cp "$REPO_DIR/dotfiles/icewm/prefoverride-$SCALE" "$HOME/.icewm/prefoverride"
rm -rf "$HOME/.icewm/themes/Chicago"
cp -a "$REPO_DIR/dotfiles/icewm/themes-$SCALE/Chicago" "$HOME/.icewm/themes/Chicago"
chmod +x "$HOME/.icewm/startup"

# Fill in the real home directory (IceWM config files don't expand $HOME).
sed -i "s#__HOME__#$HOME#g" "$HOME/.icewm/menu" "$HOME/.icewm/toolbar"
cp "$REPO_DIR/icons/chicago95-applications/48.png" "$HOME/.icewm/dots6.png"

# ---------------------------------------------------------------------------
# 5. GTK3 / GTK4 / mimeapps / dunst
# ---------------------------------------------------------------------------
echo "-- Installing GTK / app-default config --"
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" "$HOME/.config/dunst"
cp "$REPO_DIR/dotfiles/config/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
cp "$REPO_DIR/dotfiles/config/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
cp "$REPO_DIR/dotfiles/config/mimeapps.list" "$HOME/.config/mimeapps.list"
cp "$REPO_DIR/dotfiles/config/dunst/dunstrc" "$HOME/.config/dunst/dunstrc"

# ---------------------------------------------------------------------------
# 6. Custom "Applications" grid icon (6-dot glyph), into the icon theme
#    and the user hicolor fallback (IceWM's own icon lookup is unreliable
#    by name, but every other consumer — GTK, the desktop icon — uses this).
# ---------------------------------------------------------------------------
echo "-- Installing the Applications icon --"
for sz in 16 22 24 32 48 256; do
  mkdir -p "$HOME/.icons/Chicago95-tux/apps/$sz" "$HOME/.local/share/icons/hicolor/${sz}x${sz}/apps"
  cp "$REPO_DIR/icons/chicago95-applications/$sz.png" "$HOME/.icons/Chicago95-tux/apps/$sz/chicago95-applications.png"
  cp "$REPO_DIR/icons/chicago95-applications/$sz.png" "$HOME/.local/share/icons/hicolor/${sz}x${sz}/apps/chicago95-applications.png"
done
gtk-update-icon-cache -f "$HOME/.icons/Chicago95-tux" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 7. The flat "Applications" grid folder (~/Applications), kept in sync
#    automatically on every login via .icewm/startup.
# ---------------------------------------------------------------------------
echo "-- Building the Applications grid (~/Applications) --"
mkdir -p "$HOME/.local/bin"
cp "$REPO_DIR/dotfiles/local/bin/build-app-grid" "$HOME/.local/bin/build-app-grid"
chmod +x "$HOME/.local/bin/build-app-grid"
"$HOME/.local/bin/build-app-grid"

# ---------------------------------------------------------------------------
# 8. Desktop launcher icons
# ---------------------------------------------------------------------------
mkdir -p "$HOME/Desktop"
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
# 9. GSettings (affects GTK4/portal-aware apps and anything reading the
#    freedesktop interface schema, independent of IceWM's own config files)
# ---------------------------------------------------------------------------
if command -v gsettings >/dev/null 2>&1; then
  echo "-- Syncing GSettings to Chicago95 --"
  gsettings set org.gnome.desktop.interface gtk-theme 'Chicago95' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme 'Chicago95-tux' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme 'default' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface font-name 'Adwaita Sans 15' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface document-font-name 'Adwaita Sans 15' 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 10. LightDM greeter (only if LightDM is already the display manager)
# ---------------------------------------------------------------------------
if [ -d /etc/lightdm ]; then
  echo "-- Configuring LightDM greeter (sudo required) --"
  sudo mkdir -p /etc/lightdm/lightdm-gtk-greeter.conf.d
  sudo tee /etc/lightdm/lightdm-gtk-greeter.conf.d/50-chicago95-dpi.conf >/dev/null <<EOF
[greeter]
theme-name=Chicago95
icon-theme-name=Chicago95-tux
xft-antialias=false
xft-dpi=$DPI
xft-hintstyle=hintfull
xft-rgba=none
EOF
  sudo cp "$REPO_DIR/system/icewm-chicago95.desktop" /usr/share/xsessions/icewm-chicago95.desktop
fi

# ---------------------------------------------------------------------------
# 11. Hot-reload if IceWM is already running in this session
# ---------------------------------------------------------------------------
if pgrep -x icewm >/dev/null 2>&1; then
  killall -SIGHUP icewm || true
  pkill -f 'pcmanfm --desktop' 2>/dev/null || true
  ( setsid nohup pcmanfm --desktop --profile=icewm >/dev/null 2>&1 < /dev/null & ) 2>/dev/null || true
  echo "-- IceWM reloaded live --"
fi

echo
echo "Done. Log out and pick the 'IceWM Chicago95' session for a clean start."
echo
echo "Optional next step: run optional/migrate-firefox-to-deb.sh to replace a"
echo "snap-installed Firefox with the real .deb — snap sandboxing means Firefox"
echo "otherwise cannot see this theme at all."
