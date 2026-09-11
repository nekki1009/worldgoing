extends SceneTree

const EdgeChecks = preload("res://scripts/tests/terrain_army_default_edge_test.gd")
const EntranceFixture = preload("res://scripts/tests/terrain_army_entrance_clearance_test.gd")
const FormationCases = preload("res://scripts/tests/terrain_army_formation_advance_test.gd")
var _capture_root := ""
var _caption: Label
var _metadata: Array[Dictionary] = []

const OUTPUT := "res://.visual_captures/terrain_lab/army_100_deployed.png"
const SWAP_BEFORE_OUTPUT := "res://.visual_captures/terrain_lab/army_swap_before.png"
const SWAP_MID_OUTPUT := "res://.visual_captures/terrain_lab/army_swap_mid.png"
const SWAP_AFTER_OUTPUT := "res://.visual_captures/terrain_lab/army_swap_after.png"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if "--legacy" in OS.get_cmdline_user_args():
		await _legacy()
		return
	if DisplayServer.get_name() == "headless":
		push_error("VISUAL_NOT_RUN: a GPU-backed scene is required")
		quit(1)
		return
	var label := "D01"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			label = argument.trim_prefix("--case=")
	if label not in ["D01", "E01", "E02", "G01", "G02", "G08_BEND", "V_MOVE", "V_CAPTAIN_SWAP", "V_FOLLOWER_SWAP", "V_PUSH", "V_HANDOFF"]:
		push_error("Unknown visual case")
		quit(1)
		return
	_capture_root = "res://.visual_captures/terrain_lab/v6/" + FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd").left(12) + "/"
	DisplayServer.window_set_size(Vector2i(2560, 1440))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var lab := (load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene).instantiate() as TerrainLab
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.army.set_process(false)
	lab.npc.set_process(false)
	lab.character.set_process(false)
	if label not in ["D01", "G08_BEND"]:
		lab.army.clear()
		lab.terrain = EntranceFixture._entrance_data(label == "E02")
		if label.begins_with("V_") or label.begins_with("G"):
			lab.terrain.flags.fill(TerrainData.Flag.WALKABLE)
		lab.renderer.display(lab.terrain)
		lab.renderer.debug_enabled = true
		lab.renderer.redraw()
		lab.parameters_label.text = "FIXED TEST FIXTURE: %s\n40 x 30 | wall x=20 except y=15\n%s" % [label, "Height 0 -> 1 with reciprocal ramp" if label == "E02" else "Same-height legal opening"]
		if label.begins_with("V_") or label.begins_with("G"):
			lab.parameters_label.text = "CONTROLLED VISUAL FIXTURE: %s\n40 x 30 flat | 100 real army members\nOne-time legal placement before replay" % label
		lab.preset_dropdown.disabled = true
		lab.seed_input.text = "Fixed " + label + " (not a generated seed)"
		lab.character.data = lab.terrain
		lab.npc.set_data(lab.terrain)
		if not lab.character.place(Vector2i(3, 15), true) or not lab.npc.place(Vector2i(2, 15), true):
			push_error("FIXTURE_INVALID GPU external positions")
			quit(1)
			return
	lab.deploy_army()
	if not lab.army.has_army() or lab.army.visual_mode() != "baked_atlas" or lab.army.active_3d_source_count() != 1:
		push_error("GPU army deployment/render contract failed")
		quit(1)
		return
	var overlay := CanvasLayer.new()
	lab.add_child(overlay)
	_caption = Label.new()
	_caption.position = Vector2(520, 30)
	_caption.add_theme_font_size_override("font_size", 28)
	_caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	_caption.add_theme_constant_override("shadow_offset_x", 2)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(_caption)
	for frame: int in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	if label.begins_with("G"):
		var valid := await _bend_frames(lab, label) if label == "G08_BEND" else await _cohesive_frames(lab, label)
		if valid:
			var file := FileAccess.open(ProjectSettings.globalize_path(_capture_root + label + "_metadata.json"), FileAccess.WRITE)
			file.store_string(JSON.stringify(_metadata, "\t"))
			file.close()
			print("ARMY_GPU_COHESIVE_RECORDED case=", label, " captures=", _metadata.size(), " source=", FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"), " inspect_images_required=true")
		lab.army.clear()
		lab.queue_free()
		await process_frame
		quit(0 if valid else 1)
		return
	if label.begins_with("V_"):
		var valid := await _transaction_frames(lab, label)
		if valid:
			var file := FileAccess.open(ProjectSettings.globalize_path(_capture_root + label + "_metadata.json"), FileAccess.WRITE)
			file.store_string(JSON.stringify(_metadata, "\t"))
			file.close()
			print("ARMY_GPU_TRANSACTION_RECORDED case=", label, " captures=", _metadata.size(), " source=", FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"), " inspect_images_required=true")
		lab.army.clear()
		lab.queue_free()
		await process_frame
		quit(0 if valid else 1)
		return
	if label != "D01" and not lab.character.place(Vector2i(36, 15), true):
		push_error("FIXTURE_INVALID GPU follow target")
		quit(1)
		return
	if not lab.issue_army_command(TerrainArmy.Command.MOVE_TO_EDGE if label == "D01" else TerrainArmy.Command.FOLLOW_PLAYER):
		push_error("GPU command rejected")
		quit(1)
		return
	print("VISUAL START wall_ticks_ms=", Time.get_ticks_msec(), " case=", label, " source=", FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"), " fingerprint=", lab.terrain.fingerprint(), " INITIAL_CELLS=", lab.army.cells)
	var valid := await _milestones(lab, label)
	if valid:
		var metadata_path := ProjectSettings.globalize_path(_capture_root + label + "_metadata.json")
		var metadata_file := FileAccess.open(metadata_path, FileAccess.WRITE)
		metadata_file.store_string(JSON.stringify(_metadata, "\t"))
		metadata_file.close()
		print("ARMY_GPU_MILESTONES_RECORDED case=", label, " captures=", _metadata.size(), " source=", FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"), " inspect_images_required=true")
	lab.army.clear()
	lab.queue_free()
	await process_frame
	quit(0 if valid else 1)

func _bend_frames(lab: TerrainLab, label: String) -> bool:
	var army := lab.army
	if lab.terrain.fingerprint() != "c8a3021229df7f5f4324c39ee75fada205999efd74ec4f2cb13b481f12bc3367" or not lab.issue_army_command(TerrainArmy.Command.MOVE_TO_EDGE):
		push_error("GPU bend fixture requires the unchanged D01 terrain")
		return false
	for _frame: int in range(20 * 60):
		army.advance_frame(1.0 / 60.0)
		if army.passage_active() and not army._passage_plan_pending and not army._formation_target_pending:
			break
	if army._passage_descriptors.size() != 5:
		return false
	var previous := FormationCases.configure_bend_snapshot(army)
	# Fixture construction bypasses a simulation tick; initialize its cached
	# summary once before recording. Captures themselves remain read-only.
	army._update_formation_status()
	var guard_field := EdgeChecks._flood(lab.terrain, Vector2i(54, 25), [Vector2i(54, 25), Vector2i(54, 24)])
	lab.parameters_label.text = "CONTROLLED G08 BEND SNAPSHOT\n100 real members | D01 terrain unchanged\nOne initial placement, then ordinary advance_frame\nLocal turn proof only; not a full D01 replay"
	if not await _capture(lab, label, "initial_snapshot", PackedInt32Array(), PackedInt32Array()):
		return false
	var before := army.completed_steps()
	var captain_edges := 0
	var strip_start := -1
	var last_ground := {}
	var min_guards := Vector2i(99, 99)
	for frame: int in range(600):
		army.advance_frame(1.0 / 60.0)
		if not army._formation_march_active:
			break # Local bend ends at the next real passage, tested separately.
		army._visual_dirty = true
		army._sync_visual_positions()
		if not EdgeChecks._legal_state(army, lab.terrain):
			return false
		var guards := FormationCases.bend_guard_counts(army, guard_field)
		min_guards = min_guards.min(guards)
		if guards.x < 20 or guards.y < 20:
			push_error("GPU bend captain lost independently checked front/rear guards")
			return false
		if previous != army.cells and FormationCases.bend_connected_count(army, lab.terrain) != 100:
			push_error("GPU bend detached a member beyond one legal empty-cell gap")
			return false
		captain_edges += int(previous[0] != army.cells[0])
		for unit: int in range(100):
			if previous[unit] != army.cells[unit] and not lab.terrain.can_step(previous[unit], army.cells[unit]):
				push_error("GPU bend illegal physical edge")
				return false
		previous = army.cells.duplicate()
		if strip_start < 0 and frame >= 300 and army._formation_step_units.size() >= 4:
			strip_start = frame
		var strip_frame := frame - strip_start
		if strip_start >= 0 and strip_frame <= 30:
			for unit: int in range(100):
				var sprite_anchor: Vector2 = army._captain_anchor if unit == 0 else army._soldier_sprite_anchors[unit]
				var ground := army._sprites[unit].position + sprite_anchor
				var bound := 1.5 * TerrainRenderer.CELL_PIXELS / (TerrainArmy.RUN_DURATION * 60.0) + 0.01
				if last_ground.has(unit) and ground.distance_to(last_ground[unit]) > bound:
					push_error("GPU bend interpolation jumped")
					return false
				last_ground[unit] = ground
			if strip_frame % 6 == 0:
				if not await _capture(lab, label, "turn_frame_%02d" % strip_frame, PackedInt32Array(), PackedInt32Array()):
					return false
				_metadata[-1].merge({"bend_elapsed": float(frame + 1) / 60.0, "bend_steps": army.formation_bend_steps, "ground_points": last_ground.duplicate(), "progress": Array(army.move_progress), "independent_guards": guards})
	if strip_start < 0 or army.completed_steps() - before < 100 or captain_edges < 3:
		push_error("GPU bend lacked real collective progress")
		return false
	print("GPU_BEND_METRICS commits=", army.completed_steps() - before, " captain_edges=", captain_edges, " independent_min_front_rear=", min_guards, " command_complete=", army.is_formation_complete())
	return await _capture(lab, label, "after_local_turn_not_command_complete", PackedInt32Array(), PackedInt32Array())

func _cohesive_frames(lab: TerrainLab, label: String) -> bool:
	if label == "G02":
		return await _catch_up_frames(lab, label)
	var army := lab.army
	if not lab.character.place(Vector2i(36, 15), true) or not lab.issue_army_command(TerrainArmy.Command.FOLLOW_PLAYER):
		return false
	var started := false
	for frame: int in range(40 * 60):
		army.advance_frame(1.0 / 60.0)
		if not EdgeChecks._legal_state(army, lab.terrain):
			return false
		if army.formation_batch_steps >= 3:
			started = true
			break
	if not started:
		push_error("GPU cohesive march did not start: " + army.command_status)
		return false
	var previous := army.cells.duplicate()
	var last_ground := {}
	var saved_offsets := army._formation_offsets.duplicate()
	for frame: int in range(31):
		if frame > 0:
			army.advance_frame(1.0 / 60.0)
		army._visual_dirty = true
		army._sync_visual_positions()
		if not EdgeChecks._legal_state(army, lab.terrain) or army._formation_offsets != saved_offsets:
			push_error("GPU cohesive identity/owner/claim changed")
			return false
		for unit: int in range(100):
			if army.cells[unit] != previous[unit] and not lab.terrain.can_step(previous[unit], army.cells[unit]):
				return false
			var sprite_anchor: Vector2 = army._captain_anchor if unit == 0 else army._soldier_sprite_anchors[unit]
			var ground := army._sprites[unit].position + sprite_anchor
			var bound := 1.5 * TerrainRenderer.CELL_PIXELS / (TerrainArmy.RUN_DURATION * 60.0) + 0.01
			if last_ground.has(unit) and (ground.distance_to(last_ground[unit]) > bound or (ground - last_ground[unit]).dot(Vector2.RIGHT) < -0.001):
				push_error("GPU cohesive interpolation jumped or rewound")
				return false
			last_ground[unit] = ground
		previous = army.cells.duplicate()
		if frame % 6 == 0:
			if not await _capture(lab, label, "march_frame_%02d" % frame, PackedInt32Array(), PackedInt32Array()):
				return false
			_metadata[-1].merge({"batch_steps": army.formation_batch_steps, "guide": army._formation_anchor_cell, "front_goal": army._march_goal, "ground_points": last_ground.duplicate(), "progress": Array(army.move_progress)})
	for frame: int in range(40 * 60):
		if army.is_formation_complete():
			break
		army.advance_frame(1.0 / 60.0)
		if not EdgeChecks._legal_state(army, lab.terrain):
			return false
	if not army.is_formation_complete():
		push_error("GPU cohesive march did not finish")
		return false
	previous = army.cells.duplicate()
	for frame: int in range(300):
		army.advance_frame(1.0 / 60.0)
		if army.cells != previous or not army.is_formation_complete():
			return false
	return await _capture(lab, label, "final_100_settled", PackedInt32Array(), PackedInt32Array())

func _catch_up_frames(lab: TerrainLab, label: String) -> bool:
	var army := lab.army
	FormationCases.configure_rectangular_snapshot(army, Vector2i(14, 15))
	for unit: int in [98, 99]:
		army._cell_owners.erase(army.cells[unit])
		army.cells[unit] += Vector2i.LEFT * 3
		army._cell_owners[army.cells[unit]] = unit
	var anchor := army._formation_anchor_cell
	var previous := army.cells.duplicate()
	var ground_before := {}
	var runners := {}
	var walked := {}
	for frame: int in range(91):
		if frame > 0:
			army.advance_frame(1.0 / 60.0)
		army._update_formation_status()
		army._visual_dirty = true
		army._sync_visual_positions()
		if not EdgeChecks._legal_state(army, lab.terrain):
			return false
		for unit: int in range(100):
			if previous[unit] != army.cells[unit] and not lab.terrain.can_step(previous[unit], army.cells[unit]):
				return false
			var sprite_anchor: Vector2 = army._captain_anchor if unit == 0 else army._soldier_sprite_anchors[unit]
			var ground := army._sprites[unit].position + sprite_anchor
			var bound := 1.5 * TerrainRenderer.CELL_PIXELS / (TerrainArmy.RUN_DURATION * 60.0) + 0.01
			if ground_before.has(unit) and (ground.distance_to(ground_before[unit]) > bound or (ground - ground_before[unit]).x < -0.001):
				push_error("GPU catch-up interpolation jumped or rewound")
				return false
			ground_before[unit] = ground
		for unit: int in [98, 99]:
			if army.locomotion_mode[unit] == TerrainArmy.Locomotion.RUN:
				if not is_equal_approx(army.move_duration[unit], TerrainArmy.RUN_DURATION) or army.cells[0] != anchor:
					push_error("GPU rear RUN duration or front hold mismatch")
					return false
				runners[unit] = true
			if runners.has(unit) and army.locomotion_mode[unit] == TerrainArmy.Locomotion.WALK and army._formation_step_units.size() == 100:
				if not is_equal_approx(army.move_duration[unit], TerrainArmy.MOVE_DURATION):
					return false
				walked[unit] = true
		previous = army.cells.duplicate()
		if frame % 9 == 0:
			if not await _capture(lab, label, "rear_run_to_walk_frame_%02d" % frame, PackedInt32Array(), PackedInt32Array()):
				return false
			_metadata[-1].merge({"ground_points": ground_before.duplicate(), "rear_modes": [army.locomotion_mode[98], army.locomotion_mode[99]], "rear_durations": [army.move_duration[98], army.move_duration[99]], "batches": army.formation_batch_steps, "hold": army.formation_cohesion})
	if runners.size() != 2 or walked.size() != 2 or army.formation_batch_steps < 2:
		push_error("GPU catch-up did not show both rear units RUN then collective WALK")
		return false
	print("GPU_CATCH_UP_PASS frames=91 rear_runners=", runners.keys(), " resumed_walk=", walked.keys(), " batches=", army.formation_batch_steps)
	return true

func _milestones(lab: TerrainLab, label: String) -> bool:
	var army := lab.army
	var gates: Array = EdgeChecks.EXPECTED_GATES if label == "D01" else [[Vector2i(19, 15), Vector2i(20, 15)]]
	var counts := PackedInt32Array()
	var clear_counts := PackedInt32Array()
	counts.resize(gates.size())
	clear_counts.resize(gates.size())
	var next_gate := PackedInt32Array()
	var next_clear := PackedInt32Array()
	next_gate.resize(100)
	next_clear.resize(100)
	var previous := army.cells.duplicate()
	var stages := {}
	var captain_orders := PackedInt32Array()
	captain_orders.resize(gates.size())
	captain_orders.fill(-1)
	var rally_batches := -1
	var completion := -1.0
	var hz := 30 if "--30hz" in OS.get_cmdline_user_args() else 60
	# Same predeclared D01 engineering budget as the headless oracle.
	var deadline := 503.0 if label == "D01" else 140.0
	for frame: int in range(ceili(deadline * hz)):
		army.advance_frame(1.0 / float(hz))
		if not EdgeChecks._legal_state(army, lab.terrain):
			return false
		for unit: int in range(100):
			if army.cells[unit] == previous[unit]:
				continue
			if not lab.terrain.can_step(previous[unit], army.cells[unit]):
				push_error("GPU illegal committed edge")
				return false
			for gate: int in range(gates.size()):
				if previous[unit] == gates[gate][1] and army.cells[unit] == gates[gate][0]:
					push_error("GPU reverse physical gate")
					return false
				if previous[unit] == gates[gate][0] and army.cells[unit] == gates[gate][1]:
					if next_gate[unit] != gate:
						push_error("GPU crossing order")
						return false
					next_gate[unit] += 1
					if unit == 0:
						captain_orders[gate] = counts[gate]
						if counts[gate] < 20 or counts[gate] > 70:
							push_error("GPU captain bypassed protected passage order")
							return false
					else:
						counts[gate] += 1
				if previous[unit] == gates[gate][1] and army.cells[unit] != gates[gate][0]:
					if next_clear[unit] != gate or next_gate[unit] != gate + 1:
						push_error("GPU clearance order")
						return false
					next_clear[unit] += 1
					if unit > 0:
						clear_counts[gate] += 1
		previous = army.cells.duplicate()
		if not stages.has("captain") and army._unit_passage_phase[0] == TerrainArmy.PassagePhase.IN_PASSAGE:
			if not await _capture(lab, label, "01_captain_middle_passage", counts, clear_counts):
				return false
			stages["captain"] = true
		if not stages.has("receiving") and clear_counts[0] >= 20 and counts[0] < 99:
			if not await _capture(lab, label, "02_first_receiving_tail_still_crossing", counts, clear_counts):
				return false
			stages["receiving"] = true
		if label == "D01" and clear_counts[0] == 99 and next_clear[0] >= 1 and counts[1] == 0:
			if not stages.has("rally") and int(army._passage_descriptors[0].get("rally_completed_tick", -1)) >= 0:
				if not EdgeChecks._physical_body_connected(army.cells, lab.terrain):
					push_error("GPU middle rally lacks a connected 100-person body")
					return false
				if not await _capture(lab, label, "03_middle_platform_full_rally", counts, clear_counts):
					return false
				stages["rally"] = true
				rally_batches = army.formation_batch_steps + army.formation_bend_steps
			if stages.has("rally") and not stages.has("resumed") and army.formation_batch_steps + army.formation_bend_steps > rally_batches and army._formation_step_units.size() >= 4:
				if not await _capture(lab, label, "04_middle_platform_collective_resumed", counts, clear_counts):
					return false
				stages["resumed"] = true
		if not stages.has("cleared") and clear_counts[-1] == 99 and next_clear[0] == gates.size() and army.passage_summary().completed == 99 and army._unit_completed_exits[0] >= gates.size():
			if not await _capture(lab, label, "05_last_exit_all_100_cleared", counts, clear_counts):
				return false
			stages["cleared"] = true
		if army.is_formation_complete():
			completion = army.input_seconds
			break
	if completion < 0 or stages.size() != (5 if label == "D01" else 3) or counts.count(99) != gates.size() or clear_counts.count(99) != gates.size() or army.cells[0] != army._passage_final_captain_slot:
		push_error("GPU milestones incomplete case=%s stages=%s counts=%s clears=%s input=%.3f" % [label, stages, counts, clear_counts, army.input_seconds])
		return false
	for frame: int in range(5 * hz):
		army.advance_frame(1.0 / float(hz))
		if army.cells != previous or not army.is_formation_complete() or not EdgeChecks._legal_state(army, lab.terrain):
			push_error("GPU final five-second stability failed")
			return false
	if not await _capture(lab, label, "06_final_99_and_middle_captain_stable_5s", counts, clear_counts):
		return false
	print("GPU_COMPLETE case=", label, " complete_seconds=", completion, " stable=5 counts=", counts, " clears=", clear_counts, " captain_orders=", captain_orders, " hz=", hz)
	return true

func _transaction_frames(lab: TerrainLab, label: String) -> bool:
	var army := lab.army
	# Separate controlled action fixture, not the default-map acceptance case.
	# All initialization is before the first replay frame; no position, binding
	# or interpolation is overwritten once the tested action has started.
	var initial: Array[Vector2i] = []
	for x: int in range(9, 14):
		initial.append(Vector2i(x, 10))
	for y: int in range(18, 23):
		for x: int in range(5, 24):
			initial.append(Vector2i(x, y))
	army.cells.assign(initial)
	army.desired_cells.assign(initial)
	army._formation_slot_cells.assign(initial)
	army._cell_owners.clear()
	for unit: int in range(100):
		army._cell_owners[initial[unit]] = unit
		army._formation_offsets[unit] = initial[unit] - initial[0]
	army.command = TerrainArmy.Command.NONE
	var started := false
	var watched: Array[int] = []
	match label:
		"V_MOVE":
			army.desired_cells[1] = Vector2i(10, 11)
			started = army._schedule_push_unit(1, army.desired_cells[1], 0)
			watched = [1]
		"V_CAPTAIN_SWAP":
			army.desired_cells[0] = initial[1]
			army.desired_cells[1] = initial[0]
			started = army._begin_captain_swap(1)
			watched = [0, 1]
		"V_FOLLOWER_SWAP":
			army.desired_cells[1] = initial[2]
			army.desired_cells[2] = initial[1]
			started = army._begin_follower_swap(1, 2)
			watched = [1, 2]
		"V_PUSH", "V_HANDOFF":
			for unit: int in range(1, 5):
				army.desired_cells[unit] = initial[unit] + Vector2i.RIGHT
			started = army._queue_push_chain(1, [Vector2i(11, 10), Vector2i(12, 10), Vector2i(13, 10), Vector2i(14, 10)])
			watched = [1, 2, 3, 4]
	if not started or not EdgeChecks._legal_state(army, lab.terrain):
		push_error("FIXTURE_INVALID GPU action " + label)
		return false
	var original_destinations := army.desired_cells.duplicate()
	var previous_cells := army.cells.duplicate()
	var last_ground := {}
	var committed := []
	var snapshots := [0, 3, 6, 9, 12, 15, 18, 24, 36, 54, 72, 96]
	var handoff_epoch := -1
	var handoff_boundary_checked := false
	army._update_formation_status()
	print("GPU_TRANSACTION_INITIAL case=", label, " fingerprint=", lab.terrain.fingerprint(), " INITIAL_CELLS=", initial, " desired=", army.desired_cells)
	for frame: int in range(97):
		if frame > 0:
			army.advance_frame(1.0 / 60.0)
		if label == "V_HANDOFF" and frame == 9:
			# Only the last blocker is in flight. The public command request must
			# retain its edge/claim and cancel only the unstarted transaction tail.
			var before := army.move_progress[4]
			handoff_epoch = army._command_epoch
			if not army.issue_command(TerrainArmy.Command.MOVE_TO_EDGE) or not army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER):
				return false
			if army.cells != previous_cells or army.move_progress[4] != before or army.moving_to[4] != original_destinations[4] or army._reserved_cells.get(original_destinations[4], -1) != 4:
				push_error("GPU handoff rewound the in-flight blocker")
				return false
		if not EdgeChecks._legal_state(army, lab.terrain):
			return false
		if label == "V_HANDOFF" and handoff_epoch >= 0 and army._command_epoch > handoff_epoch:
			if not handoff_boundary_checked:
				# Check OLD transaction cleanup exactly when the new command activates.
				# Later FOLLOW may legitimately start its own moves and pushes.
				if army.command != TerrainArmy.Command.FOLLOW_PLAYER or army._pending_command >= 0 \
					or army.cells[4] != original_destinations[4] or army.moving_count() != 0 \
					or not army._pending_pushes.is_empty() or not army._reserved_cells.is_empty() or army._push_lock.count(1) != 0:
					push_error("GPU handoff activation leaked the old transaction or lost its original commit")
					return false
				for unit: int in range(1, 4):
					if army.cells[unit] != initial[unit]:
						push_error("GPU handoff completed an unstarted old push member")
						return false
				handoff_boundary_checked = true
				print("GPU_HANDOFF_CLEAN_BOUNDARY frame=", frame, " epoch=", army._command_epoch, " original_blocker=", army.cells[4])
			for pending: Dictionary in army._pending_pushes:
				if int(pending.get("command_epoch", -1)) != army._command_epoch:
					push_error("GPU handoff retained an old-command push")
					return false
		for unit: int in range(100):
			if army.cells[unit] != previous_cells[unit]:
				if not lab.terrain.can_step(previous_cells[unit], army.cells[unit]):
					push_error("GPU transaction committed an illegal edge")
					return false
				if watched.has(unit) and not committed.has(unit):
					committed.append(unit)
		previous_cells = army.cells.duplicate()
		army._visual_dirty = true
		army._sync_visual_positions()
		var ground_samples := {}
		for unit: int in watched:
			var anchor: Vector2 = army._captain_anchor if unit == 0 else army._soldier_sprite_anchors[unit]
			var ground: Vector2 = army._sprites[unit].position + anchor
			ground_samples[unit] = ground
			# Cubic smoothstep has maximum slope 1.5. Derive the bound from
			# the unchanged fastest production duration (RUN=0.18s), not 0.20s.
			var frame_bound := 1.5 * TerrainRenderer.CELL_PIXELS / (minf(TerrainArmy.MOVE_DURATION, TerrainArmy.RUN_DURATION) * 60.0) + 0.01
			if last_ground.has(unit) and ground.distance_to(last_ground[unit]) > frame_bound:
				push_error("GPU visual ground jump case=%s frame=%s unit=%s from=%s to=%s distance=%s bound=%s state=%s duration=%s" % [label, frame, unit, last_ground[unit], ground, ground.distance_to(last_ground[unit]), frame_bound, army.movement_state[unit], army.move_duration[unit]])
				return false
			if label != "V_HANDOFF":
				var direction: Vector2 = Vector2(original_destinations[unit] - initial[unit])
				if last_ground.has(unit) and (ground - last_ground[unit]).dot(direction) < -0.001:
					push_error("GPU original action visibly moved backwards")
					return false
		last_ground = ground_samples
		if snapshots.has(frame):
			if not await _capture(lab, label, "%02d_frame_%03d" % [snapshots.find(frame), frame], PackedInt32Array(), PackedInt32Array(), Vector2i(12, 10), 2.0):
				return false
			_metadata[-1].merge({"watched_units": watched, "ground_points": ground_samples, "moving_to": army.moving_to.duplicate(), "move_progress": Array(army.move_progress), "states": Array(army.movement_state), "claims": str(army._reserved_cells), "pending": str(army._pending_pushes), "command_epoch": army._command_epoch})
	if label == "V_HANDOFF":
		if not handoff_boundary_checked or not committed.has(4) or army.command != TerrainArmy.Command.FOLLOW_PLAYER or army._command_epoch <= handoff_epoch or army._pending_command >= 0:
			push_error("GPU latest-command handoff did not finish")
			return false
	else:
		for unit: int in watched:
			if army.cells[unit] != original_destinations[unit]:
				push_error("GPU original action did not reach its actual destination")
				return false
		if label == "V_PUSH" and committed != [4, 3, 2, 1]:
			push_error("GPU push did not commit from empty end to requester")
			return false
	if label != "V_HANDOFF" and (not army._pending_pushes.is_empty() or army._push_lock.count(1) != 0):
		push_error("GPU transaction left pending work or locks")
		return false
	if label == "V_HANDOFF":
		print("GPU_HANDOFF_NEW_COMMAND_WORK pending=", army._pending_pushes, " locks=", army._push_lock.count(1), " clean_boundary=", handoff_boundary_checked)
	print("GPU_TRANSACTION_PASS case=", label, " committed_order=", committed, " frames=97 no_rewind=true")
	return true

func _capture(lab: TerrainLab, label: String, stage: String, counts: PackedInt32Array, clears: PackedInt32Array, focus: Vector2i = TerrainArmy.INVALID_CELL, zoom: float = 0.0) -> bool:
	var army := lab.army
	if focus != TerrainArmy.INVALID_CELL:
		lab.camera.zoom = Vector2.ONE * zoom
		lab.camera.position = lab.renderer.cell_center(focus) - Vector2(220.0 / zoom, 0)
	else:
		var bounds := Rect2(Vector2(army.cells[0]), Vector2.ONE)
		for cell: Vector2i in army.cells:
			bounds = bounds.expand(Vector2(cell))
		bounds = bounds.grow(3.0)
		var fitted := minf(1.25, minf(1950.0 / (bounds.size.x * 64.0), 1190.0 / (bounds.size.y * 64.0)))
		lab.camera.zoom = Vector2.ONE * fitted
		lab.camera.position = (bounds.get_center() + Vector2.ONE * 0.5) * 64.0 - Vector2(220.0 / fitted, 0)
	lab.camera.force_update_scroll()
	var observed_cells := army.cells.duplicate()
	var observed_targets := army.desired_cells.duplicate()
	var observed_claims := army._reserved_cells.duplicate()
	var observed_searches := Vector3i(army.structure_search_expansions, army.local_search_expansions, army.push_search_expansions)
	lab._update_info()
	if army.cells != observed_cells or army.desired_cells != observed_targets or army._reserved_cells != observed_claims or observed_searches != Vector3i(army.structure_search_expansions, army.local_search_expansions, army.push_search_expansions):
		push_error("GPU HUD observation mutated simulation/search state")
		return false
	if not lab.army_info.text.contains("Captain: %s -> local slot %s" % [army.cells[0], army.desired_cells[0]]) \
		or not lab.army_info.text.contains("Front goal: %s | guide: %s" % [army._march_goal, army._formation_anchor_cell]):
		push_error("GPU HUD did not show the actual captain goal")
		return false
	if label in ["G01", "G08_BEND"]:
		var actual_settled := 0
		for unit: int in range(1, 100):
			actual_settled += int(army.cells[unit] == army.desired_cells[unit] and army.movement_state[unit] != TerrainArmy.UnitState.MOVING and army.movement_state[unit] != TerrainArmy.UnitState.SWAPPING)
		if actual_settled != army.formation_count():
			push_error("GPU HUD cached settled count differs from the actual local body")
			return false
	_caption.text = "%s | %s | input %.2fs\nPhysical crossings %s | cleared %s | settled %d/99" % [label, stage, army.input_seconds, counts, clears, army.formation_count()]
	army._visual_dirty = true
	army._sync_visual_positions()
	for frame: int in range(2):
		await process_frame
		await RenderingServer.frame_post_draw
		var ancestor: Node = lab.army_info.get_parent()
		while ancestor != null and not ancestor is ScrollContainer:
			ancestor = ancestor.get_parent()
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(lab.army_info)
	var relative_path := _capture_root + label + "_" + stage + ".png"
	var output_path := ProjectSettings.globalize_path(relative_path)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if root.get_texture().get_image().save_png(output_path) != OK:
		push_error("GPU capture write failed")
		return false
	_metadata.append({"case": label, "stage": stage, "input_seconds": army.input_seconds, "cells": army.cells.duplicate(), "gate_crossings": Array(counts), "gate_clearings": Array(clears), "summary": army.passage_summary(), "goal": army.desired_cells[0], "image": relative_path, "source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd")})
	print("GPU_CAPTURE ", relative_path, " input=", army.input_seconds, " counts=", counts, " clears=", clears, " wall_ticks_ms=", Time.get_ticks_msec())
	return true

func _legacy() -> void:
	if DisplayServer.get_name() == "headless":
		quit(0)
		return
	DisplayServer.window_set_size(Vector2i(2560, 1440))
	var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn")
	var lab: TerrainLab = scene.instantiate() as TerrainLab
	root.add_child(lab)
	current_scene = lab
	lab.preset_dropdown.select(TerrainPreset.Kind.PLAINS)
	lab.seed_input.text = "24680"
	lab.generate_button.pressed.emit()
	assert(lab.army.deploy(lab.terrain, lab.character, lab.npc), lab.army.command_status)
	assert(lab.army.has_army())
	assert(lab.army.visual_mode() == "baked_atlas", "Ordinary soldiers did not use the baked atlas")
	assert(lab.army.active_3d_source_count() == 1, "Baked army still owns a live soldier 3D source")
	assert(lab.army._captain_editor._body_index == 1, "Captain visual source is not distinct")
	_verify_captain_presentation(lab)
	lab.camera.zoom = Vector2.ONE * 2.2
	lab.camera.position = lab.character.position
	lab.camera.force_update_scroll()
	for _frame: int in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	assert(root.get_texture().get_image().save_png(output_path) == OK)
	assert(lab.army._sprites.size() == TerrainArmy.SOLDIER_COUNT)
	assert(lab.army._sprites[1].texture != null, "Baked soldier sprite has no texture")
	var forced := _force_visual_formation(lab)
	await process_frame
	assert(_save_capture(root, SWAP_BEFORE_OUTPUT))
	lab.army.desired_cells[0] = forced[0] + Vector2i(2, 0)
	lab.army._simulate_step(TerrainArmy.SIM_STEP)
	await process_frame
	assert(lab.army.has_active_swap(), "Visual swap did not enter SWAPPING state")
	assert(_save_capture(root, SWAP_MID_OUTPUT))
	for _frame: int in range(30):
		await process_frame
	assert(lab.army.swap_count() == 1 and lab.army.cells[0] == forced[0] + Vector2i(2, 0), "Visual swap did not complete and advance")
	assert(_save_capture(root, SWAP_AFTER_OUTPUT))
	print("TERRAIN LAB ARMY VISUAL PASS: captain live + 99 baked atlas projections; four-way captain presentation; swap before/mid/after -> ", OUTPUT, ", ", SWAP_BEFORE_OUTPUT, ", ", SWAP_MID_OUTPUT, ", ", SWAP_AFTER_OUTPUT)
	lab.queue_free()
	await process_frame
	quit(0)

func _force_visual_formation(lab: TerrainLab) -> Array[Vector2i]:
	var base := lab.character.terrain_cell + Vector2i(-5, -5)
	var forced: Array[Vector2i] = [base, base + Vector2i.RIGHT]
	for y: int in range(base.y + 3, base.y + 20):
		for x: int in range(base.x - 5, base.x + 12):
			var candidate := Vector2i(x, y)
			if not lab.terrain.contains(candidate) or not lab.terrain.is_walkable(candidate):
				continue
			if candidate == lab.character.terrain_cell or candidate == lab.npc.terrain_cell or forced.has(candidate):
				continue
			forced.append(candidate)
			if forced.size() == TerrainArmy.SOLDIER_COUNT:
				break
		if forced.size() == TerrainArmy.SOLDIER_COUNT:
			break
	assert(forced.size() == TerrainArmy.SOLDIER_COUNT, "Visual swap formation could not find 100 walkable cells")
	lab.army._cell_owners.clear()
	lab.army._reserved_cells.clear()
	lab.army.cells = forced.duplicate()
	for index: int in range(TerrainArmy.SOLDIER_COUNT):
		lab.army.desired_cells[index] = forced[index]
		lab.army.moving_to[index] = TerrainArmy.INVALID_CELL
		lab.army.movement_state[index] = TerrainArmy.UnitState.IDLE
		lab.army.move_progress[index] = 0.0
		lab.army.blocked_time[index] = 0.0
		lab.army.swap_partner[index] = -1
		lab.army._cell_owners[forced[index]] = index
	lab.army._swap_cooldown = 0.0
	lab.army.command = TerrainArmy.Command.NONE
	lab.army._visual_dirty = true
	return forced

func _verify_captain_presentation(lab: TerrainLab) -> void:
	var expected_yaw := {
		Vector2i.DOWN: 0.0,
		Vector2i.UP: 180.0,
		Vector2i.LEFT: -90.0,
		Vector2i.RIGHT: 90.0,
	}
	for direction: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
		lab.army.facing[0] = direction
		lab.army.movement_state[0] = TerrainArmy.UnitState.MOVING
		lab.army._sync_captain_presentation(true)
		assert(lab.army.captain_animation_id() == &"walk", "Captain did not select walk for movement")
		assert(is_equal_approx(lab.army.captain_yaw_degrees(), float(expected_yaw[direction])), "Captain yaw mapping is incorrect")
	lab.army.movement_state[0] = TerrainArmy.UnitState.IDLE
	lab.army.facing[0] = Vector2i.DOWN
	lab.army._sync_captain_presentation(true)
	assert(lab.army.captain_animation_id() == &"idle", "Captain did not return to idle")

func _save_capture(scene_root: Viewport, relative_path: String) -> bool:
	var output_path := ProjectSettings.globalize_path(relative_path)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	return scene_root.get_texture().get_image().save_png(output_path) == OK
