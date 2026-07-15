# PR 15 Ollama AMD performance evidence

## Scope

This evidence compares exact `upstream/main` commit `5fde51ed3ecb16039c96cd259a94c440ac702deb` with exact PR commit `3b08d8a76f106a9c5b58d642a0843b8fb2655630`. The harness used 30-second warm-ups, 120-second main/disabled/enabled-closed windows, a 60-second enabled-open window, and 15-second QSG diagnostics. All four scenarios and calibrations were valid.

The final sampler recorded the initial boundary plus every one-second interval: 121/121/121/61 boundaries and 120/120/120/60 rate intervals. Matching recursive live-descendant snapshots are retained in each scenario.

## Host and GPU

- GPU: XFX Speedster QICK 319 Radeon RX 6700 XT, PCI `1002:73df`
- Driver and provider: `amdgpu`, `amdgpu-sysfs`
- Source: readable `/sys/class/drm/card1/device/gpu_busy_percent`
- Real AMD smoke: passed, with zero injected `nvidia-smi` starts

NVIDIA behavior was validated only with deterministic fixtures. No NVIDIA GPU was available on the benchmark machine, so working and broken NVIDIA behavior could not be tested on real hardware.

The working, broken, and no-source fixtures passed. Working NVIDIA used one persistent sampler per cadence (`--loop-ms=120`, then `--loop-ms=40`); broken NVIDIA stayed unavailable after explicit retry; no-source stayed unavailable with zero NVIDIA starts.

## Results

CPU values are percentages of one core. Live-descendant CPU is a conservative observed lower bound based on stable identities at adjacent boundaries.

| Scenario | Own p50 | Own p95 | Own whole | Delta vs main | Reaped child whole | Live descendant lower bound |
|---|---:|---:|---:|---:|---:|---:|
| Main | 5.0000% | 9.0000% | 5.4750% | 0.0000 pp | 4.8250% | 0.0000% |
| PR disabled | 5.0505% | 7.0000% | 5.6329% | +0.1579 pp | 4.7079% | 0.0000% |
| PR enabled, closed | 6.0000% | 8.0000% | 6.1912% | +0.7162 pp | 4.6746% | 0.0000% |
| PR enabled, open | 6.0000% | 8.0000% | 6.1323% | +0.6573 pp | 4.7492% | 0.0000% |

PR-disabled whole-window own CPU crossed the requested 0.10 percentage-point review trigger by reaching +0.1579 pp. This is reported as a review flag, not an invented pass/fail threshold.

| Scenario | PSS before | PSS after | Delta | Delta percent |
|---|---:|---:|---:|---:|
| Main | 146023 KiB | 159563 KiB | +13540 KiB | +9.2725% |
| PR disabled | 174986 KiB | 174043 KiB | -943 KiB | -0.5389% |
| PR enabled, closed | 171705 KiB | 187442 KiB | +15737 KiB | +9.1651% |
| PR enabled, open | 166017 KiB | 170656 KiB | +4639 KiB | +2.7943% |

Main and enabled-closed crossed both PSS review triggers; enabled-open crossed the 2% trigger only. These are noisy boundary measurements and are not presented as leak proof. Disabled PSS decreased.

| Scenario | Observed starts | curl | Ollama API curl | `nvidia-smi` | QSG lines |
|---|---:|---:|---:|---:|---:|
| Main | 292 | 2 | 0 | 0 | 7181 |
| PR disabled | 310 | 2 | 0 | 0 | 5792 |
| PR enabled, closed | 304 | 2 | 0 | 0 | 5653 |
| PR enabled, open | 110 | 1 | 0 | 0 | 5931 |

All observed curl starts were weather requests. The panel-open refresh occurred during warm-up, and no periodic Ollama API polling was observed in any measured idle window. No recurring `nvidia-smi` or GPU-attributed shell process was observed. Process monitoring is calibrated observation and can miss a process entirely between polls.

## Safety and artifacts

The harness restored the widget cache byte-for-byte at SHA-256 `edb95a090e19f559e7bf981dddf9f6ad584164a219239d4d78a2adca825398b0`, restored the original `qs -n -d -c bar` argv as identity `425269:1449833`, and reported zero survivors among 24 owned process identities.

Raw parent boundaries, live-descendant snapshots, PSS boundaries, process starts, calibration, Quickshell logs, QSG logs, fixture logs, restoration records, manifest, machine report, and checksums are retained below this directory.
