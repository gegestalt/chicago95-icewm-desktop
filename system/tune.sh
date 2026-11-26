#!/usr/bin/env bash
# system/tune.sh — general performance settings for the Chicago OS dev VM.
# Run by system-setup.sh; safe to run again. Everything here is reversible.
#
#   1. Compressed swap in RAM (zram, zstd): the VM had no swap at all, so a
#      busy Firefox + VS Code + Docker had nothing to fall back on before
#      apps got killed. zram typically fits 2-3x its size in RAM, with no
#      disk I/O.
#   2. Kernel memory settings tuned for zram, and more file watches for
#      VS Code / gopls / air on large repos.
#   3. Background services a VM dev box doesn't use are switched off.
#   4. Docker starts on first use (socket activation) instead of at boot.
#   5. apt stops rebuilding the man-page index on every install.
set -euo pipefail

sudo -v

echo "-- Compressed swap in RAM (zram) --"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y systemd-zram-generator >/dev/null
sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
# Chicago OS: compressed swap in RAM (system/tune.sh)
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF
sudo systemctl daemon-reload
sudo systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true

echo "-- Kernel memory and file-watch settings --"
sudo tee /etc/sysctl.d/99-chicago-os.conf >/dev/null <<'EOF'
# Chicago OS (system/tune.sh)
# zram swap is cheap (no disk), so use it before dropping file caches;
# read single pages, not clusters, since there is no seek cost.
vm.swappiness = 180
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
# VS Code, gopls and air watch every file of a project.
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
EOF
sudo sysctl -q --system

echo "-- Logs: journal only, capped at 200 MB --"
sudo install -d /etc/systemd/journald.conf.d
printf '[Journal]\nStorage=persistent\nSystemMaxUse=200M\n' \
  | sudo tee /etc/systemd/journald.conf.d/chicago-os.conf >/dev/null
sudo systemctl restart systemd-journald

echo "-- Switching off services a VM dev box doesn't use --"
# All reversible: `sudo systemctl enable --now <name>` brings one back.
#   avahi-daemon          mDNS/.local network discovery
#   power-profiles-daemon power modes for real laptops (the VM has none)
#   sysstat               performance history collection every 10 minutes
#   rsyslog               duplicate of the systemd journal (journalctl)
#   motd-news             fetches login-banner news
for u in avahi-daemon.service avahi-daemon.socket power-profiles-daemon.service \
         sysstat.service sysstat-collect.timer sysstat-summary.timer \
         rsyslog.service motd-news.timer; do
  sudo systemctl disable --now "$u" 2>/dev/null || true
done
# Phone, camera and online-account volume monitors (no USB devices here).
systemctl --user mask --now gvfs-afc-volume-monitor.service \
  gvfs-gphoto2-volume-monitor.service gvfs-mtp-volume-monitor.service \
  gvfs-goa-volume-monitor.service 2>/dev/null || true

echo "-- Docker: start on first use --"
# `docker` / `docker compose` start the daemon on demand through the
# socket; nothing changes in how they're used. Containers with a restart
# policy come back as soon as Docker starts.
if systemctl list-unit-files docker.socket >/dev/null 2>&1; then
  sudo systemctl enable docker.socket >/dev/null 2>&1 || true
  sudo systemctl disable docker.service containerd.service >/dev/null 2>&1 || true
fi

echo "-- apt: no man-page index rebuild on every install --"
echo 'man-db man-db/auto-update boolean false' | sudo debconf-set-selections
sudo rm -f /var/lib/man-db/auto-update

echo "-- Tuning done: $(swapon --show=NAME,SIZE --noheadings | tr '\n' ' ')swap --"
