#!/usr/bin/env bash
# Periodic security-status scan for the bar's SecurityWidget.
#
# Runs two independent scanners and merges their result into one status file:
#   AUR_MALWARE = check-atomic-arch, Atomic-Arch-incident IOC scanner (pacman/AUR,
#                 npm/bun caches, eBPF rootkit artifacts, hidden processes, etc.)
#   BUMBLEBEE   = endpoint package inventory across npm/pypi/go/rubygems/homebrew/etc.
#                 No --exposure-catalog is wired yet, so v1 is inventory-only:
#                 findings will read 0 until a catalog is added. Package/ecosystem
#                 counts are still useful signal (drift, unexpected growth).
# bun-checkV2 is deliberately NOT included — it's a per-project dev-env check
# (takes a target directory), not a system-wide scan.
#
# Fail-closed like qs-aur-blacklist-fetch.sh: a scanner that errors out is
# reported as status="error" in its section rather than silently omitted, so
# the widget never shows false-green on a broken scan. Atomic write (tmp + mv).
set -uo pipefail

AUR_MALWARE_SCRIPT="${QS_SEC_AUR_MALWARE:-/local/applications/AUR-Malware/check-atomic-arch_new.sh}"
BUMBLEBEE_BIN="${QS_SEC_BUMBLEBEE:-bumblebee}"
# Maintained supply-chain campaign catalogs (Mastra, Shai-Hulud, GlassWorm,
# node-ipc, TrapDoor, etc.), copied from the bumblebee repo's threat_intel/ dir
# so a `go clean -modcache` can't silently disable real threat matching.
BUMBLEBEE_CATALOG="${QS_SEC_BUMBLEBEE_CATALOG:-$HOME/.local/share/qs-security/threat-intel}"
DEST="${QS_SEC_STATUS_FILE:-$HOME/.cache/qs-security-status.json}"

tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT

json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }

# --- 1. AUR-Malware / Atomic-Arch IOC scan --------------------------------
aur_json='{"status":"error","passed":0,"warnings":0,"failures":0,"summary":"scanner not found"}'
if [ -x "$AUR_MALWARE_SCRIPT" ]; then
  raw_out="$("$AUR_MALWARE_SCRIPT" 2>&1)"
  # strip ANSI color codes before matching the summary line
  plain="$(printf '%s' "$raw_out" | sed -E 's/\x1b\[[0-9;]*m//g')"
  results_line="$(printf '%s' "$plain" | grep -E '^\s*Results:' | tail -1)"
  if [ -n "$results_line" ]; then
    p="$(printf '%s' "$results_line" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')"
    w="$(printf '%s' "$results_line" | grep -oE '[0-9]+ warnings' | grep -oE '[0-9]+')"
    f="$(printf '%s' "$results_line" | grep -oE '[0-9]+ failures' | grep -oE '[0-9]+')"
    p="${p:-0}"; w="${w:-0}"; f="${f:-0}"
    if [ "$f" -gt 0 ]; then status="fail"; elif [ "$w" -gt 0 ]; then status="warn"; else status="clean"; fi
    summary="$p passed, $w warnings, $f failures"
    aur_json="$(printf '{"status":%s,"passed":%s,"warnings":%s,"failures":%s,"summary":%s}' \
      "$(printf '%s' "$status" | json_escape)" "$p" "$w" "$f" "$(printf '%s' "$summary" | json_escape)")"
  else
    aur_json="$(printf '{"status":"error","passed":0,"warnings":0,"failures":0,"summary":%s}' \
      "$(printf '%s' "scan produced no parseable result" | json_escape)")"
  fi
fi

# --- 2. bumblebee inventory scan ------------------------------------------
bb_json='{"status":"error","packages":0,"findings":0,"ecosystems":0,"summary":"bumblebee not found"}'
# bumblebee is `go install`ed into GOBIN, which mise does not shim (mise only
# shims tools it manages directly). Under systemd's stripped-down PATH this
# means bumblebee resolves in an interactive shell but not here, so fall back
# to asking the (shimmed) `go` binary where GOBIN is.
if ! command -v "$BUMBLEBEE_BIN" >/dev/null 2>&1 && command -v go >/dev/null 2>&1; then
  gobin="$(go env GOBIN 2>/dev/null)"
  [ -n "$gobin" ] && [ -x "$gobin/$BUMBLEBEE_BIN" ] && PATH="$gobin:$PATH"
fi
if command -v "$BUMBLEBEE_BIN" >/dev/null 2>&1; then
  ndjson="$tmpd/bumblebee.ndjson"
  catalog_args=()
  [ -d "$BUMBLEBEE_CATALOG" ] && catalog_args=(--exposure-catalog "$BUMBLEBEE_CATALOG")
  if "$BUMBLEBEE_BIN" scan --profile=baseline "${catalog_args[@]}" --output=file --output-file="$ndjson" >/dev/null 2>&1; then
    summary_line="$(grep '"record_type":"scan_summary"' "$ndjson" | tail -1)"
    if [ -n "$summary_line" ]; then
      bb_json="$(printf '%s' "$summary_line" | python3 -c '
import json, sys
r = json.loads(sys.stdin.read())
counts = r.get("counts", {})
pkgs = counts.get("package", 0)
finds = counts.get("finding", 0)
eco = len({p.get("kind","") for p in r.get("roots", [])})
status = r.get("status", "unknown")
out_status = "clean" if (status == "complete" and finds == 0) else ("findings" if finds > 0 else "error")
print(json.dumps({
    "status": out_status,
    "packages": pkgs,
    "findings": finds,
    "ecosystems": eco,
    "summary": f"{pkgs} packages inventoried, {finds} findings against threat-intel catalog",
}))
')"
    fi
  fi
fi

# --- 3. merge + atomic write ----------------------------------------------
mkdir -p "$(dirname "$DEST")"
tmp="$(mktemp "$DEST.XXXXXX")" || exit 1
printf '{"checked":"%s","aur_malware":%s,"bumblebee":%s}\n' \
  "$(date -Iseconds)" "$aur_json" "$bb_json" > "$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$DEST"

echo "qs-security-scan: wrote $DEST"
