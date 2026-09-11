extends SceneTree

const EdgeChecks = preload("res://scripts/tests/terrain_army_default_edge_test.gd")
const EntranceFixture = preload("res://scripts/tests/terrain_army_entrance_clearance_test.gd")

var _failed := false
var _army: TerrainArmy
var _terrain: TerrainData
var _player: TerrainTestCharacter
var _npc: TerrainTestNPC

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var selected := "G01"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			selected = argument.trim_prefix("--case=")
	if not _fixture(selected):
		_finish(selected)
		return
	match selected:
		"G01":
			_check_open_advance()
		"G02":
			_check_catch_up(false)
		"G03":
			_check_catch_up(true)
		"G04":
			_check_atomic_step()
		"G04_SUBSET":
			_check_subset_step()
		"G04_PARALLEL":
			_check_parallel_subsets()
		"G08_BEND":
			_check_bend_counterexample()
		"G08_BEND_FOURTH":
			_check_bend_counterexample(true)
		"G08_BEND_REPLAY":
			_check_bend_counterexample(true)
		"G05":
			_check_single_gate()
		"G05_BINDING":
			_check_future_receiving_binding()
		"G06":
			_check_two_gate_rally()
		"G07_MEDIUM":
			_check_medium_corridor()
		"G08", "G08_RETURN":
			_check_turn(selected == "G08_RETURN")
		"G09":
			_check_edge_front()
		"G10_RECEIVING_EF", "G10_RECEIVING_FE":
			_check_receiving_handoff(selected.ends_with("EF"))
		_:
			_check(false, "unknown case %s" % selected)
	_finish(selected)

func _fixture(selected: String) -> bool:
	_terrain = TerrainData.new()
	_terrain.allocate(Vector2i(100, 100))
	for index: int in range(_terrain.size.x * _terrain.size.y):
		_terrain.height_levels[index] = 0
		_terrain.surface_types[index] = TerrainData.Surface.GRASS
		_terrain.flags[index] = TerrainData.Flag.WALKABLE
	if selected in ["G08_BEND", "G08_BEND_FOURTH", "G08_BEND_REPLAY"]:
		var terrain_seed := 12345
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--terrain-seed="):
				terrain_seed = int(argument.trim_prefix("--terrain-seed="))
		_terrain = TerrainGenerator.generate(TerrainPreset.Kind.TERRACED_HIGHLAND, terrain_seed)
	elif selected in ["G05", "G07_MEDIUM", "G10_RECEIVING_EF", "G10_RECEIVING_FE"]:
		_terrain = EntranceFixture._entrance_data(false)
		if selected == "G07_MEDIUM":
			for y: int in range(13, 18):
				_terrain.flags[_terrain.index(Vector2i(20, y))] = TerrainData.Flag.WALKABLE
		if selected.begins_with("G10_"):
			for y: int in range(30):
				for x: int in range(40):
					if (x == 0 or x == 39 or y == 0 or y == 29) and Vector2i(x, y) != Vector2i(39, 15):
						_terrain.flags[_terrain.index(Vector2i(x, y))] = TerrainData.Flag.BLOCKED
	elif selected == "G06":
		_terrain.allocate(Vector2i(70, 30))
		_terrain.flags.fill(TerrainData.Flag.WALKABLE)
		_terrain.surface_types.fill(TerrainData.Surface.GRASS)
		for x: int in [20, 45]:
			for y: int in range(30):
				if y != 15:
					_terrain.flags[_terrain.index(Vector2i(x, y))] = TerrainData.Flag.BLOCKED
	_player = TerrainTestCharacter.new()
	_player.data = _terrain
	_npc = TerrainTestNPC.new()
	_npc.set_data(_terrain)
	var entrance_case := selected in ["G05", "G06", "G07_MEDIUM"] or selected.begins_with("G10_")
	var player_cell := Vector2i(3, 15) if entrance_case else Vector2i(50, 50)
	var npc_cell := Vector2i(2, 15) if entrance_case else Vector2i(51, 50)
	if not _check(_player.place(player_cell, true) and _npc.place(npc_cell, true), "fixture actors"):
		return false
	_army = TerrainArmy.new()
	_army.set_process(false)
	if not _check(_army.deploy(_terrain, _player, _npc), "formal 100-person deployment"):
		return false
	_player.cell_blocker = Callable(_army, "blocks_cell")
	_npc.cell_blocker = Callable(_army, "blocks_cell")
	_npc.issue_command(TerrainTestNPC.Command.STOP)
	print("FORMATION_V6_START source=", FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"), " initial=", _army.cells)
	return true

func _check_open_advance() -> void:
	if not _check(_player.place(Vector2i(88, 50), true) and _army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER), "follow command"):
		return
	var previous := _army.cells.duplicate()
	var marching_frames := 0
	var first_batch_time := -1.0
	var last_progress_time := 0.0
	var previous_steps := _army.completed_steps()
	var complete_time := -1.0
	var hz := 30 if "--30hz" in OS.get_cmdline_user_args() else 60
	var alternating := "--alternating" in OS.get_cmdline_user_args()
	for frame_index: int in range(40 * hz):
		var delta := (1.0 / 120.0 if frame_index % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz)
		_army.advance_frame(delta)
		if not _check(EdgeChecks._legal_state(_army, _terrain), "owner/claim invariant"):
			return
		for unit: int in range(100):
			if previous[unit] != _army.cells[unit] and not _check(_terrain.can_step(previous[unit], _army.cells[unit]), "illegal edge unit=%d" % unit):
				return
		previous = _army.cells.duplicate()
		if "--trace" in OS.get_cmdline_user_args() and frame_index % hz == 0:
			var pending := []
			for unit: int in range(100):
				if _army.cells[unit] != _army.desired_cells[unit]:
					pending.append([unit, _army.cells[unit], _army.desired_cells[unit]])
			print("G01_TRACE t=", _army.input_seconds, " batches=", _army.formation_batch_steps, " anchor=", _army._formation_anchor_cell, " mode=", _army.formation_mode_name(), " status=", _army.command_status, " pending=", pending)
		if _army.completed_steps() > previous_steps or _army._command_goal_pending or _army._passage_plan_pending or _army._formation_target_pending:
			last_progress_time = _army.input_seconds
		previous_steps = _army.completed_steps()
		if not _check(_army.input_seconds - last_progress_time < 5.0, "initial formation had no physical progress for five seconds"):
			return
		if first_batch_time < 0.0 and (_army.formation_batch_steps > 0 or _army._formation_step_direction != Vector2i.ZERO):
			first_batch_time = _army.input_seconds
		if first_batch_time < 0.0 and not _check(_army.input_seconds <= 20.0, "initial formation exceeded the predeclared 20-second setup allowance"):
			return
		# The deployment is intentionally irregular. Verify the whole body from
		# the first collective intent, not an arbitrary eight-second timestamp
		# that also included a frame-budgeted command feasibility search.
		if first_batch_time >= 0.0:
			var forward := 0
			var behind := 0
			for unit: int in range(1, 100):
				forward += int(_army.cells[unit].x > _army.cells[0].x)
				behind += int(_army.cells[unit].x < _army.cells[0].x)
			if not _check(forward >= 10 and behind >= 10, "captain exposed t=%.3f front=%d rear=%d captain=%s" % [_army.input_seconds, forward, behind, _army.cells[0]]):
				return
			var footprint := Rect2i(_army.cells[0], Vector2i.ONE)
			for cell: Vector2i in _army.cells:
				footprint = footprint.merge(Rect2i(cell, Vector2i.ONE))
			if not _check(footprint.size.x <= 12 and footprint.size.y <= 12, "open formation stretched: %s" % footprint):
				return
			if _army.moving_count() > 0:
				marching_frames += 1
		if _army.is_formation_complete():
			complete_time = _army.input_seconds
			break
	if not _check(complete_time > 8.0 and marching_frames > hz and _army.formation_count() == 99, "no continuous cohesive march / completion t=%.3f moving_frames=%d" % [complete_time, marching_frames]):
		return
	var settled := _army.cells.duplicate()
	for frame_index: int in range(5 * hz):
		var delta := (1.0 / 120.0 if frame_index % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz)
		_army.advance_frame(delta)
		if not _check(_army.cells == settled and _army.is_formation_complete(), "final stability"):
			return
	_check(_army.dropped_seconds == 0.0, "ordinary dt dropped simulation time")
	_check(_army.formation_batch_steps >= 15, "no sustained collective steps")
	_check(_army._formation_anchor_cell == _army.cells[0] and _army.cells[0] + Vector2i.RIGHT * 4 == _army._march_goal, "captain/front command semantics")
	print("G01_METRICS first_batch=", first_batch_time, " complete=", complete_time, " marching_frames=", marching_frames, " stable=5 captain=", _army.cells[0], " command_goal=", _army._march_goal)

func _place_rectangular_fixture() -> void:
	configure_rectangular_snapshot(_army)

static func configure_rectangular_snapshot(army: TerrainArmy, anchor: Vector2i = Vector2i(50, 50)) -> void:
	# A single legal fixture publication before running the ordinary scheduler.
	army.player.place(Vector2i(army.data.size.x - 6, anchor.y), true)
	army.npc.place(army.data.size - Vector2i.ONE, true)
	army._cell_owners.clear()
	army._formation_anchor_cell = anchor
	army._formation_heading = Vector2i.RIGHT
	army._formation_march_active = true
	army.command = TerrainArmy.Command.FOLLOW_PLAYER
	army._last_follow_player_cell = army.player.terrain_cell
	army._march_goal = Vector2i(army.data.size.x - 10, anchor.y)
	army._march_goal_valid = true
	army._path_route.clear()
	for x: int in range(anchor.x + 1, army._march_goal.x + 1):
		army._path_route.append(Vector2i(x, anchor.y))
	for unit: int in range(100):
		var slot := 44 if unit == 0 else unit - 1
		if unit > 0 and slot >= 44:
			slot += 1
		var cell := anchor + Vector2i(4 - floori(float(slot) / 10.0), -4 + slot % 10)
		army.cells[unit] = cell
		army.desired_cells[unit] = cell
		army._formation_slot_cells[unit] = cell
		army._formation_offsets[unit] = cell - army._formation_anchor_cell
		army._cell_owners[cell] = unit

func _check_catch_up(long_wait: bool) -> void:
	_place_rectangular_fixture()
	for unit: int in ([99] if long_wait else [98, 99]):
		_army._cell_owners.erase(_army.cells[unit])
		_army.cells[unit] += Vector2i.LEFT * 3
		_army._cell_owners[_army.cells[unit]] = unit
	var source := _army.cells[99]
	var anchor := _army._formation_anchor_cell
	if long_wait:
		# Three walls and a temporary NPC leave no legal start for >5 seconds.
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			_terrain.flags[_terrain.index(source + direction)] = 0
		_npc.place(source + Vector2i.RIGHT, true)
		for frame_index: int in range(6 * 60):
			_army.advance_frame(1.0 / 60.0)
			if not _check(_army.cells[99] == source and _army._formation_anchor_cell == anchor and EdgeChecks._legal_state(_army, _terrain), "long wait moved army or blocked rear"):
				return
		if not _check(_army.blocked_time[99] >= 5.0, "long wait was not physically blocked"):
			return
		_npc.place(Vector2i(99, 99), true)
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			_terrain.flags[_terrain.index(source + direction)] = TerrainData.Flag.WALKABLE
		_army.formation_mode = TerrainArmy.FormationMode.COLUMN
		_army._formation_width = 1
	var ran := false
	var resumed := false
	var previous := _army.cells.duplicate()
	for frame_index: int in range(10 * 60):
		_army.advance_frame(1.0 / 60.0)
		if not _check(EdgeChecks._legal_state(_army, _terrain), "catch-up owner/claim invariant"):
			return
		for unit: int in range(100):
			if previous[unit] != _army.cells[unit] and not _check(_terrain.can_step(previous[unit], _army.cells[unit]), "catch-up illegal edge"):
				return
		previous = _army.cells.duplicate()
		if _army.locomotion_mode[99] == TerrainArmy.Locomotion.RUN:
			ran = true
			if not _check(is_equal_approx(_army.move_duration[99], TerrainArmy.RUN_DURATION), "RUN animation/duration mismatch"):
				return
		if _army.formation_batch_steps == 0 and _army._formation_step_direction == Vector2i.ZERO:
			if not _check(_army._formation_anchor_cell == anchor and _army.cells[0] == anchor, "front left the rear behind"):
				return
		if _army.formation_batch_steps >= 2:
			resumed = true
			break
	_check(ran and resumed, "rear did not RUN then resume collective WALK")
	print("CATCH_UP_METRICS long_wait=", long_wait, " ran=", ran, " resumed=", resumed, " batches=", _army.formation_batch_steps)

func _check_atomic_step() -> void:
	_place_rectangular_fixture()
	var sources := _army.cells.duplicate()
	var front := Vector2i(55, 50)
	_npc.place(front, true)
	if not _check(not _army._begin_formation_step(Vector2i.RIGHT) and _army._reserved_cells.is_empty() and _army.moving_count() == 0, "external blocker admitted a partial batch"):
		return
	_npc.place(Vector2i(99, 99), true)
	_army._reserved_cells[front] = 17
	if not _check(not _army._begin_formation_step(Vector2i.RIGHT) and _army._reserved_cells.size() == 1, "foreign claim overwritten"):
		return
	_army._reserved_cells.erase(front)
	if not _check(_army._begin_formation_step(Vector2i.RIGHT) and _army._reserved_cells.size() == 100 and _army.moving_count() == 100, "same-batch vacate not admitted atomically"):
		return
	for frame_index: int in range(8):
		_army.advance_frame(1.0 / 60.0)
	if not _check(_army.issue_command(TerrainArmy.Command.MOVE_TO_EDGE), "in-flight command change rejected"):
		return
	for unit: int in range(100):
		if not _check(_army.cells[unit] == sources[unit] and _army.moving_to[unit] == sources[unit] + Vector2i.RIGHT, "half batch rewound or committed"):
			return
	for frame_index: int in range(10):
		_army.advance_frame(1.0 / 60.0)
		if not _check(EdgeChecks._legal_state(_army, _terrain), "atomic handoff owner/claim invariant"):
			return
	for unit: int in range(100):
		if not _check(_army.cells[unit] == sources[unit] + Vector2i.RIGHT, "batch did not commit every physical edge"):
			return
	_check(_army.command == TerrainArmy.Command.MOVE_TO_EDGE and _army._pending_command < 0 and _army.formation_batch_steps == 1 and _army._reserved_cells.is_empty(), "latest command not active at clean batch boundary")

func _check_subset_step() -> void:
	# Two front ranks in a genuine 100-person body, deliberately without index 0.
	# Check the interface first so the old implementation fails cleanly.
	var supports_subset := false
	for method: Dictionary in _army.get_method_list():
		if method.name == "_begin_formation_step":
			supports_subset = method.args.size() == 2
	if not _check(supports_subset, "same-direction subset batch is not implemented"):
		return
	_place_rectangular_fixture()
	var sources := _army.cells.duplicate()
	var participants: Array[int] = []
	for y: int in [46, 47]:
		for x: int in [53, 54]:
			participants.append(_army._cell_owners[Vector2i(x, y)])
	_army.set("_formation_bend_active", true)
	for unit: int in participants:
		_army.desired_cells[unit] = sources[unit] + Vector2i.RIGHT
		_army._formation_slot_cells[unit] = _army.desired_cells[unit]
	var wrong_subset: Array[int] = [participants[0], participants[2]]
	if not _check(not _army.call("_begin_formation_step", Vector2i.RIGHT, wrong_subset) and _army._reserved_cells.is_empty(), "unrelated friendly occupant was admitted"):
		return
	var duplicates: Array[int] = [participants[0], participants[0]]
	if not _check(not _army.call("_begin_formation_step", Vector2i.RIGHT, duplicates) and _army._reserved_cells.is_empty(), "duplicate participant was admitted"):
		return
	_npc.place(Vector2i(55, 46), true)
	if not _check(not _army.call("_begin_formation_step", Vector2i.RIGHT, participants) and _army.moving_count() == 0, "subset ignored an external occupant"):
		return
	_npc.place(Vector2i(99, 99), true)
	_army._reserved_cells[Vector2i(55, 46)] = 17
	if not _check(not _army.call("_begin_formation_step", Vector2i.RIGHT, participants) and _army._reserved_cells.size() == 1, "subset overwrote a foreign claim"):
		return
	_army._reserved_cells.erase(Vector2i(55, 46))
	if not _check(_army.call("_begin_formation_step", Vector2i.RIGHT, participants) and _army.moving_count() == 4 and _army._reserved_cells.size() == 4, "2x2 subset did not start atomically"):
		return
	for frame: int in range(8):
		_army.advance_frame(1.0 / 60.0)
	var claims := _army._reserved_cells.duplicate()
	_army._prune_stale_reservations()
	if not _check(claims == _army._reserved_cells and _army.cells == sources and _army.movement_state[0] != TerrainArmy.UnitState.MOVING, "subset interpolation/prune changed owners or unrelated captain"):
		return
	_army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER)
	_army.issue_command(TerrainArmy.Command.MOVE_TO_EDGE)
	for frame: int in range(10):
		_army.advance_frame(1.0 / 60.0)
		if not _check(EdgeChecks._legal_state(_army, _terrain), "subset handoff owner/claim invariant"):
			return
	for unit: int in range(100):
		var expected: Vector2i = sources[unit] + (Vector2i.RIGHT if unit in participants else Vector2i.ZERO)
		if not _check(_army.cells[unit] == expected, "subset omitted, duplicated or moved unrelated unit %d" % unit):
			return
	_check(_army.command == TerrainArmy.Command.MOVE_TO_EDGE and _army._pending_command < 0 and _army._reserved_cells.is_empty(), "subset did not drain to latest command")
	print("G04_SUBSET_METRICS participants=4 captain_moved=false clean_latest_command=true")

func _check_parallel_subsets() -> void:
	if not _check(_army.has_method("_append_formation_batch"), "independent same-direction batches cannot yet overlap in time"):
		return
	_place_rectangular_fixture()
	var sources := _army.cells.duplicate()
	var right: Array[int] = []
	var left: Array[int] = []
	for y: int in [46, 47]:
		for x: int in [53, 54]:
			right.append(_army._cell_owners[Vector2i(x, y)])
	for y: int in [53, 54]:
		for x: int in [45, 46]:
			left.append(_army._cell_owners[Vector2i(x, y)])
	_army._formation_bend_active = true
	for unit: int in right:
		_army.desired_cells[unit] = sources[unit] + Vector2i.RIGHT
	for unit: int in left:
		_army.desired_cells[unit] = sources[unit] + Vector2i.LEFT
	if not _check(_army._begin_formation_step(Vector2i.RIGHT, right), "first independent batch did not start"):
		return
	var claims_before := _army._reserved_cells.duplicate()
	for unit: int in right:
		_army._complete_move(unit)
	if not _check(_army.cells == sources and _army._reserved_cells == claims_before, "ordinary completion committed one member of a batch"):
		return
	var cross_batch := int(_army._cell_owners[Vector2i(53, 48)])
	var old_target := _army.desired_cells[cross_batch]
	_army.desired_cells[cross_batch] = Vector2i(53, 47)
	var crossing: Array[int] = [cross_batch]
	if not _check(not _army._append_formation_batch(Vector2i.UP, crossing) and _army._reserved_cells == claims_before, "separate batch consumed another batch's in-flight source/claim"):
		return
	_army.desired_cells[cross_batch] = old_target
	if not _check(not _army.call("_append_formation_batch", Vector2i.RIGHT, right), "same members admitted to two batches"):
		return
	if not _check(_army.call("_append_formation_batch", Vector2i.LEFT, left) and _army.moving_count() == 8, "independent four-person batch did not start concurrently"):
		return
	for _frame: int in range(8):
		_army.advance_frame(1.0 / 60.0)
	if not _check(_army.cells == sources and _army._reserved_cells.size() == 8, "parallel interpolation changed committed cells or claims"):
		return
	_army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER)
	_army.issue_command(TerrainArmy.Command.MOVE_TO_EDGE)
	for _frame: int in range(10):
		_army.advance_frame(1.0 / 60.0)
		if not _check(EdgeChecks._legal_state(_army, _terrain), "parallel handoff owner/claim invariant"):
			return
	for unit: int in range(100):
		var direction := Vector2i.RIGHT if unit in right else (Vector2i.LEFT if unit in left else Vector2i.ZERO)
		if not _check(_army.cells[unit] == sources[unit] + direction, "parallel batch moved the wrong member or direction"):
			return
	_check(_army.command == TerrainArmy.Command.MOVE_TO_EDGE and _army._pending_command < 0 and _army._reserved_cells.is_empty(), "parallel batches did not drain before latest command")

func _check_future_receiving_binding() -> void:
	_place_rectangular_fixture()
	var layout: Array[Vector2i] = []
	for cell: Vector2i in _army.cells:
		layout.append(cell + Vector2i.RIGHT * 20)
	_army.desired_cells.assign(layout)
	_army._formation_slot_cells.assign(layout)
	_army._passage_group_start = 0
	_army._passage_group_end = 0
	_army._passage_descriptors = [{"rally_layout": layout}]
	_army._unit_passage.fill(0)
	_army._unit_passage_phase.fill(TerrainArmy.PassagePhase.APPROACH)
	_army._unit_passage_crossed.fill(0)
	_army._unit_passage_phase[2] = TerrainArmy.PassagePhase.IN_PASSAGE
	# One-time legal transit fixture: a third person owns the first future
	# receiving slot, another has an in-flight claim on the arriving unit's
	# old future slot. Neither physical transaction belongs to this rebinding.
	for unit: int in [98, 99]:
		_army._cell_owners.erase(_army.cells[unit])
	_army.cells[98] = layout[1]
	_army.cells[99] = layout[2] + Vector2i.RIGHT
	_army._cell_owners[_army.cells[98]] = 98
	_army._cell_owners[_army.cells[99]] = 99
	if not _check(_army.cells[99] != layout[1] and _army._schedule_push_unit(99, layout[2]), "future binding transit fixture"):
		return
	var sources := _army.cells.duplicate()
	var owners := _army._cell_owners.duplicate()
	var claims := _army._reserved_cells.duplicate()
	var destinations := _army.moving_to.duplicate()
	var durations := _army.move_duration.duplicate()
	var revision := _army._passage_binding_revision
	_army._bind_receiving_arrival(2)
	if not _check(_army.desired_cells[2] == layout[1] and _army.desired_cells[1] == layout[2] and _army._passage_binding_revision == revision + 1, "occupied transit slot incorrectly postponed to last arrival"):
		return
	_check(_army.cells == sources and _army._cell_owners == owners and _army._reserved_cells == claims and _army.moving_to == destinations and _army.move_duration == durations and EdgeChecks._legal_state(_army, _terrain), "future receiving rebinding changed an unrelated physical owner or move")

func _check_receiving_handoff(edge_to_follow: bool) -> void:
	var old_command := TerrainArmy.Command.MOVE_TO_EDGE if edge_to_follow else TerrainArmy.Command.FOLLOW_PLAYER
	var next_command := TerrainArmy.Command.FOLLOW_PLAYER if edge_to_follow else TerrainArmy.Command.MOVE_TO_EDGE
	if not _check(_player.place(Vector2i(36, 15), true) and _army.issue_command(old_command), "receiving handoff command"):
		return
	var requested := false
	var old_epoch := -1
	var active_destinations := {}
	var committed := {}
	var clearing: Array[int] = []
	var previous := _army.cells.duplicate()
	for frame: int in range(100 * 60):
		_army.advance_frame(1.0 / 60.0)
		if not _check(EdgeChecks._legal_state(_army, _terrain), "receiving handoff owner/claim invariant"):
			return
		for unit: int in range(100):
			if previous[unit] != _army.cells[unit] and not _check(_terrain.can_step(previous[unit], _army.cells[unit]), "receiving handoff illegal edge"):
				return
			if active_destinations.has(unit) and _army.cells[unit] == active_destinations[unit]:
				committed[unit] = true
		previous = _army.cells.duplicate()
		if not requested and _army._passage_crossings.size() == 1 and _army._passage_crossings[0] >= 20 and _army._unit_passage_phase.count(TerrainArmy.PassagePhase.IN_PASSAGE) > 0:
			requested = true
			old_epoch = _army._command_epoch
			var progress := _army.move_progress.duplicate()
			for unit: int in range(100):
				if _army.movement_state[unit] in [TerrainArmy.UnitState.MOVING, TerrainArmy.UnitState.SWAPPING]:
					active_destinations[unit] = _army.moving_to[unit]
				if _army._unit_passage_phase[unit] == TerrainArmy.PassagePhase.IN_PASSAGE or (_army._unit_passage_phase[unit] == TerrainArmy.PassagePhase.EXIT_CLEAR and _army._unit_passage_exit_clear[unit] == 0):
					clearing.append(unit)
			_army.issue_command(next_command)
			_army.issue_command(old_command)
			_army.issue_command(next_command)
			if not _check(_army._command_epoch == old_epoch and not active_destinations.is_empty(), "receiving handoff skipped drain"):
				return
			for unit: int in active_destinations:
				if not _check(_army.cells[unit] == previous[unit] and _army.moving_to[unit] == active_destinations[unit] and _army.move_progress[unit] == progress[unit], "receiving handoff rewound an active move"):
					return
		if requested and _army._command_epoch != old_epoch:
			if not _check(_army.command == next_command and _army._pending_command < 0 and committed.size() == active_destinations.size() and _army._reserved_cells.is_empty() and _army._pending_pushes.is_empty() and _army._push_lock.count(1) == 0, "receiving handoff lost original commits, latest request or clean claims"):
				return
			for unit: int in clearing:
				if not _check(_army.cells[unit] != Vector2i(20, 15) and _army.cells[unit] != Vector2i(21, 15), "latest command activated before old core/egress cleared"):
					return
			print("G10_RECEIVING_METRICS edge_to_follow=", edge_to_follow, " input=", _army.input_seconds, " active_commits=", committed.size(), " cleared_old_core=", clearing.size(), " clean_latest_command=true")
			return
	_check(false, "receiving handoff failed to activate latest command within fixed bound")

func _check_edge_front() -> void:
	if not _check(_army.issue_command(TerrainArmy.Command.MOVE_TO_EDGE), "edge command"):
		return
	for frame_index: int in range(40 * 60):
		_army.advance_frame(1.0 / 60.0)
		if not _check(EdgeChecks._legal_state(_army, _terrain), "edge owner/claim invariant"):
			return
		if _army.is_formation_complete():
			break
	print("G09_METRICS complete=", _army.is_formation_complete(), " time=", _army.input_seconds, " batches=", _army.formation_batch_steps, " anchor=", _army._formation_anchor_cell, " captain=", _army.cells[0], " goal=", _army._march_goal, " status=", _army.command_status, " settled=", _army.formation_count(), " desired=", _army.desired_cells, " cells=", _army.cells)
	_check(_army.is_formation_complete() and _army.formation_count() == 99 and not _army.captain_at_boundary() and _army.cells.has(_army._march_goal) and _army._edge_distance(_army._march_goal) == 0, "EDGE must finish with the front at boundary and captain inside")

func _check_turn(reverse: bool) -> void:
	if not _check(_player.place(Vector2i(94, 50), true) and _army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER), "turn initial command"):
		return
	var changed := false
	var changed_epoch := -1
	var new_batches := 0
	var observed_batches := 0
	var previous := _army.cells.duplicate()
	var current_goal := TerrainArmy.INVALID_CELL
	var expected_heading := Vector2i.LEFT if reverse else Vector2i.UP
	for frame: int in range(100 * 60):
		_army.advance_frame(1.0 / 60.0)
		if not _check(EdgeChecks._legal_state(_army, _terrain), "turn owner/claim invariant"):
			return
		for unit: int in range(100):
			if previous[unit] != _army.cells[unit] and not _check(_terrain.can_step(previous[unit], _army.cells[unit]), "turn illegal committed edge"):
				return
		previous = _army.cells.duplicate()
		if not changed and _army.formation_batch_steps >= 5 and _army._formation_step_direction != Vector2i.ZERO:
			var target := Vector2i(5, _army.cells[0].y) if reverse else Vector2i(_army.cells[0].x, 8)
			if not _check(_player.place(target, true) and _army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER), "turn moving PLAYER command"):
				return
			changed = true
			changed_epoch = _army._command_request_epoch
			observed_batches = _army.formation_batch_steps
		if changed and _army._command_epoch == changed_epoch and not _army._command_goal_pending and not _army._passage_plan_pending:
			if current_goal == TerrainArmy.INVALID_CELL:
				current_goal = _army._march_goal
			if not _check(current_goal == _army._march_goal, "stationary PLAYER made command goal drift"):
				return
			if _army.formation_batch_steps > observed_batches:
				new_batches += 1
				observed_batches = _army.formation_batch_steps
				var guards := 0
				var rear := 0
				for unit: int in range(1, 100):
					var offset := _army.cells[unit] - _army.cells[0]
					guards += int(offset.x * expected_heading.x + offset.y * expected_heading.y > 0)
					rear += int(offset.x * expected_heading.x + offset.y * expected_heading.y < 0)
				if not _check(guards >= 20 and rear >= 20, "turn captain resumed without front/rear ranks"):
					return
			if _army.is_formation_complete():
				break
	if not _check(changed and new_batches >= 10 and _army.is_formation_complete(), "turn failed to reform and finish changed=%s batches=%d captain=%s final_captain=%s goal=%s status=%s cells=%s final_slots=%s" % [changed, new_batches, _army.cells[0], _army._passage_final_captain_slot, _army._march_goal, _army.command_status, _army.cells, _army._passage_final_slots]):
		return
	var settled := _army.cells.duplicate()
	for frame: int in range(5 * 60):
		_army.advance_frame(1.0 / 60.0)
		if not _check(_army.cells == settled and _army.is_formation_complete(), "turn final stability"):
			return
	print("G08_METRICS reverse=", reverse, " new_batches=", new_batches, " captain=", _army.cells[0], " front=", _army._march_goal, " input=", _army.input_seconds, " stable=5")

func _check_single_gate() -> void:
	if not _check(_player.place(Vector2i(36, 15), true) and _army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER), "single gate command"):
		return
	var previous := _army.cells.duplicate()
	var order := []
	var exited := {}
	var rear_runners := {}
	for frame: int in range(180 * 60):
		_army.advance_frame(1.0 / 60.0)
		if not _check(EdgeChecks._legal_state(_army, _terrain), "single gate owner/claim invariant"):
			return
		for unit: int in range(100):
			var current := _army.cells[unit]
			if previous[unit] != current and not _check(_terrain.can_step(previous[unit], current), "single gate illegal edge"):
				return
			if previous[unit] == Vector2i(19, 15) and current == Vector2i(20, 15):
				if not _check(not order.has(unit), "duplicate physical crossing"):
					return
				order.append(unit)
				if unit == 0 and not _check(order.size() >= 21 and order.size() <= 71, "captain used leading/scout passage order: %s" % [order]):
					return
			if previous[unit] == Vector2i(21, 15) and current != previous[unit]:
				exited[unit] = true
			if exited.has(unit) and _army.locomotion_mode[unit] == TerrainArmy.Locomotion.RUN and exited.size() < 100:
				rear_runners[unit] = true
		previous = _army.cells.duplicate()
		if _army.is_formation_complete():
			break
	print("G05_METRICS t=", _army.input_seconds, " crossing_order=", order, " exited=", exited.size(), " rear_runners=", rear_runners.keys(), " captain=", _army.cells[0], " slots=", _army.formation_count(), " status=", _army.command_status)
	_check(order.size() == 100 and exited.size() == 100 and _army.is_formation_complete() and _army.formation_count() == 99 and not rear_runners.is_empty(), "single gate did not settle all 100 / run after clearance")

func _check_medium_corridor() -> void:
	if not _check(_player.place(Vector2i(36, 15), true) and _army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER), "five-wide command"):
		return
	var previous := _army.cells.duplicate()
	var narrow_batches := 0
	var old_batches := 0
	for frame: int in range(120 * 60):
		_army.advance_frame(1.0 / 60.0)
		if not _check(EdgeChecks._legal_state(_army, _terrain), "five-wide owner/claim invariant"):
			return
		for unit: int in range(100):
			if previous[unit] != _army.cells[unit] and not _check(_terrain.can_step(previous[unit], _army.cells[unit]), "five-wide illegal committed edge"):
				return
		previous = _army.cells.duplicate()
		if _army.formation_batch_steps > old_batches:
			old_batches = _army.formation_batch_steps
			narrow_batches += int(_army.formation_cohesion.width == 5)
		if _army.is_formation_complete():
			break
	if not _check(_army.is_formation_complete() and _army.formation_count() == 99 and narrow_batches >= 3 and _army.formation_cohesion.width == 10, "five-wide corridor did not shrink, advance and expand"):
		print("G07_MEDIUM_DIAGNOSTIC status=", _army.command_status, " anchor=", _army._formation_anchor_cell, " captain=", _army.cells[0], " width=", _army.formation_cohesion, " narrow_batches=", narrow_batches, " desired=", _army.desired_cells, " cells=", _army.cells)
		return
	var settled := _army.cells.duplicate()
	for frame: int in range(5 * 60):
		_army.advance_frame(1.0 / 60.0)
		if not _check(_army.cells == settled and _army.is_formation_complete(), "five-wide final stability"):
			return
	print("G07_MEDIUM_METRICS input=", _army.input_seconds, " narrow_batches=", narrow_batches, " final_width=", _army.formation_cohesion.width, " stable=5")

func _check_two_gate_rally() -> void:
	# Independent geometry proof: x=23..32, y=10..19 is a legal connected
	# 100-cell pocket between the two walls, clear of both mouths and exits.
	for y: int in range(10, 20):
		for x: int in range(23, 33):
			if not _check(_terrain.is_walkable(Vector2i(x, y)), "middle platform fixture capacity"):
				return
	if not _check(_player.place(Vector2i(66, 15), true) and _army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER), "two gate command"):
		return
	var previous := _army.cells.duplicate()
	var crossed := [{}, {}]
	var cleared := [{}, {}]
	var rally_observed := false
	var collective_after_rally := false
	var first_rally_batches := -1
	var last_progress := 0
	var no_progress := 0.0
	# Predeclared V6 budget: L <= 55, K=2 => 16.5+118.8+60, rounded to 200 s.
	for frame: int in range(200 * 60):
		_army.advance_frame(1.0 / 60.0)
		if _army.completed_steps() > last_progress or _army._command_goal_pending or _army._passage_plan_pending or _army._formation_target_pending:
			no_progress = 0.0
		else:
			no_progress += 1.0 / 60.0
		last_progress = _army.completed_steps()
		if no_progress > 5.0:
			var pending := []
			for unit: int in range(100):
				if _army.cells[unit] != _army.desired_cells[unit]:
					pending.append([unit, _army.cells[unit], _army.desired_cells[unit], _army.movement_state[unit], _army._push_lock[unit]])
			print("G06_STALL t=", _army.input_seconds, " pending=", pending, " captain=", _army.cells[0], " target=", _army.desired_cells[0], " claims=", _army._reserved_cells, " transactions=", _army._pending_pushes)
			_check(false, "two gate five-second physical progress stall")
			return
		if not _check(EdgeChecks._legal_state(_army, _terrain), "two gate owner/claim invariant"):
			return
		for unit: int in range(100):
			var current := _army.cells[unit]
			if previous[unit] != current and not _check(_terrain.can_step(previous[unit], current), "two gate illegal edge"):
				return
			for gate: int in range(2):
				var mouth := Vector2i(19 if gate == 0 else 44, 15)
				if previous[unit] == mouth and current == mouth + Vector2i.RIGHT:
					if crossed[gate].is_empty():
						print("G06_GATE_START gate=", gate, " input=", _army.input_seconds)
					if gate == 1 and not _check(cleared[0].size() == 100 and rally_observed and collective_after_rally, "head entered second gate before full-team middle rally / collective advance"):
						return
					crossed[gate][unit] = true
				if previous[unit] == mouth + Vector2i.RIGHT * 2 and current != previous[unit] and current != mouth + Vector2i.RIGHT:
					cleared[gate][unit] = true
		previous = _army.cells.duplicate()
		if cleared[0].size() == 100 and crossed[1].is_empty():
			var bounds := Rect2i(_army.cells[0], Vector2i.ONE)
			for cell: Vector2i in _army.cells:
				bounds = bounds.merge(Rect2i(cell, Vector2i.ONE))
			if bounds.size.x == 10 and bounds.size.y == 10:
				rally_observed = true
				if first_rally_batches < 0:
					first_rally_batches = _army.formation_batch_steps
			if rally_observed and _army.formation_batch_steps > first_rally_batches:
				collective_after_rally = true
		if _army.is_formation_complete():
			break
		if "--trace" in OS.get_cmdline_user_args() and frame % 600 == 0:
			var pending := []
			for unit: int in range(100):
				if _army.cells[unit] != _army.desired_cells[unit]:
					pending.append([unit, _army.cells[unit], _army.desired_cells[unit], _army._unit_passage_phase[unit]])
			print("G06_TRACE t=", _army.input_seconds, " group=", [_army._passage_group_start, _army._passage_group_end], " macro=", _army._formation_march_active, " pending=", pending)
	print("G06_METRICS t=", _army.input_seconds, " crossed=", [crossed[0].size(), crossed[1].size()], " cleared=", [cleared[0].size(), cleared[1].size()], " rally=", rally_observed, " collective=", collective_after_rally, " status=", _army.command_status)
	if not _army.is_formation_complete():
		var pending := []
		for unit: int in range(100):
			if _army.cells[unit] != _army.desired_cells[unit]:
				pending.append([unit, _army.cells[unit], _army.desired_cells[unit], _army._unit_passage_phase[unit]])
		print("G06_DEADLINE pending=", pending, " claims=", _army._reserved_cells, " pushes=", _army._pending_pushes)
	_check(_army.is_formation_complete() and cleared[1].size() == 100 and rally_observed and collective_after_rally, "two gate 200-second declared deadline / final completeness")

static func configure_bend_snapshot(army: TerrainArmy, fourth: bool = false, replay: Dictionary = {}) -> Array[Vector2i]:
	# One initial, legal physical snapshot from the D01 stalled turn. No cells
	# or targets are injected after this fixture publication.
	var snapshot: Array[Vector2i] = []
	var coordinates := [32,46,28,47,31,48,35,40,30,44,32,50,31,43,32,43,31,45,35,36,35,39,34,46,35,42,31,53,32,53,29,49,29,46,36,35,34,44,37,32,34,38,33,42,32,44,35,35,26,49,33,43,30,51,31,51,33,48,31,47,36,37,35,43,31,46,38,31,33,40,36,36,39,32,27,48,33,41,31,55,32,51,29,47,29,50,30,53,32,54,31,50,32,52,33,45,31,54,36,32,32,42,32,56,32,55,31,44,39,31,27,49,32,48,34,45,28,50,29,48,30,47,32,47,29,45,27,50,35,41,38,33,37,34,34,40,36,33,37,35,32,45,37,33,30,50,34,43,33,44,33,46,28,48,30,48,31,49,28,51,36,38,29,51,34,42,28,49,30,45,38,32,34,41,37,36,35,38,35,37,36,34,29,52,34,39,34,47,33,47,31,52,32,49,30,46,30,49,30,52]
	if fourth:
		coordinates = [36,25,34,25,39,23,31,30,31,26,52,23,37,22,33,28,41,25,48,23,30,30,35,24,34,27,56,24,53,24,55,24,35,29,35,26,33,23,35,28,35,23,34,26,31,29,38,22,36,26,50,23,42,24,36,21,34,22,41,24,32,25,31,28,32,29,30,29,30,28,35,30,33,29,43,24,37,24,34,28,44,23,40,24,35,25,33,27,38,24,38,20,44,24,39,24,37,29,36,29,31,27,32,30,35,27,29,29,36,27,37,23,37,21,34,23,36,24,39,26,38,27,38,21,34,29,34,24,30,27,37,25,37,26,32,27,33,26,38,23,36,22,35,22,38,28,39,20,35,21,32,26,38,26,42,23,36,23,39,25,36,30,38,25,36,28,39,21,29,30,37,28,41,21,57,24,37,27,46,23,41,22,33,25,40,25,33,24,34,30,39,22,41,23,32,28,40,23,33,30]
	var group := int(replay.get("group", 3 if fourth else 2))
	for position: int in range(0, coordinates.size(), 2):
		snapshot.append(Vector2i(coordinates[position], coordinates[position + 1]))
	if not replay.is_empty():
		snapshot.assign(replay.cells)
	army._reserved_cells.clear()
	army._pending_pushes.clear()
	army._push_lock.fill(0)
	army._cell_owners.clear()
	army._formation_step_direction = Vector2i.ZERO
	army._formation_step_units.clear()
	army._formation_step_batches.clear()
	army._formation_bend_preview.clear()
	army._formation_bend_followup.clear()
	army._formation_bend_order.clear()
	army._formation_bend_active = false
	army._formation_bend_field.clear()
	army._formation_bend_lateral.clear()
	army._formation_bend_span = int(replay.get("span", 0))
	army._formation_bend_field = replay.get("field", {}).duplicate()
	army._formation_bend_lateral = replay.get("lateral", {}).duplicate()
	army._formation_march_active = true
	army._formation_has_bottleneck = false
	army.formation_mode = TerrainArmy.FormationMode.OPEN
	army._formation_anchor_cell = snapshot[0]
	army._formation_heading = replay.get("heading", Vector2i.LEFT if fourth else Vector2i.UP)
	army._formation_guide_group = group
	army._path_route.clear()
	army._path_route_cursor = 0
	army._passage_group_start = group
	army._passage_group_end = group
	army._unit_completed_exits.fill(group)
	army._unit_passage.fill(group)
	army._unit_passage_phase.fill(TerrainArmy.PassagePhase.APPROACH)
	army._unit_passage_crossed.fill(0)
	army._unit_passage_exit_clear.fill(0)
	army._unit_passage_cursor.fill(0)
	for unit: int in range(100):
		army.cells[unit] = snapshot[unit]
		army.desired_cells[unit] = snapshot[unit]
		army._formation_slot_cells[unit] = snapshot[unit]
		army._formation_offsets[unit] = snapshot[unit] - snapshot[0]
		army._cell_owners[snapshot[unit]] = unit
		army.moving_to[unit] = TerrainArmy.INVALID_CELL
		army.movement_state[unit] = TerrainArmy.UnitState.IDLE
		army.move_progress[unit] = 0.0
	return snapshot

func _check_bend_counterexample(fourth: bool = false) -> void:
	if not _check(_army.issue_command(TerrainArmy.Command.MOVE_TO_EDGE), "bend fixture command"):
		return
	for _frame: int in range(20 * 60):
		_army.advance_frame(1.0 / 60.0)
		if _army.passage_active() and not _army._passage_plan_pending and not _army._formation_target_pending:
			break
	if not _check(_army._passage_descriptors.size() == 5, "bend fixture requires the unchanged five-gate terrain"):
		return
	var replay := {}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--snapshot="):
			var snapshot_file := FileAccess.open(argument.trim_prefix("--snapshot="), FileAccess.READ)
			if not _check(snapshot_file != null, "cannot read exact bend replay snapshot"):
				return
			replay = snapshot_file.get_var()
			snapshot_file.close()
			print("G08_BEND_REPLAY_SOURCE=", replay.source, " input_seconds=", replay.input_seconds)
	var snapshot := configure_bend_snapshot(_army, fourth, replay)
	if OS.get_cmdline_user_args().has("--inspect-bend"):
		var debug_cells := []
		var debug_nodes := []
		for cell: Vector2i in _army.cells:
			debug_cells.append([cell.x, cell.y])
		for cell: Vector2i in _army._formation_bend_field:
			var mask := 0
			for direction_index: int in range(4):
				var next: Vector2i = cell + TerrainData.DIRECTIONS[direction_index]
				if _army._formation_bend_field.has(next) and _terrain.can_step(cell, next) and not _army._passage_cell_is_protected(next) and not _army._is_external_cell(next):
					mask |= 1 << direction_index
			debug_nodes.append([cell.x, cell.y, _army._formation_bend_field[cell], _army._formation_bend_lateral[cell], mask])
		print("BEND_DIAGNOSTIC_JSON=", JSON.stringify({"cells": debug_cells, "nodes": debug_nodes, "span": _army._formation_bend_span}))
		return
	var before := _army.completed_steps()
	var bend_input_start := _army.input_seconds
	var previous := snapshot.duplicate()
	var captain_commits := 0
	var descriptor := _army._passage_descriptor(_army._passage_group_start)
	var mouth: Vector2i = descriptor.entry
	var core: Vector2i = descriptor.corridor[1]
	var guard_field := EdgeChecks._flood(_terrain, mouth, [mouth, core])
	var min_guards := Vector2i(99, 99)
	var fixed_span := -1
	var long_bend := OS.get_cmdline_user_args().has("--long-bend")
	var bend_structure_start := _army.structure_search_expansions
	var bend_planning_frames := 0
	var bend_batches_start := _army.formation_bend_steps
	for _frame: int in range((60 if long_bend else 10) * 60):
		var structure_before := _army.structure_search_expansions
		_army.advance_frame(1.0 / 60.0)
		bend_planning_frames += int(_army._formation_target_pending)
		# This fixture verifies the bend up to the next actual passage mouth.
		# Once local admission begins, its physical queue has a different span
		# contract, covered by the full-route and passage tests.
		if not _army._formation_march_active:
			break
		if not _check(EdgeChecks._legal_state(_army, _terrain), "bend owner/claim invariant"):
			return
		if not _check(_army.structure_search_expansions - structure_before <= 256, "bend exceeded shared structure budget"):
			return
		var guards := bend_guard_counts(_army, guard_field)
		min_guards = min_guards.min(guards)
		if not _check(guards.x >= 20 and guards.y >= 20, "bend captain lacks actual front/rear guards under independent legal-distance oracle"):
			return
		if previous != _army.cells and not _check(bend_connected_count(_army, _terrain) == 100, "bend left a detached soldier beyond one legal empty-cell gap"):
			return
		if _army._formation_bend_span > 0:
			if fixed_span < 0:
				fixed_span = _army._formation_bend_span
			if not _check(_army._formation_bend_span == fixed_span, "bend span ratcheted wider during a platform"):
				return
			var front_depth := 1 << 29
			var rear_depth := 0
			for cell: Vector2i in _army.cells:
				front_depth = mini(front_depth, int(guard_field[cell]))
				rear_depth = maxi(rear_depth, int(guard_field[cell]))
			if not _check(rear_depth - front_depth <= fixed_span, "bend legal tail span exceeds its fixed platform limit t=%.3f depth=%s span=%d commits=%d" % [_army.input_seconds - bend_input_start, Vector2i(front_depth, rear_depth), fixed_span, _army.completed_steps() - before]):
				return
		for unit: int in range(100):
			if previous[unit] != _army.cells[unit] and not _check(_terrain.can_step(previous[unit], _army.cells[unit]), "bend illegal physical edge"):
				return
		captain_commits += int(previous[0] != _army.cells[0])
		previous = _army.cells.duplicate()
		if "--trace" in OS.get_cmdline_user_args() and _frame % 60 == 0:
			var distance_sum := 0
			for cell: Vector2i in _army.cells:
				distance_sum += int(_army._passage_march_field().get(cell, -1))
			print("G08_BEND_TRACE frame=", _frame, " captain=", _army.cells[0], " commits=", _army.completed_steps() - before, " potential=", distance_sum, " active=", _army._formation_step_units, " direction=", _army._formation_step_direction)
		if not _army._passage_failure_reason.is_empty():
			print("G08_BEND_FAILURE ", _army._passage_failure_reason)
			for cell: Vector2i in [Vector2i(32, 42), Vector2i(33, 42), Vector2i(34, 42), Vector2i(35, 42)]:
				var edges := []
				for direction: Vector2i in TerrainData.DIRECTIONS:
					var next := cell + direction
					edges.append([next, _terrain.can_step(cell, next), _terrain.height_levels[_terrain.index(next)], _army._passage_cell_is_protected(next), _army._passage_march_field().get(next, -1), _army._cell_owners.get(next, -1)])
				print("G08_BEND_CELL ", cell, " height=", _terrain.height_levels[_terrain.index(cell)], " field=", _army._passage_march_field().get(cell, -1), " edges=", edges)
			break
	# Count the actual legal corner edges, not Euclidean displacement across it.
	_check(_army.completed_steps() - before >= 100 and captain_commits >= 3, "bend snapshot did not make protected collective progress in ten seconds")
	if long_bend:
		_check(not _army._formation_march_active, "long bend did not reach the next local passage within sixty seconds")
	print("G08_BEND_METRICS commits=", _army.completed_steps() - before, " captain_edges=", captain_commits, " captain=", _army.cells[0], " source=", snapshot[0], " independent_min_front_rear=", min_guards, " fixed_span=", fixed_span, " planning_frames=", bend_planning_frames, " structure=", _army.structure_search_expansions - bend_structure_start, " batches=", _army.formation_bend_steps - bend_batches_start, " input_seconds=", _army.input_seconds - bend_input_start)

static func bend_connected_count(army: TerrainArmy, terrain: TerrainData) -> int:
	# Independent physical oracle: adjacent members or one legal empty cell
	# between them. A terrain-wide distance field cannot prove body cohesion.
	var occupied := {}
	for cell: Vector2i in army.cells:
		occupied[cell] = true
	var seen := {army.cells[0]: true}
	var queue: Array[Vector2i] = [army.cells[0]]
	var head := 0
	while head < queue.size():
		var source := queue[head]
		head += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var middle := source + direction
			if not terrain.can_step(source, middle):
				continue
			var neighbors: Array[Vector2i] = [middle]
			for second: Vector2i in TerrainData.DIRECTIONS:
				if terrain.can_step(middle, middle + second):
					neighbors.append(middle + second)
			for next: Vector2i in neighbors:
				if occupied.has(next) and not seen.has(next):
					seen[next] = true
					queue.append(next)
	return seen.size()

static func bend_guard_counts(army: TerrainArmy, field: Dictionary) -> Vector2i:
	var result := Vector2i.ZERO
	if not field.has(army.cells[0]):
		return result
	for unit: int in range(1, 100):
		if not field.has(army.cells[unit]):
			return Vector2i.ZERO
		result.x += int(int(field[army.cells[unit]]) < int(field[army.cells[0]]))
		result.y += int(int(field[army.cells[unit]]) > int(field[army.cells[0]]))
	return result

func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("FORMATION_V6_FAIL " + message)
	return condition

func _finish(selected: String) -> void:
	if _army != null:
		_army.clear()
		_army.free()
	if _npc != null:
		_npc.free()
	if _player != null:
		_player.free()
	if not _failed:
		print("FORMATION_V6_PASS case=", selected)
	quit(1 if _failed else 0)
