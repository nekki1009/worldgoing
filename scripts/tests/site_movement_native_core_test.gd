extends SceneTree
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const OUTPUT := "res://output/site_movement_batch_implementation_20260928/revision2/native_core_parity.json"
var route_checks := 0
var target_checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _route(army: TerrainArmy, start: Vector2i, goal: Vector2i, limit: int, allow: bool, avoid: bool, profile: Object, label: String) -> void:
	var snapshots: Array = []
	var hits_before := army.native_local_route_hits
	for native: bool in [false, true]:
		army.native_local_route_enabled = native
		army.expanded_nodes = 0
		army.local_search_expansions = 0
		army.max_local_search_expansions = 0
		army.direct_route_hits = 0
		army.profiled_search_cap_failures = 0
		var status := {"track_dynamic": true}
		var path := army._find_local_route(start, goal, limit, allow, -1, 0, false, profile, avoid, status)
		snapshots.append([path, status, army.expanded_nodes, army.local_search_expansions, army.max_local_search_expansions, army.direct_route_hits, army.profiled_search_cap_failures])
	assert(snapshots[0] == snapshots[1], "Route parity %s limit=%d allow=%s avoid=%s GD=%s native=%s" % [label, limit, allow, avoid, snapshots[0], snapshots[1]])
	assert(army.native_local_route_hits == hits_before + 1, "Native route not admitted: " + label)
	route_checks += 1

func _targets(army: TerrainArmy, label: String) -> void:
	var results: Array = []
	for native: bool in [false, true]:
		army.native_move_intent_enabled = native
		army._combat_deployment_plan.centered_platform_handoff = TerrainArmy.INVALID_CELL
		var context := army._movement_target_context()
		if native:
			var active := 0
			for index in range(army.combat_units.size()): active += int(army.is_member(index) and army.combat_can_act(index))
			assert(context.targets.size() == active, "Native target context not populated: " + label)
		var targets := {}
		for index in range(army.combat_units.size()):
			if not army.is_member(index) or not army.combat_can_act(index): continue
			var identity := army.combat_identity(index)
			targets[identity] = FormationDestinationPlanner.resolve_member_target(army._combat_move_plan, army._combat_deployment_plan, identity, army.cells[index], context)
		results.append([targets, army._combat_deployment_plan.centered_platform_handoff])
	assert(results[0] == results[1], "Target parity %s GD=%s native=%s" % [label, results[0], results[1]])
	target_checks += 1

func _run() -> void:
	var data := Helper.build_flat_map(40, 30)
	var army := Helper.create_test_army(data, 1, 1, 4, Vector2i(4, 4))
	root.add_child(army)
	army.set_process(false)
	army.combat_profile_enabled = true
	for index in range(4): army.combat_units[index].person_id = 9007199254741000 + index
	army._invalidate_combat_identity_cache()
	var other := Helper.create_test_army(data, 2, 2, 2, Vector2i(20, 20))
	root.add_child(other)
	other.set_process(false)
	army.external_blocker = other.blocks_cell
	var actor := TerrainTestCharacter.new()
	actor.data = data
	actor.terrain_cell = Vector2i(17, 5)
	actor.movement_from_cell = Vector2i(16, 5)
	actor._movement_duration = 0.38
	actor._movement_elapsed = 0.1
	army.player = actor
	var coordinator := SiteCombatMovementCoordinator.new()
	army._coordinator = coordinator
	army._combat_move_plan = CombatMovePlan.new()
	army._combat_deployment_plan = CombatDeploymentPlan.new()
	var plan: CombatMovePlan = army._combat_move_plan
	var deployment: CombatDeploymentPlan = army._combat_deployment_plan
	plan.destination_plan = deployment
	plan.terrain_revision = data.navigation_revision
	plan.macro_path.assign([Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5)])
	deployment.approach_bottlenecked = 1
	army.combat_order = TerrainArmy.CombatOrder.MOVE
	var standard := FormationMovementProfile.new()
	for scenario in range(8):
		data.flags.fill(TerrainData.Flag.WALKABLE)
		data.height_levels.fill(0)
		data.ramp_edges.fill(0)
		data.static_blocked.fill(0)
		army._cell_owners.clear()
		army._reserved_cells.clear()
		other._cell_owners.clear()
		other._reserved_cells.clear()
		coordinator.movement_reservation_grid.blocked_destinations.clear()
		match scenario:
			1:
				for y in range(3, 10): data.static_blocked[data.index(Vector2i(9, y))] = 1
			2:
				army.cells[0] = Vector2i(8, 5)
				army.combat_slots[0] = Vector2i(12, 5)
				army._cell_owners[army.cells[0]] = 0
				army.cells[1] = Vector2i(9, 6)
				army.combat_slots[1] = army.cells[1]
				army._cell_owners[army.cells[1]] = 1
			3:
				army._reserved_cells[Vector2i(8, 5)] = 0
				army._reserved_cells[Vector2i(9, 5)] = -1
				other._cell_owners[Vector2i(9, 6)] = 0
				other._reserved_cells[Vector2i(10, 4)] = 1
			4:
				coordinator.movement_reservation_grid.blocked_destinations[Vector2i(6, 5)] = true
				coordinator.movement_reservation_grid.blocked_destinations[Vector2i(5, 6)] = true
			5:
				other._cell_owners[Vector2i(15, 5)] = 0
			6:
				for direction: Vector2i in TerrainData.DIRECTIONS: data.static_blocked[data.index(Vector2i(5, 5) + direction)] = 1
			7:
				for y in range(data.size.y):
					for x in range(10, data.size.x): data.height_levels[data.index(Vector2i(x, y))] = 1
				data.ramp_edges[data.index(Vector2i(9, 5))] = 1 << 1
				data.ramp_edges[data.index(Vector2i(10, 5))] = 1 << 3
		for limit: int in [-1, 0, 1, 5, 16, 64, 256]:
			for allow: bool in [false, true]:
				for avoid: bool in [false, true]:
					_route(army, Vector2i(5, 5), Vector2i(15, 5), limit, allow, avoid, standard, "scenario %d" % scenario)
		if scenario == 7:
			_route(army, Vector2i(5, 5), Vector2i(18, 5), 256, true, false, FormationMovementProfile.new(1, 0, true), "level-only")
			_route(army, Vector2i(5, 5), Vector2i(18, 5), 256, true, false, FormationMovementProfile.new(1, 1, false), "ramp-disabled")
			_route(army, Vector2i(5, 5), Vector2i(18, 5), 256, true, false, null, "null-profile")
	# Borrow current claims again for every search, including after a predecessor reserves.
	data.height_levels.fill(0)
	army._reserved_cells.clear()
	_route(army, Vector2i(5, 5), Vector2i(15, 5), 256, true, false, standard, "before claim")
	army._reserved_cells[Vector2i(6, 5)] = 3
	_route(army, Vector2i(5, 5), Vector2i(15, 5), 256, true, false, standard, "after claim")
	# Target roles, precedence, soft progress and the broad-footprint handoff.
	deployment.ingress_cell = Vector2i(2, 10)
	deployment.resolved_anchor = Vector2i(20, 10)
	deployment.final_facing = Vector2i.RIGHT
	deployment.assignment_epoch = 13
	plan.macro_path.clear()
	for x in range(2, 21): plan.macro_path.append(Vector2i(x, 10))
	for y in range(5, 16):
		for x in range(10, 31): deployment.platform_footprint.append(Vector2i(x, y))
	for index in range(24): deployment.platform_slots.append(Vector2i(18 + index % 4, 7 + floori(float(index) / 4.0)))
	for index in range(4):
		var mid := army.combat_identity(index)
		deployment.member_slot_map[mid] = Vector2i(25, 10 + index)
		plan.member_assignment_epoch[mid] = 4
		plan.member_soft_assignment_epoch[mid] = 7
		plan.member_transit_slots[mid] = Vector2i(11, 10 + index)
		army.cells[index] = Vector2i(12, 10 + index)
	var first := army.combat_identity(0)
	var second := army.combat_identity(1)
	var third := army.combat_identity(2)
	var fourth := army.combat_identity(3)
	_targets(army, "default roles")
	deployment.approach_bottlenecked = 0
	_targets(army, "broad centered handoff")
	deployment.member_role_map[second] = CombatMovementTypes.CombatDestinationRole.APPROACH_QUEUE
	_targets(army, "queue hold")
	deployment.queue_released = true
	plan.member_queue_egress_waypoint[second] = Vector2i(14, 12)
	plan.member_entry_waypoint[third] = Vector2i(13, 11)
	plan.member_crossed_swap_hold[first] = true
	plan.member_recovery_hold[fourth] = true
	_targets(army, "queue and hold precedence")
	plan.member_crossed_swap_hold.clear()
	plan.member_recovery_hold.clear()
	plan.member_entry_waypoint.clear()
	plan.member_vacancy_chain_target[first] = deployment.member_slot_map[first]
	deployment.ever_admitted_platform_member_ids[third] = true
	army.cells[2] = Vector2i(8, 10)
	plan.member_entry_waypoint[third] = Vector2i(13, 11)
	_targets(army, "former entrant wins waypoint")
	plan.member_vacancy_chain_target.clear()
	plan.member_entry_hold[first] = true
	deployment.admitted_platform_member_ids.append(fourth)
	_targets(army, "entry wait and admitted")
	plan.member_entry_hold.clear()
	army.cells[0] = Vector2i(9, 10)
	plan.member_path_s[first] = 1.0
	plan.member_observed_path_s[first] = 8.0
	deployment.member_slot_map.erase(third)
	_targets(army, "soft behind and missing final")
	army.native_hot_enabled = true
	assert(army._try_install_combat_hot_store())
	army.combat_hot_set(1, &"ko", 2.0)
	army.combat_hot_set(2, &"member", false)
	_targets(army, "hot eligibility")
	var result := {"status": "PASS", "route_checks": route_checks, "target_checks": target_checks,
		"paths_status_expansions_equal": true, "int64_id": first}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	print("MOVEMENT_NATIVE_CORE_PASS ", JSON.stringify(result))
	army.player = null
	army.free()
	other.free()
	actor.free()
	quit(0)
