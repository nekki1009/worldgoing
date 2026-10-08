extends "res://scripts/tests/site_siege_generated_art_visual_test.gd"
## A separate GPU fixture for manual ground landmarks; no siege gameplay records.
const CALIBRATION_OUT := "res://output/site_siege_direction_calibration_20261004/visual"
const AXIS_CROSS_LIMIT := 0.02
const GROUND_EPSILON_PIXELS := 1.0
const FOOTPRINTS := {"ram": Vector2i(2, 3), "ballista": Vector2i(2, 3), "traction_trebuchet": Vector2i(3, 4), "counterweight_trebuchet": Vector2i(4, 6), "siege_ladder": Vector2i(1, 2), "siege_tower": Vector2i(3, 4)}
const PRESERVED_BALLISTA := {
	"right": {"source": "ballista_right.png", "sha256": "2cff9007c7a19d66afdd86819df268c88b291584091ffb3a50b573269ee19836", "pivot": Vector2(912.206897, 751.534483), "scale": 0.145, "muzzle": Vector2(1486, 420.5)},
	"left": {"source": "ballista_left.png", "sha256": "02795e629f51dca13445b07abf4d476e4065798b6eb5123055e47c3cfcb55fee", "pivot": Vector2(597.793103, 751.034483), "scale": 0.145, "muzzle": Vector2(24, 420)},
	"down": {"source": "ballista_down.png", "sha256": "c2a9bbfc7360eef33deb2c947658ff1592be96a5de9f0ffa5a405795f48a62a5", "pivot": Vector2(767, 794.487179), "scale": 0.195, "muzzle": Vector2(767, 975)},
	"up": {"source": "ballista_up.png", "sha256": "860d1c7d9bc0aa9bc36ae8868d72a872e54255bb7dd86dc7a7f8ad27230b474f", "pivot": Vector2(767.5, 690.820513), "scale": 0.195, "muzzle": Vector2(767.5, 18)}
}
var calibration_manifest: Dictionary = {}
var ground_checks: Array[Dictionary] = []
var source_hashes: Dictionary = {}
var new_sources: Dictionary = {}
var preserved_ballista_checks: Array[Dictionary] = []
var ground_rectangles: Array[Dictionary] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and not failed and Time.get_ticks_msec() > deadline:
		_check(false, "120-second calibration deadline", {"frames": completed.frames, "ground_axes": ground_checks.size(), "captures": captures.size()})
	return false

func _check(condition: bool, message: String, details: Dictionary = {}) -> bool:
	if failed: return false
	if condition: return true
	failed = true
	push_error("SIEGE_DIRECTION_CALIBRATION_FAIL " + message + " " + JSON.stringify(details))
	quit(1)
	return false

func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

func _point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])

func _v2(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func _pair(value: Vector2) -> Array:
	return [value.x, value.y]

func _source_hash(source: String) -> String:
	if not source_hashes.has(source): source_hashes[source] = FileAccess.get_sha256(source)
	return str(source_hashes[source])

func _check_preserved_ballista(facing: Vector2i, direction: String) -> bool:
	var frame: Dictionary = view.siege_art_frame("ballista", facing)
	var expected: Dictionary = PRESERVED_BALLISTA[direction]
	var digest: String = _source_hash(str(frame.source))
	if not _check(str(frame.source).get_file() == str(expected.source) and digest == str(expected.sha256)
		and frame.region == Rect2(0, 0, 1536, 1024) and frame.pivot.is_equal_approx(expected.pivot)
		and is_equal_approx(float(frame.scale), float(expected.scale)) and frame.has("muzzle") and frame.muzzle.is_equal_approx(expected.muzzle),
		"Original ballista image/pivot/scale/muzzle changed", {"direction": direction, "sha256": digest}): return false
	preserved_ballista_checks.append({"direction": direction, "source": frame.source, "sha256": digest, "pivot": _pair(frame.pivot), "scale": frame.scale, "muzzle": _pair(frame.muzzle), "preserved": true})
	return true

func _envelope(kind: String, facing: Vector2i, centre: Vector2) -> Dictionary:
	var footprint: Vector2i = FOOTPRINTS[kind]
	var forward := Vector2(facing)
	var side := Vector2(-facing.y, facing.x)
	var half_forward: float = footprint.y * TerrainRenderer.CELL_PIXELS * 0.5
	var half_side: float = footprint.x * TerrainRenderer.CELL_PIXELS * 0.5
	var corners: Array[Vector2] = [centre - forward * half_forward - side * half_side, centre + forward * half_forward - side * half_side,
		centre + forward * half_forward + side * half_side, centre - forward * half_forward + side * half_side]
	var extent := Vector2i(absi(facing.x) * footprint.y + absi(facing.y) * footprint.x, absi(facing.y) * footprint.y + absi(facing.x) * footprint.x)
	var anchor_value: Vector2 = centre / TerrainRenderer.CELL_PIXELS - Vector2.ONE * 0.5 - forward * (footprint.y - 1) * 0.5 - side * (footprint.x - 1) * 0.5
	return {"footprint": footprint, "rotated_extent": extent, "centre": centre, "corners": corners, "anchor": anchor_value, "forward": forward, "side": side, "half_forward": half_forward, "half_side": half_side}

func _check_ground(sprite: Sprite2D, kind: String, facing: Vector2i, direction: String, envelope: Dictionary) -> bool:
	var definition: Dictionary = calibration_manifest.entries[kind]
	var raw_frame: Dictionary = definition.frames[direction]
	var frame: Dictionary = view.siege_art_frame(kind, facing)
	var calibration_value: Variant = raw_frame.get("calibration")
	if not _check(calibration_value is Dictionary, "Manual landmark metadata missing", {"kind": kind, "direction": direction}): return false
	var calibration: Dictionary = calibration_value
	for key: String in ["ground_center", "front", "rear", "side0", "side1"]:
		if not _check(_point(calibration.get(key)), "Malformed manual ground point", {"kind": kind, "direction": direction, "key": key}): return false
	var points_value: Variant = calibration.get("ground_points")
	if not _check(points_value is Array and points_value.size() >= 4, "At least four declared ground contacts required", {"kind": kind, "direction": direction}): return false
	var source: String = str(frame.source)
	var digest: String = _source_hash(source)
	if not _check(digest.length() == 64 and digest == str(calibration.get("source_sha256", "")), "Manual landmarks refer to different source pixels", {"kind": kind, "direction": direction, "sha256": digest}): return false
	if not _check(not new_sources.has(source), "Calibrated directions must have unique source PNGs", {"source": source}): return false
	new_sources[source] = true
	if not _check(frame.region == Rect2(Vector2.ZERO, Vector2(frame.image_size)) and not frame.reference_region.has_area() and frame.exclusions.is_empty(),
		"New cardinal PNG must use full region without reference/masks", {"kind": kind, "direction": direction}): return false
	var image_value: Image = _image_cache[source]
	var clear_samples: int = 0
	for y in range(0, image_value.get_height(), 16):
		for x in range(0, image_value.get_width(), 16):
			if image_value.get_pixel(x, y).a <= 0.01: clear_samples += 1
	if not _check(clear_samples > 0, "Calibrated PNG has no transparent samples", {"source": source}): return false
	var ground_centre: Vector2 = _v2(calibration.ground_center)
	if not _check(ground_centre.is_equal_approx(frame.pivot), "Pivot differs from declared ground centre", {"kind": kind, "direction": direction}): return false
	var centre_world: Vector2 = sprite.to_global(ground_centre + sprite.offset)
	var pivot_error: float = centre_world.distance_to(envelope.centre)
	if not _check(pivot_error < 0.01, "Original Sprite does not align the ground centre", {"kind": kind, "direction": direction, "pixels": pivot_error}): return false
	var forward_axis: Vector2 = _v2(calibration.front) - _v2(calibration.rear)
	var side_axis: Vector2 = _v2(calibration.side1) - _v2(calibration.side0)
	if not _check(forward_axis.length() > 1.0 and side_axis.length() > 1.0, "Manual ground axes are degenerate", {"kind": kind, "direction": direction}): return false
	var forward_cross: float = absf(forward_axis.normalized().cross(envelope.forward))
	var side_cross: float = absf(side_axis.normalized().cross(envelope.side))
	if not _check(forward_axis.normalized().dot(envelope.forward) > 0.0 and side_axis.normalized().dot(envelope.side) > 0.0
		and forward_cross <= AXIS_CROSS_LIMIT and side_cross <= AXIS_CROSS_LIMIT,
		"Declared ground axes/heading are not cardinal", {"kind": kind, "direction": direction, "forward_cross": forward_cross, "side_cross": side_cross}): return false
	var ground_rows: Array[Dictionary] = []
	for point_value: Variant in points_value:
		if not _check(_point(point_value), "Malformed contact point", {"kind": kind, "direction": direction}): return false
		var pixel: Vector2 = _v2(point_value)
		if not _check(Rect2(Vector2.ZERO, Vector2(frame.image_size)).has_point(pixel), "Ground landmark is outside source", {"kind": kind, "direction": direction, "point": _pair(pixel)}): return false
		var world: Vector2 = sprite.to_global(pixel + sprite.offset)
		var relative: Vector2 = world - envelope.centre
		var forward_distance: float = relative.dot(envelope.forward)
		var side_distance: float = relative.dot(envelope.side)
		if not _check(absf(forward_distance) <= float(envelope.half_forward) + GROUND_EPSILON_PIXELS and absf(side_distance) <= float(envelope.half_side) + GROUND_EPSILON_PIXELS,
			"Declared contact exceeds logical ground envelope", {"kind": kind, "direction": direction, "point": _pair(pixel), "forward_pixels": forward_distance, "side_pixels": side_distance}): return false
		ground_rows.append({"source_point": _pair(pixel), "world_point": _pair(world), "forward_pixels": forward_distance, "side_pixels": side_distance})
	ground_checks.append({"kind": kind, "direction": direction, "source": source, "sha256": digest, "method": calibration.get("method", ""),
		"details": calibration.get("details", ""), "ground_point_status": calibration.get("ground_point_status", ""), "source_landmarks": calibration,
		"pivot_error_pixels": pivot_error, "forward_axis_normalized_cross": forward_cross, "side_axis_normalized_cross": side_cross,
		"axis_cross_limit": AXIS_CROSS_LIMIT, "contact_epsilon_pixels": GROUND_EPSILON_PIXELS, "ground_points": ground_rows,
		"transparent_samples_step16": clear_samples, "uniform_scale": frame.scale, "declared_contact_fit_inside": true})
	return true

func _fixture_line(parent: Node2D, points: Array[Vector2], colour: Color, width: float = 2.0) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array(points)
	line.default_color = colour
	line.width = width
	line.z_index = 100
	parent.add_child(line)

func _fixture_label(parent: Node2D, text_value: String, point_value: Vector2, size: int = 20) -> void:
	var label := Label.new()
	label.text = text_value
	label.position = point_value
	label.add_theme_font_override("font", lab.site_controller.details.get_theme_font("font"))
	label.add_theme_font_size_override("font_size", size)
	label.z_index = 200
	parent.add_child(label)

func _capture(name_value: String, details: Dictionary = {}, _gallery: bool = false) -> bool:
	if not _check(Time.get_ticks_msec() < deadline, "Calibration capture deadline"): return false
	var records_before: Dictionary = lab.terrain.site.vehicles.duplicate(true)
	var inventory_before: Dictionary = lab.terrain.site.inventory.duplicate(true)
	var units_before: Array = team.combat_units.duplicate(true)
	var cells_before: Array[Vector2i] = team.cells.duplicate()
	for army: TerrainArmy in lab.combat_armies: army.advance_frame(0.0)
	lab.site_controller.view.refresh()
	view.refresh()
	var environment_visible: bool = lab.site_controller.view.visible
	lab.site_controller.view.hide() # Presentation only, for an unobscured calibration fixture.
	for _frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	var result: int = ERR_CANT_CREATE
	if picture != null and not picture.is_empty(): result = picture.save_png(CALIBRATION_OUT + "/" + name_value + ".png")
	lab.site_controller.view.visible = environment_visible
	if not _check(result == OK, "Calibration GPU capture failed", {"file": name_value}): return false
	if not _check(lab.terrain.site.vehicles == records_before and records_before.is_empty() and lab.terrain.site.inventory == inventory_before
		and team.combat_units == units_before and team.cells == cells_before, "Pure calibration changed gameplay records or original people"): return false
	details.merge({"file": name_value + ".png", "original_people": team.combat_units.size(), "original_person_ids": [team.combat_identity(0), team.combat_identity(1)],
		"vehicle_records": 0, "presentation_only": true, "fixture_guides_only": true, "resource_presentation_temporarily_hidden": true}, true)
	captures.append(details)
	return true

func _calibration_gallery(kind: String, title: String, number: int) -> bool:
	var gallery := Node2D.new()
	gallery.name = "DirectionCalibrationFixture_" + kind
	lab.add_child(gallery)
	var offsets: Array[Vector2i] = [Vector2i(-7, -4), Vector2i(6, -4), Vector2i(-7, 5), Vector2i(6, 5)]
	var rectangles: Array[Dictionary] = []
	for quarter in range(4):
		var facing: Vector2i = FACINGS[quarter]
		var footprint: Vector2i = FOOTPRINTS[kind]
		var extent := Vector2i(absi(facing.x) * footprint.y + absi(facing.y) * footprint.x, absi(facing.y) * footprint.y + absi(facing.x) * footprint.x)
		var centre: Vector2 = (Vector2(anchor + offsets[quarter]) + Vector2((extent.x % 2) * 0.5, (extent.y % 2) * 0.5)) * TerrainRenderer.CELL_PIXELS
		var envelope: Dictionary = _envelope(kind, facing, centre)
		if not _check(envelope.anchor.is_equal_approx(envelope.anchor.round()), "Rotated anchor is not a logical cell", {"kind": kind, "direction": DIRECTIONS[quarter]}): return false
		var corners: Array[Vector2] = envelope.corners
		var corner_rows: Array = []
		for corner: Vector2 in corners:
			if not _check((corner / TerrainRenderer.CELL_PIXELS).is_equal_approx((corner / TerrainRenderer.CELL_PIXELS).round()), "Footprint boundary is off the original grid", {"kind": kind, "direction": DIRECTIONS[quarter], "corner": _pair(corner)}): return false
			corner_rows.append(_pair(corner))
		var sprite: Sprite2D = view.show_pure_preview(kind, facing, gallery, centre)
		if not _check_sprite(sprite, kind, facing): return false
		if kind != "ballista" and not _check_ground(sprite, kind, facing, DIRECTIONS[quarter], envelope): return false
		var outline: Array[Vector2] = corners.duplicate()
		outline.append(corners[0])
		_fixture_line(gallery, outline, Color(0.1, 0.85, 1.0, 0.9))
		# This arrow annotates the test fixture; it is not a product or gameplay UI.
		var tip: Vector2 = centre + envelope.forward * (float(envelope.half_forward) + 28.0)
		_fixture_line(gallery, [centre, tip], Color(1.0, 0.8, 0.1, 0.95), 3.0)
		_fixture_line(gallery, [tip - envelope.forward * 16.0 + envelope.side * 10.0, tip, tip - envelope.forward * 16.0 - envelope.side * 10.0], Color(1.0, 0.8, 0.1, 0.95), 3.0)
		_fixture_line(gallery, [centre - Vector2(6, 0), centre + Vector2(6, 0)], Color.WHITE)
		_fixture_line(gallery, [centre - Vector2(0, 6), centre + Vector2(0, 6)], Color.WHITE)
		_fixture_label(gallery, "%s · %s · %d×%d 格\n黃箭頭＝前向／青框＝邏輯接地範圍" % [title, DIRECTIONS[quarter], extent.x, extent.y], centre + Vector2(-150, float(extent.y) * 32.0 + 45.0))
		var row: Dictionary = {"kind": kind, "direction": DIRECTIONS[quarter], "footprint_width_length_cells": [footprint.x, footprint.y], "rotated_extent_xy_cells": [extent.x, extent.y],
			"ground_centre_world_pixels": _pair(centre), "anchor_cell": _pair(envelope.anchor), "ground_rectangle_corners_world_pixels": corner_rows, "grid_aligned": true}
		ground_rectangles.append(row)
		rectangles.append(row)
	_fixture_label(gallery, title + " · 四向方格校準／原 2 位隊員比例參考\n只量人工接地軸與中心、接地點不越格；保留透視縮短。圖像相機朝向另由 GPU 目視審閱。", (Vector2(anchor) + Vector2(-12, -10)) * TerrainRenderer.CELL_PIXELS, 23)
	_fixture_label(gallery, "原隊 2 真人（未操作器具）", (Vector2(anchor) + Vector2(-4, 2)) * TerrainRenderer.CELL_PIXELS, 20)
	_focus((Vector2(anchor) + Vector2(0, -0.5)) * TerrainRenderer.CELL_PIXELS, 0.7)
	if not await _capture("%02d_calibration_%s" % [number, kind], {"kind": kind, "directions": DIRECTIONS, "ground_rectangles": rectangles}, true): return false
	completed.gallery += 1
	gallery.queue_free()
	await process_frame
	return true

func _run() -> void:
	if not _check(DisplayServer.get_name() != "headless", "GPU viewport required"): return
	if not _check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn", "Original main scene required"): return
	if not _check(DirAccess.make_dir_recursive_absolute(CALIBRATION_OUT) == OK and FileAccess.file_exists(MANIFEST), "Missing calibration output or art manifest"): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not _check(parsed is Dictionary and int(parsed.get("schema_version", 0)) == 1 and parsed.get("entries") is Dictionary, "Art manifest schema"): return
	calibration_manifest = parsed
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var main: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = main.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	var data: TerrainData = Helper.build_flat_map(60, 44)
	data.spawn_cell = Vector2i(4, 4)
	data.site.player_cell = data.index(data.spawn_cell)
	data.site.manual.cell = data.site.player_cell
	data.site.worker.cell = data.index(Vector2i(4, 3))
	data.site.depot_cell = data.index(Vector2i(3, 4))
	lab.bind_terrain(data)
	var ui: SiteController = lab.site_controller
	ui._auto_save_blocked = true
	ui.release_worker()
	ui.hide_tool_windows()
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	view = ui.vehicle_view
	view.set_process(false)
	team = lab.army
	team.team_id = lab._next_army_identity()
	team.roster_size = 2
	var initial: Array[Vector2i] = [anchor - Vector2i(3, 0), anchor - Vector2i(3, -1)]
	if not _check(team.deploy_at(data, lab.character, lab.npc, initial) and team.enable_combat(false, 0), "Original two-person Army fixture"): return
	team.set_process(false)
	if not _check(data.site.vehicles.is_empty(), "Calibration fixture must have no gameplay vehicles"): return
	lab.renderer.debug_enabled = true
	lab.renderer.redraw()
	for kind: String in KINDS:
		var definition: Variant = calibration_manifest.entries.get(kind)
		if not _check(definition is Dictionary and _point(definition.get("body_footprint_cells")) and _v2(definition.body_footprint_cells) == Vector2(FOOTPRINTS[kind]), "Manifest footprint changed", {"kind": kind}): return
		if not _check(bool(definition.get("gameplay_available", false)) == (kind == "ballista"), "Pure gallery does not add other kinds gameplay", {"kind": kind}): return
		for quarter in range(4):
			if not _check_frame(kind, FACINGS[quarter], DIRECTIONS[quarter]): return
			if kind == "ballista" and not _check_preserved_ballista(FACINGS[quarter], DIRECTIONS[quarter]): return
	for kind_index in range(KINDS.size()):
		if not await _calibration_gallery(KINDS[kind_index], TITLES[kind_index], kind_index + 1): return
	if not _check(completed.frames == 24 and completed.gallery == 6 and ground_checks.size() == 20 and new_sources.size() == 20 and preserved_ballista_checks.size() == 4
		and sprite_mask_checks.size() == 24 and ground_rectangles.size() == 24 and captures.size() == 6 and data.site.vehicles.is_empty(),
		"Incomplete calibration acceptance", {"completed": completed, "ground_axes": ground_checks.size(), "new_sources": new_sources.size(), "preserved_ballista": preserved_ballista_checks.size(), "sprite_checks": sprite_mask_checks.size(), "rectangles": ground_rectangles.size(), "captures": captures.size()}): return
	var report: FileAccess = FileAccess.open(CALIBRATION_OUT + "/captures.json", FileAccess.WRITE)
	if not _check(report != null, "Cannot write calibration report"): return
	report.store_string(JSON.stringify({"status": "SITE_SIEGE_DIRECTION_CALIBRATION_VISUAL_PASS", "gpu_appearance_review": "PENDING_MANUAL_REVIEW", "captures": captures,
		"completed": {"frames": 24, "sprite_checks": 24, "manual_ground_axis_checks": 20, "new_unique_pngs": 20, "preserved_ballista_frames": 4, "rotated_grid_rectangles": 24, "gallery_captures": 6},
		"source_sha256": source_hashes, "manifest_sha256": FileAccess.get_sha256(MANIFEST), "asset_checks": asset_checks, "sprite_mask_checks": sprite_mask_checks,
		"preserved_ballista_checks": preserved_ballista_checks, "ground_checks": ground_checks, "ground_rectangles": ground_rectangles,
		"scope": "Original TerrainLab/VehicleView/Army presentation only on an explicit flat-map fixture. Four cardinal pure previews per kind, 24 original Sprite/frame/mask checks, 20 unique transparent full-region PNGs bound to manually supplied ground landmarks, normalized ground-axis cross tolerance 0.02, positive front/rear and side heading, pivot centre error below 0.01 pixels, declared contacts within rotated logical grid envelopes with at most 1 pixel tolerance. Uniform source scale is retained; foreshortened ground spans need not fill tile rectangles. Original four ballista PNG hashes/pivots/scales/muzzles are preserved. Exactly two original Army members remain unchanged; no new person or vehicle gameplay records. Grid outlines/front arrows are test guides only. These measurements depend on manual visible or estimated landmarks and do not prove all mechanical details, semantic person absence, camera yaw, perspective correctness, other five kinds gameplay, performance or export. GPU camera orientation and appearance require separate human review."}, "\t"))
	report.close()
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	finished = true
	print("SITE_SIEGE_DIRECTION_CALIBRATION_VISUAL_PASS: frames=24 manual_ground_axes=20 unique_new_pngs=20 preserved_ballista=4 sprites=24 grid_rectangles=24 captures=6 original_people=2 gameplay_vehicles=0 camera_yaw_review=pending")
	quit(0)
