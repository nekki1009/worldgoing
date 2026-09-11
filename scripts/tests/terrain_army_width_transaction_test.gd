extends SceneTree

var _failed := false

func _check(value: bool, message: String = "fixture contract") -> bool:
	if not value:
		_failed = true
		push_error(message)
		quit(1)
	return value

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--contract="):
			var case_name := argument.trim_prefix("--contract=")
			var passed := _contract(case_name)
			if passed:
				print("ARMY_CONTRACT_PASS case=%s source=%s" % [case_name, FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd")])
			quit(0 if passed else 1)
			return
	if "--case=M01_PIPELINE" in OS.get_cmdline_user_args():
		var passed := _verify_phase_edges(true)
		if passed:
			print("ARMY_M01_PIPELINE_PASS")
		quit(0 if passed else 1)
		return
	if "--case=Q03_PHASE" in OS.get_cmdline_user_args():
		var passed := _verify_phase_edges()
		if passed:
			print("ARMY_Q03_PHASE_PASS")
		quit(0 if passed else 1)
		return
	if "--case=Q02_RELEASE" in OS.get_cmdline_user_args():
		var passed := _verify_committed_release()
		if passed:
			print("ARMY_Q02_COMMITTED_RELEASE_PASS")
		quit(0 if passed else 1)
		return
	if "--case=F03" in OS.get_cmdline_user_args():
		var passed := _verify_search_budget()
		if passed:
			print("ARMY_F03_FAIR_PASS: 99 continuously eligible units served in <=25 ticks; one request each")
		quit(0 if passed else 1)
		return
	var army := TerrainArmy.new()
	var defaults := TerrainGenerator.generate(TerrainPreset.Kind.TERRACED_HIGHLAND, 12345)
	army.data = defaults
	for gate: Array in preload("res://scripts/tests/terrain_army_default_edge_test.gd").EXPECTED_GATES:
		if not _check(army._route_edge_width(gate[0], gate[1]) == 1, "W01 default width"):
			return
		if not _check(army._route_edge_width(gate[1], gate[0]) == 1, "W01 reverse width"):
			return
	for rotated: bool in [false, true]:
		for separated: bool in [false, true]:
			var data := TerrainData.new()
			data.allocate(Vector2i(8, 8))
			data.flags.fill(TerrainData.Flag.WALKABLE)
			for y: int in range(8):
				for x: int in range(8):
					data.height_levels[data.index(Vector2i(x, y))] = int((y if rotated else x) >= 3)
			for lane: int in [2, 4 if separated else 3]:
				var low := Vector2i(lane, 2) if rotated else Vector2i(2, lane)
				var high := Vector2i(lane, 3) if rotated else Vector2i(3, lane)
				data.ramp_edges[data.index(low)] = 1 << (2 if rotated else 1)
				data.ramp_edges[data.index(high)] = 1 << (0 if rotated else 3)
			army.data = data
			var start := Vector2i(2, 2)
			var end := Vector2i(2, 3) if rotated else Vector2i(3, 2)
			var expected := 1 if separated else 2
			if not _check(army._route_edge_width(start, end) == expected, "W02/W03 width"):
				return
			if not _check(army._route_edge_width(end, start) == expected, "W02/W03 reverse width"):
				return
	var flat := TerrainData.new()
	flat.allocate(Vector2i(24, 24))
	flat.flags.fill(TerrainData.Flag.WALKABLE)
	army.data = flat
	if not _check(army._route_edge_width(Vector2i(12, 12), Vector2i(13, 12)) == 11, "W05 horizontal"):
		return
	if not _check(army._route_edge_width(Vector2i(13, 12), Vector2i(13, 13)) == 11, "W05 turn"):
		return
	for y: int in range(24):
		if y != 12:
			flat.flags[flat.index(Vector2i(13, y))] = TerrainData.Flag.BLOCKED
	if not _check(army._route_edge_width(Vector2i(12, 12), Vector2i(13, 12)) == 1, "W04 wall"):
		return
	army.free()
	for cancel_started: bool in [false, true]:
		_verify_cancel(cancel_started)
		if _failed:
			return
	print("TERRAIN ARMY WIDTH/TRANSACTION PASS: W01-W05, both release modes preserve in-flight claim and commit")
	quit(0)

func _verify_search_budget() -> bool:
	# Search-service replay on a real 100-person deployment, not a completion
	# claim. Every unique, unlocked requester continuously needs an unreachable
	# route through the sealed wall; no overlapping fake cells are used.
	var army := TerrainArmy.new()
	var terrain := TerrainData.new()
	terrain.allocate(Vector2i(40, 30))
	terrain.flags.fill(TerrainData.Flag.WALKABLE)
	for y: int in range(30):
		terrain.flags[terrain.index(Vector2i(20, y))] = TerrainData.Flag.BLOCKED
	var player := TerrainTestCharacter.new()
	player.data = terrain
	player.place(Vector2i(3, 15), true)
	var npc := TerrainTestNPC.new()
	npc.data = terrain
	npc.place(Vector2i(2, 15), true)
	if not _check(army.deploy(terrain, player, npc), "FIXTURE_INVALID F03 deployment"):
		return false
	var initial := army.cells.duplicate()
	print("F03 INITIAL_CELLS=%s fingerprint=%s" % [initial, terrain.fingerprint()])
	var served := {}
	for tick: int in range(1, 26):
		army._passage_tick = tick
		army._local_path_requests_remaining = 4
		for unit: int in army._formation_planning_order(Vector2i.RIGHT):
			if unit == 0:
				continue
			var before := army._local_path_requests_remaining
			army._find_local_route(army.cells[unit], Vector2i(35, 15), 1024, false, unit)
			var after := army._local_path_requests_remaining
			if after == before - 1:
				served[unit] = tick
				army._find_local_route(army.cells[unit], Vector2i(35, 15), 1024, true, unit)
				if army._local_path_requests_remaining != after:
					push_error("F03 one unit consumed two search requests in one tick: %s" % unit)
					army.free()
					return false
		if army._local_path_requests_remaining != 0:
			push_error("F03 common search entrance did not charge four eligible requests")
			army.free()
			return false
	var passed := served.size() == 99 and army.cells == initial and army.max_local_search_expansions <= 1024
	if not passed:
		push_error("F03 starvation: only %s/99 units served in 25 ticks" % served.size())
	army.free()
	npc.free()
	player.free()
	return passed

func _verify_phase_edges(pipeline: bool = false) -> bool:
	# Pure phase/edge fixture. Four consecutive core cells make the common
	# protected-mask bug observable without depending on a complete deployment.
	var terrain := TerrainData.new()
	terrain.allocate(Vector2i(16, 8))
	terrain.flags.fill(TerrainData.Flag.WALKABLE)
	var army := TerrainArmy.new()
	army.data = terrain
	army.cells.resize(100)
	army.cells.fill(Vector2i(1, 1))
	army._unit_passage.resize(100)
	army._unit_passage.fill(0)
	army._unit_passage_cursor.resize(100)
	army._unit_passage_phase.resize(100)
	army._unit_passage_phase.fill(TerrainArmy.PassagePhase.APPROACH)
	army._unit_passage_phase[1] = TerrainArmy.PassagePhase.IN_PASSAGE
	army.cells[1] = Vector2i(4, 4)
	army.desired_cells.assign(army.cells)
	army._passage_active = true
	army._passage_descriptors = [{"entry": Vector2i(2, 4), "core": [Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4)], "exit": Vector2i(6, 4), "corridor": [Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)], "protected": [Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4)]}]
	army._unit_passage_ticket.resize(100)
	army._unit_passage_ticket.fill(-1)
	army._unit_passage_ticket[1] = 0
	army._unit_passage_ticket[2] = 1
	army._passage_ticket_order = [1, 2]
	army._passage_service_owner = PackedInt32Array([1])
	army.cells[2] = Vector2i(2, 4)
	var passed := army._passage_unit_may_be_pushed(1, Vector2i(5, 4), 2) \
		and not army._passage_unit_may_be_pushed(1, Vector2i(3, 4), 2) \
		and not army._passage_unit_may_be_pushed(1, Vector2i(4, 3), 2)
	if not passed:
		push_error("Q03 own next protected core edge must remain legal; reverse/side exits must be refused")
	if not pipeline and army._next_step(army.cells[1], army.cells[1], 1) != Vector2i(5, 4):
		passed = false
		push_error("Q03 old slot equality stopped an unfinished passage")
	if pipeline and not army._passage_ready_for_entry(2, 0):
		passed = false
		push_error("M01 first core is free, but the previous unit farther inside still monopolizes admission")
	army.free()
	return passed

func _verify_committed_release() -> bool:
	var terrain := TerrainData.new()
	terrain.allocate(Vector2i(100, 100))
	terrain.flags.fill(TerrainData.Flag.WALKABLE)
	var player := TerrainTestCharacter.new()
	player.data = terrain
	player.place(Vector2i(50, 50), true)
	var npc := TerrainTestNPC.new()
	npc.data = terrain
	npc.place(Vector2i(51, 50), true)
	var army := TerrainArmy.new()
	var passed := army.deploy(terrain, player, npc)
	army.command = TerrainArmy.Command.NONE
	for unit: int in range(1, 5):
		army._cell_owners.erase(army.cells[unit])
		army.cells[unit] = Vector2i(9 + unit, 10)
		army._cell_owners[army.cells[unit]] = unit
	passed = passed and army._queue_push_chain(1, [Vector2i(11, 10), Vector2i(12, 10), Vector2i(13, 10), Vector2i(14, 10)])
	army._complete_move(4)
	passed = passed and army._push_lock[4] == 0 and army._push_lock[1] == 1
	if not passed:
		push_error("Q02 a committed tail remained unnecessarily locked while requester must stay protected")
	else:
		passed = army._schedule_push_unit(4, Vector2i(14, 11))
		army._advance_pending_pushes()
		passed = passed and army.moving_to[3] == Vector2i(13, 10) and army._pending_pushes.size() == 1
		if passed:
			army._release_push_transaction(army._pending_pushes[0])
			army._pending_pushes.clear()
			passed = army._reserved_cells.get(Vector2i(14, 11), -1) == 4 and army.moving_to[4] == Vector2i(14, 11)
		if not passed:
			push_error("Q02 committed tail's next legal move corrupted its old transaction")
	army.free()
	npc.free()
	player.free()
	return passed

func _verify_cancel(cancel_started: bool) -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(100, 100))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	var player := TerrainTestCharacter.new()
	player.data = data
	if not _check(player.place(Vector2i(50, 50), true)):
		return
	var npc := TerrainTestNPC.new()
	npc.data = data
	if not _check(npc.place(Vector2i(51, 50), true)):
		return
	var army := TerrainArmy.new()
	if not _check(army.deploy(data, player, npc)):
		return
	army.command = TerrainArmy.Command.NONE
	army._cell_owners.erase(army.cells[1])
	army._cell_owners.erase(army.cells[2])
	army.cells[1] = Vector2i(10, 10)
	army.cells[2] = Vector2i(11, 10)
	army._cell_owners[army.cells[1]] = 1
	army._cell_owners[army.cells[2]] = 2
	army.desired_cells[1] = Vector2i(11, 10)
	army.desired_cells[2] = Vector2i(12, 10)
	if not _check(army._can_follower_swap(1, 2), "swap control fixture invalid"):
		return
	army._push_lock[1] = 1
	if not _check(not army._can_follower_swap(1, 2), "locked follower accepted swap"):
		return
	army._push_lock[1] = 0
	if not _check(army._queue_push_chain(1, [Vector2i(11, 10), Vector2i(12, 10)]), "queue rejected"):
		return
	army.move_progress[2] = 0.5
	var pending: Dictionary = army._pending_pushes[0]
	army._release_push_transaction(pending, cancel_started)
	army._pending_pushes.clear()
	if not _check(army.cells[2] == Vector2i(11, 10) and army.moving_to[2] == Vector2i(12, 10), "cancel snapped move"):
		return
	if not _check(army.move_progress[2] == 0.5, "cancel reset interpolation"):
		return
	if not _check(army._reserved_cells.get(Vector2i(12, 10), -1) == 2, "cancel dropped active claim"):
		return
	if not _check(not army._reserved_cells.has(Vector2i(11, 10)), "cancel retained unstarted claim"):
		return
	army._complete_move(2)
	if not _check(army.cells[2] == Vector2i(12, 10) and army._reserved_cells.is_empty(), "commit after cancellation failed"):
		return
	if not _check(army._push_lock[1] == 0 and army._push_lock[2] == 0, "cancel leaked lock"):
		return
	var input_before := army.input_seconds
	var sim_before := army.simulated_seconds
	var dropped_before := army.dropped_seconds
	var remainder_before := army._sim_accumulator
	army.advance_frame(1.0)
	if not _check(is_equal_approx(army.input_seconds - input_before, 1.0), "large dt input not recorded"):
		return
	if not _check(army.simulated_seconds - sim_before <= TerrainArmy.MAX_SIM_STEPS_PER_FRAME * TerrainArmy.SIM_STEP + 0.00001, "large dt exceeded catch-up budget"):
		return
	if not _check(army.dropped_seconds > 0.0, "large dt lost time silently"):
		return
	var simulated := army.simulated_seconds - sim_before
	var dropped := army.dropped_seconds - dropped_before
	var remainder := army._sim_accumulator - remainder_before
	if not _check(is_equal_approx(simulated + dropped + remainder, 1.0) and is_equal_approx(dropped, maxf(0.0, remainder_before + 1.0 - TerrainArmy.MAX_ACCUMULATED_SIM_TIME)), "large dt input != simulated + dropped + retained remainder"):
		return
	print("LARGE_DT_ACCOUNTING_PASS input=1 simulated=", simulated, " dropped=", dropped, " retained=", remainder)
	army.free()
	npc.free()
	player.free()


func _contract(case_name: String) -> bool:
	# Isolated transaction fixture. Relocations occur only before replay.
	var terrain := TerrainData.new()
	terrain.allocate(Vector2i(100, 100))
	terrain.flags.fill(TerrainData.Flag.WALKABLE)
	var player := TerrainTestCharacter.new()
	player.data = terrain
	player.place(Vector2i(50, 50), true)
	var npc := TerrainTestNPC.new()
	npc.data = terrain
	npc.place(Vector2i(51, 50), true)
	var army := TerrainArmy.new()
	if not _check(army.deploy(terrain, player, npc), "FIXTURE_INVALID deploy"):
		return false
	army.command = TerrainArmy.Command.NONE
	for unit: int in range(21):
		army._cell_owners.erase(army.cells[unit])
	for unit: int in range(21):
		army.cells[unit] = Vector2i(9 + unit, 10)
		army._cell_owners[army.cells[unit]] = unit
	army.desired_cells.assign(army.cells)
	army._formation_slot_cells.assign(army.cells)
	var passed := false
	if case_name.begins_with("SWITCH_"):
		var parts := case_name.split("_")
		var action := parts[1]
		var old_command := TerrainArmy.Command.MOVE_TO_EDGE if parts[2] == "EF" else TerrainArmy.Command.FOLLOW_PLAYER
		var next_command := TerrainArmy.Command.FOLLOW_PLAYER if parts[2] == "EF" else TerrainArmy.Command.MOVE_TO_EDGE
		army.command = old_command
		var changed: Array[int] = []
		if action == "MOVE":
			army.desired_cells[1] = Vector2i(10, 11)
			army._formation_slot_cells[1] = Vector2i(10, 11)
			passed = army._schedule_push_unit(1, Vector2i(10, 11))
			changed = [1]
		elif action == "CAPTAIN":
			passed = army._begin_captain_swap(1)
			changed = [0, 1]
		elif action == "FOLLOWER":
			passed = army._begin_follower_swap(1, 2)
			changed = [1, 2]
		elif action == "PUSH":
			army._cell_owners.erase(army.cells[3])
			army.cells[3] = Vector2i(10, 12)
			army._cell_owners[army.cells[3]] = 3
			passed = army._queue_push_chain(1, [Vector2i(11, 10), Vector2i(12, 10)])
			changed = [2]
		if not _check(passed, "FIXTURE_INVALID command handoff action"):
			return false
		for unit: int in changed:
			army.move_progress[unit] = 0.5
		var cells_before := army.cells.duplicate()
		var destinations := army.moving_to.duplicate()
		var old_epoch := army._command_epoch
		army.issue_command(next_command)
		# Coalesce another two button presses into the latest request.
		army.issue_command(old_command)
		army.issue_command(next_command)
		passed = _check(army._command_epoch == old_epoch and army.cells == cells_before, "switch activated before old movement commit")
		for unit: int in changed:
			passed = passed and _check(army.moving_to[unit] == destinations[unit] and army.move_progress[unit] == 0.5 and army._reserved_cells.get(destinations[unit], -1) == unit, "switch reset interpolation or dropped active claim")
		for frame: int in range(60):
			army.advance_frame(1.0 / 60.0)
			if army._command_epoch != old_epoch:
				break
		for unit: int in changed:
			passed = passed and _check(army.cells[unit] == destinations[unit], "switch failed original edge's atomic commit")
		passed = passed and _check(army.command == next_command and army._pending_command < 0 and army._command_epoch > old_epoch and army._pending_pushes.is_empty() and army._reserved_cells.is_empty() and army._push_lock.count(1) == 0, "switch lost latest request or leaked old transaction")
		print("COMMAND_HANDOFF action=%s old=%s new=%s epoch=%s -> %s committed_units=%s" % [action, old_command, next_command, old_epoch, army._command_epoch, changed])
		army.clear()
		army.free()
		npc.free()
		player.free()
		return passed
	match case_name:
		"Q03_DIRECTION":
			army._passage_active = true
			army._passage_descriptors = [{"entry": Vector2i(9, 10), "core": [Vector2i(10, 10), Vector2i(11, 10)], "exit": Vector2i(12, 10), "corridor": [Vector2i(9, 10), Vector2i(10, 10), Vector2i(11, 10), Vector2i(12, 10)], "protected": [Vector2i(9, 10), Vector2i(10, 10), Vector2i(11, 10)]}]
			for unit: int in [1, 2]:
				army._unit_passage[unit] = 0
				army._unit_passage_phase[unit] = TerrainArmy.PassagePhase.IN_PASSAGE
			passed = _check(not army._begin_captain_swap(1) and not army._begin_follower_swap(1, 2) and army._reserved_cells.is_empty(), "Q03 swap bypassed forward-only core edges")
		"M02":
			army._passage_active = true
			# This fixture is explicitly a two-gate continuous group, not a
			# completed first-group rally waiting to republish its next targets.
			army._passage_group_start = 0
			army._passage_group_end = 1
			army._passage_descriptors = [{"entry": Vector2i(7, 10), "core": [Vector2i(8, 10)], "exit": Vector2i(9, 10), "corridor": [Vector2i(7, 10), Vector2i(8, 10), Vector2i(9, 10)], "protected": [Vector2i(7, 10), Vector2i(8, 10)]}, {"entry": Vector2i(10, 10), "core": [Vector2i(11, 10)], "exit": Vector2i(12, 10), "corridor": [Vector2i(10, 10), Vector2i(11, 10), Vector2i(12, 10)], "protected": [Vector2i(10, 10), Vector2i(11, 10)]}]
			army._passage_crossings.resize(2)
			army._passage_clearings.resize(2)
			army._passage_service_owner = PackedInt32Array([-1, 2])
			army._unit_passage[1] = 0
			army._unit_passage[2] = 1
			army._unit_passage_phase[1] = TerrainArmy.PassagePhase.EXIT_CLEAR
			army._unit_passage_exit_clear[1] = 1
			army._unit_completed_exits[1] = 1
			army._unit_passage_ticket[1] = 0
			army._passage_ticket_order = [1, 2]
			army._unit_passage_phase[2] = TerrainArmy.PassagePhase.IN_PASSAGE
			army._unit_passage_crossed[2] = 1
			army._unit_completed_exits[2] = 1
			army._cell_owners.erase(army.cells[3])
			army.cells[3] = Vector2i(10, 12)
			army._cell_owners[army.cells[3]] = 3
			var binding := army.desired_cells[1]
			passed = _check(army._next_passage_step(1) == TerrainArmy.INVALID_CELL and army._unit_passage[1] == 0 and army._unit_completed_exits[1] == 1 and army.desired_cells[1] == binding and army._passage_crossings[1] == 0, "M02 occupied next core skipped admission or changed final binding")
			passed = passed and _check(army._schedule_push_unit(2, Vector2i(12, 10), 1), "M02 core occupant could not leave")
			army._complete_move(2)
			passed = passed and _check(army._next_passage_step(1) == Vector2i(11, 10) and army._unit_passage[1] == 0 and army._passage_crossings[1] == 0, "M02 did not reopen actual freed capacity")
		"X01":
			army._cell_owners.erase(army.cells[0])
			army.cells[0] = Vector2i(0, 10)
			army._cell_owners[army.cells[0]] = 0
			army.desired_cells[0] = army.cells[0]
			army.command = TerrainArmy.Command.MOVE_TO_EDGE
			army._passage_active = true
			army._passage_descriptors = [{"protected": [Vector2i(9, 10)]}]
			army._passage_final_slots.assign(army.cells.slice(1))
			army._passage_final_slots[10] = Vector2i(10, 11)
			for slot: Vector2i in army._passage_final_slots:
				army._passage_final_component[slot] = 1
			army._passage_slot_capacity = 99
			army._exit_rally_slots.clear()
			army._exit_rally_assigned = true
			army._unit_passage[1] = 0
			army._unit_passage_phase[1] = TerrainArmy.PassagePhase.EXIT_CLEAR
			passed = _check(army._push_endpoint_allowed(Vector2i(10, 11)) and army._schedule_push_unit(1, Vector2i(10, 11), 1) and not army._push_endpoint_allowed(Vector2i(9, 10)), "X01 legacy empty slot view vetoed the published final egress")
		"Q06_TRAIL_CACHE":
			army._captain_trail = [Vector2i(9, 10), Vector2i(10, 10), Vector2i(11, 10)]
			army._captain_trail_progress_cache.clear()
			passed = _check(army._captain_trail_progress(Vector2i(10, 10)) == 1 and army._captain_trail_progress_cache.get(Vector2i(10, 10), -1) == 1, "Q06 exact trail hits bypass the existing cache")
		"Q06_ENCLOSED_GOAL":
			var goal := Vector2i(10, 12)
			for direction: Vector2i in TerrainData.DIRECTIONS:
				army._reserved_cells[goal + direction] = 20
			army._local_path_requests_remaining = 4
			var before := army.local_search_expansions
			passed = _check(army._find_passage_route(army.cells[1], goal, 1).is_empty() and army.local_search_expansions == before, "Q06 no legal final edge still searched the whole platform")
			army._reserved_cells.erase(Vector2i(10, 11))
			army._passage_tick += 1
			army._local_path_requests_remaining = 4
			passed = passed and _check(not army._find_passage_route(army.cells[1], goal, 1).is_empty(), "Q06 opening a final edge did not restore a free route")
		"Q06_BLOCKED_GOAL":
			var entry := Vector2i(10, 12)
			army._reserved_cells[entry] = 20
			army._local_path_requests_remaining = 4
			var expansions_before := army.local_search_expansions
			var route := army._find_passage_route(army.cells[1], entry, 1, true)
			passed = _check(route.is_empty() and army.local_search_expansions == expansions_before, "Q06 impossible claimed goal searched the entire reachable platform")
			army._reserved_cells.erase(entry)
			army._passage_tick += 1
			army._local_path_requests_remaining = 4
			passed = passed and _check(not army._find_passage_route(army.cells[1], entry, 1, true).is_empty(), "Q06 released goal did not become searchable again")
		"Q05_TRANSIT", "Q05_SHARED_GOAL", "Q05_GOAL", "Q05_DETOUR":
			army._passage_active = true
			army._passage_descriptors = [{"protected": []}]
			army._unit_passage_phase[1] = TerrainArmy.PassagePhase.EXIT_CLEAR
			army._unit_passage[1] = 0
			army._unit_completed_exits[1] = 1
			army._passage_final_slots = [Vector2i(11, 10), Vector2i(14, 10)]
			for x: int in range(10, 15):
				army._passage_final_component[Vector2i(x, 10)] = x - 10
			army._local_path_requests_remaining = 4
			if case_name == "Q05_DETOUR":
				army.desired_cells[1] = Vector2i(14, 10)
				army._unit_passage_exit_clear[1] = 1
				army._passage_final_routes[Vector2i(14, 10)] = [Vector2i(10, 10), Vector2i(10, 9), Vector2i(11, 9), Vector2i(12, 9), Vector2i(13, 9), Vector2i(14, 9), Vector2i(14, 10)]
				army._follower_routes[1] = [Vector2i(10, 10), Vector2i(10, 11), Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(14, 10)]
				army._follower_route_goals[1] = Vector2i(14, 10)
				army._follower_route_cursors[1] = 1
				passed = _check(army._passage_step_to_goal(1, Vector2i(14, 10)) == Vector2i(10, 11), "Q05 shared shortcut overwrote a live detour and caused a two-cell oscillation")
			elif case_name == "Q05_GOAL":
				army.desired_cells[1] = Vector2i(11, 10)
				passed = _check(army._passage_step_to_goal(1, Vector2i(11, 10)) == Vector2i(11, 10), "Q05 a successful route to an occupied goal never produced a push intent")
			else:
				army._reserved_cells[Vector2i(14, 10) if case_name == "Q05_SHARED_GOAL" else Vector2i(13, 10)] = 20
				var route := army._find_passage_route(Vector2i(10, 10), Vector2i(14, 10), 1, true)
				passed = _check(route == [Vector2i(10, 10), Vector2i(11, 10), Vector2i(12, 10), Vector2i(13, 10), Vector2i(14, 10)], "Q05 prospective route treated a future empty slot as an already-settled owner")
		"Q01":
			terrain.allocate(Vector2i(8, 4))
			terrain.flags.fill(TerrainData.Flag.BLOCKED)
			for x: int in range(1, 5):
				terrain.flags[terrain.index(Vector2i(x, 1))] = TerrainData.Flag.WALKABLE
			terrain.flags[terrain.index(Vector2i(7, 1))] = TerrainData.Flag.WALKABLE
			army.cells[0] = Vector2i(7, 1)
			army.cells[1] = Vector2i(1, 1)
			army.cells[2] = Vector2i(2, 1)
			army._cell_owners = {army.cells[0]: 0, army.cells[1]: 1, army.cells[2]: 2}
			army.command = TerrainArmy.Command.MOVE_TO_EDGE
			army._exit_rally_assigned = true
			army._exit_rally_slots = [Vector2i(4, 1)]
			army._push_searches_remaining = 1
			passed = _check(army._find_push_chain(Vector2i(2, 1), 1).is_empty() and army._reserved_cells.is_empty(), "Q01 crossed empty intermediate")
		"Q02", "Q04", "Q05":
			var blockers := 19 if case_name == "Q04" else (1 if case_name == "Q05" else 3)
			var tail := Vector2i(11 + blockers, 10)
			if army._cell_owners.has(tail):
				var displaced := int(army._cell_owners[tail])
				army._cell_owners.erase(tail)
				army.cells[displaced] = Vector2i(10, 12)
				army.desired_cells[displaced] = army.cells[displaced]
				army._cell_owners[army.cells[displaced]] = displaced
			var chain: Array[Vector2i] = []
			for x: int in range(11, 12 + blockers):
				chain.append(Vector2i(x, 10))
			if not _check(army._queue_push_chain(1, chain), "%s queue rejected" % case_name):
				return false
			var order: Array[int] = []
			var previous := army.cells.duplicate()
			for tick: int in range(120):
				# Exercise real move/transaction owners without unrelated command planning.
				army._passage_tick += 1
				for unit: int in range(100):
					if army.movement_state[unit] == TerrainArmy.UnitState.MOVING:
						army.move_progress[unit] += 0.1 / army.move_duration[unit]
						if army.move_progress[unit] >= 1.0:
							army._complete_move(unit)
				army._advance_pending_pushes()
				for unit: int in range(1, blockers + 2):
					if army.cells[unit] != previous[unit]:
						if not _check(terrain.can_step(previous[unit], army.cells[unit]), "%s illegal commit" % case_name):
							return false
						order.append(unit)
						previous[unit] = army.cells[unit]
				if army.cells[1] != chain[0]:
					if not _check(army._reserved_cells.get(chain[0], -1) == 1 and not army._schedule_push_unit(20, chain[0]), "%s requester claim stolen" % case_name):
						return false
				if army._pending_pushes.is_empty():
					break
			var expected: Array[int] = []
			for unit: int in range(blockers + 1, 0, -1):
				expected.append(unit)
			passed = _check(order == expected and army._reserved_cells.is_empty() and army._push_lock.count(1) == 0, "%s requester last actual=%s expected=%s" % [case_name, order, expected])
			print("%s transaction_ticks=%s commit_order=%s" % [case_name, army._passage_tick, order])
		"Q02_ENV", "Q04_CANCEL":
			army._cell_owners.erase(Vector2i(12, 10))
			army.cells[3] = Vector2i(10, 12)
			army._cell_owners[army.cells[3]] = 3
			var chain: Array[Vector2i] = [Vector2i(11, 10), Vector2i(12, 10)]
			if case_name == "Q02_ENV":
				army._reserved_cells[Vector2i(12, 10)] = 20
				var claims := army._reserved_cells.duplicate()
				var owners := army._cell_owners.duplicate()
				passed = _check(not army._queue_push_chain(1, chain) and army._reserved_cells == claims and army._cell_owners == owners and army._push_lock.count(1) == 0, "Q02 environment change partially committed")
			else:
				if not _check(army._queue_push_chain(1, chain), "Q04 cancel queue"):
					return false
				army.move_progress[2] = 0.5
				for tick: int in range(41):
					army._advance_pending_pushes()
				passed = _check(army._pending_pushes.is_empty() and army.cells[2] == Vector2i(11, 10) and army.move_progress[2] == 0.5 and army._reserved_cells == {Vector2i(12, 10): 2}, "Q04 timeout cancelled active edge or retained unstarted claim")
				army._complete_move(2)
				passed = passed and _check(army.cells[2] == Vector2i(12, 10) and army._reserved_cells.is_empty() and army._push_lock.count(1) == 0, "Q04 cancelled active tail failed commit")
		"Q03_LOCK":
			army._push_lock[1] = 1
			if not _check(not army._schedule_push_unit(1, Vector2i(10, 11)), "Q03 direct push scheduling ignored a foreign lock"):
				return false
			army._push_lock[1] = 0
			passed = true
			for captain: bool in [true, false]:
				var first := 0 if captain else 1
				var second := 1 if captain else 2
				for locked: int in [first, second]:
					army._push_lock[locked] = 1
					var accepted := army._begin_captain_swap(second) if captain else army._begin_follower_swap(first, second)
					passed = passed and _check(not accepted and army._reserved_cells.is_empty(), "Q03 swap ignored lock")
					army._push_lock[locked] = 0
				army.movement_state[second] = TerrainArmy.UnitState.MOVING
				var accepted := army._begin_captain_swap(second) if captain else army._begin_follower_swap(first, second)
				passed = passed and _check(not accepted and army._reserved_cells.is_empty(), "Q03 moving partner accepted")
				army.movement_state[second] = TerrainArmy.UnitState.IDLE
		"Q03_OWNER":
			army._cell_owners[army.cells[1]] = 77
			passed = _check(not army._begin_captain_swap(1) and not army._begin_follower_swap(1, 2) and army._reserved_cells.is_empty(), "Q03 begin-swap accepted stale source ownership")
		"F02":
			passed = true
			for count: int in [2, 3]:
				army.desired_cells.assign(army.cells)
				for unit: int in range(1, count + 1):
					army.desired_cells[unit] = army.cells[unit % count + 1]
				army._formation_slot_cells.assign(army.desired_cells)
				var slots := army.desired_cells.duplicate()
				var physical := army.cells.duplicate()
				army.movement_state[10] = TerrainArmy.UnitState.MOVING
				army.moving_to[10] = Vector2i(19, 11)
				army._reserved_cells[Vector2i(19, 11)] = 10
				army._repair_idle_slot_bindings()
				for unit: int in range(1, count + 1):
					passed = passed and _check(army.desired_cells[unit] == physical[unit], "F02 cycle not repaired")
				slots.sort()
				var result := army.desired_cells.duplicate()
				result.sort()
				passed = passed and _check(result == slots and army.cells == physical and army._reserved_cells == {Vector2i(19, 11): 10}, "F02 changed slots/physical/unrelated claim")
		_:
			push_error("Unknown contract: %s" % case_name)
	army.free()
	npc.free()
	player.free()
	return passed
