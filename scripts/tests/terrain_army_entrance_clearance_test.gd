extends SceneTree

# Fixed 40x30 fixtures; every full-formation case uses the public frame entry.
const CORE := Vector2i(20, 15)
const ENTRY := Vector2i(19, 15)
const EXIT_CELL := Vector2i(21, 15)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var cases := ["E01", "E02"]
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			cases = [argument.trim_prefix("--case=")]
	for label: String in cases:
		if label in ["TERMINAL_FLAT", "TERMINAL_RAMP"]:
			if not _terminal_case(label):
				quit(1)
				return
			continue
		if label not in ["E01", "E02", "E03_FLAT", "E03_RAMP", "E04_LAST", "E07_LANES", "E08_NEAR", "E09_EXTERNAL", "E10_REVERSE", "E11_CAPACITY", "E12_BYPASS", "E12_DOWNSTREAM"]:
			push_error("Unknown entrance case: " + label)
			quit(1)
			return
		if not _run_case(label):
			quit(1)
			return
	print("ARMY_ENTRANCE_CLEARANCE_PASS: ", cases)
	quit(0)

func _terminal_case(label: String) -> bool:
	# Fixed terminal-only map: 37x28 same-height interior, one cell-wide
	# branch (37,15)->(38,15)->(39,15), sole boundary goal (39,15).
	# RAMP changes ONLY the last two cells to height 1 with reciprocal entry.
	# The high side then has two cells, independently fewer than 99 slots.
	var terrain := TerrainData.new()
	terrain.allocate(Vector2i(40, 30))
	terrain.flags.fill(TerrainData.Flag.BLOCKED)
	for y: int in range(1, 29):
		for x: int in range(1, 38):
			terrain.flags[terrain.index(Vector2i(x, y))] = TerrainData.Flag.WALKABLE
	for x: int in range(38, 40):
		terrain.flags[terrain.index(Vector2i(x, 15))] = TerrainData.Flag.WALKABLE
		terrain.height_levels[terrain.index(Vector2i(x, 15))] = 1 if label == "TERMINAL_RAMP" else 0
	if label == "TERMINAL_RAMP":
		terrain.ramp_edges[terrain.index(Vector2i(37, 15))] = 1 << TerrainData.DIRECTIONS.find(Vector2i.RIGHT)
		terrain.ramp_edges[terrain.index(Vector2i(38, 15))] = 1 << TerrainData.DIRECTIONS.find(Vector2i.LEFT)
	var player := TerrainTestCharacter.new()
	player.data = terrain
	var npc := TerrainTestNPC.new()
	npc.data = terrain
	var army := TerrainArmy.new()
	var valid := player.place(Vector2i(3, 15), true) and npc.place(Vector2i(2, 15), true)
	valid = valid and army.deploy(terrain, player, npc)
	if valid:
		print(label, " PREFLIGHT platform_cells=1036 high_side=", 2 if label == "TERMINAL_RAMP" else 0, " sole_boundary=(39,15) fingerprint=", terrain.fingerprint(), " INITIAL_CELLS=", army.cells, " source=", FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"))
		valid = army.issue_command(TerrainArmy.Command.MOVE_TO_EDGE) and _terminal_replay(army, terrain, label)
	else:
		push_error("FIXTURE_INVALID " + label)
	army.free()
	npc.free()
	player.free()
	return valid

func _terminal_replay(army: TerrainArmy, terrain: TerrainData, label: String) -> bool:
	var previous := army.cells.duplicate()
	var slots: Array[Vector2i] = []
	var complete_time := -1.0
	var hz := 30 if "--30hz" in OS.get_cmdline_user_args() else 60
	var alternating := "--alternating" in OS.get_cmdline_user_args()
	for frame: int in range(180 * hz):
		army.advance_frame((1.0 / 120.0 if frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz))
		if not _legal(army, terrain):
			return _fail(army, label, "owner/claim/lock/budget invariant")
		for unit: int in range(100):
			if previous[unit] != army.cells[unit] and not terrain.can_step(previous[unit], army.cells[unit]):
				return _fail(army, label, "illegal committed edge")
		previous = army.cells.duplicate()
		if "--trace" in OS.get_cmdline_user_args() and frame % (10 * hz) == 0:
			var pending := []
			for unit: int in range(100):
				if army.cells[unit] != army.desired_cells[unit]:
					pending.append([unit, army.cells[unit], army.desired_cells[unit]])
			print("TERMINAL_TRACE t=", army.input_seconds, " macro=", army._formation_march_active, " batches=", army.formation_batch_steps, " guide=", army._formation_anchor_cell, " reformed=", army._formation_final_reform, " pending=", pending, " capacity=", army._passage_slot_capacity, " group=", [army._passage_group_start, army._passage_group_end], " capfinal=", army._passage_final_captain_slot, " capclear=", army._unit_has_cleared_passages(0), " capegress=", army._passage_final_egress_cell(army.cells[0]), " locks=", army._push_lock, " swap=", [army.has_active_swap(), army._has_active_follower_swap()])
		if not army._command_goal_pending and army._march_goal != Vector2i(39, 15):
			return _fail(army, label, "wrong sole boundary goal")
		if army.passage_active() and slots.is_empty():
			slots = army._passage_final_slots.duplicate()
		if not slots.is_empty() and army._passage_final_slots != slots:
			return _fail(army, label, "slot set changed")
		if label == "TERMINAL_RAMP" and army.input_seconds >= 20.0:
			if army.cells[0].x >= 38 or army.passage_crossed_count() != 0 or army.moving_count() != 0 or not army._reserved_cells.is_empty() \
				or army.is_formation_complete() or army._passage_descriptors.is_empty() or not army.command_status.contains("INSUFFICIENT_RALLY_CAPACITY"):
				return _fail(army, label, "final height change was skipped or capacity/goal wrong")
			print(label, " PASS front_goal=(39,15) no_partial_admission complete=false true_capacity<100 status=", army.command_status)
			return true
		if army.is_formation_complete():
			if label != "TERMINAL_FLAT" or slots.size() != 99 or not army._passage_descriptors.is_empty() or army.passage_crossed_count() != 0:
				return _fail(army, label, "terminal-only classification/counts wrong")
			if not slots.has(Vector2i(39, 15)) or army.cells[0].x >= 38 or army.cells[0] != army._passage_final_captain_slot:
				return _fail(army, label, "front rank must occupy boundary while captain remains central")
			var guards := 0
			var rear := 0
			for unit: int in range(1, 100):
				guards += int(army.cells[unit].x > army.cells[0].x)
				rear += int(army.cells[unit].x < army.cells[0].x)
				if not slots.has(army.cells[unit]) or army.cells[unit] != army.desired_cells[unit]:
					return _fail(army, label, "final body is incomplete")
			if guards < 20 or rear < 20:
				return _fail(army, label, "captain lacks a real front/rear protection layer")
			complete_time = army.input_seconds
			break
	if complete_time < 0:
		return _fail(army, label, "missed 180-second input deadline")
	for frame: int in range(5 * hz):
		army.advance_frame((1.0 / 120.0 if frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz))
		if not _legal(army, terrain) or army.cells != previous or not army.is_formation_complete():
			return _fail(army, label, "unstable five-second completion")
	print(label, " PASS complete_seconds=", complete_time, " settled=99 stable=5 descriptors=0 physical_crossings=0 claims=", army._reserved_cells.size())
	return true

func _run_case(label: String) -> bool:
	var terrain := _entrance_data(label in ["E02", "E03_RAMP"])
	var edge := label.begins_with("E03")
	if edge:
		for y: int in range(30):
			for x: int in range(40):
				if (x == 0 or x == 39 or y == 0 or y == 29) and Vector2i(x, y) != Vector2i(39, 15):
					terrain.flags[terrain.index(Vector2i(x, y))] = TerrainData.Flag.BLOCKED
	if label == "E11_CAPACITY":
		# 67 right-side walkable cells, including the captain's goal corridor:
		# an independently obvious insufficient-capacity fixture, not bad search.
		for y: int in range(30):
			for x: int in range(21, 40):
				if not (y == 15 or (x >= 25 and x <= 32 and y >= 12 and y <= 18)):
					terrain.flags[terrain.index(Vector2i(x, y))] = TerrainData.Flag.BLOCKED
	if label == "E12_BYPASS":
		# A second, separated opening makes the chosen gate NON_SEPARATING.
		# The conservative runtime policy must still consume the selected gate.
		terrain.flags[terrain.index(Vector2i(20, 8))] = TerrainData.Flag.WALKABLE
	if label == "E07_LANES":
		terrain.flags[terrain.index(Vector2i(20, 16))] = TerrainData.Flag.WALKABLE
	var player := TerrainTestCharacter.new()
	player.data = terrain
	var npc := TerrainTestNPC.new()
	npc.data = terrain
	var army := TerrainArmy.new()
	var valid := player.place(Vector2i(3, 15), true) and npc.place(Vector2i(2, 15), true)
	valid = valid and army.deploy(terrain, player, npc)
	for cell: Vector2i in army.cells:
		valid = valid and cell.x < 20
	if valid and label == "E12_DOWNSTREAM":
		# Additional one-gate fixture: ten followers start on the proven exit
		# platform. This one-time placement precedes the command and all frames.
		for unit: int in range(1, 11):
			army._cell_owners.erase(army.cells[unit])
			army.cells[unit] = Vector2i(24 + (unit - 1) % 5, 8 + floori(float(unit - 1) / 5.0))
			army.desired_cells[unit] = army.cells[unit]
			army._formation_slot_cells[unit] = army.cells[unit]
			army._formation_offsets[unit] = army.cells[unit] - army.cells[0]
			army._cell_owners[army.cells[unit]] = unit
		print("E12_DOWNSTREAM INITIALIZATION_ONLY units=1..10 right-side; others=89 upstream")
	if valid and label in ["E12_BYPASS", "E12_DOWNSTREAM"]:
		var reachable := _reachable_with_gate_sealed(terrain, ENTRY)
		valid = reachable.has(EXIT_CELL) if label == "E12_BYPASS" else not reachable.has(EXIT_CELL)
		print(label, " PREFLIGHT selected_gate_sealed exit_connected=", reachable.has(EXIT_CELL), " reachable_cells=", reachable.size())
	if not valid:
		push_error("FIXTURE_INVALID " + label + " initial 100-person deployment")
	else:
		player.cell_blocker = Callable(army, "blocks_cell")
		npc.cell_blocker = Callable(army, "blocks_cell")
		if not edge:
			valid = player.place(Vector2i(26, 20) if label == "E08_NEAR" else Vector2i(36, 15), true)
		if label == "E09_EXTERNAL":
			valid = valid and npc.place(ENTRY, true)
		valid = valid and army.issue_command(TerrainArmy.Command.MOVE_TO_EDGE if edge else TerrainArmy.Command.FOLLOW_PLAYER)
		if valid:
			valid = _replay_reverse(army, terrain) if label == "E10_REVERSE" else _replay(army, terrain, label, edge)
		else:
			push_error("FIXTURE_INVALID " + label + " command or external placement")
	army.free()
	npc.free()
	player.free()
	return valid

func _replay_reverse(army: TerrainArmy, terrain: TerrainData) -> bool:
	var hz := 30 if "--30hz" in OS.get_cmdline_user_args() else 60
	var alternating := "--alternating" in OS.get_cmdline_user_args()
	var requested := false
	var activated := false
	var old_epoch := -1
	var old_protected := {}
	var required := {}
	var crossed := {}
	var cleared := {}
	var previous := army.cells.duplicate()
	print("E10_REVERSE START source=", FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"), " INITIAL_CELLS=", previous)
	for frame: int in range(180 * hz):
		army.advance_frame((1.0 / 120.0 if frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz))
		if not _legal(army, terrain):
			return _fail(army, "E10_REVERSE", "ownership or budget invariant")
		if not requested and army.passage_active():
			for unit: int in range(1, 100):
				if army._unit_passage_phase[unit] != TerrainArmy.PassagePhase.IN_PASSAGE:
					continue
				old_epoch = army._command_epoch
				for descriptor: Dictionary in army._passage_descriptors:
					for cell: Vector2i in descriptor.core:
						old_protected[cell] = true
					old_protected[descriptor.exit] = true
				var source := army.cells.duplicate()
				var destinations := army.moving_to.duplicate()
				var interpolation := army.move_progress.duplicate()
				if not army.player.place(Vector2i(3, 15), true) or not army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER):
					return _fail(army, "E10_REVERSE", "FIXTURE_INVALID reverse request")
				if army.cells != source or army.moving_to != destinations or army.move_progress != interpolation or army._command_epoch != old_epoch or army._pending_command < 0:
					return _fail(army, "E10_REVERSE", "request rewound an edge or activated before draining")
				requested = true
				print("E10_REVERSE REQUEST input=", army.input_seconds, " old_epoch=", old_epoch, " cells=", source)
				break
		if requested and not activated and army._command_epoch != old_epoch:
			activated = true
			for unit: int in range(1, 100):
				if old_protected.has(army.cells[unit]):
					return _fail(army, "E10_REVERSE", "new direction published before old core/egress cleared")
				if army.cells[unit].x > 20:
					required[unit] = true
			print("E10_REVERSE ACTIVATE input=", army.input_seconds, " new_epoch=", army._command_epoch, " reverse_required=", required.keys())
		if requested and not activated:
			for unit: int in range(1, 100):
				if previous[unit] == CORE and army.cells[unit] == ENTRY:
					return _fail(army, "E10_REVERSE", "old in-flight unit reversed before clearance")
		if activated:
			for unit: int in range(1, 100):
				if previous[unit] == EXIT_CELL and army.cells[unit] == CORE:
					if not required.has(unit) or crossed.has(unit):
						return _fail(army, "E10_REVERSE", "unexpected or duplicate reverse crossing")
					crossed[unit] = true
				if previous[unit] == CORE and army.cells[unit] == ENTRY:
					if not crossed.has(unit) or cleared.has(unit):
						return _fail(army, "E10_REVERSE", "reverse exit before ordered crossing")
					cleared[unit] = true
		previous = army.cells.duplicate()
		if activated and army.is_formation_complete():
			if required.is_empty() or crossed.size() != required.size() or cleared.size() != required.size():
				return _fail(army, "E10_REVERSE", "required reverse passages incomplete")
			for unit: int in range(1, 100):
				if army.cells[unit].x >= 20:
					return _fail(army, "E10_REVERSE", "final member remained on old exit side")
			var stable := army.cells.duplicate()
			for stable_frame: int in range(5 * hz):
				army.advance_frame((1.0 / 120.0 if stable_frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz))
				if army.cells != stable or not _legal(army, terrain) or not army.is_formation_complete():
					return _fail(army, "E10_REVERSE", "stable final formation failed")
			print("E10_REVERSE PASS input=", army.input_seconds, " required=", required.size(), " crossed=", crossed.size(), " cleared=", cleared.size())
			return true
	return _fail(army, "E10_REVERSE", "missed 180-second deadline")

func _replay(army: TerrainArmy, terrain: TerrainData, label: String, edge: bool) -> bool:
	var hz := 30 if "--30hz" in OS.get_cmdline_user_args() else 60
	var alternating := "--alternating" in OS.get_cmdline_user_args()
	var initial := army.cells.duplicate()
	var previous := initial.duplicate()
	var crossed := {}
	var cleared := {}
	var slots: Array[Vector2i] = []
	var completion := -1.0
	var external_removed := false
	var restored_progress := false
	var last_hold_started := -1.0
	var last_hold_finished := false
	var no_progress_time := 0.0
	var last_physical_progress := 0
	var rally_best := {}
	var rally_progress := 0
	var required_count := 89 if label == "E12_DOWNSTREAM" else 99
	var source := FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd")
	print(label, " START source=", source, " fingerprint=", terrain.fingerprint(), " INITIAL_CELLS=", initial)
	for frame: int in range(180 * hz):
		if label == "E09_EXTERNAL" and not external_removed and army.input_seconds + 0.0001 >= 20.0:
			if not army.npc.place(Vector2i(2, 15), true):
				return _fail(army, label, "FIXTURE_INVALID NPC removal")
			external_removed = true
		var delta := (1.0 / 120.0 if frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz)
		army.advance_frame(delta)
		if not _legal(army, terrain):
			return _fail(army, label, "overlap / owner / claim / lock / illegal cell")
		if edge and not army._command_goal_pending and army._march_goal != Vector2i(39, 15):
			return _fail(army, label, "EDGE did not select the sole boundary opening")
		if army.passage_active() and slots.is_empty():
			slots = army._passage_final_slots.duplicate()
			if label == "E12_DOWNSTREAM":
				for unit: int in range(1, 100):
					if army._unit_initial_exempt_exits[unit] != (1 if unit <= 10 else 0):
						return _fail(army, label, "initial exemption disagrees with sealed-gate topology")
		if not slots.is_empty() and army._passage_final_slots != slots:
			return _fail(army, label, "published slot set changed")
		for unit: int in range(100):
			if previous[unit] == army.cells[unit]:
				continue
			if not terrain.can_step(previous[unit], army.cells[unit]):
				return _fail(army, label, "illegal committed edge")
			# V6 counts actual local receiving work, not only crossing the gate.
			# A new best distance for this fixed goal cannot be refreshed by an
			# oscillating push or interpolation, and upstream/remote units do not count.
			if army.cells[unit].x > 21 and army.desired_cells[unit] != TerrainArmy.INVALID_CELL:
				var goal: Vector2i = army.desired_cells[unit]
				var key := "%d:%s" % [unit, goal]
				var distance := absi(army.cells[unit].x - goal.x) + absi(army.cells[unit].y - goal.y)
				var old_distance := absi(previous[unit].x - goal.x) + absi(previous[unit].y - goal.y)
				if distance < int(rally_best.get(key, old_distance)):
					rally_progress += 1
					rally_best[key] = distance
			if unit == 0:
				continue
			if previous[unit] == CORE and army.cells[unit] == ENTRY:
				return _fail(army, label, "reverse gate crossing")
			if previous[unit] == ENTRY and army.cells[unit] == CORE:
				if label == "E12_DOWNSTREAM" and unit <= 10:
					return _fail(army, label, "initial downstream exemption was forced back through the gate")
				if crossed.has(unit):
					return _fail(army, label, "duplicate crossing")
				crossed[unit] = army.input_seconds
				if external_removed:
					restored_progress = true
			if previous[unit] == CORE and army.cells[unit] == EXIT_CELL:
				if not crossed.has(unit) or cleared.has(unit):
					return _fail(army, label, "out-of-order or duplicate physical clearance")
				cleared[unit] = army.input_seconds
		var physical_progress := crossed.size() + cleared.size() + rally_progress
		var ready := army.cells.has(ENTRY) or army.cells.has(CORE)
		var externally_blocked: bool = army.npc.terrain_cell in [ENTRY, CORE, EXIT_CELL] or army.player.terrain_cell in [ENTRY, CORE, EXIT_CELL]
		no_progress_time = no_progress_time + delta if ready and physical_progress == last_physical_progress and not externally_blocked and army.passage_active() and label != "E11_CAPACITY" else 0.0
		last_physical_progress = physical_progress
		if no_progress_time >= 5.0:
			return _fail(army, label, "NO_PASSAGE_PROGRESS despite ready front and no external/capacity blocker")
		previous = army.cells.duplicate()
		if label == "E04_LAST" and crossed.size() == 99 and cleared.size() == 98:
			if not army.cells.has(CORE) or army.is_formation_complete():
				return _fail(army, label, "last unit remains in core but completion or physical observation is wrong")
			if last_hold_started < 0.0:
				last_hold_started = army.input_seconds
		if last_hold_started >= 0.0 and not last_hold_finished and cleared.size() == 99:
			last_hold_finished = army.input_seconds > last_hold_started
			print(label, " LAST_CORE_WINDOW start=", last_hold_started, " clear=", army.input_seconds, " completion_false=true")
		if label == "E09_EXTERNAL" and army.input_seconds >= 25.0 and not restored_progress:
			return _fail(army, label, "no forward passage commit within five seconds of NPC removal")
		if (frame + 1) % (10 * hz) == 0:
			print(label, " t=", army.input_seconds, " crossed=", crossed.size(), " cleared=", cleared.size(), " settled=", army.formation_count(), " status=", army.command_status)
		if label == "E11_CAPACITY" and army.input_seconds >= 20.0:
			if army._command_goal_pending or army.is_formation_complete() or army.passage_slot_capacity() >= 99 \
				or not crossed.is_empty() or army.cells[0].x >= 20 or army.moving_count() != 0 or not army._reserved_cells.is_empty():
				return _fail(army, label, "capacity failure admitted a partial army or scout")
			if not army.command_status.contains("INSUFFICIENT_RALLY_CAPACITY"):
				return _fail(army, label, "missing explicit insufficient-capacity reason")
			print(label, " PASS input=", army.input_seconds, " capacity=", army.passage_slot_capacity(), " status=", army.command_status)
			return true
		if army.is_formation_complete():
			if crossed.size() != required_count or cleared.size() != required_count or army.formation_count() != 99:
				return _fail(army, label, "completion preceded all 99 physical crossings / clearances")
			completion = army.input_seconds
			break
	if completion < 0:
		return _fail(army, label, "missed 180 input-second deadline")
	if label == "E04_LAST" and not last_hold_finished:
		return _fail(army, label, "FIXTURE_INVALID last-core hold was not exercised")
	var actual_slots := {}
	for unit: int in range(1, 100):
		var cell: Vector2i = army.cells[unit]
		if cell.x <= 20 or not slots.has(cell) or cell != army.desired_cells[unit] or actual_slots.has(cell):
			return _fail(army, label, "invalid final slot/binding")
		actual_slots[cell] = true
	if slots.size() != 99 or actual_slots.size() != 99 or army.passage_crossed_count() != required_count:
		return _fail(army, label, "physical and production final counts disagree")
	var settled := army.cells.duplicate()
	if edge and (not slots.has(Vector2i(39, 15)) or army.cells[0].x >= 38 or army.cells[0] != army._passage_final_captain_slot):
		return _fail(army, label, "EDGE requires the front rank at boundary and captain inside")
	var bindings := army.desired_cells.duplicate()
	for frame: int in range(5 * hz):
		var delta := (1.0 / 120.0 if frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz)
		army.advance_frame(delta)
		if not _legal(army, terrain) or army.cells != settled or army.desired_cells != bindings or not army.is_formation_complete():
			return _fail(army, label, "five-second stable completion failed")
	print(label, " PASS complete_seconds=", completion, " crossed=", crossed.size(), " cleared=", cleared.size(), " initial_exempt=", 99 - required_count, " stable=5 source=", source, " gate_events=", crossed, " clear_events=", cleared, " max_structure=", army.max_frame_structure_expansions, " max_local=", army.max_frame_local_expansions, " max_push=", army.max_frame_push_expansions)
	return true

func _reachable_with_gate_sealed(terrain: TerrainData, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if (current == ENTRY and next == CORE) or (current == CORE and next == ENTRY):
				continue
			if terrain.can_step(current, next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen

func _legal(army: TerrainArmy, terrain: TerrainData) -> bool:
	var seen := {}
	var claims := {}
	var locks := {}
	for pending: Dictionary in army._pending_pushes:
		claims[pending.cells[0]] = int(pending.requester)
		locks[int(pending.requester)] = true
		for offset: int in range(pending.units.size()):
			var unit := int(pending.units[offset])
			if pending.get("committed", {}).has(unit):
				continue
			claims[pending.cells[offset + 1]] = unit
			locks[unit] = true
	for unit: int in range(100):
		var cell: Vector2i = army.cells[unit]
		if seen.has(cell) or army._cell_owners.get(cell, -1) != unit or not terrain.is_walkable(cell) or army._is_external_cell(cell):
			return false
		seen[cell] = true
		if army.movement_state[unit] in [TerrainArmy.UnitState.MOVING, TerrainArmy.UnitState.SWAPPING]:
			if army._reserved_cells.get(army.moving_to[unit], -1) != unit:
				return false
			claims[army.moving_to[unit]] = unit
		if army._push_lock[unit] != 0 and not locks.has(unit):
			return false
	for cell: Vector2i in army._reserved_cells:
		if claims.get(cell, -1) != army._reserved_cells[cell]:
			return false
	return army.max_frame_structure_expansions <= 256 and army.max_frame_local_expansions <= 8192 and army.max_frame_push_expansions <= 1024 and army.dropped_seconds == 0.0

func _fail(army: TerrainArmy, label: String, reason: String) -> bool:
	push_error(label + " " + reason)
	print(label, " FAILURE input=", army.input_seconds, " captain=", army.cells[0], " goal=", army.desired_cells[0], " status=", army.command_status, " phases=", army._unit_passage_phase, " completed_exits=", army._unit_completed_exits, " slots=", army._passage_final_slots, " cells=", army.cells, " claims=", army._reserved_cells, " pending=", army._pending_pushes)
	return false

static func _entrance_data(elevated_exit: bool) -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(40, 30))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.height_levels.fill(0)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	for y: int in range(data.size.y):
		if y != 15:
			data.flags[data.index(Vector2i(20, y))] = TerrainData.Flag.BLOCKED
	if elevated_exit:
		for y: int in range(data.size.y):
			for x: int in range(20, data.size.x):
				data.height_levels[data.index(Vector2i(x, y))] = 1
		var low := Vector2i(19, 15)
		var high := Vector2i(20, 15)
		data.ramp_edges[data.index(low)] |= 1 << TerrainData.DIRECTIONS.find(Vector2i.RIGHT)
		data.ramp_edges[data.index(high)] |= 1 << TerrainData.DIRECTIONS.find(Vector2i.LEFT)
	data.spawn_cell = Vector2i(3, 15)
	return data
