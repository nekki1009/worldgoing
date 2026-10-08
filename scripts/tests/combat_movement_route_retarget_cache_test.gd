extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Grid = preload("res://scripts/terrain_lab/site_movement_reservation_grid.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data := Helper.build_flat_map(12, 12)
	var army := Helper.create_test_army(data, 1, 0, 1, Vector2i(2, 2))
	var mid := army.combat_identity(0)
	var start := army.cells[0]
	var first := start + Vector2i.RIGHT
	var target := start + Vector2i(2, 0)
	var old_target := start + Vector2i(3, 0)
	var plan := CombatMovePlan.new()
	plan.order_serial = 1
	plan.terrain_revision = data.navigation_revision
	var initial_route: Array[Vector2i] = [start, first, target, old_target]
	plan.member_paths[mid] = initial_route
	plan.stamp_member_route(mid, old_target)
	army._combat_move_plan = plan
	army.combat_slots[0] = old_target
	if not _require(army._retain_member_route_to_target(mid, 0, target), "A target on the legal remaining route should retain its prefix"): return
	army.combat_slots[0] = target
	if not _require(plan.member_paths[mid] == [start, first, target] and plan.is_member_route_current(mid, target), "Retained route must end at the new exact target"): return
	army.reset_movement_metrics()
	army._refresh_member_route_caches(null)
	if not _require(army.route_calls == 0, "Retargeting to an existing route node must not run A*"): return
	army.combat_order = TerrainArmy.CombatOrder.MOVE
	army._order_delay = 0.0
	var grid := Grid.new()
	grid.begin_tick({start: mid}, data)
	army.propose_combat_moves(grid)
	if not _require(grid.get_proposals().size() == 1 and grid.get_proposals()[0].to_cell == first and data.can_step(start, first), "Retained route must propose the same legal physical first edge"): return
	var reserved_route: Array[Vector2i] = [start, first, target, old_target]
	plan.member_paths[mid] = reserved_route
	plan.stamp_member_route(mid, old_target)
	army.combat_slots[0] = old_target
	army._reserved_cells[first] = 99
	if not _require(not army._retain_member_route_to_target(mid, 0, target), "Another member's physical reservation must prevent route retention"): return
	army._reserved_cells.erase(first)
	data.static_blocked[data.index(first)] = 1
	if not _require(not army._retain_member_route_to_target(mid, 0, target), "An illegal first terrain edge must prevent route retention"): return
	data.static_blocked[data.index(first)] = 0
	data.navigation_revision += 1
	if not _require(not army._retain_member_route_to_target(mid, 0, target), "A stale terrain revision must prevent route retention"): return
	print("COMBAT MOVEMENT ROUTE RETARGET CACHE PASS")
	army.free()
	quit(0)

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false
