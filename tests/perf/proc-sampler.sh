#!/usr/bin/env bash
set -euo pipefail

read_proc_stat() {
    local pid="$1"
    local -n out_pid="$2" out_comm="$3" out_utime="$4" out_stime="$5"
    local -n out_cutime="$6" out_cstime="$7" out_starttime="$8"
    local line body rest suffix
    local -a fields

    IFS= read -r line < "/proc/$pid/stat" 2>/dev/null || return 1
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

read_stable_descendant_cpu() {
    local pid="$1"
    local first_pid first_comm first_utime first_stime first_cutime first_cstime first_start
    local second_pid second_comm second_utime second_stime second_cutime second_cstime second_start
    read_proc_stat "$pid" first_pid first_comm first_utime first_stime \
        first_cutime first_cstime first_start || return 1
    read_proc_stat "$pid" second_pid second_comm second_utime second_stime \
        second_cutime second_cstime second_start || return 1
    [[ "$first_start" == "$second_start" ]] || return 1
    DESCENDANT_PID="$second_pid"
    DESCENDANT_STARTTIME="$second_start"
    DESCENDANT_UTIME="$second_utime"
    DESCENDANT_STIME="$second_stime"
}

write_descendant_boundary() {
    local root_pid="$1" sample="$2" uptime="$3" boot_id="$4" output="$5"
    local pid separator="" identity
    local -a descendants
    collect_descendants "$root_pid" descendants
    printf '{"sample":%d,"uptime_seconds":%s,"descendants":[' \
        "$sample" "$uptime" >> "$output"
    for pid in "${descendants[@]}"; do
        read_stable_descendant_cpu "$pid" || continue
        identity="$boot_id:$DESCENDANT_PID:$DESCENDANT_STARTTIME"
        printf '%s{"identity":"%s","pid":%d,"starttime":%s,"utime":%s,"stime":%s}' \
            "$separator" "$identity" "$DESCENDANT_PID" "$DESCENDANT_STARTTIME" \
            "$DESCENDANT_UTIME" "$DESCENDANT_STIME" >> "$output"
        separator=,
    done
    printf ']}\n' >> "$output"
}

write_initial_boundary() {
    local output="$1" tsv="$2" pid="$3" starttime="$4" uptime="$5"
    local utime="$6" stime="$7" cutime="$8" cstime="$9" clock_tick="${10}"
    printf '{"sample":0,"boundary":true,"pid":%d,"starttime":%s,' \
        "$pid" "$starttime" >> "$output"
    printf '"clock_tick_hz":%s,"uptime_seconds":%s,"elapsed_seconds":0,"utime":%s,"stime":%s,' \
        "$clock_tick" "$uptime" "$utime" "$stime" >> "$output"
    printf '"cutime":%s,"cstime":%s,"own_delta_jiffies":null,' \
        "$cutime" "$cstime" >> "$output"
    printf '"child_delta_jiffies":null,"delta_jiffies":null,' >> "$output"
    printf '"own_cpu_one_core_percent":null,"child_cpu_one_core_percent":null,' >> "$output"
    printf '"cpu_one_core_percent":null}\n' >> "$output"
    printf '0\tboundary\t%s\t%s\t%s\t%s\t0\t%s\t%s\t%s\t%s\tnull\tnull\tnull\tnull\tnull\tnull\n' \
        "$pid" "$starttime" "$clock_tick" "$uptime" "$utime" "$stime" "$cutime" "$cstime" >> "$tsv"
}

write_interval_boundary() {
    local output="$1" tsv="$2" sample="$3" pid="$4" starttime="$5" uptime="$6"
    local elapsed="$7" utime="$8" stime="$9" cutime="${10}" cstime="${11}"
    local own_delta="${12}" child_delta="${13}" delta="${14}"
    local own_cpu="${15}" child_cpu="${16}" cpu="${17}" clock_tick="${18}"
    printf '{"sample":%d,"boundary":false,"pid":%d,"starttime":%s,' \
        "$sample" "$pid" "$starttime" >> "$output"
    printf '"clock_tick_hz":%s,"uptime_seconds":%s,"elapsed_seconds":%s,"utime":%s,"stime":%s,' \
        "$clock_tick" "$uptime" "$elapsed" "$utime" "$stime" >> "$output"
    printf '"cutime":%s,"cstime":%s,"own_delta_jiffies":%d,' \
        "$cutime" "$cstime" "$own_delta" >> "$output"
    printf '"child_delta_jiffies":%d,"delta_jiffies":%d,' \
        "$child_delta" "$delta" >> "$output"
    printf '"own_cpu_one_core_percent":%s,"child_cpu_one_core_percent":%s,' \
        "$own_cpu" "$child_cpu" >> "$output"
    printf '"cpu_one_core_percent":%s}\n' "$cpu" >> "$output"
    printf '%s\tinterval\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$sample" "$pid" "$starttime" "$clock_tick" "$uptime" "$elapsed" "$utime" "$stime" \
        "$cutime" "$cstime" "$own_delta" "$child_delta" "$delta" \
        "$own_cpu" "$child_cpu" "$cpu" >> "$tsv"
}

wait_until_uptime() {
    local target="$1" fd="$2" current remaining
    while :; do
        read_proc_uptime current || return 1
        remaining="$(awk -v target="$target" -v current="$current" \
            'BEGIN { remaining = target - current; printf "%.6f", (remaining > 0 ? remaining : 0) }')"
        awk -v remaining="$remaining" 'BEGIN { exit !(remaining <= 0) }' && return 0
        read -r -t "$remaining" -u "$fd" _ || true
    done
}

sample_proc() {
    local pid="$1" sample_count="$2" output="$3" proc_stat_output="$4"
    local descendant_output="$5" pss_output="$6" start_marker="$7" stop_marker="$8"
    local clock_tick wait_dir wait_fifo sample_wait_fd
    local boot_id
    local parsed_pid comm utime stime cutime cstime starttime stable_starttime
    local next_pid next_comm next_utime next_stime next_cutime next_cstime next_starttime
    local uptime initial_uptime target_uptime next_uptime total next_total delta elapsed cpu sample boundary_jiffies
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
    printf 'sample\tkind\tpid\tstarttime\tclock_tick_hz\tuptime_seconds\telapsed_seconds\tutime\tstime\tcutime\tcstime\town_delta_jiffies\tchild_delta_jiffies\tdelta_jiffies\town_cpu_one_core_percent\tchild_cpu_one_core_percent\tcpu_one_core_percent\n' \
        > "$proc_stat_output"
    : > "$descendant_output"
    IFS= read -r boot_id < /proc/sys/kernel/random/boot_id
    [[ "$boot_id" =~ ^[0-9a-f-]+$ ]] || return 1
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
    initial_uptime="$uptime"
    boundary_jiffies="$(awk -v uptime="$uptime" -v hz="$clock_tick" \
        'BEGIN { printf "%d", uptime * hz }')"
    write_marker "$start_marker" "$boundary_jiffies"
    own=$((utime + stime))
    child=$((cutime + cstime))
    total=$((utime + stime + cutime + cstime))
    write_initial_boundary "$output" "$proc_stat_output" "$pid" "$stable_starttime" \
        "$uptime" "$utime" "$stime" "$cutime" "$cstime" "$clock_tick"
    write_descendant_boundary "$pid" 0 "$uptime" "$boot_id" "$descendant_output"

    wait_dir="$(mktemp -d "${TMPDIR:-/tmp}/proc-sampler.XXXXXX")"
    wait_fifo="$wait_dir/tick"
    mkfifo "$wait_fifo"
    exec {sample_wait_fd}<>"$wait_fifo"
    trap 'exec {sample_wait_fd}>&- 2>/dev/null || true; rm -rf -- "$wait_dir"' RETURN

    for ((sample = 1; sample <= sample_count; sample++)); do
        target_uptime="$(awk -v initial="$initial_uptime" -v sample="$sample" \
            'BEGIN { printf "%.6f", initial + sample }')"
        wait_until_uptime "$target_uptime" "$sample_wait_fd"
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
        write_interval_boundary "$output" "$proc_stat_output" "$sample" "$pid" \
            "$stable_starttime" "$next_uptime" "$elapsed" "$next_utime" "$next_stime" \
            "$next_cutime" "$next_cstime" "$own_delta" "$child_delta" "$delta" \
            "$own_cpu" "$child_cpu" "$cpu" "$clock_tick"
        write_descendant_boundary "$pid" "$sample" "$next_uptime" "$boot_id" \
            "$descendant_output"
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
    if (($# != 8)); then
        printf 'usage: %s PID SAMPLE_COUNT OUTPUT_JSONL PROC_STAT_TSV DESCENDANT_JSONL PSS_OUTPUT_JSON START_MARKER STOP_MARKER\n' "$0" >&2
        exit 2
    fi
    sample_proc "$@"
fi
