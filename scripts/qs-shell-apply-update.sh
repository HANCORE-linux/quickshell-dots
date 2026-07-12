#!/usr/bin/env bash
# QS-Shell apply update.
#
# Topology: the live bar dir is a *copy* of versions/<V>/ from the deploy clone
# at ~/.local/share/quickshell-dots by default (override with QS_SHELL_REPO).
# Updating = read the checked state, verify the immutable target commit, deploy
# exactly that commit's version payload, restart the bar.
#
# MUST be launched outside the bar's service/cgroup, because this script stops
# and restarts the bar. `setsid` is not enough for systemd-managed launches.
#
# Safety contract:
#   - single-flight (flock): no concurrent applies
#   - never mutates the deploy repo worktree; reads the pinned target via git archive
#   - ALWAYS backs up the live dir first (it may hold un-synced live edits)
#   - atomic same-filesystem rename swap with automatic rollback: $DEST always
#     holds the old OR the new tree in full, and any failure leaves a running bar
#   - persisted settings (slot order / splits) live in ~/.cache and are untouched
set -euo pipefail

REPO="${QS_SHELL_REPO:-$HOME/.local/share/quickshell-dots}"
DEST="${QS_SHELL_DEST:-$HOME/.config/quickshell/bar}"
[ "$DEST" != "/" ] && DEST="${DEST%/}"
STATE_DIR="$HOME/.cache/qs-shell"
STATE="$STATE_DIR/update-available.json"
PROGRESS_STATE="${QS_SHELL_PROGRESS_STATE:-$STATE_DIR/apply-status.json}"
SCHEMA_VERSION=5
PROGRESS_SCHEMA_VERSION=1
PROGRESS_TOTAL_STEPS=5
PROGRESS_STALE_SECONDS=600
HOOK_PATH="hooks/50-quickshell-bar.sh"
POST_BOOT_HOOK_PATH="contrib/post-boot.d/quickshell-rise"
# Backups live in STATE_HOME (durable), NOT in ~/.cache — caches get tmpfs-mounted
# or wiped by hygiene tools, and the backup is the rollback's last-resort restore.
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/qs-shell/backups"
mkdir -p "$STATE_DIR"

note() { notify-send -a "QS-Shell" "$@" 2>/dev/null || true; }

progress_run_id=""
progress_state="idle"
progress_phase=""
progress_step=0
progress_target=""
progress_started_epoch=0
progress_screen="${QS_SHELL_PROGRESS_SCREEN:-}"
progress_panel_open=true
progress_last_trace_key=""
launched_bar_unit=""

systemd_env_args() {
  local -n _args_ref="$1"
  local name value
  for name in \
      DISPLAY \
      WAYLAND_DISPLAY \
      XDG_RUNTIME_DIR \
      XDG_SESSION_ID \
      XDG_SESSION_TYPE \
      XDG_CURRENT_DESKTOP \
      QT_QPA_PLATFORM \
      QT_QUICK_CONTROLS_STYLE \
      HYPRLAND_INSTANCE_SIGNATURE \
      OMARCHY_PATH \
      PATH; do
    value="${!name-}"
    [ -n "$value" ] && _args_ref+=("--setenv=$name=$value")
  done
}

start_bar_instance() {
  local unit args=()
  unit="qsrise-bar-$(random_run_id)"

  if command -v systemd-run >/dev/null 2>&1; then
    args=(--user --collect --quiet "--unit=$unit" "--slice=app-graphical.slice" "--property=Type=exec")
    systemd_env_args args
    if systemd-run "${args[@]}" qs -n -c bar >/dev/null 2>&1 9>&-; then
      launched_bar_unit="$unit"
      return 0
    fi
    if [ -n "${INVOCATION_ID:-}" ]; then
      return 1
    fi
  fi

  setsid qs -n -d -c bar >/dev/null 2>&1 9>&- < /dev/null &
}

stop_launched_bar_unit() {
  [ -n "${launched_bar_unit:-}" ] || return 0
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl --user stop "$launched_bar_unit" >/dev/null 2>&1 || true
}

epoch_now() {
  date +%s
}

random_run_id() {
  local id
  id="$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')" || true
  if [ -n "$id" ]; then
    printf '%s\n' "$id"
  else
    printf '%s-%s\n' "$(epoch_now)" "$$"
  fi
}

progress_trace() {
  local key
  [ -n "${QS_SHELL_PROGRESS_TRACE:-}" ] || return 0
  key="$progress_state:$progress_phase:$progress_step"
  [ "$key" != "$progress_last_trace_key" ] || return 0
  progress_last_trace_key="$key"
  printf '%s\t%s\t%s\t%s\n' "$progress_state" "$progress_phase" "$progress_step" "$progress_run_id" \
    >> "$QS_SHELL_PROGRESS_TRACE" 2>/dev/null || true
}

write_progress() {
  local state="$1" phase="$2" step="$3" error="${4:-}"
  local now t panel_open

  [ -n "$progress_run_id" ] || return 0
  if [ -r "$PROGRESS_STATE" ]; then
    panel_open="$(jq -r --argjson schema "$PROGRESS_SCHEMA_VERSION" --arg run "$progress_run_id" '
      if .schemaVersion == $schema and .runId == $run and (.panelOpen | type == "boolean")
      then .panelOpen else empty end
    ' "$PROGRESS_STATE" 2>/dev/null)" || panel_open=""
    case "$panel_open" in
      true) progress_panel_open=true ;;
      false) progress_panel_open=false ;;
    esac
  fi
  now="$(epoch_now)"
  [ "$progress_started_epoch" -gt 0 ] || progress_started_epoch="$now"
  progress_state="$state"
  progress_phase="$phase"
  progress_step="$step"

  t="$(mktemp -p "$STATE_DIR" apply-status.XXXXXX 2>/dev/null)" || return 0
  if jq -nc \
      --argjson schema "$PROGRESS_SCHEMA_VERSION" \
      --arg runId "$progress_run_id" \
      --arg state "$state" \
      --arg phase "$phase" \
      --argjson step "$step" \
      --argjson totalSteps "$PROGRESS_TOTAL_STEPS" \
      --arg targetCommit "$progress_target" \
      --argjson startedEpoch "$progress_started_epoch" \
      --argjson updatedEpoch "$now" \
      --arg screenName "$progress_screen" \
      --arg error "$error" \
      --argjson panelOpen "$progress_panel_open" \
      '{
        schemaVersion: $schema,
        runId: $runId,
        state: $state,
        phase: $phase,
        step: $step,
        totalSteps: $totalSteps,
        targetCommit: $targetCommit,
        startedEpoch: $startedEpoch,
        updatedEpoch: $updatedEpoch,
        screenName: $screenName,
        error: $error,
        acknowledged: false,
        panelOpen: $panelOpen
      }' > "$t" 2>/dev/null && mv "$t" "$PROGRESS_STATE" 2>/dev/null; then
    progress_trace
    return 0
  fi

  rm -f "$t" 2>/dev/null || true
  return 0
}

progress_fail() {
  local msg="$1"
  [ -n "$progress_run_id" ] || return 0
  [ -n "$progress_phase" ] || progress_phase="checking"
  [ "$progress_step" -gt 0 ] || progress_step=1
  write_progress "failed" "$progress_phase" "$progress_step" "$msg"
}

fail() {
  progress_fail "$1"
  note -u critical "Shell update failed" "$1"
  exit 1
}

progress_recent_running_exists() {
  local row state updated now
  [ -r "$PROGRESS_STATE" ] || return 1
  row="$(jq -r --argjson schema "$PROGRESS_SCHEMA_VERSION" '
    if .schemaVersion == $schema
       and (.state == "running")
       and ((.updatedEpoch // 0) > 0)
    then [.state, (.updatedEpoch | tostring)] | @tsv else empty end
  ' "$PROGRESS_STATE" 2>/dev/null)" || return 1
  [ -n "$row" ] || return 1
  IFS=$'\t' read -r state updated <<< "$row"
  now="$(epoch_now)"
  [ $((now - updated)) -lt "$PROGRESS_STALE_SECONDS" ]
}

start_progress_run() {
  progress_run_id="$(random_run_id)"
  progress_state="running"
  progress_phase="checking"
  progress_step=1
  progress_target=""
  progress_started_epoch="$(epoch_now)"
  progress_panel_open=true
  write_progress "running" "checking" 1 ""
}

set_progress_panel() {
  local run_id="$1" mode="$2" open t
  case "$mode" in
    open) open=true ;;
    closed) open=false ;;
    *) return 0 ;;
  esac
  [ -n "$run_id" ] || return 0
  [ -r "$PROGRESS_STATE" ] || return 0
  t="$(mktemp -p "$STATE_DIR" apply-status.XXXXXX 2>/dev/null)" || return 0
  if jq -c --argjson schema "$PROGRESS_SCHEMA_VERSION" \
      --arg run "$run_id" \
      --argjson open "$open" \
      'if .schemaVersion == $schema and .runId == $run
       then .panelOpen = $open
       else . end' "$PROGRESS_STATE" > "$t" 2>/dev/null \
      && mv "$t" "$PROGRESS_STATE" 2>/dev/null; then
    return 0
  fi
  rm -f "$t" 2>/dev/null || true
  return 0
}

load_progress_for_run() {
  local run_id="$1" row
  [ -n "$run_id" ] || return 1
  [ -r "$PROGRESS_STATE" ] || return 1
  row="$(jq -r --argjson schema "$PROGRESS_SCHEMA_VERSION" --arg run "$run_id" '
    if .schemaVersion == $schema and .runId == $run
    then [
      .runId,
      (.state // ""),
      (.phase // ""),
      ((.step // 0) | tostring),
      (.targetCommit // ""),
      ((.startedEpoch // 0) | tostring),
      (.screenName // ""),
      (if (.panelOpen | type == "boolean") then (.panelOpen | tostring) else "true" end)
    ] | @tsv else empty end
  ' "$PROGRESS_STATE" 2>/dev/null)" || return 1
  [ -n "$row" ] || return 1
  IFS=$'\t' read -r progress_run_id progress_state progress_phase progress_step progress_target progress_started_epoch progress_screen progress_panel_open <<< "$row"
  [ -n "$progress_run_id" ]
}

complete_progress() {
  local run_id="$1" deployed=""
  load_progress_for_run "$run_id" || return 0
  [ "$progress_state" = "running" ] || return 0
  if [ -f "$DEST/.qsrise-commit" ]; then
    deployed="$(tr -d '[:space:]' < "$DEST/.qsrise-commit" 2>/dev/null || true)"
  fi
  if [ -n "$progress_target" ] && [ "$deployed" = "$progress_target" ]; then
    write_progress "completed" "restarting" 5 ""
    note "Shell updated" "Now on reviewed target ${progress_target:0:12}."
  else
    write_progress "failed" "restarting" 5 "Loaded shell does not match the reviewed target."
    note -u critical "Shell update failed" "Loaded shell does not match the reviewed target."
  fi
}

ack_progress() {
  local run_id="$1" now t
  load_progress_for_run "$run_id" || return 0
  now="$(epoch_now)"
  t="$(mktemp -p "$STATE_DIR" apply-status.XXXXXX 2>/dev/null)" || return 0
  if jq -nc \
      --argjson schema "$PROGRESS_SCHEMA_VERSION" \
      --arg runId "$progress_run_id" \
      --arg targetCommit "$progress_target" \
      --argjson startedEpoch "$progress_started_epoch" \
      --argjson updatedEpoch "$now" \
      --arg screenName "$progress_screen" \
      --argjson panelOpen false \
      '{
        schemaVersion: $schema,
        runId: $runId,
        state: "idle",
        phase: "",
        step: 0,
        totalSteps: 5,
        targetCommit: $targetCommit,
        startedEpoch: $startedEpoch,
        updatedEpoch: $updatedEpoch,
        screenName: $screenName,
        error: "",
        acknowledged: true,
        panelOpen: $panelOpen
      }' > "$t" 2>/dev/null && mv "$t" "$PROGRESS_STATE" 2>/dev/null; then
    return 0
  fi
  rm -f "$t" 2>/dev/null || true
  return 0
}

case "${1:-}" in
  --complete-progress)
    complete_progress "${2:-}"
    exit 0
    ;;
  --ack-progress)
    ack_progress "${2:-}"
    exit 0
    ;;
  --progress-panel)
    set_progress_panel "${2:-}" "${3:-}"
    exit 0
    ;;
esac

# Single-flight: a second click (the panel lingers ~120ms while closing) must not
# start a concurrent rm/rename on $DEST.
exec 9>"$STATE_DIR/apply.lock"
if ! flock -n 9; then
  note "Shell update" "An update is already running."
  exit 0
fi
if progress_recent_running_exists; then
  note "Shell update" "An update is already running."
  exit 0
fi
start_progress_run

# State contract: never delete the state file; "up to date" is behind:0 (atomic).
clear_state() {
  local t
  t="$(mktemp -p "$STATE_DIR")" || return 1
  if printf '{"schemaVersion": %d, "behind": 0, "checked": "%s"}\n' "$SCHEMA_VERSION" "$(date -Is)" > "$t" \
      && mv "$t" "$STATE"; then
    return 0
  fi
  rm -f "$t"
  return 1
}

is_commit_hash() {
  [[ "$1" =~ ^[0-9a-f]{40}$ || "$1" =~ ^[0-9a-f]{64}$ ]]
}

read_pending_state() {
  local parsed
  [ -r "$STATE" ] || fail "No pending shell update state."
  parsed="$(jq -r --argjson schema "$SCHEMA_VERSION" '
    if .schemaVersion == $schema
       and ((.behind // 0) > 0)
       and (.repository | type == "string")
       and (.upstreamRef | type == "string")
       and (.baseCommit | type == "string")
       and (.targetCommit | type == "string")
       and (.version | type == "string")
       and (.summary | type == "array")
       and (.commitIds | type == "array")
       and (.commitIds | all(type == "string"))
       and (.payloadTree | type == "string")
       and (.scriptsTree | type == "string")
       and (.systemdTree | type == "string")
       and (.hookBlob | type == "string")
       and (.postBootHookBlob | type == "string")
    then [.repository, .upstreamRef, .baseCommit, .targetCommit, .version, .hookBlob, .postBootHookBlob] | @tsv
    else empty end
  ' "$STATE" 2>/dev/null)" || fail "Could not read shell update state."
  [ -n "$parsed" ] || fail "Shell update state is missing immutable target data."
  IFS=$'\t' read -r state_repo state_upstream state_base state_target state_version state_hook_blob state_post_boot_hook_blob <<< "$parsed"
  is_commit_hash "$state_base" || fail "Stored base commit is invalid."
  is_commit_hash "$state_target" || fail "Stored target commit is invalid."
  [ -z "$state_hook_blob" ] || is_commit_hash "$state_hook_blob" || fail "Stored theme hook blob is invalid."
  [ -z "$state_post_boot_hook_blob" ] || is_commit_hash "$state_post_boot_hook_blob" || fail "Stored post-boot hook blob is invalid."
}

bar_pids() {
  local cfg="$DEST/shell.qml"
  qs list --all 2>/dev/null | awk -v cfg="$cfg" '
    $1 == "Process" && $2 == "ID:" { pid = $3 }
    /^[[:space:]]*Config path:/ {
      path = $0
      sub(/^[[:space:]]*Config path:[[:space:]]*/, "", path)
      gsub(/^"|"$/, "", path)
      if (path == cfg && pid != "") print pid
      pid = ""
    }
  ' || true
}

stop_registered_bars() {
  local rounds="${1:-60}" stable="${2:-5}"
  local pids pid quiet=0

  # Crash-relaunched Quickshell instances can respawn after a TERM. Rescan on
  # every pass and require a short stable-empty window before trusting that the
  # old bar is gone.
  for _ in $(seq 1 "$rounds"); do
    pids="$(bar_pids | sort -u)"
    if [ -z "$pids" ]; then
      quiet=$((quiet + 1))
      [ "$quiet" -ge "$stable" ] && return 0
    else
      quiet=0
      for pid in $pids; do
        kill -TERM "$pid" 2>/dev/null || true
      done
    fi
    sleep 0.1
  done

  [ -z "$(bar_pids | sort -u)" ]
}

legacy_bar_running() {
  pgrep -f 'qs.* -c bar([[:space:]]|$)' >/dev/null 2>&1 || \
    pgrep -f "quickshell -p $DEST" >/dev/null 2>&1
}

stop_legacy_bars() {
  # Legacy fallback for installs too old to show up in `qs list`, and a backup
  # if Quickshell's registry misses an instance.
  pkill -f 'qs.* -c bar([[:space:]]|$)' 2>/dev/null || true
  pkill -f "quickshell -p $DEST" 2>/dev/null || true
  for _ in $(seq 1 50); do
    legacy_bar_running || return 0
    sleep 0.1
  done

  ! legacy_bar_running
}

stop_bar_instances() {
  local rc=0

  stop_registered_bars 60 5 || true
  stop_legacy_bars || rc=1
  # One final registry pass catches a crash-relaunch that appeared while the
  # legacy command-line fallback was waiting.
  stop_registered_bars 30 5 || rc=1
  return "$rc"
}

safe_companion_target() {
  local rel="$1" part
  [ -n "$rel" ] || return 1
  [[ "$rel" != /* ]] || return 1
  IFS=/ read -r -a parts <<< "$rel"
  for part in "${parts[@]}"; do
    [ -n "$part" ] || return 1
    [ "$part" != "." ] || return 1
    [ "$part" != ".." ] || return 1
  done
}

trim_line() {
  local s="$1"
  s="${s%%#*}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s\n' "$s"
}

backup_companion_targets() {
  local targets="$1" raw rel src dst
  [ -f "$targets" ] || return 0
  companion_backup="$(mktemp -d -p "$STATE_DIR" companion-targets.XXXXXX)" || \
    fail "Could not create companion rollback backup."
  companion_backup_manifest="$companion_backup/manifest"
  : > "$companion_backup_manifest" || fail "Could not create companion rollback manifest."

  while IFS= read -r raw || [ -n "$raw" ]; do
    rel="$(trim_line "$raw")"
    [ -n "$rel" ] || continue
    safe_companion_target "$rel" || fail "Unsafe companion rollback target '$rel'."
    src="$HOME/$rel"
    dst="$companion_backup/root/$rel"
    if [ -e "$src" ] || [ -L "$src" ]; then
      mkdir -p "$(dirname "$dst")" || fail "Could not back up companion target '$rel'."
      cp -a "$src" "$dst" || fail "Could not back up companion target '$rel'."
      printf 'present\t%s\n' "$rel" >> "$companion_backup_manifest"
    else
      printf 'missing\t%s\n' "$rel" >> "$companion_backup_manifest"
    fi
  done < "$targets"
}

restore_companion_targets() {
  local status rel dst src rc=0
  [ -n "${companion_backup_manifest:-}" ] || return 0
  [ -f "$companion_backup_manifest" ] || return 0

  while IFS=$'\t' read -r status rel || [ -n "$status$rel" ]; do
    [ -n "$rel" ] || continue
    safe_companion_target "$rel" || continue
    dst="$HOME/$rel"
    src="$companion_backup/root/$rel"
    rm -rf "$dst" 2>/dev/null || rc=1
    if [ "$status" = "present" ] && { [ -e "$src" ] || [ -L "$src" ]; }; then
      mkdir -p "$(dirname "$dst")" 2>/dev/null || rc=1
      cp -a "$src" "$dst" 2>/dev/null || rc=1
    fi
  done < "$companion_backup_manifest"
  return "$rc"
}

companion_systemd_units=(
  qs-aur-blacklist-fetch.timer
  qs-shell-update-check.timer
  opencode-usage.timer
)

snapshot_companion_systemd() {
  local unit enabled active
  command -v systemctl >/dev/null 2>&1 || return 0
  [ -n "${companion_backup:-}" ] || return 0
  companion_systemd_snapshot="$companion_backup/systemd-state"
  : > "$companion_systemd_snapshot" || fail "Could not snapshot companion systemd state."
  for unit in "${companion_systemd_units[@]}"; do
    enabled="$(systemctl --user is-enabled "$unit" 2>/dev/null || true)"
    active="$(systemctl --user is-active "$unit" 2>/dev/null || true)"
    printf '%s\t%s\t%s\n' "$unit" "${enabled:-unknown}" "${active:-unknown}" >> "$companion_systemd_snapshot"
  done
}

restore_companion_systemd() {
  local unit enabled active rc=0
  [ -n "${companion_systemd_snapshot:-}" ] || return 0
  [ -f "$companion_systemd_snapshot" ] || return 0
  command -v systemctl >/dev/null 2>&1 || return 0

  systemctl --user daemon-reload >/dev/null 2>&1 || rc=1
  while IFS=$'\t' read -r unit enabled active || [ -n "$unit$enabled$active" ]; do
    [ -n "$unit" ] || continue
    case "$enabled" in
      enabled|enabled-runtime|linked|linked-runtime)
        systemctl --user enable "$unit" >/dev/null 2>&1 || rc=1
        ;;
      disabled|disabled-runtime|masked|masked-runtime|bad|not-found)
        systemctl --user disable "$unit" >/dev/null 2>&1 || rc=1
        ;;
    esac
    case "$active" in
      active|activating|reloading)
        systemctl --user start "$unit" >/dev/null 2>&1 || rc=1
        ;;
      inactive|failed|deactivating)
        systemctl --user stop "$unit" >/dev/null 2>&1 || rc=1
        ;;
    esac
  done < "$companion_systemd_snapshot"
  systemctl --user daemon-reload >/dev/null 2>&1 || rc=1
  return "$rc"
}

commit_companion_systemd() {
  local units="$HOME/.config/systemd/user" unit rc=0
  local changed_units=()
  command -v systemctl >/dev/null 2>&1 || return 0

  for unit in "${companion_systemd_units[@]}"; do
    if [ -f "$units/$unit" ]; then
      changed_units+=("$unit")
    fi
  done
  if [ "${#changed_units[@]}" -gt 0 ]; then
    systemctl --user daemon-reload >/dev/null 2>&1 || rc=1
    for unit in "${changed_units[@]}"; do
      systemctl --user enable --now "$unit" >/dev/null 2>&1 || rc=1
    done
    systemctl --user try-restart "${changed_units[@]}" >/dev/null 2>&1 || rc=1
  fi
  return "$rc"
}

check_stage_imports() {
  local root="$1" file dir line rel path rc=0
  while IFS= read -r -d '' file; do
    dir="$(dirname "$file")"
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ "$line" =~ ^[[:space:]]*import[[:space:]]*\"([^\"]+)\" ]]; then
        rel="${BASH_REMATCH[1]}"
        case "$rel" in
          :*|qrc:*) ;;
          *) [ -e "$dir/$rel" ] || rc=1 ;;
        esac
      fi

      if [[ "$line" =~ ^[[:space:]]*import[[:space:]]+qs\.([A-Za-z0-9_.]+) ]]; then
        rel="${BASH_REMATCH[1]}"
        path="${rel//./\/}"
        [ -d "$root/$path" ] || rc=1
        [ -f "$root/$path/qmldir" ] || rc=1
      fi
    done < "$file"
  done < <(find "$root" -name '*.qml' -type f -print0)
  return "$rc"
}

run_quickshell_smoke() {
  local qs_bin="$1" wrapper="$2" timeout_s="$3" platform="$4" out="$5" err="$6" rc=0
  if [ -n "$platform" ]; then
    QT_QPA_PLATFORM="$platform" timeout "$timeout_s" "$qs_bin" -p "$wrapper" --no-duplicate --no-color >"$out" 2>"$err" || rc=$?
  else
    timeout "$timeout_s" "$qs_bin" -p "$wrapper" --no-duplicate --no-color >"$out" 2>"$err" || rc=$?
  fi
  [ "$rc" -eq 0 ] || return 1
  grep -Fq "QS_SHELL_SMOKE_OK" "$out" "$err" 2>/dev/null || return 1
  ! grep -Fq "QS_SHELL_SMOKE_FAIL" "$out" "$err" 2>/dev/null
}

smoke_stage() {
  local root="$1" smoke out err qs_bin smoke_timeout smoke_platform wrapper target_url root_wrapper
  [ -f "$root/shell.qml" ] || fail "Staged version '$ver' is missing shell.qml."
  qs_bin="${QS_SHELL_QUICKSHELL_BIN:-}"
  if [ -z "$qs_bin" ]; then
    qs_bin="$(command -v quickshell 2>/dev/null || command -v qs 2>/dev/null || true)"
  fi
  [ -n "$qs_bin" ] || fail "quickshell is required for staged shell smoke."
  command -v timeout >/dev/null 2>&1 || fail "timeout is required for staged shell smoke."
  check_stage_imports "$root" || fail "Staged shell contains unresolved local or qs.* QML imports."

  smoke="$(mktemp -d -p "$STATE_DIR" smoke.XXXXXX)" || fail "Could not create staged shell smoke directory."
  wrapper="$smoke/file-url-smoke.qml"
  target_url="file://$root/shell.qml"
  target_url="${target_url//\\/\\\\}"
  target_url="${target_url//\"/\\\"}"
  cat > "$wrapper" <<'QML'
import QtQuick

QtObject {
  id: root
  property var component: null
  property bool finished: false

  function finish(ok, errorText) {
    if (finished)
      return
    finished = true
    if (ok)
      console.log("QS_SHELL_SMOKE_OK")
    else
      console.error("QS_SHELL_SMOKE_FAIL " + errorText)
    Qt.callLater(Qt.quit)
  }

  function evaluateStatus() {
    if (component.status === Component.Ready)
      finish(true, "")
    else if (component.status === Component.Error)
      finish(false, component.errorString())
  }

  Component.onCompleted: {
    component = Qt.createComponent("__QS_SHELL_TARGET_URL__")
    if (component.status === Component.Loading)
      component.statusChanged.connect(function() { root.evaluateStatus() })
    root.evaluateStatus()
  }
}
QML
  sed -i "s|__QS_SHELL_TARGET_URL__|$target_url|" "$wrapper" || {
    rm -rf "$smoke"
    fail "Could not prepare staged shell smoke wrapper."
  }
  out="$smoke/file-url.out"
  err="$smoke/file-url.err"
  smoke_timeout="${QS_SHELL_SMOKE_TIMEOUT:-3}"
  smoke_platform="${QS_SHELL_SMOKE_PLATFORM:-}"
  if run_quickshell_smoke "$qs_bin" "$wrapper" "$smoke_timeout" "$smoke_platform" "$out" "$err"; then
    rm -rf "$smoke"
    return 0
  fi

  # Fallback for staged qs.* modules. The wrapper must live in the staged root
  # so that root-relative module resolution can see <root>/modules/qmldir, but
  # it must only load the component. Do not start the staged shell as a real
  # Quickshell entry point and do not call createObject(): both can execute
  # PanelWindow, Process, IPC and cache-writing side effects before the swap.
  root_wrapper="$root/.qs-shell-smoke.qml"
  cat > "$wrapper" <<'QML'
import QtQuick

QtObject {
  id: root
  property var component: null
  property bool finished: false

  function finish(ok, errorText) {
    if (finished)
      return
    finished = true
    if (ok)
      console.log("QS_SHELL_SMOKE_OK")
    else
      console.error("QS_SHELL_SMOKE_FAIL " + errorText)
    Qt.callLater(Qt.quit)
  }

  function evaluateStatus() {
    if (component.status === Component.Ready)
      finish(true, "")
    else if (component.status === Component.Error)
      finish(false, component.errorString())
  }

  Component.onCompleted: {
    component = Qt.createComponent(Qt.resolvedUrl("shell.qml"))
    if (component.status === Component.Loading)
      component.statusChanged.connect(function() { root.evaluateStatus() })
    root.evaluateStatus()
  }
}
QML
  mv "$wrapper" "$root_wrapper" || {
    rm -rf "$smoke"
    fail "Could not prepare staged shell root smoke wrapper."
  }
  out="$smoke/root.out"
  err="$smoke/root.err"
  if run_quickshell_smoke "$qs_bin" "$root_wrapper" "$smoke_timeout" "$smoke_platform" "$out" "$err"; then
    rm -f "$root_wrapper" || { rm -rf "$smoke"; fail "Could not clean staged shell smoke wrapper."; }
    rm -rf "$smoke"
    return 0
  fi
  rm -f "$root_wrapper"
  rm -rf "$smoke"
  fail "Staged shell Quickshell smoke failed."
}

ver="V1"
[ -f "$DEST/.qsrise" ] && ver="$(tr -d '[:space:]' < "$DEST/.qsrise")"
[ -n "$ver" ] || ver="V1"

[ -d "$REPO/.git" ] || fail "Repo not found at $REPO"
cd "$REPO"
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "Repo is not a valid git checkout."
head_commit="$(git rev-parse 'HEAD^{commit}' 2>/dev/null)" || fail "Repo HEAD is not a commit."
read_pending_state
progress_target="$state_target"
write_progress "running" "checking" 1 ""
[ "$state_repo" = "$repo_root" ] || fail "Pending update belongs to a different repo."
[ "$state_version" = "$ver" ] || fail "Pending update targets '$state_version', but installed version is '$ver'."

current_base="$head_commit"
if [ -f "$DEST/.qsrise-commit" ]; then
  deployed_commit="$(tr -d '[:space:]' < "$DEST/.qsrise-commit" 2>/dev/null || true)"
  if is_commit_hash "$deployed_commit" && git cat-file -e "$deployed_commit^{commit}" 2>/dev/null; then
    current_base="$deployed_commit"
  fi
fi
[ "$current_base" = "$state_base" ] || fail "Pending update is stale — refresh the shell update check first."

# 1. Refresh refs, then prove that the stored immutable target is still a valid
#    commit from the expected upstream. Never install the moving branch tip.
git fetch --quiet origin || fail "Could not reach origin (offline?)."
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" \
  || fail "No upstream tracking branch in $REPO."
[ "$upstream" = "$state_upstream" ] || fail "Upstream changed since check — refresh first."
git cat-file -e "$state_base^{commit}" 2>/dev/null || fail "Stored base commit is not available locally."
git cat-file -e "$state_target^{commit}" 2>/dev/null || fail "Stored target commit is not available locally."
git merge-base --is-ancestor "$state_base" "$state_target" 2>/dev/null || \
  fail "Stored target is not a fast-forward from the checked base."
git merge-base --is-ancestor "$state_target" "$state_upstream" 2>/dev/null || \
  fail "Stored target is no longer reachable from $state_upstream."
git cat-file -e "$state_target:versions/$ver" 2>/dev/null || \
  fail "Version '$ver' missing at stored target commit."
write_progress "running" "validating" 2 ""

# Detect a state file where targetCommit was edited to a different reachable
# commit: the immutable target must still match the stored full commit lineage,
# payload tree, companion tree IDs and hook blobs that the check wrote for
# baseCommit..targetCommit. Count and changelog remain UI consistency checks,
# but are not trusted as provenance.
payload=("versions/$ver/" "scripts/" "systemd/" "$HOOK_PATH" "$POST_BOOT_HOOK_PATH")
state_behind="$(jq -r '.behind // empty' "$STATE" 2>/dev/null)" || fail "Could not read stored update count."
[[ "$state_behind" =~ ^[0-9]+$ ]] || fail "Stored update count is invalid."
actual_behind="$(git rev-list --count "$state_base..$state_target" -- "${payload[@]}" 2>/dev/null)" || \
  fail "Could not verify stored update count."
[ "$actual_behind" = "$state_behind" ] || fail "Stored target does not match the checked update count."
summary_check="$(mktemp -p "$STATE_DIR" summary.XXXXXX)" || fail "Could not create summary check."
if ! git log --max-count=8 --format='%s' "$state_base..$state_target" -- "${payload[@]}" \
    | jq -R . | jq -s . > "$summary_check"; then
  rm -f "$summary_check"
  fail "Could not verify stored update summary."
fi
if ! jq -e --slurpfile actual "$summary_check" '.summary == $actual[0]' "$STATE" >/dev/null 2>&1; then
  rm -f "$summary_check"
  fail "Stored target does not match the checked update summary."
fi
rm -f "$summary_check"
commit_ids_check="$(mktemp -p "$STATE_DIR" commits.XXXXXX)" || fail "Could not create commit lineage check."
if ! git rev-list --reverse "$state_base..$state_target" | jq -R . | jq -s . > "$commit_ids_check"; then
  rm -f "$commit_ids_check"
  fail "Could not verify stored commit lineage."
fi
if ! jq -e --slurpfile actual "$commit_ids_check" '.commitIds == $actual[0]' "$STATE" >/dev/null 2>&1; then
  rm -f "$commit_ids_check"
  fail "Stored target does not match the checked commit lineage."
fi
rm -f "$commit_ids_check"
state_payload_tree="$(jq -r '.payloadTree' "$STATE" 2>/dev/null)" || fail "Could not read stored payload tree."
actual_payload_tree="$(git rev-parse "$state_target:versions/$ver" 2>/dev/null)" || \
  fail "Could not verify stored payload tree."
[ "$actual_payload_tree" = "$state_payload_tree" ] || fail "Stored target does not match the checked payload tree."
state_scripts_tree="$(jq -r '.scriptsTree' "$STATE" 2>/dev/null)" || fail "Could not read stored scripts tree."
actual_scripts_tree=""
if git cat-file -e "$state_target:scripts" 2>/dev/null; then
  actual_scripts_tree="$(git rev-parse "$state_target:scripts" 2>/dev/null)" || \
    fail "Could not verify stored scripts tree."
fi
[ "$actual_scripts_tree" = "$state_scripts_tree" ] || fail "Stored target does not match the checked scripts tree."
state_systemd_tree="$(jq -r '.systemdTree' "$STATE" 2>/dev/null)" || fail "Could not read stored systemd tree."
actual_systemd_tree=""
if git cat-file -e "$state_target:systemd" 2>/dev/null; then
  actual_systemd_tree="$(git rev-parse "$state_target:systemd" 2>/dev/null)" || \
    fail "Could not verify stored systemd tree."
fi
[ "$actual_systemd_tree" = "$state_systemd_tree" ] || fail "Stored target does not match the checked systemd tree."
actual_hook_blob=""
if git cat-file -e "$state_target:$HOOK_PATH" 2>/dev/null; then
  actual_hook_blob="$(git rev-parse "$state_target:$HOOK_PATH" 2>/dev/null)" || \
    fail "Could not verify stored theme hook blob."
fi
[ "$actual_hook_blob" = "$state_hook_blob" ] || fail "Stored target does not match the checked theme hook blob."
actual_post_boot_hook_blob=""
if git cat-file -e "$state_target:$POST_BOOT_HOOK_PATH" 2>/dev/null; then
  actual_post_boot_hook_blob="$(git rev-parse "$state_target:$POST_BOOT_HOOK_PATH" 2>/dev/null)" || \
    fail "Could not verify stored post-boot hook blob."
fi
[ "$actual_post_boot_hook_blob" = "$state_post_boot_hook_blob" ] || \
  fail "Stored target does not match the checked post-boot hook blob."

# Sweep any stage dir orphaned by a previously hard-killed run (SIGKILL / power
# loss skips the EXIT trap). Safe here: the flock above guarantees no other apply
# is mid-run, and provenance has already been validated.
rm -rf "$(dirname "$DEST")"/.qs-stage.* 2>/dev/null || true

# 3. Always back up the live dir before overwriting (protects un-synced edits).
mkdir -p "$BACKUP_ROOT"
ts="$(date +%Y%m%d-%H%M%S)"
backup="$BACKUP_ROOT/bar.$ts"
cp -a "$DEST" "$backup"
# keep only the 3 most recent backups
# shellcheck disable=SC2012
ls -1dt "$BACKUP_ROOT"/bar.* 2>/dev/null | tail -n +4 | xargs -r rm -rf

# 4. Stage in $DEST's OWN parent directory — same filesystem by construction, so
#    the swap is guaranteed an atomic rename (never a cross-FS copy that could be
#    interrupted mid-write, regardless of how ~/.cache or ~/.local are mounted).
#    The bar watches the `bar` config dir specifically, so a sibling .qs-stage.*
#    dir is ignored. Clean the stage on any exit.
stage="$(mktemp -d -p "$(dirname "$DEST")" .qs-stage.XXXXXX)"
companion=""
companion_backup=""
companion_backup_manifest=""
companion_systemd_snapshot=""
cleanup() {
  [ -n "${stage:-}" ] && rm -rf "$stage" 2>/dev/null || true
  [ -n "${companion:-}" ] && rm -rf "$companion" 2>/dev/null || true
  [ -n "${companion_backup:-}" ] && rm -rf "$companion_backup" 2>/dev/null || true
}
trap cleanup EXIT
git archive "$state_target:versions/$ver" | tar -x -C "$stage" || \
  fail "Could not stage version '$ver' from stored target commit."
if [ -f "$backup/quotes.txt" ]; then
  cp -p "$backup/quotes.txt" "$stage/quotes.txt"
fi
printf '%s\n' "$ver" > "$stage/.qsrise"
printf '%s\n' "$state_target" > "$stage/.qsrise-commit"
printf '%s\n' "$state_payload_tree" > "$stage/.qsrise-payload-tree"
write_progress "running" "testing" 3 ""
smoke_stage "$stage"

companion_paths=()
for p in scripts systemd; do
  if git cat-file -e "$state_target:$p" 2>/dev/null; then
    companion_paths+=("$p")
  fi
done
if git cat-file -e "$state_target:$HOOK_PATH" 2>/dev/null; then
  companion_paths+=("$HOOK_PATH")
fi
if git cat-file -e "$state_target:$POST_BOOT_HOOK_PATH" 2>/dev/null; then
  companion_paths+=("$POST_BOOT_HOOK_PATH")
fi
if [ "${#companion_paths[@]}" -gt 0 ]; then
  companion="$(mktemp -d -p "$STATE_DIR" companion.XXXXXX)" || fail "Could not create companion stage."
  git archive "$state_target" "${companion_paths[@]}" | tar -x -C "$companion" || \
    fail "Could not stage companion files from stored target commit."
  if [ -f "$companion/scripts/qs-shell-post-update.sh" ]; then
    [ -f "$companion/scripts/qs-shell-post-update.targets" ] || \
      fail "Companion post-update is missing rollback target manifest."
    backup_companion_targets "$companion/scripts/qs-shell-post-update.targets"
    snapshot_companion_systemd
  fi
fi

write_progress "running" "installing" 4 ""
# Stop the bar before swapping, and WAIT for it to actually exit (don't trust a
# fixed sleep). Prefer Quickshell's registered config path over command-line
# matching: after IPC/crash recovery, the same bar can show up as
# `/usr/bin/quickshell`, not `qs -c bar`.
if [ -z "${QS_SHELL_NO_RESTART:-}" ]; then
  stop_bar_instances || fail "Could not stop the old bar instance safely."
fi

# Atomic swap with rollback. At every instant $DEST holds either the old or the
# new tree in full; any failure restores a working bar and notifies.
old="$DEST.old.$ts"
swapped=0
rollback() {
  local msg
  stop_launched_bar_unit
  if [ "${swapped:-0}" -eq 1 ]; then   # new tree is visible, later step failed → restore old
    rm -rf "$DEST" 2>/dev/null || true
    if [ -d "$old" ]; then
      mv "$old" "$DEST" 2>/dev/null || cp -a "$backup" "$DEST" 2>/dev/null || true
    else
      cp -a "$backup" "$DEST" 2>/dev/null || true
    fi
    msg="Deploy failed — previous version restored."
  elif [ ! -e "$DEST" ]; then          # old tree was moved aside, swap-in failed → restore
    if [ -d "$old" ]; then
      mv "$old" "$DEST" 2>/dev/null || cp -a "$backup" "$DEST" 2>/dev/null || true
    else
      cp -a "$backup" "$DEST" 2>/dev/null || true
    fi
    msg="Deploy failed — previous version restored."
  else                                 # $DEST never changed (the aside-move itself failed)
    msg="Update aborted before any change — bar restarted unchanged."
  fi
  rm -rf "$old" 2>/dev/null || true
  progress_fail "$msg"
  if [ -z "${QS_SHELL_NO_RESTART:-}" ]; then
    start_bar_instance || true
  fi
  note -u critical "Shell update failed" "$msg"
}
post_swap_fail() {
  restore_companion_targets || note -u critical "Shell update rollback warning" "Could not fully restore companion files."
  restore_companion_systemd || note -u critical "Shell update rollback warning" "Could not fully restore systemd user state."
  rollback
  exit 1
}
trap 'rollback' ERR

mv "$DEST" "$old"        # atomic rename (same FS)
mv "$stage" "$DEST"      # atomic rename (same FS)
stage=""
swapped=1
trap 'post_swap_fail' ERR

# 5. Companion pieces (helper scripts, systemd units): refresh them from the
#     same stored target commit so a bar update is complete on its own — no
#     manual install.sh re-run. This is part of the reviewed update transaction:
#     a failure rolls back the visible deploy and leaves the pending state intact.
if [ -n "$companion" ] && [ -f "$companion/scripts/qs-shell-post-update.sh" ]; then
  QS_SHELL_COMPANION_DEFER_SYSTEMD=1 \
  QS_SHELL_REQUIRE_POST_BOOT_SOURCE=1 \
    bash "$companion/scripts/qs-shell-post-update.sh" "$companion" >/dev/null 2>&1 || post_swap_fail
  commit_companion_systemd || post_swap_fail
fi

write_progress "running" "restarting" 5 ""
# 6. Relaunch the bar outside the apply unit/cgroup before finalizing the
#    transaction. If restart fails, rollback is still armed and the old deploy is
#    restored.
#
#    systemd-run is preferred so
#    a systemd-managed apply can exit without killing the new bar. 9>&- prevents
#    the relaunched bar from inheriting the flock fd and blocking future updates.
if [ -z "${QS_SHELL_NO_RESTART:-}" ]; then
  start_bar_instance || post_swap_fail
fi

# 6b. Mark up-to-date via an atomic state write (never delete), but only after
#     deploy, companion steps and the new bar start have completed successfully.
clear_state || post_swap_fail

trap - ERR
rm -rf "$old" 2>/dev/null || true
swapped=0
