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
	var all_female := "--female" in OS.get_cmdline_user_args()
	var mixed := "--mixed" in OS.get_cmdline_user_args()
	assert(not (all_female and mixed))
	actual.setup(army, COUNT)
	reference.setup(army, COUNT)
	army._sprites.resize(COUNT)
	for i in range(COUNT):
		var female := all_female or (mixed and i % 2 == 1)
		army.combat_units.append({"person_id": i + 1, "age": 0.0, "pose": "idle", "visual_role": "female_atlas" if female else "male_atlas"})
		var cell := Vector2i(i % 100, (i * 17) % 100)
		if i == 0: cell = Vector2i(127, 5)
		elif i == 1: cell = Vector2i(5, 127)
		elif i == 2: cell = Vector2i(127, 127)
		army.cells.append(cell)
		army.moving_to.append(TerrainArmy.INVALID_CELL)
		army.facing.append([Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i(4, -7)][i % 5])
		var appearance: Dictionary = TerrainArmy.EquipmentAtlas.female_appearance() if female else TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
		var weapon: String = "longsword_01" if female else ["longsword_01", "bow_01", "crossbow_01"][i % 3]
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
	_check_unconscious(army, site, actual, reference, COUNT)
	# One changed input at a time must reject only its row without touching it.
	for condition in range(15):
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
			13: army.combat_units[1].visual_role = "male_live"
			14: army.combat_units[1].visual_role = "unknown_atlas"
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
		army.cells[1] = Vector2i(5, 127)
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
	_check_restored_identity(kernel)
	_check_read_fields(kernel)
	assert(kernel.call("render_idle", [], [], [], [], {}, [], [], [], [], 64.0).is_empty())
	assert(kernel.call("render_idle", army.combat_units, [], army.moving_to, army.facing, site._equipment_appearances, actual._appearances, actual._descriptors, actual._idle_samples, army._sprites, 64.0).is_empty())
	assert(kernel.call("render_idle", army.combat_units, army.cells, army.moving_to, army.facing, site._equipment_appearances, actual._appearances, actual._descriptors, actual._idle_samples, army._sprites, 32.0).is_empty())
	print("ARMY_NATIVE_RENDER_PASS exact_columns=", checked, " gender=", "female" if all_female else ("mixed" if mixed else "male"), " rejection_cases=15 input_bytes_unchanged retained_COW callback_fallback bounds")
	actual.free()
	reference.free()
	army.free()
	site.free()
	return true

func _check_restored_identity(kernel: RefCounted) -> void:
	# JSON stores an exact person ID as FLOAT, while the equipment publisher
	# retains its integer key. A restored roster must stay on native render.
	var restored: Dictionary = JSON.parse_string('{"person_id":1,"age":0.25,"pose":"idle","visual_role":"male_atlas"}')
	assert(typeof(restored.person_id) == TYPE_FLOAT)
	var appearance := {"parts": {}}
	SiteController._freeze_appearance(appearance)
	var directions: Array = []
	for direction in range(4):
		directions.append([direction, 1.0, true, PackedFloat64Array([0.0, 0.5]),
			PackedVector2Array([Vector2.ZERO, Vector2.ONE])])
	var inputs: Array = [[restored], [Vector2i(5, 5)], [TerrainArmy.INVALID_CELL],
		[Vector2i.RIGHT], {1: appearance}, [appearance], [{"page": 0, "palette": 0}],
		[directions], [null], 64.0]
	var original := var_to_bytes(inputs)
	var actual: Array = kernel.callv("render_idle", inputs)
	assert(actual.size() == 7 and actual[0][0] == 1, "JSON-restored person fell off native rendering")
	var canonical := restored.duplicate(true)
	canonical.person_id = 1
	inputs[0] = [canonical]
	var expected: Array = kernel.callv("render_idle", inputs)
	assert(var_to_bytes(actual) == var_to_bytes(expected), "Restored native render columns differ")
	inputs[0] = [restored]
	assert(var_to_bytes(inputs) == original, "Restored native render modified owner rows")

func _check_unconscious(army: TerrainArmy, site: SiteController, actual: Node2D, reference: Node2D, count: int) -> void:
	var knocked := 0
	for i in range(count):
		if i % 4 != 0: continue
		army.combat_units[i].pose = "unconscious"
		army.combat_units[i].hp = 100.0
		army.combat_units[i].ko = 20.0
		knocked += 1
	var boundaries: Array[float] = [0.0, 0.173, 2.4, 1000.173]
	for page: Dictionary in actual._pages:
		for direction: String in ["up", "right", "down", "left"]:
			var key := "unconscious|" + direction
			if not page.sequences.has(key): continue
			var frames: Array = page.samples[page.sequences[key]]
			for frame: Dictionary in [frames[0], frames[frames.size() >> 1], frames.back()]:
				for epsilon: float in [-0.000000002, 0.0, 0.000000002]:
					boundaries.append(maxf(0.0, float(frame.sample_time) + epsilon))
	var compared := 0
	for age: float in boundaries:
		for i in range(count): army.combat_units[i].age = age
		var inputs_before := var_to_bytes([army.combat_units, army.cells, army.moving_to, army.facing, site._equipment_appearances])
		actual.begin()
		actual.prepare_idle()
		assert(actual._native_mask.size() == count and actual.prepared_exceptions().is_empty())
		actual.finish_prepared_groups()
		reference.begin()
		for i in range(count):
			var clip := "unconscious" if i % 4 == 0 else "combat_idle"
			assert(reference.submit(i, army.combat_ground(i), site.person_appearance(i + 1), clip, army._soldier_direction_id(army.facing[i]), age))
		assert(var_to_bytes(_columns(actual)) == var_to_bytes(_columns(reference)), "Unconscious exact columns at %.12f" % age)
		assert(var_to_bytes([army.combat_units, army.cells, army.moving_to, army.facing, site._equipment_appearances]) == inputs_before)
		compared += count
	# The formal A/B switch must restore the old idle-only native admission.
	actual.native_unconscious_enabled = false
	actual.begin()
	actual.prepare_idle()
	assert(actual.prepared_exceptions().size() == knocked)
	for i in range(0, count, 4):
		assert(actual.submit(i, army.combat_ground(i), site.person_appearance(i + 1), "unconscious", army._soldier_direction_id(army.facing[i]), float(army.combat_units[i].age)))
	actual.finish_prepared_groups()
	assert(var_to_bytes(_columns(actual)) == var_to_bytes(_columns(reference)), "Legacy KO fallback differs")
	actual.native_unconscious_enabled = true
	var kernel := TerrainArmy._get_idle_kernel()
	var input := [army.combat_units, army.cells, army.moving_to, army.facing,
		site._equipment_appearances, actual._appearances, actual._descriptors,
		actual._idle_and_unconscious_samples, army._sprites, TerrainRenderer.CELL_PIXELS]
	for condition in range(8):
		var previous_row: Dictionary = army.combat_units[0].duplicate(true)
		var previous_appearance: Dictionary = site.person_appearance(1)
		match condition:
			0: army.combat_units[0].pose = "down"
			1: army.combat_units[0].pose = "get_up"
			2: army.combat_units[0].ko = 0.0
			3: army.combat_units[0].hp = 0.0
			4: army.combat_units[0].exchange_visual = {}
			5: army.moving_to[0] = Vector2i(0, 1)
			6: army._sprites[0] = Sprite2D.new()
			7: site._equipment_appearances[1] = previous_appearance.duplicate(true)
		var before := var_to_bytes([army.combat_units, army.cells, army.moving_to, army.facing, site._equipment_appearances])
		var packet: Array = kernel.callv("render_idle", input)
		assert(packet.size() == 7 and packet[0][0] == 0 and packet[0][4] == 1, "KO fallback %d" % condition)
		assert(var_to_bytes([army.combat_units, army.cells, army.moving_to, army.facing, site._equipment_appearances]) == before)
		if army._sprites[0] != null: army._sprites[0].free(); army._sprites[0] = null
		army.moving_to[0] = TerrainArmy.INVALID_CELL
		army.combat_units[0] = previous_row
		site._equipment_appearances[1] = previous_appearance
	for i in range(count):
		if i % 4 != 0: continue
		army.combat_units[i].pose = "idle"
		army.combat_units[i].erase("hp")
		army.combat_units[i].erase("ko")
	print("ARMY_RENDER_UNCONSCIOUS_PASS rows=", compared, " KO/native/legacy exact columns; down/get_up/wake/death/visual/move/Sprite/appearance fallback")

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
			var input_bytes := var_to_bytes(inputs)
			var actual: Array = kernel.callv("render_idle", inputs)
			var admitted := mode == 3 or (key == "visual_role" and mode == 0)
			for index in range(3):
				assert(actual[0][index] == int(index != 1 or admitted), "%s mode=%d" % [key, mode])
				for field in range(7):
					var expected: Variant = baseline[field][index]
					if index == 1 and not admitted:
						if field == 1:
							expected = Vector2.ZERO
						else:
							expected = 0
					assert(actual[field][index] == expected)
			assert(var_to_bytes(inputs) == input_bytes)
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
