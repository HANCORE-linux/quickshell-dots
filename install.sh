#!/usr/bin/env bash
# Quickshell Rise — one-command installer
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh)
#   bash <(curl -fsSL .../install.sh) V1          # select the initial UI variant non-interactively
#   bash <(curl -fsSL .../install.sh) V1 --autostart
# Autostart via Omarchy post-boot hook (opt-in).
set -euo pipefail

REPO_URL="https://github.com/HANCORE-linux/quickshell-dots.git"
DEST="$HOME/.config/quickshell/bar"
QSR_STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-rise"
QSR_VARIANT_STATE="$QSR_STATE_ROOT/active-variant"
QSR_LEGACY_VARIANT_STATE="$QSR_STATE_ROOT/active-version"

# args: optional initial UI variant + flags
WANT_VERSION=""
WANT_AUTOSTART="" # "" = leave unchanged and print hint, "yes" = install hook, "no" = remove hook
WANT_CLAUDE=""   # "" = ask interactively, "yes"/"no" = non-interactive
for a in "$@"; do
  case "$a" in
    --autostart)          WANT_AUTOSTART="yes" ;;
    --no-autostart)       WANT_AUTOSTART="no"  ;;
    --claude-backend|--ai-backend)       WANT_CLAUDE="yes" ;;
    --no-claude-backend|--no-ai-backend) WANT_CLAUDE="no"  ;;
    *) WANT_VERSION="$a" ;;
  esac
done

c_b=$'\e[1m'; c_g=$'\e[32m'; c_y=$'\e[33m'; c_r=$'\e[31m'; c_0=$'\e[0m'
info() { printf "%s==>%s %s\n" "$c_g" "$c_0" "$*"; }
warn() { printf "%s!!%s %s\n"  "$c_y" "$c_0" "$*"; }
err()  { printf "%s✗%s %s\n"   "$c_r" "$c_0" "$*" >&2; }

# ── claude-usage backend (opt-in AI usage backend) ──────────────
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

# ── codex-usage backend (opt-in; pairs with the AI usage widget) ─
# Installs the script + systemd timer that feed the Codex side of the quota
# widget. It reads the authoritative rate limits the Codex CLI exposes over its
# local app-server JSON-RPC (account/rateLimits/read) — no browser, no scraping,
# 0 tokens. Any failure here only warns; it never aborts the bar install.
install_codex_backend() {
  local src="$1"                              # repo root (temp clone)
  local bindst="$HOME/.local/bin"
  local unitdst="$HOME/.config/systemd/user"

  command -v python3 >/dev/null 2>&1 || { err "python3 missing — skipping Codex backend"; return 1; }
  command -v codex   >/dev/null 2>&1 || \
    warn "codex CLI not found in PATH — install it and run 'codex login'; the widget fills once Codex has run."

  mkdir -p "$bindst" "$unitdst"
  install -m 755 "$src/scripts/codex-usage"          "$bindst/codex-usage"
  install -m 644 "$src/systemd/codex-usage.service"   "$unitdst/codex-usage.service"
  install -m 644 "$src/systemd/codex-usage.timer"     "$unitdst/codex-usage.timer"

  systemctl --user daemon-reload
  systemctl --user enable --now codex-usage.timer >/dev/null 2>&1 || true
  "$bindst/codex-usage" >/dev/null 2>&1 || true   # prime the cache now

  info "Codex usage backend installed (Codex app-server RPC plus validated session-window fallback, 0 tokens)"
}

# ── opencode-usage backend (opt-in; pairs with the AI usage widget) ─
# Reads OpenCode's local SQLite usage DB and writes the shared AI usage cache.
# No network calls and no API tokens; if OpenCode has not run yet, the cache
# starts filling once ~/.local/share/opencode/opencode.db exists.
install_opencode_backend() {
  local src="$1"                              # repo root (temp clone)
  local bindst="$HOME/.local/bin"
  local unitdst="$HOME/.config/systemd/user"

  command -v python3 >/dev/null 2>&1 || { err "python3 missing — skipping OpenCode backend"; return 1; }
  if ! command -v opencode >/dev/null 2>&1 && [[ ! -e "$HOME/.local/share/opencode/opencode.db" ]]; then
    warn "opencode not found yet — install/run OpenCode; the widget fills once its local DB exists."
  fi

  mkdir -p "$bindst" "$unitdst"
  install -m 755 "$src/scripts/opencode-usage"          "$bindst/opencode-usage"
  install -m 644 "$src/systemd/opencode-usage.service"   "$unitdst/opencode-usage.service"
  install -m 644 "$src/systemd/opencode-usage.timer"     "$unitdst/opencode-usage.timer"

  systemctl --user daemon-reload
  systemctl --user enable --now opencode-usage.timer >/dev/null 2>&1 || true
  "$bindst/opencode-usage" >/dev/null 2>&1 || true   # prime the cache now

  info "OpenCode usage backend installed (local SQLite, configurable soft caps, 0 tokens)"
}

# ── shell self-updater (the in-bar update badge + apply) ────────
# Installs the check/apply scripts + systemd timer, and keeps a persistent FULL
# clone the updater pulls from (the install clone below is --depth 1, too shallow
# for a correct changelog / behind count). Any failure here only warns; it never
# aborts the bar install.
install_shell_updater() {
  local src="$1"                                   # repo root (temp clone) for the files
  local bindst="$HOME/.config/quickshell/bin"
  local unitdst="$HOME/.config/systemd/user"
  local repodir="$HOME/.local/share/quickshell-dots"

  if [[ -d "$repodir/.git" ]]; then
    git -C "$repodir" fetch --quiet origin || true
  else
    mkdir -p "$(dirname "$repodir")"
    git clone --quiet "$REPO_URL" "$repodir" || { err "Updater clone failed — skipping self-updater"; return 1; }
  fi

  mkdir -p "$bindst" "$unitdst"
  install -m 755 "$src/scripts/qs-barctl" "$bindst/qs-barctl"
  install -m 755 "$src/scripts/qs-proj" "$HOME/.local/bin/qs-proj"
  install -m 755 "$src/scripts/qs-shell-check-update.sh" "$bindst/qs-shell-check-update.sh"
  install -m 755 "$src/scripts/qs-shell-apply-update.sh" "$bindst/qs-shell-apply-update.sh"
  install -m 644 "$src/systemd/qs-shell-update-check.service" "$unitdst/qs-shell-update-check.service"
  install -m 644 "$src/systemd/qs-shell-update-check.timer"   "$unitdst/qs-shell-update-check.timer"

  systemctl --user daemon-reload
  systemctl --user enable --now qs-shell-update-check.timer >/dev/null 2>&1 || true
  "$bindst/qs-shell-check-update.sh" >/dev/null 2>&1 || true   # prime the state now

  info "Shell self-updater installed (badge appears when this repo has updates)"
}

# ── theme update helpers (checked state + pinned apply) ─────────
# Installs the helpers the ArchUpdaterPanel runs on demand. The check helper
# records exact base/target commits; the apply helper only fast-forwards to the
# recorded target after revalidating the repo and upstream identity.
install_theme_updater() {
  local src="$1"
  local bindst="$HOME/.config/quickshell/bin"
  local state="$HOME/.cache/qs-theme-updates.json"
  local t

  [[ -f "$src/scripts/qs-theme-update-check.sh" ]] || return 0
  [[ -f "$src/scripts/qs-theme-apply-update.sh" ]] || {
    err "Theme update apply helper missing — themes tab update action would be incomplete"
    return 1
  }

  mkdir -p "$bindst"
  install -m 755 "$src/scripts/qs-theme-update-check.sh" "$bindst/qs-theme-update-check.sh"
  install -m 755 "$src/scripts/qs-theme-apply-update.sh" "$bindst/qs-theme-apply-update.sh"
  if [[ ! -e "$state" ]]; then
    mkdir -p "$(dirname "$state")"
    t="$(mktemp -p "$(dirname "$state")" .qs-theme-updates.XXXXXX)"
    printf '{"checked":"","total":0,"reachable":0,"outdated":0,"localEdits":0,"degraded":false,"currentStale":false,"themes":[]}\n' > "$t"
    mv "$t" "$state"
  fi

  info "Theme update helpers installed (panel applies only checked theme commits)"
}

# ── 1. dependencies ─────────────────────────────────────────────
need=(qs git jq curl checkupdates flock lslocks md5sum readlink timeout setsid pkill systemd-run systemctl)
opt=(wpctl pactl pamixer brightnessctl upower powerprofilesctl bluetoothctl iwctl makoctl hypridle cava)
miss=()
for b in "${need[@]}"; do command -v "$b" >/dev/null 2>&1 || miss+=("$b"); done
if ((${#miss[@]})); then
  err "Missing required: ${miss[*]}"
  warn "On Arch:  sudo pacman -S quickshell git jq curl pacman-contrib coreutils util-linux procps-ng"
  exit 1
fi
optmiss=()
for b in "${opt[@]}"; do command -v "$b" >/dev/null 2>&1 || optmiss+=("$b"); done
((${#optmiss[@]})) && warn "Optional tools missing (some widgets disabled): ${optmiss[*]}"
fontmiss=()
# capture once: `fc-list | grep -q` can SIGPIPE-fail under `set -o pipefail`
fonts="$(fc-list)"
[[ "$fonts" == *"JetBrainsMono Nerd"* ]] || fontmiss+=("JetBrainsMono Nerd Font")
[[ "$fonts" == *"Material Symbols"*  ]] || fontmiss+=("Material Symbols Rounded")
if ((${#fontmiss[@]})); then
  warn "Missing fonts: ${fontmiss[*]}"
  warn "The bar needs these to display icons correctly."
  if [[ -z "$WANT_VERSION" ]]; then
    read -r -p "Install missing fonts? [Y/n] " ans </dev/tty || ans=""   # no tty → empty, not unset (set -u)
    case "${ans,,}" in n|no) err "Fonts required — aborting."; exit 1 ;; esac
  fi
  if [[ "$fonts" != *"JetBrainsMono Nerd"* ]]; then
    info "Installing ttf-jetbrains-mono-nerd..."
    sudo pacman -S --noconfirm ttf-jetbrains-mono-nerd
  fi
  if [[ "$fonts" != *"Material Symbols"* ]]; then
    info "Installing ttf-material-symbols-variable..."
    sudo pacman -S --noconfirm ttf-material-symbols-variable
  fi
fi

# ── 2. fetch repo ───────────────────────────────────────────────
tmp="$(mktemp -d)"
stage=""
restore_src=""
install_swapped=false
install_committed=false
variant_state_existed=false
variant_state_previous=""
if [[ -f "$QSR_VARIANT_STATE" ]]; then
  variant_state_existed=true
  variant_state_previous="$(cat "$QSR_VARIANT_STATE" 2>/dev/null || true)"
fi
cleanup_install() {
  [[ -n "${stage:-}" && -d "$stage" ]] && rm -rf "$stage"
  if [[ "${install_swapped:-false}" == true && "${install_committed:-false}" != true ]]; then
    # Disarm before cleanup work so a secondary failure cannot repeat the swap.
    install_swapped=false
    if declare -F qsr_stop_bar_instances >/dev/null 2>&1; then
      qsr_stop_bar_instances >/dev/null 2>&1 || true
    fi
    [[ -d "$DEST" ]] && rm -rf "$DEST"
    if [[ -n "${restore_src:-}" && -d "$restore_src" ]]; then
      mv "$restore_src" "$DEST" 2>/dev/null || true
    fi
    mkdir -p "$QSR_STATE_ROOT" 2>/dev/null || true
    if [[ "${variant_state_existed:-false}" == true ]]; then
      state_restore_tmp="$(mktemp -p "$QSR_STATE_ROOT" .active-variant.restore.XXXXXX 2>/dev/null || true)"
      if [[ -n "$state_restore_tmp" ]]; then
        printf '%s\n' "$variant_state_previous" > "$state_restore_tmp"
        chmod 0600 "$state_restore_tmp" 2>/dev/null || true
        mv -f "$state_restore_tmp" "$QSR_VARIANT_STATE" 2>/dev/null || true
      fi
    else
      rm -f "$QSR_VARIANT_STATE"
    fi
    if [[ -f "$DEST/shell.qml" && "${stock_provider_restored:-false}" != true ]] \
        && declare -F qsr_start_bar >/dev/null 2>&1; then
      qsr_start_bar >/dev/null 2>&1 || true
    fi
  fi
  if [[ -n "${restore_src:-}" && -d "$restore_src" && ! -e "$DEST" ]]; then
    mv "$restore_src" "$DEST" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup_install EXIT
info "Downloading…"
git clone --depth 1 "$REPO_URL" "$tmp/repo" >/dev/null 2>&1

# Load the same bounded lifecycle helper used by the post-boot hook. It reads
# Quickshell's registry directly and deliberately never invokes `qs list`.
runtime_helper="$tmp/repo/contrib/post-boot.d/quickshell-rise"
[[ -r "$runtime_helper" ]] || { err "Runtime helper missing from repository"; exit 1; }
export QSR_CONFIG_PATH="$DEST/shell.qml"
export QSR_RUNTIME_LIB_ONLY=1
# shellcheck source=/dev/null
source "$runtime_helper"
unset QSR_RUNTIME_LIB_ONLY
qsr_export_omarchy_path

autostart_dir="$HOME/.config/omarchy/hooks/post-boot.d"
autostart_hook="$autostart_dir/quickshell-rise"
hook_was_installed=false
[[ -f "$autostart_hook" ]] && hook_was_installed=true

quattro_mode=false
qsr_has_quattro && quattro_mode=true

# An interactive Quattro install without an existing Rise hook can opt into the
# existing autostart path.
# Probe /dev/tty separately: checking only that its device node exists is unsafe
# without a controlling TTY, while redirecting read's stderr would hide -p.
if [[ "$quattro_mode" == true && -z "$WANT_AUTOSTART" && "$hook_was_installed" == false ]]; then
  if : 2>/dev/null </dev/tty; then
    if read -r -p "Omarchy Quattro detected. Hide the stock bar and start Rise automatically at login? [Y/n] " quattro_autostart_answer </dev/tty; then
      case "${quattro_autostart_answer,,}" in
        ""|y|yes) WANT_AUTOSTART="yes" ;;
        n|no) ;;
      esac
    fi
  fi
fi

# Quattro's bar-off flag persists across logins. Only take ownership when the
# user requested autostart or already had the Rise hook installed.
hide_stock_after_install=false
if [[ "$WANT_AUTOSTART" == "yes" || ( -z "$WANT_AUTOSTART" && "$hook_was_installed" == true ) ]]; then
  hide_stock_after_install=true
fi

payload="$tmp/repo/versions/V1"
[[ -f "$payload/shell.qml" && -f "$payload/VariantRoot.qml" \
   && -f "$payload/variants/V2/VariantRoot.qml" \
   && -x "$payload/core/qs-system-update.sh" ]] || {
  err "Integrated V1/V2 payload is incomplete"
  exit 1
}

versions=(V1 V2)

read_saved_variant() {
  local candidate="" state_file status=""

  [[ -e "$DEST/.qsrise" ]] || return 1
  for state_file in "$QSR_VARIANT_STATE" "$QSR_LEGACY_VARIANT_STATE"; do
    [[ -r "$state_file" ]] || continue
    candidate="$(tr -d '[:space:]' < "$state_file" 2>/dev/null || true)"
    case "${candidate,,}" in
      v1) printf 'V1\n'; return 0 ;;
      v2) printf 'V2\n'; return 0 ;;
    esac
  done

  if [[ -x "$HOME/.config/quickshell/bin/qs-barctl" ]]; then
    status="$("$HOME/.config/quickshell/bin/qs-barctl" status 2>/dev/null || true)"
    case "${status,,}" in
      v1) printf 'V1\n'; return 0 ;;
      v2) printf 'V2\n'; return 0 ;;
    esac
  fi
  return 1
}

write_initial_variant() {
  local normalized="${1,,}" state_tmp

  mkdir -p "$QSR_STATE_ROOT"
  state_tmp="$(mktemp -p "$QSR_STATE_ROOT" .active-variant.XXXXXX)"
  chmod 0600 "$state_tmp"
  printf '%s\n' "$normalized" > "$state_tmp"
  mv -f "$state_tmp" "$QSR_VARIANT_STATE"
}

verify_selected_variant() {
  local expected="${choice,,}" actual=""
  local installer_barctl="$tmp/repo/scripts/qs-barctl"

  [[ -x "$installer_barctl" ]] || {
    err "Lifecycle controller missing from the downloaded installation generation."
    return 1
  }
  if ! QSR_CONFIG="$DEST/shell.qml" "$installer_barctl" start-wait; then
    err "The integrated bar did not reach lifecycle ready=true."
    return 1
  fi
  if ! actual="$(QSR_CONFIG="$DEST/shell.qml" "$installer_barctl" status)"; then
    err "The integrated bar did not remain in a healthy active state (status: ${actual:-unknown})."
    return 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    err "Requested '$expected', but the integrated host became ready as '$actual'."
    return 1
  fi
}

# ── 3. choose initial UI variant ────────────────────────────────
choice="$WANT_VERSION"
if [[ -z "$choice" ]]; then
  if choice="$(read_saved_variant)"; then
    info "Keeping previously active UI variant '${c_b}$choice${c_0}'"
  else
    echo "${c_b}Available UI variants:${c_0}"
    select v in "${versions[@]}"; do [[ -n "$v" ]] && { choice="$v"; break; }; done
  fi
fi
choice="${choice^^}"
printf '%s\n' "${versions[@]}" | grep -qx "$choice" || { err "Unknown UI variant: $choice"; exit 1; }

# ── 4. install ──────────────────────────────────────────────────
# back up only a FOREIGN config (no .qsrise marker). Re-installing our own bar
# uses a same-parent stage/rename so custom quotes are never held only in /tmp.
mkdir -p "$(dirname "$DEST")"
# Sweep install stages orphaned by SIGKILL / power loss before creating a new one.
rm -rf "$(dirname "$DEST")"/.qs-install-stage.* 2>/dev/null || true
ts="$(date +%Y%m%d-%H%M%S)"
stage="$(mktemp -d -p "$(dirname "$DEST")" .qs-install-stage.XXXXXX)"
cp -r "$payload/." "$stage/"
# .qsrise identifies the single update payload. V1 now contains the common
# bootstrap plus both isolated UI variants; active-variant selects the UI.
printf 'V1\n' > "$stage/.qsrise"

# On a Quattro reinstall, return our persistent bar-off state before touching
# the running Rise instance. If any later step fails, a known-good bar remains.
if [[ "$quattro_mode" == true ]] && qsr_owns_stock_bar_hide; then
  if ! qsr_release_owned_stock_bar; then
    err "Could not restore the Omarchy stock bar; installation aborted before replacing anything."
    exit 1
  fi
  info "Temporarily restored the Omarchy stock bar for the safe reinstall."
fi

# A current integrated controller can stop its exact configured instance without
# touching any other Quickshell application. Older dual-process controllers do
# not expose stop-wait; the registry helper below can still stop a legacy V1 at
# $DEST. If an old V2 at a different project path survives, fail before swapping
# files instead of creating a second bar.
installed_barctl="$HOME/.config/quickshell/bin/qs-barctl"
controller_seen=false
if [[ -x "$installed_barctl" ]]; then
  controller_status="$("$installed_barctl" status 2>/dev/null || true)"
  case "$controller_status" in
    v1|v2|switching:*|degraded:*|duplicate:*)
      controller_seen=true
      "$installed_barctl" stop-wait >/dev/null 2>&1 || true
      ;;
  esac
fi

if ! qsr_stop_bar_instances; then
  err "Could not stop all registered Rise instances; installation aborted before replacing the config."
  exit 1
fi
if [[ "$controller_seen" == true ]]; then
  controller_status="$("$installed_barctl" status 2>/dev/null || true)"
  case "$controller_status" in
    ""|stopped) ;;
    *)
      err "A previous Rise controller still reports '$controller_status'; stop that legacy bar before migrating."
      exit 1
      ;;
  esac
fi

if [[ -d "$DEST" ]]; then
  if [[ -e "$DEST/.qsrise" ]]; then
    if [[ -f "$DEST/quotes.txt" ]]; then
      cp -p "$DEST/quotes.txt" "$stage/quotes.txt"
      info "Preserved custom quotes.txt"
    fi
    restore_src="$DEST.old.$ts"
    mv "$DEST" "$restore_src"
  else
    bak="$DEST.bak.$ts"
    info "Backing up your existing config → $bak"
    mv "$DEST" "$bak"
    restore_src="$bak"
  fi
fi
mv "$stage" "$DEST"
stage=""
install_swapped=true
write_initial_variant "$choice"
info "Installed integrated V1/V2 shell with '${c_b}$choice${c_0}' active → $DEST"

# ── 4b. ArchUpdater security gate (pre-install package verdicts) ─
# Pure bash, no extra deps. The weekly fetch timer keeps the known-infected
# list current; without any list the updater panel fail-closes to
# "protection limited" instead of claiming packages are clean.
if [[ -f "$tmp/repo/scripts/qs-arch-security-gate.sh" ]]; then
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$tmp/repo/scripts/qs-arch-security-gate.sh" "$HOME/.local/bin/qs-arch-security-gate.sh"
  install -m 755 "$tmp/repo/scripts/qs-arch-update-check.sh" "$HOME/.local/bin/qs-arch-update-check.sh"
  install -m 755 "$tmp/repo/scripts/qs-arch-apply-update.sh" "$HOME/.local/bin/qs-arch-apply-update.sh"
  if [[ -f "$tmp/repo/scripts/qs-aur-blacklist-fetch.sh" ]]; then
    install -m 755 "$tmp/repo/scripts/qs-aur-blacklist-fetch.sh" "$HOME/.local/bin/qs-aur-blacklist-fetch.sh"
    mkdir -p "$HOME/.config/systemd/user"
    install -m 644 "$tmp/repo/systemd/qs-aur-blacklist-fetch.service" "$HOME/.config/systemd/user/qs-aur-blacklist-fetch.service"
    install -m 644 "$tmp/repo/systemd/qs-aur-blacklist-fetch.timer"   "$HOME/.config/systemd/user/qs-aur-blacklist-fetch.timer"
    systemctl --user daemon-reload
    systemctl --user enable --now qs-aur-blacklist-fetch.timer >/dev/null 2>&1 || true
    "$HOME/.local/bin/qs-aur-blacklist-fetch.sh" >/dev/null 2>&1 || true   # prime the list now
  fi
  info "ArchUpdater security gate installed (weekly blacklist refresh)"
fi

# ── 4c. Theme update helpers (panel "Check themes" + pinned apply) ─────
install_theme_updater "$tmp/repo" || warn "Theme update helpers setup incomplete — the bar is fine; the themes tab just cannot apply updates yet."

# ── 5. theme hook (live color updates on Omarchy theme switch) ──
hookdst="$HOME/.config/omarchy/hooks/theme-set.d"
if [[ -f "$tmp/repo/hooks/50-quickshell-bar.sh" ]]; then
  mkdir -p "$hookdst"
  install -m 0755 "$tmp/repo/hooks/50-quickshell-bar.sh" "$hookdst/50-quickshell-bar.sh"
  info "Theme hook installed (bar follows Omarchy themes)"
fi

# ── 6. start and verify Rise before changing the stock provider ─
# Use the controller from the same downloaded generation as the staged QML. Its
# start-wait contract validates lifecycle.ready(), a stable instance identity and
# exactly one integrated bar. The explicit status check also rejects a healthy V1
# fallback when V2 was requested (and vice versa).
if ! verify_selected_variant; then
  # This only restores a bar-off state previously owned by Rise. A state set by
  # the user or another tool is never claimed or changed automatically.
  if [[ "$quattro_mode" == true ]] && ! qsr_release_owned_stock_bar; then
    warn "Rise did not start and its previous Omarchy bar state could not be restored."
  fi
  err "Rise did not become ready; the existing stock-bar state was preserved or restored when owned by Rise."
  exit 1
fi
info "Bar started with '$choice' and verified through the variant lifecycle."

# The new generation and requested variant are now healthy. Only now discard an
# owned previous generation; foreign .bak backups remain available to uninstall.
install_committed=true
install_swapped=false
if [[ -n "$restore_src" && "$restore_src" == "$DEST.old."* ]]; then
  rm -rf "$restore_src"
fi
restore_src=""

if [[ "$quattro_mode" != true ]]; then
  # Omarchy 3.8.x and generic Waybar sessions retain their previous behavior,
  # but Waybar is stopped only after Rise has proven healthy.
  pkill -x waybar 2>/dev/null && info "Stopped waybar (use the panel/control to manage)" || true
fi

# ── 6b. shell self-updater (never blocks the bar install) ───────
install_shell_updater "$tmp/repo" || warn "Self-updater setup incomplete — the bar is fine; the update badge just won't appear."

# ── 7. autostart hook / hint ─────────────────────────────────────
RAW="https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main"
case "$WANT_AUTOSTART" in
  yes)
    if command -v omarchy >/dev/null 2>&1; then
      mkdir -p "$autostart_dir"
      install -m 0755 "$runtime_helper" "$autostart_hook"
      info "Autostart hook installed → $autostart_hook"
    else
      warn "--autostart uses Omarchy's hook system, which is unavailable here; Rise still runs for this session."
    fi
    ;;
  no)
    rm -f "$autostart_hook"
    info "Autostart hook removed → $autostart_hook"
    ;;
  *)
    if [[ "$hook_was_installed" == true ]] && command -v omarchy >/dev/null 2>&1; then
      install -m 0755 "$runtime_helper" "$autostart_hook"
      info "Existing autostart hook refreshed → $autostart_hook"
    elif command -v omarchy >/dev/null 2>&1; then
      info "Autostart at login via Omarchy post-boot hook:"
      printf "  ${c_b}curl -fsSL -o %s/quickshell-rise %s/contrib/post-boot.d/quickshell-rise${c_0}\n" \
        "\$HOME/.config/omarchy/hooks/post-boot.d" "$RAW"
      printf "  ${c_b}chmod +x %s/quickshell-rise${c_0}\n" \
        "\$HOME/.config/omarchy/hooks/post-boot.d"
      printf "  ${c_b}rm -f %s/quickshell-rise${c_0}  # to remove\n" \
        "\$HOME/.config/omarchy/hooks/post-boot.d"
    else
      info "No Omarchy hook system detected; configure autostart with your desktop's normal session mechanism."
    fi
    ;;
esac

if [[ "$quattro_mode" == true ]]; then
  if [[ "$hide_stock_after_install" == true ]]; then
    if qsr_hide_stock_bar_owned; then
      if qsr_owns_stock_bar_hide; then
        info "Omarchy Quattro stock bar hidden (Rise owns this bar-off state)."
      else
        info "Omarchy Quattro stock bar was already hidden; its existing ownership was left unchanged."
      fi
    else
      qsr_warn_stock_bar_hide_failure
    fi
  else
    if qsr_stock_bar_hidden; then
      info "Omarchy Quattro stock bar was already hidden and was left unchanged; Rise does not own that state."
    else
      info "Omarchy Quattro stock bar left visible; use --autostart to let Rise manage it persistently."
    fi
  fi
fi

# ── 8. AI usage backends (opt-in; never block the bar install) ──
do_claude="$WANT_CLAUDE"
if [[ -z "$do_claude" ]]; then
  if [[ -t 0 || -e /dev/tty ]]; then
    read -r -p "Install the AI usage backend for the quota widget (Claude + Codex + OpenCode, 0 tokens)? [y/N] " ans </dev/tty || ans=""
    case "${ans,,}" in y|yes) do_claude="yes" ;; *) do_claude="no" ;; esac
  else
    do_claude="no"
  fi
fi
if [[ "$do_claude" == "yes" ]]; then
  install_claude_backend "$tmp/repo" || warn "Claude backend setup incomplete — the bar is installed and fine; re-run with --ai-backend to retry."
  # Codex side of the same AI usage widget — installed alongside when present.
  if command -v codex >/dev/null 2>&1; then
    install_codex_backend "$tmp/repo" || warn "Codex backend setup incomplete — re-run with --ai-backend to retry."
  else
    info "Skipped Codex usage backend (codex CLI not found; the bar still shows Claude)."
  fi
  install_opencode_backend "$tmp/repo" || warn "OpenCode backend setup incomplete — re-run with --ai-backend to retry."
else
  info "Skipped AI usage backend (the quota widget stays hidden until it's installed)."
fi

info "${c_b}Done — enjoy!${c_0}"
