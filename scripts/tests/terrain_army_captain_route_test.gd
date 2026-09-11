extends SceneTree

const EdgeChecks = preload("res://scripts/tests/terrain_army_default_edge_test.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var terrain := TerrainData.new()
	terrain.allocate(Vector2i(12, 10))
	terrain.flags.fill(TerrainData.Flag.BLOCKED)
	for x: int in range(1, 7):
		terrain.flags[terrain.index(Vector2i(x, 5))] = TerrainData.Flag.WALKABLE
	for x: int in range(1, 9):
		terrain.flags[terrain.index(Vector2i(x, 3))] = TerrainData.Flag.WALKABLE
	terrain.flags[terrain.index(Vector2i(1, 4))] = TerrainData.Flag.WALKABLE
	var start := Vector2i(2, 5)
	var goal := Vector2i(8, 3)
	var expected := _distance(terrain, start, goal)
	if not _check(expected == 10, "Fixture oracle changed"):
		return
	var army := TerrainArmy.new()
	army.data = terrain
	army.cells.append(start)
	army.blocked_time.resize(TerrainArmy.SOLDIER_COUNT)
	army.blocked_time.fill(1.0)
	var trace: Array[Vector2i] = [start]
	for _attempt: int in range(100):
		if army.cells[0] == goal:
			break
		army._detour_requests_remaining = TerrainArmy.PLANNING_BUDGET
		army._structure_expansions_remaining = TerrainArmy.PATH_EXPANSIONS_PER_STEP
		var next := army._next_step(army.cells[0], goal, 0)
		if next == TerrainArmy.INVALID_CELL:
			continue
		army.cells[0] = next
		army._consume_path_route_step(0, next)
		trace.append(next)
	if not _check(army.cells[0] == goal and trace.size() - 1 == expected, "Captain helper route is not shortest"):
		return
	print("CAPTAIN ROUTE PASS: oracle=%d actual=%d trace=%s" % [expected, trace.size() - 1, trace])
	if not _check(army._find_path(goal, goal, 0).is_empty() and army._path_status == TerrainArmy.PathStatus.FOUND, "C02 zero-length helper route must remain FOUND"):
		return
	print("C02_ZERO_ROUTE_PASS: start equals goal, zero edges, FOUND")
	army.free()
	if not _formal_command(false) or not _formal_command(true):
		quit(1)
		return
	quit(0)

func _formal_command(zero_goal: bool) -> bool:
	# V3 C01: one-time legal 100-person initialization, NOT a deploy oracle.
	# No authority cells/targets are changed after issue_command.
	var terrain := TerrainData.new()
	terrain.allocate(Vector2i(100, 100))
	terrain.flags.fill(TerrainData.Flag.WALKABLE if zero_goal else TerrainData.Flag.BLOCKED)
	if not zero_goal:
		for x: int in range(14, 25):
			terrain.flags[terrain.index(Vector2i(x, 50))] = TerrainData.Flag.WALKABLE
		for x: int in range(19, 27):
			terrain.flags[terrain.index(Vector2i(x, 48))] = TerrainData.Flag.WALKABLE
		terrain.flags[terrain.index(Vector2i(19, 49))] = TerrainData.Flag.WALKABLE
		for y: int in range(50, 60):
			for x: int in range(5, 15):
				terrain.flags[terrain.index(Vector2i(x, y))] = TerrainData.Flag.WALKABLE
		for y: int in range(30, 48):
			for x: int in range(26, 46):
				terrain.flags[terrain.index(Vector2i(x, y))] = TerrainData.Flag.WALKABLE
		terrain.flags[terrain.index(Vector2i(31, 48))] = TerrainData.Flag.WALKABLE
	var player := TerrainTestCharacter.new()
	player.data = terrain
	var npc := TerrainTestNPC.new()
	npc.data = terrain
	var army := TerrainArmy.new()
	var valid := player.place(Vector2i(80, 50) if zero_goal else Vector2i(31, 48), true) and npc.place(Vector2i(5, 50), true)
	valid = valid and army.deploy(terrain, player, npc)
	if valid:
		var initial: Array[Vector2i] = [Vector2i(75, 50) if zero_goal else Vector2i(20, 50)]
		for y: int in range(50, 60):
			for x: int in range(5, 15):
				if Vector2i(x, y) != Vector2i(5, 50):
					initial.append(Vector2i(x, y))
		army.cells = initial.duplicate()
		army.desired_cells = initial.duplicate()
		army._formation_slot_cells = initial.duplicate()
		army._cell_owners.clear()
		for unit: int in range(100):
			army._cell_owners[initial[unit]] = unit
			army._formation_offsets[unit] = initial[unit] - initial[0]
		army._formation_anchor_cell = initial[0]
		army._captain_trail = [initial[0]]
		valid = _replay_command(army, terrain, zero_goal)
	else:
		push_error("FIXTURE_INVALID C01/C02")
	army.clear()
	army.free()
	npc.free()
	player.free()
	return valid

func _replay_command(army: TerrainArmy, terrain: TerrainData, zero_goal: bool) -> bool:
	var hz := 30 if "--30hz" in OS.get_cmdline_user_args() else 60
	var alternating := "--alternating" in OS.get_cmdline_user_args()
	var label := "C02_FORMATION_GOAL" if zero_goal else "C01_FORMAL"
	var goal := Vector2i(75, 50) if zero_goal else Vector2i(26, 48)
	var expected := _distance(terrain, army.cells[0], goal)
	if not _check(expected == (0 if zero_goal else 10), "FIXTURE_INVALID " + label + " BFS distance"):
		return false
	print(label, " START source=", FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"), " fingerprint=", terrain.fingerprint(), " INITIAL_CELLS=", army.cells)
	if not _check(army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER), "formal FOLLOW rejected"):
		return false
	var trace: Array[Vector2i] = [army.cells[0]]
	var previous := army.cells.duplicate()
	var revision := -1
	var published_at := -1.0
	var published_goal := TerrainArmy.INVALID_CELL
	var snapshot: Array[Vector2i] = []
	for frame: int in range(30 * hz):
		army.advance_frame((1.0 / 120.0 if frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz))
		if not _check(EdgeChecks._legal_state(army, terrain) and army.max_frame_structure_expansions <= 256 and army.max_frame_local_expansions <= 8192 and army.max_frame_push_expansions <= 1024 and army.dropped_seconds == 0.0, label + " owner/budget/time"):
			return false
		for unit: int in range(100):
			if previous[unit] != army.cells[unit] and not _check(terrain.can_step(previous[unit], army.cells[unit]), label + " illegal edge"):
				return false
		if previous[0] != army.cells[0]:
			trace.append(army.cells[0])
		previous = army.cells.duplicate()
		if not army._command_goal_pending:
			if revision < 0:
				revision = army._path_route_snapshot_revision
				published_goal = army._march_goal
				published_at = army.input_seconds
				snapshot = army._path_route_snapshot.duplicate()
				if not _check(not snapshot.is_empty() and snapshot.back() == published_goal, label + " missing shared front-goal route"):
					return false
				expected = _distance(terrain, snapshot[0], published_goal)
				if not _check(snapshot.size() - 1 == expected, label + " shared route differs from independent shortest-path oracle"):
					return false
				var player_target: Vector2i = army.player.terrain_cell
				var separation := absi(published_goal.x - player_target.x) + absi(published_goal.y - player_target.y)
				if not _check(separation >= TerrainArmy.FOLLOW_DISTANCE and separation <= TerrainArmy.FOLLOW_TRIGGER, label + " formation front outside follow ring"):
					return false
				for edge: int in range(snapshot.size() - 1):
					if not _check(terrain.can_step(snapshot[edge], snapshot[edge + 1]), label + " illegal shared guide edge"):
						return false
			if not _check(army._march_goal == published_goal and army._path_route_snapshot_revision == revision and army._path_route_snapshot == snapshot, label + " stationary PLAYER front goal/snapshot changed"):
				return false
		if published_at >= 0 and army.input_seconds - published_at >= 5.0:
			print(label, " PASS shared_oracle=", expected, " shared_edges=", snapshot.size() - 1, " stable_front_goal=5 captain_physical_edges=", trace.size() - 1, " input=", army.input_seconds, " command_complete=", army.is_formation_complete())
			return true
	return _check(false, label + " shared route missed 30-second diagnostic bound")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func _distance(terrain: TerrainData, start: Vector2i, goal: Vector2i) -> int:
	var pending: Array[Vector2i] = [start]
	var distances := {start: 0}
	var head := 0
	while head < pending.size():
		var cell: Vector2i = pending[head]
		head += 1
		if cell == goal:
			return int(distances[cell])
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not terrain.contains(next) or distances.has(next) or not terrain.can_step(cell, next):
				continue
			distances[next] = int(distances[cell]) + 1
			pending.append(next)
	return -1
