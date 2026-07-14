#!/usr/bin/env bash
set -euo pipefail

read_proc_stat() {
    local pid="$1"
    local -n out_pid="$2" out_comm="$3" out_utime="$4" out_stime="$5"
    local -n out_cutime="$6" out_cstime="$7" out_starttime="$8"
    local line body rest suffix
    local -a fields

    IFS= read -r line < "/proc/$pid/stat" || return 1
    [[ "$line" == "$pid ("*') '* ]] || return 1
    rest="${line##*) }"
    [[ "$rest" != "$line" ]] || return 1
    read -r -a fields <<< "$rest"
    ((${#fields[@]} > 19)) || return 1

    out_pid="${line%% *}"
    body="${line#"$out_pid ("}"
    suffix=") $rest"
    out_comm="${body%"$suffix"}"
    out_utime="${fields[11]}"
    out_stime="${fields[12]}"
    out_cutime="${fields[13]}"
    out_cstime="${fields[14]}"
    out_starttime="${fields[19]}"

    [[ "$out_pid" == "$pid" ]] || return 1
    [[ "$out_utime" =~ ^[0-9]+$ && "$out_stime" =~ ^[0-9]+$ ]] || return 1
    [[ "$out_cutime" =~ ^-?[0-9]+$ && "$out_cstime" =~ ^-?[0-9]+$ ]] || return 1
    [[ "$out_starttime" =~ ^[0-9]+$ ]] || return 1
}

read_proc_uptime() {
    local -n out_uptime="$1"
    local ignored
    read -r out_uptime ignored < /proc/uptime || return 1
    [[ "$out_uptime" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

read_proc_pss() {
    local pid="$1"
    local -n out_pss="$2" out_anon="$3" out_file="$4" out_shmem="$5"
    local key value unit
    local have_pss=0 have_anon=0 have_file=0 have_shmem=0

    out_pss=0
    out_anon=0
    out_file=0
    out_shmem=0
    while read -r key value unit; do
        case "$key" in
            Pss:)
                out_pss="$value"
                have_pss=1
                ;;
            Pss_Anon:)
                out_anon="$value"
                have_anon=1
                ;;
            Pss_File:)
                out_file="$value"
                have_file=1
                ;;
            Pss_Shmem:)
                out_shmem="$value"
                have_shmem=1
                ;;
        esac
    done < "/proc/$pid/smaps_rollup" || return 1
    ((have_pss && have_anon && have_file && have_shmem)) || return 1
    [[ "$out_pss" =~ ^[0-9]+$ && "$out_anon" =~ ^[0-9]+$ ]] || return 1
    [[ "$out_file" =~ ^[0-9]+$ && "$out_shmem" =~ ^[0-9]+$ ]] || return 1
}

read_stable_pss() {
    local pid="$1" expected_start="$2"
    local out_pss_name="$3" out_anon_name="$4" out_file_name="$5" out_shmem_name="$6"
    local parsed_pid comm utime stime cutime cstime starttime
    read_proc_stat "$pid" parsed_pid comm utime stime cutime cstime starttime || return 1
    [[ "$starttime" == "$expected_start" ]] || return 1
    read_proc_pss "$pid" "$out_pss_name" "$out_anon_name" "$out_file_name" \
        "$out_shmem_name" || return 1
    read_proc_stat "$pid" parsed_pid comm utime stime cutime cstime starttime || return 1
    [[ "$starttime" == "$expected_start" ]]
}

write_marker() {
    local path="$1" value="$2" tmp
    tmp="$path.tmp.$$"
    printf '%s\n' "$value" > "$tmp"
    mv -f -- "$tmp" "$path"
}

write_pss_boundaries() {
    local output="$1"
    local before_pss="$2" before_anon="$3" before_file="$4" before_shmem="$5"
    local after_pss="$6" after_anon="$7" after_file="$8" after_shmem="$9"
    local tmp="$output.tmp.$$"

    printf '{"unit":"kB","before":{"Pss":%s,"Pss_Anon":%s,"Pss_File":%s,"Pss_Shmem":%s},' \
        "$before_pss" "$before_anon" "$before_file" "$before_shmem" > "$tmp"
    printf '"after":{"Pss":%s,"Pss_Anon":%s,"Pss_File":%s,"Pss_Shmem":%s}}\n' \
        "$after_pss" "$after_anon" "$after_file" "$after_shmem" >> "$tmp"
    mv -f -- "$tmp" "$output"
}

sample_proc() {
    local pid="$1" sample_count="$2" output="$3" pss_output="$4"
    local start_marker="$5" stop_marker="$6"
    local clock_tick wait_dir wait_fifo sample_wait_fd
    local parsed_pid comm utime stime cutime cstime starttime stable_starttime
    local next_pid next_comm next_utime next_stime next_cutime next_cstime next_starttime
    local uptime next_uptime total next_total delta elapsed cpu sample boundary_jiffies
    local own next_own own_delta own_cpu child next_child child_delta child_cpu
    local before_pss before_anon before_file before_shmem
    local after_pss after_anon after_file after_shmem

    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || {
        printf 'invalid PID: %s\n' "$pid" >&2
        return 2
    }
    [[ "$sample_count" =~ ^[1-9][0-9]*$ ]] || {
        printf 'sample count must be a positive integer\n' >&2
        return 2
    }
    clock_tick="$(getconf CLK_TCK)"
    [[ "$clock_tick" =~ ^[1-9][0-9]*$ ]] || return 1

    : > "$output"
    read_proc_stat "$pid" parsed_pid comm utime stime cutime cstime starttime || {
        printf 'cannot read initial stat for PID %s\n' "$pid" >&2
        return 1
    }
    stable_starttime="$starttime"
    read_stable_pss "$pid" "$stable_starttime" before_pss before_anon before_file before_shmem || {
        printf 'cannot read initial smaps_rollup for PID %s\n' "$pid" >&2
        return 1
    }
    read_proc_stat "$pid" parsed_pid comm utime stime cutime cstime starttime || return 1
    [[ "$starttime" == "$stable_starttime" ]] || return 1
    read_proc_uptime uptime
    boundary_jiffies="$(awk -v uptime="$uptime" -v hz="$clock_tick" \
        'BEGIN { printf "%d", uptime * hz }')"
    write_marker "$start_marker" "$boundary_jiffies"
    own=$((utime + stime))
    child=$((cutime + cstime))
    total=$((utime + stime + cutime + cstime))

    wait_dir="$(mktemp -d "${TMPDIR:-/tmp}/proc-sampler.XXXXXX")"
    wait_fifo="$wait_dir/tick"
    mkfifo "$wait_fifo"
    exec {sample_wait_fd}<>"$wait_fifo"
    trap 'exec {sample_wait_fd}>&- 2>/dev/null || true; rm -rf -- "$wait_dir"' RETURN

    for ((sample = 1; sample <= sample_count; sample++)); do
        read -r -t 1 -u "$sample_wait_fd" _ || true
        read_proc_stat "$pid" next_pid next_comm next_utime next_stime \
            next_cutime next_cstime next_starttime || {
            printf 'PID %s disappeared during sample %s\n' "$pid" "$sample" >&2
            return 1
        }
        [[ "$next_starttime" == "$stable_starttime" ]] || {
            printf 'PID %s was reused during sample %s\n' "$pid" "$sample" >&2
            return 1
        }
        read_proc_uptime next_uptime
        next_own=$((next_utime + next_stime))
        next_child=$((next_cutime + next_cstime))
        next_total=$((next_utime + next_stime + next_cutime + next_cstime))
        own_delta=$((next_own - own))
        child_delta=$((next_child - child))
        delta=$((next_total - total))
        ((own_delta >= 0 && child_delta >= 0 && delta >= 0)) || {
            printf 'CPU jiffies moved backwards for PID %s\n' "$pid" >&2
            return 1
        }
        elapsed="$(awk -v current="$next_uptime" -v previous="$uptime" \
            'BEGIN { printf "%.6f", current - previous }')"
        awk -v elapsed="$elapsed" 'BEGIN { exit !(elapsed > 0) }' || {
            printf 'non-positive elapsed time for PID %s\n' "$pid" >&2
            return 1
        }
        cpu="$(awk -v delta="$delta" -v hz="$clock_tick" -v elapsed="$elapsed" \
            'BEGIN { printf "%.6f", 100 * delta / (hz * elapsed) }')"
        own_cpu="$(awk -v delta="$own_delta" -v hz="$clock_tick" -v elapsed="$elapsed" \
            'BEGIN { printf "%.6f", 100 * delta / (hz * elapsed) }')"
        child_cpu="$(awk -v delta="$child_delta" -v hz="$clock_tick" -v elapsed="$elapsed" \
            'BEGIN { printf "%.6f", 100 * delta / (hz * elapsed) }')"
        printf '{"sample":%d,"pid":%d,"starttime":%s,"elapsed_seconds":%s,' \
            "$sample" "$pid" "$stable_starttime" "$elapsed" >> "$output"
        printf '"own_delta_jiffies":%d,"child_delta_jiffies":%d,"delta_jiffies":%d,' \
            "$own_delta" "$child_delta" "$delta" >> "$output"
        printf '"own_cpu_one_core_percent":%s,"child_cpu_one_core_percent":%s,' \
            "$own_cpu" "$child_cpu" >> "$output"
        printf '"cpu_one_core_percent":%s}\n' "$cpu" >> "$output"
        utime="$next_utime"
        stime="$next_stime"
        cutime="$next_cutime"
        cstime="$next_cstime"
        uptime="$next_uptime"
        own="$next_own"
        child="$next_child"
        total="$next_total"
    done

    read_proc_stat "$pid" next_pid next_comm next_utime next_stime \
        next_cutime next_cstime next_starttime || return 1
    [[ "$next_starttime" == "$stable_starttime" ]] || return 1
    read_stable_pss "$pid" "$stable_starttime" after_pss after_anon after_file after_shmem || {
        printf 'cannot read final smaps_rollup for PID %s\n' "$pid" >&2
        return 1
    }
    write_pss_boundaries "$pss_output" \
        "$before_pss" "$before_anon" "$before_file" "$before_shmem" \
        "$after_pss" "$after_anon" "$after_file" "$after_shmem"
    write_marker "$stop_marker" "$next_uptime"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if (($# != 6)); then
        printf 'usage: %s PID SAMPLE_COUNT OUTPUT_JSONL PSS_OUTPUT_JSON START_MARKER STOP_MARKER\n' "$0" >&2
        exit 2
    fi
    sample_proc "$@"
fi
