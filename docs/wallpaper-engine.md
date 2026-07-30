# Animated (Wallpaper Engine) picker

Rise's image picker has a third mode, `animated`, that lists **live Wallpaper
Engine wallpapers** (Steam Workshop scene/video wallpapers) and applies them.
It reuses the existing filmstrip picker (all three styles) and delegates every
wallpaper action to the external [`omarchy-we`](https://github.com/dkgamer02ai/omarchy-wallpaper-engine)
CLI, which drives [`linux-wallpaperengine`](https://github.com/Almamu/linux-wallpaperengine).

## Compatibility

This mode is **optional and self-disabling**. Rise never hard-depends on
`omarchy-we`:

- On startup a single `WallpaperEngineAdapter` runs `omarchy-we ipc version` and
  enables the mode only if it exits 0 and reports a compatible contract
  (`ipc >= 1`).
- On Omarchy 3.8.x, generic Hyprland, or any system without `omarchy-we`, the
  probe fails and `qs-barctl ipc picker animated` is a no-op. The `theme` and
  `wallpaper` pickers are unaffected.

## Installation

1. Install `omarchy-we` (see its repo) — it needs Omarchy 4, Steam's Wallpaper
   Engine, and `linux-wallpaperengine`.
2. Nothing else to install in Rise. The `animated` mode lights up automatically
   once the capability probe succeeds.

## Invocation

Bind a key to the IPC route (same shape as the theme/wallpaper pickers):

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER + CTRL + SHIFT + W", "Animated wallpaper picker",
       "~/.config/quickshell/bin/qs-barctl ipc picker animated")
```

Or call it directly: `qs-barctl ipc picker animated`.

## GPU implications

Live wallpapers keep `linux-wallpaperengine` running and rendering on the GPU
continuously (heavier than a static image, especially 4K scenes). Two things
matter:

- **Switching back to a static wallpaper stops the renderer.** Selecting any
  `theme` or `wallpaper` in the picker calls `omarchy-we ipc kill`, so the GPU
  renderer is torn down rather than left running hidden behind the static image.
- On a laptop/iGPU, prefer the video wallpapers over heavy scenes, cap the frame
  rate via `omarchy-we`, or stop the renderer on battery.

## How it works (architecture)

- `versions/V1/WallpaperEngineAdapter.qml` is the single owner of all
  `omarchy-we` interaction: capability probe, entry fetch, JSON validation,
  sanitisation, atomic caching, error state, apply, and renderer teardown. All
  three picker styles delegate to it — no per-style command pipeline.
- Entries are consumed as **structured JSON** (`omarchy-we ipc entries`), then
  every field is control-char-stripped before the picker's row model sees it, so
  Workshop metadata cannot corrupt the list.
- The scan cache is replaced atomically (temp file + rename) and only after a
  validated response, so a failed refresh never truncates it.
- A non-zero exit or malformed response surfaces an actionable error in the
  picker instead of an empty "nothing found" state. A failed `set` raises a
  desktop notification rather than closing the picker silently.

Contract: `omarchy-we ipc {version|entries|current|set <id>|kill}`. `version`
returns `{"ipc":N,...}`; `entries`/`current` return JSON and exit non-zero on
failure (treated as an error, not an empty result).
