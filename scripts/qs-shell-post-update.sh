#!/usr/bin/env bash
# QS-Shell post-update hook.
#
# Called by qs-shell-apply-update.sh after every successful shell update, with
# the repo root as $1. Installs/refreshes the companion pieces that live
# OUTSIDE the bar config dir — helper scripts and systemd user units — so a
# bar update is complete on its own and never needs a manual install.sh re-run.
#
# Idempotent and defensive: legacy companions may lack newer optional sources
# and are skipped, while current strict companions can require reviewed sources
# and report failures via exit code so qs-shell-apply-update.sh can roll the
# whole update transaction back. Opt-in AI backends are refreshed only when
# installed or discoverable.
set -uo pipefail

repo="${1:-${QS_SHELL_REPO:-$HOME/.local/share/quickshell-dots}}"
bin="$HOME/.local/bin"
qsbin="$HOME/.config/quickshell/bin"
units="$HOME/.config/systemd/user"
theme_hooks="$HOME/.config/omarchy/hooks/theme-set.d"
post_boot_hooks="$HOME/.config/omarchy/hooks/post-boot.d"
defer_systemd="${QS_SHELL_COMPANION_DEFER_SYSTEMD:-0}"
require_post_boot_source="${QS_SHELL_REQUIRE_POST_BOOT_SOURCE:-0}"

# install via temp + rename: the target gets a NEW inode, so replacing a script
# that is currently executing (e.g. the apply script calling us) is safe.
put() { # src dst mode
  local src="$1" dst="$2" mode="$3" t
  [ -f "$src" ] || return 0
  t="$(mktemp "$dst.XXXXXX")" || return 1
  if cp "$src" "$t" && chmod "$mode" "$t" && mv -f "$t" "$dst"; then
    return 0
  fi
  rm -f "$t"
  return 1
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

systemd_user() {
  [ "$defer_systemd" = "1" ] && return 0
  systemctl --user "$@" >/dev/null 2>&1 || true
}

rc=0
mkdir -p "$bin" "$qsbin" "$units" "$theme_hooks"

# ── ArchUpdater security gate + weekly blacklist refresh ───────
put "$repo/scripts/qs-arch-security-gate.sh" "$bin/qs-arch-security-gate.sh" 755 || rc=1
put "$repo/scripts/qs-arch-update-check.sh" "$bin/qs-arch-update-check.sh" 755 || rc=1
put "$repo/scripts/qs-arch-apply-update.sh" "$bin/qs-arch-apply-update.sh" 755 || rc=1
if put "$repo/scripts/qs-aur-blacklist-fetch.sh" "$bin/qs-aur-blacklist-fetch.sh" 755; then
  put "$repo/systemd/qs-aur-blacklist-fetch.service" "$units/qs-aur-blacklist-fetch.service" 644 || rc=1
  put "$repo/systemd/qs-aur-blacklist-fetch.timer"   "$units/qs-aur-blacklist-fetch.timer"   644 || rc=1
  systemd_user daemon-reload
  systemd_user enable --now qs-aur-blacklist-fetch.timer
  # prime the list once so the gate is armed right away (keep an existing list)
  [ -s "$HOME/.local/share/qs-aur-blacklist.txt" ] || \
    "$bin/qs-aur-blacklist-fetch.sh" >/dev/null 2>&1 || true
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
  if [ -f "$repo/scripts/qs-theme-apply-update.sh" ]; then
    put "$repo/scripts/qs-theme-update-check.sh" "$qsbin/qs-theme-update-check.sh" 755 || rc=1
    put "$repo/scripts/qs-theme-apply-update.sh" "$qsbin/qs-theme-apply-update.sh" 755 || rc=1
    seed_theme_state || rc=1
  else
    rc=1
  fi
fi

# ── Omarchy theme hook coupled to the picker thumbnail cache contract ─
if [ -f "$repo/hooks/50-quickshell-bar.sh" ]; then
  put "$repo/hooks/50-quickshell-bar.sh" "$theme_hooks/50-quickshell-bar.sh" 755 || rc=1
else
  rc=1
fi

# ── optional autostart hook: refresh only if the user installed it ─────
if [ -f "$post_boot_hooks/quickshell-rise" ]; then
  mkdir -p "$post_boot_hooks" || rc=1
  if [ -f "$repo/contrib/post-boot.d/quickshell-rise" ]; then
    put "$repo/contrib/post-boot.d/quickshell-rise" "$post_boot_hooks/quickshell-rise" 755 || rc=1
  elif [ "$require_post_boot_source" = "1" ]; then
    rc=1
  fi
fi

# Re-arm both timers so refreshed unit files take effect now. Plain
# enable --now is a no-op on an already-active timer, and a daemon-reload
# alone can leave a monotonic timer "elapsed" with no next trigger.
systemd_user daemon-reload
systemd_user enable --now qs-shell-update-check.timer
systemd_user try-restart qs-shell-update-check.timer qs-aur-blacklist-fetch.timer

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
  systemd_user daemon-reload
  systemd_user enable --now opencode-usage.timer
fi

exit "$rc"
