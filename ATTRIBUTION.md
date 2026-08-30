# Third-party assets

This repo is MIT-licensed (see `LICENSE`), but a few directories vendor
binary assets from the upstream [Chicago95](https://github.com/grassmunk/Chicago95)
project (License: GPL-3.0+/MIT) rather than generating them fresh, since
Chicago95's own installer doesn't wire them up. Those assets remain under
Chicago95's license, not this repo's.

- `system/plymouth/Chicago95/` — the Chicago95 Plymouth boot theme (a
  20-frame Windows-95-style boot animation, script, and supporting
  images). `install.sh` installs this to
  `/usr/share/plymouth/themes/Chicago95` and sets it as the default via
  `update-alternatives`.
- `system/sounds/Chicago95/` — the full Chicago95 sound theme (`.wav`
  files + `index.theme`). `install.sh` installs this to
  `~/.local/share/sounds/Chicago95` and sets it as the active sound theme,
  and copies a handful of these files into `~/.icewm/sounds/` for IceWM's
  own `icesound` daemon (startup/shutdown/restart/dialog events).
  Upstream ships these as 8-bit/22050Hz PCM; that format made PipeWire's
  resampler stutter badly on playback (`spa.audioconvert: ... out of
  buffers`), so the `.wav` files here are transcoded to 16-bit/44100Hz —
  same audio, no other changes.
