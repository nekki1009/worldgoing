extends "res://scripts/tests/site_tactical_ai_formal_visual_test.gd"
## In-memory wrappers only. Original results, owners, clock and formal gates remain.
const RW_ARMY := "res://scripts/terrain_lab/terrain_army.gd"
const RW_OUT := "res://output/three_faction_root_cause_20260928/repeated_work"
const RW_MAX_SAMPLES := 1000
var rw_rosters := {}
var rw_pending := {}
var rw_failed_routes := {}
var rw_totals := {"roster_calls": 0, "roster_original_usec": 0,
	"roster_same_tick_repeats": 0, "roster_equal_results": 0, "roster_changed_results": 0,
	"roster_equal_repeat_usec": 0, "intent_calls": 0, "intent_original_usec": 0,
	"intent_prepare_samples": 0, "intent_paired_samples": 0,
	"observable_inputs_equal": 0, "result_equal": 0, "inputs_and_result_equal": 0,
	"equal_pair_propose_original_usec": 0, "signature_usec": 0,
	"common_route_calls": 0, "common_route_original_usec": 0, "common_route_searches": 0,
	"common_route_cached_success": 0, "common_route_failed": 0, "common_route_same_query_failed": 0}
var rw_examples: Array[Dictionary] = []
var rw_disk_hash := ""
var rw_installed := false

func _initialize() -> void:
	deadline_us = Time.get_ticks_usec() + int(DEADLINE_SECONDS * 1000000.0)
	output = "%s/run_%d_%d" % [RW_OUT, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	_run.call_deferred()

func _run() -> void:
	if not _rw_install():
		push_error("Repeated-work wrappers could not be installed")
		quit(1)
		return
	await super._run()

func _rw_install() -> bool:
	var script := load(RW_ARMY) as GDScript
	var source: String = script.source_code
	rw_disk_hash = FileAccess.get_sha256(RW_ARMY)
	var headers := ["func _get_active_member_ids() -> Array[int]:",
		"func _transit_field_intent(mid: int, index: int, grid: Object, target_context: Dictionary = {}) -> Dictionary:",
		"func _common_order_route_step(index: int, goal: Vector2i, operator_id: int) -> Vector2i:"]
	for header: String in headers:
		if source.count(header) != 1:
			push_error("Repeated-work original function header changed: " + header)
			return false
	source = source.replace(headers[0], headers[0].replace("_get_active_member_ids", "_rw_original_active_member_ids"))
	source = source.replace(headers[1], headers[1].replace("_transit_field_intent", "_rw_original_transit_field_intent"))
	source = source.replace(headers[2], headers[2].replace("_common_order_route_step", "_rw_original_common_order_route_step"))
	script.source_code = source + """

func _get_active_member_ids() -> Array[int]:
	var probe: Object = Engine.get_main_loop()
	if not probe.has_method("rw_enabled") or not probe.rw_enabled():
		return _rw_original_active_member_ids()
	var started := Time.get_ticks_usec()
	var result: Array[int] = _rw_original_active_member_ids()
	var elapsed := Time.get_ticks_usec() - started
	probe.rw_roster_result(self, result, elapsed)
	return result

func _transit_field_intent(mid: int, index: int, grid: Object, target_context: Dictionary = {}) -> Dictionary:
	var probe: Object = Engine.get_main_loop()
	if not probe.has_method("rw_enabled") or not probe.rw_enabled():
		return _rw_original_transit_field_intent(mid, index, grid, target_context)
	var ticket: Dictionary = {}
	if probe.rw_wants_intent_ticket(self, mid):
		ticket = probe.rw_intent_ticket(self, mid, index, grid, get_stack())
	var started := Time.get_ticks_usec()
	var result: Dictionary = _rw_original_transit_field_intent(mid, index, grid, target_context)
	var elapsed := Time.get_ticks_usec() - started
	probe.rw_intent_result(self, mid, ticket, result, elapsed)
	return result

func _common_order_route_step(index: int, goal: Vector2i, operator_id: int) -> Vector2i:
	var probe: Object = Engine.get_main_loop()
	if not probe.has_method("rw_enabled") or not probe.rw_enabled():
		return _rw_original_common_order_route_step(index, goal, operator_id)
	var query := [combat_identity(index), cells[index], goal, get_order_serial(), combat_order, data.navigation_revision, operator_id]
	var calls_before := route_calls
	var started := Time.get_ticks_usec()
	var result: Vector2i = _rw_original_common_order_route_step(index, goal, operator_id)
	var elapsed := Time.get_ticks_usec() - started
	probe.rw_common_route_result(self, index, query, result, route_calls - calls_before, elapsed)
	return result
"""
	if script.reload(true) != OK:
		return false
	rw_installed = true
	return true

func rw_enabled() -> bool:
	return measured_us > 0 and not finished and is_instance_valid(lab) and lab.is_processing()

func rw_roster_result(team: TerrainArmy, result: Array[int], elapsed: int) -> void:
	rw_totals.roster_calls += 1
	rw_totals.roster_original_usec += elapsed
	var old: Dictionary = rw_rosters.get(team.team_id, {})
	if int(old.get("tick", -1)) == team.current_logic_tick:
		rw_totals.roster_same_tick_repeats += 1
		if old["result"] == result:
			rw_totals.roster_equal_results += 1
			rw_totals.roster_equal_repeat_usec += elapsed
		else:
			rw_totals.roster_changed_results += 1
	rw_rosters[team.team_id] = {"tick": team.current_logic_tick, "result": result.duplicate()}

func rw_common_route_result(team: TerrainArmy, index: int, query: Array, result: Vector2i, searches: int, elapsed: int) -> void:
	rw_totals.common_route_calls += 1
	rw_totals.common_route_original_usec += elapsed
	rw_totals.common_route_searches += searches
	if not rw_failed_routes.has(team.team_id): rw_failed_routes[team.team_id] = {}
	var failed: Dictionary = rw_failed_routes[team.team_id]
	if result == TerrainArmy.INVALID_CELL:
		rw_totals.common_route_failed += 1
		if failed.get(index, []) == query: rw_totals.common_route_same_query_failed += 1
		failed[index] = query
	else:
		if searches == 0: rw_totals.common_route_cached_success += 1
		failed.erase(index)

func rw_wants_intent_ticket(team: TerrainArmy, mid: int) -> bool:
	if int(rw_totals.intent_prepare_samples) < RW_MAX_SAMPLES: return true
	var previous: Dictionary = rw_pending.get(team.team_id, {})
	return int(previous.get("tick", -1)) == team.current_logic_tick and previous.get("members", {}).has(mid)

func rw_intent_ticket(team: TerrainArmy, mid: int, index: int, grid: Object, stack: Array) -> Dictionary:
	var caller := ""
	for frame: Dictionary in stack:
		if str(frame.get("function", "")) == "_refresh_member_route_caches": caller = "prepare"
		elif str(frame.get("function", "")) == "propose_combat_moves": caller = "propose"
	if caller.is_empty(): return {}
	var previous: Dictionary = rw_pending.get(team.team_id, {})
	if int(previous.get("tick", -1)) != team.current_logic_tick:
		previous = {"tick": team.current_logic_tick, "members": {}}
		rw_pending[team.team_id] = previous
	if caller == "prepare":
		if int(rw_totals.intent_prepare_samples) >= RW_MAX_SAMPLES: return {}
		rw_totals.intent_prepare_samples += 1
	elif not previous["members"].has(mid):
		return {}
	var started := Time.get_ticks_usec()
	var signature := _rw_observable_inputs(team, mid, index, grid)
	rw_totals.signature_usec += Time.get_ticks_usec() - started
	return {"caller": caller, "signature": signature, "tick": team.current_logic_tick}

func _rw_observable_inputs(team: TerrainArmy, mid: int, index: int, grid: Object) -> Dictionary:
	var move: CombatMovePlan = team._combat_move_plan
	var plan: CombatDeploymentPlan = team._combat_deployment_plan
	if move == null or plan == null or grid == null or index < 0 or index >= team.cells.size(): return {}
	# Do not build/warm the shared distance field before timing the original call.
	# A missing/stale derived field is intentionally visible in this signature.
	var field: Dictionary = move.get_meta("_transit_distance_field", {})
	var here: Vector2i = team.cells[index]
	var target: Dictionary = FormationDestinationPlanner.resolve_member_target(move, plan, mid, here)
	var fid: int = team.try_get_formation_id()
	if fid <= 0: fid = team.team_id
	var registry: Object = team._coordinator.deployment_registry if team._coordinator != null else null
	var signature := {"from": here, "target": target, "path": move.path_epoch,
		"phase": move.phase, "order": move.order_serial, "assignment": move.member_assignment_epoch.get(mid, 0),
		"plan_terrain": move.terrain_revision, "terrain": team.data.navigation_revision,
		"short_translation": move.short_translation, "field_key": move.get_meta("_transit_distance_key", []),
		"distance": field.get(here, -1), "neighbors": []}
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var next := here + direction
		var owner: int = int(team._cell_owners.get(next, -1))
		var neighbor := {"cell": next, "distance": field.get(next, -1),
			"legal": FormationTransitPlanner._can_profile_step(team.data, here, next, team._formation_movement_profile),
			"external": team._is_external_cell(next, mid),
			"lease": registry != null and registry.is_slot_reserved(next, fid),
			"reserved": team._reserved_cells.has(next), "blocked": grid.blocked_destinations.has(next),
			"grid_owner": grid.initial_occupancy.get(next, -1), "owner_index": owner}
		if owner >= 0 and owner < team.combat_units.size():
			var owner_id: int = team.combat_identity(owner)
			neighbor["owner"] = {"id": owner_id, "moving_to": team.moving_to[owner],
				"member": team.is_member(owner), "can_act": team.combat_can_act(owner),
				"controlled": team.is_controlled_person(owner),
				"target": FormationDestinationPlanner.resolve_member_target(move, plan, owner_id, next)}
		signature.neighbors.append(neighbor)
	return signature

func rw_intent_result(team: TerrainArmy, mid: int, ticket: Dictionary, result: Dictionary, elapsed: int) -> void:
	rw_totals.intent_calls += 1
	rw_totals.intent_original_usec += elapsed
	if ticket.is_empty(): return
	var pending: Dictionary = rw_pending[team.team_id]["members"]
	if ticket.caller == "prepare":
		pending[mid] = {"signature": ticket.signature, "result": result.duplicate(true), "usec": elapsed}
		return
	if not pending.has(mid): return
	var original: Dictionary = pending[mid]
	pending.erase(mid)
	var inputs_equal: bool = original.signature == ticket.signature
	var result_equal: bool = original.result == result
	rw_totals.intent_paired_samples += 1
	rw_totals.observable_inputs_equal += int(inputs_equal)
	rw_totals.result_equal += int(result_equal)
	if inputs_equal and result_equal:
		rw_totals.inputs_and_result_equal += 1
		rw_totals.equal_pair_propose_original_usec += elapsed
	if rw_examples.size() < 12 or (not result_equal and rw_examples.size() < 24):
		rw_examples.append({"team": team.team_id, "tick": ticket.tick, "member": mid,
			"observable_inputs_equal": inputs_equal, "result_equal": result_equal,
			"prepare": original, "propose": {"signature": ticket.signature, "result": result, "usec": elapsed}})

func _finish() -> void:
	if finished: return
	var diagnostic := {"installed": rw_installed, "totals": rw_totals, "examples": rw_examples,
		"max_prepare_samples": RW_MAX_SAMPLES,
		"army_disk_source_unchanged": FileAccess.get_sha256(RW_ARMY) == rw_disk_hash,
		"scope": "Original results retained. Roster equality means repeated same-tick output only. Intent equality is observable-input equality, not proof of cross-phase or cross-tick cache safety. Same failed route query does not assert unchanged dynamic blockers. Added signature/stack overhead makes this diagnostic unsuitable as an FPS baseline.",
		"original_timers_exclude_signature": true, "engine_script_profiler_enabled_by_this_test": false}
	report["repeated_work_diagnostic"] = diagnostic
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var file := FileAccess.open(output + "/repeated_work.json", FileAccess.WRITE)
	if file == null:
		faults.append("Could not save repeated-work diagnostics")
	else:
		file.store_string(JSON.stringify(diagnostic, "\t"))
		file.close()
	if not bool(diagnostic.army_disk_source_unchanged): faults.append("Army disk source changed during diagnostic")
	super._finish()
