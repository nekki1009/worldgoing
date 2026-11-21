extends SceneTree
## Real original Taiwan metadata/resource reader + full Slot/Store cold source
## contract. Candidate files must first be installed by the sole publisher in
## the isolated project. NOT birth, production, whole-Lab or FULL G06 proof.
const Atlas = preload("res://scripts/region_lab/region_data.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Slot = preload("res://scripts/region_lab/region_save_slot.gd")
const NEW_GEO := "res://assets/region_lab/earth_tw_tm2_121_v1_r4/manifest.terrain_mapped_potential_v1.json"
const NEW_RESOURCE := "res://assets/region_lab/earth_tw_resources_v1/manifest.terrain_mapped_potential_v1.json"
const RULE := "terrain_mapped_potential_v1"
const FIELDS: Array[String] = ["fertility", "moisture", "drainage", "foundation", "groundwater"]
const FOREST := Vector2i(1170, 13252) # Same original resource-contract source site.
var failed := false
var checks := 0
var tmp := ""
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	tmp = "user://g06_paired_source_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("G06 paired source fixture deadline")
		quit(1)
	return false

func _check(value: bool, message: String) -> bool:
	checks += 1
	if value: return true
	failed = true
	push_error(message)
	return false

func _soil(data: TerrainData) -> Dictionary:
	var result := {}
	for field: String in FIELDS: result[field] = data.get(field).duplicate()
	return result

func _source_state(source: RegionData) -> PackedByteArray:
	return var_to_bytes([source.manifest, source.manifest_hash, source.resource_manifest_hash,
		source.resource_rule_revision, source._resource_manifest, source._folder])

func _write(path: String, bytes: PackedByteArray) -> bool:
	if not _check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK, "Own unique source fixture folder"): return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null, "Own unique fixture file is writable"): return false
	file.store_buffer(bytes)
	file.close()
	return true

func _write_payload(path: String, payload: Dictionary) -> bool:
	var text := JSON.stringify(payload, "", true, true)
	return _write(path, JSON.stringify({"checksum": text.sha256_text(), "payload": text}, "", true, true).to_utf8_buffer())

func _unregistered_source_refuses(source: RegionData) -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NEW_GEO))
	# Real checksummed metadata files are copied unchanged into this test folder.
	# Height tiles are lazy and never sampled from this rejected source.
	for field: String in ["summary", "content_scope", "source_quality"]:
		if not parsed.has(field): continue
		var record: Dictionary = parsed[field]
		if not _write(tmp.path_join(str(record.path)), FileAccess.get_file_as_bytes(NEW_GEO.get_base_dir().path_join(str(record.path)))): return
	parsed.base_revision = str(parsed.base_revision) + "-unregistered-test-only"
	var path := tmp.path_join("unregistered_geo.json")
	if not _write(path, JSON.stringify(parsed, "", true, true).to_utf8_buffer()): return
	var before := _source_state(source)
	var rejected := source.load_manifest(path)
	_check(not rejected.ok and rejected.code == "MISSING_RESOURCE_PAIR" and _source_state(source) == before,
		"A changed official land Geo cannot silently drop its paired resources or replace the accepted atlas: " + str(rejected))

func _cold_guards(source: RegionData, slot: RegionSaveSlot, data: TerrainData, coordinate: Vector2i) -> void:
	var path := slot.site_path(coordinate)
	var saved := slot.save_site(data)
	if not _check(saved.ok, "Original full-pin Slot saves the actual paired source: " + str(saved)): return
	path = slot.site_path(coordinate)
	var archive_sha := FileAccess.get_sha256(path)
	var live_before := var_to_bytes([data.parameters, data.site, _soil(data)])
	var soil_before := _soil(data)
	var decoded := Store._read(path)
	if not _check(decoded.ok, "Original checksum payload decoder"): return
	var cold := slot.open_site(coordinate)
	if not _check(cold.ok, "Original paired Slot/Store cold read: " + str(cold)): return
	_check(_soil(cold.data) == soil_before and cold.data.parameters.fixed_base == data.parameters.fixed_base
		and cold.data.site.world_pin == data.site.world_pin, "True base rederivation retains five arrays and full resource/policy pin")
	var navigation := Env.navigation_for_state(cold.data, cold.data.site)
	_check(_soil(navigation) == soil_before, "Original detached navigation projection retains all five source arrays")
	for attack: String in ["parameter_only", "erase_parameter", "erase_both", "erase_pin", "minimal_pin", "downgrade_pin"]:
		var payload: Dictionary = decoded.payload.duplicate(true)
		match attack:
			"parameter_only": payload.parameters.fixed_land_condition_rule = "mapped_terrain_potential_v1"
			"erase_parameter": payload.parameters.erase("fixed_land_condition_rule")
			"erase_both":
				payload.parameters.erase("fixed_land_condition_rule")
				payload.parameters.fixed_base.erase("land_condition_rule")
			"erase_pin": payload.state.erase("world_pin")
			"minimal_pin": payload.state.world_pin = {"manifest_sha256": source.manifest_hash}
			"downgrade_pin":
				payload.state.world_pin.format = 1
				payload.state.world_pin.erase("technology_policy")
		var bad_path := tmp.path_join("cold_" + attack + ".json")
		if not _write_payload(bad_path, payload): return
		var rejected := Store.load_site(bad_path, func(base: Dictionary) -> Dictionary:
			return source.make_terrain_data(coordinate.x, coordinate.y), 1, true)
		_check(not rejected.ok and rejected.code == "SAVE_VERSION" and FileAccess.get_sha256(path) == archive_sha
			and var_to_bytes([data.parameters, data.site, _soil(data)]) == live_before,
			"Checksum-valid new-source " + attack + " refuses before scene/archive mutation: " + str(rejected))

func _real_level_component(source: RegionData, slot: RegionSaveSlot) -> void:
	# Real original Runtime level command, original finite payment/work endpoint.
	# This component excludes travel/Fatigue/whole-Lab/Slot clock proof.
	for preview: Dictionary in source.manifest.preview_sites:
		var coordinate := Vector2i(int(preview.site[0]), int(preview.site[1]))
		var opened := slot.open_site(coordinate)
		if not opened.ok or not opened.get("interactive", false): continue
		var data: TerrainData = opened.data
		data.site.inventory = {"wood": 100, "stone": 100, "tools": 5} # Named finite initial supply only.
		var base_soil := _soil(data)
		var started := {}
		var changed := -1
		for y: int in range(1, 99):
			for x: int in range(1, 98):
				var a := data.index(Vector2i(x, y))
				var b := data.index(Vector2i(x+1, y))
				if data.height_levels[a] == data.height_levels[b]: continue
				var cells: Array[int] = [a, b]
				var admitted := Runtime.preview_build(data, "level", cells, Callable(), {"owner_faction": 1})
				if not admitted.ok: continue
				changed = a if int(data.height_levels[a]) > int(data.height_levels[b]) else b
				started = Runtime.request_build(data, "level", cells, Callable(), {"owner_faction": 1})
				break
			if not started.is_empty(): break
		if started.is_empty(): continue
		if not _check(started.ok, "Original real unequal-height level request"): return
		var key := str(started.feature)
		var feature: Dictionary = data.site.features[key]
		var old_height := int(data.height_levels[changed])
		Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "construct", "cell": int(feature.entrance)}))
		data.site.worker.cell = int(feature.entrance) # Explicit original legacy worker station; no travel proof.
		data.site.worker.mode = "work"
		Runtime.advance(data, float(feature.work) + 1.0, true, false, Callable(), Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1)
		if not _check(not data.site.features.has(key) and int(data.height_levels[changed]) != old_height and data.site.terrain_changes.has(str(changed)),
			"Only the original completed paid level operation produces this real height delta"): return
		_check(_soil(data) == base_soil, "Source soil remains the immutable-base derivation after original Terraform")
		var saved := slot.save_site(data)
		if not _check(saved.ok, "Original level component can be cold-saved: " + str(saved)): return
		var cold := slot.open_site(coordinate)
		_check(cold.ok and cold.data.site.terrain_changes == data.site.terrain_changes
			and int(cold.data.height_levels[changed]) == int(data.height_levels[changed]) and _soil(cold.data) == base_soil,
			"Original Store derives soil from base BEFORE applying the true saved height delta")
		return
	_check(false, "No legal real unequal-height Terraform endpoint was found in the bounded six original preview Sites; no synthetic terrain substitute")

func _run() -> void:
	if not _check(FileAccess.file_exists(NEW_GEO) and FileAccess.file_exists(NEW_RESOURCE), "Sole publisher must install BOTH exact metadata candidates in the isolated project before this test"): quit(1); return
	var old_geo_sha := FileAccess.get_sha256(Atlas.DEFAULT_MANIFEST)
	var old_resource_sha := FileAccess.get_sha256(Atlas.RESOURCE_MANIFEST)
	var new_geo_sha := FileAccess.get_sha256(NEW_GEO)
	var new_resource_sha := FileAccess.get_sha256(NEW_RESOURCE)
	var old := Atlas.new()
	var fresh := Atlas.new()
	if not _check(old.load_manifest().ok and fresh.load_manifest(NEW_GEO).ok, "Original reader admits both complete exact geography/resource source pairs"): quit(1); return
	_check(old.manifest_hash == old_geo_sha and old.resource_manifest_hash == old_resource_sha
		and fresh.manifest_hash == new_geo_sha and fresh.resource_manifest_hash == new_resource_sha
		and fresh.resource_rule_revision == old.resource_rule_revision and fresh.manifest.land_condition_rule == RULE,
		"Both original paired SHAs are pinned; new eligibility never loses the original resource layer")
	var old_base := old.make_terrain_data(FOREST.x, FOREST.y)
	var new_base := fresh.make_terrain_data(FOREST.x, FOREST.y)
	if not _check(old_base.ok and new_base.ok, "Both true original forest source tiles rebuild through the real Adapter"): quit(1); return
	_check(old_base.data.fingerprint() == new_base.data.fingerprint() and old_base.data.resource_base == new_base.data.resource_base
		and old_base.data.water_kind == new_base.data.water_kind and old_base.data.water_body == new_base.data.water_body,
		"Paired source keeps exact geographic/resource/water base; fingerprint is geometry evidence only")
	Env.initialize(old_base.data, str(old_base.base.site_id))
	Env.initialize(new_base.data, str(new_base.base.site_id))
	for field: String in FIELDS:
		var old_values: PackedByteArray = old_base.data.get(field)
		_check(old_values.count(0) == old_values.size(), "Old missing-rule source still has original zero " + field)
	_check(_soil(new_base.data) != _soil(old_base.data) and new_base.data.moisture != old_base.data.moisture,
		"Explicit new game-potential source changes real source conditions/moisture; no surveyed soil or Eco acceptance claimed")
	_unregistered_source_refuses(fresh)
	var epoch := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var old_world := "g06_pair_old_" + epoch
	var new_world := "g06_pair_new_" + epoch
	var old_slot := Slot.new()
	var new_slot := Slot.new()
	if not _check(old_slot.open_map(old, old_world, "source").ok and new_slot.open_map(fresh, new_world, "source").ok, "Original separate Slot pins preserve old/new source coexistence"): quit(1); return
	var opened_old := old_slot.open_site(FOREST)
	var opened_new := new_slot.open_site(FOREST)
	if not _check(opened_old.ok and opened_new.ok and opened_old.interactive and opened_new.interactive, "Original interactive paired fixed Sites"): quit(1); return
	_check(old_slot.pin.resource_layer_sha256 == old_resource_sha and new_slot.pin.resource_layer_sha256 == new_resource_sha
		and int(new_slot.pin.format) == 2 and new_slot.pin.has("technology_policy"), "Full original Slot resource and default empty policy identity, never minimal fake pin")
	var old_saved := old_slot.save_site(opened_old.data)
	if not _check(old_saved.ok, "Original old full pin remains cold-save compatible"): quit(1); return
	var old_path := old_slot.site_path(FOREST)
	var old_sha := FileAccess.get_sha256(old_path)
	var mismatch_slot := Slot.new()
	var refused := mismatch_slot.open_map(fresh, old_world, "source")
	_check(not refused.ok and refused.code == "SAVE_VERSION" and FileAccess.get_sha256(old_path) == old_sha,
		"New source cannot rebind an old original full Slot or rewrite its old archive")
	_cold_guards(fresh, new_slot, opened_new.data, FOREST)
	_real_level_component(fresh, new_slot)
	_check(FileAccess.get_sha256(Atlas.DEFAULT_MANIFEST) == old_geo_sha and FileAccess.get_sha256(Atlas.RESOURCE_MANIFEST) == old_resource_sha
		and FileAccess.get_sha256(NEW_GEO) == new_geo_sha and FileAccess.get_sha256(NEW_RESOURCE) == new_resource_sha,
		"All old/new paired metadata source bytes remain unchanged")
	if failed: quit(1); return
	print("G06_PAIRED_SOURCE_ORIGINAL_READER_PIN_COLD_PASS: checks=", checks, "; source/Slot/Store/Terraform-component only; no birth/master/manufacture/whole-Lab/TaiwanGPU/FULL G06 acceptance")
	quit(0)
