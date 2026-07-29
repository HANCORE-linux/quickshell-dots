#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="${CHECK:-$REPO_ROOT/scripts/qs-arch-update-check.sh}"
GATE="${GATE:-$REPO_ROOT/scripts/qs-arch-security-gate.sh}"
APPLY="${APPLY:-$REPO_ROOT/scripts/qs-arch-apply-update.sh}"
FRONTEND="${FRONTEND:-$REPO_ROOT/versions/V1/core/qs-system-update.sh}"
WORK="$(mktemp -d /tmp/qs-arch-update-test.XXXXXX)"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_exists() {
  [ -e "$1" ] || fail "$2"
}

assert_file_absent() {
  [ ! -e "$1" ] || fail "$2"
}

assert_contains() {
  grep -Fq -- "$1" "$2" || fail "$3"
}

assert_not_contains() {
  if grep -Fq -- "$1" "$2"; then
    fail "$3"
  fi
}

init_fixture() {
  local root="$1"
  mkdir -p "$root/bin" "$root/home" "$root/state"
  cat > "$root/bin/checkupdates" <<'SCRIPT'
#!/usr/bin/env bash
cat "$FAKE_CHECKUPDATES_FILE"
exit "${FAKE_CHECKUPDATES_RC:-0}"
SCRIPT
  cat > "$root/bin/sudo" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SUDO_LOG"
if [ "${1:-}" = "-v" ]; then
  if [ "${FAKE_SUDO_DELAY:-0}" != "0" ]; then
    sleep "$FAKE_SUDO_DELAY"
  fi
  exit "${FAKE_SUDO_VALIDATE_RC:-0}"
fi
if [ "${1:-}" = "pacman" ]; then
  shift
  exec pacman "$@"
fi
exit 127
SCRIPT
  cat > "$root/bin/pacman" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_PACMAN_LOG"
if [ "$*" = "-Syu" ]; then
  printf 'PACMAN-SYU\n' > "$FAKE_PACMAN_MARKER"
  exit 0
fi
exit 64
SCRIPT
  cat > "$root/bin/paru" <<'SCRIPT'
#!/usr/bin/env bash
if [ "${1:-}" = "-Qum" ]; then
  cat "${FAKE_AUR_FILE:-/dev/null}"
  exit 0
fi
exit 64
SCRIPT
  chmod +x "$root/bin/checkupdates" "$root/bin/sudo" "$root/bin/pacman" "$root/bin/paru"
  : > "$root/sudo.log"
  : > "$root/pacman.log"
  : > "$root/omarchy.log"
  : > "$root/terminal.log"
  : > "$root/gum.log"
  : > "$root/aur.out"
}

env_common() {
  local root="$1"
  shift
  PATH="$root/bin:/usr/bin:/bin" \
  HOME="$root/home" \
  XDG_STATE_HOME="$root/state" \
  QS_GATE_MIN=0 \
  QS_ARCH_CHECK_HELPER="$CHECK" \
  QS_ARCH_GATE_HELPER="$GATE" \
  QS_ARCH_SCAN_MAX_AGE="${QS_ARCH_SCAN_MAX_AGE:-900}" \
  QS_ARCH_OMARCHY_SYSTEM_ROOT="$root/omarchy-system" \
  QS_ARCH_OMARCHY_USER_ROOT="$root/home/.local/share/omarchy" \
  QS_ARCH_OMARCHY_UPDATE_COMMAND="${QS_ARCH_OMARCHY_UPDATE_COMMAND-$root/missing-omarchy-update}" \
  QS_ARCH_OMARCHY_CLI_COMMAND="${QS_ARCH_OMARCHY_CLI_COMMAND-$root/missing-omarchy-cli}" \
  QS_ARCH_PACMAN_PROBE_COMMAND="${QS_ARCH_PACMAN_PROBE_COMMAND:-pacman}" \
  FAKE_SUDO_LOG="$root/sudo.log" \
  FAKE_PACMAN_LOG="$root/pacman.log" \
  FAKE_PACMAN_MARKER="$root/pacman.marker" \
  FAKE_OMARCHY_LOG="$root/omarchy.log" \
  FAKE_OMARCHY_MARKER="$root/omarchy.marker" \
  FAKE_TERMINAL_LOG="$root/terminal.log" \
  FAKE_GUM_LOG="$root/gum.log" \
  FAKE_CHECKUPDATES_FILE="$root/checkupdates.out" \
  FAKE_AUR_FILE="$root/aur.out" \
  FAKE_SUDO_DELAY="${FAKE_SUDO_DELAY:-0}" \
  "$@"
}

run_check() {
  local root="$1"
  env_common "$root" "$CHECK" > "$root/check.out"
}

run_gate_from_check() {
  local root="$1"
  awk -F '|' 'NF >= 4 && ($1 == "S" || $1 == "A") { repo = ($1 == "A" ? "aur" : "system"); print $2 "|" repo "|" $3 "|" $4 }' "$root/check.out" \
    | env_common "$root" "$GATE" > "$root/gate.out"
}

run_apply() {
  local root="$1"
  shift
  env_common "$root" "$APPLY" "$@"
}

run_frontend() {
  local root="$1"
  shift
  env_common "$root" "$FRONTEND" "$@"
}

scan_args() {
  local root="$1"
  jq -r '.scanId, .systemHash, (.systemCount | tostring), (.checkedEpoch | tostring)' \
    "$root/home/.cache/qs-arch-updates.json"
}

run_apply_checked() {
  local root="$1"
  mapfile -t args < <(scan_args "$root")
  run_apply "$root" "${args[@]}"
}

prepare_checked_gate() {
  local root="$1" payload="$2"
  printf '%s\n' "$payload" > "$root/checkupdates.out"
  run_check "$root"
  run_gate_from_check "$root"
  jq -e '.schemaVersion == 1 and (.scanId | length > 0) and .systemCount > 0 and (.systemHash | length > 0)' \
    "$root/home/.cache/qs-arch-updates.json" >/dev/null
  jq -e '.schemaVersion == 1 and .degraded == false and .fail == 0 and .ok >= .systemCount' \
    "$root/home/.cache/qs-arch-gate.json" >/dev/null
}

install_fake_terminal() {
  local root="$1"
  cat > "$root/bin/test-terminal" <<'SCRIPT'
#!/usr/bin/env bash
printf '%q ' "$@" >> "$FAKE_TERMINAL_LOG"
printf '\n' >> "$FAKE_TERMINAL_LOG"
exec "$@"
SCRIPT
  chmod +x "$root/bin/test-terminal"
}

install_fake_presentation_launcher() {
  local root="$1"
  cat > "$root/bin/test-presentation" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$FAKE_TERMINAL_LOG"
exec bash -c "$1"
SCRIPT
  chmod +x "$root/bin/test-presentation"
}

install_fake_gum() {
  local root="$1"
cat > "$root/bin/gum" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s|prompt=%s\n' "$*" "${GUM_CONFIRM_PROMPT_FOREGROUND:-}" >> "$FAKE_GUM_LOG"
exit "${FAKE_GUM_RC:-0}"
SCRIPT
  chmod +x "$root/bin/gum"
}

test_backend_probe_reports_plain_arch() {
  local root="$WORK/backend-arch"
  init_fixture "$root"
  local backend
  backend="$(run_apply "$root" --backend)"
  [ "$backend" = "arch" ] || fail "plain Arch backend probe returned '$backend'"
  local frontend_backend frontend_mode frontend_command frontend_protocol
  IFS=$'\t' read -r frontend_backend frontend_mode frontend_command frontend_protocol \
    < <(run_frontend "$root" --probe "$APPLY")
  [ "$frontend_backend" = "arch" ] || fail "panel probe did not detect plain Arch"
  [ "$frontend_mode" = "apply" ] || fail "panel probe returned the wrong plain Arch mode"
  [ "$frontend_command" = "$APPLY" ] || fail "panel probe returned the wrong apply helper"
  [ "$frontend_protocol" = "2" ] || fail "panel probe did not recognize the current helper protocol"
}

test_omarchy_update_command_is_delegated_before_pacman() {
  local root="$WORK/omarchy-update"
  init_fixture "$root"
  install_fake_terminal "$root"
  cat > "$root/bin/omarchy-update" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_OMARCHY_LOG"
printf 'OMARCHY-UPDATE\n' > "$FAKE_OMARCHY_MARKER"
SCRIPT
  chmod +x "$root/bin/omarchy-update"

  local backend
  backend="$(QS_ARCH_OMARCHY_UPDATE_COMMAND="$root/bin/omarchy-update" run_apply "$root" --backend)"
  [ "$backend" = "omarchy" ] || fail "Omarchy updater backend probe returned '$backend'"
  QS_ARCH_OMARCHY_UPDATE_COMMAND="$root/bin/omarchy-update" \
    run_apply "$root" invalid ignored arguments >/dev/null
  QS_ARCH_OMARCHY_UPDATE_COMMAND="$root/bin/omarchy-update" \
  QS_TEST_SYSTEM_UPDATE_ARGV_TERMINAL="$root/bin/test-terminal" \
    run_frontend "$root" --launch "$root/bin/omarchy-update" >/dev/null

  assert_file_exists "$root/omarchy.marker" "Omarchy updater was not delegated"
  [ -z "$(tr -d '\n' < "$root/omarchy.log")" ] || fail "QS arguments leaked into the Omarchy updater"
  [ ! -s "$root/sudo.log" ] || fail "sudo ran before Omarchy delegation"
  assert_file_absent "$root/pacman.marker" "pacman ran instead of the Omarchy updater"
  assert_contains "$root/bin/omarchy-update" "$root/terminal.log" "Omarchy update did not pass through the portable terminal launcher"
}

test_omarchy_cli_is_supported_as_compatibility_fallback() {
  local root="$WORK/omarchy-cli"
  init_fixture "$root"
  install_fake_terminal "$root"
  cat > "$root/bin/omarchy" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_OMARCHY_LOG"
printf 'OMARCHY-CLI\n' > "$FAKE_OMARCHY_MARKER"
SCRIPT
  chmod +x "$root/bin/omarchy"

  QS_ARCH_OMARCHY_CLI_COMMAND="$root/bin/omarchy" \
    run_apply "$root" stale scan arguments are ignored >/dev/null
  QS_ARCH_OMARCHY_CLI_COMMAND="$root/bin/omarchy" \
  QS_TEST_SYSTEM_UPDATE_ARGV_TERMINAL="$root/bin/test-terminal" \
    run_frontend "$root" --launch "$root/bin/omarchy" update >/dev/null

  assert_file_exists "$root/omarchy.marker" "Omarchy CLI fallback was not delegated"
  assert_contains "update" "$root/omarchy.log" "Omarchy CLI did not receive the update subcommand"
  [ ! -s "$root/sudo.log" ] || fail "sudo ran before Omarchy CLI delegation"
  assert_file_absent "$root/pacman.marker" "pacman ran instead of the Omarchy CLI"
  assert_contains "$root/bin/omarchy" "$root/terminal.log" "Omarchy CLI fallback bypassed the portable terminal launcher"
  assert_contains "update" "$root/terminal.log" "portable terminal lost the Omarchy CLI subcommand"
}

test_broken_omarchy_never_falls_back_to_pacman() {
  local root="$WORK/omarchy-broken"
  init_fixture "$root"
  mkdir -p "$root/home/.local/share/omarchy"

  local backend
  backend="$(run_apply "$root" --backend)"
  [ "$backend" = "omarchy-broken" ] || fail "broken Omarchy backend probe returned '$backend'"
  if run_apply "$root" ignored >"$root/apply.out" 2>"$root/apply.err"; then
    fail "broken Omarchy installation fell back to an updater"
  fi
  assert_contains "update command is unavailable" "$root/apply.err" "broken Omarchy error is not actionable"
  [ ! -s "$root/sudo.log" ] || fail "sudo ran for a broken Omarchy installation"
  assert_file_absent "$root/pacman.marker" "pacman ran for a broken Omarchy installation"
}

test_unsupported_system_fails_without_privilege() {
  local root="$WORK/unsupported"
  init_fixture "$root"

  local backend
  backend="$(QS_ARCH_PACMAN_PROBE_COMMAND=qs-missing-pacman run_apply "$root" --backend)"
  [ "$backend" = "unsupported" ] || fail "unsupported backend probe returned '$backend'"
  if QS_ARCH_PACMAN_PROBE_COMMAND=qs-missing-pacman \
      run_apply "$root" ignored >"$root/apply.out" 2>"$root/apply.err"; then
    fail "unsupported system accepted an update"
  fi
  assert_contains "no supported system update backend" "$root/apply.err" "unsupported-system error is not actionable"
  [ ! -s "$root/sudo.log" ] || fail "sudo ran on an unsupported system"
}

test_plain_arch_launches_without_omarchy_terminal() {
  local root="$WORK/arch-terminal"
  init_fixture "$root"
  install_fake_terminal "$root"
  install_fake_gum "$root"
  prepare_checked_gate "$root" $'linux 1.0 -> 1.1'
  printf 'linux 1.0 -> 1.1\n' > "$root/checkupdates.out"
  mapfile -t args < <(scan_args "$root")

  GUM_CONFIRM_PROMPT_FOREGROUND="#123456" \
  QS_TEST_SYSTEM_UPDATE_ARGV_TERMINAL="$root/bin/test-terminal" \
    run_frontend "$root" --launch "$APPLY" --run "${args[@]}" 2 >/dev/null

  assert_file_exists "$root/pacman.marker" "plain Arch launch did not reach pacman"
  assert_contains "--run" "$root/terminal.log" "plain Arch update did not pass through the portable terminal launcher"
  assert_contains "2 AUR review packages will be skipped" "$root/gum.log" "plain Arch confirmation lost its AUR scope"
  assert_contains "prompt=#123456" "$root/gum.log" "plain Arch confirmation lost its QML theme environment"
}

test_user_root_fallback_survives_minimal_path() {
  local root="$WORK/omarchy-user-root"
  init_fixture "$root"
  mkdir -p "$root/home/.local/share/omarchy/bin"
  cat > "$root/home/.local/share/omarchy/bin/omarchy-update" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$root/home/.local/share/omarchy/bin/omarchy-update"

  local backend
  backend="$(env -i \
    HOME="$root/home" \
    PATH=/usr/bin:/bin \
    QS_ARCH_OMARCHY_SYSTEM_ROOT="$root/omarchy-system" \
    QS_ARCH_OMARCHY_USER_ROOT="$root/home/.local/share/omarchy" \
    QS_ARCH_PACMAN_PROBE_COMMAND=qs-missing-pacman \
    "$APPLY" --backend)"
  [ "$backend" = "omarchy" ] || fail "apply helper lost user-root Omarchy under a minimal PATH"

  local frontend_backend frontend_mode frontend_command frontend_protocol
  IFS=$'\t' read -r frontend_backend frontend_mode frontend_command frontend_protocol < <(
    env -i \
      HOME="$root/home" \
      PATH=/usr/bin:/bin \
      QS_ARCH_OMARCHY_SYSTEM_ROOT="$root/omarchy-system" \
      QS_ARCH_OMARCHY_USER_ROOT="$root/home/.local/share/omarchy" \
      QS_ARCH_PACMAN_PROBE_COMMAND=qs-missing-pacman \
      "$FRONTEND" --probe "$APPLY"
  )
  [ "$frontend_backend" = "omarchy" ] || fail "panel probe lost user-root Omarchy under a minimal PATH"
  [ "$frontend_mode" = "update" ] || fail "panel probe did not prefer the user-root updater"
  [ "$frontend_command" = "$root/home/.local/share/omarchy/bin/omarchy-update" ] \
    || fail "panel probe returned the wrong user-root updater"
  [ "$frontend_protocol" = "2" ] || fail "panel probe lost the apply protocol under a minimal PATH"
}

test_legacy_helper_is_inspected_without_execution() {
  local root="$WORK/legacy-helper"
  init_fixture "$root"
  cat > "$root/bin/legacy-apply" <<'SCRIPT'
#!/usr/bin/env bash
printf 'INVOKED\n' > "$FAKE_LEGACY_MARKER"
exit 1
SCRIPT
  cat > "$root/bin/omarchy-update" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$root/bin/legacy-apply" "$root/bin/omarchy-update"

  local backend mode command_path protocol probe
  probe="$(FAKE_LEGACY_MARKER="$root/legacy-invoked" \
    QS_ARCH_OMARCHY_UPDATE_COMMAND="$root/bin/omarchy-update" \
    run_frontend "$root" --probe "$root/bin/legacy-apply")"
  IFS=$'\t' read -r backend mode command_path protocol <<< "$probe"

  [ "$backend" = "omarchy" ] || fail "legacy-helper probe lost the Omarchy backend"
  [ "$mode" = "update" ] || fail "legacy-helper probe returned the wrong Omarchy mode"
  [ "$command_path" = "$root/bin/omarchy-update" ] || fail "legacy-helper probe returned the wrong updater"
  [ "$protocol" = "legacy" ] || fail "legacy apply helper was not classified safely"
  assert_file_absent "$root/legacy-invoked" "panel probe executed the legacy privileged helper"
}

test_missing_apply_helper_does_not_block_omarchy() {
  local root="$WORK/missing-apply-helper"
  init_fixture "$root"
  install_fake_terminal "$root"
  cat > "$root/bin/omarchy-update" <<'SCRIPT'
#!/usr/bin/env bash
printf 'OMARCHY-WITHOUT-APPLY\n' > "$FAKE_OMARCHY_MARKER"
SCRIPT
  chmod +x "$root/bin/omarchy-update"

  local backend mode command_path protocol probe
  probe="$(QS_ARCH_OMARCHY_UPDATE_COMMAND="$root/bin/omarchy-update" \
    run_frontend "$root" --probe "$root/missing-apply-helper")"
  IFS=$'\t' read -r backend mode command_path protocol <<< "$probe"
  [ "$backend" = "omarchy" ] || fail "missing apply helper hid the Omarchy updater"
  [ "$mode" = "update" ] || fail "missing apply helper changed the Omarchy mode"
  [ "$command_path" = "$root/bin/omarchy-update" ] || fail "missing apply helper changed the updater path"
  [ "$protocol" = "missing" ] || fail "missing apply helper was not reported explicitly"

  QS_TEST_SYSTEM_UPDATE_ARGV_TERMINAL="$root/bin/test-terminal" \
    run_frontend "$root" --launch "$command_path" >/dev/null
  assert_file_exists "$root/omarchy.marker" "Omarchy update was blocked by a missing apply helper"
}

test_presentation_launcher_preserves_update_argv() {
  local root="$WORK/presentation-argv"
  init_fixture "$root"
  install_fake_presentation_launcher "$root"
  cat > "$root/bin/argv-recorder" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_OMARCHY_LOG"
SCRIPT
  chmod +x "$root/bin/argv-recorder"

  QS_TEST_SYSTEM_UPDATE_PRESENTATION_LAUNCHER="$root/bin/test-presentation" \
    run_frontend "$root" --launch "$root/bin/argv-recorder" \
      "argument with spaces" "quote'argument" >/dev/null

  local expected="$root/argv.expected"
  printf '%s\n' "argument with spaces" "quote'argument" > "$expected"
  cmp -s "$expected" "$root/omarchy.log" \
    || fail "presentation launcher did not preserve the exact update argv"
}

test_success_runs_exact_full_upgrade() {
  local root="$WORK/success"
  init_fixture "$root"
  prepare_checked_gate "$root" $'linux 1.0 -> 1.1\nglibc 2.0 -> 2.1'

  printf 'linux 1.0 -> 1.1\nglibc 2.0 -> 2.1\n' > "$root/checkupdates.out"
  run_apply_checked "$root" >/dev/null

  assert_file_exists "$root/pacman.marker" "pacman -Syu was not executed"
  assert_contains "-v" "$root/sudo.log" "sudo -v was not called"
  assert_contains "pacman -Syu" "$root/sudo.log" "sudo pacman -Syu was not called"
  assert_contains "-Syu" "$root/pacman.log" "pacman did not receive exact -Syu"
}

test_aur_warnings_do_not_block_full_repo_upgrade() {
  local root="$WORK/aur-warn"
  init_fixture "$root"
  printf 'aurtool 1.0 -> 1.1\n' > "$root/aur.out"
  prepare_checked_gate "$root" $'linux 1.0 -> 1.1'

  jq -e '.aurCount == 1 and .systemCount == 1' "$root/home/.cache/qs-arch-updates.json" >/dev/null
  jq -e '.warn == 1 and .ok == 1 and .fail == 0 and .degraded == false' "$root/home/.cache/qs-arch-gate.json" >/dev/null

  printf 'linux 1.0 -> 1.1\n' > "$root/checkupdates.out"
  run_apply_checked "$root" >/dev/null

  assert_file_exists "$root/pacman.marker" "pacman -Syu was blocked by AUR warnings"
  assert_contains "pacman -Syu" "$root/sudo.log" "sudo pacman -Syu was not called with AUR warnings"
  assert_contains "-Syu" "$root/pacman.log" "pacman did not receive exact -Syu with AUR warnings"
}

test_rescan_drift_aborts_before_pacman() {
  local root="$WORK/drift"
  init_fixture "$root"
  prepare_checked_gate "$root" $'linux 1.0 -> 1.1\nglibc 2.0 -> 2.1'

  printf 'linux 1.0 -> 1.2\nglibc 2.0 -> 2.1\n' > "$root/checkupdates.out"
  if run_apply_checked "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded despite package drift"
  fi
  assert_file_absent "$root/pacman.marker" "pacman ran despite package drift"
  assert_contains "-v" "$root/sudo.log" "sudo -v should happen before the fresh rescan"
}

test_stale_scan_aborts_before_sudo() {
  local root="$WORK/stale"
  init_fixture "$root"
  prepare_checked_gate "$root" $'linux 1.0 -> 1.1'
  local stale
  stale="$(( $(date +%s) - 99999 ))"
  local tmp
  tmp="$(mktemp)"
  jq --argjson stale "$stale" '.checkedEpoch = $stale' "$root/home/.cache/qs-arch-updates.json" > "$tmp"
  mv "$tmp" "$root/home/.cache/qs-arch-updates.json"

  if run_apply_checked "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with stale scan"
  fi
  assert_file_absent "$root/pacman.marker" "pacman ran despite stale scan"
  [ ! -s "$root/sudo.log" ] || fail "sudo ran despite stale scan"
}

test_gate_mismatch_aborts_before_sudo() {
  local root="$WORK/gate-mismatch"
  init_fixture "$root"
  prepare_checked_gate "$root" $'linux 1.0 -> 1.1'
  local tmp
  tmp="$(mktemp)"
  jq '.systemHash = "not-the-scan-hash"' "$root/home/.cache/qs-arch-gate.json" > "$tmp"
  mv "$tmp" "$root/home/.cache/qs-arch-gate.json"

  if run_apply_checked "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with mismatched gate state"
  fi
  assert_file_absent "$root/pacman.marker" "pacman ran despite gate mismatch"
  [ ! -s "$root/sudo.log" ] || fail "sudo ran despite gate mismatch"
}

test_degraded_gate_aborts_before_sudo() {
  local root="$WORK/gate-degraded"
  init_fixture "$root"
  prepare_checked_gate "$root" $'linux 1.0 -> 1.1'
  local tmp
  tmp="$(mktemp)"
  jq '.degraded = true' "$root/home/.cache/qs-arch-gate.json" > "$tmp"
  mv "$tmp" "$root/home/.cache/qs-arch-gate.json"

  if run_apply_checked "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with degraded gate"
  fi
  assert_file_absent "$root/pacman.marker" "pacman ran despite degraded gate"
  [ ! -s "$root/sudo.log" ] || fail "sudo ran despite degraded gate"
}

test_missing_checkupdates_fails_closed() {
  local root="$WORK/missing-checkupdates"
  init_fixture "$root"
  prepare_checked_gate "$root" $'linux 1.0 -> 1.1'
  rm -f "$root/bin/checkupdates"

  if run_apply_checked "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded without checkupdates"
  fi
  assert_file_absent "$root/pacman.marker" "pacman ran without checkupdates"
  assert_contains "-v" "$root/sudo.log" "sudo -v should happen before the fresh rescan"
}

test_check_without_checkupdates_fails() {
  local root="$WORK/check-missing"
  init_fixture "$root"
  rm -f "$root/bin/checkupdates"
  printf 'linux 1.0 -> 1.1\n' > "$root/checkupdates.out"

  if run_check "$root" >"$root/check.stdout" 2>"$root/check.stderr"; then
    fail "check succeeded without checkupdates"
  fi
  [ ! -e "$root/home/.cache/qs-arch-updates.json" ] || fail "check wrote state without checkupdates"
}

test_state_replaced_after_click_aborts_before_sudo() {
  local root="$WORK/state-replaced"
  init_fixture "$root"
  prepare_checked_gate "$root" $'linux 1.0 -> 1.1'
  mapfile -t clicked_args < <(scan_args "$root")

  printf 'linux 1.0 -> 1.2\n' > "$root/checkupdates.out"
  run_check "$root"

  if run_apply "$root" "${clicked_args[@]}" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded after checked state was replaced"
  fi
  assert_file_absent "$root/pacman.marker" "pacman ran after checked state replacement"
  [ ! -s "$root/sudo.log" ] || fail "sudo ran after checked state replacement"
}

test_gate_changed_after_review_aborts_before_pacman() {
  local root="$WORK/gate-changed"
  init_fixture "$root"
  prepare_checked_gate "$root" $'linux 1.0 -> 1.1'
  mkdir -p "$root/home/.local/share"
  printf 'linux\n' > "$root/home/.local/share/qs-aur-blacklist.txt"

  printf 'linux 1.0 -> 1.1\n' > "$root/checkupdates.out"
  if run_apply_checked "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded after gate source changed"
  fi
  assert_file_absent "$root/pacman.marker" "pacman ran after gate source changed"
  assert_contains "-v" "$root/sudo.log" "sudo -v should happen before the final gate rescan"
}

test_scan_stales_during_sudo_aborts_before_pacman() {
  local root="$WORK/stale-during-sudo"
  init_fixture "$root"
  QS_ARCH_SCAN_MAX_AGE=1 prepare_checked_gate "$root" $'linux 1.0 -> 1.1'

  printf 'linux 1.0 -> 1.1\n' > "$root/checkupdates.out"
  if QS_ARCH_SCAN_MAX_AGE=1 FAKE_SUDO_DELAY=2 run_apply_checked "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded after scan became stale during sudo authentication"
  fi
  assert_file_absent "$root/pacman.marker" "pacman ran after scan became stale during sudo authentication"
  assert_contains "-v" "$root/sudo.log" "sudo -v was not reached in stale-during-sudo test"
}

test_malformed_checkupdates_line_fails_check() {
  local root="$WORK/malformed-check"
  init_fixture "$root"
  printf 'linux 1.0 -> 1.1\nthis is not valid checkupdates output\n' > "$root/checkupdates.out"

  if run_check "$root" >"$root/check.stdout" 2>"$root/check.stderr"; then
    fail "check succeeded with malformed checkupdates output"
  fi
  [ ! -e "$root/home/.cache/qs-arch-updates.json" ] || fail "check wrote state from malformed checkupdates output"
}

test_invalid_checkupdates_package_name_fails_check() {
  local root="$WORK/invalid-package-name"
  init_fixture "$root"
  printf '%s\n' "bad\$name 1.0 -> 1.1" > "$root/checkupdates.out"

  if run_check "$root" >"$root/check.stdout" 2>"$root/check.stderr"; then
    fail "check succeeded with invalid checkupdates package name"
  fi
  [ ! -e "$root/home/.cache/qs-arch-updates.json" ] || fail "check wrote state from invalid package name"
}

test_malformed_rescan_aborts_before_pacman() {
  local root="$WORK/malformed-rescan"
  init_fixture "$root"
  prepare_checked_gate "$root" $'linux 1.0 -> 1.1'

  printf 'linux 1.0 -> 1.1\nthis is not valid checkupdates output\n' > "$root/checkupdates.out"
  if run_apply_checked "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with malformed fresh checkupdates output"
  fi
  assert_file_absent "$root/pacman.marker" "pacman ran after malformed fresh checkupdates output"
  assert_contains "-v" "$root/sudo.log" "sudo -v should happen before fresh malformed rescan"
}

test_checkupdates_bad_exit_fails_even_without_stderr() {
  local root="$WORK/check-bad-exit"
  init_fixture "$root"
  printf 'linux 1.0 -> 1.1\n' > "$root/checkupdates.out"

  if FAKE_CHECKUPDATES_RC=1 run_check "$root" >"$root/check.stdout" 2>"$root/check.stderr"; then
    fail "check succeeded with non-accepted checkupdates exit code"
  fi
  [ ! -e "$root/home/.cache/qs-arch-updates.json" ] || fail "check wrote state after bad checkupdates exit code"
}

test_blacklist_fetch_service_has_bounded_retries() {
  local service="$REPO_ROOT/systemd/qs-aur-blacklist-fetch.service"
  assert_contains "StartLimitIntervalSec=1h" "$service" "blacklist fetch service missing retry interval limit"
  assert_contains "StartLimitBurst=4" "$service" "blacklist fetch service missing retry burst limit"
  assert_contains "Restart=on-failure" "$service" "blacklist fetch service missing failure retry policy"
  assert_contains "RestartSec=15min" "$service" "blacklist fetch service missing retry delay"
}

test_arch_panel_refresh_updates_freshness_clock() {
  local panel refresh frontend="$REPO_ROOT/versions/V1/core/qs-system-update.sh"
  for panel in \
    "$REPO_ROOT/versions/V1/panels/ArchUpdaterPanel.qml" \
    "$REPO_ROOT/versions/V1/variants/V2/panels/ArchUpdaterPanel.qml"; do
    assert_contains "function onArchScanCheckedEpochChanged()" "$panel" "arch panel does not refresh its freshness clock after package scan"
    assert_contains "archPanel.nowEpoch = Math.floor(Date.now() / 1000)" "$panel" "arch panel freshness clock update is missing"
    assert_contains 'command: [archPanel.packageFrontendScript, "--probe", archPanel.packageApplyScript]' "$panel" "arch panel does not use the side-effect-free backend probe"
    assert_not_contains 'command: [archPanel.packageApplyScript, "--backend"]' "$panel" "arch panel still probes the privileged helper directly"
    assert_contains 'interval: 2000' "$panel" "arch panel backend probe has no bounded timeout"
    assert_contains "function retryPackageBackendProbe()" "$panel" "arch panel cannot recover from a transient backend-probe failure"
    assert_contains "if (packageBackendProbe.running" "$panel" "arch panel retry can interrupt a live backend probe"
    assert_contains '|| packageUpdateBackendAvailable) return' "$panel" "arch panel retries a healthy backend unnecessarily"
    assert_contains 'packageApplyProtocol = ""' "$panel" "arch panel retry can retain a stale helper protocol"
    refresh="$(sed -n '/function refreshPackagesTabState() {/,/^    }/p' "$panel")"
    [[ "$refresh" == *"archPanel.retryPackageBackendProbe()"* ]] \
      || fail "opening the packages tab does not retry a failed backend probe"
    [[ "$refresh" != *"packageBackendProbe.running = false"* \
       && "$refresh" != *"packageBackendProbe.running = true"* ]] \
      || fail "package-tab refresh still force-restarts the backend probe"
    assert_contains '&& (usesOmarchyUpdater || repoGateAllowsFullUpgrade)' "$panel" "Omarchy updater is still incorrectly gated by the plain Arch transaction"
    assert_contains '.concat(themedGumEnvironment())' "$panel" "package confirmation lost the active QML theme"
    assert_contains '"Open Omarchy update"' "$panel" "arch panel does not identify the Omarchy-owned update path"
  done
  assert_contains '--wait-after-command=true' "$frontend" "Ghostty update terminal does not remain open"
  assert_contains 'QS_TEST_SYSTEM_UPDATE_ARGV_TERMINAL' "$frontend" "frontend is missing its hermetic argv-preserving test seam"
  assert_not_contains "QS_ARCH_TERMINAL_LAUNCHER" "$frontend" "frontend retains the ambiguous one-string terminal override"
  assert_contains "On plain Arch" "$REPO_ROOT/docs/maintenance-and-recovery.md" "docs do not describe the plain Arch security boundary"
  assert_contains "On Omarchy" "$REPO_ROOT/docs/maintenance-and-recovery.md" "docs do not disclose the advisory Omarchy gate"
  assert_not_contains "OMARCHY_ALLOW_DIRECT_PACMAN" "$APPLY" "apply helper bypasses Quattro's pacman guard"
  assert_not_contains "OMARCHY_UPDATE_PACMAN=1" "$APPLY" "apply helper impersonates an Omarchy-owned transaction"
}

test_backend_probe_reports_plain_arch
test_omarchy_update_command_is_delegated_before_pacman
test_omarchy_cli_is_supported_as_compatibility_fallback
test_broken_omarchy_never_falls_back_to_pacman
test_unsupported_system_fails_without_privilege
test_plain_arch_launches_without_omarchy_terminal
test_user_root_fallback_survives_minimal_path
test_legacy_helper_is_inspected_without_execution
test_missing_apply_helper_does_not_block_omarchy
test_presentation_launcher_preserves_update_argv
test_success_runs_exact_full_upgrade
test_aur_warnings_do_not_block_full_repo_upgrade
test_rescan_drift_aborts_before_pacman
test_stale_scan_aborts_before_sudo
test_gate_mismatch_aborts_before_sudo
test_degraded_gate_aborts_before_sudo
test_missing_checkupdates_fails_closed
test_check_without_checkupdates_fails
test_state_replaced_after_click_aborts_before_sudo
test_gate_changed_after_review_aborts_before_pacman
test_scan_stales_during_sudo_aborts_before_pacman
test_malformed_checkupdates_line_fails_check
test_invalid_checkupdates_package_name_fails_check
test_malformed_rescan_aborts_before_pacman
test_checkupdates_bad_exit_fails_even_without_stderr
test_blacklist_fetch_service_has_bounded_retries
test_arch_panel_refresh_updates_freshness_clock

printf 'qs-arch-update regression tests passed\n'
