extends "res://scripts/tests/site_building_ui_test.gd"
## F02 (v2 plan R0): duty-AI rounds, seat waits, inmate fallbacks and traces are
## process-wide statics; walk-then-release jobs are unsaved. A successful Site
## bind (new map, load, travel) starts all of them fresh for the new Site.

const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var lab := _building_lab(_building_fixture())
	DutyAI.review_round = 17
	DutyAI._seat_waits["team:1:p1"] = 3
	DutyAI._inmate_since["42"] = 5
	DutyAI.settlement_traces.append({"site": "old"})
	DutyAI.nation_traces["1"] = [{"site": "old"}]
	DutyAI.last_nation_trace = {"site": "old"}
	var escort: SiteCaptiveEscort = lab.site_controller.captive_escort
	escort._release_walks[77] = {"target_id": 42, "requester_id": 77}
	escort.last_release_result = {"ok": true}
	lab.bind_terrain(_building_fixture())
	assert(DutyAI.review_round == 0 and DutyAI._seat_waits.is_empty() and DutyAI._inmate_since.is_empty(), "Duty-AI cadence and waits restart with the new Site")
	assert(DutyAI.settlement_traces.is_empty() and DutyAI.nation_traces.is_empty() and DutyAI.last_nation_trace.is_empty(), "Traces describe one Site")
	assert(escort._release_walks.is_empty() and escort.last_release_result.is_empty(), "Unsaved release walks never cross a Site bind")
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_DUTY_AI_SITE_RESET_PASS: rounds, seat waits, inmate fallback, traces and release walks reset on a successful Site bind")
	quit(0)
