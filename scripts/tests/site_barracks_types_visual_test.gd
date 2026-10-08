extends "res://scripts/tests/site_barracks_dense_visual_test.gd"
## Original GPU view, construction window and Actor; captures never touch formal saves.
const TYPES_VISUAL_ROOT := "res://output/site_barracks_two_types_20261003/visual/"
var typed_geometry := {}
var typed_assets := {}
var typed_ui_captures := 0

func _initialize() -> void:
	dense_visual_output = TYPES_VISUAL_ROOT
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Two-type visual acceptance requires the original GPU renderer")
	assert(DirAccess.make_dir_recursive_absolute(TYPES_VISUAL_ROOT) == OK)
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
	for camp_type: String in ["standard", "chinese"]:
		for quarter: int in range(4): await _typed_facility(camp_type, 10, quarter)
		await _typed_facility(camp_type, 50, 0)
		await _typed_flags(camp_type)
	if dense_completed != 12 or dense_captures.size() != 40 or typed_assets.size() != 16 or typed_ui_captures != 2:
		push_error("Two-type GPU acceptance incomplete: groups=%d/12 captures=%d/40 assets=%d/16 UI=%d/2" % [dense_completed, dense_captures.size(), typed_assets.size(), typed_ui_captures])
		quit(1)
		return
	var report := FileAccess.open(TYPES_VISUAL_ROOT + "captures.json", FileAccess.WRITE)
	assert(report != null)
	report.store_string(JSON.stringify({"status": "SITE_BARRACKS_TYPES_VISUAL_PASS", "captures": dense_captures, "asset_files": typed_assets,
		"scope": "40 original GPU captures: both formal construction choices; standard/Chinese 10x10 four-direction compound, dormitory and HQ views; two 50x50 densities; both types' original faction flags. Real Actor steps, shared physical geometry, fixed sprite sizes, distinct module artwork and projected door anchors. Manual appearance review and native parity are separate."}, "\t"))
	report.close()
	military_lab.free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_BARRACKS_TYPES_VISUAL_PASS: 40 GPU captures, two original construction choices, 16 directional dormitory/HQ assets, same Runtime geometry, fixed density sizes, real Actor routes and original faction flags")
	quit(0)

func _typed_ui(camp_type: String) -> void:
	var controller: SiteController = military_lab.site_controller
	military_lab.get_node("SiteUI").show()
	controller.open_window("construction")
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var window: Window = controller.formal_windows.construction
	var choice_text := controller.buildings.get_item_text(controller.buildings.selected)
	var description := Runtime.barracks_type_description({"kind": "barracks", "camp_type": camp_type})
	assert(window.visible and controller.buildings.is_visible_in_tree() and controller.building_policy.is_visible_in_tree())
	assert(choice_text == Runtime.barracks_type_name({"kind": "barracks", "camp_type": camp_type}))
	assert(controller.building_policy.text.contains(description) and controller._building_options().camp_type == camp_type)
	var text_width := controller.buildings.get_theme_font("font").get_string_size(choice_text, HORIZONTAL_ALIGNMENT_LEFT, -1, controller.buildings.get_theme_font_size("font_size")).x
	assert(controller.buildings.size.x >= text_width + 32.0, "The original construction type label is clipped")
	var picture := window.get_texture().get_image()
	var file := "construction_%s.png" % camp_type
	assert(not picture.is_empty() and picture.save_png(TYPES_VISUAL_ROOT + file) == OK)
	dense_captures.append({"file": file, "case": "original construction window", "camp_type": camp_type,
		"name": choice_text, "description": description, "capture_size_pixels": [picture.get_width(), picture.get_height()]})
	typed_ui_captures += 1
	military_lab.get_node("SiteUI").hide()

func _typed_facility(camp_type: String, side: int, quarter: int) -> void:
	var data := _reset_military()
	var controller: SiteController = military_lab.site_controller
	var view: SiteResourceView = controller.view
	var key: String
	if side == 10 and quarter == 0:
		_choose(controller, "barracks", Vector2i(20, 20), Vector2i(side, side), camp_type)
		controller.building_direction.select(0)
		controller.building_direction.item_selected.emit(0)
		assert(not controller._building_options().has("barracks_layout_version"))
		await _typed_ui(camp_type)
		_press(military_lab, "BuildFeature")
		key = controller.feature_key
		assert(not key.is_empty())
		_complete_key(data, key)
		controller.release_worker()
		controller.hide_tool_windows()
	else:
		key = _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(side, side), {"quarter": quarter, "barracks_layout_version": 2, "camp_type": camp_type})
	var feature: Dictionary = data.site.features[key]
	assert(feature.camp_type == camp_type and int(feature.barracks_layout_version) == 2 and int(feature.quarter) == quarter)
	assert(str(feature.stage) == "complete" and Runtime.validate_feature_layout(data, feature).ok)
	var modules := Runtime.military_modules(data, feature)
	var geometry := Runtime.feature_geometry(data, feature)
	var standing := Runtime.military_walkable_cells(data, feature)
	var shape := {"modules": modules, "blocked": geometry.blocked, "standing": standing, "capacity": Runtime.military_capacity(data, feature)}
	var shape_key := "%d:%d" % [side, quarter]
	if typed_geometry.has(shape_key): assert(shape == typed_geometry[shape_key], "A visual camp type changed the existing physical geometry")
	else: typed_geometry[shape_key] = shape
	var blocked := {}
	var dormitories: Array[Dictionary] = []
	var hq: Dictionary = {}
	for module: Dictionary in modules:
		if str(module.kind) == "barracks_dormitory":
			dormitories.append(module)
			assert(module.base_size == Vector2i(3, 2) and int(module.quarter) == quarter)
			assert(Runtime._cell_bounds(data, module.cells).size == (Vector2i(2, 3) if quarter % 2 else Vector2i(3, 2)))
		else:
			assert(hq.is_empty() and str(module.kind) == "house" and str(module.variant) == "small")
			hq = module
			assert(Runtime._cell_bounds(data, module.cells).size == Vector2i(2, 2))
		for index: int in module.cells:
			assert(feature.cells.has(index) and not blocked.has(index) and geometry.blocked.has(index) and data.static_blocked[index] == 1)
			blocked[index] = true
	assert(not hq.is_empty() and dormitories.size() == (6 if side == 10 else 192))
	assert(blocked.size() == geometry.blocked.size() and standing.size() + blocked.size() == side * side)
	assert(Runtime.military_capacity(data, feature) == (60 if side == 10 else 1344))
	for index: int in standing: assert(not blocked.has(index) and data.is_walkable(data.cell_from_index(index)))
	var direction: String = ["south", "west", "north", "east"][quarter]
	var dorm_key := ("barracks_chinese_dormitory_" if camp_type == "chinese" else "barracks_dormitory_") + direction
	var hq_key := ("barracks_chinese_hq_" if camp_type == "chinese" else "house_small_") + direction
	var dorm_draws: Array[Dictionary] = []
	var hq_draw: Dictionary = {}
	var ground_count := 0
	var flag_count := 0
	var fence_count := 0
	for part: Dictionary in view.building_part_draws(feature):
		var asset_key := str(part.asset_key)
		if asset_key == "road": ground_count += 1
		elif asset_key == dorm_key: dorm_draws.append(part)
		elif asset_key == hq_key:
			assert(hq_draw.is_empty())
			hq_draw = part
		elif asset_key == "barracks_flag": flag_count += 1
		elif str(part.part_id).begins_with("barracks:fence:"): fence_count += 1
	assert(ground_count == side * side and dorm_draws.size() == dormitories.size() and not hq_draw.is_empty() and flag_count == 3 and fence_count > 0)
	var source_files := {}
	for index: int in range(dormitories.size()):
		_typed_anchor(view, dormitories[index], dorm_draws[index], Vector2i(3, 2))
		var part: Dictionary = dorm_draws[index]
		source_files[str(part.file)] = true
	_typed_anchor(view, hq, hq_draw, Vector2i(2, 2))
	assert(str(hq_draw.file) != str(dorm_draws[0].file), "The headquarters must have its own source image")
	source_files[str(hq_draw.file)] = true
	var actor := military_lab.character
	assert(actor.place(data.cell_from_index(int(feature.entrance)), true))
	var centre := Runtime._layout_cell(Vector2i(floori(float(side) * 0.5), side - 2), Vector2i(side, side), quarter, Vector2i(20, 20))
	assert(standing.has(data.index(centre)))
	_military_walk(centre)
	assert(actor.terrain_cell == centre and not actor.is_moving(), "The original Actor did not reach the common passage")
	var details := {"camp_type": camp_type, "side": side, "quarter": quarter, "case": camp_type + " compound / original Actor in shared passage",
		"source": ", ".join(source_files.keys()), "asset_files": source_files.keys(), "dormitories": dormitories.size(), "houses": 1,
		"flags": flag_count, "fence_parts": fence_count, "capacity": standing.size(), "blocked": blocked.size()}
	var bounds := view.building_art_bounds(feature).merge(Rect2(Vector2(20, 20) * 64.0, Vector2(side, side) * 64.0))
	await _dense_capture("%s_%d_q%d" % [camp_type, side, quarter], bounds, details)
	if side == 10:
		await _typed_door(camp_type, "dormitory", dormitories[0], dorm_draws[0], Vector2i(3, 2), standing, details)
		await _typed_door(camp_type, "hq", hq, hq_draw, Vector2i(2, 2), standing, details)
	dense_completed += 1

func _typed_anchor(view: SiteResourceView, module: Dictionary, part: Dictionary, base_size: Vector2i) -> void:
	var art := view._building_asset(str(part.asset_key))
	assert(art.has("door_sill_anchor") and not str(art.file).is_empty())
	var anchor := Vector2(float(art.door_sill_anchor[0]), float(art.door_sill_anchor[1]))
	var doorway: Vector2 = part.rect.position + part.rect.size * anchor
	assert(doorway.is_equal_approx(view._building_local_point(module, Vector2(float(base_size.x) * 0.5, float(base_size.y)))), "Module pixels drifted from the original rotated door anchor")
	var asset_key := str(part.asset_key)
	if dense_sizes.has(asset_key): assert(Vector2(dense_sizes[asset_key]).is_equal_approx(part.rect.size), "Density or type stretched a fixed module sprite")
	else: dense_sizes[asset_key] = part.rect.size
	if typed_assets.has(asset_key): assert(typed_assets[asset_key] == str(art.file))
	else: typed_assets[asset_key] = str(art.file)

func _typed_door(camp_type: String, role: String, module: Dictionary, part: Dictionary, base_size: Vector2i, standing: Array[int], details: Dictionary) -> void:
	var data := military_lab.terrain
	var view: SiteResourceView = military_lab.site_controller.view
	var actor := military_lab.character
	var module_bounds := Runtime._cell_bounds(data, module.cells)
	var doorstep := Runtime._layout_cell(Vector2i(floori(float(base_size.x) * 0.5), base_size.y), base_size, int(module.quarter), module_bounds.position)
	assert(standing.has(data.index(doorstep)), "The module has no connected standing cell at its physical door")
	_military_walk(doorstep)
	assert(actor.terrain_cell == doorstep and not actor.is_moving(), "The original Actor did not reach the module doorway")
	var detail := details.duplicate(true)
	detail.case = "%s %s doorway / original Actor walked through the common passage" % [camp_type, role]
	detail.module_role = role
	detail.module_physical_size = [module_bounds.size.x, module_bounds.size.y]
	detail.sprite_rect = [part.rect.position.x, part.rect.position.y, part.rect.size.x, part.rect.size.y]
	var art := view._building_asset(str(part.asset_key))
	var region: Rect2 = art.region
	var sprite_rect: Rect2 = part.rect
	var source_scale := sprite_rect.size / region.size
	var calibration: Dictionary = art.get("source_calibration", {})
	detail.source_file = str(art.file)
	detail.asset_key = str(part.asset_key)
	detail.source_bbox_pixels = [region.position.x, region.position.y, region.size.x, region.size.y]
	detail.source_texture_size_pixels = [art.texture.get_width(), art.texture.get_height()]
	detail.source_to_world_scale = [source_scale.x, source_scale.y]
	detail.source_scale_is_uniform = is_equal_approx(source_scale.x, source_scale.y)
	assert(detail.source_scale_is_uniform, "Directional source was stretched unevenly")
	detail.door_visible = bool(art.get("door_visible", calibration.get("door_visible", false)))
	detail.door_clear_height_source_pixels = null
	detail.door_clear_height_world_pixels = null
	detail.door_clear_height_capture_pixels = null
	if detail.door_visible and calibration.has("door_clear_height_pixels"):
		detail.door_clear_height_source_pixels = float(calibration.door_clear_height_pixels)
		detail.door_clear_height_world_pixels = float(calibration.door_clear_height_pixels) * source_scale.y
	detail.door_height_basis = "Manifest opening height at the actual source/world/capture transforms; hidden doors remain null. This is not metre or anatomical-height acceptance."
	var closeup := Rect2(actor.position - Vector2(280, 270), Vector2(560, 440))
	await _dense_capture("%s_10_q%d_%s_detail" % [camp_type, int(details.quarter), role], closeup, detail)

func _typed_flags(camp_type: String) -> void:
	var data := _reset_military()
	var view: SiteResourceView = military_lab.site_controller.view
	var key := _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(10, 10), {"barracks_layout_version": 2, "camp_type": camp_type})
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
		assert(Runtime.feature_geometry(data, feature) == original_geometry and data.static_blocked == original_blocked, "A faction palette changed physical occupancy")
		colors[expected_color.to_html()] = true
		var details := {"camp_type": camp_type, "side": 10, "quarter": 0, "case": "%s faction %d / central flag" % [camp_type, faction],
			"source": "owner_faction -> existing equipment palette " + expected_palette, "owner_faction": faction,
			"palette_id": expected_palette, "flag_color": expected_color.to_html()}
		var centre: Vector2 = flag_parts["flag:center"].flag_base
		await _dense_capture("%s_flags_%d_center" % [camp_type, faction], Rect2(centre - Vector2(230, 280), Vector2(460, 400)), details)
		var gate_bounds: Rect2 = flag_parts["flag:entrance:left"].rect.merge(flag_parts["flag:entrance:right"].rect)
		var entrance_details := details.duplicate(true)
		entrance_details.case = "%s faction %d / both entrance flags" % [camp_type, faction]
		await _dense_capture("%s_flags_%d_entrance" % [camp_type, faction], gate_bounds.grow(120.0), entrance_details)
	assert(colors.size() == 3, "Three original fixture factions must remain distinguishable")
	dense_completed += 1
