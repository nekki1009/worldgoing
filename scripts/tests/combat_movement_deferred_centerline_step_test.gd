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
	var budget := SiteRouteBudget.new() # No formation allocation: zero A* calls.
	var cached: Array[Vector2i] = [start, occupied, tail, goal]
	plan.member_paths[lead] = cached
	plan.stamp_member_route(lead, goal)
	army._refresh_member_route_caches(budget)
	if not _require(plan.is_member_route_current(lead, goal) and not army._capped_transit_steps.has(lead) \
		and army.profiled_deferred_step_eligible == 0 and army.route_calls == 0,
		"A current full route must not be replaced by a deferred edge"): return
	plan.invalidate_member_route(lead)
	army._refresh_member_route_caches(budget)
	if not _require(army.route_calls == 0 and plan.member_defer_count.get(lead, 0) == 1 \
		and not plan.member_paths.has(lead) and army._capped_transit_steps.has(lead) \
		and bool(army._capped_transit_steps[lead].get("deferred", false)) \
		and army.profiled_deferred_step_eligible == 1 and army.profiled_capped_step_eligible == 0,
		"Zero route budget must offer one transient deferred edge, age its member, and make no A* call"): return
	if not _require(army._current_capped_transit_step(lead, 0, goal, grid) == occupied,
		"Deferred step must revalidate the legal forward centerline edge"): return
	army.combat_slots[1] = occupied
	if not _require(army._current_capped_transit_step(lead, 0, goal, grid) == TerrainArmy.INVALID_CELL,
		"Standing owner must block a deferred step"): return
	army.combat_slots[1] = tail
	grid.blocked_destinations[occupied] = true
	if not _require(army._current_capped_transit_step(lead, 0, goal, grid) == TerrainArmy.INVALID_CELL,
		"In-flight destination claim must block a deferred step"): return
	grid.blocked_destinations.clear()
	coordinator.deployment_registry.try_replace_reservations(99, -1, 1, [occupied])
	if not _require(army._current_capped_transit_step(lead, 0, goal, grid) == TerrainArmy.INVALID_CELL,
		"Foreign final lease must block a deferred step"): return
	coordinator.deployment_registry.release_order(99)
	plan.path_epoch += 1
	if not _require(army._current_capped_transit_step(lead, 0, goal, grid) == TerrainArmy.INVALID_CELL,
		"Changed path epoch must invalidate the current-tick stamp"): return
	plan.path_epoch -= 1
	if not _require(army._current_capped_transit_step(lead, 0, tail, grid) == TerrainArmy.INVALID_CELL,
		"Changed goal must invalidate the current-tick stamp"): return
	army.propose_combat_moves(grid)
	if not _require(army.profiled_deferred_step_proposed == 1 and army.profiled_capped_step_proposed == 0 \
		and grid.get_proposals().size() == 2,
		"Deferred member and empty-tail follower must submit legal dependency proposals"): return
	grid.resolve_all()
	var lookup: Dictionary = {}
	lookup[lead] = {"formation": army, "cell": start}
	lookup[follower] = {"formation": army, "cell": occupied}
	grid.commit_all(lookup, 1)
	if not _require(army.moving_to[0] == occupied and army.moving_to[1] == tail \
		and not plan.member_paths.has(lead),
		"Grid must commit the empty-tail chain without creating a cached full route"): return
	army.finalize_combat_movement_tick(0.1, grid, coordinator.deployment_registry)
	if not _require(army.profiled_deferred_step_accepted == 1 and army.profiled_capped_step_accepted == 0,
		"Accepted deferred edge must stay separate from true-cap counters"): return
	print("COMBAT MOVEMENT DEFERRED CENTERLINE STEP PASS")
	army.free()
	quit(0)

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false
