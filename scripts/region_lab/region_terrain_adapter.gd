class_name RegionTerrainAdapter
extends RefCounted

const Grid = preload("res://scripts/region_lab/region_grid.gd")
const SIDE := 100
const HALO_SIDE := SIDE + 2
const RAMP_RULE_REVISION := "sparse_platform_passes_v1"

static func build(source: RefCounted, site: Vector2i) -> Dictionary:
	var samples: Array[Dictionary] = []
	var centre_cache: Dictionary = {} # One build only; typically 12x12 source cells.
	var ramp_visual_halo: Dictionary = {}
	# A global two-metre halo supplies every edge, including all four corners.
	for y: int in range(-1, SIDE + 1):
		for x: int in range(-1, SIDE + 1):
			var sample: Dictionary = source._sample_site_meters(site.x * 200.0 + x * 2.0 + 1.0, site.y * 200.0 + (SIDE - 1 - y) * 2.0 + 1.0, centre_cache)
			if not sample.ok:
				return sample
			samples.append(sample)
			if x < 0 or y < 0 or x >= SIDE or y >= SIDE:
				ramp_visual_halo["%d:%d" % [x, y]] = [int(sample.level), int(sample.water_kind)]
	var data := TerrainData.new()
	data.allocate(Vector2i(SIDE, SIDE))
	data.preset = TerrainPreset.Kind.PLAINS
	var identity := Grid.site_id(str(source.manifest.atlas_id), site)
	data.seed_value = int(identity.sha256_text().substr(0, 7).hex_to_int())
	data.parameters = TerrainPreset.defaults(data.preset)
	data.parameters["size"] = Vector2i(SIDE, SIDE)
	data.parameters["max_height"] = 5
	data.parameters["micro_strength"] = 0.0
	data.parameters["composition"] = "fixed_geography"
	# A named ocean-mask gameplay licence. Inland/unknown water stays unlicensed;
	# this does not claim measured seabed depth or alter the infantry walk mask.
	data.parameters["navigable_water_version"] = 1
	data.parameters["navigable_water_source"] = "fixed-ocean-mask-rule-v1"
	data.parameters["navigable_water_cells"] = []
	# Rebuildable source evidence for display-only cross-Site ramp joining.
	data.parameters["ramp_visual_halo"] = ramp_visual_halo
	var absolute_height := PackedFloat32Array()
	absolute_height.resize(SIDE * SIDE)
	var quality := PackedByteArray()
	quality.resize(SIDE * SIDE)
	var estimated_cells := 0
	data.water_kind.resize(SIDE * SIDE)
	data.water_body.resize(SIDE * SIDE)
	data.water_body.fill(-1)
	data.static_blocked.resize(SIDE * SIDE)
	var best_spawn := INF
	var water_cells := 0
	for y: int in range(SIDE):
		for x: int in range(SIDE):
			var cell := Vector2i(x, y)
			var index := data.index(cell)
			var sample: Dictionary = samples[(y + 1) * HALO_SIDE + x + 1]
			var water := int(sample.water_kind)
			absolute_height[index] = float(sample.elevation_m) if bool(sample.elevation_valid) else NAN
			quality[index] = int(sample.get("source_quality_code", 0))
			if quality[index] >= 2:
				estimated_cells += 1
			data.height_levels[index] = int(sample.level)
			data.water_kind[index] = water
			data.surface_types[index] = TerrainData.Surface.WATER if water > 0 else TerrainData.Surface.GRASS
			data.flags[index] = TerrainData.Flag.BLOCKED | TerrainData.Flag.WET if water > 0 else TerrainData.Flag.WALKABLE
			data.detail_variation[index] = 128
			if water > 0:
				water_cells += 1
				data.water_body[index] = int(sample.get("water_body", 1))
				if water == 2 and str(sample.get("water_id", "")) == "ocean" and data.water_body[index] == 1:
					data.parameters.navigable_water_cells.append(index)
			else:
				var distance := Vector2(cell).distance_squared_to(Vector2(49.5, 49.5))
				if distance < best_spawn:
					best_spawn = distance
					data.spawn_cell = cell
			for direction: int in range(4):
				var neighbour := cell + TerrainData.DIRECTIONS[direction]
				var adjacent: Dictionary = samples[(neighbour.y + 1) * HALO_SIDE + neighbour.x + 1]
				var difference := int(sample.level) - int(adjacent.level)
				data.cliff_drops[index * 4 + direction] = maxi(difference, 0)
				if difference > 0:
					data.flags[index] |= TerrainData.Flag.CLIFF
				if water == 0 and int(adjacent.water_kind) > 0:
					data.flags[index] |= TerrainData.Flag.SHORE
	# Reuse the original generator's spanning passes between same-height platforms.
	# The Site ID pins the ordering; one-level height alone is not a pass.
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed_value
	TerrainGenerator._connect_platforms(data, rng)
	for direction: int in range(4):
		var contacts := PackedInt32Array()
		for offset: int in range(SIDE):
			var cell := boundary_cell(direction, offset)
			var outside := cell + TerrainData.DIRECTIONS[direction]
			var sample: Dictionary = samples[(cell.y + 1) * HALO_SIDE + cell.x + 1]
			var neighbour: Dictionary = samples[(outside.y + 1) * HALO_SIDE + outside.x + 1]
			contacts.append(boundary_contact(int(sample.level), int(sample.water_kind), int(neighbour.level), int(neighbour.water_kind)))
		for offset: int in boundary_passes(contacts):
			var index := data.index(boundary_cell(direction, offset))
			data.ramp_edges[index] |= 1 << direction
			data.flags[index] |= TerrainData.Flag.RAMP
	# Rebuildable immutable-base evidence; only height deltas are saved. Restoring
	# an edited height must restore the same valid pass in memory and after load.
	data.parameters["fixed_ramp_edges"] = data.ramp_edges.duplicate()
	var resource_cover := PackedByteArray()
	var resources_enabled := false
	if source.has_method("site_resource_cover"):
		var resources: Dictionary = source.site_resource_cover(site)
		if not bool(resources.get("ok", false)):
			return resources
		resources_enabled = bool(resources.get("enabled", false))
		if resources_enabled:
			resource_cover = resources.cover
			SiteEnvironment.populate_fixed_resources(data, resource_cover, site, absolute_height)
	var base := {"base_kind": "fixed_geography", "atlas_id": str(source.manifest.atlas_id),
		"grid_contract_version": Grid.CONTRACT_VERSION, "base_revision": str(source.manifest.base_revision),
		"manifest_sha256": str(source.manifest_hash), "site_id": identity, "site": [site.x, site.y],
		"terrain_fingerprint": data.fingerprint(), "ramp_rule_revision": RAMP_RULE_REVISION}
	if resources_enabled:
		base["resource_layer_sha256"] = source.resource_manifest_hash
		base["resource_rule_revision"] = source.resource_rule_revision
		base["resource_fingerprint"] = JSON.stringify(data.resource_base, "", true, true).sha256_text()
	data.parameters["fixed_base"] = base.duplicate(true)
	return {"ok": true, "code": "OK", "message": "固定地形已展開", "data": data, "base": base,
		"metadata": {"site_id": identity, "site": site, "absolute_elevation_m": absolute_height,
			"source_quality_codes": quality, "estimated_elevation_cells": estimated_cells,
			"water_cells": water_cells, "land_cells": SIDE * SIDE - water_cells,
			"can_place_probe": data.spawn_cell != Vector2i(-1, -1), "source_quality": str(source.manifest.get("quality", "source_limited")),
			"height_rule": str(source.manifest.get("terrain_rule", "packaged_relative_levels_v1")),
			"height_levels_are_metres": false, "resource_cover": resource_cover,
			"resource_source_summary": "地類範圍依 OSM；2m 配置、棲地資源及存量為遊戲規則。未標示地類與未確認礦種不代表沒有資源。" if resources_enabled else "此來源尚未提供資源圖層。"}}

static func boundary_cell(direction: int, offset: int) -> Vector2i:
	return [Vector2i(offset, 0), Vector2i(SIDE - 1, offset), Vector2i(offset, SIDE - 1), Vector2i(0, offset)][direction]

static func boundary_contact(level: int, water: int, other_level: int, other_water: int) -> int:
	# Each side of a contiguous contact is a same-level connected platform.
	return level * 8 + other_level if water == 0 and other_water == 0 and absi(level - other_level) == 1 else -1

static func boundary_passes(contacts: PackedInt32Array) -> PackedInt32Array:
	# Both Sites scan west-to-east / north-to-south. Swapping the two levels
	# preserves run boundaries and the midpoint, including after saved leveling.
	var selected := PackedInt32Array()
	var start := 0
	while start < contacts.size():
		var end := start + 1
		while end < contacts.size() and contacts[end] == contacts[start]:
			end += 1
		if contacts[start] >= 0:
			selected.append(floori(float(start + end - 1) * 0.5))
		start = end
	return selected
