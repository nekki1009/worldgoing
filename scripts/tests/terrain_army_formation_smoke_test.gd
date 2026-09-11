extends SceneTree

const EdgeChecks = preload("res://scripts/tests/terrain_army_default_edge_test.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(100, 100))
	for index: int in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.surface_types[index] = TerrainData.Surface.GRASS
		data.flags[index] = TerrainData.Flag.WALKABLE
	var player := TerrainTestCharacter.new()
	player.data = data
	if not _check(player.place(Vector2i(50, 50), true), "FIXTURE_INVALID player"):
		return
	var npc := TerrainTestNPC.new()
	npc.data = data
	if not _check(npc.place(Vector2i(51, 50), true), "FIXTURE_INVALID npc"):
		return
	var army := TerrainArmy.new()
	if not _check(army.deploy(data, player, npc), army.command_status):
		return
	print("F01 START source=", FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"), " fingerprint=", data.fingerprint(), " INITIAL_CELLS=", army.cells)
	if not _check(army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER) and player.place(Vector2i(80, 50), true) and army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER), "FIXTURE_INVALID follow sequence"):
		return
	var saw_running := false
	var previous_anchor: Vector2i = army._formation_anchor_cell
	var previous_heading: Vector2i = army._formation_heading
	var previous_slots := army.desired_cells.duplicate()
	var traced_cell := army.cells[24]
	var previous := army.cells.duplicate()
	var translations := 0
	var completion := -1.0
	var hz := 30 if "--30hz" in OS.get_cmdline_user_args() else 60
	var alternating := "--alternating" in OS.get_cmdline_user_args()
	var v6_budget := "--v6-budget" in OS.get_cmdline_user_args()
	var initial_anchor := army._formation_anchor_cell
	var deadline := 20.0
	var budget_frozen := false
	var _step := 0
	while army.input_seconds < deadline - 0.00001:
		var delta := (1.0 / 120.0 if _step % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz)
		army.advance_frame(delta)
		if v6_budget and not budget_frozen and army.moving_count() > 0:
			# Use the predeclared V6 K=0 budget, frozen at first physical motion.
			# Later replanning cannot extend it; the default still tests V5's 20s.
			var route := EdgeChecks._independent_route(data, initial_anchor, army._march_goal)
			if not _check(not route.is_empty(), "independent route missing for timing budget"):
				return
			deadline = 0.30 * float(route.size() - 1) + 20.0 + float(army.structure_search_expansions) / (256.0 * float(hz))
			budget_frozen = true
			print("F01_V6_BUDGET L=", route.size() - 1, " K=0 structural_work=", army.structure_search_expansions, " deadline=", deadline, " legacy_deadline=20")
		if not _frame_valid(army, data, previous):
			return
		previous = army.cells.duplicate()
		if "--trace-unit=24" in OS.get_cmdline_user_args() and army.cells[24] != traced_cell:
			print("F01 TRACE24 t=%.2f %s -> %s goal=%s route=%s" % [army.input_seconds, traced_cell, army.cells[24], army.desired_cells[24], army._follower_routes.get(24)])
			traced_cell = army.cells[24]
		if army._formation_anchor_cell != previous_anchor and army._formation_heading == previous_heading and army.cells[0] != army.desired_cells[0]:
			var translation: Vector2i = army._formation_anchor_cell - previous_anchor
			var changed_offsets := 0
			for unit: int in range(1, 100):
				changed_offsets += int(army.desired_cells[unit] - previous_slots[unit] != translation)
			print("OPEN_TRANSLATION anchor=%s delta=%s changed_offsets=%d" % [army._formation_anchor_cell, translation, changed_offsets])
			if not _check(changed_offsets == 0, "OPEN translation changed unit offsets"):
				return
			translations += 1
		previous_anchor = army._formation_anchor_cell
		previous_heading = army._formation_heading
		previous_slots = army.desired_cells.duplicate()
		saw_running = saw_running or army.running_count() > 0
		if completion < 0 and army.is_formation_complete():
			completion = army.input_seconds
		if _step % hz == hz - 1:
			print("F01 t=%.1f assembled=%d moving=%d captain=%s repair=%.1f" % [army.input_seconds, army.formation_count(), army.moving_count(), army.cells[0], army._formation_rebind_elapsed])
			var occupied_slots := 0
			for slot: Vector2i in army._formation_slot_cells.slice(1):
				occupied_slots += int(army._cell_owners.has(slot))
			print("SLOT_OCCUPANCY %d pending=%d full=%s" % [occupied_slots, army._pending_pushes.size(), army._open_slot_set_is_occupied()])
		_step += 1
		if v6_budget and completion >= 0.0:
			break
	if not _check(army.formation_mode == TerrainArmy.FormationMode.OPEN and army.formation_width() == TerrainArmy.FORMATION_COLUMNS, "Open flat follow lost OPEN width"):
		return
	if not _check(_unique(army.cells) and army.completed_steps() > 0 and translations > 0, "Open flat follow lost uniqueness / progress / translation"):
		return
	print("FORMATION SMOKE: mode=%s width=%d moving=%d running=%d saw_running=%s steps=%d assembled=%d captain=%s goal=%s status=%s" % [army.formation_mode_name(), army.formation_width(), army.moving_count(), army.running_count(), saw_running, army.completed_steps(), army.formation_count(), army.cells[0], army.desired_cells[0], army.command_status])
	if army.formation_count() != 99 or not army.is_formation_complete() or completion < 0 or completion > deadline + 0.0001:
		print("F01 PUSH requests=%d queued=%d expansions=%d" % [army.push_search_requests, army.push_search_queued, army.push_search_expansions])
		for index: int in range(1, 100):
			if army.cells[index] != army.desired_cells[index]:
				print("UNSETTLED %d cell=%s goal=%s state=%d" % [index, army.cells[index], army.desired_cells[index], army.movement_state[index]])
		push_error("Open flat follow did not reform all 99 within declared %.3f seconds" % deadline)
		army.clear()
		army.free()
		npc.free()
		player.free()
		quit(1)
		return
	var settled := army.cells.duplicate()
	var bindings := army.desired_cells.duplicate()
	for _frame: int in range(5 * hz):
		var delta := (1.0 / 120.0 if _frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz)
		army.advance_frame(delta)
		if not _frame_valid(army, data, settled) or not _check(army.cells == settled and army.desired_cells == bindings and army.is_formation_complete(), "Open flat follow did not remain stable"):
			return
	if not _check(saw_running, "Far follow never selected running locomotion"):
		return
	if not _check(army._reserved_cells.is_empty() and army._pending_pushes.is_empty() and army.moving_count() == 0, "residual transaction/movement"):
		return
	print("ARMY_FORMATION_F01_PASS complete_seconds=", completion, " deadline=", deadline, " v6_budget=", v6_budget, " legacy_20s_met=", completion <= 20.0001, " stable=5 settled=99 translations=", translations, " hz=", hz, " jitter=", alternating, " input=", army.input_seconds, " sim=", army.simulated_seconds, " dropped=", army.dropped_seconds, " structure=", army.max_frame_structure_expansions, " local=", army.max_frame_local_expansions, " push=", army.max_frame_push_expansions)
	army.free()
	npc.free()
	player.free()
	quit(0)

func _unique(cells: Array[Vector2i]) -> bool:
	var seen := {}
	for cell: Vector2i in cells:
		if seen.has(cell):
			return false
		seen[cell] = true
	return true

func _frame_valid(army: TerrainArmy, terrain: TerrainData, previous: Array[Vector2i]) -> bool:
	if not _check(EdgeChecks._legal_state(army, terrain) and army.max_frame_structure_expansions <= 256 and army.max_frame_local_expansions <= 8192 and army.max_frame_push_expansions <= 1024 and army.dropped_seconds == 0.0, "ownership / search-budget / dropped-time invariant"):
		return false
	for unit: int in range(100):
		if previous[unit] != army.cells[unit] and not _check(terrain.can_step(previous[unit], army.cells[unit]), "illegal committed edge unit=%d" % unit):
			return false
	return true

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("F01 " + message + " source=" + FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"))
		quit(1)
	return condition
