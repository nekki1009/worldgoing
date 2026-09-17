extends SceneTree
## Call boundary/memory semantics and CPU probe only, not a replacement FPS scene.
const EXTENSION := "res://native/army_idle/army_idle.gdextension"
var kernel: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func _row() -> Dictionary:
	return {"age": 0.0, "think": 0.5, "pose": "idle", "hp": 100.0, "ko": 0.0, "stun": 0.0, "grace": 0.0, "fatigue": 0.0, "fatigue_rest": 0.0}

func _reference(rows: Array[Dictionary], moving: Array[Vector2i], rescues: Dictionary, start: int, end: int, delta: float) -> int:
	for i in range(start, end):
		var unit := rows[i]
		if not (unit.pose == "idle" and float(unit.hp) > 0.0 and float(unit.ko) <= 0.0 and moving[i] == Vector2i(-1, -1) and not rescues.has(i)
			and unit.stun == 0.0 and unit.grace == 0.0 and (not unit.has("exchange_visual") or unit.exchange_visual.is_empty()) and unit.get("exchange_pose_duration", 0.0) == 0.0
			and unit.get("exchange_cooldown", 0.0) == 0.0 and unit.get("exchange_stagger", 0.0) == 0.0 and unit.get("exchange_skill_cooldown", 0.0) == 0.0 and unit.get("ranged_cooldown", 0.0) == 0.0): return i
		unit.age = float(unit.age) + delta
		unit["exchange_cooldown"] = 0.0
		unit["exchange_stagger"] = 0.0
		unit["exchange_skill_cooldown"] = 0.0
		unit["ranged_cooldown"] = 0.0
		unit.grace = 0.0
		unit.stun = 0.0
		unit.think = maxf(0.0, float(unit.think) - delta)
	return end

func _run() -> void:
	if not GDExtensionManager.is_extension_loaded(EXTENSION):
		assert(GDExtensionManager.load_extension(EXTENSION) == GDExtensionManager.LOAD_STATUS_OK)
	assert(ClassDB.class_exists(&"ArmyIdleKernel"))
	kernel = ClassDB.instantiate(&"ArmyIdleKernel")
	assert(kernel != null)
	var negative_zero := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	var checked := 0
	for condition in range(18):
		var rows: Array[Dictionary] = [_row(), _row(), _row(), _row()]
		var moving: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1)]
		var rescues := {}
		match condition:
			0: rows[1].stun = 0; rows[1].grace = negative_zero; rows[1].age = 2; rows[1].think = 0
			1: rows[1].exchange_visual = {}
			2: rows[1].exchange_cooldown = negative_zero
			3: rows[1].exchange_stagger = 0
			4: rows[1].exchange_pose_duration = negative_zero
			5: rows[1].pose = "hit"
			6: rows[1].hp = 0.0
			7: rows[1].ko = 1.0
			8: moving[1] = Vector2i.ZERO
			9: rescues[1] = {"patient": 2}
			10: rows[1].stun = 0.001
			11: rows[1].grace = 0.001
			12: rows[1].exchange_visual = {"pose": "hit"}
			13: rows[1].exchange_pose_duration = 0.001
			14: rows[1].exchange_cooldown = 0.0000000001
			15: rows[1].exchange_stagger = 0.0000000001
			16: rows[1].exchange_skill_cooldown = 0.0000000001
			17: rows[1].ranged_cooldown = 0.0000000001
		var before := rows.duplicate(true)
		var alias := rows[0]
		var reference: Array[Dictionary] = rows.duplicate(true)
		var expected := _reference(reference, moving, rescues, 0, 4, 1.0 / 30.0)
		var consumed := int(kernel.advance_prefix(rows, moving, rescues, 0, 4, 1.0 / 30.0))
		assert(consumed == expected)
		assert(var_to_bytes(rows) == var_to_bytes(reference), "Prefix mismatch condition=%d" % condition)
		assert(is_same(alias, rows[0]), "Original row identity replaced")
		if consumed < 4:
			assert(var_to_bytes(rows[consumed]) == var_to_bytes(before[consumed]), "Rejected row partially advanced")
			# Simulate original fallback modifying a later row, then resume.
			rows[2].ko = 1.0
			reference[2].ko = 1.0
			assert(kernel.advance_prefix(rows, moving, rescues, 2, 4, 1.0 / 30.0) == 2)
			assert(var_to_bytes(rows) == var_to_bytes(reference))
		checked += 1
	var shared := _row()
	var aliased: Array[Dictionary] = [shared, shared]
	var positions: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(-1, -1)]
	assert(kernel.advance_prefix(aliased, positions, {}, 0, 2, 0.25) == 2)
	assert(is_same(aliased[0], aliased[1]) and shared.age == 0.5 and shared.think == 0.0)
	var readonly := _row()
	readonly.make_read_only()
	assert(kernel.advance_prefix([readonly], [Vector2i(-1, -1)], {}, 0, 1, 0.25) == 0)
	assert(readonly.age == 0.0)
	print("ARMY_IDLE_NATIVE_BOUNDARY_PASS cases=", checked, " alias/read-only/rejection/interleaving")
	for condition in range(6):
		var rows: Array[Dictionary] = [_row(), _row(), _row(), _row()]
		var moving: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(-1, -1)]
		rows[0].fatigue = negative_zero
		rows[0].fatigue_rest = negative_zero
		rows[1].fatigue = 0
		rows[1].fatigue_rest = 30
		match condition:
			0: rows[2].fatigue = 0.00000000001
			1: moving[2] = Vector2i.ZERO
			2: rows[2].make_read_only()
			3: rows[2].erase("fatigue_rest")
			4: rows[2].fatigue = null
			5: rows[2].fatigue = NAN
		var before := var_to_bytes(rows[2])
		assert(kernel.fatigue_prefix(rows, moving, 0, 4) == 2)
		assert(var_to_bytes(rows[2]) == before and rows[3].fatigue_rest == 0.0)
		assert(var_to_bytes(rows[0].fatigue) == var_to_bytes(negative_zero))
		assert(var_to_bytes(rows[0].fatigue_rest) == var_to_bytes(0.0))
		assert(typeof(rows[1].fatigue) == TYPE_FLOAT and typeof(rows[1].fatigue_rest) == TYPE_FLOAT)
	print("ARMY_NATIVE_FATIGUE_BOUNDARY_PASS signed-zero/int/positive/moving/readonly/missing/null/NaN")
	var named := {}
	var plain := _row()
	for key: String in plain: named[StringName(key)] = plain[key]
	var named_rows: Array[Dictionary] = [named]
	var named_reference: Array[Dictionary] = [named.duplicate(true)]
	var stationary: Array[Vector2i] = [Vector2i(-1, -1)]
	assert(_reference(named_reference, stationary, {}, 0, 1, 0.25) == 1)
	assert(kernel.advance_prefix(named_rows, stationary, {}, 0, 1, 0.25) == 1)
	assert(var_to_bytes(named_rows) == var_to_bytes(named_reference), "Original StringName keys or inserted String timers changed")
	var typed: Dictionary[String, Variant] = {}
	for key: String in plain: typed[key] = plain[key]
	var typed_before := var_to_bytes(typed)
	assert(typed.is_typed())
	assert(kernel.advance_prefix([typed], stationary, {}, 0, 1, 0.25) == 0)
	assert(kernel.fatigue_prefix([typed], stationary, 0, 1) == 0)
	assert(var_to_bytes(typed) == typed_before)
	for field: String in ["age", "think"]:
		for value: float in [INF, -INF, NAN]:
			var row := _row()
			row[field] = value
			var before := var_to_bytes(row)
			assert(kernel.advance_prefix([row], stationary, {}, 0, 1, 0.25) == 0)
			assert(var_to_bytes(row) == before)
	for delta: float in [0.0, -1.0, INF, NAN, 1.7976931348623157e308]:
		var row := _row()
		row.age = 1.7976931348623157e308
		var before := var_to_bytes(row)
		assert(kernel.advance_prefix([row], stationary, {}, 0, 1, delta) == 0)
		assert(var_to_bytes(row) == before)
	var bounds_row := _row()
	var bounds_before := var_to_bytes(bounds_row)
	assert(kernel.advance_prefix([bounds_row], stationary, {}, -1, 1, 0.25) == -1)
	assert(kernel.advance_prefix([bounds_row], stationary, {}, 0, 2, 0.25) == 0)
	assert(kernel.advance_prefix([bounds_row], [], {}, 0, 1, 0.25) == 0)
	assert(kernel.fatigue_prefix([bounds_row], stationary, 0, 2) == 0)
	assert(var_to_bytes(bounds_row) == bounds_before)
	var slot_cases := 0
	for field: String in ["age", "think", "stun", "grace", "exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "ranged_cooldown"]:
		for value: Variant in [0, negative_zero, 0.0]:
			var row := _row()
			for timer: String in ["exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "ranged_cooldown"]: row[timer] = 0.0
			row[field] = value
			var actual_rows: Array[Dictionary] = [row, row] # Reacquire after the preceding aliased row's writes.
			var expected_row := row.duplicate(true)
			var expected_rows: Array[Dictionary] = [expected_row, expected_row]
			assert(_reference(expected_rows, positions, {}, 0, 2, 0.25) == 2)
			assert(kernel.advance_prefix(actual_rows, positions, {}, 0, 2, 0.25) == 2)
			assert(is_same(actual_rows[0], actual_rows[1]) and var_to_bytes(actual_rows) == var_to_bytes(expected_rows), "Validated numeric storage changed " + field)
			slot_cases += 1
		var row := _row()
		row[field] = null
		var before := var_to_bytes(row)
		assert(kernel.advance_prefix([row], stationary, {}, 0, 1, 0.25) == 0 and var_to_bytes(row) == before)
	print("ARMY_VALIDATED_NUMERIC_STORAGE_PASS cases=", slot_cases, " float/int/signed-zero/alias and null rejection; sparse insertion covered above")
	var timer_keys: Array[String] = ["exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "ranged_cooldown"]
	for presence in range(16):
		var row := _row()
		for bit in range(4):
			if presence & (1 << bit): row[timer_keys[bit]] = negative_zero if bit % 2 else 0
		var rows: Array[Dictionary] = [row, row]
		var expected_row := row.duplicate(true)
		var expected_rows: Array[Dictionary] = [expected_row, expected_row]
		assert(_reference(expected_rows, positions, {}, 0, 2, 0.25) == 2)
		assert(kernel.advance_prefix(rows, positions, {}, 0, 2, 0.25) == 2)
		assert(is_same(rows[0], rows[1]) and var_to_bytes(rows) == var_to_bytes(expected_rows), "Timer slot presence mask " + str(presence))
	for required: String in ["age", "think", "stun", "grace"]:
		var row := _row()
		row.erase(required)
		var before := var_to_bytes(row)
		assert(kernel.advance_prefix([row], stationary, {}, 0, 1, 0.25) == 0 and var_to_bytes(row) == before)
	print("ARMY_ROW_LOCAL_SLOTS_PASS 16 optional timer combinations with int/signed-zero/alias/insertion; four missing required fields reject untouched")
	print("ARMY_NATIVE_DEFENSIVE_BOUNDARY_PASS typed/StringName/nonfinite/overflow/bounds untouched")
	var read_cases := 0
	for read_key: String in ["pose", "hp", "ko", "exchange_visual", "exchange_pose_duration"]:
		for invalid: Variant in [null, "invalid", Vector2i.ZERO, NAN, INF]:
			var row := _row()
			row[read_key] = invalid
			for recovering: bool in [false, true]:
				var before := var_to_bytes(row)
				var consumed: int = kernel.advance_recovery_prefix([row], stationary, {}, 0, 1, 0.25, 10.0) if recovering else kernel.advance_prefix([row], stationary, {}, 0, 1, 0.25)
				assert(consumed == 0 and var_to_bytes(row) == before, "Qualification read rejection changed " + read_key)
				read_cases += 1
		var missing := _row()
		missing.erase(read_key)
		var missing_before := var_to_bytes(missing)
		var optional := read_key.begins_with("exchange_")
		assert(kernel.advance_prefix([missing], stationary, {}, 0, 1, 0.25) == (1 if optional else 0))
		if not optional: assert(var_to_bytes(missing) == missing_before)
		read_cases += 1
	print("ARMY_QUALIFICATION_READ_BOUNDARY_PASS cases=", read_cases, " missing versus present null/invalid untouched; recovery and idle")
	if "--native-profile" in OS.get_cmdline_user_args():
		for recovering: bool in [false, true]:
			var probe_rows: Array[Dictionary] = []
			var probe_moving: Array[Vector2i] = []
			for ordinal in range(5000):
				var row := _row()
				row.exchange_visual = {}
				row.exchange_pose_duration = 0.0
				for timer: String in timer_keys: row[timer] = 100.0 if recovering else 0.0
				row.stun = 1000.0 if recovering else 0.0
				probe_rows.append(row)
				probe_moving.append(Vector2i(-1, -1))
			var samples: Array[int] = []
			for batch in range(6):
				var started := Time.get_ticks_usec()
				for step in range(200):
					assert(kernel.advance_recovery_prefix(probe_rows, probe_moving, {}, 0, 5000, 1.0 / 30.0, 10.0) == 5000)
				samples.append(Time.get_ticks_usec() - started)
			print("ARMY_NATIVE_QUALIFICATION_PROFILE ", JSON.stringify({"recovering": recovering, "people": 5000, "steps_per_batch": 200, "batch_usec": samples, "state_sha256": var_to_bytes(probe_rows).hex_encode().sha256_text()}))
	var original: Array[Dictionary] = []
	var destinations: Array[Vector2i] = []
	for i in range(5000): original.append(_row()); destinations.append(Vector2i(-1, -1))
	var results: Array[Dictionary] = []
	for native: bool in [false, true, true, false]:
		var rows: Array[Dictionary] = original.duplicate(true)
		var started := Time.get_ticks_usec()
		for step in range(30):
			var consumed := int(kernel.advance_prefix(rows, destinations, {}, 0, 5000, 1.0 / 30.0)) if native else _reference(rows, destinations, {}, 0, 5000, 1.0 / 30.0)
			assert(consumed == 5000)
		results.append({"native": native, "milliseconds": (Time.get_ticks_usec() - started) / 1000.0, "state_sha256": var_to_bytes(rows).hex_encode().sha256_text()})
	for row: Dictionary in results: assert(row.state_sha256 == results[0].state_sha256)
	print("ARMY_IDLE_NATIVE_CPU_ABBA ", JSON.stringify(results))
	kernel = null
	quit(0)
