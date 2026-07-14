# PR 15 Ollama AMD performance evidence

## Scope

This evidence compares exact `upstream/main` commit `5fde51ed3ecb16039c96cd259a94c440ac702deb` with exact PR `HEAD` commit `d34ae8217d86f4d4ea9167ae122c0bf9a75358b7` for HANCORE-linux. The committed harness ran with its reportable defaults: 30-second warm-up per scenario, 120-second main/disabled/enabled-closed windows, a 60-second enabled-open window, and a 15-second QSG diagnostic per scenario. No timing overrides were set.

The harness marked all scenarios valid. Each process-monitor calibration observed all three 5 ms and all three 20 ms children, and every sampled bar retained a stable PID/starttime identity.

## Host and AMD source

- GPU: XFX Speedster QICK 319 Radeon RX 6700 XT, PCI device `1002:73df`
- Kernel driver: `amdgpu`
- Provider probe: `provider=amdgpu-sysfs`, `provider_state=active`
- Source: `/sys/class/drm/card1/device/gpu_busy_percent`
- Source driver: `amdgpu`
- Source readable: `true`
- Clock tick: 100 Hz; page size: 4096 bytes
- Quickshell: `0.3.0` Arch Linux package

`hardware/lspci-nnk.txt`, `hardware/amdgpu-sysfs.txt`, `hardware/amd-provider.log`, and `hardware/real-amd-smoke.log` contain the raw hardware and runtime evidence. The real-hardware smoke test sampled the source successfully and its injected `nvidia-smi` start log remained empty.

## CPU results

CPU percentages are one-core percentages. Whole-window deltas are relative to main. The child values are the harness's reaped-child `cutime/cstime` measurements.

| Scenario | Own p50 | Own p95 | Own whole | Own delta | Child p50 | Child p95 | Child whole | Child delta |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Main | 4.9505% | 5.9406% | 4.6111% | 0.0000 pp | 2.9703% | 14.8515% | 4.2316% | 0.0000 pp |
| PR disabled | 4.9505% | 6.9307% | 4.8008% | +0.1897 pp | 2.9703% | 13.8614% | 4.3719% | +0.1402 pp |
| PR enabled, closed | 0.0000% | 0.9901% | 0.2557% | -4.3553 pp | 2.9703% | 14.8515% | 4.3227% | +0.0911 pp |
| PR enabled, open | 0.0000% | 0.9901% | 0.3135% | -4.2976 pp | 2.9703% | 13.8614% | 4.5207% | +0.2891 pp |

Flag for review: PR-disabled whole-window own CPU was 0.1897 percentage point above main, which exceeds the brief's 0.10 percentage-point review trigger. Disabled own p95 increased by 0.990099 percentage point, approximately one jiffy per roughly 1.01-second sample, not more than the stated one-jiffy/sample trigger. These are review flags, not invented pass/fail thresholds.

Live-descendant CPU supplement: unavailable. The committed sampler records parent `utime/stime` and reaped-child `cutime/cstime`; it does not sum CPU from descendants still alive at a sample boundary. No numeric zero is inferred.

## PSS results

| Scenario | Before | After | Delta | Delta percent |
|---|---:|---:|---:|---:|
| Main | 156947 KiB | 148900 KiB | -8047 KiB | -5.1272% |
| PR disabled | 168482 KiB | 167824 KiB | -658 KiB | -0.3905% |
| PR enabled, closed | 156512 KiB | 155375 KiB | -1137 KiB | -0.7265% |
| PR enabled, open | 160390 KiB | 157902 KiB | -2488 KiB | -1.5512% |

All four boundary measurements decreased, so none triggered the brief's growth review level of 5 MiB or 2%.

## Process starts and QSG

| Scenario | Total observed | curl | other | Ollama API curl | `nvidia-smi` | GPU detector bash | QSG | QSG lines |
|---|---:|---:|---:|---:|---:|---:|---|---:|
| Main | 245 | 2 | 243 | 0 | 0 | 0 | available | 5240 |
| PR disabled | 254 | 2 | 252 | 0 | 0 | 0 | available | 36 |
| PR enabled, closed | 259 | 2 | 257 | 0 | 0 | 0 | available | 36 |
| PR enabled, open | 134 | 7 | 127 | 6 | 0 | 0 | available | 50 |

The non-Ollama curl starts were weather requests to `https://wttr.in?format=j1`. Disabled and enabled-closed had no observed Ollama child. Enabled-open had six expected `/api/ps` requests. There were no observed `nvidia-smi` starts and no recurring GPU-attributed bash/cat starts. This is calibrated observation rather than proof that no process could start and exit between monitor polls.

QSG timing was available in all scenarios. Main's much larger timing-line count (5240 versus 36/36/50) is retained as an unexplained run characteristic and should not be interpreted as a direct timing regression without inspecting the raw QSG logs.

## GPU fixtures

The deterministic working-NVIDIA fixture selected the NVIDIA provider, reached 70% from two fake GPUs, and retained a persistent sampler. Its actual start log contains exactly two launches: closed cadence `--loop-ms=120`, then open cadence `--loop-ms=40`. The broken-NVIDIA fixture asserted provider `nvidia`, unavailable state, percent `-1` (`N/A`), and stable unavailable state after an explicit redetection; its start log contains the failed launch and one explicit retry. The no-source fixture asserted provider `none`, percent `-1` (`N/A`), and stable unavailable state after opening the panel, with zero NVIDIA starts.

NVIDIA behavior was validated only with deterministic fixtures. No NVIDIA GPU was available on the benchmark machine, so working and broken NVIDIA behavior could not be tested on real hardware.

## Safety and reproducibility

Preflight found a clean worktree and no active Ollama pull. The harness backed up the active `qs -n -d -c bar` argv and widget cache before mutation. It restored the cache byte-for-byte at SHA-256 `edb95a090e19f559e7bf981dddf9f6ad584164a219239d4d78a2adca825398b0`, relaunched the same argv as identity `207587:934731`, and independently matched both cache and argv bytes. See `hardware/restoration.txt`.

The raw scenario directories retain CPU JSONL, PSS boundaries, process starts, IPC state, calibration records, Quickshell logs, and QSG logs/results. The exact benchmark command and SHAs are in `manifest.json`. Re-run from a clean checkout on equivalent hardware, choosing a nonexistent output path.

The committed harness emitted and validated 120/120/120/60 interval rows. The task brief expected 121/121/121/61 raw rows, but the harness explicitly samples once after each configured one-second interval and rejects any count other than the configured duration. No boundary rows were synthesized; this discrepancy remains a concern.
