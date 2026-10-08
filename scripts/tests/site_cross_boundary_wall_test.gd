extends "res://scripts/tests/site_bridge_contract_test.gd"
## Run only after cross_boundary.patch is merged. No person handoff is claimed.

class PinnedGeography:
	extends RegionData
	var bases: Dictionary = {}
	var last_created: TerrainData
	func make_terrain_data(x: int, y: int) -> Dictionary:
		var key := Vector2i(x, y)
		if not bases.has(key): return {"ok": false, "code": "MISSING_BASE"}
		var old: TerrainData = bases[key]
		var fresh := TerrainData.new()
		for field: String in ["size", "spawn_cell", "preset", "seed_value"]: fresh.set(field, old.get(field))
		for field: String in ["height_levels", "surface_types", "flags", "cliff_drops", "ramp_edges", "detail_variation",
			"water_kind", "water_body", "fertility", "moisture", "drainage", "foundation", "groundwater"]:
			fresh.set(field, old.get(field).duplicate())
		fresh.parameters = old.parameters.duplicate(true)
		fresh.resource_base = old.resource_base.duplicate(true)
		last_created = fresh
		return {"ok": true, "data": fresh, "base": fresh.parameters.fixed_base.duplicate(true)}
	func sample_meters(_easting: float, _northing: float) -> Dictionary:
		return {"ok": true, "level": 1, "water_kind": 0}

func _run() -> void:
	deadline = Time.get_ticks_msec() + 150000
	_bridge_output("boundary")
	for direction: Vector2i in TerrainData.DIRECTIONS:
		assert(_cross_wall(direction))
	assert(_reciprocal_edges())
	TerrainArmy.release_contact_source()
	print("SITE_CROSS_BOUNDARY_WALL_PASS: four-direction RegionGrid pairs, separately paid original wall IDs, effective two-Site surfaces, checksum-valid original SiteStore reads, damage/demolition/rebuild refresh, slot isolation, corrupt neighbour rejection, reciprocal one-level ramps and half-edge blockers; no person travel/GPU/performance claim")
	quit(0)

func _flat_site(coordinate: Vector2i) -> TerrainData:
	var data := _bridge_fixture()
	data.height_levels.fill(1)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	Runtime.rebuild_terrain_edges(data)
	data.site.id = RegionGrid.site_id(RegionGrid.ATLAS_ID, coordinate)
	data.parameters.fixed_base.site_id = str(data.site.id)
	data.parameters.fixed_base.site = [coordinate.x, coordinate.y]
	data.parameters.fixed_base.terrain_fingerprint = data.fingerprint()
	Env.rebuild_indexes(data)
	return data

func _cross_wall(direction: Vector2i) -> bool:
	var number := TerrainData.DIRECTIONS.find(direction)
	var from_site := Vector2i(-1, 99)
	var from_cell: Vector2i = [Vector2i(50, 0), Vector2i(99, 50), Vector2i(50, 99), Vector2i(0, 50)][number]
	var pair := RegionSaveSlot.boundary_pair(from_site, from_cell, direction)
	assert(pair.ok and pair.site == from_site + Vector2i(direction.x, -direction.y))
	var back := RegionSaveSlot.boundary_pair(pair.site, pair.cell, -direction)
	assert(back.ok and back.site == from_site and back.cell == from_cell)
	var left := _flat_site(from_site)
	var right := _flat_site(pair.site)
	var source := PinnedGeography.new()
	source.manifest_hash = "b".repeat(64)
	source.manifest = {"atlas_id": RegionGrid.ATLAS_ID, "grid_contract_version": 1, "base_revision": "bridge_contract_v1"}
	source.bases[from_site] = _bridge_base(left)
	source.bases[pair.site] = _bridge_base(right)
	var slot := RegionSaveSlot.new()
	slot.source = source
	slot.folder = bridge_output.path_join("direction_" + str(number))
	slot.pin = {"world_instance_id": "boundary_world", "slot_id": "slot_a", "atlas_id": RegionGrid.ATLAS_ID,
		"grid_contract_version": 1, "base_revision": "bridge_contract_v1", "manifest_sha256": source.manifest_hash,
		"ramp_rule_revision": RegionTerrainAdapter.RAMP_RULE_REVISION}
	# These are two independently allocated original paid wall segments.
	var left_key := _formal_feature(left, "stone_wall", from_cell, Vector2i.ONE, {"quarter": number})
	var right_key := _formal_feature(right, "palisade", pair.cell, Vector2i.ONE, {"quarter": (number + 2) % 4})
	assert(left_key == right_key and str(left.site.id) != str(right.site.id))
	var left_path := slot.site_path(from_site)
	var right_path := slot.site_path(pair.site)
	assert(Store.save(left, left_path).ok and Store.save(right, right_path).ok)
	var left_bytes := FileAccess.get_file_as_string(left_path)
	var right_bytes := FileAccess.get_file_as_string(right_path)
	var before := JSON.stringify(left.site)
	var flags_before := left.flags.duplicate()
	var params_before := JSON.stringify(left.parameters)
	var crossing := slot.query_boundary_crossing(left, from_cell, direction)
	assert(crossing.ok, str(crossing))
	assert(crossing.source_feature_id == left_key and crossing.destination_feature_id == right_key)
	assert(crossing.source_surface.height == 3 and crossing.destination_surface.height == 3)
	assert(crossing.source_site_id != crossing.destination_site_id and crossing.to_site == pair.site and crossing.to_cell == pair.cell)
	assert(JSON.stringify(left.site) == before and left.flags == flags_before and JSON.stringify(left.parameters) == params_before)
	assert(FileAccess.get_file_as_string(left_path) == left_bytes and FileAccess.get_file_as_string(right_path) == right_bytes)
	var part := "c:" + str(right.index(pair.cell))
	assert(Runtime.damage_structure_part(right, right_key, part, 100000.0).ok)
	assert(Store.save(right, right_path).ok)
	assert(not slot.query_boundary_crossing(left, from_cell, direction).ok, "A destroyed far wall retained a phantom top")
	assert(Runtime.cancel_feature(right, right_key, Callable(), 1).ok)
	var replacement := _formal_feature(right, "stone_wall", pair.cell, Vector2i.ONE, {"quarter": (number + 2) % 4})
	assert(replacement != right_key and Store.save(right, right_path).ok)
	crossing = slot.query_boundary_crossing(left, from_cell, direction)
	assert(crossing.ok and crossing.destination_feature_id == replacement)
	var original_folder := slot.folder
	slot.folder = bridge_output.path_join("other_world_" + str(number))
	assert(not slot.query_boundary_crossing(left, from_cell, direction).ok)
	assert(source.last_created.site.is_empty(), "Unvisited query initialized mutable Site state")
	assert(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(slot.folder)), "Query wrote an unvisited neighbour")
	slot.folder = original_folder
	var file := FileAccess.open(right_path, FileAccess.WRITE)
	assert(file != null)
	file.store_string("{}")
	file.close()
	assert(not slot.query_boundary_crossing(left, from_cell, direction).ok)
	assert(FileAccess.get_file_as_string(right_path) == "{}" and FileAccess.get_file_as_string(left_path) == left_bytes)
	assert(JSON.stringify(left.site) == before and left.flags == flags_before)
	assert(Runtime.cancel_feature(left, left_key, Callable(), 1).ok)
	slot.folder = bridge_output.path_join("other_world_" + str(number))
	var fresh_crossing := slot.query_boundary_crossing(left, from_cell, direction)
	assert(fresh_crossing.ok and fresh_crossing.destination_data.site.is_empty(), str(fresh_crossing))
	assert(fresh_crossing.destination_feature_id == "" and fresh_crossing.destination_path == "")
	assert(fresh_crossing.destination_site_id == RegionGrid.site_id(RegionGrid.ATLAS_ID, pair.site))
	assert(source.last_created.site.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(slot.folder)))
	return true

func _reciprocal_edges() -> bool:
	var data := _flat_site(Vector2i.ZERO)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var edge := TerrainData.DIRECTIONS.find(direction)
		var reverse := (edge + 2) % 4
		var a := {"ok": true, "walkable": true, "height": 2, "ramp": 1 << edge}
		var b := {"ok": true, "walkable": true, "height": 3, "ramp": 1 << reverse}
		assert(RegionSaveSlot.boundary_surfaces_can_step(a, b, direction))
		assert(RegionSaveSlot.boundary_surfaces_can_step(b, a, -direction))
		b.ramp = 0
		assert(not RegionSaveSlot.boundary_surfaces_can_step(a, b, direction))
		b.height = 2
		assert(RegionSaveSlot.boundary_surfaces_can_step(a, b, direction))
		b.ramp = 1 << (reverse + 4)
		assert(not RegionSaveSlot.boundary_surfaces_can_step(a, b, direction))
		b.ramp = 0
		b.walkable = false
		assert(not RegionSaveSlot.boundary_surfaces_can_step(a, b, direction))
		var cell: Vector2i = [Vector2i(50, 0), Vector2i(99, 50), Vector2i(50, 99), Vector2i(0, 50)][edge]
		var mask := {}
		Runtime._geometry_edge(data, mask, cell, cell + direction)
		assert(mask.size() == 1 and int(mask[data.index(cell)]) == 1 << edge)
	return true
