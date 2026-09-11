extends SceneTree

const OUTPUT := "res://.visual_captures/terrain_lab/cliff_readability/"
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const LOW_CELLS: Array[Vector2i] = [Vector2i(7, 11), Vector2i(4, 7), Vector2i(8, 4), Vector2i(11, 8)]
var label_prefix := "after_"
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 24000
	if "--before" in OS.get_cmdline_user_args():
		label_prefix = "before_"
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("CLIFF VISUAL exceeded its capture deadline")
		quit(1)
	return false

func _capture(lab: TerrainLab, label: String, focus: Vector2, zoom: float) -> void:
	lab.camera.zoom = Vector2.ONE * zoom
	lab.camera.position = focus + Vector2(lab.site_controller.PANEL_SPACE * 0.5 / zoom, 0)
	lab.camera.force_update_scroll()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + label_prefix + label + ".png") == OK)

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "GPU surface required")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.npc.set_process(false)
	lab.army.set_process(false)
	var original := lab.terrain.fingerprint()
	await _capture(lab, "highland", lab.renderer.cell_center(lab.terrain.spawn_cell), 0.68)
	assert(lab.terrain.fingerprint() == original)
	# A controlled plateau supplies all four directions; a natural seed need not contain them all.
	var fixture := _plateau_fixture()
	lab.bind_terrain(fixture)
	original = fixture.fingerprint()
	await _capture(lab, "four_sides", Vector2(8, 8) * 64, 1.0)
	for d: int in range(4):
		var low_cell := LOW_CELLS[d]
		assert(lab.character.place(low_cell, true))
		var upper_cell := low_cell + TerrainData.DIRECTIONS[d]
		var midpoint := (lab.renderer.cell_center(low_cell) + lab.renderer.cell_center(upper_cell)) * 0.5
		lab.site_controller.select_cell(upper_cell)
		await _capture(lab, "ramp_" + ["north", "east", "south", "west"][d], midpoint, 2.4)
		assert(lab.character.step(TerrainData.DIRECTIONS[d]))
		while lab.character.is_moving():
			await process_frame
		assert(lab.character.terrain_cell == upper_cell)
		assert(lab.character.step(-TerrainData.DIRECTIONS[d]))
		while lab.character.is_moving():
			await process_frame
		assert(lab.character.terrain_cell == low_cell)
	assert(lab.terrain.fingerprint() == original, "Drawing changed terrain or passage data")
	assert(not fixture.can_step(Vector2i(6, 7), Vector2i(7, 7)), "A two-level cliff became a passage")
	var coast := TerrainGenerator.generate(TerrainPreset.Kind.COASTAL_CLIFF, 71)
	Env.initialize(coast)
	lab.bind_terrain(coast)
	var shore_cell := Vector2i(-1, -1)
	for i: int in range(coast.height_levels.size()):
		if coast.surface_types[i] == TerrainData.Surface.WATER:
			continue
		var cell := coast.cell_from_index(i)
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var neighbor := cell + direction
			if coast.contains(neighbor) and coast.surface_types[coast.index(neighbor)] == TerrainData.Surface.WATER:
				if shore_cell.x < 0 or cell.distance_squared_to(coast.spawn_cell) < shore_cell.distance_squared_to(coast.spawn_cell):
					shore_cell = cell
	assert(shore_cell.x >= 0)
	await _capture(lab, "coast", lab.renderer.cell_center(shore_cell), 0.75)
	assert(lab.renderer.get_child_count() == 4)
	print("CLIFF GPU PASS: four slope orientations crossed both ways, rendering did not mutate terrain, four terrain batches; inspect same-seed before/after PNGs")
	lab.queue_free()
	await process_frame
	quit(0)

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
	Env.initialize(data)
	data.resource_base.clear() # Visual fixture isolates cliff geometry from resource occlusion.
	data.resources_at.clear()
	Env.rebuild_indexes(data)
	return data
