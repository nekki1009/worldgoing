extends SceneTree

## Formal replay of the shipped TERRACED_HIGHLAND EDGE case. The route and
## height-transition oracle are computed here instead of reading passage
## counters from TerrainArmy.

const SEED := 12345
const INPUT_FRAMES := 10800 # 180 input seconds at 60 Hz.
const STABLE_FRAMES := 300 # Five seconds after completion.
const EXPECTED_GOAL := Vector2i(99, 75)
const EXPECTED_GATES: Array[Array] = [
	[Vector2i(66, 52), Vector2i(66, 53)],
	[Vector2i(33, 50), Vector2i(33, 49)],
	[Vector2i(54, 25), Vector2i(54, 24)],
	[Vector2i(50, 74), Vector2i(50, 75)],
	[Vector2i(78, 74), Vector2i(78, 75)],
]

var _gate_local_best := {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--generated="):
			var parts := argument.trim_prefix("--generated=").split(",")
			var passed := _generated(TerrainPreset.Kind.ROCKY_HIGHLAND if parts[0] == "rocky" else TerrainPreset.Kind.TERRACED_HIGHLAND, int(parts[1]), parts[2] == "follow")
			quit(0 if passed else 1)
			return
	var hz := 30 if OS.get_cmdline_user_args().has("--30hz") else 60
	var alternating := OS.get_cmdline_user_args().has("--alternating")
	var frame_limit := 180 * hz
	var stable_limit := 5 * hz
	var terrain := TerrainGenerator.generate(TerrainPreset.Kind.TERRACED_HIGHLAND, SEED)
	if not _check(terrain.fingerprint() == "c8a3021229df7f5f4324c39ee75fada205999efd74ec4f2cb13b481f12bc3367", "default terrain changed"):
		quit(1)
		return
	var player := TerrainTestCharacter.new()
	var npc := TerrainTestNPC.new()
	player.data = terrain
	npc.set_data(terrain)
	var lab := TerrainLab.new()
	lab.terrain = terrain
	var npc_spawn := lab._find_npc_spawn_cell()
	lab.free()
	if not _check(player.place(terrain.spawn_cell, true), "default EDGE player placement failed"):
		quit(1)
		return
	if not _check(npc.place(npc_spawn, true), "default EDGE NPC placement failed"):
		quit(1)
		return
	npc.issue_command(TerrainTestNPC.Command.STOP)
	var army := TerrainArmy.new()
	army.set_process(false)
	player.cell_blocker = Callable(army, "blocks_cell")
	npc.cell_blocker = Callable(army, "blocks_cell")
	if not _check(army.deploy(terrain, player, npc), "default EDGE deploy failed: %s" % army.command_status):
		quit(1)
		return
	if not _check(army.issue_command(TerrainArmy.Command.MOVE_TO_EDGE), "default EDGE command failed: %s" % army.command_status):
		quit(1)
		return

	var captain_route := _independent_route(terrain, army.cells[0], EXPECTED_GOAL)
	if not _check(captain_route.size() > 1, "default EDGE independent captain route is missing"):
		quit(1)
		return
	var gates := _route_gates(terrain, captain_route)
	# Declared before simulation: route travel + each gate's 100-person flow
	# + initial/intermediate receiving work. V5's 180 s remains a comparison.
	var declared_seconds := ceili(0.30 * float(captain_route.size() - 1) + 0.60 * 99.0 * float(gates.size()) + 20.0 * float(gates.size() + 1)) + 10
	frame_limit = declared_seconds * hz
	print("D01 V6_BUDGET seconds=", declared_seconds, " route_edges=", captain_route.size() - 1, " gate_groups=", gates.size(), " V5_reference=180")
	if not _check(gates == EXPECTED_GATES, "default EDGE gate oracle changed: %s" % str(gates)):
		quit(1)
		return
	for gate: Array in gates:
		var upstream := _flood(terrain, gate[0], gate)
		if not _check(not upstream.has(gate[1]), "D01 gate is not a true separator"):
			quit(1)
			return
		for unit: int in range(1, 100):
			if not _check(upstream.has(army.cells[unit]), "D01 initial follower was incorrectly exempted"):
				quit(1)
				return
	var final_component := _flood(terrain, gates.back()[1], gates.back())
	var layout_witness := _layout_witness(terrain, final_component, [player.terrain_cell, npc.terrain_cell, EXPECTED_GOAL, gates.back()[1]])
	if not _check(layout_witness.size() == 99, "FIXTURE_INVALID D01 independent downstream layout capacity"):
		quit(1)
		return
	print("D01 PREFLIGHT required_per_gate=[99,99,99,99,99] downstream_cells=", final_component.size(), " independent_layout=", layout_witness)
	var gate_waits: Array[float] = []
	gate_waits.resize(gates.size())
	var gate_counts := PackedInt32Array()
	gate_counts.resize(gates.size())
	var gate_seen := {}
	var clear_seen := {}
	var clear_counts := PackedInt32Array()
	clear_counts.resize(gates.size())
	var previous_cells: Array[Vector2i] = army.cells.duplicate()
	var completion_frame := -1
	var captain_steps := 0
	var published_slots: Array[Vector2i] = []
	var progress := PackedInt32Array()
	progress.resize(TerrainArmy.SOLDIER_COUNT)
	var clear_progress := PackedInt32Array()
	clear_progress.resize(TerrainArmy.SOLDIER_COUNT)
	var latest_commit_time := 0.0
	var physical_march_started := false
	var captain_order: Array[int] = []
	captain_order.resize(gates.size())
	var observed_rallies := {}
	print("D01 START source=%s goal=%s" % [FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"), army.desired_cells[0]])
	print("D01 INITIAL_CELLS=", army.cells, " fingerprint=", terrain.fingerprint())
	for frame: int in range(frame_limit):
		var delta := (1.0 / 120.0 if frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz)
		var structure_before := army.structure_search_expansions
		var local_before := army.local_search_expansions
		var push_before := army.push_search_expansions
		var steps_before := army.completed_steps()
		var sim_before := army.simulated_seconds
		army.advance_frame(delta)
		if army.completed_steps() != steps_before:
			physical_march_started = true
			latest_commit_time = army.input_seconds
		elif not physical_march_started and (army._command_goal_pending or army._passage_plan_pending or army._formation_target_pending):
			# Only the initial bounded plan is exempt. Later guide rebuilding
			# cannot refresh a no-physical-progress clock.
			latest_commit_time = army.input_seconds
		elif not army.is_formation_complete() and army.input_seconds - latest_commit_time >= 5.0:
			var layouts := []
			for descriptor: Dictionary in army._passage_descriptors:
				layouts.append([descriptor.entry, descriptor.exit, descriptor.get("rally_layout", []).size(), descriptor.get("rally_completed_tick", -1)])
			print("D01 STALL macro=", army._formation_march_active, " group=", [army._passage_group_start, army._passage_group_end], " layouts=", layouts, " anchor=", army._formation_anchor_cell, " target0=", army.desired_cells[0], " phases=", army._unit_passage_phase, " failure=", army._passage_failure_reason)
			print("D01 STALL_CELLS=", army.cells, " targets=", army.desired_cells, " bend_steps=", army.formation_bend_steps)
			var predecessors := []
			for unit: int in range(100):
				if army._unit_passage_ticket[unit] <= army._unit_passage_ticket[0] and army._unit_passage_phase[unit] == TerrainArmy.PassagePhase.APPROACH:
					predecessors.append([unit, army._unit_passage_ticket[unit], army.cells[unit], army._follower_routes.get(unit, []), army._follower_route_cursors.get(unit, -1), army.blocked_time[unit]])
			print("D01 STALL_PREDECESSORS=", predecessors, " captain_ticket=", army._unit_passage_ticket[0], " claims=", army._reserved_cells, " pushes=", army._pending_pushes)
			if army._formation_march_active and not army._formation_bend_field.is_empty() and army.moving_count() == 0:
				var snapshot_path := "res://.godot-temp/d01_bend_" + FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd").left(12) + ".bin"
				var snapshot_file := FileAccess.open(snapshot_path, FileAccess.WRITE)
				snapshot_file.store_var({"cells": army.cells, "field": army._formation_bend_field, "lateral": army._formation_bend_lateral, "span": army._formation_bend_span, "heading": army._formation_heading, "group": army._passage_group_start, "input_seconds": army.input_seconds, "source": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd")})
				snapshot_file.close()
				print("D01 BEND_SNAPSHOT=", snapshot_path)
			push_error("D01 five seconds without a physical commit")
			army.clear()
			army.free()
			npc.free()
			player.free()
			quit(1)
			return
		if army.structure_search_expansions - structure_before > 256 \
			or army.local_search_expansions - local_before > 8192 \
			or army.push_search_expansions - push_before > 1024:
			push_error("D01 shared per-frame navigation budget exceeded: structure=%s local=%s push=%s" % [army.structure_search_expansions - structure_before, army.local_search_expansions - local_before, army.push_search_expansions - push_before])
			quit(1)
			return
		if not army._command_goal_pending and army._march_goal != EXPECTED_GOAL:
			push_error("default EDGE selected an unexpected front goal: %s" % army._march_goal)
			quit(1)
			return
		if not _legal_state(army, terrain):
			quit(1)
			return
		if army.passage_active():
			if "--inspect-layouts" in OS.get_cmdline_user_args():
				for group: int in range(army._passage_descriptors.size()):
					var descriptor: Dictionary = army._passage_descriptors[group]
					print("D01_LAYOUT group=", group, " component_cells=", descriptor.rally_component.size(), " layout=", descriptor.rally_layout, " component=", descriptor.rally_component.keys())
				army.clear()
				army.free()
				npc.free()
				player.free()
				quit(0)
				return
			if published_slots.is_empty():
				published_slots = army._passage_final_slots.duplicate()
				if not _slot_set_valid(army, terrain, published_slots, final_component):
					quit(1)
					return
				var bounds := Rect2i(published_slots[0], Vector2i.ONE)
				for slot: Vector2i in published_slots:
					bounds = bounds.merge(Rect2i(slot, Vector2i.ONE))
				if not _check(bounds.size.x <= 10 and bounds.size.y <= 10, "final layout exceeds ten columns/ranks"):
					quit(1)
					return
			if not _check(army._passage_final_slots == published_slots, "published slot set changed"):
				quit(1)
				return
		for index: int in range(TerrainArmy.SOLDIER_COUNT):
			if previous_cells[index] != army.cells[index]:
				if not _check(terrain.can_step(previous_cells[index], army.cells[index]), "illegal committed edge for %d" % index):
					quit(1)
					return
				if index == 0:
					captain_steps += 1
		for index: int in range(TerrainArmy.SOLDIER_COUNT):
			for gate_index: int in range(gates.size()):
				if not _check(not (previous_cells[index] == gates[gate_index][1] and army.cells[index] == gates[gate_index][0]), "reverse gate crossing"):
					quit(1)
					return
				if previous_cells[index] == gates[gate_index][0] and army.cells[index] == gates[gate_index][1]:
					if not _check(progress[index] == gate_index, "gate order mismatch"):
						quit(1)
						return
					progress[index] += 1
					var crossing_key := Vector2i(gate_index, index)
					if gate_seen.has(crossing_key):
						push_error("default EDGE follower %d recrossed gate %d" % [index, gate_index])
						quit(1)
						return
					gate_seen[crossing_key] = true
					if index == 0:
						captain_order[gate_index] = gate_counts[gate_index] + 1
						if not _check(captain_order[gate_index] >= 21 and captain_order[gate_index] <= 71, "captain was not protected by front ranks at gate %d" % gate_index):
							quit(1)
							return
					else:
						gate_counts[gate_index] += 1
				if previous_cells[index] == gates[gate_index][1] and army.cells[index] != previous_cells[index] and army.cells[index] != gates[gate_index][0]:
					var clearing_key := Vector2i(gate_index, index)
					if not _check(progress[index] == gate_index + 1 and clear_progress[index] == gate_index and not clear_seen.has(clearing_key), "physical core clearance occurred out of order"):
						quit(1)
						return
					clear_seen[clearing_key] = true
					clear_counts[gate_index] += int(index > 0)
					clear_progress[index] += 1
			if not _check(army._unit_completed_exits[index] <= clear_progress[index], "runtime completed an exit before the physical core was vacated"):
				quit(1)
				return
		for group: int in range(army._passage_descriptors.size()):
			var descriptor: Dictionary = army._passage_descriptors[group]
			if observed_rallies.has(group) or int(descriptor.get("rally_completed_tick", -1)) < 0:
				continue
			var actual := {}
			for cell: Vector2i in army.cells:
				actual[cell] = true
			var reachable := {army.cells[0]: true}
			var pending: Array[Vector2i] = [army.cells[0]]
			var cursor := 0
			while cursor < pending.size():
				var current := pending[cursor]
				cursor += 1
				for direction: Vector2i in TerrainData.DIRECTIONS:
					var next := current + direction
					if actual.has(next) and not reachable.has(next) and terrain.can_step(current, next):
						reachable[next] = true
						pending.append(next)
			if not _check(reachable.size() == 100 and clear_counts[group] == 99 and clear_progress[0] > group, "intermediate rally lacks a physically connected complete 100-person body"):
				quit(1)
				return
			observed_rallies[group] = army.input_seconds
			print("D01 RALLY_WITNESS group=", group, " time=", army.input_seconds, " physical_layout=", army.cells)
		if army.simulated_seconds > sim_before and not _gate_progress(army, gates, previous_cells, gate_waits, army.simulated_seconds - sim_before):
			quit(1)
			return
		previous_cells = army.cells.duplicate()
		if (frame + 1) % (10 * hz) == 0:
			print("D01 t=%.1f captain=%s gates=%s assembled=%d summary=%s bend_steps=%d structure=%d" % [army.input_seconds, army.cells[0], gate_counts, army.formation_count(), army.passage_summary(), army.formation_bend_steps, army.structure_search_expansions])
			if ("--inspect-tail" in OS.get_cmdline_user_args() or "--inspect-gate2" in OS.get_cmdline_user_args()) and not army._formation_march_active and army._passage_group_start < gates.size():
				var group := army._passage_group_start
				if gate_counts[group] >= 85 or (group == 1 and army.input_seconds >= 160.0):
					var tail := []
					var approach: Dictionary = army._passage_descriptor(group).get("approach_component", {})
					for unit: int in range(100):
						if army.cells[unit] != army.desired_cells[unit]:
							tail.append([unit, army.cells[unit], army.desired_cells[unit], army._unit_passage_phase[unit], army.movement_state[unit], army._push_lock[unit], army.blocked_time[unit], approach.get(army.cells[unit], -1), army._follower_routes.get(unit, []), army._follower_route_cursors.get(unit, -1)])
					print("D01 TAIL group=", group, " units=", tail, " pushes=", army._pending_pushes)
					if "--inspect-gate2" in OS.get_cmdline_user_args() and group == 1:
						print("D01 DIAGNOSTIC_ONLY tickets=", army._unit_passage_ticket, " captain_ticket=", army._unit_passage_ticket[0])
						army.clear()
						army.free()
						npc.free()
						player.free()
						quit(0)
						return
		if completion_frame < 0 and not army.passage_active() and army.is_formation_complete():
			completion_frame = frame + 1
			break

	if completion_frame <= 0 or completion_frame > frame_limit:
		for unit: int in range(1, 100):
			if army.cells[unit] != army.desired_cells[unit]:
				print("D01 UNSETTLED unit=%d cell=%s goal=%s phase=%d state=%d lock=%d retry=%s route=%s" % [unit, army.cells[unit], army.desired_cells[unit], army._unit_passage_phase[unit], army.movement_state[unit], army._push_lock[unit], army._local_occupied_retry.get(unit), army._follower_routes.get(unit)])
		print("D01 CLAIMS=%s PENDING=%s" % [army._reserved_cells, army._pending_pushes])
		push_error("default EDGE missed declared %d-second deadline: frame=%d status=%s assembled=%d" % [declared_seconds, completion_frame, army.command_status, army.formation_count()])
		quit(1)
		return
	if not _check(army.cells.has(EXPECTED_GOAL) and army.cells[0] != EXPECTED_GOAL and army.cells[0] == army._passage_final_captain_slot, "front did not reach edge with captain in its protected slot"):
		quit(1)
		return
	if not _check(progress[0] == gates.size() and clear_progress[0] == gates.size() and observed_rallies.size() == gates.size(), "captain or an intermediate full-team rally was skipped"):
		quit(1)
		return
	for gate_index: int in range(gate_counts.size()):
		if not _check(gate_counts[gate_index] == TerrainArmy.SOLDIER_COUNT - 1, "default EDGE gate %d crossings are short: %s" % [gate_index, gate_counts]):
			quit(1)
			return
		if not _check(clear_counts[gate_index] == 99 and army._passage_crossings[gate_index] == 99 and army._passage_clearings[gate_index] == 99, "physical and runtime per-gate counts disagree"):
			quit(1)
			return
	var settled_cells: Array[Vector2i] = army.cells.duplicate()
	if not _check(published_slots.size() == 99, "missing published slots"):
		quit(1)
		return
	for index: int in range(1, TerrainArmy.SOLDIER_COUNT):
		if not _check(published_slots.has(army.cells[index]) and army.cells[index] == army.desired_cells[index], "unit outside its final binding"):
			quit(1)
			return
	var settled_targets: Array[Vector2i] = army.desired_cells.duplicate()
	for _stable_frame: int in range(stable_limit):
		var delta := (1.0 / 120.0 if _stable_frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz)
		army.advance_frame(delta)
		if not _legal_state(army, terrain):
			quit(1)
			return
		if not _check(army.cells == settled_cells, "default EDGE moved after completion"):
			quit(1)
			return
		if not _check(army.desired_cells == settled_targets, "default EDGE changed final bindings after completion"):
			quit(1)
			return
	if not _check(army.moving_count() == 0 and army._pending_pushes.is_empty() and army._reserved_cells.is_empty(), "default EDGE left active claims after stability window"):
		quit(1)
		return
	for lock: int in army._push_lock:
		if not _check(lock == 0, "default EDGE leaked a push lock"):
			quit(1)
			return
	if not _check(army.max_passage_expansions <= TerrainArmy.PASSAGE_EGRESS_EXPANSIONS, "passage search exceeded original cap"):
		quit(1)
		return
	if not _check(army.dropped_seconds == 0.0, "normal frame sequence dropped simulation time"):
		quit(1)
		return
	print("ARMY_DEFAULT_EDGE_V6_PASS: hz=%d alternating=%s complete_seconds=%.3f gate_crossings=%s clearings=%s captain_orders=%s rallies=%s stable_frames=%d goal=%s max_frame_structure=%d max_frame_local=%d max_frame_push=%d input=%.3f simulated=%.3f dropped=%.3f source=%s" % [hz, alternating, float(completion_frame) / hz, gate_counts, clear_counts, captain_order, observed_rallies, stable_limit, EXPECTED_GOAL, army.max_frame_structure_expansions, army.max_frame_local_expansions, army.max_frame_push_expansions, army.input_seconds, army.simulated_seconds, army.dropped_seconds, FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd")])
	army.free()
	npc.free()
	player.free()
	quit(0)

static func _independent_route(data: TerrainData, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	if not data.contains(start) or not data.contains(goal):
		return route
	var pending: Array[Vector2i] = [start]
	var previous := {start: TerrainArmy.INVALID_CELL}
	var head := 0
	while head < pending.size():
		var current: Vector2i = pending[head]
		head += 1
		if current == goal:
			break
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if previous.has(next) or not data.contains(next) or not data.can_step(current, next):
				continue
			previous[next] = current
			pending.append(next)
	if not previous.has(goal):
		return route
	var cursor := goal
	while cursor != TerrainArmy.INVALID_CELL:
		route.push_front(cursor)
		cursor = previous[cursor]
	return route

static func _route_gates(data: TerrainData, route: Array[Vector2i]) -> Array[Array]:
	var gates: Array[Array] = []
	for route_index: int in range(route.size() - 1):
		var from: Vector2i = route[route_index]
		var to: Vector2i = route[route_index + 1]
		if data.height_levels[data.index(from)] != data.height_levels[data.index(to)]:
			gates.append([from, to])
	return gates

static func _legal_state(army: TerrainArmy, terrain: TerrainData) -> bool:
	if not _check(army.cells.size() == 100 and army._cell_owners.size() == 100, "authoritative owner table is not exactly 100 members"):
		return false
	var seen := {}
	var claimed := {}
	var locked := {}
	for pending: Dictionary in army._pending_pushes:
		var path: Array = pending.cells
		var units: Array = pending.units
		claimed[path[0]] = int(pending.requester)
		locked[int(pending.requester)] = true
		for offset: int in range(units.size()):
			if pending.get("committed", {}).has(int(units[offset])):
				continue
			locked[int(units[offset])] = true
			claimed[path[offset + 1]] = int(units[offset])
	for index: int in range(TerrainArmy.SOLDIER_COUNT):
		if army.movement_state[index] == TerrainArmy.UnitState.MOVING or army.movement_state[index] == TerrainArmy.UnitState.SWAPPING:
			if not _check(army._reserved_cells.get(army.moving_to[index], -1) == index, "moving unit lost destination claim"):
				return false
			claimed[army.moving_to[index]] = index
		if not _check(army._push_lock[index] == 0 or locked.has(index), "orphan push lock"):
			return false
	for destination: Vector2i in army._reserved_cells:
		if not _check(claimed.get(destination, -1) == army._reserved_cells[destination], "orphan reservation"):
			return false
	for index: int in range(TerrainArmy.SOLDIER_COUNT):
		var cell := army.cells[index]
		if not _check(not seen.has(cell), "default EDGE overlap at %s" % cell):
			return false
		seen[cell] = true
		if not _check(int(army._cell_owners.get(cell, -1)) == index, "cell owner mismatch"):
			return false
		if not _check(terrain.contains(cell) and terrain.is_walkable(cell), "default EDGE illegal cell %s" % cell):
			return false
		if not _check(cell != army.player.terrain_cell and cell != army.npc.terrain_cell, "default EDGE occupied an external cell %s" % cell):
			return false
	return true

static func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("D01 %s source=%s" % [message, FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd")])
	return condition


func _generated(preset: int, seed_value: int, follow: bool) -> bool:
	var hz := 30 if "--30hz" in OS.get_cmdline_user_args() else 60
	var alternating := "--alternating" in OS.get_cmdline_user_args()
	var terrain := TerrainGenerator.generate(preset as TerrainPreset.Kind, seed_value)
	var player := TerrainTestCharacter.new()
	var npc := TerrainTestNPC.new()
	player.data = terrain
	npc.set_data(terrain)
	var lab := TerrainLab.new()
	lab.terrain = terrain
	var npc_spawn := lab._find_npc_spawn_cell()
	lab.free()
	if not _check(player.place(terrain.spawn_cell, true) and npc.place(npc_spawn, true), "FIXTURE_INVALID generated actors"):
		return false
	var army := TerrainArmy.new()
	if not _check(army.deploy(terrain, player, npc), "FIXTURE_INVALID generated deploy"):
		return false
	army.set_process(false)
	player.cell_blocker = Callable(army, "blocks_cell")
	npc.cell_blocker = Callable(army, "blocks_cell")
	npc.issue_command(TerrainTestNPC.Command.STOP)
	var distances := _flood(terrain, army.cells[0])
	# FOLLOW uses the same independently nearest reachable boundary as EDGE
	# for PLAYER's destination; no seed replacement or production retargeting.
	var target := TerrainArmy.INVALID_CELL
	var shortest := 1 << 30
	for y: int in range(terrain.size.y):
		for x: int in range(terrain.size.x):
			var candidate := Vector2i(x, y)
			if x != 0 and y != 0 and x != terrain.size.x - 1 and y != terrain.size.y - 1:
				continue
			if distances.has(candidate) and int(distances[candidate]) < shortest and candidate != player.terrain_cell and candidate != npc.terrain_cell:
				target = candidate
				shortest = int(distances[candidate])
	if target == TerrainArmy.INVALID_CELL or distances.size() < 102:
		print("GENERATED_EXCLUDED preset=%s seed=%s follow=%s reachable=%s reason=NO_REACHABLE_GOAL_OR_TOTAL_CAPACITY" % [preset, seed_value, follow, distances.size()])
		army.free()
		npc.free()
		player.free()
		return true
	if follow and not _check(player.place(target, true), "FIXTURE_INVALID generated follow target"):
		return false
	if not _check(army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER if follow else TerrainArmy.Command.MOVE_TO_EDGE), "generated command"):
		return false
	var initial := army.cells.duplicate()
	var budget_route := _independent_route(terrain, initial[0], target)
	var budget_gates := _route_gates(terrain, budget_route).size()
	var declared_seconds := ceili(0.30 * float(budget_route.size() - 1) + 0.60 * 99.0 * float(budget_gates) + 20.0 * float(budget_gates + 1)) + 10
	print("GENERATED_V6_BUDGET seconds=", declared_seconds, " route_edges=", budget_route.size() - 1, " gates=", budget_gates, " V5_reference=180")
	print("GENERATED_START preset=%s seed=%s follow=%s fingerprint=%s target=%s terrain_reachable=%s source=%s INITIAL_CELLS=%s" % [preset, seed_value, follow, terrain.fingerprint(), target, distances.size(), FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"), initial])
	var goal := TerrainArmy.INVALID_CELL
	var revision := -1
	var expected_steps := -1
	var captain_steps := 0
	var gates: Array[Array] = []
	var required: Array[Dictionary] = []
	var crossed: Array[Dictionary] = []
	var cleared: Array[Dictionary] = []
	var previous := initial.duplicate()
	var complete_time := -1.0
	var stable := 0.0
	var frozen: Array[Vector2i] = []
	var published_slots: Array[Vector2i] = []
	var final_component := {}
	var gate_waits: Array[float] = []
	var observed_rallies := {}
	var latest_commit_time := 0.0
	var physical_march_started := false
	for frame: int in range((declared_seconds + 6) * hz):
		var delta := (1.0 / 120.0 if frame % 2 == 0 else 1.0 / 40.0) if alternating else 1.0 / float(hz)
		var steps_before := army.completed_steps()
		var sim_before := army.simulated_seconds
		army.advance_frame(delta)
		if army.completed_steps() != steps_before:
			physical_march_started = true
			latest_commit_time = army.input_seconds
		elif not physical_march_started and (army._command_goal_pending or army._passage_plan_pending or army._formation_target_pending):
			latest_commit_time = army.input_seconds
		elif not army.is_formation_complete() and army.input_seconds - latest_commit_time >= 5.0:
			print("GENERATED_STALL t=", army.input_seconds, " macro=", army._formation_march_active, " group=", army._passage_group_start, " failure=", army._passage_failure_reason, " cells=", army.cells)
			var last_descriptor := army._passage_descriptor(army._passage_descriptors.size() - 1)
			var stall_metrics := []
			for unit: int in range(100):
				stall_metrics.append([unit, army.cells[unit], army.desired_cells[unit], last_descriptor.get("goal_slot_component", {}).get(army.cells[unit], -1), army._formation_bend_field.get(army.cells[unit], -1)])
			print("GENERATED_STALL_DETAILS pending=", army._formation_target_pending, " bend=", army._formation_bend_active, " final=", army._formation_final_reform, " span=", army._formation_bend_span, " captain_final=", army._passage_final_captain_slot, " cohort=", army.formation_cohesion, " units=", stall_metrics)
			return _check(false, "generated five seconds without physical progress")
		if not _legal_state(army, terrain):
			return false
		if not _check(army.max_frame_structure_expansions <= 256 and army.max_frame_local_expansions <= 8192 and army.max_frame_push_expansions <= 1024, "generated frame budget"):
			return false
		if "--snapshot-bend" in OS.get_cmdline_user_args() and army._passage_group_start == 4 and army._formation_march_active \
			and not army._formation_bend_field.is_empty() and army.moving_count() == 0 and army.input_seconds >= 430.0:
			var path := "res://.godot-temp/generated_bend_" + str(seed_value) + ".bin"
			var capture := FileAccess.open(path, FileAccess.WRITE)
			capture.store_var({"cells": army.cells, "field": army._formation_bend_field, "lateral": army._formation_bend_lateral, "span": army._formation_bend_span, "heading": army._formation_heading, "group": army._passage_group_start, "input_seconds": army.input_seconds, "source": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd")})
			capture.close()
			print("GENERATED_DIAGNOSTIC_ONLY_BEND_SNAPSHOT=", path)
			army.clear()
			army.free()
			npc.free()
			player.free()
			return true
		if goal == TerrainArmy.INVALID_CELL and not army._command_goal_pending:
			goal = army._march_goal
			revision = army._path_route_snapshot_revision
			var route := _independent_route(terrain, initial[0], goal)
			expected_steps = route.size() - 1
			if not _check(expected_steps >= 0 and (follow or expected_steps == shortest), "generated goal is not nearest reachable boundary"):
				return false
			gates = _route_gates(terrain, route)
			for gate: Array in gates:
				var upstream := _flood(terrain, gate[0], gate)
				var downstream := _flood(terrain, gate[1], gate)
				var needed := {}
				if not upstream.has(gate[1]):
					for unit: int in range(100):
						if upstream.has(initial[unit]):
							needed[unit] = true
						elif not downstream.has(initial[unit]):
							push_error("FIXTURE_INVALID initial unit outside gate components")
							return false
				required.append(needed)
				crossed.append({})
				cleared.append({})
			gate_waits.resize(gates.size())
			final_component = _flood(terrain, goal) if gates.is_empty() else _flood(terrain, gates.back()[1], gates.back())
			var exclusions := [player.terrain_cell, npc.terrain_cell, goal]
			if not gates.is_empty():
				exclusions.append(gates.back()[1])
			var witness := _layout_witness(terrain, final_component, exclusions)
			if not _check(witness.size() == 99, "FIXTURE_INVALID generated independent downstream layout capacity"):
				return false
			print("GENERATED_CAPACITY_WITNESS downstream_cells=", final_component.size(), " independent_layout=", witness)
			print("GENERATED_ORACLE goal=%s route_edges=%s gates=%s required=%s" % [goal, expected_steps, gates, required.map(func(v: Dictionary) -> int: return v.size())])
		if goal != TerrainArmy.INVALID_CELL and not _check(army._march_goal == goal and army._path_route_snapshot_revision == revision, "C02 stable PLAYER changed goal/revision: %s/%d -> %s/%d" % [goal, revision, army._march_goal, army._path_route_snapshot_revision]):
			return false
		if army.passage_active() and published_slots.is_empty() and army._passage_final_slots.size() == 99:
			published_slots = army._passage_final_slots.duplicate()
			if not _slot_set_valid(army, terrain, published_slots, final_component, false):
				return false
			for slot: Vector2i in published_slots:
				for direction: Vector2i in TerrainData.DIRECTIONS:
					if published_slots.has(slot + direction) and not _check(terrain.can_step(slot, slot + direction), "generated layout crossed an internal cliff: %s -> %s" % [slot, slot + direction]):
						return false
		if not published_slots.is_empty() and not _check(army._passage_final_slots == published_slots, "generated final slot set changed"):
			return false
		for unit: int in range(100):
			if previous[unit] == army.cells[unit]:
				continue
			if "--trace-late" in OS.get_cmdline_user_args() and army.input_seconds >= 135.0:
				print("LATE_COMMIT t=%.2f unit=%s %s -> %s goal=%s phase=%s" % [army.input_seconds, unit, previous[unit], army.cells[unit], army.desired_cells[unit], army._unit_passage_phase[unit]])
			if not _check(terrain.can_step(previous[unit], army.cells[unit]), "generated illegal edge"):
				return false
			if unit == 0:
				captain_steps += 1
			for gate_index: int in range(gates.size()):
				var gate: Array = gates[gate_index]
				if previous[unit] == gate[0] and army.cells[unit] == gate[1]:
					if not _check(not crossed[gate_index].has(unit), "generated repeated crossing"):
						return false
					for earlier: int in range(gate_index):
						if required[earlier].has(unit) and not _check(cleared[earlier].has(unit), "generated mandatory gate order"):
							return false
					if unit == 0 and required[gate_index].size() == 100 and not _check(crossed[gate_index].size() >= 20 and crossed[gate_index].size() <= 70, "generated captain lost middle admission order"):
						return false
					crossed[gate_index][unit] = army.input_seconds
				if previous[unit] == gate[1] and army.cells[unit] != gate[0]:
					if crossed[gate_index].has(unit):
						cleared[gate_index][unit] = army.input_seconds
				if required[gate_index].has(unit) and previous[unit] == gate[1] and army.cells[unit] == gate[0]:
					push_error("generated reverse mandatory gate t=%s unit=%s gate=%s edge=%s->%s goal=%s phase=%s macro=%s final=%s pushes=%s" % [army.input_seconds, unit, gate_index, previous[unit], army.cells[unit], army.desired_cells[unit], army._unit_passage_phase[unit], army._formation_march_active, army._formation_final_reform, army._pending_pushes])
					return false
		for group: int in range(army._passage_descriptors.size()):
			var descriptor: Dictionary = army._passage_descriptors[group]
			if observed_rallies.has(group) or int(descriptor.get("rally_completed_tick", -1)) < 0:
				continue
			if not _check(_physical_body_connected(army.cells, terrain), "generated intermediate rally lacks an actual connected 100-person body"):
				return false
			observed_rallies[group] = army.input_seconds
			print("GENERATED_RALLY_WITNESS group=", group, " time=", army.input_seconds, " cells=", army.cells)
		if army.simulated_seconds > sim_before and not _gate_progress(army, gates, previous, gate_waits, army.simulated_seconds - sim_before):
			return false
		previous = army.cells.duplicate()
		if frame % (10 * hz) == 10 * hz - 1:
			print("GENERATED_PROGRESS t=%.1f captain=%s assembled=%s crossings=%s clearings=%s summary=%s" % [army.input_seconds, army.cells[0], army.formation_count(), crossed.map(func(v: Dictionary) -> int: return v.size()), cleared.map(func(v: Dictionary) -> int: return v.size()), army.passage_summary()])
			for pending: Dictionary in army._pending_pushes:
				var requester := int(pending.requester)
				print("PUSH_FRONT requester=%s phase=%s exit_clear=%s passage=%s members=%s cursor=%s age=%s" % [requester, army._unit_passage_phase[requester], army._unit_passage_exit_clear[requester], army._unit_passage[requester], pending.units.size(), pending.cursor, pending.age])
		if frame == 40 * hz - 1 and "--diagnostic40" in OS.get_cmdline_user_args():
			print("INITIAL_BODY_DIAGNOSTIC cells=%s active_slots=%s heading=%s" % [army.cells, army.desired_cells, army._formation_heading])
			for descriptor: Dictionary in army._passage_descriptors:
				print("GATE_GEOMETRY_DIAGNOSTIC corridor=%s exit=%s rally=%s" % [descriptor.corridor, descriptor.exit, descriptor.rally_layout])
			print("DIAGNOSTIC_ONLY claims=%s pending=%s slots=%s" % [army._reserved_cells, army._pending_pushes, army._passage_final_slots])
			for unit: int in range(1, 100):
				if army._unit_passage_phase[unit] != TerrainArmy.PassagePhase.EXIT_CLEAR or army._unit_passage_exit_clear[unit] != 0:
					continue
				var cursor := army.desired_cells[unit]
				var reverse_path: Array[Vector2i] = [cursor]
				for hop: int in range(1024):
					if cursor == army.cells[unit]:
						break
					var depth := int(army._passage_final_component.get(cursor, -1))
					var parent := TerrainArmy.INVALID_CELL
					for direction: Vector2i in TerrainData.DIRECTIONS:
						if army._passage_final_component.get(cursor + direction, -2) == depth - 1 and terrain.can_step(cursor + direction, cursor):
							parent = cursor + direction
							break
					if parent == TerrainArmy.INVALID_CELL:
						break
					reverse_path.append(parent)
					cursor = parent
				var obstacles := []
				for cell: Vector2i in reverse_path:
					if army._reserved_cells.has(cell) or army._cell_owners.has(cell) or army._is_external_cell(cell):
						obstacles.append([cell, army._cell_owners.get(cell), army._reserved_cells.get(cell), army._is_external_cell(cell)])
				print("FIELD_ROUTE unit=%s depth_start=%s depth_goal=%s recovered_to=%s length=%s obstacles=%s" % [unit, army._passage_final_component.get(army.cells[unit]), army._passage_final_component.get(army.desired_cells[unit]), cursor, reverse_path.size(), obstacles])
			for unit: int in range(1, 100):
				if army.cells[unit] != army.desired_cells[unit]:
					print("TRACE unit=%s cell=%s goal=%s phase=%s completed=%s state=%s lock=%s retry=%s route=%s" % [unit, army.cells[unit], army.desired_cells[unit], army._unit_passage_phase[unit], army._unit_completed_exits[unit], army.movement_state[unit], army._push_lock[unit], army._local_occupied_retry.get(unit), army._follower_routes.get(unit)])
			army.free()
			npc.free()
			player.free()
			return true
		if complete_time < 0.0 and army.is_formation_complete():
			complete_time = army.input_seconds
			frozen.assign(army.cells)
			for gate_index: int in range(gates.size()):
				for unit: int in required[gate_index]:
					if not _check(crossed[gate_index].has(unit) and cleared[gate_index].has(unit), "generated completion skipped a mandatory physical crossing"):
						return false
			for unit: int in range(1, 100):
				if not _check(army.cells[unit] == army.desired_cells[unit] and published_slots.has(army.cells[unit]), "generated final binding outside fixed slot set"):
					return false
			if not _check(army.cells.has(goal) and army.cells[0] != goal and _physical_body_connected(army.cells, terrain), "generated final front/captain/body mismatch"):
				return false
			for group: int in range(army._passage_descriptors.size()):
				if army._passage_descriptors[group].get("rally_layout", []).size() == 100 and not _check(observed_rallies.has(group), "generated skipped a feasible full-team rally"):
					return false
		if complete_time >= 0.0:
			if not _check(army.cells == frozen and army.is_formation_complete(), "generated completion not stable"):
				return false
			stable = army.input_seconds - complete_time
			if stable >= 5.0:
				break
		elif army.input_seconds >= float(declared_seconds):
			break
	var passed := _check(complete_time >= 0.0 and complete_time <= float(declared_seconds) and stable >= 5.0 and army.formation_count() == 99 and army.dropped_seconds == 0.0, "generated deadline failed status=%s summary=%s" % [army.command_status, army.passage_summary()])
	if passed:
		print("ARMY_GENERATED_V6_PASS preset=%s seed=%s follow=%s hz=%s alternating=%s complete_seconds=%.3f stable=%.3f source=%s" % [preset, seed_value, follow, hz, alternating, complete_time, stable, FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd")])
	else:
		print("GENERATED_FAILURE claims=%s pending=%s ready=%s budget=%s" % [army._reserved_cells, army._pending_pushes, army._push_search_ready, army._local_path_requests_remaining])
		var final_descriptor := army._passage_descriptor(army._passage_descriptors.size() - 1)
		var outside := []
		for unit: int in range(100):
			var depth := int(final_descriptor.get("goal_slot_component", {}).get(army.cells[unit], -1))
			if depth != 0:
				outside.append([unit, army.cells[unit], depth, final_descriptor.get("front_component", {}).get(army.cells[unit], -1), army._formation_bend_field.get(army.cells[unit], -1)])
		print("GENERATED_FINAL_GEOMETRY captain=%s goal=%s ready=%s outsiders=%s slots=%s" % [army.cells[0], army._passage_final_captain_slot, army._final_reform_ready(army.cells), outside, army._passage_final_slots])
		var diagnostics := []
		var slot_field: Dictionary = army._passage_descriptor(army._passage_descriptors.size() - 1).get("goal_slot_component", {})
		var body_field := army._passage_march_field()
		for unit: int in range(100):
			diagnostics.append([unit, army.cells[unit], body_field.get(army.cells[unit], -1), slot_field.get(army.cells[unit], -1), army._formation_bend_lateral.get(army.cells[unit], -1)])
		print("GENERATED_BODY_DIAGNOSTIC final_captain=", army._passage_final_captain_slot, " span=", army._formation_bend_span, " members=", diagnostics)
		for unit: int in range(1, 100):
			if army.cells[unit] != army.desired_cells[unit]:
				print("GENERATED_UNSETTLED unit=%s cell=%s goal=%s passage=%s completed=%s initial_exempt=%s phase=%s wait=%s" % [unit, army.cells[unit], army.desired_cells[unit], army._unit_passage[unit], army._unit_completed_exits[unit], army._unit_initial_exempt_exits[unit], army._unit_passage_phase[unit], army.blocked_time[unit]])
				print("GENERATED_ROUTE unit=%s route=%s cursor=%s route_goal=%s retry=%s state=%s lock=%s" % [unit, army._follower_routes.get(unit), army._follower_route_cursors.get(unit), army._follower_route_goals.get(unit), army._local_occupied_retry.get(unit), army.movement_state[unit], army._push_lock[unit]])
				if terrain.can_step(army.cells[unit], army.desired_cells[unit]):
					army._push_searches_remaining = 1
					print("DIAGNOSTIC_ONLY failed-case push query unit=%s chain=%s" % [unit, army._find_push_chain(army.desired_cells[unit], unit)])
	army.free()
	npc.free()
	player.free()
	return passed

static func _physical_body_connected(body: Array[Vector2i], terrain: TerrainData) -> bool:
	if body.size() != 100:
		return false
	var occupied := {}
	for cell: Vector2i in body:
		occupied[cell] = true
	if occupied.size() != 100:
		return false
	var seen := {body[0]: true}
	var pending: Array[Vector2i] = [body[0]]
	var cursor := 0
	while cursor < pending.size():
		var current := pending[cursor]
		cursor += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if occupied.has(next) and not seen.has(next) and terrain.can_step(current, next):
				seen[next] = true
				pending.append(next)
	return seen.size() == 100

static func _flood(terrain: TerrainData, start: Vector2i, sealed: Array = []) -> Dictionary:
	var distances := {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if not sealed.is_empty() and ((current == sealed[0] and next == sealed[1]) or (current == sealed[1] and next == sealed[0])):
				continue
			if distances.has(next) or not terrain.can_step(current, next):
				continue
			distances[next] = int(distances[current]) + 1
			queue.append(next)
	return distances

func _layout_witness(terrain: TerrainData, component: Dictionary, excluded: Array) -> Array[Vector2i]:
	# Independent existence proof, not a copy of production anchor/depth ranking.
	# An intact flat 10x10 rectangle with at most one excluded cell can hold 99.
	for y: int in range(terrain.size.y - 9):
		for x: int in range(terrain.size.x - 9):
			var anchor := Vector2i(x, y)
			if not component.has(anchor):
				continue
			var height := int(terrain.height_levels[terrain.index(anchor)])
			var slots: Array[Vector2i] = []
			var valid := true
			for row: int in range(10):
				for column: int in range(10):
					var cell := anchor + Vector2i(column, row)
					if not component.has(cell) or not terrain.is_walkable(cell) or int(terrain.height_levels[terrain.index(cell)]) != height:
						valid = false
						break
					if not excluded.has(cell):
						slots.append(cell)
				if not valid:
					break
			if valid and slots.size() >= 99:
				slots.resize(99)
				return slots
	return []

func _slot_set_valid(army: TerrainArmy, terrain: TerrainData, slots: Array[Vector2i], component: Dictionary, square: bool = true) -> bool:
	if not _check(slots.size() == 99, "layout does not contain 99 slots"):
		return false
	var unique := {}
	var bounds := Rect2i(slots[0], Vector2i.ONE)
	for slot: Vector2i in slots:
		if not _check(not unique.has(slot) and component.has(slot) and terrain.is_walkable(slot) and slot != army._passage_final_captain_slot and slot != army.player.terrain_cell and slot != army.npc.terrain_cell, "layout slot invalid, duplicate or outside downstream component"):
			return false
		unique[slot] = true
		bounds = bounds.merge(Rect2i(slot, Vector2i.ONE))
		for direction: Vector2i in TerrainData.DIRECTIONS:
			if slots.has(slot + direction) and not _check(terrain.can_step(slot, slot + direction), "layout internal cliff"):
				return false
	var body: Array[Vector2i] = [army._passage_final_captain_slot]
	body.append_array(slots)
	if not _check(_physical_body_connected(body, terrain), "final layout is not one legal connected 100-person body"):
		return false
	if square:
		return _check(bounds.size == Vector2i(10, 10), "layout is not an actual 10-column/rank footprint")
	var heading: Vector2i = army._path_route_snapshot[-1] - army._path_route_snapshot[-2]
	var side := Vector2i(-heading.y, heading.x)
	var nearest_side := 1 << 29
	var farthest_side := -(1 << 29)
	var guards := 0
	var rear := 0
	for slot: Vector2i in body:
		var offset := slot - army._passage_final_captain_slot
		var depth := offset.x * heading.x + offset.y * heading.y
		guards += int(depth > 0)
		rear += int(depth < 0)
		nearest_side = mini(nearest_side, slot.x * side.x + slot.y * side.y)
		farthest_side = maxi(farthest_side, slot.x * side.x + slot.y * side.y)
	return _check(farthest_side - nearest_side < 10 and guards >= 20 and guards <= 70 and rear >= 20, "narrow final layout lost width/captain protection")

func _gate_progress(army: TerrainArmy, gates: Array[Array], previous: Array[Vector2i], waits: Array[float], delta: float) -> bool:
	# V6 includes real receiving work of this gate's downstream group. Only a
	# new best fixed-target distance counts; remote movement / oscillation cannot.
	for gate_index: int in range(gates.size()):
		var gate: Array = gates[gate_index]
		var ready := not army._formation_march_active and gate_index >= army._passage_group_start and gate_index <= army._passage_group_end and not army.is_formation_complete()
		var forward := false
		var field_key := "approach_field:%d" % gate_index
		if not _gate_local_best.has(field_key):
			_gate_local_best[field_key] = _flood(army.data, gate[0], gate)
		var approach: Dictionary = _gate_local_best[field_key]
		var receiving_workers := {}
		for transaction: Dictionary in army._pending_pushes:
			var requester := int(transaction.requester)
			if army._unit_passage_phase[requester] == TerrainArmy.PassagePhase.EXIT_CLEAR \
				and army._unit_passage[requester] >= gate_index and army._unit_passage[requester] <= army._passage_group_end:
				for worker: int in transaction.units:
					receiving_workers[worker] = true
		for unit: int in range(100):
			ready = ready or army.cells[unit] == gate[0] or army.cells[unit] == gate[1]
			forward = forward or (previous[unit] == gate[0] and army.cells[unit] == gate[1]) or (previous[unit] == gate[1] and army.cells[unit] != gate[1] and army.cells[unit] != gate[0])
			if previous[unit] != army.cells[unit] and army._unit_passage_phase[unit] == TerrainArmy.PassagePhase.APPROACH and army._unit_passage[unit] == gate_index and approach.has(army.cells[unit]) and approach.has(previous[unit]):
				var approach_key := "approach:%d:%d" % [gate_index, unit]
				if int(approach[army.cells[unit]]) < int(_gate_local_best.get(approach_key, approach[previous[unit]])):
					_gate_local_best[approach_key] = int(approach[army.cells[unit]])
					forward = true
			if previous[unit] != army.cells[unit] and receiving_workers.has(unit):
				# Actual vacancy-chain commits are local clearance work even when
				# a settled receiver temporarily moves away from its own identity.
				# Count each directed edge once; repeating the same push cannot mask a stall.
				var edge_key := "%d:%d:%s>%s" % [gate_index, unit, previous[unit], army.cells[unit]]
				if not _gate_local_best.has(edge_key):
					_gate_local_best[edge_key] = true
					forward = true
			if previous[unit] != army.cells[unit] and army._unit_completed_exits[unit] > gate_index \
				and gate_index >= army._passage_group_start and gate_index <= army._passage_group_end:
				var goal: Vector2i = army.desired_cells[unit]
				var key := "%d:%d:%s" % [gate_index, unit, goal]
				var distance := absi(army.cells[unit].x - goal.x) + absi(army.cells[unit].y - goal.y)
				var old_distance := absi(previous[unit].x - goal.x) + absi(previous[unit].y - goal.y)
				if distance < int(_gate_local_best.get(key, old_distance)):
					_gate_local_best[key] = distance
					forward = true
		var external := [army.player.terrain_cell, army.npc.terrain_cell]
		var blocked := external.has(gate[0]) or external.has(gate[1]) or external.has(gate[1] + (gate[1] - gate[0]))
		var planning := army._command_goal_pending or army._passage_plan_pending or army._formation_target_pending
		waits[gate_index] = waits[gate_index] + delta if ready and not forward and not blocked and not planning and army.passage_active() else 0.0
		if waits[gate_index] >= 5.0:
			var pending_units := []
			for unit: int in range(100):
				if army.cells[unit] != army.desired_cells[unit] or unit == 0:
					pending_units.append([unit, army.cells[unit], army.desired_cells[unit], army._unit_passage_phase[unit], army._unit_passage_ticket[unit]])
			print("D01 LOCAL_STALL t=", army.input_seconds, " group=", [army._passage_group_start, army._passage_group_end], " macro=", army._formation_march_active, " pending_units=", pending_units, " pocket=", army._passage_descriptor(army._passage_group_end).get("rally_layout", []))
			print("D01 CAPTAIN_STALL route=", army._follower_routes.get(0, []), " cursor=", army._follower_route_cursors.get(0, -1), " held=", army._passage_order_hold(0, army._unit_passage[0]), " goal=", army.desired_cells[0])
			_check(false, "NO_PASSAGE_PROGRESS gate=%s wait=%s status=%s claims=%s pending=%s" % [gate, waits[gate_index], army.command_status, army._reserved_cells, army._pending_pushes])
			return false
	return true
