#!/usr/bin/env bash
# Quickshell Rise — uninstaller (version-agnostic; removes whatever is installed)
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/uninstall.sh)
set -euo pipefail

DEST="$HOME/.config/quickshell/bar"

c_g=$'\e[32m'; c_y=$'\e[33m'; c_0=$'\e[0m'
info() { printf "%s==>%s %s\n" "$c_g" "$c_0" "$*"; }
warn() { printf "%s!!%s %s\n"  "$c_y" "$c_0" "$*"; }

# Bounded Rise lifecycle helpers. The uninstaller is intentionally standalone,
# so this small subset is kept here instead of depending on an installed hook.
# It reads the Quickshell registry directly and never invokes `qs list`.
QSR_CONFIG_PATH="$DEST/shell.qml"
QSR_RUNTIME_ROOT="${QSR_RUNTIME_ROOT:-${XDG_RUNTIME_DIR:-/run/user/$UID}/quickshell}"
QSR_PROC_ROOT="${QSR_PROC_ROOT:-/proc}"
QSR_STATE_ROOT="${QSR_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-rise}"
QSR_BAR_MARKER="${QSR_BAR_MARKER:-$QSR_STATE_ROOT/owns-omarchy-bar-off}"
QSR_BAR_PENDING="${QSR_BAR_PENDING:-$QSR_BAR_MARKER.pending}"
QSR_TOGGLE_ROOT="${QSR_TOGGLE_ROOT:-$HOME/.local/state/omarchy/toggles}"
QSR_STOP_ROUNDS="${QSR_STOP_ROUNDS:-60}"
QSR_STABLE_ROUNDS="${QSR_STABLE_ROUNDS:-5}"
QSR_POLL_INTERVAL="${QSR_POLL_INTERVAL:-0.1}"
QSR_COMMAND_TIMEOUT="${QSR_COMMAND_TIMEOUT:-4}"

qsr_export_omarchy_path() {
  if command -v omarchy-shell >/dev/null 2>&1 && [[ -d /usr/share/omarchy ]]; then
    export OMARCHY_PATH=/usr/share/omarchy
  else
    export OMARCHY_PATH="$HOME/.local/share/omarchy"
  fi
}

qsr_has_quattro() {
  command -v omarchy >/dev/null 2>&1 && command -v omarchy-toggle-bar >/dev/null 2>&1
}

qsr_config_registry_dir() {
  local path_id

  path_id="$(printf '%s' "$QSR_CONFIG_PATH" | md5sum 2>/dev/null)" || return 1
  path_id="${path_id%% *}"
  [[ $path_id =~ ^[0-9a-f]{32}$ ]] || return 1
  printf '%s/by-path/%s\n' "$QSR_RUNTIME_ROOT" "$path_id"
}

qsr_pid_holds_lock() {
  local pid="$1" lock_path="$2" process_fd target

  for process_fd in "$QSR_PROC_ROOT/$pid/fd/"*; do
    [[ -e $process_fd || -L $process_fd ]] || continue
    target="$(readlink -f "$process_fd" 2>/dev/null)" || continue
    [[ $target == "$lock_path" ]] && return 0
  done
  return 1
}

qsr_live_bar_pids() {
  local config_dir instance_link instance_dir
  local lock_pid lock_path locks_text candidate candidate_exe process_exe linked_instance
  local -A allowed_instances=() expected_exes=() emitted_pids=()

  config_dir="$(qsr_config_registry_dir)" || return 1
  [[ -d $config_dir ]] || return 0
  command -v lslocks >/dev/null 2>&1 || return 1

  # Normal instances run as `qs`; Quickshell's crash handler may relaunch the
  # same config as a bare `quickshell` process with no original CLI arguments.
  for candidate in qs quickshell; do
    candidate_exe="$(command -v "$candidate" 2>/dev/null)" || continue
    candidate_exe="$(readlink -f "$candidate_exe" 2>/dev/null)" || continue
    expected_exes["$candidate_exe"]=1
  done
  ((${#expected_exes[@]} > 0)) || return 1

  for instance_link in "$config_dir/"*; do
    [[ -L $instance_link ]] || continue
    instance_dir="$(readlink -f "$instance_link" 2>/dev/null)" || continue
    [[ $instance_dir == "$QSR_RUNTIME_ROOT/by-id/"* ]] || continue
    allowed_instances["$instance_dir"]=1
  done

  locks_text="$(timeout "$QSR_COMMAND_TIMEOUT" lslocks -n -o PID,PATH 2>/dev/null)" || return 1
  while read -r lock_pid lock_path; do
    [[ $lock_pid =~ ^[0-9]+$ ]] || continue
    instance_dir="${lock_path%/instance.lock}"
    [[ $lock_path == "$instance_dir/instance.lock" ]] || continue
    [[ -n ${allowed_instances[$instance_dir]+x} ]] || continue
    [[ -d $QSR_PROC_ROOT/$lock_pid ]] || continue
    process_exe="$(readlink -f "$QSR_PROC_ROOT/$lock_pid/exe" 2>/dev/null)" || continue
    [[ -n ${expected_exes[$process_exe]+x} ]] || continue
    linked_instance="$(readlink -f "$QSR_RUNTIME_ROOT/by-pid/$lock_pid" 2>/dev/null)" || continue
    [[ $linked_instance == "$instance_dir" ]] || continue
    qsr_pid_holds_lock "$lock_pid" "$lock_path" || continue
    [[ -n ${emitted_pids[$lock_pid]+x} ]] && continue
    emitted_pids[$lock_pid]=1
    printf '%s\n' "$lock_pid"
  done <<< "$locks_text"
}

qsr_term_pid() {
  kill -TERM "$1" 2>/dev/null || true
}

qsr_stop_registered_bars() {
  local rounds="${1:-$QSR_STOP_ROUNDS}" stable="${2:-$QSR_STABLE_ROUNDS}"
  local attempt quiet=0 pid pids_text
  local -a pids=()

  for ((attempt = 0; attempt < rounds; attempt++)); do
    pids_text="$(qsr_live_bar_pids)" || return 1
    pids=()
    [[ -n $pids_text ]] && mapfile -t pids <<< "$pids_text"
    if ((${#pids[@]} == 0)); then
      ((quiet += 1))
      ((quiet >= stable)) && return 0
    else
      quiet=0
      for pid in "${pids[@]}"; do
        qsr_term_pid "$pid"
      done
    fi
    sleep "$QSR_POLL_INTERVAL"
  done

  pids_text="$(qsr_live_bar_pids)" || return 1
  pids=()
  [[ -n $pids_text ]] && mapfile -t pids <<< "$pids_text"
  ((${#pids[@]} == 0))
}

qsr_stop_legacy_patterns() {
  local config_dir="${QSR_CONFIG_PATH%/shell.qml}"

  pkill -f 'qs.*[[:space:]]-c[[:space:]]bar([[:space:]]|$)' 2>/dev/null || true
  pkill -f "quickshell -p $config_dir" 2>/dev/null || true
}

qsr_stop_bar_instances() {
  local rc=0

  qsr_stop_registered_bars "$QSR_STOP_ROUNDS" "$QSR_STABLE_ROUNDS" || true
  qsr_stop_legacy_patterns
  qsr_stop_registered_bars 30 "$QSR_STABLE_ROUNDS" || rc=1
  return "$rc"
}

qsr_stock_bar_hidden() {
  # Read the persistent capability flag directly. The helper command uses the
  # same nonzero status for "disabled" and operational errors, which cannot
  # prove the visible state needed before Rise is stopped.
  [[ -f $QSR_TOGGLE_ROOT/bar-off ]]
}

qsr_wait_for_stock_state() {
  local wanted="$1" attempt

  for ((attempt = 0; attempt < 20; attempt++)); do
    if [[ $wanted == hidden ]]; then
      qsr_stock_bar_hidden && return 0
    else
      qsr_stock_bar_hidden || return 0
    fi
    sleep "$QSR_POLL_INTERVAL"
  done
  return 1
}

qsr_set_stock_bar() {
  local wanted="$1" action

  qsr_has_quattro || return 1
  if [[ $wanted == hidden ]]; then
    qsr_stock_bar_hidden && return 0
    action=on  # Omarchy's `bar on` enables bar-off, therefore hides the bar.
  else
    qsr_stock_bar_hidden || return 0
    action=off # Omarchy's `bar off` removes bar-off, therefore shows the bar.
  fi

  timeout "$QSR_COMMAND_TIMEOUT" omarchy toggle bar "$action" >/dev/null 2>&1 || return 1
  qsr_wait_for_stock_state "$wanted"
}

qsr_owns_stock_bar_hide() {
  [[ -f $QSR_BAR_MARKER || -f $QSR_BAR_PENDING ]]
}

qsr_release_owned_stock_bar() {
  qsr_owns_stock_bar_hide || return 0
  qsr_set_stock_bar visible || return 1
  rm -f "$QSR_BAR_MARKER" "$QSR_BAR_PENDING"
}

# 0. ownership guard — refuse to touch ANYTHING if a config dir exists that we
# did not install (install.sh writes .qsrise). Checked before any removal so a
# foreign install aborts cleanly instead of losing helpers/units/lists first.
if [[ -d "$DEST" && ! -e "$DEST/.qsrise" ]]; then
  warn "$DEST was not installed by Quickshell Rise (no .qsrise marker) — leaving everything untouched."
  exit 1
fi

# 1. restore an owned Quattro provider before stopping Rise. If the toggle or
# its state verification fails, abort before removing any user-visible files.
qsr_export_omarchy_path
quattro_mode=false
qsr_has_quattro && quattro_mode=true
stock_provider_restored=false

if [[ "$quattro_mode" == true ]] && qsr_owns_stock_bar_hide; then
  if ! qsr_release_owned_stock_bar; then
    warn "Could not restore the Omarchy stock bar — leaving Rise and all installed files untouched."
    exit 1
  fi
  stock_provider_restored=true
  info "Restored the Omarchy Quattro stock bar before stopping Rise"
fi

if ! qsr_stop_bar_instances; then
  warn "Could not stop all registered Rise instances — leaving installed files untouched."
  exit 1
fi
info "Stopped the bar"

# 1b. remove the Claude usage backend, if it was installed (idempotent).
# Covers the current OAuth backend and any older split cookie/calc install.
unitdir="$HOME/.config/systemd/user"
bindir="$HOME/.local/bin"
if compgen -G "$unitdir/claude-usage*" >/dev/null 2>&1 || compgen -G "$bindir/claude-usage*" >/dev/null 2>&1; then
  # stop + disable timers AND services (covers a oneshot run that's mid-flight)
  systemctl --user disable --now \
    claude-usage.timer claude-usage-cookie.timer claude-usage-calc.timer >/dev/null 2>&1 || true
  systemctl --user stop \
    claude-usage.service claude-usage-cookie.service claude-usage-calc.service >/dev/null 2>&1 || true
  rm -f "$unitdir"/claude-usage.service       "$unitdir"/claude-usage.timer \
        "$unitdir"/claude-usage-calc.service   "$unitdir"/claude-usage-calc.timer \
        "$unitdir"/claude-usage-cookie.service "$unitdir"/claude-usage-cookie.timer
  rm -f "$bindir"/claude-usage "$bindir"/claude-usage-calc "$bindir"/claude-usage-cookie
  rm -f "$HOME/.cache/claude-usage.json" "$HOME/.cache/claude-usage-api.json" \
        "$HOME/.cache/claude-usage-skip" "$HOME/.cache/claude-usage-notified" \
        "$HOME/.cache/claude-usage-calibration.json"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user reset-failed 'claude-usage*' >/dev/null 2>&1 || true   # clear any ghost state
  # belt-and-suspenders: kill any lingering process (there shouldn't be one)
  pkill -f "$bindir/claude-usage" 2>/dev/null || true
  info "Removed Claude usage backend (script, timer, cache; nothing left running)"
fi

# 1b2. remove the Codex usage backend, if it was installed (idempotent).
# Pairs with the AI usage widget's Codex side (install_codex_backend in install.sh).
if compgen -G "$unitdir/codex-usage*" >/dev/null 2>&1 || compgen -G "$bindir/codex-usage*" >/dev/null 2>&1 \
   || [[ -e "$HOME/.cache/codex-usage.json" || -e "$HOME/.cache/codex-usage-activity.json" ]]; then
  systemctl --user disable --now codex-usage.timer >/dev/null 2>&1 || true
  systemctl --user stop codex-usage.service >/dev/null 2>&1 || true
  rm -f "$unitdir"/codex-usage.service "$unitdir"/codex-usage.timer
  rm -f "$bindir"/codex-usage
  rm -f "$HOME/.cache/codex-usage.json" "$HOME/.cache/codex-usage-activity.json"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user reset-failed 'codex-usage*' >/dev/null 2>&1 || true   # clear any ghost state
  pkill -f "$bindir/codex-usage" 2>/dev/null || true
  info "Removed Codex usage backend (script, timer, cache; nothing left running)"
fi

# 1b3. remove the OpenCode usage backend, if it was installed (idempotent).
if compgen -G "$unitdir/opencode-usage*" >/dev/null 2>&1 || compgen -G "$bindir/opencode-usage*" >/dev/null 2>&1; then
  systemctl --user disable --now opencode-usage.timer >/dev/null 2>&1 || true
  systemctl --user stop opencode-usage.service >/dev/null 2>&1 || true
  rm -f "$unitdir"/opencode-usage.service "$unitdir"/opencode-usage.timer
  rm -f "$bindir"/opencode-usage
  rm -f "$HOME/.cache/opencode-usage.json"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user reset-failed 'opencode-usage*' >/dev/null 2>&1 || true
  pkill -f "$bindir/opencode-usage" 2>/dev/null || true
  info "Removed OpenCode usage backend (script, timer, cache; nothing left running)"
fi

# 1c. remove the shell self-updater, if installed (idempotent).
qsbindir="$HOME/.config/quickshell/bin"
if compgen -G "$unitdir/qs-shell-update-check.*" >/dev/null 2>&1 \
   || [[ -e "$qsbindir/qs-shell-check-update.sh" || -e "$qsbindir/qs-barctl" ]]; then
  systemctl --user disable --now qs-shell-update-check.timer >/dev/null 2>&1 || true
  systemctl --user stop qs-shell-update-check.service >/dev/null 2>&1 || true
  rm -f "$unitdir"/qs-shell-update-check.service "$unitdir"/qs-shell-update-check.timer
  rm -f "$qsbindir"/qs-shell-check-update.sh \
        "$qsbindir"/qs-shell-apply-update.sh \
        "$qsbindir"/qs-barctl \
        "$bindir"/qs-proj
  rm -rf "$HOME/.cache/qs-shell" "$HOME/.local/share/quickshell-dots" \
         "${XDG_STATE_HOME:-$HOME/.local/state}/qs-shell"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user reset-failed 'qs-shell-update-check*' >/dev/null 2>&1 || true
  info "Removed shell self-updater (scripts, timer, cache, updater clone)"
fi

# 1c.1 remove the theme update checker, if installed (idempotent).
if [[ -e "$qsbindir/qs-theme-update-check.sh" || -e "$qsbindir/qs-theme-apply-update.sh" || -e "$HOME/.cache/qs-theme-updates.json" ]]; then
  rm -f "$qsbindir"/qs-theme-update-check.sh \
        "$qsbindir"/qs-theme-apply-update.sh \
        "$HOME/.cache/qs-theme-updates.json" \
        "$HOME/.cache/qs-theme-update.lock"
  info "Removed theme update helpers (scripts, cache, lock)"
fi

# 1d. remove the ArchUpdater security gate and package update helpers.
if [[ -f "$bindir/qs-arch-security-gate.sh" || -f "$bindir/qs-arch-update-check.sh" || -f "$bindir/qs-arch-apply-update.sh" || -f "$bindir/qs-aur-blacklist-fetch.sh" ]]; then
  systemctl --user disable --now qs-aur-blacklist-fetch.timer >/dev/null 2>&1 || true
  systemctl --user stop qs-aur-blacklist-fetch.service >/dev/null 2>&1 || true
  rm -f "$unitdir"/qs-aur-blacklist-fetch.service "$unitdir"/qs-aur-blacklist-fetch.timer
  rm -f "$bindir"/qs-arch-security-gate.sh \
        "$bindir"/qs-arch-update-check.sh \
        "$bindir"/qs-arch-apply-update.sh \
        "$bindir"/qs-aur-blacklist-fetch.sh
  # generated artifacts (cache, regenerated by the fetcher) — safe to remove
  rm -f "$HOME/.local/share/qs-aur-blacklist.txt" \
        "$HOME/.local/share/qs-aur-blacklist.txt.meta.json" \
        "$HOME/.local/share/qs-aur-blacklist.txt.pending" \
        "$HOME/.cache/qs-arch-updates.json" \
        "$HOME/.cache/qs-arch-gate.json"
  # the supplement is user-editable (ad-hoc additions survive refreshes) — keep it
  if [[ -f "$HOME/.local/share/qs-aur-blacklist.local.txt" ]]; then
    info "Kept blacklist supplement (qs-aur-blacklist.local.txt) — delete it manually to purge"
  fi
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user reset-failed 'qs-aur-blacklist-fetch*' >/dev/null 2>&1 || true
  info "Removed ArchUpdater security gate and package update helpers"
fi

# 2. remove the post-boot hook (if the user installed it)
boot="$HOME/.config/omarchy/hooks/post-boot.d/quickshell-rise"
[[ -f "$boot" ]] && { rm -f "$boot"; info "Removed post-boot hook"; }

# 3. remove the theme hook we installed
hook="$HOME/.config/omarchy/hooks/theme-set.d/50-quickshell-bar.sh"
[[ -f "$hook" ]] && { rm -f "$hook"; info "Removed theme hook"; }

# 4. remove the config — restore the most recent backup if one exists
# (ownership already verified at the top: $DEST is ours, or does not exist)
restored=false
if [[ -d "$DEST" ]]; then
  rm -rf "$DEST"
  latest="$(find "$(dirname "$DEST")" -maxdepth 1 -type d -name "$(basename "$DEST").bak.*" -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk 'NR == 1 {sub(/^[^ ]+ /, ""); print}')"
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

# 4b. remove saved bar settings (widget toggles, splits, slot order)
if compgen -G "$HOME/.cache/quickshell_*" >/dev/null 2>&1; then
  rm -f "$HOME/.cache/quickshell_widgets" "$HOME/.cache/quickshell_splits" \
        "$HOME/.cache/quickshell_barorder" "$HOME/.cache/quickshell_barsplits" \
        "$HOME/.cache/quickshell_widgets_v2" "$HOME/.cache/quickshell_barorder_v2"
  info "Removed saved bar settings (widget toggles, splits, slot order)"
fi

# 4c. remove small runtime caches owned by this bar
rm -f "$HOME/.cache/qs-reactor-event" "$HOME/.cache/qs-rise-notifications.json"

# 5. restore exactly one bar provider. When Rise owned Quattro's bar-off state,
# the stock bar is already visible; starting a foreign backup as well would
# create the double-bar failure this ownership marker is designed to prevent.
if [[ "$restored" == true && -f "$DEST/shell.qml" ]]; then
  if [[ "$stock_provider_restored" == true ]]; then
    info "Restored the previous config but left it stopped because the Omarchy stock bar is active"
  else
    setsid quickshell -p "$DEST" >/dev/null 2>&1 & disown
    info "Restarted quickshell from backup"
  fi
elif [[ "$quattro_mode" == true ]]; then
  if [[ "$stock_provider_restored" == true ]]; then
    info "Omarchy Quattro stock bar is active"
  else
    info "Left the Omarchy Quattro bar state unchanged (Rise did not own it)"
  fi
elif command -v omarchy >/dev/null 2>&1; then
  if omarchy restart waybar 2>/dev/null; then
    info "Restarted waybar"
  else
    warn "Could not restart waybar"
  fi
elif command -v waybar >/dev/null 2>&1; then
  setsid waybar >/dev/null 2>&1 & disown 2>/dev/null || true
  info "Restarted waybar"
else
  warn "No previous bar provider was found; configure one with your desktop session"
fi

# Variant selection and transaction locks are lifecycle state, not ownership
# evidence. Remove them even when the ownership marker must survive so a later
# reinstall can still restore the stock provider safely.
rm -f "$QSR_STATE_ROOT/active-variant" "$QSR_STATE_ROOT/active-version" \
      "$QSR_STATE_ROOT/switch.lock"
if qsr_owns_stock_bar_hide; then
  warn "Kept the Rise ownership marker because the Quattro toggle is unavailable; a later reinstall can restore it."
else
  rmdir "$QSR_STATE_ROOT" 2>/dev/null || true
fi

info "Uninstalled.${c_0}  (older backups under ~/.config/quickshell/bar.bak.* are kept)"
