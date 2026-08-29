#!/usr/bin/env bash
# Replaces a snap-installed Firefox with Mozilla's official .deb and migrates
# the existing profile across. This is separate from install.sh and NOT run
# automatically, because it removes a package and touches your browser
# profile — read it before running it.
#
# Why: snap Firefox is sandboxed to only the themes/icons bundled in the
# gtk-common-themes snap. It cannot see ~/.themes or ~/.icons at all, so it
# will never match Chicago95 (or any custom theme) no matter what you set.
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not root — it will sudo when it needs to." >&2
  exit 1
fi

if ! snap list firefox >/dev/null 2>&1; then
  echo "Firefox isn't installed as a snap — nothing to migrate." >&2
  exit 0
fi

echo "This will:"
echo "  1. Back up your current Firefox profile"
echo "  2. Remove the Firefox snap"
echo "  3. Add Mozilla's official APT repo and install the real .deb"
echo "  4. Restore your profile (bookmarks, logins, extensions) into it"
read -r -p "Continue? [y/N] " REPLY
case "$REPLY" in
  [yY]*) ;;
  *) echo "Aborted."; exit 1 ;;
esac

SNAP_PROFILE_ROOT="$HOME/snap/firefox/common/.mozilla/firefox"
if [ ! -d "$SNAP_PROFILE_ROOT" ]; then
  echo "Couldn't find the snap's profile directory at $SNAP_PROFILE_ROOT" >&2
  exit 1
fi
PROFILE_NAME=$(awk -F= '/^Path=/{print $2; exit}' "$SNAP_PROFILE_ROOT/profiles.ini")
if [ -z "$PROFILE_NAME" ]; then
  echo "Couldn't determine the default profile from profiles.ini" >&2
  exit 1
fi

BACKUP_DIR="$HOME/firefox-profile-backup-$(date -u +%Y%m%d-%H%M%S)"
echo "-- Backing up profile to $BACKUP_DIR --"
cp -a "$SNAP_PROFILE_ROOT" "$BACKUP_DIR"

echo "-- Removing the Firefox snap --"
sudo snap remove firefox

echo "-- Adding Mozilla's official APT repo --"
sudo install -d -m 0755 /etc/apt/keyrings
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O /tmp/mozilla-key.asc
sudo cp /tmp/mozilla-key.asc /etc/apt/keyrings/packages.mozilla.org.asc
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
  | sudo tee /etc/apt/sources.list.d/mozilla.list >/dev/null
printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
  | sudo tee /etc/apt/preferences.d/mozilla >/dev/null

echo "-- Installing the real Firefox .deb --"
sudo apt-get update -qq
# Ubuntu ships a transitional "firefox" stub that just reinstalls the snap;
# its epoch (1:...) makes apt think the real package is a downgrade unless
# the stub is purged first.
sudo apt-get purge -y firefox || true
sudo apt-get install -y firefox

echo "-- Restoring your profile --"
mkdir -p "$HOME/.mozilla/firefox"
cp -a "$BACKUP_DIR/$PROFILE_NAME" "$HOME/.mozilla/firefox/$PROFILE_NAME"
cat > "$HOME/.mozilla/firefox/profiles.ini" <<EOF
[Profile0]
Name=default
IsRelative=1
Path=$PROFILE_NAME
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF
# Native-widget rendering, so scrollbars/dialogs pick up the GTK theme
# instead of Firefox's own flat renderer.
echo 'user_pref("widget.non-native-theme.enabled", false);' >> "$HOME/.mozilla/firefox/$PROFILE_NAME/user.js"

DPI=96
if command -v xdpyinfo >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  DETECTED=$(xdpyinfo 2>/dev/null | awk -F'[x ]+' '/resolution:/{print $2}')
  [ -n "${DETECTED:-}" ] && DPI="$DETECTED"
fi

mkdir -p "$HOME/.local/share/applications"
if [ "$DPI" -ge 120 ]; then
  echo "-- Detected ${DPI} DPI -- installing a HiDPI-aware launcher override --"
  sed 's/^Exec=firefox /Exec=env GDK_SCALE=2 GDK_DPI_SCALE=1 firefox /; s#^Exec=/usr/bin/firefox #Exec=env GDK_SCALE=2 GDK_DPI_SCALE=1 /usr/bin/firefox #' \
    /usr/share/applications/firefox.desktop > "$HOME/.local/share/applications/firefox.desktop"
else
  cp /usr/share/applications/firefox.desktop "$HOME/.local/share/applications/firefox.desktop"
fi
cp "$HOME/.local/share/applications/firefox.desktop" "$HOME/Desktop/Firefox.desktop" 2>/dev/null || true
chmod +x "$HOME/Desktop/Firefox.desktop" 2>/dev/null || true
gio set "$HOME/Desktop/Firefox.desktop" metadata::trusted true >/dev/null 2>&1 || true

echo
echo "Done. Your old profile is safely kept at: $BACKUP_DIR"
firefox --version
