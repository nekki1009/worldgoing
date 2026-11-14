extends SceneTree
## Crowd live/cold parity through the original Native, WorkTeam, Store and Region owners.
const SAVE := "res://.godot-temp/site_shared_step_replay/crowd.json"
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const DT := 1.0 / 30.0
var checks := 0
var deadline := 0
var failed := false
var started := false
var finished := false
var labs: Array[TerrainLab] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 600000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not failed and ((started and not finished) or Time.get_ticks_msec() > deadline): _require(false, "body interrupted or 600s total deadline")
	return false

func _require(ok: bool, label: String, detail: Variant = null) -> bool:
	checks += 1
	if not ok:
		failed = true
		push_error("SHARED_STEP_CROWD_FAIL " + label + " " + str(detail))
		quit(1)
	return ok

func _scene(cold: bool) -> TerrainLab:
	var packed: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _require(packed != null, "original scene"): return null
	var lab: TerrainLab = packed.instantiate() as TerrainLab
	lab.restore_only = cold
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	lab.site_controller._auto_save_blocked = true
	labs.append(lab)
	return lab

func _build(data: TerrainData, kind: String, anchor: Vector2i, extent := Vector2i.ONE) -> String:
	var options := {"layout_version": 1, "quarter": 0, "owner_faction": 0}
	var layout: Dictionary = SiteRuntime.building_cells(data, kind, anchor, extent, options)
	if not _require(layout.ok, "original building cells", layout): return ""
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var result: Dictionary = SiteRuntime.request_build(data, kind, cells, Callable(), options)
	if not _require(result.ok, "original paid construction", result): return ""
	var feature: Dictionary = data.site.features[result.feature]
	var task: Dictionary = {"version": 2, "zone": -1, "target": "feature:" + str(result.feature), "action": "construct",
		"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(data, str(result.feature), float(feature.work), Callable(), Callable(), task, {}, 20, 0)
	if not _require(str(feature.stage) == "complete", "original complete feature"): return ""
	return str(result.feature)

func _step(lab: TerrainLab, seconds: float = DT) -> bool:
	var result: Dictionary = lab._advance_original_shared_step(seconds)
	if not _require(result.ok and bool(result.get("completed", false)), "live original shared point", result): return false
	return true

func _live_frame(lab: TerrainLab, seconds: float = DT) -> bool:
	var before: float = SiteRuntime.now(lab.terrain) * 60.0
	lab._advance_action_time(seconds)
	var fault: Dictionary = lab.site_controller.original_step_fault_guard()
	if not _require(fault.ok, "original live producer", fault): return false
	var now: float = SiteRuntime.now(lab.terrain) * 60.0
	# This fixture has no RegionSaveSlot; publish the actually completed local interval through its original watermark owner.
	if now > before:
		var recorded: Dictionary = RegionSaveSlot.record_completed_replay_step(lab.terrain.site, now, now - before)
		if not _require(recorded.ok, "publish actual completed live clock", recorded): return false
	return true

func _dump(name: String, state: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("res://output/shared_step_replay_crowd")
	var file: FileAccess = FileAccess.open("res://output/shared_step_replay_crowd/" + name + ".var", FileAccess.WRITE)
	if file != null:
		file.store_var(state)
		file.close()

func _station(lab: TerrainLab, identity: int, cell: Vector2i) -> bool:
	var native: int = int(lab.crowd_site.crowd.soldier_index(identity))
	if not _require(native >= 0 and lab.terrain.is_walkable(cell), "real native worker station", [identity, cell]): return false
	if identity == lab.controlled_person_id():
		if not _require(lab.character.place(cell, true), "controlled original station"): return false
	return _require(lab.crowd_site.set_soldier_fields(native, {"px": cell.x + 0.5, "py": cell.y + 0.5}), "place same native identity")

func _initial() -> Dictionary:
	var lab: TerrainLab = _scene(false)
	if failed: return {}
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(72, 72)})
	SiteEnvironment.initialize(data, "original-shared-step-replay-crowd")
	for y: int in range(5, 70):
		for x: int in range(5, 70):
			var index: int = data.index(Vector2i(x, y))
			data.site.terrain_changes[str(index)] = 0
			data.height_levels[index] = 0
	for key: String in data.resource_base: SiteEnvironment.change(data, key, {"cleared": true, "remaining": 0})
	data.site.depot_cell = data.index(Vector2i(6, 6))
	data.site.worker_enabled = false
	data.site.capacity = 100000
	data.site.manual.cargo = {"grain": 8} # Finite authored starting cargo; delivery itself is a real original transaction.
	for item: String in SiteEnvironment.ITEM_NAMES: data.site.inventory[item] = 1000
	if not _require(SiteRuntime.initialize_item_storage(data.site).ok, "initial real item storage"): return {}
	SiteRuntime.rebuild_terrain_edges(data)
	SiteEnvironment.rebuild_indexes(data)
	var farm: String = _build(data, "farm", Vector2i(10, 30), Vector2i(12, 6))
	_build(data, "well", Vector2i(8, 32))
	_build(data, "well", Vector2i(24, 32))
	if failed: return {}
	if not _require(SiteRuntime.operate_feature(data, farm).ok, "enable original farm"): return {}
	lab.bind_terrain(data)
	var deployed: Dictionary = lab.deploy_trial_armies([{"faction": 0, "count": 3, "attack": false, "ai_enabled": false, "entry": "west", "spawn": Vector2i(8, 8)}])
	if not _require(deployed.ok and lab.crowd_site != null and lab.crowd_site.active, "formal Native deployment; no grid simulation", deployed): return {}
	var owner: CrowdPersonOwner
	for team: Dictionary in lab.crowd_site.command_teams():
		var record: Dictionary = lab.crowd_site._team_by_id(int(team.team_id))
		if record.person_ids.size() == 3: owner = lab.crowd_site.person_owner(int(record.person_ids[0])); break
	if not _require(owner != null, "original three-member Native team"): return {}
	var commander: int = int(owner.combat_identity(owner.current_commander))
	var workers: Array[int] = []
	for index: int in owner.combat_units.keys():
		var identity: int = int(owner.combat_identity(index))
		if identity != commander: workers.append(identity)
	if not _require(workers.size() == 2 and lab.controlled_person_id() > 0 and lab.crowd_site.contains_person(lab.controlled_person_id()), "controlled original plus two native workers"): return {}
	if not _station(lab, lab.controlled_person_id(), Vector2i(6, 7)): return {}
	if not _station(lab, commander, Vector2i(7, 7)): return {}
	for index: int in 2:
		if not _station(lab, workers[index], Vector2i(8 + index, 7)): return {}
	lab.crowd_site.set_formation_fields(owner.formation_index, {"cx": 7.5, "cy": 7.5, "origin_x": 7.5, "origin_y": 7.5, "goal_x": 7.5, "goal_y": 7.5})
	for tick: int in 120:
		lab.crowd_site.siege_approach_step(commander, Vector2i(7, 7))
		if not _step(lab): return {}
		if tick >= 4 and owner.moving_member_count() == 0: break
	var carried_before: int = int(lab.site_controller.person_actions._person(lab.controlled_person_id()).cargo.get("grain", 0))
	var begun: Dictionary = lab.site_controller.begin_team_food(owner, 4.0, commander, {"kind": "person"})
	if not _require(begun.ok, "actual controlled-person food delivery", begun): return {}
	var entry: Dictionary = lab.site_controller._supply_entry(owner)
	for tick: int in 300:
		if not _step(lab): return {}
		if entry.delivery.is_empty(): break
	if not _require(entry.delivery.is_empty() and not entry.sustain.cohorts.is_empty() and carried_before - int(lab.site_controller.person_actions._person(lab.controlled_person_id()).cargo.get("grain", 0)) == 4 and Sustain.rations(entry.sustain, lab.site_controller._supply_stock(entry)) > 0.0, "actual four-grain debit, real supplied meals and held food", entry): return {}
	var slots: Array = SiteRuntime.feature_work_slots(data, data.site.features[farm])
	if not _require(slots.size() >= 2, "two actual farm work slots"): return {}
	if not _station(lab, commander, Vector2i(9, 30)): return {}
	lab.crowd_site.set_formation_fields(owner.formation_index, {"cx": 9.5, "cy": 30.5, "origin_x": 9.5, "origin_y": 30.5, "goal_x": 9.5, "goal_y": 30.5})
	for index: int in 2:
		if not _station(lab, workers[index], data.cell_from_index(int(slots[index].cell))): return {}
	for tick: int in 90:
		for index: int in 2: lab.crowd_site.siege_approach_step(workers[index], data.cell_from_index(int(slots[index].cell)))
		if not _step(lab): return {}
		if tick >= 4 and owner.moving_member_count() == 0: break
	var assigned: Dictionary = lab.site_controller.work_team.assign(owner, workers, commander)
	if not _require(assigned.ok, "original commander dispatches two workers", assigned): return {}
	for tick: int in 30:
		if not _step(lab): return {}
	var feature: Dictionary = data.site.features[farm]
	var person: Dictionary = lab.site_controller.person_actions._person(workers[0])
	if not _require(bool(feature.batch_paid) and float(feature.production) > 0.0 and float(feature.production) < float(SiteRuntime.FEATURES.farm.cycle), "actual paid partial farm batch", feature): return {}
	if not _require(float(lab.site_controller.person_actions._body_get(person, "fatigue")) > 0.0, "actual native pool work fatigue"): return {}
	print("CROWD_REPLAY_INITIAL_READY farm=", farm, " workers=", workers)
	return {"lab": lab, "farm": farm, "workers": workers, "team_id": int(owner.team_id)}

func _context(lab: TerrainLab) -> Dictionary:
	var fire: Dictionary = lab.terrain.site.get("fire_settlement", {})
	return {"purpose": "region_checkpoint", "mode": "cold_exact" if lab.restore_only else "live", "source_generation": 0, "runtime_revision": 0,
		"token": "shared_step_crowd", "game_seconds": SiteRuntime.now(lab.terrain) * 60.0, "action_seconds": float(lab.fire_action_cursor),
		"fire_epoch": str(fire.get("epoch", "")), "fire_sequence": int(fire.get("sequence", 0)), "interval_complete": true, "effects_complete": true,
		"mode_revision": 0, "backend": lab.region_backend_expected(), "events": [], "endpoint_payload": {}}

func _capture(lab: TerrainLab) -> Dictionary:
	var captured: Dictionary = lab.crowd_site.capture_save(true)
	if not _require(captured.ok, "original native checkpoint capture", captured): return {}
	lab.site_controller._capture_positions()
	lab.site_controller._apply_region_crowd_capture(captured)
	# The Lab's current Fire transport and owners, not the copy the last save left in the Site dictionary (as the GD base
	# _capture does; found 2026-11-14: the stale copy hid that both sides' real action cursors were never compared).
	var state: Dictionary = lab.terrain.site.duplicate(true)
	var transport: Dictionary = lab.capture_fire_transport()
	if not _require(transport.ok, "original Fire transport capture", transport): return {}
	if transport.state.is_empty(): state.erase("fire_transport")
	else: state.fire_transport = transport.state
	var owners: Dictionary = lab.capture_fire_owner_state()
	if not _require(owners.ok, "original Fire owner capture", owners): return {}
	if owners.state.is_empty(): state.erase("fire_owners")
	else: state.fire_owners = owners.state
	return state

func _checkpoint(lab: TerrainLab, path: String) -> bool:
	_capture(lab)
	if failed: return false
	var context: Dictionary = _context(lab)
	var stamp: Dictionary = RegionSaveSlot.attach_settlement(lab.terrain.site, context.game_seconds)
	if not _require(stamp.ok, "original settlement endpoint stamp", stamp): return false
	var owners: Dictionary = lab.capture_region_owner_state(context, true)
	if not _require(owners.ok, "original complete owner graph", owners): return false
	var saved: Dictionary = SiteStore.save_region_snapshot(lab.terrain, path, context, owners.get("owner_states", {}), true)
	return _require(saved.ok, "original Store region checkpoint", saved)

func _restore(source: TerrainData) -> TerrainLab:
	var before: PackedByteArray = _source_bytes(source)
	var lab: TerrainLab = _scene(true)
	if failed: return null
	var restored: Dictionary = lab.restore_original_site(source)
	if not _require(restored.ok and lab.crowd_site != null and lab.crowd_site.active, "original crowd snapshot bootstrap", restored): return null
	if not _require(lab.terrain != source and _source_bytes(source) == before, "caller data is unchanged"): return null
	if not _require(lab.site_controller.work_team.active_ids().size() == 2, "same two original work identities restored"): return null
	return lab

func _source_bytes(data: TerrainData) -> PackedByteArray:
	return var_to_bytes([data.site, data.height_levels, data.flags, data.ramp_edges, data.resource_base, data.fertility, data.moisture, data.drainage, data.foundation, data.groundwater, data.surface_types, data.cliff_drops, data.detail_variation, data.water_kind, data.water_body, data.parameters])

func _blob_hash(bytes: PackedByteArray) -> String:
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func _blob_vector(blob: PackedByteArray, cursor: Dictionary, width: int) -> bool:
	if not _require(cursor.at + 8 <= blob.size(), "KW21 vector header bounds"): return false
	var count: int = int(blob.decode_u64(cursor.at))
	if not _require(count >= 0 and count <= 1048576 and cursor.at + 8 + count * width <= blob.size(), "KW21 vector bounds"): return false
	cursor.at += 8 + count * width
	return true

func _native_numeric_offsets(blob: PackedByteArray) -> Dictionary:
	# Same-build KW21 prefix from World::serialize/io_formation; this fixture has no native projectiles or undrained events.
	if not _require(blob.size() >= 158 and blob.decode_u32(0) == 0x3132574b, "explicit current KW21 layout"): return {}
	var cursor: Dictionary = {"at": 158} # magic4 + serialized Config146 + terrain dimensions8 (no struct padding).
	for _field: int in 7:
		if not _blob_vector(blob, cursor, 1): return {}
	if not _require(cursor.at + 8 <= blob.size(), "KW21 formation count bounds"): return {}
	var formations: int = int(blob.decode_u64(cursor.at))
	cursor.at += 8
	if not _require(formations > 0 and formations <= 65537, "KW21 formation count"): return {}
	var fields: Dictionary = {}
	for formation: int in formations:
		cursor.at += 48
		if not _blob_vector(blob, cursor, 4): return {}
		cursor.at += 8 + 8 + 4 + 8 + 8 + 8 + 2 + 12
		if not _blob_vector(blob, cursor, 4): return {}
		cursor.at += 1 + 8 + 1 + 8 + 8 + 8 + 8 + 1
		fields[cursor.at - 9] = "formation%d.rally_rest" % formation
		fields[cursor.at] = "formation%d.fatigue" % formation
		fields[cursor.at + 8] = "formation%d.fatigue_rest" % formation
		cursor.at += 16 + 139
		if not _blob_vector(blob, cursor, 4): return {}
	for _field: int in 10:
		if not _blob_vector(blob, cursor, 4): return {}
	if not _blob_vector(blob, cursor, 1): return {}
	for _field: int in 4:
		if not _blob_vector(blob, cursor, 4): return {}
	for _field: int in 12:
		if not _blob_vector(blob, cursor, 8): return {}
	for _field: int in 13:
		if not _blob_vector(blob, cursor, 1): return {}
	for _field: int in 10:
		if not _blob_vector(blob, cursor, 4): return {}
	for width: int in [8, 4, 1, 8, 1, 1, 1, 4, 4, 2]:
		if not _blob_vector(blob, cursor, width): return {}
	if not _require(cursor.at + 8 <= blob.size(), "KW21 equipment count bounds"): return {}
	var equipment: int = int(blob.decode_u64(cursor.at))
	if not _require(equipment >= 0 and equipment <= 65536, "KW21 equipment count"): return {}
	cursor.at += 8 + equipment * 4
	for width: int in [6, 8, 1, 1, 1, 1, 4, 1, 1, 1, 1, 1, 4, 8, 8, 4, 8, 1]:
		if not _blob_vector(blob, cursor, width): return {}
	if not _require(cursor.at + 16 <= blob.size() and blob.decode_u64(cursor.at) == 0 and blob.decode_u64(cursor.at + 8) == 0, "no undrained events or native projectile in this work/clock fixture"): return {}
	cursor.at += 16
	for _field: int in 3:
		if not _blob_vector(blob, cursor, 4): return {}
	cursor.at += 4 + 8 + 8 + 8 + 1 + 8 + 8
	if not _require(cursor.at + 8 <= blob.size(), "KW21 clock bounds"): return {}
	fields[cursor.at] = "world.game_dt"
	return fields

func _same_native_section(actual: Dictionary, expected: Dictionary, path: String) -> bool:
	var a: PackedByteArray = Marshalls.base64_to_raw(str(actual.blob))
	var b: PackedByteArray = Marshalls.base64_to_raw(str(expected.blob))
	if not _require(_blob_hash(a) == str(actual.blob_sha256) and _blob_hash(b) == str(expected.blob_sha256), path + " original blob SHA256 validity"): return false
	if not _require(a.size() == b.size(), path + " exact payload size"): return false
	var offsets: Dictionary = _native_numeric_offsets(a)
	var other: Dictionary = _native_numeric_offsets(b)
	if failed or not _require(offsets == other, path + " same parsed typed fields"): return false
	for offset: int in offsets:
		var x: float = a.decode_double(offset)
		var y: float = b.decode_double(offset)
		var tolerance: float = maxf(0.00000001, maxf(absf(x), absf(y)) * 0.000000001) if offsets[offset] == "world.game_dt" else 0.000001
		if not _require(is_finite(x) and is_finite(y) and absf(x - y) < tolerance, path + "." + str(offsets[offset]), [x, y, tolerance]): return false
		# Values have passed their typed numeric comparison; only their encoded double representation may differ.
		for byte: int in range(offset, offset + 8):
			a[byte] = 0
			b[byte] = 0
	if not _require(a == b, path + " all other native bytes exact"): return false
	for key: Variant in actual:
		if key not in ["blob", "blob_sha256"] and not _same_original(actual[key], expected[key], path + "." + str(key)): return false
	return true

func _same_original(actual: Variant, expected: Variant, path: String = "state") -> bool:
	if (actual is int or actual is float) and (expected is int or expected is float):
		return _require(absf(float(actual) - float(expected)) < 0.000001, path, [actual, expected])
	if actual is Dictionary and expected is Dictionary:
		if not _require(actual.size() == expected.size(), path + " size", [actual.keys(), expected.keys()]): return false
		if actual.has("blob") and actual.has("blob_sha256") and expected.has("blob") and expected.has("blob_sha256"):
			return _same_native_section(actual, expected, path)
		for key: Variant in actual:
			if not _require(expected.has(key), path + "." + str(key) + " key"): return false
			if not _same_original(actual[key], expected[key], path + "." + str(key)): return false
		return true
	if actual is Array and expected is Array:
		if not _require(actual.size() == expected.size(), path + " size"): return false
		for index: int in actual.size():
			if not _same_original(actual[index], expected[index], path + "[%d]" % index): return false
		return true
	return _require(actual == expected, path, [actual, expected])

func _replay(lab: TerrainLab, target: float, result: Dictionary = {}) -> Dictionary:
	if result.is_empty(): result = lab.replay_site_to(target, 0, 17)
	for attempt: int in 10000:
		if failed: return result
		if result.ok and str(result.get("status", "")) == "COMPLETE": return result
		if not lab._region_point_pending.is_empty():
			var consumed: Dictionary = lab.consume_region_point(false)
			if not _require(consumed.ok, "consume original replay endpoint", consumed): return consumed
		elif not result.ok and str(result.get("code", "")) != "REGION_REPLAY_PENDING":
			_require(false, "original cold replay refused", result)
			return result
		if not _require(Time.get_ticks_msec() <= deadline, "bounded pending retries"): return result
		result = lab.replay_site_to(target, 0, 17)
	_require(false, "bounded replay iteration count", result)
	return result

func _close(lab: TerrainLab) -> void:
	labs.erase(lab)
	lab.free()

func _mixed_clock(source: TerrainData) -> bool:
	var seed: TerrainLab = _restore(source)
	if failed: return false
	SiteRuntime.start_combat(seed.terrain.site, 0.04)
	if not _checkpoint(seed, SAVE + ".mixed"): return false
	var saved: Dictionary = SiteStore.load_site(SAVE + ".mixed")
	if not _require(saved.ok, "mixed clock checkpoint", saved): return false
	_close(seed)
	var live: TerrainLab = _restore(saved.data)
	var cold: TerrainLab = _restore(saved.data)
	if failed: return false
	live.restore_only = false
	live.movement_input_enabled = false
	var game_before: float = SiteRuntime.now(live.terrain) * 60.0
	for tick: int in 6:
		if not _live_frame(live): return false
	var target: float = SiteRuntime.now(live.terrain) * 60.0
	if not _require(absf(target - game_before - (0.04 + 0.16 * 60.0)) < 0.000001, "current Native 30Hz combat-to-peace integration", [game_before, target]): return false
	var replayed: Dictionary = _replay(cold, target)
	if failed or not _require(replayed.ok, "mixed clock replay", replayed): return false
	if not _same_original(_capture(cold), _capture(live), "mixed"): return false
	_close(live)
	_close(cold)
	print("SHARED_STEP_CROWD_MIXED_CLOCK_OK")
	return true

## One retained slot-less cold owner (advance_cold_site) accepts retries of the SAME untouched input and fixed target and
## publishes one completed detached result equal to the live run (2026-11-14: the adapter now consumes its native
## endpoints, terrain_lab._slotless_cold_replay). The region_snapshot envelope (mode/token/context) is the published
## result's own checkpoint metadata, not simulated state, and is not compared.
func _retained_adapter(source: TerrainData, target: float, expected: Dictionary) -> bool:
	var host: TerrainLab = _scene(true)
	if failed: return false
	var result: Dictionary = host.advance_cold_site(source, target)
	var retried := false
	for attempt: int in 10000:
		if result.ok: break
		if not _require(str(result.get("code", "")) == "PENDING", "original retained cold adapter retry", result): return false
		var retained: TerrainLab = host._cold_replay_lab
		if not _require(is_instance_valid(retained), "same retained original cold owner exists"): return false
		if not retried:
			var replaced: Dictionary = host.advance_cold_site(source, target + 1.0)
			if not _require(not replaced.ok and replaced.code == "BUSY" and is_same(host._cold_replay_lab, retained), "adapter also pins source and target", replaced): return false
			retried = true
		if not _require(Time.get_ticks_msec() <= deadline, "bounded original adapter retry deadline"): return false
		result = host.advance_cold_site(source, target)
	if not _require(result.ok and retried and result.data != source, "retained cold adapter publishes one completed detached result", result): return false
	var restored: TerrainLab = _restore(result.data)
	if failed: return false
	var actual: Dictionary = _capture(restored)
	var reference: Dictionary = expected.duplicate(true)
	# The loader rebuilds water links/status and notices from the restored state (derived caches, as the GD base's
	# _persistent_original_projection treats them); they are not saved simulation state.
	for derived: String in ["region_snapshot", "water_links", "water_status", "notices"]:
		actual.erase(derived)
		reference.erase(derived)
	if not _same_original(actual, reference, "retained_adapter"): return false
	_close(restored)
	_close(host)
	print("SHARED_STEP_CROWD_RETAINED_ADAPTER_OK")
	return true

func _run() -> void:
	started = true
	if not _require(OS.get_cmdline_user_args().has("--crowd") and OS.get_cmdline_user_args().has("--crowd-test"), "explicit isolated crowd startup"): return
	if not _require(FileAccess.get_sha256("res://native/crowd10k/src/state.cpp") == "e09788315d303457d4bb0be529390232359e16f881e341a86b59381005d9a2cd", "fixed KW21 serializer state.cpp for typed byte comparison"): return
	if not _require(FileAccess.get_sha256("res://native/crowd10k/src/crowd_core.hpp") == "5c3f6a5c5b3bab3102685d0eb663a9c66fc0ead66f9da8be597b06719fab6437", "fixed KW21 serializer crowd_core.hpp for typed byte comparison"): return
	root.gui_embed_subwindows = true
	var initial := _initial()
	if failed: return
	if not _checkpoint(initial.lab, SAVE): return
	var loaded: Dictionary = SiteStore.load_site(SAVE)
	if not _require(loaded.ok, "Store loads the shared starting checkpoint", loaded): return
	var source: TerrainData = loaded.data
	var source_before: PackedByteArray = _source_bytes(source)
	var live: TerrainLab = _restore(source)
	if failed: return
	var initial_live: Dictionary = _capture(live)
	live.restore_only = false
	live.movement_input_enabled = false
	var original_worker: Dictionary = live.site_controller.person_actions._person(initial.workers[0])
	var fatigue_before: float = float(live.site_controller.person_actions._body_get(original_worker, "fatigue"))
	for tick: int in 600:
		if not _live_frame(live): return
	if not _require(float(live.site_controller.person_actions._body_get(live.site_controller.person_actions._person(initial.workers[0]), "fatigue")) != fatigue_before, "live Native work fatigue really changes"): return
	print("CROWD_REPLAY_LIVE20_DONE")
	var target: float = SiteRuntime.now(live.terrain) * 60.0
	var expected: Dictionary = _capture(live)
	if failed: return
	if not _require(expected.features[initial.farm].production != source.site.features[initial.farm].production, "live farm genuinely advanced"): return
	if not _require(expected.inventory != source.site.inventory or expected.team_supply != source.site.team_supply, "real goods or supply changed"): return
	var cold: TerrainLab = _restore(source)
	if failed: return
	if not _same_original(_capture(cold), initial_live, "same_start"): return
	var pending: Dictionary = cold.replay_site_to(target, 0, 1)
	if not _require(pending.ok and pending.status == "PENDING" and pending.steps <= 1 and float(pending.pending) > 0.0, "bounded first pending slice", pending): return
	if not cold._region_point_pending.is_empty():
		var consumed: Dictionary = cold.consume_region_point(false)
		if not _require(consumed.ok, "consume the bounded first Native endpoint before the next command", consumed): return
	var retained: float = float(cold.terrain.site.simulation_settlement.last_settled_game_seconds)
	var wrong: Dictionary = cold.replay_site_to(target + 1.0, 0, 1)
	if not _require(not wrong.ok and wrong.code == "BUSY" and float(cold.terrain.site.simulation_settlement.last_settled_game_seconds) == retained, "fixed target cannot be replaced", wrong): return
	var complete: Dictionary = _replay(cold, target, pending)
	if failed: return
	if not _require(complete.ok and complete.status == "COMPLETE", "cold replay completed", complete): return
	var actual: Dictionary = _capture(cold)
	_dump("live", expected)
	_dump("cold", actual)
	print("CROWD_REPLAY_CLOCKS live=", SiteRuntime.now(live.terrain) * 60.0, " cold=", SiteRuntime.now(cold.terrain) * 60.0, " remainder=", live._action_time_remainder, " cold_steps_last=", complete.get("steps"))
	if not _same_original(actual, expected): return
	if not _require(_source_bytes(source) == source_before, "source remains byte identical after all branches"): return
	print("SHARED_STEP_CROWD_CORE_PARITY_OK target=", target)
	var settled: Dictionary = _capture(cold)
	var zero: Dictionary = cold.replay_site_to(target, 0, 1)
	if not _require(zero.ok and zero.steps == 0 and zero.pending == 0.0, "zero target does no work", zero): return
	if not _same_original(_capture(cold), settled): return
	if not _checkpoint(cold, SAVE + ".settled"): return
	var reopened: Dictionary = SiteStore.load_site(SAVE + ".settled")
	if not _require(reopened.ok, "Store reopens settled crowd", reopened): return
	var revisit: TerrainLab = _restore(reopened.data)
	if failed: return
	var before_revisit: Dictionary = _capture(revisit)
	var offline: Dictionary = revisit.replay_site_to(target, 0, 1)
	if not _require(offline.ok and offline.steps == 0 and offline.pending == 0.0, "reopen without world time does zero work", offline): return
	if not _same_original(_capture(revisit), before_revisit): return
	var blocked: TerrainLab = _restore(source)
	if failed: return
	blocked.terrain.site.paused = true
	var before_pause: PackedByteArray = _source_bytes(blocked.terrain)
	var paused_result: Dictionary = blocked.replay_site_to(target, 0, 1)
	if not _require(not paused_result.ok and paused_result.code == "PAUSED_SITE" and _source_bytes(blocked.terrain) == before_pause, "pause refuses without state change", paused_result): return
	if not _require(_source_bytes(source) == source_before, "all restore paths leave source bytes unchanged"): return
	for original: TerrainLab in [live, cold, revisit, blocked]: _close(original)
	if not _mixed_clock(source): return
	if not _require(_source_bytes(source) == source_before, "mixed-clock branch also leaves original source untouched"): return
	if not _retained_adapter(source, target, expected): return
	if not _require(_source_bytes(source) == source_before, "retained adapter leaves original source untouched"): return
	for lab: Variant in labs:
		if is_instance_valid(lab): lab.free()
	TerrainArmy.release_contact_source()
	finished = true
	print("SHARED_STEP_CROWD_OPTIONAL_NOT_PORTED fire=unresolved_native_parity death=not_ported; see CC193 report/probes")
	print("SITE_SHARED_STEP_REPLAY_CROWD_PASS checks=", checks, " all_other_native_bytes_exact=true numeric_tolerance=1e-6 native_game_dt=product_relative_1e-9 legacy_grid_removed=true")
	quit(0)
