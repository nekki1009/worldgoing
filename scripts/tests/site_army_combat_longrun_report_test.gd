extends SceneTree
## Report-only regression and immutable evidence review. Never reruns or edits
## the measured battle, its raw metrics, images, safe save or canonical result.

const Longrun = preload("res://scripts/tests/site_army_combat_longrun_test.gd")
const RAW_PATH := "res://output/site_army_combat_longrun/mixed/full_endurance/measurements.json"
const RESULT_PATH := "res://output/site_institutions_20260913_0330/verification/20260913_073548_879/result.json"
const VALIDATION_PATH := "res://output/site_army_combat_longrun/mixed/full_endurance/report_validation.json"

func _initialize() -> void:
	var old_merge := {"goal_met": false}
	old_merge.merge({"goal_met": true})
	assert(not old_merge.goal_met, "Reproduce the old reporter bug using the actual Dictionary API")
	var cases: Array[Dictionary] = [
		{"seconds": 60.0, "terminal": false, "hits": 1, "expected": true},
		{"seconds": 60.0916666666639, "terminal": false, "hits": 184, "expected": true},
		{"seconds": 59.9999995, "terminal": false, "hits": 1, "expected": true},
		{"seconds": 59.99, "terminal": false, "hits": 184, "expected": false},
		{"seconds": 40.291667, "terminal": false, "hits": 156, "expected": false},
		{"seconds": 10.0, "terminal": true, "hits": 1, "expected": true},
		{"seconds": 60.1, "terminal": false, "hits": 0, "expected": false},
		{"seconds": 10.0, "terminal": true, "hits": 0, "expected": false},
	]
	for sample: Dictionary in cases:
		for previous_flag: bool in [false, true]:
			var report := {"goal_met": previous_flag, "longest_combat_streak_seconds": sample.seconds,
				"natural_terminal": sample.terminal, "effective_hit_events": sample.hits, "unchanged": 123}
			Longrun.finalize_report(report)
			assert(report.goal_met == sample.expected and int(report.unchanged) == 123)
			assert(("no weakened PASS" in str(report.reason)) == not bool(sample.expected))
	var raw_hash := FileAccess.get_sha256(RAW_PATH)
	var result_hash := FileAccess.get_sha256(RESULT_PATH)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RAW_PATH)) as Dictionary
	var canonical: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RESULT_PATH)) as Dictionary
	assert(canonical.status == "PASS" and int(canonical.exit_code) == 0 and not bool(canonical.timed_out))
	assert("--full-endurance" in canonical.arguments and canonical.missing_outputs.is_empty())
	assert(raw.display == "Windows" and not bool(raw.goal_met), "Preserve the original erroneous flag as historical evidence")
	assert(float(raw.longest_combat_streak_seconds) >= 60.0 and int(raw.effective_hit_events) == 184)
	assert(int(raw.shared_steps) == 7212 and int(raw.final_life.actual_rows) == 200)
	assert(bool(raw.item_conservation) and int(raw.items) == 1018 and raw.save_result == "BUSY")
	assert(int(raw.final_life.dead) == 25 and int(raw.containers) == 24 and int(raw.pending_original_deaths) == 1)
	assert(int(raw.nodes_before) == 4311 and int(raw.nodes_after) == 4311)
	assert(raw.shared_source_sha256 == FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"))
	var reviewed := raw.duplicate(true)
	Longrun.finalize_report(reviewed)
	assert(bool(reviewed.goal_met))
	var untouched_raw := raw.duplicate(true)
	var untouched_reviewed := reviewed.duplicate(true)
	for field: String in ["goal_met", "reason"]:
		untouched_raw.erase(field)
		untouched_reviewed.erase(field)
	assert(untouched_raw == untouched_reviewed, "Reclassification cannot edit or generate any measured gameplay value")
	assert(FileAccess.get_sha256(RAW_PATH) == raw_hash and FileAccess.get_sha256(RESULT_PATH) == result_hash)
	var validation := {"status": "REPORTER_REVIEW_PASS", "report_cases": cases.size() * 2,
		"canonical_run": "20260913_073548_879", "raw_report_sha256": raw_hash, "canonical_result_sha256": result_hash,
		"original_goal_flag": raw.goal_met, "verified_goal_met": reviewed.goal_met,
		"longest_combat_streak_seconds": raw.longest_combat_streak_seconds, "effective_hit_events": raw.effective_hit_events,
		"raw_files_unchanged": true, "scope": "Report-only correction; original full GPU run and assertions preserved, no second endurance run claimed",
		"reason": reviewed.reason}
	var file := FileAccess.open(VALIDATION_PATH, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(validation, "\t"))
	file.close()
	print("SITE_ARMY_COMBAT_LONGRUN_REPORT_PASS ", JSON.stringify(validation))
	quit(0)
