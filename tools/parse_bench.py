#!/usr/bin/env python3
"""
AMS Benchmark Console Parser

Extracts structured benchmark data from Project Zomboid console.txt.

Usage:
    python3 parse_bench.py <path> [options]

Output modes (pick one):
    (default)          Concise JSON summary (run metadata + validity)
    --full             JSON with aggregates + raw steps
    --brief            Compact text tables: run/walk/sprint/combat with ratios vs naked (LLM-friendly)
    --validity         Text summary of rejected steps with reasons
    --diag-load        Text diagnostics for effective-load decomposition
    --diag-weight      Text diagnostics for runtime weight-source usage
    --diag-order       Text diagnostics for endurance ordering (pre/post AMS)
    --compare A B      Side-by-side diff of two run IDs

Filters:
    --run-id ID        Single run
    --last N           Most recent N runs
    --label LABEL      Filter by label
    --scenario a,b     Filter by scenario
    --set a,b          Filter by set

Examples:
    parse_bench.py snapshot.log --brief                   # compact table for AI assistant
    parse_bench.py snapshot.log --validity                # what failed and why
    parse_bench.py snapshot.log --brief --set heavy,light # specific sets only
    parse_bench.py snapshot.log --full                    # full JSON for deep analysis
"""

import argparse
import csv
import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path


TAG_START = "[AMS_BENCH_START]"
TAG_STEP  = "[AMS_BENCH_STEP_DONE]"
TAG_REPORT = "[AMS_BENCHMARK_REPORT]"
TAG_DONE  = "[AMS_BENCH_DONE]"

KV_RE = re.compile(r'(\w+)=((?:"[^"]*"|\S+))')

METRIC_FIELDS = [
    "endDelta", "thirstDelta", "fatigueDelta", "tempDelta", "strainDelta", "achieved_sec", "swings_per_minute",
]

ENV_FIELDS = [
    "ambientAirTemp", "skinTemp", "clothingCondition",
]

COMBAT_FIELDS = [
    "attack_cooldown_blocks", "attack_cooldown_sec",
]

QUALITY_NUMERIC_FIELDS = [
    "reset_attempts",
    "forward_rearm_attempts",
    "forward_rearm_failures",
    "teleport_jump_count",
    "anchor_start_err_tiles",
    "anchor_end_err_tiles",
    "anchor_delta_before_start",
    "anchor_delta_after_post_reset",
    "sample_window_sec",
    "total_samples",
    "valid_samples",
    "moving_samples",
    "stall_sec_accum",
]

CORE_DIFF_FIELDS = [
    "endDelta", "thirstDelta", "fatigueDelta", "tempDelta", "strainDelta", "achieved_sec",
]

# Built-in design targets used by --check-targets auto mode.
# Metric options:
# - ratio: endDelta(set) / endDelta(naked) within same scenario
# - achieved_sec_ratio: achieved_sec(set) / achieved_sec(naked)
# - drain_per_swing_ratio: drain_per_swing(set) / drain_per_swing(naked)
DEFAULT_TARGET_BANDS = {
    "benchmark_core_v1": {
        "id": "core_v1",
        "checks": [
            {"label": "run_heavy_ratio", "scenario": "native_treadmill_run", "set": "heavy", "metric": "ratio", "min": 1.45, "max": 1.70},
            {"label": "run_civilian_baseline_ratio", "scenario": "native_treadmill_run", "set": "civilian_baseline", "metric": "ratio", "min": 0.95, "max": 1.05},
            {"label": "sprint_heavy_ratio", "scenario": "native_treadmill_sprint", "set": "heavy", "metric": "ratio", "min": 1.08, "max": 1.25},
            {"label": "combat_heavy_dsw_ratio", "scenario": "native_standing_combat_air", "set": "heavy", "metric": "drain_per_swing_ratio", "min": 1.10, "max": 1.45},
        ],
    },
    "benchmark_sleep_v1": {
        "id": "sleep_v1",
        "checks": [
            {"label": "sleep_heavy_duration_ratio", "scenario": "sleep_real_neutral_v1", "set": "heavy", "metric": "achieved_sec_ratio", "min": 1.06, "max": 1.15},
        ],
    },
    "benchmark_thermal_v1": {
        "id": "thermal_v1",
        "checks": [
            {"label": "hot_run_heavy_ratio", "scenario": "run_hot", "set": "heavy", "metric": "ratio", "min": 1.70, "max": 2.10},
            {"label": "hot_run_winter_ratio", "scenario": "run_hot", "set": "civilian_winter_layer", "metric": "ratio", "min": 1.25, "max": 1.70},
            {"label": "cold_run_heavy_ratio", "scenario": "run_cold", "set": "heavy", "metric": "ratio", "min": 1.45, "max": 1.85},
            {"label": "cold_run_winter_ratio", "scenario": "run_cold", "set": "civilian_winter_layer", "metric": "ratio", "min": 1.10, "max": 1.40},
        ],
    },
}


def parse_kv(text):
    """Parse key=value pairs from a log line fragment."""
    result = {}
    for m in KV_RE.finditer(text):
        key, val = m.group(1), m.group(2).strip('"')
        if val == "na":
            result[key] = None
            continue
        for cast in (int, float):
            try:
                result[key] = cast(val)
                break
            except (ValueError, OverflowError):
                continue
        else:
            result[key] = val
    return result


def extract_tag_payload(line, tag):
    """Extract everything after [TAG] from a log line."""
    idx = line.find(tag)
    if idx < 0:
        return None
    return line[idx + len(tag):].strip()


def parse_console(path):
    """Single pass: collect all AMS bench log lines grouped by run id."""
    runs = {}  # id -> { start: {}, steps: [], report_lines: [], done: {} }

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if "[ArmorMakesSense]" not in line:
                continue

            if TAG_START in line:
                payload = extract_tag_payload(line, TAG_START)
                kv = parse_kv(payload)
                rid = kv.get("id")
                if rid:
                    runs[rid] = {"start": kv, "steps": [], "report_lines": [], "done": None}

            elif TAG_STEP in line:
                payload = extract_tag_payload(line, TAG_STEP)
                kv = parse_kv(payload)
                rid = kv.get("id")
                if rid and rid in runs:
                    runs[rid]["steps"].append(kv)

            elif TAG_REPORT in line:
                payload = extract_tag_payload(line, TAG_REPORT)
                kv = parse_kv(payload)
                rid = kv.get("id")
                if rid and rid in runs:
                    runs[rid]["report_lines"].append(kv)

            elif TAG_DONE in line:
                payload = extract_tag_payload(line, TAG_DONE)
                kv = parse_kv(payload)
                rid = kv.get("id")
                if rid and rid in runs:
                    runs[rid]["done"] = kv

    return runs


def parse_snapshot(path):
    """Parse a bench snapshot log file (written by AMS bench runner)."""
    runs = {}
    header = {}

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if line.startswith("#") or not line:
                continue

            # Header key=value lines (no tag prefix)
            if "=" in line and not line.startswith("["):
                kv = parse_kv(line)
                header.update(kv)
                continue

            rid = header.get("run_id")
            if not rid:
                continue

            if rid not in runs:
                runs[rid] = {
                    "start": {
                        "id": rid,
                        "preset": header.get("preset"),
                        "label": header.get("label"),
                        "version": header.get("script_version"),
                        "speedReq": header.get("speed"),
                        "repeats": header.get("repeats"),
                        "setsApplied": header.get("sets_applied"),
                        "scenariosApplied": header.get("scenarios_applied"),
                        "mode": header.get("mode"),
                    },
                    "steps": [],
                    "samples": [],
                    "report_lines": [],
                    "done": {"id": rid, "reason": header.get("reason", "unknown")},
                    "header": header.copy(),
                }

            if "AMS_BENCH_STEP_DONE" in line:
                kv = parse_kv(line)
                runs[rid]["steps"].append(kv)
            elif "AMS_BENCHMARK_REPORT" in line:
                kv = parse_kv(line)
                runs[rid]["report_lines"].append(kv)
            elif "AMS_BENCH_SAMPLE" in line:
                kv = parse_kv(line)
                runs[rid]["samples"].append(kv)
            elif "AMS_BENCH_DONE" in line:
                kv = parse_kv(line)
                runs[rid]["done"] = kv

    return runs


def parse_input(path):
    """Parse either console.txt or a snapshot log, or a directory of snapshots."""
    p = Path(path)
    if p.is_dir():
        all_runs = {}
        for f in sorted(p.glob("bench_*.log")):
            all_runs.update(parse_snapshot(f))
        return all_runs
    elif p.name.startswith("bench_") and p.suffix == ".log":
        return parse_snapshot(p)
    else:
        return parse_console(p)


def compute_aggregates(steps):
    """Compute per (set, scenario) aggregates from valid steps."""
    groups = defaultdict(list)
    for s in steps:
        if s.get("gate_rejected") == "true" or s.get("gate_rejected") is True:
            continue
        key = (s.get("set", "?"), s.get("scenario", "?"))
        groups[key].append(s)

    agg = {}
    for (set_name, scenario), valid_steps in groups.items():
        n = len(valid_steps)
        metrics = {}
        for field in METRIC_FIELDS:
            vals = [s[field] for s in valid_steps if s.get(field) is not None and isinstance(s.get(field), (int, float))]
            if not vals:
                metrics[field] = {"mean": None, "stddev": None, "cv": None, "n": 0}
                continue
            mean = sum(vals) / len(vals)
            if len(vals) >= 2:
                var = sum((v - mean) ** 2 for v in vals) / (len(vals) - 1)
                stddev = var ** 0.5
                cv = stddev / abs(mean) if abs(mean) > 1e-9 else None
            else:
                stddev = None
                cv = None
            metrics[field] = {"mean": round(mean, 6), "stddev": round(stddev, 6) if stddev is not None else None, "cv": round(cv, 4) if cv is not None else None, "n": len(vals)}

        # Collect per-step env/thermal snapshot (new v0.3.18 fields)
        env_snapshot = {}
        for field in ENV_FIELDS:
            vals = [s[field] for s in valid_steps if s.get(field) is not None and isinstance(s.get(field), (int, float))]
            if vals:
                env_snapshot[field] = {"mean": round(sum(vals)/len(vals), 4), "min": round(min(vals), 4), "max": round(max(vals), 4)}

        # Combat cooldown stats (new v0.3.18 fields)
        cooldown = {}
        for field in COMBAT_FIELDS:
            vals = [s[field] for s in valid_steps if s.get(field) is not None and isinstance(s.get(field), (int, float))]
            if vals:
                cooldown[field] = {"mean": round(sum(vals)/len(vals), 4)}

        # Derived combat metric: endurance drain per swing (positive magnitude).
        # This decouples cadence effects from fixed-time per-minute comparisons.
        drain_per_swing_vals = []
        for s in valid_steps:
            end_delta = s.get("endDelta")
            swings = s.get("achieved_swings")
            if not isinstance(end_delta, (int, float)) or not isinstance(swings, (int, float)):
                continue
            if swings <= 0:
                continue
            drain_per_swing_vals.append((-end_delta) / swings)

        combat_derived = {}
        if drain_per_swing_vals:
            dps_mean = sum(drain_per_swing_vals) / len(drain_per_swing_vals)
            if len(drain_per_swing_vals) >= 2:
                dps_var = sum((v - dps_mean) ** 2 for v in drain_per_swing_vals) / (len(drain_per_swing_vals) - 1)
                dps_stddev = dps_var ** 0.5
                dps_cv = dps_stddev / abs(dps_mean) if abs(dps_mean) > 1e-9 else None
            else:
                dps_stddev = None
                dps_cv = None
            combat_derived["drain_per_swing"] = {
                "mean": round(dps_mean, 6),
                "stddev": round(dps_stddev, 6) if dps_stddev is not None else None,
                "cv": round(dps_cv, 4) if dps_cv is not None else None,
                "n": len(drain_per_swing_vals),
            }

        entry = {
            "set": set_name,
            "scenario": scenario,
            "valid_steps": n,
            "metrics": metrics,
        }
        if env_snapshot:
            entry["environment"] = env_snapshot
        if cooldown:
            entry["combat_cooldown"] = cooldown
        if combat_derived:
            entry["combat_derived"] = combat_derived
        agg[(set_name, scenario)] = entry

    # Compute marginal deltas (subtract naked baseline)
    scenarios = set(sc for (_, sc) in agg)
    for scenario in scenarios:
        naked_key = ("naked", scenario)
        if naked_key not in agg:
            continue
        naked_agg = agg[naked_key]
        for (set_name, sc), entry in agg.items():
            if sc != scenario:
                continue
            marginals = {}
            for field in ["endDelta", "thirstDelta", "fatigueDelta", "tempDelta", "strainDelta", "achieved_sec"]:
                naked_mean = naked_agg["metrics"].get(field, {}).get("mean")
                set_mean = entry["metrics"].get(field, {}).get("mean")
                if naked_mean is not None and set_mean is not None:
                    marginals[f"marginal_{field}"] = round(set_mean - naked_mean, 6)
                else:
                    marginals[f"marginal_{field}"] = None
            entry["marginals"] = marginals

    return agg


def is_step_rejected(step):
    return step.get("gate_rejected") == "true" or step.get("gate_rejected") is True


def safe_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def mean(values):
    return sum(values) / len(values) if values else None


def stdev_sample(values):
    if len(values) < 2:
        return None
    m = mean(values)
    var = sum((v - m) ** 2 for v in values) / (len(values) - 1)
    return var ** 0.5


def percentile(values, p):
    if not values:
        return None
    vals = sorted(values)
    if len(vals) == 1:
        return vals[0]
    rank = max(0.0, min(1.0, p)) * (len(vals) - 1)
    lo = int(math.floor(rank))
    hi = int(math.ceil(rank))
    if lo == hi:
        return vals[lo]
    frac = rank - lo
    return vals[lo] + ((vals[hi] - vals[lo]) * frac)


def parse_validity_ratio(summary):
    validity = summary.get("validity", "0/0")
    parts = str(validity).split("/")
    if len(parts) != 2:
        return 0.0, 0, 0
    try:
        valid = int(parts[0])
        total = int(parts[1])
    except ValueError:
        return 0.0, 0, 0
    ratio = (valid / total) if total > 0 else 0.0
    return ratio, valid, total


def compute_quality(steps):
    total = len(steps)
    rejected = [s for s in steps if is_step_rejected(s)]
    valid = [s for s in steps if not is_step_rejected(s)]

    gate_counts = defaultdict(int)
    exit_counts = defaultdict(int)
    stall_reason_counts = defaultdict(int)
    for s in steps:
        gate_counts[str(s.get("gate_failed", "none"))] += 1
        exit_counts[str(s.get("exit_reason", "unknown"))] += 1
        stall_reason = str(s.get("stall_reason", "none"))
        stall_reason_counts[stall_reason] += 1

    numeric = {}
    for field in QUALITY_NUMERIC_FIELDS:
        vals = [safe_float(s.get(field)) for s in steps]
        vals = [v for v in vals if v is not None]
        if not vals:
            continue
        numeric[field] = {
            "mean": round(mean(vals), 4),
            "p95": round(percentile(vals, 0.95), 4),
            "max": round(max(vals), 4),
        }

    overrun_vals = []
    for s in steps:
        req = safe_float(s.get("requested_sec"))
        ach = safe_float(s.get("achieved_sec"))
        if req is None or ach is None:
            continue
        overrun_vals.append(ach - req)
    timing = {}
    if overrun_vals:
        timing = {
            "overrun_mean_sec": round(mean(overrun_vals), 4),
            "overrun_p95_sec": round(percentile(overrun_vals, 0.95), 4),
            "overrun_max_sec": round(max(overrun_vals), 4),
        }

    by_scenario = {}
    for scenario in sorted({str(s.get("scenario", "?")) for s in steps}):
        sub = [s for s in steps if str(s.get("scenario", "?")) == scenario]
        r = [s for s in sub if is_step_rejected(s)]
        by_scenario[scenario] = {
            "steps": len(sub),
            "valid_steps": len(sub) - len(r),
            "rejected_steps": len(r),
        }

    return {
        "steps": total,
        "valid_steps": len(valid),
        "rejected_steps": len(rejected),
        "validity_rate": round((len(valid) / total), 4) if total else 0.0,
        "gate_fail_counts": dict(sorted(gate_counts.items(), key=lambda kv: (-kv[1], kv[0]))),
        "exit_reason_counts": dict(sorted(exit_counts.items(), key=lambda kv: (-kv[1], kv[0]))),
        "stall_reason_counts": dict(sorted(stall_reason_counts.items(), key=lambda kv: (-kv[1], kv[0]))),
        "timing": timing,
        "signals": numeric,
        "by_scenario": by_scenario,
    }


def aggregate_lookup(summary):
    lookup = {}
    for entry in summary.get("aggregates", []):
        lookup[(entry.get("set"), entry.get("scenario"))] = entry
    return lookup


def _metric_diff_score(row):
    score = 0.0
    for field in CORE_DIFF_FIELDS:
        delta = row.get(f"{field}_delta")
        if isinstance(delta, (int, float)):
            score = max(score, abs(delta))
    return score


def compare_runs(summary_a, summary_b, max_diffs=None):
    ratio_a, valid_a, total_a = parse_validity_ratio(summary_a)
    ratio_b, valid_b, total_b = parse_validity_ratio(summary_b)
    agg_a = aggregate_lookup(summary_a)
    agg_b = aggregate_lookup(summary_b)
    keys = sorted(set(agg_a.keys()) | set(agg_b.keys()), key=lambda x: (str(x[1]), str(x[0])))

    metric_diffs = []
    for key in keys:
        a = agg_a.get(key)
        b = agg_b.get(key)
        set_name, scenario = key
        row = {"set": set_name, "scenario": scenario}
        for field in CORE_DIFF_FIELDS:
            av = a and a.get("metrics", {}).get(field, {}).get("mean")
            bv = b and b.get("metrics", {}).get(field, {}).get("mean")
            row[f"{field}_a"] = av
            row[f"{field}_b"] = bv
            row[f"{field}_delta"] = round((bv - av), 6) if av is not None and bv is not None else None
        metric_diffs.append(row)

    metric_diffs = sorted(
        metric_diffs,
        key=lambda row: (-_metric_diff_score(row), str(row.get("scenario")), str(row.get("set"))),
    )
    total_diffs = len(metric_diffs)
    if isinstance(max_diffs, int) and max_diffs > 0:
        metric_diffs = metric_diffs[:max_diffs]

    return {
        "run_a": {
            "run_id": summary_a.get("run_id"),
            "label": summary_a.get("label"),
            "validity": f"{valid_a}/{total_a}",
            "validity_rate": round(ratio_a, 4),
        },
        "run_b": {
            "run_id": summary_b.get("run_id"),
            "label": summary_b.get("label"),
            "validity": f"{valid_b}/{total_b}",
            "validity_rate": round(ratio_b, 4),
        },
        "validity_rate_delta": round(ratio_b - ratio_a, 4),
        "metric_diffs_total": total_diffs,
        "metric_diffs_returned": len(metric_diffs),
        "metric_diffs": metric_diffs,
    }


def flatten_steps(summary):
    rows = []
    for step in summary.get("raw_steps", []):
        row = {
            "run_id": summary.get("run_id"),
            "label": summary.get("label"),
            "preset": summary.get("preset"),
            "version": summary.get("version"),
        }
        for k, v in step.items():
            row[str(k)] = v
        rows.append(row)
    return rows


def export_csv(path, summaries):
    rows = []
    for s in summaries:
        rows.extend(flatten_steps(s))
    if not rows:
        return 0
    fieldnames = sorted({k for r in rows for k in r.keys()})
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)
    return len(rows)


def save_json(path, payload):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, default=str)


def apply_step_filters(run_data, args):
    steps = run_data["steps"]
    if args.scenario:
        allowed = {s.strip() for s in args.scenario.split(",") if s.strip()}
        steps = [s for s in steps if str(s.get("scenario")) in allowed]
    if args.set_id:
        allowed = {s.strip() for s in args.set_id.split(",") if s.strip()}
        steps = [s for s in steps if str(s.get("set")) in allowed]
    clone = {
        "start": dict(run_data["start"]),
        "steps": steps,
        "report_lines": list(run_data.get("report_lines", [])),
        "done": dict(run_data["done"]) if run_data.get("done") else None,
    }
    return clone


def build_run_summary(run_data, include_quality=False, include_aggregates=False):
    """Build a compact summary for one run."""
    start = run_data["start"]
    done = run_data["done"]
    steps = run_data["steps"]

    total = len(steps)
    valid = sum(1 for s in steps if s.get("gate_rejected") != "true" and s.get("gate_rejected") is not True)
    rejected = [
        f"{s.get('set')}:{s.get('scenario')}:r{s.get('repeat_index')}"
        for s in steps
        if s.get("gate_rejected") == "true" or s.get("gate_rejected") is True
    ]

    summary = {
        "run_id": start.get("id"),
        "preset": start.get("preset"),
        "label": start.get("label"),
        "version": start.get("version"),
        "sets_applied": start.get("setsApplied"),
        "scenarios_applied": start.get("scenariosApplied"),
        "repeats": start.get("repeats"),
        "speed": start.get("speedReq"),
        "completed": done is not None,
        "exit_reason": done.get("reason") if done else None,
        "validity": f"{valid}/{total}",
        "rejected": rejected,
    }
    if include_aggregates:
        agg = compute_aggregates(steps)
        summary["aggregates"] = sorted(agg.values(), key=lambda x: (x["scenario"], x["set"]))
    if include_quality:
        summary["quality"] = compute_quality(steps)

    return summary


def filter_runs(runs, args):
    """Filter runs based on CLI arguments."""
    completed = {rid: r for rid, r in runs.items() if r["done"] is not None}

    if args.run_id:
        if args.run_id in completed:
            return {args.run_id: completed[args.run_id]}
        return {}

    if args.label:
        return {rid: r for rid, r in completed.items() if r["start"].get("label") == args.label}

    if args.last:
        sorted_ids = sorted(completed.keys())
        selected = sorted_ids[-args.last:]
        return {rid: completed[rid] for rid in selected}

    return completed


def sort_summaries(summaries, key):
    if not key or key == "run_id":
        return sorted(summaries, key=lambda s: str(s.get("run_id")))
    if key == "validity_desc":
        return sorted(summaries, key=lambda s: parse_validity_ratio(s)[0], reverse=True)
    if key == "validity_asc":
        return sorted(summaries, key=lambda s: parse_validity_ratio(s)[0])
    if key == "label":
        return sorted(summaries, key=lambda s: str(s.get("label") or ""))
    return summaries


def load_baseline(path):
    p = Path(path)
    if not p.exists():
        return None
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)


def check_baseline(current, baseline, tol_validity=0.03):
    # Minimal, robust gate for CI-style usage.
    if not current or not baseline:
        return {"ok": False, "error": "missing current or baseline payload"}

    cur = current[0]
    base = baseline[0] if isinstance(baseline, list) else baseline
    cur_ratio, cur_valid, cur_total = parse_validity_ratio(cur)
    base_ratio, base_valid, base_total = parse_validity_ratio(base)
    delta = cur_ratio - base_ratio
    ok = delta >= -abs(tol_validity)

    return {
        "ok": ok,
        "current": {
            "run_id": cur.get("run_id"),
            "label": cur.get("label"),
            "validity": f"{cur_valid}/{cur_total}",
            "validity_rate": round(cur_ratio, 4),
        },
        "baseline": {
            "run_id": base.get("run_id"),
            "label": base.get("label"),
            "validity": f"{base_valid}/{base_total}",
            "validity_rate": round(base_ratio, 4),
        },
        "validity_rate_delta": round(delta, 4),
        "tolerance_validity_drop": abs(tol_validity),
    }


def _status_from_band(value, min_v, max_v, warn_margin):
    if value is None:
        return "fail"
    if min_v <= value <= max_v:
        return "pass"
    if (min_v - warn_margin) <= value <= (max_v + warn_margin):
        return "warn"
    return "fail"


def _lookup_aggregate(summary):
    return {(a.get("scenario"), a.get("set")): a for a in summary.get("aggregates", [])}


def _naked_metric(agg_lookup, scenario, metric):
    naked = agg_lookup.get((scenario, "naked"))
    if not naked:
        return None
    if metric in ("ratio", "achieved_sec_ratio"):
        key = "endDelta" if metric == "ratio" else "achieved_sec"
        return naked.get("metrics", {}).get(key, {}).get("mean")
    if metric == "drain_per_swing_ratio":
        return naked.get("combat_derived", {}).get("drain_per_swing", {}).get("mean")
    return None


def _resolve_scenario_key(agg_lookup, scenario):
    if scenario is None:
        return None
    scenario = str(scenario)
    scenario_names = {str(k[0]) for k in agg_lookup.keys()}
    if scenario in scenario_names:
        return scenario
    for name in scenario_names:
        short = name.replace("native_treadmill_", "").replace("native_standing_", "")
        if short == scenario or name.endswith("_" + scenario):
            return name
    return scenario


def _resolve_metric_value(agg_lookup, scenario, set_name, metric):
    scenario = _resolve_scenario_key(agg_lookup, scenario)
    entry = agg_lookup.get((scenario, set_name))
    if not entry:
        return None
    if metric == "ratio":
        set_val = entry.get("metrics", {}).get("endDelta", {}).get("mean")
        base_val = _naked_metric(agg_lookup, scenario, metric)
        if isinstance(set_val, (int, float)) and isinstance(base_val, (int, float)) and abs(base_val) > 1e-9:
            return set_val / base_val
        return None
    if metric == "achieved_sec_ratio":
        set_val = entry.get("metrics", {}).get("achieved_sec", {}).get("mean")
        base_val = _naked_metric(agg_lookup, scenario, metric)
        if isinstance(set_val, (int, float)) and isinstance(base_val, (int, float)) and abs(base_val) > 1e-9:
            return set_val / base_val
        return None
    if metric == "drain_per_swing_ratio":
        set_val = entry.get("combat_derived", {}).get("drain_per_swing", {}).get("mean")
        base_val = _naked_metric(agg_lookup, scenario, metric)
        if isinstance(set_val, (int, float)) and isinstance(base_val, (int, float)) and abs(base_val) > 1e-9:
            return set_val / base_val
        return None
    return entry.get("metrics", {}).get(metric, {}).get("mean")


def load_target_spec(arg_value, summary):
    if arg_value == "auto":
        preset = str(summary.get("preset") or "")
        return DEFAULT_TARGET_BANDS.get(preset)
    p = Path(arg_value)
    if not p.exists():
        return None
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)


def check_targets(summaries, target_spec, warn_margin=0.03):
    if not summaries:
        return {"ok": False, "error": "no summaries to check"}
    if not target_spec or not isinstance(target_spec, dict):
        return {"ok": False, "error": "missing or invalid target spec"}

    checks = target_spec.get("checks") or []
    per_run = []
    any_fail = False
    any_warn = False

    for summary in summaries:
        agg_lookup = _lookup_aggregate(summary)
        results = []
        for c in checks:
            scenario = c.get("scenario")
            set_name = c.get("set")
            metric = c.get("metric", "ratio")
            min_v = safe_float(c.get("min"))
            max_v = safe_float(c.get("max"))
            value = _resolve_metric_value(agg_lookup, scenario, set_name, metric)
            status = "fail"
            if min_v is not None and max_v is not None and min_v <= max_v:
                status = _status_from_band(value, min_v, max_v, abs(warn_margin))
            if status == "fail":
                any_fail = True
            elif status == "warn":
                any_warn = True
            results.append({
                "label": c.get("label") or f"{scenario}:{set_name}:{metric}",
                "scenario": scenario,
                "set": set_name,
                "metric": metric,
                "target_min": min_v,
                "target_max": max_v,
                "value": round(value, 6) if isinstance(value, (int, float)) else None,
                "status": status,
            })

        overall = "fail" if any(r["status"] == "fail" for r in results) else ("warn" if any(r["status"] == "warn" for r in results) else "pass")
        per_run.append({
            "run_id": summary.get("run_id"),
            "label": summary.get("label"),
            "preset": summary.get("preset"),
            "version": summary.get("version"),
            "overall": overall,
            "checks": results,
        })

    overall = "fail" if any_fail else ("warn" if any_warn else "pass")
    return {
        "ok": overall != "fail",
        "overall": overall,
        "target_set": target_spec.get("id") or "custom",
        "warn_margin": abs(warn_margin),
        "runs": per_run,
    }


def format_brief(summaries):
    """Compact text table output. One table per scenario, ratios vs naked."""
    lines = []
    for summary in summaries:
        aggs = summary.get("aggregates", [])
        if not aggs:
            lines.append(f"Run {summary.get('run_id')}: no aggregates (use --full to generate)")
            continue

        lines.append(f"Run: {summary.get('run_id')}  Version: {summary.get('version')}  "
                      f"Preset: {summary.get('preset')}  Validity: {summary.get('validity')}  "
                      f"Repeats: {summary.get('repeats')}  Speed: {summary.get('speed')}")
        rejected = summary.get("rejected", [])
        if rejected:
            lines.append(f"Rejected: {', '.join(rejected)}")
        lines.append("")

        by_scenario = defaultdict(list)
        for a in aggs:
            by_scenario[a["scenario"]].append(a)

        for scenario in sorted(by_scenario.keys()):
            entries = by_scenario[scenario]
            short = scenario.replace("native_treadmill_", "").replace("native_standing_", "")
            lines.append(f"=== {short} ===")
            is_combat = "combat" in scenario
            naked_end = None
            naked_drain_per_swing = None
            for e in entries:
                if e["set"] == "naked":
                    naked_end = e["metrics"].get("endDelta", {}).get("mean")
                    naked_drain_per_swing = (
                        e.get("combat_derived", {})
                         .get("drain_per_swing", {})
                         .get("mean")
                    )
                    break

            if is_combat:
                hdr = (
                    f"{'Set':<24s} {'dSwing':>8s} {'dSwCV':>6s} {'dSwRat':>7s} "
                    f"{'swPM':>7s} {'endD':>8s} {'ratio':>7s} {'n':>3s}"
                )
            else:
                hdr = f"{'Set':<24s} {'endD':>8s} {'CV':>6s} {'margEnd':>8s} {'ratio':>7s} {'thirst':>8s} {'temp':>8s} {'n':>3s}"
            lines.append(hdr)
            lines.append("-" * len(hdr))

            if is_combat:
                sorted_entries = sorted(
                    entries,
                    key=lambda e: -(
                        e.get("combat_derived", {})
                         .get("drain_per_swing", {})
                         .get("mean")
                        or 0
                    ),
                )
            else:
                sorted_entries = sorted(entries, key=lambda e: (e["metrics"].get("endDelta", {}).get("mean") or 0))
            for e in sorted_entries:
                s = e["set"]
                m = e["metrics"]
                end_m = m.get("endDelta", {}).get("mean")
                end_cv = m.get("endDelta", {}).get("cv")
                thirst_m = m.get("thirstDelta", {}).get("mean")
                temp_m = m.get("tempDelta", {}).get("mean")
                n = m.get("endDelta", {}).get("n", 0)
                marg = e.get("marginals", {}).get("marginal_endDelta")

                end_s = f"{end_m:8.4f}" if end_m is not None else "      na"
                cv_s = f"{end_cv:6.4f}" if end_cv is not None else "    na"
                marg_s = f"{marg:8.4f}" if marg is not None else "      na"
                thirst_s = f"{thirst_m:8.4f}" if thirst_m is not None else "      na"
                temp_s = f"{temp_m:8.4f}" if temp_m is not None else "      na"

                if naked_end is not None and end_m is not None and naked_end != 0:
                    ratio = end_m / naked_end
                    ratio_s = f"{ratio:6.2f}x"
                else:
                    ratio_s = "     na"

                if is_combat:
                    dsw_mean = (
                        e.get("combat_derived", {})
                         .get("drain_per_swing", {})
                         .get("mean")
                    )
                    dsw_cv = (
                        e.get("combat_derived", {})
                         .get("drain_per_swing", {})
                         .get("cv")
                    )
                    swpm = m.get("swings_per_minute", {}).get("mean")
                    dsw_s = f"{dsw_mean:8.4f}" if dsw_mean is not None else "      na"
                    dsw_cv_s = f"{dsw_cv:6.4f}" if dsw_cv is not None else "    na"
                    swpm_s = f"{swpm:7.3f}" if swpm is not None else "     na"
                    if naked_drain_per_swing is not None and dsw_mean is not None and naked_drain_per_swing > 0:
                        dsw_ratio_s = f"{(dsw_mean / naked_drain_per_swing):6.2f}x"
                    else:
                        dsw_ratio_s = "     na"
                    lines.append(f"{s:<24s} {dsw_s} {dsw_cv_s} {dsw_ratio_s} {swpm_s} {end_s} {ratio_s} {n:3d}")
                else:
                    lines.append(f"{s:<24s} {end_s} {cv_s} {marg_s} {ratio_s} {thirst_s} {temp_s} {n:3d}")
            lines.append("")
    return "\n".join(lines)


def format_validity(summaries):
    """Show rejected steps grouped by rejection reason."""
    lines = []
    for summary in summaries:
        lines.append(f"Run: {summary.get('run_id')}  Version: {summary.get('version')}  Validity: {summary.get('validity')}")
        rejected = summary.get("rejected", [])
        if not rejected:
            lines.append("  All steps valid.")
            lines.append("")
            continue

        raw_steps = summary.get("raw_steps", [])
        if not raw_steps:
            lines.append(f"  Rejected ({len(rejected)}): {', '.join(rejected)}")
            lines.append("  (use with --full for detailed rejection reasons)")
            lines.append("")
            continue

        rej_steps = [s for s in raw_steps if is_step_rejected(s)]
        by_reason = defaultdict(list)
        for s in rej_steps:
            gate = str(s.get("gate_failed", "unknown"))
            exit_r = str(s.get("exit_reason", "unknown"))
            reason = f"gate={gate}" if gate != "none" else f"exit={exit_r}"
            label = f"{s.get('set')}:{s.get('scenario')}:r{s.get('repeat_index')}"
            by_reason[reason].append((label, s))

        for reason, items in sorted(by_reason.items()):
            lines.append(f"  {reason} ({len(items)} steps):")
            for label, s in items:
                uptime = s.get("movement_uptime", "na")
                achieved = s.get("achieved_sec", "na")
                lines.append(f"    {label}  uptime={uptime}  achieved_sec={achieved}")
        lines.append("")
    return "\n".join(lines)


def _group_valid_steps(summary):
    grouped = defaultdict(list)
    for step in summary.get("raw_steps", []):
        if is_step_rejected(step):
            continue
        grouped[(str(step.get("scenario", "?")), str(step.get("set", "?")))].append(step)
    return grouped


def _mean_numeric(rows, key):
    vals = [safe_float(r.get(key)) for r in rows]
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    return sum(vals) / len(vals)


def _mean_numeric_any(rows, keys):
    for key in keys:
        value = _mean_numeric(rows, key)
        if value is not None:
            return value
    return None


def _fmt(value, digits=4):
    if value is None:
        return "na"
    return f"{value:.{digits}f}"


def format_diag_load(summaries):
    lines = []
    for summary in summaries:
        lines.append(
            f"Run: {summary.get('run_id')}  Version: {summary.get('version')}  "
            f"Preset: {summary.get('preset')}  Validity: {summary.get('validity')}"
        )
        grouped = _group_valid_steps(summary)
        if not grouped:
            lines.append("  no valid steps")
            lines.append("")
            continue
        hdr = (
            f"{'Scenario':<24s} {'Set':<20s} {'eff':>8s} {'norm':>7s} {'mass':>7s} "
            f"{'thmC':>7s} {'brC':>7s} {'scale':>7s} {'hot':>7s} {'bodyT':>7s} {'dom':<8s}"
        )
        lines.append(hdr)
        lines.append("-" * len(hdr))
        for (scenario, set_name) in sorted(grouped.keys()):
            rows = grouped[(scenario, set_name)]
            eff = _mean_numeric(rows, "eff_load")
            norm = _mean_numeric(rows, "load_norm_runtime")
            mass = _mean_numeric(rows, "mass_load_runtime")
            thm_c = _mean_numeric(rows, "thermal_contribution")
            br_c = _mean_numeric(rows, "breathing_contribution")
            scale = _mean_numeric(rows, "thermal_scale")
            hot = _mean_numeric(rows, "thermal_hot_strain")
            body_t = _mean_numeric(rows, "body_temp_runtime")
            dominance = {
                "mass": abs(mass or 0),
                "thermal": abs(thm_c or 0),
                "breathing": abs(br_c or 0),
                "muscle": abs(_mean_numeric(rows, "muscle_contribution") or 0),
                "recovery": abs(_mean_numeric(rows, "recovery_contribution") or 0),
            }
            dom = max(dominance, key=dominance.get) if any(v > 0 for v in dominance.values()) else "none"
            lines.append(
                f"{scenario:<24.24s} {set_name:<20.20s} {_fmt(eff):>8s} {_fmt(norm, 5):>7s} "
                f"{_fmt(mass):>7s} {_fmt(thm_c):>7s} {_fmt(br_c):>7s} {_fmt(scale):>7s} "
                f"{_fmt(hot):>7s} {_fmt(body_t):>7s} {dom:<8s}"
            )
        lines.append("")
    return "\n".join(lines)


def format_diag_weight(summaries):
    lines = []
    for summary in summaries:
        lines.append(
            f"Run: {summary.get('run_id')}  Version: {summary.get('version')}  "
            f"Preset: {summary.get('preset')}  Validity: {summary.get('validity')}"
        )
        grouped = _group_valid_steps(summary)
        if not grouped:
            lines.append("  no valid steps")
            lines.append("")
            continue
        hdr = (
            f"{'Scenario':<24s} {'Set':<20s} {'usedW':>8s} {'eqW':>8s} {'actW':>8s} "
            f"{'fallbackW':>9s} {'fallback':>9s} {'actualSrc':>9s} {'fallbackSrc':>11s}"
        )
        lines.append(hdr)
        lines.append("-" * len(hdr))
        for (scenario, set_name) in sorted(grouped.keys()):
            rows = grouped[(scenario, set_name)]
            lines.append(
                f"{scenario:<24.24s} {set_name:<20.20s} "
                f"{_fmt(_mean_numeric(rows, 'weight_used_total')):>8s} "
                f"{_fmt(_mean_numeric(rows, 'equipped_weight_total')):>8s} "
                f"{_fmt(_mean_numeric(rows, 'actual_weight_total')):>8s} "
                f"{_fmt(_mean_numeric_any(rows, ('fallback_weight_total', 'legacy_weight_total'))):>9s} "
                f"{_fmt(_mean_numeric(rows, 'fallback_weight_count'), 2):>9s} "
                f"{_fmt(_mean_numeric(rows, 'source_actual_count'), 2):>9s} "
                f"{_fmt(_mean_numeric_any(rows, ('source_fallback_count', 'source_legacy_count')), 2):>11s}"
            )
        lines.append("")
    return "\n".join(lines)


def format_diag_order(summaries):
    lines = []
    for summary in summaries:
        lines.append(
            f"Run: {summary.get('run_id')}  Version: {summary.get('version')}  "
            f"Preset: {summary.get('preset')}  Validity: {summary.get('validity')}"
        )
        grouped = _group_valid_steps(summary)
        if not grouped:
            lines.append("  no valid steps")
            lines.append("")
            continue
        hdr = (
            f"{'Scenario':<24s} {'Set':<20s} {'preAMS':>9s} {'postAMS':>9s} "
            f"{'natDelta':>9s} {'applied':>9s}"
        )
        lines.append(hdr)
        lines.append("-" * len(hdr))
        for (scenario, set_name) in sorted(grouped.keys()):
            rows = grouped[(scenario, set_name)]
            lines.append(
                f"{scenario:<24.24s} {set_name:<20.20s} "
                f"{_fmt(_mean_numeric(rows, 'end_before_ams'), 6):>9s} "
                f"{_fmt(_mean_numeric(rows, 'end_after_ams'), 6):>9s} "
                f"{_fmt(_mean_numeric(rows, 'end_natural_delta'), 6):>9s} "
                f"{_fmt(_mean_numeric(rows, 'end_applied_delta'), 6):>9s}"
            )
        lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Parse AMS benchmark data from console.txt")
    parser.add_argument("console", help="Path to console.txt")
    parser.add_argument("--run-id", help="Filter to specific run ID")
    parser.add_argument("--last", type=int, help="Show only last N completed runs")
    parser.add_argument("--label", help="Filter by label")
    parser.add_argument("--scenario", help="Comma-separated scenario filter (step-level)")
    parser.add_argument("--set", dest="set_id", help="Comma-separated set filter (step-level)")
    parser.add_argument("--sort", choices=["run_id", "validity_desc", "validity_asc", "label"], default="run_id")
    parser.add_argument("--quality", action="store_true", help="Include quality diagnostics in output")
    parser.add_argument("--compare", nargs=2, metavar=("RUN_A", "RUN_B"), help="Compare two run IDs")
    parser.add_argument("--max-diffs", type=int, default=25, help="Max metric diff rows to return for --compare (default: 25)")
    parser.add_argument("--export-csv", help="Export flattened step rows to CSV")
    parser.add_argument("--export-json", help="Write output JSON to path in addition to stdout")
    parser.add_argument("--save-baseline", help="Save current output as baseline JSON")
    parser.add_argument("--check-baseline", help="Check current output against baseline JSON")
    parser.add_argument("--tol-validity-drop", type=float, default=0.03, help="Allowed validity-rate drop for baseline check")
    parser.add_argument("--check-targets", nargs="?", const="auto", help="Check design target bands. Use 'auto' (default) or provide target JSON path.")
    parser.add_argument("--target-warn-margin", type=float, default=0.03, help="Warn margin outside target bands before fail.")
    parser.add_argument("--full", action="store_true", help="Include aggregates and raw step payloads")
    parser.add_argument("--brief", action="store_true", help="Compact text tables with ratios vs naked (LLM-friendly)")
    parser.add_argument("--validity", action="store_true", help="Show rejected steps with reasons")
    parser.add_argument("--diag-load", action="store_true", help="Show effective-load decomposition diagnostics")
    parser.add_argument("--diag-weight", action="store_true", help="Show runtime weight-source diagnostics")
    parser.add_argument("--diag-order", action="store_true", help="Show endurance ordering diagnostics")
    parser.add_argument("--compact", action="store_true", help="Deprecated alias for concise mode (now default)")
    args = parser.parse_args()

    path = Path(args.console)
    if not path.exists():
        print(f"Error: {path} not found", file=sys.stderr)
        sys.exit(1)

    runs = parse_input(path)
    filtered = filter_runs(runs, args)

    if not filtered:
        print(json.dumps({"error": "no matching runs found", "total_runs_in_file": len(runs)}))
        sys.exit(0)

    if args.compare:
        run_a, run_b = args.compare
        completed = {rid: r for rid, r in runs.items() if r["done"] is not None}
        if run_a not in completed or run_b not in completed:
            print(json.dumps({"error": "compare run id not found", "run_a": run_a, "run_b": run_b}))
            sys.exit(0)
        sum_a = build_run_summary(
            apply_step_filters(completed[run_a], args),
            include_quality=args.quality,
            include_aggregates=True,
        )
        sum_b = build_run_summary(
            apply_step_filters(completed[run_b], args),
            include_quality=args.quality,
            include_aggregates=True,
        )
        payload = compare_runs(sum_a, sum_b, max_diffs=args.max_diffs)
        if args.export_json:
            save_json(args.export_json, payload)
        print(json.dumps(payload, indent=2, default=str))
        return

    need_aggregates = args.full or args.brief or bool(args.check_targets)
    need_raw = args.full or args.validity or args.diag_load or args.diag_weight or args.diag_order

    output = []
    for rid in sorted(filtered.keys()):
        run = apply_step_filters(filtered[rid], args)
        summary = build_run_summary(run, include_quality=args.quality, include_aggregates=need_aggregates)
        if need_raw:
            summary["raw_steps"] = run["steps"]
        output.append(summary)

    output = sort_summaries(output, args.sort)

    if args.export_csv:
        # CSV export needs raw steps even in compact mode.
        csv_payload = []
        for rid in sorted(filtered.keys()):
            run = apply_step_filters(filtered[rid], args)
            s = build_run_summary(run, include_quality=args.quality, include_aggregates=True)
            s["raw_steps"] = run["steps"]
            csv_payload.append(s)
        rows_written = export_csv(args.export_csv, csv_payload)
        if args.full:
            for s in output:
                s.setdefault("_export", {})["csv_rows"] = rows_written

    if args.save_baseline:
        save_json(args.save_baseline, output)

    if args.check_baseline:
        baseline = load_baseline(args.check_baseline)
        payload = check_baseline(output, baseline, tol_validity=args.tol_validity_drop)
        if args.export_json:
            save_json(args.export_json, payload)
        print(json.dumps(payload, indent=2, default=str))
        return

    if args.check_targets:
        target_spec = load_target_spec(args.check_targets, output[0] if output else {})
        payload = check_targets(output, target_spec, warn_margin=args.target_warn_margin)
        if args.export_json:
            save_json(args.export_json, payload)
        print(json.dumps(payload, indent=2, default=str))
        return

    if args.export_json:
        save_json(args.export_json, output)

    if args.brief:
        print(format_brief(output))
        return

    if args.validity:
        print(format_validity(output))
        return
    if args.diag_load:
        print(format_diag_load(output))
        return
    if args.diag_weight:
        print(format_diag_weight(output))
        return
    if args.diag_order:
        print(format_diag_order(output))
        return

    print(json.dumps(output, indent=2, default=str))


if __name__ == "__main__":
    main()
