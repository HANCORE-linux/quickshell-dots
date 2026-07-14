def nearest_rank($values; $percentile):
  ($values | sort) as $sorted
  | if ($sorted | length) == 0 then null
    else $sorted[((($sorted | length) * $percentile | ceil) - 1)]
    end;

def weighted_cpu($samples; $field):
  ($samples | map(.elapsed_seconds) | add) as $elapsed
  | if $elapsed == 0 then null
    else ($samples | map(.elapsed_seconds * .[$field]) | add) / $elapsed
    end;

def cpu_summary($samples):
  if ($samples | length) == 0 then
    {
      sample_count: 0,
      elapsed_seconds: 0,
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
      whole_window_child_one_core_percent: null
    }
  else
    {
      sample_count: ($samples | length),
      elapsed_seconds: ($samples | map(.elapsed_seconds) | add),
      mean_one_core_percent: ($samples | map(.cpu_one_core_percent) | add / length),
      min_one_core_percent: ($samples | map(.cpu_one_core_percent) | min),
      max_one_core_percent: ($samples | map(.cpu_one_core_percent) | max),
      p50_one_core_percent: nearest_rank(($samples | map(.cpu_one_core_percent)); 0.50),
      p95_one_core_percent: nearest_rank(($samples | map(.cpu_one_core_percent)); 0.95),
      own_p50_one_core_percent: nearest_rank(($samples | map(.own_cpu_one_core_percent)); 0.50),
      own_p95_one_core_percent: nearest_rank(($samples | map(.own_cpu_one_core_percent)); 0.95),
      child_p50_one_core_percent: nearest_rank(($samples | map(.child_cpu_one_core_percent)); 0.50),
      child_p95_one_core_percent: nearest_rank(($samples | map(.child_cpu_one_core_percent)); 0.95),
      whole_window_one_core_percent: weighted_cpu($samples; "cpu_one_core_percent"),
      whole_window_own_one_core_percent: weighted_cpu($samples; "own_cpu_one_core_percent"),
      whole_window_child_one_core_percent: weighted_cpu($samples; "child_cpu_one_core_percent")
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
  | (.pss // null) as $pss
  | (.starts // []) as $starts
  | {
      name,
      source: .source,
      requested_state: .requested_state,
      duration_seconds: .duration_seconds,
      valid: (.valid // false),
      invalid_reasons: (.invalid_reasons // []),
      cpu: cpu_summary($samples),
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
