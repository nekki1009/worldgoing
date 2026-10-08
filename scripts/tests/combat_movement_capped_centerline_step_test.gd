extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data := Helper.build_flat_map(20, 3)
	for x in range(20):
		data.static_blocked[data.index(Vector2i(x, 0))] = 1
		data.static_blocked[data.index(Vector2i(x, 2))] = 1
	var start := Vector2i(1, 1)
	var occupied := Vector2i(2, 1)
	var tail := Vector2i(3, 1)
	var goal := Vector2i(17, 1)
	var army := Helper.create_test_army(data, 1, 0, 2, start)
	army.combat_profile_enabled = true
	army._formation_movement_profile = FormationMovementProfile.new()
	var coordinator := SiteCombatMovementCoordinator.new()
	army.set_coordinator(coordinator)
	army.combat_order = TerrainArmy.CombatOrder.MOVE
	army._order_delay = 0.0
	var lead := army.combat_identity(0)
	var follower := army.combat_identity(1)
	army.combat_slots[0] = goal
	army.combat_slots[1] = tail
	var plan := CombatMovePlan.new()
	plan.order_serial = 1
	plan.terrain_revision = data.navigation_revision
	for x in range(19):
		plan.macro_path.append(Vector2i(x, 1))
	plan.member_observed_path_k[lead] = 1
	plan.member_path_s[lead] = 17.0
	plan.member_transit_slots[lead] = goal
	var destination := CombatDeploymentPlan.new()
	destination.order_serial = 1
	destination.set_approach_bottlenecked(true, occupied)
	plan.destination_plan = destination
	army._combat_move_plan = plan
	army._combat_deployment_plan = destination
	var grid := coordinator.movement_reservation_grid
	var occupancy: Dictionary = {}
	occupancy[start] = lead
	occupancy[occupied] = follower
	grid.begin_tick(occupancy, data)
	army.current_logic_tick = 1
	data.static_blocked[data.index(Vector2i(4, 1))] = 1
	var exhausted_status: Dictionary = {}
	var exhausted: Array[Vector2i] = army._find_local_route(start, goal, 64, true, -1, 0, false, army.get_formation_movement_profile(), false, exhausted_status)
	if not _require(exhausted.is_empty() and not bool(exhausted_status.get("capped", true)), "Exhausted A* must not report a search cap"): return
	data.static_blocked[data.index(Vector2i(4, 1))] = 0
	var pre_step := army._capped_transit_centerline_step(lead, 0, start, goal, false, grid)
	if not _require(pre_step == occupied,
		"Fixture must admit the forward step before A*: step=%s observed=%s width=%d verified=%s owner=%s grid=%s" % [
			pre_step, plan.member_observed_path_k.get(lead),
			FormationTransitPlanner.detect_corridor_width(data, occupied, Vector2i.RIGHT, army.get_formation_movement_profile()),
			FormationTransitPlanner._find_furthest_verified_head_s(1, 2, plan, data, army.get_formation_movement_profile()),
			army._cell_owners.get(occupied), grid.initial_occupancy.get(occupied)]): return
	var route: Array[Vector2i] = army._find_combat_route_after_rejection(lead, start, goal, 4)
	if not _require(route.is_empty() and army._capped_transit_steps.has(lead) and not plan.member_paths.has(lead) \
		and army.profiled_capped_step_eligible == 1,
		"True capped A* should retain only a transient one-step candidate, never a full route: route=%s cap=%d step=%s eligible=%d" % [
			route, army.profiled_search_cap_failures, army._capped_transit_steps.get(lead), army.profiled_capped_step_eligible]): return
	if not _require(army._current_capped_transit_step(lead, 0, goal, grid) == occupied,
		"Capped candidate must be the verified legal forward centerline edge"): return
	army.combat_slots[1] = occupied
	if not _require(army._capped_transit_centerline_step(lead, 0, start, goal, false, grid) == TerrainArmy.INVALID_CELL,
		"A stationary owner must block the fallback"): return
	army.combat_slots[1] = tail
	army.moving_to[1] = tail
	if not _require(army._capped_transit_centerline_step(lead, 0, start, goal, false, grid) == TerrainArmy.INVALID_CELL,
		"An in-flight owner must block the fallback"): return
	army.moving_to[1] = TerrainArmy.INVALID_CELL
	grid.blocked_destinations[occupied] = true
	if not _require(army._current_capped_transit_step(lead, 0, goal, grid) == TerrainArmy.INVALID_CELL,
		"A blocked destination claim must invalidate the fallback"): return
	grid.blocked_destinations.clear()
	coordinator.deployment_registry.try_replace_reservations(99, -1, 1, [occupied])
	if not _require(army._current_capped_transit_step(lead, 0, goal, grid) == TerrainArmy.INVALID_CELL,
		"Another formation's final lease must invalidate the fallback"): return
	coordinator.deployment_registry.release_order(99)
	if not _require(army._capped_transit_centerline_step(lead, 0, start, goal, true, grid) == TerrainArmy.INVALID_CELL,
		"Avoid-occupied-first-step retry must not use the occupied forward edge"): return
	plan.phase = CombatMovementTypes.CombatMovePhase.PLATFORM_INGRESS
	if not _require(army._current_capped_transit_step(lead, 0, goal, grid) == TerrainArmy.INVALID_CELL,
		"Fallback must not run after transit"): return
	plan.phase = CombatMovementTypes.CombatMovePhase.TRANSIT
	plan.macro_path.append(start)
	if not _require(army._current_capped_transit_step(lead, 0, goal, grid) == TerrainArmy.INVALID_CELL,
		"Ambiguous centerline membership must not produce a fallback"): return
	plan.macro_path.pop_back()
	plan.path_epoch += 1
	if not _require(army._current_capped_transit_step(lead, 0, goal, grid) == TerrainArmy.INVALID_CELL,
		"Changed path epoch must invalidate the transient candidate"): return
	plan.path_epoch -= 1
	if not _require(army._current_capped_transit_step(lead, 0, tail, grid) == TerrainArmy.INVALID_CELL,
		"Changed goal must invalidate the transient candidate"): return
	army.cells[0] = Vector2i(0, 1)
	if not _require(army._current_capped_transit_step(lead, 0, goal, grid) == TerrainArmy.INVALID_CELL,
		"Changed physical source must invalidate the transient candidate"): return
	army.cells[0] = start
	army.propose_combat_moves(grid)
	if not _require(grid.get_proposals().size() == 2 and army.profiled_capped_step_proposed == 1,
		"The valid dependency chain should submit exactly two one-edge proposals"): return
	grid.resolve_all()
	var lookup: Dictionary = {}
	lookup[lead] = {"formation": army, "cell": start}
	lookup[follower] = {"formation": army, "cell": occupied}
	grid.commit_all(lookup, 1)
	if not _require(army.moving_to[0] == occupied and army.moving_to[1] == tail and not plan.member_paths.has(lead),
		"Grid must commit the same-direction empty-tail chain without a cached full route"): return
	army.finalize_combat_movement_tick(0.1, grid, coordinator.deployment_registry)
	if not _require(army.profiled_capped_step_accepted == 1, "Accepted fallback must be counted only after Grid commit"): return
	army.combat_enabled = false
	army.prepare_combat_movement_tick(0.1, null, coordinator.deployment_registry)
	if not _require(army._capped_transit_steps.is_empty(), "Prepare must clear previous-tick transient candidates"): return
	if not _run_off_center_lane(): return
	print("COMBAT MOVEMENT CAPPED CENTERLINE STEP PASS")
	army.free()
	quit(0)

func _run_off_center_lane() -> bool:
	var data := Helper.build_flat_map(20, 4)
	for x in range(20):
		data.static_blocked[data.index(Vector2i(x, 0))] = 1
		data.static_blocked[data.index(Vector2i(x, 3))] = 1
	data.static_blocked[data.index(Vector2i(9, 2))] = 1
	var start := Vector2i(1, 2)
	var occupied := Vector2i(2, 2)
	var tail := Vector2i(3, 2)
	var goal := Vector2i(17, 2)
	var army := Helper.create_test_army(data, 2, 0, 2, start)
	army.combat_profile_enabled = true
	army._formation_movement_profile = FormationMovementProfile.new()
	if not _require(FormationTransitPlanner.detect_corridor_width(data, Vector2i(9, 1), Vector2i.RIGHT, army.get_formation_movement_profile()) == 1,
		"Off-center fixture must include a real one-cell choke on the macro path"): return false
	army.combat_order = TerrainArmy.CombatOrder.MOVE
	army._order_delay = 0.0
	var coordinator := SiteCombatMovementCoordinator.new()
	army.set_coordinator(coordinator)
	var lead := army.combat_identity(0)
	var follower := army.combat_identity(1)
	army.combat_slots[0] = goal
	army.combat_slots[1] = tail
	var plan := CombatMovePlan.new()
	plan.order_serial = 3
	plan.terrain_revision = data.navigation_revision
	plan.current_width = 2
	plan.pending_width = 2
	for x in range(19):
		plan.macro_path.append(Vector2i(x, 1))
	plan.member_observed_path_k[lead] = 9 # Deliberately stale: physical row membership is authoritative.
	plan.member_path_s[lead] = 17.0
	plan.member_transit_slots[lead] = goal
	var destination := CombatDeploymentPlan.new()
	destination.order_serial = plan.order_serial
	destination.set_approach_bottlenecked(true, Vector2i(9, 1))
	plan.destination_plan = destination
	army._combat_move_plan = plan
	army._combat_deployment_plan = destination
	var grid := coordinator.movement_reservation_grid
	var occupancy: Dictionary = {}
	occupancy[start] = lead
	occupancy[occupied] = follower
	grid.begin_tick(occupancy, data)
	army.current_logic_tick = 1
	var center := Vector2i(1, 1)
	army.cells[0] = center
	army._cell_owners.erase(start)
	army._cell_owners[center] = 0
	occupancy.erase(start)
	occupancy[center] = lead
	grid.begin_tick(occupancy, data)
	plan.member_observed_path_k[lead] = 1
	plan.macro_path[3] = Vector2i(2, 2)
	plan.macro_path[4] = Vector2i(1, 2)
	plan.macro_path[5] = Vector2i(2, 2)
	plan.path_epoch += 1
	if not _require(int(army._capped_transit_row_lookup().get(center, -2)) == -1 \
		and army._capped_transit_centerline_step(lead, 0, center, goal, false, grid) == Vector2i(2, 1),
		"Unique centerline must retain its original fallback even when another row side section overlaps"): return false
	plan.macro_path[3] = Vector2i(3, 1)
	plan.macro_path[4] = Vector2i(4, 1)
	plan.macro_path[5] = Vector2i(5, 1)
	plan.path_epoch += 1
	plan.member_observed_path_k[lead] = 9
	army.cells[0] = start
	army._cell_owners.erase(center)
	army._cell_owners[start] = 0
	occupancy.erase(center)
	occupancy[start] = lead
	grid.begin_tick(occupancy, data)
	if not _require(army._capped_transit_centerline_step(lead, 0, start, goal, false, grid) == occupied,
		"Unique off-center row must translate one step in the same lane despite stale observed k"): return false
	plan.macro_path[3] = Vector2i(2, 2)
	plan.macro_path[4] = Vector2i(3, 2)
	plan.path_epoch += 1
	if not _require(army._capped_transit_centerline_step(lead, 0, start, goal, false, grid) == TerrainArmy.INVALID_CELL,
		"A 90-degree bend must not translate a side lane onto a later centerline row"): return false
	plan.macro_path[3] = Vector2i(3, 1)
	plan.macro_path[4] = Vector2i(4, 1)
	plan.path_epoch += 1
	destination.order_serial += 1
	if not _require(army._capped_transit_centerline_step(lead, 0, start, goal, false, grid) == TerrainArmy.INVALID_CELL,
		"Destination order mismatch must invalidate the fallback"): return false
	destination.order_serial -= 1
	plan.macro_path[2] = plan.macro_path[1]
	plan.macro_path[3] = Vector2i(2, 1)
	plan.path_epoch += 1
	if not _require(int(army._capped_transit_row_lookup().get(start, -2)) == -1 \
		and army._capped_transit_centerline_step(lead, 0, start, goal, false, grid) == TerrainArmy.INVALID_CELL,
		"A cell in two static row cross-sections must be ambiguous"): return false
	plan.macro_path[2] = Vector2i(2, 1)
	plan.macro_path[3] = Vector2i(3, 1)
	plan.path_epoch += 1
	var route: Array[Vector2i] = army._find_combat_route_after_rejection(lead, start, goal, 4)
	if not _require(route.is_empty() and army._capped_transit_steps.has(lead) and not plan.member_paths.has(lead) \
		and army.profiled_capped_side_eligible == 1 and army.profiled_capped_center_eligible == 0,
		"Off-center lane true cap must store one edge only"): return false
	army.propose_combat_moves(grid)
	grid.resolve_all()
	var lookup: Dictionary = {}
	lookup[lead] = {"formation": army, "cell": start}
	lookup[follower] = {"formation": army, "cell": occupied}
	grid.commit_all(lookup, 1)
	if not _require(army.moving_to[0] == occupied and army.moving_to[1] == tail and not plan.member_paths.has(lead),
		"Grid must commit off-center same-direction empty-tail steps without a full route"): return false
	army.finalize_combat_movement_tick(0.1, grid, coordinator.deployment_registry)
	if not _require(army.profiled_capped_side_accepted == 1 and army.profiled_capped_center_accepted == 0,
		"Accepted off-center fallback must be counted in the side-lane bucket"): return false
	army.free()
	return true

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false
