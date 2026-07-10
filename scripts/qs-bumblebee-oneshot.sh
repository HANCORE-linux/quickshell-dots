#!/usr/bin/env bash
# One-shot bumblebee scan against a user-picked project folder. Not part of
# the periodic security scan (qs-security-scan.sh, which runs --profile=baseline
# system-wide) -- this is an ad-hoc --profile=project scan of one folder, using
# the same bundled threat-intel catalog for real findings.
set -uo pipefail

BUMBLEBEE_BIN="${QS_SEC_BUMBLEBEE:-bumblebee}"
BUMBLEBEE_CATALOG="${QS_SEC_BUMBLEBEE_CATALOG:-$HOME/.local/share/qs-security/threat-intel}"

# Resolve to an absolute path up front: bumblebee is `go install`ed into
# GOBIN, which mise does not shim, and the floating terminal below launches
# through uwsm-app/xdg-terminal-exec, which may not inherit this script's
# PATH at all (uwsm often relaunches apps against the systemd user-manager's
# environment rather than the calling process's). Embedding a bare command
# name in $cmd would silently fail there even with PATH fixed here.
if command -v "$BUMBLEBEE_BIN" >/dev/null 2>&1; then
  BUMBLEBEE_BIN="$(command -v "$BUMBLEBEE_BIN")"
elif command -v go >/dev/null 2>&1; then
  gobin="$(go env GOBIN 2>/dev/null)"
  [ -n "$gobin" ] && [ -x "$gobin/$BUMBLEBEE_BIN" ] && BUMBLEBEE_BIN="$gobin/$BUMBLEBEE_BIN"
fi

dir="$(zenity --file-selection --directory --title="bumblebee: pick a project folder" 2>/dev/null)"
[ -z "$dir" ] && exit 0   # cancelled

catalog_args=()
[ -d "$BUMBLEBEE_CATALOG" ] && catalog_args=(--exposure-catalog "$BUMBLEBEE_CATALOG")

cmd="$BUMBLEBEE_BIN scan --profile=project --root $(printf '%q' "$dir") ${catalog_args[*]} | jq -r '
  if .record_type == \"finding\" then
    \"\u001b[31m[FINDING]\u001b[0m \" + .ecosystem + \" \" + .name + \"@\" + .version + \" -- \" + (.rule_id // \"see catalog\")
  elif .record_type == \"scan_summary\" then
    \"\n\u001b[36m----------------------------------------\u001b[0m\n\" +
    \"  packages: \" + (.counts.package | tostring) +
    \"   findings: \" + (.counts.finding | tostring) +
    \"   duration: \" + (.duration_ms | tostring) + \"ms\"
  else empty end
'"
omarchy-launch-floating-terminal-with-presentation "$cmd"
