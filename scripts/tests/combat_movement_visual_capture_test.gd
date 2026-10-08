extends SceneTree
## GPU evidence from the formal scene, UI gesture handler and original Army presenter.

const LAB_SCENE = preload("res://scenes/terrain_lab/TerrainLab.tscn")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const STEP := 1.0 / 120.0
const MEMBERS := 4
const LARGE_MEMBERS := 100
const LARGE_STEP := 1.0 / 30.0
const GOAL := Vector2i(34, 26)
const FINAL_FACING := Vector2i.UP
const DEFAULT_OUTPUT := "res://output/pathfinding_impl_20260924/visual_move_original_01"
const FILES := ["00_preview.png", "01_order.png", "02_step_start.png", "03_step_quarter.png", "04_step_half.png", "05_step_three_quarters.png", "06_step_committed.png", "07_final_hold.png", "08_final_stable.png"]

var _lab: TerrainLab
var _caption: Label
var _output := DEFAULT_OUTPUT
var _preset_id := ""
var _members := MEMBERS
var _seconds := 0.0
var _witness := -1
var _samples: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if not condition:
		push_error("MOVE VISUAL FAIL at %.4fs: %s" % [_seconds, message])
		quit(1)
	return condition

func _run() -> void:
	if not _require(DisplayServer.get_name() != "headless", "A GPU-backed visual run is required"): return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=").trim_suffix("/")
		elif argument.begins_with("--preset="):
			_preset_id = argument.trim_prefix("--preset=")
		elif argument.begins_with("--members="):
			_members = int(argument.trim_prefix("--members="))
	if not _require(_members == MEMBERS or _members == LARGE_MEMBERS, "--members must be 4 or 100"): return
	if not _require(_preset_id.is_empty() or _preset_id in ["square", "wedge", "goose", "circle", "hook", "loose"], "Unknown visual formation preset"): return
	if not _require(_members == MEMBERS or not _preset_id.is_empty(), "100-person capture requires --preset"): return
	if not _require((_output.begins_with("res://output/pathfinding_impl_20260924/") or _output.begins_with("res://output/team_formation_switch_impl_20260926/")) and not _output.contains(".."), "Output must be a fresh movement evidence directory"): return
	if not _require(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_output)), "Use a fresh --output directory; previous evidence is preserved"): return
	if not _require(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output)) == OK, "Cannot create output directory"): return
	if _members == LARGE_MEMBERS:
		create_timer(300.0).timeout.connect(func() -> void: _require(false, "300-second capture watchdog expired"))
	else:
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
	# A disposable flat Site isolates locomotion; no authored scene or asset is changed.
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "movement-visual-fixture")
	data.resource_base.clear()
	data.resources_at.clear()
	for index in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	_lab.bind_terrain(data)
	_lab.character.place(Vector2i(60, 60), true)
	# The distant held support team permits independent legal placement, with no combat contact.
	var deployment: Dictionary = _lab.start_melee_trial({"friendly_count": _members, "enemy_count": 1,
		"friendly_spawn": Vector2i(24, 25), "enemy_spawn": Vector2i(75, 75),
		"friendly_female_percent": 0, "enemy_female_percent": 0,
		"friendly_attack": false, "enemy_attack": false, "enemy_role": "logistics"})
	if not _require(bool(deployment.get("ok", false)), "Formal deployment failed: " + str(deployment)): return
	var army := _lab.army
	if not _require(army.combat_units.size() == _members and army._sprites.size() == _members and army.visual_mode() == "baked_atlas", "Expected original Army people and the shipped presenter"): return
	if _members == LARGE_MEMBERS and not _require(army._batch_render_active() and army._batch_view != null, "100-person run must use the shipped Army batch presenter"): return
	_lab.get_node("SiteUI").hide()
	assert(not _lab.has_node("TerrainLabUI"), "Legacy debug panel must not be constructed")
	if is_instance_valid(_lab.site_test_window): _lab.site_test_window.hide()
	_lab.camera.zoom = Vector2.ONE * 1.6
	_lab.camera.position = _lab.renderer.cell_center(Vector2i(29, 26))
	_lab.camera.force_update_scroll()
	var overlay := CanvasLayer.new()
	root.add_child(overlay)
	_caption = Label.new()
	_caption.position = Vector2(18, 16)
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	_caption.add_theme_constant_override("shadow_offset_x", 2)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(_caption)
	await process_frame
	# Exercise the existing press / drag / release handler, including map picking.
	if not _preset_id.is_empty():
		_lab.site_controller.formation_command_source.select(2)
		_lab.site_controller._formation_context_changed()
		for index in range(_lab.site_controller.formation_preset_choice.item_count):
			if str(_lab.site_controller.formation_preset_choice.get_item_metadata(index)) == _preset_id:
				_lab.site_controller.formation_preset_choice.select(index)
				_lab.site_controller._select_formation_candidate(index)
				break
		if _members == MEMBERS:
			_lab.get_node("SiteUI").show()
			_lab.site_controller._open_combat_window()
			await process_frame
			var scrolls: Array[Node] = _lab.site_controller.combat_window.find_children("*", "ScrollContainer", true, false)
			var form_scroll: ScrollContainer = scrolls[0] as ScrollContainer if not scrolls.is_empty() else null
			if form_scroll != null:
				form_scroll.ensure_control_visible(_lab.site_controller.formation_preset_choice)
				form_scroll.scroll_vertical += 120
			await RenderingServer.frame_post_draw
			if not _require(_lab.site_controller.combat_window.get_texture().get_image().save_png(_output + "/00_ui_candidate.png") == OK,
				"Cannot capture the actual formation selector window"): return
	_lab.site_controller._begin_facing_move("test")
	if not _preset_id.is_empty():
		_lab.get_node("SiteUI").hide()
	if not _require(_lab.site_controller._facing_order_source == "test", "UI did not enter facing-MOVE mode"): return
	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.pressed = true
	pressed.position = _screen_point(GOAL)
	if not _require(_lab.site_controller.handle_input(pressed), "UI did not consume destination press"): return
	var dragged := InputEventMouseMotion.new()
	dragged.position = _screen_point(GOAL + FINAL_FACING * 2)
	if not _require(_lab.site_controller.handle_input(dragged), "UI did not consume facing drag"): return
	if not _require(_lab.site_controller.view.combat_preview_facing == FINAL_FACING and _lab.site_controller.view.combat_preview_platform_slots.size() + _lab.site_controller.view.combat_preview_queue_slots.size() == _members, "Facing drag must display the validated assigned final slots"): return
	if _members == MEMBERS:
		var preview_center := Vector2.ZERO
		for cell: Vector2i in _lab.site_controller.view.combat_preview_platform_slots:
			preview_center += _lab.renderer.cell_center(cell)
		for cell: Vector2i in _lab.site_controller.view.combat_preview_queue_slots:
			preview_center += _lab.renderer.cell_center(cell)
		_lab.camera.position = preview_center / MEMBERS
		_lab.camera.force_update_scroll()
		await process_frame
		if not await _capture(FILES[0], "Validated final-slot preview during drag"): return
		_lab.camera.position = _lab.renderer.cell_center(Vector2i(29, 26))
		_lab.camera.force_update_scroll()
		await process_frame
	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.position = dragged.position
	if not _require(_lab.site_controller.handle_input(released), "UI did not consume facing release"): return
	if not _require(_lab.site_controller.view.combat_preview_platform_slots.is_empty() and _lab.site_controller.view.combat_preview_queue_slots.is_empty(), "Facing preview must clear after issuing the order"): return
	var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
	if not _require(army.combat_order == TerrainArmy.CombatOrder.MOVE and plan != null and plan.final_facing == FINAL_FACING and (_preset_id.is_empty() or plan.formation_preset_id == _preset_id) and _lab.site_controller._facing_order_source.is_empty(), "UI gesture did not issue the final-facing MOVE: %s preset=%s" % [_lab.site_controller.message.text, plan.formation_preset_id if plan != null else "none"]): return
	if _members == LARGE_MEMBERS:
		await _capture_large_final(plan)
		return
	if not await _capture(FILES[1], "UI MOVE accepted; final facing UP"): return
	while _seconds < 20.0 and _witness < 0:
		if not _advance(): return
		for index in range(1, MEMBERS):
			if army.moving_to[index] != TerrainArmy.INVALID_CELL and army.move_progress[index] > 0.0 and army.move_progress[index] < 0.1:
				_witness = index
				break
	if not _require(_witness >= 1, "No ordinary original member began a physical step within 20 simulated seconds"): return
	var source: Vector2i = army.cells[_witness]
	var target: Vector2i = army.moving_to[_witness]
	var duration: float = army.move_duration[_witness]
	var previous_ground := army.combat_ground(_witness)
	if not _require(duration > 0.0 and data.can_step(source, target), "Witness must use a real legal edge and duration"): return
	if not await _capture(FILES[2], "Same physical step: start"): return
	for sample in range(3):
		var threshold: float = [0.25, 0.5, 0.75][sample]
		while army.move_progress[_witness] < threshold:
			if not _advance(): return
			if not _require(army.cells[_witness] == source and army.moving_to[_witness] == target, "Source occupancy or step destination changed before interpolation completed"): return
		var ground := army.combat_ground(_witness)
		var along := (ground - _lab.renderer.cell_center(source)).dot(Vector2(target - source))
		var previous_along := (previous_ground - _lab.renderer.cell_center(source)).dot(Vector2(target - source))
		if not _require(along > previous_along + 0.1 and along < TerrainRenderer.CELL_PIXELS, "Sub-step ground positions must advance monotonically and stay strictly between the cells"): return
		previous_ground = ground
		if not await _capture(FILES[sample + 3], "Same physical step: %d%%" % roundi(threshold * 100.0)): return
	while army.cells[_witness] == source and _seconds < 25.0:
		if not _advance(): return
	if not _require(army.cells[_witness] == target, "Original step did not commit its reserved destination"): return
	if not await _capture(FILES[6], "Original step committed; source occupancy released"): return
	while army.combat_order == TerrainArmy.CombatOrder.MOVE and _seconds < 60.0:
		if not _advance(): return
		if roundi(_seconds / STEP) % 120 == 0: await process_frame
	if not _require(army.combat_order == TerrainArmy.CombatOrder.HOLD and army.command_status.begins_with("已抵達") and Destination.is_settled(plan, army.get_active_members_occupancy()), "All four must reach exact final slots and HOLD within 60 simulated seconds; " + army.command_status): return
	if not _final_facing(plan): return
	var final_center := Vector2.ZERO
	for cell: Vector2i in army.cells:
		final_center += _lab.renderer.cell_center(cell)
	_lab.camera.position = final_center / MEMBERS
	_lab.camera.force_update_scroll()
	await process_frame
	if not await _capture(FILES[7], "All 4 exact final slots; HOLD; facing UP"): return
	var settled: Array[Vector2i] = army.cells.duplicate()
	var slots: Dictionary = plan.member_slot_map.duplicate()
	for tick in range(roundi(5.0 / STEP)):
		if not _advance(): return
		if not _require(army.cells == settled and plan.member_slot_map == slots and army.combat_order == TerrainArmy.CombatOrder.HOLD, "Final HOLD drifted during five simulated seconds"): return
		if not _final_facing(plan): return
	if not await _capture(FILES[8], "Final HOLD unchanged for 5 simulated seconds"): return
	var record := {"complete": true, "scene": "res://scenes/terrain_lab/TerrainLab.tscn", "input_path": "SiteController facing MOVE press/drag/release handler", "formation_preset_id": _preset_id if not _preset_id.is_empty() else "auto",
		"display_server": DisplayServer.get_name(), "members": MEMBERS, "witness_index": _witness,
		"step_duration": duration, "simulated_seconds": _seconds, "final_facing": [0, -1], "samples": _samples,
		"limitations": "Synthetic UI events; generated flat Site; 4-person original Sprite presenter; no 100-person batch, choke, FPS or physical mouse acceptance. PNGs require human visual inspection."}
	var file := FileAccess.open(_output + "/capture.json", FileAccess.WRITE)
	if not _require(file != null, "Cannot write capture manifest"): return
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	print("COMBAT MOVEMENT VISUAL CAPTURE PASS: 9 PNGs; original step duration=", duration, " final HOLD stable=5s; inspect images at ", _output)
	_lab.clear_army()
	_lab.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _screen_point(cell: Vector2i) -> Vector2:
	return _lab.renderer.get_global_transform_with_canvas() * _lab.renderer.cell_center(cell)

func _advance() -> bool:
	var army := _lab.army
	var previous: Array[Vector2i] = army.cells.duplicate()
	_lab._advance_combat(STEP)
	_seconds += STEP
	var occupied := {}
	var claims := {}
	for index in range(MEMBERS):
		var cell: Vector2i = army.cells[index]
		if not _require(not occupied.has(cell) and army.data.is_walkable(cell) and army._cell_owners.get(cell, -1) == index, "Duplicate, illegal or unowned source occupancy at " + str(cell)): return false
		occupied[cell] = true
		if cell != previous[index] and not _require(army.data.can_step(previous[index], cell), "Physical cell skipped an edge"): return false
		var target: Vector2i = army.moving_to[index]
		if target != TerrainArmy.INVALID_CELL:
			if not _require(army.data.can_step(cell, target) and not claims.has(target), "Illegal or duplicate in-flight target"): return false
			claims[target] = true
	return true

func _final_facing(plan: CombatDeploymentPlan) -> bool:
	var army := _lab.army
	if not _require(army._reserved_cells.is_empty() and _lab.combat_movement_coordinator.get_inflight_batches_for_formation(army).is_empty(), "Final HOLD retained claims or in-flight batches"): return false
	for index in range(MEMBERS):
		if not _require(army.cells[index] == plan.get_slot_for_member(army.combat_identity(index)) and army.moving_to[index] == TerrainArmy.INVALID_CELL and army.facing[index] == FINAL_FACING, "Final slot or facing differs at original member " + str(index)): return false
	return true

func _capture_large_final(plan: CombatDeploymentPlan) -> void:
	var army := _lab.army
	var wall_started := Time.get_ticks_msec()
	var starting_cells: Array[Vector2i] = army.cells.duplicate()
	_frame_large_army(army)
	if not await _capture_large("01_order_100.png", "MOVE accepted / 100 starting cells before physical advance", plan): return
	if not _require(army.cells == starting_cells, "100-person starting cells changed before simulation advanced"): return
	var progress_witness := -1
	for tick in range(9000):
		if army.combat_order == TerrainArmy.CombatOrder.HOLD and Destination.is_settled(plan, army.get_active_members_occupancy()):
			break
		_lab._advance_combat(LARGE_STEP)
		_seconds += LARGE_STEP
		if progress_witness < 0:
			for index in range(1, LARGE_MEMBERS):
				var target: Vector2i = army.moving_to[index]
				if target == TerrainArmy.INVALID_CELL or army.move_progress[index] <= 0.0 or army.move_progress[index] >= 1.0:
					continue
				var source: Vector2i = army.cells[index]
				var center: Vector2 = _lab.renderer.cell_center(source)
				var edge: Vector2 = _lab.renderer.cell_center(target) - center
				var along: float = (army.combat_ground(index) - center).dot(edge) / edge.length_squared()
				if not _require(army._cell_owners.get(source, -1) == index and army.data.can_step(source, target) and along > 0.0 and along < 1.0, "100-person progress witness must be on a real uncommitted physical step"): return
				progress_witness = index
				_frame_large_army(army)
				if not await _capture_large("03_step_in_progress_100.png", "Physical step in progress / source held / nonzero interpolation", plan, progress_witness): return
				break
		if tick % 30 == 0:
			await process_frame
		if not _require(Time.get_ticks_msec() - wall_started < 240000, "100-person completion exceeded 240 wall seconds; " + army.command_status): return
	if not _require(progress_witness >= 1, "100-person MOVE reached HOLD without a captured physical in-progress step"): return
	if not _large_final_valid(plan): return
	var settled: Array[Vector2i] = army.cells.duplicate()
	var facings: Array[Vector2i] = army.facing.duplicate()
	var slots: Dictionary = plan.member_slot_map.duplicate()
	for tick in range(roundi(5.0 / LARGE_STEP)):
		_lab._advance_combat(LARGE_STEP)
		_seconds += LARGE_STEP
		if not _require(army.cells == settled and army.facing == facings and plan.member_slot_map == slots, "100-person final slots or facing drifted during five simulated seconds"): return
		if not _large_final_valid(plan): return
		if tick % 30 == 0: await process_frame
	var bounds := _large_bounds(plan, 2.0)
	_lab.camera.position = bounds.get_center()
	var fit := minf((float(root.size.x) - 120.0) / bounds.size.x, (float(root.size.y) - 160.0) / bounds.size.y)
	_lab.camera.zoom = Vector2.ONE * minf(1.3, fit)
	_lab.camera.force_update_scroll()
	if not await _capture_large("07_final_hold_100.png", "100 exact slots / leases / facing / HOLD stable 5s", plan): return
	if _preset_id == "circle":
		var close_bounds := _large_bounds(plan, 1.0)
		_lab.camera.position = close_bounds.get_center()
		var close_fit := minf((float(root.size.x) - 120.0) / close_bounds.size.x, (float(root.size.y) - 140.0) / close_bounds.size.y)
		_lab.camera.zoom = Vector2.ONE * minf(1.15, close_fit)
		_lab.camera.force_update_scroll()
		if not await _capture_large("08_circle_directions_100.png", "Circle: outward facing on all four sides", plan): return
	var facing_counts := _large_facing_counts(army)
	var record := {"complete": true, "scene": "res://scenes/terrain_lab/TerrainLab.tscn", "input_path": "SiteController facing MOVE press/drag/release handler",
		"formation_preset_id": _preset_id, "display_server": DisplayServer.get_name(), "members": LARGE_MEMBERS,
		"presenter": "TerrainArmy batch MultiMesh", "batch_presented_count": _large_presented_count(army),
		"simulated_seconds": _seconds, "stable_seconds": 5.0, "final_facing": _cell(FINAL_FACING), "progress_witness_index": progress_witness,
		"facing_counts": facing_counts, "samples": _samples,
		"limitations": "Synthetic UI events and generated flat Site; screenshots require human visual inspection. This is not an FPS or physical mouse acceptance run."}
	var file := FileAccess.open(_output + "/capture.json", FileAccess.WRITE)
	if not _require(file != null, "Cannot write 100-person capture manifest"): return
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	print("COMBAT MOVEMENT VISUAL CAPTURE PASS: ", _preset_id, " 100-person batch; exact HOLD stable 5s; inspect ", _output)
	_lab.clear_army()
	_lab.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _large_final_valid(plan: CombatDeploymentPlan) -> bool:
	var army := _lab.army
	if not _require(army.combat_order == TerrainArmy.CombatOrder.HOLD and army.get_active_deployment_plan() == plan and plan.formation_preset_id == _preset_id, "100-person order did not settle on requested preset; " + army.command_status): return false
	if not _require(plan.requested_count == LARGE_MEMBERS and plan.member_slot_map.size() == LARGE_MEMBERS and plan.platform_slots.size() == LARGE_MEMBERS and plan.queue_member_ids.is_empty(), "100-person plan incomplete: units=%d active=%d requested=%d mapped=%d platform=%d queue_members=%d status=%s" % [army.combat_units.size(), army._get_active_member_ids().size(), plan.requested_count, plan.member_slot_map.size(), plan.platform_slots.size(), plan.queue_member_ids.size(), army.command_status]): return false
	if not _require(Destination.is_settled(plan, army.get_active_members_occupancy()) and army._automatic_deployment_settled(), "100-person physical occupancy differs from exact assigned slots"): return false
	if not _require(army._combat_batch_members.is_empty() and army.get_active_movement_claims().is_empty() and _lab.combat_movement_coordinator.get_inflight_batches_for_formation(army).is_empty(), "100-person final HOLD retained movement claims or batches"): return false
	if not _require(army._settled_deployment_leases_valid(), "100-person final slot leases are invalid"): return false
	var registry: SiteDeploymentReservationRegistry = _lab.combat_movement_coordinator.deployment_registry
	var seen := {}
	var directions := {}
	for index in range(LARGE_MEMBERS):
		var member_id: int = army.combat_identity(index)
		var cell: Vector2i = army.cells[index]
		var expected: Vector2i = plan.get_slot_for_member(member_id)
		var expected_facing: Vector2i = plan.get_facing_for_slot(cell)
		if not _require(cell == expected and not seen.has(cell) and army._cell_owners.get(cell, -1) == index and army.moving_to[index] == TerrainArmy.INVALID_CELL and army.facing[index] == expected_facing, "100-person exact slot, source occupancy or facing differs at member " + str(member_id)): return false
		var lease: Variant = registry.owner_of(cell)
		if not _require(lease != null and lease.formation_id == army.team_id and lease.order_serial == plan.order_serial, "100-person slot lease differs at " + str(cell)): return false
		seen[cell] = true
		directions[str(expected_facing)] = true
	if _preset_id == "circle" and not _require(directions.size() == 4, "Circle must face outward in all four cardinal directions"): return false
	return true

func _large_bounds(plan: CombatDeploymentPlan, padding_cells: float) -> Rect2:
	var first: Vector2i = plan.platform_slots[0]
	var minimum := first
	var maximum := first
	for cell: Vector2i in plan.platform_slots:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)
	var cell_size := float(TerrainRenderer.CELL_PIXELS)
	var origin := _lab.renderer.cell_center(minimum) - Vector2.ONE * cell_size * 0.5
	var extent := Vector2(maximum - minimum + Vector2i.ONE) * cell_size
	return Rect2(origin, extent).grow(padding_cells * cell_size)

func _frame_large_army(army: TerrainArmy) -> void:
	var minimum: Vector2i = army.cells[0]
	var maximum: Vector2i = minimum
	for cell: Vector2i in army.cells:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)
	var cell_size := float(TerrainRenderer.CELL_PIXELS)
	var origin := _lab.renderer.cell_center(minimum) - Vector2.ONE * cell_size * 0.5
	var extent := Vector2(maximum - minimum + Vector2i.ONE) * cell_size
	var bounds := Rect2(origin, extent).grow(2.0 * cell_size)
	_lab.camera.position = bounds.get_center()
	var fit := minf((float(root.size.x) - 120.0) / bounds.size.x, (float(root.size.y) - 160.0) / bounds.size.y)
	_lab.camera.zoom = Vector2.ONE * minf(1.3, fit)
	_lab.camera.force_update_scroll()

func _large_presented_count(army: TerrainArmy) -> int:
	var count := 0
	for item: Variant in army._batch_view._batches.values():
		var batch: MultiMeshInstance2D = item as MultiMeshInstance2D
		if batch != null and batch.visible and batch.multimesh != null:
			count += batch.multimesh.instance_count
	for sprite: Sprite2D in army._sprites:
		if sprite != null and sprite.visible and sprite.texture != null:
			count += 1
	return count

func _large_facing_counts(army: TerrainArmy) -> Dictionary:
	var counts := {}
	for facing: Vector2i in army.facing:
		var direction := str(facing)
		counts[direction] = int(counts.get(direction, 0)) + 1
	return counts

func _capture_large(filename: String, label: String, plan: CombatDeploymentPlan, witness_index: int = -1) -> bool:
	var army := _lab.army
	for team: TerrainArmy in _lab.combat_armies:
		team.advance_frame(0.0)
	var presented := _large_presented_count(army)
	if not _require(army._batch_render_active() and army._batch_view != null and army._batch_view.active_batches > 0 and presented == LARGE_MEMBERS, "100-person batch presenter did not display all people: " + str(presented)): return false
	var rows: Array[Dictionary] = []
	var moving_count := 0
	for index in range(LARGE_MEMBERS):
		var cell: Vector2i = army.cells[index]
		if army.moving_to[index] != TerrainArmy.INVALID_CELL: moving_count += 1
		rows.append({"person_id": army.combat_identity(index), "cell": _cell(cell), "assigned_slot": _cell(plan.get_slot_for_member(army.combat_identity(index))),
			"moving_to": _cell(army.moving_to[index]), "move_progress": army.move_progress[index],
			"ground": [army.combat_ground(index).x, army.combat_ground(index).y],
			"facing": _cell(army.facing[index]), "expected_facing": _cell(plan.get_facing_for_slot(cell))})
	var witness := {}
	if witness_index >= 0:
		var source: Vector2i = army.cells[witness_index]
		var target: Vector2i = army.moving_to[witness_index]
		var center: Vector2 = _lab.renderer.cell_center(source)
		var edge: Vector2 = _lab.renderer.cell_center(target) - center
		var along: float = (army.combat_ground(witness_index) - center).dot(edge) / edge.length_squared()
		if not _require(target != TerrainArmy.INVALID_CELL and army._cell_owners.get(source, -1) == witness_index and army.data.can_step(source, target) and army.move_progress[witness_index] > 0.0 and army.move_progress[witness_index] < 1.0 and along > 0.0 and along < 1.0, "Captured 100-person witness lost its physical in-progress step"): return false
		witness = {"index": witness_index, "person_id": army.combat_identity(witness_index), "source": _cell(source), "target": _cell(target),
			"move_progress": army.move_progress[witness_index], "ground_fraction_along_edge": along}
	_caption.text = "%s\nFormal TerrainLab / Army batch presenter / %s / 100 people\nAnchor facing UP / simulation %.2fs" % [label, _preset_id, _seconds]
	for draw in range(2):
		await process_frame
		await RenderingServer.frame_post_draw
	if not _require(root.get_texture().get_image().save_png(_output + "/" + filename) == OK, "Cannot write " + filename): return false
	_samples.append({"image": filename, "label": label, "simulated_seconds": _seconds, "order": army.combat_order,
		"batch_presented_count": presented, "moving_count": moving_count, "witness": witness, "rows": rows,
		"army_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"),
		"coordinator_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")})
	var partial := FileAccess.open(_output + "/capture.json", FileAccess.WRITE)
	if not _require(partial != null, "Cannot preserve 100-person capture diagnostics"): return false
	partial.store_string(JSON.stringify({"complete": false, "samples": _samples}, "\t"))
	partial.close()
	print("MOVE GPU CAPTURE ", filename, " at ", _seconds, "s")
	return true

func _capture(filename: String, label: String) -> bool:
	var army := _lab.army
	for team: TerrainArmy in _lab.combat_armies:
		team.advance_frame(0.0)
	var rows: Array[Dictionary] = []
	for index in range(MEMBERS):
		var frame: Dictionary = army.combat_frame(index)
		var sprite: Sprite2D = army._sprites[index]
		if not _require(sprite != null and sprite.visible and sprite.texture != null and sprite.position.is_equal_approx(army.combat_ground(index) + army.combat_offset(index) - army._unit_anchor(index)), "Original sprite is not anchored to original interpolation at " + str(index)): return false
		if index > 0 and not _require(army._soldier_current_keys[index] == "%s|%s|%d" % [frame.clip, frame.direction, int(frame.frame)], "Original atlas frame does not match original animation time"): return false
		if army.combat_order == TerrainArmy.CombatOrder.HOLD and army.get_active_deployment_plan() != null and not _require(str(frame.direction) == army._soldier_direction_id(FINAL_FACING), "Final rendered facing differs from the requested direction"): return false
		rows.append({"person_id": army.combat_identity(index), "source": _cell(army.cells[index]), "moving_to": _cell(army.moving_to[index]),
			"progress": army.move_progress[index], "duration": army.move_duration[index], "ground": [army.combat_ground(index).x, army.combat_ground(index).y],
			"sprite_position": [sprite.position.x, sprite.position.y], "facing": _cell(army.facing[index]), "clip": frame.clip, "direction": frame.direction, "frame": frame.frame})
	_caption.text = "%s\nFormal TerrainLab / original Army / simulation %.4fs / witness row %d\nGoal %s / final facing UP" % [label, _seconds, _witness, GOAL]
	for draw in range(2):
		await process_frame
		await RenderingServer.frame_post_draw
	if not _require(root.get_texture().get_image().save_png(_output + "/" + filename) == OK, "Cannot write " + filename): return false
	_samples.append({"image": filename, "label": label, "simulated_seconds": _seconds, "order": army.combat_order, "rows": rows,
		"army_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"),
		"coordinator_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")})
	var partial := FileAccess.open(_output + "/capture.json", FileAccess.WRITE)
	if not _require(partial != null, "Cannot preserve capture diagnostics"): return false
	partial.store_string(JSON.stringify({"complete": false, "samples": _samples}, "\t"))
	partial.close()
	print("MOVE GPU CAPTURE ", filename, " at ", _seconds, "s")
	return true

func _cell(value: Vector2i) -> Array[int]:
	return [value.x, value.y]
