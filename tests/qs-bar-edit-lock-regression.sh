#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V1_BAR="$REPO_ROOT/versions/V1/BarSlot.qml"
V2_BAR="$REPO_ROOT/versions/V1/variants/V2/BarSlot.qml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_unlock_guard() {
  local id="$1" file="$2" block
  block="$(sed -n "/id: ${id}[[:space:]]*$/,+8p" "$file")"
  [[ -n $block ]] || fail "missing MouseArea id: $id in $file"
  grep -Fq 'enabled: barSlot.root.barUnlocked' <<<"$block" \
    || fail "$id can mutate separators while the bar is locked"
}

assert_unlock_guard mkMa "$V1_BAR"
assert_unlock_guard bMa "$V1_BAR"
assert_unlock_guard sepMa "$V2_BAR"

printf 'PASS: separator edit handles require unlock mode\n'
