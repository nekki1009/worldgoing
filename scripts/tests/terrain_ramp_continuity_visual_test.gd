extends SceneTree
## Actual-GPU ramp geometry contract for the original TerrainRenderer owner.

const OUTPUT_ROOT := "res://output/terrain_ramp_continuity"
const WINDOW := Vector2i(1600, 1000)
const YUSHAN := Vector2i(1228, 12981)
const EXPECTED_PROGRESSIVE_DRAWS := 520
const Atlas = preload("res://scripts/region_lab/region_data.gd")

var _normal: TerrainRenderer
var _progressive: TerrainRenderer
var _folder := ""
var _deadline_usec := 0
var _finished := false
var _failures: Array[String] = []
var _report: Dictionary = {"cases": []}
var _background: ColorRect

func _init() -> void:
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if not _finished and _deadline_usec > 0 and Time.get_ticks_usec() >= _deadline_usec:
		_failures.append("GPU_TEST_TIMEOUT_120S")
		_finish()
	return false

func _run() -> void:
	_deadline_usec = Time.get_ticks_usec() + 120_000_000
	if DisplayServer.get_name() == "headless":
		_failures.append("GPU_WINDOW_REQUIRED")
		_finish()
		return
	var run_id := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--run="):
			run_id = arg.trim_prefix("--run=")
	if not _valid_run_id(run_id):
		_failures.append("MISSING_OR_INVALID_RUN_ID")
		_finish()
		return
	_folder = OUTPUT_ROOT.path_join(run_id)
	var absolute := ProjectSettings.globalize_path(_folder)
	if DirAccess.dir_exists_absolute(absolute):
		_failures.append("RUN_DIRECTORY_ALREADY_EXISTS")
		_finish()
		return
	if DirAccess.make_dir_recursive_absolute(absolute) != OK:
		_failures.append("RUN_DIRECTORY_FAILED")
		_finish()
		return
	DisplayServer.window_set_size(WINDOW)
	root.size = WINDOW
	root.content_scale_size = WINDOW
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_background = ColorRect.new()
	_background.color = Color("15202a")
	_background.size = WINDOW
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_background)
	_normal = TerrainRenderer.new()
	_normal.brush_enabled = false
	_normal.visible = false
	root.add_child(_normal)
	_progressive = TerrainRenderer.new()
	_progressive.brush_enabled = false
	_progressive.progressive_display = true
	_progressive.visible = false
	root.add_child(_progressive)
	_report["run"] = run_id
	_report["renderer_source_sha256"] = FileAccess.get_sha256("res://scripts/terrain_lab/terrain_renderer.gd")
	_report["display_server"] = DisplayServer.get_name()
	_report["resolution"] = [WINDOW.x, WINDOW.y]
	_report["comparison"] = "Same TerrainData, brush disabled, default and progressive renderer; each GPU crop must be pixel-identical."
	var board := _board_fixture()
	var board_before := _data_contract(board)
	if not _check_board_passage(board):
		_finish()
		return
	_report["board"] = board_before
	if not _check_ramp_relief(board):
		_finish()
		return
	if not await _display_pair(board, "board"):
		_finish()
		return
	for case: Dictionary in [
		{"name": "four_directions", "focus": Vector2(50.5, 43.0), "zoom": 1.2},
		{"name": "continuous_and_wide", "focus": Vector2(47.5, 50.0), "zoom": 1.8},
		{"name": "turn_and_multi_edge", "focus": Vector2(57.5, 53.0), "zoom": 2.3},
		{"name": "forbidden_cliffs", "focus": Vector2(47.0, 58.5), "zoom": 2.0},
		{"name": "internal_edge_pair", "focus": Vector2(19.5, 63.0), "zoom": 2.5}]:
		if not await _capture_pair(str(case.name), Vector2(case.focus) * TerrainRenderer.CELL_PIXELS, float(case.zoom)):
			_finish()
			return
	if _data_contract(board) != board_before or not _check_board_passage(board):
		_failures.append("BOARD_DATA_OR_PASSAGE_CHANGED_BY_DRAW")
		_finish()
		return
	var natural := _empty_terrain()
	_set_level(natural, Vector2i(20, 63), 1)
	_rebuild_cliff_drops(natural)
	_prepare_natural(natural)
	if not await _display_pair(natural, "natural_board") or not await _capture_pair(
			"natural_internal_edge_pair", Vector2(19.5, 63.0) * TerrainRenderer.CELL_PIXELS, 2.5):
		_finish()
		return
	if not _check_cliff_entrances(natural):
		_finish()
		return
	if not await _check_blocked_halo_approach():
		_finish()
		return
	if not await _check_false_entrance_pixels():
		_finish()
		return
	var source := Atlas.new()
	var loaded: Dictionary = source.load_manifest()
	if not bool(loaded.get("ok", false)):
		_failures.append("YUSHAN_ATLAS_LOAD_FAILED:" + str(loaded.get("code", "UNKNOWN")))
		_finish()
		return
	var opened: Dictionary = source.make_terrain_data(YUSHAN.x, YUSHAN.y)
	if not bool(opened.get("ok", false)):
		_failures.append("YUSHAN_TERRAIN_FAILED:" + str(opened.get("code", "UNKNOWN")))
		_finish()
		return
	var yushan: TerrainData = opened.data
	var real_before := _data_contract(yushan)
	var focus := _ramp_hotspot(yushan)
	if focus.x < 0:
		_failures.append("YUSHAN_HAS_NO_VISIBLE_RAMP")
		_finish()
		return
	_report["yushan"] = {"site": [YUSHAN.x, YUSHAN.y], "manifest_sha256": source.manifest_hash,
		"base_fingerprint": str(opened.base.terrain_fingerprint), "before": real_before,
		"ramp_hotspot": [focus.x, focus.y]}
	if not await _display_pair(yushan, "yushan"):
		_finish()
		return
	if not await _capture_pair("yushan_ramp_local", (Vector2(focus) + Vector2(0.5, 0.5)) * TerrainRenderer.CELL_PIXELS, 2.0):
		_finish()
		return
	if _data_contract(yushan) != real_before or yushan.fingerprint() != str(opened.base.terrain_fingerprint):
		_failures.append("YUSHAN_DATA_OR_PASSAGE_CHANGED_BY_DRAW")
	if _failures.is_empty() and not await _split_site_edge_pair():
		_finish()
		return
	if _failures.is_empty() and not await _split_site_edge_pair(true):
		_finish()
		return
	if _failures.is_empty() and not _check_preserved_cliff_pixels():
		_finish()
		return
	_finish()

func _check_preserved_cliff_pixels() -> bool:
	# Same board/camera from the pre-change GPU capture. Neither cliff has a
	# legal entrance, so the whole visible scene must retain its original pixels.
	var baseline := Image.new()
	var current := Image.new()
	var old_path := OUTPUT_ROOT.path_join("20260930_relief_before/forbidden_cliffs_normal.png")
	var new_path := _folder.path_join("forbidden_cliffs_normal.png")
	if baseline.load(old_path) != OK or current.load(new_path) != OK:
		_failures.append("MISSING_ORIGINAL_CLIFF_PIXEL_EVIDENCE")
		return false
	var same := baseline.get_size() == current.get_size() and baseline.get_data() == current.get_data()
	_report["preserved_cliff_pixels"] = {"same_rgba": same,
		"original": ProjectSettings.globalize_path(old_path), "current": ProjectSettings.globalize_path(new_path)}
	if not same:
		_failures.append("ORIGINAL_UNRAMPED_CLIFF_PIXELS_CHANGED")
	return same

func _check_false_entrance_pixels() -> bool:
	var fixture := _empty_terrain()
	_set_level(fixture, Vector2i(20, 63), 2)
	_set_level(fixture, Vector2i(20, 62), 1)
	_rebuild_cliff_drops(fixture)
	_prepare_natural(fixture)
	var focus := Vector2(20.5, 63.5) * TerrainRenderer.CELL_PIXELS
	if not await _display_pair(fixture, "stale_reference") or not await _capture_pair("stale_reference", focus, 2.5):
		return false
	fixture.ramp_edges[fixture.index(Vector2i(20, 63))] |= 1 << 2
	if not await _display_pair(fixture, "stale_flags") or not await _capture_pair("stale_flags", focus, 2.5):
		return false
	var reference := Image.new()
	var candidate := Image.new()
	if reference.load(_folder.path_join("stale_reference_normal.png")) != OK \
			or candidate.load(_folder.path_join("stale_flags_normal.png")) != OK:
		_failures.append("STALE_FLAG_CAPTURE_MISSING")
		return false
	var stale_same := reference.get_data() == candidate.get_data()
	fixture = _empty_terrain()
	fixture.parameters["composition"] = "fixed_geography"
	_set_level(fixture, Vector2i(20, 62), 1)
	_set_level(fixture, Vector2i(20, 64), 2)
	_rebuild_cliff_drops(fixture)
	_prepare_natural(fixture)
	if not await _display_pair(fixture, "mixed_wall_reference"):
		return false
	# Keep exactly the same cliff openings and submission order. Hiding the
	# original detail layer isolates whether the slope itself paints over stone.
	_normal.layers[3].visible = false
	_progressive.layers[3].visible = false
	if not await _capture_pair("mixed_wall_reference", focus, 2.5):
		return false
	_normal.layers[3].visible = true
	_progressive.layers[3].visible = true
	if not await _capture_pair("mixed_wall_with_ramp", focus, 2.5):
		return false
	if reference.load(_folder.path_join("mixed_wall_reference_normal.png")) != OK \
			or candidate.load(_folder.path_join("mixed_wall_with_ramp_normal.png")) != OK:
		_failures.append("MIXED_WALL_CAPTURE_MISSING")
		return false
	# Opposite blocked cliff projects over the low cell. A new extended
	# approach must not paint a soil entrance onto this unrelated stone face.
	var roi := Rect2i(784, 556, 32, 20)
	var mixed_same := reference.get_region(roi).get_data() == candidate.get_region(roi).get_data()
	_report["false_entrance_pixels"] = {"invalid_flag_full_rgba_unchanged": stale_same,
		"opposite_blocked_wall_roi_rgba_unchanged": mixed_same, "wall_roi": [784, 556, 32, 20]}
	if not stale_same or not mixed_same:
		_failures.append("RAMP_PAINTED_FALSE_ENTRANCE_OVER_CLIFF")
		return false
	return true

func _check_blocked_halo_approach() -> bool:
	# A closed one-level cliff behind a pass must clip its lower approach the
	# same way inside a Site and across its halo. Compare the real detail pixels.
	var images: Array[Image] = []
	for row: int in [63, 99]:
		var terrain := _empty_terrain()
		terrain.parameters["composition"] = "fixed_geography"
		var lower := Vector2i(20, row)
		_set_level(terrain, lower + Vector2i.UP, 1)
		if row == 63:
			_set_level(terrain, lower + Vector2i.DOWN, 1)
		else:
			terrain.parameters["ramp_visual_halo"] = {"20:100": [1, 0]}
		_rebuild_cliff_drops(terrain)
		_allow_ramp(terrain, lower, lower + Vector2i.UP)
		var label := "blocked_approach_internal" if row == 63 else "blocked_approach_halo"
		if not await _display_pair(terrain, label):
			return false
		for layer: int in [0, 1, 2]:
			_normal.layers[layer].visible = false
			_progressive.layers[layer].visible = false
		if not await _capture_pair(label, (Vector2(lower) + Vector2(0.5, 0.5)) * TerrainRenderer.CELL_PIXELS, 2.5):
			return false
		for layer: int in [0, 1, 2]:
			_normal.layers[layer].visible = true
			_progressive.layers[layer].visible = true
		var captured := Image.new()
		if captured.load(_folder.path_join(label + "_normal.png")) != OK:
			return false
		images.append(captured.get_region(Rect2i(730, 430, 140, 140)))
	var same := images[0].get_data() == images[1].get_data()
	_report["blocked_halo_approach"] = {"same_rgba_as_internal": same, "roi": [730, 430, 140, 140]}
	if not same:
		_failures.append("BLOCKED_HALO_APPROACH_DIFFERS_FROM_INTERNAL")
	return same

func _prepare_natural(terrain: TerrainData) -> void:
	terrain.parameters["composition"] = "fixed_geography"
	for y: int in range(terrain.size.y):
		for x: int in range(terrain.size.x):
			var cell := Vector2i(x, y)
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var adjacent := cell + direction
				if terrain.contains(adjacent) and int(terrain.height_levels[terrain.index(adjacent)]) - int(terrain.height_levels[terrain.index(cell)]) == 1:
					_allow_ramp(terrain, cell, adjacent)

func _check_cliff_entrances(terrain: TerrainData) -> bool:
	var probe := TerrainRenderer.new()
	probe.data = terrain
	var shoulders := 0
	for d: int in range(4):
		var upper := Vector2i(20, 63)
		var direction := TerrainData.DIRECTIONS[d]
		var lower := upper + direction
		var span := TerrainRenderer.ramp_span(terrain, upper, d)
		var cliff_parts := probe._cliff_spans(upper, d)
		if span != Vector2(-18, 18) or cliff_parts != [Vector2(-32, -18), Vector2(18, 32)] \
				or not terrain.can_step(upper, lower) or not terrain.can_step(lower, upper):
			_failures.append("RAMP_ERASED_CLIFF_SHOULDERS_OR_PASSAGE:" + str(d))
			probe.free()
			return false
		shoulders += 2
	var high := terrain.index(Vector2i(20, 63))
	terrain.ramp_edges[high] &= ~(1 << 0)
	var full_wall := probe._cliff_spans(Vector2i(20, 63), 0) == [Vector2(-32, 32)]
	terrain.ramp_edges[high] |= 1 << 0
	var level := terrain.height_levels[high]
	terrain.height_levels[high] = 2
	var stale_cliff := probe._cliff_spans(Vector2i(20, 63), 0) == [Vector2(-32, 32)]
	terrain.height_levels[high] = level
	probe.free()
	_report["cliff_entrances"] = {"directions": 4, "shoulders": shoulders,
		"opening_width_px": 36, "each_shoulder_width_px": 14,
		"unramped_wall_preserved": full_wall, "invalid_two_level_ramp_wall_preserved": stale_cliff}
	if not full_wall or not stale_cliff:
		_failures.append("RAMP_ERASED_COMPLETE_CLIFF")
		return false
	return true

func _empty_terrain() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(100, 100))
	data.height_levels.fill(0)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.cliff_drops.fill(0)
	data.ramp_edges.fill(0)
	data.detail_variation.fill(128)
	data.spawn_cell = Vector2i(40, 40)
	return data

func _board_fixture() -> TerrainData:
	var data := _empty_terrain()
	for upper: Vector2i in [Vector2i(42, 42), Vector2i(48, 43), Vector2i(53, 44), Vector2i(58, 43)]:
		_set_level(data, upper, 1)
	for x: int in range(43, 46):
		_set_level(data, Vector2i(x, 50), x - 42)
	for x: int in range(49, 53):
		_set_level(data, Vector2i(x, 49), 1)
	_set_level(data, Vector2i(58, 52), 1)
	_set_level(data, Vector2i(58, 51), 2)
	_set_level(data, Vector2i(57, 54), 1)
	_set_level(data, Vector2i(58, 55), 1)
	_set_level(data, Vector2i(44, 58), 2)
	_set_level(data, Vector2i(50, 58), 1)
	_set_level(data, Vector2i(20, 63), 1)
	_rebuild_cliff_drops(data)
	for pair: Array in [
		[Vector2i(42, 43), Vector2i(42, 42)],
		[Vector2i(47, 43), Vector2i(48, 43)],
		[Vector2i(53, 43), Vector2i(53, 44)],
		[Vector2i(59, 43), Vector2i(58, 43)],
		[Vector2i(42, 50), Vector2i(43, 50)],
		[Vector2i(43, 50), Vector2i(44, 50)],
		[Vector2i(44, 50), Vector2i(45, 50)],
		[Vector2i(57, 52), Vector2i(58, 52)],
		[Vector2i(58, 52), Vector2i(58, 51)],
		[Vector2i(57, 55), Vector2i(57, 54)],
		[Vector2i(57, 55), Vector2i(58, 55)],
		[Vector2i(19, 63), Vector2i(20, 63)]]:
		_allow_ramp(data, pair[0], pair[1])
	for x: int in range(49, 53):
		_allow_ramp(data, Vector2i(x, 50), Vector2i(x, 49))
	return data

func _set_level(data: TerrainData, cell: Vector2i, level: int) -> void:
	data.height_levels[data.index(cell)] = level

func _rebuild_cliff_drops(data: TerrainData) -> void:
	for y: int in range(data.size.y):
		for x: int in range(data.size.x):
			var cell := Vector2i(x, y)
			var index := data.index(cell)
			for d: int in range(4):
				var adjacent := cell + TerrainData.DIRECTIONS[d]
				if data.contains(adjacent):
					var drop := maxi(int(data.height_levels[index]) - int(data.height_levels[data.index(adjacent)]), 0)
					data.cliff_drops[index * 4 + d] = drop
					if drop > 0:
						data.flags[index] |= TerrainData.Flag.CLIFF

func _allow_ramp(data: TerrainData, low: Vector2i, high: Vector2i) -> void:
	var direction := TerrainData.DIRECTIONS.find(high - low)
	assert(direction >= 0 and int(data.height_levels[data.index(high)]) - int(data.height_levels[data.index(low)]) == 1)
	var reverse := (direction + 2) % 4
	var low_index := data.index(low)
	var high_index := data.index(high)
	data.ramp_edges[low_index] |= 1 << direction
	data.ramp_edges[high_index] |= 1 << reverse
	data.flags[low_index] |= TerrainData.Flag.RAMP
	data.flags[high_index] |= TerrainData.Flag.RAMP

func _check_board_passage(data: TerrainData) -> bool:
	for pair: Array in [
		[Vector2i(42, 43), Vector2i(42, 42)], [Vector2i(47, 43), Vector2i(48, 43)],
		[Vector2i(53, 43), Vector2i(53, 44)], [Vector2i(59, 43), Vector2i(58, 43)],
		[Vector2i(42, 50), Vector2i(43, 50)], [Vector2i(43, 50), Vector2i(44, 50)],
		[Vector2i(44, 50), Vector2i(45, 50)], [Vector2i(57, 52), Vector2i(58, 52)],
		[Vector2i(58, 52), Vector2i(58, 51)], [Vector2i(57, 55), Vector2i(57, 54)],
		[Vector2i(57, 55), Vector2i(58, 55)], [Vector2i(19, 63), Vector2i(20, 63)]]:
		if not data.can_step(pair[0], pair[1]) or not data.can_step(pair[1], pair[0]):
			_failures.append("ALLOWED_RAMP_BLOCKED:" + str(pair))
			return false
	for x: int in range(49, 53):
		if not data.can_step(Vector2i(x, 50), Vector2i(x, 49)) or not data.can_step(Vector2i(x, 49), Vector2i(x, 50)):
			_failures.append("WIDE_RAMP_BLOCKED:" + str(x))
			return false
		var span := TerrainRenderer.ramp_span(data, Vector2i(x, 50), 0)
		if x > 49 and span.x != -32.0 or x < 52 and span.y != 32.0:
			_failures.append("WIDE_RAMP_HAS_SIDE_GAP:" + str(x) + ":" + str(span))
			return false
	for pair: Array in [[Vector2i(44, 59), Vector2i(44, 58)], [Vector2i(50, 59), Vector2i(50, 58)]]:
		if data.can_step(pair[0], pair[1]) or data.can_step(pair[1], pair[0]):
			_failures.append("FORBIDDEN_CLIFF_WALKABLE:" + str(pair))
			return false
	return true

func _check_ramp_relief(terrain: TerrainData) -> bool:
	_normal.data = terrain
	var shared_samples := 0
	for y: int in range(100):
		for x: int in range(100):
			var cell := Vector2i(x, y)
			var i := terrain.index(cell)
			for d: int in range(4):
				var step: Vector2i = TerrainData.DIRECTIONS[d]
				if (terrain.ramp_edges[i] & (1 << d)) == 0 or not terrain.contains(cell + step):
					continue
				var axis := Vector2(step)
				var tangent := Vector2(-axis.y, axis.x)
				for side: float in [-18.0, -9.0, 0.0, 9.0, 18.0]:
					var from := _normal._ramp_vertex_color(i, axis * 32.0 + tangent * side)
					var to := _normal._ramp_vertex_color(terrain.index(cell + step), -axis * 32.0 + tangent * side)
					if not from.is_equal_approx(to):
						_failures.append("RAMP_SHARED_EDGE_LIGHTING_SEAM:%s:%d" % [cell, d])
						return false
					shared_samples += 1
	for pair: Array in [[Vector2i(42, 43), Vector2i(42, 42)], [Vector2i(47, 43), Vector2i(48, 43)],
			[Vector2i(53, 43), Vector2i(53, 44)], [Vector2i(59, 43), Vector2i(58, 43)]]:
		var low := _normal._ramp_vertex_color(terrain.index(pair[0]), Vector2.ZERO)
		var high := _normal._ramp_vertex_color(terrain.index(pair[1]), Vector2.ZERO)
		if high.get_luminance() - low.get_luminance() < 0.12:
			_failures.append("RAMP_FOOT_AND_UPPER_LANDING_NOT_DISTINCT:" + str(pair))
			return false
	var lights: Array[float] = []
	for cell: Vector2i in [Vector2i(42, 43), Vector2i(47, 43), Vector2i(53, 43), Vector2i(59, 43)]:
		lights.append(TerrainRenderer.ramp_light(terrain, terrain.index(cell), Vector2.ZERO))
	if lights.max() - lights.min() < 0.12:
		_failures.append("RAMP_ORIENTATION_NOT_READABLE_IN_LIGHTING")
		return false
	for x: int in range(49, 52):
		var first := _normal._ramp_vertex_color(terrain.index(Vector2i(x, 50)), Vector2(32, 0))
		var second := _normal._ramp_vertex_color(terrain.index(Vector2i(x + 1, 50)), Vector2(-32, 0))
		if not first.is_equal_approx(second):
			_failures.append("PARALLEL_RAMP_LIGHTING_SEAM")
			return false
	_report["relief"] = {"shared_edge_samples": shared_samples, "directional_lights": lights,
		"scope": "Four directions, serial and parallel slopes, bends and forks; unchanged original passage contract"}
	return true

func _data_contract(data: TerrainData) -> Dictionary:
	var passage := PackedByteArray()
	passage.resize(data.size.x * data.size.y * 4)
	for y: int in range(data.size.y):
		for x: int in range(data.size.x):
			var cell := Vector2i(x, y)
			for d: int in range(4):
				passage[data.index(cell) * 4 + d] = int(data.can_step(cell, cell + TerrainData.DIRECTIONS[d]))
	return {"terrain_fingerprint": data.fingerprint(), "can_step_sha256": _sha256(passage)}

func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _ramp_hotspot(data: TerrainData) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := 0
	for y: int in range(4, 96):
		for x: int in range(4, 96):
			var score := 0
			for dy: int in range(-3, 4):
				for dx: int in range(-3, 4):
					var i := data.index(Vector2i(x + dx, y + dy))
					if data.ramp_edges[i] != 0:
						score += 3
					for d: int in range(4):
						score += int(data.cliff_drops[i * 4 + d] > 0)
			if score > best_score:
				best_score = score
				best = Vector2i(x, y)
	_report["yushan_hotspot_score"] = best_score
	return best

func _display_pair(data: TerrainData, label: String) -> bool:
	_normal.visible = false
	_progressive.visible = true
	_normal.display(data)
	_progressive.display(data)
	var cutoff := mini(_deadline_usec, Time.get_ticks_usec() + 15_000_000)
	while _progressive.display_pending and Time.get_ticks_usec() < cutoff:
		await process_frame
	if _progressive.display_pending or _progressive.display_samples.size() != EXPECTED_PROGRESSIVE_DRAWS:
		_failures.append("PROGRESSIVE_NOT_FULLY_DRAWN_" + label)
		return false
	await RenderingServer.frame_post_draw
	return true

func _capture_pair(label: String, focus: Vector2, zoom: float) -> bool:
	var pictures: Array[Image] = []
	var files: Array[Dictionary] = []
	for mode: String in ["normal", "progressive"]:
		_normal.visible = mode == "normal"
		_progressive.visible = mode == "progressive"
		var renderer: TerrainRenderer = _normal if mode == "normal" else _progressive
		renderer.scale = Vector2.ONE * zoom
		renderer.position = Vector2(WINDOW) * 0.5 - focus * zoom
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		if image == null or image.is_empty() or image.get_size() != WINDOW:
			_failures.append("GPU_CAPTURE_EMPTY_" + label + "_" + mode)
			return false
		var path := _folder.path_join(label + "_" + mode + ".png")
		if FileAccess.file_exists(path) or image.save_png(path) != OK:
			_failures.append("GPU_CAPTURE_WRITE_FAILED_" + label + "_" + mode)
			return false
		pictures.append(image)
		files.append({"path": ProjectSettings.globalize_path(path), "sha256": FileAccess.get_sha256(path)})
	var first: PackedByteArray = pictures[0].get_data()
	var second: PackedByteArray = pictures[1].get_data()
	var differing_pixels := 0
	for offset: int in range(0, first.size(), 4):
		if first[offset] != second[offset] or first[offset + 1] != second[offset + 1] \
				or first[offset + 2] != second[offset + 2] or first[offset + 3] != second[offset + 3]:
			differing_pixels += 1
	_report.cases.append({"case": label, "zoom": zoom, "focus_px": [focus.x, focus.y],
		"pixel_difference": differing_pixels, "captures": files})
	if differing_pixels != 0:
		_failures.append("NORMAL_PROGRESSIVE_PIXEL_DIFFERENCE_" + label + ":" + str(differing_pixels))
		return false
	return true

func _split_site_edge_pair(natural: bool = false) -> bool:
	var prefix := "natural_" if natural else ""
	# The same one-level eastward slope, placed on the east and west edge of two
	# separate 100-cell Sites. Its opening must match the internal x=19/20 pair:
	# both share the same phase of the renderer's 20-cell grass repeat.
	var west := _empty_terrain()
	var east := _empty_terrain()
	_set_level(east, Vector2i(0, 63), 1)
	_rebuild_cliff_drops(east)
	var west_cell := west.index(Vector2i(99, 63))
	var east_cell := east.index(Vector2i(0, 63))
	west.ramp_edges[west_cell] |= 1 << 1
	east.ramp_edges[east_cell] |= 1 << 3
	west.flags[west_cell] |= TerrainData.Flag.RAMP
	east.flags[east_cell] |= TerrainData.Flag.RAMP | TerrainData.Flag.CLIFF
	east.cliff_drops[east_cell * 4 + 3] = 1
	if natural:
		_prepare_natural(west)
		_prepare_natural(east)
		for terrain: TerrainData in [west, east]:
			var halo: Dictionary = {}
			for y: int in range(-1, 101):
				for x: int in range(-1, 101):
					if x < 0 or x >= 100 or y < 0 or y >= 100:
						halo["%d:%d" % [x, y]] = [1 if terrain == west and x == 100 and y == 63 else 0, 0]
			terrain.parameters["ramp_visual_halo"] = halo
	var expected_span := Vector2(-18, 18)
	if west.height_levels[west_cell] != 0 or east.height_levels[east_cell] != 1 \
			or TerrainRenderer.ramp_span(west, Vector2i(99, 63), 1) != expected_span \
			or TerrainRenderer.ramp_span(east, Vector2i(0, 63), 3) != expected_span:
		_failures.append("SPLIT_SITE_RAMP_SOURCE_INVALID")
		return false
	var west_before := _data_contract(west)
	var east_before := _data_contract(east)
	_normal.visible = false
	_progressive.visible = false
	var left := TerrainRenderer.new()
	var right := TerrainRenderer.new()
	left.brush_enabled = false
	right.brush_enabled = false
	root.add_child(left)
	root.add_child(right)
	left.display(west)
	right.display(east)
	var zoom := 2.5
	var focus := Vector2(99.5, 63.0) * TerrainRenderer.CELL_PIXELS
	left.scale = Vector2.ONE * zoom
	right.scale = Vector2.ONE * zoom
	left.position = Vector2(WINDOW) * 0.5 - focus * zoom
	right.position = left.position + Vector2(100.0 * TerrainRenderer.CELL_PIXELS * zoom, 0.0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var split: Image = root.get_texture().get_image()
	var internal := Image.new()
	var loaded := internal.load(_folder.path_join(prefix + "internal_edge_pair_normal.png"))
	if split == null or split.is_empty() or loaded != OK or split.get_size() != internal.get_size():
		_failures.append("SPLIT_SITE_CAPTURE_INVALID")
		return false
	var split_path := _folder.path_join(prefix + "split_site_edge_pair_normal.png")
	if FileAccess.file_exists(split_path) or split.save_png(split_path) != OK:
		_failures.append("SPLIT_SITE_CAPTURE_WRITE_FAILED")
		return false
	# 12 × 88 pixels cover almost the full 90px opening at this zoom, including both shoulders.
	# Cliff faces outside this crop are intentionally not part of this contract.
	var roi := Rect2i(874, 536, 12, 88)
	var inside := internal.get_region(roi)
	var across := split.get_region(roi)
	var inside_path := _folder.path_join(prefix + "internal_edge_opening_roi.png")
	var across_path := _folder.path_join(prefix + "split_site_opening_roi.png")
	if inside.save_png(inside_path) != OK or across.save_png(across_path) != OK:
		_failures.append("SPLIT_SITE_ROI_WRITE_FAILED")
		return false
	var before_bytes: PackedByteArray = inside.get_data()
	var after_bytes: PackedByteArray = across.get_data()
	var difference := 0
	for offset: int in range(0, before_bytes.size(), 4):
		if before_bytes[offset] != after_bytes[offset] or before_bytes[offset + 1] != after_bytes[offset + 1] \
				or before_bytes[offset + 2] != after_bytes[offset + 2] or before_bytes[offset + 3] != after_bytes[offset + 3]:
			difference += 1
	_report[prefix + "split_site_pair"] = {"west_site_edge_cell": [99, 63], "east_site_edge_cell": [0, 63],
		"internal_edge_cells": [[19, 63], [20, 63]], "grass_repeat_period_cells": 20,
		"west_before": west_before, "east_before": east_before,
		"roi": [roi.position.x, roi.position.y, roi.size.x, roi.size.y],
		"opening_roi_pixel_difference": difference,
		"split_capture": ProjectSettings.globalize_path(split_path),
		"internal_roi": ProjectSettings.globalize_path(inside_path),
		"split_roi": ProjectSettings.globalize_path(across_path)}
	left.free()
	right.free()
	if _data_contract(west) != west_before or _data_contract(east) != east_before:
		_failures.append("SPLIT_SITE_DATA_CHANGED_BY_DRAW")
		return false
	if difference != 0:
		_failures.append("SPLIT_SITE_OPENING_DIFFERS_FROM_INTERNAL:" + str(difference))
		return false
	return true

func _valid_run_id(value: String) -> bool:
	if value.is_empty() or value.length() > 72:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true

func _finish() -> void:
	if _finished:
		return
	_finished = true
	_report["failures"] = _failures
	if not _folder.is_empty():
		var file := FileAccess.open(_folder.path_join("result.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(_report, "\t"))
			file.close()
		else:
			_failures.append("REPORT_WRITE_FAILED")
	if _failures.is_empty():
		print("TERRAIN_RAMP_CONTINUITY_VISUAL_PASS " + JSON.stringify(_report))
		quit(0)
	else:
		printerr("TERRAIN_RAMP_CONTINUITY_VISUAL_FAIL " + JSON.stringify(_report))
		quit(1)
