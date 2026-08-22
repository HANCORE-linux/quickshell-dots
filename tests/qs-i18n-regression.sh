#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'i18n regression: %s\n' "$*" >&2
  exit 1
}

require_contains() {
  local file=$1 needle=$2
  grep -Fq -- "$needle" "$file" || fail "$file missing: $needle"
}

require_absent() {
  local file=$1 needle=$2
  if grep -Fq -- "$needle" "$file"; then
    fail "$file still contains: $needle"
  fi
}

helper=versions/V1/i18n/Translation.qml
require_contains "$helper" 'Quickshell.env("LC_ALL")'
require_contains "$helper" 'Quickshell.env("LC_MESSAGES")'
require_contains "$helper" 'Quickshell.env("LANG")'
require_contains "$helper" 'readonly property string localeName: language === "it" ? "it_IT" : "en_US"'
require_contains "$helper" '"Weather": "Meteo"'
require_contains "$helper" '"Today": "Oggi"'

for clock in \
  versions/V1/modules/ClockWidget.qml \
  versions/V1/variants/V2/modules/ClockWidget.qml; do
  require_contains "$clock" 'Translation { id: i18n }'
  require_contains "$clock" 'toLocaleString(Qt.locale(i18n.localeName), "ddd, d MMMM yyyy")'
  require_absent "$clock" 'readonly property var months: ["January"'
  require_absent "$clock" 'readonly property var days: ["Sun"'
done

for calendar in \
  versions/V1/panels/CalendarPopup.qml \
  versions/V1/variants/V2/panels/CalendarPopup.qml; do
  require_contains "$calendar" 'Translation { id: i18n }'
  require_contains "$calendar" 'i18n.monthName('
  require_contains "$calendar" 'i18n.weekdayShort(1)'
  require_absent "$calendar" 'model: ["MO","TU","WE","TH","FR","SA","SU"]'
done

for weather in \
  versions/V1/panels/WeatherPanel.qml \
  versions/V1/variants/V2/panels/WeatherPanel.qml; do
  require_contains "$weather" 'Translation { id: i18n }'
  require_contains "$weather" 'return i18n.tr("Today")'
  require_contains "$weather" 'return d.toLocaleString(Qt.locale(i18n.localeName), "ddd")'
  require_contains "$weather" 'text: i18n.tr("Weather")'
  require_contains "$weather" 'i18n.tr("Refreshing…")'
done

printf 'i18n regression checks passed\n'
