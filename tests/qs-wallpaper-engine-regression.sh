#!/usr/bin/env bash
# Contract regression for the "animated" (Wallpaper Engine) image-picker mode.
# Pins the lifecycle/robustness guarantees agreed in review: capability guard,
# centralized adapter (no duplicated shell pipeline), structured error state,
# safe serialization, atomic cache, apply feedback, and the transition back to
# static wallpapers. Static assertions on the QML sources — QML behavior is not
# executable from bash, so these lock the contracts in place.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V1="$REPO_ROOT/versions/V1"
V2="$REPO_ROOT/versions/V1/variants/V2"

PANELS=(
  "$V1/panels/ImageCarouselPanel.qml"
  "$V1/panels/ImageCarouselHearthstone.qml"
  "$V1/panels/ImageCarouselCarousel.qml"
  "$V2/panels/ImageCarouselPanel.qml"
  "$V2/panels/ImageCarouselHearthstone.qml"
  "$V2/panels/ImageCarouselCarousel.qml"
)
THEMES=("$V1/Theme.qml" "$V2/Theme.qml")
ADAPTERS=("$V1/WallpaperEngineAdapter.qml" "$V2/WallpaperEngineAdapter.qml")

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "$3: '$1' missing '$2'"; }
assert_absent()   { grep -Fq -- "$2" "$1" && fail "$3: '$1' unexpectedly contains '$2'" || true; }
assert_count()    { local n; n="$(grep -Fc -- "$2" "$1" || true)"; [ "$n" = "$3" ] || fail "$4: '$1' has $n of '$2', want $3"; }

# ── 1. IPC route ───────────────────────────────────────────────────────────
assert_contains "$V1/core/IpcRouter.qml" 'function animated(): void { router.openPicker("animated") }' \
  "IPC router exposes picker.animated"
for t in "${THEMES[@]}"; do
  assert_contains "$t" 'function animated(): void { ipcOpenPicker("animated") }' "Theme picker handler routes animated"
done

# ── 2. Capability guard (Omarchy-4 / omarchy-we optional) ────────────────────
for t in "${THEMES[@]}"; do
  assert_contains "$t" 'if (theme.wallpaperEngine.checked && !theme.wallpaperEngine.available) return' \
    "ipcOpenPicker guards animated on capability"
  assert_contains "$t" 'WallpaperEngineAdapter { id: wallpaperEngineAdapter }' "Theme owns one shared adapter"
done

# ── 3. Centralized adapter — no duplicated command pipeline in the panels ────
for a in "${ADAPTERS[@]}"; do
  [ -f "$a" ] || fail "adapter missing: $a"
  assert_contains "$a" '"omarchy-we", "ipc", "version"' "adapter probes capability version"
  assert_contains "$a" 'adapter.contract >= adapter.requiredContract' "adapter enforces version contract"
  assert_contains "$a" '"omarchy-we", "ipc", "entries"' "adapter owns the entries fetch"
done
for p in "${PANELS[@]}"; do
  assert_absent "$p" 'omarchy-we ipc entries' "panel must not duplicate the entries pipeline"
  assert_absent "$p" 'omarchy-we ipc current' "panel must not duplicate the current pipeline"
  assert_contains "$p" 'root.wallpaperEngine.refresh()' "panel delegates animated load to the adapter"
done

# ── 4. Structured error state (failing/incompatible CLI is not empty) ────────
for a in "${ADAPTERS[@]}"; do
  assert_contains "$a" 'if (exitCode !== 0) {' "adapter treats non-zero exit as error"
  assert_contains "$a" 'adapter.errorText =' "adapter records an error message"
  assert_contains "$a" 'returned malformed JSON' "adapter reports malformed JSON"
done
for p in "${PANELS[@]}"; do
  assert_contains "$p" 'root.wallpaperEngine.errorText !== ""' "panel shows the adapter error, not empty state"
done

# ── 5. Safe serialization (sanitize every field) + validation ────────────────
for a in "${ADAPTERS[@]}"; do
  assert_contains "$a" '(c < 32) ? " " : t[i]' "adapter strips control chars from fields"
  assert_contains "$a" 'if (id === "" || preview === "") continue' "adapter validates required fields"
done

# ── 6. Apply success/failure feedback ────────────────────────────────────────
for a in "${ADAPTERS[@]}"; do
  assert_contains "$a" 'adapter.applied(exitCode === 0)' "adapter signals apply success/failure"
  assert_contains "$a" 'Failed to apply wallpaper' "adapter notifies on a failed apply"
done

# ── 7. Transition back to static wallpapers stops the renderer ───────────────
for a in "${ADAPTERS[@]}"; do
  assert_contains "$a" '"omarchy-we", "ipc", "kill"' "adapter tears down the renderer"
done
for p in "${PANELS[@]}"; do
  # once in the theme branch, once in the static-wallpaper branch
  assert_count "$p" 'if (root.wallpaperEngine.available) root.wallpaperEngine.stopRenderer()' 2 \
    "static apply stops the renderer in both theme and wallpaper branches"
done

# ── 8. Atomic cache replacement (temp file + rename, after validation) ───────
for a in "${ADAPTERS[@]}"; do
  assert_contains "$a" 'mv -f' "adapter cache write renames atomically"
  assert_contains "$a" 'cacheWriteProc.running = true' "adapter writes cache only in the success branch"
done

# ── 9. V1 / V2 parity for the new + changed picker files ─────────────────────
for rel in WallpaperEngineAdapter.qml panels/ImageCarouselPanel.qml \
           panels/ImageCarouselHearthstone.qml panels/ImageCarouselCarousel.qml \
           panels/ImagePickerModel.js; do
  cmp -s "$V1/$rel" "$V2/$rel" || fail "V1/V2 diverged: $rel"
done

printf 'qs-wallpaper-engine regression tests passed\n'
