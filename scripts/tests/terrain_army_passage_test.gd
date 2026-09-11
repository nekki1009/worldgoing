extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			var label := argument.trim_prefix("--case=")
			if label not in ["E05_TURN", "M01_SMALL_PLATFORM"]:
				push_error("Unknown geometry fixture: " + label)
				quit(1)
				return
			var passed := _run_geometry(label)
			quit(0 if passed else 1)
			return
	if not _verify_no_false_follow_rally():
		quit(1)
		return
	print("TERRAIN ARMY PASSAGE P0: no generic FOLLOW rally completion")
	quit(0)

func _verify_no_false_follow_rally() -> bool:
	var data := _flat_data()
	var player := TerrainTestCharacter.new()
	player.data = data
	var passed := player.place(Vector2i(50, 50), true)
	var npc := TerrainTestNPC.new()
	npc.data = data
	passed = passed and npc.place(Vector2i(51, 50), true)
	var army := TerrainArmy.new()
	if not passed or not army.deploy(data, player, npc):
		push_error("FIXTURE_INVALID generic FOLLOW rally")
		return false
	army.command = TerrainArmy.Command.FOLLOW_PLAYER
	army.desired_cells[0] = army.cells[0]
	army.formation_mode = TerrainArmy.FormationMode.OPEN
	army._formation_has_bottleneck = false
	passed = not army._all_followers_in_exit_rally()
	army._settle_exit_rally()
	passed = passed and not army._exit_rally_settled and not army.command_status.contains("Exit rally assembled")
	if not passed:
		push_error("FOLLOW without a passage accepted a generic exit rally")
	army.free()
	npc.free()
	player.free()
	return passed

func _flat_data() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(100, 100))
	for index: int in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.surface_types[index] = TerrainData.Surface.GRASS
		data.flags[index] = TerrainData.Flag.WALKABLE
	return data

func _run_geometry(label: String) -> bool:
	var terrain := TerrainData.new()
	terrain.allocate(Vector2i(60, 40))
	terrain.flags.fill(TerrainData.Flag.BLOCKED)
	var required: Array[Array] = []
	var goal_player := Vector2i(55, 28)
	if label == "E05_TURN":
		# Two open deployment/rally platforms linked only by this single-cell S.
		for y: int in range(1, 39):
			for x: int in range(1, 59):
				if x <= 18 or x >= 41:
					terrain.flags[terrain.index(Vector2i(x, y))] = TerrainData.Flag.WALKABLE
		var corners: Array[Vector2i] = [Vector2i(18, 20), Vector2i(28, 20), Vector2i(28, 8), Vector2i(36, 8), Vector2i(36, 28), Vector2i(41, 28)]
		for segment: int in range(corners.size() - 1):
			var current := corners[segment]
			var direction := (corners[segment + 1] - current).sign()
			while current != corners[segment + 1]:
				var next := current + direction
				required.append([current, next])
				terrain.flags[terrain.index(current)] = TerrainData.Flag.WALKABLE
				terrain.flags[terrain.index(next)] = TerrainData.Flag.WALKABLE
				current = next
	else:
		# The middle level has exactly 3x5=15 cells, not room to hold 99.
		# All units must stream 0 -> 1 -> 0 through two independently gated ramps.
		for y: int in range(1, 39):
			for x: int in range(1, 59):
				if x <= 21 or x >= 25 or (y >= 18 and y <= 22):
					terrain.flags[terrain.index(Vector2i(x, y))] = TerrainData.Flag.WALKABLE
				if x >= 22 and x <= 24:
					terrain.height_levels[terrain.index(Vector2i(x, y))] = 1
		required = [[Vector2i(21, 20), Vector2i(22, 20)], [Vector2i(24, 20), Vector2i(25, 20)]]
		for gate: Array in required:
			terrain.ramp_edges[terrain.index(gate[0])] = 1 << 1
			terrain.ramp_edges[terrain.index(gate[1])] = 1 << 3
		goal_player = Vector2i(55, 20)
	var player := TerrainTestCharacter.new()
	player.data = terrain
	var npc := TerrainTestNPC.new()
	npc.data = terrain
	var army := TerrainArmy.new()
	var passed := player.place(Vector2i(3, 20), true) and npc.place(Vector2i(2, 20), true)
	passed = passed and army.deploy(terrain, player, npc) and player.place(goal_player, true) and army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER)
	if passed:
		passed = _replay_geometry(army, terrain, label, required)
	else:
		push_error("FIXTURE_INVALID " + label)
	army.free()
	npc.free()
	player.free()
	return passed

func _replay_geometry(army: TerrainArmy, terrain: TerrainData, label: String, required: Array[Array]) -> bool:
	var hz := 30 if "--30hz" in OS.get_cmdline_user_args() else 60
	var alternating := "--alternating" in OS.get_cmdline_user_args()
	var last_progress := 0
	var no_progress_time := 0.0
	var progress := PackedInt32Array()
	progress.resize(100)
	var counts := PackedInt32Array()
	counts.resize(required.size())
	var previous := army.cells.duplicate()
	var rally_best := {}
	var rally_progress := 0
	print(label, " START source=", FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"), " fingerprint=", terrain.fingerprint(), " required_edges=", required, " INITIAL_CELLS=", previous)
	for frame: int in range(180 * hz):
		var delta := (1.0 / 120.0 if frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz)
		army.advance_frame(delta)
		if not preload("res://scripts/tests/terrain_army_default_edge_test.gd")._legal_state(army, terrain):
			return false
		var seen := {}
		for unit: int in range(100):
			if seen.has(army.cells[unit]) or army._cell_owners.get(army.cells[unit], -1) != unit:
				push_error(label + " owner or overlap failure")
				return false
			seen[army.cells[unit]] = true
			if previous[unit] == army.cells[unit]:
				continue
			if not terrain.can_step(previous[unit], army.cells[unit]):
				push_error(label + " illegal committed edge")
				return false
			var last_gate: Array = required.back()
			var forward: Vector2i = last_gate[1] - last_gate[0]
			var from_exit: Vector2i = army.cells[unit] - last_gate[1]
			if from_exit.x * forward.x + from_exit.y * forward.y > 0:
				var goal: Vector2i = army.desired_cells[unit]
				var key := "%d:%s" % [unit, goal]
				var distance := absi(army.cells[unit].x - goal.x) + absi(army.cells[unit].y - goal.y)
				var old_distance := absi(previous[unit].x - goal.x) + absi(previous[unit].y - goal.y)
				if distance < int(rally_best.get(key, old_distance)):
					rally_progress += 1
					rally_best[key] = distance
				for transaction: Dictionary in army._pending_pushes:
					var requester: int = transaction.requester
					if not transaction.units.has(unit) or army._unit_passage_phase[requester] != TerrainArmy.PassagePhase.EXIT_CLEAR or army._unit_passage_exit_clear[requester] != 0:
						continue
					var edge_key := "outlet:%d:%s:%s" % [unit, previous[unit], army.cells[unit]]
					if not rally_best.has(edge_key):
						rally_best[edge_key] = true
						rally_progress += 1
			for edge: int in range(required.size()):
				if previous[unit] == required[edge][1] and army.cells[unit] == required[edge][0]:
					push_error(label + " backward corridor commit")
					return false
				if previous[unit] == required[edge][0] and army.cells[unit] == required[edge][1]:
					if progress[unit] != edge:
						push_error(label + " out-of-order corridor commit")
						return false
					progress[unit] += 1
					if unit == 0:
						if counts[edge] < 20 or counts[edge] > 70:
							push_error(label + " captain bypassed front/rear corridor order")
							return false
					else:
						counts[edge] += 1
		var progress_sum := rally_progress
		var ready := false
		for unit: int in range(100):
			progress_sum += progress[unit]
			if progress[unit] < required.size() and army.cells[unit] == required[progress[unit]][0]:
				ready = true
		no_progress_time = no_progress_time + delta if ready and progress_sum == last_progress and army.passage_active() else 0.0
		last_progress = progress_sum
		if no_progress_time >= 5.0:
			var pending_units := []
			for unit: int in range(100):
				if army.cells[unit] != army.desired_cells[unit]:
					pending_units.append([unit, army.cells[unit], army.desired_cells[unit], army._unit_passage_phase[unit], army._unit_passage[unit], army._push_lock[unit]])
			print(label, " STALL t=", army.input_seconds, " counts=", counts, " group=", [army._passage_group_start, army._passage_group_end], " pending_units=", pending_units, " transactions=", army._pending_pushes, " claims=", army._reserved_cells)
			push_error(label + " NO_PASSAGE_PROGRESS physical corridor cursors stalled")
			return false
		previous = army.cells.duplicate()
		if army.max_frame_structure_expansions > 256 or army.max_frame_local_expansions > 8192 or army.max_frame_push_expansions > 1024 or army.dropped_seconds != 0.0:
			push_error(label + " search budget or time accounting failure")
			return false
		if (frame + 1) % (10 * hz) == 0:
			print(label, " t=", army.input_seconds, " front=", counts[0], " tail=", counts[-1], " settled=", army.formation_count(), " summary=", army.passage_summary())
		if army.is_formation_complete():
			for unit: int in range(100):
				if progress[unit] != required.size() or army.cells[unit] != army.desired_cells[unit]:
					push_error(label + " completion before every required edge")
					return false
			var completion := army.input_seconds
			var stable := army.cells.duplicate()
			for stable_frame: int in range(5 * hz):
				army.advance_frame((1.0 / 120.0 if stable_frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz))
				if not army.is_formation_complete() or army.cells != stable or not preload("res://scripts/tests/terrain_army_default_edge_test.gd")._legal_state(army, terrain):
					push_error(label + " unstable final formation")
					return false
			if label == "M01_SMALL_PLATFORM" and (army._passage_descriptors.size() != 2 or not army._passage_descriptors[0].rally_layout.is_empty()):
				push_error(label + " 15-cell middle platform was not merged as a continuous group")
				return false
			print(label, " PASS complete=", completion, " all_edge_counts=", counts, " captain_required_edges=", progress[0], " captain_middle_order=true stable=5")
			return true
	push_error(label + " missed 180-second input deadline")
	print(label, " FAILURE cells=", army.cells, " phases=", army._unit_passage_phase, " completed=", army._unit_completed_exits, " counts=", counts, " status=", army.command_status)
	return false
