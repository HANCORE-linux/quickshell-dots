#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="${CHECK:-$REPO_ROOT/scripts/qs-shell-check-update.sh}"
APPLY="${APPLY:-$REPO_ROOT/scripts/qs-shell-apply-update.sh}"
WORK="$(mktemp -d /tmp/qs-shell-update-test.XXXXXX)"

cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local want="$1" got="$2" msg="$3"
  [ "$want" = "$got" ] || fail "$msg: want '$want', got '$got'"
}

assert_contains() {
  local needle="$1" file="$2" msg="$3"
  grep -Fq -- "$needle" "$file" || fail "$msg: missing '$needle'"
}

assert_not_contains() {
  local needle="$1" file="$2" msg="$3"
  [ ! -f "$file" ] || ! grep -Fq -- "$needle" "$file" || fail "$msg: unexpected '$needle'"
}

state_file() {
  printf '%s/.cache/qs-shell/update-available.json\n' "$1/home"
}

progress_file() {
  printf '%s/.cache/qs-shell/apply-status.json\n' "$1/home"
}

progress_trace_file() {
  printf '%s/progress.trace\n' "$1"
}

notify_log() {
  printf '%s/home/notify.log\n' "$1"
}

write_payload() {
  local repo="$1" label="$2" mode="${3:-ok}"
  rm -rf "$repo/versions" "$repo/scripts" "$repo/systemd" "$repo/hooks"
  mkdir -p "$repo/versions/V1" "$repo/scripts" "$repo/systemd" "$repo/hooks"
  case "$mode" in
    missing-shell) ;;
    invalid-shell) printf 'import QtQuick\nItem {\n' > "$repo/versions/V1/shell.qml" ;;
    invalid-import) printf 'import Definitely.Not.A.Real.Module\nimport QtQuick\nItem {}\n' > "$repo/versions/V1/shell.qml" ;;
    bad-local-import) printf 'import QtQuick\nimport "missingLocal"\nItem {}\n' > "$repo/versions/V1/shell.qml" ;;
    missing-component) printf 'import QtQuick\nMissingComponent {}\n' > "$repo/versions/V1/shell.qml" ;;
    qs-module-import)
      mkdir -p "$repo/versions/V1/modules"
      printf 'module qs.modules\nTestThing 1.0 TestThing.qml\n' > "$repo/versions/V1/modules/qmldir"
      printf 'import QtQuick\nItem {}\n' > "$repo/versions/V1/modules/TestThing.qml"
      printf 'import QtQuick\nimport qs.modules\nItem { TestThing {} }\n' > "$repo/versions/V1/shell.qml"
      ;;
    qs-module-import-side-effect)
      mkdir -p "$repo/versions/V1/modules"
      printf 'module qs.modules\nTestThing 1.0 TestThing.qml\n' > "$repo/versions/V1/modules/qmldir"
      printf 'import QtQuick\nItem {}\n' > "$repo/versions/V1/modules/TestThing.qml"
      cat > "$repo/versions/V1/shell.qml" <<'QML'
import QtQuick
import Quickshell.Io
import qs.modules

Item {
  TestThing {}
  Process {
    command: ["sh", "-c", "printf SIDE_EFFECT > \"$HOME/qs-smoke-side-effect\""]
    running: true
  }
}
QML
      ;;
    qs-module-import-no-qmldir-side-effect)
      mkdir -p "$repo/versions/V1/modules"
      printf 'import QtQuick\nItem {}\n' > "$repo/versions/V1/modules/TestThing.qml"
      cat > "$repo/versions/V1/shell.qml" <<'QML'
import QtQuick
import Quickshell.Io
import qs.modules

Item {
  TestThing {}
  Process {
    command: ["sh", "-c", "printf SIDE_EFFECT > \"$HOME/qs-smoke-side-effect\""]
    running: true
  }
}
QML
      ;;
    *) printf 'import QtQuick\nItem {}\n' > "$repo/versions/V1/shell.qml" ;;
  esac
  printf '%s\n' "$label" > "$repo/versions/V1/payload.txt"
  printf '%s\n' "$label" > "$repo/scripts/companion.txt"
  mkdir -p "$repo/contrib/post-boot.d"
  printf 'post-boot-%s\n' "$label" > "$repo/contrib/post-boot.d/quickshell-rise"
  chmod 755 "$repo/contrib/post-boot.d/quickshell-rise"
  printf 'theme-hook-%s\n' "$label" > "$repo/hooks/50-quickshell-bar.sh"
  chmod 755 "$repo/hooks/50-quickshell-bar.sh"
  printf 'companion-marker\n.config/omarchy/hooks/post-boot.d/quickshell-rise\n.config/omarchy/hooks/theme-set.d/50-quickshell-bar.sh\n' > "$repo/scripts/qs-shell-post-update.targets"
  if [ "$mode" = "bad-companion" ]; then
    cat > "$repo/scripts/qs-shell-post-update.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 42
SCRIPT
  elif [ "$mode" = "no-companion-manifest" ]; then
    rm -f "$repo/scripts/qs-shell-post-update.targets"
    cat > "$repo/scripts/qs-shell-post-update.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'SHOULD-NOT-RUN\n' > "$HOME/companion-marker"
SCRIPT
  elif [ "$mode" = "bad-companion-after-mutation" ]; then
    printf 'companion-side-effect\n' > "$repo/scripts/qs-shell-post-update.targets"
    cat > "$repo/scripts/qs-shell-post-update.sh" <<'SCRIPT'
#!/usr/bin/env bash
printf 'TARGET-SIDE-EFFECT\n' > "$HOME/companion-side-effect"
exit 42
SCRIPT
  elif [ "$mode" = "blacklist-side-effects-fail" ]; then
    printf '.local/share/qs-aur-blacklist.txt\n.local/share/qs-aur-blacklist.txt.meta.json\n.local/share/qs-aur-blacklist.txt.pending\n' > "$repo/scripts/qs-shell-post-update.targets"
    cat > "$repo/scripts/qs-shell-post-update.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/.local/share"
printf 'TARGET-LIST\n' > "$HOME/.local/share/qs-aur-blacklist.txt"
printf 'TARGET-META\n' > "$HOME/.local/share/qs-aur-blacklist.txt.meta.json"
printf 'TARGET-PENDING\n' > "$HOME/.local/share/qs-aur-blacklist.txt.pending"
exit 42
SCRIPT
  elif [ "$mode" = "systemd-unit-mutation-fail" ]; then
    printf '.config/systemd/user/qs-shell-update-check.timer\n' > "$repo/scripts/qs-shell-post-update.targets"
    cat > "$repo/scripts/qs-shell-post-update.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/.config/systemd/user"
printf 'TARGET-UNIT\n' > "$HOME/.config/systemd/user/qs-shell-update-check.timer"
exit 42
SCRIPT
  elif [ "$mode" = "systemd-unit-mutation-ok" ]; then
    printf '.config/systemd/user/qs-shell-update-check.timer\n' > "$repo/scripts/qs-shell-post-update.targets"
    cat > "$repo/scripts/qs-shell-post-update.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/.config/systemd/user"
printf 'TARGET-UNIT\n' > "$HOME/.config/systemd/user/qs-shell-update-check.timer"
SCRIPT
  elif [ "$mode" = "missing-postboot-source" ]; then
    rm -f "$repo/contrib/post-boot.d/quickshell-rise"
    printf '.config/omarchy/hooks/post-boot.d/quickshell-rise\n' > "$repo/scripts/qs-shell-post-update.targets"
    cat > "$repo/scripts/qs-shell-post-update.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
src="${1:?}"
if [ -f "$HOME/.config/omarchy/hooks/post-boot.d/quickshell-rise" ]; then
  if [ ! -f "$src/contrib/post-boot.d/quickshell-rise" ] && [ "${QS_SHELL_REQUIRE_POST_BOOT_SOURCE:-0}" = "1" ]; then
    exit 42
  fi
fi
SCRIPT
  elif [ "$mode" = "hook-mutation-fail" ]; then
    printf '.config/omarchy/hooks/theme-set.d/50-quickshell-bar.sh\n' > "$repo/scripts/qs-shell-post-update.targets"
    cat > "$repo/scripts/qs-shell-post-update.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
src="${1:?}"
mkdir -p "$HOME/.config/omarchy/hooks/theme-set.d"
cp "$src/hooks/50-quickshell-bar.sh" "$HOME/.config/omarchy/hooks/theme-set.d/50-quickshell-bar.sh"
exit 42
SCRIPT
  else
    cat > "$repo/scripts/qs-shell-post-update.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
src="${1:?}"
mkdir -p "$HOME"
cp "$src/scripts/companion.txt" "$HOME/companion-marker"
if [ -f "$HOME/.config/omarchy/hooks/post-boot.d/quickshell-rise" ]; then
  [ -f "$src/contrib/post-boot.d/quickshell-rise" ] || exit 43
  mkdir -p "$HOME/.config/omarchy/hooks/post-boot.d"
  cp "$src/contrib/post-boot.d/quickshell-rise" "$HOME/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  chmod 755 "$HOME/.config/omarchy/hooks/post-boot.d/quickshell-rise"
fi
mkdir -p "$HOME/.config/omarchy/hooks/theme-set.d"
cp "$src/hooks/50-quickshell-bar.sh" "$HOME/.config/omarchy/hooks/theme-set.d/50-quickshell-bar.sh"
chmod 755 "$HOME/.config/omarchy/hooks/theme-set.d/50-quickshell-bar.sh"
SCRIPT
  fi
  printf '[Unit]\nDescription=%s\n' "$label" > "$repo/systemd/qs-test.service"
}

commit_payload() {
  local repo="$1" label="$2" mode="${3:-ok}"
  write_payload "$repo" "$label" "$mode"
  git -C "$repo" add -A >/dev/null
  git -C "$repo" commit -m "payload-$label" >/dev/null
}

init_fixture() {
  local root="$1"
  mkdir -p "$root/home" "$root/state" "$root/dest"
  git init --bare "$root/remote.git" >/dev/null
  git init "$root/repo" >/dev/null
  git -C "$root/repo" config user.email test@example.invalid
  git -C "$root/repo" config user.name Test
  git -C "$root/repo" branch -M main
  git -C "$root/repo" remote add origin "$root/remote.git"

  commit_payload "$root/repo" base
  git -C "$root/repo" push -u origin main >/dev/null 2>&1
  git --git-dir="$root/remote.git" symbolic-ref HEAD refs/heads/main

  git -C "$root/repo" archive HEAD:versions/V1 | tar -x -C "$root/dest"
  printf 'V1\n' > "$root/dest/.qsrise"
  git -C "$root/repo" rev-parse HEAD > "$root/dest/.qsrise-commit"
  mkdir -p "$root/home/.config/omarchy/hooks/theme-set.d"
  git -C "$root/repo" show HEAD:hooks/50-quickshell-bar.sh > "$root/home/.config/omarchy/hooks/theme-set.d/50-quickshell-bar.sh"
  chmod 755 "$root/home/.config/omarchy/hooks/theme-set.d/50-quickshell-bar.sh"
}

make_update_and_check() {
  local root="$1" label="$2" mode="${3:-ok}"
  commit_payload "$root/repo" "$label" "$mode"
  git -C "$root/repo" push origin main >/dev/null 2>&1
  HOME="$root/home" \
  QS_SHELL_REPO="$root/repo" \
  QS_SHELL_DEST="$root/dest" \
    "$CHECK"
  jq -e '(.schemaVersion == 5) and (.behind > 0)
    and (.targetCommit | type == "string")
    and (.commitIds | type == "array") and (.commitIds | length > 0)
    and (.payloadTree | type == "string") and (.payloadTree | length > 0)
    and (.scriptsTree | type == "string")
    and (.systemdTree | type == "string")
    and (.hookBlob | type == "string")
    and (.postBootHookBlob | type == "string")' "$(state_file "$root")" >/dev/null
}

run_apply() {
  local root="$1"
  local trace="${QS_SHELL_PROGRESS_TRACE:-$(progress_trace_file "$root")}"
  local screen="${QS_SHELL_PROGRESS_SCREEN:-DP-1}"
  PATH="$root/bin:$PATH" \
  HOME="$root/home" \
  XDG_STATE_HOME="$root/state" \
  QS_SHELL_REPO="$root/repo" \
  QS_SHELL_DEST="$root/dest" \
  QS_SHELL_NO_RESTART=1 \
  QS_SHELL_SMOKE_PLATFORM=offscreen \
  QS_SHELL_SMOKE_TIMEOUT="${QS_SHELL_SMOKE_TIMEOUT:-1}" \
  QS_SHELL_PROGRESS_TRACE="$trace" \
  QS_SHELL_PROGRESS_SCREEN="$screen" \
    "$APPLY"
}

run_apply_with_restart() {
  local root="$1"
  local trace="${QS_SHELL_PROGRESS_TRACE:-$(progress_trace_file "$root")}"
  local screen="${QS_SHELL_PROGRESS_SCREEN:-DP-1}"
  PATH="$root/bin:$PATH" \
  HOME="$root/home" \
  XDG_STATE_HOME="$root/state" \
  QS_SHELL_REPO="$root/repo" \
  QS_SHELL_DEST="$root/dest" \
  QS_SHELL_SMOKE_PLATFORM=offscreen \
  QS_SHELL_SMOKE_TIMEOUT="${QS_SHELL_SMOKE_TIMEOUT:-1}" \
  QS_SHELL_PROGRESS_TRACE="$trace" \
  QS_SHELL_PROGRESS_SCREEN="$screen" \
    "$APPLY"
}

run_progress_command() {
  local root="$1"; shift
  PATH="$root/bin:$PATH" \
  HOME="$root/home" \
  XDG_STATE_HOME="$root/state" \
  QS_SHELL_REPO="$root/repo" \
  QS_SHELL_DEST="$root/dest" \
    "$APPLY" "$@"
}

install_fake_systemctl() {
  local root="$1"
  mkdir -p "$root/bin"
cat > "$root/bin/systemctl" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/systemctl.log"
[ "${1:-}" = "--user" ] || exit 0
shift
case "${1:-}" in
  daemon-reload)
    if [ -e "$HOME/.config/systemd/user/qs-shell-update-check.timer" ]; then
      printf 'daemon-reload-unit=%s\n' "$(tr -d '\n' < "$HOME/.config/systemd/user/qs-shell-update-check.timer")" >> "$HOME/systemctl.log"
    else
      printf 'daemon-reload-unit=missing\n' >> "$HOME/systemctl.log"
    fi
    ;;
  is-enabled)
    if [ "${2:-}" = "qs-shell-update-check.timer" ]; then
      printf 'enabled\n'
      exit 0
    fi
    printf 'disabled\n'
    exit 1
    ;;
  is-active)
    if [ "${2:-}" = "qs-shell-update-check.timer" ]; then
      printf 'active\n'
      exit 0
    fi
    printf 'inactive\n'
    exit 3
    ;;
esac
exit 0
SCRIPT
  chmod 755 "$root/bin/systemctl"
}

install_fake_restart_tools() {
  local root="$1"
  mkdir -p "$root/bin"
  cat > "$root/bin/qs" <<'SCRIPT'
#!/usr/bin/env bash
if [ "${1:-}" = "list" ] && [ "${2:-}" = "--all" ]; then
  exit 0
fi
printf 'qs %s\n' "$*" >> "$HOME/qs.log"
exit 0
SCRIPT
  cat > "$root/bin/systemd-run" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/systemd-run.log"
if [ -n "${QS_TEST_SYSTEMD_RUN_FAIL:-}" ]; then
  exit 1
fi
exit 0
SCRIPT
  cat > "$root/bin/setsid" <<'SCRIPT'
#!/usr/bin/env bash
printf 'setsid %s\n' "$*" >> "$HOME/setsid.log"
exit 99
SCRIPT
  cat > "$root/bin/mv" <<'SCRIPT'
#!/usr/bin/env bash
last=""
for arg in "$@"; do
  last="$arg"
done
if [ -n "${QS_TEST_CLEAR_STATE_FAIL:-}" ] && [ "$last" = "$HOME/.cache/qs-shell/update-available.json" ]; then
  printf 'blocked clear_state mv: %s\n' "$*" >> "$HOME/mv.log"
  exit 1
fi
exec /usr/bin/mv "$@"
SCRIPT
  chmod 755 "$root/bin/qs" "$root/bin/systemd-run" "$root/bin/setsid" "$root/bin/mv"
}

install_failing_systemctl() {
  local root="$1"
  mkdir -p "$root/bin"
  cat > "$root/bin/systemctl" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/systemctl.log"
exit 1
SCRIPT
  chmod 755 "$root/bin/systemctl"
}

install_fake_notify() {
  local root="$1"
  mkdir -p "$root/bin"
  cat > "$root/bin/notify-send" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/notify.log"
SCRIPT
  chmod 755 "$root/bin/notify-send"
}

assert_pending_state_preserved() {
  local root="$1" before="$2"
  assert_eq "$before" "$(jq -c . "$(state_file "$root")")" "pending state preserved"
}

assert_dest_label() {
  local root="$1" label="$2"
  assert_eq "$label" "$(tr -d '\n' < "$root/dest/payload.txt")" "deployed payload label"
}

assert_installed_hook() {
  local root="$1" label="$2"
  assert_eq "theme-hook-$label" "$(tr -d '\n' < "$root/home/.config/omarchy/hooks/theme-set.d/50-quickshell-bar.sh")" "installed theme hook"
}

assert_installed_post_boot_hook() {
  local root="$1" label="$2"
  assert_eq "post-boot-$label" "$(tr -d '\n' < "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise")" "installed post-boot hook"
}

assert_progress_json_valid() {
  local root="$1"
  jq -e '(.schemaVersion == 1)
    and (.runId | type == "string")
    and (.state | type == "string")
    and (.phase | type == "string")
    and (.step | type == "number")
    and (.totalSteps == 5)
    and (.targetCommit | type == "string")
    and (.startedEpoch | type == "number")
    and (.updatedEpoch | type == "number")
    and (.screenName | type == "string")
    and (.error | type == "string")
    and (.acknowledged | type == "boolean")
    and (.panelOpen | type == "boolean")' "$(progress_file "$root")" >/dev/null
}

assert_progress_state() {
  local root="$1" state="$2" phase="$3" step="$4" msg="$5"
  assert_progress_json_valid "$root"
  jq -e --arg state "$state" --arg phase "$phase" --argjson step "$step" \
    '(.state == $state) and (.phase == $phase) and (.step == $step)' \
    "$(progress_file "$root")" >/dev/null || fail "$msg"
}

progress_run_id() {
  jq -r '.runId' "$(progress_file "$1")"
}

assert_progress_trace_order() {
  local root="$1" want="$2" got
  got="$(awk -F '\t' '{print $2 ":" $3}' "$(progress_trace_file "$root")" | paste -sd ' ' -)"
  assert_eq "$want" "$got" "progress phase order"
}

installed_payload_hash() {
  local dir="$1"
  (
    cd "$dir"
    LC_ALL=C find . -type f ! -name '.qsrise' ! -name '.qsrise-commit' ! -name '.qsrise-payload-tree' -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 sha256sum \
      | sha256sum \
      | awk '{print $1}'
  )
}

target_payload_hash() {
  local root="$1" commit="$2" tmp
  tmp="$root/expected-payload"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  git -C "$root/repo" archive "$commit:versions/V1" | tar -x -C "$tmp"
  installed_payload_hash "$tmp"
}

test_remote_moves_but_apply_installs_checked_target() {
  local root="$WORK/move"
  init_fixture "$root"
  make_update_and_check "$root" A
  local target_a
  target_a="$(jq -r '.targetCommit' "$(state_file "$root")")"

  commit_payload "$root/repo" B
  git -C "$root/repo" push origin main >/dev/null 2>&1
  run_apply "$root" >/dev/null

  assert_dest_label "$root" A
  assert_eq "$target_a" "$(tr -d '\n' < "$root/dest/.qsrise-commit")" "deploy stayed pinned to checked target"
  assert_eq "$(target_payload_hash "$root" "$target_a")" "$(installed_payload_hash "$root/dest")" "installed payload byte hash"
  assert_eq "$(git -C "$root/repo" rev-parse "$target_a:versions/V1")" \
    "$(tr -d '\n' < "$root/dest/.qsrise-payload-tree")" "installed payload tree marker"
  assert_eq A "$(tr -d '\n' < "$root/home/companion-marker")" "companion came from checked target"
  assert_installed_hook "$root" A
  assert_eq 0 "$(jq -r '.behind' "$(state_file "$root")")" "success cleared state"
}

test_hook_only_update_installs_checked_hook() {
  local root="$WORK/hook-only"
  init_fixture "$root"
  printf 'theme-hook-A\n' > "$root/repo/hooks/50-quickshell-bar.sh"
  git -C "$root/repo" add hooks/50-quickshell-bar.sh >/dev/null
  git -C "$root/repo" commit -m "hook-only" >/dev/null
  git -C "$root/repo" push origin main >/dev/null 2>&1

  HOME="$root/home" QS_SHELL_REPO="$root/repo" QS_SHELL_DEST="$root/dest" "$CHECK"
  local target hook_blob
  target="$(jq -r '.targetCommit' "$(state_file "$root")")"
  hook_blob="$(git -C "$root/repo" rev-parse "$target:hooks/50-quickshell-bar.sh")"
  jq -e --arg hook "$hook_blob" '(.schemaVersion == 5) and (.behind == 1) and (.hookBlob == $hook)' "$(state_file "$root")" >/dev/null

  run_apply "$root" >/dev/null
  assert_dest_label "$root" base
  assert_installed_hook "$root" A
  assert_eq "$target" "$(tr -d '\n' < "$root/dest/.qsrise-commit")" "hook-only update deployed checked target"
  assert_eq 0 "$(jq -r '.behind' "$(state_file "$root")")" "success cleared state"
}

test_post_boot_only_update_refreshes_installed_hook() {
  local root="$WORK/post-boot-only"
  init_fixture "$root"
  mkdir -p "$root/home/.config/omarchy/hooks/post-boot.d"
  printf 'OLD-HOOK\n' > "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  chmod 755 "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  printf 'post-boot-A\n' > "$root/repo/contrib/post-boot.d/quickshell-rise"
  git -C "$root/repo" add contrib/post-boot.d/quickshell-rise >/dev/null
  git -C "$root/repo" commit -m "post-boot-only" >/dev/null
  git -C "$root/repo" push origin main >/dev/null 2>&1

  HOME="$root/home" QS_SHELL_REPO="$root/repo" QS_SHELL_DEST="$root/dest" "$CHECK"
  local target post_boot_blob
  target="$(jq -r '.targetCommit' "$(state_file "$root")")"
  post_boot_blob="$(git -C "$root/repo" rev-parse "$target:contrib/post-boot.d/quickshell-rise")"
  jq -e --arg blob "$post_boot_blob" '(.schemaVersion == 5) and (.behind == 1) and (.postBootHookBlob == $blob)' "$(state_file "$root")" >/dev/null

  run_apply "$root" >/dev/null
  assert_dest_label "$root" base
  assert_installed_post_boot_hook "$root" A
  assert_eq "$target" "$(tr -d '\n' < "$root/dest/.qsrise-commit")" "post-boot-only update deployed checked target"
  assert_eq 0 "$(jq -r '.behind' "$(state_file "$root")")" "success cleared state"
}

test_post_boot_update_does_not_install_absent_opt_in_hook() {
  local root="$WORK/post-boot-absent"
  init_fixture "$root"
  printf 'post-boot-A\n' > "$root/repo/contrib/post-boot.d/quickshell-rise"
  git -C "$root/repo" add contrib/post-boot.d/quickshell-rise >/dev/null
  git -C "$root/repo" commit -m "post-boot-only" >/dev/null
  git -C "$root/repo" push origin main >/dev/null 2>&1

  HOME="$root/home" QS_SHELL_REPO="$root/repo" QS_SHELL_DEST="$root/dest" "$CHECK"
  run_apply "$root" >/dev/null

  [ ! -e "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise" ] || \
    fail "post-boot update installed absent opt-in hook"
  assert_eq 0 "$(jq -r '.behind' "$(state_file "$root")")" "success cleared state"
}

test_changed_post_boot_hook_blob_aborts_before_mutation() {
  local root="$WORK/post-boot-blob"
  init_fixture "$root"
  mkdir -p "$root/home/.config/omarchy/hooks/post-boot.d"
  printf 'OLD-HOOK\n' > "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  chmod 755 "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  printf 'post-boot-A\n' > "$root/repo/contrib/post-boot.d/quickshell-rise"
  git -C "$root/repo" add contrib/post-boot.d/quickshell-rise >/dev/null
  git -C "$root/repo" commit -m "post-boot-only" >/dev/null
  git -C "$root/repo" push origin main >/dev/null 2>&1
  HOME="$root/home" QS_SHELL_REPO="$root/repo" QS_SHELL_DEST="$root/dest" "$CHECK"
  jq '.postBootHookBlob = "0000000000000000000000000000000000000000"' "$(state_file "$root")" > "$root/state.tmp"
  mv "$root/state.tmp" "$(state_file "$root")"
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded after stored post-boot hook blob was changed"
  fi
  assert_dest_label "$root" base
  assert_eq "OLD-HOOK" "$(tr -d '\n' < "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise")" "post-boot hook survived blob mismatch"
  assert_pending_state_preserved "$root" "$before"
  assert_progress_state "$root" failed validating 2 "post-boot blob mismatch did not fail in validating phase"
}

test_check_clears_stale_schema_before_offline_fetch() {
  local root="$WORK/stale-schema-offline"
  init_fixture "$root"
  mkdir -p "$(dirname "$(state_file "$root")")"
  printf '{"behind":3,"checked":"old"}\n' > "$(state_file "$root")"
  git -C "$root/repo" remote set-url origin "$root/missing-remote.git"

  HOME="$root/home" QS_SHELL_REPO="$root/repo" QS_SHELL_DEST="$root/dest" "$CHECK"
  jq -e '(.schemaVersion == 5) and (.behind == 0)' "$(state_file "$root")" >/dev/null
}

test_alternate_reachable_commit_with_same_subject_aborts() {
  local root="$WORK/alternate-same-subject"
  init_fixture "$root"
  local base target_b before
  base="$(git -C "$root/repo" rev-parse HEAD)"

  printf 'CHECKED-A\n' > "$root/repo/versions/V1/checked-marker"
  git -C "$root/repo" add versions/V1/checked-marker >/dev/null
  git -C "$root/repo" commit -m "same-subject" >/dev/null
  git -C "$root/repo" push origin main >/dev/null 2>&1
  HOME="$root/home" QS_SHELL_REPO="$root/repo" QS_SHELL_DEST="$root/dest" "$CHECK"
  jq -e '(.schemaVersion == 5) and (.behind == 1) and (.summary == ["same-subject"])' "$(state_file "$root")" >/dev/null

  git -C "$root/repo" checkout -b alternate "$base" >/dev/null 2>&1
  printf 'ALTERNATE-B\n' > "$root/repo/versions/V1/alternate-marker"
  git -C "$root/repo" add versions/V1/alternate-marker >/dev/null
  git -C "$root/repo" commit -m "same-subject" >/dev/null
  target_b="$(git -C "$root/repo" rev-parse HEAD)"
  git -C "$root/repo" checkout main >/dev/null 2>&1
  git -C "$root/repo" merge --no-ff alternate -m "merge alternate" >/dev/null
  git -C "$root/repo" push origin main >/dev/null 2>&1

  jq --arg target "$target_b" '.targetCommit = $target' "$(state_file "$root")" > "$root/state.tmp"
  mv "$root/state.tmp" "$(state_file "$root")"
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded after target SHA was changed to alternate reachable commit with same count and subject"
  fi
  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
}

test_later_non_payload_commit_in_target_state_aborts() {
  local root="$WORK/later-non-payload"
  init_fixture "$root"
  make_update_and_check "$root" A
  mkdir -p "$root/repo/docs"
  printf 'docs only\n' > "$root/repo/docs/readme.txt"
  git -C "$root/repo" add docs/readme.txt >/dev/null
  git -C "$root/repo" commit -m "docs-only" >/dev/null
  git -C "$root/repo" push origin main >/dev/null 2>&1
  local target_docs before
  target_docs="$(git -C "$root/repo" rev-parse HEAD)"
  jq --arg target "$target_docs" '.targetCommit = $target' "$(state_file "$root")" > "$root/state.tmp"
  mv "$root/state.tmp" "$(state_file "$root")"
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded after target SHA was changed to later non-payload commit"
  fi
  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
}

test_missing_target_aborts_before_mutation() {
  local root="$WORK/missing-target"
  init_fixture "$root"
  make_update_and_check "$root" A
  local before
  before="$(jq -c . "$(state_file "$root")")"
  jq '.targetCommit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$(state_file "$root")" > "$root/state.tmp"
  mv "$root/state.tmp" "$(state_file "$root")"
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with missing target commit"
  fi
  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
}

test_changed_target_sha_aborts_before_mutation() {
  local root="$WORK/changed-target"
  init_fixture "$root"
  make_update_and_check "$root" A
  commit_payload "$root/repo" B
  git -C "$root/repo" push origin main >/dev/null 2>&1
  local target_b before
  target_b="$(git -C "$root/repo" rev-parse HEAD)"
  jq --arg target "$target_b" '.targetCommit = $target' "$(state_file "$root")" > "$root/state.tmp"
  mv "$root/state.tmp" "$(state_file "$root")"
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded after target SHA was changed to a different reachable commit"
  fi
  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
}

test_unreachable_target_aborts_before_mutation() {
  local root="$WORK/unreachable"
  init_fixture "$root"
  make_update_and_check "$root" A
  local before base
  before="$(jq -c . "$(state_file "$root")")"
  base="$(tr -d '\n' < "$root/dest/.qsrise-commit")"

  git -C "$root/repo" reset --hard "$base" >/dev/null
  commit_payload "$root/repo" C
  git -C "$root/repo" push --force origin main >/dev/null 2>&1

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with target no longer reachable"
  fi
  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
}

test_dirty_repo_is_preserved_while_deploying_checked_target() {
  local root="$WORK/dirty"
  init_fixture "$root"
  make_update_and_check "$root" A
  local target before_head after_head before_status after_status tracked_content staged_content untracked_content
  target="$(jq -r '.targetCommit' "$(state_file "$root")")"
  before_head="$(git -C "$root/repo" rev-parse HEAD)"
  printf 'local tracked edit\n' >> "$root/repo/versions/V1/payload.txt"
  printf 'staged local edit\n' > "$root/repo/local-staged.txt"
  git -C "$root/repo" add local-staged.txt >/dev/null
  printf 'untracked local edit\n' > "$root/repo/local-untracked.txt"
  before_status="$(git -C "$root/repo" status --porcelain=v1)"
  tracked_content="$(cat "$root/repo/versions/V1/payload.txt")"
  staged_content="$(cat "$root/repo/local-staged.txt")"
  untracked_content="$(cat "$root/repo/local-untracked.txt")"

  run_apply "$root" >/dev/null

  after_head="$(git -C "$root/repo" rev-parse HEAD)"
  after_status="$(git -C "$root/repo" status --porcelain=v1)"
  assert_eq "$before_head" "$after_head" "dirty repo HEAD preserved"
  assert_eq "$before_status" "$after_status" "dirty repo status preserved"
  assert_eq "$tracked_content" "$(cat "$root/repo/versions/V1/payload.txt")" "dirty tracked file content preserved"
  assert_eq "$staged_content" "$(cat "$root/repo/local-staged.txt")" "dirty staged file content preserved"
  assert_eq "$untracked_content" "$(cat "$root/repo/local-untracked.txt")" "dirty untracked file content preserved"
  assert_dest_label "$root" A
  assert_eq "$target" "$(tr -d '\n' < "$root/dest/.qsrise-commit")" "dirty repo update deployed checked target"
  assert_eq 0 "$(jq -r '.behind' "$(state_file "$root")")" "success cleared state"
}

test_shell_apply_launcher_uses_systemd_unit() {
  local file="$REPO_ROOT/versions/V1/panels/ShellUpdateTab.qml"
  assert_contains '"systemd-run"' "$file" "shell apply launcher does not use systemd-run"
  assert_contains '"--collect"' "$file" "shell apply launcher does not collect transient unit"
  assert_contains '"--unit=" + applyUnitName()' "$file" "shell apply launcher does not use unique unit name"
  assert_contains '"--property=Type=exec"' "$file" "shell apply launcher does not use Type=exec"
  assert_contains 'cmd.push("bash", applyScript)' "$file" "shell apply launcher does not invoke apply helper"
  assert_not_contains '"setsid"' "$file" "shell apply launcher still uses setsid"
}

test_shell_apply_ui_requires_checked_target_and_dismisses_failure() {
  local file="$REPO_ROOT/versions/V1/panels/ShellUpdateTab.qml"
  assert_contains 'readonly property bool canApply: root.shellUpdateBehind > 0' "$file" "shell apply UI does not require an available update"
  assert_contains '&& root.shellUpdateRepository !== ""' "$file" "shell apply UI does not require the checked repository"
  assert_contains '&& root.shellUpdateUpstreamRef !== ""' "$file" "shell apply UI does not require the checked upstream ref"
  assert_contains '&& root.shellUpdateBaseCommit !== ""' "$file" "shell apply UI does not require the checked base commit"
  assert_contains '&& root.shellUpdateTargetCommit !== ""' "$file" "shell apply UI does not require the checked target commit"
  assert_contains 'if (!canApply) return' "$file" "shell apply launcher is not guarded against incomplete state"
  assert_contains 'label: "Dismiss"' "$file" "failed shell progress has no dismiss action"
  assert_contains 'root.ackShellProgress()' "$file" "failed shell progress dismiss does not acknowledge the terminal state"
  assert_contains 'buttonEnabled: tab.canApply' "$file" "shell apply buttons do not share the checked-target guard"
}

test_apply_restarts_bar_in_own_systemd_unit() {
  local root="$WORK/restart-systemd-unit"
  init_fixture "$root"
  install_fake_systemctl "$root"
  install_fake_restart_tools "$root"
  make_update_and_check "$root" A

  run_apply_with_restart "$root" >/dev/null

  assert_dest_label "$root" A
  assert_contains "--unit=qsrise-bar-" "$root/home/systemd-run.log" "bar restart did not use a transient systemd unit"
  assert_contains "--slice=app-graphical.slice" "$root/home/systemd-run.log" "bar restart did not use app-graphical.slice"
  assert_contains "--property=Type=exec" "$root/home/systemd-run.log" "bar restart did not use Type=exec"
  assert_contains "qs -n -c bar" "$root/home/systemd-run.log" "bar restart did not invoke qs as the systemd service main process"
  [ ! -e "$root/home/setsid.log" ] || fail "bar restart fell back to setsid despite successful systemd-run"
  assert_progress_state "$root" running restarting 5 "successful apply did not reach restarting phase"
}

test_systemd_apply_does_not_setsids_bar_when_systemd_run_fails() {
  local root="$WORK/restart-systemd-fail-closed"
  init_fixture "$root"
  install_fake_systemctl "$root"
  install_fake_restart_tools "$root"
  make_update_and_check "$root" A
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if INVOCATION_ID=test QS_TEST_SYSTEMD_RUN_FAIL=1 run_apply_with_restart "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "systemd-managed apply succeeded after bar systemd-run failed"
  fi

  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
  [ ! -e "$root/home/setsid.log" ] || fail "systemd-managed apply fell back to setsid after systemd-run failed"
  assert_contains "Deploy failed" "$(progress_file "$root")" "restart failure did not record rollback failure"
}

test_restart_success_then_clear_state_failure_restarts_old_bar_with_new_unit() {
  local root="$WORK/restart-clear-state-fail"
  init_fixture "$root"
  install_fake_systemctl "$root"
  install_fake_restart_tools "$root"
  make_update_and_check "$root" A
  local before first second unit_count
  before="$(jq -c . "$(state_file "$root")")"

  if QS_TEST_CLEAR_STATE_FAIL=1 run_apply_with_restart "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded despite clear_state failure after bar start"
  fi

  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
  assert_contains "blocked clear_state mv" "$root/home/mv.log" "clear_state failure was not exercised"
  [ ! -e "$root/home/setsid.log" ] || fail "rollback fell back to setsid"

  unit_count="$(grep -o -- '--unit=qsrise-bar-[^ ]*' "$root/home/systemd-run.log" | wc -l | tr -d ' ')"
  assert_eq 2 "$unit_count" "expected one new-bar start and one rollback-bar start"
  first="$(grep -o -- '--unit=qsrise-bar-[^ ]*' "$root/home/systemd-run.log" | sed -n '1p' | sed 's/^--unit=//')"
  second="$(grep -o -- '--unit=qsrise-bar-[^ ]*' "$root/home/systemd-run.log" | sed -n '2p' | sed 's/^--unit=//')"
  [ -n "$first" ] || fail "first bar unit missing"
  [ -n "$second" ] || fail "rollback bar unit missing"
  [ "$first" != "$second" ] || fail "rollback reused the same bar unit name"
  assert_contains "--user stop $first" "$root/home/systemctl.log" "rollback did not stop the started new-bar unit"
}

test_progress_success_complete_and_ack() {
  local root="$WORK/progress-success"
  init_fixture "$root"
  install_fake_notify "$root"
  make_update_and_check "$root" A
  local target run
  target="$(jq -r '.targetCommit' "$(state_file "$root")")"

  run_apply "$root" >/dev/null

  assert_not_contains "Shell updated" "$(notify_log "$root")" "success notification fired before loaded-bar completion"
  assert_progress_trace_order "$root" "checking:1 validating:2 testing:3 installing:4 restarting:5"
  assert_progress_state "$root" running restarting 5 "successful apply did not wait for loaded-bar completion"
  assert_eq "$target" "$(jq -r '.targetCommit' "$(progress_file "$root")")" "progress target commit"
  assert_eq "DP-1" "$(jq -r '.screenName' "$(progress_file "$root")")" "progress screen name"
  jq -e '.panelOpen == true' "$(progress_file "$root")" >/dev/null || fail "new progress run did not start with panelOpen true"
  run="$(progress_run_id "$root")"

  run_progress_command "$root" --complete-progress "$run"
  assert_progress_state "$root" completed restarting 5 "complete-progress did not mark completed"
  assert_contains "Shell updated" "$(notify_log "$root")" "success notification missing after loaded-bar completion"
  assert_eq 1 "$(grep -Fc 'Shell updated' "$(notify_log "$root")")" "success notification count after completion"

  run_progress_command "$root" --complete-progress "$run"
  assert_eq 1 "$(grep -Fc 'Shell updated' "$(notify_log "$root")")" "success notification was repeated"

  run_progress_command "$root" --ack-progress "$run"
  assert_progress_state "$root" idle "" 0 "ack-progress did not mark idle"
  jq -e '.acknowledged == true' "$(progress_file "$root")" >/dev/null || fail "ack-progress did not acknowledge status"
}

test_progress_panel_visibility_survives_phase_writes() {
  local root="$WORK/progress-panel-open"
  init_fixture "$root"
  make_update_and_check "$root" A
  run_apply "$root" >/dev/null
  local run
  run="$(progress_run_id "$root")"

  run_progress_command "$root" --progress-panel "$run" closed
  jq -e '.panelOpen == false' "$(progress_file "$root")" >/dev/null || fail "progress panel close was not persisted"

  run_progress_command "$root" --complete-progress "$run"
  jq -e '(.state == "completed") and (.panelOpen == false)' "$(progress_file "$root")" >/dev/null || \
    fail "complete-progress did not preserve closed panel state"

  run_progress_command "$root" --progress-panel "$run" open
  jq -e '.panelOpen == true' "$(progress_file "$root")" >/dev/null || fail "progress panel reopen was not persisted"
}

test_complete_progress_requires_target_marker_match() {
  local root="$WORK/progress-complete-mismatch"
  init_fixture "$root"
  install_fake_notify "$root"
  make_update_and_check "$root" A
  run_apply "$root" >/dev/null
  local run
  run="$(progress_run_id "$root")"
  printf '0000000000000000000000000000000000000000\n' > "$root/dest/.qsrise-commit"

  run_progress_command "$root" --complete-progress "$run"

  assert_progress_state "$root" failed restarting 5 "complete-progress accepted wrong deploy marker"
  assert_contains "Loaded shell does not match" "$(progress_file "$root")" "complete-progress mismatch error"
  assert_not_contains "Shell updated" "$(notify_log "$root")" "mismatch emitted success notification"
  assert_contains "Shell update failed" "$(notify_log "$root")" "mismatch did not emit failure notification"
}

test_recent_running_progress_blocks_second_apply() {
  local root="$WORK/progress-double-click"
  init_fixture "$root"
  make_update_and_check "$root" A
  mkdir -p "$(dirname "$(progress_file "$root")")"
  local now before
  now="$(date +%s)"
  jq -nc --argjson now "$now" '{
    schemaVersion: 1,
    runId: "already-running",
    state: "running",
    phase: "installing",
    step: 4,
    totalSteps: 5,
    targetCommit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    startedEpoch: $now,
    updatedEpoch: $now,
    screenName: "DP-2",
    error: "",
    acknowledged: false,
    panelOpen: true
  }' > "$(progress_file "$root")"
  before="$(jq -c . "$(progress_file "$root")")"

  run_apply "$root" >/dev/null

  assert_dest_label "$root" base
  assert_eq "$before" "$(jq -c . "$(progress_file "$root")")" "second apply overwrote active progress"
  [ ! -e "$(progress_trace_file "$root")" ] || fail "second apply started a new progress trace"
}

test_stale_running_progress_can_be_replaced() {
  local root="$WORK/progress-stale"
  init_fixture "$root"
  make_update_and_check "$root" A
  mkdir -p "$(dirname "$(progress_file "$root")")"
  local old
  old="$(( $(date +%s) - 1200 ))"
  jq -nc --argjson old "$old" '{
    schemaVersion: 1,
    runId: "stale-running",
    state: "running",
    phase: "installing",
    step: 4,
    totalSteps: 5,
    targetCommit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    startedEpoch: $old,
    updatedEpoch: $old,
    screenName: "DP-2",
    error: "",
    acknowledged: false,
    panelOpen: true
  }' > "$(progress_file "$root")"

  run_apply "$root" >/dev/null

  assert_dest_label "$root" A
  [ "$(progress_run_id "$root")" != "stale-running" ] || fail "stale progress run was not replaced"
  assert_progress_state "$root" running restarting 5 "stale progress replacement did not finish apply"
}

test_progress_failure_in_checking_phase() {
  local root="$WORK/progress-checking-fail"
  init_fixture "$root"
  local run

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with no pending state"
  fi

  assert_progress_state "$root" failed checking 1 "checking failure did not write failed checking status"
  run="$(progress_run_id "$root")"
  run_progress_command "$root" --ack-progress "$run"
  assert_progress_state "$root" idle "" 0 "checking failure could not be acknowledged with an empty target commit"
  assert_eq true "$(jq -r '.acknowledged' "$(progress_file "$root")")" "acknowledged failure did not persist acknowledgement"
}

test_staging_smoke_failure_keeps_old_deploy_and_pending_state() {
  local root="$WORK/smoke"
  init_fixture "$root"
  make_update_and_check "$root" broken missing-shell
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with staged payload missing shell.qml"
  fi
  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
  assert_progress_state "$root" failed testing 3 "staging smoke failure did not fail in testing phase"
}

test_invalid_shell_qml_fails_smoke_and_keeps_old_deploy() {
  local root="$WORK/invalid-qml"
  init_fixture "$root"
  make_update_and_check "$root" invalid invalid-shell
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with invalid staged shell.qml"
  fi
  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
  assert_progress_state "$root" failed testing 3 "invalid shell failure did not fail in testing phase"
}

test_invalid_import_fails_smoke_and_keeps_old_deploy() {
  local root="$WORK/invalid-import"
  init_fixture "$root"
  make_update_and_check "$root" invalid-import invalid-import
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with staged shell.qml importing an unknown module"
  fi
  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
  assert_progress_state "$root" failed testing 3 "invalid import failure did not fail in testing phase"
}

test_bad_local_import_fails_smoke_and_keeps_old_deploy() {
  local root="$WORK/bad-local-import"
  init_fixture "$root"
  make_update_and_check "$root" bad-local bad-local-import
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with staged shell.qml importing a missing local directory"
  fi
  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
}

test_missing_component_fails_smoke_and_keeps_old_deploy() {
  local root="$WORK/missing-component"
  init_fixture "$root"
  make_update_and_check "$root" missing-component missing-component
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with staged shell.qml referencing a missing component"
  fi
  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
}

test_qs_module_import_passes_smoke() {
  local root="$WORK/qs-module-import"
  init_fixture "$root"
  make_update_and_check "$root" qs-module qs-module-import

  run_apply "$root" >/dev/null
  assert_dest_label "$root" qs-module
  [ ! -e "$root/dest/.qs-shell-smoke.qml" ] || fail "smoke wrapper leaked into deployed payload"
  assert_eq 0 "$(jq -r '.behind' "$(state_file "$root")")" "success cleared state"
}

test_successful_smoke_exits_without_timeout() {
  local root="$WORK/smoke-fast-success"
  init_fixture "$root"
  make_update_and_check "$root" fast
  local start end elapsed
  start="$(date +%s%3N)"
  QS_SHELL_SMOKE_TIMEOUT=5 run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"
  end="$(date +%s%3N)"
  elapsed=$((end - start))
  assert_dest_label "$root" fast
  [ "$elapsed" -lt 4000 ] || fail "successful shell smoke waited for timeout: elapsed=${elapsed}ms"
}

test_qs_module_with_qmldir_smoke_does_not_execute_side_effect() {
  local root="$WORK/qs-module-side-effect"
  init_fixture "$root"
  make_update_and_check "$root" qs-module-side-effect qs-module-import-side-effect

  run_apply "$root" >/dev/null
  assert_dest_label "$root" qs-module-side-effect
  [ ! -e "$root/home/qs-smoke-side-effect" ] || fail "qs.* qmldir smoke executed staged QML side effect"
  assert_eq 0 "$(jq -r '.behind' "$(state_file "$root")")" "success cleared state"
}

test_qs_module_without_qmldir_fails_before_side_effect() {
  local root="$WORK/qs-module-no-qmldir"
  init_fixture "$root"
  make_update_and_check "$root" no-qmldir qs-module-import-no-qmldir-side-effect
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with qs.* module missing qmldir"
  fi
  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
  [ ! -e "$root/home/qs-smoke-side-effect" ] || fail "qs.* no-qmldir smoke executed staged QML side effect"
}

test_manifest_does_not_restore_whole_systemd_wants_dir() {
  if grep -Fxq '.config/systemd/user/timers.target.wants' "$REPO_ROOT/scripts/qs-shell-post-update.targets"; then
    fail "companion target manifest restores whole timers.target.wants directory"
  fi
}

test_companion_manifest_is_required() {
  local root="$WORK/companion-no-manifest"
  init_fixture "$root"
  make_update_and_check "$root" A no-companion-manifest
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded despite companion post-update missing rollback manifest"
  fi
  assert_dest_label "$root" base
  [ ! -e "$root/home/companion-marker" ] || fail "companion ran despite missing manifest"
  assert_pending_state_preserved "$root" "$before"
}

test_real_post_update_refreshes_installed_post_boot_hook_only() {
  local root="$WORK/real-post-update"
  local repo="$REPO_ROOT"

  mkdir -p "$root/home/.local/share" "$root/home/.config/omarchy/hooks/post-boot.d" "$root/bin"
  printf 'cached\n' > "$root/home/.local/share/qs-aur-blacklist.txt"
  printf 'OLD\n' > "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  chmod 755 "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/bin/systemctl"
  chmod 755 "$root/bin/systemctl"

  HOME="$root/home" PATH="$root/bin:$PATH" QS_SHELL_COMPANION_DEFER_SYSTEMD=1 QS_SHELL_REQUIRE_POST_BOOT_SOURCE=1 \
    bash "$repo/scripts/qs-shell-post-update.sh" "$repo" >/dev/null

  cmp -s "$repo/contrib/post-boot.d/quickshell-rise" "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise" || \
    fail "installed post-boot hook was not refreshed"

  rm -rf "$root/home/.config/omarchy/hooks/post-boot.d"
  HOME="$root/home" PATH="$root/bin:$PATH" QS_SHELL_COMPANION_DEFER_SYSTEMD=1 \
    bash "$repo/scripts/qs-shell-post-update.sh" "$repo" >/dev/null

  [ ! -e "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise" ] || \
    fail "post-update installed opt-in post-boot hook unexpectedly"
  grep -Fxq '.config/omarchy/hooks/post-boot.d/quickshell-rise' "$repo/scripts/qs-shell-post-update.targets" || \
    fail "post-boot hook is missing from companion rollback targets"
}

make_minimal_legacy_companion() {
  local root="$1"
  mkdir -p "$root/companion/scripts" "$root/companion/hooks"
  cp "$REPO_ROOT/scripts/qs-shell-post-update.sh" "$root/companion/scripts/qs-shell-post-update.sh"
  printf 'theme-hook\n' > "$root/companion/hooks/50-quickshell-bar.sh"
  chmod 755 "$root/companion/hooks/50-quickshell-bar.sh"
}

test_legacy_post_update_missing_post_boot_source_keeps_installed_hook() {
  local root="$WORK/legacy-post-boot-missing-source"
  make_minimal_legacy_companion "$root"
  mkdir -p "$root/home/.local/share" "$root/home/.config/omarchy/hooks/post-boot.d" "$root/bin"
  printf 'cached\n' > "$root/home/.local/share/qs-aur-blacklist.txt"
  printf 'OLD-HOOK\n' > "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  chmod 755 "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/bin/systemctl"
  chmod 755 "$root/bin/systemctl"

  HOME="$root/home" PATH="$root/bin:$PATH" QS_SHELL_COMPANION_DEFER_SYSTEMD=1 \
    bash "$root/companion/scripts/qs-shell-post-update.sh" "$root/companion" >/dev/null

  assert_eq "OLD-HOOK" "$(tr -d '\n' < "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise")" \
    "legacy missing post-boot source should leave installed hook untouched"
}

test_strict_post_update_missing_post_boot_source_fails() {
  local root="$WORK/strict-post-boot-missing-source"
  make_minimal_legacy_companion "$root"
  mkdir -p "$root/home/.local/share" "$root/home/.config/omarchy/hooks/post-boot.d" "$root/bin"
  printf 'cached\n' > "$root/home/.local/share/qs-aur-blacklist.txt"
  printf 'OLD-HOOK\n' > "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  chmod 755 "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/bin/systemctl"
  chmod 755 "$root/bin/systemctl"

  if HOME="$root/home" PATH="$root/bin:$PATH" QS_SHELL_COMPANION_DEFER_SYSTEMD=1 QS_SHELL_REQUIRE_POST_BOOT_SOURCE=1 \
      bash "$root/companion/scripts/qs-shell-post-update.sh" "$root/companion" >"$root/post.out" 2>"$root/post.err"; then
    fail "strict post-update accepted installed post-boot hook with missing staged source"
  fi
  assert_eq "OLD-HOOK" "$(tr -d '\n' < "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise")" \
    "strict missing post-boot source should not mutate installed hook"
}

test_missing_post_boot_source_rolls_back_and_preserves_pending_state() {
  local root="$WORK/post-boot-missing-source"
  init_fixture "$root"
  mkdir -p "$root/home/.config/omarchy/hooks/post-boot.d"
  printf 'OLD-HOOK\n' > "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  chmod 755 "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise"
  make_update_and_check "$root" A missing-postboot-source
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded with installed post-boot hook but missing staged source"
  fi
  assert_dest_label "$root" base
  assert_eq "OLD-HOOK" "$(tr -d '\n' < "$root/home/.config/omarchy/hooks/post-boot.d/quickshell-rise")" "post-boot hook restored after missing source"
  assert_pending_state_preserved "$root" "$before"
}

test_companion_failure_keeps_old_deploy_and_pending_state() {
  local root="$WORK/companion-fail"
  init_fixture "$root"
  make_update_and_check "$root" A bad-companion
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded despite failing companion post-update"
  fi
  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
  assert_progress_state "$root" failed installing 4 "companion failure did not fail in installing phase"
}

test_companion_mutation_failure_restores_side_effect() {
  local root="$WORK/companion-mutation-fail"
  init_fixture "$root"
  printf 'BASE-SIDE-EFFECT\n' > "$root/home/companion-side-effect"
  make_update_and_check "$root" A bad-companion-after-mutation
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded despite companion mutation followed by failure"
  fi
  assert_dest_label "$root" base
  assert_eq BASE-SIDE-EFFECT "$(tr -d '\n' < "$root/home/companion-side-effect")" "companion side effect restored"
  assert_pending_state_preserved "$root" "$before"
}

test_hook_mutation_failure_restores_old_hook() {
  local root="$WORK/hook-mutation-fail"
  init_fixture "$root"
  make_update_and_check "$root" A hook-mutation-fail
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded despite hook mutation followed by companion failure"
  fi
  assert_dest_label "$root" base
  assert_installed_hook "$root" base
  assert_pending_state_preserved "$root" "$before"
}

test_companion_blacklist_side_effects_restore() {
  local root="$WORK/companion-blacklist-fail"
  init_fixture "$root"
  mkdir -p "$root/home/.local/share"
  printf 'BASE-LIST\n' > "$root/home/.local/share/qs-aur-blacklist.txt"
  printf 'BASE-META\n' > "$root/home/.local/share/qs-aur-blacklist.txt.meta.json"
  printf 'BASE-PENDING\n' > "$root/home/.local/share/qs-aur-blacklist.txt.pending"
  make_update_and_check "$root" A blacklist-side-effects-fail
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded despite companion blacklist mutation followed by failure"
  fi
  assert_dest_label "$root" base
  assert_eq BASE-LIST "$(tr -d '\n' < "$root/home/.local/share/qs-aur-blacklist.txt")" "blacklist list restored"
  assert_eq BASE-META "$(tr -d '\n' < "$root/home/.local/share/qs-aur-blacklist.txt.meta.json")" "blacklist meta restored"
  assert_eq BASE-PENDING "$(tr -d '\n' < "$root/home/.local/share/qs-aur-blacklist.txt.pending")" "blacklist pending restored"
  assert_pending_state_preserved "$root" "$before"
}

test_companion_failure_restores_systemd_state() {
  local root="$WORK/companion-systemd-fail"
  init_fixture "$root"
  install_fake_systemctl "$root"
  make_update_and_check "$root" A bad-companion-after-mutation
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded despite companion failure in systemd restore test"
  fi
  assert_dest_label "$root" base
  assert_contains "--user daemon-reload" "$root/home/systemctl.log" "systemd daemon-reload was not run during rollback"
  assert_contains "--user enable qs-shell-update-check.timer" "$root/home/systemctl.log" "previous enabled timer state was not restored"
  assert_contains "--user start qs-shell-update-check.timer" "$root/home/systemctl.log" "previous active timer state was not restored"
  assert_pending_state_preserved "$root" "$before"
}

test_systemd_restore_happens_after_file_restore() {
  local root="$WORK/companion-systemd-order"
  init_fixture "$root"
  install_fake_systemctl "$root"
  mkdir -p "$root/home/.config/systemd/user"
  printf 'BASE-UNIT\n' > "$root/home/.config/systemd/user/qs-shell-update-check.timer"
  make_update_and_check "$root" A systemd-unit-mutation-fail
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded despite companion systemd unit mutation followed by failure"
  fi
  assert_dest_label "$root" base
  assert_eq BASE-UNIT "$(tr -d '\n' < "$root/home/.config/systemd/user/qs-shell-update-check.timer")" "systemd unit file restored"
  assert_contains "daemon-reload-unit=BASE-UNIT" "$root/home/systemctl.log" "systemd daemon-reload did not observe restored unit files"
  assert_pending_state_preserved "$root" "$before"
}

test_systemd_commit_failure_keeps_pending_state() {
  local root="$WORK/systemd-commit-fail"
  init_fixture "$root"
  install_failing_systemctl "$root"
  make_update_and_check "$root" A systemd-unit-mutation-ok
  local before
  before="$(jq -c . "$(state_file "$root")")"

  if run_apply "$root" >"$root/apply.out" 2>"$root/apply.err"; then
    fail "apply succeeded despite systemctl failing during commit phase"
  fi
  assert_dest_label "$root" base
  assert_pending_state_preserved "$root" "$before"
}

test_remote_moves_but_apply_installs_checked_target
test_check_clears_stale_schema_before_offline_fetch
test_hook_only_update_installs_checked_hook
test_post_boot_only_update_refreshes_installed_hook
test_post_boot_update_does_not_install_absent_opt_in_hook
test_changed_post_boot_hook_blob_aborts_before_mutation
test_missing_target_aborts_before_mutation
test_changed_target_sha_aborts_before_mutation
test_alternate_reachable_commit_with_same_subject_aborts
test_later_non_payload_commit_in_target_state_aborts
test_unreachable_target_aborts_before_mutation
test_dirty_repo_is_preserved_while_deploying_checked_target
test_shell_apply_launcher_uses_systemd_unit
test_shell_apply_ui_requires_checked_target_and_dismisses_failure
test_apply_restarts_bar_in_own_systemd_unit
test_systemd_apply_does_not_setsids_bar_when_systemd_run_fails
test_restart_success_then_clear_state_failure_restarts_old_bar_with_new_unit
test_progress_success_complete_and_ack
test_progress_panel_visibility_survives_phase_writes
test_complete_progress_requires_target_marker_match
test_recent_running_progress_blocks_second_apply
test_stale_running_progress_can_be_replaced
test_progress_failure_in_checking_phase
test_staging_smoke_failure_keeps_old_deploy_and_pending_state
test_invalid_shell_qml_fails_smoke_and_keeps_old_deploy
test_invalid_import_fails_smoke_and_keeps_old_deploy
test_bad_local_import_fails_smoke_and_keeps_old_deploy
test_missing_component_fails_smoke_and_keeps_old_deploy
test_qs_module_import_passes_smoke
test_successful_smoke_exits_without_timeout
test_qs_module_with_qmldir_smoke_does_not_execute_side_effect
test_qs_module_without_qmldir_fails_before_side_effect
test_manifest_does_not_restore_whole_systemd_wants_dir
test_companion_manifest_is_required
test_real_post_update_refreshes_installed_post_boot_hook_only
test_legacy_post_update_missing_post_boot_source_keeps_installed_hook
test_strict_post_update_missing_post_boot_source_fails
test_missing_post_boot_source_rolls_back_and_preserves_pending_state
test_companion_failure_keeps_old_deploy_and_pending_state
test_companion_mutation_failure_restores_side_effect
test_hook_mutation_failure_restores_old_hook
test_companion_blacklist_side_effects_restore
test_companion_failure_restores_systemd_state
test_systemd_restore_happens_after_file_restore
test_systemd_commit_failure_keeps_pending_state

printf 'qs-shell-update regression tests passed\n'
