extends SceneTree
## Only original Sustain collapse starts retreat; accepted physical edges survive it.

const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const SAVE := "res://.godot-temp/site_combat/tactical-ai-retreat.json"
const SITE_ID := "tactical-ai-retreat-bent-mountain"
const GOAL := Vector2i(5, 9)
const STEP := 0.05

class ObservedTerrain extends TerrainData:
	var step_calls := 0
	func can_step(from_cell: Vector2i, to_cell: Vector2i) -> bool:
		step_calls += 1
		return to_cell != Vector2i(2, 1) and super.can_step(from_cell, to_cell)

var _armies: Array[TerrainArmy] = []
var _coordinators: Array[SiteCombatMovementCoordinator] = []

func _initialize() -> void:
	call_deferred("_run")
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("SITE TACTICAL AI RETREAT timed out")
		quit(1))

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("SITE TACTICAL AI RETREAT: " + message)
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
	# Fixed geography supplies its own dry-land water classification.
	var count := data.size.x * data.size.y
	data.water_kind.resize(count)
	data.water_kind.fill(0)
	data.water_body.resize(count)
	data.water_body.fill(-1)
	data.height_levels.fill(3)
	data.flags.fill(0)
	data.ramp_edges.fill(0)
	for y in range(5, 13):
		for x in range(3, 9):
			_open_cell(data, Vector2i(x, y))
	for x in range(3): _open_cell(data, Vector2i(x, 9))
	for x in range(9, 19): _open_cell(data, Vector2i(x, 9))
	for y in range(10, 18): _open_cell(data, Vector2i(18, y))
	for x in range(19, 26): _open_cell(data, Vector2i(x, 17))
	for y in range(18, 23): _open_cell(data, Vector2i(25, y))
	data.spawn_cell = Vector2i(3, 5)
	data.parameters["fixed_base"] = {"base_kind": "fixed_geography", "atlas_id": "tactical-retreat-test",
		"base_revision": "1", "manifest_sha256": "tactical-retreat-test-v1".sha256_text(),
		"site_id": SITE_ID, "terrain_fingerprint": data.fingerprint(), "grid_contract_version": 1, "site": [0, 0]}
	SiteEnvironment.initialize(data, SITE_ID)
	if not _check(data.site.get("id") == SITE_ID and data.site.has("combat_left")
		and data.site.get("worker") is Dictionary, "Fixed retreat fixture must initialize a complete original Site"): return null
	return data

func _open_cell(data: TerrainData, cell: Vector2i) -> void:
	data.height_levels[data.index(cell)] = 1
	data.flags[data.index(cell)] = TerrainData.Flag.WALKABLE

func _load_base(_requested: Dictionary) -> Dictionary:
	var data := _map()
	if data == null: return {"ok": false, "code": "INVALID_FIXTURE"}
	return {"ok": true, "data": data, "base": data.parameters.fixed_base}

func _create_army(data: TerrainData, positions: Array[Vector2i] = []) -> TerrainArmy:
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.exchange_enabled = true
	if positions.is_empty():
		positions.assign([Vector2i(12, 9), Vector2i(14, 9), Vector2i(16, 9), Vector2i(18, 9),
			Vector2i(18, 11), Vector2i(18, 13), Vector2i(18, 15), Vector2i(18, 17),
			Vector2i(20, 17), Vector2i(22, 17), Vector2i(24, 17), Vector2i(25, 19)])
	team.roster_size = positions.size()
	var coordinator := Coordinator.new()
	_armies.append(team)
	_coordinators.append(coordinator)
	if not _check(team.deploy_at(data, null, null, positions) and team.enable_combat(false), "Bent-column deployment failed"): return null
	coordinator.register_formation(team)
	if not _install_sustain(team): return null
	return team

func _bind_sustain(team: TerrainArmy) -> void:
	team.sustain_routed_query = func(original: TerrainArmy) -> bool:
		return bool(original.data.site.team_supply[str(original.team_id)].sustain.routed)

func _install_sustain(team: TerrainArmy) -> bool:
	var members := {}
	var checkpoints := {}
	for row: Dictionary in team.combat_units:
		members[int(row.person_id)] = row
		checkpoints[str(row.person_id)] = 0
	var state := Sustain.create(SiteRuntime.now(team.data) * 60.0)
	if not _check(bool(Sustain.add_members(state, members, members.keys()).ok), "Original Sustain fixture enrollment failed"): return false
	if not team.data.site.has("team_supply"): team.data.site["team_supply"] = {}
	team.data.site.team_supply[str(team.team_id)] = {"version": 1, "sustain": state, "inventory": {},
		"training_order": false, "training_requester": -1, "revision": 0, "delivery": {}, "life_checkpoint": checkpoints}
	_bind_sustain(team)
	return true

func _collapse_sustain(team: TerrainArmy) -> bool:
	var entry: Dictionary = team.data.site.team_supply[str(team.team_id)]
	var members := {}
	for row: Dictionary in team.combat_units: members[int(row.person_id)] = row
	var outcome := Sustain.advance_to(entry.sustain, members, entry.inventory, float(entry.sustain.at) + 40.0 * Sustain.HOUR)
	team.data.site.minute = int(team.data.site.minute) + 2400
	return _check(bool(outcome.ok) and bool(outcome.routed_now) and team.is_sustain_routed()
		and float(entry.sustain.morale) <= 20.0 and outcome.damage.is_empty(),
		"Original Sustain must cross its morale threshold before retreat, without fake routed flags or casualty damage")

func _advance(team: TerrainArmy, coordinator: SiteCombatMovementCoordinator) -> bool:
	var prior := team.cells.duplicate()
	coordinator.combat_logic_tick_if_needed(STEP)
	team.prepare_combat(STEP)
	coordinator.complete_committed_moves()
	team.settle_combat_command()
	var occupied := {}
	for index in range(team.cells.size()):
		var cell: Vector2i = team.cells[index]
		if cell != prior[index] and not _check(team.data.can_step(prior[index], cell), "Original RETREAT teleported or crossed a cliff"): return false
		if bool(team.combat_hot_get(index, &"site_exited", false)):
			if not _check(team._edge_distance(cell) == 0 and team.moving_to[index] == TerrainArmy.INVALID_CELL,
				"A living exit requires physical arrival at a boundary with no unfinished edge"): return false
			continue # Exited original rows retain their last cell, but no longer occupy it.
		if not _check(not occupied.has(cell), "Original RETREAT produced duplicate physical cells"): return false
		occupied[cell] = true
	return true

func _all_exited(team: TerrainArmy) -> bool:
	for index in range(team.combat_units.size()):
		if not bool(team.combat_hot_get(index, &"site_exited", false)): return false
	return team.morale_retreat_terminal() and team.moving_member_count() == 0 \
		and team._cell_owners.is_empty() and team._reserved_cells.is_empty()

func _progress_error(team: TerrainArmy, copy: TerrainArmy) -> float:
	if team.move_progress.size() != copy.move_progress.size(): return INF
	var error := 0.0
	for index in range(team.move_progress.size()):
		error = maxf(error, absf(team.move_progress[index] - copy.move_progress[index]))
	return error

func _commander_route_anchor(team: TerrainArmy) -> bool:
	var original := team.current_commander
	if not _check(team._get_combat_route_anchor_cell() == team.cells[original], "Route starts from the real commander row, not an unrelated person ID or mean"): return false
	# Only qualified original officers may supply a command route anchor.
	if not _check(not team.command_eligible(3), "An ordinary soldier cannot supply the commander anchor"): return false
	var promoted := team.set_military_role(team.combat_identity(3), "officer")
	if not _check(bool(promoted.ok), "Original row 3 officer qualification failed: " + str(promoted)): return false
	team.current_commander = 3
	var row_anchor := team._get_combat_route_anchor_cell()
	team.current_commander = original
	if not _check(team.command_eligible(3) and row_anchor == team.cells[3], "A nonzero commander row must not be interpreted as another member's person ID"): return false
	var actor := TerrainTestCharacter.new()
	actor.military_role = "officer"
	actor.data = team.data
	actor.terrain_cell = Vector2i(4, 6)
	team.player_member = actor
	team.current_commander = TerrainArmy.PLAYER_MEMBER
	team.player_present = true
	var player_anchor := team._get_combat_route_anchor_cell()
	team.player_present = false
	var absent_anchor := team._get_combat_route_anchor_cell()
	team.player_present = true
	actor.knockout_left = 1.0
	var ko_anchor := team._get_combat_route_anchor_cell()
	team.player_member = null
	team.player_present = false
	team.current_commander = original
	var player_cell := actor.terrain_cell
	actor.free()
	return _check(player_anchor == player_cell and absent_anchor != player_cell and ko_anchor == absent_anchor,
		"Only an eligible present PLAYER_MEMBER supplies its original Actor cell; absent or KO commanders retain the legal fallback")

func _null_profile_routes(team: TerrainArmy) -> bool:
	var before := team.direct_route_hits
	var direct := team._find_local_route(Vector2i(4, 6), Vector2i(7, 6))
	if not _check(direct.size() == 4 and team.direct_route_hits == before + 1, "Null-profile infantry must use the existing direct route"): return false
	var prior_blocker := team.external_blocker
	team.external_blocker = func(cell: Vector2i) -> bool: return cell == Vector2i(5, 6)
	var detour := team._find_local_route(Vector2i(4, 6), Vector2i(7, 6))
	team.external_blocker = prior_blocker
	if not _check(detour.size() > 4 and not detour.has(Vector2i(5, 6)), "Null-profile A* must still avoid the current external blocker"): return false
	var cliff_route := team._find_local_route(Vector2i(8, 8), Vector2i(10, 9))
	if not _check(cliff_route.size() == 4 and not cliff_route.has(Vector2i(9, 8)), "Direct foot routing must go around the fixture cliff"): return false
	for route: Array[Vector2i] in [direct, detour, cliff_route]:
		for index in range(1, route.size()):
			if not _check(team.data.can_step(route[index - 1], route[index]), "Fast infantry route crossed an illegal terrain edge"): return false
	var custom := ObservedTerrain.new()
	custom.allocate(Vector2i(5, 4))
	custom.height_levels.fill(1)
	custom.flags.fill(TerrainData.Flag.WALKABLE)
	var probe := TerrainArmy.new()
	probe.data = custom
	probe.combat_enabled = true
	var custom_route := probe._find_local_route(Vector2i(1, 1), Vector2i(3, 1))
	var custom_valid := custom.step_calls > 0 and custom_route.size() > 3 and not custom_route.has(Vector2i(2, 1)) and probe.direct_route_hits == 0
	probe.free()
	return _check(custom_valid, "Custom terrain must retain its can_step override instead of canonical foot shortcuts")

func _fallback_outcomes() -> bool:
	for kind: String in ["edge", "building", "ally", "surrender", "unreachable"]:
		var data := _map()
		if data == null: return false
		if kind != "edge":
			data.flags[data.index(Vector2i(0, 9))] = 0
			data.navigation_revision += 1
		if kind in ["edge", "building", "unreachable"]:
			var entrance := GOAL
			if kind == "unreachable":
				entrance = Vector2i(35, 25)
				_open_cell(data, entrance)
			data.site.features["retreat-house"] = {"kind": "house", "stage": "complete",
				"entrance": data.index(entrance), "cells": [data.index(entrance + Vector2i.UP)], "solid": true}
		var team := _create_army(data, [Vector2i(6, 9)])
		if team == null: return false
		var coordinator: SiteCombatMovementCoordinator = _coordinators.back()
		var ally: TerrainArmy
		if kind == "ally":
			ally = TerrainArmy.new()
			root.add_child(ally)
			ally.set_process(false)
			ally.team_id = 2
			ally.roster_size = 1
			ally.exchange_enabled = true
			_armies.append(ally)
			_coordinators.append(coordinator)
			if not _check(ally.deploy_at(data, null, null, [Vector2i(4, 7)]) and ally.enable_combat(false), "Allied refuge fixture failed"): return false
			coordinator.register_formation(ally)
		if not _collapse_sustain(team): return false
		if not _check(bool(team.begin_morale_retreat().ok), "Sustain must begin " + kind + " retreat"): return false
		var original_cell := team.cells[0]
		for tick in range(200):
			if not _advance(team, coordinator): return false
			var step_outcome: Dictionary = team._retreat_resolution.get("members", {}).get(str(team.combat_identity(0)), {})
			if str(step_outcome.get("status", "")) in ["exited", "sheltered", "surrendered"]: break
		var outcome: Dictionary = team._retreat_resolution.get("members", {}).get(str(team.combat_identity(0)), {})
		if kind == "edge":
			if not _check(_all_exited(team) and str(outcome.get("kind", "")) == "edge", "Reachable boundary must outrank the closer completed building"): return false
		elif kind in ["building", "ally"]:
			if not _check(str(outcome.get("kind", "")) == kind and str(outcome.get("status", "")) == "sheltered"
				and not bool(team.combat_hot_get(0, &"site_exited", false)) and not bool(team.combat_hot_get(0, &"surrender_pending", false)),
				"No boundary: reachable " + kind + " must shelter the original person"): return false
			if kind == "building" and not _check(team._retreat_refuge_cells().has(team.cells[0]), "Building retreat must arrive at a real entrance or its walkable approach"): return false
			if kind == "ally" and not _check(team.cells[0].distance_squared_to(ally.cells[0]) == 1, "Allied refuge must stop adjacent to the original ally"): return false
		else:
			if not _check(team.cells[0] == original_cell and team.moving_to[0] == TerrainArmy.INVALID_CELL
				and bool(team.combat_hot_get(0, &"surrender_pending", false)) and not bool(team.combat_hot_get(0, &"captive", false))
				and not bool(team.combat_hot_get(0, &"site_exited", false)) and team.morale_retreat_terminal(),
				"No reachable boundary or refuge: surrender stays in place awaiting capture (" + kind + ")"): return false
	return true

func _run() -> void:
	var data := _map()
	if data == null: return
	var team := _create_army(data)
	if team == null: return
	if not _commander_route_anchor(team): return
	if not _null_profile_routes(team): return
	var coordinator := _coordinators[0]
	var displacement := GOAL - Vector2i(team.command_reference.floor())
	var rigid_legal := true
	for cell: Vector2i in team.cells:
		rigid_legal = rigid_legal and data.is_walkable(cell + displacement)
	if not _check(not rigid_legal, "Fixture must reject translating the complete bent column to this retreat area"): return
	var move := team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(25, 21))
	if not _check(bool(move.ok), "Initial original MOVE failed: " + str(move)): return
	var old_plan := team.get_active_move_plan()
	var serial := team.get_order_serial()
	var member := team.combat_identity(0)
	var source: Vector2i = team.cells[0]
	var endpoint := source + Vector2i.RIGHT
	coordinator._rebuild_occupancy()
	var grid := coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, data)
	var proposal := grid.propose_move(team.formation_runtime_id, member, serial, source, endpoint)
	grid.resolve_all()
	if not _check(proposal > 0 and grid.proposal_lookup[proposal].status == Types.MoveProposalStatus.ACCEPTED, "Original Grid refused the legal in-flight fixture step"): return
	grid.commit_all(coordinator._member_lookup, 1)
	coordinator._register_started_batches()
	team.prepare_combat(0.10)
	if not _check(team.cells[0] == source and team.moving_to[0] == endpoint and team.move_progress[0] > 0.0 and team.move_progress[0] < 1.0, "Fixture must stop inside a real committed edge"): return
	if not _check(team.set_tactical_ai_enabled(team.current_commander, true).ok, "Cannot enable original commander AI"): return
	var prior_slots := team.combat_slots.duplicate()
	var prior_progress := team.move_progress.duplicate()
	var prior_claims := team._reserved_cells.duplicate()
	var prior_batch := coordinator.get_inflight_batches_for_formation(team).duplicate(true)
	var prior_leases := coordinator.deployment_registry.get_formation_reserved_slots(team.team_id)
	var threats: Array[Vector2i] = [Vector2i(25, 21)]
	for request: Dictionary in [{"ai": false, "goal": GOAL}, {"ai": true, "goal": GOAL},
		{"ai": true, "goal": Vector2i(35, 25)}]:
		var refused: Dictionary = team.issue_tactical_ai_order(TerrainArmy.CombatOrder.RETREAT, request.goal, -1, threats) if request.ai \
			else team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.RETREAT, request.goal)
		if not _check(not bool(refused.ok) and (request.goal != GOAL or str(refused.code) == "NOT_ROUTED"),
			"Manual/AI RETREAT cannot bypass intact Sustain morale, even toward a legal safer goal: " + str(refused)): return
		if not _check(team.get_active_move_plan() == old_plan and team.get_order_serial() == serial and team.combat_slots == prior_slots
			and team.move_progress == prior_progress and team._reserved_cells == prior_claims
			and coordinator.get_inflight_batches_for_formation(team) == prior_batch
			and coordinator.deployment_registry.get_formation_reserved_slots(team.team_id) == prior_leases
			and team.combat_order == TerrainArmy.CombatOrder.MOVE and team.tactical_ai_enabled and not team.is_sustain_routed(),
			"Rejected RETREAT changed the original order, AI setting, lease or physical edge"): return
	if not _collapse_sustain(team): return
	var retreat := team.begin_morale_retreat()
	if not _check(bool(retreat.ok), "Original Sustain collapse failed to start retreat: " + str(retreat)): return
	if not _check(team.combat_order == TerrainArmy.CombatOrder.RETREAT and team.get_active_move_plan() == null and team.get_active_deployment_plan() == null
		and team.get_order_serial() == serial + 1 and not team.tactical_ai_enabled
		and team._retreat_resolution.reason == "morale_collapse", "Sustain must force the original RETREAT and stop tactical AI"): return
	if not _check(team.cells[0] == source and team.moving_to[0] == endpoint and team.move_progress == prior_progress
		and team._reserved_cells == prior_claims and coordinator.get_inflight_batches_for_formation(team) == prior_batch,
		"Morale collapse must preserve every accepted in-flight edge"): return
	for _tick in range(20):
		if not _advance(team, coordinator): return
		if team.cells[0] == endpoint: break
	if not _check(team.cells[0] == endpoint, "The already committed original MOVE edge must complete before retreat"): return
	for _tick in range(40):
		if not _advance(team, coordinator): return
		if team.completed_steps() > 1 and team.moving_member_count() > 0: break
	if not _check(team.completed_steps() > 1 and team.moving_member_count() > 0 and team.combat_order == TerrainArmy.CombatOrder.RETREAT,
		"RETREAT must physically continue and retain an unfinished edge for its mid-route save"): return
	var destinations: Array[Vector2i] = team.combat_slots.duplicate()
	data.site["army_trial_active"] = true
	data.site["army_next_team"] = 2
	data.site["actors"] = {}
	data.site["armies"] = [team.capture_combat_state()]
	var saved := Store.save(data, SAVE)
	if not _check(saved.has("ok") and bool(saved.get("ok", false)), "Original SiteStore rejected in-flight morale retreat: " + str(saved)): return
	var loaded := Store.load_site(SAVE, _load_base)
	if not _check(bool(loaded.get("ok", false)) and loaded.get("data") is TerrainData, "Original SiteStore failed to reload retreat: " + str(loaded)): return
	var loaded_data: TerrainData = loaded.data
	if not _check(loaded_data.site.get("armies") is Array and loaded_data.site.get("armies", []).size() == 1,
		"Reloaded retreat must contain exactly the saved original army"): return
	var copy := TerrainArmy.new()
	root.add_child(copy)
	copy.set_process(false)
	copy.exchange_enabled = true
	var copied_coordinator := Coordinator.new()
	_armies.append(copy)
	_coordinators.append(copied_coordinator)
	copied_coordinator.register_formation(copy)
	copy.restore_combat_state(loaded_data.site.armies[0], loaded_data, null, null)
	_bind_sustain(copy)
	# SiteStore's JSON transport converts numbers to floats and rounds decimal
	# tails; retain every resolution field and progress within 1e-12.
	var saved_resolution: Dictionary = JSON.parse_string(JSON.stringify(team._retreat_resolution))
	if not _check(copy.combat_order == TerrainArmy.CombatOrder.RETREAT and copy.combat_slots == destinations
		and copy.cells == team.cells and copy.moving_to == team.moving_to and _progress_error(team, copy) <= 0.000000000001
		and not copy.tactical_ai_enabled and copy.is_sustain_routed()
		and copy._retreat_resolution == saved_resolution,
		"Reload must preserve original Sustain collapse, retreat resolution, people and physical progress: " + str({
			"order": [team.combat_order, copy.combat_order], "slots_equal": copy.combat_slots == destinations,
			"cells_equal": copy.cells == team.cells, "destinations_equal": copy.moving_to == team.moving_to,
			"progress_error": _progress_error(team, copy), "ai": copy.tactical_ai_enabled,
			"routed": copy.is_sustain_routed(), "resolution_equal": copy._retreat_resolution == saved_resolution})): return
	for _tick in range(2400):
		if not _advance(team, coordinator) or not _advance(copy, copied_coordinator): return
		if _all_exited(team) and _all_exited(copy): break
	if not _check(_all_exited(team) and _all_exited(copy), "All twelve original members must physically leave within 120 simulated seconds; source=%s/%s copy=%s/%s" % [team.combat_order, team.cells, copy.combat_order, copy.cells]): return
	for original: TerrainArmy in [team, copy]:
		if not _check(original.combat_units.size() == 12 and original.get_active_members_occupancy().is_empty(), "Exit retains all original people but removes occupancy"): return
		for index in range(original.combat_units.size()):
			if not _check(float(original.combat_hot_get(index, &"hp")) > 0.0 and not bool(original.combat_hot_get(index, &"captive"))
				and not bool(original.combat_hot_get(index, &"surrender_pending", false)), "Leaving the map must not kill, capture or surrender the person"): return
	if not _fallback_outcomes(): return
	print("SITE TACTICAL AI RETREAT PASS: intact-morale rejection atomicity, Sustain collapse, bent mountain edges, twelve exits, SiteStore resume, edge priority, ally/building refuge and pending surrender")
	_cleanup()
	quit(0)
