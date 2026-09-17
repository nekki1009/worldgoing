extends SceneTree

const SCRIPT := "res://scripts/terrain_lab/terrain_renderer.gd"
const REFERENCE := "res://scripts/tests/fixtures/terrain_renderer_phase24.gd.txt"
var renderer: TerrainRenderer
var candidate := ""
var reference := ""
var out := ""
var results: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "GPU required; this is a pixel contract, not an FPS scene")
	create_timer(80.0).timeout.connect(func() -> void: push_error("Terrain pixel contract deadline"); quit(1))
	out = "res://output/site_army_scale_phase25_20260915/terrain_contract_%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	candidate = (load(SCRIPT) as GDScript).source_code
	reference = FileAccess.get_file_as_string(REFERENCE)
	assert(candidate != reference, "Candidate must exercise a different implementation")
	renderer = TerrainRenderer.new()
	root.add_child(renderer)
	renderer.position = Vector2(13.37, 15.61)
	for preset: int in range(TerrainPreset.NAMES.size()):
		var terrain := TerrainGenerator.generate(preset, 71, {"size": Vector2i(16, 16)})
		for index in range(256): terrain.detail_variation[index] = index
		renderer.display(terrain)
		for zoom: float in [0.375, 1.0]:
			for debug: bool in [false, true]:
				renderer.scale = Vector2.ONE * zoom
				renderer.debug_enabled = debug
				if not await _pair("%s_%.3f_%s" % [TerrainPreset.NAMES[preset], zoom, debug]): return
	# Explicit four-way ramp geometry, all 256 variations and empty/full batches.
	var terrain := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 71, {"size": Vector2i(16, 16)})
	terrain.height_levels.fill(0)
	terrain.surface_types.fill(TerrainData.Surface.GRASS)
	terrain.ramp_edges.fill(0)
	for index in range(256): terrain.detail_variation[index] = index
	for y in range(5, 11):
		for x in range(5, 11): terrain.height_levels[terrain.index(Vector2i(x, y))] = 1
	TerrainGenerator._detect_edges(terrain)
	var low_cells: Array[Vector2i] = [Vector2i(7, 11), Vector2i(4, 7), Vector2i(8, 4), Vector2i(11, 8)]
	for direction in range(4):
		terrain.ramp_edges[terrain.index(low_cells[direction])] |= 1 << direction
		terrain.ramp_edges[terrain.index(low_cells[direction] + TerrainData.DIRECTIONS[direction])] |= 1 << ((direction + 2) % 4)
	renderer.display(terrain)
	renderer.debug_enabled = false
	for zoom: float in [0.2125, 0.5, 1.0, 1.3]:
		renderer.scale = Vector2.ONE * zoom
		if not await _pair("four_ramps_%.4f" % zoom): return
	# Same owner and layer nodes: data changes must invalidate the old primitives.
	terrain.detail_variation.fill(0)
	terrain.ramp_edges.fill(0)
	if not await _pair("changed_details_and_removed_ramps"): return
	terrain.surface_types.fill(TerrainData.Surface.WATER)
	if not await _pair("all_water_empty_brush_batch"): return
	terrain.surface_types.fill(TerrainData.Surface.GRASS)
	terrain.surface_types[255] = TerrainData.Surface.WATER
	if not await _pair("grass_restored_last_cell_water"): return
	assert(results.size() == 39)
	print("TERRAIN_BRUSH_RGBA_PASS 39 exact image pairs: eight presets, 256 variations, debug, four ramps, fractional transforms, same-owner redraw mutations; NOT FPS output=", out)
	renderer.queue_free()
	await process_frame
	quit(0)

func _pair(label: String) -> bool:
	var fingerprint := renderer.data.fingerprint()
	var layers_before := renderer.layers.duplicate()
	var images: Array[Image] = []
	for source: String in [reference, candidate]:
		var script := load(SCRIPT) as GDScript
		script.source_code = source
		assert(script.reload(true) == OK)
		renderer.redraw()
		for frame in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		images.append(root.get_texture().get_image())
	var equal := images[0].get_data() == images[1].get_data()
	var unchanged := fingerprint == renderer.data.fingerprint() and layers_before == renderer.layers
	results.append({"case": label, "exact_full_rgba": equal, "terrain_and_layers_unchanged": unchanged,
		"reference_rgba_sha256": _rgba_hash(images[0].get_data()), "candidate_rgba_sha256": _rgba_hash(images[1].get_data())})
	var file := FileAccess.open(out + "/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	if not equal or not unchanged or label == "four_ramps_0.5000":
		assert(images[0].save_png(out + "/" + label + "_reference.png") == OK)
		assert(images[1].save_png(out + "/" + label + "_candidate.png") == OK)
	if not equal or not unchanged:
		push_error("Terrain brush pixel/owner mismatch: " + label)
		quit(1)
		return false
	return true

func _rgba_hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	assert(context.start(HashingContext.HASH_SHA256) == OK)
	assert(context.update(bytes) == OK)
	return context.finish().hex_encode()
