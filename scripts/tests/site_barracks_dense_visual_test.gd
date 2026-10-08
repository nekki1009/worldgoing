extends "res://scripts/tests/site_military_building_visual_test.gd"
## Captures the original TerrainLab, SiteResourceView and moving player Actor.
const DENSE_VISUAL_OUTPUT := "res://output/site_barracks_redesign_20261003/visual/"
var dense_visual_output := DENSE_VISUAL_OUTPUT
var dense_captures: Array[Dictionary] = []
var dense_caption: Label
var dense_sizes := {}
var dense_completed := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var output_index := args.find("--barracks-capture-root")
	if output_index >= 0:
		assert(output_index + 1 < args.size(), "A barracks capture root value is required")
		dense_visual_output = str(args[output_index + 1]).trim_suffix("/") + "/"
		assert(dense_visual_output.begins_with("res://output/") and not dense_visual_output.contains(".."), "Barracks captures must stay under res://output/")
	deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Dense visual acceptance requires the original GPU renderer")
	assert(DirAccess.make_dir_recursive_absolute(dense_visual_output) == OK)
	military_lab = _building_lab(_flat_military())
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	military_lab.add_child(overlay)
	dense_caption = Label.new()
	dense_caption.position = Vector2(18, 12)
	dense_caption.add_theme_font_size_override("font_size", 19)
	dense_caption.add_theme_color_override("font_color", Color.WHITE)
	dense_caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	dense_caption.add_theme_constant_override("shadow_offset_x", 2)
	dense_caption.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(dense_caption)
	for quarter: int in range(4): await _dense_facility(10, quarter)
	await _dense_facility(50, 0)
	await _dense_faction_flags()
	if dense_completed != 6 or dense_captures.size() != 15:
		push_error("A dense visual acceptance group stopped before completion")
		quit(1)
		return
	var report := FileAccess.open(dense_visual_output + "captures.json", FileAccess.WRITE)
	assert(report != null)
	report.store_string(JSON.stringify({"status": "SITE_BARRACKS_DENSE_VISUAL_PASS", "captures": dense_captures,
		"scope": "15 original TerrainLab GPU captures: 10x10 four-direction overview/doorway details, 50x50 density, and center/entrance flags for three factions. Real UI default-v2 build and Actor steps; shared module/blocked geometry, fixed sprite sizes and rotated door anchors. Manual image review remains separate."}, "\t"))
	report.close()
	military_lab.free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_BARRACKS_DENSE_VISUAL_PASS: 15 GPU captures; formal UI default-v2 build, 10x10 four directions, 50x50 dense modules, real Actor routes, door anchors and three owner-faction flag palettes")
	quit(0)

func _dense_capture(label: String, bounds: Rect2, details: Dictionary) -> void:
	var actor := military_lab.character
	actor._process(0.0)
	military_lab.site_controller.view.refresh()
	dense_caption.text = "Barracks v2 | %dx%d | q%d | %s\nOriginal TerrainLab / SiteResourceView | %s" % [int(details.side), int(details.side), int(details.quarter), str(details.case), str(details.source)]
	military_lab.camera.position = bounds.get_center()
	military_lab.camera.zoom = Vector2.ONE * minf(2.0, minf(1100.0 / maxf(320.0, bounds.size.x + 180.0), 740.0 / maxf(260.0, bounds.size.y + 180.0)))
	military_lab.camera.reset_smoothing()
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(not picture.is_empty() and picture.save_png(dense_visual_output + label + ".png") == OK)
	details.merge({"file": label + ".png", "barracks_layout_version": 2, "person_id": actor.person_id,
		"cell": [actor.terrain_cell.x, actor.terrain_cell.y], "ground_position": [actor.position.x, actor.position.y],
		"camera_zoom": [military_lab.camera.zoom.x, military_lab.camera.zoom.y],
		"capture_size_pixels": [picture.get_width(), picture.get_height()]}, true)
	if details.has("source_to_world_scale"):
		# Canvas coordinates still precede the root window's content stretch.
		var viewport_final := root.get_final_transform()
		var view_to_capture: Transform2D = viewport_final * military_lab.site_controller.view.get_global_transform_with_canvas()
		var capture_scale := view_to_capture.get_scale().abs()
		details.viewport_final_transform = _dense_transform_values(viewport_final)
		details.world_to_capture_transform = _dense_transform_values(view_to_capture)
		details.world_to_capture_scale = [capture_scale.x, capture_scale.y]
		if details.door_clear_height_world_pixels != null:
			details.door_clear_height_capture_pixels = float(details.door_clear_height_world_pixels) * view_to_capture.y.length()
		var actor_image: Image = actor.player_sprite.texture.get_image()
		var used := actor_image.get_used_rect()
		var sprite_to_capture: Transform2D = viewport_final * actor.player_sprite.get_global_transform_with_canvas()
		var sprite_capture_scale := sprite_to_capture.get_scale().abs()
		var sprite_rect: Rect2 = actor.player_sprite.get_rect()
		var used_in_sprite := Rect2(Vector2(used.position) + sprite_rect.position, Vector2(used.size))
		var used_in_capture: Rect2 = sprite_to_capture * used_in_sprite
		details.actor_sprite = {"texture_size_pixels": [actor_image.get_width(), actor_image.get_height()],
			"used_rect_pixels": [used.position.x, used.position.y, used.size.x, used.size.y],
			"scale": [actor.player_sprite.scale.x, actor.player_sprite.scale.y],
			"texture_origin_in_sprite": [sprite_rect.position.x, sprite_rect.position.y],
			"sprite_to_capture_transform": _dense_transform_values(sprite_to_capture),
			"sprite_to_capture_scale": [sprite_capture_scale.x, sprite_capture_scale.y],
			"used_rect_capture_pixels": [used_in_capture.position.x, used_in_capture.position.y, used_in_capture.size.x, used_in_capture.size.y],
			"used_rect_basis": "Nontransparent rendered silhouette includes equipment; it is not anatomical body height. Capture bounds include sprite/ancestor/camera transforms and the viewport final stretch."}
	assert(Time.get_ticks_msec() < deadline)
	dense_captures.append(details)

func _dense_transform_values(value: Transform2D) -> Array:
	# Transform columns: local X, local Y, origin; each pair is in capture pixels.
	return [[value.x.x, value.x.y], [value.y.x, value.y.y], [value.origin.x, value.origin.y]]

func _dense_facility(side: int, quarter: int) -> void:
	var data := _reset_military()
	var controller: SiteController = military_lab.site_controller
	var view: SiteResourceView = controller.view
	var key: String
	if side == 10 and quarter == 0:
		# A real construction-window choice must reach Runtime's new default.
		_choose(controller, "barracks", Vector2i(20, 20), Vector2i(side, side))
		controller.building_direction.select(0)
		controller.building_direction.item_selected.emit(0)
		assert(not controller._building_options().has("barracks_layout_version"))
		_press(military_lab, "BuildFeature")
		key = controller.feature_key
		assert(not key.is_empty())
		_complete_key(data, key)
		controller.release_worker()
		controller.hide_tool_windows()
	else:
		key = _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(side, side), {"quarter": quarter, "barracks_layout_version": 2})
	var feature: Dictionary = data.site.features[key]
	assert(int(feature.barracks_layout_version) == 2 and int(feature.quarter) == quarter)
	assert(str(feature.stage) == "complete" and Runtime.validate_feature_layout(data, feature).ok)
	var modules := Runtime.military_modules(data, feature)
	var geometry := Runtime.feature_geometry(data, feature)
	var standing := Runtime.military_walkable_cells(data, feature)
	var blocked := {}
	var dormitories: Array[Dictionary] = []
	var houses := 0
	for module: Dictionary in modules:
		if str(module.kind) == "barracks_dormitory":
			dormitories.append(module)
			assert(module.base_size == Vector2i(3, 2) and int(module.quarter) == quarter)
			assert(Runtime._cell_bounds(data, module.cells).size == (Vector2i(2, 3) if quarter % 2 else Vector2i(3, 2)))
		else:
			assert(str(module.kind) == "house" and str(module.variant) == "small")
			houses += 1
		for index: int in module.cells:
			assert(feature.cells.has(index) and not blocked.has(index) and geometry.blocked.has(index) and data.static_blocked[index] == 1)
			blocked[index] = true
	assert(houses == 1 and dormitories.size() == (6 if side == 10 else 192))
	assert(blocked.size() == geometry.blocked.size() and standing.size() + blocked.size() == side * side)
	assert(Runtime.military_capacity(data, feature) == (60 if side == 10 else 1344))
	for index: int in standing: assert(not blocked.has(index) and data.is_walkable(data.cell_from_index(index)))
	var draws := view.building_part_draws(feature)
	var dorm_draws: Array[Dictionary] = []
	var ground_count := 0
	var flag_count := 0
	var fence_count := 0
	for part: Dictionary in draws:
		var asset_key := str(part.asset_key)
		if asset_key == "road": ground_count += 1
		elif asset_key.begins_with("barracks_dormitory_"): dorm_draws.append(part)
		elif asset_key == "barracks_flag": flag_count += 1
		elif str(part.part_id).begins_with("barracks:fence:"): fence_count += 1
	assert(ground_count == side * side and dorm_draws.size() == dormitories.size() and flag_count == 3 and fence_count > 0)
	var source_files := {}
	for index: int in range(dormitories.size()):
		var module: Dictionary = dormitories[index]
		var part: Dictionary = dorm_draws[index]
		var asset_key: String = "barracks_dormitory_" + ["south", "west", "north", "east"][quarter]
		assert(str(part.asset_key) == asset_key)
		var art := view._building_asset(asset_key)
		assert(art.has("door_sill_anchor") and not str(art.file).is_empty())
		var anchor := Vector2(float(art.door_sill_anchor[0]), float(art.door_sill_anchor[1]))
		var door: Vector2 = part.rect.position + part.rect.size * anchor
		assert(door.is_equal_approx(view._building_local_point(module, Vector2(float(module.base_size.x) * 0.5, float(module.base_size.y)))), "Dormitory pixels drifted from their rotated physical doorway")
		if dense_sizes.has(asset_key): assert(Vector2(dense_sizes[asset_key]).is_equal_approx(part.rect.size), "Increasing the compound stretched a dormitory sprite")
		else: dense_sizes[asset_key] = part.rect.size
		source_files[str(art.file)] = true
	var actor := military_lab.character
	assert(actor.place(data.cell_from_index(int(feature.entrance)), true))
	var center := Runtime._layout_cell(Vector2i(floori(float(side) * 0.5), side - 2), Vector2i(side, side), quarter, Vector2i(20, 20))
	assert(standing.has(data.index(center)))
	_military_walk(center)
	assert(actor.terrain_cell == center and not actor.is_moving(), "Original Actor passage walk stopped before its destination")
	var details := {"side": side, "quarter": quarter, "case": "dense compound / original Actor in shared passage", "source": ", ".join(source_files.keys()),
		"asset_files": source_files.keys(), "dormitories": dormitories.size(), "houses": houses, "flags": flag_count, "fence_parts": fence_count, "capacity": standing.size(), "blocked": blocked.size()}
	var bounds := view.building_art_bounds(feature).merge(Rect2(Vector2(20, 20) * 64.0, Vector2(side, side) * 64.0))
	await _dense_capture("barracks_%d_q%d" % [side, quarter], bounds, details)
	if side == 10:
		var module: Dictionary = dormitories[0]
		var module_bounds := Runtime._cell_bounds(data, module.cells)
		var doorstep := Runtime._layout_cell(Vector2i(floori(float(module.base_size.x) * 0.5), module.base_size.y), module.base_size, quarter, module_bounds.position)
		assert(standing.has(data.index(doorstep)), "A dormitory front door has no connected standing cell")
		_military_walk(doorstep)
		assert(actor.terrain_cell == doorstep and not actor.is_moving(), "Original Actor doorway walk stopped before its destination")
		var closeup := Rect2(military_lab.character.position - Vector2(280, 270), Vector2(560, 440))
		var detail := details.duplicate(true)
		detail.case = "dormitory doorway / player walked along original passage"
		detail.module_physical_size = [module_bounds.size.x, module_bounds.size.y]
		detail.sprite_rect = [dorm_draws[0].rect.position.x, dorm_draws[0].rect.position.y, dorm_draws[0].rect.size.x, dorm_draws[0].rect.size.y]
		var art := view._building_asset(str(dorm_draws[0].asset_key))
		var region: Rect2 = art.region
		var sprite_rect: Rect2 = dorm_draws[0].rect
		var source_scale := sprite_rect.size / region.size
		var calibration: Dictionary = art.get("source_calibration", {})
		detail.source_file = str(art.file)
		detail.source_bbox_pixels = [region.position.x, region.position.y, region.size.x, region.size.y]
		detail.source_texture_size_pixels = [art.texture.get_width(), art.texture.get_height()]
		detail.source_to_world_scale = [source_scale.x, source_scale.y]
		detail.source_scale_is_uniform = is_equal_approx(source_scale.x, source_scale.y)
		detail.door_visible = bool(art.get("door_visible", calibration.get("door_visible", false)))
		detail.door_clear_height_source_pixels = null
		detail.door_clear_height_world_pixels = null
		detail.door_clear_height_capture_pixels = null
		if detail.door_visible and calibration.has("door_clear_height_pixels"):
			detail.door_clear_height_source_pixels = float(calibration.door_clear_height_pixels)
			detail.door_clear_height_world_pixels = float(calibration.door_clear_height_pixels) * source_scale.y
		detail.door_height_basis = "Manifest clear opening height projected at the current scale; hidden doors remain null. No metre or anatomical-height acceptance."
		await _dense_capture("barracks_10_q%d_door_detail" % quarter, closeup, detail)
	dense_completed += 1

func _dense_faction_flags() -> void:
	var data := _reset_military()
	var view: SiteResourceView = military_lab.site_controller.view
	var key := _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(10, 10), {"barracks_layout_version": 2})
	var feature: Dictionary = data.site.features[key]
	var original_geometry := Runtime.feature_geometry(data, feature)
	var original_blocked := data.static_blocked.duplicate()
	var colors := {}
	assert(military_lab.character.place(data.cell_from_index(int(feature.entrance)), true))
	_military_walk(Vector2i(25, 28))
	assert(military_lab.character.terrain_cell == Vector2i(25, 28) and not military_lab.character.is_moving())
	for faction: int in [1, 2, 3]:
		feature.owner_faction = faction # Fixture changes the original feature's sole ownership field.
		var expected_palette := SiteEquipmentOrders.npc_palette_id(faction)
		var expected_color := Color(str(Runtime.EquipmentDye.PRESETS[expected_palette].colors.armor))
		var flag_parts := {}
		for part: Dictionary in view.building_part_draws(feature):
			if str(part.asset_key) != "barracks_flag": continue
			assert(int(part.owner_faction) == faction and str(part.palette_id) == expected_palette and Color(part.flag_color).is_equal_approx(expected_color))
			flag_parts[str(part.part_id)] = part
		assert(flag_parts.size() == 3 and flag_parts.has("flag:center") and flag_parts.has("flag:entrance:left") and flag_parts.has("flag:entrance:right"))
		assert(Runtime.feature_geometry(data, feature) == original_geometry and data.static_blocked == original_blocked, "Changing a visual flag changed physical military occupancy")
		colors[expected_color.to_html()] = true
		var details := {"side": 10, "quarter": 0, "case": "faction %d / central flag" % faction, "source": "owner_faction -> existing equipment palette " + expected_palette,
			"owner_faction": faction, "palette_id": expected_palette, "flag_color": expected_color.to_html()}
		var center: Vector2 = flag_parts["flag:center"].flag_base
		await _dense_capture("flags_faction_%d_center" % faction, Rect2(center - Vector2(230, 280), Vector2(460, 400)), details)
		var gate_bounds: Rect2 = flag_parts["flag:entrance:left"].rect.merge(flag_parts["flag:entrance:right"].rect)
		var entrance_details := details.duplicate(true)
		entrance_details.case = "faction %d / both entrance flags" % faction
		await _dense_capture("flags_faction_%d_entrance" % faction, gate_bounds.grow(120.0), entrance_details)
	assert(colors.size() == 3, "Three fixture factions did not receive distinguishable flag colors")
	dense_completed += 1
