extends "res://scripts/tests/site_wildlife_capture_test.gd"
## ECO13 supplement. Original fixed-resource rules and livestock owners only.
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Adapter = preload("res://scripts/region_lab/region_terrain_adapter.gd")
var conservation_output := ""
var conservation_started := false
var conservation_finished := false
var conservation_groups := 0

func _initialize() -> void:
	conservation_output = "res://.godot-temp/site_ecology_base_conservation/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if conservation_started and not conservation_finished:
		printerr("SITE_ECOLOGY_BASE_CONSERVATION_FAILED: assertion interrupted the synchronous test")
		quit(1)
	return false

func _run() -> void:
	conservation_started = true
	_check_fixed_absence(0)
	_check_fixed_absence(1)
	_check_livestock_isolation()
	assert(conservation_groups == 3, "A base conservation helper did not finish")
	conservation_finished = true
	print("SITE_ECOLOGY_BASE_CONSERVATION_PASS empty_fixed_base_and_absent_species_stay_absent=true original_fixed_loader_store_roundtrip=true policy_and_natural_recovery_preserve_original_livestock_and_cargo=true; focused ECO13 supplement, no new generation rule, GPU or performance claim")
	quit(0)

func _fixed_fixture(category: int) -> TerrainData:
	# Same 100x100 synthetic land fixture as region_lab_resource_contract_test.
	var data := TerrainData.new()
	data.allocate(Vector2i(100, 100))
	data.height_levels.fill(2)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.water_kind.resize(10000)
	data.water_body.resize(10000)
	data.water_body.fill(-1)
	data.spawn_cell = Vector2i(20, 50)
	var cover := PackedByteArray()
	cover.resize(100)
	cover.fill(category)
	var heights := PackedFloat32Array()
	heights.resize(10000)
	heights.fill(0.0 if category == 0 else 3850.0)
	var coordinate := Vector2i(37, 91)
	Env.populate_fixed_resources(data, cover, coordinate, heights)
	var resource_hash := JSON.stringify(data.resource_base, "", true, true).sha256_text()
	data.parameters = TerrainPreset.defaults(data.preset)
	data.parameters["max_height"] = 5
	data.parameters["micro_strength"] = 0.0
	data.parameters["composition"] = "fixed_geography"
	# Explicit fixture pin, admitted by the same Store fixed-base contract as
	# site_bridge_contract_test; it is not presented as a real atlas manifest.
	data.parameters["fixed_base"] = {"base_kind": "fixed_geography", "atlas_id": Grid.ATLAS_ID,
		"site_id": Grid.site_id(Grid.ATLAS_ID, coordinate), "site": [coordinate.x, coordinate.y],
		"grid_contract_version": 1, "base_revision": "ecology_absence_fixture_v1_" + str(category),
		"manifest_sha256": "e".repeat(64), "terrain_fingerprint": data.fingerprint(),
		"ramp_rule_revision": Adapter.RAMP_RULE_REVISION, "resource_layer_sha256": "f".repeat(64),
		"resource_rule_revision": Env.FIXED_RESOURCE_RULE, "resource_fingerprint": resource_hash}
	return data

func _fixed_copy(data: TerrainData) -> TerrainData:
	# Exact base copy follows the original bridge contract loader. Never recreate
	# resources during load, and never return the mutable caller as the loaded Site.
	var result := TerrainData.new()
	result.allocate(data.size)
	for field: String in ["height_levels", "surface_types", "flags", "cliff_drops", "ramp_edges", "detail_variation",
		"water_kind", "water_body", "fertility", "moisture", "drainage", "foundation", "groundwater"]:
		result.set(field, data.get(field).duplicate())
	result.spawn_cell = data.spawn_cell
	result.preset = data.preset
	result.seed_value = data.seed_value
	result.parameters = data.parameters.duplicate(true)
	result.resource_base = data.resource_base.duplicate(true)
	return result

func _check_fixed_absence(category: int) -> void:
	var data := _fixed_fixture(category)
	assert(data.resource_base.is_empty() == (category == 0))
	for resource: Dictionary in data.resource_base.values():
		assert(int(resource.kind) in [Env.Kind.FOOD, Env.Kind.HERB], "Original alpine fixture must have plants and no fish, wildlife or timber")
	var base := _fixed_copy(data)
	var fingerprint := data.fingerprint()
	var resource_bytes := var_to_bytes(data.resource_base)
	var pin: Dictionary = data.parameters.fixed_base.duplicate(true)
	Env.initialize(data, str(pin.site_id))
	assert(Env.ecology_active(data) and Runtime.ecology_reconcile(data).ok)
	var missing := "%d:%d" % [Env.Kind.FISH, data.index(data.spawn_cell)]
	var before := var_to_bytes(data.site)
	assert(Runtime.ecology_reconcile(data, [missing]).code == "NO_TARGET")
	for mode: String in ["general", "protected", "sustainable"]:
		assert(not Runtime.ecology_set_modes(data, [missing], mode).ok)
	assert(Runtime.harvest(data, missing, data.spawn_cell, {}, "restore").code == "NO_TARGET")
	assert(var_to_bytes(data.site) == before, "Absent-source commands published mutable state")
	Runtime.advance(data, 4320.125)
	assert(var_to_bytes(data.resource_base) == resource_bytes and data.fingerprint() == fingerprint)
	var loader := func(saved: Dictionary) -> Dictionary:
		if not Store._same_fixed_base(saved, pin): return Runtime.fail("SAVE_VERSION")
		return {"ok": true, "data": _fixed_copy(base), "base": pin.duplicate(true)}
	var path := conservation_output.path_join("absence_%d.json" % category)
	var saved := Store.save(data, path)
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(path, loader, 1, true)
	assert(loaded.ok, str(loaded))
	assert(loaded.data.parameters.fixed_base == pin and loaded.data.fingerprint() == fingerprint)
	assert(Runtime.ecology_reconcile(loaded.data).ok)
	Runtime.advance(loaded.data, 1440.0)
	assert(var_to_bytes(loaded.data.resource_base) == resource_bytes and var_to_bytes(base.resource_base) == resource_bytes)
	assert(not loaded.data.site.changes.has(missing), "Store or time advancement invented an absent source delta")
	conservation_groups += 1

func _livestock_state(data: TerrainData, pasture: String, ranch: String) -> PackedByteArray:
	return var_to_bytes([data.site.features[pasture].residents, data.site.features[ranch].residents,
		data.site.manual.cargo, data.site.worker.cargo, data.site.inventory.get("horse", 0), data.site.inventory.get("sheep", 0)])

func _check_livestock_isolation() -> void:
	var data := _map()
	var resource_bytes := var_to_bytes(data.resource_base)
	var pasture := _build(data, "pasture")
	var ranch := _build(data, "horse_ranch")
	var keys: Array[String] = []
	for species: String in ["horse", "sheep"]:
		for key: String in data.resource_base:
			var resource := Env.resource(data, key)
			if Runtime.capturable_species(resource) == species and not bool(resource.cleared) \
					and Env.habitat_capacity(data, key) == int(resource.capacity) and not Env.work_cells(data, key).is_empty():
				keys.append(key)
				break
	assert(keys.size() == 2 and not pasture.is_empty() and not ranch.is_empty())
	var before := _livestock_state(data, pasture, ranch)
	assert(Runtime.ecology_set_modes(data, keys, "general").ok)
	assert(_livestock_state(data, pasture, ranch) == before)
	for key: String in keys:
		assert(Runtime.harvest(data, key, Env.work_cells(data, key)[0], data.site.manual.cargo, "capture").ok)
	assert(data.site.manual.cargo == {"horse": 1, "sheep": 1})
	before = _livestock_state(data, pasture, ranch)
	assert(Runtime.ecology_set_modes(data, keys, "protected").ok)
	assert(Runtime.ecology_reconcile(data, keys).ok and _livestock_state(data, pasture, ranch) == before)
	var due := maxi(int(Env.resource(data, keys[0]).next_recovery), int(Env.resource(data, keys[1]).next_recovery))
	Runtime.advance(data, float(due) - Runtime.now(data))
	for key: String in keys:
		assert(int(Env.resource(data, key).remaining) == int(data.resource_base[key].capacity), "Original wildlife must actually recover in this cross-owner check")
	assert(_livestock_state(data, pasture, ranch) == before)
	assert(Runtime.ecology_set_modes(data, keys, "general").ok and _livestock_state(data, pasture, ranch) == before)
	assert(var_to_bytes(data.resource_base) == resource_bytes)
	var path := conservation_output.path_join("original_livestock.json")
	var saved := Store.save(data, path)
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(path, Callable(), 1, true)
	assert(loaded.ok, str(loaded))
	assert(_livestock_state(loaded.data, pasture, ranch) == before and var_to_bytes(loaded.data.resource_base) == resource_bytes)
	conservation_groups += 1
