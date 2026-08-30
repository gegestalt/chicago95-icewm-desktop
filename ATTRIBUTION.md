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
  Upstream ships these as 8-bit/22050Hz PCM. Two independent things made
  that stutter on playback: the low bit depth, and — the bigger one —
  22050Hz/44100Hz isn't a rate PipeWire's clock ever runs at (it's fixed to
  48000Hz here), so *every* playback needed live resampling, and that
  resampler underran repeatedly for the whole duration of the clip
  (`spa.audioconvert: ... out of buffers`, dozens of times per play, not
  just once at start). The `.wav` files here are transcoded straight to
  16-bit/48000Hz — PipeWire's native rate — so no resampling happens at
  all; same audio, no other changes. (A single harmless `out of buffers`
  blip can still show up the very first time a fresh PipeWire graph plays
  anything at all — that's normal stream-startup buffering, not this bug.)
