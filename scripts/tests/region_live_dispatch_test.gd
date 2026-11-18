extends "res://scripts/tests/region_remote_nation_original_test.gd"
## An NPC team leaves the live crowd Site the player stands in, decided inside real steps (2026-11-18: both were refused
## by the Site's own open Region point and silently dropped). The remote-nation fixture; each case is a captain's
## dispatch of one authored two-person team to the neighbouring cold Site:
## - "daily": from the daily hook (SiteController.resident_exodus_day), through a stand-in that takes over
##   site_caravan.gd's path. The hook waits for the point to close and runs between two steps: nothing is pending,
##   consuming or dispatching, no fire boundary is open, and the team leaves;
## - "evaluation": from the live owner's hourly evaluation (the slot's dispatch-intents callable), while the point is
##   dispatching the world events with its fire boundary open: the slot closes the points first and the team leaves.
## Then the world keeps stepping with both parties on the road.
## Output: the fixture's REGION_REMOTE_NATION_ORIGINAL_PASS marker and exit 0; quit(1) on any failure or the deadline.
const ProbeCaravan = preload("res://scripts/tests/support/caravan_dispatch_probe.gd")
var probe_evaluation: Dictionary = {}

func _initialize() -> void:
	super._initialize()
	deadline = Time.get_ticks_msec() + 840000

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "840-second live dispatch deadline")
	return false

func _probe_send(team_id: int, label: String) -> Dictionary:
	var captain := int(controller.team_captain_of_team(team_id))
	if captain <= 0: return {"ok": false, "code": "NO_CAPTAIN", "label": label}
	var person: Dictionary = lab.crowd_site.combat_target(captain)
	var component: int = RegionTravelSite.start_component(slot, slot._coordinate(lab.terrain).site, person.cell, lab.terrain)
	var state := {"pending": not lab._region_point_pending.is_empty(), "consuming": lab._region_point_consuming, "dispatching": lab._region_point_dispatching,
		"boundary": not lab.terrain.get_meta(&"fire_boundary", {}).is_empty()}
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, "captain:trade", team_id, nation_goal_coordinate, component, [], "probe_%s_%d" % [label, OS.get_process_id()])
	if not prepared.ok: return {"ok": false, "label": label, "stage": "prepare", "code": str(prepared.get("code", "")), "message": str(prepared.get("message", "")), "state": state}
	var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
	return {"ok": bool(committed.get("ok", false)), "label": label, "stage": "commit", "code": str(committed.get("code", "")), "message": str(committed.get("message", "")), "state": state}

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest() or not await _setup_action_world() or not _nation_initial_bodies(): _finish(); return
	for _frame: int in range(10): await process_frame
	var teams: Array = []
	for team: Dictionary in lab.crowd_site.teams:
		if int(team.get("faction", -1)) == 1 and team.get("person_ids", []).size() >= 2 and not team.person_ids.has(lab.controlled_person_id()): teams.append(int(team.team_id))
	if not _check(teams.size() >= 2, "two authored teams can be sent", teams): _finish(); return
	(ProbeCaravan as Script).take_over_path("res://scripts/terrain_lab/site_caravan.gd")
	ProbeCaravan.on_dispatch = func(_controller: Variant) -> Dictionary:
		ProbeCaravan.on_dispatch = Callable()
		return _probe_send(int(teams[0]), "daily")
	controller.set_meta(&"resident_exodus_day", -1)
	await _nation_until(func() -> bool: return not ProbeCaravan.calls.is_empty(), "the daily hook runs inside a real step")
	var inner: Callable = slot.region_dispatch_intents
	slot.region_dispatch_intents = func(original: TerrainLab, intel: Variant, at: float) -> Dictionary:
		if original == lab and probe_evaluation.is_empty(): probe_evaluation = _probe_send(int(teams[1]), "evaluation")
		return inner.call(original, intel, at)
	await _nation_until(func() -> bool: return not probe_evaluation.is_empty(), "the live owner's evaluation runs inside a real step")
	var daily: Dictionary = ProbeCaravan.calls[0] if not ProbeCaravan.calls.is_empty() else {}
	if not _check(bool(daily.get("ok", false)) and daily.get("state", {}) == {"pending": false, "consuming": false, "dispatching": false, "boundary": false},
		"the daily hook runs with the Site at rest and its team leaves", daily): _finish(); return
	if not _check(bool(probe_evaluation.get("ok", false)) and bool(probe_evaluation.get("state", {}).get("dispatching", false)),
		"the evaluation's team leaves from inside the dispatching point", probe_evaluation): _finish(); return
	var parties: Dictionary = slot.region_registry().parties
	if not _check(parties.has("probe_daily_%d" % OS.get_process_id()) and parties.has("probe_evaluation_%d" % OS.get_process_id()), "both parties are on the Region map", parties.keys()): _finish(); return
	var until := float(slot.control.logical_game_seconds) + 60.0
	if not await _nation_until(func() -> bool: return float(slot.control.logical_game_seconds) >= until, "the world keeps stepping with both on the road"): _finish(); return
	report["live_dispatch"] = {"daily": daily, "evaluation": probe_evaluation}
	_finish()
