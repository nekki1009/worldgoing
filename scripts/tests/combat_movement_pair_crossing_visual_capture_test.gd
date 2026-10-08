extends SceneTree
## GPU witness for a same-formation atomic two-person crossing in TerrainLab.

const LAB_SCENE = preload("res://scenes/terrain_lab/TerrainLab.tscn")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const OUTPUT_ROOT := "res://output/pathfinding_impl_20260924/"
const DEFAULT_OUTPUT := OUTPUT_ROOT + "visual_pair_crossing_01"
const IMAGE_NAMES := ["00_start.png", "01_midpoint.png", "02_committed.png"]
const PAIR := [1, 2] # Two original male-atlas soldiers, not a test drawing.
const MASK_DELTA := 0.06

var _lab: TerrainLab
var _output := DEFAULT_OUTPUT
var _samples: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if not condition:
		push_error("PAIR CROSSING VISUAL FAIL: " + message)
		quit(1)
	return condition

func _run() -> void:
	if not _require(DisplayServer.get_name() != "headless", "GPU-backed display is required"): return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=").trim_suffix("/")
	if not _require(_output.begins_with(OUTPUT_ROOT) and not _output.contains(".."), "Output must stay in " + OUTPUT_ROOT): return
	if not _require(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_output)), "Use a fresh output directory"): return
	if not _require(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output)) == OK, "Cannot make output directory"): return
	create_timer(180.0).timeout.connect(func() -> void: _require(false, "180-second capture watchdog expired"))
	root.size = Vector2i(1600, 1000)
	_lab = LAB_SCENE.instantiate() as TerrainLab
	_lab.pause_when_unfocused = false
	root.add_child(_lab)
	current_scene = _lab
	_lab.set_process(false)
	_lab.site_controller.set_process(false)
	for actor: TerrainTestCharacter in _lab.combat_actors:
		actor.set_process(false)
	for team: TerrainArmy in _lab.combat_armies:
		team.set_process(false)
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "pair-crossing-visual-fixture")
	data.resource_base.clear()
	data.resources_at.clear()
	for cell_index in range(data.height_levels.size()):
		data.height_levels[cell_index] = 0
		data.flags[cell_index] = TerrainData.Flag.WALKABLE
		data.static_blocked[cell_index] = 0
	data.ramp_edges.fill(0)
	_lab.bind_terrain(data)
	_lab.character.place(Vector2i(60, 60), true)
	var deployment: Dictionary = _lab.start_melee_trial({"friendly_count": 4, "enemy_count": 1,
		"friendly_spawn": Vector2i(24, 25), "enemy_spawn": Vector2i(75, 75),
		"friendly_female_percent": 0, "enemy_female_percent": 0,
		"friendly_attack": false, "enemy_attack": false, "enemy_role": "logistics"})
	if not _require(bool(deployment.get("ok", false)), "TerrainLab deployment failed: " + str(deployment)): return
	var army: TerrainArmy = _lab.army
	if not _require(army.combat_units.size() == 4 and army._sprites.size() == 4 and army.visual_mode() == "baked_atlas", "Expected original four-person Sprite presenter"): return
	for index in PAIR:
		if not _require(not army._uses_live_presenter(index) and army._sprites[index] != null and army._sprites[index].texture != null, "Pair must use actual baked Sprite2D at index " + str(index)): return
	_lab.get_node("SiteUI").hide()
	assert(not _lab.has_node("TerrainLabUI"), "Legacy debug panel must not be constructed")
	if is_instance_valid(_lab.site_test_window): _lab.site_test_window.hide()
	var source_a: Vector2i = army.cells[PAIR[0]]
	var source_b: Vector2i = army.cells[PAIR[1]]
	if not _require(source_b - source_a in TerrainData.DIRECTIONS and data.can_step(source_a, source_b) and data.can_step(source_b, source_a), "Pair must start on mutually legal adjacent cells"): return
	_lab.camera.zoom = Vector2.ONE * 3.0
	_lab.camera.position = (_lab.renderer.cell_center(source_a) + _lab.renderer.cell_center(source_b)) * 0.5
	_lab.camera.force_update_scroll()
	var overlay := CanvasLayer.new()
	root.add_child(overlay)
	var caption := Label.new()
	caption.position = Vector2(18, 16)
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(caption)
	await process_frame
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(34, 26), -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), "Original MOVE order rejected: " + str(order)): return
	var coordinator: SiteCombatMovementCoordinator = _lab.combat_movement_coordinator
	coordinator._rebuild_occupancy()
	var grid: SiteMovementReservationGrid = coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, data)
	var id_a: int = army.combat_identity(PAIR[0])
	var id_b: int = army.combat_identity(PAIR[1])
	var pid_a: int = grid.propose_move(army.formation_runtime_id, id_a, army.get_order_serial(), source_a, source_b)
	var pid_b: int = grid.propose_move(army.formation_runtime_id, id_b, army.get_order_serial(), source_b, source_a)
	if not _require(pid_a >= 0 and pid_b >= 0, "Could not propose reciprocal pair"): return
	grid.resolve_all()
	if not _require(grid.proposal_lookup[pid_a].status == Types.MoveProposalStatus.ACCEPTED and grid.proposal_lookup[pid_b].status == Types.MoveProposalStatus.ACCEPTED, "Pair did not resolve atomically"): return
	grid.commit_all(coordinator._member_lookup, 1)
	coordinator._register_started_batches()
	var batches: Array = coordinator.get_inflight_batches_for_formation(army)
	if not _require(batches.size() == 1 and batches[0].size() == 2 and batches[0].has(id_a) and batches[0].has(id_b), "Both people need one shared completion batch"): return
	var duration: float = army.move_duration[PAIR[0]]
	if not _require(absf(duration - 0.38) < 0.001 and absf(army.move_duration[PAIR[1]] - duration) < 0.001, "Expected synchronized 0.38-second physical step"): return
	if not _pair_in_flight(army, source_a, source_b): return
	if not await _capture(IMAGE_NAMES[0], "Start: both source cells owned", caption): return
	army.prepare_combat(duration * 0.5)
	coordinator.complete_committed_moves()
	if not _pair_in_flight(army, source_a, source_b): return
	if not _require(absf(army.move_progress[PAIR[0]] - 0.5) < 0.01 and absf(army.move_progress[PAIR[1]] - 0.5) < 0.01, "Both people must reach the same half-step"): return
	if not await _capture(IMAGE_NAMES[1], "Midpoint: visual sidestep", caption): return
	var mask: Dictionary = await _midpoint_mask_overlap(army)
	if not _require(int(mask.get("a_pixels", 0)) > 20 and int(mask.get("b_pixels", 0)) > 20, "Both original sprites must be visibly rendered at midpoint: " + str(mask)): return
	if not _require(int(mask.get("overlap_pixels", -1)) == 0, "Visible Sprite pixels overlap at midpoint: " + str(mask)): return
	army.prepare_combat(duration * 0.5 + 0.001)
	coordinator.complete_committed_moves()
	if not _require(army.cells[PAIR[0]] == source_b and army.cells[PAIR[1]] == source_a and army.moving_to[PAIR[0]] == TerrainArmy.INVALID_CELL and army.moving_to[PAIR[1]] == TerrainArmy.INVALID_CELL, "Two original cells must exchange together at completion"): return
	if not _require(coordinator.get_inflight_batches_for_formation(army).is_empty() and army._reserved_cells.is_empty() and army._cell_owners.get(source_a, -1) == PAIR[1] and army._cell_owners.get(source_b, -1) == PAIR[0], "Final occupancy or reservation barrier is wrong"): return
	if not await _capture(IMAGE_NAMES[2], "End: both cells atomically committed", caption): return
	var record := {"complete": true, "scene": "res://scenes/terrain_lab/TerrainLab.tscn", "pair_indices": PAIR,
		"source_a": [source_a.x, source_a.y], "source_b": [source_b.x, source_b.y],
		"step_duration": duration, "midpoint_mask": mask, "samples": _samples,
		"limitations": "Manual reciprocal proposals exercise the real Grid, coordinator, Army and Sprite presenter; no autonomous route choice or 100-person mountain acceptance. Inspect all PNGs."}
	var manifest := FileAccess.open(_output + "/capture.json", FileAccess.WRITE)
	if not _require(manifest != null, "Cannot write capture manifest"): return
	manifest.store_string(JSON.stringify(record, "\t"))
	manifest.close()
	print("PAIR CROSSING VISUAL PASS: 3 PNGs, midpoint visible overlap=0, output=", _output)
	_lab.clear_army()
	_lab.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _pair_in_flight(army: TerrainArmy, source_a: Vector2i, source_b: Vector2i) -> bool:
	return _require(army.cells[PAIR[0]] == source_a and army.cells[PAIR[1]] == source_b
		and army.moving_to[PAIR[0]] == source_b and army.moving_to[PAIR[1]] == source_a
		and army._cell_owners.get(source_a, -1) == PAIR[0] and army._cell_owners.get(source_b, -1) == PAIR[1],
		"Both authoritative source cells must stay owned until the shared barrier")

func _show_pair_only(army: TerrainArmy) -> void:
	for team: TerrainArmy in _lab.combat_armies:
		for sprite: Sprite2D in team._sprites:
			if sprite != null:
				sprite.visible = team == army and (sprite == army._sprites[PAIR[0]] or sprite == army._sprites[PAIR[1]])

func _capture(filename: String, label: String, caption: Label) -> bool:
	var army: TerrainArmy = _lab.army
	for team: TerrainArmy in _lab.combat_armies:
		team.advance_frame(0.0)
	_show_pair_only(army)
	caption.text = "%s\nFormal TerrainLab Sprite / original pair %d + %d / %.3f s" % [label, PAIR[0], PAIR[1], army.move_progress[PAIR[0]] * army.move_duration[PAIR[0]]]
	var rows: Array[Dictionary] = []
	for index in PAIR:
		var sprite: Sprite2D = army._sprites[index]
		if not _require(sprite != null and sprite.visible and sprite.texture != null and sprite.position.is_equal_approx(army.combat_visual_ground(index) + army.combat_offset(index) - army._unit_anchor(index)), "Original Sprite is not anchored to visual sidestep at " + str(index)): return false
		rows.append({"index": index, "source": [army.cells[index].x, army.cells[index].y], "target": [army.moving_to[index].x, army.moving_to[index].y],
			"progress": army.move_progress[index], "logical_ground": army.combat_ground(index), "visual_ground": army.combat_visual_ground(index), "sprite_position": sprite.position,
			"sprite_key": army._soldier_current_keys[index]})
	var frame: Image = await _frame_image()
	if not _require(frame.save_png(_output + "/" + filename) == OK, "Cannot write " + filename): return false
	_samples.append({"image": filename, "label": label, "rows": rows})
	var partial := FileAccess.open(_output + "/capture.json", FileAccess.WRITE)
	if not _require(partial != null, "Cannot preserve partial capture record"): return false
	partial.store_string(JSON.stringify({"complete": false, "samples": _samples}, "\t"))
	partial.close()
	print("PAIR CROSSING GPU CAPTURE ", filename)
	return true

func _frame_image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _midpoint_mask_overlap(army: TerrainArmy) -> Dictionary:
	var a: Sprite2D = army._sprites[PAIR[0]]
	var b: Sprite2D = army._sprites[PAIR[1]]
	a.hide()
	b.hide()
	var background: Image = await _frame_image()
	a.show()
	var only_a: Image = await _frame_image()
	a.hide()
	b.show()
	var only_b: Image = await _frame_image()
	a.show()
	b.show()
	background.convert(Image.FORMAT_RGBA8)
	only_a.convert(Image.FORMAT_RGBA8)
	only_b.convert(Image.FORMAT_RGBA8)
	var base_bytes: PackedByteArray = background.get_data()
	var a_bytes: PackedByteArray = only_a.get_data()
	var b_bytes: PackedByteArray = only_b.get_data()
	var threshold := ceili(MASK_DELTA * 255.0)
	var a_pixels := 0
	var b_pixels := 0
	var overlap := 0
	for byte_index in range(0, base_bytes.size(), 4):
		var a_visible: bool = absi(int(a_bytes[byte_index]) - int(base_bytes[byte_index])) > threshold or absi(int(a_bytes[byte_index + 1]) - int(base_bytes[byte_index + 1])) > threshold or absi(int(a_bytes[byte_index + 2]) - int(base_bytes[byte_index + 2])) > threshold
		var b_visible: bool = absi(int(b_bytes[byte_index]) - int(base_bytes[byte_index])) > threshold or absi(int(b_bytes[byte_index + 1]) - int(base_bytes[byte_index + 1])) > threshold or absi(int(b_bytes[byte_index + 2]) - int(base_bytes[byte_index + 2])) > threshold
		if a_visible:
			a_pixels += 1
		if b_visible:
			b_pixels += 1
		if a_visible and b_visible:
			overlap += 1
	return {"a_pixels": a_pixels, "b_pixels": b_pixels, "overlap_pixels": overlap}
