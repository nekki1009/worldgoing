extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Grid = preload("res://scripts/terrain_lab/site_movement_reservation_grid.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("SITE MOVE ENCOUNTER timed out")
		quit(1))

func _run() -> void:
	var data := Helper.build_flat_map(30, 30)
	var army := Helper.create_test_army(data, 1, 0, 1, Vector2i(3, 3))
	var result := army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 15))
	assert(bool(result.get("ok", false)), "MOVE must be accepted: " + str(result))
	var plan := army.get_active_move_plan()
	var member_id := army.combat_identity(0)
	var source := army.cells[0]
	var step := source + Vector2i.RIGHT
	army._order_delay = 0.0
	army.combat_slots[0] = step
	var contacts := {0: {77: true}}
	army.publish_move_encounters(contacts)
	var published: Dictionary = contacts[0]
	published.clear()
	assert(army.exchange_initiates(0, 77, true), "Published adjacent enemy must be a legal MOVE melee initiator")
	assert(not army.exchange_initiates(0, 78, true), "MOVE cannot initiate against an unpublished enemy")
	assert(not army.exchange_initiates(0, 77, false), "MOVE contact does not authorize ranged fire")
	assert(plan.tactical_overlay == Types.TacticalOverlay.ENGAGING, "Contact must set ENGAGING on original move plan")
	var deployment := army.get_active_deployment_plan()
	var lease_slot := Vector2i(20, 20)
	deployment.slot_lease_timers[lease_slot] = 1.0
	army.update_combat_deployment(0.1)
	assert(is_equal_approx(float(deployment.slot_lease_timers[lease_slot]), 0.9),
		"ENGAGING must not freeze absence lease clocks")
	deployment.slot_lease_timers.erase(lease_slot)
	var grid := Grid.new()
	grid.begin_tick({source: member_id}, data)
	army.propose_combat_moves(grid)
	assert(grid.get_proposals().is_empty(), "Formation must not start an automatic step while engaging")
	army.moving_to[0] = step
	army.prepare_combat_movement_tick(0.1, null, null)
	assert(army.moving_to[0] == step and army.combat_order == TerrainArmy.CombatOrder.MOVE and army.get_active_move_plan() == plan,
		"Engagement must preserve the in-flight step and original MOVE plan")
	army.moving_to[0] = TerrainArmy.INVALID_CELL
	army.publish_move_encounters({})
	assert(plan.tactical_overlay == Types.TacticalOverlay.NONE and not army.exchange_initiates(0, 77, true),
		"Empty publication must end engagement and revoke stale contacts")
	army.combat_units[0]["work_task"] = {"test": true}
	army.publish_move_encounters({0: {77: true}})
	assert(not army.move_encounter_eligible(0) and plan.tactical_overlay == Types.TacticalOverlay.NONE,
		"A worker cannot create an automatic MOVE encounter")
	army.combat_units[0]["work_task"] = {}
	plan.tactical_overlay = Types.TacticalOverlay.ENGAGING # A restored plan has no saved contact references yet.
	grid.begin_tick({source: member_id}, data)
	army.propose_combat_moves(grid)
	assert(grid.get_proposals().is_empty() and not army.can_begin_committed_move(member_id, source, step, {}),
		"Restored ENGAGING must block proposals and commit before the next Lab query")
	army.publish_move_encounters({})
	assert(plan.tactical_overlay == Types.TacticalOverlay.NONE, "First empty Lab query must release restored ENGAGING")
	var cached_route: Array[Vector2i] = [source, step]
	plan.member_paths[member_id] = cached_route
	plan.stamp_member_route(member_id, step)
	for _attempt in range(3):
		grid.begin_tick({source: member_id}, data, {step: true})
		army.propose_combat_moves(grid)
		assert(grid.get_proposals().is_empty(), "External blocker must not create a rejected direct-route proposal")
	assert(int(plan.member_reservation_wait_age.get(member_id, 0)) == 3 and not plan.is_member_route_current(member_id, step),
		"Blocked cached edge must age and invalidate for bounded detour search")
	var farther := source + Vector2i(2, 0)
	army.external_blocker = func(cell: Vector2i) -> bool: return cell == step
	var detour: Array[Vector2i] = army._find_combat_route_after_rejection(member_id, source, farther, 256)
	assert(detour.size() > 2 and detour[0] == source and detour[1] != step and detour[-1] == farther,
		"A blocked first edge must take the existing bounded detour when one exists")
	army.external_blocker = Callable()
	grid.begin_tick({source: member_id}, data)
	army.propose_combat_moves(grid)
	assert(grid.get_proposals().size() == 1, "Original MOVE route must resume after contact clears")
	army.publish_move_encounters({0: {77: true}})
	result = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.HOLD)
	assert(bool(result.get("ok", false)) and army._move_encounters.is_empty(), "Forced HOLD must clear transient MOVE contact")
	army.free()
	print("SITE MOVE ENCOUNTER PASS")
	quit(0)
