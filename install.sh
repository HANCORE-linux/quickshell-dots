#!/usr/bin/env bash
# Quickshell Rise — one-command installer
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh)
#   bash <(curl -fsSL .../install.sh) V1          # install a specific version non-interactively
# Autostart via Omarchy post-boot hook (opt-in): see step 7.
set -euo pipefail

REPO_URL="https://github.com/HANCORE-linux/quickshell-dots.git"
DEST="$HOME/.config/quickshell/bar"

# args: optional version name + flags
WANT_VERSION=""
WANT_CLAUDE=""   # "" = ask interactively, "yes"/"no" = non-interactive
for a in "$@"; do
  case "$a" in
    --autostart|--no-autostart) ;;
    --claude-backend)    WANT_CLAUDE="yes" ;;
    --no-claude-backend) WANT_CLAUDE="no"  ;;
    *) WANT_VERSION="$a" ;;
  esac
done

c_b=$'\e[1m'; c_g=$'\e[32m'; c_y=$'\e[33m'; c_r=$'\e[31m'; c_0=$'\e[0m'
info() { printf "%s==>%s %s\n" "$c_g" "$c_0" "$*"; }
warn() { printf "%s!!%s %s\n"  "$c_y" "$c_0" "$*"; }
err()  { printf "%s✗%s %s\n"   "$c_r" "$c_0" "$*" >&2; }

# ── claude-usage backend (opt-in) ───────────────────────────────
# Installs the script + systemd timer that feed the Claude quota widget.
# It reads the OAuth token Claude Code already stores (~/.claude/.credentials.json)
# and queries the same endpoint that powers Claude Code's `/usage` — no browser,
# no cookie, no extra deps, 0 tokens. Any failure here only warns; it never
# aborts the bar install.
install_claude_backend() {
  local src="$1"                              # repo root (temp clone)
  local bindst="$HOME/.local/bin"
  local unitdst="$HOME/.config/systemd/user"

  command -v python3 >/dev/null 2>&1 || { err "python3 missing — skipping Claude backend"; return 1; }
  [[ -f "$HOME/.claude/.credentials.json" ]] || \
    warn "No Claude Code OAuth credentials yet — run 'claude' and log in; the widget fills once a session has run."

  # migrate away from any older split scripts/units (cookie/calc)
  systemctl --user disable --now claude-usage-cookie.timer claude-usage-calc.timer >/dev/null 2>&1 || true
  rm -f "$unitdst"/claude-usage-cookie.* "$unitdst"/claude-usage-calc.* \
        "$bindst"/claude-usage-cookie "$bindst"/claude-usage-calc

  mkdir -p "$bindst" "$unitdst"
  install -m 755 "$src/scripts/claude-usage"          "$bindst/claude-usage"
  install -m 644 "$src/systemd/claude-usage.service"   "$unitdst/claude-usage.service"
  install -m 644 "$src/systemd/claude-usage.timer"     "$unitdst/claude-usage.timer"

  systemctl --user daemon-reload
  systemctl --user enable --now claude-usage.timer >/dev/null 2>&1 || true
  "$bindst/claude-usage" >/dev/null 2>&1 || true   # prime the cache now

  info "Claude usage backend installed (exact 5h + 7d via Claude Code's own token, 0 tokens)"
}

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
fontmiss=()
fc-list | grep -qi "JetBrainsMono Nerd"  || fontmiss+=("JetBrainsMono Nerd Font")
fc-list | grep -qi "Material Symbols"    || fontmiss+=("Material Symbols Rounded")
if ((${#fontmiss[@]})); then
  warn "Missing fonts: ${fontmiss[*]}"
  warn "The bar needs these to display icons correctly."
  if [[ -z "$WANT_VERSION" ]]; then
    read -p "Install missing fonts? [Y/n] " ans </dev/tty || true
    case "${ans,,}" in n|no) err "Fonts required — aborting."; exit 1 ;; esac
  fi
  if ! fc-list | grep -qi "JetBrainsMono Nerd"; then
    info "Installing ttf-jetbrains-mono-nerd..."
    sudo pacman -S --noconfirm ttf-jetbrains-mono-nerd
  fi
  if ! fc-list | grep -qi "Material Symbols"; then
    info "Installing ttf-material-symbols-variable..."
    sudo pacman -S --noconfirm ttf-material-symbols-variable
  fi
fi

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

# ── 4. install ──────────────────────────────────────────────────
# back up only a FOREIGN config (no .qsrise marker). Re-installing our own
# bar just replaces it — no redundant backups.
if [[ -d "$DEST" ]]; then
  if [[ -e "$DEST/.qsrise" ]]; then
    rm -rf "$DEST"
  else
    bak="$DEST.bak.$(date +%Y%m%d-%H%M%S)"
    info "Backing up your existing config → $bak"
    mv "$DEST" "$bak"
  fi
fi
mkdir -p "$DEST"
cp -r "$tmp/repo/versions/$choice/." "$DEST/"
echo "$choice" > "$DEST/.qsrise"
info "Installed '${c_b}$choice${c_0}' → $DEST"

# ── 5. theme hook (live color updates on Omarchy theme switch) ──
hookdst="$HOME/.config/omarchy/hooks/theme-set.d"
if [[ -f "$tmp/repo/hooks/50-quickshell-bar.sh" ]]; then
  mkdir -p "$hookdst"
  install -m 0755 "$tmp/repo/hooks/50-quickshell-bar.sh" "$hookdst/50-quickshell-bar.sh"
  info "Theme hook installed (bar follows Omarchy themes)"
fi

# ── 6. stop waybar (would overlap) and start the bar now ────────
pkill -x waybar 2>/dev/null && info "Stopped waybar (use the panel/control to manage)" || true
# stop existing bar (supports both -c bar and -p $DEST modes)
pkill -f "qs.*-c bar" 2>/dev/null || true
pkill -f "quickshell -p $DEST" 2>/dev/null || true
sleep 0.3
setsid quickshell -p "$DEST" >/dev/null 2>&1 &
info "Bar started — try it out."

# ── 7. autostart hint ────────────────────────────────────────────
info "Autostart at login via Omarchy post-boot hook:"
RAW="https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main"
printf "  ${c_b}curl -fsSL -o %s/quickshell-rise %s/contrib/post-boot.d/quickshell-rise${c_0}\n" \
  "\$HOME/.config/omarchy/hooks/post-boot.d" "$RAW"
printf "  ${c_b}chmod +x %s/quickshell-rise${c_0}\n" \
  "\$HOME/.config/omarchy/hooks/post-boot.d"
printf "  ${c_b}rm -f %s/quickshell-rise${c_0}  # to remove\n" \
  "\$HOME/.config/omarchy/hooks/post-boot.d"

# ── 8. claude-usage backend (opt-in; never blocks the bar install) ──
do_claude="$WANT_CLAUDE"
if [[ -z "$do_claude" ]]; then
  if [[ -t 0 || -e /dev/tty ]]; then
    read -p "Install the Claude usage backend for the quota widget (exact 5h + 7d, 0 tokens)? [y/N] " ans </dev/tty || ans=""
    case "${ans,,}" in y|yes) do_claude="yes" ;; *) do_claude="no" ;; esac
  else
    do_claude="no"
  fi
fi
if [[ "$do_claude" == "yes" ]]; then
  install_claude_backend "$tmp/repo" || warn "Claude backend setup incomplete — the bar is installed and fine; re-run with --claude-backend to retry."
else
  info "Skipped Claude usage backend (the quota widget stays hidden until it's installed)."
fi

info "${c_b}Done — enjoy!${c_0}"
