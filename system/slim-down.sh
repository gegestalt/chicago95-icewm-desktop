#!/usr/bin/env bash
# system/slim-down.sh — strips a stock Ubuntu desktop install down to what
# Chicago OS actually uses: removes the GNOME session, apps that aren't
# used on this dev VM, telemetry, accessibility daemons, printing and
# hardware services a VM doesn't have. Called by install.sh; safe to run
# again (already-removed packages are skipped).
#
#   ./system/slim-down.sh            remove (asks for sudo)
#   ./system/slim-down.sh --dry-run  only list what would be removed
#
# How it stays safe: every package the desktop depends on (KEEP below) is
# first marked "manually installed", so apt's autoremove can never take
# it along with the GNOME meta-packages. The KEEP list covers the session
# itself (Xorg, LightDM, IceWM, dock, audio, network, VMware tools), the
# dev toolchain, and the apps chosen to stay (LibreOffice, Calculator).
set -euo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

KEEP=(
  # session
  xserver-xorg xserver-xorg-core xserver-xorg-legacy xserver-xorg-input-libinput
  x11-xserver-utils x11-utils xinit lightdm lightdm-gtk-greeter
  icewm icewm-common tint2 jgmenu picom pcmanfm libfm-modules dunst yad
  xfce4-settings xfce4-power-manager network-manager network-manager-gnome
  blueman bluez pavucontrol arandr hardinfo2 xdotool imagemagick mesa-utils
  open-vm-tools open-vm-tools-desktop ibus dconf-cli gnome-keyring
  gvfs gvfs-backends gvfs-fuse xdg-desktop-portal xdg-desktop-portal-gtk
  xdg-utils xdg-user-dirs at-spi2-core policykit-desktop-privileges
  pipewire pipewire-pulse pipewire-alsa wireplumber alsa-base linux-sound-base
  python3-gi python3-cairo gir1.2-gtk-3.0 gir1.2-gtk-4.0 gir1.2-rsvg-2.0
  gnome-control-center snapd plymouth dracut sudo unattended-upgrades bc
  # apps
  ghostty code gpicview evince mpv file-roller gnome-text-editor
  gnome-calculator libreoffice-writer libreoffice-calc libreoffice-impress
  libreoffice-draw libreoffice-math libreoffice-gtk3
  # fonts (CJK so web pages never show boxes)
  fonts-ubuntu fonts-jetbrains-mono fonts-dejavu-core fonts-liberation
  fonts-noto-color-emoji fonts-noto-cjk
  # dev toolchain
  build-essential git curl wget jq ripgrep fd-find fzf htop tree unzip
  nodejs npm rustup gh docker.io docker-compose-v2 inotify-tools
  nmap net-tools openssh-client xclip xsel
)

PURGE_PATTERNS=(
  # GNOME session (Chicago OS logs in through LightDM into IceWM)
  ubuntu-desktop ubuntu-desktop-minimal ubuntu-session gnome-shell
  'gnome-shell-extension-*' gdm3 gnome-initial-setup nautilus 'nautilus-*' ptyxis
  # apps not used on this VM
  thunderbird 'rhythmbox*' 'shotwell*' 'transmission-*' 'remmina*' deja-dup
  gnome-calendar gnome-clocks gnome-characters gnome-logs gnome-system-monitor
  gnome-font-viewer gnome-startup-applications gnome-snapshot gnome-power-manager
  baobab gnome-disk-utility seahorse yelp ubuntu-docs gnome-user-docs loupe
  papers showtime decibels aisleriot gnome-mahjongg gnome-mines gnome-sudoku
  # accessibility daemons
  orca brltty 'speech-dispatcher*'
  # printing and scanning
  'cups*' hplip 'printer-driver-*' system-config-printer simple-scan 'sane-*'
  # telemetry and crash reporting
  whoopsie 'apport*' ubuntu-report popularity-contest kerneloops
  # hardware/services a VM doesn't have or need
  modemmanager fwupd 'fwupd-*' wsdd sssd 'sssd-*'
  # GNOME update GUIs (unattended-upgrades still installs security fixes)
  update-manager update-notifier software-properties-gtk landscape-common
  ubuntu-pro-client-l10n
  # spellcheck dictionaries and GNOME language packs
  'language-pack-gnome-*' 'hunspell-*' 'hyphen-*' 'mythes-*'
)

SNAPS=(thunderbird snap-store desktop-security-center prompting-client firmware-updater)

installed() {
  dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' "$@" 2>/dev/null \
    | awk '$1 == "ii" { print $2 }' | sort -u
}

mapfile -t keep < <(installed "${KEEP[@]}")
mapfile -t purge < <(installed "${PURGE_PATTERNS[@]}" | grep -vxF -f <(printf '%s\n' "${keep[@]}"))
mapfile -t snaps < <(snap list 2>/dev/null | awk 'NR > 1 { print $1 }' | grep -xF -f <(printf '%s\n' "${SNAPS[@]}") || true)

if [ ${#purge[@]} -eq 0 ] && [ ${#snaps[@]} -eq 0 ]; then
  echo "Nothing to remove: the system is already slim."
  exit 0
fi

if [ "$DRY" = 1 ]; then
  # Simulation: naming the KEEP packages on the same command line makes
  # apt treat them as wanted, the same effect apt-mark manual has below.
  out=$(apt-get -s --autoremove install "${keep[@]}" "${purge[@]/%/-}" 2>&1)
  removed=$(printf '%s\n' "$out" | awk '/^Remv/ { print $2 }')
  echo "Would remove $(printf '%s\n' "$removed" | grep -c .) packages:"
  printf '%s\n' "$removed" | column -c "${COLUMNS:-120}"
  [ ${#snaps[@]} -gt 0 ] && echo && echo "Would remove snaps: ${snaps[*]}"
  exit 0
fi

sudo -v
echo "-- Protecting the packages Chicago OS uses --"
sudo apt-mark manual "${keep[@]}" >/dev/null

echo "-- Removing ${#purge[@]} packages and everything only they needed --"
# Keep services running during the purge: removing gdm3 would otherwise
# stop the display manager and end the session this script runs in (it
# may be the GNOME session of a fresh install). Changes apply at reboot.
printf '#!/bin/sh\nexit 101\n' | sudo tee /usr/sbin/policy-rc.d >/dev/null
sudo chmod +x /usr/sbin/policy-rc.d
trap 'sudo rm -f /usr/sbin/policy-rc.d' EXIT
if [ ${#purge[@]} -gt 0 ]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y --autoremove "${purge[@]}"
fi
sudo rm -f /usr/sbin/policy-rc.d
trap - EXIT

for s in "${snaps[@]}"; do
  echo "-- Removing snap $s --"
  sudo snap remove --purge "$s" || true
done
# Old disabled snap revisions waste a few hundred MB each.
snap list --all 2>/dev/null | awk '/disabled/ { print $1, $3 }' | while read -r name rev; do
  sudo snap remove "$name" --revision="$rev" || true
done
sudo apt-get clean
echo "-- Slim-down done: $(df -h / | awk 'NR==2 { print $3 " used, " $4 " free" }') --"
