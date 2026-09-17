extends SceneTree
## Native boundary and actual atlas projection; not an alternate FPS scene.
const Batch = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")

func _initialize() -> void:
	_run.call_deferred()

func _columns(view: Node2D) -> Array:
	return [view._positions, view._sequence, view._frames, view._page, view._palette, view._rows, view.rendered_count]

func _run() -> void:
	quit(0 if _check() else 1)

func _check_sample_reuse(kernel: RefCounted) -> void:
	# A single-row call cannot hit a preceding sample. Compare all seven output
	# columns to these cold calls, including rejection and cross-call changes.
	var pages: Array = []
	for page in range(2):
		var directions: Array = []
		for direction in range(4):
			directions.append([page * 4 + direction, 1.0, page == 0,
				PackedFloat64Array([0.0, 0.25, 0.75]),
				PackedVector2Array([Vector2(page, direction), Vector2(2.5 + page, 3.5 + direction), Vector2(5.5 + page, 7.5 + direction)])])
		pages.append(directions)
	pages.append([]) # Malformed page between two identical successful requests.
	var appearance := {"parts": {}}
	SiteController._freeze_appearance(appearance)
	var checked := 0
	var retained: Array = []
	var retained_bytes := PackedByteArray()
	for pattern in range(5):
		# Reusing the same input containers across calls must not retain a sample.
		pages[0][0][0] = 100 + pattern
		var inputs: Array = [[], [], [], [], {}, [], [], pages, [], 64.0]
		for i in range(64):
			var page := (i >> 3) % 2 if pattern in [1, 4] else 0
			var direction := (i >> 2) % 5 if pattern in [2, 4] else 0
			var age: float = [0.0, -0.0, 0.25 - 0.000000002, 0.25, 0.25 + 0.000000002, 0.75, 1.0, 1000.75][(i >> 1) % 8] if pattern in [3, 4] else 0.75
			inputs[0].append({"person_id": i + 1, "age": age, "pose": "idle", "visual_role": "male_atlas"})
			inputs[1].append(Vector2i(i, 63 - i))
			inputs[2].append(TerrainArmy.INVALID_CELL)
			inputs[3].append([Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i(4, -7)][direction])
			inputs[4][i + 1] = appearance
			inputs[5].append(appearance)
			inputs[6].append({"page": 2 if i == 17 else page, "palette": 0})
			inputs[8].append(null)
		inputs[0][19].age = INF
		inputs[0][21].pose = "hit"
		inputs[8][23] = true # Every non-NIL original Sprite slot is unadmitted.
		var original := var_to_bytes(inputs)
		var actual: Array = kernel.callv("render_idle", inputs)
		var expected: Array = [PackedByteArray(), PackedVector2Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
		for i in range(64):
			var single := inputs.duplicate()
			for column in [0, 1, 2, 3, 5, 6, 8]: single[column] = [inputs[column][i]]
			var cold: Array = kernel.callv("render_idle", single)
			assert(cold.size() == 7)
			for column in range(7): expected[column].append_array(cold[column])
		assert(var_to_bytes(actual) == var_to_bytes(expected), "Repeated atlas sample pattern %d" % pattern)
		assert(actual[0][16] == 1 and actual[0][17] == 0 and actual[0][18] == 1)
		assert(var_to_bytes(inputs) == original, "Render sample reuse mutated its inputs")
		if not retained.is_empty(): assert(var_to_bytes(retained) == retained_bytes, "Cross-call output alias changed")
		retained = actual
		retained_bytes = var_to_bytes(actual)
		checked += 64
	print("ARMY_RENDER_SAMPLE_REUSE_PASS rows=", checked, " exact cold-call columns; page/direction/time/rejection/reset/alias")

func _check() -> bool:
	var army := TerrainArmy.new()
	root.add_child(army)
	army.set_process(false)
	assert(TerrainArmy.load_combat_bake() and army._load_baked_soldier())
	army._soldier_baked_ready = true # Normally assigned by the original visual setup caller.
	var site := SiteController.new()
	root.add_child(site)
	army.equipment_appearance_query = site.person_appearance
	army.equipment_appearance_batch_query = site.person_appearance_batch
	var actual := Batch.new()
	var reference := Batch.new()
	root.add_child(actual)
	root.add_child(reference)
	var COUNT := 2500 if "--large" in OS.get_cmdline_user_args() else 200
	actual.setup(army, COUNT)
	reference.setup(army, COUNT)
	army._sprites.resize(COUNT)
	for i in range(COUNT):
		army.combat_units.append({"person_id": i + 1, "age": 0.0, "pose": "idle", "visual_role": "male_atlas"})
		army.cells.append(Vector2i(i % 100, (i * 17) % 100))
		army.moving_to.append(TerrainArmy.INVALID_CELL)
		army.facing.append([Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i(4, -7)][i % 5])
		var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
		var weapon: String = ["longsword_01", "bow_01", "crossbow_01"][i % 3]
		appearance.parts.weapon = weapon
		if weapon != "longsword_01": appearance.parts.shield = "none"
		appearance.equipment_dyes = {"armor": "114477ff" if i % 2 == 0 else "ee3366ff"}
		SiteController._freeze_appearance(appearance)
		site._equipment_appearances[i + 1] = appearance
		for view: Node2D in [actual, reference]:
			assert(view.submit(i, army.combat_ground(i), appearance, "combat_idle", army._soldier_direction_id(army.facing[i]), 0.0))
	var checked := 0
	var boundaries: Array[float] = [0.0, -0.0, 0.371, 0.9, 1.0, 1000.371]
	for page: Dictionary in actual._pages:
		for direction: String in ["up", "right", "down", "left"]:
			for frame: Dictionary in page.samples[page.sequences["combat_idle|" + direction]]:
				for epsilon: float in [-0.000000002, 0.0, 0.000000002]:
					boundaries.append(maxf(0.0, float(frame.sample_time) + epsilon))
	for age: float in boundaries:
		for i in range(COUNT): army.combat_units[i].age = age
		var row_aliases := army.combat_units.duplicate()
		var original := var_to_bytes([army.combat_units, army.cells, army.moving_to, army.facing, site._equipment_appearances])
		var retained_positions: PackedVector2Array = actual._positions
		var retained_bytes := retained_positions.to_byte_array()
		actual.begin()
		actual.prepare_idle()
		reference.begin()
		assert(actual.can_group_prepared() and actual.prepared_exceptions().is_empty())
		actual.finish_prepared_groups()
		assert(actual._groups_ready and actual.native_grouped_count == COUNT)
		for i in range(COUNT):
			assert(reference.submit(i, army.combat_ground(i), site.person_appearance(i + 1), "combat_idle", army._soldier_direction_id(army.facing[i]), age))
		assert(var_to_bytes(_columns(actual)) == var_to_bytes(_columns(reference)), "Exact atlas columns at %.12f" % age)
		assert(original == var_to_bytes([army.combat_units, army.cells, army.moving_to, army.facing, site._equipment_appearances]))
		for i in range(COUNT): assert(is_same(row_aliases[i], army.combat_units[i]), "Original row identity replaced")
		assert(retained_positions.to_byte_array() == retained_bytes, "Native output modified retained COW data")
		checked += COUNT
	# One changed input at a time must reject only its row without touching it.
	for condition in range(13):
		var before_row := army.combat_units[1].duplicate(true)
		var before_appearance: Dictionary = site.person_appearance(2)
		match condition:
			0: army.combat_units[1].pose = "hit"
			1: army.combat_units[1].exchange_visual = {}
			2: army.moving_to[1] = Vector2i.ZERO
			3: army.combat_units[1].visual_role = "female_live"
			4: army.combat_units[1].age = INF
			5: army.combat_units[1].age = -0.001
			6: army.combat_units[1].age = NAN
			7: site._equipment_appearances[2] = before_appearance.duplicate(true)
			8:
				var changed := before_appearance.duplicate(true)
				changed.equipment_dyes.armor = "aabbccff"
				SiteController._freeze_appearance(changed)
				site._equipment_appearances[2] = changed
			9: site._equipment_appearances.erase(2)
			10: army.cells[1] = Vector2i(-1, 10)
			11: army.combat_units[1].pose = &"idle"
			12: army._sprites[1] = Sprite2D.new()
		var original := var_to_bytes([army.combat_units, army.cells, army.moving_to, site._equipment_appearances])
		actual.begin()
		actual.prepare_idle()
		assert(actual._native_mask[0] == 1 and actual._native_mask[1] == 0 and actual._native_mask[2] == 1, "Boundary %d" % condition)
		assert(original == var_to_bytes([army.combat_units, army.cells, army.moving_to, site._equipment_appearances]))
		if condition == 8:
			# Actual changed publication takes the original descriptor/dye path,
			# then becomes eligible again only after that successful admission.
			reference.begin()
			for i in range(COUNT):
				var appearance := site.person_appearance(i + 1)
				var direction := army._soldier_direction_id(army.facing[i])
				var age := float(army.combat_units[i].age)
				if not actual.submit_prepared(i): assert(actual.submit(i, army.combat_ground(i), appearance, "combat_idle", direction, age))
				assert(reference.submit(i, army.combat_ground(i), appearance, "combat_idle", direction, age))
			assert(var_to_bytes(_columns(actual)) == var_to_bytes(_columns(reference)), "Changed dye fallback differs")
			actual.begin()
			actual.prepare_idle()
			assert(actual._native_mask[1] == 1, "Re-admitted publication did not resume native")
		if army._sprites[1] != null: army._sprites[1].free(); army._sprites[1] = null
		army.combat_units[1] = before_row
		army.cells[1] = Vector2i(1, 17)
		army.moving_to[1] = TerrainArmy.INVALID_CELL
		site._equipment_appearances[2] = before_appearance
	# Callback replacement cannot be bypassed even if an old batch provider remains.
	var calls := [0]
	army.equipment_appearance_query = func(identity: int) -> Dictionary: calls[0] += 1; return site.person_appearance(identity)
	actual.begin()
	actual.prepare_idle()
	assert(actual._native_mask.is_empty() and calls[0] == 0)
	for i in range(COUNT):
		assert(not actual.submit_prepared(i))
		assert(actual.submit(i, army.combat_ground(i), army.equipment_appearance(i), "combat_idle", army._soldier_direction_id(army.facing[i]), float(army.combat_units[i].age)))
	assert(calls[0] == COUNT)
	var kernel := TerrainArmy._get_idle_kernel()
	_check_sample_reuse(kernel)
	_check_read_fields(kernel)
	assert(kernel.call("render_idle", [], [], [], [], {}, [], [], [], [], 64.0).is_empty())
	assert(kernel.call("render_idle", army.combat_units, [], army.moving_to, army.facing, site._equipment_appearances, actual._appearances, actual._descriptors, actual._idle_samples, army._sprites, 64.0).is_empty())
	assert(kernel.call("render_idle", army.combat_units, army.cells, army.moving_to, army.facing, site._equipment_appearances, actual._appearances, actual._descriptors, actual._idle_samples, army._sprites, 32.0).is_empty())
	print("ARMY_NATIVE_RENDER_PASS exact_columns=", checked, " rejection_cases=13 input_bytes_unchanged retained_COW callback_fallback bounds")
	actual.free()
	reference.free()
	army.free()
	site.free()
	return true

func _check_read_fields(kernel: RefCounted) -> void:
	var appearance := {"parts": {}}
	SiteController._freeze_appearance(appearance)
	var sample := [0, 1.0, true, PackedFloat64Array([0.0]), PackedVector2Array([Vector2.ZERO])]
	var source: Array = [[], [], [], [], {}, [], [], [[sample, sample, sample, sample]], [], 64.0]
	for i in range(3):
		source[0].append({"person_id": (1 << 54) + i, "age": 0.0, "pose": "idle", "visual_role": "male_atlas"})
		source[1].append(Vector2i(i, 4))
		source[2].append(TerrainArmy.INVALID_CELL)
		source[3].append(Vector2i.DOWN)
		source[4][(1 << 54) + i] = appearance
		source[5].append(appearance)
		source[6].append({"page": 0, "palette": 0})
		source[8].append(null)
	var baseline: Array = kernel.callv("render_idle", source)
	assert(baseline[0] == PackedByteArray([1, 1, 1]))
	var checked := 0
	for key: String in ["pose", "visual_role", "age", "person_id", "page", "palette"]:
		for mode in range(4):
			var inputs := source.duplicate()
			var column := 6 if key in ["page", "palette"] else 0
			inputs[column] = source[column].duplicate()
			var row: Dictionary = source[column][1].duplicate()
			inputs[column][1] = row
			match mode:
				0: row.erase(key)
				1: row[key] = null
				2: row[key] = true
				3:
					var value: Variant = row[key]
					row.erase(key)
					row[StringName(key)] = value
			var before := var_to_bytes(inputs)
			var actual: Array = kernel.callv("render_idle", inputs)
			var admitted := mode == 3 or (key == "visual_role" and mode == 0)
			for index in range(3):
				assert(actual[0][index] == int(index != 1 or admitted), "%s mode=%d" % [key, mode])
				for field in range(7):
					var expected: Variant = baseline[field][index] if index != 1 or admitted else (Vector2.ZERO if field == 1 else 0)
					assert(actual[field][index] == expected)
			assert(var_to_bytes(inputs) == before)
			checked += 1
	# Typed/read-only dictionaries are legal read inputs; no raw write is allowed.
	for column in [0, 6]:
		var typed: Dictionary[StringName, Variant] = {}
		for key: String in source[column][1]: typed[StringName(key)] = source[column][1][key]
		typed.make_read_only()
		source[column][1] = typed
	var before := var_to_bytes(source)
	assert(var_to_bytes(kernel.callv("render_idle", source)) == var_to_bytes(baseline))
	assert(var_to_bytes(source) == before)
	print("ARMY_RENDER_READ_FIELDS_PASS cases=", checked, " absent/NIL/type/StringName/typed-readonly/64bit-id; original inputs untouched")
