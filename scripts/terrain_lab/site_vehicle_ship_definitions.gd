extends RefCounted
## Pure ship geometry and tuning. No instances, people, reservations or item state.
## Coordinates use cells: anchor is the stern-port cell centre, x starboard,
## y toward the bow. One cell remains the original 2-metre navigation unit.

const VERSION := 1
const KINDS: Array[String] = ["ferry", "river", "coastal", "troop", "patrol", "tower"]
const HELM_BERTH := 0
const INVALID_LOCAL := Vector2(INF, INF)
const INVALID_CELL := Vector2i(-2147483648, -2147483648)

static func is_kind(kind: String) -> bool:
	return kind in KINDS

static func definition(kind: String) -> Dictionary:
	match kind:
		"ferry": return _definition(kind, 2, 4, 10, 1, 1, 80, 1.0, 1.5)
		"river": return _definition(kind, 3, 7, 20, 2, 5, 600, 1.2, 3.0)
		"coastal": return _definition(kind, 4, 12, 25, 2, 5, 2000, 2.0, 5.0)
		"troop": return _definition(kind, 4, 10, 50, 2, 5, 500, 1.6, 4.0)
		"patrol": return _definition(kind, 3, 12, 25, 5, 10, 200, 2.5, 2.0)
		"tower": return _definition(kind, 6, 16, 100, 10, 20, 1200, 1.0, 8.0)
	return {}

static func _definition(kind: String, width: int, length: int, people: int, minimum: int, standard: int, capacity: int, full_speed: float, turn: float) -> Dictionary:
	var berths: Array[Vector2] = []
	var centre := float(width - 1) * 0.5
	berths.append(Vector2(centre, 0.25))
	var rows := ceili(float(people - 1) * 0.5)
	var lateral := maxf(0.6, centre - 0.2)
	for berth in range(1, people):
		var row := floori(float(berth - 1) * 0.5)
		var y := 0.25 + float(row) * float(length - 1) / float(maxi(1, rows - 1))
		berths.append(Vector2(centre + (-lateral if berth % 2 == 1 else lateral), y))
	return {"id": kind, "version": VERSION, "width": width, "length": length,
		"max_people": people, "capacity": capacity, "min_crew": minimum,
		"standard_crew": standard, "speed": full_speed, "turn_seconds": turn,
		"helm_berth": HELM_BERTH, "berths": berths}

static func valid_facing(facing: Vector2i) -> bool:
	return facing in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

static func footprint(kind: String, anchor: Vector2i, facing: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var spec := definition(kind)
	if spec.is_empty() or not valid_facing(facing): return cells
	var right := Vector2i(-facing.y, facing.x)
	for y in range(int(spec.length)):
		for x in range(int(spec.width)):
			cells.append(anchor + right * x + facing * y)
	return cells

static func swept_footprint(kind: String, from_anchor: Vector2i, from_facing: Vector2i, anchor: Vector2i, facing: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var spec := definition(kind)
	if spec.is_empty() or not valid_facing(from_facing) or not valid_facing(facing): return cells
	var minimum := from_anchor
	var maximum := from_anchor
	if from_facing == facing:
		for cell: Vector2i in footprint(kind, from_anchor, from_facing) + footprint(kind, anchor, facing):
			minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
			maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
	elif from_anchor == anchor and from_facing.x * facing.x + from_facing.y * facing.y == 0:
		# The continuous quarter-turn includes corners beyond either end pose.
		# V1 reserves the full square around the stern-port pivot, conservatively.
		var radius := ceili(Vector2(float(spec.width) - 0.5, float(spec.length) - 0.5).length())
		minimum = anchor - Vector2i.ONE * radius
		maximum = anchor + Vector2i.ONE * radius
	else:
		return cells
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1): cells.append(Vector2i(x, y))
	return cells

static func local_position(kind: String, berth: int) -> Vector2:
	var spec := definition(kind)
	if spec.is_empty() or berth < 0 or berth >= int(spec.max_people): return INVALID_LOCAL
	return spec.berths[berth]

static func world_position(anchor: Vector2i, facing: Vector2i, local: Vector2) -> Vector2:
	if not valid_facing(facing) or not local.is_finite(): return INVALID_LOCAL
	return Vector2(anchor) + Vector2(-facing.y, facing.x) * local.x + Vector2(facing) * local.y

static func local_from_world(anchor: Vector2i, facing: Vector2i, position: Vector2) -> Vector2:
	if not valid_facing(facing) or not position.is_finite(): return INVALID_LOCAL
	var offset := position - Vector2(anchor)
	return Vector2(offset.dot(Vector2(-facing.y, facing.x)), offset.dot(Vector2(facing)))

static func world_cell(anchor: Vector2i, facing: Vector2i, local: Vector2) -> Vector2i:
	var position := world_position(anchor, facing, local)
	return Vector2i(roundi(position.x), roundi(position.y)) if position.is_finite() else INVALID_CELL

static func crew_berths(kind: String) -> Array[int]:
	var positions: Array[int] = []
	var spec := definition(kind)
	if not spec.is_empty():
		for berth in range(int(spec.standard_crew)): positions.append(berth)
	return positions

static func helm_path(kind: String, source_berth: int) -> Array[Vector2]:
	var path: Array[Vector2] = []
	var start := local_position(kind, source_berth)
	if not start.is_finite(): return path
	var helm := local_position(kind, HELM_BERTH)
	path.append(start)
	var aisle := Vector2(helm.x, start.y)
	if not aisle.is_equal_approx(path.back()): path.append(aisle)
	if not helm.is_equal_approx(path.back()): path.append(helm)
	return path

static func boarding_local_position(kind: String, side: int) -> Vector2:
	var spec := definition(kind)
	if spec.is_empty() or side not in [-1, 1]: return INVALID_LOCAL
	return Vector2(0.0 if side == -1 else float(int(spec.width) - 1), 0.0)

static func boarding_cells(kind: String, anchor: Vector2i, facing: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var spec := definition(kind)
	if spec.is_empty() or not valid_facing(facing): return cells
	var right := Vector2i(-facing.y, facing.x)
	cells.append(anchor - right)
	cells.append(anchor + right * int(spec.width))
	return cells

static func _crew_multiplier(spec: Dictionary, crew: int) -> float:
	if spec.is_empty() or crew < int(spec.min_crew) or crew > int(spec.max_people): return 0.0
	if crew >= int(spec.standard_crew): return 1.0
	return 0.5 + 0.5 * float(crew - int(spec.min_crew)) / float(int(spec.standard_crew) - int(spec.min_crew))

static func speed(kind: String, people: int, load_amount: float, crew: int, docking: bool = false, reverse: bool = false) -> float:
	var spec := definition(kind)
	if spec.is_empty() or people < 0 or people > int(spec.max_people) or not is_finite(load_amount) or load_amount < 0.0 or load_amount > float(spec.capacity) or crew > people: return 0.0
	var multiplier := _crew_multiplier(spec, crew)
	if multiplier <= 0.0: return 0.0
	var ratio := maxf(float(people) / float(spec.max_people), load_amount / float(spec.capacity))
	var result := float(spec.speed) * (1.25 - 0.25 * ratio) * multiplier
	if reverse: result *= 0.25
	return minf(result, 0.5) if docking else result

static func turn_seconds(kind: String, crew: int) -> float:
	var spec := definition(kind)
	var multiplier := _crew_multiplier(spec, crew)
	return float(spec.turn_seconds) / multiplier if multiplier > 0.0 else INF

# Version 1 game recipes use the existing depot resources and worker seconds.
static func build_cost(kind: String) -> Dictionary:
	match kind:
		"ferry": return {"wood": 40, "fiber": 8, "iron": 2}
		"river": return {"wood": 100, "fiber": 20, "iron": 8}
		"coastal": return {"wood": 240, "fiber": 60, "iron": 20}
		"troop": return {"wood": 200, "fiber": 40, "iron": 20}
		"patrol": return {"wood": 220, "fiber": 40, "iron": 30}
		"tower": return {"wood": 500, "fiber": 100, "iron": 60}
	return {}

static func build_work_seconds(kind: String) -> float:
	return float({"ferry": 600.0, "river": 1500.0, "coastal": 3600.0,
		"troop": 3000.0, "patrol": 3300.0, "tower": 7200.0}.get(kind, 0.0))

static func hull_hp(kind: String) -> float:
	return float({"ferry": 200.0, "river": 500.0, "coastal": 1200.0,
		"troop": 1000.0, "patrol": 900.0, "tower": 2400.0}.get(kind, 0.0))

static func make_record(identity: String, team_id: int, kind: String, cell: int, facing: Vector2i) -> Dictionary:
	if identity.is_empty() or team_id <= 0 or not is_kind(kind) or cell < 0 or not valid_facing(facing): return {}
	return {"id": identity, "kind": "ship", "ship_version": 1, "ship_type": kind,
		"definition_version": VERSION, "team_id": team_id, "operator_id": 0, "cell": cell,
		"facing": [facing.x, facing.y], "cargo": {},
		"holder": {"holder": "vehicle:" + identity, "version": 0, "item_ids": [], "equipped": {}},
		"move": {}, "stop_pending": false, "revision": 1, "command": {},
		"naval": {"version": 1, "hp": hull_hp(kind), "state": "afloat", "repair": {}}}

static func deck_contains(kind: String, point: Vector2) -> bool:
	var spec := definition(kind)
	return not spec.is_empty() and point.is_finite() and point.x >= -0.25 and point.y >= -0.25 \
		and point.x <= float(spec.width) - 0.75 and point.y <= float(spec.length) - 0.75
