extends SceneTree
const Query = preload("res://scripts/region_lab/region_faction_query.gd")
var checks := 0
var failed := false
var deadline: int

class FaultLog extends Logger:
	var mutex: Mutex = Mutex.new()
	var first := ""
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		mutex.lock()
		if first.is_empty(): first = "%s:%d %s %s %s" % [file, line, function, code, rationale]
		mutex.unlock()
	func read() -> String:
		mutex.lock()
		var result: Variant = first
		mutex.unlock()
		return result
var fault: FaultLog = FaultLog.new()

func check(value: bool, message: String) -> bool:
	if failed: return false
	checks += 1
	if not fault.read().is_empty(): value = false; message = fault.read()
	if Time.get_ticks_msec() > deadline: value = false; message = "unchanged 90s test deadline"
	if not value:
		failed = true
		push_error("REGION_FACTION_F1A_FAIL: " + message)
		quit(1)
	return value

func receipt(owner: String) -> Dictionary:
	return {"owner": owner, "source_generation": 1, "runtime_revision": 0, "checksum": "a".repeat(64), "as_of_game_seconds": 0.0, "complete": true}

func identity(state: Dictionary) -> Dictionary:
	return RegionTravel.prepare_identity(state).get("state", {})

func _initialize() -> void:
	OS.add_logger(fault)
	deadline = Time.get_ticks_msec() + 90000
	call_deferred("_run")

func _collect_ids_regression() -> bool:
	var mixed: Dictionary = {Vector2i(2, 4): {"owner_faction": 17}, 7: {"faction_id": 9}, true: [{"owner_faction": 11},
		{3: {"last_fall": {"from": 42, "to": 11}}}], "faction": -1,
		&"captor_faction": 13, "unrelated_integer": 99999}
	var before: PackedByteArray = var_to_bytes(mixed)
	var ids: Dictionary = {}
	var collected: Dictionary = Query.collect_ids(mixed, ids)
	if not check(collected.has("ok") and collected.ok and ids == {"9": true, "11": true, "42": true, "13": true, "17": true},
			"F1A_V4 mixed Vector2i/int/bool/text keys preserve recursive named/history IDs, not arbitrary integers"): return false
	if not check(var_to_bytes(mixed) == before, "F1A_V4 collector never changes original mixed-key owners"): return false
	for malformed: Variant in [{Vector2i(3, 5): [{"faction_id": "9"}]}, {8: [{"faction_id": "9"}]}, [{false: {"last_fall": {"from": "bad", "to": 1}}}],
			{4: {"owner_faction": Query.MAX_ID + 1}}]:
		var rejected: Dictionary = Query.collect_ids(malformed, {})
		if not check(rejected.has("ok") and not rejected.ok and rejected.get("code") == "CORRUPT_SAVE",
				"F1A_V4 malformed nested faction/history returns structured failure through every recursion"): return false
	var scalar_ids: Dictionary = {}
	for scalar: Variant in [null, 77, "faction_id"]:
		var scalar_result: Dictionary = Query.collect_ids(scalar, scalar_ids)
		if not check(scalar_result.has("ok") and scalar_result.ok and scalar_ids.is_empty(),
				"F1A_V4 scalar leaves always return ok without inventing IDs"): return false
	return true

func _run() -> void:
	if not _collect_ids_regression(): return
	var site := {"id": "site:A", "actors": {"player": {"person_id": 1, "faction_id": 2}}, "equipment_nations": {"legacy": {"military_head": 1, "members": [1], "standards": {}}}, "settlement": {"owner_faction": 2, "fall_record": {"last_fall": {"from": 55, "to": 2}}}, "organization_refs": {"remote_people": {"7": {"faction_id": 80}}}}
	var party := {"id": "party:A", "actors": {"npc": {"person_id": 7, "faction_id": 900}}, "equipment_nations": {}}
	var original: PackedByteArray = var_to_bytes([site, party])
	var states: Array[Dictionary] = [site, party]
	var receipts: Array[Dictionary] = [receipt("site:A"), receipt("party:A")]
	var migration: Variant = Query.migration(states, receipts, [3000], {}, 0.0, true)
	if not check(migration.ok and migration.registry.next_faction_id == 3001, "FA03 reserved ID high water"): return
	var party_max: Variant = Query.migration(states, receipts, [], {}, 0.0, true)
	if not check(party_max.ok and party_max.registry.next_faction_id == 901, "FA03 party-only maximum sets actual cursor"): return
	var registry: Dictionary = migration.registry
	if not check(var_to_bytes([site, party]) == original and not site.equipment_nations.legacy.has("faction_id"), "FA01 unmapped legacy/person/history unchanged"): return
	if not check(registry.entries.has("900") and registry.entries.has("80") and registry.entries.has("55"), "FA03 party-only/remote/history max included"): return
	if not check(Query.display(registry, 900).name == "勢力 900" and Query.display({}, 2).name == "勢力 2", "FA02 raw N never N+1"): return
	var palette: Variant = SiteEquipmentOrders.npc_palette_id(2)
	if not check(registry.entries["2"].color == str(SiteRuntime.EquipmentDye.PRESETS[palette].colors.armor), "FA02 legacy flag original palette"): return
	if not check(Query.display(registry, 2).counts == null and not Query.display(registry, 2).coverage_complete, "FA30 UNKNOWN never zero"): return
	if not check(not Query.migration(states, receipts, [], {}, 0.0, false).ok and not Query.migration(states, [receipt("site:A")], [], {}, 0.0, true).ok, "FA21 incomplete scan rejected"): return
	var unknown: Variant = registry.duplicate(true)
	unknown.version = 99
	if not check(Query.validate(unknown, 0.0).code == "SAVE_VERSION", "FA21 unknown registry schema"): return
	var exhausted: Variant = Query.migration(states, receipts, [Query.MAX_ID], {}, 0.0, true)
	if not check(exhausted.ok and Query.allocate(exhausted.registry, int(exhausted.registry.revision), 0.0).code == "FACTION_ID_EXHAUSTED", "FA03 exhausted cursor no wrap"): return
	var allocated: Variant = Query.allocate(registry, int(registry.revision), 0.0)
	if not check(allocated.ok and allocated.faction_id == 3001 and Query.allocate(allocated.registry, int(registry.revision), 0.0).code == "CONFLICT", "FA03 revision CAS candidates"): return
	var merged_active: Variant = registry.duplicate(true)
	merged_active.entries["55"].status = "merged"
	merged_active.entries["55"].ended_at = 0.0
	merged_active.entries["55"].merged_into = 2
	if not check(Query.validate(merged_active, 0.0).ok and Query.active(merged_active, 55).faction_id == 2, "historical alias resolves active terminal without body mutation"): return
	var historic: Variant = registry.duplicate(true)
	historic.entries["2"].status = "extinct"
	historic.entries["2"].ended_at = 0.0
	historic.entries["55"].status = "merged"
	historic.entries["55"].merged_into = 2
	historic.entries["55"].ended_at = 0.0
	if not check(Query.validate(historic, 0.0).ok and Query.resolve(historic, 55).faction_id == 2 and not Query.active(historic, 55).ok and not Query.active(historic, 2).ok, "FA03 tombstones resolve historical extinct endpoint; active refuses"): return
	historic.entries["55"].merged_into = 55
	if not check(not Query.validate(historic, 0.0).ok, "FA03 merged self rejected"): return
	historic.entries["55"].merged_into = 9999
	if not check(not Query.validate(historic, 0.0).ok, "FA03 missing endpoint rejected"): return
	historic.entries["2"].status = "merged"
	historic.entries["2"].merged_into = 55
	historic.entries["55"].merged_into = 2
	if not check(not Query.validate(historic, 0.0).ok, "FA03 cycle rejected"): return
	var nation_state: Dictionary = identity({"id": "site:N", "actors": {"player": {"person_id": 1, "faction_id": 2}}, "equipment_nations": {"N": {"offices": SiteOffices.default_offices("nation", 1), "members": [1], "standards": {}}}})
	var binding: Variant = SiteEquipmentOrders.prepare_faction_nation(nation_state, "N", 2)
	if not check(binding.ok and not nation_state.equipment_nations.N.has("faction_id"), "explicit binding detached; no office/member mutation"): return
	var bound: Variant = registry.duplicate(true)
	bound.entries["2"].nation_ref = binding.state.travel_identity.refs.nation.N.duplicate(true)
	bound.entries["2"].erase("duty_ai")
	var bound_states: Array[Dictionary] = [binding.state]
	if not check(Query.validate(bound, 0.0).ok and Query.reciprocal(bound, bound_states).ok, "Store/Region reciprocal formal nation"): return
	if not check(Query.bound_faction(bound, binding.state, "N").ok and Query.bound_faction(registry, site, "legacy").code == "NO_FORMAL_NATION", "formal query denies unmapped legacy authority"): return
	if not check(not Query.reciprocal(bound, []).ok, "missing nation owner rejected"): return
	var duplicate: Dictionary = binding.state.duplicate(true)
	duplicate.equipment_nations.other = {"military_head": 7, "members": [7], "standards": {}, "faction_version": 1, "faction_id": 2}
	duplicate.actors.npc = {"person_id": 7, "faction_id": 2}
	duplicate = identity(duplicate)
	if not check(not SiteEquipmentOrders.valid_nations(duplicate.equipment_nations, {}, RegionTravel._body_records(duplicate), duplicate), "Store local duplicate faction rejected"): return
	var mismatch: Dictionary = binding.state.duplicate(true)
	mismatch.actors.player.faction_id = 3
	if not check(not SiteEquipmentOrders.valid_nations(mismatch.equipment_nations, {}, RegionTravel._body_records(mismatch), mismatch), "formal head faction mismatch rejected without appointment"): return
	if not check(not Query.nation_schema({"faction_version": 1, "faction_id": 2}, "trial_team_1"), "trial never formal binding"): return
	var creating: Variant = SiteEquipmentOrders.prepare_faction_nation({"id": "site:C", "actors": {"player": {"person_id": 1, "faction_id": 2}}, "equipment_nations": {}}, "C", 2, {"offices": SiteOffices.default_offices("nation", 1), "members": [1], "standards": {}})
	if not check(creating.ok and creating.state.equipment_nations.C.faction_id == 2, "explicit original nation creation; no inferred members"): return
	var maps := {"nation": {"N": "arrived_N"}}
	var remapped: Variant = RegionTravel._remap_content(binding.state, maps)
	if not check(not remapped.is_empty() and remapped.equipment_nations.arrived_N.faction_id == 2 and remapped.travel_identity.refs.nation.arrived_N == binding.state.travel_identity.refs.nation.N, "FA20 original typed nation ref survives mapping"): return
	var missing_nation: Variant = remapped.duplicate(true)
	missing_nation.equipment_nations.erase("arrived_N")
	var refusal_bytes: PackedByteArray = var_to_bytes([binding.state, missing_nation, maps])
	if not check(not RegionTravel._faction_nations_remapped(binding.state, missing_nation, maps) and var_to_bytes([binding.state, missing_nation, maps]) == refusal_bytes, "FA20 missing mapped nation refuses without script error or mutation"): return
	if not check(not RegionTravel._faction_nations_remapped(binding.state, remapped, {"nation": {}}), "FA20 absent mapping cannot index absent original nation key"): return
	var missing_ref: Variant = remapped.duplicate(true)
	missing_ref.travel_identity.refs.nation.erase("arrived_N")
	if not check(not RegionTravel._faction_nations_remapped(binding.state, missing_ref, maps), "FA20 missing mapped typed nation ref refuses safely"): return
	var after_states: Array[Dictionary] = [remapped]
	if not check(Query.reciprocal(bound, after_states).ok, "FA20 reciprocal mapping locator changes only"): return
	var last := {"from": 2, "to": 55, "leader": 1, "minute": 10}
	var last_bytes: PackedByteArray = var_to_bytes(last)
	if not check(not SiteSettlement.valid_last_fall(last, 2, 1, 20) and SiteSettlement.valid_last_fall(last, 2, 2, 20) and var_to_bytes(last) == last_bytes, "versioned last_fall history not rewritten"): return
	if not check(not SiteSettlement.valid_last_fall(last, 2, 99, 20) and not SiteSettlement.valid_last_fall(last, 2, 2, 5), "unknown/future historical schema refused"): return
	var folder: Variant = "user://tests/faction_f1a_" + Crypto.new().generate_random_bytes(8).hex_encode()
	var slot: RegionSaveSlot = RegionSaveSlot.new()
	slot.folder = folder
	slot.source = RegionData.new()
	slot.pin = {"format": 1, "world_instance_id": "test", "slot_id": "test", "atlas_id": "test", "base_revision": "test", "manifest_sha256": "a".repeat(64), "ramp_rule_revision": "test", "grid_contract_version": 1}
	var recovered: Variant = slot._recover_control()
	if not check(recovered.ok, "original empty Slot recovery"): return
	var published: Variant = slot._publish({}, slot.control)
	if not check(published.ok and slot._marker.format == 2 and slot.control.has("faction_registry"), "FA09 registry publishes on original common marker"): return
	var marker_path: Variant = folder.path_join("commits/%020d.json" % 1)
	var marker_sha: String = FileAccess.get_sha256(marker_path)
	var before_control: PackedByteArray = var_to_bytes(slot.control)
	var old_clock := {"logical_game_seconds": 0.0, "active_site_id": ""}
	var bad: Variant = slot.control.duplicate(true)
	bad.faction_registry.version = 99
	if not check(not slot._publish({}, bad).ok and FileAccess.get_sha256(marker_path) == marker_sha and var_to_bytes(slot.control) == before_control and not FileAccess.file_exists(folder.path_join("commits/%020d.json" % 2)), "FA21 failed original publish no partial marker/runtime write"): return
	var roundtrip: Variant = slot.region_commit_control(1)
	if not check(roundtrip.ok and roundtrip.control.faction_registry == slot.control.faction_registry, "FA09 original Variant readback registry"): return
	var legacy_clock: Variant = slot._publish({}, old_clock)
	if not check(legacy_clock.ok and slot.control.has("faction_registry"), "all legacy control writer preserves registry"): return
	var data: TerrainData = TerrainData.new()
	data.site = {"id": "site:test", "actors": {}}
	slot.control.active_site_id = "site:test"
	var revision: int = int(slot.control.faction_registry.revision)
	var creation: Variant = slot.prepare_faction_creation(data, revision, [4000])
	if not check(creation.ok and creation.faction_id == 4001, "Slot explicit reservations actual allocator path"): return
	slot._marker.generation = int(slot._marker.generation) + 1
	if not check(slot.checkpoint_faction_creation(data, creation, {}, {}).code == "CONFLICT", "Slot actual stale-generation commit rejected before capture/write"): return
	slot._marker.generation = int(slot._marker.generation) - 1
	slot.control.faction_registry.revision = revision + 1
	if not check(slot.checkpoint_faction_creation(data, creation, {}, {}).code == "CONFLICT", "Slot actual registry CAS rejects competing creation"): return
	var document_path: Variant = folder.path_join("travel/unknown/party.json")
	var payload: Dictionary = {"version": 99, "encoding": "godot_var_v1", "pin": slot.pin, "party": "unknown"}
	var write: Variant = slot._write_new_document(document_path, payload)
	if not check(write.ok, "isolated bad party schema fixture"): return
	var journey: Dictionary = {"kind": RegionTravel.KIND, "party_path": "travel/unknown/party.json", "party_sha256": FileAccess.get_sha256(document_path)}
	slot.control = slot.region_commit_control(2).control
	var scan: Variant = slot._publish({}, slot.control, "", journey)
	if not check(not scan.ok and scan.code == "SAVE_VERSION" and FileAccess.get_sha256(marker_path) == marker_sha, "FA21 unknown party document schema preserves marker"): return
	var unknown_party: Dictionary = {"version": 99, "party_id": "unknown", "content": identity({"id": "party:unknown", "actors": {}, "equipment_nations": {}})}
	var version_path := "travel/unknown/body_version.json"
	var version_document: Variant = slot._write_new_document(folder.path_join(version_path), {"version": 1, "token": "unknown", "encoding": "godot_var_v1", "pin": slot.pin, "party": Marshalls.raw_to_base64(var_to_bytes(unknown_party))})
	if not check(version_document.ok, "unknown inner party version fixture"): return
	var unknown_journey: Dictionary = {"kind": RegionTravel.KIND, "party_path": version_path, "party_sha256": FileAccess.get_sha256(folder.path_join(version_path))}
	if not check(slot._publish({}, slot.control, "", unknown_journey).code == "SAVE_VERSION" and not FileAccess.file_exists(folder.path_join("commits/%020d.json" % 3)), "FA21 unknown inner party schema no partial marker"): return
	journey.party_sha256 = "b".repeat(64)
	if not check(slot._faction_scan({}, slot.control, journey, slot.faction_registry_view(), [], false).code == "CORRUPT_SAVE", "FA21 party bad checksum rejects complete scan"): return
	var store_path: Variant = folder.path_join("bad_site.json")
	var bad_site: Variant = slot._write_new_document(store_path, {"format": 999, "terrain_version": 1, "environment_version": SiteEnvironment.VERSION, "state": {}, "parameters": {}})
	if not check(bad_site.ok and SiteStore._read(store_path).code == "SAVE_VERSION", "FA21 unknown Site schema original reader"): return
	var file: FileAccess = FileAccess.open(store_path, FileAccess.WRITE)
	if not check(file != null, "bad checksum fixture file"): return
	file.store_string(JSON.stringify({"payload": "{}", "checksum": "a".repeat(64)}))
	file.close()
	if not check(SiteStore._read(store_path).code == "CORRUPT_SAVE", "FA21 Site bad checksum original reader"): return
	if not check(fault.read().is_empty() and Time.get_ticks_msec() <= deadline, "FA36 no hidden engine errors or relaxed deadline"): return
	print("REGION_FACTION_F1A_PASS: ", checks, " source/candidate/empty-Slot boundaries only; no F1b/F2/F3, Native, GPU, performance or release claim")
	quit(0)
