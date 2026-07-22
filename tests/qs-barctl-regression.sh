#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BARCTL="${BARCTL:-$REPO_ROOT/scripts/qs-barctl}"
WORK="$(mktemp -d /tmp/qs-barctl-test.XXXXXX)"

cleanup() {
  if [[ -n ${KEEP_WORK:-} ]]; then
    printf 'Kept test fixtures: %s\n' "$WORK" >&2
    return
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local want="$1" got="$2" message="$3"
  [[ $want == "$got" ]] || fail "$message: want '$want', got '$got'"
}

assert_contains() {
  local needle="$1" file="$2" message="$3"
  grep -Fq -- "$needle" "$file" || fail "$message: missing '$needle'"
}

assert_not_contains() {
  local needle="$1" file="$2" message="$3"
  grep -Fq -- "$needle" "$file" && fail "$message: unexpectedly found '$needle'"
  return 0
}

make_fakes() {
  local root="$1"
  mkdir -p "$root/bin"

  cat > "$root/bin/qs" <<'FAKE_QS'
#!/usr/bin/env bash
set -euo pipefail

state="$FAKE_INSTANCE_STATE"

update_instance() {
  local id="$1" version="$2" ready="$3" tmp="$state.tmp"
  awk -F '\t' -v id="$id" -v version="$version" -v ready="$ready" '
    BEGIN { OFS="\t" }
    $1 == id { $5=ready; $6=version }
    { print }
  ' "$state" > "$tmp"
  mv "$tmp" "$state"
}

switch_state_value() {
  local id="$1" mode source target poll
  if [[ ! -s $FAKE_SWITCH_STATE ]]; then
    printf 'active\n'
    return
  fi
  IFS=$'\t' read -r mode source target poll < "$FAKE_SWITCH_STATE"
  poll=$((poll + 1))
  if ((poll < 2)); then
    printf '%s\t%s\t%s\t%s\n' "$mode" "$source" "$target" "$poll" > "$FAKE_SWITCH_STATE"
    printf 'preparing\n'
    return
  fi

  case "$mode" in
    success)
      update_instance "$id" "${target^^}" true
      : > "$FAKE_SWITCH_STATE"
      printf 'active\n'
      ;;
    rollback)
      printf 'test rollback\n' > "$FAKE_SWITCH_ERROR"
      : > "$FAKE_SWITCH_STATE"
      printf 'active\n'
      ;;
    timeout)
      printf '%s\t%s\t%s\t%s\n' "$mode" "$source" "$target" "$poll" > "$FAKE_SWITCH_STATE"
      printf 'preparing\n'
      ;;
  esac
}

case "${1:-}" in
  list)
    if [[ ! -s $state ]]; then
      printf 'No running instances.\n'
      exit 0
    fi
    while IFS=$'\t' read -r id pid path display ready version killable; do
      [[ -n $id ]] || continue
      printf 'Instance %s:\n' "$id"
      printf '  Process ID: %s\n' "$pid"
      printf '  Config path: %s\n' "$path"
      printf '  Display connection: %s\n\n' "$display"
    done < "$state"
    ;;
  ipc)
    shift
    [[ ${1:-} == -i ]] || exit 2
    id="$2"
    shift 2
    [[ ${1:-} == call ]] || exit 2
    shift
    target="${1:-}"
    function="${2:-}"
    shift 2
    row="$(awk -F '\t' -v id="$id" '$1 == id { print; exit }' "$state")"
    [[ -n $row ]] || exit 1
    IFS=$'\t' read -r _ _ _ _ ready version _ <<< "$row"

    case "$target:$function" in
      lifecycle:version) printf '%s\n' "$version" ;;
      lifecycle:ready) printf '%s\n' "$ready" ;;
      variant:current) printf '%s\n' "${version,,}" ;;
      variant:state) switch_state_value "$id" ;;
      variant:error) [[ -r $FAKE_SWITCH_ERROR ]] && cat "$FAKE_SWITCH_ERROR" ;;
      variant:activate)
        requested="${1:-}"
        printf '%s\t%s\t%s\t0\n' \
          "${FAKE_SWITCH_MODE:-success}" "${version,,}" "$requested" \
          > "$FAKE_SWITCH_STATE"
        ;;
      *)
        {
          printf 'id=%s\n' "$id"
          printf 'target=%s\n' "$target"
          printf 'function=%s\n' "$function"
          printf 'argc=%s\n' "$#"
          index=0
          for argument in "$@"; do
            printf 'arg%s=%s\n' "$index" "$argument"
            index=$((index + 1))
          done
        } > "$FAKE_IPC_LOG"
        ;;
    esac
    ;;
  kill)
    shift
    [[ ${1:-} == -i ]] || exit 2
    id="$2"
    row="$(awk -F '\t' -v id="$id" '$1 == id { print; exit }' "$state")"
    [[ -n $row ]] || exit 0
    killable="$(cut -f7 <<< "$row")"
    if [[ $killable == 1 ]]; then
      awk -F '\t' -v id="$id" '$1 != id { print }' "$state" > "$state.tmp"
      mv "$state.tmp" "$state"
    fi
    ;;
  *) exit 2 ;;
esac
FAKE_QS

  cat > "$root/bin/systemd-run" <<'FAKE_SYSTEMD_RUN'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_SYSTEMD_LOG"
while (($#)); do
  if [[ $1 == -- ]]; then shift; break; fi
  shift
done
(($# > 0)) || exit 2
command="$1"
shift

if [[ ${command##*/} != qs ]]; then
  # Front-controller dispatch is tested as submission only. Worker behavior is
  # covered directly with QSR_WORKER_MODE=1.
  exit 0
fi

path=""
while (($#)); do
  if [[ $1 == -p ]]; then path="$2"; break; fi
  shift
done
[[ -n $path ]] || exit 2
[[ ${FAKE_START_MODE:-ready} != fail ]] || exit 1
ready=true
[[ ${FAKE_START_MODE:-ready} != notready ]] || ready=false
printf 'newbar\t%s\t%s\t%s\t%s\t%s\t1\n' \
  "$RANDOM" "$path" "$QSR_DISPLAY_MATCH" "$ready" "${FAKE_BOOT_VERSION:-V1}" \
  >> "$FAKE_INSTANCE_STATE"
FAKE_SYSTEMD_RUN

  cat > "$root/bin/systemctl" <<'FAKE_SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_SYSTEMCTL_LOG"
FAKE_SYSTEMCTL

  chmod 755 "$root/bin/qs" "$root/bin/systemd-run" "$root/bin/systemctl"
}

new_fixture() {
  local name="$1" root
  root="$WORK/$name"
  mkdir -p "$root/config" "$root/state"
  printf 'import QtQuick\nItem {}\n' > "$root/config/shell.qml"
  : > "$root/instances.tsv"
  : > "$root/systemd.log"
  : > "$root/systemctl.log"
  : > "$root/ipc.log"
  : > "$root/switch.state"
  : > "$root/switch.error"
  make_fakes "$root"
  printf '%s\n' "$root"
}

add_instance() {
  local root="$1" id="$2" version="$3" ready="${4:-true}" killable="${5:-1}"
  local path="${6:-$root/config/shell.qml}"
  printf '%s\t%s\t%s\twayland/test-0\t%s\t%s\t%s\n' \
    "$id" "$RANDOM" "$path" "$ready" "$version" "$killable" \
    >> "$root/instances.tsv"
}

run_ctl() {
  local root="$1"
  shift
  HOME="$root/home" \
  PATH="$root/bin:$PATH" \
  WAYLAND_DISPLAY=test-0 \
  QSR_WORKER_MODE=1 \
  QSR_STATE_ROOT="$root/state" \
  QSR_SWITCH_LOCK="$root/state/switch.lock" \
  QSR_CONFIG="$root/config/shell.qml" \
  QSR_READY_ROUNDS=6 \
  QSR_STOP_ROUNDS=4 \
  QSR_STABLE_ROUNDS=2 \
  QSR_POLL_INTERVAL=0.01 \
  QSR_COMMAND_TIMEOUT=2 \
  QSR_SKIP_INSTANCE_VALIDATION=1 \
  QSR_QS_BIN="$root/bin/qs" \
  QSR_SYSTEMD_RUN_BIN="$root/bin/systemd-run" \
  QSR_SYSTEMCTL_BIN="$root/bin/systemctl" \
  QSR_DISPLAY_MATCH=wayland/test-0 \
  FAKE_INSTANCE_STATE="$root/instances.tsv" \
  FAKE_SYSTEMD_LOG="$root/systemd.log" \
  FAKE_SYSTEMCTL_LOG="$root/systemctl.log" \
  FAKE_IPC_LOG="$root/ipc.log" \
  FAKE_SWITCH_STATE="$root/switch.state" \
  FAKE_SWITCH_ERROR="$root/switch.error" \
  FAKE_SWITCH_MODE="${FAKE_SWITCH_MODE:-success}" \
  FAKE_START_MODE="${FAKE_START_MODE:-ready}" \
  FAKE_BOOT_VERSION="${FAKE_BOOT_VERSION:-V1}" \
    "$BARCTL" "$@"
}

test_internal_switch_keeps_instance() {
  local root pid
  root="$(new_fixture internal-switch)"
  add_instance "$root" onlybar V1
  pid="$(cut -f2 "$root/instances.tsv")"

  run_ctl "$root" switch v2

  assert_eq onlybar "$(cut -f1 "$root/instances.tsv")" "internal switch changed instance id"
  assert_eq "$pid" "$(cut -f2 "$root/instances.tsv")" "internal switch changed process id"
  assert_eq V2 "$(cut -f6 "$root/instances.tsv")" "internal switch did not activate V2"
  assert_eq 0 "$(wc -l < "$root/systemd.log")" "internal switch started another unit"
  [[ ! -e $root/state/active-version ]] || fail "controller wrote legacy active-version"
  [[ ! -e $root/state/active-variant ]] || fail "controller wrote VariantHost state"
}

test_internal_rollback_is_reported() {
  local root rc=0
  root="$(new_fixture rollback)"
  add_instance "$root" onlybar V1
  FAKE_SWITCH_MODE=rollback run_ctl "$root" switch v2 >/dev/null 2>&1 || rc=$?
  ((rc != 0)) || fail "rolled-back switch unexpectedly succeeded"
  assert_eq V1 "$(cut -f6 "$root/instances.tsv")" "rollback changed running variant"
  assert_contains onlybar "$root/instances.tsv" "rollback lost the bar instance"
}

test_duplicate_bar_is_normalized() {
  local root count
  root="$(new_fixture duplicate)"
  add_instance "$root" first V2
  add_instance "$root" second V1
  run_ctl "$root" start
  count="$(wc -l < "$root/instances.tsv")"
  assert_eq 1 "$count" "duplicate integrated bars were not normalized"
  assert_contains first "$root/instances.tsv" "first healthy instance was not retained"
}

test_degraded_bar_is_rebuilt() {
  local root
  root="$(new_fixture degraded)"
  add_instance "$root" hung V2 false
  FAKE_BOOT_VERSION=V2 run_ctl "$root" start
  assert_not_contains hung "$root/instances.tsv" "degraded bar was retained"
  assert_contains newbar "$root/instances.tsv" "degraded bar was not rebuilt"
  assert_eq V2 "$(cut -f6 "$root/instances.tsv")" "rebuilt bar lost saved variant behavior"
}

test_foreign_quickshell_is_untouched() {
  local root foreign="$WORK/foreign/shell.qml"
  root="$(new_fixture foreign)"
  add_instance "$root" bar V1
  add_instance "$root" foreign V1 true 1 "$foreign"
  run_ctl "$root" switch v2
  assert_contains foreign "$root/instances.tsv" "foreign Quickshell instance was touched"
  assert_eq 2 "$(wc -l < "$root/instances.tsv")" "foreign instance changed bar count"
}

test_stop_removes_only_integrated_bar() {
  local root foreign="$WORK/stop-foreign/shell.qml"
  root="$(new_fixture stop-only-bar)"
  add_instance "$root" bar V2
  add_instance "$root" foreign V1 true 1 "$foreign"
  run_ctl "$root" stop-wait
  assert_not_contains $'bar\t' "$root/instances.tsv" "integrated bar survived stop-wait"
  assert_contains foreign "$root/instances.tsv" "stop-wait touched a foreign Quickshell instance"
  assert_eq 1 "$(wc -l < "$root/instances.tsv")" "stop-wait changed foreign instance count"
}

test_ipc_preserves_json_and_spaces() {
  local root json='{"logo":"red dragon","enabled":true}'
  root="$(new_fixture ipc)"
  add_instance "$root" onlybar V2
  run_ctl "$root" ipc theme applyLauncher "$json" "second argument"
  assert_contains 'id=onlybar' "$root/ipc.log" "IPC selected integrated bar"
  assert_contains 'argc=2' "$root/ipc.log" "IPC argument count"
  assert_contains "arg0=$json" "$root/ipc.log" "IPC JSON was changed"
  assert_contains 'arg1=second argument' "$root/ipc.log" "IPC spaces were changed"
}

test_front_process_dispatches_worker_unit() {
  local root
  root="$(new_fixture worker-dispatch)"
  HOME="$root/home" PATH="$root/bin:$PATH" WAYLAND_DISPLAY=test-0 \
  QSR_WORKER_MODE=0 QSR_STATE_ROOT="$root/state" \
  QSR_CONFIG="$root/config/shell.qml" \
  QSR_SYSTEMD_RUN_BIN="$root/bin/systemd-run" \
  FAKE_SYSTEMD_LOG="$root/systemd.log" \
    "$BARCTL" switch v2
  assert_contains 'qsrise-worker-' "$root/systemd.log" "front process did not use worker unit"
  assert_contains 'QSR_WORKER_MODE=1' "$root/systemd.log" "worker mode was not propagated"
  assert_contains ' switch v2' "$root/systemd.log" "worker command was not preserved"
}

test_waiting_dispatch_preserves_worker_status_channel() {
  local root
  root="$(new_fixture waiting-dispatch)"
  HOME="$root/home" PATH="$root/bin:$PATH" WAYLAND_DISPLAY=test-0 \
  QSR_WORKER_MODE=0 QSR_STATE_ROOT="$root/state" \
  QSR_CONFIG="$root/config/shell.qml" \
  QSR_SYSTEMD_RUN_BIN="$root/bin/systemd-run" \
  FAKE_SYSTEMD_LOG="$root/systemd.log" \
    "$BARCTL" switch-wait v2
  assert_contains '--wait' "$root/systemd.log" "switch-wait did not wait for worker"
  assert_contains '--pipe' "$root/systemd.log" "switch-wait lost worker exit status channel"
}

test_start_wait_dispatch_preserves_worker_status_channel() {
  local root
  root="$(new_fixture start-waiting-dispatch)"
  HOME="$root/home" PATH="$root/bin:$PATH" WAYLAND_DISPLAY=test-0 \
  QSR_WORKER_MODE=0 QSR_STATE_ROOT="$root/state" \
  QSR_CONFIG="$root/config/shell.qml" \
  QSR_SYSTEMD_RUN_BIN="$root/bin/systemd-run" \
  FAKE_SYSTEMD_LOG="$root/systemd.log" \
    "$BARCTL" start-wait
  assert_contains '--wait' "$root/systemd.log" "start-wait did not wait for worker"
  assert_contains '--pipe' "$root/systemd.log" "start-wait lost worker exit status channel"
  assert_contains ' start' "$root/systemd.log" "start-wait did not dispatch the start worker"
}

test_stale_registry_row_is_ignored() {
  local root pid output rc=0
  root="$(new_fixture stale)"
  add_instance "$root" livebar V1
  pid="$(cut -f2 "$root/instances.tsv")"
  mkdir -p "$root/proc/$pid" "$root/runtime/by-id/livebar" "$root/runtime/by-pid"
  ln -s "$root/bin/qs" "$root/proc/$pid/exe"
  ln -s "$root/runtime/by-id/livebar" "$root/runtime/by-pid/$pid"

  output="$(HOME="$root/home" PATH="$root/bin:$PATH" WAYLAND_DISPLAY=test-0 \
    QSR_STATE_ROOT="$root/state" QSR_CONFIG="$root/config/shell.qml" \
    QSR_QS_BIN="$root/bin/qs" QSR_PROC_ROOT="$root/proc" \
    QSR_RUNTIME_ROOT="$root/runtime" QSR_DISPLAY_MATCH=wayland/test-0 \
    FAKE_INSTANCE_STATE="$root/instances.tsv" FAKE_SWITCH_STATE="$root/switch.state" \
    FAKE_SWITCH_ERROR="$root/switch.error" FAKE_IPC_LOG="$root/ipc.log" \
      "$BARCTL" status)"
  assert_eq v1 "$output" "validated registry instance"

  rm "$root/proc/$pid/exe"
  output="$(HOME="$root/home" PATH="$root/bin:$PATH" WAYLAND_DISPLAY=test-0 \
    QSR_STATE_ROOT="$root/state" QSR_CONFIG="$root/config/shell.qml" \
    QSR_QS_BIN="$root/bin/qs" QSR_PROC_ROOT="$root/proc" \
    QSR_RUNTIME_ROOT="$root/runtime" QSR_DISPLAY_MATCH=wayland/test-0 \
    FAKE_INSTANCE_STATE="$root/instances.tsv" FAKE_SWITCH_STATE="$root/switch.state" \
    FAKE_SWITCH_ERROR="$root/switch.error" FAKE_IPC_LOG="$root/ipc.log" \
      "$BARCTL" status)" || rc=$?
  assert_eq 3 "$rc" "stale registry status code"
  assert_eq stopped "$output" "stale registry row was treated as active"
}

test_internal_switch_keeps_instance
test_internal_rollback_is_reported
test_duplicate_bar_is_normalized
test_degraded_bar_is_rebuilt
test_foreign_quickshell_is_untouched
test_stop_removes_only_integrated_bar
test_ipc_preserves_json_and_spaces
test_front_process_dispatches_worker_unit
test_waiting_dispatch_preserves_worker_status_channel
test_start_wait_dispatch_preserves_worker_status_channel
test_stale_registry_row_is_ignored

printf 'PASS: qs-barctl integrated regression suite\n'
