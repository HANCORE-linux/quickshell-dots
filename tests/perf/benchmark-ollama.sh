#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sampler="$script_dir/proc-sampler.sh"
start_monitor="$script_dir/proc-start-monitor.sh"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

wait_tick() {
    local duration="${1:-0.001}"
    read -r -t "$duration" -u "$wait_fd" _ || true
}

read_uptime_value() {
    local value _
    read -r value _ < /proc/uptime || return 1
    printf '%s\n' "$value"
}

set_widget_cache_ollama() {
    local input="$1" output="$2" enabled="$3" ws_index ollama_index index tmp
    local -a fields boolean_offsets
    [[ "$enabled" == 0 || "$enabled" == 1 ]] || return 2
    [[ -f "$input" ]] || return 1
    IFS=' ' read -r -a fields < "$input" || return 1
    ((${#fields[@]} >= 5)) || return 1

    for index in 0 1 2 3; do
        [[ "${fields[index]}" == 0 || "${fields[index]}" == 1 ]] || return 1
    done
    if [[ "${fields[4]}" == 0 || "${fields[4]}" == 1 ]]; then
        ws_index=5
    else
        ws_index=4
    fi
    [[ "${fields[ws_index]:-}" == 10 || "${fields[ws_index]:-}" == 5 \
        || "${fields[ws_index]:-}" == active ]] || return 1
    ollama_index=$((ws_index + 32))
    ((${#fields[@]} > ws_index + 33)) || return 1
    [[ "${fields[ws_index + 1]}" == tanzaku || "${fields[ws_index + 1]}" == hearthstone \
        || "${fields[ws_index + 1]}" == carousel ]] || return 1
    [[ "${fields[ws_index + 8]}" == default || "${fields[ws_index + 8]}" == numbers \
        || "${fields[ws_index + 8]}" == magic ]] || return 1
    [[ "${fields[ws_index + 9]}" == top || "${fields[ws_index + 9]}" == bottom ]] || return 1
    [[ "${fields[ws_index + 16]}" == claude || "${fields[ws_index + 16]}" == codex \
        || "${fields[ws_index + 16]}" == opencode ]] || return 1
    [[ "${fields[ws_index + 18]}" == text || "${fields[ws_index + 18]}" == icon ]] || return 1
    boolean_offsets=(2 3 4 5 6 7 10 11 12 13 14 15 17 21 22 23 24 25 26 27 28 29 30 31 32 33)
    for index in "${boolean_offsets[@]}"; do
        [[ "${fields[ws_index + index]}" == 0 || "${fields[ws_index + index]}" == 1 ]] || return 1
    done

    fields[ollama_index]="$enabled"
    tmp="$output.tmp.$$"
    : > "$tmp"
    for index in "${!fields[@]}"; do
        ((index == 0)) || printf ' ' >> "$tmp"
        printf '%s' "${fields[index]}" >> "$tmp"
    done
    printf '\n' >> "$tmp"
    mv -f -- "$tmp" "$output"
}

archive_source() {
    local repo_root="$1" sha="$2" destination="$3"
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 2
    [[ ! -e "$destination" ]] || return 1
    mkdir -p "$destination/source"
    git -C "$repo_root" archive --format=tar -o "$destination/source.tar" "$sha"
    tar -xf "$destination/source.tar" -C "$destination/source"
    chmod 0444 "$destination/source.tar"
    chmod -R a-w "$destination/source"
}

uptime_milliseconds() {
    local value seconds fraction ignored
    read -r value ignored < /proc/uptime || return 1
    seconds="${value%%.*}"
    fraction="${value#*.}000"
    fraction="${fraction:0:3}"
    REPLY=$((10#$seconds * 1000 + 10#$fraction))
}

process_starttime() {
    local pid="$1" line rest
    local -a fields
    [[ -r "/proc/$pid/stat" ]] || return 1
    IFS= read -r line < "/proc/$pid/stat" || return 1
    rest="${line##*) }"
    [[ "$rest" != "$line" ]] || return 1
    read -r -a fields <<< "$rest"
    ((${#fields[@]} > 19)) || return 1
    [[ "${fields[19]}" =~ ^[0-9]+$ ]] || return 1
    REPLY="${fields[19]}"
}

identity_alive() {
    local pid="$1" starttime="$2"
    process_starttime "$pid" && [[ "$REPLY" == "$starttime" ]]
}

read_cmdline() {
    local pid="$1" output_name="$2" arg
    local -n output="$output_name"
    output=()
    [[ -r "/proc/$pid/cmdline" ]] || return 1
    { while IFS= read -r -d '' arg; do
        output+=("$arg")
    done < "/proc/$pid/cmdline"; } 2>/dev/null || true
    ((${#output[@]}))
}

argv_is_bar() {
    local argv_name="$1" index value
    local -n argv_ref="$argv_name"
    local executable="${argv_ref[0]##*/}"
    [[ "$executable" == qs || "$executable" == quickshell ]] || return 1
    for ((index = 1; index < ${#argv_ref[@]}; index++)); do
        value="${argv_ref[index]}"
        case "$value" in
            -c|--config)
                ((index + 1 < ${#argv_ref[@]})) || return 1
                [[ "${argv_ref[index + 1]}" == bar ]] && return 0
                ((index++))
                ;;
            --config=bar)
                return 0
                ;;
            -p|--path)
                ((index + 1 < ${#argv_ref[@]})) || return 1
                [[ "${argv_ref[index + 1]}" == *'/quickshell/bar' \
                    || "${argv_ref[index + 1]}" == *'/quickshell/bar/'* ]] && return 0
                ((index++))
                ;;
            --path=*'/quickshell/bar'|--path=*'/quickshell/bar/'*)
                return 0
                ;;
        esac
    done
    return 1
}

capture_active_bar() {
    local output="$1" path pid start config_arg index
    local -a argv candidates=()

    for path in /proc/[0-9]*/cmdline; do
        pid="${path#/proc/}"
        pid="${pid%/cmdline}"
        read_cmdline "$pid" argv || continue
        argv_is_bar argv || continue
        process_starttime "$pid" || continue
        candidates+=("$pid:$REPLY")
    done
    ((${#candidates[@]} == 1)) || {
        printf 'expected exactly one active Quickshell bar, found %d\n' \
            "${#candidates[@]}" >&2
        return 1
    }

    ACTIVE_BAR_PID="${candidates[0]%%:*}"
    ACTIVE_BAR_STARTTIME="${candidates[0]#*:}"
    read_cmdline "$ACTIVE_BAR_PID" ACTIVE_BAR_ARGV || return 1
    identity_alive "$ACTIVE_BAR_PID" "$ACTIVE_BAR_STARTTIME" || return 1
    config_arg=""
    for ((index = 1; index < ${#ACTIVE_BAR_ARGV[@]}; index++)); do
        case "${ACTIVE_BAR_ARGV[index]}" in
            -c|--config|-p|--path)
                config_arg="${ACTIVE_BAR_ARGV[index + 1]:-}"
                break
                ;;
            --config=*|--path=*)
                config_arg="${ACTIVE_BAR_ARGV[index]#*=}"
                break
                ;;
        esac
    done
    cp -- "/proc/$ACTIVE_BAR_PID/cmdline" "$output/active-bar.argv.nul"
    identity_alive "$ACTIVE_BAR_PID" "$ACTIVE_BAR_STARTTIME" || return 1
    printf '%s\0' "${ACTIVE_BAR_ARGV[@]}" | jq -Rs \
        --argjson pid "$ACTIVE_BAR_PID" --arg starttime "$ACTIVE_BAR_STARTTIME" \
        --arg config "$config_arg" \
        '{pid: $pid, starttime: $starttime, config: $config,
          argv: (split("\u0000")[:-1])}' > "$output/active-bar.json"
}

argv_equal() {
    local left_name="$1" right_name="$2" index
    local -n left="$left_name" right="$right_name"
    ((${#left[@]} == ${#right[@]})) || return 1
    for index in "${!left[@]}"; do
        [[ "${left[index]}" == "${right[index]}" ]] || return 1
    done
}

find_matching_bar() {
    local path pid
    local -a candidate_argv
    for path in /proc/[0-9]*/cmdline; do
        pid="${path#/proc/}"
        pid="${pid%/cmdline}"
        read_cmdline "$pid" candidate_argv || continue
        argv_equal ACTIVE_BAR_ARGV candidate_argv || continue
        process_starttime "$pid" || continue
        REPLY="$pid:$REPLY"
        return 0
    done
    return 1
}

wait_identity_gone() {
    local pid="$1" starttime="$2" timeout="$3" deadline
    uptime_milliseconds
    deadline=$((REPLY + timeout * 1000))
    while identity_alive "$pid" "$starttime"; do
        uptime_milliseconds
        ((REPLY < deadline)) || return 1
        wait_tick 0.02
    done
}

stop_identity() {
    local pid="$1" starttime="$2"
    identity_alive "$pid" "$starttime" || return 0
    kill -TERM "$pid" || return 1
    if ! wait_identity_gone "$pid" "$starttime" 10; then
        identity_alive "$pid" "$starttime" || return 0
        kill -KILL "$pid" || return 1
        wait_identity_gone "$pid" "$starttime" 5 || return 1
    fi
}

descendant_pull_active() {
    local root="$1" index=0 pid child_file children child arg executable
    local -a queue=("$root") argv
    local -A visited=(["$root"]=1)
    while ((index < ${#queue[@]})); do
        pid="${queue[index++]}"
        read_cmdline "$pid" argv || argv=()
        if ((${#argv[@]})); then
            executable="${argv[0]##*/}"
            if [[ "$executable" == curl ]]; then
                for arg in "${argv[@]:1}"; do
                    [[ "$arg" == http://*/api/pull || "$arg" == https://*/api/pull ]] && return 0
                done
            fi
        fi
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
            done
        done
    done
    return 1
}

stop_run_bar() {
    if [[ -n "${RUN_BAR_PID:-}" && -n "${RUN_BAR_STARTTIME:-}" ]]; then
        stop_identity "$RUN_BAR_PID" "$RUN_BAR_STARTTIME" || true
    fi
    RUN_BAR_PID=""
    RUN_BAR_STARTTIME=""
}

restore_environment() {
    local deadline restored=0 candidate="" stable_candidate="" stable_since=0 now
    ((RUN_RESTORED == 0)) || return 0
    stop_run_bar
    if ((RUN_CACHE_EXISTED)); then
        cp -p -- "$RUN_CACHE_BACKUP" "$RUN_CACHE_PATH"
    else
        rm -f -- "$RUN_CACHE_PATH"
    fi

    if ((RUN_ACTIVE_STOPPED)); then
        if identity_alive "$ACTIVE_BAR_PID" "$ACTIVE_BAR_STARTTIME"; then
            restored=1
        else
            "${ACTIVE_BAR_ARGV[@]}" > /dev/null 2>&1 < /dev/null &
            uptime_milliseconds
            deadline=$((REPLY + 15000))
            while :; do
                if find_matching_bar; then
                    candidate="$REPLY"
                    if qs ipc --pid "${candidate%%:*}" show >/dev/null 2>&1; then
                        uptime_milliseconds
                        now="$REPLY"
                        if [[ "$candidate" != "$stable_candidate" ]]; then
                            stable_candidate="$candidate"
                            stable_since="$now"
                        elif ((now - stable_since >= 250)); then
                            printf 'restored active bar as %s\n' "$candidate" \
                                >> "$RUN_OUTPUT/restoration.log"
                            restored=1
                            break
                        fi
                    else
                        stable_candidate=""
                        stable_since=0
                    fi
                else
                    stable_candidate=""
                    stable_since=0
                fi
                uptime_milliseconds
                ((REPLY < deadline)) || break
                wait_tick 0.05
            done
        fi
        ((restored)) || {
            printf 'failed to verify active bar restoration\n' >> "$RUN_OUTPUT/restoration.log"
            return 1
        }
    fi
    RUN_RESTORED=1
}

cleanup_run() {
    local status="$1"
    trap - EXIT INT TERM
    if ! restore_environment; then
        ((status != 0)) || status=1
    fi
    exit "$status"
}

wait_seconds_for_identity() {
    local seconds="$1" pid="$2" starttime="$3" deadline remaining timeout
    uptime_milliseconds
    deadline=$((REPLY + seconds * 1000))
    while :; do
        identity_alive "$pid" "$starttime" || return 1
        uptime_milliseconds
        remaining=$((deadline - REPLY))
        ((remaining > 0)) || return 0
        timeout=0.25
        ((remaining < 250)) && printf -v timeout '0.%03d' "$remaining"
        wait_tick "$timeout"
    done
}

wait_for_instance() {
    local pid="$1" starttime="$2" log="$3" deadline
    uptime_milliseconds
    deadline=$((REPLY + 15000))
    while identity_alive "$pid" "$starttime"; do
        if qs ipc --pid "$pid" show >> "$log" 2>&1; then
            return 0
        fi
        uptime_milliseconds
        ((REPLY < deadline)) || return 1
        wait_tick 0.05
    done
    return 1
}

wait_for_file_identity() {
    local file="$1" pid="$2" starttime="$3" timeout="$4" deadline
    uptime_milliseconds
    deadline=$((REPLY + timeout * 1000))
    while [[ ! -e "$file" ]]; do
        identity_alive "$pid" "$starttime" || return 1
        uptime_milliseconds
        ((REPLY < deadline)) || return 1
        wait_tick 0.001
    done
}

start_source_bar() {
    local source="$1" log="$2"
    qs --no-color --log-times -p "$source/versions/V1/shell.qml" > "$log" 2>&1 &
    RUN_BAR_PID=$!
    process_starttime "$RUN_BAR_PID" || return 1
    RUN_BAR_STARTTIME="$REPLY"
    wait_for_instance "$RUN_BAR_PID" "$RUN_BAR_STARTTIME" "$log"
}

set_scenario_state() {
    local state="$1" log="$2"
    case "$state" in
        absent)
            return 0
            ;;
        closed)
            qs ipc --pid "$RUN_BAR_PID" call ollama close >> "$log" 2>&1
            ;;
        open)
            qs ipc --pid "$RUN_BAR_PID" call ollama open >> "$log" 2>&1
            ;;
        *)
            return 2
            ;;
    esac
    qs ipc --pid "$RUN_BAR_PID" show >> "$log" 2>&1
}

calibrate_start_monitor() {
    local directory="$1" commands="$directory/commands" ready="$directory/ready"
    local starts="$directory/starts.jsonl" root_pid root_start monitor_pid monitor_start
    local duration observed observed_5ms observed_20ms valid ready_ok=false
    mkdir -p "$directory"
    mkfifo "$commands" "$directory/wait"
    exec {calibration_command_fd}<>"$commands"
    exec {calibration_wait_fd}<>"$directory/wait"
    bash -c '
        while IFS= read -r duration <&"$1"; do
            [[ "$duration" == stop ]] && break
            bash -c '\''read -r -t "$1" -u "$2" _ || :'\'' _ "$duration" "$2" &
        done
        wait
    ' _ "$calibration_command_fd" "$calibration_wait_fd" &
    root_pid=$!
    if process_starttime "$root_pid"; then
        root_start="$REPLY"
        PROC_MONITOR_INTERVAL=0.001 "$start_monitor" "$root_pid" 1 "$starts" "$ready" &
        monitor_pid=$!
        if process_starttime "$monitor_pid"; then
            monitor_start="$REPLY"
            if wait_for_file_identity "$ready" "$monitor_pid" "$monitor_start" 2 \
                    && identity_alive "$root_pid" "$root_start"; then
                ready_ok=true
            fi
        fi
    fi
    if [[ "$ready_ok" == true ]]; then
        for duration in 0.005 0.005 0.005 0.020 0.020 0.020; do
            printf '%s\n' "$duration" >&"$calibration_command_fd"
            if [[ "$duration" == 0.005 ]]; then
                wait_tick 0.010
            else
                wait_tick 0.025
            fi
        done
        wait "$monitor_pid" || true
    elif [[ -n "${monitor_pid:-}" ]]; then
        kill "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true
    fi
    printf '%s\n' stop >&"$calibration_command_fd" 2>/dev/null || true
    wait "$root_pid" || true
    exec {calibration_command_fd}>&-
    exec {calibration_wait_fd}>&-
    observed="$(jq -s 'length' "$starts" 2>/dev/null || printf 0)"
    observed_5ms="$(jq -s '[.[] | select(.argv[4] == "0.005")] | length' \
        "$starts" 2>/dev/null || printf 0)"
    observed_20ms="$(jq -s '[.[] | select(.argv[4] == "0.020")] | length' \
        "$starts" 2>/dev/null || printf 0)"
    valid=false
    [[ "$observed_5ms" == 3 && "$observed_20ms" == 3 ]] && jq -e -s \
        '([.[].identity] | unique | length) == 6' "$starts" >/dev/null && valid=true
    jq -n --argjson expected_5ms 3 --argjson expected_20ms 3 \
        --argjson observed_5ms "$observed_5ms" --argjson observed_20ms "$observed_20ms" \
        --argjson observed "$observed" --argjson valid "$valid" \
        '{expected_5ms: $expected_5ms, expected_20ms: $expected_20ms,
          observed_5ms: $observed_5ms, observed_20ms: $observed_20ms,
          expected: ($expected_5ms + $expected_20ms), observed: $observed, valid: $valid}' \
        > "$directory/result.json"
    [[ "$valid" == true ]]
}

run_qsg_diagnostic() {
    local source="$1" state="$2" directory="$3" seconds="$4"
    local timing_count status
    mkdir -p "$directory"
    QSG_RENDER_TIMING=1 QSG_INFO=1 \
    QT_LOGGING_RULES='qt.scenegraph.time.*=true' \
        qs --no-color --log-times -p "$source/versions/V1/shell.qml" \
        > "$directory/qsg.log" 2>&1 &
    RUN_BAR_PID=$!
    process_starttime "$RUN_BAR_PID" || return 1
    RUN_BAR_STARTTIME="$REPLY"
    if wait_for_instance "$RUN_BAR_PID" "$RUN_BAR_STARTTIME" "$directory/qsg.log"; then
        set_scenario_state "$state" "$directory/qsg-ipc.log" || true
        wait_seconds_for_identity "$seconds" "$RUN_BAR_PID" "$RUN_BAR_STARTTIME" || true
    fi
    stop_run_bar
    grep -Ei 'qt[.]scenegraph[.]time|render[^ ]* timing|frame[^ ]* [0-9.]+ ?ms' \
        "$directory/qsg.log" > "$directory/qsg-timing-lines.log" || true
    timing_count="$(grep -c . "$directory/qsg-timing-lines.log" || true)"
    status=unavailable
    ((timing_count > 0)) && status=available
    jq -n --arg status "$status" --argjson timing_count "$timing_count" \
        --arg raw_log "qsg/qsg.log" \
        '{status: $status,
          timing_line_count: (if $status == "available" then $timing_count else null end),
          raw_log: $raw_log}' > "$directory/result.json"
}

run_scenario() {
    local name="$1" source_name="$2" source="$3" enabled="$4" state="$5" duration="$6"
    local directory="$RUN_OUTPUT/scenarios/$name" valid=true pss_json qsg_json calibration_json
    local sampler_pid monitor_pid monitor_start monitor_ready=false
    local -a invalid_reasons=()
    mkdir -p "$directory"
    set_widget_cache_ollama "$RUN_CACHE_BACKUP" "$RUN_CACHE_PATH" "$enabled" || \
        die "failed to prepare widget cache for $name"

    if ! calibrate_start_monitor "$directory/calibration"; then
        valid=false
        invalid_reasons+=("start monitor calibration mismatch")
    fi
    if ! start_source_bar "$source" "$directory/quickshell.log"; then
        valid=false
        invalid_reasons+=("Quickshell did not become ready")
    else
        if ! set_scenario_state "$state" "$directory/ipc.log"; then
            valid=false
            invalid_reasons+=("requested IPC state was not accepted")
        fi
        if descendant_pull_active "$RUN_BAR_PID"; then
            valid=false
            invalid_reasons+=("Ollama pull was active before warm-up")
        fi
        if ! wait_seconds_for_identity "$RUN_WARMUP_SECONDS" "$RUN_BAR_PID" "$RUN_BAR_STARTTIME"; then
            valid=false
            invalid_reasons+=("Quickshell exited during warm-up")
        elif descendant_pull_active "$RUN_BAR_PID"; then
            valid=false
            invalid_reasons+=("Ollama pull was active before sampling")
        else
            "$start_monitor" "$RUN_BAR_PID" "$duration" "$directory/starts.jsonl" \
                "$directory/start-monitor.ready" &
            monitor_pid=$!
            if ! process_starttime "$monitor_pid"; then
                valid=false
                invalid_reasons+=("process-start monitor did not launch")
            else
                monitor_start="$REPLY"
                if wait_for_file_identity "$directory/start-monitor.ready" \
                        "$monitor_pid" "$monitor_start" 2; then
                    monitor_ready=true
                else
                    valid=false
                    invalid_reasons+=("process-start monitor did not become ready")
                fi
            fi
            if [[ "$monitor_ready" == true ]]; then
                "$sampler" "$RUN_BAR_PID" "$duration" "$directory/cpu-samples.jsonl" \
                    "$directory/pss.json" &
                sampler_pid=$!
                if ! wait "$sampler_pid"; then
                    valid=false
                    invalid_reasons+=("CPU/PSS sampler failed")
                fi
                if ! wait "$monitor_pid"; then
                    valid=false
                    invalid_reasons+=("process-start monitor failed")
                fi
                if jq -e 'select(.attribution == "curl" and
                        (.endpoint | test("/api/pull$")))' \
                        "$directory/starts.jsonl" >/dev/null 2>&1; then
                    valid=false
                    invalid_reasons+=("Ollama pull started during sampling")
                fi
                if [[ "$(wc -l < "$directory/cpu-samples.jsonl" 2>/dev/null || printf 0)" != "$duration" ]]; then
                    valid=false
                    invalid_reasons+=("CPU sample count mismatch")
                fi
            else
                kill "$monitor_pid" 2>/dev/null || true
                wait "$monitor_pid" 2>/dev/null || true
            fi
        fi
    fi
    stop_run_bar

    run_qsg_diagnostic "$source" "$state" "$directory/qsg" "$RUN_QSG_SECONDS" || {
        mkdir -p "$directory/qsg"
        printf '%s\n' '{"status":"unavailable","timing_line_count":null,"raw_log":"qsg/qsg.log"}' \
            > "$directory/qsg/result.json"
    }
    [[ -f "$directory/cpu-samples.jsonl" ]] || : > "$directory/cpu-samples.jsonl"
    [[ -f "$directory/starts.jsonl" ]] || : > "$directory/starts.jsonl"
    pss_json=null
    [[ -f "$directory/pss.json" ]] && pss_json="$(<"$directory/pss.json")"
    qsg_json="$(<"$directory/qsg/result.json")"
    calibration_json="$(<"$directory/calibration/result.json")"
    printf '%s\n' "${invalid_reasons[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))' \
        > "$directory/invalid-reasons.json"
    jq -n --arg name "$name" --arg source "$source_name" --arg state "$state" \
        --argjson duration "$duration" --argjson valid "$valid" \
        --slurpfile samples "$directory/cpu-samples.jsonl" \
        --slurpfile starts "$directory/starts.jsonl" \
        --slurpfile reasons "$directory/invalid-reasons.json" \
        --argjson pss "$pss_json" --argjson qsg "$qsg_json" \
        --argjson calibration "$calibration_json" \
        '{name: $name, source: $source, requested_state: $state,
          duration_seconds: $duration, valid: $valid, invalid_reasons: $reasons[0],
          samples: $samples, pss: $pss, starts: $starts,
          calibration: $calibration, qsg: $qsg}' > "$directory/result.json"
}

write_manifest() {
    local restoration="$1"
    jq -n --arg main_ref "$RUN_MAIN_REF" --arg main_sha "$RUN_MAIN_SHA" \
        --arg pr_ref "$RUN_PR_REF" --arg pr_sha "$RUN_PR_SHA" \
        --arg output "$RUN_OUTPUT" --arg created "$RUN_CREATED" \
        --arg boot_id "$RUN_BOOT_ID" --arg kernel "$RUN_KERNEL" \
        --arg restoration "$restoration" --argjson duration "$RUN_BASE_DURATION" \
        --argjson warmup "$RUN_WARMUP_SECONDS" --argjson qsg_seconds "$RUN_QSG_SECONDS" \
        --argjson active_bar_pid "$ACTIVE_BAR_PID" --arg active_bar_starttime "$ACTIVE_BAR_STARTTIME" \
        '{schema_version: 1, created_utc: $created, output: $output,
          refs: {main: {input: $main_ref, sha: $main_sha}, pr: {input: $pr_ref, sha: $pr_sha}},
          timing: {base_scenario_seconds: $duration, open_scenario_seconds: (($duration + 1) / 2 | floor),
                   warmup_seconds: $warmup, qsg_diagnostic_seconds: $qsg_seconds},
          monitor: {identity: "boot_id:pid:starttime", poll_seconds: 0.002,
                    calibration_poll_seconds: 0.001, calibration_children: {"5ms": 3, "20ms": 3}},
          host: {boot_id: $boot_id, kernel: $kernel},
          active_bar: {pid: $active_bar_pid, starttime: $active_bar_starttime},
          restoration_status: $restoration}' > "$RUN_OUTPUT/manifest.json.tmp"
    mv -f -- "$RUN_OUTPUT/manifest.json.tmp" "$RUN_OUTPUT/manifest.json"
}

write_checksums() {
    local file
    (
        cd "$RUN_OUTPUT"
        shopt -s globstar nullglob
        for file in **/*; do
            [[ -f "$file" && "$file" != checksums.sha256 ]] || continue
            sha256sum -- "$file"
        done | LC_ALL=C sort
    ) > "$RUN_OUTPUT/checksums.sha256"
}

run_benchmark() {
    local repo_root parent output_arg open_duration
    (($# == 3 || $# == 4)) || \
        die "usage: $0 run MAIN_REF PR_REF OUTPUT_DIR [BASE_DURATION_SECONDS]"
    RUN_MAIN_REF="$1"
    RUN_PR_REF="$2"
    output_arg="$3"
    RUN_BASE_DURATION="${4:-120}"
    [[ "$RUN_BASE_DURATION" =~ ^[1-9][0-9]*$ ]] || die "duration must be a positive integer"
    RUN_WARMUP_SECONDS="${OLLAMA_PERF_WARMUP_SECONDS:-30}"
    RUN_QSG_SECONDS="${OLLAMA_PERF_QSG_SECONDS:-15}"
    [[ "$RUN_WARMUP_SECONDS" =~ ^[0-9]+$ ]] || die "warm-up must be a non-negative integer"
    [[ "$RUN_QSG_SECONDS" =~ ^[1-9][0-9]*$ ]] || die "QSG duration must be a positive integer"
    for tool in bash git jq sha256sum getconf mkfifo tar qs awk grep wc uname date; do
        command -v "$tool" >/dev/null || die "required tool is unavailable: $tool"
    done
    [[ -r /proc/uptime && -r /proc/sys/kernel/random/boot_id ]] || die "Linux procfs is required"
    repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
    RUN_MAIN_SHA="$(git -C "$repo_root" rev-parse --verify "$RUN_MAIN_REF^{commit}")" || \
        die "cannot resolve main ref: $RUN_MAIN_REF"
    RUN_PR_SHA="$(git -C "$repo_root" rev-parse --verify "$RUN_PR_REF^{commit}")" || \
        die "cannot resolve PR ref: $RUN_PR_REF"
    [[ "$RUN_MAIN_SHA" != "$RUN_PR_SHA" ]] || die "main and PR refs resolve to the same commit"
    parent="$(dirname "$output_arg")"
    [[ -d "$parent" ]] || die "output parent does not exist: $parent"
    mkdir "$output_arg" || die "output directory must not already exist"
    RUN_OUTPUT="$(cd "$output_arg" && pwd -P)"
    mkdir -p "$RUN_OUTPUT/sources" "$RUN_OUTPUT/scenarios" "$RUN_OUTPUT/safety"
    RUN_CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    IFS= read -r RUN_BOOT_ID < /proc/sys/kernel/random/boot_id
    RUN_KERNEL="$(uname -srmo)"
    mkfifo "$RUN_OUTPUT/safety/wait"
    exec {wait_fd}<>"$RUN_OUTPUT/safety/wait"
    source "$sampler"

    archive_source "$repo_root" "$RUN_MAIN_SHA" "$RUN_OUTPUT/sources/main"
    archive_source "$repo_root" "$RUN_PR_SHA" "$RUN_OUTPUT/sources/pr"
    [[ -f "$RUN_OUTPUT/sources/main/source/versions/V1/shell.qml" ]] || die "main archive lacks V1 shell"
    [[ -f "$RUN_OUTPUT/sources/pr/source/versions/V1/shell.qml" ]] || die "PR archive lacks V1 shell"

    capture_active_bar "$RUN_OUTPUT/safety"
    descendant_pull_active "$ACTIVE_BAR_PID" && die "an Ollama pull is active on the current bar"
    RUN_CACHE_PATH="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell_widgets"
    RUN_CACHE_BACKUP="$RUN_OUTPUT/safety/quickshell_widgets.original"
    RUN_CACHE_EXISTED=0
    if [[ -f "$RUN_CACHE_PATH" ]]; then
        set_widget_cache_ollama "$RUN_CACHE_PATH" "$RUN_OUTPUT/safety/cache-schema-check" 0 || \
            die "widget cache schema is not recognized; refusing to mutate it"
        rm -f "$RUN_OUTPUT/safety/cache-schema-check"
        cp -p -- "$RUN_CACHE_PATH" "$RUN_CACHE_BACKUP"
        RUN_CACHE_EXISTED=1
    else
        die "widget cache does not exist; refusing to invent a schema"
    fi

    RUN_BAR_PID=""
    RUN_BAR_STARTTIME=""
    RUN_ACTIVE_STOPPED=0
    RUN_RESTORED=0
    trap 'cleanup_run $?' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    write_manifest pending
    RUN_ACTIVE_STOPPED=1
    stop_identity "$ACTIVE_BAR_PID" "$ACTIVE_BAR_STARTTIME" || die "failed to stop active bar safely"

    open_duration=$(((RUN_BASE_DURATION + 1) / 2))
    run_scenario 01-main main "$RUN_OUTPUT/sources/main/source" 0 absent "$RUN_BASE_DURATION"
    run_scenario 02-pr-disabled pr "$RUN_OUTPUT/sources/pr/source" 0 closed "$RUN_BASE_DURATION"
    run_scenario 03-pr-enabled-closed pr "$RUN_OUTPUT/sources/pr/source" 1 closed "$RUN_BASE_DURATION"
    run_scenario 04-pr-enabled-open pr "$RUN_OUTPUT/sources/pr/source" 1 open "$open_duration"

    jq -n --slurpfile manifest "$RUN_OUTPUT/manifest.json" \
        --slurpfile s1 "$RUN_OUTPUT/scenarios/01-main/result.json" \
        --slurpfile s2 "$RUN_OUTPUT/scenarios/02-pr-disabled/result.json" \
        --slurpfile s3 "$RUN_OUTPUT/scenarios/03-pr-enabled-closed/result.json" \
        --slurpfile s4 "$RUN_OUTPUT/scenarios/04-pr-enabled-open/result.json" \
        '{manifest: $manifest[0], scenarios: [$s1[0], $s2[0], $s3[0], $s4[0]]}' \
        > "$RUN_OUTPUT/results.json"
    jq -f "$script_dir/summarize-ollama.jq" "$RUN_OUTPUT/results.json" > "$RUN_OUTPUT/summary.json"
    restore_environment || die "active bar restoration failed"
    write_manifest restored
    jq --slurpfile manifest "$RUN_OUTPUT/manifest.json" '.manifest = $manifest[0]' \
        "$RUN_OUTPUT/results.json" > "$RUN_OUTPUT/results.json.tmp"
    mv -f "$RUN_OUTPUT/results.json.tmp" "$RUN_OUTPUT/results.json"
    jq -f "$script_dir/summarize-ollama.jq" "$RUN_OUTPUT/results.json" > "$RUN_OUTPUT/summary.json"
    write_checksums
    printf 'artifacts: %s\n' "$RUN_OUTPUT"
}

bar_identities() {
    local path pid argv0 arg stat_line rest
    local -a argv

    for path in /proc/[0-9]*/cmdline; do
        pid="${path#/proc/}"
        pid="${pid%/cmdline}"
        argv=()
        if [[ -r "$path" ]]; then
            { while IFS= read -r -d '' arg; do
                argv+=("$arg")
            done < "$path"; } 2>/dev/null || true
        fi
        ((${#argv[@]})) || continue
        argv0="${argv[0]##*/}"
        [[ "$argv0" == qs || "$argv0" == quickshell ]] || continue
        [[ -r "/proc/$pid/stat" ]] || continue
        IFS= read -r stat_line < "/proc/$pid/stat" || continue
        rest="${stat_line##*) }"
        read -r -a fields <<< "$rest"
        ((${#fields[@]} > 19)) || continue
        printf '%s:%s\n' "$pid" "${fields[19]}"
    done | sort
}

self_test_cleanup() {
    local pid
    for pid in "${!self_test_pid_starts[@]}"; do
        if identity_alive "$pid" "${self_test_pid_starts[$pid]}"; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    if [[ -n "${self_test_tmp:-}" ]]; then
        chmod -R u+w -- "$self_test_tmp" 2>/dev/null || true
        rm -rf -- "$self_test_tmp"
    fi
}

self_test_track_pid() {
    local pid="$1"
    process_starttime "$pid" || die "cannot identify self-test child $pid"
    self_test_pid_starts["$pid"]="$REPLY"
}

self_test_wait_for_file() {
    local file="$1" timeout="$2" start now
    start="$(read_uptime_value)"
    while [[ ! -e "$file" ]]; do
        now="$(read_uptime_value)"
        awk -v now="$now" -v start="$start" -v timeout="$timeout" \
            'BEGIN { exit !((now - start) >= timeout) }' && return 1
        wait_tick
    done
}

self_test_stat_parser() {
    local hold_fifo="$self_test_tmp/stat-hold" pid line rest
    local parsed_pid parsed_comm utime stime cutime cstime starttime
    local -a expected

    mkfifo "$hold_fifo"
    exec {hold_fd}<>"$hold_fifo"
    bash -c 'printf %s "stat ) child" > /proc/self/comm; read -r -u "$1" _' \
        _ "$hold_fd" &
    pid=$!
    self_test_track_pid "$pid"

    while :; do
        IFS= read -r line < "/proc/$pid/stat" || die "known stat child exited early"
        [[ "$line" == *'(stat ) child)'* ]] && break
        wait_tick
    done
    rest="${line##*) }"
    read -r -a expected <<< "$rest"
    read_proc_stat "$pid" parsed_pid parsed_comm utime stime cutime cstime starttime

    [[ "$parsed_pid" == "$pid" ]] || die "stat parser returned the wrong PID"
    [[ "$parsed_comm" == 'stat ) child' ]] || die "stat parser split comm at the wrong parenthesis"
    [[ "$utime" == "${expected[11]}" ]] || die "stat field 14 mapping is wrong"
    [[ "$stime" == "${expected[12]}" ]] || die "stat field 15 mapping is wrong"
    [[ "$cutime" == "${expected[13]}" ]] || die "stat field 16 mapping is wrong"
    [[ "$cstime" == "${expected[14]}" ]] || die "stat field 17 mapping is wrong"
    [[ "$starttime" == "${expected[19]}" ]] || die "stat field 22 mapping is wrong"

    kill "$pid"
    wait "$pid" 2>/dev/null || true
    exec {hold_fd}>&-
}

self_test_sampler() {
    local pid samples="$self_test_tmp/samples.jsonl" pss="$self_test_tmp/pss.json"
    local unstable_samples="$self_test_tmp/unstable.jsonl"
    local unstable_pss="$self_test_tmp/unstable-pss.json"

    bash -c 'while :; do :; done' &
    pid=$!
    self_test_track_pid "$pid"
    "$sampler" "$pid" 2 "$samples" "$pss"
    kill "$pid"
    wait "$pid" 2>/dev/null || true

    jq -e -s '
        length == 2 and
        all(.[]; .sample >= 1 and .elapsed_seconds > 0.5 and
                  .cpu_one_core_percent >= 0 and .starttime > 0)
    ' "$samples" >/dev/null || die "sampler did not emit two valid elapsed-time samples"
    jq -e '
        (.before | has("Pss") and has("Pss_Anon") and has("Pss_File") and has("Pss_Shmem")) and
        (.after | has("Pss") and has("Pss_Anon") and has("Pss_File") and has("Pss_Shmem"))
    ' "$pss" >/dev/null || die "sampler omitted a PSS boundary field"

    bash -c 'read -r -t 0.15 -u "$1" _ || :' _ "$wait_fd" &
    pid=$!
    self_test_track_pid "$pid"
    if "$sampler" "$pid" 2 "$unstable_samples" "$unstable_pss" 2>/dev/null; then
        die "sampler accepted a process that exited during the window"
    fi
}

self_test_start_monitor() {
    local commands="$self_test_tmp/calibration-commands"
    local ready="$self_test_tmp/monitor-ready"
    local starts="$self_test_tmp/starts.jsonl"
    local root_pid monitor_pid duration

    bash -c '
        source "$1"
        PROCESS_ARGV=(curl --fail http://127.0.0.1:11434/api/ps)
        attribute_process
        [[ "$PROCESS_ATTRIBUTION" == curl &&
           "$PROCESS_ENDPOINT" == http://127.0.0.1:11434/api/ps ]]
        PROCESS_ARGV=(bash -lc "cat /sys/class/drm/card0/device/gpu_busy_percent")
        attribute_process
        [[ "$PROCESS_ATTRIBUTION" == gpu-detector-bash ]]
        PROCESS_ARGV=(nvidia-smi --query-gpu=index,utilization.gpu)
        attribute_process
        [[ "$PROCESS_ATTRIBUTION" == nvidia-smi ]]
    ' _ "$start_monitor" || die "process-start attribution fixtures failed"

    mkfifo "$commands"
    exec {command_fd}<>"$commands"
    bash -c '
        while IFS= read -r duration <&"$1"; do
            [[ "$duration" == stop ]] && break
            bash -c '\''read -r -t "$1" -u "$2" _ || :'\'' _ "$duration" "$2" &
        done
        wait
    ' _ "$command_fd" "$wait_fd" &
    root_pid=$!
    self_test_track_pid "$root_pid"

    PROC_MONITOR_INTERVAL=0.001 "$start_monitor" "$root_pid" 1 "$starts" "$ready" &
    monitor_pid=$!
    self_test_track_pid "$monitor_pid"
    self_test_wait_for_file "$ready" 2 || die "start monitor did not become ready"

    for duration in 0.005 0.005 0.005 0.020 0.020 0.020; do
        printf '%s\n' "$duration" >&"$command_fd"
        if [[ "$duration" == 0.005 ]]; then
            wait_tick 0.010
        else
            wait_tick 0.025
        fi
    done
    wait "$monitor_pid"
    printf '%s\n' stop >&"$command_fd"
    wait "$root_pid"
    exec {command_fd}>&-

    jq -e -s '
        length == 6 and
        ([.[].identity] | unique | length) == 6 and
        all(.[]; (.identity | test("^[^:]+:[0-9]+:[0-9]+$")) and
                  (.argv | type == "array"))
    ' "$starts" >/dev/null || die "5 ms/20 ms calibration did not observe exactly six unique starts"
}

self_test_orchestration_helpers() {
    local repo_root cache enabled disabled bad archive_root sha
    local -a fields argv=(qs -n -d -c bar)
    repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
    cache="$self_test_tmp/widgets"
    enabled="$self_test_tmp/widgets-enabled"
    disabled="$self_test_tmp/widgets-disabled"
    bad="$self_test_tmp/widgets-bad"
    archive_root="$self_test_tmp/archive"
    argv_is_bar argv || die "bar argv recognition failed"

    printf '%s\n' \
        '1 1 1 0 0 10 tanzaku 0 0 1 0 0 0 default top 1 1 1 1 1 1 opencode 0 text omarchy rebel 1 1 0 0 0 1 1 1 0 0 1 0 0' \
        > "$cache"
    set_widget_cache_ollama "$cache" "$enabled" 1
    read -r -a fields < "$enabled"
    [[ "${fields[37]}" == 1 ]] || die "cache helper did not enable Ollama"
    set_widget_cache_ollama "$enabled" "$disabled" 0
    read -r -a fields < "$disabled"
    [[ "${fields[37]}" == 0 ]] || die "cache helper did not disable Ollama"
    printf '%s\n' 'unrecognized cache data' > "$bad"
    if set_widget_cache_ollama "$bad" "$disabled" 1 2>/dev/null; then
        die "cache helper accepted an unrecognized schema"
    fi

    sha="$(git -C "$repo_root" rev-parse --verify HEAD^{commit})"
    archive_source "$repo_root" "$sha" "$archive_root"
    [[ -f "$archive_root/source/versions/V1/shell.qml" ]] || \
        die "git archive helper omitted shell.qml"
    [[ -f "$archive_root/source.tar" ]] || die "git archive helper did not retain the archive"
    [[ "$(git -C "$repo_root" rev-parse --verify "$sha^{commit}")" == "$sha" ]] || \
        die "archive helper changed the resolved commit"
}

self_test() {
    local before after
    command -v jq >/dev/null || die "self-test requires jq"
    [[ -r /proc/uptime && -r /proc/sys/kernel/random/boot_id ]] || \
        die "self-test requires Linux procfs"
    [[ -r "$sampler" ]] || die "missing $sampler"
    [[ -r "$start_monitor" ]] || die "missing $start_monitor"

    self_test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/ollama-perf-self-test.XXXXXX")"
    mkfifo "$self_test_tmp/wait"
    exec {wait_fd}<>"$self_test_tmp/wait"
    declare -gA self_test_pid_starts=()
    trap self_test_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    before="$(bar_identities)"

    # shellcheck source=proc-sampler.sh
    source "$sampler"
    self_test_stat_parser
    self_test_sampler
    self_test_start_monitor
    self_test_orchestration_helpers

    after="$(bar_identities)"
    [[ "$after" == "$before" ]] || die "active Quickshell process identity changed during self-test"
    printf 'stat parsing: PASS\n'
    printf 'CPU/PSS sampling: PASS\n'
    printf '5ms/20ms start calibration: PASS\n'
    printf 'cache/archive isolation: PASS\n'
    printf 'active bar unchanged: PASS (%s)\n' "${before:-none}"
    printf 'self-test: PASS\n'
}

case "${1:-}" in
    self-test)
        self_test
        ;;
    run)
        shift
        run_benchmark "$@"
        ;;
    *)
        die "usage: $0 self-test | run MAIN_REF PR_REF OUTPUT_DIR [BASE_DURATION_SECONDS]"
        ;;
esac
