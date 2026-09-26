extends SceneTree

const EXTENSION := "res://native/army_idle/army_idle.gdextension"

func _initialize() -> void:
	_run.call_deferred()

func _row() -> Dictionary:
	return {"hp": 100.0, "ko": 0.0, "age": -0.0, "think": 0.5, "stun": 0.0,
		"grace": 0.0, "pose": "idle", "attack": false, "member": true,
		"captive": false, "departed": false, "present": true}

func _expect_reason(actual: PackedInt32Array, expected: int, label: String) -> bool:
	if actual == PackedInt32Array([0, 3, expected]): return true
	push_error("Owner reason " + label + " differs: " + str(actual))
	quit(1)
	return false

func _run() -> void:
	if not GDExtensionManager.is_extension_loaded(EXTENSION):
		assert(GDExtensionManager.load_extension(EXTENSION) == GDExtensionManager.LOAD_STATUS_OK)
	assert(ClassDB.class_exists(&"ArmyCombatHot"))
	var first: RefCounted = ClassDB.instantiate(&"ArmyCombatHot")
	var second: RefCounted = ClassDB.instantiate(&"ArmyCombatHot")
	var source := [_row(), _row()]
	assert(first.load_rows(source))
	assert(second.load_rows(source))
	assert(first.row_count() == 2)
	assert(first.has_field(0, "hp"))
	assert(not first.has_field(0, "exchange_cooldown"))
	assert(first.get_field(0, "exchange_cooldown", 3.0) == 3.0)
	assert(first.set_field(0, "hp", 71.5))
	assert(first.set_field(0, "present", false))
	assert(first.set_field(1, "exchange_cooldown", 0.25))
	assert(first.erase_field(1, "exchange_cooldown"))
	assert(not first.has_field(1, "exchange_cooldown"))
	assert(not first.erase_field(0, "hp"))
	assert(not first.set_field(0, "hp", "bad"))
	assert(first.column("hp") == PackedFloat64Array([71.5, 100.0]))
	assert(first.column("present") == PackedFloat64Array([0.0, 1.0]))
	assert(first.column("member") == PackedFloat64Array([1.0, 1.0]))
	assert(float(second.get_field(0, "hp", 0.0)) == 100.0)
	assert(float(source[0].hp) == 100.0)
	var captured: Array = first.capture_rows()
	assert(captured.size() == 2 and float(captured[0].hp) == 71.5)
	assert(not captured[1].has("exchange_cooldown"))
	var single: Dictionary = first.capture_row(0)
	assert(float(single.hp) == 71.5 and not single.has("exchange_cooldown"))
	single.hp = 12.5
	assert(first.absorb_row(0, single))
	assert(float(first.get_field(0, "hp", 0.0)) == 12.5)
	single.pose = 7
	assert(not first.absorb_row(0, single))
	assert(float(first.get_field(0, "hp", 0.0)) == 12.5)
	var invalid := [_row()]
	invalid[0].pose = 7
	assert(not first.load_rows(invalid))
	assert(first.row_count() == 2 and float(first.get_field(0, "hp", 0.0)) == 12.5)
	assert(first.load_rows([_row(), _row()]))
	var moving := [Vector2i(-1, -1), Vector2i(-1, -1)]
	var progress := PackedFloat64Array([0.0, 0.0])
	var durations := PackedFloat64Array([0.38, 0.38])
	var delta := 1.0 / 30.0
	var packed_result: PackedInt32Array = first.advance_numeric(moving, progress, durations, {}, 0, 2, delta, delta, 15.0)
	if packed_result != PackedInt32Array([2, 0]):
		push_error("packed advance ABI: " + str(packed_result))
		quit(1)
		return
	assert(float(first.get_field(0, "age", 0.0)) == delta and float(first.get_field(1, "age", 0.0)) == delta)
	assert(first.load_rows([_row(), _row()]))
	moving[0] = Vector2i.ZERO
	assert(first.advance_numeric(moving, progress, durations, {}, 0, 2, delta, delta, 15.0) == PackedInt32Array([2, 0]))
	assert(progress[0] > 0.0)
	moving[0] = Vector2i(-1, -1)
	progress[0] = 0.0
	assert(first.load_rows([_row(), _row()]))
	moving[1] = Vector2i.ZERO
	progress[1] = 0.99
	durations[1] = 0.1
	assert(first.advance_numeric(moving, progress, durations, {}, 0, 2, delta, delta, 15.0) == PackedInt32Array([1, 1]))
	assert(float(first.get_field(0, "age", 0.0)) == delta and float(first.get_field(1, "age", 0.0)) == 0.0)
	assert(progress[1] == 0.99)
	assert(first.advance_numeric(moving, progress, durations, {}, 0, 1, delta, delta, 15.0) == PackedInt32Array([1, 0]))
	assert(float(first.get_field(0, "age", 0.0)) == 2.0 * delta)
	assert(first.load_rows([_row(), _row()]))
	assert(first.set_field(1, "ko", delta * 0.5))
	assert(first.set_field(1, "pose", "unconscious"))
	moving[1] = Vector2i(-1, -1)
	assert(first.advance_numeric(moving, progress, durations, {}, 0, 2, delta, delta, 15.0) == PackedInt32Array([1, 2]))
	assert(float(first.get_field(0, "age", 0.0)) == delta and float(first.get_field(1, "age", 0.0)) == 0.0)
	var visual_row := _row()
	visual_row.exchange_visual = {"pose": "hit", "age": 0.2, "left": 0.8, "facing": Vector2i.DOWN}
	assert(first.load_rows([visual_row, _row()]))
	var visual_result: PackedInt32Array = first.advance_numeric(moving, progress, durations, {}, 0, 2, delta, delta, 15.0)
	var visual_after: Dictionary = first.get_field(0, "exchange_visual", {})
	if visual_result != PackedInt32Array([2, 0]) or visual_after.age != 0.2 + delta or visual_after.left != 0.8 - delta:
		push_error("pure visual must stay native without owner barrier: " + str([visual_result, visual_after]))
		quit(1)
		return
	visual_row.exchange_visual = {"pose": "hit", "age": 0.2, "left": delta * 0.5, "facing": Vector2i.DOWN}
	assert(first.load_rows([visual_row, _row()]))
	var expiry_result: PackedInt32Array = first.advance_numeric(moving, progress, durations, {}, 0, 2, delta, delta, 15.0)
	if expiry_result != PackedInt32Array([0, 3]) or first.get_field(0, "exchange_visual", {}) != visual_row.exchange_visual:
		push_error("visual expiry must remain an ordered owner barrier: " + str(expiry_result))
		quit(1)
		return
	if not _expect_reason(first.advance_numeric_reason(moving, progress, durations, {}, 0, 2, delta, delta, 15.0), 6, "visual expiry"): return
	var attack_row := _row()
	attack_row.attack = true
	attack_row.pose = "attack_unarmed"
	assert(first.load_rows([attack_row, _row()]))
	var attack_result: PackedInt32Array = first.advance_numeric_reason(moving, progress, durations, {}, 0, 2, delta, delta, 15.0)
	if attack_result != PackedInt32Array([2, 0, 0]) or not bool(first.get_field(0, "attack", false)):
		push_error("Attack clock should remain a native numeric step: " + str(attack_result))
		quit(1)
		return
	var think_row := _row()
	think_row.pose = "hit"
	think_row.think = 0.0
	assert(first.load_rows([think_row, _row()]))
	var think_result: PackedInt32Array = first.advance_numeric_reason(moving, progress, durations, {}, 0, 2, delta, delta, 15.0)
	if think_result != PackedInt32Array([2, 0, 0]) or float(first.get_field(0, "think", -1.0)) != 0.0:
		push_error("Non-HOLD think expiry should remain a native numeric step: " + str(think_result))
		quit(1)
		return
	if not _expect_reason(first.advance_numeric_hold_reason(moving, progress, durations, {}, 0, 2, delta, delta, 15.0), 13, "think HOLD"): return
	think_row.think = 0.5
	think_row.exchange_pose_duration = delta * 0.5
	assert(first.load_rows([think_row, _row()]))
	if not _expect_reason(first.advance_numeric_reason(moving, progress, durations, {}, 0, 2, delta, delta, 15.0), 11, "pose expiry"): return
	assert(first.load_rows([_row(), _row()]))
	if not _expect_reason(first.advance_numeric_reason(moving, progress, durations, {0: {}}, 0, 2, delta, delta, 15.0), 4, "rescue"): return
	var output := FileAccess.open("res://output/site_army_5k_hot_close_20260926/hot_store_smoke.json", FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify({"checks": {"load_and_isolation": true, "get_set_erase": true,
		"numeric_and_flag_columns": true, "capture": true, "single_row_borrow": true, "atomic_rejection": true,
		"native_no_barrier_single_call": true, "native_barrier_order": true, "packed_progress_abi": true,
		"pure_visual_no_owner_barrier": true, "visual_expiry_ordered_barrier": true,
		"owner_reason_abi": true, "attack_native_safe": true, "think_nonhold_native_safe": true,
		"hold_think_reason": true, "visual_expiry_reason": true,
		"pose_expiry_reason": true, "rescue_reason": true},
		"cpp_sha256": FileAccess.get_sha256("res://native/army_idle/army_idle.cpp"),
		"dll_sha256": FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll"),
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_hot_store_native_test.gd")}))
	output.close()
	print("ARMY_COMBAT_HOT_NATIVE_PASS")
	quit(0)
