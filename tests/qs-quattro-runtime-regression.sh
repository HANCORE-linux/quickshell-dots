#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031,SC2218,SC2329
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/contrib/post-boot.d/quickshell-rise"
INSTALLER="$REPO_ROOT/install.sh"
UNINSTALLER="$REPO_ROOT/uninstall.sh"
README="$REPO_ROOT/README.md"
GETTING_STARTED="$REPO_ROOT/docs/getting-started.md"
MAINTENANCE="$REPO_ROOT/docs/maintenance-and-recovery.md"
USAGE="$REPO_ROOT/docs/usage.md"
V1_THEME="$REPO_ROOT/versions/V1/Theme.qml"
V2_THEME="$REPO_ROOT/versions/V1/variants/V2/Theme.qml"
V2_BAR_SLOT="$REPO_ROOT/versions/V1/variants/V2/BarSlot.qml"
V2_CONNECTED_PANEL_SURFACE="$REPO_ROOT/versions/V1/variants/V2/modules/ConnectedPanelSurface.qml"
V1_PALETTE="$REPO_ROOT/versions/V1/Palette.js"
V1_CONTROL_PANEL="$REPO_ROOT/versions/V1/panels/ControlPanel.qml"
V1_ARCH_UPDATER="$REPO_ROOT/versions/V1/panels/ArchUpdaterPanel.qml"
V1_BLUETOOTH_PANEL="$REPO_ROOT/versions/V1/panels/BluetoothPanel.qml"
V1_MPRIS_WIDGET="$REPO_ROOT/versions/V1/modules/MprisWidget.qml"
V1_MPRIS_PANEL="$REPO_ROOT/versions/V1/panels/MprisPanel.qml"
V2_ARCH_UPDATER="$REPO_ROOT/versions/V1/variants/V2/panels/ArchUpdaterPanel.qml"
V2_BLUETOOTH_PANEL="$REPO_ROOT/versions/V1/variants/V2/panels/BluetoothPanel.qml"
V2_MPRIS_WIDGET="$REPO_ROOT/versions/V1/variants/V2/modules/MprisWidget.qml"
V2_MPRIS_PANEL="$REPO_ROOT/versions/V1/variants/V2/panels/MprisPanel.qml"
WORK="$(mktemp -d /tmp/qs-quattro-runtime-test.XXXXXX)"

cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f $1 ]] || fail "$2: missing $1"
}

assert_executable() {
  [[ -x $1 ]] || fail "$2: missing executable $1"
}

assert_no_file() {
  [[ ! -e $1 ]] || fail "$2: unexpected $1"
}

assert_contains() {
  local needle="$1" file="$2" message="$3"
  grep -Fq -- "$needle" "$file" || fail "$message: missing '$needle'"
}

assert_not_contains() {
  local needle="$1" file="$2" message="$3"
  [[ ! -f $file ]] || ! grep -Fq -- "$needle" "$file" || fail "$message: unexpected '$needle'"
}

assert_eq() {
  local want="$1" got="$2" message="$3"
  [[ $want == "$got" ]] || fail "$message: want '$want', got '$got'"
}

assert_before() {
  local first_pattern="$1" second_pattern="$2" file="$3" message="$4"
  local first_line second_line
  first_line="$(grep -n -m1 -- "$first_pattern" "$file" | cut -d: -f1)"
  second_line="$(grep -n -m1 -- "$second_pattern" "$file" | cut -d: -f1)"
  [[ -n $first_line && -n $second_line && $first_line -lt $second_line ]] || \
    fail "$message: '$first_pattern' ($first_line) must precede '$second_pattern' ($second_line)"
}

qml_process_command() {
  local file="$1" process_id="$2"

  awk -v wanted="$process_id" '
    $0 ~ "id: " wanted "$" { found = 1; next }
    found && $0 ~ /command: \["bash", "-c", "/ {
      line = $0
      sub(/^.*command: \["bash", "-c", "/, "", line)
      sub(/"\][[:space:]]*$/, "", line)
      print line
      exit
    }
  ' "$file"
}

probe_rc() {
  local command="$1"
  shift
  local rc=0

  "$@" /usr/bin/bash -c "$command" || rc=$?
  printf '%s\n' "$rc"
}

assert_shared_function_same() {
  local function_name="$1"

  diff -u \
    <(sed -n "/^${function_name}() {$/,/^}$/p" "$HOOK") \
    <(sed -n "/^${function_name}() {$/,/^}$/p" "$UNINSTALLER") \
    >/dev/null || fail "standalone uninstall helper drift: $function_name"
}

make_fake_tools() {
  local root="$1"
  mkdir -p "$root/bin"

  cat > "$root/bin/omarchy" <<'SCRIPT'
#!/usr/bin/env bash
set -u
printf 'omarchy %s\n' "$*" >> "${QSR_TEST_LOG:?}"
if [[ ${QSR_TEST_TOGGLE_FAIL:-0} == 1 && ${1:-} == toggle && ${2:-} == bar ]]; then
  exit 42
fi
if [[ ${1:-} == toggle && ${2:-} == bar ]]; then
  [[ ${QSR_TEST_TOGGLE_NOOP:-0} == 1 ]] && exit 0
  mkdir -p "${QSR_TOGGLE_ROOT:?}"
  case "${3:-}" in
    on)
      : > "$QSR_TOGGLE_ROOT/bar-off"
      if [[ ${QSR_TEST_TOGGLE_TIMEOUT_AFTER_WRITE:-0} == 1 ]]; then
        sleep "${QSR_TEST_TOGGLE_SLEEP:-2}"
      fi
      ;;
    off)
      [[ ${QSR_TEST_ROLLBACK_FAIL:-0} == 1 ]] && exit 43
      rm -f "$QSR_TOGGLE_ROOT/bar-off"
      ;;
    *)   exit 2 ;;
  esac
fi
SCRIPT

  cat > "$root/bin/omarchy-toggle-bar" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT

  cat > "$root/bin/omarchy-toggle-enabled" <<'SCRIPT'
#!/usr/bin/env bash
[[ ${1:-} == bar-off && -f ${QSR_TOGGLE_ROOT:?}/bar-off ]]
SCRIPT

  cat > "$root/bin/pkill" <<'SCRIPT'
#!/usr/bin/env bash
printf 'pkill %s\n' "$*" >> "${QSR_TEST_LOG:?}"
exit 1
SCRIPT

  cat > "$root/bin/setsid" <<'SCRIPT'
#!/usr/bin/env bash
printf 'setsid %s\n' "$*" >> "${QSR_TEST_LOG:?}"
exit 0
SCRIPT

  cat > "$root/bin/waybar" <<'SCRIPT'
#!/usr/bin/env bash
printf 'waybar %s\n' "$*" >> "${QSR_TEST_LOG:?}"
SCRIPT

  chmod 0755 "$root/bin/omarchy" "$root/bin/omarchy-toggle-bar" \
    "$root/bin/omarchy-toggle-enabled" "$root/bin/pkill" \
    "$root/bin/setsid" "$root/bin/waybar"
}

build_installer_fixture() {
  local repo="$WORK/installer-source"

  mkdir -p "$repo/contrib/post-boot.d" "$repo/versions/V1/core" \
    "$repo/versions/V1/variants/V2" \
    "$repo/scripts" "$repo/systemd"
  printf 'import QtQuick\nItem {}\n' > "$repo/versions/V1/shell.qml"
  printf 'import QtQuick\nItem {}\n' > "$repo/versions/V1/VariantRoot.qml"
  printf 'import QtQuick\nItem {}\n' > "$repo/versions/V1/variants/V2/VariantRoot.qml"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$repo/versions/V1/core/qs-system-update.sh"
  chmod 0755 "$repo/versions/V1/core/qs-system-update.sh"

  # Stock-bar ownership remains isolated from the host. Installer readiness is
  # intentionally not stubbed here: the fixture ships the real qs-barctl below
  # and provides only a deterministic Quickshell registry/IPC transport.
  cat > "$repo/contrib/post-boot.d/quickshell-rise" <<'SCRIPT'
#!/usr/bin/env bash
QSR_STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-rise"
QSR_BAR_MARKER="$QSR_STATE_ROOT/owns-omarchy-bar-off"
QSR_BAR_PENDING="$QSR_BAR_MARKER.pending"
QSR_TOGGLE_ROOT="${QSR_TOGGLE_ROOT:-$HOME/.local/state/omarchy/toggles}"
export QSR_STATE_ROOT QSR_BAR_MARKER QSR_BAR_PENDING QSR_TOGGLE_ROOT

qsr_export_omarchy_path() { :; }
qsr_has_quattro() {
  command -v omarchy >/dev/null 2>&1 && command -v omarchy-toggle-bar >/dev/null 2>&1
}
qsr_owns_stock_bar_hide() {
  [[ -f $QSR_BAR_MARKER || -f $QSR_BAR_PENDING ]]
}
qsr_stock_bar_hidden() {
  [[ -f $QSR_TOGGLE_ROOT/bar-off ]]
}
qsr_release_owned_stock_bar() {
  qsr_owns_stock_bar_hide || return 0
  omarchy toggle bar off || return 1
  rm -f "$QSR_BAR_MARKER" "$QSR_BAR_PENDING"
}
qsr_stop_bar_instances() {
  printf 'stop\n' >> "${QSR_TEST_LOG:?}"
}
qsr_start_bar() {
  printf 'start\n' >> "${QSR_TEST_LOG:?}"
}
qsr_wait_for_bar() { printf 'legacy-ready\n' >> "${QSR_TEST_LOG:?}"; }
qsr_hide_stock_bar_owned() {
  printf 'hide\n' >> "${QSR_TEST_LOG:?}"
  qsr_stock_bar_hidden && return 0
  mkdir -p "$QSR_STATE_ROOT" "$QSR_TOGGLE_ROOT"
  (umask 077; : > "$QSR_BAR_PENDING")
  omarchy toggle bar on || return 1
  qsr_stock_bar_hidden || return 1
  mv -f "$QSR_BAR_PENDING" "$QSR_BAR_MARKER"
}
qsr_warn_stock_bar_hide_failure() {
  printf 'fixture hide failure\n' >&2
}
SCRIPT

  cp "$REPO_ROOT/scripts/qs-barctl" "$repo/scripts/qs-barctl"
  cat > "$repo/scripts/qs-proj" <<'SCRIPT'
#!/usr/bin/env bash
exec "$HOME/.config/quickshell/bin/qs-barctl" "$@"
SCRIPT

  cat > "$repo/scripts/qs-shell-check-update.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  cat > "$repo/scripts/qs-shell-apply-update.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  printf '[Unit]\nDescription=fixture\n' > "$repo/systemd/qs-shell-update-check.service"
  printf '[Unit]\nDescription=fixture\n' > "$repo/systemd/qs-shell-update-check.timer"
  chmod 0755 "$repo/contrib/post-boot.d/quickshell-rise" \
    "$repo/scripts/qs-barctl" "$repo/scripts/qs-proj" \
    "$repo/scripts/qs-shell-check-update.sh" "$repo/scripts/qs-shell-apply-update.sh"

  git init "$repo" >/dev/null
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name Test
  git -C "$repo" add -A
  git -C "$repo" update-index --chmod=+x \
    contrib/post-boot.d/quickshell-rise \
    scripts/qs-barctl \
    scripts/qs-proj \
    scripts/qs-shell-check-update.sh \
    scripts/qs-shell-apply-update.sh \
    versions/V1/core/qs-system-update.sh
  git -C "$repo" commit -m fixture >/dev/null

  sed "s|^REPO_URL=.*|REPO_URL=\"$repo\"|" "$INSTALLER" > "$WORK/install-under-test.sh"
  chmod 0755 "$WORK/install-under-test.sh"
}

make_installer_case() {
  local root="$1"

  mkdir -p "$root/home" "$root/run" "$root/state" "$root/toggles"
  : > "$root/actions.log"
  make_fake_tools "$root"

  : > "$root/instances.tsv"
  cat > "$root/bin/qs" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
state="${QSR_TEST_INSTANCE_STATE:?}"

case "${1:-}" in
  list)
    while IFS=$'\t' read -r id pid path display ready version; do
      [[ -n $id ]] || continue
      printf 'Instance %s:\n' "$id"
      printf '  Process ID: %s\n' "$pid"
      printf '  Config path: %s\n' "$path"
      printf '  Display connection: %s\n\n' "$display"
    done < "$state"
    ;;
  -n)
    path=""
    shift
    while (($#)); do
      if [[ $1 == -p ]]; then path="$2"; break; fi
      shift
    done
    [[ -n $path ]] || exit 2
    variant="${QSR_TEST_CONTROLLER_STATUS:-}"
    if [[ -z $variant ]]; then
      variant="$(tr -d '[:space:]' < "${XDG_STATE_HOME:?}/quickshell-rise/active-variant")"
    fi
    printf 'installer-bar\t%s\t%s\tfixture/display\t%s\t%s\n' \
      "$$" "$path" "${QSR_TEST_CONTROLLER_READY:-true}" "${variant^^}" > "$state"
    ;;
  ipc)
    shift
    [[ ${1:-} == -i ]] || exit 2
    id="$2"
    shift 2
    [[ ${1:-} == call ]] || exit 2
    target="$2"
    function="$3"
    printf 'ipc %s %s\n' "$target" "$function" >> "${QSR_TEST_LOG:?}"
    row="$(awk -F '\t' -v wanted="$id" '$1 == wanted { print; exit }' "$state")"
    [[ -n $row ]] || exit 1
    IFS=$'\t' read -r _ _ _ _ ready version <<< "$row"
    case "$target:$function" in
      lifecycle:version) printf '%s\n' "$version" ;;
      lifecycle:ready) printf '%s\n' "$ready" ;;
      variant:state) printf 'active\n' ;;
      *) exit 2 ;;
    esac
    ;;
  kill)
    : > "$state"
    ;;
  *) exit 2 ;;
esac
SCRIPT
  cat > "$root/bin/checkupdates" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  cat > "$root/bin/fc-list" <<'SCRIPT'
#!/usr/bin/env bash
printf 'JetBrainsMono Nerd\nMaterial Symbols Rounded\n'
SCRIPT
  cat > "$root/bin/systemctl" <<'SCRIPT'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "${QSR_TEST_LOG:?}"
exit 0
SCRIPT
  cat > "$root/bin/systemd-run" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'systemd-run %s\n' "$*" >> "${QSR_TEST_LOG:?}"
while (($#)); do
  case "$1" in
    --setenv=*) export "${1#--setenv=}" ;;
    --) shift; break ;;
  esac
  shift
done
(($#)) || exit 2
"$@"
SCRIPT
  chmod 0755 "$root/bin/qs" "$root/bin/checkupdates" "$root/bin/fc-list" \
    "$root/bin/systemctl" "$root/bin/systemd-run"

  cat > "$root/run-installer" <<SCRIPT
#!/usr/bin/env bash
export HOME="$root/home"
export XDG_RUNTIME_DIR="$root/run"
export XDG_STATE_HOME="$root/state"
export QSR_TOGGLE_ROOT="$root/toggles"
export QSR_TEST_LOG="$root/actions.log"
export QSR_TEST_INSTANCE_STATE="$root/instances.tsv"
export QSR_SKIP_INSTANCE_VALIDATION=1
export QSR_DISPLAY_MATCH=fixture/display
export QSR_READY_ROUNDS=3
export QSR_STOP_ROUNDS=3
export QSR_STABLE_ROUNDS=2
export QSR_POLL_INTERVAL=0
export QSR_COMMAND_TIMEOUT=1
export PATH="$root/bin:/usr/bin:/bin"
exec /usr/bin/bash "$WORK/install-under-test.sh" V1 --no-ai-backend "\$@"
SCRIPT
  chmod 0755 "$root/run-installer"
}

run_installer_with_tty() {
  local root="$1" answer="$2" argument
  local command="$root/run-installer"
  shift 2

  for argument in "$@"; do
    printf -v command '%s %q' "$command" "$argument"
  done
  printf '%s\n' "$answer" | script -qefc "$command" /dev/null \
    > "$root/installer.out" 2>&1
}

run_installer_without_tty() {
  local root="$1"
  shift

  QSR_TEST_CONTROLLER_READY="${QSR_TEST_CONTROLLER_READY:-true}" \
  QSR_TEST_CONTROLLER_STATUS="${QSR_TEST_CONTROLLER_STATUS:-}" \
    /usr/bin/setsid -f -w "$root/run-installer" "$@" </dev/null \
    > "$root/installer.out" 2>&1
}

run_installer_preserving_without_tty() {
  local root="$1"

  HOME="$root/home" \
  XDG_RUNTIME_DIR="$root/run" \
  XDG_STATE_HOME="$root/state" \
  QSR_TOGGLE_ROOT="$root/toggles" \
  QSR_TEST_LOG="$root/actions.log" \
  QSR_TEST_INSTANCE_STATE="$root/instances.tsv" \
  QSR_SKIP_INSTANCE_VALIDATION=1 \
  QSR_DISPLAY_MATCH=fixture/display \
  QSR_READY_ROUNDS=3 \
  QSR_STOP_ROUNDS=3 \
  QSR_STABLE_ROUNDS=2 \
  QSR_POLL_INTERVAL=0 \
  QSR_COMMAND_TIMEOUT=1 \
  PATH="$root/bin:/usr/bin:/bin" \
    /usr/bin/bash "$WORK/install-under-test.sh" --no-ai-backend --no-autostart \
      > "$root/installer.out" 2>&1
}

assert_installer_autostart() {
  local root="$1" message="$2"

  assert_file "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise" "$message hook"
  assert_file "$root/state/quickshell-rise/owns-omarchy-bar-off" "$message marker"
  assert_file "$root/toggles/bar-off" "$message stock flag"
  assert_contains "omarchy toggle bar on" "$root/actions.log" "$message toggle"
  assert_before "ipc lifecycle ready" "omarchy toggle bar on" "$root/actions.log" "$message health-before-hide"
}

assert_installer_manual_mode() {
  local root="$1" message="$2"

  assert_no_file "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise" "$message hook"
  assert_no_file "$root/state/quickshell-rise/owns-omarchy-bar-off" "$message marker"
  assert_no_file "$root/toggles/bar-off" "$message stock flag"
  assert_not_contains "omarchy toggle bar" "$root/actions.log" "$message toggle"
  assert_contains "stock bar left visible" "$root/installer.out" "$message hint"
}

case_installer_interactive_prompt_matrix() {
  local prompt="Omarchy Quattro detected. Hide the stock bar and start Rise automatically at login? [Y/n]"
  local root source="$WORK/installer-source"

  command -v script >/dev/null 2>&1 || fail "script is required for installer PTY regressions"
  build_installer_fixture

  root="$WORK/installer-y"
  make_installer_case "$root"
  run_installer_with_tty "$root" y
  assert_contains "$prompt" "$root/installer.out" "yes prompt"
  assert_installer_autostart "$root" "yes answer"

  root="$WORK/installer-enter"
  make_installer_case "$root"
  run_installer_with_tty "$root" ""
  assert_contains "$prompt" "$root/installer.out" "enter prompt"
  assert_installer_autostart "$root" "enter answer"

  root="$WORK/installer-no"
  make_installer_case "$root"
  run_installer_with_tty "$root" n
  assert_contains "$prompt" "$root/installer.out" "no prompt"
  assert_installer_manual_mode "$root" "no answer"

  root="$WORK/installer-invalid"
  make_installer_case "$root"
  run_installer_with_tty "$root" x
  assert_contains "$prompt" "$root/installer.out" "invalid prompt"
  assert_installer_manual_mode "$root" "invalid answer"

  root="$WORK/installer-no-tty"
  make_installer_case "$root"
  run_installer_without_tty "$root"
  assert_not_contains "$prompt" "$root/installer.out" "no-TTY prompt"
  assert_not_contains "No such device or address" "$root/installer.out" "no-TTY device error"
  assert_installer_manual_mode "$root" "no-TTY"

  root="$WORK/installer-flag-on"
  make_installer_case "$root"
  run_installer_with_tty "$root" n --autostart
  assert_not_contains "$prompt" "$root/installer.out" "explicit autostart prompt"
  assert_installer_autostart "$root" "explicit autostart"

  root="$WORK/installer-flag-off"
  make_installer_case "$root"
  run_installer_with_tty "$root" y --no-autostart
  assert_not_contains "$prompt" "$root/installer.out" "explicit no-autostart prompt"
  assert_installer_manual_mode "$root" "explicit no-autostart"

  root="$WORK/installer-hook"
  make_installer_case "$root"
  mkdir -p "$root/home/.config/omarchy/hooks/post-boot.d"
  : > "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  run_installer_with_tty "$root" n
  assert_not_contains "$prompt" "$root/installer.out" "existing hook prompt"
  assert_contains "Existing autostart hook refreshed" "$root/installer.out" "existing hook refresh"
  assert_installer_autostart "$root" "existing hook"

  root="$WORK/installer-legacy"
  make_installer_case "$root"
  rm -f "$root/bin/omarchy-toggle-bar"
  run_installer_with_tty "$root" y
  assert_not_contains "$prompt" "$root/installer.out" "legacy prompt"
  assert_no_file "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise" "legacy hook"
  assert_not_contains "omarchy toggle bar" "$root/actions.log" "legacy toggle"
  assert_contains "pkill -x waybar" "$root/actions.log" "legacy Waybar behavior"

  root="$WORK/installer-v2"
  make_installer_case "$root"
  run_installer_without_tty "$root" V2 --no-autostart
  assert_eq V1 "$(tr -d '[:space:]' < "$root/home/.config/quickshell/bar/.qsrise")" \
    "integrated payload marker"
  assert_eq v2 "$(tr -d '[:space:]' < "$root/state/quickshell-rise/active-variant")" \
    "fresh V2 initial selection"
  assert_file "$root/home/.config/quickshell/bar/variants/V2/VariantRoot.qml" \
    "integrated V2 payload"
  assert_contains "ipc lifecycle ready" "$root/actions.log" \
    "fresh V2 lifecycle readiness"

  root="$WORK/installer-preserve-v2"
  make_installer_case "$root"
  mkdir -p "$root/home/.config/quickshell/bar" "$root/state/quickshell-rise"
  : > "$root/home/.config/quickshell/bar/.qsrise"
  printf 'old config\n' > "$root/home/.config/quickshell/bar/shell.qml"
  printf 'v2\n' > "$root/state/quickshell-rise/active-variant"
  run_installer_preserving_without_tty "$root"
  assert_eq v2 "$(tr -d '[:space:]' < "$root/state/quickshell-rise/active-variant")" \
    "reinstall preserved active V2"
  assert_contains "Keeping previously active UI variant" "$root/installer.out" \
    "reinstall preserve message"

  root="$WORK/installer-legacy-v2-active"
  make_installer_case "$root"
  mkdir -p "$root/home/.config/quickshell/bar" "$root/home/.config/quickshell/bin"
  : > "$root/home/.config/quickshell/bar/.qsrise"
  printf 'old config\n' > "$root/home/.config/quickshell/bar/shell.qml"
  cat > "$root/home/.config/quickshell/bin/qs-barctl" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  status) printf 'v2\n' ;;
  stop-wait) exit 2 ;;
  *) exit 2 ;;
esac
SCRIPT
  chmod 0755 "$root/home/.config/quickshell/bin/qs-barctl"
  if run_installer_without_tty "$root" --no-autostart; then
    fail "installer replaced files while a legacy V2 controller remained active"
  fi
  assert_contains "old config" "$root/home/.config/quickshell/bar/shell.qml" \
    "legacy V2 migration preserved old config"
  assert_contains "still reports 'v2'" "$root/installer.out" \
    "legacy V2 migration diagnostic"

  root="$WORK/installer-readiness-rollback"
  make_installer_case "$root"
  mkdir -p "$root/home/.config/quickshell/bar" "$root/state/quickshell-rise"
  : > "$root/home/.config/quickshell/bar/.qsrise"
  printf 'old config\n' > "$root/home/.config/quickshell/bar/shell.qml"
  printf 'v2\n' > "$root/state/quickshell-rise/active-variant"
  if QSR_TEST_CONTROLLER_READY=false run_installer_without_tty "$root" --no-autostart; then
    fail "installer accepted a new payload that never became ready"
  fi
  assert_contains "old config" "$root/home/.config/quickshell/bar/shell.qml" \
    "readiness rollback restored old payload"
  assert_eq v2 "$(tr -d '[:space:]' < "$root/state/quickshell-rise/active-variant")" \
    "readiness rollback restored active variant"

  root="$WORK/installer-variant-fallback-rollback"
  make_installer_case "$root"
  mkdir -p "$root/home/.config/quickshell/bar" "$root/state/quickshell-rise"
  : > "$root/home/.config/quickshell/bar/.qsrise"
  printf 'old config\n' > "$root/home/.config/quickshell/bar/shell.qml"
  printf 'v1\n' > "$root/state/quickshell-rise/active-variant"
  if QSR_TEST_CONTROLLER_STATUS=v1 run_installer_without_tty "$root" V2 --no-autostart; then
    fail "installer accepted a ready fallback instead of the requested V2"
  fi
  assert_contains "old config" "$root/home/.config/quickshell/bar/shell.qml" \
    "variant fallback restored old payload"
  assert_eq v1 "$(tr -d '[:space:]' < "$root/state/quickshell-rise/active-variant")" \
    "variant fallback restored previous active variant"
  assert_contains "Requested 'v2', but the integrated host became ready as 'v1'" \
    "$root/installer.out" "variant fallback diagnostic"

  git -C "$source" rm versions/V1/core/qs-system-update.sh >/dev/null
  git -C "$source" commit -m missing-system-update-adapter >/dev/null
  root="$WORK/installer-missing-system-update-adapter"
  make_installer_case "$root"
  if run_installer_without_tty "$root" --no-autostart; then
    fail "installer accepted a payload missing the system-update adapter"
  fi
  assert_contains "Integrated V1/V2 payload is incomplete" "$root/installer.out" \
    "missing system-update adapter diagnostic"
  assert_no_file "$root/home/.config/quickshell/bar/shell.qml" \
    "missing system-update adapter install mutation"

  mkdir -p "$source/versions/V1/core"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$source/versions/V1/core/qs-system-update.sh"
  chmod 0644 "$source/versions/V1/core/qs-system-update.sh"
  git -C "$source" add versions/V1/core/qs-system-update.sh
  git -C "$source" update-index --chmod=-x versions/V1/core/qs-system-update.sh
  git -C "$source" commit -m nonexecutable-system-update-adapter >/dev/null
  root="$WORK/installer-nonexecutable-system-update-adapter"
  make_installer_case "$root"
  if run_installer_without_tty "$root" --no-autostart; then
    fail "installer accepted a non-executable system-update adapter"
  fi
  assert_contains "Integrated V1/V2 payload is incomplete" "$root/installer.out" \
    "non-executable system-update adapter diagnostic"
  assert_no_file "$root/home/.config/quickshell/bar/shell.qml" \
    "non-executable system-update adapter install mutation"

  chmod 0755 "$source/versions/V1/core/qs-system-update.sh"
  git -C "$source" add versions/V1/core/qs-system-update.sh
  git -C "$source" update-index --chmod=+x versions/V1/core/qs-system-update.sh
  git -C "$source" commit -m restore-system-update-adapter >/dev/null
  root="$WORK/installer-system-update-adapter"
  make_installer_case "$root"
  run_installer_without_tty "$root" --no-autostart
  assert_executable "$root/home/.config/quickshell/bar/core/qs-system-update.sh" \
    "installed system-update adapter"
}

run_uninstaller() {
  local root="$1"
  HOME="$root/home" \
  XDG_RUNTIME_DIR="$root/run" \
  XDG_STATE_HOME="$root/state" \
  QSR_RUNTIME_ROOT="$root/run/quickshell" \
  QSR_PROC_ROOT="${QSR_PROC_ROOT:-/proc}" \
  QSR_TOGGLE_ROOT="$root/toggles" \
  QSR_TEST_LOG="$root/actions.log" \
  QSR_POLL_INTERVAL=0 \
  QSR_STOP_ROUNDS=3 \
  QSR_STABLE_ROUNDS=1 \
  QSR_COMMAND_TIMEOUT=1 \
  PATH="$root/bin:/usr/bin:/bin" \
    bash "$UNINSTALLER"
}

case_runtime_toggle_ownership() (
  local root="$WORK/runtime-toggle"
  mkdir -p "$root/home" "$root/run" "$root/state" "$root/toggles"
  : > "$root/actions.log"
  make_fake_tools "$root"

  export HOME="$root/home"
  export XDG_RUNTIME_DIR="$root/run"
  export XDG_STATE_HOME="$root/state"
  export QSR_RUNTIME_ROOT="$root/run/quickshell"
  export QSR_TOGGLE_ROOT="$root/toggles"
  export QSR_TEST_LOG="$root/actions.log"
  export QSR_POLL_INTERVAL=0
  export QSR_COMMAND_TIMEOUT=1
  export QSR_RUNTIME_LIB_ONLY=1
  export PATH="$root/bin:/usr/bin:/bin"
  # shellcheck source=/dev/null
  source "$HOOK"

  qsr_has_quattro || fail "runtime capability gate missed fake Quattro"
  qsr_hide_stock_bar_owned || fail "could not hide visible fake stock bar"
  assert_file "$QSR_BAR_MARKER" "visible stock bar ownership"
  assert_file "$QSR_TOGGLE_ROOT/bar-off" "hidden stock flag"
  qsr_hide_stock_bar_owned || fail "owned hide was not idempotent"
  assert_eq 1 "$(grep -c 'omarchy toggle bar on' "$QSR_TEST_LOG")" "hide toggle count"

  qsr_release_owned_stock_bar || fail "could not release owned stock bar"
  assert_no_file "$QSR_BAR_MARKER" "released ownership marker"
  assert_no_file "$QSR_TOGGLE_ROOT/bar-off" "visible stock flag"
  assert_contains "omarchy toggle bar off" "$QSR_TEST_LOG" "show direction"

  mkdir -p "$QSR_STATE_ROOT" "$QSR_TOGGLE_ROOT"
  : > "$QSR_BAR_PENDING"
  : > "$QSR_TOGGLE_ROOT/bar-off"
  qsr_hide_stock_bar_owned || fail "pending hide transaction was not recovered"
  assert_file "$QSR_BAR_MARKER" "pending transaction promotion"
  assert_no_file "$QSR_BAR_PENDING" "pending transaction cleanup"
  qsr_release_owned_stock_bar || fail "promoted transaction could not be released"

  : > "$QSR_TOGGLE_ROOT/bar-off"
  : > "$QSR_TEST_LOG"
  qsr_hide_stock_bar_owned || fail "pre-hidden stock bar should be accepted"
  assert_no_file "$QSR_BAR_MARKER" "foreign hidden state must not be claimed"
  assert_not_contains "omarchy toggle bar" "$QSR_TEST_LOG" "foreign hidden state mutation"

  rm -f "$QSR_TOGGLE_ROOT/bar-off"
  export QSR_TEST_TOGGLE_NOOP=1
  if qsr_hide_stock_bar_owned; then
    fail "no-op toggle was accepted without verified bar-off state"
  fi
  assert_no_file "$QSR_BAR_MARKER" "no-op toggle ownership"
  unset QSR_TEST_TOGGLE_NOOP

  # A timed-out command may already have written bar-off. The failed hide must
  # restore visibility before dropping its pending ownership record.
  : > "$QSR_TEST_LOG"
  export QSR_COMMAND_TIMEOUT=0.05
  export QSR_TEST_TOGGLE_TIMEOUT_AFTER_WRITE=1
  if qsr_hide_stock_bar_owned; then
    fail "timed-out hide was accepted"
  fi
  assert_no_file "$QSR_TOGGLE_ROOT/bar-off" "timeout-after-write rollback"
  assert_no_file "$QSR_BAR_MARKER" "timed-out hide ownership marker"
  assert_no_file "$QSR_BAR_PENDING" "timed-out hide pending marker"
  assert_contains "omarchy toggle bar on" "$QSR_TEST_LOG" "timed-out hide direction"
  assert_contains "omarchy toggle bar off" "$QSR_TEST_LOG" "timeout rollback direction"
  qsr_warn_stock_bar_hide_failure 2> "$root/visible-warning.log"
  assert_contains "it remains visible" "$root/visible-warning.log" "verified rollback warning"
  assert_not_contains "omarchy toggle bar off" "$root/visible-warning.log" "unnecessary recovery command"

  # If the compensating toggle also fails, ownership evidence must survive so
  # a later post-boot run or uninstall can recover the hidden stock bar.
  : > "$QSR_TEST_LOG"
  export QSR_TEST_ROLLBACK_FAIL=1
  if qsr_hide_stock_bar_owned; then
    fail "hide with failed rollback was accepted"
  fi
  assert_file "$QSR_TOGGLE_ROOT/bar-off" "failed rollback hidden state"
  assert_no_file "$QSR_BAR_MARKER" "failed rollback final marker"
  assert_file "$QSR_BAR_PENDING" "failed rollback recovery evidence"
  assert_contains "omarchy toggle bar off" "$QSR_TEST_LOG" "failed rollback direction"
  qsr_warn_stock_bar_hide_failure 2> "$root/hidden-warning.log"
  assert_contains "omarchy toggle bar off" "$root/hidden-warning.log" "failed rollback recovery command"
  unset QSR_TEST_ROLLBACK_FAIL
  unset QSR_TEST_TOGGLE_TIMEOUT_AFTER_WRITE
  qsr_release_owned_stock_bar || fail "could not clean up failed rollback fixture"
)

case_runtime_postboot_order_and_fail_open() (
  local root="$WORK/runtime-postboot"
  mkdir -p "$root/home" "$root/run" "$root/state" "$root/toggles"
  : > "$root/actions.log"
  make_fake_tools "$root"

  export HOME="$root/home"
  export XDG_RUNTIME_DIR="$root/run"
  export XDG_STATE_HOME="$root/state"
  export QSR_RUNTIME_ROOT="$root/run/quickshell"
  export QSR_TOGGLE_ROOT="$root/toggles"
  export QSR_TEST_LOG="$root/actions.log"
  export QSR_POLL_INTERVAL=0
  export QSR_COMMAND_TIMEOUT=1
  export QSR_RUNTIME_LIB_ONLY=1
  export PATH="$root/bin:/usr/bin:/bin"
  # shellcheck source=/dev/null
  source "$HOOK"

  qsr_start_bar() { printf 'start\n' >> "$QSR_TEST_LOG"; }
  qsr_wait_for_bar() { printf 'ready\n' >> "$QSR_TEST_LOG"; }
  qsr_hide_stock_bar_owned() { printf 'hide\n' >> "$QSR_TEST_LOG"; }
  qsr_post_boot_main
  assert_eq $'start\nready\nhide' "$(cat "$QSR_TEST_LOG")" "post-boot start/ready/hide order"

  # Reload pristine functions, then simulate a failed start with an owned flag.
  : > "$QSR_TEST_LOG"
  # shellcheck source=/dev/null
  source "$HOOK"
  qsr_live_bar_pids() { return 1; }
  if qsr_start_bar; then
    fail "registry read failure was treated as permission to start another bar"
  fi
  assert_not_contains "setsid" "$QSR_TEST_LOG" "start after registry failure"

  # Reload once more before simulating a failed real start with owned state.
  # shellcheck source=/dev/null
  source "$HOOK"
  mkdir -p "$QSR_STATE_ROOT" "$QSR_TOGGLE_ROOT"
  : > "$QSR_BAR_MARKER"
  : > "$QSR_TOGGLE_ROOT/bar-off"
  qsr_start_bar() { return 1; }
  qsr_post_boot_main 2>/dev/null
  assert_no_file "$QSR_BAR_MARKER" "failed start marker release"
  assert_no_file "$QSR_TOGGLE_ROOT/bar-off" "failed start stock restore"
)

case_runtime_postboot_uses_controller_selection() (
  local root="$WORK/postboot-controller"
  mkdir -p "$root/home/.config/quickshell/bin"
  : > "$root/home/controller.log"
  cat > "$root/home/.config/quickshell/bin/qs-barctl" <<'SCRIPT'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$HOME/controller.log"
case "${1:-}" in
  status)
    if [[ -f $HOME/controller.active ]]; then
      printf 'v2\n'
      exit 0
    fi
    printf 'stopped\n'
    exit 3
    ;;
  start)
    : > "$HOME/controller.active"
    ;;
  *) exit 2 ;;
esac
SCRIPT
  chmod 0755 "$root/home/.config/quickshell/bin/qs-barctl"

  export HOME="$root/home"
  export QSR_BARCTL="$root/home/.config/quickshell/bin/qs-barctl"
  export QSR_READY_ROUNDS=2
  export QSR_POLL_INTERVAL=0.01
  export QSR_RUNTIME_LIB_ONLY=1
  # shellcheck source=/dev/null
  source "$HOOK"
  qsr_start_selected_bar
  qsr_wait_for_selected_bar
  qsr_start_selected_bar

  assert_contains 'start' "$root/home/controller.log" "post-boot did not ask the controller to start the saved variant"
  assert_eq 1 "$(grep -Fc start "$root/home/controller.log")" "healthy controller state was started twice"
  assert_contains 'status' "$root/home/controller.log" "post-boot did not verify controller readiness"
)

case_registry_live_health_and_stop() (
  local root="$WORK/registry"
  local config="$root/home/.config/quickshell/bar/shell.qml"
  local runtime="$root/run/quickshell"
  local instance="$runtime/by-id/live-instance"
  local stale="$runtime/by-id/stale-instance"
  local path_id bar_pid live

  mkdir -p "$root/bin" "$(dirname "$config")" "$instance" "$stale" \
    "$runtime/by-path" "$runtime/by-pid"
  : > "$config"
  printf 'Configuration Loaded\n' > "$instance/log.log"
  : > "$instance/instance.lock"
  : > "$stale/instance.lock"

  # Deliberately make qs resolve to a different executable. The live process is
  # the bare quickshell candidate, exercising the crash-relaunch allowance.
  ln -s /usr/bin/sleep "$root/bin/qs"
  ln -s "$(command -v python3)" "$root/bin/quickshell"
  cat > "$root/bin/pkill" <<'SCRIPT'
#!/usr/bin/env bash
exit 1
SCRIPT
  chmod 0755 "$root/bin/pkill"

  path_id="$(printf '%s' "$config" | md5sum | awk '{print $1}')"
  mkdir -p "$runtime/by-path/$path_id"
  ln -s "$instance" "$runtime/by-path/$path_id/live"
  ln -s "$stale" "$runtime/by-path/$path_id/stale"

  "$root/bin/quickshell" -c 'import fcntl, sys, time; f = open(sys.argv[1], "w"); fcntl.lockf(f, fcntl.LOCK_EX | fcntl.LOCK_NB); time.sleep(300)' \
    "$instance/instance.lock" &
  bar_pid=$!
  trap 'kill "$bar_pid" 2>/dev/null || true' EXIT
  ln -s "$instance" "$runtime/by-pid/$bar_pid"

  for _ in {1..50}; do
    lslocks -n -o PID,PATH | grep -Fq "$instance/instance.lock" && break
    sleep 0.02
  done

  export HOME="$root/home"
  export XDG_STATE_HOME="$root/state"
  export QSR_CONFIG_PATH="$config"
  export QSR_RUNTIME_ROOT="$runtime"
  export QSR_PROC_ROOT=/proc
  export QSR_READY_ROUNDS=2
  export QSR_STOP_ROUNDS=20
  export QSR_STABLE_ROUNDS=2
  export QSR_POLL_INTERVAL=0.02
  export QSR_COMMAND_TIMEOUT=1
  export QSR_RUNTIME_LIB_ONLY=1
  export PATH="$root/bin:/usr/bin:/bin"
  # shellcheck source=/dev/null
  source "$HOOK"

  live="$(qsr_live_bar_pids)" || fail "direct registry scan failed"
  assert_eq "$bar_pid" "$live" "live registry PID"

  rm -f "$runtime/by-pid/$bar_pid"
  assert_eq "" "$(qsr_live_bar_pids)" "missing by-pid cross-check"
  ln -s "$stale" "$runtime/by-pid/$bar_pid"
  assert_eq "" "$(qsr_live_bar_pids)" "wrong by-pid cross-check"
  rm -f "$runtime/by-pid/$bar_pid"
  ln -s "$instance" "$runtime/by-pid/$bar_pid"

  qsr_stop_registered_bars || fail "registered stop did not stabilize"
  wait "$bar_pid" 2>/dev/null || true
  if kill -0 "$bar_pid" 2>/dev/null; then
    fail "registered lock owner survived TERM/rescan"
  fi
)

prepare_owned_install() {
  local root="$1"
  mkdir -p "$root/home/.config/quickshell/bar" "$root/state/quickshell-rise" \
    "$root/toggles" "$root/run"
  : > "$root/home/.config/quickshell/bar/.qsrise"
  : > "$root/home/.config/quickshell/bar/shell.qml"
  : > "$root/state/quickshell-rise/owns-omarchy-bar-off"
  : > "$root/toggles/bar-off"
  : > "$root/actions.log"
}

case_uninstall_owned_backup_provider() {
  local root="$WORK/uninstall-owned"
  make_fake_tools "$root"
  prepare_owned_install "$root"
  mkdir -p "$root/home/.config/quickshell/bar.bak.20260719-120000"
  printf 'foreign backup\n' > "$root/home/.config/quickshell/bar.bak.20260719-120000/shell.qml"
  mkdir -p "$root/home/.config/omarchy/hooks/post-boot.d"
  : > "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"

  run_uninstaller "$root" >/dev/null
  assert_no_file "$root/state/quickshell-rise/owns-omarchy-bar-off" "uninstall marker release"
  assert_no_file "$root/toggles/bar-off" "uninstall stock visibility"
  assert_contains "foreign backup" "$root/home/.config/quickshell/bar/shell.qml" "backup restore"
  assert_contains "omarchy toggle bar off" "$root/actions.log" "uninstall show-before-stop"
  assert_not_contains "setsid quickshell" "$root/actions.log" "double-provider restore"
}

case_uninstall_foreign_hidden_state() {
  local root="$WORK/uninstall-foreign-state"
  make_fake_tools "$root"
  mkdir -p "$root/home/.config/quickshell/bar" "$root/toggles" "$root/run"
  : > "$root/home/.config/quickshell/bar/.qsrise"
  : > "$root/home/.config/quickshell/bar/shell.qml"
  : > "$root/toggles/bar-off"
  : > "$root/actions.log"

  run_uninstaller "$root" >/dev/null
  assert_file "$root/toggles/bar-off" "foreign hidden state preservation"
  assert_not_contains "omarchy toggle bar" "$root/actions.log" "foreign toggle mutation"
  assert_not_contains "restart waybar" "$root/actions.log" "Quattro Waybar restart"
}

case_uninstall_toggle_failure_aborts() {
  local root="$WORK/uninstall-toggle-fail"
  make_fake_tools "$root"
  prepare_owned_install "$root"
  mkdir -p "$root/home/.config/omarchy/hooks/post-boot.d"
  : > "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"

  if QSR_TEST_TOGGLE_FAIL=1 run_uninstaller "$root" >/dev/null 2>&1; then
    fail "uninstaller accepted failed Quattro toggle"
  fi
  assert_file "$root/home/.config/quickshell/bar/.qsrise" "toggle failure config preservation"
  assert_file "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise" "toggle failure hook preservation"
  assert_file "$root/state/quickshell-rise/owns-omarchy-bar-off" "toggle failure marker preservation"
}

case_uninstall_legacy_and_generic() {
  local legacy="$WORK/uninstall-legacy" generic="$WORK/uninstall-generic"

  make_fake_tools "$legacy"
  rm -f "$legacy/bin/omarchy-toggle-bar" "$legacy/bin/omarchy-toggle-enabled"
  mkdir -p "$legacy/home/.config/quickshell/bar" "$legacy/run"
  : > "$legacy/home/.config/quickshell/bar/.qsrise"
  : > "$legacy/actions.log"
  run_uninstaller "$legacy" >/dev/null
  assert_contains "omarchy restart waybar" "$legacy/actions.log" "legacy Waybar restore"

  make_fake_tools "$generic"
  rm -f "$generic/bin/omarchy" "$generic/bin/omarchy-toggle-bar" "$generic/bin/omarchy-toggle-enabled"
  mkdir -p "$generic/home/.config/quickshell/bar" "$generic/run"
  : > "$generic/home/.config/quickshell/bar/.qsrise"
  : > "$generic/actions.log"
  run_uninstaller "$generic" >/dev/null
  assert_contains "setsid waybar" "$generic/actions.log" "generic Waybar restore"
}

case_uninstall_removes_lifecycle_controller() {
  local root="$WORK/uninstall-controller"
  make_fake_tools "$root"
  mkdir -p "$root/home/.config/quickshell/bar" \
    "$root/home/.config/quickshell/bin" \
    "$root/state/quickshell-rise" "$root/toggles" "$root/run"
  : > "$root/home/.config/quickshell/bar/.qsrise"
  : > "$root/home/.config/quickshell/bar/shell.qml"
  : > "$root/home/.config/quickshell/bin/qs-barctl"
  printf 'v2\n' > "$root/state/quickshell-rise/active-version"
  printf 'v2\n' > "$root/state/quickshell-rise/active-variant"
  : > "$root/state/quickshell-rise/switch.lock"
  : > "$root/actions.log"

  run_uninstaller "$root" >/dev/null

  assert_no_file "$root/home/.config/quickshell/bin/qs-barctl" "uninstall lifecycle controller"
  assert_no_file "$root/state/quickshell-rise/active-version" "uninstall active version state"
  assert_no_file "$root/state/quickshell-rise/active-variant" "uninstall active variant state"
  assert_no_file "$root/state/quickshell-rise/switch.lock" "uninstall switch lock"
  [[ ! -d $root/state/quickshell-rise ]] || fail "uninstall left lifecycle state directory"
}

case_uninstall_keeps_ownership_but_removes_lifecycle_state() {
  local root="$WORK/uninstall-marker-without-toggle"
  make_fake_tools "$root"
  rm -f "$root/bin/omarchy-toggle-bar"
  mkdir -p "$root/home/.config/quickshell/bar" "$root/state/quickshell-rise" \
    "$root/toggles" "$root/run"
  : > "$root/home/.config/quickshell/bar/.qsrise"
  : > "$root/home/.config/quickshell/bar/shell.qml"
  : > "$root/state/quickshell-rise/owns-omarchy-bar-off"
  printf 'v2\n' > "$root/state/quickshell-rise/active-version"
  printf 'v2\n' > "$root/state/quickshell-rise/active-variant"
  : > "$root/state/quickshell-rise/switch.lock"
  : > "$root/actions.log"

  run_uninstaller "$root" >/dev/null

  assert_file "$root/state/quickshell-rise/owns-omarchy-bar-off" "unavailable-toggle ownership marker"
  assert_no_file "$root/state/quickshell-rise/active-version" "marker case legacy variant state"
  assert_no_file "$root/state/quickshell-rise/active-variant" "marker case active variant state"
  assert_no_file "$root/state/quickshell-rise/switch.lock" "marker case switch lock"
}

case_uninstall_registry_failure_aborts() {
  local root="$WORK/uninstall-registry-fail" config path_id
  make_fake_tools "$root"
  mkdir -p "$root/home/.config/quickshell/bar" "$root/run/quickshell/by-path" "$root/toggles"
  : > "$root/home/.config/quickshell/bar/.qsrise"
  : > "$root/home/.config/quickshell/bar/shell.qml"
  : > "$root/actions.log"
  config="$root/home/.config/quickshell/bar/shell.qml"
  path_id="$(printf '%s' "$config" | md5sum | awk '{print $1}')"
  mkdir -p "$root/run/quickshell/by-path/$path_id"
  ln -s /usr/bin/bash "$root/bin/qs"
  cat > "$root/bin/lslocks" <<'SCRIPT'
#!/usr/bin/env bash
exit 70
SCRIPT
  chmod 0755 "$root/bin/lslocks"

  if run_uninstaller "$root" >/dev/null 2>&1; then
    fail "uninstaller treated failed lslocks as an empty registry"
  fi
  assert_file "$root/home/.config/quickshell/bar/.qsrise" "registry failure config preservation"
}

case_omarchy_service_backend_probe_matrix() {
  local root="$WORK/omarchy-service-probes"
  local idle_probe notif_probe
  mkdir -p "$root/bin" \
    "$root/omarchy/shell/plugins/services/idle" \
    "$root/omarchy/shell/plugins/notifications"
  : > "$root/omarchy/shell/plugins/services/idle/manifest.json"
  : > "$root/omarchy/shell/plugins/notifications/manifest.json"

  cat > "$root/bin/omarchy-shell" <<'SCRIPT'
#!/usr/bin/env bash
set -u
case "${1:-} ${2:-}" in
  "idle status")
    exit "${QSR_TEST_IDLE_RC:-0}"
    ;;
  "notifications ping")
    [[ ${QSR_TEST_NOTIF_RC:-0} == 0 ]] || exit "${QSR_TEST_NOTIF_RC}"
    printf '%s\n' "${QSR_TEST_NOTIF_REPLY:-ok}"
    ;;
  *)
    exit 64
    ;;
esac
SCRIPT
  chmod 0755 "$root/bin/omarchy-shell"

  idle_probe="$(qml_process_command "$V1_THEME" idleBackendProc)"
  notif_probe="$(qml_process_command "$V1_THEME" notifBackendProc)"
  [[ -n $idle_probe && -n $notif_probe ]] \
    || fail "Omarchy service backend probes are missing"
  assert_eq "$idle_probe" "$(qml_process_command "$V2_THEME" idleBackendProc)" \
    "V1/V2 idle backend probe"
  assert_eq "$notif_probe" "$(qml_process_command "$V2_THEME" notifBackendProc)" \
    "V1/V2 notification backend probe"

  assert_eq 0 "$(probe_rc "$idle_probe" env \
    PATH="$root/bin:/usr/bin:/bin" OMARCHY_PATH="$root/omarchy")" \
    "enabled Omarchy idle service"
  assert_eq 0 "$(probe_rc "$notif_probe" env \
    PATH="$root/bin:/usr/bin:/bin" OMARCHY_PATH="$root/omarchy")" \
    "enabled Omarchy notification service"

  assert_eq 1 "$(probe_rc "$idle_probe" env \
    PATH="$root/bin:/usr/bin:/bin" OMARCHY_PATH="$root/omarchy" QSR_TEST_IDLE_RC=1)" \
    "disabled Omarchy idle service"
  assert_eq 1 "$(probe_rc "$notif_probe" env \
    PATH="$root/bin:/usr/bin:/bin" OMARCHY_PATH="$root/omarchy" QSR_TEST_NOTIF_RC=1)" \
    "disabled Omarchy notification service"
  assert_eq 1 "$(probe_rc "$notif_probe" env \
    PATH="$root/bin:/usr/bin:/bin" OMARCHY_PATH="$root/omarchy" QSR_TEST_NOTIF_REPLY=stale)" \
    "invalid Omarchy notification probe response"

  rm "$root/bin/omarchy-shell"
  assert_eq 1 "$(probe_rc "$idle_probe" env \
    PATH="$root/bin:/usr/bin:/bin" OMARCHY_PATH="$root/omarchy")" \
    "unreachable Quattro idle service"
  assert_eq 1 "$(probe_rc "$notif_probe" env \
    PATH="$root/bin:/usr/bin:/bin" OMARCHY_PATH="$root/omarchy")" \
    "unreachable Quattro notification service"

  rm "$root/omarchy/shell/plugins/services/idle/manifest.json" \
    "$root/omarchy/shell/plugins/notifications/manifest.json"
  assert_eq 2 "$(probe_rc "$idle_probe" env \
    PATH="$root/bin:/usr/bin:/bin" OMARCHY_PATH="$root/omarchy")" \
    "legacy idle backend classification"
  assert_eq 2 "$(probe_rc "$notif_probe" env \
    PATH="$root/bin:/usr/bin:/bin" OMARCHY_PATH="$root/omarchy")" \
    "legacy notification backend classification"
}

case_bluetooth_settings_launcher_matrix() {
  local root="$WORK/bluetooth-settings-launcher" launch_command
  mkdir -p "$root/bin"

  cat > "$root/bin/omarchy-launch-bluetooth" <<'SCRIPT'
#!/bin/bash
printf 'legacy\n' >> "${QSR_BT_LOG:?}"
SCRIPT
  cat > "$root/bin/omarchy-launch-or-focus-tui" <<'SCRIPT'
#!/bin/bash
printf 'quattro:%s\n' "$*" >> "${QSR_BT_LOG:?}"
SCRIPT
  cat > "$root/bin/bluetui" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
  cat > "$root/bin/bluetoothctl" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
  cat > "$root/bin/rfkill" <<'SCRIPT'
#!/bin/bash
printf 'rfkill:%s\n' "$*" >> "${QSR_BT_LOG:?}"
SCRIPT
  cat > "$root/bin/notify-send" <<'SCRIPT'
#!/bin/bash
printf 'notify:%s\n' "$*" >> "${QSR_BT_LOG:?}"
SCRIPT
  chmod 0755 "$root/bin/"*
  : > "$root/actions.log"
  export QSR_BT_LOG="$root/actions.log"

  launch_command="$(sed -n 's/^[[:space:]]*readonly property string launchBtCmd:[[:space:]]*"\(.*\)"$/\1/p' "$V1_THEME")"
  [[ -n $launch_command ]] || fail "V1 Bluetooth settings launcher is not a single shell command"
  [[ $launch_command != *\\* ]] \
    || fail "Bluetooth settings launcher test requires an escape-free QML string"
  assert_eq "$launch_command" \
    "$(sed -n 's/^[[:space:]]*readonly property string launchBtCmd:[[:space:]]*"\(.*\)"$/\1/p' "$V2_THEME")" \
    "V1/V2 Bluetooth settings launcher"

  PATH="$root/bin" /usr/bin/bash -c "$launch_command"
  assert_eq "legacy" "$(cat "$root/actions.log")" "Omarchy 3.8 Bluetooth launcher"

  : > "$root/actions.log"
  rm "$root/bin/omarchy-launch-bluetooth"
  PATH="$root/bin" /usr/bin/bash -c "$launch_command"
  assert_eq $'rfkill:unblock bluetooth\nquattro:bluetui' \
    "$(cat "$root/actions.log")" "bluetui fallback"

  : > "$root/actions.log"
  rm "$root/bin/bluetui"
  PATH="$root/bin" /usr/bin/bash -c "$launch_command"
  assert_eq $'rfkill:unblock bluetooth\nquattro:bluetoothctl' \
    "$(cat "$root/actions.log")" "Omarchy Quattro bluetoothctl fallback"

  : > "$root/actions.log"
  rm "$root/bin/bluetoothctl"
  PATH="$root/bin" /usr/bin/bash -c "$launch_command"
  assert_contains "notify:" "$root/actions.log" "missing Bluetooth settings backend notification"

  : > "$root/actions.log"
  rm "$root/bin/notify-send"
  PATH="$root/bin" /usr/bin/bash -c "$launch_command"
  assert_eq "" "$(cat "$root/actions.log")" "missing Bluetooth backend and notifier"
}

case_static_contracts() {
  local shared_function

  assert_not_contains "qs list --all" "$README" "README unsafe instance query"
  assert_contains "qsr_has_quattro" "$INSTALLER" "installer capability gate"
  assert_contains "hook_was_installed" "$INSTALLER" "installer existing-hook gate"
  assert_contains "if : 2>/dev/null </dev/tty; then" "$INSTALLER" "installer usable-TTY probe"
  assert_before "Omarchy Quattro detected" "hide_stock_after_install=false" "$INSTALLER" "prompt before hide gating"
  assert_contains "qsr_hide_stock_bar_owned" "$INSTALLER" "installer ownership hide"
  assert_contains "pkill -x waybar" "$INSTALLER" "legacy/generic Waybar overlap guard"
  assert_contains "if [[ \"\$quattro_mode\" != true ]]" "$INSTALLER" "Waybar Quattro exclusion"
  assert_contains "\"\$installer_barctl\" start-wait" "$INSTALLER" "installer lifecycle readiness"
  assert_contains "\"\$installer_barctl\" status" "$INSTALLER" "installer exact variant status"
  assert_not_contains "if ! qsr_start_bar || ! qsr_wait_for_bar" "$INSTALLER" "legacy installer readiness"
  assert_before "if ! verify_selected_variant" "pkill -x waybar" "$INSTALLER" "health before Waybar stop"
  assert_before "if ! verify_selected_variant" "qsr_hide_stock_bar_owned" "$INSTALLER" "health before Quattro hide"
  assert_before "if ! qsr_release_owned_stock_bar" "if ! qsr_stop_bar_instances" "$UNINSTALLER" "show before stop"
  assert_contains "left it stopped because the Omarchy stock bar is active" "$UNINSTALLER" "backup double-bar guard"
  assert_contains "Other Hyprland systems" "$MAINTENANCE" "non-Omarchy compatibility docs"
  assert_contains "Flags let non-interactive installs choose autostart" \
    "$GETTING_STARTED" "non-interactive prompt docs"
  assert_contains "hypridle cava)" "$INSTALLER" "CAVA optional dependency check"
  assert_contains "real-time CAVA waveform" "$USAGE" "CAVA optional dependency docs"
  assert_contains 'property bool panelInsetReady: false' \
    "$V2_THEME" "V2 connected panel geometry readiness"
  assert_not_contains 'activePanelCaretX' \
    "$V2_THEME" "V2 coordinate-based panel ownership"
  assert_contains 'required property bool ownerActive' \
    "$V2_CONNECTED_PANEL_SURFACE" "V2 explicit connected panel ownership"
  assert_contains 'if (!ownerActive || !root) return' \
    "$V2_CONNECTED_PANEL_SURFACE" "V2 inactive panel geometry rejection"
  assert_contains 'readonly property bool hostGeometryCoversTarget:' \
    "$V2_CONNECTED_PANEL_SURFACE" "V2 first-map host geometry guard"
  assert_contains 'if (reveal <= 0.001 || !hostGeometryCoversTarget)' \
    "$V2_CONNECTED_PANEL_SURFACE" "V2 provisional connected panel anchor"
  assert_contains 'root.setPanelInsetX(targetX)' \
    "$V2_CONNECTED_PANEL_SURFACE" "V2 provisional connected panel geometry"
  assert_contains 'root.setPanelInsetX(resolvedTargetX)' \
    "$V2_CONNECTED_PANEL_SURFACE" "V2 connected panel geometry ownership"
  assert_contains 'onTargetXChanged: publishResolvedTarget()' \
    "$V2_CONNECTED_PANEL_SURFACE" "V2 connected panel style-change retry"
  assert_contains '&& barSlot.root.panelInsetReady' \
    "$V2_BAR_SLOT" "V2 connected border readiness gate"
  assert_not_contains 'bridgeOpen' \
    "$V2_BAR_SLOT" "V2 stale connected border fallback"
  local connected_panel connected_panel_count=0
  while IFS= read -r connected_panel; do
    connected_panel_count=$((connected_panel_count + 1))
    assert_contains 'ownerActive:' \
      "$connected_panel" "V2 connected panel owner binding"
  done < <(grep -Rl --include='*.qml' 'ConnectedPanelSurface {' \
    "$REPO_ROOT/versions/V1/variants/V2/panels")
  assert_eq "20" "$connected_panel_count" "V2 connected panel owner coverage"
  for theme_file in "$V1_THEME" "$V2_THEME"; do
    assert_contains 'omarchy-shell idle status' "$theme_file" "live Omarchy idle service probe"
    assert_contains 'omarchy-shell notifications ping' "$theme_file" "live Omarchy notification service probe"
    assert_not_contains '/usr/share/omarchy/shell/plugins/services/idle/manifest.json' \
      "$theme_file" "stale Omarchy idle manifest probe"
    assert_not_contains '/usr/share/omarchy/shell/plugins/notifications/manifest.json' \
      "$theme_file" "stale Omarchy notification manifest probe"
    assert_contains 'readonly property string omarchyShellConfigPath:' \
      "$theme_file" "Omarchy shell config watcher path"
    assert_contains 'root=${OMARCHY_PATH:-/usr/share/omarchy}' \
      "$theme_file" "environment-independent Omarchy root"
    assert_contains 'OMARCHY_PATH=$root omarchy-shell idle status' \
      "$theme_file" "resolved Omarchy root for idle IPC"
    assert_contains 'OMARCHY_PATH=$root omarchy-shell notifications ping' \
      "$theme_file" "resolved Omarchy root for notification IPC"
    assert_contains 'theme._idleOmarchyShellSystem = exitCode !== 2' \
      "$theme_file" "three-state idle backend classification"
    assert_contains 'theme._notifOmarchyShellSystem = exitCode !== 2' \
      "$theme_file" "three-state notification backend classification"
    assert_contains 'watchChanges: theme._idleOmarchyShellSystem' \
      "$theme_file" "Quattro idle state-file fallback"
    assert_contains 'watchChanges: theme._notifOmarchyShellSystem' \
      "$theme_file" "Quattro notification state-file fallback"
    assert_contains 'if (!theme._idleOmarchyShellSystem) theme.stayAwake = exitCode !== 0' \
      "$theme_file" "Quattro idle fallback isolation"
    assert_contains 'if (!theme._notifOmarchyShellSystem) theme.notifSilenced = this.text.indexOf("do-not-disturb") >= 0' \
      "$theme_file" "Quattro notification fallback isolation"
    assert_contains 'readonly property var _omarchyBackendRetryDelays: [2000, 5000, 15000]' \
      "$theme_file" "bounded Omarchy backend retry schedule"
    assert_contains 'return (_idleOmarchyShellSystem && !_idleOmarchyShellBackend)' \
      "$theme_file" "Quattro-only backend retries"
    assert_contains 'id: omarchyBackendProbeDebounce' \
      "$theme_file" "Omarchy backend re-probe debounce"
    assert_contains 'id: omarchyBackendConfirmTimer' \
      "$theme_file" "Omarchy backend confirmation probe"
    assert_contains 'if (idleBackendProc.running || notifBackendProc.running)' \
      "$theme_file" "Omarchy backend in-flight guard"
    assert_not_contains 'atomicWrites: true' \
      "$theme_file" "write mode on read-only Omarchy config watcher"
    assert_not_contains 'Qt.callLater(function() { theme.finishOmarchyBackendReprobe() })' \
      "$theme_file" "deferred Omarchy backend completion"
    assert_not_contains 'idleBackendProc.running = false' \
      "$theme_file" "idle backend probe cancellation"
    assert_not_contains 'notifBackendProc.running = false' \
      "$theme_file" "notification backend probe cancellation"
  done
  assert_before "// Check themes" "// Update clean" "$V1_ARCH_UPDATER" \
    "V1 theme check before apply action"
  assert_before "// Check themes" "// Update clean" "$V2_ARCH_UPDATER" \
    "V2 theme check before apply action"
  for bluetooth_panel in "$V1_BLUETOOTH_PANEL" "$V2_BLUETOOTH_PANEL"; do
    assert_contains 'text: devTile.modelData.connected ? "Connected"' \
      "$bluetooth_panel" "Bluetooth device status"
    assert_contains 'font.pixelSize: 10; font.weight: Font.Medium' \
      "$bluetooth_panel" "Bluetooth device status legibility"
    assert_contains 'text: devTile.modelData.connected ? "Disconnect" : "Connect"' \
      "$bluetooth_panel" "explicit Bluetooth device action"
    assert_contains 'btPanel.activateDevice(devTile.modelData)' \
      "$bluetooth_panel" "Bluetooth device action wiring"
    assert_contains 'tileHover.containsMouse || actionMa.containsMouse' \
      "$bluetooth_panel" "Bluetooth tile hover continuity"
    assert_contains 'readonly property color deviceActionFill: Qt.rgba(' \
      "$bluetooth_panel" "opaque Bluetooth action fill"
    assert_contains 'color: btPanel.deviceActionFill' \
      "$bluetooth_panel" "consistent Bluetooth action fill"
    assert_contains 'border.color: root.sep' \
      "$bluetooth_panel" "consistent Bluetooth action border"
    assert_contains 'color: actionMa.containsMouse ? root.seal : root.ink' \
      "$bluetooth_panel" "Bluetooth action text hover"
    assert_not_contains 'IconMap.icon("link_off")' \
      "$bluetooth_panel" "obsolete Bluetooth disconnect icon"
  done

  # V1's palette and MPRIS presentation are persisted extensions of the legacy
  # cache schema. Guard both ends so a UI-only refactor cannot silently leave a
  # control that neither saves nor restores its state.
  assert_contains '{ target: "color07"' "$V1_PALETTE" "V1 color07 palette parsing"
  assert_contains '"color05", "color06", "color07", "foreground"' "$V1_THEME" "V1 full bar palette"
  assert_contains 'if (id === "red" || id === "accent") return "color01"' "$V1_THEME" "V1 legacy palette normalization"
  assert_contains 'property bool compactMpris:' "$V1_THEME" "V1 MPRIS presentation state"
  assert_contains '(compactMpris      ? "1" : "0")' "$V1_THEME" "V1 MPRIS presentation save"
  assert_contains 'parts.length > wsField + 32' "$V1_THEME" "V1 MPRIS presentation restore"
  assert_contains 'compactMpris = false' "$V1_THEME" "V1 MPRIS default-layout reset"
  assert_contains 'model: root.barColorOptions' "$V1_CONTROL_PANEL" "V1 bar palette control"
  assert_contains 'label: "Now playing"' "$V1_CONTROL_PANEL" "V1 MPRIS presentation control"
  assert_contains 'readonly property bool fullMode: root.compactMpris' "$V1_MPRIS_WIDGET" "V1 FULL presentation binding"

  # The analyzer config is supplied over an inherited file descriptor. Keeping
  # exec preserves Quickshell's direct process lifecycle while avoiding the old
  # mktemp + unreachable EXIT-trap leak.
  for mpris_file in \
    "$V1_MPRIS_WIDGET" "$V1_MPRIS_PANEL" \
    "$V2_MPRIS_WIDGET" "$V2_MPRIS_PANEL"; do
    assert_contains "exec cava -p <(printf" "$mpris_file" "CAVA fd-backed config"
    assert_not_contains "cfg=\$(mktemp)" "$mpris_file" "CAVA tempfile leak"
  done

  # uninstall.sh intentionally stays standalone. Keep the shared lifecycle
  # functions byte-identical so future fixes cannot silently land in one copy.
  for shared_function in \
    qsr_export_omarchy_path qsr_has_quattro qsr_pid_holds_lock \
    qsr_live_bar_pids qsr_term_pid qsr_stop_registered_bars \
    qsr_stop_legacy_patterns qsr_stop_bar_instances qsr_stock_bar_hidden \
    qsr_wait_for_stock_state qsr_set_stock_bar qsr_owns_stock_bar_hide \
    qsr_release_owned_stock_bar; do
    assert_shared_function_same "$shared_function"
  done
}

case_installer_interactive_prompt_matrix
case_runtime_toggle_ownership
case_runtime_postboot_order_and_fail_open
case_runtime_postboot_uses_controller_selection
case_registry_live_health_and_stop
case_uninstall_owned_backup_provider
case_uninstall_foreign_hidden_state
case_uninstall_toggle_failure_aborts
case_uninstall_legacy_and_generic
case_uninstall_removes_lifecycle_controller
case_uninstall_keeps_ownership_but_removes_lifecycle_state
case_uninstall_registry_failure_aborts
case_omarchy_service_backend_probe_matrix
case_bluetooth_settings_launcher_matrix
case_static_contracts

printf 'PASS: Quattro lifecycle, ownership, fail-open, registry, uninstall, legacy, and generic regressions\n'
