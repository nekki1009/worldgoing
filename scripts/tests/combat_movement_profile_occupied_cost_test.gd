extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data := Helper.build_flat_map(10, 5)
	var start := Vector2i(0, 2)
	var occupied := Vector2i(2, 2)
	var goal := Vector2i(4, 2)
	var army := Helper.create_test_army(data, 1, 0, 2, start)
	army.cells[1] = occupied
	army._cell_owners.clear()
	army._cell_owners[start] = 0
	army._cell_owners[occupied] = 1
	army.combat_slots[1] = Vector2i(3, 2) # This owner is moving, so the route may use its cell.
	var profile := FormationMovementProfile.new()
	for y in range(5):
		if y != 2:
			data.static_blocked[data.index(Vector2i(7, y))] = 1
	var choke := Vector2i(7, 2)
	if not _require(FormationTransitPlanner.detect_corridor_width(data, choke, Vector2i.RIGHT, profile) == 1,
		"Fixture must contain a real static one-cell choke on the macro route"): return
	var plan := CombatMovePlan.new()
	plan.order_serial = 1
	plan.terrain_revision = data.navigation_revision
	for x in range(9):
		plan.macro_path.append(Vector2i(x, 2))
	var destination := CombatDeploymentPlan.new()
	destination.order_serial = plan.order_serial
	destination.set_approach_bottlenecked(true, choke)
	plan.destination_plan = destination
	army._combat_move_plan = plan
	army._combat_deployment_plan = destination
	army.combat_order = TerrainArmy.CombatOrder.MOVE
	var moving_route: Array[Vector2i] = army._find_local_route(start, goal, 64, true, -1, 0, false, profile)
	if not _require(moving_route.size() == 5 and moving_route.has(occupied),
		"Choke transit should choose cost-5 moving-owner route over cost-6 free detour"): return
	destination.set_approach_bottlenecked(false)
	var open_route: Array[Vector2i] = army._find_local_route(start, goal, 64, true, -1, 0, false, profile)
	if not _require(open_route.size() == 7 and not open_route.has(occupied),
		"Open transit must retain the original +3 occupied cost"): return
	destination.set_approach_bottlenecked(true, choke)
	plan.phase = CombatMovementTypes.CombatMovePhase.PLATFORM_INGRESS
	var later_route: Array[Vector2i] = army._find_local_route(start, goal, 64, true, -1, 0, false, profile)
	if not _require(later_route.size() == 7 and not later_route.has(occupied),
		"Platform ingress must retain the original +3 occupied cost"): return
	plan.phase = CombatMovementTypes.CombatMovePhase.TRANSIT
	var legacy_route: Array[Vector2i] = army._find_local_route(start, goal, 64, true)
	if not _require(legacy_route.size() == 7 and not legacy_route.has(occupied),
		"No-profile local route must retain the original +3 occupied cost"): return
	army.combat_slots[1] = occupied # A standing owner remains a hard blocker.
	var standing_route: Array[Vector2i] = army._find_local_route(start, goal, 64, true, -1, 0, false, profile)
	if not _require(standing_route.size() == 7 and not standing_route.has(occupied),
		"Standing owner must remain blocked even for a combat foot profile"): return
	print("COMBAT MOVEMENT PROFILE OCCUPIED COST PASS")
	army.free()
	quit(0)

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false
