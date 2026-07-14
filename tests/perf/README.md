# Ollama `/proc` performance harness

This harness compares the idle Quickshell bar at exact main and PR commits. It
uses Linux procfs and tools already required by the project; it does not install
profilers or tracing tools.

## Requirements

- Linux with `/proc`, `smaps_rollup`, and `/proc/<pid>/task/*/children`
- Bash 4.3 or newer
- `git`, `jq`, `awk`, `getconf`, `sha256sum`, `tar`, and Quickshell's `qs`
- Exactly one active Quickshell bar selected as `-c bar` or from a
  `.../quickshell/bar` path
- A recognized `~/.cache/quickshell_widgets` schema with the Ollama fields
- No active Ollama pull

## Self-test

```bash
bash tests/perf/benchmark-ollama.sh self-test
```

Self-test uses only temporary synthetic processes. It validates stat parsing,
initial-plus-interval CPU boundaries, recursive descendant CPU snapshots, PSS
fields, PID/starttime rejection, 5 ms and 20 ms descendant observation, cache
mutation and restoration evidence on fixtures, and exact git archives. It
snapshots active Quickshell PID/starttime identities and fails if they change;
it never signals the bar or reads/writes the live widget cache.

## Benchmark

```bash
bash tests/perf/benchmark-ollama.sh run \
  upstream/main HEAD /path/to/new-artifact-directory
```

The optional fourth argument changes the 120-second base window. The open-panel
window is half of that value, rounded up. Defaults reproduce these scenarios:

| Scenario | Source and state | Warm-up | Window |
|---|---|---:|---:|
| `01-main` | main baseline | 30 s | 120 s |
| `02-pr-disabled` | PR, Ollama disabled | 30 s | 120 s |
| `03-pr-enabled-closed` | PR, enabled and closed | 30 s | 120 s |
| `04-pr-enabled-open` | PR, enabled and open | 30 s | 60 s |

For smoke testing only, `OLLAMA_PERF_WARMUP_SECONDS` and
`OLLAMA_PERF_QSG_SECONDS` override the recorded warm-up and diagnostic lengths.
Do not use overrides for reportable benchmark results.

The output directory must not exist. The run is built in a private sibling
directory and the requested path remains absent until cleanup atomically renames
one complete success or failure directory into place. Both refs are resolved
once to commit SHAs, retained as `git archive` tar files, extracted under the
private artifact directory, and made read-only. The mutable worktree is never
launched.

## Safety

Before mutation, the runner records the active bar's NUL-delimited argv,
configuration selector, PID, and starttime. It also validates and backs up the
widget cache. EXIT, INT, and TERM traps stop only PID/starttime identities owned
by the run, escalating from bounded TERM to bounded KILL and retaining identity
until death is verified. Only then do they restore the cache byte-for-byte and
relaunch the original argv. Finalization records the restoration outcome and
original exit status before regenerating summaries and checksums.
Ambiguous bars, unknown cache schemas, missing caches, and active pulls abort
before the live bar is stopped.

Ownership is role-based rather than tied to one code path. Benchmark and QSG
bars, scenario monitors, samplers, and calibration root/monitor processes enter
a cleanup-visible registry immediately after spawn. A role cannot be reused
while its identity may survive. Identity-capture failure triggers synchronous
TERM/KILL/reap by PID; failure to prove absence blocks cache and bar restoration.
Calibration command/wait descriptors are global cleanup state and are closed on
normal exit, INT, or TERM before registered calibration processes are stopped.
The safety directory retains original and restored NUL-delimited argv and
PID/starttime identities, the exact cache hash commands/results before backup and
after restoration, every owned-process claim/capture, and a final inventory that
must report zero surviving owned identities.

PR state transitions use the `ollama open` and `ollama close` IPC methods. Before
every primary and QSG window, the harness reads the live `ollama.enabled` and
`ollama.panelVisible` IPC properties and requires exact boolean matches. The main
baseline instead requires the Ollama IPC target to be absent.

## Artifacts

- `manifest.json`: schema version 2, resolved SHAs, timing, host boot ID, monitor
  calibration and observed calibration, top-level validity/exit status, and
  restoration outcome
- `sources/{main,pr}/source.tar`: retained immutable git archives
- `sources/{main,pr}/source/`: read-only extracted sources
- `safety/`: original/restored bar argv and identities, widget-cache backup and
  hash transcript, owned-process history, and zero-survivor inventory
- `scenarios/*/cpu-samples.jsonl`: initial boundary plus one record per interval,
  with raw parent counters/uptime on every row; sample zero has elapsed zero and
  null rates
- `scenarios/*/proc-stat.tsv`: the same raw parent boundaries in tabular form;
  excluding its header, default scenarios contain 121/121/121/61 data rows
- `scenarios/*/descendant-cpu.jsonl`: one recursive stable PID/starttime
  descendant snapshot per parent boundary, including each live descendant's
  `utime` and `stime`
- `scenarios/*/pss.json`: before/after `Pss`, `Pss_Anon`, `Pss_File`, and
  `Pss_Shmem` from `smaps_rollup`
- `scenarios/*/starts.jsonl`: observed descendant identities, argv, curl
  endpoints, GPU detector Bash attribution, and `nvidia-smi` attribution
- `scenarios/*/calibration/`: exact expected/observed 5 ms and 20 ms child starts
- `scenarios/*/qsg/qsg.log`: raw QSG diagnostic output from a separate pass
- `summary.json`: deterministic aggregates for all scenarios
- `checksums.sha256`: SHA-256 checksums for every regular artifact file
- `finalization-errors.json`: empty on complete success; otherwise lists failed
  or skipped scenario validation, calibration jq, manifest, results, summary,
  error-report, or checksum operations

A finalization failure publishes raw diagnostics plus only an invalid, nonzero
`manifest.json` and nonempty `finalization-errors.json`. It deliberately omits
`results.json`, `summary.json`, and `checksums.sha256`. If those failure metadata
files cannot both be written and validated, the requested output path remains
absent and the private directory is retained for local recovery.

The sampler publishes start/stop markers around the CPU/PSS window. The process
monitor compares field-22 starttime against the shared start boundary and makes
a final tail scan after the stop marker.

QSG timing is `unavailable` when the raw log has no recognized timing lines; it
is never reported as zero. A state mismatch or premature diagnostic process exit
invalidates the QSG pass and scenario even when timing text exists. A calibrated
monitor result with no records is
reported as `zero observed starts`. Polling can miss a process that starts and
exits between scans, so this wording is observation, not mathematical proof
that no process started.

CPU percentages are scaled so 100% means one fully occupied core. Nearest-rank
p50/p95 values use interval rows only and exclude sample zero. Whole-window
parent-own and reaped-child values use first-to-last raw counters and actual
`/proc/uptime` elapsed time. Reaped-child `cutime+cstime` remains separate from
live-descendant CPU.

Live-descendant CPU is a conservative observed lower bound: only positive
`utime+stime` deltas for the same PID/starttime identity on adjacent boundaries
are counted. Processes entirely between boundaries, or disappearing before the
next boundary, are not observed or inferred. Terminated descendants may later
appear in reaped-child counters, so the two values must not be blindly added.
PSS is a boundary measurement, not a continuous memory trace. Results remain
sensitive to compositor load, GPU driver state, filesystem caches, and unrelated
host activity.

Artifact finalization does not rely on Bash `errexit`. It prepares manifest,
results, summary, error-report, and checksum candidates privately, validates all
JSON and verifies the checksum set against that private generation, then
publishes the whole run with one directory rename. `finalization-errors.json`
always uses a checked temporary-file rename. `RUN_FINALIZED` is set only after
complete success. A preparation failure discards success candidates, regenerates
failure metadata with `valid=false` and the final nonzero status, and preserves
an existing failure or signal status.
