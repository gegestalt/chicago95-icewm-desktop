#!/usr/bin/env bash
# system/firefox-deb.sh — replaces the Firefox snap with Mozilla's own .deb
# and carries the profile over (bookmarks, logins, history, extensions,
# open tabs). Run by system-setup.sh; does nothing if Firefox already
# isn't a snap.
#
# Why: the snap needs ~1.2 GB of snap runtimes plus the snapd daemon, and
# its sandbox can't see ~/.themes, so Firefox never matched Chicago95.
# With Firefox off snap, system/slim-down.sh removes snapd entirely.
set -euo pipefail

if ! snap list firefox >/dev/null 2>&1; then
  exit 0
fi

SNAP_ROOT="$HOME/snap/firefox/common/.mozilla/firefox"
DEB_ROOT="$HOME/.mozilla/firefox"

# The profile must not be in use while it is copied.
if pgrep -u "$USER" -x firefox >/dev/null; then
  echo "   Close Firefox to continue (your tabs are restored afterwards)..."
  while pgrep -u "$USER" -x firefox >/dev/null; do sleep 2; done
fi

profile=""
if [ -f "$SNAP_ROOT/profiles.ini" ]; then
  # The profile the snap actually used: its [Install...] entry, else Default=1.
  profile=$(awk -F= '/^\[Install/{i=1} i && /^Default=/{print $2; exit}' "$SNAP_ROOT/profiles.ini")
  [ -n "$profile" ] || profile=$(awk -F= '/^Path=/{p=$2} /^Default=1/{print p; exit}' "$SNAP_ROOT/profiles.ini")
  [ -n "$profile" ] || profile=$(awk -F= '/^Path=/{print $2; exit}' "$SNAP_ROOT/profiles.ini")
fi

if [ -n "$profile" ] && [ -d "$SNAP_ROOT/$profile" ] && [ ! -d "$DEB_ROOT/$profile" ]; then
  echo "-- Moving the Firefox profile ($profile) out of the snap --"
  mkdir -p "$DEB_ROOT"
  cp -a "$SNAP_ROOT/$profile" "$DEB_ROOT/$profile"
  rm -f "$DEB_ROOT/$profile/lock" "$DEB_ROOT/$profile/.parentlock"
  # Firefox only adopts an existing profile when profiles.ini/installs.ini
  # assign it to this installation; otherwise it creates an empty
  # "default-release" one. The key is a hash of the install directory,
  # fixed for Mozilla's .deb (/usr/lib/firefox).
  hash=4F96D1932A9F858E
  printf '[%s]\nDefault=%s\nLocked=1\n\n' "$hash" "$profile" > "$DEB_ROOT/installs.ini"
  cat > "$DEB_ROOT/profiles.ini" <<EOF
[Install$hash]
Default=$profile
Locked=1

[Profile0]
Name=default
IsRelative=1
Path=$profile
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF
fi

echo "-- Mozilla's Firefox apt repository --"
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
  | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
  | sudo tee /etc/apt/sources.list.d/mozilla.list >/dev/null
# Prefer Mozilla's firefox over Ubuntu's snap-installing stub.
printf 'Package: firefox*\nPin: origin packages.mozilla.org\nPin-Priority: 1001\n' \
  | sudo tee /etc/apt/preferences.d/mozilla >/dev/null

echo "-- Swapping the Firefox snap for the .deb --"
sudo snap remove --purge firefox
sudo apt-get update -qq
# Ubuntu's transitional "firefox" package only reinstalls the snap.
sudo apt-get purge -y firefox >/dev/null 2>&1 || true
sudo apt-get install -y firefox
# The copied profile is now the live one; drop the snap's leftovers.
if [ -n "$profile" ] && [ -d "$DEB_ROOT/$profile" ]; then rm -rf "$HOME/snap/firefox"; fi
firefox --version
