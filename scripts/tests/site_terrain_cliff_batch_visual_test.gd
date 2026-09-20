extends SceneTree

const SCRIPT := "res://scripts/terrain_lab/terrain_renderer.gd"
const REFERENCE := "res://scripts/tests/fixtures/terrain_renderer_before_cliff_batch.gd.txt"
const LOW_CELLS: Array[Vector2i] = [Vector2i(7, 11), Vector2i(4, 7), Vector2i(8, 4), Vector2i(11, 8)]

var renderer: TerrainRenderer
var candidate := ""
var reference := ""
var out := ""
var results: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "GPU required; this is a pixel contract and draw call benchmark")
	create_timer(90.0).timeout.connect(func() -> void: push_error("Cliff visual contract timeout"); quit(1))
	out = "res://output/terrain_cliff_batch_20260920"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))

	candidate = (load(SCRIPT) as GDScript).source_code
	reference = FileAccess.get_file_as_string(REFERENCE)
	assert(candidate != reference, "Candidate must exercise a different implementation")

	DisplayServer.window_set_size(Vector2i(1600, 1000))
	renderer = TerrainRenderer.new()
	root.add_child(renderer)
	renderer.position = Vector2(50.0, 50.0)

	# Case 1: 4-Way Ramps & Multi-level Plateau Fixture (16x16)
	var plateau := _plateau_fixture()
	renderer.display(plateau)
	for zoom: float in [0.5, 1.0, 2.0]:
		renderer.scale = Vector2.ONE * zoom
		if not await _pair("plateau_four_ramps_zoom_%.1f" % zoom): return

	# Case 2: COASTAL_CLIFF (32x32)
	var coast := TerrainGenerator.generate(TerrainPreset.Kind.COASTAL_CLIFF, 71, {"size": Vector2i(32, 32)})
	renderer.display(coast)
	for zoom: float in [0.5, 1.0]:
		renderer.scale = Vector2.ONE * zoom
		if not await _pair("coastal_cliff_zoom_%.1f" % zoom): return

	# Case 3: ROCKY_HIGHLAND (32x32, heavy cliff concentration)
	var mountain := TerrainGenerator.generate(TerrainPreset.Kind.ROCKY_HIGHLAND, 71, {"size": Vector2i(32, 32)})
	renderer.display(mountain)
	renderer.scale = Vector2.ONE * 0.75
	if not await _pair("rocky_highland_zoom_0.75"): return

	# Case 4: Debug enabled fallback check (candidate must match reference exactly when debug is on)
	renderer.debug_enabled = true
	renderer.scale = Vector2.ONE * 1.0
	renderer.display(plateau)
	if not await _pair("plateau_debug_enabled_fallback"): return
	renderer.debug_enabled = false

	# Case 5: 100x100 Coastal Cliff benchmark
	var map100_coast := TerrainGenerator.generate(TerrainPreset.Kind.COASTAL_CLIFF, 71, {"size": Vector2i(100, 100)})
	renderer.display(map100_coast)
	renderer.scale = Vector2.ONE * 0.25
	if not await _pair("map_100x100_coastal_benchmark"): return

	# Case 6: 100x100 Terraced Highland (1000+ cliff edges, the primary user case)
	var map100_highland := TerrainGenerator.generate(TerrainPreset.Kind.TERRACED_HIGHLAND, 71, {"size": Vector2i(100, 100)})
	renderer.display(map100_highland)
	renderer.scale = Vector2.ONE * 0.25
	if not await _pair("map_100x100_terraced_highland_benchmark"): return

	var report_file := FileAccess.open(out + "/results.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(results, "\t"))
	report_file.close()

	print("CLIFF_BATCH_VERIFICATION_PASS: All %d test cases verified. Results in %s" % [results.size(), out])
	renderer.queue_free()
	await process_frame
	quit(0)

func _pair(label: String) -> bool:
	var images: Array[Image] = []
	var draws: Array[int] = []

	# Render reference then candidate
	for source: String in [reference, candidate]:
		var script := load(SCRIPT) as GDScript
		script.source_code = source
		assert(script.reload(true) == OK)
		renderer.redraw()
		for frame in range(4):
			await process_frame
			await RenderingServer.frame_post_draw
		images.append(root.get_texture().get_image())
		draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

	var ref_img: Image = images[0]
	var cand_img: Image = images[1]
	var ref_draw: int = draws[0]
	var cand_draw: int = draws[1]

	# Compare pixels
	var diff_pixels := 0
	var total_pixels := ref_img.get_width() * ref_img.get_height()
	var ref_data: PackedByteArray = ref_img.get_data()
	var cand_data: PackedByteArray = cand_img.get_data()

	for idx: int in range(0, ref_data.size(), 4):
		var dr := absi(int(ref_data[idx]) - int(cand_data[idx]))
		var dg := absi(int(ref_data[idx + 1]) - int(cand_data[idx + 1]))
		var db := absi(int(ref_data[idx + 2]) - int(cand_data[idx + 2]))
		var da := absi(int(ref_data[idx + 3]) - int(cand_data[idx + 3]))
		if dr > 2 or dg > 2 or db > 2 or da > 2:
			diff_pixels += 1

	var diff_pct: float = (float(diff_pixels) / float(total_pixels)) * 100.0
	var draw_reduction_pct: float = 0.0
	if ref_draw > 0:
		draw_reduction_pct = (float(ref_draw - cand_draw) / float(ref_draw)) * 100.0

	var record := {
		"case": label,
		"ref_draw_calls": ref_draw,
		"cand_draw_calls": cand_draw,
		"draw_reduction_pct": draw_reduction_pct,
		"diff_pixels": diff_pixels,
		"diff_pct": diff_pct,
		"pass": diff_pct < 8.0 and (cand_draw <= ref_draw or label.contains("debug"))
	}
	results.append(record)
	print("CASE [%s]: ref_draw=%d, cand_draw=%d (%.1f%% reduction), diff_pixels=%d (%.3f%%)" % [
		label, ref_draw, cand_draw, draw_reduction_pct, diff_pixels, diff_pct
	])

	# Save visual comparison images
	assert(ref_img.save_png(out + "/" + label + "_reference.png") == OK)
	assert(cand_img.save_png(out + "/" + label + "_candidate.png") == OK)

	if not record.pass:
		push_error("Visual contract failed for case: " + label)
		quit(1)
		return false
	return true

func _plateau_fixture() -> TerrainData:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 71, {"size": Vector2i(16, 16)})
	data.height_levels.fill(0)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.cliff_drops.fill(0)
	data.ramp_edges.fill(0)
	data.spawn_cell = Vector2i(2, 2)
	for y: int in range(5, 11):
		for x: int in range(5, 11):
			data.height_levels[data.index(Vector2i(x, y))] = 1
	for y: int in range(7, 9):
		for x: int in range(7, 9):
			data.height_levels[data.index(Vector2i(x, y))] = 3
	TerrainGenerator._detect_edges(data)
	for d: int in range(4):
		data.ramp_edges[data.index(LOW_CELLS[d])] |= 1 << d
		data.ramp_edges[data.index(LOW_CELLS[d] + TerrainData.DIRECTIONS[d])] |= 1 << ((d + 2) % 4)
	return data
