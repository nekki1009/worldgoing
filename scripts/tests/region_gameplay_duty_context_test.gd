extends SceneTree
var checks := 0
var failed := false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("REGION_GAMEPLAY_DUTY_CONTEXT_FAIL: " + message)

func _initialize() -> void:
	var main := TerrainLab.new()
	var first := TerrainLab.new()
	var second := TerrainLab.new()
	first.restore_only = true
	second.restore_only = true
	TerrainLab.DutyAI.review_round = 11
	TerrainLab.DutyAI._seat_waits = {"person:17": 8}
	TerrainLab.DutyAI._inmate_since = {"17": 1440}
	TerrainLab.DutyAI.settlement_traces = [{"site": "main"}]
	TerrainLab.DutyAI.nation_traces = {"nation": [{"site": "main"}]}
	TerrainLab.DutyAI.last_nation_trace = {"site": "main"}
	var source := main._region_capture_duty_cache()
	var initial := first._region_duty_enter()
	check(TerrainLab.DutyAI.review_round == 0 and TerrainLab.DutyAI._seat_waits.is_empty() and TerrainLab.DutyAI._inmate_since.is_empty(), "A new hidden Site never inherits the main Site's person-ID waits")
	TerrainLab.DutyAI.review_round = 3
	TerrainLab.DutyAI._seat_waits["person:17"] = 2
	TerrainLab.DutyAI._inmate_since["17"] = 99
	TerrainLab.DutyAI.settlement_traces.append({"site": "first"})
	first._region_duty_leave(initial)
	check(main._region_capture_duty_cache() == source, "Hidden Site initialization restores every main duty transient")
	var other := second._region_duty_enter()
	check(TerrainLab.DutyAI.review_round == 0 and TerrainLab.DutyAI._seat_waits.is_empty(), "A second Site with the same local person IDs has an independent original context")
	TerrainLab.DutyAI._seat_waits["person:17"] = 1
	second._region_duty_leave(other)
	var outer := first._region_duty_enter()
	check(TerrainLab.DutyAI.review_round == 3 and TerrainLab.DutyAI._seat_waits["person:17"] == 2 and TerrainLab.DutyAI._inmate_since["17"] == 99, "The same original Site resumes its captured wait and prisoner history")
	TerrainLab.DutyAI.review_round = 4
	var nested := first._region_duty_enter()
	check(TerrainLab.DutyAI.review_round == 4, "Nested capture/restore does not reload stale entry values")
	TerrainLab.DutyAI._seat_waits["person:17"] = 3
	first._region_duty_leave(nested)
	check(TerrainLab.DutyAI.review_round == 4, "Nested exit preserves the active original consumer's actual progress")
	first._region_duty_leave(outer)
	check(main._region_capture_duty_cache() == source, "Leaving the positive consumer restores the unchanged main context")
	check(first._region_duty_transient.round == 4 and first._region_duty_transient.seat_waits["person:17"] == 3, "The first Site retains actual progress in its existing roots.duty context")
	check(second._region_duty_transient.seat_waits["person:17"] == 1, "The other Site's same-ID wait remains unchanged")
	var live := main._region_duty_enter()
	TerrainLab.DutyAI.review_round = 12
	main._region_duty_leave(live)
	check(TerrainLab.DutyAI.review_round == 12 and main._region_duty_transient.round == 12, "The main live consumer keeps its own actual post-review context")
	main._region_restore_duty_cache(source)
	main.free()
	first.free()
	second.free()
	if not failed: print("REGION_GAMEPLAY_DUTY_CONTEXT_PASS checks=%d scope=original_duty_context_isolation" % checks)
	quit(1 if failed else 0)
