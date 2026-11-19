"""Validate and summarize the four separately run S0 CPU replays in A/B/B/A order."""
import argparse
import json
import math
import statistics
from pathlib import Path


def summarize(values):
    ordered = sorted(values)
    return {
        "samples": len(values),
        "mean_ms": statistics.fmean(values) / 1000,
        "p95_ms": ordered[math.ceil(len(values) * 0.95) - 1] / 1000,
        "p99_ms": ordered[math.ceil(len(values) * 0.99) - 1] / 1000,
        "max_ms": ordered[-1] / 1000,
    }


def analyze(paths):
    runs = [json.loads(path.read_text(encoding="utf-8-sig")) for path in paths]
    errors = []
    if [run.get("mode") for run in runs] != ["reference", "candidate", "candidate", "reference"]:
        errors.append("Files must be four independent reference/candidate/candidate/reference runs")
    for index, run in enumerate(runs):
        if not run.get("passed") or run.get("revision") != 2:
            errors.append(f"Run {index} failed or has wrong revision")
        if run.get("sources_before") != run.get("sources_after") or run.get("sources_before") != runs[0].get("sources_before"):
            errors.append(f"Run {index} has differing source manifests")
        for field in ["terrain_hash", "initial_state_hash", "final_state_hash", "warmup_steps", "step_seconds"]:
            if run.get(field) != runs[0].get(field):
                errors.append(f"Run {index} differs in {field}")
        if run.get("steps_requested") != 450 or [row.get("step") for row in run.get("steps", [])] != list(range(1, 451)):
            errors.append(f"Run {index} does not contain the fixed 450-step trace")
        if run.get("state_hashing_inside_timed_steps") is not False:
            errors.append(f"Run {index} does not exclude correctness observations from timed steps")
        if run.get("warmup_steps") != 30 or any(row.get("warmup") != (row.get("step", 0) <= 30) for row in run.get("steps", [])):
            errors.append(f"Run {index} has a differing warmup")
    result = {"passed": not errors, "errors": errors, "input_files": [str(path.resolve()) for path in paths],
              "scope": "450 original action steps, first 30 excluded only from warm statistics; CPU replay, not FPS",
              "runs": [], "pooled_warm": {}}
    if errors:
        return result
    for path, run in zip(paths, runs):
        result["runs"].append({"file": str(path), "mode": run["mode"],
                               "all_steps": {field: summarize([row[field] for row in run["steps"]]) for field in ["action_usec", "coordinator_usec"]},
                               "warm_steps": {field: summarize([row[field] for row in run["steps"] if not row["warmup"]]) for field in ["action_usec", "coordinator_usec"]}})
    for mode in ["reference", "candidate"]:
        result["pooled_warm"][mode] = {field: summarize([row[field] for run in runs if run["mode"] == mode for row in run["steps"] if not row["warmup"]]) for field in ["action_usec", "coordinator_usec"]}
    result["mean_saving_ms"] = {field: result["pooled_warm"]["reference"][field]["mean_ms"] - result["pooled_warm"]["candidate"][field]["mean_ms"] for field in ["action_usec", "coordinator_usec"]}
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", nargs=4, type=Path, metavar="REPLAY_JSON")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = analyze(args.runs)
    rendered = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    raise SystemExit(0 if result["passed"] else 1)
