.pragma library

var omarchyPathCmd = "PATH=\"$HOME/.local/share/omarchy/bin:$PATH\"; export PATH; "

// Prefer omarchy-shell's display resolver when present. The fallback matches
// omarchy-brightness-display's device preference, with /sys-anchored globs so
// Quickshell's working directory cannot affect the selected device.
var backlightDeviceCmd = omarchyPathCmd + "if command -v omarchy-hw-display >/dev/null 2>&1; then BL=$(omarchy-hw-display 2>/dev/null) || exit 0; [ -n \"$BL\" ] || exit 0; else BL=$(ls -1 /sys/class/backlight 2>/dev/null | head -n1); for C in /sys/class/backlight/amdgpu_bl* /sys/class/backlight/intel_backlight /sys/class/backlight/acpi_video*; do [ -e \"$C\" ] && { BL=\"${C##*/}\"; break; }; done; [ -n \"$BL\" ] || exit 0; fi; "

var backlightDetectCmd = backlightDeviceCmd + "echo \"$BL\""

var brightnessPercentCmd = backlightDeviceCmd + "brightnessctl -d \"$BL\" -m 2>/dev/null | cut -d',' -f4 | tr -d '%' | awk '{print int($1)}'"

function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

function brightnessSetCmd(step) {
    var qStep = shellQuote(step)
    return omarchyPathCmd +
        "if command -v omarchy-brightness-display >/dev/null 2>&1; then " +
        "omarchy-brightness-display " + qStep + " >/dev/null 2>&1; " +
        "else " +
        "RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp}; exec 9>\"$RUNTIME_DIR/omarchy-brightness-display.lock\"; flock -n 9 || exit 0; " +
        backlightDeviceCmd +
        "STEP=" + qStep + "; " +
        "CURRENT=$(brightnessctl -d \"$BL\" -m 2>/dev/null | cut -d',' -f4 | tr -d '%' | awk '{print int($1)}'); " +
        "if [ \"$STEP\" = '+5%' ]; then if [ \"${CURRENT:-0}\" -lt 5 ]; then TARGET=$((CURRENT + 1)); else TARGET=$((CURRENT + 5)); fi; [ \"$TARGET\" -gt 100 ] && TARGET=100; STEP=\"$TARGET%\"; " +
        "elif [ \"$STEP\" = '5%-' ]; then if [ \"${CURRENT:-0}\" -le 5 ]; then TARGET=$((CURRENT - 1)); else TARGET=$((CURRENT - 5)); fi; [ \"$TARGET\" -lt 1 ] && TARGET=1; STEP=\"$TARGET%\"; fi; " +
        "brightnessctl -d \"$BL\" set \"$STEP\" >/dev/null 2>&1; " +
        "if command -v omarchy-swayosd-brightness >/dev/null 2>&1; then omarchy-swayosd-brightness \"$(brightnessctl -d \"$BL\" -m 2>/dev/null | cut -d',' -f4 | tr -d '%')\" >/dev/null 2>&1; fi; " +
        "fi"
}

var batteryDataCmd =
    "BAT_PATH=$(upower -e 2>/dev/null | grep BAT | head -n1); [ -n \"$BAT_PATH\" ] || exit 0; " +
    "INFO=$(upower -i \"$BAT_PATH\" 2>/dev/null); [ -n \"$INFO\" ] || exit 0; " +
    "BAT=${BAT_PATH##*/}; BAT=${BAT#battery_}; " +
    "PCT=$(printf '%s\\n' \"$INFO\" | awk '/percentage/ { gsub(\"%\", \"\", $2); print int($2); exit }'); " +
    "STATE=$(printf '%s\\n' \"$INFO\" | awk '/state/ { print $2; exit }'); " +
    "RATE=$(printf '%s\\n' \"$INFO\" | awk '/energy-rate/ { rounded=sprintf(\"%.1f\", $2); sub(/\\.0$/, \"\", rounded); print rounded; exit }'); " +
    "SIZE=$(printf '%s\\n' \"$INFO\" | awk '/energy-full:/ { printf \"%d Wh\", $2; exit }'); " +
    "TIME=$(printf '%s\\n' \"$INFO\" | awk '/time to (empty|full)/ { value=$4; unit=$5; if (unit ~ /^minute/) printf \"%dm\", int(value); else { hours=int(value); minutes=int((value-hours)*60); if (minutes>0) printf \"%dh %dm\", hours, minutes; else printf \"%dh\", hours } exit }'); " +
    "LABEL=$(case \"$STATE\" in charging) echo 'Time to full';; *) echo 'Time left';; esac); " +
    "SYS=/sys/class/power_supply/$BAT; " +
    "FULL=$(cat \"$SYS/charge_full\" 2>/dev/null || cat \"$SYS/energy_full\" 2>/dev/null || echo 0); " +
    "DESIGN=$(cat \"$SYS/charge_full_design\" 2>/dev/null || cat \"$SYS/energy_full_design\" 2>/dev/null || echo 0); " +
    "HEALTH=$(awk -v f=\"$FULL\" -v d=\"$DESIGN\" 'BEGIN{ if(d>0){ h=f*100/d; if(h>100) h=100; printf \"%d%%\", h } }'); " +
    "CYC=$(cat \"$SYS/cycle_count\" 2>/dev/null || echo 0); " +
    "printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\\n' \"$BAT\" \"$PCT\" \"$STATE\" \"$LABEL\" \"$TIME\" \"$RATE\" \"$SIZE\" \"$HEALTH\" \"$CYC\""
