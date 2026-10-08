extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Grid = preload("res://scripts/terrain_lab/site_movement_reservation_grid.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	var data := Helper.build_flat_map(30, 20)
	var army := Helper.create_test_army(data, 1, 0, 1, Vector2i(5, 5))
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 5), -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), "The test order must be accepted"): return
	army._order_delay = 0.0
	var mid := army.combat_identity(0)
	var start := army.cells[0]
	var plan = army.get_active_move_plan()
	var old_goal := start + Vector2i(3, 0)
	plan.member_paths[mid] = [start, start + Vector2i.RIGHT, start + Vector2i(2, 0), old_goal]
	plan.stamp_member_route(mid, old_goal)
	army.combat_slots[0] = start + Vector2i(0, 3)
	var grid := Grid.new()
	grid.begin_tick({start: mid}, data)
	army.propose_combat_moves(grid)
	if not _require(grid.get_proposals().is_empty(), "A cached route to an obsolete target must never generate a step"): return
	plan.note_assignment_change(mid)
	if not _require(not plan.member_paths.has(mid), "A final or transit slot change must invalidate the old route immediately"): return
	print("COMBAT MOVEMENT STALE ROUTE PASS")
	army.free()
	quit(0)
