extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var kernel := TerrainArmy._get_idle_kernel()
	assert(kernel != null and ClassDB.class_exists(&"ArmyCombatHot"))
	var hot: RefCounted = ClassDB.instantiate(&"ArmyCombatHot")
	var rows := [
		{"person_id": 11, "visual_role": "male_atlas", "hp": 100.0, "ko": 0.0, "age": 0.25,
			"think": 0.5, "stun": 0.0, "grace": 0.0, "pose": "idle", "attack": false,
			"captive": false, "departed": false, "present": false},
		{"person_id": 12, "visual_role": "female_atlas", "hp": 0.0, "ko": 0.0, "age": 0.25,
			"think": 0.5, "stun": 0.0, "grace": 0.0, "pose": "idle", "attack": false,
			"captive": false, "departed": false, "present": false}]
	var cells := [Vector2i(2, 3), Vector2i(3, 3)]
	var appearance := {"parts": {}}
	SiteController._freeze_appearance(appearance)
	var directions := []
	for direction in range(4):
		directions.append([direction, 1.0, true, PackedFloat64Array([0.0, 0.5]),
			PackedVector2Array([Vector2.ZERO, Vector2.ONE])])
	var render := [rows, cells, [TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL],
		[Vector2i.UP, Vector2i.RIGHT], {11: appearance, 12: appearance},
		[appearance, appearance], [{"page": 0, "palette": 0}, {"page": 0, "palette": 1}],
		[directions], [null, null], 64.0]
	var expected := [kernel.call("capture_columns", rows, cells),
		kernel.call("capture_people", rows, cells, self, 7),
		kernel.call("command_presence", rows, cells, {}),
		kernel.call("command_presence_delta", rows, cells, {}, 2.0, []),
		kernel.callv("render_idle", render)]
	assert(expected[0][0] == PackedInt32Array([0]) and expected[4][0] == PackedByteArray([1, 1]))
	var walker_source: Dictionary = rows[0].duplicate(true)
	walker_source.pose = "walk"
	walker_source.think = 0.15
	assert(hot.load_rows(rows))
	for row: Dictionary in rows:
		for field: StringName in TerrainArmy.COMBAT_HOT_FIELDS:
			row.erase(String(field))
	assert(not rows[0].has("hp") and not rows[0].has("pose") and not rows[0].has("present"))
	var actual := [hot.call("capture_columns", rows, cells),
		hot.call("capture_people", rows, cells, self, 7),
		hot.call("command_presence", rows, cells, {}),
		hot.call("command_presence_delta", rows, cells, {}, 2.0, []),
		hot.callv("render_idle", render)]
	for index in expected.size():
		assert(var_to_bytes(actual[index]) == var_to_bytes(expected[index]), "Hot projection %d changed output" % index)
	assert(hot.retained_idle_mask() == PackedByteArray([1, 1]))
	assert(hot.can_act(0) and not hot.can_act(1) and not hot.can_act(-1))
	assert(hot.set_field(0, "pose", "get_up") and not hot.can_act(0) and hot.retained_idle_mask()[0] == 0)
	assert(hot.set_field(0, "pose", "idle") and hot.set_field(0, "ko", 1.0) and not hot.can_act(0))
	assert(hot.set_field(0, "exchange_visual", {}) and hot.retained_idle_mask()[0] == 0)
	assert(hot.set_field(0, "exchange_visual", {"hit": true}) and hot.retained_idle_mask()[0] == 0)
	assert(hot.erase_field(0, "exchange_visual") and hot.retained_idle_mask()[0] == 1)
	rows[1] = rows[0]
	assert(hot.call("command_presence_delta", rows, cells, {}, 2.0, []).is_empty(), "Aliased owner rows reject atomically")
	assert(hot.load_rows([walker_source]))
	var progress := PackedFloat64Array([0.25])
	var movement: PackedInt32Array = hot.advance_numeric([Vector2i(3, 3)], progress,
		PackedFloat64Array([1.0]), {}, 0, 1, 0.1, 0.1, 15.0)
	assert(movement == PackedInt32Array([1, 0]), "Moving walk remains on the native safe path")
	assert(progress[0] == 0.25 + 0.1 and float(hot.get_field(0, "age", 0.0)) == 0.25 + 0.1
		and float(hot.get_field(0, "think", 0.0)) == 0.15 - 0.1, "Moving walk clocks advance exactly once")
	var hold_rows := []
	for settings: Dictionary in [
		{"pose": "idle", "think": 0.5}, {"pose": "idle", "think": 0.15},
		{"pose": "idle", "think": 0.1},
		{"pose": "idle", "think": 0.5, "ko": 1.0},
		{"pose": "idle", "think": 0.5, "hp": 0.0},
		{"pose": "guard", "think": 0.5},
		{"pose": "guard_raise", "think": 0.5},
		{"pose": "idle", "think": 0.5, "ko": 1.0, "exchange_visual": {}}]:
		var row: Dictionary = walker_source.duplicate(true)
		row.merge(settings, true)
		hold_rows.append(row)
	var hold: RefCounted = ClassDB.instantiate(&"ArmyCombatHot")
	assert(hold.load_rows(hold_rows) and hold.has_method("advance_numeric_hold"))
	var hold_moving: Array = []
	var hold_progress := PackedFloat64Array()
	var hold_durations := PackedFloat64Array()
	for unused in hold_rows.size():
		hold_moving.append(TerrainArmy.INVALID_CELL)
		hold_progress.append(0.0)
		hold_durations.append(1.0)
	var hold_expected := [PackedInt32Array([1, 0]), PackedInt32Array([2, 0]),
		PackedInt32Array([2, 3]), PackedInt32Array([4, 0]),
		PackedInt32Array([5, 0]), PackedInt32Array([6, 0]),
		PackedInt32Array([6, 3]), PackedInt32Array([7, 3])]
	for index in hold_rows.size():
		var before: Dictionary = hold.capture_row(index)
		var status: PackedInt32Array = hold.advance_numeric_hold(hold_moving, hold_progress,
			hold_durations, {}, index, index + 1, 0.1, 0.1, 15.0)
		assert(status == hold_expected[index], "HOLD native barrier %d" % index)
		if status[1] != 0:
			assert(var_to_bytes(hold.capture_row(index)) == var_to_bytes(before), "HOLD barrier must not mutate row %d" % index)
	assert(float(hold.get_field(0, "age", 0.0)) == 0.25 + 0.1
		and float(hold.get_field(0, "think", 0.0)) == maxf(0.0, 0.5 - 0.1)
		and float(hold.get_field(1, "think", 0.0)) == maxf(0.0, 0.15 - 0.1),
		"HOLD idle age and one think decrement match the owner")
	assert(float(hold.get_field(3, "ko", 0.0)) == 1.0 - 0.1 and float(hold.get_field(3, "think", 0.0)) == 0.5
		and float(hold.get_field(4, "age", 0.0)) == 0.25 + 0.1 and float(hold.get_field(4, "think", 0.0)) == 0.5,
		"HOLD KO and death continue before think")
	assert(float(hold.get_field(5, "think", 0.0)) == maxf(0.0, 0.5 - 0.1)
		and float(hold.get_field(5, "age", 0.0)) == 0.25 + 0.1, "HOLD guard remains on the safe path")
	var output := FileAccess.open("res://output/site_army_5k_hot_close_20260926/hot_projection_smoke.json", FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify({"checks": {"capture_columns": true, "capture_people": true,
		"command_presence": true, "command_presence_delta": true, "render_idle": true,
		"can_act": true, "retained_idle_mask": true, "empty_visual_rejection": true,
		"alias_rejection": true, "moving_walk_exact": true,
		"hold_idle_exact": true, "hold_think_barrier": true, "hold_ko_death": true,
		"hold_guard": true, "hold_empty_visual_barrier": true},
		"cpp_sha256": FileAccess.get_sha256("res://native/army_idle/army_idle.cpp"),
		"dll_sha256": FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll"),
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_hot_projection_native_test.gd"),
		"batch_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_batch_view.gd")}))
	output.close()
	print("ARMY_HOT_PROJECTIONS_PASS capture/presence/delta/render exact stripped-row packets; can_act; retained mask; alias rejection; moving walk; HOLD exact/barriers")
	quit(0)
