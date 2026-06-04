#!/usr/bin/env bash
# Quickshell Rise — one-command installer
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh)
#   bash <(curl -fsSL .../install.sh) rise        # install a specific version non-interactively
set -euo pipefail

REPO_URL="https://github.com/HANCORE-linux/quickshell-dots.git"
DEST="$HOME/.config/quickshell/bar"
WANT_VERSION="${1:-}"

c_b=$'\e[1m'; c_g=$'\e[32m'; c_y=$'\e[33m'; c_r=$'\e[31m'; c_0=$'\e[0m'
info() { printf "%s==>%s %s\n" "$c_g" "$c_0" "$*"; }
warn() { printf "%s!!%s %s\n"  "$c_y" "$c_0" "$*"; }
err()  { printf "%s✗%s %s\n"   "$c_r" "$c_0" "$*" >&2; }

# ── 1. dependencies ─────────────────────────────────────────────
need=(quickshell git jq curl)
opt=(pamixer brightnessctl powerprofilesctl bluetoothctl iwctl makoctl hypridle)
miss=()
for b in "${need[@]}"; do command -v "$b" >/dev/null 2>&1 || miss+=("$b"); done
if ((${#miss[@]})); then
  err "Missing required: ${miss[*]}"
  warn "On Arch:  sudo pacman -S quickshell git jq curl"
  exit 1
fi
optmiss=()
for b in "${opt[@]}"; do command -v "$b" >/dev/null 2>&1 || optmiss+=("$b"); done
((${#optmiss[@]})) && warn "Optional tools missing (some widgets disabled): ${optmiss[*]}"
fc-list | grep -qi "JetBrainsMono Nerd" || warn "Font 'JetBrainsMono Nerd Font' not found"
fc-list | grep -qi "Material Symbols"   || warn "Font 'Material Symbols Rounded' not found"

# ── 2. fetch repo ───────────────────────────────────────────────
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
info "Downloading…"
git clone --depth 1 "$REPO_URL" "$tmp/repo" >/dev/null 2>&1

mapfile -t versions < <(cd "$tmp/repo/versions" && ls -d */ | sed 's#/##')
((${#versions[@]})) || { err "No versions found in repo"; exit 1; }

# ── 3. choose version ───────────────────────────────────────────
choice="$WANT_VERSION"
if [[ -z "$choice" ]]; then
  echo "${c_b}Available versions:${c_0}"
  select v in "${versions[@]}"; do [[ -n "$v" ]] && { choice="$v"; break; }; done
fi
printf '%s\n' "${versions[@]}" | grep -qx "$choice" || { err "Unknown version: $choice"; exit 1; }

# ── 4. install (with backup) ────────────────────────────────────
if [[ -d "$DEST" ]]; then
  bak="$DEST.bak.$(date +%Y%m%d-%H%M%S)"
  info "Backing up existing config → $bak"
  mv "$DEST" "$bak"
fi
mkdir -p "$DEST"
cp -r "$tmp/repo/versions/$choice/." "$DEST/"
info "Installed '${c_b}$choice${c_0}' → $DEST"

# ── 5. launch / autostart ───────────────────────────────────────
hypr="$HOME/.config/hypr/hyprland.conf"
line="exec-once = quickshell -p $DEST"
if [[ -f "$hypr" ]] && ! grep -qF "quickshell -p $DEST" "$hypr"; then
  echo "$line" >> "$hypr"
  info "Added Hyprland autostart"
fi
info "Done. Launch now with:  ${c_b}quickshell -p $DEST${c_0}"
