extends SceneTree
const Data = preload("res://scripts/region_lab/region_data.gd")
const Adapter = preload("res://scripts/region_lab/region_terrain_adapter.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Route = preload("res://scripts/region_lab/region_route.gd")
const Slot = preload("res://scripts/region_lab/region_save_slot.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
var _failed := false
var folder := ""
var natural_record: Dictionary = {}

func _initialize() -> void:
	_logger = ScriptFailureLogger.new()
	_logger.host = weakref(self)
	OS.add_logger(_logger)
	call_deferred("_run")

func _check(value: bool, message: String) -> bool:
	if _failed: return false
	if value: return true
	_failed = true
	push_error("MAP_EDITOR_TERRAIN_CONTRACT_FAIL: " + message)
	quit(1)
	return false

func _write(name: String, bytes: PackedByteArray) -> Dictionary:
	var path: String = folder.path_join(name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null, "fixture open " + name): return {}
	file.store_buffer(bytes)
	file.flush()
	var status: int = file.get_error()
	file.close()
	if not _check(status == OK and FileAccess.get_file_as_bytes(path) == bytes, "fixture readback " + name): return {}
	return {"path": name, "bytes": bytes.size(), "sha256": FileAccess.get_sha256(path)}

func _json(name: String, value: Dictionary) -> Dictionary:
	return _write(name, JSON.stringify(value, "", true, true).to_utf8_buffer())

func _static() -> Dictionary:
	return {"format": 2, "terrain": {}, "resources": {}, "water_bodies": {}, "water_permissions": {"cells": [], "bodies": []}}

func _file(name: String, value: Dictionary, kind: String, site: Vector2i) -> Dictionary:
	var record: Dictionary = _json(name, value)
	if _failed: return {}
	record.kind = kind
	record.site = [site.x, site.y]
	return record

func _package(name: String, files: Array[Dictionary], revision: int = 1) -> String:
	var manifest: Dictionary = {"format": 1, "source_kind": "fixed_tw_author", "scenario_id": "p2a_fixture", "revision": revision,
		"name": "離散地形測試", "description": "唯讀初始投影；不出生人物", "atlas_id": Grid.ATLAS_ID,
		"grid_contract_version": Grid.CONTRACT_VERSION, "natural_source": "natural", "dependencies": [natural_record],
		"files": files, "start": {"mode": "created_player", "site": [0,0], "cell": [49,49]}, "package_digest": "0".repeat(64)}
	manifest.package_digest = Data.author_package_digest(manifest)
	if not _check(not manifest.package_digest.is_empty(), "package schema"): return ""
	var record: Dictionary = _json(name, manifest)
	if _failed: return ""
	return folder.path_join(str(record.path))

func _natural() -> bool:
	var classes: PackedByteArray = PackedByteArray()
	classes.resize(49); classes.fill(2)
	var summary: Dictionary = _write("summary.bin", classes)
	if _failed: return false
	summary.erase("bytes")
	summary.merge({"size": [7,7], "site_origin": [-3,-3], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var elevations: PackedFloat32Array = PackedFloat32Array()
	elevations.resize(121); elevations.fill(20.0)
	var tile: Dictionary = _write("elevation.bin", elevations.to_byte_array())
	if _failed: return false
	tile.erase("bytes")
	tile.merge({"id": "p2a", "size": [11,11], "origin": [-1000,-1000], "spacing_m": 200,
		"encoding": "float32_le", "row_order": "north_to_south", "nodata": -9999})
	var levels: PackedByteArray = PackedByteArray()
	levels.resize(121); levels.fill(1)
	var waters: PackedByteArray = PackedByteArray()
	waters.resize(121); waters.fill(0)
	var l: Dictionary = _write("levels.bin", levels)
	if _failed: return false
	var w: Dictionary = _write("water.bin", waters)
	if _failed: return false
	tile.derived = {"levels_path": l.path, "levels_sha256": l.sha256, "water_path": w.path, "water_sha256": w.sha256, "encoding": "u8"}
	var manifest: Dictionary = {"format": 1, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": Grid.CONTRACT_VERSION,
		"crs": "EPSG:3826", "base_revision": "p2a_fixture", "sources": [], "synthetic_fixture": true,
		"grid": {"origin": [0,0], "cell_m": 2, "site_cells": 100, "region_sites": 100}, "summary": summary, "elevation_tiles": [tile], "preview_sites": [{"label": "fixture", "site": [0,0]}]}
	natural_record = _json("natural.json", manifest)
	if _failed: return false
	natural_record.path = folder.path_join("natural.json")
	natural_record.id = "natural"
	return true

func _run() -> void:
	if "--script-error-probe" in OS.get_cmdline_user_args():
		_intentional_script_fault()
		if _failed: return
		if not _check(false, "script logger failed to intercept"): return
	if "--fail-fast-probe" in OS.get_cmdline_user_args():
		if not _check(false, "intentional first failure"): return
	folder = "user://map_editor_terrain_contract_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var made: int = DirAccess.make_dir_recursive_absolute(folder)
	if not _check(made == OK, "fixture directory"): return
	if not _natural(): return
	var natural: RegionData = Data.new()
	var loaded: Dictionary = natural.load_manifest(str(natural_record.path))
	if not _check(loaded.ok, "real natural loader"): return
	for at: Vector2i in [Vector2i(-1,-1), Vector2i.ZERO, Vector2i(1,1)]:
		for cell: Vector2i in [Vector2i.ZERO, Vector2i(99,0), Vector2i(0,99), Vector2i(99,99)]:
			var mm: Dictionary = Grid.cell_center_mm(at, cell)
			if not _check(Grid.site_from_mm(int(mm.easting_mm), int(mm.northing_mm)) == at and Grid.local_from_mm(int(mm.easting_mm), int(mm.northing_mm)) == cell, "E02 grid corners/negative"): return
	var raw: Dictionary = _static()
	raw.terrain["4949"] = {"height": 2, "surface": TerrainData.Surface.FOREST_GROUND, "fertility": 17, "moisture": 28, "drainage": 39, "foundation": 40, "groundwater": 51}
	for field: String in ["height", "fertility", "water_kind"]:
		var invalid: Dictionary = raw.duplicate(true)
		invalid.terrain["4949"][field] = 0.5
		if not _check(not natural.author_static_valid(invalid), "fractional rejected " + field): return
	var files: Array[Dictionary] = []
	files.append(_file("a.json", raw, "static", Vector2i.ZERO))
	if _failed: return
	var path: String = _package("package.json", files)
	if _failed: return
	var source: RegionData = Data.new()
	var admitted: Dictionary = source.load_author_package(path)
	if not _check(admitted.ok and admitted.initial_admitted, "author source admitted; source load itself does not birth"): return
	var built: Dictionary = source.make_terrain_data(0,0)
	if not _check(built.ok and built.data.height_levels[4949] == 2 and built.data.surface_types[4949] == TerrainData.Surface.FOREST_GROUND, "E03 real Adapter applies static"): return
	var data: TerrainData = built.data
	var hash_before: String = Adapter.author_environment_fingerprint(data)
	Env.initialize(data, str(built.base.site_id))
	if _failed: return
	if not _check(Adapter.author_environment_fingerprint(data) == hash_before, "E03 initialize retains land/hash"): return
	var staged_build: Dictionary = source.make_terrain_data(0,0)
	if not _check(staged_build.ok, "staged initialization source"): return
	var staged_data: TerrainData = staged_build.data
	var staged_job: Dictionary = Env.begin_initialize(staged_data, str(staged_build.base.site_id))
	if not _check(not staged_job.is_empty(), "original staged initializer admitted"): return
	for _unit: int in range(4):
		if bool(staged_job.done): break
		Env.step_initialize(staged_job, 0, 1)
		if _failed: return
	if not _check(bool(staged_job.done), "empty legacy fixture completes original bounded stages"): return
	for field: String in Data.AUTHOR_LAND_FIELDS:
		if not _check(staged_data.get(field) == data.get(field), "staged and blocking author soil match " + field): return
	data.site["world_pin"] = Data.author_projection_pin(built.base)
	for field: String in Data.AUTHOR_LAND_FIELDS:
		var values: PackedByteArray = data.get(field)
		if not _check(values[4949] == int(raw.terrain["4949"][field]), "initialize retains " + field): return
	var archive: String = folder.path_join("saved.json")
	var saved: Dictionary = Store.save(data, archive)
	if not _check(saved.ok, "original Store save"): return
	var restored: Dictionary = Store.load_site(archive, func(_base: Dictionary) -> Dictionary: return source.make_terrain_data(0,0))
	if not _check(restored.ok and restored.data.fertility[4949] == 17 and restored.data.height_levels[4949] == 2, "E03 original Store rebuild/read"): return
	for field: String in Data.AUTHOR_LAND_FIELDS:
		var values: PackedByteArray = restored.data.get(field)
		if not _check(values[4949] == int(raw.terrain["4949"][field]), "Store reload retains " + field): return
	var legacy: Dictionary = natural.make_terrain_data(0,0)
	if not _check(legacy.ok, "legacy source body"): return
	Env.initialize(legacy.data, str(legacy.base.site_id))
	if _failed: return
	if not _check(legacy.data.fertility[4949] == 0, "zero legacy preserved"): return
	var edges_before: PackedByteArray = data.cliff_drops.duplicate()
	var flags_before: PackedByteArray = data.flags.duplicate()
	var halo_before: Dictionary = data.parameters.get("ramp_visual_halo", {}).duplicate(true)
	var samples: Array[int] = []
	samples.append(0)
	var rejected_halo: Dictionary = source.refresh_boundary(data, Vector2i.ZERO, func(_at: Vector2i, _cell: Vector2i) -> Dictionary:
		samples[0] += 1
		return {"ok": false, "code": "MISSING_CORNER"} if samples[0] == 404 else {"ok": true, "level": 1, "water_kind": 0})
	if not _check(not rejected_halo.ok and samples[0] == 404 and data.cliff_drops == edges_before and data.flags == flags_before and data.parameters.ramp_visual_halo == halo_before, "E23 fourth corner failure leaves all edges unchanged"): return
	var wet: Dictionary = _static()
	wet.water_bodies["1000000000"] = {"id": "river", "kind": 1}
	for i: int in [2000,2100]: wet.terrain[str(i)] = {"height": 0, "surface": TerrainData.Surface.WATER, "water_kind": 1, "water_body": 1000000000}
	var water: Dictionary = natural.make_author_draft(Vector2i(1,0), wet, 1)
	if not _check(water.ok and not water.data.can_navigate_water(Vector2i(0,20)), "E05 new water has no implicit navigation"): return
	wet.water_permissions.cells = [2000,2100]
	water = natural.make_author_draft(Vector2i(1,0), wet, 2)
	if not _check(water.ok and water.data.can_navigate_water(Vector2i(0,20)), "E05 explicit true water permission"): return
	var right: TerrainData = water.data
	Env.initialize(right, str(water.base.site_id))
	if _failed: return
	right.site.inventory.wood = 12
	right.site.inventory.tools = 1 # Fixed geography starts empty; original paid build also requires a tool.
	var storage: Dictionary = Runtime.initialize_item_storage(right.site)
	if not _check(storage.ok, "original legal holder initialization"): return
	var options: Dictionary = {"layout_version": 1, "quarter": 0, "material": "wood", "owner_faction": 1}
	var layout: Dictionary = Runtime.building_cells(right, "bridge", Vector2i(0,20), Vector2i(1,2), options)
	if not _check(layout.ok, "original bridge geometry"): return
	var cells: Array[int] = []
	for value: Variant in layout.cells: cells.append(int(value))
	var banks: Dictionary = Runtime.bridge_layout(right, cells, int(options.quarter))
	if not _check(banks.ok, "original bridge banks: " + str(banks)): return
	right.site.inventory.tools = 0
	var missing_tools_before: PackedByteArray = var_to_bytes(right.site)
	var missing_tools: Dictionary = Runtime.preview_build(right, "bridge", cells, Callable(), options)
	if _failed: return
	if not _check(not missing_tools.ok and missing_tools.code == "MATERIALS" and var_to_bytes(right.site) == missing_tools_before, "original bridge tool prerequisite rejects without mutation: " + str(missing_tools)): return
	right.site.inventory.tools = 1
	var paid_preview: Dictionary = Runtime.preview_build(right, "bridge", cells, Callable(), options)
	if _failed: return
	if not _check(paid_preview.ok and paid_preview.cost == {"wood": 12} and float(paid_preview.work) == 20.0, "original paid bridge preview: " + str(paid_preview)): return
	var bridge: Dictionary = Runtime.request_build(right, "bridge", cells, Callable(), options)
	if not _check(bridge.ok, "original paid bridge fixture: " + str(bridge)): return
	if not _check(int(right.site.inventory.wood) == 0 and int(right.site.inventory.tools) == 1, "original depot paid exactly twelve wood; tool is a prerequisite"): return
	var feature: Dictionary = right.site.features[str(bridge.feature)]
	var task: Dictionary = {"target": "feature:" + str(bridge.feature), "action": "construct", "cell": int(feature.entrance), "mode": "work", "status": "", "progress": 0.0}
	Runtime._feature_work(right, str(bridge.feature), float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	if _failed: return
	if not _check(feature.stage == "complete" and right.effective_height(Vector2i(0,20)) != int(right.height_levels[2000]) and not right.can_navigate_water(Vector2i(0,20)), "E05 bridge single effective surface denies ship"): return
	right.site.terrain_changes["5000"] = 3
	files.append(_file("b.json", wet, "static", Vector2i(1,0)))
	if _failed: return
	var initial_state: Dictionary = right.site.duplicate(true)
	initial_state.erase("world_pin")
	files.append(_file("initial_b.json", initial_state, "initial", Vector2i(1,0)))
	if _failed: return
	path = _package("initial_package.json", files, 2)
	if _failed: return
	var initial_source: RegionData = Data.new()
	admitted = initial_source.load_author_package(path)
	if not _check(admitted.ok, "initial package transport"): return
	var initial: Dictionary = initial_source.project_terrain(Vector2i.ZERO, "author_initial")
	if not _check(initial.ok and int(initial.data.parameters.ramp_visual_halo["100:50"][0]) == 3, "E23 initial neighbour delta, not slot data"): return
	var template_before: Dictionary = initial_source._author_initial.duplicate(true)
	var projected_right: Dictionary = initial_source.project_terrain(Vector2i(1,0), "author_initial")
	if not _check(projected_right.ok, "initial bridge validated by original Store"): return
	if not _check(not projected_right.data.site.has("world_pin") and initial_source._author_initial == template_before, "validation pin erased and raw templates unchanged"): return
	var forbidden: String = folder.path_join("must_not_save_initial.json")
	var denied_save: Dictionary = Store.save(projected_right.data, forbidden)
	if not _check(not denied_save.ok and not FileAccess.file_exists(forbidden), "readonly initial cannot become a gameplay save"): return
	var surface: Dictionary = Slot.boundary_surface(projected_right.data, Vector2i(0,20))
	if not _check(surface.ok and int(surface.height) == right.effective_height(Vector2i(0,20)) and int(surface.height) != int(projected_right.data.height_levels[2000]), "E23 boundary uses effective bridge, halo keeps ground"): return
	if not _check(initial.data.site.is_empty() and initial.data.feature_at.size() == initial.data.size.x * initial.data.size.y, "template-free initial remains pure but has boundary query indexes"): return
	var left_surface: Dictionary = Slot.boundary_surface(initial.data, Vector2i(99,20))
	if not _check(Route.seam_step(initial.data, projected_right.data, 1, 20) == Slot.boundary_surfaces_can_step(left_surface, surface, Vector2i.RIGHT), "E17 original seam and Slot effective surfaces agree"): return
	Route.clear_memory_cache()
	var base_body: Dictionary = Route.effective_terrain(initial_source, Vector2i(1,0))
	var initial_body: Dictionary = Route.effective_terrain(initial_source, Vector2i(1,0), {"projection_mode": "author_initial"})
	if not _check(base_body.ok and initial_body.ok and base_body.data.site.is_empty() and not initial_body.data.site.is_empty(), "E17 base/initial memo separated"): return
	var no_provider: Dictionary = Route.effective_terrain(initial_source, Vector2i(1,0), {"projection_mode": "slot_current"})
	if not _check(not no_provider.ok, "current needs original provider"): return
	var current: Dictionary = Route.effective_terrain(initial_source, Vector2i(1,0), {"projection_mode": "slot_current", "effective_terrain": func(_at: Vector2i) -> Dictionary: return {"ok": true, "data": null, "revision": "unvisited"}})
	if not _check(current.ok and is_same(current.data, initial_body.data) and current.data.site == initial_body.data.site, "current authored unvisited uses same initial memo; no current body overlay"): return
	var different: Dictionary = raw.duplicate(true)
	different.terrain["4949"].height = 4
	var other_files: Array[Dictionary] = []
	other_files.append(_file("other_a.json", different, "static", Vector2i.ZERO))
	if _failed: return
	path = _package("other_package.json", other_files, 3)
	if _failed: return
	var other: RegionData = Data.new()
	admitted = other.load_author_package(path)
	if not _check(admitted.ok and Route.cache_key(other) != Route.cache_key(source), "author revisions cannot share natural cache identity"): return
	var conflict: Dictionary = wet.duplicate(true)
	conflict.water_bodies["1000000000"].id = "different_river"
	files.append(_file("conflict.json", conflict, "static", Vector2i(0,1)))
	if _failed: return
	path = _package("conflict_package.json", files, 4)
	if _failed: return
	var old_identity: Dictionary = initial_source.author_identity()
	var rejected: Dictionary = initial_source.load_author_package(path)
	if not _check(not rejected.ok and rejected.code == "AUTHOR_WATER_ID_CONFLICT" and initial_source.author_identity() == old_identity, "cross-Site body collision preserves source"): return
	if not _mapped_land(): return
	if not _resource_conflicts(): return
	if not _current_contract(natural, initial_source): return
	if not _frame_water_contract(natural): return
	if not _editor_rejection(): return
	if _failed: return
	print("MAP_EDITOR_TERRAIN_CONTRACT_PASS E02/E03/E05/E17/E23 fixture subset; runtime/GPU scopes separate")
	quit(0)

class DraftFixtureSource:
	extends RegionData
	static var natural_path := ""
	func load_manifest(_path: String = DEFAULT_MANIFEST) -> Dictionary:
		return super.load_manifest(natural_path)

class ResourceFixture:
	extends RegionData
	func site_resource_cover(_site: Vector2i) -> Dictionary:
		var cover: PackedByteArray = PackedByteArray()
		cover.resize(100); cover.fill(1)
		return {"ok": true, "enabled": true, "cover": cover}
	func get_water_body(identity: int) -> Dictionary:
		return {"id": 42, "kind": 1, "source_id": "fixture_river", "name": "河"} if identity == 42 else {}
	func _sample_natural_site_meters(easting: float, northing: float, cache: Dictionary) -> Dictionary:
		var sample: Dictionary = super._sample_natural_site_meters(easting, northing, cache)
		if not bool(sample.get("ok", false)): return sample
		var cell: Vector2i = Grid.local_from_mm(roundi(easting * 1000), roundi(northing * 1000))
		if cell.y >= 20 and cell.y < 26:
			sample = sample.duplicate(true)
			sample.water_kind = 1; sample.water_body = 42; sample.water_id = "fixture_river"
		return sample
	func _sample_site_meters(easting: float, northing: float, cache: Dictionary) -> Dictionary:
		return _author_sample(_sample_natural_site_meters(easting, northing, cache), easting, northing)

func _resource_conflicts() -> bool:
	var source: ResourceFixture = ResourceFixture.new()
	var loaded: Dictionary = source.load_manifest(str(natural_record.path))
	if not _check(loaded.ok, "resource fixture real natural loader"): return false
	source.resource_manifest_hash = "a".repeat(64)
	source.resource_rule_revision = Env.FIXED_RESOURCE_RULE
	var original: Dictionary = Adapter.build(source, Vector2i.ZERO)
	if not _check(original.ok, "original Env fixed resource generation"): return false
	var found := {}
	for value: Dictionary in original.data.resource_base.values():
		if int(value.kind) in [Env.Kind.FISH, Env.Kind.TIMBER] and not found.has(int(value.kind)): found[int(value.kind)] = int(value.cell)
	if not _check(found.has(Env.Kind.FISH) and found.has(Env.Kind.TIMBER), "original fish/tree footprints exist; no skipped negative"): return false
	var before: String = JSON.stringify(original.data.resource_base, "", true, true)
	for kind: int in [Env.Kind.FISH, Env.Kind.TIMBER]:
		var raw: Dictionary = _static()
		var index: int = int(found[kind])
		if kind == Env.Kind.FISH: raw.terrain[str(index)] = {"surface": TerrainData.Surface.GRASS, "water_kind": 0, "water_body": -1}
		else:
			raw.water_bodies["1000000000"] = {"id": "pond", "kind": 1}
			raw.terrain[str(index)] = {"surface": TerrainData.Surface.WATER, "water_kind": 1, "water_body": 1000000000}
		source._author_static = {"0:0": raw}
		source._author_pin = {"scenario_id": "resource_fixture", "scenario_revision": 1, "scenario_package_sha256": JSON.stringify(raw).sha256_text()}
		var rejected: Dictionary = Adapter.build(source, Vector2i.ZERO)
		if not _check(not rejected.ok and rejected.code == "AUTHOR_RESOURCE_CONFLICT" and JSON.stringify(original.data.resource_base, "", true, true) == before, "original resource conflict retained " + str(kind)): return false
	return true

func _mapped_land() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(natural_record.path)))
	if not _check(parsed is Dictionary, "mapped manifest fixture"): return false
	parsed.land_condition_rule = "terrain_mapped_potential_v1"
	var record: Dictionary = _json("mapped.json", parsed)
	if _failed: return false
	var source: RegionData = Data.new()
	var loaded: Dictionary = source.load_manifest(folder.path_join(str(record.path)))
	if not _check(loaded.ok, "mapped-potential source loader"): return false
	var natural: Dictionary = source.make_terrain_data(0,0)
	if not _check(natural.ok, "mapped natural body"): return false
	Env.initialize(natural.data, str(natural.base.site_id))
	if _failed: return false
	var authored: Dictionary = source.make_author_draft(Vector2i.ZERO, _static(), 1)
	if not _check(authored.ok, "mapped source with empty author overrides"): return false
	Env.initialize(authored.data, str(authored.base.site_id))
	if _failed: return false
	for field: String in Data.AUTHOR_LAND_FIELDS:
		if not _check(var_to_bytes(natural.data.get(field)) == var_to_bytes(authored.data.get(field)), "mapped-potential preserved " + field): return false
	return true

func _current_contract(natural: RegionData, initial_source: RegionData) -> bool:
	var refused: RegionSaveSlot = Slot.new()
	var unsupported: Dictionary = refused.open_map(initial_source, "must_not_birth", "readonly")
	if not _check(not unsupported.ok and unsupported.code == "AUTHOR_MULTI_SITE_UNSUPPORTED" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://region_lab/worlds/must_not_birth/slots/readonly")), "cross-Site initial package refuses partial initialization and writes nothing"): return false
	var slot: RegionSaveSlot = Slot.new()
	var opened: Dictionary = slot.open_map(natural, "p2a_current_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()], "contract")
	if not _check(opened.ok, "real natural Slot API"): return false
	var site := Vector2i(1,0)
	var selected: Dictionary = slot.open_site(site, false)
	if not _check(selected.ok and selected.get("interactive", false), "original empty-actor current Site"): return false
	var data: TerrainData = selected.data
	data.site.terrain_changes["5000"] = 4
	data.height_levels[5000] = 4
	Runtime.rebuild_terrain_edges(data)
	if _failed: return false
	Env.rebuild_indexes(data)
	if _failed: return false
	var saved: Dictionary = slot.save_site(data)
	if not _check(saved.ok and int(slot._marker.get("generation", 0)) > 0, "real public Slot save publishes commit"): return false
	var sites: Array[Vector2i] = []
	sites.append(site)
	var prepared: Dictionary = slot.prepare_region_route_context(null, {}, sites)
	if not _check(prepared.ok and prepared.context.projection_mode == "slot_current", "real Slot current context"): return false
	var current: Dictionary = Route.effective_terrain(natural, site, prepared.context)
	if not _check(current.ok and int(current.data.height_levels[5000]) == 4 and current.data.site.features.is_empty(), "real current commit is used"): return false
	var initial: Dictionary = initial_source.project_terrain(site, "author_initial")
	if not _check(initial.ok and int(initial.data.height_levels[5000]) == 3 and not initial.data.site.features.is_empty(), "separate initial fixture stays height3/bridge"): return false
	var repeated: Dictionary = slot.prepare_region_route_context(null, {}, sites)
	if not _check(repeated.ok and is_same(current.data, slot._region_route_snapshot[site]), "original current context cache reused"): return false
	var derived: Dictionary = Route.table_from_terrain(current.data, PackedByteArray(), true)
	if not _check(derived.ok, "current component table"): return false
	var component: int = RegionTravelSite.start_component(slot, site, Vector2i(49,49))
	if not _check(component >= 0 and component == Route.component_of(derived, Vector2i(49,49)), "formal start_component uses same current projection"): return false
	slot.clear_route_context_cache()
	return true

func _editor_rejection() -> bool:
	DraftFixtureSource.natural_path = str(natural_record.path)
	var editor: Variant = load("res://scripts/map_editor/map_editor.gd").new()
	editor.source = DraftFixtureSource.new()
	root.add_child(editor)
	if not _check(not editor.draft.is_empty(), "editor original source/provider fixture"): return false
	editor._file.text = "p2a_reject_%d" % Time.get_ticks_usec()
	var saved: bool = editor.save_work()
	if not _check(saved, "editor original saved checkpoint"): return false
	var old: Dictionary = editor.draft.duplicate(true)
	var path: String = editor._saved_path
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var fingerprint: String = editor.terrain.fingerprint()
	var denied: bool = editor.set_cell_patch(Vector2i(49,49), {"height": 6})
	if not _check(not denied and editor.draft == old and editor._saved_path == path and editor.terrain.fingerprint() == fingerprint and FileAccess.get_file_as_bytes(path) == bytes, "illegal edit preserves draft/view/path/file"): return false
	editor.free()
	return true

class ScriptFailureLogger:
	extends Logger
	var host: WeakRef
	var mutex: Mutex = Mutex.new()
	var seen := false
	func _log_error(_function: String, file: String, line: int, _code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != Logger.ERROR_TYPE_SCRIPT: return
		mutex.lock()
		var first: bool = not seen
		seen = true
		mutex.unlock()
		if not first: return
		var target: Variant = host.get_ref()
		if not is_instance_valid(target): return
		if Thread.is_main_thread(): target._script_failure(file, line, rationale)
		else: target.call_deferred("_script_failure", file, line, rationale)

var _logger: ScriptFailureLogger

func _script_failure(file: String, line: int, message: String) -> void:
	_failed = true
	printerr("MAP_EDITOR_TERRAIN_SCRIPT_FAIL: %s:%d %s" % [file, line, message])
	quit(1)

func _intentional_script_fault() -> void:
	var missing: Dictionary = {}
	var value: Variant = missing["intentional_missing_key"]
	print("SCRIPT_FAIL_UNREACHABLE", value)


func _frame_water_contract(source: RegionData) -> bool:
	var raw: Dictionary = _static()
	raw.water_bodies["1000000000"] = {"id": "pond", "kind": 1}
	raw.terrain["2000"] = {"height": 0, "surface": TerrainData.Surface.WATER, "water_kind": 1, "water_body": 1000000000}
	var left: Dictionary = source.make_author_draft(Vector2i.ZERO, raw, 1)
	if not _check(left.ok, "first tile author denial"): return false
	raw.water_permissions.cells = [2000]
	var right: Dictionary = source.make_author_draft(Vector2i(1,0), raw, 2)
	if not _check(right.ok, "offset tile author permission"): return false
	var provider: Callable = func(at: Vector2i) -> Dictionary:
		return {"ok": true, "data": left.data if at == Vector2i.ZERO else right.data, "revision": "frame_fixture"}
	var frame: Dictionary = Route.party_frame_geometry(source, {"version": 1, "world_origin": [0,0], "size": [200,100]}, {"projection_mode": "slot_current", "effective_terrain": provider})
	if not _check(frame.ok and not frame.data.can_navigate_water(Vector2i(0,20)) and frame.data.can_navigate_water(Vector2i(100,20)), "frame offsets permission and preserves first-tile denial"): return false
	if not _check(not frame.data.parameters.has("author_water_permissions") and not frame.data.parameters.has("author_water_changed_cells"), "frame removes already folded tile-local rules"): return false
	return true
