#!/usr/bin/env bash
set -euo pipefail

# 1) live-reload the active bar's theme colors
barctl="$HOME/.config/quickshell/bin/qs-barctl"
if [ -x "$barctl" ]; then
  "$barctl" ipc theme reload >/dev/null 2>&1 || true
else
  qs -c bar ipc call theme reload >/dev/null 2>&1 || true
fi

resolve_current_root() {
  local state="$HOME/.local/state/omarchy/current"
  local legacy="$HOME/.config/omarchy/current"

  if command -v omarchy-shell >/dev/null 2>&1 && [ -d "$state" ]; then
    printf '%s\n' "$state"
  elif [ -d "$legacy" ]; then
    printf '%s\n' "$legacy"
  else
    return 1
  fi
}

current_root="$(resolve_current_root || true)"
[ -n "$current_root" ] && [ -d "$current_root" ] || exit 0

theme_name_file="$current_root/theme.name"

# theme.name is authoritative on Omarchy 4, where current/theme is a real
# directory named "theme". The symlink fallback is only for the legacy layout.
theme_name="$(tr -d '[:space:]' < "$theme_name_file" 2>/dev/null || true)"
if [ -z "$theme_name" ] && [ "$current_root" = "$HOME/.config/omarchy/current" ]; then
  theme_name="$(basename "$(readlink "$current_root/theme" 2>/dev/null)" 2>/dev/null || true)"
fi
case "$theme_name" in
  ""|.|..|*/*|*\\*) theme_name="" ;;
esac

background_sources=()
[ -d "$current_root/theme/backgrounds" ] && background_sources+=("$current_root/theme/backgrounds")
if [ -n "$theme_name" ] && [ -d "$HOME/.config/omarchy/backgrounds/$theme_name" ]; then
  background_sources+=("$HOME/.config/omarchy/backgrounds/$theme_name")
fi
((${#background_sources[@]} > 0)) || exit 0

# 2) pre-generate the wallpaper scan cache for the freshly switched theme.
#    This must match the image picker wallpaper scan contract:
#      source_path<TAB>content-addressed_512px_thumbnail_path
#    The content hash is stable across Omarchy's current/theme copy mtimes, so
#    switching A -> B -> A can reuse already generated thumbnails.
C="$HOME/.cache/quickshell-scan-wallpaper"
D="$HOME/.cache/quickshell-img-thumbs"
cache_dir="$(dirname "$C")"
mkdir -p "$D" "$cache_dir"

stamp_tmp=""
tmp="$(mktemp "$cache_dir/.quickshell-scan-wallpaper.XXXXXX")"
trap 'rm -f "$tmp" "$stamp_tmp"' EXIT

find -L "${background_sources[@]}" -maxdepth 1 -type f \
     \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) \
     2>/dev/null | sort | while IFS= read -r f; do
       k=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1) || continue
       [ -n "$k" ] || continue
       printf '%s\t%s/%s-512.jpg\n' "$f" "$D" "$k"
     done > "$tmp"
mv -f "$tmp" "$C"

# Theme sidecar stamp — prepares Schicht 2 (cache validation); inert until QML
# reads it.
if [ -n "$theme_name" ]; then
  stamp_tmp="$(mktemp "$cache_dir/.quickshell-scan-wallpaper.theme.XXXXXX")"
  printf '%s\n' "$theme_name" > "$stamp_tmp"
  mv -f "$stamp_tmp" "$C.theme"
fi

# NOTE: thumbnail generation remains in the picker warm path. The hook only
# writes deterministic scan metadata so the first open after a theme switch does
# not show a stale previous-theme cache.
