#!/usr/bin/env bash
# QS-Shell update check (writes a state file the bar watches; no apply here).
#
# Topology: the live bar dir is a copy of the integrated versions/V1 generation
# from the deploy clone at ~/.local/share/quickshell-dots by default (override
# with QS_SHELL_REPO). It contains both UI variants. We never run git in the live
# dir; the marker remains V1 because that is the one atomic payload path.
#
# State contract: ~/.cache/qs-shell/update-available.json ALWAYS exists.
#   "up to date" = {"schemaVersion": 5, "behind": 0}.
#   Pending includes immutable provenance: repository, upstreamRef, baseCommit,
#   targetCommit, full commit IDs, payload/companion tree IDs, theme/post-boot
#   hook blobs, version, summary and checked.
# The bar's FileView only ever reads a complete file via atomic replace and never
# depends on delete-detection.
set -euo pipefail

REPO="${QS_SHELL_REPO:-$HOME/.local/share/quickshell-dots}"
DEST="${QS_SHELL_DEST:-$HOME/.config/quickshell/bar}"
STATE_DIR="$HOME/.cache/qs-shell"
STATE="$STATE_DIR/update-available.json"
SCHEMA_VERSION=5
HOOK_PATH="hooks/50-quickshell-bar.sh"
POST_BOOT_HOOK_PATH="contrib/post-boot.d/quickshell-rise"
mkdir -p "$STATE_DIR"

# jq is required (and a hard dependency in install.sh). Warn once rather than
# failing silently under `set -e` after a successful fetch.
if ! command -v jq >/dev/null 2>&1; then
  notify-send -a "QS-Shell" "Shell update check disabled" "jq is not installed." 2>/dev/null || true
  exit 0
fi

# Never leak the temp state file on any error path.
STATE_TMP=""
trap '[ -n "$STATE_TMP" ] && rm -f "$STATE_TMP"' EXIT

write_state() {                       # $1 = complete JSON; atomic replace
  STATE_TMP="$(mktemp -p "$STATE_DIR")"
  printf '%s\n' "$1" > "$STATE_TMP"
  mv "$STATE_TMP" "$STATE"
  STATE_TMP=""
}
clear_state() {
  write_state "$(jq -nc \
    --argjson schema "$SCHEMA_VERSION" \
    --arg c "$(date -Is)" \
    '{schemaVersion: $schema, behind: 0, checked: $c}')"
}

if [ -r "$STATE" ] && ! jq -e --argjson schema "$SCHEMA_VERSION" '.schemaVersion == $schema' "$STATE" >/dev/null 2>&1; then
  clear_state
fi

is_commit_hash() {
  [[ "$1" =~ ^[0-9a-f]{40}$ || "$1" =~ ^[0-9a-f]{64}$ ]]
}

# Installed payload (.qsrise marker; legacy installs without it fall back to V1).
ver="V1"
[ -f "$DEST/.qsrise" ] && ver="$(tr -d '[:space:]' < "$DEST/.qsrise")"
[ -n "$ver" ] || ver="V1"

# No repo ⇒ an update is impossible ⇒ clear any stale badge. (Unlike the offline
# case below, where keeping the last known state is correct.)
if [ ! -d "$REPO/.git" ]; then clear_state; exit 0; fi
cd "$REPO"
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { clear_state; exit 0; }
head_commit="$(git rev-parse 'HEAD^{commit}' 2>/dev/null)" || { clear_state; exit 0; }

# Prefer the commit marker written into the deployed bar. The deploy clone's
# working tree may intentionally remain behind a reviewed update; the marker is
# the source of truth for what the user is currently running.
base_commit="$head_commit"
if [ -f "$DEST/.qsrise-commit" ]; then
  deployed_commit="$(tr -d '[:space:]' < "$DEST/.qsrise-commit" 2>/dev/null || true)"
  if is_commit_hash "$deployed_commit" && git cat-file -e "$deployed_commit^{commit}" 2>/dev/null; then
    base_commit="$deployed_commit"
  fi
fi

# Offline-tolerant: a failed fetch must NOT touch the existing state.
git fetch --quiet origin 2>/dev/null || exit 0

# No upstream ⇒ nothing to compare ⇒ clear stale badge.
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" \
  || { clear_state; exit 0; }
target_commit="$(git rev-parse "$upstream^{commit}" 2>/dev/null)" || exit 0
is_commit_hash "$target_commit" || exit 0
git merge-base --is-ancestor "$base_commit" "$target_commit" 2>/dev/null || exit 0

# Commits the upstream is ahead by that change the deployable payload: THIS
# integrated payload directory, the companion pieces the post-update hook ships
# (helper scripts / systemd units), the Omarchy theme hook coupled to the picker
# cache contract, or the optional post-boot hook. Docs-only commits stay
# badge-free.
payload=("versions/$ver/" "scripts/" "systemd/" "$HOOK_PATH" "$POST_BOOT_HOOK_PATH")
behind="$(git rev-list --count "$base_commit..$target_commit" -- "${payload[@]}" 2>/dev/null || echo 0)"
if [ "${behind:-0}" -eq 0 ]; then
  clear_state
  exit 0
fi
payload_tree="$(git rev-parse "$target_commit:versions/$ver" 2>/dev/null)" || { clear_state; exit 0; }
scripts_tree=""
if git cat-file -e "$target_commit:scripts" 2>/dev/null; then
  scripts_tree="$(git rev-parse "$target_commit:scripts" 2>/dev/null)" || scripts_tree=""
fi
systemd_tree=""
if git cat-file -e "$target_commit:systemd" 2>/dev/null; then
  systemd_tree="$(git rev-parse "$target_commit:systemd" 2>/dev/null)" || systemd_tree=""
fi
hook_blob=""
if git cat-file -e "$target_commit:$HOOK_PATH" 2>/dev/null; then
  hook_blob="$(git rev-parse "$target_commit:$HOOK_PATH" 2>/dev/null)" || hook_blob=""
fi
post_boot_hook_blob=""
if git cat-file -e "$target_commit:$POST_BOOT_HOOK_PATH" 2>/dev/null; then
  post_boot_hook_blob="$(git rev-parse "$target_commit:$POST_BOOT_HOOK_PATH" 2>/dev/null)" || post_boot_hook_blob=""
fi

# Short changelog. `git log --max-count` (no `head` in the pipe) — so a large
# commit count can't SIGPIPE git and trip pipefail before the state is written.
summary="$(git log --max-count=8 --format='%s' "$base_commit..$target_commit" -- "${payload[@]}" | jq -R . | jq -s .)"
commit_ids="$(git rev-list --reverse "$base_commit..$target_commit" | jq -R . | jq -s .)"

write_state "$(jq -nc \
  --argjson schema  "$SCHEMA_VERSION" \
  --argjson behind  "$behind" \
  --arg     repository "$repo_root" \
  --arg     upstreamRef "$upstream" \
  --arg     baseCommit "$base_commit" \
  --arg     targetCommit "$target_commit" \
  --arg     version "$ver" \
  --argjson summary "$summary" \
  --argjson commitIds "$commit_ids" \
  --arg     payloadTree "$payload_tree" \
  --arg     scriptsTree "$scripts_tree" \
  --arg     systemdTree "$systemd_tree" \
  --arg     hookBlob "$hook_blob" \
  --arg     postBootHookBlob "$post_boot_hook_blob" \
  --arg     checked "$(date -Is)" \
  '{schemaVersion: $schema, behind: $behind, repository: $repository,
    upstreamRef: $upstreamRef, baseCommit: $baseCommit, targetCommit: $targetCommit,
    version: $version, summary: $summary, commitIds: $commitIds,
    payloadTree: $payloadTree, scriptsTree: $scriptsTree, systemdTree: $systemdTree,
    hookBlob: $hookBlob, postBootHookBlob: $postBootHookBlob,
    checked: $checked}')"
