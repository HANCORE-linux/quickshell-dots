#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
test_config_root="$fixture_root/tests/fixtures"
test_config_path="$test_config_root/OllamaGpuSmoke.qml"

cleanup() {
    rm -rf "$fixture_root"
}
trap cleanup EXIT

mkdir -p "$test_config_root/modules"
cp "$repo_root/tests/fixtures/OllamaGpuSmoke.qml" "$test_config_path"
cp "$repo_root/versions/V1/modules/OllamaGpuSampler.qml" \
   "$repo_root/versions/V1/modules/OllamaGpuLogic.js" \
   "$test_config_root/modules/"

make_card() {
    local root="$1" card="$2" driver="$3" vendor="$4" busy="${5-}"
    mkdir -p "$root/class/drm/$card/device"
    printf 'DRIVER=%s\n' "$driver" >"$root/class/drm/$card/device/uevent"
    printf '%s\n' "$vendor" >"$root/class/drm/$card/device/vendor"
    if [[ -n "$busy" ]]; then
        printf '%s\n' "$busy" >"$root/class/drm/$card/device/gpu_busy_percent"
    fi
}

make_nvidia_smi() {
    local path="$1" mode="$2"
    if [[ "$mode" == "working" ]]; then
        cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OLLAMA_GPU_START_LOG"
while :; do
    printf '0, 20\n1, 70\n'
    sleep 0.03
done
SH
    else
        cat >"$path" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OLLAMA_GPU_START_LOG"
exit 1
SH
    fi
    chmod +x "$path"
}

run_case() {
    local case_name="$1"
    local case_root="$fixture_root/$case_name"
    local sysfs_root="$case_root/sys"
    local start_log="$case_root/nvidia-starts.log"
    local executable="$case_root/nvidia-smi"
    local output="$case_root/qs.log"

    mkdir -p "$sysfs_root/class/drm"
    : >"$start_log"
    make_nvidia_smi "$executable" working

    case "$case_name" in
        amd)
            make_card "$sysfs_root" card0 amdgpu 0x1002 17
            make_card "$sysfs_root" card1 nvidia 0x10de
            make_card "$sysfs_root" card3 amdgpu 0x1002 82
            ;;
        amd-initial-invalid)
            make_card "$sysfs_root" card0 amdgpu 0x1002 101
            make_card "$sysfs_root" card1 nvidia 0x10de
            ;;
        nvidia)
            make_card "$sysfs_root" card47 nvidia 0x10de
            ;;
        broken-nvidia)
            make_card "$sysfs_root" card2 nvidia 0x10de
            make_nvidia_smi "$executable" broken
            ;;
        no-source)
            make_card "$sysfs_root" card0 i915 0x8086
            ;;
    esac

    local status=0
    timeout --kill-after=1s 8s env QT_QPA_PLATFORM=offscreen \
        OLLAMA_GPU_TEST_CASE="$case_name" \
        OLLAMA_GPU_SYSFS_ROOT="$sysfs_root" \
        OLLAMA_GPU_NVIDIA_SMI="$executable" \
        OLLAMA_GPU_START_LOG="$start_log" \
        qs --no-color -p "$test_config_path" >"$output" 2>&1 || status=$?
    if [[ "$status" -ne 0 ]] || grep -Fq 'OLLAMA_GPU_FAIL' "$output" \
            || ! grep -Fq "OLLAMA_GPU_PASS: $case_name" "$output"; then
        command cat "$output"
        exit 1
    fi

    local starts
    starts="$(wc -l <"$start_log")"
    case "$case_name" in
        amd|amd-initial-invalid|no-source)
            [[ "$starts" -eq 0 ]] || {
                printf '%s started nvidia-smi %s times\n' "$case_name" "$starts" >&2
                exit 1
            }
            ;;
        nvidia)
            [[ "$starts" -eq 2 ]] || {
                printf 'working NVIDIA expected one start per cadence, got %s\n' "$starts" >&2
                exit 1
            }
            grep -Fxq -- '--query-gpu=index,utilization.gpu --format=csv,noheader,nounits --loop-ms=120' "$start_log"
            grep -Fxq -- '--query-gpu=index,utilization.gpu --format=csv,noheader,nounits --loop-ms=40' "$start_log"
            ;;
        broken-nvidia)
            [[ "$starts" -eq 2 ]] || {
                printf 'broken NVIDIA expected failed start plus explicit retry, got %s\n' "$starts" >&2
                exit 1
            }
            ;;
    esac
}

run_hardware_amd() {
    local case_root="$fixture_root/hardware-amd"
    local start_log="$case_root/nvidia-starts.log"
    local executable="$case_root/nvidia-smi"
    local output="$case_root/qs.log"

    mkdir -p "$case_root"
    : >"$start_log"
    make_nvidia_smi "$executable" broken

    local status=0
    timeout --kill-after=1s 8s env QT_QPA_PLATFORM=offscreen \
        OLLAMA_GPU_TEST_CASE=hardware-amd \
        OLLAMA_GPU_SYSFS_ROOT=/sys \
        OLLAMA_GPU_NVIDIA_SMI="$executable" \
        OLLAMA_GPU_START_LOG="$start_log" \
        qs --no-color -p "$test_config_path" >"$output" 2>&1 || status=$?
    if [[ "$status" -ne 0 ]] || grep -Fq 'OLLAMA_GPU_FAIL' "$output" \
            || ! grep -Fq 'OLLAMA_GPU_PASS: hardware-amd' "$output"; then
        command cat "$output"
        exit 1
    fi
    [[ ! -s "$start_log" ]] || {
        printf 'real AMD hardware started injected nvidia-smi\n' >&2
        exit 1
    }
    printf '%s\n' 'ollama GPU real AMD smoke: PASS'
}

run_case amd
run_case amd-initial-invalid
run_case nvidia
run_case broken-nvidia
run_case no-source
if [[ "${OLLAMA_GPU_RUN_HARDWARE:-0}" == "1" ]]; then
    run_hardware_amd
fi
printf '%s\n' 'ollama GPU integration: PASS'
