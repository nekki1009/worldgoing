"""Offline TEST_ONLY fixtures. Never launch the canonical helper or an engine."""
import contextlib
import io
import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch
import rebuild_army_mechanism as driver


class MockCanonical:
    def __init__(self, config, fault=None):
        self.config = config
        self.fault = fault
        self.started = []
        self.frozen_checked = False

    def source_head(self, project):
        return self.config["source_head"]

    def invoke(self, request, request_path, check_only=False):
        if check_only:
            return {"returncode": 23 if self.fault == "busy" else 0, "stdout": "TEST_ONLY", "stderr": ""}
        name = request_path.parent.name.split("_", 1)[1]
        self.started.append(name)
        spec = next(s for s in driver.stages() if s["id"] == name)
        project = Path(self.config["project"])
        root = project / driver.ROOT
        root.mkdir(parents=True, exist_ok=True)
        epoch = self.config["raw_source_sha256"]
        # Every producer output must be absent after its retained-byte backup.
        for name_out in spec["outputs"]:
            assert not (root / name_out).exists(), "Old producer output survived admission"
        report = {"status": "PASS", "TEST_ONLY_MOCK": True}
        for pointer, source in spec["hashes"].items():
            value = report
            parts = pointer.split("/")
            for part in parts[:-1]:
                value = value.setdefault(part, {})
            value[parts[-1]] = epoch["res://" + source]
        if name.startswith("manifest_"):
            report["source_sha256"] = epoch
        if name.startswith("oracle_") and name != "oracle_stream_selfcheck":
            role = name.removeprefix("oracle_")
            report.update(source_manifest=epoch, role="B" if role == "merge" else role,
                          snapshots_checked=601 if role == "B0" else 600 if role in ("B1", "B2") else 1801,
                          materialized_ticks=1801, process_steps=1800)
            if role == "A":
                for label, relative in self.config["TEST_ONLY_frozen"].items():
                    assert (root / "frozen_A" / relative).read_bytes() == (project / self.config["TEST_ONLY_products"][label][6:]).read_bytes()
                self.frozen_checked = True
                (root / "frozen_A_logical.bin").write_bytes(b"SAO2TEST_ONLY_NOT_A_REAL_ORACLE")
                report["binary_sha256"] = driver.digest(root / "frozen_A_logical.bin")
            else:
                report["reference_binary_sha256"] = driver.digest(root / "frozen_A_logical.bin")
            if role == "merge":
                report["segments"] = [dict(TEST_ONLY=True)] * 3
                report["segment_sha256"] = {"candidate_B_segment_%d.json" % n: driver.digest(root / ("candidate_B_segment_%d.json" % n)) for n in range(3)}
        for name_out in spec["outputs"]:
            if name_out.endswith(".json") and not (self.fault == "missing" and name == "hot_store_smoke"):
                driver.save(root / name_out, report)
            if self.fault == "same_tick":
                boundary = (request_path.parent / "output_start").stat().st_mtime_ns
                os.utime(root / name_out, ns=(boundary, boundary))
            if self.fault == "stale" and name == "hot_store_smoke":
                os.utime(root / name_out, ns=(1, 1))
        if self.fault == "drift" and name == "hot_store_smoke":
            (project / "project.godot").write_text("TEST_ONLY source changed", encoding="utf-8")
        run = project / ".godot-temp/godot_verify" / name
        run.mkdir(parents=True, exist_ok=True)
        (run / "stdout.log").write_text("TEST_ONLY original producer never run", encoding="utf-8")
        error = ""
        if name == "hot_store_smoke":
            error = {"stderr": "SCRIPT ERROR: TEST_ONLY", "material": 'ERROR: Parameter "material" is null.',
                     "noise": "ERROR: Failed to read the root certificate store"}.get(self.fault, "")
        (run / "stderr.log").write_text(error, encoding="utf-8")
        result = {"status": "FAIL" if self.fault == "canonical" and name == "hot_store_smoke" else "PASS", "mode": "headless",
                  "exit_code": 0, "timed_out": False, "arguments": ["--headless", "--path", str(project), *spec["args"]],
                  "stdout": str(run / "stdout.log"), "stderr": str(run / "stderr.log"), "failure": None, "missing_outputs": []}
        driver.save(run / "result.json", result)
        return {"returncode": 0, "stdout": "RESULT=" + str(run / "result.json") + "\n", "stderr": ""}


class RebuildTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix="TEST_ONLY_", dir=Path(__file__).parent / "scratch")
        self.addCleanup(temporary.cleanup)
        project = Path(temporary.name)
        paths = {"project.godot", "native/army_idle/bin/army_idle.windows.x86_64.dll"}
        for s in driver.stages():
            paths.add(s["script"][6:])
            paths.update(s["hashes"].values())
        # Reuse pinned mock sources; preserve 15 distinct snapshots without duplicate IO.
        paths.add("scripts/terrain_lab/TEST_ONLY_extra.gd")
        products = {str(n): "res://" + name for n, name in enumerate(sorted(paths))}
        assert len(products) == 15
        frozen = {str(n): "TEST_ONLY_%d.gd.txt" % n for n in range(15)}
        for name in paths:
            p = project / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("# TEST_ONLY SOURCE " + name, encoding="utf-8")
        (project / "project.godot").write_text('[application]\nrun/main_scene="res://scenes/terrain_lab/TerrainLab.tscn"\n', encoding="utf-8")
        (project / "scripts/tests/site_army_oracle_stream_test.gd").write_text("const PRODUCT_PATHS := " + json.dumps(products) + "\nconst FROZEN_FILES := " + json.dumps(frozen), encoding="utf-8")
        verifier = project / "TEST_ONLY_VERIFIER.ps1"
        verifier.write_text("# TEST_ONLY never executed", encoding="utf-8")
        executable = project / "TEST_ONLY_NOT_GODOT.exe"
        executable.write_bytes(b"NOT AN EXECUTABLE")
        return {"project": str(project), "powershell": "NEVER_INVOKE", "verifier": str(verifier), "verifier_sha256": driver.digest(verifier),
                "godot_executable": str(executable), "run_output": "output/TEST_ONLY_rebuild", "source_head": "TEST_ONLY_NOT_A_COMMIT",
                "source_window": "TEST_ONLY_OFFLINE", "raw_source_sha256": {"res://" + name: driver.digest(project / name) for name in paths},
                "timeouts": {s["id"]: {"seconds": 1, "transport_seconds": 2, "source": "TEST_ONLY_NOT_PRODUCTION_LIMIT"} for s in driver.stages()},
                "TEST_ONLY_products": products, "TEST_ONLY_frozen": frozen}

    @classmethod
    def setUpClass(cls):
        (Path(__file__).parent / "scratch").mkdir(exist_ok=True)

    def test_default_plan_no_launch_or_write(self):
        config = self.fixture()
        before = {str(p): (p.stat().st_mtime_ns, driver.digest(p)) for p in Path(config["project"]).rglob("*") if p.is_file()}
        with patch.object(driver.subprocess, "Popen", side_effect=AssertionError("No launch")):
            plan = driver.plan(config)
        self.assertEqual(len(plan["labels"]), 11)
        self.assertEqual({x["label"] for x in plan["manual_only"]}, driver.GPU)
        self.assertTrue(all(s["mode"] == "headless" for s in plan["automatic_stages"]))
        self.assertEqual(before, {str(p): (p.stat().st_mtime_ns, driver.digest(p)) for p in Path(config["project"]).rglob("*") if p.is_file()})

    def test_unknown_limit_blocks_before_process(self):
        config = self.fixture()
        config["timeouts"]["oracle_A"]["seconds"] = None
        backend = MockCanonical(config)
        with self.assertRaisesRegex(ValueError, "UNRESOLVED_CONFIGURATION"):
            driver.execute(config, backend)
        self.assertEqual(backend.started, [])

    def test_full_serial_mock_backups_and_frozen_sources(self):
        config = self.fixture()
        root = Path(config["project"]) / driver.ROOT
        root.mkdir(parents=True)
        (root / "hot_store_smoke.json").write_bytes(b"TEST_ONLY_OLD_BYTES")
        frozen = root / "frozen_A/TEST_ONLY_0.gd.txt"
        frozen.parent.mkdir()
        frozen.write_bytes(b"TEST_ONLY_OLD_FROZEN")
        backend = MockCanonical(config)
        result = driver.execute(config, backend)
        self.assertNotIn("PASS", result["status"])
        self.assertEqual(backend.started, [s["id"] for s in driver.stages()])
        self.assertEqual([x for x in backend.started if x.startswith("oracle_") and x != "oracle_stream_selfcheck"], ["oracle_A", "oracle_B0", "oracle_B1", "oracle_B2", "oracle_merge"])
        self.assertTrue(backend.frozen_checked)
        archive = Path(config["project"]) / config["run_output"]
        self.assertTrue(any(p.read_bytes() == b"TEST_ONLY_OLD_BYTES" for p in archive.rglob("hot_store_smoke.json")))
        self.assertTrue(any(p.read_bytes() == b"TEST_ONLY_OLD_FROZEN" for p in archive.rglob("TEST_ONLY_0.gd.txt")))

    def test_first_failures_stop_and_archive(self):
        for fault in ("canonical", "stale", "drift", "stderr", "busy"):
            with self.subTest(fault=fault):
                config = self.fixture()
                backend = MockCanonical(config, fault)
                with self.assertRaises(ValueError):
                    driver.execute(config, backend)
                self.assertNotIn("hot_prepare_smoke", backend.started)
                records = list((Path(config["project"]) / config["run_output"]).rglob("series.json"))
                self.assertEqual(driver.read_json(records[0])["status"], "FAIL_FIRST_STAGE_STOPPED")

    def test_main_scene_and_paths_block(self):
        config = self.fixture()
        (Path(config["project"]) / "project.godot").write_text('run/main_scene="res://scenes/main_menu/MainMenu.tscn"', encoding="utf-8")
        backend = MockCanonical(config)
        with self.assertRaisesRegex(ValueError, "WRONG_MAIN_SCENE"):
            driver.execute(config, backend)
        self.assertEqual(backend.started, [])
        for bad in ("../escape", "output/../../escape", str(Path(config["project"]).anchor)):
            with self.assertRaises(ValueError):
                driver.contained(Path(config["project"]), bad)

    def test_filesystem_boundary_and_missing_old_output(self):
        original = driver.stages()
        for fault in ("same_tick", "missing", "stale"):
            with self.subTest(fault=fault):
                config = self.fixture()
                root = Path(config["project"]) / driver.ROOT
                root.mkdir(parents=True)
                old = root / "hot_store_smoke.json"
                old.write_bytes(b"TEST_ONLY_OLD_OUTPUT")
                # A future-dated old file must also be removed, not accepted as new.
                os.utime(old, ns=(2**62, 2**62))
                backend = MockCanonical(config, fault)
                with patch.object(driver, "stages", return_value=original[:2]), \
                        patch.object(driver.time, "time_ns", side_effect=AssertionError("No cross-clock comparison")):
                    if fault == "same_tick":
                        result = driver.execute(config, backend)
                        self.assertEqual(len(result["stages"]), 2)
                    else:
                        with self.assertRaisesRegex(ValueError, "MISSING_OR_STALE_OUTPUT: hot_store_smoke.json"):
                            driver.execute(config, backend)
                archive = Path(config["project"]) / config["run_output"]
                self.assertTrue(any(p.read_bytes() == b"TEST_ONLY_OLD_OUTPUT" for p in archive.rglob("before/hot_store_smoke.json")))

    def test_original_known_noise_only(self):
        original = driver.stages()
        for fault in ("noise", "material"):
            with self.subTest(fault=fault):
                config = self.fixture()
                backend = MockCanonical(config, fault)
                with patch.object(driver, "stages", return_value=original[:2]):
                    if fault == "noise":
                        result = driver.execute(config, backend)
                        self.assertIn("Failed to read the root certificate store", result["stages"][-1]["observed_original_noise"][0])
                    else:
                        with self.assertRaisesRegex(ValueError, "CANONICAL_ERROR_LOG"):
                            driver.execute(config, backend)


if __name__ == "__main__":
    import threading
    # Offline test-command bound only; never a canonical producer deadline.
    watchdog = threading.Timer(240, lambda: os._exit(124))
    watchdog.daemon = True
    watchdog.start()
    result = unittest.main(exit=False)
    watchdog.cancel()
    raise SystemExit(0 if result.result.wasSuccessful() else 1)
