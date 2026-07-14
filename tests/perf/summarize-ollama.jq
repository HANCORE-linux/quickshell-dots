def nearest_rank($values; $percentile):
  ($values | sort) as $sorted
  | if ($sorted | length) == 0 then null
    else $sorted[((($sorted | length) * $percentile | ceil) - 1)]
    end;

def descendant_summary($snapshots; $window_elapsed; $hz):
  [$snapshots[] as $snapshot
    | ($snapshot.descendants // [])[]
    | . + {sample: $snapshot.sample, observed_uptime_seconds: $snapshot.uptime_seconds}]
  | sort_by(.identity, .sample)
  | group_by(.identity)
  | map(
      . as $observations
      | reduce range(1; $observations | length) as $index
          ({positive_delta_jiffies: 0, adjacent_transition_count: 0};
           if $observations[$index].sample == ($observations[$index - 1].sample + 1) then
             (($observations[$index].utime + $observations[$index].stime)
              - ($observations[$index - 1].utime + $observations[$index - 1].stime)) as $delta
             | .adjacent_transition_count += 1
             | if $delta > 0 then .positive_delta_jiffies += $delta else . end
           else . end) as $deltas
      | {
          identity: $observations[0].identity,
          pid: $observations[0].pid,
          starttime: $observations[0].starttime,
          first_sample: ($observations | map(.sample) | min),
          last_sample: ($observations | map(.sample) | max),
          observation_count: ($observations | length),
          adjacent_transition_count: $deltas.adjacent_transition_count,
          positive_delta_jiffies: $deltas.positive_delta_jiffies
        }) as $identities
  | ($identities | map(.positive_delta_jiffies) | add // 0) as $positive_delta
  | {
      method: "positive deltas between adjacent boundary observations of the same PID/starttime identity",
      observed_identity_count: ($identities | length),
      identities_with_positive_delta: ($identities | map(select(.positive_delta_jiffies > 0)) | length),
      positive_delta_jiffies: $positive_delta,
      whole_window_one_core_percent:
        (if $window_elapsed > 0 and $hz > 0
         then 100 * $positive_delta / ($hz * $window_elapsed)
         else null end),
      identities: $identities,
      limitations: [
        "processes entirely between boundaries are not observed or inferred",
        "CPU after a process disappears before the next boundary is not inferred",
        "reaped-child cutime/cstime is reported separately and may overlap terminated descendants"
      ]
    };

def cpu_summary($samples; $descendants):
  ($samples | sort_by(.sample)) as $boundaries
  | [$boundaries[] | select((.sample // 0) > 0 and
      (.cpu_one_core_percent | type) == "number")] as $intervals
  | if ($boundaries | length) == 0 then
    {
      boundary_count: 0,
      sample_count: 0,
      elapsed_seconds: 0,
      whole_window_elapsed_seconds: 0,
      mean_one_core_percent: null,
      min_one_core_percent: null,
      max_one_core_percent: null,
      p50_one_core_percent: null,
      p95_one_core_percent: null,
      own_p50_one_core_percent: null,
      own_p95_one_core_percent: null,
      child_p50_one_core_percent: null,
      child_p95_one_core_percent: null,
      whole_window_one_core_percent: null,
      whole_window_own_one_core_percent: null,
      whole_window_child_one_core_percent: null,
      whole_window_reaped_child_one_core_percent: null,
      whole_window_parent_plus_reaped_one_core_percent: null,
      live_descendants: descendant_summary($descendants; 0; 0)
    }
  else
    ($boundaries[0]) as $first
    | ($boundaries[-1]) as $last
    | ($last.uptime_seconds - $first.uptime_seconds) as $window_elapsed
    | ($first.clock_tick_hz // 0) as $hz
    | (($last.utime + $last.stime) - ($first.utime + $first.stime)) as $own_delta
    | (($last.cutime + $last.cstime) - ($first.cutime + $first.cstime)) as $reaped_delta
    | {
      boundary_count: ($boundaries | length),
      sample_count: ($intervals | length),
      elapsed_seconds: ($intervals | map(.elapsed_seconds) | add // 0),
      whole_window_elapsed_seconds: $window_elapsed,
      mean_one_core_percent: (if ($intervals | length) > 0 then ($intervals | map(.cpu_one_core_percent) | add / length) else null end),
      min_one_core_percent: (if ($intervals | length) > 0 then ($intervals | map(.cpu_one_core_percent) | min) else null end),
      max_one_core_percent: (if ($intervals | length) > 0 then ($intervals | map(.cpu_one_core_percent) | max) else null end),
      p50_one_core_percent: nearest_rank(($intervals | map(.cpu_one_core_percent)); 0.50),
      p95_one_core_percent: nearest_rank(($intervals | map(.cpu_one_core_percent)); 0.95),
      own_p50_one_core_percent: nearest_rank(($intervals | map(.own_cpu_one_core_percent)); 0.50),
      own_p95_one_core_percent: nearest_rank(($intervals | map(.own_cpu_one_core_percent)); 0.95),
      child_p50_one_core_percent: nearest_rank(($intervals | map(.child_cpu_one_core_percent)); 0.50),
      child_p95_one_core_percent: nearest_rank(($intervals | map(.child_cpu_one_core_percent)); 0.95),
      whole_window_own_delta_jiffies: $own_delta,
      whole_window_reaped_child_delta_jiffies: $reaped_delta,
      whole_window_one_core_percent:
        (if $window_elapsed > 0 and $hz > 0 then 100 * ($own_delta + $reaped_delta) / ($hz * $window_elapsed) else null end),
      whole_window_own_one_core_percent:
        (if $window_elapsed > 0 and $hz > 0 then 100 * $own_delta / ($hz * $window_elapsed) else null end),
      whole_window_child_one_core_percent:
        (if $window_elapsed > 0 and $hz > 0 then 100 * $reaped_delta / ($hz * $window_elapsed) else null end),
      whole_window_reaped_child_one_core_percent:
        (if $window_elapsed > 0 and $hz > 0 then 100 * $reaped_delta / ($hz * $window_elapsed) else null end),
      whole_window_parent_plus_reaped_one_core_percent:
        (if $window_elapsed > 0 and $hz > 0 then 100 * ($own_delta + $reaped_delta) / ($hz * $window_elapsed) else null end),
      live_descendants: descendant_summary($descendants; $window_elapsed; $hz)
    }
  end;

def pss_summary($pss):
  if ($pss | type) != "object" or ($pss.before | type) != "object"
      or ($pss.after | type) != "object" then
    {status: "unavailable"}
  else
    {
      status: "available",
      unit: ($pss.unit // "kB"),
      before: $pss.before,
      after: $pss.after,
      delta: {
        Pss: ($pss.after.Pss - $pss.before.Pss),
        Pss_Anon: ($pss.after.Pss_Anon - $pss.before.Pss_Anon),
        Pss_File: ($pss.after.Pss_File - $pss.before.Pss_File),
        Pss_Shmem: ($pss.after.Pss_Shmem - $pss.before.Pss_Shmem)
      }
    }
  end;

def start_summary($starts):
  {
    wording: (if ($starts | length) == 0 then "zero observed starts" else "observed starts" end),
    observed_count: ($starts | length),
    by_attribution: ($starts
      | sort_by(.attribution)
      | group_by(.attribution)
      | map({key: .[0].attribution, value: length})
      | from_entries),
    curl_endpoints: ($starts
      | map(select(.attribution == "curl" and .endpoint != "") | .endpoint)
      | unique)
  };

def scenario_summary:
  (.samples // []) as $samples
  | (.descendant_cpu // []) as $descendants
  | (.pss // null) as $pss
  | (.starts // []) as $starts
  | {
      name,
      source: .source,
      requested_state: .requested_state,
      duration_seconds: .duration_seconds,
      valid: (.valid // false),
      invalid_reasons: (.invalid_reasons // []),
      cpu: cpu_summary($samples; $descendants),
      pss: pss_summary($pss),
      process_starts: start_summary($starts),
      calibration: (.calibration // {valid: false, expected: 0, observed: 0}),
      qsg: ({valid: true, status: "unavailable", timing_line_count: null,
             invalid_reasons: [], raw_log: null} + (.qsg // {}))
    };

if . == null then
  {valid: false, manifest: null, observed_calibration: [], scenarios: []}
else
  . as $input
  |
  {
    valid: (($input.manifest.valid == true) and all(($input.scenarios // [])[];
      (.valid == true and .calibration.valid == true))),
    manifest: ($input.manifest // null),
    observed_calibration: [($input.scenarios // [])[]
      | {scenario: .name} + (.calibration // {valid: false, expected: 0, observed: 0})],
    scenarios: [($input.scenarios // [])[] | scenario_summary]
  }
end
