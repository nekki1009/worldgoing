extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false

func _valid_route(route: Array[Vector2i], start: Vector2i, goal: Vector2i, data: TerrainData, profile: FormationMovementProfile, level_only: bool) -> bool:
	if route.size() < 2 or route[0] != start or route[-1] != goal:
		return false
	for i in range(1, route.size()):
		var from := route[i - 1]
		var to := route[i]
		if absi(from.x - to.x) + absi(from.y - to.y) != 1 or not data.can_step_static(from, to, profile):
			return false
		if level_only and data.height_levels[data.index(from)] != data.height_levels[data.index(to)]:
			return false
	return true

func _check_foot_edge_equivalence(army: TerrainArmy, data: TerrainData) -> bool:
	var center := Vector2i(2, 2)
	var profiles: Array[FormationMovementProfile] = [
		FormationMovementProfile.new(TerrainData.Flag.WALKABLE, 0, false, 1),
		FormationMovementProfile.new(TerrainData.Flag.WALKABLE, 1, false, 1),
		FormationMovementProfile.new(TerrainData.Flag.WALKABLE, 1, true, 1),
		FormationMovementProfile.new(TerrainData.Flag.WALKABLE, 2, true, 1),
	]
	var cases := [
		{"name": "level", "height": 0},
		{"name": "reciprocal ramp", "height": 1, "from_ramp": true, "to_ramp": true},
		{"name": "source-only ramp", "height": 1, "from_ramp": true},
		{"name": "target-only ramp", "height": 1, "to_ramp": true},
		{"name": "two-level cliff", "height": 2, "from_ramp": true, "to_ramp": true},
		{"name": "blocked source", "height": 0, "block_from": true},
		{"name": "blocked target", "height": 0, "block_to": true},
		{"name": "unwalkable source", "height": 0, "walk_from": false},
		{"name": "unwalkable target", "height": 0, "walk_to": false},
	]
	for direction_index in range(TerrainData.DIRECTIONS.size()):
		var target: Vector2i = center + TerrainData.DIRECTIONS[direction_index]
		for edge_case in cases:
			data.flags.fill(0)
			data.height_levels.fill(0)
			data.ramp_edges.fill(0)
			data.static_blocked.fill(0)
			if edge_case.get("walk_from", true):
				data.flags[data.index(center)] = TerrainData.Flag.WALKABLE
			if edge_case.get("walk_to", true):
				data.flags[data.index(target)] = TerrainData.Flag.WALKABLE
			data.height_levels[data.index(target)] = edge_case.height
			if edge_case.get("from_ramp", false):
				data.ramp_edges[data.index(center)] = 1 << direction_index
			if edge_case.get("to_ramp", false):
				data.ramp_edges[data.index(target)] = 1 << ((direction_index + 2) % 4)
			if edge_case.get("block_from", false):
				data.static_blocked[data.index(center)] = 1
			if edge_case.get("block_to", false):
				data.static_blocked[data.index(target)] = 1
			for profile in profiles:
				var expected := data.can_step_static(center, target, profile) \
					and (data.height_levels[data.index(center)] == data.height_levels[data.index(target)] or profile.can_use_ramp)
				var route := army._find_local_route(center, target, 8, false, -1, 0, false, profile)
				var actual := route.size() == 2 and route[0] == center and route[1] == target
				if not _require(actual == expected, "%s direction=%d max_step=%d can_ramp=%s disagrees with TerrainData" % [edge_case.name, direction_index, profile.max_step_height, profile.can_use_ramp]):
					return false
	return true

func _run() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(5, 5))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.height_levels.fill(0)
	data.static_blocked.resize(25)
	data.static_blocked.fill(0)
	var army := TerrainArmy.new()
	army.data = data
	var foot := FormationMovementProfile.new(TerrainData.Flag.WALKABLE, 0, false, 1)
	var start := Vector2i(1, 2)
	var goal := Vector2i(3, 2)
	var straight := army._find_local_route(start, goal, 64, false, -1, 0, false, foot)
	if not _require(_valid_route(straight, start, goal, data, foot, true) and straight[1] == Vector2i(2, 2), "Level foot route must use a clear equal-height cell"): return

	data.static_blocked[data.index(Vector2i(2, 2))] = 1
	var detour := army._find_local_route(start, goal, 64, false, -1, 0, false, foot)
	if not _require(_valid_route(detour, start, goal, data, foot, true) and not detour.has(Vector2i(2, 2)), "Level foot route must detour around a static blocker"): return

	# A reciprocal ramp is legal for the general route, but the no-ramp
	# formation profile must not cross it even when its height limit is one.
	data.flags.fill(0)
	data.static_blocked.fill(0)
	for x in range(1, 4):
		data.flags[data.index(Vector2i(x, 2))] = TerrainData.Flag.WALKABLE
	data.height_levels[data.index(Vector2i(2, 2))] = 1
	data.ramp_edges[data.index(Vector2i(1, 2))] = 1 << 1
	data.ramp_edges[data.index(Vector2i(2, 2))] = (1 << 1) | (1 << 3)
	data.ramp_edges[data.index(Vector2i(3, 2))] = 1 << 3
	var no_ramp := FormationMovementProfile.new(TerrainData.Flag.WALKABLE, 1, false, 1)
	if not _require(data.can_step_static(start, Vector2i(2, 2), no_ramp), "Fixture ramp must be legal in TerrainData"): return
	if not _require(army._find_local_route(start, goal, 64, false, -1, 0, false, no_ramp).is_empty(), "No-ramp foot profile must reject the unequal-height crossing"): return
	var ramp := FormationMovementProfile.new(TerrainData.Flag.WALKABLE, 1, true, 1)
	var ramp_route := army._find_local_route(start, goal, 64, false, -1, 0, false, ramp)
	if not _require(_valid_route(ramp_route, start, goal, data, ramp, false) and ramp_route.has(Vector2i(2, 2)), "Ramp-capable route must retain the legal crossing"): return
	if not _check_foot_edge_equivalence(army, data): return

	print("COMBAT MOVEMENT LOCAL ROUTE LEVEL EQUIVALENCE PASS")
	army.free()
	quit(0)
