#!/usr/bin/env bash
# system-setup.sh — the root-level half of the Chicago OS setup.
# install.sh does everything that lives in your home directory; this does
# the things that need sudo. install.sh runs it first, so a fresh Ubuntu
# needs only ./install.sh. Every step is safe to run again.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run as your normal user; it calls sudo itself." >&2; exit 1
fi
sudo -v

step() { printf '\n== %s ==\n' "$*"; }

# ---------------------------------------------------------------------------
step "Keyboard: US layout system-wide (login screen, consoles, new sessions)"
# The system default was Turkish, so the login screen and every ibus
# restart put shift+2 back on ' instead of @. US stays the default and
# Turkish remains one click away in the taskbar layout picker.
sudo sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT="us"/; s/^XKBVARIANT=.*/XKBVARIANT=""/; s/^XKBOPTIONS=.*/XKBOPTIONS="altwin:alt_win"/' /etc/default/keyboard
sudo setupcon --save-only 2>/dev/null || true

# ---------------------------------------------------------------------------
step "Visual Studio Code apt repository (Microsoft)"
if [ ! -f /etc/apt/sources.list.d/vscode.sources ]; then
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg >/dev/null
  sudo tee /etc/apt/sources.list.d/vscode.sources >/dev/null <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
fi

# ---------------------------------------------------------------------------
step "X11 + LightDM + IceWM session (Ubuntu 26.04 ships Wayland/GDM only)"
sudo apt-get update
# Pick LightDM as the display manager without the interactive prompt.
echo "lightdm shared/default-x-display-manager select lightdm" | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  xserver-xorg xserver-xorg-core xserver-xorg-legacy xserver-xorg-input-libinput \
  x11-xserver-utils xinit lightdm lightdm-gtk-greeter icewm icewm-common \
  open-vm-tools open-vm-tools-desktop ghostty code nmap net-tools
echo /usr/sbin/lightdm | sudo tee /etc/X11/default-display-manager >/dev/null
sudo systemctl disable gdm3.service 2>/dev/null || true
sudo systemctl enable lightdm.service
sudo mkdir -p /etc/lightdm/lightdm.conf.d
sudo cp "$REPO_DIR/system/lightdm/99-chicago95.conf" /etc/lightdm/lightdm.conf.d/99-chicago95.conf
sudo cp "$REPO_DIR/system/icewm-chicago95.desktop" /usr/share/xsessions/icewm-chicago95.desktop

# ---------------------------------------------------------------------------
step "Ghostty as the system default terminal (x-terminal-emulator)"
sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/ghostty 60
sudo update-alternatives --set x-terminal-emulator /usr/bin/ghostty

# ---------------------------------------------------------------------------
step "Developer toolchain"
sudo apt-get install -y \
  build-essential git curl wget jq ripgrep fd-find fzf htop tree unzip \
  nodejs npm rustup gh docker.io docker-compose-v2 inotify-tools \
  tint2 jgmenu nmap net-tools
# Debian names fd's binary fdfind; give it its usual name.
mkdir -p "$HOME/.local/bin"
[ -e "$HOME/.local/bin/fd" ] || ln -s /usr/bin/fdfind "$HOME/.local/bin/fd"
# Rust stable toolchain for this user.
rustup default stable
# Docker without sudo (takes effect at next login).
sudo usermod -aG docker "$USER"

# ---------------------------------------------------------------------------
step "Firefox: Mozilla's .deb instead of the snap (profile carried over)"
"$REPO_DIR/system/firefox-deb.sh"

# ---------------------------------------------------------------------------
step "Performance: switch off services a single-user dev VM doesn't use"
# All reversible: `sudo systemctl enable --now <name>` brings one back.
#   kdump-tools    reserves ~512 MB RAM at boot for kernel crash dumps
#   cloud-init     cloud-server provisioning, slows every boot
#   ModemManager   cellular modems
#   cups-browsed   network printer auto-discovery (printing itself stays)
#   openvpn        unused VPN daemon
#   iperf3         network benchmark server listening on a port
#   sssd           enterprise/LDAP logins
for svc in ModemManager cups-browsed openvpn iperf3 sssd \
           cloud-init-local cloud-init-main cloud-init-network cloud-config cloud-final; do
  sudo systemctl disable --now "$svc.service" 2>/dev/null || true
done
sudo touch /etc/cloud/cloud-init.disabled
# Removing kdump-tools also removes its crashkernel= boot option.
sudo apt-get purge -y kdump-tools kexec-tools || true
sudo update-grub

# ---------------------------------------------------------------------------
step "Performance tuning (zram swap, idle services off, Docker on demand)"
"$REPO_DIR/system/tune.sh"

# ---------------------------------------------------------------------------
step "Done"
echo "Reboot to apply the keyboard layout, the login screen, the freed RAM and docker group."
