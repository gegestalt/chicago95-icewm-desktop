#!/bin/sh
# Run this ON THE MAC (not in the VM), once:
#   curl -fsSL https://raw.githubusercontent.com/gegestalt/chicago95-icewm-desktop/master/host/macos/install-battery-feed.sh | sh
#
# Installs a launchd job that, every minute, writes the Mac's battery
# ("percent state unix-time") into every running VMware Fusion VM's
# guestinfo, where Chicago OS's dock reads it (chicago-battery). Needed
# because Fusion doesn't give ARM Linux guests a virtual battery.
# Remove with: launchctl bootout gui/$(id -u)/com.chicago-os.battery-feed
#   && rm ~/Library/LaunchAgents/com.chicago-os.battery-feed.plist
set -eu
dir="$HOME/Library/Application Support/chicago-os"
feed="$dir/battery-feed.sh"
plist="$HOME/Library/LaunchAgents/com.chicago-os.battery-feed.plist"
label=com.chicago-os.battery-feed
mkdir -p "$dir" "$HOME/Library/LaunchAgents"

cat > "$feed" <<'FEED'
#!/bin/sh
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
[ -x "$VMRUN" ] || exit 0
out=$(pmset -g batt)
pct=$(printf '%s\n' "$out" | grep -Eo '[0-9]+%' | head -1 | tr -d %)
[ -n "$pct" ] || exit 0
state=$(printf '%s\n' "$out" | sed -n 's/.*[0-9]%; *\([^;]*\);.*/\1/p' | head -1 | tr ' ' '-')
[ -n "$state" ] || state=unknown
"$VMRUN" -T fusion list | tail -n +2 | while IFS= read -r vmx; do
  "$VMRUN" -T fusion writeVariable "$vmx" guestVar battery "$pct $state $(date +%s)" >/dev/null 2>&1 || true
done
FEED
chmod +x "$feed"

cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>$feed</string></array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
sh "$feed"
echo "Battery feed installed: the VM's dock shows it within a minute."
