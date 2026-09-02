# Chicago95 IceWM Desktop

[![Lint](https://github.com/gegestalt/chicago95-icewm-desktop/actions/workflows/lint.yml/badge.svg)](https://github.com/gegestalt/chicago95-icewm-desktop/actions/workflows/lint.yml)
[![Release](https://img.shields.io/github/v/release/gegestalt/chicago95-icewm-desktop)](https://github.com/gegestalt/chicago95-icewm-desktop/releases)

See [CHANGELOG.md](CHANGELOG.md) for release notes.

A Windows-95/XP-styled IceWM desktop for Ubuntu, built on top of the
[Chicago95](https://github.com/grassmunk/Chicago95) GTK/icon theme. This repo
is the post-install layer: a proper Start menu, a real "all apps" grid like
Ubuntu's app grid or macOS Launchpad, HiDPI-correct window chrome, and every
default app wired to something that actually matches the theme instead of
falling back to stock GNOME apps.

![Demo](screenshots/demo.gif)

## Technology stack

- **Window manager:** [IceWM](https://ice-wm.org/)
- **Theme:** [Chicago95](https://github.com/grassmunk/Chicago95) (GTK + icon theme)
- **Terminal:** [Ghostty](https://ghostty.org/) — wired in as `TerminalCommand`
  and the Start menu/taskbar launcher
- **File manager:** `pcmanfm`
- **Settings:** a `yad`-based Control Panel (`dotfiles/local/bin/chicago95-settings`)
  fronting a themable GTK3 tool per category — `arandr` (Display), `nm-connection-editor`
  (Network), `blueman` (Bluetooth), `pavucontrol` (Sound), `xfce4-power-manager-settings`
  (Power), and `xfce4-settings`' own Keyboard/Mouse/Appearance panels — instead of
  GNOME Control Center, whose GTK4/libadwaita panels can't be reskinned and, for
  several categories, depend on session daemons (Mutter, gsd) a plain IceWM
  session doesn't run. Users and Date & Time stay on GNOME Control Center (no
  themable GTK3 equivalent ships in Ubuntu's repos for either, and both work
  fine regardless — their backends, accountsservice and systemd-timedated, don't
  need Mutter or gsd). `xfce4-settings-manager` remains available separately as
  its own "Settings Manager" app-grid entry.
- **Notifications:** `dunst`
- **Network applet:** `network-manager-gnome` (`nm-applet`)
- **Keyboard layout switcher:** `keyboard-layout-picker`
  (`dotfiles/local/bin/keyboard-layout-picker`) — a small custom GTK3 tray
  icon; an "EN"/"TR" indicator in the taskbar tray (bottom-right), click
  for a menu of layouts with the active one highlighted
- **Image/document/media viewers:** `gpicview`, `evince`, `mpv`
- **Display manager:** LightDM, themed to match
- **Boot splash:** Plymouth, running the vendored Chicago95 boot animation
- **Browser:** Firefox (`.deb`, not snap — see [What it doesn't
  do](#what-it-doesnt-do))
- **Install/uninstall tooling:** POSIX `sh`, no build step, no external
  dependencies beyond `apt`

## What it does

- **Start menu** with every installed app, auto-generated and grouped by
  category (`icewm-menu-fdo`), plus quick-launch shortcuts on top.
- **A taskbar "Applications" button** (3x3 grid icon, matching Ubuntu's app-grid glyph) that opens `~/Applications`
  — a flat, one-page, alphabetized grid of *every* installed app, no category
  folders. Kept in sync automatically on every login. Entries are deduplicated
  by their visible name as well as by filename, so a local override (like the
  Chicago95 Control Panel below) cleanly replaces the system's own same-named
  entry instead of both showing up side by side (see
  [#28](https://github.com/gegestalt/chicago95-icewm-desktop/issues/28)).
- **One working "Settings" entry, themed to match and actually functional.**
  GNOME Control Center's own `org.gnome.Settings.desktop` shows up in the app
  grid regardless of desktop environment, but its GTK4/libadwaita panels can't
  be reskinned, and several depend on session daemons a plain IceWM session
  doesn't run — Display needs `org.gnome.Mutter.DisplayConfig` (Mutter/GNOME
  Shell only), Power needs its own daemon started (`xfce4-power-manager`,
  now started from `.icewm/startup`) — so those panels open but every control
  in them silently does nothing (see
  [#29](https://github.com/gegestalt/chicago95-icewm-desktop/issues/29)).
  `chicago95-settings` is a small `yad` picker that fronts a themable,
  actually-working GTK3 tool per category instead (see the tech-stack entry
  above for the full mapping).
- **The screen actually fills the display.** `dotfiles/icewm/startup` checks
  every connected output against its own preferred mode on login and
  switches to it if they differ — fixes a VM-observed case where the X
  server came up already locked to an undersized mode, leaving a visible
  gap of unused screen instead of filling the real display
  ([#28](https://github.com/gegestalt/chicago95-icewm-desktop/issues/28)).
- **Desktop icons that don't vanish when you drag them.** `pcmanfm --desktop`
  has a bug where a dragged icon's new position is saved correctly but
  never repainted until some unrelated screen event forces it to (see
  [#19](https://github.com/gegestalt/chicago95-icewm-desktop/issues/19)). A
  small watcher (`dotfiles/local/bin/desktop-icon-repaint-watch`) forces
  that repaint within ~50ms of any drag instead.
- **Super+Tab also switches windows.** Both Windows/Super keys are set up as
  an extra Alt (`altwin:alt_win`), so Alt+Tab's window switcher
  (`KeySysSwitchNext`) also fires on Super+Tab — handy on compact/60%
  keyboards where Alt and the Windows key sit right next to each other.
- **English/Turkish keyboard switching from the taskbar.** A 32x32
  "EN"/"TR" square in the tray — click it for a menu of layouts with the
  active one shown selected, pick one to switch (via `setxkbmap`), same
  idea as Windows' language bar but with the picker GNOME/Windows both
  use rather than a blind toggle. Custom-built
  (`dotfiles/local/bin/keyboard-layout-picker`, a small GTK3 status icon)
  because nothing packaged combines a themable Win95-style tray icon with
  an actual picker menu. Turkish here is the standard XKB `tr` (Q) layout
  — X11's `xkeyboard-config` has no Apple-style "Turkish Mac" variant to
  select instead (checked directly against
  `/usr/share/X11/xkb/rules/evdev.xml`: the real `tr` variants are
  `f`/`e`/`alt`/`intl`, none of them "mac"), and its letter-key mapping
  (Ğ/Ü, Ş/İ, Ö/Ç in the same positions) is identical to a real Turkish
  MacBook keyboard's legend regardless — the two only differ in
  modifier-key labeling (command/option vs. win/alt) and physical shape,
  not in what any key types.
- **HiDPI-correct window chrome.** The stock Chicago95 IceWM theme's title-bar
  buttons and borders are raw pixel-art sized for ~96 DPI screens; on a
  HiDPI display they render tiny inside an enlarged bar. This repo ships a
  proper 2x-upscaled asset set (`dotfiles/icewm/themes-2x`) alongside the
  original (`themes-1x`), and the installer picks the right one by measuring
  your actual display DPI.
- **Theme-consistent default apps** — `gpicview`/`evince`/`mpv`/`pcmanfm`
  instead of GNOME's GTK4 Loupe/Showtime/Nautilus (which cannot be reskinned
  by any classic GTK theme), and `xfce4-settings-manager` (themable, GTK3)
  instead of GNOME Control Center (GTK4/libadwaita, also unreskinnable).
- **GSettings synced** to the theme so GTK4/portal-aware apps stop falling
  back to Yaru/Adwaita.
- **The classic Firefox icon everywhere Firefox shows up** — desktop,
  Start menu, taskbar, quickswitch, alt-tab. Firefox ignores the icon
  theme for its own window icon (it ships bundled PNGs and re-asserts them
  via `_NET_WM_ICON`), so `install.sh` replaces those bundled files
  directly with the classic Chicago95 icon. Undone by Firefox package
  upgrades; re-run `install.sh` to reapply.
- **LightDM greeter** configured for Chicago95 with the correct DPI.
- **A Plymouth boot theme** — a 20-frame Windows-95-style boot animation,
  installed to `/usr/share/plymouth/themes/Chicago95` and set as default.
  Vendored from upstream Chicago95 (see [ATTRIBUTION.md](ATTRIBUTION.md)),
  which ships it but doesn't wire it up itself. Takes effect on next
  reboot — `install.sh` stages it, it doesn't reboot you.
- **The Windows-95 login/logout chime, actually audible — and not
  stuttering.** Vendored from upstream Chicago95 (see
  [ATTRIBUTION.md](ATTRIBUTION.md)) as a full XDG sound theme, and wired
  into IceWM's own sound daemon (`icesound`) for startup, shutdown,
  restart, and dialog-open/close — not just files sitting in a theme
  folder that nothing ever plays. The upstream `.wav` files are also
  transcoded to PipeWire's native 48000Hz (see ATTRIBUTION.md) — at the
  original 22050Hz, every playback needed live resampling and that
  resampler underran for the whole clip. GSettings also points
  GTK4/portal apps at the same theme.
- **A game: ClackType.** `games/clacktype` — a from-scratch typing-speed
  test in the same vein as Monkeytype (word-by-word correct/incorrect
  highlighting, live WPM/accuracy, time and word-count modes, and a
  results-screen WPM/raw graph with error ticks). Single self-contained
  HTML file, no build step, no network dependency, runs in Firefox. Lands
  on the Start menu and Desktop as "ClackType."

  ![ClackType](screenshots/clacktype.png)

## What it doesn't do

GNOME Settings, Nautilus, and other libadwaita apps genuinely cannot be
reskinned — that's a GTK4 design decision, not something a theme or this
script can work around. This repo replaces them with themable equivalents
instead of trying to force them.

Firefox as a **snap** is sandboxed away from any custom theme entirely (it
can only see the themes bundled in the `gtk-common-themes` snap) — that's
handled by the separate, opt-in `optional/migrate-firefox-to-deb.sh`, not by
`install.sh`, since it removes a package and touches your browser profile.

## Prerequisites

- Ubuntu (apt-based)
- [Ghostty](https://ghostty.org/) installed (`apt install ghostty` on recent
  Ubuntu; see ghostty.org for other distros/versions) — it's the default
  terminal this repo wires up, and `install.sh` doesn't install it for you
- The upstream Chicago95 theme already installed:
  ```
  git clone https://github.com/grassmunk/Chicago95.git ~/Chicago95
  cd ~/Chicago95 && python3 installer.py
  ```

## Install

```
git clone https://github.com/gegestalt/chicago95-icewm-desktop.git
cd chicago95-icewm-desktop
./install.sh
```

Log out and pick the **IceWM Chicago95** session at the login screen.

Display DPI (and the 1x-vs-2x theme-asset choice it drives) is detected
once and then reused on every later run — some environments (observed on
a VMware guest) silently drift the X server's reported DPI between
logins, and re-detecting on every run would make a plain re-run of
`install.sh` randomly shrink your fonts/taskbar back down. If you
actually change monitors and want a fresh probe, run
`CHICAGO95_REDETECT_DPI=1 ./install.sh`.

Optional, recommended if Firefox is installed as a snap:
```
./optional/migrate-firefox-to-deb.sh
```

## Uninstall

Every file `install.sh` overwrites is backed up first, and every GSettings
key it changes has its previous value recorded, under
`~/.chicago95-icewm-desktop/backups/<run>/`. To revert the most recent run:

```
./uninstall.sh
```

This restores anything that already existed, deletes anything that was newly
created, and restores the old GSettings values. It leaves the `~/Applications`
grid folder and any packages `install.sh` installed via apt in place — those
are harmless to keep around, and removing packages automatically felt like
the wrong default. Pass a specific run id (a timestamp directory name under
`backups/`) to revert an older run instead of the latest one.

## Layout

```
install.sh                        main installer (idempotent, DPI-aware, self-backing-up)
uninstall.sh                      reverts a previous install.sh run
optional/migrate-firefox-to-deb.sh  snap -> .deb Firefox migration (opt-in)
dotfiles/icewm/                   menu, toolbar, preferences, theme assets (1x + 2x)
dotfiles/config/                  gtk-3.0, gtk-4.0, mimeapps.list, dunst
dotfiles/local/bin/build-app-grid script that (re)builds ~/Applications
dotfiles/local/bin/keyboard-layout-picker  the En/Tr taskbar layout switcher
icons/chicago95-applications/     the taskbar "Applications" icon, all sizes
games/clacktype/                  self-contained typing-test game (no deps)
system/plymouth/Chicago95/        boot theme (vendored, see ATTRIBUTION.md)
system/sounds/Chicago95/          full sound theme (vendored, see ATTRIBUTION.md)
system/                           lightdm + xsessions entries (sudo-installed)
.github/workflows/lint.yml        CI: bash -n + ShellCheck on every push/PR
```

## License

MIT for everything in this repo. Chicago95 itself is a separate project —
see its own repo for its license.
