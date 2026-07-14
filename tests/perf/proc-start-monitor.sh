#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

monitor_interval="${PROC_MONITOR_INTERVAL:-0.002}"

uptime_milliseconds() {
    local value seconds fraction ignored
    read -r value ignored < /proc/uptime || return 1
    seconds="${value%%.*}"
    fraction="${value#*.}000"
    fraction="${fraction:0:3}"
    REPLY=$((10#$seconds * 1000 + 10#$fraction))
}

stat_starttime() {
    local pid="$1" line rest
    local -a fields
    [[ -r "/proc/$pid/stat" ]] || return 1
    { IFS= read -r line < "/proc/$pid/stat"; } 2>/dev/null || return 1
    rest="${line##*) }"
    [[ "$rest" != "$line" ]] || return 1
    read -r -a fields <<< "$rest"
    ((${#fields[@]} > 19)) || return 1
    [[ "${fields[19]}" =~ ^[0-9]+$ ]] || return 1
    REPLY="${fields[19]}"
}

collect_descendants() {
    local root="$1" output_name="$2" index=0 pid child_file children child
    local -n output="$output_name"
    local -a queue=("$root")
    local -A visited=(["$root"]=1)
    output=()

    while ((index < ${#queue[@]})); do
        pid="${queue[index++]}"
        for child_file in /proc/"$pid"/task/*/children; do
            [[ -r "$child_file" ]] || continue
            children=""
            { IFS= read -r children < "$child_file"; } 2>/dev/null \
                || [[ -n "$children" ]] || continue
            for child in $children; do
                [[ "$child" =~ ^[1-9][0-9]*$ ]] || continue
                [[ -z "${visited[$child]+x}" ]] || continue
                visited["$child"]=1
                queue+=("$child")
                output+=("$child")
            done
        done
    done
}

read_process() {
    local pid="$1" first_start second_start arg
    stat_starttime "$pid" || return 1
    first_start="$REPLY"
    PROCESS_ARGV=()
    [[ -r "/proc/$pid/cmdline" ]] || return 1
    { while IFS= read -r -d '' arg; do
        PROCESS_ARGV+=("$arg")
    done < "/proc/$pid/cmdline"; } 2>/dev/null || true
    ((${#PROCESS_ARGV[@]})) || return 1
    stat_starttime "$pid" || return 1
    second_start="$REPLY"
    [[ "$second_start" == "$first_start" ]] || return 1
    PROCESS_STARTTIME="$first_start"
}

json_quote() {
    local value="$1" output='"' char ordinal i
    for ((i = 0; i < ${#value}; i++)); do
        char="${value:i:1}"
        case "$char" in
            '"') output+='\"' ;;
            '\') output+='\\' ;;
            $'\b') output+='\b' ;;
            $'\f') output+='\f' ;;
            $'\n') output+='\n' ;;
            $'\r') output+='\r' ;;
            $'\t') output+='\t' ;;
            *)
                printf -v ordinal '%d' "'$char"
                if ((ordinal < 32 || ordinal >= 127)); then
                    printf -v char '\\u%04x' "$ordinal"
                fi
                output+="$char"
                ;;
        esac
    done
    REPLY="$output\""
}

argv_json() {
    local arg separator="" output="["
    for arg in "${PROCESS_ARGV[@]}"; do
        json_quote "$arg"
        output+="$separator$REPLY"
        separator=,
    done
    REPLY="$output]"
}

attribute_process() {
    local executable="${PROCESS_ARGV[0]##*/}" arg joined=" ${PROCESS_ARGV[*]} "
    PROCESS_ATTRIBUTION=other
    PROCESS_ENDPOINT=""
    case "$executable" in
        curl)
            PROCESS_ATTRIBUTION=curl
            for arg in "${PROCESS_ARGV[@]:1}"; do
                if [[ "$arg" == http://* || "$arg" == https://* ]]; then
                    PROCESS_ENDPOINT="$arg"
                fi
            done
            ;;
        nvidia-smi)
            PROCESS_ATTRIBUTION=nvidia-smi
            ;;
        bash)
            if [[ "$joined" == *gpu_busy_percent* || "$joined" == *'/class/drm/'* \
                    || "$joined" == *nvidia-smi* || "$joined" == *amdgpu* ]]; then
                PROCESS_ATTRIBUTION=gpu-detector-bash
            fi
            ;;
    esac
}

write_process_record() {
    local output="$1" boot_id="$2" pid="$3" observed_ms="$4" identity
    identity="$boot_id:$pid:$PROCESS_STARTTIME"
    argv_json
    local argv_value="$REPLY"
    attribute_process
    json_quote "$identity"
    local identity_value="$REPLY"
    json_quote "$PROCESS_ATTRIBUTION"
    local attribution_value="$REPLY"
    json_quote "$PROCESS_ENDPOINT"
    local endpoint_value="$REPLY"
    printf '{"identity":%s,"boot_id":"%s","pid":%d,"starttime":%s,' \
        "$identity_value" "$boot_id" "$pid" "$PROCESS_STARTTIME" >> "$output"
    printf '"observed_uptime_ms":%d,"attribution":%s,"endpoint":%s,"argv":%s}\n' \
        "$observed_ms" "$attribution_value" "$endpoint_value" "$argv_value" >> "$output"
}

monitor_starts() {
    local root_pid="$1" duration="$2" output="$3" ready_file="${4:-}"
    local boot_id root_start deadline now pid identity wait_dir monitor_wait_fd
    local -a descendants
    local -A seen=()

    [[ "$root_pid" =~ ^[1-9][0-9]*$ ]] || return 2
    [[ "$duration" =~ ^[1-9][0-9]*$ ]] || return 2
    IFS= read -r boot_id < /proc/sys/kernel/random/boot_id
    [[ "$boot_id" =~ ^[0-9a-f-]+$ ]] || return 1
    stat_starttime "$root_pid" || {
        printf 'cannot read root PID %s\n' "$root_pid" >&2
        return 1
    }
    root_start="$REPLY"
    : > "$output"

    collect_descendants "$root_pid" descendants
    for pid in "${descendants[@]}"; do
        read_process "$pid" || continue
        seen["$boot_id:$pid:$PROCESS_STARTTIME"]=1
    done

    if [[ -n "$ready_file" ]]; then
        : > "$ready_file.tmp.$$"
        mv -f -- "$ready_file.tmp.$$" "$ready_file"
    fi
    uptime_milliseconds
    deadline=$((REPLY + duration * 1000))

    wait_dir="$(mktemp -d "${TMPDIR:-/tmp}/proc-start-monitor.XXXXXX")"
    mkfifo "$wait_dir/tick"
    exec {monitor_wait_fd}<>"$wait_dir/tick"
    trap 'exec {monitor_wait_fd}>&- 2>/dev/null || true; rm -rf -- "$wait_dir"' RETURN

    while :; do
        uptime_milliseconds
        now="$REPLY"
        ((now < deadline)) || break
        stat_starttime "$root_pid" || {
            printf 'root PID %s exited during monitoring\n' "$root_pid" >&2
            return 1
        }
        [[ "$REPLY" == "$root_start" ]] || {
            printf 'root PID %s was reused during monitoring\n' "$root_pid" >&2
            return 1
        }
        collect_descendants "$root_pid" descendants
        for pid in "${descendants[@]}"; do
            read_process "$pid" || continue
            identity="$boot_id:$pid:$PROCESS_STARTTIME"
            [[ -z "${seen[$identity]+x}" ]] || continue
            seen["$identity"]=1
            write_process_record "$output" "$boot_id" "$pid" "$now"
        done
        read -r -t "$monitor_interval" -u "$monitor_wait_fd" _ || true
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if (($# < 3 || $# > 4)); then
        printf 'usage: %s ROOT_PID DURATION_SECONDS OUTPUT_JSONL [READY_FILE]\n' "$0" >&2
        exit 2
    fi
    monitor_starts "$@"
fi
