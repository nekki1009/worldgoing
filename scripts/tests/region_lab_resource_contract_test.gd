extends SceneTree

const Atlas = preload("res://scripts/region_lab/region_data.gd")
const Adapter = preload("res://scripts/region_lab/region_terrain_adapter.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Slot = preload("res://scripts/region_lab/region_save_slot.gd")

# The same geographic sampler without a resource layer supplies the comparison
# baseline; this proxy owns no terrain, resources or mutable Site state.
class GeographyOnly extends RefCounted:
	var source: RegionData
	var manifest: Dictionary
	var manifest_hash: String
	func _init(value: RegionData) -> void:
		source = value
		manifest = value.manifest
		manifest_hash = value.manifest_hash
	func _sample_site_meters(east: float, north: float, cache: Dictionary) -> Dictionary:
		return source._sample_site_meters(east, north, cache)

var _started := false
var _finished := false
var _resource_checks := 0

func _init() -> void:
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if _started and not _finished:
		printerr("REGION_RESOURCE_CONTRACT_FAILED: assertion interrupted the synchronous test")
		quit(1)
	return false

func _run() -> void:
	_started = true
	assert(_synthetic(), "Synthetic resource checks aborted")
	var source := Atlas.new()
	var loaded := source.load_manifest()
	assert(loaded.ok, str(loaded))
	var layer_text := FileAccess.get_file_as_string(Atlas.RESOURCE_MANIFEST)
	var layer: Dictionary = JSON.parse_string(layer_text)
	assert(source.manifest_hash == Atlas.RESOURCE_GEOGRAPHY_SHA)
	assert(source.resource_manifest_hash == layer_text.sha256_text()
		and source.resource_rule_revision == Env.FIXED_RESOURCE_RULE)
	# Source audit verified 100 forest, zero water and one level at the 20m lattice.
	var forest_site := Vector2i(1170, 13252)
	var sampled: Dictionary = {}
	for sample: Dictionary in layer.samples:
		var parts := str(sample.region_key).split(",")
		var site := Vector2i(int(parts[0]) * 100 + Grid.floor_div(int(sample.col), 10),
			int(parts[1]) * 100 + 99 - Grid.floor_div(int(sample.row), 10))
		var cover_result := source.site_resource_cover(site)
		assert(cover_result.ok and cover_result.enabled and cover_result.cover.size() == 100)
		var offset := posmod(int(sample.row), 10) * 10 + posmod(int(sample.col), 10)
		assert(int(cover_result.cover[offset]) == int(sample.category), "Source category changed at " + str(site))
		sampled[int(sample.category)] = true
	assert(sampled.size() == 8)
	var forest_cover := source.site_resource_cover(forest_site)
	assert(forest_cover.ok and forest_cover.cover.count(1) == 100)
	var records: Array[Dictionary] = []
	for site: Vector2i in [forest_site, Vector2i(1545, 12170)]:
		var record := _real_site(source, site, site == forest_site)
		assert(not record.is_empty(), "Real resource Site checks aborted: " + str(site))
		records.append(record)
	var harvest_record := _real_forest_save(source, forest_site)
	assert(not harvest_record.is_empty(), "Real forest harvest/save checks aborted")
	assert(source.cache_stats().bytes <= Atlas.MAX_CACHE_BYTES)
	_finished = true
	print("REGION_RESOURCE_CONTRACT_PASS ", JSON.stringify({"source_categories": sampled.size(),
		"resources_checked": _resource_checks, "sites": records,
		"real_forest_harvest_save": harvest_record,
		"resource_layer_sha256": source.resource_manifest_hash, "rule": source.resource_rule_revision}))
	quit(0)

func _real_site(source: RegionData, site: Vector2i, expect_forest: bool) -> Dictionary:
	var geographic := Adapter.build(GeographyOnly.new(source), site)
	assert(geographic.ok, str(geographic))
	var original: TerrainData = geographic.data
	assert(original.resource_base.is_empty())
	var built := source.make_terrain_data(site.x, site.y)
	assert(built.ok, str(built))
	var data: TerrainData = built.data
	assert(data.fingerprint() == original.fingerprint()
		and data.water_kind == original.water_kind and data.water_body == original.water_body,
		"Resource placement changed the original geography or water")
	assert(built.base.resource_layer_sha256 == source.resource_manifest_hash
		and built.base.resource_rule_revision == source.resource_rule_revision
		and built.base.resource_fingerprint == _resource_hash(data)
		and data.parameters.fixed_base == built.base)
	assert(_validate_resources(data, built.metadata.resource_cover))
	for resource: Dictionary in data.resource_base.values():
		var elevation := float(built.metadata.absolute_elevation_m[int(resource.cell)])
		if int(resource.kind) == Env.Kind.TIMBER:
			assert(elevation < 3600.0, "Real alpine terrain retained forest timber")
		if elevation >= 3850.0:
			assert(int(resource.kind) != Env.Kind.WILDLIFE, "Unverified summit wildlife was populated")
	if expect_forest:
		assert(_kind_count(data, Env.Kind.TIMBER) > 0, "Mapped forest Site generated no timber")
	else:
		assert(data.water_kind.has(0) and data.water_kind.has(2), "Lanyu lost its land/sea boundary")
	var repeated := source.make_terrain_data(site.x, site.y)
	assert(repeated.ok and repeated.base == built.base
		and repeated.data.resource_base == data.resource_base
		and repeated.data.static_blocked == data.static_blocked
		and repeated.data.site.is_empty(), "Rebuilding a Site changed its resource base")
	return {"site": [site.x, site.y], "resource_count": data.resource_base.size(),
		"timber": _kind_count(data, Env.Kind.TIMBER), "fish": _kind_count(data, Env.Kind.FISH),
		"salt": _kind_count(data, Env.Kind.SALT), "resource_fingerprint": _resource_hash(data)}

func _real_forest_save(source: RegionData, site: Vector2i) -> Dictionary:
	var slot := Slot.new()
	var opened_map := slot.open_map(source, "real_resources_%d" % Time.get_ticks_usec(), "contract")
	assert(opened_map.ok, str(opened_map))
	var opened := slot.open_site(site)
	assert(opened.ok and opened.interactive, str(opened))
	var data: TerrainData = opened.data
	assert(data.site.inventory.is_empty() and data.site.get("actors", {}).is_empty())
	var fingerprint := _resource_hash(data)
	var fixed_base: Dictionary = data.parameters.fixed_base.duplicate(true)
	assert(fingerprint == fixed_base.resource_fingerprint)
	var target := ""
	var work_cell := Vector2i(-1, -1)
	var nearest := INF
	for key: String in data.resource_base:
		if int(data.resource_base[key].kind) != Env.Kind.TIMBER:
			continue
		for cell: Vector2i in Env.work_cells(data, key):
			var distance := Vector2(cell - data.spawn_cell).length_squared()
			if distance < nearest:
				nearest = distance
				target = key
				work_cell = cell
	assert(not target.is_empty() and (work_cell == data.spawn_cell
		or not data.path_between(data.spawn_cell, work_cell).is_empty()), "Real forest has no reachable timber work cell")
	# Only the fixture supplies tools; the real fixed source contributes no stock.
	data.site.inventory["tools"] = 1
	var capacity := int(data.resource_base[target].capacity)
	var harvested := SiteRuntime.harvest(data, target, work_cell, data.site.manual.cargo)
	assert(harvested.ok, str(harvested))
	var taken := int(harvested.taken)
	var remaining := int(Env.resource(data, target).remaining)
	var recovery := int(Env.resource(data, target).next_recovery)
	assert(taken == mini(capacity, Env.BATCH[Env.Kind.TIMBER]) and remaining == capacity - taken
		and recovery > int(data.site.minute) and int(data.site.manual.cargo.wood) == taken)
	assert(_resource_hash(data) == fingerprint, "Harvest mutated the immutable real resource base")
	var saved := slot.save_site(data)
	assert(saved.ok, str(saved))
	var resumed := slot.open_site(site)
	assert(resumed.ok, str(resumed))
	var loaded: TerrainData = resumed.data
	var resource := Env.resource(loaded, target)
	assert(loaded.parameters.fixed_base == fixed_base and _resource_hash(loaded) == fingerprint
		and loaded.resource_base == data.resource_base, "Real resource pin or base changed on readback")
	assert(int(resource.remaining) == remaining and int(resource.next_recovery) == recovery
		and loaded.site.changes.size() == 1 and loaded.site.changes.has(target),
		"Real forest harvest delta was lost or refilled on readback")
	assert(int(loaded.site.manual.cargo.wood) == taken and int(loaded.site.inventory.tools) == 1
		and loaded.site.get("actors", {}).is_empty(), "Harvest cargo or explicit fixture stock changed on readback")
	return {"site": [site.x, site.y], "resource": target, "taken": taken,
		"remaining": remaining, "next_recovery": recovery, "save_path": slot.site_path(site)}

func _synthetic() -> bool:
	var lowland_height := _heights(0.0)
	for category: int in [0, 4, 6, 7]:
		var empty_land := _terrain()
		var cover := _cover(category)
		var before := empty_land.fingerprint()
		Env.populate_fixed_resources(empty_land, cover, Vector2i(37, 91), lowland_height)
		assert(empty_land.resource_base.is_empty(), "Unknown, farmland, untyped quarry or built land invented deposits")
		assert(empty_land.fingerprint() == before and _validate_resources(empty_land, cover))
	var forest := _terrain()
	for y: int in range(100):
		for x: int in range(50, 100):
			forest.height_levels[forest.index(Vector2i(x, y))] = 3
		var west := forest.index(Vector2i(49, y))
		var east := forest.index(Vector2i(50, y))
		forest.ramp_edges[west] = 1 << 1
		forest.ramp_edges[east] = 1 << 3
		forest.flags[west] |= TerrainData.Flag.RAMP
		forest.flags[east] |= TerrainData.Flag.RAMP | TerrainData.Flag.CLIFF
		forest.cliff_drops[east * 4 + 3] = 1
	var forest_fingerprint := forest.fingerprint()
	Env.populate_fixed_resources(forest, _cover(1), Vector2i(37, 91), lowland_height)
	assert(forest.fingerprint() == forest_fingerprint and _kind_count(forest, Env.Kind.TIMBER) > 0)
	assert(_validate_resources(forest, _cover(1)))
	assert(forest.is_walkable(forest.spawn_cell)
		and not forest.path_between(forest.spawn_cell, Vector2i(51, 50)).is_empty(),
		"Blocking resources closed the original connected platform")
	var forest_hash := _resource_hash(forest)
	Env.populate_fixed_resources(forest, _cover(1), Vector2i(37, 91), lowland_height)
	assert(_resource_hash(forest) == forest_hash and forest.site.is_empty())
	var alpine_plants := 0
	for elevation: float in [3599.0, 3600.0, 3849.0, 3850.0]:
		var alpine := _terrain()
		var before := alpine.fingerprint()
		Env.populate_fixed_resources(alpine, _cover(1), Vector2i(37, 91), _heights(elevation))
		assert(_validate_resources(alpine, _cover(1)) and alpine.fingerprint() == before)
		assert((_kind_count(alpine, Env.Kind.TIMBER) > 0) == (elevation < 3600.0),
			"Timber crossed the 3600m alpine boundary")
		var plants := _kind_count(alpine, Env.Kind.FOOD) + _kind_count(alpine, Env.Kind.HERB)
		assert(plants > 0, "Alpine grass/shrub resources were all removed")
		if elevation == 3600.0:
			alpine_plants = plants
		elif elevation == 3849.0:
			assert(plants == alpine_plants, "Alpine resources changed inside one height band")
		elif elevation == 3850.0:
			assert(plants < alpine_plants and _kind_count(alpine, Env.Kind.WILDLIFE) == 0,
				"Summit resources ignored the 3850m sparse-plants/no-wildlife boundary")
	for water: int in [1, 2, 3, 4]:
		var coast := _terrain()
		for y: int in range(100):
			for x: int in range(1, 100, 2):
				var index := coast.index(Vector2i(x, y))
				coast.surface_types[index] = TerrainData.Surface.WATER
				coast.flags[index] = TerrainData.Flag.BLOCKED | TerrainData.Flag.WET
				coast.water_kind[index] = water
				coast.water_body[index] = 1 if water == 2 else water + 10
		var terrain_hash := coast.fingerprint()
		var water_kinds := coast.water_kind.duplicate()
		var water_bodies := coast.water_body.duplicate()
		Env.populate_fixed_resources(coast, _cover(0), Vector2i(37, 91), lowland_height)
		assert(coast.fingerprint() == terrain_hash and coast.water_kind == water_kinds
			and coast.water_body == water_bodies, "Resource placement changed water classification")
		assert(_validate_resources(coast, _cover(0)))
		assert((_kind_count(coast, Env.Kind.FISH) > 0) == (water in [1, 2]))
		assert((_kind_count(coast, Env.Kind.SALT) > 0) == (water == 2))
		if water in [3, 4]:
			assert(coast.resource_base.is_empty(), "Unverified salinity invented fish or salt")
		elif water == 2:
			for index: int in range(10000):
				if coast.water_kind[index] == 2:
					coast.height_levels[index] = 3
			Env.populate_fixed_resources(coast, _cover(0), Vector2i(37, 91), lowland_height)
			assert(coast.resource_base.is_empty(), "Water resources ignored an inaccessible shore height")
	return true

func _terrain() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(100, 100))
	data.height_levels.fill(2)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.water_kind.resize(10000)
	data.water_body.resize(10000)
	data.water_body.fill(-1)
	data.static_blocked.resize(10000)
	data.spawn_cell = Vector2i(20, 50)
	return data

func _cover(category: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(100)
	result.fill(category)
	return result

func _heights(elevation: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(10000)
	result.fill(elevation)
	return result

func _resource_hash(data: TerrainData) -> String:
	return JSON.stringify(data.resource_base, "", true, true).sha256_text()

func _kind_count(data: TerrainData, kind: int) -> int:
	var count := 0
	for resource: Dictionary in data.resource_base.values():
		count += int(int(resource.kind) == kind)
	return count

func _validate_resources(data: TerrainData, cover: PackedByteArray) -> bool:
	assert(data.site.is_empty() and data.site.get("inventory", {}).is_empty()
		and data.site.get("actors", {}).is_empty() and data.ground_loot_at.is_empty(),
		"Resource preview created mutable Site, stock or persons")
	assert(data.static_blocked.size() == 10000 and data.feature_at.size() == 10000)
	assert(data.feature_at.count(0) == 10000, "Preview invented a constructed feature")
	var blockers: Dictionary = {}
	for key: String in data.resource_base:
		var resource: Dictionary = data.resource_base[key]
		var kind := int(resource.kind)
		var index := int(resource.cell)
		assert(kind >= 0 and kind < Env.NAMES.size() and index >= 0 and index < 10000)
		assert(key == "%d:%d" % [kind, index] and int(resource.capacity) > 0
			and int(resource.variant) in [0, 1, 2] and int(resource.recover) == Env.RECOVERY[kind])
		assert(kind not in [Env.Kind.STONE, Env.Kind.IRON, Env.Kind.CLAY], "Land cover invented an unidentified mineral")
		assert(resource.cells is Array and not resource.cells.is_empty() and resource.cells.has(index))
		assert(int(resource.water) == int(data.water_body[index]))
		var anchor := data.cell_from_index(index)
		var habitat := int(cover[Grid.floor_div(anchor.y, 10) * 10 + Grid.floor_div(anchor.x, 10)])
		if kind in [Env.Kind.FISH, Env.Kind.SALT]:
			assert(data.water_kind[index] in [1, 2])
			assert(kind != Env.Kind.SALT or data.water_kind[index] == 2)
			assert(Env._shore_work_cell(data, anchor) >= 0, "Water resource has no same-height shore")
		else:
			assert(data.is_terrain_walkable(anchor) and habitat in [1, 2, 3, 5])
			assert(kind != Env.Kind.TIMBER or habitat in [1, 5])
		assert(bool(resource.blocks) == (kind in [Env.Kind.TIMBER, Env.Kind.STONE]))
		if bool(resource.blocks):
			assert(Vector2(anchor - data.spawn_cell).length() >= 6.0)
			for direction: Vector2i in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var adjacent := anchor + direction
				assert(not data.contains(adjacent) or data.ramp_edges[data.index(adjacent)] == 0,
					"Blocking resource occupied a ramp or its opening")
			blockers[index] = true
		var occupied: Dictionary = {}
		for cell_index: int in resource.cells:
			assert(cell_index >= 0 and cell_index < 10000 and not occupied.has(cell_index))
			occupied[cell_index] = true
			var cell := data.cell_from_index(cell_index)
			assert(absi(cell.x - anchor.x) + absi(cell.y - anchor.y) <= 1)
			assert(data.resources_at.get(cell_index, []).has(key))
			if kind == Env.Kind.FISH:
				assert(data.water_body[cell_index] == data.water_body[index] and data.water_kind[cell_index] in [1, 2])
			elif kind != Env.Kind.SALT:
				assert(data.is_terrain_walkable(cell))
		_resource_checks += 1
	for index: int in range(10000):
		assert((data.static_blocked[index] != 0) == blockers.has(index))
	return true
