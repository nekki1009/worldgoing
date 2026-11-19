extends SceneTree

const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

const PRESETS := ["square", "wedge", "goose", "circle", "hook", "loose"]
const FACINGS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const ANCHOR := Vector2i(40, 40)

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func _bounds(slots: Array[Vector2i], facing: Vector2i) -> Vector2i:
	var side := Vector2i(-facing.y, facing.x)
	var min_u := 999
	var max_u := -999
	var min_v := 999
	var max_v := -999
	for cell in slots:
		var offset := cell - ANCHOR
		var u: int = offset.x * side.x + offset.y * side.y
		var v: int = offset.x * facing.x + offset.y * facing.y
		min_u = mini(min_u, u)
		max_u = maxi(max_u, u)
		min_v = mini(min_v, v)
		max_v = maxi(max_v, v)
	return Vector2i(max_u - min_u + 1, max_v - min_v + 1)

func _ranks_from_front(slots: Array[Vector2i]) -> Array:
	# Facing RIGHT: x is depth, y is the lateral coordinate.
	var by_depth: Dictionary = {}
	for cell in slots:
		var depth: int = cell.x - ANCHOR.x
		if not by_depth.has(depth):
			by_depth[depth] = []
		by_depth[depth].append(cell.y - ANCHOR.y)
	var depths: Array[int] = []
	for depth in by_depth.keys():
		depths.append(int(depth))
	depths.sort()
	depths.reverse()
	var ranks: Array = []
	for depth in depths:
		var sides: Array = by_depth[depth]
		sides.sort()
		ranks.append(sides)
	return ranks

func _run() -> void:
	if not _check(Destination.is_valid_preset("auto") and not Destination.is_valid_preset("missing"), "Preset whitelist failed"): return
	for preset in PRESETS:
		for count in range(1, 201):
			var slots: Array[Vector2i] = Destination.shape_slots(preset, count, ANCHOR, Vector2i.RIGHT)
			var unique: Dictionary = {}
			for slot in slots:
				unique[slot] = true
			if not _check(slots.size() == count and unique.size() == count and Destination.preset_footprint_radius(preset, count) <= Destination.MAX_PRESET_RADIUS, "%s N=%d must have exact bounded unique cells" % [preset, count]): return
		for count in [1, 2, 3, 5, 10, 25, 100, 200]:
			var right: Array[Vector2i] = Destination.shape_slots(preset, count, ANCHOR, Vector2i.RIGHT)
			for facing in FACINGS:
				var rotated: Array[Vector2i] = Destination.shape_slots(preset, count, ANCHOR, facing)
				var side := Vector2i(-facing.y, facing.x)
				for i in range(count):
					var offset := right[i] - ANCHOR
					var expected: Vector2i = ANCHOR + side * offset.y + facing * offset.x
					if not _check(rotated[i] == expected, "%s N=%d changed template while rotating" % [preset, count]): return
				if not _check(rotated == Destination.shape_slots(preset, count, ANCHOR, facing), "%s N=%d is unstable" % [preset, count]): return
	if not _check(Destination.shape_slots("square", 100, ANCHOR, Vector2i.RIGHT).size() == 100 and _bounds(Destination.shape_slots("square", 100, ANCHOR, Vector2i.RIGHT), Vector2i.RIGHT) == Vector2i(10, 10), "Square 100 is not 10x10"): return
	if not _check(_bounds(Destination.shape_slots("wedge", 100, ANCHOR, Vector2i.RIGHT), Vector2i.RIGHT) == Vector2i(19, 10), "Wedge 100 must widen through ten ranks"): return
	if not _check(_bounds(Destination.shape_slots("goose", 100, ANCHOR, Vector2i.RIGHT), Vector2i.RIGHT) == Vector2i(19, 10), "Goose 100 must stagger ten ranks"): return
	if not _check(_bounds(Destination.shape_slots("loose", 100, ANCHOR, Vector2i.RIGHT), Vector2i.RIGHT) == Vector2i(19, 19), "Loose 100 must have one-cell gaps"): return
	for width in [5, 10]:
		var count: int = width * width
		var square_ranks: Array = _ranks_from_front(Destination.shape_slots("square", count, ANCHOR, Vector2i.RIGHT))
		if not _check(square_ranks.size() == width, "Square N=%d has wrong rank count" % count): return
		var square_left: int = -floori(float(width - 1) / 2.0)
		for row in square_ranks:
			if not _check(row.size() == width and row[0] == square_left and row[-1] == square_left + width - 1, "Square N=%d lost a filled rank" % count): return
		var wedge_ranks: Array = _ranks_from_front(Destination.shape_slots("wedge", count, ANCHOR, Vector2i.RIGHT))
		if not _check(wedge_ranks.size() == width, "Wedge N=%d has wrong rank count" % count): return
		for rank in range(width):
			var wedge_row: Array = wedge_ranks[rank]
			if not _check(wedge_row.size() == 2 * rank + 1 and wedge_row[0] == -rank and wedge_row[-1] == rank, "Wedge N=%d rank %d lost its centered widening" % [count, rank]): return
		var goose_ranks: Array = _ranks_from_front(Destination.shape_slots("goose", count, ANCHOR, Vector2i.RIGHT))
		if not _check(goose_ranks.size() == width, "Goose N=%d has wrong rank count" % count): return
		for rank in range(width):
			var goose_row: Array = goose_ranks[rank]
			if not _check(goose_row.size() == width and goose_row[0] == rank - width + 1 and goose_row[-1] == rank, "Goose N=%d rank %d lost its one-cell diagonal shift" % [count, rank]): return
		var loose: Array[Vector2i] = Destination.shape_slots("loose", count, ANCHOR, Vector2i.RIGHT)
		for row in range(width):
			for column in range(width):
				var lattice_cell: Vector2i = ANCHOR + Vector2i(width - 1 - 2 * row, 2 * column - width + 1)
				if not _check(loose.has(lattice_cell), "Loose N=%d lost its two-cell lattice at %s" % [count, lattice_cell]): return
	var circle_hundred: Array[Vector2i] = Destination.shape_slots("circle", 100, ANCHOR, Vector2i.RIGHT)
	var circle_set: Dictionary = {}
	var outer_shell_count := 0
	for cell in circle_hundred:
		var distance_squared: int = (cell - ANCHOR).length_squared()
		circle_set[cell] = true
		if distance_squared == 32:
			outer_shell_count += 1
		if not _check(distance_squared <= 32, "Circle 100 contains a cell outside its nearest radial shell"): return
	for x in range(-5, 6):
		for y in range(-5, 6):
			if x * x + y * y < 32 and not _check(circle_set.has(ANCHOR + Vector2i(x, y)), "Circle 100 omitted an inner radial cell at (%d,%d)" % [x, y]): return
	if not _check(outer_shell_count == 3, "Circle 100 must fill 97 inner cells and three outer-shell cells"): return
	var hook: Array[Vector2i] = Destination.shape_slots("hook", 100, ANCHOR, Vector2i.RIGHT)
	if not _check(_bounds(hook, Vector2i.RIGHT) == Vector2i(14, 13) and not hook.has(ANCHOR) and hook.has(ANCHOR + Vector2i(0, -6)) and hook.has(ANCHOR + Vector2i(0, 7)), "Hook 100 must retain its hollow middle and both wings"): return
	for count in [25, 100]:
		var hook_ranks: Array = _ranks_from_front(Destination.shape_slots("hook", count, ANCHOR, Vector2i.RIGHT))
		var widths: Array[int] = []
		for row in hook_ranks:
			widths.append(row.size())
		var expected_widths: Array = [6, 6, 4, 4, 4, 1] if count == 25 else [14, 14, 14, 6, 6, 6, 6, 6, 6, 6, 6, 6, 4]
		if not _check(widths == expected_widths, "Hook N=%d lost its thick front or rear rank profile" % count): return
		var first_wing: Array = hook_ranks[2 if count == 25 else 3]
		var expected_wing: Array = [-2, -1, 2, 3] if count == 25 else [-6, -5, -4, 5, 6, 7]
		if not _check(first_wing == expected_wing, "Hook N=%d lost its separated rear wings" % count): return
	var circle: Array[Vector2i] = Destination.shape_slots("circle", 25, ANCHOR, Vector2i.RIGHT)
	var plan := CombatDeploymentPlan.new()
	plan.formation_preset_id = "circle"
	plan.resolved_anchor = ANCHOR
	plan.final_facing = Vector2i.RIGHT
	plan.platform_slots = circle
	if not _check(circle.has(ANCHOR) and plan.get_facing_for_slot(ANCHOR) == Vector2i.RIGHT, "Circle center must follow command facing"): return
	var side_slot := ANCHOR + Vector2i(0, 2)
	if not _check(circle.has(side_slot) and plan.get_facing_for_slot(side_slot) == Vector2i.DOWN, "Circle outer slot must face outward"): return
	var terrain := Helper.build_flat_map(80, 80)
	var members: Array[int] = []
	for i in range(25):
		members.append(i)
	var path: Array[Vector2i] = [ANCHOR]
	var placed := Destination.plan_deployment(1, 1, terrain, ANCHOR, path, members, null, [], {}, Vector2i.RIGHT, null, "hook")
	if not _check(placed != null and placed.platform_slots.size() == 25 and placed.final_width == 6 and placed.final_depth == 6 and placed.shape_version == 2 and placed.formation_preset_id == "hook", "Planner changed or split the fixed hook shape"): return
	var two_hundred: Array[int] = []
	for i in range(200):
		two_hundred.append(i)
	var wide := Destination.plan_deployment(2, 2, terrain, ANCHOR, path, two_hundred, null, [], {}, Vector2i.RIGHT, null, "loose")
	if not _check(wide != null and wide.final_width == 29 and wide.final_depth == 27 and Destination.refresh_derived_ingress(wide, terrain, path), "Wide shape must keep its larger footprint during ingress rebuild"): return
	var blocked: Vector2i = placed.platform_slots[0]
	terrain.flags[terrain.index(blocked)] = 0
	var partial := Destination.plan_deployment(1, 1, terrain, ANCHOR, path, members, null, [], {}, Vector2i.RIGHT, null, "hook")
	if not _check(partial != null and partial.platform_slots.size() == 24 and partial.following_member_ids.size() == 1 and partial.formation_preset_id == "hook" and partial.final_width == placed.final_width and partial.final_depth == placed.final_depth, "Blocked fixed shape must retain its template and let the remaining original member follow"): return
	if not _check(Destination.shape_slots("missing", 25, ANCHOR, Vector2i.RIGHT).is_empty() and Destination.shape_slots("square", 0, ANCHOR, Vector2i.RIGHT).is_empty() and Destination.shape_slots("square", 25, ANCHOR, Vector2i(1, 1)).is_empty(), "Invalid template inputs must be refused"): return
	print("COMBAT FORMATION SHAPE PASS")
	quit(0)
