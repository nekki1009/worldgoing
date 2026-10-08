extends SceneTree
## Exact original atlas/ground/buffer oracle; no FPS claim or alternate renderer.
const Batch = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const OUTPUT := "res://output/site_movement_batch_implementation_20260928/revision2/render_parity.json"
var comparisons := 0

func _initialize() -> void:
	_run.call_deferred()

func _state(view: Node2D) -> Array:
	var rows := {}
	var keys: Array = view._rows.keys()
	keys.sort()
	for key: int in keys: rows[key] = view._rows[key]
	var buffers := {}
	keys = view._batches.keys()
	keys.sort()
	for key: Vector2i in keys:
		var batch: MultiMeshInstance2D = view._batches[key]
		if batch.visible: buffers[key] = [batch.multimesh.buffer, batch.multimesh.custom_aabb]
	return [view._positions, view._sequence, view._frames, view._page, view._palette, rows, buffers, view.rendered_count]

func _compare(army: TerrainArmy, expected: Node2D, label: String, minimum_native: int) -> void:
	var before := var_to_bytes([army.combat_units, army.cells, army.moving_to, army.move_progress, army.move_duration, army.move_curve])
	expected.begin()
	for index in range(army.roster_size):
		var pose := army._exchange_visual_pose(index)
		var clip := army._combat_clip(index, pose)
		var direction := army._soldier_direction_id(army._exchange_visual_facing(index, pose))
		var duration := float(army._combat_bake.contact_clocks[clip][direction][1])
		var sample := army._exchange_animation_time(index, duration, pose)
		assert(expected.submit(index, army.combat_visual_ground(index), army.equipment_appearance(index), clip, direction, sample, duration), label + " reference admission")
	expected.flush()
	army._visual_dirty = true
	army.advance_frame(0.0)
	var actual: Node2D = army._batch_view
	var left := _state(actual)
	var right := _state(expected)
	for column in range(left.size()):
		assert(var_to_bytes(left[column]) == var_to_bytes(right[column]), "%s column %d" % [label, column])
	assert(actual.native_moving_count >= minimum_native, label + " native moving admission")
	assert(before == var_to_bytes([army.combat_units, army.cells, army.moving_to, army.move_progress, army.move_duration, army.move_curve]), label + " presentation changed simulation")
	comparisons += 1

func _run() -> void:
	var army := TerrainArmy.new()
	root.add_child(army)
	army.set_process(false)
	army.roster_size = 64
	army.native_hot_enabled = true
	army.exchange_enabled = true
	var initial: Array[Vector2i] = []
	for index in range(64): initial.append(Vector2i(10 + (index % 8) * 3, 10 + floori(float(index) / 8.0) * 3))
	initial[1] = initial[0] + Vector2i.RIGHT
	assert(army.deploy_at(Helper.build_flat_map(), null, null, initial) and army.enable_combat(false))
	assert(army.combat_hot_active() and TerrainArmy.load_combat_bake() and army._load_baked_soldier())
	army._soldier_baked_ready = true
	var site := SiteController.new()
	root.add_child(site)
	army.equipment_appearance_query = site.person_appearance
	army.equipment_appearance_batch_query = site.person_appearance_batch
	var actual := Batch.new()
	var expected := Batch.new()
	army.add_child(actual)
	root.add_child(expected)
	actual.setup(army, 64)
	expected.setup(army, 64)
	actual.retained_enabled = true
	expected.retained_enabled = true
	army._batch_view = actual
	army._sprites.resize(64)
	for index in range(64):
		army.combat_units[index].visual_role = "male_atlas"
		army.combat_hot_set(index, &"pose", "idle")
		army.combat_hot_set(index, &"age", 0.0)
		var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
		appearance.equipment_dyes = {"armor": "114477ff" if index % 2 == 0 else "ee3366ff"}
		SiteController._freeze_appearance(appearance)
		site._equipment_appearances[army.combat_identity(index)] = appearance
		for view: Node2D in [actual, expected]:
			assert(view.submit(index, army.combat_ground(index), appearance, "combat_idle", army._soldier_direction_id(army.facing[index]), 0.0))
	actual.flush()
	expected.flush()
	army._visual_full_dirty = false
	_compare(army, expected, "initial idle", 0)
	assert(actual._retained_ready and not actual.use_native_crowd())
	army.moving_to[7] = army.cells[7] + Vector2i.RIGHT
	army._reserved_cells[army.moving_to[7]] = 7
	army.move_progress[7] = 0.35
	army.combat_hot_set(7, &"pose", "walk")
	assert(not actual.use_native_crowd())
	_compare(army, expected, "sparse retained", 0)
	assert(actual.native_crowd_frames == 0)
	army._reserved_cells.clear()
	for index in range(64):
		army.facing[index] = TerrainData.DIRECTIONS[index % 4]
		army.moving_to[index] = army.cells[index] + army.facing[index]
		army.move_duration[index] = TerrainArmy.RUN_DURATION if index % 3 == 0 else TerrainArmy.MOVE_DURATION
		army.move_curve[index] = index % 2
		army.combat_hot_set(index, &"pose", "walk")
		army._reserved_cells[army.moving_to[index]] = index
	army.moving_to[0] = army.cells[1]
	army.moving_to[1] = army.cells[0]
	army.facing[0] = Vector2i.RIGHT
	army.facing[1] = Vector2i.LEFT
	assert(actual.use_native_crowd())
	for progress: float in [0.0, 0.000001, 0.123456789, 0.35, 0.5, 0.999999, 1.0]:
		army.move_progress.fill(progress)
		for index in range(64): army.combat_hot_set(index, &"age", progress * 2.371 + float(index % 3) * 0.01)
		_compare(army, expected, "dense %.9f" % progress, 64)
		assert(not actual._retained_ready)
	# Every atlas boundary uses the original double clock, including running.
	for clip: String in ["combat_walk", "combat_run"]:
		for frame: Dictionary in actual._pages[0].samples[actual._pages[0].sequences[clip + "|down"]]:
			for epsilon: float in [-0.000000002, 0.0, 0.000000002]:
				for index in range(64): army.combat_hot_set(index, &"age", maxf(0.0, float(frame.sample_time) + epsilon))
				_compare(army, expected, "boundary %s %.12f" % [clip, float(frame.sample_time) + epsilon], 64)
	army.combat_hot_set(2, &"exchange_visual", {"pose": "hit", "age": 0.1, "left": 0.2, "facing": Vector2i.LEFT})
	_compare(army, expected, "exchange fallback", 63)
	army.combat_hot_erase(2, &"exchange_visual")
	var kernel: RefCounted = army._combat_hot_store
	var inputs: Array = [army.combat_units, army.cells, army.moving_to, army.facing,
		site.person_appearance_batch(site.person_appearance), actual._appearances, actual._descriptors,
		actual._crowd_samples, army._sprites, TerrainRenderer.CELL_PIXELS,
		[army.move_progress, army.move_duration, army.move_curve, army._cell_owners, TerrainArmy.RUN_DURATION]]
	var original := var_to_bytes(inputs)
	var packet: Array = kernel.callv("render_crowd", inputs)
	assert(packet.size() == 8 and int(packet[7]) == 64)
	var saved: PackedVector2Array = packet[1]
	var saved_bytes := saved.to_byte_array()
	assert(var_to_bytes(inputs) == original)
	var invalid := inputs.duplicate()
	invalid[10] = [PackedFloat64Array(), army.move_duration, army.move_curve, army._cell_owners, TerrainArmy.RUN_DURATION]
	assert(kernel.callv("render_crowd", invalid).is_empty())
	assert(saved.to_byte_array() == saved_bytes)
	army._reserved_cells.clear()
	army.moving_to.fill(TerrainArmy.INVALID_CELL)
	for index in range(64): army.combat_hot_set(index, &"pose", "idle")
	_compare(army, expected, "stopped rebuild", 0)
	assert(actual._retained_ready and not actual.use_native_crowd())
	_compare(army, expected, "stopped retained", 0)
	var result := {"status": "PASS", "comparisons": comparisons, "native_crowd_frames": actual.native_crowd_frames,
		"native_moving_total": actual.native_moving_total, "exact_columns_and_buffers": true}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	print("ARMY_MOVING_NATIVE_RENDER_PASS ", JSON.stringify(result))
	army._batch_view = null
	army.free()
	expected.free()
	site.free()
	quit(0)
