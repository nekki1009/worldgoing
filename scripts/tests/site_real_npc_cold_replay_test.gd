extends "res://scripts/tests/site_shared_step_replay_base.gd"
## Independent scope: an exact saved real NPC, not the empty-ground test.
var npc_output: String = ""

class NpcFaultLog extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _first: String = ""
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		_mutex.lock()
		if _first.is_empty(): _first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]
		_mutex.unlock()
	func first_error() -> String:
		_mutex.lock()
		var result: String = _first
		_mutex.unlock()
		return result

var _npc_fault_log: NpcFaultLog = NpcFaultLog.new()
var _npc_failed: bool = false

func _initialize() -> void:
	OS.add_logger(_npc_fault_log)
	super._initialize()

func _process(_delta: float) -> bool:
	if not _npc_ok(): return false
	return super._process(_delta)

func _npc_check(value: bool, message: String) -> bool:
	if _npc_failed: return false
	var script_fault: String = _npc_fault_log.first_error()
	if not script_fault.is_empty(): value = false; message = script_fault
	if not value:
		_npc_failed = true
		_finished = true
		push_error("real_npc first failure: " + message)
		print("SITE_REAL_NPC_COLD_REPLAY_FAIL: ", message)
		quit(1)
	return value

func _npc_ok() -> bool:
	return _npc_check(true, "")

func _scene() -> TerrainLab:
	var original: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _npc_ok(): return null
	if not _npc_check(original != null, "_scene: original condition failed"): return null
	var lab: TerrainLab = original.instantiate() as TerrainLab
	if not _npc_ok(): return null
	lab.restore_only = true
	lab.pause_when_unfocused = false
	lab.exchange_enabled = true
	root.add_child(lab)
	if not _npc_ok(): return null
	if not _npc_check(lab.terrain == null and not is_instance_valid(lab.npc), "Restore-only startup must not load a default save or add a worker"): return null
	return lab

func _build(data: TerrainData, kind: String, anchor: Vector2i, extent := Vector2i.ONE) -> String:
	var options: Dictionary = {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	var layout: Dictionary = SiteRuntime.building_cells(data, kind, anchor, extent, options)
	if not _npc_ok(): return ""
	if not _npc_check(layout.ok, str(layout)): return ""
	var cells: Array[int] = []
	cells.assign(layout.cells)
	if not _npc_ok(): return ""
	var result: Dictionary = SiteRuntime.request_build(data, kind, cells, Callable(), options)
	if not _npc_ok(): return ""
	if not _npc_check(result.ok, str(result)): return ""
	var feature: Dictionary = data.site.features[result.feature]
	var task: Dictionary = {"version": 2, "zone": -1, "target": "feature:" + str(result.feature), "action": "construct",
		"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0,
		"status": "", "work_slot": -1}
	if not _npc_ok(): return ""
	SiteRuntime._feature_work(data, str(result.feature), float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	if not _npc_ok(): return ""
	if not _npc_check(str(feature.stage) == "complete", "_build: original condition failed"): return ""
	return str(result.feature)

func _same_original(actual: Variant, expected: Variant, path: String = "state") -> void:
	if not _npc_ok(): return
	if (actual is int or actual is float) and (expected is int or expected is float):
		if not _npc_check(absf(float(actual) - float(expected)) < 0.000001, "%s actual=%s expected=%s" % [path, str(actual), str(expected)]): return
	elif actual is Dictionary and expected is Dictionary:
		if not _npc_check(actual.size() == expected.size(), path): return
		for key: Variant in actual:
			if not _npc_check(expected.has(key), path + "." + str(key)): return
			_same_original(actual[key], expected[key], path + "." + str(key))
			if not _npc_ok(): return
	elif actual is Array and expected is Array:
		if not _npc_check(actual.size() == expected.size(), path): return
		for index: int in range(actual.size()):
			_same_original(actual[index], expected[index], path + "[%d]" % index)
			if not _npc_ok(): return
	else:
		# Mismatched container types report their path instead of a script error on ==.
		if not _npc_check(typeof(actual) == typeof(expected) and actual == expected, "%s actual=%s expected=%s" % [path, str(actual).left(300), str(expected).left(300)]): return

func _capture(lab: TerrainLab) -> Dictionary:
	var _npc_operation_1: Dictionary = lab.site_controller._capture_for_save()
	if not _npc_ok(): return {}
	if not _npc_check(_npc_operation_1.ok, "_capture: original condition failed"): return {}
	var state: Dictionary = lab.terrain.site.duplicate(true)
	if not _npc_ok(): return {}
	var transport: Dictionary = lab.capture_fire_transport()
	if not _npc_ok(): return {}
	if not _npc_check(transport.ok, str(transport)): return {}
	if transport.state.is_empty(): state.erase("fire_transport")
	else: state.fire_transport = transport.state
	var owners: Dictionary = lab.capture_fire_owner_state()
	if not _npc_ok(): return {}
	if not _npc_check(owners.ok, str(owners)): return {}
	if owners.state.is_empty(): state.erase("fire_owners")
	else: state.fire_owners = owners.state
	var validated: Dictionary = SiteStore._validate_state(lab.terrain, state)
	if not _npc_ok(): return {}
	if not _npc_check(validated.ok, str(validated)): return {}
	return state

func _persistent_original_projection(data: TerrainData) -> Dictionary:
	# The original loader rebuilds these derived fields. Actual operating slots
	# are last-slice TerrainData metadata, never persistent work authorities.
	# Rebuild both detached candidates through that SAME original water owner;
	# compare every field, including all unchanged people, goods and paid work.
	var projected: TerrainData = SiteEnvironment.navigation_for_state(data, data.site.duplicate(true))
	if not _npc_ok(): return {}
	projected.site.water_links = {}
	projected.site.water_status = {}
	projected.site.notices = []
	SiteRuntime.rebuild_water(projected)
	if not _npc_ok(): return {}
	var capture_transport: Variant = data.get_meta(&"fire_transport_snapshot") if data.has_meta(&"fire_transport_snapshot") else null
	if not _npc_ok(): return {}
	if capture_transport is Callable and capture_transport.is_valid():
		var transport: Variant = capture_transport.call()
		if not _npc_ok(): return {}
		if not _npc_check(transport.ok, str(transport)): return {}
		if transport.state.is_empty(): projected.site.erase("fire_transport")
		else: projected.site.fire_transport = transport.state
	# SiteStore keeps the normalized owner maps in live Site state while a capture/JSON uses the wire arrays; it accepts
	# both at the save/load boundary. Compare the one wire shape SiteStore itself produces.
	var transport_state: Variant = projected.site.get("fire_transport")
	if transport_state is Dictionary and not transport_state.is_empty():
		var wired: Dictionary = SiteStore._validate_fire_transport_snapshot(projected, projected.site.get("fire", {}), transport_state)
		if not _npc_check(wired.ok, "fire transport wire projection: " + str(wired).left(300)): return {}
		projected.site.fire_transport = wired.wire
	var capture_owners: Variant = data.get_meta(&"fire_owner_snapshot") if data.has_meta(&"fire_owner_snapshot") else null
	if not _npc_ok(): return {}
	if capture_owners is Callable and capture_owners.is_valid():
		var owners: Variant = capture_owners.call()
		if not _npc_ok(): return {}
		if not _npc_check(owners.ok, str(owners)): return {}
		if owners.state.is_empty(): projected.site.erase("fire_owners")
		else: projected.site.fire_owners = owners.state
	return projected.site


func _npc_scene() -> TerrainLab:
	var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _npc_ok(): return null
	if not _npc_check(scene != null, "_npc_scene: original condition failed"): return null
	var lab: TerrainLab = scene.instantiate() as TerrainLab
	if not _npc_ok(): return null
	lab.npc = TerrainTestNPC.new() # Existing presenter receives the saved original body.
	if not _npc_ok(): return null
	lab.restore_only = true
	lab.pause_when_unfocused = false
	root.add_child(lab)
	if not _npc_ok(): return null
	if not _npc_check(lab.terrain == null and is_instance_valid(lab.npc), "_npc_scene: original condition failed"): return null
	return lab

func _npc_source_bytes(data: TerrainData) -> PackedByteArray:
	var values: Array = [data.site, data.parameters, data.resource_base]
	for field: String in ["height_levels", "surface_types", "flags", "cliff_drops", "ramp_edges", "detail_variation",
		"fertility", "moisture", "drainage", "foundation", "groundwater", "water_kind", "water_body"]:
		values.append(data.get(field))
	return var_to_bytes(values)

func _npc_initial(dry: bool = false) -> Dictionary:
	var lab: TerrainLab = _npc_scene()
	if not _npc_ok(): return {}
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(72, 72)})
	if not _npc_ok(): return {}
	SiteEnvironment.initialize(data, "original-real-npc-cold-replay")
	if not _npc_ok(): return {}
	for y: int in range(5, 70):
		for x: int in range(5, 70):
			var index: int = data.index(Vector2i(x, y))
			if not _npc_ok(): return {}
			data.site.terrain_changes[str(index)] = 0
			if not _npc_ok(): return {}
			data.height_levels[index] = 0
	for key: String in data.resource_base:
		SiteEnvironment.change(data, key, {"cleared": true, "remaining": 0})
		if not _npc_ok(): return {}
	data.site.depot_cell = data.index(Vector2i(6, 6))
	if not _npc_ok(): return {}
	data.site.worker.cell = data.index(Vector2i(6, 7))
	if not _npc_ok(): return {}
	data.site.capacity = 100000
	for item: String in SiteEnvironment.ITEM_NAMES: data.site.inventory[item] = 1000
	var _npc_operation_2: Dictionary = SiteRuntime.initialize_item_storage(data.site)
	if not _npc_ok(): return {}
	if not _npc_check(_npc_operation_2.ok, "_npc_initial: original condition failed"): return {}
	SiteRuntime.rebuild_terrain_edges(data)
	if not _npc_ok(): return {}
	SiteEnvironment.rebuild_indexes(data)
	if not _npc_ok(): return {}
	var farm: String = _build(data, "farm", Vector2i(10, 30), Vector2i(12, 6))
	if not _npc_ok(): return {}
	if not dry:
		_build(data, "well", Vector2i(8, 32))
		if not _npc_ok(): return {}
		_build(data, "well", Vector2i(24, 32))
		if not _npc_ok(): return {}
	var _npc_operation_3: Dictionary = SiteRuntime.operate_feature(data, farm)
	if not _npc_ok(): return {}
	if not _npc_check(_npc_operation_3.ok, "_npc_initial: original condition failed"): return {}
	lab.npc.person_id = 2027
	lab.bind_terrain(data)
	if not _npc_ok(): return {}
	if not _npc_check(lab.actor_present(lab.npc) and lab.npc.person_id == 2027, "_npc_initial: original condition failed"): return {}
	data.site.next_person_id = maxi(2028, int(data.site.get("next_person_id", 2)))
	if not _npc_ok(): return {}
	lab.npc.hp = 63.0
	lab.npc.fatigue = 17.0
	lab.npc.training = 37.0
	lab.npc.faction_id = 1
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	if not _npc_ok(): return {}
	var slots: Array = SiteRuntime.feature_work_slots(data, data.site.features[farm])
	if not _npc_ok(): return {}
	var slot: Dictionary = slots[0]
	var _npc_operation_4: bool = lab.npc.place(data.cell_from_index(int(slot.cell)), true)
	if not _npc_ok(): return {}
	if not _npc_check(_npc_operation_4, "_npc_initial: original condition failed"): return {}
	data.site.worker.cell = int(slot.cell)
	if not _npc_ok(): return {}
	data.site.worker_enabled = true
	SiteRuntime.assign_task(data, SiteRuntime.ok("原 NPC 延續農場工作", {"target": "feature:" + farm,
		"action": "operate", "cell": int(slot.cell), "work_slot": int(slot.slot)}))
	if not _npc_ok(): return {}
	data.site.worker.mode = "work"
	data.site.worker.cargo = {"grain": 6, "wood": 2}
	lab.npc.ammo_inventory = data.site.worker.cargo
	var pool: Dictionary = SiteStore.Sustain.create(0.0)
	if not _npc_ok(): return {}
	var _npc_operation_5: Dictionary = SiteStore.Sustain.add_members(pool, {2027: {"hp": lab.npc.hp}}, [2027])
	if not _npc_ok(): return {}
	if not _npc_check(_npc_operation_5.ok, "_npc_initial: original condition failed"): return {}
	data.site.person_supply = {"2027": pool}
	lab.restore_only = false
	lab.movement_input_enabled = false
	lab.set_process(false)
	if not _npc_ok(): return {}
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.set_process(false)
		if not _npc_ok(): return {}
	if dry: return {"lab": lab, "farm": farm, "at": 0.0}
	lab._advance_action_time(0.5)
	if not _npc_ok(): return {}
	for meta: StringName in [&"site_camp_operating_task", &"site_operating_other_jobs", &"site_operating_slots", &"site_operating_water_revision"]:
		if not _npc_check(data.has_meta(meta), "NPC_WATER_ORIGINAL_PROJECTION_PRESENT: " + str(meta)): return {}
	var water: Dictionary = data.site.water_status.get(farm, {}).get("slots", {}).get(str(slot.slot), {})
	if not _npc_check(float(water.get("demand", 0.0)) > 0.0 and float(water.get("supplied", 0.0)) > 0.0, "NPC_WATER_REAL_SLOT_SUPPLIED"): return {}
	if not _npc_check(data.site.features[farm].batch_paid and float(data.site.features[farm].production) > 0.0, "NPC_INITIAL_PAID_PARTIAL_FARM: original batch_paid AND production > 0 failed"): return {}
	if not _npc_check(lab.npc.fatigue > 17.0 and lab.npc.hp != 100.0, "_npc_initial: original condition failed"): return {}
	if not _npc_check(float(pool.at) > 0.0 and not pool.cohorts.is_empty() and int(data.site.worker.cargo.grain) < 6, "_npc_initial: original condition failed"): return {}
	var _npc_operation_6: Dictionary = lab.site_controller._capture_for_save()
	if not _npc_ok(): return {}
	if not _npc_check(_npc_operation_6.ok, "_npc_initial: original condition failed"): return {}
	data.site.actor_presence_version = 1
	var at: float = SiteRuntime.now(data) * 60.0
	if not _npc_ok(): return {}
	var _npc_operation_7: Dictionary = RegionSaveSlot.attach_settlement(data.site, at)
	if not _npc_ok(): return {}
	if not _npc_check(_npc_operation_7.ok, "_npc_initial: original condition failed"): return {}
	var saved: Dictionary = SiteStore.save(data, npc_output.path_join("source.json"))
	if not _npc_ok(): return {}
	if not _npc_check(saved.ok, str(saved)): return {}
	return {"lab": lab, "farm": farm, "at": at}

func _npc_restore(data: TerrainData) -> TerrainLab:
	var original: PackedByteArray = _npc_source_bytes(data)
	if not _npc_ok(): return null
	var lab: TerrainLab = _npc_scene()
	if not _npc_ok(): return null
	var restored: Dictionary = lab.restore_original_site(data)
	if not _npc_ok(): return null
	if not _npc_check(restored.ok, str(restored)): return null
	if not _npc_check(lab.terrain != data and _npc_source_bytes(data) == original, "_npc_restore: original condition failed"): return null
	if not _npc_check(lab.actor_present(lab.npc) and lab.npc.person_id == 2027, "_npc_restore: original condition failed"): return null
	var bound_guard: Variant = lab.terrain.get_meta(&"siege_event_guard") if lab.terrain.has_meta(&"siege_event_guard") else null
	if not _npc_ok(): return null
	if not _npc_check(bound_guard is Callable and bound_guard.is_valid() and bound_guard.get_object() == lab, "_npc_restore: original condition failed"): return null
	_same_original(lab.npc.capture_state(), data.site.actors.npc)
	if not _npc_ok(): return null
	_same_original(lab.terrain.site.worker, data.site.worker)
	if not _npc_ok(): return null
	if not _npc_check(lab.terrain.site.worker_enabled and str(lab.terrain.site.worker.target).begins_with("feature:"), "_npc_restore: original condition failed"): return null
	return lab

func _npc_saved_shapes(path: String) -> void:
	var read: Dictionary = SiteStore._read(path)
	if not _npc_ok(): return
	if not _npc_check(read.ok, str(read)): return
	var state: Dictionary = read.payload.state
	for domain: String in ["actors", "features", "terrain_changes", "changes", "person_supply", "item_records", "item_definitions"]:
		for key: Variant in state.get(domain, {}):
			if not _npc_check(key is String, domain + " saved key must be a string"): return
	if not _npc_check(state.actors.npc.cell is Array and state.actors.npc.cell.size() == 2, "_npc_saved_shapes: original condition failed"): return
	if not _npc_check(state.actors.npc.movement_from is Array and state.actors.npc.movement_from.size() == 2, "_npc_saved_shapes: original condition failed"): return
	if not _npc_check(state.actors.npc.item_state.item_ids is Array, "_npc_saved_shapes: original condition failed"): return
	if not _npc_check(state.person_supply["2027"].cohorts is Array, "_npc_saved_shapes: original condition failed"): return
	if not _npc_check(state.person_supply["2027"].cohorts[0].ids is Array, "_npc_saved_shapes: original condition failed"): return

func _npc_water_economy(lab: TerrainLab, farm: String) -> PackedByteArray:
	var data: TerrainData = lab.terrain
	return var_to_bytes([data.site.features[farm], data.site.inventory, data.site.worker.cargo,
		lab.npc.capture_state(), data.site.person_supply, data.site.item_records,
		data.site.minute, data.site.phase, lab.fire_action_cursor])

func _npc_dry_refusal() -> bool:
	var fixture: Dictionary = _npc_initial(true)
	if not _npc_ok() or fixture.is_empty(): return false
	var lab: TerrainLab = fixture.lab
	var data: TerrainData = lab.terrain
	var controller: SiteController = lab.site_controller
	var before: PackedByteArray = _npc_water_economy(lab, str(fixture.farm))
	controller._shared_worker_inputs = controller._prepare_original_work_inputs()
	if not _npc_check(bool(controller._shared_worker_inputs.worker_ready), "NPC_DRY_ORIGINAL_READY"): return false
	var requests: Array = controller.prepare_shared_owner_work_requests(2.0)
	if not _npc_ok(): return false
	var admitted: bool = false
	for request: Dictionary in requests:
		if str(request.provider) == "runtime" and str(request.key) == "worker": admitted = true
	if not _npc_check(data.has_meta(&"site_camp_operating_task"), "NPC_DRY_PROJECTION_SETTLED"): return false
	var camp: Variant = data.get_meta(&"site_camp_operating_task")
	if not _npc_check(not admitted and camp is Dictionary and camp.is_empty() and _npc_water_economy(lab, str(fixture.farm)) == before, "NPC_DRY_NO_ADMISSION_PAYMENT_WORK_OR_CLOCK"): return false
	lab.free()
	return _npc_ok()

func _finalize() -> void:
	OS.remove_logger(_npc_fault_log)

func _run() -> void:
	_started = true
	deadline = Time.get_ticks_msec() + 90000
	if not _npc_ok(): return
	root.gui_embed_subwindows = true
	npc_output = "res://output/site_building_close_20261004/ground_caller_candidate/npc_cold_followup/runs/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _npc_ok(): return
	var _npc_operation_8: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(npc_output))
	if not _npc_ok(): return
	if not _npc_check(_npc_operation_8 == OK, "_run: original condition failed"): return
	if not _npc_dry_refusal(): return
	var initial: Dictionary = _npc_initial()
	if not _npc_ok(): return
	var loaded: Dictionary = SiteStore.load_site(npc_output.path_join("source.json"), Callable(), 1, true)
	if not _npc_ok(): return
	if not _npc_check(loaded.ok, str(loaded)): return
	var source: TerrainData = loaded.data
	var original: PackedByteArray = _npc_source_bytes(source)
	if not _npc_ok(): return
	_npc_saved_shapes(npc_output.path_join("source.json"))
	if not _npc_ok(): return
	var missing: TerrainLab = _scene()
	if not _npc_ok(): return
	var refused: Dictionary = missing.restore_original_site(source)
	if not _npc_ok(): return
	if not _npc_check(not refused.ok and refused.code == "RESTORE_PRESENTER" and missing.terrain == null, "_run: original condition failed"): return
	if not _npc_check(_npc_source_bytes(source) == original, "_run: original condition failed"): return
	checks += 1

	var live: TerrainLab = _npc_restore(source)
	if not _npc_ok(): return
	var slot: RegionSaveSlot = RegionSaveSlot.new()
	if not _npc_ok(): return
	slot.pin = {"world_instance_id": "original-npc-cold-replay", "slot_id": "synthetic-live-clock"}
	slot.control = {"logical_game_seconds": float(initial.at), "active_site_id": str(source.site.id)}
	if not _npc_ok(): return
	live.site_controller.region_slot = slot
	live.restore_only = false
	live.movement_input_enabled = false
	live._advance_action_time(8.0)
	if not _npc_ok(): return
	# This synthetic slot has no fixed geography or formal Fire journal (the same rule as site_shared_step_replay_test):
	# the live step's Fire settlement watermark belongs to no journal, so the capture compares without it.
	live.terrain.site.erase("fire_settlement")
	var target: float = float(slot.control.logical_game_seconds)
	if not _npc_ok(): return
	var expected: Dictionary = _capture(live)
	if not _npc_ok(): return
	if not _npc_check(float(expected.person_supply["2027"].at) > float(source.site.person_supply["2027"].at), "_run: original condition failed"): return
	if not _npc_check(float(expected.actors.npc.fatigue) != float(source.site.actors.npc.fatigue), "_run: original condition failed"): return
	if not _npc_check(float(expected.features[initial.farm].production) != float(source.site.features[initial.farm].production), "_run: original condition failed"): return
	if not _npc_check(expected.actors.npc.item_state.item_ids == source.site.actors.npc.item_state.item_ids, "_run: original condition failed"): return
	if not _npc_check(int(expected.actors.npc.person_id) == 2027 and str(expected.actors.npc.item_state.holder) == "person:2027", "_run: original condition failed"): return
	var cold: TerrainLab = _npc_restore(source)
	if not _npc_ok(): return
	var replay: Dictionary = cold.replay_site_to(target, 0, 1)
	if not _npc_ok(): return
	if not _npc_check(replay.ok and replay.status == "PENDING", "_run: original condition failed"): return
	while replay.ok and replay.status == "PENDING":
		if not _npc_check(Time.get_ticks_msec() <= deadline, "_run: original condition failed"): return
		replay = cold.replay_site_to(target, 0, 17)
		if not _npc_ok(): return
	if not _npc_check(replay.ok and replay.status == "COMPLETE", str(replay)): return
	_same_original(_capture(cold), expected)
	if not _npc_ok(): return
	if not _npc_check(_npc_source_bytes(source) == original, "_run: original condition failed"): return
	checks += 1

	# Production adapter must construct the existing presenter before _ready,
	# then restore this saved original ID/body/items instead of retiring it.
	var host: TerrainLab = _scene()
	if not _npc_ok(): return
	var adapted: Dictionary = host.advance_cold_site(source, target)
	if not _npc_ok(): return
	while not adapted.ok and adapted.code == "PENDING":
		if not _npc_check(Time.get_ticks_msec() <= deadline, "_run: original condition failed"): return
		if not _npc_check(is_instance_valid(host._cold_replay_lab.npc) and host._cold_replay_lab.npc.person_id == 2027, "_run: original condition failed"): return
		if not _npc_check(_npc_source_bytes(source) == original, "_run: original condition failed"): return
		adapted = host.advance_cold_site(source, target)
		if not _npc_ok(): return
	if not _npc_check(adapted.ok and adapted.data != source, str(adapted)): return
	for hook: StringName in [&"siege_event_guard", &"fire_event_guard", &"fire_pending_projectile_query", &"ship_journey_active", &"region_operation_pending", &"ship_vehicle_in_journey"]:
		if not _npc_check(not adapted.data.has_meta(hook), "A completed cold candidate must not retain its retired scene callback: " + str(hook)): return
	_same_original(adapted.data.site, expected)
	if not _npc_ok(): return
	if not _npc_check(not is_instance_valid(host._cold_replay_lab) and _npc_source_bytes(source) == original, "_run: original condition failed"): return
	checks += 1

	var settled_path: String = npc_output.path_join("settled.json")
	if not _npc_ok(): return
	var settled_save: Dictionary = SiteStore.save(adapted.data, settled_path)
	if not _npc_ok(): return
	if not _npc_check(settled_save.ok, str(settled_save)): return
	_npc_saved_shapes(settled_path)
	if not _npc_ok(): return
	var reopened: Dictionary = SiteStore.load_site(settled_path, Callable(), 1, true)
	if not _npc_ok(): return
	if not _npc_check(reopened.ok, str(reopened)): return
	var revisit: TerrainLab = _npc_restore(reopened.data)
	if not _npc_ok(): return
	var before_zero: Dictionary = _capture(revisit)
	if not _npc_ok(): return
	# Loader water/notices caches use detached original rebuilds; last-slice
	# operating metadata is never a saved job/person/material authority.
	var settled_original: PackedByteArray = _npc_source_bytes(adapted.data)
	if not _npc_ok(): return
	var _npc_revisit_projection_1: Dictionary = _persistent_original_projection(revisit.terrain)
	if not _npc_ok(): return
	var _npc_settled_projection_1: Dictionary = _persistent_original_projection(adapted.data)
	if not _npc_ok(): return
	_same_original(_npc_revisit_projection_1, _npc_settled_projection_1)
	if not _npc_ok(): return
	if not _npc_check(_npc_source_bytes(adapted.data) == settled_original, "_run: original condition failed"): return
	var _npc_water_projection: Dictionary = _persistent_original_projection(revisit.terrain)
	if not _npc_ok(): return
	_same_original(revisit.terrain.site.water_status, _npc_water_projection.water_status)
	if not _npc_ok(): return
	var zero: Dictionary = revisit.replay_site_to(target, 0, 1)
	if not _npc_ok(): return
	if not _npc_check(zero.ok and zero.steps == 0 and zero.pending == 0.0, "_run: original condition failed"): return
	_same_original(_capture(revisit), before_zero)
	if not _npc_ok(): return
	var _npc_revisit_projection_2: Dictionary = _persistent_original_projection(revisit.terrain)
	if not _npc_ok(): return
	var _npc_settled_projection_2: Dictionary = _persistent_original_projection(adapted.data)
	if not _npc_ok(): return
	_same_original(_npc_revisit_projection_2, _npc_settled_projection_2)
	if not _npc_ok(): return
	if not _npc_check(_npc_source_bytes(source) == original, "_run: original condition failed"): return
	checks += 1
	for lab: TerrainLab in [initial.lab, missing, live, cold, host, revisit]:
		lab.free()
		if not _npc_ok(): return
	TerrainArmy.release_contact_source()
	if not _npc_ok(): return
	if not _npc_check(checks == 4, "_run: original condition failed"): return
	if not _npc_ok(): return
	_finished = true
	print("SITE_REAL_NPC_COLD_REPLAY_PASS: actual original PackedScene and saved NPC 2027; pure missing-presenter refusal; original body/HP/fatigue/training/items/private meal/cargo/worker task retained, paid partial farm live-vs-cold full-state equality, actual production cold adapter restores same original NPC, all mutable source arrays untouched, saved array/string-key shapes, zero-game-time reopen; no native/GPU/performance/release claim")
	if not _npc_ok(): return
	quit(0)
	if not _npc_ok(): return
