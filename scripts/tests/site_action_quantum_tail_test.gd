extends SceneTree
const Clock = preload("res://scripts/region_lab/region_gameplay_clock.gd")
const Genesis = preload("res://scripts/tests/region_two_npc_sea_legal_named_genesis.gd")
var deadline: int = 0
var checks: int = 0
var out: String = ""
var manifest_path: String = ""

# Receipt-consumer unit fixture; only the original _advance_action_time is exercised here.
class ReceiptProbe extends TerrainLab:
	var receipts: Array[Dictionary] = []
	var requests: Array[float] = []
	func _advance_original_shared_step(elapsed: float, _target: float = -1.0, _interval: Dictionary = {}, _formula: bool = false) -> Dictionary:
		requests.append(elapsed)
		if receipts.is_empty(): return {"ok": true, "completed": false, "status": "REGION_EVENT_PENDING", "action_seconds": 0.0, "game_seconds": 0.0}
		return receipts.pop_front()

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	out = "res://.godot-temp/site_action_quantum_tail/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline: push_error("Quantum entrypoint deadline"); quit(1)
	return false

func _check(condition: bool, message: String, _details: Variant = null) -> bool:
	checks += 1
	if condition and Time.get_ticks_msec() <= deadline: return true
	push_error(message)
	quit(1)
	return false

func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var path: String = out.path_join(name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return {}
	file.store_buffer(bytes); file.close()
	return {"path": name, "sha256": FileAccess.get_sha256(path)}

func _probe() -> ReceiptProbe:
	var probe: ReceiptProbe = ReceiptProbe.new()
	probe.terrain = TerrainData.new()
	probe.terrain.site = {"paused": false}
	probe.site_controller = SiteController.new()
	probe.add_child(probe.site_controller)
	probe.exchange_enabled = true
	probe.fixed_action_steps_enabled = true
	return probe

func _receipt(consumed: float, complete: bool, pending: bool = false) -> Dictionary:
	var result: Dictionary = {"ok": true, "completed": true, "action_seconds": consumed, "game_seconds": consumed * 60.0, "completed_action_request": complete}
	if pending: result.status = "REGION_EVENT_PENDING"
	return result

func _consumer_contract() -> bool:
	var step: float = TerrainLab.EXCHANGE_ACTION_STEP
	var begin: float = step * 2.0
	var saw_negative: bool = false
	var saw_positive: bool = false
	for index: int in 2:
		var end: float = begin + step
		var consumed: float = end - begin
		saw_negative = saw_negative or consumed > step
		saw_positive = saw_positive or consumed < step
		var probe: ReceiptProbe = _probe()
		probe.receipts.append(_receipt(consumed, true))
		probe._advance_action_time(step)
		var valid: bool = probe.requests.size() == 1 and probe._action_step_remaining == 0.0 and probe._action_time_remainder == step - consumed
		probe.free()
		if not _check(valid, "Original 088 consumer closes a proved full request and charges actual backlog for both rounding signs"): return false
		begin = end
	if not _check(saw_negative and saw_positive, "Fixtures reproduce both subtraction-tail signs"): return false
	var near_bits: PackedByteArray = PackedFloat64Array([step]).to_byte_array()
	near_bits.encode_u64(0, near_bits.decode_u64(0) - 1)
	var near: float = near_bits.decode_double(0)
	var saw_open_tail: bool = false
	var saw_sub_epsilon_tail: bool = false
	for consumed: float in [step * 0.25, near]:
		var probe: ReceiptProbe = _probe()
		probe.receipts.append(_receipt(consumed, false, true))
		probe._advance_action_time(step)
		var tail: float = step - consumed
		# 6fed84f: an open quantum keeps a real tail exactly; a residue <= ACTION_TIME_EPSILON closes the quantum
		# (requesting it makes no progress), while the exact unpaid tail stays in the backlog remainder.
		var open_tail: float = tail if tail > TerrainLab.ACTION_TIME_EPSILON else 0.0
		saw_open_tail = saw_open_tail or open_tail > 0.0
		saw_sub_epsilon_tail = saw_sub_epsilon_tail or (tail > 0.0 and open_tail == 0.0)
		var valid: bool = probe.requests.size() == 1 and tail > 0.0 and probe._action_step_remaining == open_tail and probe._action_time_remainder == tail
		valid = valid and TerrainLab._region_action_clock_valid({"_action_time_remainder": tail, "_action_step_remaining": tail})
		valid = valid and TerrainLab._region_action_clock_valid({"_action_time_remainder": probe._action_time_remainder, "_action_step_remaining": probe._action_step_remaining})
		probe.free()
		if not _check(valid, "Real prefix and positive sub-epsilon tail survive the original consumer exactly"): return false
	if not _check(saw_open_tail and saw_sub_epsilon_tail, "Fixtures reproduce both an open real tail and a positive sub-epsilon backlog tail"): return false
	var zero: ReceiptProbe = _probe()
	zero.receipts.append(_receipt(0.0, true, true))
	zero._advance_action_time(step)
	var zero_kept: bool = zero._action_step_remaining == step and zero._action_time_remainder == step
	zero.free()
	if not _check(zero_kept, "Zero consumption cannot close a quantum even with a completion flag"): return false
	var tiny: float = 1.0e-18
	if not _check(TerrainLab._region_action_clock_valid({"_action_time_remainder": 0.0, "_action_step_remaining": 0.0})
		and TerrainLab._region_action_clock_valid({"_action_time_remainder": tiny, "_action_step_remaining": tiny})
		and not TerrainLab._region_action_clock_valid({"_action_time_remainder": step, "_action_step_remaining": -tiny}),
		"Legitimate zero/positive owner tails remain valid and negative owner tails stay rejected"): return false
	var probe: ReceiptProbe = _probe()
	var cursor: float = 0.0
	for index: int in 300:
		var end: float = cursor + step
		probe.receipts.append(_receipt(end - cursor, true))
		cursor = end
	probe._advance_action_time(10.0)
	var conserved: bool = probe.requests.size() == 300 and probe._action_step_remaining == 0.0 and absf(probe._action_time_remainder + cursor - 10.0) < 1.0e-12
	probe.free()
	return _check(conserved, "300 original consumer calls retain actual endpoint charges without phantom tiny requests")

func _clips() -> bool:
	var step: float = TerrainLab.EXCHANGE_ACTION_STEP
	for scale: float in [0.5, 1.0, 2.0, 4.0]:
		for tactical: float in [0.0, step * 0.5, step]:
			var uncut: Dictionary = Clock.clip_interval(Clock.empty_registry(), 104.0, 0.0, step, scale, tactical)
			if not _check(uncut.ok and not uncut.get("pending", false) and float(uncut.action_seconds) == step, "Uncut ACTION stays exact at every original public scale"): return false
	var bits: PackedByteArray = PackedFloat64Array([104.0 + step * 4.0]).to_byte_array()
	bits.encode_u64(0, bits.decode_u64(0) - 1)
	var at: float = bits.decode_double(0)
	var registry: Dictionary = Clock.empty_registry()
	if not _check(Clock.queue_event(registry, "tail_event", "work", at, "tail_fixture").ok, "Original event producer admits the real earlier endpoint"): return false
	var clipped: Dictionary = Clock.clip_interval(registry, 104.0, 0.0, step, 4.0, step)
	return _check(clipped.ok and float(clipped.action_seconds) < step and float(clipped.game_end) == at
		and step - float(clipped.action_seconds) > 0.0 and step - float(clipped.action_seconds) < TerrainLab.ACTION_TIME_EPSILON,
		"A genuine original event retains its positive sub-epsilon unpaid prefix")

func _actual_region() -> bool:
	if not Genesis.write(self): return false
	var packed: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "Original PackedScene exists"): return false
	var lab: TerrainLab = packed.instantiate() as TerrainLab
	lab.restore_only = true
	lab.pause_when_unfocused = false
	root.add_child(lab)
	var archive: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	SiteEnvironment.initialize(archive, "quantum-entrypoint-archive")
	lab.bind_terrain(archive)
	lab.restore_only = false
	lab.site_controller.save_root = out.path_join("archive")
	var opened: Dictionary = lab.site_controller.open_fixed_world(manifest_path, "quantum_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()], "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Original Controller births and binds the fixed World", opened): lab.free(); return false
	lab.set_process(false)
	lab.character.set_process(false)
	# The new-game player is a one-person grid team with combat_enabled. Grid simulation is retired, and this
	# test only exercises the Site action clock, so hold that team out of combat (it is not under test here).
	for team: TerrainArmy in lab.combat_armies: team.combat_enabled = false
	lab.movement_input_enabled = false
	lab.exchange_enabled = true
	lab.fixed_action_steps_enabled = true
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var settled: Dictionary = slot.consume_due_region_events()
	if not _check(settled.ok and settled.get("complete", false), "Original zero endpoints settle before the fixed quantum"): lab.free(); return false
	var up: bool = false
	var down: bool = false
	var step: float = TerrainLab.EXCHANGE_ACTION_STEP
	for index: int in 8:
		var before: float = float(slot.control.fire_clock.action_seconds)
		var world: float = float(slot.control.logical_game_seconds)
		var sequence: int = int(slot.control.fire_clock.sequence)
		lab._advance_action_time(step)
		var consumed: float = float(slot.control.fire_clock.action_seconds) - before
		up = up or consumed > step
		down = down or consumed < step
		if not _check(lab.site_controller._original_step_fault.is_empty() and lab._action_step_remaining == 0.0
			and consumed > 0.0 and float(slot.control.logical_game_seconds) > world and int(slot.control.fire_clock.sequence) == sequence + 1,
			"Real bound Scene/Slot publisher closes one 088 full quantum exactly once"): lab.free(); return false
	lab.free()
	return _check(up and down, "Real original Region endpoint path exercised both rounding signs")

func _run() -> void:
	if not _consumer_contract() or not _clips() or not _actual_region(): return
	print("SITE_ACTION_QUANTUM_TAIL_PASS: checks=", checks, "; original088entrypoint; realSceneSlot; receipt-fixture-contract")
	quit(0)
