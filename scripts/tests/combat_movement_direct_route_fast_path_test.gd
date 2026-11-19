extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
var _external_cells := [Vector2i(3, 2), Vector2i(2, 3)]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data := Helper.build_flat_map(12, 12)
	var army := Helper.create_test_army(data, 1, 0, 1, Vector2i(2, 2))
	var profile := FormationMovementProfile.new()
	var start := army.cells[0]
	var goal := Vector2i(6, 4)
	army.combat_enabled = false
	var baseline: Array[Vector2i] = army._find_local_route(start, goal, 64, true, -1, 0, false, profile)
	army.combat_enabled = true
	army.reset_movement_metrics()
	var direct: Array[Vector2i] = army._find_local_route(start, goal, 64, true, -1, 0, false, profile)
	if not _require(_legal(direct, start, goal, data, profile) and direct.size() == baseline.size() and direct.size() == 7,
		"Open direct route must match A* minimum cost with legal physical edges"): return
	if not _require(army.direct_route_hits == 1 and army.expanded_nodes == 0,
		"Open direct route must avoid heap expansion and record one hit"): return
	# Both one-bend candidates are closed, but a legal route around the corner remains.
	data.static_blocked[data.index(Vector2i(3, 2))] = 1
	data.static_blocked[data.index(Vector2i(2, 3))] = 1
	army.reset_movement_metrics()
	var detour: Array[Vector2i] = army._find_local_route(start, goal, 128, true, -1, 0, false, profile)
	if not _require(_legal(detour, start, goal, data, profile) and army.direct_route_hits == 0 and army.expanded_nodes > 0,
		"Blocked direct candidates must fall through to the original A*"): return
	data.static_blocked.fill(0)
	# A physical claim forbids the horizontal route; the vertical-first route is safe.
	army._reserved_cells[Vector2i(3, 2)] = 99
	army.reset_movement_metrics()
	var alternate: Array[Vector2i] = army._find_local_route(start, goal, 64, true, -1, 0, false, profile)
	if not _require(_legal(alternate, start, goal, data, profile) and alternate.size() == baseline.size() and not alternate.has(Vector2i(3, 2)) and army.direct_route_hits == 1,
		"Direct route may choose another shortest bend but must not cross a reservation"): return
	army._reserved_cells.erase(Vector2i(3, 2))
	# External blockers on both shortest bends require the original detour search.
	army.external_blocker = Callable(self, "_external_blocked")
	army.reset_movement_metrics()
	var external_detour: Array[Vector2i] = army._find_local_route(start, goal, 128, true, -1, 0, false, profile)
	if not _require(_legal(external_detour, start, goal, data, profile) and not external_detour.has(Vector2i(3, 2)) and not external_detour.has(Vector2i(2, 3)) and army.direct_route_hits == 0 and army.expanded_nodes > 0,
		"External blockers must reject both direct candidates and use A*"): return
	army.external_blocker = Callable()
	# Preserve the existing first-step exclusion used after repeated rejections.
	army._cell_owners[Vector2i(3, 2)] = 99
	army._cell_owners[Vector2i(2, 3)] = 99
	army.reset_movement_metrics()
	var avoided: Array[Vector2i] = army._find_local_route(start, goal, 128, true, -1, 0, false, profile, true)
	if not _require(_legal(avoided, start, goal, data, profile) and avoided[1] not in [Vector2i(3, 2), Vector2i(2, 3)] and army.direct_route_hits == 0,
		"Occupied first steps must still force A* and preserve the rejection rule"): return
	print("COMBAT MOVEMENT DIRECT ROUTE FAST PATH PASS")
	army.free()
	quit(0)

func _external_blocked(cell: Vector2i) -> bool:
	return cell in _external_cells

func _legal(route: Array[Vector2i], start: Vector2i, goal: Vector2i, data: TerrainData, profile: FormationMovementProfile) -> bool:
	if route.size() < 2 or route[0] != start or route[-1] != goal:
		return false
	for i in range(1, route.size()):
		if not data.can_step_static(route[i - 1], route[i], profile):
			return false
	return true

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false
