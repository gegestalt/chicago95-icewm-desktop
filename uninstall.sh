#!/usr/bin/env bash
# Reverts a previous run of install.sh, using the backup manifest it wrote.
#
# Usage:
#   ./uninstall.sh            # reverts the most recent install.sh run
#   ./uninstall.sh <run-id>   # reverts a specific run (see
#                              # ~/.chicago95-icewm-desktop/backups/)
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not root — it will sudo when it needs to." >&2
  exit 1
fi

STATE_DIR="$HOME/.chicago95-icewm-desktop"

TS="${1:-}"
if [ -z "$TS" ]; then
  if [ ! -f "$STATE_DIR/last-backup" ]; then
    echo "No install.sh run recorded at $STATE_DIR — nothing to revert." >&2
    exit 1
  fi
  TS="$(cat "$STATE_DIR/last-backup")"
fi

BACKUP_ROOT="$STATE_DIR/backups/$TS"
MANIFEST="$BACKUP_ROOT/manifest.txt"
GSETTINGS_RESTORE="$BACKUP_ROOT/gsettings-restore.sh"
XFCONF_RESTORE="$BACKUP_ROOT/xfconf-restore.sh"
DCONF_RESTORE="$BACKUP_ROOT/dconf-restore.sh"

if [ ! -f "$MANIFEST" ]; then
  echo "No manifest found for run '$TS' at $MANIFEST" >&2
  exit 1
fi

echo "== Reverting install.sh run $TS =="
echo

is_system_path() {
  case "$1" in
    /etc/*|/usr/*) return 0 ;;
    *) return 1 ;;
  esac
}

while IFS= read -r line; do
  action="${line%% *}"
  path="${line#* }"
  rel="${path#/}"
  backup_src="$BACKUP_ROOT/existed/$rel"

  case "$action" in
    EXISTED)
      echo "restoring: $path"
      if is_system_path "$path"; then
        sudo rm -rf "$path"
        sudo cp -a "$backup_src" "$path"
      else
        rm -rf "$path"
        cp -a "$backup_src" "$path"
      fi
      ;;
    NEW)
      echo "removing:  $path"
      if is_system_path "$path"; then
        sudo rm -rf "$path"
      else
        rm -rf "$path"
      fi
      ;;
    *)
      echo "skipping unrecognized manifest line: $line" >&2
      ;;
  esac
done < "$MANIFEST"

if [ -s "$GSETTINGS_RESTORE" ] && command -v gsettings >/dev/null 2>&1; then
  echo "-- Restoring previous GSettings values --"
  sh "$GSETTINGS_RESTORE"
fi

if [ -s "$XFCONF_RESTORE" ] && command -v xfconf-query >/dev/null 2>&1; then
  echo "-- Restoring previous xfconf (xsettings) values --"
  sh "$XFCONF_RESTORE"
fi

if [ -s "$DCONF_RESTORE" ] && command -v dconf >/dev/null 2>&1; then
  echo "-- Restoring previous dconf (ibus) values --"
  sh "$DCONF_RESTORE"
fi

if pgrep -x icewm >/dev/null 2>&1; then
  killall -SIGHUP icewm || true
  pkill -f 'pcmanfm --desktop' 2>/dev/null || true
  ( setsid nohup pcmanfm --desktop --profile=icewm >/dev/null 2>&1 < /dev/null & ) 2>/dev/null || true
  echo "-- IceWM reloaded live --"
fi

echo
echo "Done. Note: ~/Applications (the app grid) and any packages install.sh"
echo "installed via apt are left in place — see the README if you want those"
echo "gone too. This run's backup is kept at $BACKUP_ROOT in case you want to"
echo "reapply anything from it by hand."
