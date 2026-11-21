extends SceneTree
## UNRUN native ABI/owner packet candidate, not complete Lab Native admission.
var checks := 0
var finished := false
var objects: Array[Object] = []

func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value: push_error("FIRE_NATIVE_API_FAIL: " + label)
	return value

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func() -> void: _finish(false))
	_run.call_deferred()

func _finish(ok: bool) -> void:
	if finished: return
	finished = true
	objects.clear() # ArmyCrowd uses the original RefCounted lifecycle.
	print("SITE_FIRE_NATIVE_BRIDGE_API_", "PASS" if ok else "FAIL", " checks=", checks, " P6_NOT_CLOSED")
	quit(0 if ok else 1)

func _case() -> bool:
	if not _check(ClassDB.class_exists(&"ArmyCrowd") and ClassDB.class_has_method(&"ArmyCrowd", &"fire_host_protocol"), "candidate native ABI is actually installed"): return false
	var crowd: Object = ClassDB.instantiate(&"ArmyCrowd")
	objects.append(crowd)
	if not _check(crowd.setup(1, 75) and crowd.fire_host_protocol() == 1, "explicit protocol handshake"): return false
	var data := TerrainData.new()
	data.allocate(Vector2i(30, 30))
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	if not _check(crowd.set_terrain(30, 30, data.height_levels, data.flags, data.ramp_edges, data.static_blocked, PackedByteArray()), "original terrain owner input"): return false
	var a: int = crowd.add_formation(0, 10.5, 10.5, 0.0, 1, 1.0, 1, 0.0)
	var b: int = crowd.add_formation(1, 16.5, 10.5, 0.0, 1, 1.0, 0, 0.0)
	var bow := 7 | (3 << 8) | (2 << 16)
	if not _check(crowd.add_soldiers(a, PackedInt64Array([101]), PackedInt32Array([bow]), PackedByteArray([1]), PackedInt32Array([3])) == 0
		and crowd.add_soldiers(b, PackedInt64Array([202]), PackedInt32Array([bow]), PackedByteArray([1]), PackedInt32Array([0])) == 1, "original person IDs and ammo scalar"): return false
	crowd.set_ai(false)
	if not _check(crowd.finalize(), "original native finalize"): return false
	var before: PackedByteArray = crowd.save_state()
	var rejected: PackedFloat64Array = crowd.commit_host_ranged(0, 3, 1, 1, 16, 10, false)
	if not _check(rejected.is_empty() and crowd.save_state() == before, "guarded API rejects before owner transfer without mutation"): return false
	if not _check(crowd.set_host_ranged_delegate(true), "one explicit host ranged owner"): return false
	before = crowd.save_state()
	rejected = crowd.commit_host_ranged(0, 2, 1, 1, 16, 10, true)
	if not _check(rejected.is_empty() and crowd.save_state() == before, "bad expected ammo rejects before auto-power/debit"): return false
	var receipt: PackedFloat64Array = crowd.commit_host_ranged(0, 3, 1, 7, 16, 10, false)
	if not _check(receipt.size() == 5 and receipt[4] == 2.0 and not crowd.has_projectiles(), "one paid original receipt; no second native flight"): return false
	before = crowd.save_state()
	rejected = crowd.commit_host_ranged(0, 2, 1, 7, 16, 10, false)
	if not _check(rejected.is_empty() and crowd.save_state() == before, "duplicate release watermark rejected atomically"): return false
	for tick in range(4):
		if not _check(crowd.step_clock(1.0/30.0, 1.0/30.0, 30.0), "real original World action step"): return false
	var shooter: PackedFloat64Array = crowd.get_soldier_state(0)
	if not _check(shooter[8] == 2.0 and not crowd.has_projectiles(), "native step never manufactures a second paid arrow"): return false
	var victim_before: PackedFloat64Array = crowd.get_soldier_state(1)
	if not _check(crowd.apply_fire_exposure_damage(1, 2.5), "original native thermal HP packet"): return false
	var victim_after: PackedFloat64Array = crowd.get_soldier_state(1)
	if not _check(absf(victim_before[0] - victim_after[0] - 2.5) < 0.000001, "exact original HP loss"): return false
	if not _check(crowd.apply_host_projectile_contact(1, 3.0, 0.0, 0.2), "original physical contact owner"): return false
	var damaged: PackedFloat64Array = crowd.get_soldier_state(1)
	if not _check(absf(victim_after[0] - damaged[0] - 3.0) < 0.000001, "exact physical contact loss"): return false
	var original_hash: int = crowd.state_hash()
	if not _check(crowd.set_fire_visual_rows(PackedInt32Array([0,1]), PackedByteArray([1,2]))
		and crowd.state_hash() == original_hash, "derived atlas flags do not affect authority hash"): return false
	var saved: PackedByteArray = crowd.save_state()
	var restored: Object = ClassDB.instantiate(&"ArmyCrowd")
	objects.append(restored)
	if not _check(restored.setup(1, 75) and restored.load_state(saved) and restored.state_hash() == original_hash, "original atomic native save/load includes selected owner and receipt watermark"): return false
	return true

func _run() -> void:
	_finish(_case())
