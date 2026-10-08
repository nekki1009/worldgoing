extends SceneTree
## Successful infantry routes keep their original physical cursor and live claims.

const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/common-order-route.json"
const SITE_ID := "common-order-route-corridor"
const STEP := 0.05
const START := Vector2i(2, 4)
const GOAL := Vector2i(32, 4)

class CustomTerrain extends TerrainData:
	var step_calls := 0
	func can_step(from_cell: Vector2i, to_cell: Vector2i) -> bool:
		step_calls += 1
		return to_cell != Vector2i(4, 4) and super.can_step(from_cell, to_cell)

class CustomBlockArmy extends TerrainArmy:
	var blocked_cells: Dictionary = {}
	func blocks_cell(cell: Vector2i, _requester: Node = null) -> bool:
		return blocked_cells.has(cell)

var _armies: Array[TerrainArmy] = []
var _coordinators: Array[SiteCombatMovementCoordinator] = []

func _initialize() -> void:
	call_deferred("_run")
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("SITE COMMON ORDER ROUTE timed out")
		quit(1))

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("SITE COMMON ORDER ROUTE: " + message)
		_cleanup()
		quit(1)
	return condition

func _cleanup() -> void:
	for index in range(_armies.size()):
		if is_instance_valid(_armies[index]):
			_coordinators[index].unregister_formation(_armies[index])
			_armies[index].free()
	_armies.clear()
	_coordinators.clear()
	TerrainArmy.release_contact_source()

func _map() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(40, 30))
	data.preset = TerrainPreset.Kind.TERRACED_HIGHLAND
	data.seed_value = 581
	data.parameters = TerrainPreset.defaults(data.preset)
	data.parameters["size"] = data.size
	data.parameters["composition"] = "fixed_geography"
	data.height_levels.fill(1)
	data.flags.fill(0)
	data.ramp_edges.fill(0)
	for y in range(3, 6):
		for x in range(1, 38): data.flags[data.index(Vector2i(x, y))] = TerrainData.Flag.WALKABLE
	data.water_kind.resize(data.size.x * data.size.y)
	data.water_kind.fill(0)
	data.water_body.resize(data.size.x * data.size.y)
	data.water_body.fill(-1)
	data.spawn_cell = START
	data.parameters["fixed_base"] = {"base_kind": "fixed_geography", "atlas_id": "common-route-test",
		"base_revision": "1", "manifest_sha256": "common-route-test-v1".sha256_text(),
		"site_id": SITE_ID, "terrain_fingerprint": data.fingerprint(), "grid_contract_version": 1, "site": [0, 0]}
	SiteEnvironment.initialize(data, SITE_ID)
	if not _check(data.site.get("id") == SITE_ID and data.site.has("combat_left"), "Complete original Site fixture"): return null
	return data

func _load_base(_requested: Dictionary) -> Dictionary:
	var data := _map()
	if data == null: return {"ok": false}
	return {"ok": true, "data": data, "base": data.parameters.fixed_base}

func _new_army(data: TerrainData, snapshot: Dictionary = {}, positions: Array[Vector2i] = [START]) -> TerrainArmy:
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.exchange_enabled = true
	team.roster_size = positions.size()
	var coordinator := SiteCombatMovementCoordinator.new()
	_armies.append(team)
	_coordinators.append(coordinator)
	if snapshot.is_empty():
		if not _check(team.deploy_at(data, null, null, positions) and team.enable_combat(false), "Original one-person deployment"): return null
		coordinator.register_formation(team)
	else:
		coordinator.register_formation(team)
		team.restore_combat_state(snapshot, data, null, null)
	return team

func _advance(team: TerrainArmy) -> bool:
	var coordinator := _coordinators[_armies.find(team)]
	var source: Vector2i = team.cells[0]
	coordinator.combat_logic_tick_if_needed(STEP)
	team.prepare_combat(STEP)
	coordinator.complete_committed_moves()
	team.settle_combat_command()
	if team.cells[0] != source:
		if not _check(team.data.can_step(source, team.cells[0]), "Physical commit must remain one legal terrain edge"): return false
		if not _check(not team._is_external_cell(team.cells[0]), "Physical commit cannot cross a dynamic blocker"): return false
	return _check(team._cell_owners.get(team.cells[0], -1) == 0
		and (team.moving_to[0] == TerrainArmy.INVALID_CELL or team._reserved_cells.get(team.moving_to[0], -1) == 0),
		"Original occupancy and destination reservation must own every physical step")

func _wait_for_step(team: TerrainArmy, count: int) -> bool:
	for _tick in range(200):
		if not _advance(team): return false
		if team.completed_steps() >= count and team.moving_to[0] == TerrainArmy.INVALID_CELL: return true
	return _check(false, "Expected a physically completed step")

func _wait_for_inflight(team: TerrainArmy) -> bool:
	for _tick in range(200):
		if not _advance(team): return false
		if team.moving_to[0] != TerrainArmy.INVALID_CELL and team.move_progress[0] > 0.0: return true
	return _check(false, "Expected a real partially completed reserved edge")

func _finish(team: TerrainArmy, goal: Vector2i) -> bool:
	for _tick in range(1600):
		if not _advance(team): return false
		if team.combat_order == TerrainArmy.CombatOrder.HOLD and team.cells[0] == goal and team.moving_to[0] == TerrainArmy.INVALID_CELL:
			return true
	return _check(false, "Original order failed to arrive at %s: %s / %s" % [goal, team.cells, team.combat_order])

func _long_route_and_save() -> bool:
	var data := _map()
	if data == null: return false
	var team := _new_army(data)
	if team == null: return false
	if not _check(bool(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.RETREAT, GOAL).ok), "Start original RETREAT"): return false
	if not _wait_for_inflight(team): return false
	var destination: Vector2i = team.moving_to[0]
	var progress: float = team.move_progress[0]
	var route: Array = team._follower_routes.get(0, [])
	if not _check(route.size() == 31 and team._follower_combat_route_stamps.has(0), "Long legal route must be retained by the original follower owner"): return false
	var rejected: Dictionary = team.issue_combat_order(-99, TerrainArmy.CombatOrder.HOLD)
	if not _check(not bool(rejected.ok) and is_same(route, team._follower_routes.get(0, [])), "Rejected command must preserve successful route"): return false
	if not _check(bool(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.RETREAT, GOAL).ok)
		and team._follower_combat_route_stamps.is_empty() and team.moving_to[0] == destination and team.move_progress[0] == progress,
		"Accepted repeated command invalidates unstarted route without cancelling committed motion"): return false
	data.site["army_trial_active"] = true
	data.site["army_next_team"] = 2
	data.site["actors"] = {}
	data.site["armies"] = [team.capture_combat_state()]
	var saved := Store.save(data, SAVE)
	if not _check(bool(saved.get("ok", false)), "SiteStore must accept original in-flight snapshot: " + str(saved)): return false
	var loaded := Store.load_site(SAVE, _load_base)
	if not _check(bool(loaded.get("ok", false)) and loaded.get("data") is TerrainData, "SiteStore must restore original snapshot: " + str(loaded)): return false
	var loaded_data: TerrainData = loaded.data
	if not _check(loaded_data.site.get("armies", []).size() == 1, "Saved army must remain present"): return false
	var copy := _new_army(loaded_data, loaded_data.site.armies[0])
	if copy == null: return false
	if not _check(copy._follower_combat_route_stamps.is_empty() and copy._follower_routes.is_empty()
		and copy.cells == team.cells and copy.moving_to == team.moving_to and copy.move_progress == team.move_progress,
		"Restore preserves physical edge and discards rebuildable route storage"): return false
	if not _finish(team, GOAL) or not _finish(copy, GOAL): return false
	return _check(team.completed_steps() >= 30 and copy.completed_steps() >= 29
		and team.route_calls <= 3 and copy.route_calls <= 2 and team.route_calls < team.completed_steps(),
		"Long corridor must physically arrive with fewer searches than steps; source=%d/%d restored=%d/%d" %
		[team.route_calls, team.completed_steps(), copy.route_calls, copy.completed_steps()])

func _dynamic_and_terrain_invalidation() -> bool:
	var data := _map()
	if data == null: return false
	var team := _new_army(data)
	if team == null: return false
	var blockers: Dictionary = {}
	team.external_blocker = func(cell: Vector2i) -> bool: return blockers.has(cell)
	if not _check(bool(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.RETREAT, GOAL).ok), "Start dynamic-block retreat"): return false
	if not _wait_for_step(team, 1): return false
	var route: Array = team._follower_routes[0]
	var cursor := int(team._follower_route_cursors[0])
	var blocked: Vector2i = route[cursor]
	blockers[blocked] = true
	var calls := team.route_calls
	if not _wait_for_inflight(team): return false
	if not _check(team.route_calls == calls + 1 and team.moving_to[0] != blocked
		and not team._follower_routes[0].has(blocked), "New external obstruction must replan in the same due review"): return false
	if not _wait_for_step(team, 2): return false
	blockers.clear()
	route = team._follower_routes[0]
	cursor = int(team._follower_route_cursors[0])
	if not _check(cursor + 2 < route.size(), "Terrain fixture needs an obstruction beyond the next edge"): return false
	var future: Vector2i = route[cursor + 2]
	data.flags[data.index(future)] = 0
	data.navigation_revision += 1
	calls = team.route_calls
	if not _wait_for_inflight(team): return false
	if not _check(team.route_calls == calls + 1 and not team._follower_routes[0].has(future), "Navigation revision invalidates the whole route while its next edge is still clear"): return false
	return _finish(team, GOAL)

func _pursuit_goal_and_return() -> bool:
	var data := _map()
	if data == null: return false
	var team := _new_army(data)
	if team == null: return false
	var target := {"cell": Vector2i(16, 4)}
	team.target_query = func(_team: TerrainArmy, _identity: int) -> Dictionary: return target
	if not _check(bool(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.PURSUE, TerrainArmy.INVALID_CELL, 9999).ok), "Original PURSUE admission"): return false
	if not _wait_for_step(team, 2): return false
	var calls := team.route_calls
	target.cell = Vector2i(18, 4)
	if not _wait_for_inflight(team): return false
	if not _check(team.route_calls == calls + 1 and team._follower_route_goals.get(0) == target.cell, "Moving pursuit target invalidates old goal route"): return false
	var destination: Vector2i = team.moving_to[0]
	var progress: float = team.move_progress[0]
	target.clear()
	if not _advance(team): return false
	if not _check(team.combat_order == TerrainArmy.CombatOrder.RETURN and team.moving_to[0] == destination
		and team.move_progress[0] > progress, "Lost target changes to RETURN while prior committed edge continues"): return false
	if not _wait_for_step(team, 3): return false
	calls = team.route_calls
	if not _wait_for_inflight(team): return false
	if not _check(team.route_calls == calls + 1 and team._follower_route_goals.get(0) == START
		and team._follower_combat_route_stamps[0][1] == TerrainArmy.CombatOrder.RETURN,
		"RETURN must build its own original-origin route, never consume the old chase suffix"): return false
	return _finish(team, START)

func _custom_fallback() -> bool:
	var data := CustomTerrain.new()
	data.allocate(Vector2i(12, 9))
	data.height_levels.fill(1)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	var team := _new_army(data)
	if team == null: return false
	if not _check(bool(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.RETREAT, Vector2i(8, 4)).ok), "Custom terrain original order"): return false
	var calls := team.route_calls
	var first := team._common_order_route_step(0, Vector2i(8, 4), 0)
	var second := team._common_order_route_step(0, Vector2i(8, 4), 0)
	return _check(first != TerrainArmy.INVALID_CELL and second == first and team.route_calls == calls + 2
		and team._follower_combat_route_stamps.is_empty() and data.step_calls > 0,
		"Custom terrain must retain original per-review path and overridden step rules")

func _exhausted_failure_reuse_and_release() -> bool:
	var data := _map()
	if data == null: return false
	var team := _new_army(data)
	var barrier: Array[Vector2i] = [Vector2i(10, 3), Vector2i(10, 4), Vector2i(10, 5)]
	var enemy := _new_army(data, {}, barrier)
	if team == null or enemy == null: return false
	team.external_blocker = enemy.blocks_cell
	if not _check(bool(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.RETREAT, GOAL).ok), "Start blocked retreat"): return false
	var first := team._common_order_route_step(0, GOAL, 0)
	var searches := team.route_calls
	var expansions := team.expanded_nodes
	if not _check(first == TerrainArmy.INVALID_CELL and searches == 1 and team._follower_failed_combat_routes.has(0),
		"Exhausted canonical path records its original owner inputs"): return false
	var again := team._common_order_route_step(0, GOAL, 0)
	if not _check(again == TerrainArmy.INVALID_CELL and team.route_calls == searches and team.expanded_nodes == expansions,
		"Unchanged exhausted path reuses failure without another search"): return false
	# The other Army releases one claimed cell: the next original review must search.
	enemy._cell_owners.erase(barrier[1])
	var opened := team._common_order_route_step(0, GOAL, 0)
	if not _check(opened != TerrainArmy.INVALID_CELL and team.route_calls == searches + 1
		and team._follower_routes.has(0) and not team._follower_failed_combat_routes.has(0),
		"Released remote exit must find a route immediately through original owner data"): return false
	return true

func _failed_route_key_and_cap() -> bool:
	var data := _map()
	if data == null: return false
	var team := _new_army(data)
	if team == null: return false
	for y in range(3, 6): data.flags[data.index(Vector2i(10, y))] = 0
	if not _check(bool(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.RETREAT, GOAL).ok), "Start static no-path retreat"): return false
	if not _check(team._common_order_route_step(0, GOAL, 0) == TerrainArmy.INVALID_CELL
		and team._follower_failed_combat_routes.has(0), "Static exhausted result may be reused"): return false
	var calls := team.route_calls
	if not _check(bool(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.RETREAT, GOAL).ok)
		and team._follower_failed_combat_routes.is_empty(), "Accepted new command clears failed route"): return false
	team._common_order_route_step(0, GOAL, 0)
	if not _check(team.route_calls == calls + 1, "New command searches at its original review"): return false
	data.flags[data.index(Vector2i(10, 4))] = TerrainData.Flag.WALKABLE
	data.navigation_revision += 1
	var recovered := team._common_order_route_step(0, GOAL, 0)
	if not _check(recovered != TerrainArmy.INVALID_CELL and team.route_calls == calls + 2,
		"Terrain revision opens the route in the next review"): return false
	var route_status: Dictionary = {"track_dynamic": true}
	var capped := team._find_local_route(START, GOAL, 1, false, -1, 0, false, null, false, route_status)
	return _check(capped.is_empty() and route_status.get("outcome", "") == "capped"
		and not bool(route_status.get("outcome", "") == "exhausted"),
		"Expansion cap must never masquerade as exhausted failure")

func _lab_custom_participant_fallback() -> bool:
	var data := _map()
	if data == null: return false
	var team := _new_army(data)
	if team == null: return false
	var custom := CustomBlockArmy.new()
	custom.data = data
	for y in range(3, 6): custom.blocked_cells[Vector2i(10, y)] = true
	var lab := TerrainLab.new()
	lab.terrain = data
	lab.combat_armies = [team, custom]
	team.external_blocker = lab._armies_block_cell.bind(team)
	if not _check(bool(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.RETREAT, GOAL).ok),
		"Start lab callback with scripted participant"): return false
	var first := team._common_order_route_step(0, GOAL, 0)
	var second := team._common_order_route_step(0, GOAL, 0)
	var valid := _check(first == TerrainArmy.INVALID_CELL and second == TerrainArmy.INVALID_CELL
		and team.route_calls == 2 and team._follower_failed_combat_routes.is_empty(),
		"Lab callback must not reuse failure when any participant overrides blocks_cell")
	lab.free()
	custom.free()
	return valid

func _run() -> void:
	if not _long_route_and_save(): return
	if not _dynamic_and_terrain_invalidation(): return
	if not _pursuit_goal_and_return(): return
	if not _custom_fallback(): return
	if not _exhausted_failure_reuse_and_release(): return
	if not _failed_route_key_and_cap(): return
	if not _lab_custom_participant_fallback(): return
	print("SITE COMMON ORDER ROUTE PASS: physical cursor, live blockers, failed-route dependency reuse/release, capped refusal, terrain revision, pursuit/return, orders, SiteStore restore, custom fallback")
	_cleanup()
	quit(0)
