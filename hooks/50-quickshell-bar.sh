#!/usr/bin/env bash
source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"

theme_time="$(stat -c '%Y' "$input_file" 2>/dev/null || echo "0")"
payload="$(tomlq -c --arg name "omarchy-${theme_time}" '{name: $name, colors: (with_entries(.key |= ascii_downcase))}' "$input_file" 2>/dev/null)"

if [ -n "$payload" ]; then
    qs -c bar ipc call theme apply "${payload}" 2>/dev/null || true
fi

success "Quickshell bar colors updated"
