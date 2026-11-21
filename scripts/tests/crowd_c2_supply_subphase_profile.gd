extends "res://scripts/tests/crowd_c2_host_profile.gd"
const SubphaseController = preload("res://scripts/tests/helpers/crowd_supply_subphase_controller.gd")
var source_pin_report := {}
var frozen_steps: Array[Dictionary] = []

func _initialize() -> void:
	source_pin_report = SubphaseController.source_pin()
	if not bool(source_pin_report.ok):
		printerr("GATE FAIL: supply subphase source pin ", source_pin_report)
		quit(2)
		return
	super._initialize()

func _controller_script() -> Script:
	return SubphaseController

func _profile_sources() -> Dictionary:
	var hashes: Dictionary = super._profile_sources()
	for path: String in ["res://scripts/tests/crowd_c2_supply_subphase_profile.gd", "res://scripts/tests/helpers/crowd_supply_subphase_controller.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _write_result() -> void:
	super._write_result()
	if not installed: return
	if frozen_steps.is_empty() and not frozen_profile.is_empty():
		frozen_steps = lab.site_controller.supply_phase_steps.duplicate(true)
	var report: Dictionary = frozen_profile.duplicate(true) if not frozen_profile.is_empty() else profiler.snapshot()
	var count := int(report.get("original_large_run", {}).get("costs", {}).get("host_count", 0))
	var supply_us := int(report.methods.get("host.crowd_supply", {}).get("inclusive_us", 0))
	var phases: Array[Dictionary] = []
	var phased_us := 0
	for name: String in SubphaseController.PHASE_NAMES:
		var metric: Dictionary = report.methods.get(name, {})
		var total := int(metric.get("inclusive_us", 0))
		phased_us += total
		phases.append({"phase": name, "calls": int(metric.get("calls", 0)), "inclusive_us": total,
			"mean_ms_per_host_step": float(total) / float(maxi(1, count)) / 1000.0,
			"percent_of_crowd_supply": 100.0 * float(total) / float(maxi(1, supply_us))})
	report["phases"] = phases
	report["source_pin_before"] = source_pin_report
	report["source_pin_after"] = SubphaseController.source_pin()
	report["source_hashes_before"] = source_hashes
	report["source_hashes_after"] = _profile_sources()
	report["sources_unchanged"] = source_hashes == report.source_hashes_after
	report["controller_install"] = controller_install
	report["windows"] = host_windows
	report["supply_steps"] = frozen_steps
	report["step_rows_match_host_count"] = frozen_steps.size() == count
	report["phase_balance_ok"] = phased_us <= supply_us
	report["unisolated_supply_us"] = supply_us - phased_us
	report["original_fixture_ok_so_far"] = not failed
	report["scope"] = "Unchanged original D fixture and gates. Test-only source-pinned supply transcription: removing marked timer lines restores the exact production function. Four mutually exclusive phases cover snapshot/feeding, member views/owner setup, neutral slice plus Sustain.advance_to, and damage/checkpoint/native-input commit. Phase four has separate slice and final-checkpoint intervals. Untimed loop/branch and timer bookkeeping remain in unisolated_supply_us. Each supply call records its pre-native step index and four phase totals. Nested event/equipment timers are already included in their active phase. Added timing/recording overhead is not a formal CPU/FPS result."
	var file := FileAccess.open(output_root.path_join("supply_subphase_profile.json"), FileAccess.WRITE)
	if file == null:
		printerr("GATE FAIL: cannot write supply subphase profile")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	if not bool(report.source_pin_after.ok) or (not frozen_profile.is_empty() and (not report.step_rows_match_host_count or not report.phase_balance_ok)):
		printerr("GATE FAIL: supply subphase source/step/timer accounting")
		quit(2)
