extends SceneTree

const EdgeChecks = preload("res://scripts/tests/terrain_army_default_edge_test.gd")

var _failed := false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			var method := argument.trim_prefix("--case=")
			if method not in ["_verify_captain_swap", "_verify_planning_throughput", "_verify_ramp_corridor", "_verify_multi_level_descent", "_verify_long_route_search", "_verify_captain_route_ownership", "_verify_follower_detour_route"]:
				push_error("Unknown regression case")
				quit(1)
				return
			var outcome: Variant = call(method)
			if _failed or (outcome is bool and not outcome):
				quit(1)
				return
			print("FULL_CASE_PASS ", method)
			quit(0)
			return
	var data := _flat_data()
	var player := TerrainTestCharacter.new()
	player.data = data
	if not _check(player.place(Vector2i(32, 32), true)):
		return
	var npc := TerrainTestNPC.new()
	npc.data = data
	if not _check(npc.place(Vector2i(31, 32), true)):
		return
	var army := TerrainArmy.new()
	if not _check(army.deploy(data, player, npc), army.command_status):
		return
	if not _check(army.has_army()):
		return
	if not _check(army.occupied_count() == TerrainArmy.SOLDIER_COUNT):
		return
	if not _check(army.formation_count() == TerrainArmy.SOLDIER_COUNT - 1, "Deployment should start with all followers assembled"):
		return
	if not _check(_unique_cells(army.cells), "Army deployment contains overlapping cells"):
		return
	for cell: Vector2i in army.cells:
		if not _check(data.is_walkable(cell), "Army deployed on a blocked cell"):
			return
		if not _check(cell != player.terrain_cell and cell != npc.terrain_cell):
			return
		if not _check(army.blocks_cell(cell, player)):
			return
	if not _check(army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER), "Follow must be accepted at the deployment point"):
		return
	# Move the test player beyond the initial deployment ring so follow has an
	# unambiguous legal opening instead of asking the captain to cross its own
	# occupied formation.
	if not _check(player.place(Vector2i(50, 50), true)):
		return
	if not _check(army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER), army.command_status):
		return
	var initial_captain: Vector2i = army.cells[0]
	# V6 plans the full 100-person layout with the unchanged 256/frame
	# structural quota before motion; retain G01's declared 20s setup bound.
	for _step: int in range(20 * 60):
		army.advance_frame(1.0 / 60.0)
		if army.cells[0] != initial_captain or army.moving_count() > 0:
			break
	if not _check((army.cells[0] != initial_captain or army.moving_count() > 0) and army.max_frame_structure_expansions <= 256 and army.dropped_seconds == 0.0, "Follow command did not schedule legal movement within the declared setup budget"):
		return
	for _step: int in range(72):
		army.advance_frame(1.0 / 60.0)
	if not _check(_unique_cells(army.cells), "Follow movement produced overlapping cells"):
		return
	if not _check(army.issue_command(TerrainArmy.Command.MOVE_TO_EDGE), army.command_status):
		return
	for frame: int in range(20 * 60):
		army.advance_frame(1.0 / 60.0)
		if army._pending_command < 0 and not army._command_goal_pending and not army._passage_plan_pending and not army._formation_target_pending:
			break
	if not _check(army.edge_targets.size() == 1, "Edge command created per-soldier edge destinations"):
		return
	if not _check(_is_boundary(army.edge_targets[0], data), "Formation front target is not on the map boundary"):
		return
	if not _check(army._march_goal == army.edge_targets[0], "Command lost its immutable front destination"):
		return
	if not _check(army._passage_final_slots.size() == 99 and army._passage_final_slots.has(army.edge_targets[0]) and army._passage_final_captain_slot != army.edge_targets[0], "Boundary front must belong to a guard, with captain inside the full formation"):
		return
	for _step: int in range(240):
		army.advance_frame(1.0 / 60.0)
	if not _check(_unique_cells(army.cells), "Edge movement produced overlapping cells"):
		return
	for cell: Vector2i in army.cells:
		if not _check(data.is_walkable(cell), "Edge command crossed a blocked cell"):
			return
	army.clear()
	army.free()
	npc.free()
	player.free()
	print("FULL_STAGE _verify_captain_swap")
	_verify_captain_swap()
	if _failed:
		return
	print("FULL_STAGE _verify_planning_throughput")
	_verify_planning_throughput()
	if _failed:
		return
	print("FULL_STAGE _verify_ramp_corridor")
	_verify_ramp_corridor()
	if _failed:
		return
	print("FULL_STAGE _verify_multi_level_descent")
	if not _verify_multi_level_descent():
		quit(1)
		return
	print("FULL_STAGE _verify_long_route_search")
	_verify_long_route_search()
	if _failed:
		return
	print("FULL_STAGE _verify_captain_route_ownership")
	_verify_captain_route_ownership()
	if _failed:
		return
	print("FULL_STAGE _verify_follower_detour_route")
	_verify_follower_detour_route()
	if _failed:
		return
	print("TERRAIN LAB ARMY V6 PASS: formation-front goal, legal multi-level route, atomic swaps, and shared route ownership")
	quit(0)

func _verify_captain_swap() -> void:
	var data := _flat_data()
	var player := TerrainTestCharacter.new()
	player.data = data
	if not _check(player.place(Vector2i(5, 5), true)):
		return
	var npc := TerrainTestNPC.new()
	npc.data = data
	if not _check(npc.place(Vector2i(6, 5), true)):
		return
	var army := TerrainArmy.new()
	if not _check(army.deploy(data, player, npc), army.command_status):
		return
	var forced: Array[Vector2i] = []
	forced.append(Vector2i(40, 40))
	forced.append(Vector2i(41, 40))
	for y: int in range(43, 53):
		for x: int in range(40, 50):
			var candidate := Vector2i(x, y)
			if candidate != forced[0] and candidate != forced[1] and forced.size() < TerrainArmy.SOLDIER_COUNT:
				forced.append(candidate)
	if not _check(forced.size() == TerrainArmy.SOLDIER_COUNT):
		return
	# Surround the captain on all four sides. The east soldier is the first
	# legal swap partner; after the exchange the captain must continue into the
	# newly opened cell instead of oscillating in place.
	forced[2] = Vector2i(39, 40)
	forced[3] = Vector2i(40, 39)
	forced[4] = Vector2i(40, 41)
	_force_formation(army, forced)
	army.desired_cells[0] = Vector2i(42, 40)
	var captain_before: Vector2i = army.cells[0]
	army._simulate_step(TerrainArmy.SIM_STEP)
	if not _check(army.has_active_swap(), "Captain did not enter the explicit swap state"):
		return
	if not _check(army.blocks_cell(forced[0], player) and army.blocks_cell(forced[1], player), "Swap did not reserve both source cells"):
		return
	for _step: int in range(7):
		army._simulate_step(TerrainArmy.SIM_STEP)
	if not _check(army.swap_count() == 1, "Captain did not start and complete a legal adjacent swap"):
		return
	print("SWAP_POST state=", army.movement_state[0], " captain=", army.cells[0], " goal=", army.desired_cells[0], " commits=", army.completed_steps(), " command=", army.command, " plan_pending=", army._passage_plan_pending, " passage=", army._passage_active, " route=", army._path_route_snapshot, " status=", army.command_status)
	if not _check(army.completed_steps() >= 3, "Captain did not continue after the atomic swap"):
		return
	if not _check(army.cells[0] == Vector2i(42, 40) and army.cells[1] == captain_before, "Captain swap did not exchange then advance"):
		return
	if not _check(not army.has_active_swap(), "Captain swap remained active after completion"):
		return
	if not _check(_unique_cells(army.cells), "Captain swap produced overlapping cells"):
		return
	if not _check(army.blocks_cell(forced[0], player), "Swapped partner cell lost occupancy"):
		return
	for _step: int in range(100):
		army._simulate_step(TerrainArmy.SIM_STEP)
	if not _check(army.swap_count() == 1, "Captain immediately reversed the same exchange"):
		return
	if not _check(_unique_cells(army.cells), "Post-swap settling produced overlapping cells"):
		return
	# A cliff without reciprocal ramp edges cannot be exchanged.
	var blocked_data := _flat_data()
	blocked_data.height_levels[blocked_data.index(forced[1])] = 1
	blocked_data.flags[blocked_data.index(forced[1])] = TerrainData.Flag.WALKABLE | TerrainData.Flag.CLIFF
	var blocked_player := TerrainTestCharacter.new()
	blocked_player.data = blocked_data
	if not _check(blocked_player.place(Vector2i(5, 5), true)):
		return
	var blocked_npc := TerrainTestNPC.new()
	blocked_npc.data = blocked_data
	if not _check(blocked_npc.place(Vector2i(6, 5), true)):
		return
	var blocked_army := TerrainArmy.new()
	if not _check(blocked_army.deploy(blocked_data, blocked_player, blocked_npc), blocked_army.command_status):
		return
	_force_formation(blocked_army, forced)
	blocked_army.desired_cells[0] = forced[1]
	blocked_army._simulate_step(TerrainArmy.SIM_STEP)
	if not _check(blocked_army.swap_count() == 0, "Captain exchanged across a cliff without a ramp"):
		return
	if not _check(_unique_cells(blocked_army.cells), "Illegal swap test produced overlapping cells"):
		return
	blocked_army.free()
	blocked_npc.free()
	blocked_player.free()
	army.free()
	npc.free()
	player.free()

func _force_formation(army: TerrainArmy, forced: Array[Vector2i]) -> void:
	army._cell_owners.clear()
	army._reserved_cells.clear()
	army.cells = forced.duplicate()
	for index: int in range(TerrainArmy.SOLDIER_COUNT):
		army.desired_cells[index] = army.cells[index]
		army.moving_to[index] = TerrainArmy.INVALID_CELL
		army.movement_state[index] = TerrainArmy.UnitState.IDLE
		army.move_progress[index] = 0.0
		army.blocked_time[index] = 0.0
		army.swap_partner[index] = -1
		army._cell_owners[army.cells[index]] = index
	army._swap_cooldown = 0.0
	army.command = TerrainArmy.Command.NONE
	# Keep the forced fixture authoritative for one simulation tick. Otherwise
	# the production formation planner quite correctly rebuilds these synthetic
	# slots around the captain before the swap assertion runs.
	army._formation_anchor_cell = army.cells[0]
	army._formation_heading = Vector2i.DOWN
	army._formation_anchor_height = int(army.data.height_levels[army.data.index(army.cells[0])])
	army.formation_mode = TerrainArmy.FormationMode.OPEN

func _verify_ramp_corridor() -> void:
	var data := _ramp_data()
	var player := TerrainTestCharacter.new()
	player.data = data
	if not _check(player.place(Vector2i(20, 50), true)):
		return
	var npc := TerrainTestNPC.new()
	npc.data = data
	if not _check(npc.place(Vector2i(18, 50), true)):
		return
	var army := TerrainArmy.new()
	if not _check(army.deploy(data, player, npc), army.command_status):
		return
	if not _check(player.place(Vector2i(80, 50), true)):
		return
	if not _check(army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER), army.command_status):
		return
	if not _check(_replay_multi_level(army, data, true), "Ramp full 99-person clearance failed"):
		return
	army.free()
	npc.free()
	player.free()

func _verify_planning_throughput() -> void:
	var data := _flat_data()
	var player := TerrainTestCharacter.new()
	player.data = data
	if not _check(player.place(Vector2i(50, 50), true)):
		return
	var npc := TerrainTestNPC.new()
	npc.data = data
	if not _check(npc.place(Vector2i(51, 50), true)):
		return
	var army := TerrainArmy.new()
	if not _check(army.deploy(data, player, npc), army.command_status):
		return
	var forced: Array[Vector2i] = []
	for x: int in range(TerrainArmy.SOLDIER_COUNT):
		forced.append(Vector2i(x, 10))
	_force_formation(army, forced)
	for index: int in range(TerrainArmy.SOLDIER_COUNT):
		army.desired_cells[index] = army.cells[index] + Vector2i.DOWN * 10
	army._simulate_step(TerrainArmy.SIM_STEP)
	if not _check(army.moving_count() == TerrainArmy.SOLDIER_COUNT, "Followers were throttled by a per-tick planning quota"):
		return
	army.free()
	npc.free()
	player.free()

func _verify_long_route_search() -> void:
	var data := _flat_data()
	var army := TerrainArmy.new()
	army.data = data
	var route: Array[Vector2i] = []
	for _step: int in range(100):
		army._structure_expansions_remaining = 256 # Pure helper: next explicit budget slice.
		route = army._find_path(Vector2i.ZERO, Vector2i(99, 99), 0)
		if army._path_status != TerrainArmy.PathStatus.PENDING:
			break
	if not _check(army._path_status == TerrainArmy.PathStatus.FOUND, "Long route search was not completed across multiple budgets"):
		return
	if not _check(route.size() == 198, "Long route returned an unexpected path length"):
		return
	army.free()

func _verify_captain_route_ownership() -> void:
	var data := _flat_data()
	var army := TerrainArmy.new()
	army.data = data
	army._frame_navigation_budget_active = true
	var route: Array[Vector2i] = []
	for _step: int in range(100):
		army._structure_expansions_remaining = 256 # Pure helper: one input-frame quota.
		army._detour_searches_remaining = 1
		route = army._find_path(Vector2i.ZERO, Vector2i(99, 99), 0)
		if army._path_status != TerrainArmy.PathStatus.PENDING:
			break
	if not _check(army._path_status == TerrainArmy.PathStatus.FOUND, "Captain route did not finish"):
		return
	if not _check(army._path_route_owner == 0 and army._path_route_goal == Vector2i(99, 99), "Captain route ownership is missing"):
		return
	var route_before := army._path_route.duplicate()
	var cursor_before := army._path_route_cursor
	var follower_result := army._find_path(Vector2i(1, 1), Vector2i(2, 2), 1)
	if not _check(follower_result.is_empty(), "Follower launched a full-map route search"):
		return
	if not _check(army._path_route == route_before, "Follower replaced the captain route"):
		return
	if not _check(army._path_route_cursor == cursor_before, "Follower changed the captain route cursor"):
		return
	if not _check(army._find_path(Vector2i.ZERO, Vector2i.ZERO, 1).is_empty(), "Follower trivial route was not rejected"):
		return
	if not _check(army._path_status == TerrainArmy.PathStatus.FOUND, "Follower trivial request changed captain path status"):
		return
	army.free()

func _verify_multi_level_descent() -> bool:
	var terrain := _multi_level_edge_data()
	var player := TerrainTestCharacter.new()
	player.data = terrain
	var npc := TerrainTestNPC.new()
	npc.data = terrain
	var army := TerrainArmy.new()
	var valid := player.place(Vector2i(10, 10), true) and npc.place(Vector2i(9, 10), true)
	valid = valid and army.deploy(terrain, player, npc)
	valid = valid and army.issue_command(TerrainArmy.Command.MOVE_TO_EDGE)
	if valid:
		valid = _replay_multi_level(army, terrain)
	else:
		push_error("FIXTURE_INVALID multi-level deployment/command")
	army.free()
	npc.free()
	player.free()
	return valid

func _replay_multi_level(army: TerrainArmy, terrain: TerrainData, ramp: bool = false) -> bool:
	var gates := [[Vector2i(49, 50), Vector2i(50, 50)], [Vector2i(50, 50), Vector2i(51, 50)]] if ramp else [[Vector2i(24, 15), Vector2i(25, 15)], [Vector2i(49, 70), Vector2i(50, 70)], [Vector2i(74, 40), Vector2i(75, 40)]]
	var label := "RAMP_0_1_0" if ramp else "MULTILEVEL"
	var goal := Vector2i(75, 50) if ramp else Vector2i(99, 80)
	var hz := 30 if "--30hz" in OS.get_cmdline_user_args() else 60
	var alternating := "--alternating" in OS.get_cmdline_user_args()
	# Declared before the first V6 physical replay: identical engineering
	# formula to D01. The one-cell ramp platform cannot hold 100; the three
	# large multilevel plateaus can, so they require three separate rallies.
	var independent_route := EdgeChecks._independent_route(terrain, army.cells[0], goal)
	var groups := 1 if ramp else 3
	var deadline := 0.3 * float(independent_route.size() - 1) + 0.6 * 99 * groups + 20.0 * (groups + 1) + 10.0
	var progress := PackedInt32Array()
	progress.resize(100)
	var cleared := PackedInt32Array()
	cleared.resize(100)
	var counts := []
	var clear_counts := []
	var captain_orders := []
	var expected := []
	for gate: int in range(gates.size()):
		counts.append(0)
		clear_counts.append(0)
		captain_orders.append(-1)
		expected.append(99)
	var previous := army.cells.duplicate()
	var complete_time := -1.0
	print(label, " START source=", FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"), " fingerprint=", terrain.fingerprint(), " deadline=", deadline, " route_edges=", independent_route.size() - 1, " groups=", groups, " INITIAL_CELLS=", previous)
	var frame := 0
	while army.input_seconds < deadline:
		var delta := (1.0 / 120.0 if frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz)
		frame += 1
		army.advance_frame(delta)
		if not EdgeChecks._legal_state(army, terrain) or army.max_frame_structure_expansions > 256 or army.max_frame_local_expansions > 8192 or army.max_frame_push_expansions > 1024:
			push_error("MULTILEVEL overlap or search budget exceeded")
			return false
		if not army._command_goal_pending and army._march_goal != goal:
			push_error("MULTILEVEL wrong sole boundary goal")
			return false
		for unit: int in range(100):
			if army._cell_owners.get(army.cells[unit], -1) != unit:
				push_error("MULTILEVEL owner mismatch")
				return false
			if previous[unit] == army.cells[unit]:
				continue
			if not terrain.can_step(previous[unit], army.cells[unit]):
				push_error("MULTILEVEL illegal committed edge")
				return false
			for gate: int in range(gates.size()):
				if previous[unit] == gates[gate][1] and army.cells[unit] == gates[gate][0]:
					push_error("MULTILEVEL reverse crossing")
					return false
				if previous[unit] == gates[gate][0] and army.cells[unit] == gates[gate][1]:
					if progress[unit] != gate:
						push_error("MULTILEVEL crossing order")
						return false
					progress[unit] += 1
					if unit == 0:
						captain_orders[gate] = counts[gate]
						if counts[gate] < 20 or counts[gate] > 70:
							push_error("MULTILEVEL captain crossed outside protected middle order")
							return false
					else:
						counts[gate] += 1
				if previous[unit] == gates[gate][1] and army.cells[unit] != gates[gate][0]:
					if cleared[unit] != gate or progress[unit] != gate + 1:
						push_error("MULTILEVEL clearing order")
						return false
					cleared[unit] += 1
					if unit > 0:
						clear_counts[gate] += 1
		previous = army.cells.duplicate()
		if (frame + 1) % 1080 == 0:
			print("MULTILEVEL t=", army.input_seconds, " captain=", army.cells[0], " gates=", counts, " clears=", clear_counts, " summary=", army.passage_summary(), " settled=", army.formation_count())
		if army.is_formation_complete():
			if counts != expected or clear_counts != expected or army.formation_count() != 99 or progress[0] != gates.size() or cleared[0] != gates.size() or army.cells[0] != army._passage_final_captain_slot:
				push_error("MULTILEVEL completed before all 99 crossed and cleared every gate")
				return false
			complete_time = army.input_seconds
			break
	if complete_time < 0:
		push_error("MULTILEVEL missed predeclared V6 input deadline %.1f" % deadline)
		for unit: int in range(1, 100):
			if army.cells[unit] != army.desired_cells[unit]:
				print("MULTILEVEL_UNSETTLED ", unit, " cell=", army.cells[unit], " goal=", army.desired_cells[unit], " passage=", army._unit_passage[unit], " phase=", army._unit_passage_phase[unit], " completed=", army._unit_completed_exits[unit])
		return false
	var final_cells := army.cells.duplicate()
	for stable_frame: int in range(5 * hz):
		var delta := (1.0 / 120.0 if stable_frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz)
		army.advance_frame(delta)
		if not EdgeChecks._legal_state(army, terrain) or not army.is_formation_complete() or army.cells != final_cells or army.dropped_seconds != 0.0:
			push_error("MULTILEVEL failed five-second stability")
			return false
	print("ARMY_", label, "_V6_PASS complete_seconds=", complete_time, " deadline=", deadline, " crossings=", counts, " clearings=", clear_counts, " captain_orders=", captain_orders, " hz=", hz, " jitter=", alternating, " stable=5 max_structure=", army.max_frame_structure_expansions, " max_local=", army.max_frame_local_expansions, " max_push=", army.max_frame_push_expansions)
	return true

func _verify_follower_detour_route() -> void:
	var data := _flat_data()
	for y: int in range(9, 12):
		data.flags[data.index(Vector2i(11, y))] = TerrainData.Flag.BLOCKED
	var army := TerrainArmy.new()
	army.data = data
	var start := Vector2i(10, 10)
	var goal := Vector2i(13, 10)
	var first := army._start_follower_route(start, goal, 1, 1024)
	if not _check(first != TerrainArmy.INVALID_CELL, "Follower detour route was not found"):
		return
	if not _check(first != Vector2i(11, 10), "Follower detour crossed the blocking wall"):
		return
	army._consume_follower_route_step(1, first)
	var second := army._next_follower_step(first, goal, 1)
	if not _check(second != TerrainArmy.INVALID_CELL, "Follower detour route was lost after the first step"):
		return
	if not _check(second != start, "Follower detour immediately reversed to its source cell"):
		return
	if not _check(data.can_step(first, second), "Follower detour produced an illegal edge"):
		return
	army.free()

func _flat_data() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(100, 100))
	for index: int in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.surface_types[index] = TerrainData.Surface.GRASS
		data.flags[index] = TerrainData.Flag.WALKABLE
	data.spawn_cell = Vector2i(50, 50)
	return data

func _unique_cells(cells: Array[Vector2i]) -> bool:
	var seen := {}
	for cell: Vector2i in cells:
		if seen.has(cell):
			return false
		seen[cell] = true
	return true

func _is_boundary(cell: Vector2i, data: TerrainData) -> bool:
	return cell.x == 0 or cell.y == 0 or cell.x == data.size.x - 1 or cell.y == data.size.y - 1

func _ramp_data() -> TerrainData:
	var data := _flat_data()
	for y: int in range(data.size.y):
		if y == 50:
			continue
		var wall := Vector2i(50, y)
		var wall_index := data.index(wall)
		data.height_levels[wall_index] = 1
		data.flags[wall_index] = TerrainData.Flag.WALKABLE | TerrainData.Flag.CLIFF
	var lower := Vector2i(49, 50)
	var upper := Vector2i(50, 50)
	var right := Vector2i(51, 50)
	data.height_levels[data.index(upper)] = 1
	data.ramp_edges[data.index(lower)] |= 1 << TerrainData.DIRECTIONS.find(Vector2i.RIGHT)
	data.ramp_edges[data.index(upper)] |= 1 << TerrainData.DIRECTIONS.find(Vector2i.LEFT)
	data.ramp_edges[data.index(upper)] |= 1 << TerrainData.DIRECTIONS.find(Vector2i.RIGHT)
	data.ramp_edges[data.index(right)] |= 1 << TerrainData.DIRECTIONS.find(Vector2i.LEFT)
	return data

func _multi_level_data() -> TerrainData:
	var data := _flat_data()
	for y: int in range(data.size.y):
		for x: int in range(data.size.x):
			var level := 3 if x < 25 else (2 if x < 50 else (1 if x < 75 else 0))
			var cell := Vector2i(x, y)
			var cell_index := data.index(cell)
			data.height_levels[cell_index] = level
			data.flags[cell_index] = TerrainData.Flag.WALKABLE
	# Each boundary has one offset reciprocal ramp. All other boundary cells
	# remain cliffs, so a greedy x movement must discover the complete route.
	for boundary: Array in [[Vector2i(24, 15), Vector2i(25, 15)], [Vector2i(49, 70), Vector2i(50, 70)], [Vector2i(74, 40), Vector2i(75, 40)]]:
		var low_side: Vector2i = boundary[0]
		var high_side: Vector2i = boundary[1]
		data.ramp_edges[data.index(low_side)] |= 1 << TerrainData.DIRECTIONS.find(Vector2i.RIGHT)
		data.ramp_edges[data.index(high_side)] |= 1 << TerrainData.DIRECTIONS.find(Vector2i.LEFT)
	return data

func _multi_level_edge_data() -> TerrainData:
	var data := _multi_level_data()
	# Keep only one reachable boundary opening on the lowest plateau. The
	# interior remains rectangular and the three reciprocal ramps are the only
	# legal height transitions, so this catches the old one-layer edge bug.
	for y: int in range(data.size.y):
		for x: int in range(data.size.x):
			if x != 99 or y != 80:
				if x == 0 or y == 0 or x == data.size.x - 1 or y == data.size.y - 1:
					data.flags[data.index(Vector2i(x, y))] = TerrainData.Flag.BLOCKED
	data.flags[data.index(Vector2i(99, 80))] = TerrainData.Flag.WALKABLE
	return data

func _check(condition: bool, message: String = "contract check failed") -> bool:
	if not condition:
		_failed = true
		push_error(message)
		quit(1)
	return condition
