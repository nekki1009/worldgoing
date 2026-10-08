extends SceneTree

const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Atlas = preload("res://scripts/region_lab/region_data.gd")
const Slot = preload("res://scripts/region_lab/region_save_slot.gd")
var _output := "res://.godot-temp/region_lab_contract"
var _started := false
var _finished := false

func _init() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if _started and not _finished:
		printerr("REGION_LAB_CONTRACT_FAILED: assertion interrupted the synchronous test")
		quit(1)
	return false

func _run() -> void:
	_started = true
	var coordinate_checks := _coordinates()
	assert(coordinate_checks == 126, "Coordinate checks aborted")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	var manifest := _fixture()
	var manifest_path := _output.path_join("manifest.json")
	_write(manifest_path, JSON.stringify(manifest).to_utf8_buffer())
	var source := Atlas.new()
	var loaded := source.load_manifest(manifest_path)
	assert(loaded.ok, str(loaded))
	assert(_memo_equivalence(source), "Site-scoped sampling changed public sampling values")
	assert(_scope_contract(manifest), "Content scope checks aborted")
	var overview := source.get_overview()
	assert(overview.ok and overview.width == 4 and overview.height == 4)
	assert(overview.classes == PackedByteArray(manifest.summary_test_bytes))
	assert(source.get_site_summary(98, 98).status == "missing_data")
	assert(source.make_terrain_data(98, 98).code == "MISSING_DATA")
	assert(source.get_site_summary(97, 98).code == "OUTSIDE_CONTENT")
	var snapshots: Dictionary = {}
	var ramp_checks := 0
	for site: Vector2i in [Vector2i(99, 99), Vector2i(100, 99), Vector2i(100, 100), Vector2i(99, 100)]:
		var result := source.make_terrain_data(site.x, site.y)
		assert(result.ok, str(result))
		var terrain: TerrainData = result.data
		assert(terrain.size == Vector2i(100, 100) and terrain.site.is_empty())
		assert(result.base.site_id == Grid.site_id(Grid.ATLAS_ID, site))
		assert(result.base.terrain_fingerprint == terrain.fingerprint())
		assert(terrain.parameters.fixed_base == result.base)
		assert(result.metadata.absolute_elevation_m.size() == 10000)
		assert(not result.metadata.height_levels_are_metres)
		snapshots[site] = terrain
		for y: int in range(100):
			for x: int in range(100):
				var cell := Vector2i(x, y)
				var index := terrain.index(cell)
				assert(terrain.height_levels[index] <= 5)
				for direction: int in range(4):
					var adjacent: Vector2i = cell + TerrainData.DIRECTIONS[direction]
					if not terrain.contains(adjacent):
						continue
					var next_index := terrain.index(adjacent)
					var difference := absi(int(terrain.height_levels[index]) - int(terrain.height_levels[next_index]))
					var pass_edge := (terrain.ramp_edges[index] & (1 << direction)) != 0
					var expected := terrain.is_walkable(cell) and terrain.is_walkable(adjacent) and (difference == 0 or (difference == 1 and pass_edge))
					assert(terrain.can_step(cell, adjacent) == expected)
					assert(terrain.can_step(cell, adjacent) == terrain.can_step(adjacent, cell))
					if (terrain.ramp_edges[index] & (1 << direction)) != 0:
						assert((terrain.ramp_edges[next_index] & (1 << ((direction + 2) % 4))) != 0)
						ramp_checks += 1
	assert(ramp_checks > 0)
	print("REGION_LAB_CONTRACT_PROGRESS initial_four_sites")
	for index: int in range(100):
		assert(_check_cross_edge(snapshots[Vector2i(99, 99)], Vector2i(99, index), snapshots[Vector2i(100, 99)], Vector2i(0, index), 1))
		assert(_check_cross_edge(snapshots[Vector2i(99, 99)], Vector2i(index, 0), snapshots[Vector2i(99, 100)], Vector2i(index, 99), 0))
	var stable := str(snapshots[Vector2i(99, 99)].fingerprint())
	for repeat: int in range(100):
		var site := Vector2i(99 + repeat % 2, 99 + Grid.floor_div(repeat, 2) % 2)
		var generated := source.make_terrain_data(site.x, site.y)
		assert(generated.ok and generated.data.fingerprint() == snapshots[site].fingerprint())
		assert(source.cache_stats().tiles <= Atlas.MAX_CACHE_TILES and source.cache_stats().bytes <= Atlas.MAX_CACHE_BYTES)
		if repeat % 25 == 24:
			print("REGION_LAB_CONTRACT_PROGRESS repeat_loads=", repeat + 1)
	assert(source.make_terrain_data(99, 99).data.fingerprint() == stable)
	assert(_quality_and_water_contract(manifest), "Source quality and water-body checks aborted")
	var boundary_data: TerrainData = source.make_terrain_data(99, 99).data
	SiteRuntime.rebuild_terrain_edges(boundary_data)
	assert(source.refresh_boundary(boundary_data, Vector2i(99, 99)).ok)
	assert(boundary_data.fingerprint() == stable, "Boundary refresh did not restore the fixed base")
	var rejected_boundary := source.refresh_boundary(boundary_data, Vector2i(99, 99), func(_site: Vector2i, _cell: Vector2i) -> Dictionary: return {"ok": false, "code": "MISSING_DATA"})
	assert(not rejected_boundary.ok and boundary_data.fingerprint() == stable, "Failed neighbour query partially modified edges")
	var bad := manifest.duplicate(true)
	bad.summary.sha256 = "0".repeat(64)
	_write(_output.path_join("bad.json"), JSON.stringify(bad).to_utf8_buffer())
	assert(source.load_manifest(_output.path_join("bad.json")).code == "HASH_MISMATCH")
	assert(source.make_terrain_data(99, 99).data.fingerprint() == stable, "Rejected source replaced the active atlas")
	bad = manifest.duplicate(true)
	bad.elevation_tiles = []
	_write(_output.path_join("missing.json"), JSON.stringify(bad).to_utf8_buffer())
	var missing := Atlas.new()
	assert(missing.load_manifest(_output.path_join("missing.json")).ok)
	assert(missing.make_terrain_data(99, 99).code == "MISSING_DATA")
	var masked_sea := source.sample_meters(20100.0, 20350.0)
	assert(masked_sea.ok and masked_sea.water_kind == 2 and not masked_sea.elevation_valid and masked_sea.level == 0)
	var no_height := PackedByteArray()
	no_height.resize(11 * 11 * 2)
	for i: int in range(11 * 11):
		no_height.encode_s16(i * 2, -32767)
	var nodata_manifest := manifest.duplicate(true)
	var no_height_record := _asset("land_nodata.zlib", no_height.compress(FileAccess.COMPRESSION_DEFLATE))
	nodata_manifest.elevation_tiles[0].path = no_height_record.path
	nodata_manifest.elevation_tiles[0].sha256 = no_height_record.sha256
	_write(_output.path_join("land_nodata.json"), JSON.stringify(nodata_manifest).to_utf8_buffer())
	var missing_land := Atlas.new()
	assert(missing_land.load_manifest(_output.path_join("land_nodata.json")).ok)
	assert(missing_land.make_terrain_data(99, 99).code == "MISSING_DATA", "Land NoData silently became playable terrain")
	var freshwater_manifest := manifest.duplicate(true)
	var fresh_mask := PackedByteArray()
	fresh_mask.resize(11 * 11)
	fresh_mask.fill(1)
	var fresh_record := _asset("unidentified_freshwater.zlib", fresh_mask.compress(FileAccess.COMPRESSION_DEFLATE))
	freshwater_manifest.elevation_tiles[0].derived.water_path = fresh_record.path
	freshwater_manifest.elevation_tiles[0].derived.water_sha256 = fresh_record.sha256
	_write(_output.path_join("freshwater.json"), JSON.stringify(freshwater_manifest).to_utf8_buffer())
	var freshwater := Atlas.new()
	assert(freshwater.load_manifest(_output.path_join("freshwater.json")).ok)
	assert(freshwater.make_terrain_data(99, 99).code == "MISSING_WATER_ID", "Distinct inland waters must not share an invented body")
	var sea_manifest := manifest.duplicate(true)
	var sea_summary := PackedByteArray()
	sea_summary.resize(16)
	sea_summary.fill(1)
	sea_manifest.summary.path = "sea.u8"
	sea_manifest.summary.sha256 = _asset("sea.u8", sea_summary).sha256
	sea_manifest.elevation_tiles = []
	sea_manifest.sea_surface_rule = {"source": "synthetic-contract-sea", "summary_class": 1, "gameplay_level": 0, "whole_site_verified": true}
	_write(_output.path_join("sea.json"), JSON.stringify(sea_manifest).to_utf8_buffer())
	var ocean := Atlas.new()
	assert(ocean.load_manifest(_output.path_join("sea.json")).ok)
	var sea := ocean.make_terrain_data(99, 99)
	assert(sea.ok and sea.data.site.is_empty() and sea.metadata.water_cells == 10000)
	assert(sea.data.spawn_cell == Vector2i(-1, -1) and not sea.metadata.can_place_probe)
	assert(is_nan(sea.metadata.absolute_elevation_m[0]), "Unmeasured sea elevation became measured zero")
	assert(_save_slot_contract(source, ocean, manifest), "Save-slot checks aborted")
	assert(_construction_contract(source, manifest), "Fixed-map construction checks aborted")
	assert(_fixed_resource_contract(source), "Fixed-base resource retention checks aborted")
	_finished = true
	print("REGION_LAB_CONTRACT_PASS ", JSON.stringify({"coordinate_checks": coordinate_checks, "reciprocal_ramps": ramp_checks, "repeat_loads": 100, "cache": source.cache_stats(), "source": "synthetic_contract_fixture_not_real_geography"}))
	quit(0)

func _save_slot_contract(source: RegionData, ocean: RegionData, original_manifest: Dictionary) -> bool:
	var unique := "contract_%d" % Time.get_ticks_usec()
	var first := Slot.new()
	var second := Slot.new()
	assert(first.open_map(source, unique + "_a", "slot").ok)
	assert(second.open_map(source, unique + "_b", "slot").ok)
	assert(first.folder != second.folder)
	var a_site := Vector2i(99, 99)
	var b_site := Vector2i(100, 99)
	assert(not FileAccess.file_exists(first.site_path(a_site)), "Unvisited Site wrote an empty save")
	var opened := first.open_site(a_site)
	assert(opened.ok and opened.interactive, str(opened))
	var a: TerrainData = opened.data
	assert(a.site.inventory.is_empty() and a.resource_base.is_empty())
	assert(a.site.get("actors", {}).is_empty() and a.site.get("armies", []).is_empty())
	var original := a.fingerprint()
	# Explicit fixture tools enable the existing SiteRuntime construction command.
	# No actor or inventory is created by opening the geographic map itself.
	a.site.inventory["tools"] = 1
	var cells: Array[int] = []
	for x: int in range(79, 100):
		cells.append(a.index(Vector2i(x, 40)))
	var requested := SiteRuntime.request_build(a, "level", cells)
	assert(requested.ok, str(requested))
	var feature: Dictionary = a.site.features[requested.feature]
	var work := float(feature.work)
	var target := "feature:" + str(requested.feature)
	SiteRuntime.assign_task(a, {"ok": true, "target": target, "action": "construct", "cell": int(feature.entrance), "zone": 0, "message": "Contract fixture"})
	a.site.worker.cell = int(feature.entrance)
	a.site.worker.mode = "work"
	SiteRuntime.advance(a, work + 1.0, true)
	var changed_index := a.index(Vector2i(99, 40))
	assert(a.site.terrain_changes.has(str(changed_index)) and int(a.height_levels[changed_index]) == 1)
	assert(a.site.features.is_empty() and a.site.worker.mode == "idle")
	var saved := first.save_site(a)
	assert(saved.ok, str(saved))
	var saved_bytes := FileAccess.get_file_as_bytes(first.site_path(a_site))
	assert(SiteStore.load_site(first.site_path(a_site)).code == "SAVE_VERSION", "Preset loader accepted a fixed map without its pinned source")
	var loaded_a := first.open_site(a_site)
	var loaded_b := first.open_site(b_site)
	assert(loaded_a.ok and loaded_b.ok, str([loaded_a, loaded_b]))
	assert(int(loaded_a.data.height_levels[changed_index]) == 1 and loaded_a.data.site.terrain_changes.has(str(changed_index)))
	assert(loaded_a.data.site.inventory == {"tools": 1} and loaded_a.data.resource_base.is_empty(), "Readback invented stock or deposits")
	assert(_check_cross_edge(loaded_a.data, Vector2i(99, 40), loaded_b.data, Vector2i(0, 40), 1))
	# The edited one-level contact is validated reciprocally above; only its
	# selected midpoint is a ramp under the sparse boundary rule.
	assert(first.save_site(loaded_b.data).ok)
	var reverse_b := first.open_site(b_site)
	var reverse_a := first.open_site(a_site)
	assert(reverse_a.ok and reverse_b.ok)
	assert(_check_cross_edge(reverse_a.data, Vector2i(99, 40), reverse_b.data, Vector2i(0, 40), 1))
	assert(reverse_a.data.fingerprint() == loaded_a.data.fingerprint() and reverse_b.data.fingerprint() == loaded_b.data.fingerprint(), "Load order changed saved geography")
	var independent := second.open_site(a_site)
	assert(independent.ok and independent.data.fingerprint() == original and independent.data.site.terrain_changes.is_empty())
	assert(independent.data.site.inventory.is_empty(), "Stock crossed world instances")
	var another_slot := Slot.new()
	assert(another_slot.open_map(source, unique + "_a", "other_slot").ok)
	assert(another_slot.open_site(a_site).data.fingerprint() == original)
	var newer_manifest := original_manifest.duplicate(true)
	newer_manifest.base_revision = "incompatible-v2"
	_write(_output.path_join("newer.json"), JSON.stringify(newer_manifest).to_utf8_buffer())
	var newer_source := Atlas.new()
	assert(newer_source.load_manifest(_output.path_join("newer.json")).ok)
	var rejected_slot := Slot.new()
	assert(rejected_slot.open_map(newer_source, unique + "_a", "slot").code == "SAVE_VERSION")
	assert(FileAccess.get_file_as_bytes(first.site_path(a_site)) == saved_bytes, "Version rejection changed the original save")
	var bad_pin := first.pin.duplicate(true)
	bad_pin.grid_contract_version = 1.5
	assert(not Slot._same_pin(bad_pin, first.pin), "Fractional grid version was truncated")
	var bad_base: Dictionary = a.parameters.fixed_base.duplicate(true)
	bad_base.site[0] = 99.5
	assert(not SiteStore._same_fixed_base(a.parameters.fixed_base, bad_base), "Fractional Site position was truncated")
	var ocean_slot := Slot.new()
	assert(ocean_slot.open_map(ocean, unique + "_ocean", "slot").ok)
	var sea := ocean_slot.open_site(a_site)
	assert(sea.ok and not sea.interactive and sea.data.site.is_empty())
	assert(ocean_slot.save_site(sea.data).code == "NO_TARGET" and not FileAccess.file_exists(ocean_slot.site_path(a_site)))
	print("REGION_LAB_CONTRACT_PROGRESS save_slots=pass original_runtime_level_command=pass sea_empty=pass")
	return true

func _construction_contract(source: RegionData, original_manifest: Dictionary) -> bool:
	var world := "construction_%d" % Time.get_ticks_usec()
	var slot := Slot.new()
	assert(slot.open_map(source, world, "slot").ok)
	var position := Vector2i(99, 99)
	var opened := slot.open_site(position)
	assert(opened.ok, str(opened))
	var data: TerrainData = opened.data
	assert(data.site.inventory.is_empty() and data.resource_base.is_empty())
	# Explicit synthetic stock only: the real atlas still has no sourced natural
	# deposits or soil. A road uses the original rules without inventing either.
	data.site.inventory = {"tools": 1, "stone": 4}
	var cells: Array[int] = [data.index(Vector2i(20, 20))]
	var request := SiteRuntime.request_build(data, "road", cells)
	assert(request.ok, str(request))
	var key := str(request.feature)
	var feature: Dictionary = data.site.features[key]
	assert(data.site.inventory == {"tools": 1, "stone": 3}, "Road cost was not reserved once")
	SiteRuntime.assign_task(data, {"ok": true, "target": "feature:" + key, "action": "construct", "cell": feature.entrance, "zone": 0, "message": "Synthetic fixed-map road"})
	data.site.worker.cell = int(feature.entrance)
	data.site.worker.mode = "work"
	SiteRuntime.advance(data, 1.25, true)
	assert(feature.stage == "building" and is_equal_approx(float(feature.progress), 1.25))
	assert(slot.save_site(data).ok)
	var partial := slot.open_site(position)
	assert(partial.ok, str(partial))
	var resumed: TerrainData = partial.data
	assert(resumed.site.features[key].stage == "building" and is_equal_approx(float(resumed.site.features[key].progress), 1.25))
	assert(resumed.site.inventory == {"tools": 1, "stone": 3}, "Readback reissued stock or repaid construction")
	assert(resumed.site.worker.target == "feature:" + key and resumed.site.worker.mode == "work")
	assert(resumed.site.worker.action == "construct" and int(resumed.site.worker.cell) == int(feature.entrance))
	SiteRuntime.advance(resumed, 2.0, true)
	assert(resumed.site.features[key].stage == "complete" and is_equal_approx(float(resumed.site.features[key].progress), 3.0))
	assert(resumed.site.inventory == {"tools": 1, "stone": 3})
	assert(slot.save_site(resumed).ok)
	var complete := slot.open_site(position)
	assert(complete.ok, str(complete))
	assert(complete.data.site.features[key].kind == "road" and complete.data.site.features[key].stage == "complete")
	assert(complete.data.feature_at[cells[0]] == int(key) and complete.data.is_walkable(Vector2i(20, 20)))
	assert(complete.data.site.inventory == {"tools": 1, "stone": 3} and complete.data.resource_base.is_empty())
	assert(complete.data.site.worker.target.is_empty() and complete.data.site.worker.mode == "idle")
	for identity: Array in [[world + "_other", "slot"], [world, "other_slot"]]:
		var independent := Slot.new()
		assert(independent.open_map(source, identity[0], identity[1]).ok)
		var untouched := independent.open_site(position)
		assert(untouched.ok and untouched.data.site.features.is_empty() and untouched.data.site.inventory.is_empty())
		assert(not FileAccess.file_exists(independent.site_path(position)))
	var saved_bytes := FileAccess.get_file_as_bytes(slot.site_path(position))
	var incompatible := original_manifest.duplicate(true)
	incompatible.base_revision = "construction-incompatible-v2"
	_write(_output.path_join("construction_newer.json"), JSON.stringify(incompatible).to_utf8_buffer())
	var newer := Atlas.new()
	assert(newer.load_manifest(_output.path_join("construction_newer.json")).ok)
	var rejected := Slot.new()
	assert(rejected.open_map(newer, world, "slot").code == "SAVE_VERSION")
	assert(FileAccess.get_file_as_bytes(slot.site_path(position)) == saved_bytes)
	assert(complete.data.site.features[key].stage == "complete" and complete.data.site.inventory == {"tools": 1, "stone": 3})
	print("REGION_LAB_CONTRACT_PROGRESS fixed_road_build_resume=pass completed_feature_reload=pass stock_spent_once=pass world_slot_isolation=pass natural_deposit_persistence=unsupported_no_source")
	return true

func _fixed_resource_contract(source: RegionData) -> bool:
	# This legacy geography fixture receives an explicit deterministic resource
	# base; ordinary geography-only sources must remain unchanged.
	var site := Vector2i(99, 99)
	var built := source.make_terrain_data(site.x, site.y)
	assert(built.ok and built.data.resource_base.is_empty())
	var data: TerrainData = built.data
	var legacy_base: Dictionary = built.base.duplicate(true)
	_install_fixed_resources(data)
	built.base = data.parameters.fixed_base.duplicate(true)
	assert(_resource_slot_pin_contract(source, built.base), "Resource slot pin checks aborted")
	assert(not SiteStore._same_fixed_base(legacy_base, built.base)
		and not SiteStore._same_fixed_base(built.base, legacy_base), "Resource and legacy bases became interchangeable")
	SiteEnvironment.initialize(data, str(built.base.site_id))
	assert(data.resource_base.size() == 2,
		"Fixed geography discarded resource_base supplied by its immutable base")
	data.site.inventory = {"tools": 1}
	var timber := _fixed_resource_key(data, SiteEnvironment.Kind.TIMBER)
	var food := _fixed_resource_key(data, SiteEnvironment.Kind.FOOD)
	var timber_work := SiteEnvironment.work_cells(data, timber)
	var food_work := SiteEnvironment.work_cells(data, food)
	assert(not timber_work.is_empty() and not food_work.is_empty())
	var cargo := {}
	assert(SiteRuntime.harvest(data, timber, timber_work[0], cargo).ok)
	assert(int(SiteEnvironment.resource(data, timber).remaining) == 0 and cargo.wood == 4)
	assert(SiteRuntime.harvest(data, timber, timber_work[0], cargo, "clear").ok)
	assert(bool(SiteEnvironment.resource(data, timber).cleared))
	assert(SiteRuntime.harvest(data, food, food_work[0], cargo).ok)
	var due := int(SiteEnvironment.resource(data, food).next_recovery)
	assert(int(SiteEnvironment.resource(data, food).remaining) == 0 and due > int(data.site.minute))
	var save_path := _output.path_join("fixed_resources_%d.json" % Time.get_ticks_usec())
	var saved := SiteStore.save(data, save_path)
	assert(saved.ok, str(saved))
	var saved_bytes := FileAccess.get_file_as_bytes(save_path)
	var restore := func(saved_base: Dictionary) -> Dictionary:
		var rebuilt := source.make_terrain_data(site.x, site.y)
		if not rebuilt.ok:
			return {"ok": false, "code": "SAVE_VERSION"}
		_install_fixed_resources(rebuilt.data)
		rebuilt.base = rebuilt.data.parameters.fixed_base.duplicate(true)
		if not SiteStore._same_fixed_base(rebuilt.base, saved_base):
			return {"ok": false, "code": "SAVE_VERSION"}
		return rebuilt
	for field: String in ["resource_layer_sha256", "resource_rule_revision", "resource_fingerprint"]:
		var rejected := SiteStore.load_site(save_path, func(pinned_base: Dictionary) -> Dictionary:
			var candidate: Dictionary = restore.call(pinned_base)
			assert(candidate.ok)
			candidate.base[field] = "changed-rule" if field == "resource_rule_revision" else "0".repeat(64)
			candidate.data.parameters.fixed_base = candidate.base.duplicate(true)
			return candidate
		)
		assert(rejected.code == "SAVE_VERSION", "Changed resource pin was accepted: " + field)
		assert(FileAccess.get_file_as_bytes(save_path) == saved_bytes, "Resource pin rejection changed the original save")
	var delivered: Dictionary = {}
	var corrupt_base := SiteStore.load_site(save_path, func(pinned_base: Dictionary) -> Dictionary:
		var candidate: Dictionary = restore.call(pinned_base)
		assert(candidate.ok)
		candidate.data.resource_base[food].capacity += 1
		delivered["data"] = candidate.data
		return candidate
	)
	assert(corrupt_base.code == "SAVE_VERSION" and delivered.data.site.is_empty(),
		"Loader resource contents were trusted or initialized before checking their fingerprint")
	data.resource_base[food].capacity += 1
	assert(SiteStore.save(data, save_path).code == "SAVE_VERSION", "Modified immutable resource base overwrote a valid save")
	data.resource_base[food].capacity -= 1
	assert(FileAccess.get_file_as_bytes(save_path) == saved_bytes)
	var loaded := SiteStore.load_site(save_path, restore)
	assert(loaded.ok, str({"message": "Fixed-base resource deltas did not reload", "result": loaded}))
	var resumed: TerrainData = loaded.data
	assert(resumed.resource_base.size() == 2 and bool(SiteEnvironment.resource(resumed, timber).cleared)
		and int(SiteEnvironment.resource(resumed, food).remaining) == 0
		and int(SiteEnvironment.resource(resumed, food).next_recovery) == due,
		"Fixed-base exhaustion, clearing or recovery deadline changed on load")
	SiteRuntime.advance(resumed, float(due + 1), true)
	assert(bool(SiteEnvironment.resource(resumed, timber).cleared)
		and int(SiteEnvironment.resource(resumed, timber).remaining) == 0
		and int(SiteEnvironment.resource(resumed, food).remaining) == 3,
		"Original SiteRuntime regeneration refilled a cleared source or missed due food")
	assert(SiteStore.save(resumed, save_path).ok)
	var final_load := SiteStore.load_site(save_path, restore)
	assert(final_load.ok and bool(SiteEnvironment.resource(final_load.data, timber).cleared)
		and int(SiteEnvironment.resource(final_load.data, food).remaining) == 3,
		"Regenerated fixed-base resource did not survive another save/load")
	assert(source.make_terrain_data(site.x, site.y).data.resource_base.is_empty(),
		"Synthetic fixture leaked natural deposits into the geographic source")
	print("REGION_LAB_CONTRACT_PROGRESS synthetic_fixed_resources_exhaust_clear_regenerate_save_reload=pass resource_pins_and_content_hash=pass")
	return true

func _resource_slot_pin_contract(legacy_source: RegionData, base: Dictionary) -> bool:
	# Pin checks need only source identity; they do not bypass the real loader or
	# invent a second resource-state owner.
	var pinned_source := Atlas.new()
	pinned_source.manifest = legacy_source.manifest.duplicate(true)
	pinned_source.manifest_hash = legacy_source.manifest_hash
	pinned_source.resource_manifest_hash = str(base.resource_layer_sha256)
	pinned_source.resource_rule_revision = str(base.resource_rule_revision)
	var world := "resource_pins_%d" % Time.get_ticks_usec()
	var slot := Slot.new()
	var opened := slot.open_map(pinned_source, world, "slot")
	assert(opened.ok, str(opened))
	var original_pin := FileAccess.get_file_as_bytes(str(opened.path))
	assert(slot._matches_base(base, Vector2i(99, 99)))
	assert(Slot.new().open_map(pinned_source, world, "slot").ok)
	assert(Slot.new().open_map(legacy_source, world, "slot").code == "SAVE_VERSION")
	for pair: Array in [["resource_layer_sha256", "resource_manifest_hash"], ["resource_rule_revision", "resource_rule_revision"]]:
		var field: String = pair[0]
		var property: String = pair[1]
		var changed := "changed-rule" if field == "resource_rule_revision" else "0".repeat(64)
		var bad_pin: Dictionary = slot.pin.duplicate(true)
		bad_pin[field] = changed
		assert(not Slot._same_pin(bad_pin, slot.pin), "Equal-sized resource slot pins ignored changed content")
		var bad_base: Dictionary = base.duplicate(true)
		bad_base[field] = changed
		assert(not slot._matches_base(bad_base, Vector2i(99, 99)))
		pinned_source.set(property, changed)
		assert(not slot._matches_base(base, Vector2i(99, 99)), "Active source changed without invalidating its slot")
		assert(Slot.new().open_map(pinned_source, world, "slot").code == "SAVE_VERSION")
		pinned_source.set(property, base[field])
		assert(FileAccess.get_file_as_bytes(str(opened.path)) == original_pin)
	var legacy_slot := Slot.new()
	var legacy_opened := legacy_slot.open_map(legacy_source, world, "legacy")
	assert(legacy_opened.ok)
	var legacy_pin := FileAccess.get_file_as_bytes(str(legacy_opened.path))
	assert(Slot.new().open_map(pinned_source, world, "legacy").code == "SAVE_VERSION")
	assert(FileAccess.get_file_as_bytes(str(legacy_opened.path)) == legacy_pin)
	for field: String in ["resource_layer_sha256", "resource_rule_revision", "resource_fingerprint"]:
		var incomplete: Dictionary = base.duplicate(true)
		incomplete.erase(field)
		assert(not SiteStore._same_fixed_base(incomplete, incomplete), "Incomplete resource base pin accepted")
	return true

func _install_fixed_resources(data: TerrainData) -> void:
	var chosen: Array[int] = []
	for y: int in range(8, 92):
		for x: int in range(8, 92):
			var cell := Vector2i(x, y)
			var index := data.index(cell)
			if not data.is_terrain_walkable(cell) or data.ramp_edges[index] != 0 \
					or cell == data.spawn_cell:
				continue
			if chosen.is_empty() or Vector2(data.cell_from_index(chosen[0])).distance_to(Vector2(cell)) > 5.0:
				chosen.append(index)
			if chosen.size() == 2:
				break
		if chosen.size() == 2:
			break
	assert(chosen.size() == 2, "Synthetic fixed resource fixture needs two ordinary land cells")
	for pair: Array in [[SiteEnvironment.Kind.TIMBER, chosen[0], 4, 10080, true],
			[SiteEnvironment.Kind.FOOD, chosen[1], 3, 720, false]]:
		var kind: int = pair[0]
		var index: int = pair[1]
		var key := "%d:%d" % [kind, index]
		data.resource_base[key] = {"kind": kind, "cell": index, "cells": [index],
			"capacity": pair[2], "variant": 0, "water": -1,
			"blocks": pair[4], "recover": pair[3]}
	data.parameters.fixed_base["resource_layer_sha256"] = "synthetic-resource-contract-v1".sha256_text()
	data.parameters.fixed_base["resource_rule_revision"] = "synthetic-placement-v1"
	data.parameters.fixed_base["resource_fingerprint"] = JSON.stringify(data.resource_base, "", true, true).sha256_text()

func _fixed_resource_key(data: TerrainData, kind: int) -> String:
	for key: String in data.resource_base:
		if int(data.resource_base[key].kind) == kind:
			return key
	assert(false, "Synthetic fixed resource key absent")
	return ""

func _memo_equivalence(source: RegionData) -> bool:
	var checked := 0
	for site: Vector2i in [Vector2i(99, 99), Vector2i(100, 99), Vector2i(99, 100), Vector2i(100, 101)]:
		var memo: Dictionary = {}
		var positions := [-1, 0, 1, 49, 98, 99, 100]
		for pass_index: int in range(2):
			if pass_index == 1:
				positions.reverse()
			for y: int in positions:
				for x: int in positions:
					var easting := site.x * 200.0 + x * 2.0 + 1.0
					var northing := site.y * 200.0 + (99 - y) * 2.0 + 1.0
					var plain := source.sample_meters(easting, northing)
					var cached := source._sample_site_meters(easting, northing, memo)
					assert(plain.ok == cached.ok)
					if plain.ok:
						for field: String in ["elevation_m", "elevation_valid", "level", "water_kind", "water_id"]:
							assert(plain[field] == cached[field], "Memo changed %s at %s/%s" % [field, site, Vector2i(x, y)])
					else:
						assert(plain.code == cached.code)
					checked += 1
		assert(memo.size() <= 144, "One Site retained more than its 20m source neighbourhood")
	print("REGION_LAB_CONTRACT_PROGRESS memo_equivalent_samples=", checked)
	return true

func _scope_contract(original: Dictionary) -> bool:
	var scoped_manifest := original.duplicate(true)
	scoped_manifest.erase("synthetic_fixture")
	var scope := PackedByteArray()
	scope.resize(16)
	scope.fill(1)
	scope[9] = 0 # Land Site (99,99), outside the opened content.
	var record := _asset("content_scope.u8", scope)
	record.merge({"size": [4, 4], "site_origin": [98, 98], "encoding": "u8", "row_order": "north_to_south"})
	scoped_manifest.content_scope = record
	_write(_output.path_join("scoped.json"), JSON.stringify(scoped_manifest).to_utf8_buffer())
	var scoped := Atlas.new()
	assert(scoped.load_manifest(_output.path_join("scoped.json")).ok)
	var outside := scoped.get_site_summary(99, 99)
	assert(outside.ok and outside.class_id == 2 and outside.geography_status == "land" and outside.status == "outside_content" and not outside.has_terrain)
	assert(scoped.make_terrain_data(99, 99).code == "OUTSIDE_CONTENT")
	assert(scoped.get_overview().classes[9] == 2 and scoped.get_overview().content_scope[9] == 0)
	assert(scoped.make_terrain_data(100, 99).ok)
	var missing := original.duplicate(true)
	missing.erase("synthetic_fixture")
	_write(_output.path_join("no_scope.json"), JSON.stringify(missing).to_utf8_buffer())
	assert(scoped.load_manifest(_output.path_join("no_scope.json")).code == "MISSING_SCOPE")
	var bad := scoped_manifest.duplicate(true)
	bad.content_scope.sha256 = "0".repeat(64)
	_write(_output.path_join("bad_scope_hash.json"), JSON.stringify(bad).to_utf8_buffer())
	assert(scoped.load_manifest(_output.path_join("bad_scope_hash.json")).code == "HASH_MISMATCH")
	bad = scoped_manifest.duplicate(true)
	bad.content_scope.size[0] = 3
	_write(_output.path_join("bad_scope_size.json"), JSON.stringify(bad).to_utf8_buffer())
	assert(scoped.load_manifest(_output.path_join("bad_scope_size.json")).code == "INVALID_SCOPE")
	assert(scoped.get_site_summary(99, 99).status == "outside_content", "Invalid scope replaced the current atlas")
	return true

func _quality_and_water_contract(original: Dictionary) -> bool:
	var enriched := original.duplicate(true)
	var summary := PackedByteArray(original.summary_test_bytes)
	summary[9] = 3 # Site (99,99), one named freshwater body.
	summary[10] = 4 # Adjacent Site (100,99), two distinct freshwater bodies and land.
	summary[11] = 4 # Unknown-salinity water with a named body stays distinct from fresh.
	var summary_record := _asset("r4_summary.u8", summary)
	enriched.summary.path = summary_record.path
	enriched.summary.sha256 = summary_record.sha256
	var site_quality := PackedByteArray()
	site_quality.resize(summary.size())
	site_quality.fill(1)
	site_quality[10] = 3 # A known bounded estimate, visible at Site level.
	site_quality[12] = 0 # Existing Missing Site remains explicitly distinct.
	var quality_record := _asset("r4_source_quality.u8", site_quality)
	quality_record.merge({"size": [4, 4], "site_origin": [98, 98], "encoding": "u8", "row_order": "north_to_south"})
	enriched.source_quality = quality_record
	enriched.source_quality_codes = {"0": "sea_or_missing", "1": "measured_moi", "2": "moi_interpolated",
		"3": "bounded_moi_extrapolated", "4": "other_estimate"}
	enriched.water_bodies = [{"id": 2, "source_id": "fixture_lake_a", "kind": 1, "name": "Lake A"},
		{"id": 3, "source_id": "fixture_lake_b", "kind": 1, "name": "Lake B"},
		{"id": 4, "source_id": "fixture_pond_unknown", "kind": 4, "name": "Unknown salinity pond"},
		{"id": 1000003, "source_id": "fixture_sparse_body", "kind": 3, "name": "Sparse body"}]
	for tile: Dictionary in enriched.elevation_tiles:
		var width: int = int(tile.size[0])
		var height: int = int(tile.size[1])
		var count := width * height
		var water := FileAccess.get_file_as_bytes(_output.path_join(str(tile.derived.water_path))).decompress(count, FileAccess.COMPRESSION_DEFLATE)
		assert(water.size() == count)
		var quality := PackedByteArray()
		quality.resize(count)
		var bodies := PackedByteArray()
		bodies.resize(count * 4)
		for row: int in range(height):
			for column: int in range(width):
				var index := row * width + column
				var east := int(tile.origin[0]) + column * 20 + 10
				var north := int(tile.origin[1]) + (height - 1 - row) * 20 + 10
				if north < 20000 and east < 20120:
					water[index] = 1
					bodies.encode_u32(index * 4, 2)
				elif north < 20000 and east >= 20220:
					water[index] = 4
					bodies.encode_u32(index * 4, 4)
				elif north < 20000 and east >= 20160 and east < 20200:
					water[index] = 1
					bodies.encode_u32(index * 4, 3)
				elif water[index] == 2:
					bodies.encode_u32(index * 4, 1)
				quality[index] = 0 if water[index] == 2 else 1
				if east == 20010 and north == 19990:
					quality[index] = 3
		var prefix := "r4_" + str(tile.id)
		var water_record := _asset(prefix + ".water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
		var quality_tile_record := _asset(prefix + ".quality.zlib", quality.compress(FileAccess.COMPRESSION_DEFLATE))
		var body_record := _asset(prefix + ".water_body.zlib", bodies.compress(FileAccess.COMPRESSION_DEFLATE))
		tile.derived.water_path = water_record.path
		tile.derived.water_sha256 = water_record.sha256
		tile.derived.quality_path = quality_tile_record.path
		tile.derived.quality_sha256 = quality_tile_record.sha256
		tile.derived.water_body_path = body_record.path
		tile.derived.water_body_sha256 = body_record.sha256
		tile.derived.water_body_encoding = "u32_le_zlib"
	var manifest_path := _output.path_join("r4_quality_water.json")
	_write(manifest_path, JSON.stringify(enriched).to_utf8_buffer())
	var source := Atlas.new()
	var enriched_loaded := source.load_manifest(manifest_path)
	assert(enriched_loaded.ok, str(enriched_loaded))
	assert(source.get_water_body(4) == {"id": 4, "source_id": "fixture_pond_unknown",
		"kind": 4, "name": "Unknown salinity pond"})
	assert(source.get_water_body(1000003) == {"id": 1000003, "source_id": "fixture_sparse_body",
		"kind": 3, "name": "Sparse body"})
	assert(source.get_water_body(5).is_empty())
	assert(source.get_site_summary(99, 99).source_quality_code == 1)
	assert(source.get_site_summary(100, 99).source_quality_code == 3)
	var west_water := source.sample_meters(19999.0, 19990.0)
	var east_water := source.sample_meters(20001.0, 19990.0)
	var other_water := source.sample_meters(20170.0, 19990.0)
	var unknown_water := source.sample_meters(20230.0, 19990.0)
	assert(west_water.ok and east_water.ok and other_water.ok and unknown_water.ok)
	assert(west_water.water_kind == 1 and east_water.water_kind == 1 and other_water.water_kind == 1)
	assert(unknown_water.water_kind == 4 and unknown_water.water_body == 4)
	assert(unknown_water.elevation_valid and unknown_water.elevation_m > 0.0)
	assert(west_water.water_body == 2 and east_water.water_body == 2 and other_water.water_body == 3,
		"Two inland bodies merged or one body changed across a tile edge")
	assert(west_water.elevation_valid and west_water.elevation_m > 0.0 and east_water.elevation_m > 0.0,
		"Freshwater above sea level became invented zero height")
	assert(source.sample_meters(20010.0, 19990.0).source_quality_code == 3)
	var west_site := source.make_terrain_data(99, 99)
	var east_site := source.make_terrain_data(100, 99)
	var unknown_site := source.make_terrain_data(101, 99)
	assert(west_site.ok and east_site.ok and unknown_site.ok,
		str([west_site.get("code", "OK"), east_site.get("code", "OK"), unknown_site.get("code", "OK")]))
	var matching_water_edges := 0
	var distinct_body_cells := 0
	for row: int in range(100):
		var wi: int = west_site.data.index(Vector2i(99, row))
		var ei: int = east_site.data.index(Vector2i(0, row))
		if west_site.data.water_body[wi] == 2 and east_site.data.water_body[ei] == 2:
			matching_water_edges += 1
	for body: int in east_site.data.water_body:
		if body == 3:
			distinct_body_cells += 1
	assert(matching_water_edges > 0 and distinct_body_cells > 0,
		"Water-body identity did not survive adjacent Site expansion")
	var unknown_adjacent := false
	for i: int in range(10000):
		if not unknown_site.data.is_terrain_walkable(unknown_site.data.cell_from_index(i)):
			continue
		assert(SiteRuntime.adjacent_water(unknown_site.data, [i], 1).is_empty(),
			"Unknown-salinity water was exposed as known freshwater")
		if not SiteRuntime.adjacent_water(unknown_site.data, [i], 4).is_empty():
			unknown_adjacent = true
	assert(unknown_adjacent, "Unknown-salinity water lost its named adjacency")
	var bad := enriched.duplicate(true)
	bad.source_quality.sha256 = "0".repeat(64)
	_write(_output.path_join("r4_bad_source_quality_hash.json"), JSON.stringify(bad).to_utf8_buffer())
	assert(source.load_manifest(_output.path_join("r4_bad_source_quality_hash.json")).code == "HASH_MISMATCH")
	bad = enriched.duplicate(true)
	bad.elevation_tiles[0].derived.erase("quality_path")
	bad.elevation_tiles[0].derived.erase("quality_sha256")
	_write(_output.path_join("r4_missing_quality.json"), JSON.stringify(bad).to_utf8_buffer())
	assert(Atlas.new().load_manifest(_output.path_join("r4_missing_quality.json")).code == "INVALID_QUALITY")
	bad = enriched.duplicate(true)
	bad.elevation_tiles[0].derived.quality_sha256 = "0".repeat(64)
	_write(_output.path_join("r4_bad_tile_quality_hash.json"), JSON.stringify(bad).to_utf8_buffer())
	var corrupt_quality := Atlas.new()
	assert(corrupt_quality.load_manifest(_output.path_join("r4_bad_tile_quality_hash.json")).ok)
	assert(corrupt_quality.make_terrain_data(99, 99).code == "HASH_MISMATCH")
	bad = enriched.duplicate(true)
	bad.elevation_tiles[0].derived.erase("water_body_path")
	bad.elevation_tiles[0].derived.erase("water_body_sha256")
	bad.elevation_tiles[0].derived.erase("water_body_encoding")
	_write(_output.path_join("r4_missing_water_id.json"), JSON.stringify(bad).to_utf8_buffer())
	var missing_body := Atlas.new()
	assert(missing_body.load_manifest(_output.path_join("r4_missing_water_id.json")).ok)
	assert(missing_body.make_terrain_data(99, 99).code == "MISSING_WATER_ID")
	print("REGION_LAB_CONTRACT_PROGRESS quality_hash=pass fresh_water_height=pass water_ids=pass unknown_water_not_fresh=pass edge_identity=pass")
	return true

func _coordinates() -> int:
	var checks := 0
	for easting: int in [-200001, -200000, -199999, -2001, -2000, -1, 0, 1, 1999, 2000, 199999, 200000, 200001, 250000000]:
		for northing: int in [-200001, -200000, -1, 0, 1, 199999, 200000, 2700000000, 2800000000]:
			var site := Grid.site_from_mm(easting, northing)
			var local := Grid.local_from_mm(easting, northing)
			assert(local.x >= 0 and local.x < 100 and local.y >= 0 and local.y < 100)
			var center := Grid.cell_center_mm(site, local)
			assert(Grid.site_from_mm(center.easting_mm, center.northing_mm) == site)
			assert(Grid.local_from_mm(center.easting_mm, center.northing_mm) == local)
			assert(absi(int(center.easting_mm) - easting) <= 1000 and absi(int(center.northing_mm) - northing) <= 1000)
			var region := Grid.region_of(site)
			assert(region * 100 + Grid.site_in_region(site) == site)
			checks += 1
	assert(Grid.site_from_mm(-1, -1) == Vector2i(-1, -1))
	assert(Grid.site_from_mm(200000, 200000) == Vector2i(1, 1))
	assert(Grid.cell_corner_mm(Vector2i(99, 99), Vector2i(100, 0)) == Grid.cell_corner_mm(Vector2i(100, 100), Vector2i(0, 100)))
	assert(Grid.site_id("fixed", Vector2i(-1, 100)) == "fixed:-1:100")
	return checks

func _check_cross_edge(a: TerrainData, from: Vector2i, b: TerrainData, to: Vector2i, direction: int) -> bool:
	var ai := a.index(from)
	var bi := b.index(to)
	var difference := int(a.height_levels[ai]) - int(b.height_levels[bi])
	assert(a.cliff_drops[ai * 4 + direction] == maxi(0, difference))
	assert(b.cliff_drops[bi * 4 + ((direction + 2) % 4)] == maxi(0, -difference))
	assert(((a.ramp_edges[ai] >> direction) & 1) == ((b.ramp_edges[bi] >> ((direction + 2) % 4)) & 1))
	return true

func _fixture() -> Dictionary:
	var summary := PackedByteArray([2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 2, 2, 2])
	var summary_record := _asset("summary.u8", summary)
	summary_record.merge({"size": [4, 4], "site_origin": [98, 98], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var tiles: Array[Dictionary] = []
	for tile_y: int in range(2):
		for tile_x: int in range(2):
			var west := 19780 if tile_x == 0 else 20000
			var south := 19780 if tile_y == 0 else 20000
			var width := 11 if tile_x == 0 else 21
			var height := 11 if tile_y == 0 else 21
			var elevations := PackedByteArray()
			elevations.resize(width * height * 2)
			var levels := PackedByteArray()
			var water := PackedByteArray()
			levels.resize(width * height)
			water.resize(width * height)
			for y: int in range(height):
				for x: int in range(width):
					var east := west + x * 20 + 10
					var north := south + (height - 1 - y) * 20 + 10
					var i := y * width + x
					elevations.encode_s16(i * 2, -32767 if north > 20300 else 100 + Grid.floor_div(east - 19780, 20))
					levels[i] = clampi(floori((east - 19800) / 80.0), 0, 5)
					water[i] = 2 if north > 20300 else 0
			var identity := "%d_%d" % [tile_x, tile_y]
			var tile := _asset(identity + ".height.zlib", elevations.compress(FileAccess.COMPRESSION_DEFLATE))
			var level_record := _asset(identity + ".levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
			var water_record := _asset(identity + ".water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
			tile.merge({"id": identity, "origin": [west, south], "size": [width, height], "spacing_m": 20,
				"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
				"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256, "water_path": water_record.path, "water_sha256": water_record.sha256}})
			tiles.append(tile)
	return {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": 1, "base_revision": "synthetic-contract-v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": tiles, "sources": [{"title": "Synthetic fixture only"}], "summary_test_bytes": Array(summary)}

func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	_write(_output.path_join(name), bytes)
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	return {"path": name, "sha256": hasher.finish().hex_encode()}

func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Cannot write isolated contract fixture")
	file.store_buffer(bytes)
