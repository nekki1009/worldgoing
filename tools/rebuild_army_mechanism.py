"""Serial original non-GPU producers. Default is a read-only plan, never PASS stamping."""
import argparse
import json
import re
import shutil
import subprocess
import time
import uuid
from pathlib import Path

ROOT = "output/site_army_5k_tail_close_20260927/main_delivery_oracle"
SCRIPT = "res://scripts/tests/"
GPU = {"pixel_occlusion", "render_5k_mechanism"}
LABELS = ["hot_store_smoke", "hot_prepare_smoke", "hot_lifecycle_smoke",
          "hot_projection_smoke", "retained_batch_smoke", "hot_retained_integration",
          "pixel_occlusion", "native_exact_oracle", "oracle_stream_selfcheck",
          "render_5k_mechanism", "full_oracle"]


def stage(name, script, outputs, args=(), hashes=None):
    return dict(id=name, script=SCRIPT + script, mode="headless",
                args=["--script", SCRIPT + script] + (["--", *args] if args else []),
                outputs=outputs, hashes=hashes or {})


def stages():
    army = "scripts/terrain_lab/terrain_army.gd"
    batch = "scripts/terrain_lab/terrain_army_batch_view.gd"
    cpp = "native/army_idle/army_idle.cpp"
    dll = "native/army_idle/bin/army_idle.windows.x86_64.dll"
    result = [stage("manifest_before", "site_army_mechanism_test.gd",
                    ["source_manifest.json"], ["--manifest-only"])]
    for name, fixture, paths in [
        ("hot_store_smoke", "site_army_hot_store_native_test.gd", {"cpp_sha256": cpp, "dll_sha256": dll}),
        ("hot_prepare_smoke", "site_army_hot_prepare_test.gd", {"army_sha256": army, "cpp_sha256": cpp, "dll_sha256": dll}),
        ("hot_lifecycle_smoke", "site_army_hot_lifecycle_test.gd", {"army_sha256": army, "cpp_sha256": cpp, "dll_sha256": dll}),
        ("hot_projection_smoke", "site_army_hot_projection_native_test.gd", {"cpp_sha256": cpp, "dll_sha256": dll, "batch_sha256": batch}),
    ]:
        result.append(stage(name, fixture, [name + ".json"], hashes={**paths, "test_sha256": "scripts/tests/" + fixture}))
    result += [
        stage("native_exact_oracle", "site_army_native_exact_oracle_test.gd", ["native_exact_oracle_smoke.json"],
              hashes={"source_sha256/cpp": cpp, "source_sha256/dll": dll, "source_sha256/test": "scripts/tests/site_army_native_exact_oracle_test.gd"}),
        stage("oracle_stream_selfcheck", "site_army_oracle_stream_test.gd", ["oracle_stream_selfcheck.json"], ["--oracle-role=selfcheck"],
              {"fixture_sha256": "scripts/tests/site_army_oracle_stream_test.gd"}),
        stage("retained_batch_smoke", "site_army_retained_batch_test.gd", ["retained_batch_smoke.json"], hashes={
            "sources/army": army, "sources/presenter": batch, "sources/native_source": cpp,
            "sources/native_dll": dll, "sources/fixture": "scripts/tests/site_army_retained_batch_test.gd"}),
        stage("hot_retained_integration", "site_army_hot_retained_integration_test.gd", ["hot_retained_integration_smoke.json"], hashes={
            "army_sha256": army, "batch_sha256": batch, "dll_sha256": dll,
            "test_sha256": "scripts/tests/site_army_hot_retained_integration_test.gd"}),
        stage("scope", "site_army_mechanism_test.gd", ["hot_scope_selfcheck.json"], ["--scope-only"],
              {"army_sha256": army, "dll_sha256": dll, "generator_sha256": "scripts/tests/site_army_mechanism_test.gd"}),
    ]
    for role, outputs in [("A", ["frozen_A_logical.bin", "frozen_A_logical.json"]),
                          ("B0", ["candidate_B_segment_0.json"]), ("B1", ["candidate_B_segment_1.json"]),
                          ("B2", ["candidate_B_segment_2.json"]), ("merge", ["candidate_B_logical.json"])]:
        result.append(stage("oracle_" + role, "site_army_oracle_stream_test.gd", outputs, ["--oracle-role=" + role]))
    result.append(stage("manifest_after", "site_army_mechanism_test.gd", ["source_manifest.json"], ["--manifest-only"]))
    return result


def digest(path):
    import hashlib
    with Path(path).open("rb") as stream:
        h = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest().lower()


def contained(root, relative):
    value = Path(relative)
    if value.is_absolute() or ".." in value.parts or "\\" in str(relative):
        raise ValueError("Unsafe relative path: " + str(relative))
    target = (root / value).resolve()
    if not target.is_relative_to(root.resolve()) or target == root.resolve():
        raise ValueError("Path escapes approved root: " + str(relative))
    return target


def fingerprint(project, expected):
    observed = {}
    for name, pin in expected.items():
        path = contained(project, name.removeprefix("res://"))
        if not isinstance(pin, str) or not re.fullmatch(r"[a-fA-F0-9]{64}", pin):
            raise ValueError("Unresolved raw FileAccess SHA: " + name)
        actual = digest(path)
        if actual != pin.lower():
            raise ValueError("SOURCE_DRIFT: " + name)
        observed[name] = actual
    return observed


def membership(project, epoch):
    # Gate includes every terrain-owner script, optional UID and import sidecars.
    paths = {str(p.relative_to(project)).replace("\\", "/") for p in
             contained(project, "scripts/terrain_lab").glob("*.gd")}
    for name in list(paths) + [p.removeprefix("res://") for p in epoch]:
        for suffix in (".uid", ".import"):
            p = contained(project, name + suffix)
            if p.exists():
                paths.add(name + suffix)
    return sorted(paths)


def admit(config):
    required = ["project", "powershell", "verifier", "verifier_sha256", "godot_executable",
                "run_output", "source_head", "raw_source_sha256", "source_window"]
    missing = [key for key in required if not config.get(key)]
    for s in stages():
        limit = config.get("timeouts", {}).get(s["id"], {})
        if type(limit.get("seconds")) is not int or not 1 <= limit["seconds"] <= 3600:
            missing.append("timeouts." + s["id"] + ".seconds")
        if not limit.get("source") or str(limit["source"]).upper() == "UNKNOWN":
            missing.append("timeouts." + s["id"] + ".source")
        # Transport wait is not a change to the canonical Godot deadline.
        if type(limit.get("transport_seconds")) is not int or (type(limit.get("seconds")) is int and limit["transport_seconds"] <= limit["seconds"]):
            missing.append("timeouts." + s["id"] + ".transport_seconds")
    if missing:
        raise ValueError("UNRESOLVED_CONFIGURATION: " + ", ".join(missing))


def plan(config):
    main_scene = None
    if config.get("project"):
        path = contained(Path(config["project"]).resolve(), "project.godot")
        if path.is_file():
            found = re.search(r'^run/main_scene="([^"]+)"', path.read_text(encoding="utf-8-sig"), re.M)
            main_scene = found.group(1) if found else None
    return {"status": "PLAN_ONLY_NO_LAUNCH_NO_WRITES", "labels": LABELS,
            "oracle_main_scene": {"required": "res://scenes/terrain_lab/TerrainLab.tscn", "observed": main_scene,
                                  "blocked": main_scene != "res://scenes/terrain_lab/TerrainLab.tscn", "setting_override": "FORBIDDEN"},
            "evidence_root": ROOT, "automatic_stages": stages(), "timeouts": config.get("timeouts", {}),
            "manual_only": [
                {"label": "pixel_occlusion", "command": "& ./scripts/tests/verify_site_army_hot_pixels.ps1 -ProjectPath <project> -GodotExecutable <explicit-exe> -Verifier <unchanged-helper>",
                 "hard_limit_source": "wrapper specifies canonical visual TimeoutSeconds120; ordinary pixel fixture90s; no change"},
                {"label": "render_5k_mechanism", "command": "& <unchanged-helper> -ProjectPath <project> -GodotExecutable <explicit-exe> -Mode visual -GodotArguments @('--script','res://scripts/tests/site_army_scale_realtime_test.gd','--','--mechanism-diagnostic') -TimeoutSeconds <SEALED_LIMIT>",
                 "hard_limit_source": "UNKNOWN external; measured88.691s is not a hard limit"}],
            "hot_retained_note": "Historical headless supported; CC013 epoch dummy-material FAIL is preserved. No visual fallback; future headless failure stops this series. Manual real-renderer prerequisite belongs to a separate authorized window.",
            "full_mechanism_acceptance": "NOT_CLAIMED_GPU_UNVERIFIED"}


class CanonicalBackend:
    def __init__(self, config):
        self.config = config
        self.adapter = Path(__file__).with_name("rebuild_army_mechanism_invoke.ps1")

    def source_head(self, project):
        result = subprocess.run(["git", "-c", "core.fsmonitor=false", "rev-parse", "HEAD"],
                                cwd=project, capture_output=True, timeout=30, check=True)
        return result.stdout.decode("ascii").strip()

    def invoke(self, request, request_path, check_only=False):
        request_path.write_text(json.dumps(request), encoding="utf-8")
        cmd = [self.config["powershell"], "-NoProfile", "-File", str(self.adapter), "-Request", str(request_path)]
        if check_only:
            cmd.append("-CheckOnly")
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            stdout, stderr = process.communicate(timeout=request["transport_seconds"])
        except subprocess.TimeoutExpired as exc:
            # Never kill another Godot or pretend transport timeout is canonical timeout.
            # Persist PID for explicit handoff; do not start a subsequent stage.
            raise RuntimeError("TRANSPORT_NEEDS_ATTENTION PID=" + str(process.pid)) from exc
        return {"returncode": process.returncode, "stdout": stdout.decode("utf-8-sig", errors="replace"),
                "stderr": stderr.decode("utf-8-sig", errors="replace")}


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def output_valid(project, spec, epoch, started):
    evidence = contained(project, ROOT)
    reports = []
    for name in spec["outputs"]:
        p = contained(evidence, name)
        if not p.is_file() or p.stat().st_mtime_ns < started:
            raise ValueError("MISSING_OR_STALE_OUTPUT: " + name)
        if p.suffix != ".json":
            with p.open("rb") as stream:
                header = stream.read(4)
            if header != b"SAO2":
                raise ValueError("Invalid original oracle binary header")
            continue
        report = read_json(p)
        if report.get("status", "PASS") != "PASS" or report.get("errors") or report.get("failure"):
            raise ValueError("PRODUCER_REPORT_FAIL: " + name)
        for field in ("checks", "assertions"):
            if field in report and any(value is not True for value in report[field].values()):
                raise ValueError("PRODUCER_CHECK_FAIL: " + name)
        for pointer, source in spec["hashes"].items():
            value = report
            for part in pointer.split("/"):
                value = value[part]
            if value != epoch["res://" + source]:
                raise ValueError("OUTPUT_SOURCE_STALE: " + pointer)
        reports.append(report)
    if spec["id"].startswith("oracle_") and spec["id"] != "oracle_stream_selfcheck":
        role = spec["id"].removeprefix("oracle_")
        report = reports[-1]
        if report.get("source_manifest") != epoch or report.get("first_mismatch_tick") is not None:
            raise ValueError("ORACLE_MANIFEST_OR_MISMATCH")
        if role in ("A", "B0", "B1", "B2"):
            count = 1801 if role == "A" else 601 if role == "B0" else 600
            if report.get("role") != role or report.get("snapshots_checked") != count or report.get("materialized_ticks") != 1801 or report.get("process_steps") != 1800:
                raise ValueError("ORACLE_ORIGINAL_COVERAGE")
        if role == "A":
            if report.get("binary_sha256") != digest(evidence / "frozen_A_logical.bin"):
                raise ValueError("ORACLE_A_BINARY_CHANGED")
        else:
            reference = read_json(evidence / "frozen_A_logical.json")
            if report.get("reference_binary_sha256") != reference.get("binary_sha256") or digest(evidence / "frozen_A_logical.bin") != reference.get("binary_sha256"):
                raise ValueError("ORACLE_REFERENCE_CHAIN_CHANGED")
        if role == "merge":
            if report.get("role") != "B" or report.get("snapshots_checked") != 1801 or len(report.get("segments", [])) != 3:
                raise ValueError("ORACLE_MERGE_COVERAGE")
            for n in range(3):
                name = "candidate_B_segment_%d.json" % n
                if report.get("segment_sha256", {}).get(name) != digest(evidence / name):
                    raise ValueError("ORACLE_SEGMENT_HASH_CHANGED")
    return reports[-1]


def execute(config, backend=None):
    admit(config)  # No process or output write before every limit is explicit.
    project = Path(config["project"]).resolve()
    backend = backend or CanonicalBackend(config)
    if backend.source_head(project) != config["source_head"]:
        raise ValueError("COMMITTED_HEAD_DRIFT")
    evidence = contained(project, ROOT)
    run_parent = contained(project, config["run_output"])
    if not run_parent.is_relative_to(contained(project, "output")) or run_parent.is_relative_to(evidence) or evidence.is_relative_to(run_parent):
        raise ValueError("Run archive must be a separate project/output leaf")
    if digest(config["verifier"]) != config["verifier_sha256"].lower():
        raise ValueError("Canonical verifier bytes changed")
    if not Path(config["godot_executable"]).is_file():
        raise ValueError("Explicit Godot executable missing")
    if plan(config)["oracle_main_scene"]["blocked"]:
        raise ValueError("PREEXISTING_ORACLE_WRONG_MAIN_SCENE; no producer launch or settings override")
    seed = fingerprint(project, config["raw_source_sha256"])
    if "res://native/army_idle/bin/army_idle.windows.x86_64.dll" not in seed:
        raise ValueError("Actual DLL raw SHA required")
    seed_members = membership(project, seed)
    run = run_parent / (time.strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex)
    run.mkdir(parents=True)
    state = {"status": "RUNNING_NON_GPU_ONLY", "source_head": config["source_head"],
             "source_window": config["source_window"], "source_before": seed, "stages": [], "GPU": "NOT_RUN"}
    save(run / "series.json", state)
    epoch = seed
    member_names = seed_members
    def unchanged():
        fingerprint(project, epoch)
        if membership(project, epoch) != member_names:
            raise ValueError("SOURCE_MEMBERSHIP_DRIFT")
    def backup(relative, dest):
        old = contained(evidence, relative)
        if old.exists():
            if not old.is_file():
                raise ValueError("Unexpected output directory: " + relative)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(old, dest)
    try:
        for number, spec in enumerate(stages()):
            leaf = run / ("%02d_" % number + spec["id"])
            leaf.mkdir()
            limit = config["timeouts"][spec["id"]]
            request = {"project": str(project), "verifier": config["verifier"], "verifier_sha256": config["verifier_sha256"],
                       "godot_executable": config["godot_executable"], "mode": "headless", "args": spec["args"],
                       "expected_outputs": [str(contained(evidence, name)) for name in spec["outputs"]],
                       "timeout_seconds": limit["seconds"], "transport_seconds": limit["transport_seconds"]}
            unchanged()
            check = backend.invoke(request, leaf / "process_check.json", check_only=True)
            save(leaf / "process_check_result.json", check)
            if check["returncode"] != 0:
                raise ValueError("Godot already active or process inventory unavailable")
            if spec["id"] == "oracle_A":
                # B checks A's exact original PRODUCT_PATHS bytes against FROZEN_FILES.
                # These source snapshots are not PASS reports or substitute behavior.
                stream = contained(project, "scripts/tests/site_army_oracle_stream_test.gd").read_text(encoding="utf-8-sig")
                block = re.search(r"const PRODUCT_PATHS := (\{.*?\})", stream, re.S).group(1)
                products = json.loads(block)
                frozen = json.loads(re.search(r"const FROZEN_FILES := (\{.*?\})", stream, re.S).group(1))
                for label, filename in frozen.items():
                    relative = "frozen_A/" + filename
                    backup(relative, leaf / "before" / relative)
                    source = contained(project, products[label].removeprefix("res://"))
                    dest = contained(evidence, relative)
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source, dest)
                    if digest(dest) != epoch[products[label]]:
                        raise ValueError("Frozen A source copy drift")
            for name in spec["outputs"]:
                backup(name, leaf / "before" / name)
                old_output = contained(evidence, name)
                if old_output.exists():
                    old_output.unlink()
            # Old outputs are absent; use the filesystem clock, not Python's finer wall clock.
            boundary = leaf / "output_start"
            boundary.touch()
            started = boundary.stat().st_mtime_ns
            result = backend.invoke(request, leaf / "request.json")
            save(leaf / "wrapper.json", result)
            # Archive canonical receipt/logs BEFORE status inspection or another launch.
            found = re.search(r"(?m)^RESULT=(.+?)\r?$", result["stdout"])
            if not found:
                raise ValueError("Canonical RESULT missing")
            receipt = Path(found.group(1)).resolve()
            allowed = contained(project, ".godot-temp/godot_verify")
            if not receipt.is_relative_to(allowed) or receipt.name != "result.json":
                raise ValueError("Canonical receipt path outside project verifier root")
            raw = read_json(receipt)
            shutil.copyfile(receipt, leaf / "canonical_result.json")
            for name in ("stdout", "stderr", "combined"):
                if raw.get(name):
                    log = Path(raw[name]).resolve()
                    if not log.is_relative_to(receipt.parent):
                        raise ValueError("Canonical log escapes run directory")
                    shutil.copyfile(log, leaf / (name + ".log"))
            unchanged()
            if result["returncode"] != 0 or raw.get("status") != "PASS" or raw.get("exit_code") != 0 or raw.get("timed_out") is not False or raw.get("failure") or raw.get("missing_outputs"):
                raise ValueError("CANONICAL_FAIL: " + spec["id"])
            logged = ((leaf / "stdout.log").read_text(encoding="utf-8-sig") + "\n" +
                      (leaf / "stderr.log").read_text(encoding="utf-8-sig")).splitlines()
            # Match only the unchanged helper's one existing noise category.
            known_noise = [line for line in logged if re.search("Failed to read the root certificate store", line, re.I)]
            actionable = [line for line in logged if not re.search("Failed to read the root certificate store", line, re.I)]
            if any(re.search(r"SCRIPT ERROR|Parse Error|assert(?:ion)?(?: failed|_failed)|Segmentation fault|signal\s*11|-1073741819|3221225477|ERROR:", line, re.I) for line in actionable):
                raise ValueError("CANONICAL_ERROR_LOG: " + spec["id"])
            arguments = raw.get("arguments", [])
            if raw.get("mode") != "headless" or len(arguments) < 3 or arguments[:2] != ["--headless", "--path"] or Path(arguments[2]).resolve() != project or arguments[3:] != spec["args"]:
                raise ValueError("Canonical mode/script differs")
            report = output_valid(project, spec, epoch, started)
            if spec["id"] == "manifest_before":
                full = report["source_sha256"]
                fingerprint(project, full)
                if any(full.get(key) != value for key, value in seed.items() if key in full):
                    raise ValueError("Canonical manifest conflicts with seed")
                epoch = full
                member_names = membership(project, epoch)
                save(run / "source_epoch.json", epoch)
            elif spec["id"] == "manifest_after" and report["source_sha256"] != epoch:
                raise ValueError("Full Gate manifest drift")
            state["stages"].append({"id": spec["id"], "status": "ORIGINAL_CANONICAL_PASS", "archive": str(leaf),
                                    "known_noise": raw.get("known_noise", []), "observed_original_noise": known_noise})
            save(run / "series.json", state)
        state["status"] = "NON_GPU_SERIES_COMPLETED_FULL_MECHANISM_NOT_ACCEPTED"
    except Exception as exc:
        state["status"] = "FAIL_FIRST_STAGE_STOPPED"
        state["failure"] = str(exc)
        try:
            state["source_after_observed"] = {key: digest(contained(project, key.removeprefix("res://"))) for key in epoch}
        except OSError:
            state["source_after_observed"] = "source missing; failure preserved"
        save(run / "series.json", state)
        raise
    state["source_after"] = fingerprint(project, epoch)
    save(run / "series.json", state)
    return state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--execute", action="store_true", help="Use only in a later authorized source/window task")
    args = parser.parse_args()
    config = read_json(args.config)
    if not args.execute:
        print(json.dumps(plan(config), ensure_ascii=False, indent=2))
        return 0
    try:
        result = execute(config)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except Exception as exc:
        print("MECHANISM_REBUILD_STOPPED " + str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
