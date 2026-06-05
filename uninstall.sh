#!/usr/bin/env bash
# Quickshell Rise — uninstaller (version-agnostic; removes whatever is installed)
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/uninstall.sh)
set -euo pipefail

DEST="$HOME/.config/quickshell/bar"

c_g=$'\e[32m'; c_y=$'\e[33m'; c_0=$'\e[0m'
info() { printf "%s==>%s %s\n" "$c_g" "$c_0" "$*"; }
warn() { printf "%s!!%s %s\n"  "$c_y" "$c_0" "$*"; }

# 1. stop the running bar
# stop existing bar (supports both -c bar and -p $DEST modes)
pkill -f "qs.*-c bar" 2>/dev/null && info "Stopped the bar" || true
pkill -f "quickshell -p $DEST" 2>/dev/null && info "Stopped the bar" || true

# 2. remove the post-boot hook (if the user installed it)
boot="$HOME/.config/omarchy/hooks/post-boot.d/quickshell-rise"
[[ -f "$boot" ]] && { rm -f "$boot"; info "Removed post-boot hook"; }

# 3. remove the theme hook we installed
hook="$HOME/.config/omarchy/hooks/theme-set.d/50-quickshell-bar.sh"
[[ -f "$hook" ]] && { rm -f "$hook"; info "Removed theme hook"; }

# 4. remove the config — restore the most recent backup if one exists
restored=false
if [[ -d "$DEST" ]]; then
  rm -rf "$DEST"
  latest="$(ls -dt "$DEST".bak.* 2>/dev/null | head -1 || true)"
  if [[ -n "${latest:-}" ]]; then
    mv "$latest" "$DEST"
    info "Restored previous config from backup ($(basename "$latest"))"
    restored=true
  else
    info "Removed $DEST"
  fi
else
  warn "Nothing installed at $DEST"
fi

# 5. restart the bar that was in use before install
if [[ "$restored" == true ]] && [[ -f "$DEST/shell.qml" ]]; then
  setsid quickshell -p "$DEST" >/dev/null 2>&1 & disown
  info "Restarted quickshell from backup"
else
  if command -v omarchy &>/dev/null; then
    omarchy restart waybar 2>/dev/null && info "Restarted waybar" || true
  else
    setsid waybar >/dev/null 2>&1 & disown 2>/dev/null || true
    info "Restarted waybar"
  fi
fi

info "Uninstalled.${c_0}  (older backups under ~/.config/quickshell/bar.bak.* are kept)"
