def cpu_summary($samples):
  if ($samples | length) == 0 then
    {
      sample_count: 0,
      elapsed_seconds: 0,
      mean_one_core_percent: null,
      min_one_core_percent: null,
      max_one_core_percent: null
    }
  else
    {
      sample_count: ($samples | length),
      elapsed_seconds: ($samples | map(.elapsed_seconds) | add),
      mean_one_core_percent: ($samples | map(.cpu_one_core_percent) | add / length),
      min_one_core_percent: ($samples | map(.cpu_one_core_percent) | min),
      max_one_core_percent: ($samples | map(.cpu_one_core_percent) | max)
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
      qsg: (if (.qsg.status // "unavailable") == "available" then
              .qsg
            else
              {status: "unavailable", timing_line_count: null, raw_log: .qsg.raw_log}
            end)
    };

if . == null then
  {manifest: null, scenarios: []}
else
  {
    manifest: (.manifest // null),
    scenarios: [(.scenarios // [])[] | scenario_summary]
  }
end
