class_name RegionTerrainAdapter
extends RefCounted

const Grid = preload("res://scripts/region_lab/region_grid.gd")
const SIDE := 100
const HALO_SIDE := SIDE + 2
const RAMP_RULE_REVISION := "sparse_platform_passes_v1"

## `natural_samples`: the natural (apply_author false) samples of this Site, already taken (an authored build passes its
## own to the natural build it needs for the resource base; 開局速度 2026-11-27).
static func build(source: RefCounted, site: Vector2i, apply_author: bool = true, natural_samples: Array[Dictionary] = []) -> Dictionary:
	var samples: Array[Dictionary] = []
	var centre_cache: Dictionary = {} # One build only; typically 12x12 source cells.
	var ramp_visual_halo: Dictionary = {}
	# An authored Site with resources also builds its natural self for the resource base (below). Its authored samples
	# are the natural ones with the static layer applied (_sample_site_meters is _author_sample of _sample_meters), so
	# each position is sampled once and the natural build reuses them (about 120 ms of 560 a build).
	var natural_taken: Array[Dictionary] = []
	var share_natural: bool = apply_author and natural_samples.is_empty() and source.has_method("author_static_for") 		and source.has_method("_author_sample") and source.has_method("site_resource_cover") and not source.author_static_for(site).is_empty()
	# A global two-metre halo supplies every edge, including all four corners.
	for y: int in range(-1, SIDE + 1):
		for x: int in range(-1, SIDE + 1):
			var sample: Dictionary
			var easting := site.x * 200.0 + x * 2.0 + 1.0
			var northing := site.y * 200.0 + (SIDE - 1 - y) * 2.0 + 1.0
			if not natural_samples.is_empty(): sample = natural_samples[samples.size()]
			elif share_natural:
				var natural_sample: Dictionary = source._sample_natural_site_meters(easting, northing, centre_cache)
				natural_taken.append(natural_sample)
				sample = source._author_sample(natural_sample, easting, northing)
			elif apply_author: sample = source._sample_site_meters(easting, northing, centre_cache)
			else: sample = source._sample_natural_site_meters(easting, northing, centre_cache)
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
	if source.manifest.has("land_condition_rule"):
		# RegionData already checked the exact named rule before publishing manifest.
		if not source.manifest.land_condition_rule is String or source.manifest.land_condition_rule != "terrain_mapped_potential_v1": return {"ok": false, "code": "INVALID_LAND_CONDITION_RULE"}
		data.parameters["fixed_land_condition_rule"] = str(source.manifest.land_condition_rule)
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
			if apply_author and source.has_method("author_static_for") and not source.author_static_for(site).is_empty():
				# Reuse this owner with natural samples; never regenerate away an original footprint.
				var natural: Dictionary = build(source, site, false, natural_taken)
				if not bool(natural.get("ok", false)): return natural
				data.resource_base = natural.data.resource_base.duplicate(true)
				SiteEnvironment.rebuild_indexes(data)
			else: SiteEnvironment.populate_fixed_resources(data, resource_cover, site, absolute_height)
	if apply_author and source.has_method("author_static_for") and not source.author_static_for(site).is_empty() and int(source.author_static_for(site).get("format", 1)) == 2:
		var layered: Dictionary = source.apply_author_layers(data, site)
		if not bool(layered.get("ok", false)): return layered
		water_cells = 0
		best_spawn = INF
		data.spawn_cell = Vector2i(-1, -1)
		for index: int in range(SIDE * SIDE):
			if data.water_kind[index] > 0: water_cells += 1
			elif data.is_walkable(data.cell_from_index(index)):
				var cell: Vector2i = data.cell_from_index(index)
				var distance: float = Vector2(cell).distance_squared_to(Vector2(49.5, 49.5))
				if distance < best_spawn:
					best_spawn = distance
					data.spawn_cell = cell
	var base := {"base_kind": "fixed_geography", "atlas_id": str(source.manifest.atlas_id),
		"grid_contract_version": Grid.CONTRACT_VERSION, "base_revision": str(source.manifest.base_revision),
		"manifest_sha256": str(source.manifest_hash), "site_id": identity, "site": [site.x, site.y],
		"terrain_fingerprint": data.fingerprint(), "ramp_rule_revision": RAMP_RULE_REVISION}
	if data.parameters.has("fixed_land_condition_rule"):
		base["land_condition_rule"] = data.parameters.fixed_land_condition_rule
	if resources_enabled:
		base["resource_layer_sha256"] = source.resource_manifest_hash
		base["resource_rule_revision"] = source.resource_rule_revision
		base["resource_fingerprint"] = JSON.stringify(data.resource_base, "", true, true).sha256_text()
	if apply_author and source.has_method("author_identity"):
		var author: Dictionary = source.author_identity()
		if not author.is_empty():
			if not valid_author_identity(author): return {"ok": false, "code": "INVALID_AUTHOR_IDENTITY"}
			for key: String in AUTHOR_FIELDS: base[key] = author[key]
			# P1A admits the unchanged static base; edited layers belong to P2.
			data.fertility.resize(SIDE * SIDE); data.moisture.resize(SIDE * SIDE)
			data.drainage.resize(SIDE * SIDE); data.foundation.resize(SIDE * SIDE); data.groundwater.resize(SIDE * SIDE)
			if data.parameters.get("fixed_land_condition_rule", "") == "terrain_mapped_potential_v1":
				SiteEnvironment._populate_soil_conditions(data, false)
			SiteEnvironment.restore_author_land(data)
			base["effective_environment_sha256"] = author_environment_fingerprint(data)
	data.parameters["fixed_base"] = base.duplicate(true)
	return {"ok": true, "code": "OK", "message": "固定地形已展開", "data": data, "base": base,
		"metadata": {"site_id": identity, "site": site, "absolute_elevation_m": absolute_height,
			"source_quality_codes": quality, "estimated_elevation_cells": estimated_cells,
			"water_cells": water_cells, "land_cells": SIDE * SIDE - water_cells,
			"can_place_probe": data.spawn_cell != Vector2i(-1, -1), "source_quality": str(source.manifest.get("quality", "source_limited")),
			"height_rule": str(source.manifest.get("terrain_rule", "packaged_relative_levels_v1")),
			"height_levels_are_metres": false, "resource_cover": resource_cover,
			"resource_source_summary": "地類範圍依 OSM；2m 配置、棲地資源及存量為遊戲規則。未標示地類與未確認礦種不代表沒有資源。" if resources_enabled else "此來源尚未提供資源圖層。"}}

const AUTHOR_FIELDS := ["scenario_id", "scenario_revision", "scenario_package_sha256"]

static func has_author_identity(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key: String in AUTHOR_FIELDS:
		if value.has(key): return true
	return value.has("effective_environment_sha256")

static func author_id_valid(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64: return false
	for i: int in range(value.length()):
		if "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".find(value.substr(i, 1)) < 0: return false
	return true

static func author_digest_valid(value: Variant) -> bool:
	return value is String and value.length() == 64 and value == value.to_lower() and value.is_valid_hex_number(false)

static func author_integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high

static func valid_author_identity(value: Variant, environment: bool = false) -> bool:
	if not value is Dictionary: return false
	if not has_author_identity(value): return true # Original natural/legacy identity.
	if not author_id_valid(value.get("scenario_id")) or not author_integer(value.get("scenario_revision"), 1, 2147483647) or not author_digest_valid(value.get("scenario_package_sha256")): return false
	return (not environment and not value.has("effective_environment_sha256")) or author_digest_valid(value.get("effective_environment_sha256"))

static func same_author_identity(left: Variant, right: Variant, environment: bool = false) -> bool:
	if not left is Dictionary or not right is Dictionary: return false
	var left_author: bool = has_author_identity(left)
	var right_author: bool = has_author_identity(right)
	if left_author != right_author: return false
	if not left_author: return true
	if not valid_author_identity(left, environment) or not valid_author_identity(right, environment): return false
	for key: String in AUTHOR_FIELDS:
		if key == "scenario_revision":
			if int(left[key]) != int(right[key]): return false
		elif left[key] != right[key]: return false
	return not environment or left.effective_environment_sha256 == right.effective_environment_sha256

static func author_environment_fingerprint(data: TerrainData) -> String:
	# Only the rebuilt base is hashed, before any initial/current SiteState.
	var packet := {"rule": 1, "terrain": data.fingerprint(), "water_kind": data.water_kind,
		"water_body": data.water_body, "fertility": data.fertility, "moisture": data.moisture,
		"drainage": data.drainage, "foundation": data.foundation, "groundwater": data.groundwater,
		"spawn": [data.spawn_cell.x, data.spawn_cell.y], "resources": data.resource_base,
		"water_version": data.parameters.get("navigable_water_version", 0),
		"water_source": data.parameters.get("navigable_water_source", ""),
		"water_cells": data.parameters.get("navigable_water_cells", []),
		"water_bodies": data.parameters.get("navigable_water_bodies", [])}
	if data.parameters.has("author_water_rule"):
		for field: String in ["author_water_rule", "author_water_bodies", "author_water_changed_cells", "author_water_permissions"]:
			packet[field] = data.parameters[field]
	return JSON.stringify(packet, "", true, true).sha256_text()

static func author_pair_valid(value: Variant, low: int, high: int) -> bool:
	return value is Array and value.size() == 2 and author_integer(value[0], low, high) and author_integer(value[1], low, high)

static func author_start_valid(value: Variant) -> bool:
	if not value is Dictionary or not author_pair_valid(value.get("site"), -10000000, 10000000) or not author_pair_valid(value.get("cell"), 0, SIDE - 1): return false
	if value.get("mode") == "created_player": return value.size() == 3
	return value.get("mode") == "existing_person" and value.size() == 4 and author_integer(value.get("person_id"), 1, 2147483647) and int(value.person_id) != 1000000000

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
