extends "res://scripts/tests/region_initial_world_transaction_test.gd"
## Actual checksummed fixture -> RegionData -> full Slot pin -> Store save/load.
## No prior-run files, fake source owner, helper-only assertions or Lab gameplay.
const LAND_RULE := "terrain_mapped_potential_v1"

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 150000
	_run.call_deferred()

func _land_snapshot(data: TerrainData) -> PackedByteArray:
	return var_to_bytes([data.parameters, data.site, data.fingerprint(), data.resource_base,
		data.fertility, data.moisture, data.drainage, data.foundation, data.groundwater,
		data.get_meta(&"fire_owner_checkpoint", {})])

func _land_fixture(source: RegionData, label: String) -> Dictionary:
	var slot := RegionSaveSlot.new()
	var world := "land_rule_%d_%d_%s" % [OS.get_process_id(), Time.get_ticks_usec(), label]
	var mapped := slot.open_map(source, world, "main")
	if not _check(mapped.ok, "Original source and full Slot pin: " + label, mapped): return {}
	var opened := slot.open_site(START)
	if not _check(opened.ok and bool(opened.get("interactive", false)), "Original interactive fixed Site: " + label, opened): return {}
	var data: TerrainData = opened.data
	var path := root_path.path_join(label + ".json")
	var saved := Store.save(data, path)
	if not _check(saved.ok, "Actual Store.save accepts " + label, saved): return {}
	var loader := func(_base: Dictionary) -> Dictionary: return source.make_terrain_data(START.x, START.y)
	var cold := Store.load_site(path, loader, 1, true)
	if not _check(cold.ok, "Actual Store.load_site accepts " + label, cold): return {}
	if not _check(cold.data.parameters.has("fixed_land_condition_rule") == source.manifest.has("land_condition_rule")
		and cold.data.parameters.get("fixed_land_condition_rule") == source.manifest.get("land_condition_rule")
		and cold.data.fingerprint() == data.fingerprint() and cold.data.site.world_pin == data.site.world_pin,
		"Real source rule, geometry and complete world pin survive " + label): return {}
	return {"data":data, "path":path, "loader":loader, "source":source}

func _reject_land_save(f: Dictionary, bad: TerrainData, label: String) -> bool:
	var before := _land_snapshot(bad)
	var live_before := _land_snapshot(f.data)
	var archive := FileAccess.get_file_as_bytes(f.path)
	var absent := root_path.path_join("reject_" + label + ".json")
	if not _check(not FileAccess.file_exists(absent), "Unique absent negative target " + label): return false
	var rejected := Store.save(bad, absent)
	if not _check(not rejected.ok and rejected.code == "SAVE_VERSION", "Malformed declaration refuses save " + label, rejected): return false
	if not _check(not FileAccess.file_exists(absent) and not FileAccess.file_exists(absent + ".tmp")
		and not FileAccess.file_exists(absent + ".bak"), "Rejection creates no target/temp/backup " + label): return false
	if not _check(_land_snapshot(bad) == before and _land_snapshot(f.data) == live_before
		and FileAccess.get_file_as_bytes(f.path) == archive, "Rejected save preserves candidate/live/archive bytes " + label): return false
	var overwrite := Store.save(bad, f.path)
	return _check(not overwrite.ok and overwrite.code == "SAVE_VERSION"
		and FileAccess.get_file_as_bytes(f.path) == archive and not FileAccess.file_exists(f.path + ".tmp")
		and not FileAccess.file_exists(f.path + ".bak") and _land_snapshot(bad) == before
		and _land_snapshot(f.data) == live_before, "Rejected overwrite preserves old archive and scene " + label, overwrite)

func _land_bad_saves(f: Dictionary) -> void:
	for value: Variant in [false, 1, [], {}, null, "", "unknown_potential_v1", "mapped_terrain_potential_v1", StringName(LAND_RULE)]:
		var loaded := Store.load_site(f.path, f.loader, 1, true)
		if not _check(loaded.ok, "Bad Variant starts from true checked load", loaded): return
		var bad: TerrainData = loaded.data
		# Set after the real cold read; JSON/clone must not turn StringName into String.
		bad.parameters.fixed_land_condition_rule = value
		bad.parameters.fixed_base.land_condition_rule = value
		_check(typeof(bad.parameters.fixed_land_condition_rule) == typeof(value)
			and typeof(bad.parameters.fixed_base.land_condition_rule) == typeof(value), "Original invalid Variant types retained")
		if not _reject_land_save(f, bad, "matching_%d_%d" % [typeof(value), checks]): return
	for attack: String in ["parameter_only", "base_only", "parameter_without_base", "parameter_name", "base_name", "mismatch"]:
		var loaded := Store.load_site(f.path, f.loader, 1, true)
		if not _check(loaded.ok, "Presence/type negative starts from true checked load", loaded): return
		var bad: TerrainData = loaded.data
		match attack:
			"parameter_only": bad.parameters.fixed_base.erase("land_condition_rule")
			"base_only": bad.parameters.erase("fixed_land_condition_rule")
			"parameter_without_base": bad.parameters.erase("fixed_base")
			"parameter_name": bad.parameters.fixed_land_condition_rule = StringName(LAND_RULE)
			"base_name": bad.parameters.fixed_base.land_condition_rule = StringName(LAND_RULE)
			"mismatch": bad.parameters.fixed_land_condition_rule = "unknown_potential_v1"
		if not _reject_land_save(f, bad, attack): return

func _land_bad_loads(f: Dictionary) -> void:
	var decoded := Store._read(f.path)
	if not _check(decoded.ok, "Read actual saved checksum envelope", decoded): return
	var archive := FileAccess.get_file_as_bytes(f.path)
	var live_before := _land_snapshot(f.data)
	for attack: String in ["matching_unknown", "matching_false", "parameter_only", "base_only", "erase_both", "fingerprint", "erase_full_pin"]:
		var payload: Dictionary = decoded.payload.duplicate(true)
		match attack:
			"matching_unknown":
				payload.parameters.fixed_land_condition_rule = "unknown_potential_v1"
				payload.parameters.fixed_base.land_condition_rule = "unknown_potential_v1"
			"matching_false":
				payload.parameters.fixed_land_condition_rule = false
				payload.parameters.fixed_base.land_condition_rule = false
			"parameter_only": payload.parameters.fixed_base.erase("land_condition_rule")
			"base_only": payload.parameters.erase("fixed_land_condition_rule")
			"erase_both":
				payload.parameters.erase("fixed_land_condition_rule")
				payload.parameters.fixed_base.erase("land_condition_rule")
			"fingerprint": payload.parameters.fixed_base.terrain_fingerprint = "0".repeat(64)
			"erase_full_pin": payload.state.erase("world_pin")
		var body := JSON.stringify(payload, "", true, true)
		var record := _asset("load_" + attack + ".json", JSON.stringify({"checksum":body.sha256_text(), "payload":body}, "", true, true).to_utf8_buffer())
		if record.is_empty(): return
		var target := root_path.path_join(str(record.path))
		var negative_bytes := FileAccess.get_file_as_bytes(target)
		var rejected := Store.load_site(target, f.loader, 1, true)
		if not _check(not rejected.ok and rejected.code == "SAVE_VERSION"
			and FileAccess.get_file_as_bytes(f.path) == archive and FileAccess.get_file_as_bytes(target) == negative_bytes
			and _land_snapshot(f.data) == live_before, "True source rejects checksum-valid " + attack + " without archive/scene mutation", rejected): return

func _run() -> void:
	var legacy := _fixed_source() # Existing helper writes fresh checksummed tiles/metadata.
	if legacy == null: _finish("legacy fixture unavailable"); return
	var legacy_path := manifest_path
	var original_bytes := FileAccess.get_file_as_bytes(legacy_path)
	var metadata: Dictionary = JSON.parse_string(original_bytes.get_string_from_utf8())
	metadata.land_condition_rule = LAND_RULE
	metadata.base_revision = "store-land-rule-save-fixture-v1"
	var record := _asset("manifest.land-rule.json", JSON.stringify(metadata, "", true, true).to_utf8_buffer())
	if record.is_empty(): _finish("named source metadata unavailable"); return
	var source := RegionData.new()
	var accepted := source.load_manifest(root_path.path_join(str(record.path)))
	if not _check(accepted.ok, "Actual RegionData admits named-rule source", accepted): _finish(); return
	var old := _land_fixture(legacy, "legacy")
	var fresh := _land_fixture(source, "named")
	if old.is_empty() or fresh.is_empty(): _finish("positive roundtrip failed"); return
	_land_bad_saves(fresh)
	if not failures.is_empty(): _finish("save rejection phase failed"); return
	_land_bad_loads(fresh)
	if not failures.is_empty(): _finish("load rejection phase failed"); return
	var generated := TerrainGenerator.generate(0, 581)
	Env.initialize(generated, "generated-land-rule-legacy")
	var generated_path := root_path.path_join("generated.json")
	var saved := Store.save(generated, generated_path)
	if _check(saved.ok, "Rule-free generated save remains admitted", saved):
		var cold := Store.load_site(generated_path)
		_check(cold.ok, "Rule-free generated load remains admitted", cold)
	_check(FileAccess.get_file_as_bytes(legacy_path) == original_bytes
		and legacy.manifest_hash == FileAccess.get_sha256(legacy_path), "Original legacy source unchanged")
	_finish()

func _finish(reason: String = "") -> void:
	if finished: return
	finished = true
	if not reason.is_empty(): failures.append(reason)
	print("SITE_STORE_LAND_CONDITION_RULE_SAVE_REPORT: " + JSON.stringify({"checks":checks, "failures":failures, "fixture":root_path}, "", true, true))
	print("SITE_STORE_LAND_CONDITION_RULE_SAVE_", "PASS" if failures.is_empty() else "FAILED", " scope=actual_store_save_load_checked_fixture_full_pin_legacy_no_gpu_or_source_release")
	quit(0 if failures.is_empty() else 1)
