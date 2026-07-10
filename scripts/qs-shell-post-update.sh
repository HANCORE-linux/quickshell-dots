#!/usr/bin/env bash
# QS-Shell post-update hook.
#
# Called by qs-shell-apply-update.sh after every successful shell update, with
# the repo root as $1. Installs/refreshes the companion pieces that live
# OUTSIDE the bar config dir — helper scripts and systemd user units — so a
# bar update is complete on its own and never needs a manual install.sh re-run.
#
# Idempotent and defensive: a missing source file is skipped, a failing step
# warns the caller via exit code but must never break the already-applied
# update. Opt-in AI backends are refreshed only when installed or discoverable.
set -uo pipefail

repo="${1:-${QS_SHELL_REPO:-$HOME/.local/share/quickshell-dots}}"
bin="$HOME/.local/bin"
qsbin="$HOME/.config/quickshell/bin"
units="$HOME/.config/systemd/user"

# install via temp + rename: the target gets a NEW inode, so replacing a script
# that is currently executing (e.g. the apply script calling us) is safe.
put() { # src dst mode
  local src="$1" dst="$2" mode="$3" t
  [ -f "$src" ] || return 0
  t="$(mktemp "$dst.XXXXXX")" || return 1
  cp "$src" "$t" && chmod "$mode" "$t" && mv -f "$t" "$dst" || { rm -f "$t"; return 1; }
}

seed_theme_state() {
  local state="$HOME/.cache/qs-theme-updates.json"
  local t
  [ -e "$state" ] && return 0
  mkdir -p "$(dirname "$state")" || return 1
  t="$(mktemp -p "$(dirname "$state")" .qs-theme-updates.XXXXXX)" || return 1
  if printf '{"checked":"","total":0,"reachable":0,"outdated":0,"localEdits":0,"degraded":false,"currentStale":false,"themes":[]}\n' > "$t" \
      && mv "$t" "$state"; then
    return 0
  fi
  rm -f "$t"
  return 1
}

rc=0
mkdir -p "$bin" "$qsbin" "$units"

# ── ArchUpdater security gate + weekly blacklist refresh ───────
put "$repo/scripts/qs-arch-security-gate.sh" "$bin/qs-arch-security-gate.sh" 755 || rc=1
if put "$repo/scripts/qs-aur-blacklist-fetch.sh" "$bin/qs-aur-blacklist-fetch.sh" 755; then
  put "$repo/systemd/qs-aur-blacklist-fetch.service" "$units/qs-aur-blacklist-fetch.service" 644 || rc=1
  put "$repo/systemd/qs-aur-blacklist-fetch.timer"   "$units/qs-aur-blacklist-fetch.timer"   644 || rc=1
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now qs-aur-blacklist-fetch.timer >/dev/null 2>&1 || true
  # prime the list once so the gate is armed right away (keep an existing list)
  [ -s "$HOME/.local/share/qs-aur-blacklist.txt" ] || \
    "$bin/qs-aur-blacklist-fetch.sh" >/dev/null 2>&1 || true
else
  rc=1
fi

# ── Security widget scanner + ad-hoc project scan ───────────────
if put "$repo/scripts/qs-security-scan.sh" "$bin/qs-security-scan.sh" 755; then
  put "$repo/scripts/qs-bumblebee-oneshot.sh" "$bin/qs-bumblebee-oneshot.sh" 755 || rc=1
  put "$repo/systemd/qs-security-scan.service" "$units/qs-security-scan.service" 644 || rc=1
  put "$repo/systemd/qs-security-scan.timer"   "$units/qs-security-scan.timer"   644 || rc=1
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now qs-security-scan.timer >/dev/null 2>&1 || true
  [ -s "$HOME/.cache/qs-security-status.json" ] || "$bin/qs-security-scan.sh" >/dev/null 2>&1 || true
else
  rc=1
fi

# ── keep the updater itself current (check + apply + this hook) ─
put "$repo/scripts/qs-shell-check-update.sh" "$qsbin/qs-shell-check-update.sh" 755 || rc=1
put "$repo/scripts/qs-shell-apply-update.sh" "$qsbin/qs-shell-apply-update.sh" 755 || rc=1
put "$repo/systemd/qs-shell-update-check.service" "$units/qs-shell-update-check.service" 644 || rc=1
put "$repo/systemd/qs-shell-update-check.timer"   "$units/qs-shell-update-check.timer"   644 || rc=1

# ── theme-update checker used by ArchUpdaterPanel ───────────────
if [ -f "$repo/scripts/qs-theme-update-check.sh" ]; then
  put "$repo/scripts/qs-theme-update-check.sh" "$qsbin/qs-theme-update-check.sh" 755 || rc=1
  seed_theme_state || rc=1
fi

# Re-arm both timers so refreshed unit files take effect now. Plain
# enable --now is a no-op on an already-active timer, and a daemon-reload
# alone can leave a monotonic timer "elapsed" with no next trigger.
systemctl --user daemon-reload >/dev/null 2>&1 || true
systemctl --user enable --now qs-shell-update-check.timer >/dev/null 2>&1 || true
systemctl --user try-restart qs-shell-update-check.timer qs-aur-blacklist-fetch.timer qs-security-scan.timer >/dev/null 2>&1 || true

# ── opt-in components: refresh only if the user installed them ──
if [ -x "$bin/claude-usage" ]; then
  put "$repo/scripts/claude-usage" "$bin/claude-usage" 755 || rc=1
fi
if [ -x "$bin/codex-usage" ]; then
  put "$repo/scripts/codex-usage" "$bin/codex-usage" 755 || rc=1
fi
ai_backend_installed=0
if [ -x "$bin/claude-usage" ] || [ -x "$bin/codex-usage" ] || [ -x "$bin/opencode-usage" ]; then
  ai_backend_installed=1
fi
opencode_available=0
if command -v opencode >/dev/null 2>&1 || [ -e "$HOME/.local/share/opencode/opencode.db" ]; then
  opencode_available=1
fi
if [ -x "$bin/opencode-usage" ] || { [ "$ai_backend_installed" -eq 1 ] && [ "$opencode_available" -eq 1 ]; }; then
  put "$repo/scripts/opencode-usage" "$bin/opencode-usage" 755 || rc=1
  put "$repo/systemd/opencode-usage.service" "$units/opencode-usage.service" 644 || rc=1
  put "$repo/systemd/opencode-usage.timer"   "$units/opencode-usage.timer"   644 || rc=1
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now opencode-usage.timer >/dev/null 2>&1 || true
fi

exit "$rc"
