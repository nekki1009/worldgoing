extends SceneTree
## Read-only query parity plus original-controller A/B, including all preparation.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")
const COUNT := 5000

class LabFixture extends Node2D:
	var terrain := TerrainData.new()
	var crowd_site: Node
	func _region_deferring_endpoint() -> bool: return false # No Region point is pending in this fixture.

class KernelSpy extends RefCounted:
	var native: RefCounted
	var calls := 0
	func sustain_life_sample(state: Dictionary, members: Dictionary, life: PackedFloat64Array, indices: Dictionary) -> Array:
		calls += 1
		return native.sustain_life_sample(state, members, life, indices)

class CustomController extends SiteController:
	pass

var failed := false
var checks: Array[Dictionary] = []
var kernel: RefCounted
var output := ""
var costs := {}

func _check(ok: bool, label: String) -> bool:
	checks.append({"ok": ok, "label": label})
	print("SUSTAIN_LIFE_SAMPLE ", "OK " if ok else "FAIL ", label)
	if not ok: failed = true
	return ok

func _initialize() -> void:
	_run.call_deferred()

func _fixture(count: int) -> Dictionary:
	var lab := LabFixture.new()
	var site := CrowdSite.new()
	var controller := SiteController.new()
	root.add_child(lab)
	lab.add_child(site)
	lab.add_child(controller)
	lab.crowd_site = site
	controller.lab = lab
	controller.captivity_supply.init(controller)
	site.lab = lab
	lab.terrain.allocate(Vector2i(128, 128))
	lab.terrain.flags.fill(TerrainData.Flag.WALKABLE)
	lab.terrain.site = {"paused": false, "team_supply": {}, "person_supply": {}}
	site.crowd = ClassDB.instantiate("ArmyCrowd")
	assert(site.crowd.setup(1, 9073))
	assert(site.crowd.set_terrain(128, 128, lab.terrain.height_levels, lab.terrain.flags, lab.terrain.ramp_edges, lab.terrain.static_blocked, PackedByteArray()))
	var formation: int = site.crowd.add_formation(0, 64.5, 64.5, 0.0, ceili(sqrt(float(count))), 1.0, 0, 50.0)
	var ids := PackedInt64Array()
	var equipment := PackedInt32Array()
	var roles := PackedByteArray()
	var ammo := PackedInt32Array()
	var rows := {}
	var members := {}
	for index in range(count):
		var identity := index + 1
		ids.append(identity)
		equipment.append(1 | (3 << 8) | (2 << 16))
		roles.append(0)
		ammo.append(0)
		var body := {"person_id": identity, "hp": 100.0, "ko": 0.0, "marker": "original"}
		rows[index] = body
		members[identity] = body
		site._records[identity] = body
		site._index_by_id[identity] = index
	assert(int(site.crowd.add_soldiers(formation, ids, equipment, roles, ammo)) == 0)
	assert(site.crowd.finalize())
	var owner := CrowdPersonOwner.new()
	owner.setup(site, formation, 1, 0, rows)
	site.owners = [owner]
	for identity: int in members: site._owner_by_id[identity] = owner
	site.active = true
	var state := Sustain.create()
	assert(Sustain.add_members(state, members, Array(ids).slice(0, count - 1)).ok)
	var entry := {"sustain": state, "inventory": {"grain": 10000}, "revision": 0, "life_checkpoint": {"extra": 19, "1": 7}}
	lab.terrain.site.team_supply["1"] = entry
	return {"lab": lab, "site": site, "controller": controller, "owner": owner, "members": members, "entry": entry}

func _close(fixture: Dictionary) -> void:
	fixture.controller.captivity_supply.controller = null
	fixture.owner.crowd_site = null
	fixture.site.lab = null
	fixture.lab.free()

func _reader(life: PackedFloat64Array, indices: Dictionary) -> Callable:
	return func(identity: int, field: StringName) -> Variant:
		var index := int(indices[identity])
		return life[index * 3] if field == &"hp" else life[index * 3 + 1]

func _query_cases(fixture: Dictionary) -> void:
	var native: RefCounted = fixture.site.crowd
	for index in range(3):
		var values: PackedFloat64Array = native.get_soldier_state(index)
		values[0] = [5.25, 0.0, 10.0][index]
		values[3] = 7.25 if index == 2 else 0.0
		assert(native.set_soldier_state(index, values, native.soldier_refs(index)))
	var life: PackedFloat64Array = native.get_life_states()
	var indices: Dictionary = fixture.site._index_by_id
	var members: Dictionary = fixture.members
	var state: Dictionary = fixture.entry.sustain
	var reader := _reader(life, indices)
	var cases := ["valid", "duplicate", "missing_member", "negative_hp", "nan_hp", "bad_version", "missing_index", "bad_index", "body_id_mismatch", "typed_members", "readonly", "all_dead", "empty_cohorts", "fractional_id"]
	for kind: String in cases:
		var current := state.duplicate(true)
		var people := members.duplicate(true)
		var sampled_life := life.duplicate()
		var mapped := indices.duplicate()
		match kind:
			"duplicate": current.cohorts[0].ids.append(1)
			"missing_member": people.erase(1)
			"negative_hp": sampled_life[0] = -1.0
			"nan_hp": sampled_life[0] = NAN
			"bad_version": current.version = 2
			"missing_index": mapped.erase(1)
			"bad_index": mapped[1] = -1
			"body_id_mismatch": people[1].person_id = 2
			"typed_members":
				var typed: Dictionary[int, Dictionary] = {}
				typed.assign(people)
				people = typed
			"readonly":
				current.make_read_only()
				people.make_read_only()
				mapped.make_read_only()
			"all_dead":
				for index in range(sampled_life.size() / 3): sampled_life[index * 3] = 0.0
			"empty_cohorts": current.cohorts = []
			"fractional_id": current.cohorts[0].ids = [1.5]
		var before := var_to_bytes([current, people, mapped, sampled_life])
		var native_before: PackedByteArray = native.save_state()
		var packet: Array = kernel.sustain_life_sample(current, people, sampled_life, mapped)
		var unsupported := kind in ["missing_index", "bad_index", "body_id_mismatch", "typed_members"]
		if unsupported:
			_check(packet.is_empty(), kind + " falls back without exposing partial output")
		else:
			var sample := {"counts": [], "minimums": [], "living": 0}
			var valid := Sustain._validate_sample(current, people, _reader(sampled_life, mapped), {}, sample)
			_check((packet.size() == 4) == valid and (valid or packet == [false]), kind + " preserves complete validation")
			if valid:
				var checkpoints := {}
				for identity: int in people: checkpoints[str(identity)] = fixture.controller._life(people[identity], _reader(sampled_life, mapped))
				_check(var_to_bytes(packet) == var_to_bytes([sample.counts, sample.minimums, sample.living, checkpoints]), kind + " exact counts, minimums and ALL-member checkpoints")
		_check(var_to_bytes([current, people, mapped, sampled_life]) == before and native.save_state() == native_before, kind + " keeps original dictionaries, packed input and native bytes unchanged")
	var context := {"life": life, "indices": indices}
	var sample := {"counts": [], "minimums": [], "living": 0}
	_check(Sustain._advance_sample(state, members, reader, {}, sample, context) and context.has("checkpoints"), "real native query packet is consumed")
	var pending := {1: 0.0}
	var expected := {"counts": [], "minimums": [], "living": 0}
	assert(Sustain._validate_sample(state, members, reader, pending, expected))
	sample = {"counts": [], "minimums": [], "living": 0}
	_check(Sustain._advance_sample(state, members, reader, pending, sample, context) and sample == expected and not context.has("checkpoints"), "pending HP invalidates projection and preserves original reader")
	var custom_reads: Array = []
	var invalid_reader := func(identity: int, field: StringName) -> float:
		custom_reads.append([identity, field])
		return -1.0
	var result := Sustain.advance_to(state.duplicate(true), members, {}, 1.0, {"hot_read": invalid_reader, "native_life": {"life": life, "indices": indices}})
	_check(not result.ok and custom_reads == [[1, &"hp"]], "public advance ignores forged native context and preserves custom-reader early exit")
	result = Sustain.advance_to(state.duplicate(true), members, {}, 1.0, {"hot_read": reader, "native_life": {"foo": 1}})
	_check(result.ok, "unrelated extra context remains ignored by public advance")
	for hunger: float in [0.0, 47.9, 49.0]:
		var outcomes: Array = []
		for use_native: bool in [false, true]:
			var current := state.duplicate(true)
			current.cohorts[0].hunger = hunger
			var stock := {"grain": 1}
			var changes := {}
			var shared := {"safe": false, "stopped": false, "hot_read": reader, "pending_hp": changes}
			var result_state: Dictionary = Sustain._advance_with_life_sample(current, members, stock, 600.0, shared, {"life": life, "indices": indices}) if use_native else Sustain.advance_to(current, members, stock, 600.0, shared)
			outcomes.append(var_to_bytes([result_state, current, stock, changes]))
		_check(outcomes[0] == outcomes[1], "advance transition/damage/meal parity at hunger %.1f" % hunger)

func _noop_events(_events: PackedInt64Array) -> void:
	pass

func _controller_cases(fixture: Dictionary) -> void:
	var spy := KernelSpy.new()
	spy.native = kernel
	var original: Dictionary = fixture.entry.duplicate(true)
	var native_before: PackedByteArray = fixture.site.crowd.save_state()
	var outputs: Array = []
	for mode: String in ["native", "old_dll", "observer", "subclass", "typed_checkpoint"]:
		var entry := original.duplicate(true)
		if mode == "typed_checkpoint":
			var typed: Dictionary[String, int] = {}
			typed.assign(entry.life_checkpoint)
			entry.life_checkpoint = typed
		fixture.lab.terrain.site.team_supply["1"] = entry
		assert(fixture.site.crowd.load_state(native_before))
		var retained: Dictionary = entry.life_checkpoint
		spy.calls = 0
		TerrainArmy._idle_kernel = RefCounted.new() if mode == "old_dll" else spy
		if mode == "observer": fixture.site.events_received.connect(_noop_events)
		var controller: SiteController = fixture.controller
		if mode == "subclass":
			controller = CustomController.new()
			fixture.lab.add_child(controller)
			controller.lab = fixture.lab
			controller.captivity_supply.init(controller)
		controller.advance_crowd_sustain(1.0)
		if mode == "observer": fixture.site.events_received.disconnect(_noop_events)
		if mode == "subclass":
			controller.captivity_supply.controller = null
			controller.free()
		_check((spy.calls == 1) if mode == "native" else spy.calls == 0, mode + " selects the intended original-controller route")
		_check(is_same(retained, entry.life_checkpoint) and entry.life_checkpoint.extra == 19 and entry.life_checkpoint.keys()[0] == "extra", mode + " preserves checkpoint identity, old keys and insertion order")
		var normalized: Dictionary = entry.duplicate(true)
		normalized.life_checkpoint = {}
		normalized.life_checkpoint.merge(entry.life_checkpoint)
		outputs.append(var_to_bytes([normalized, fixture.site.crowd.save_state()]))
		_check(outputs.back() == outputs[0], mode + " preserves all supply and native bytes")
	TerrainArmy._idle_kernel = kernel

func _median(values: Array[float]) -> float:
	var ordered := values.duplicate()
	ordered.sort()
	var middle := ordered.size() >> 1
	return (ordered[middle - 1] + ordered[middle]) * 0.5

func _benchmark() -> void:
	var fixture := _fixture(COUNT)
	var reference: Array[float] = []
	var candidate: Array[float] = []
	var original: Dictionary = fixture.entry.duplicate(true)
	var before := var_to_bytes(fixture.members)
	var native_before: PackedByteArray = fixture.site.crowd.save_state()
	var old_dll := RefCounted.new()
	var packet: Array = kernel.sustain_life_sample(original.sustain, fixture.members, fixture.site.crowd.get_life_states(), fixture.site._index_by_id)
	_check(packet.size() == 4 and packet[3].size() == COUNT, "5000-person cost fixture hits real native query and includes every checkpoint")
	for iteration in range(16):
		var pair: Array = []
		for mode: bool in [iteration % 2 == 0, iteration % 2 != 0]:
			fixture.lab.terrain.site.team_supply["1"] = original.duplicate(true)
			assert(fixture.site.crowd.load_state(native_before))
			TerrainArmy._idle_kernel = kernel if mode else old_dll
			var start := Time.get_ticks_usec()
			fixture.controller.advance_crowd_sustain(1.0 / 30.0)
			var elapsed := float(Time.get_ticks_usec() - start) / 1000.0
			if iteration >= 4:
				if mode: candidate.append(elapsed)
				else: reference.append(elapsed)
			pair.append(var_to_bytes([fixture.lab.terrain.site.team_supply, fixture.site.crowd.save_state()]))
		_check(pair[0] == pair[1], "5000-person A/B pair %d preserves all supply/native bytes" % iteration)
	TerrainArmy._idle_kernel = kernel
	_check(var_to_bytes(fixture.members) == before, "5000-person benchmark leaves every original cold record unchanged")
	costs = {"people": COUNT, "warmup_pairs": 4, "measured_pairs": 12, "reference_ms": reference, "candidate_ms": candidate,
		"reference_median_ms": _median(reference), "candidate_median_ms": _median(candidate),
		"scope": "Complete original advance_crowd_sustain call including native life query, feeding index, original/member assembly, validation, transitions and checkpoint consumption; setup/reset excluded. Synthetic cost only, not FPS."}
	print("SUSTAIN_LIFE_SAMPLE_COST ", JSON.stringify(costs))
	_close(fixture)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--crowd-output")
	output = args[at + 1] if at >= 0 and at + 1 < args.size() else "res://output/crowd_sustain_frame_20261003/life_sample_%d" % Time.get_ticks_usec()
	kernel = TerrainArmy._get_idle_kernel()
	if not _check(kernel != null and kernel.has_method("sustain_life_sample") and ClassDB.class_exists("ArmyCrowd"), "both real native query classes are available"):
		quit(2)
		return
	var fixture := _fixture(12)
	_query_cases(fixture)
	_controller_cases(fixture)
	_close(fixture)
	_benchmark()
	TerrainArmy._idle_kernel = kernel
	if not output.begins_with("res://output/") or DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) != OK:
		failed = true
	else:
		var file := FileAccess.open(output.path_join("sustain_life_sample.json"), FileAccess.WRITE)
		if file == null: failed = true
		else:
			file.store_string(JSON.stringify({"ok": not failed, "checks": checks, "costs": costs,
				"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_sustain_life_sample_test.gd"),
				"kernel_sha256": FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll")}, "\t", true, true))
			file.close()
	print("GATE FAIL: Sustain life sample" if failed else "GATE OK: Sustain life sample")
	quit(2 if failed else 0)
