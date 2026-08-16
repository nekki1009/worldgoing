class_name SiteData
extends RefCounted

const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
const SiteContentTypesType = preload("res://scripts/data/site_content_types.gd")

const BASE_GENERATION_VERSION: int = 3
const SITE_SEED_SALT: int = 29_011

var site_id: String = ""
var source_poi_id: String = ""
var site_name: String = ""
var site_type: int = WorldPOIType.VILLAGE
var layout_kind: int = SiteLayoutDataType.LayoutKind.POI
var parent_world_cell: Vector2i = Vector2i(-1, -1)
var parent_region_cell: Vector2i = Vector2i(-1, -1)
var global_region_cell: Vector2i = Vector2i(-1, -1)
var base_generation_version: int = BASE_GENERATION_VERSION
var site_seed: int = 0
var entrance_local_meters: Vector2i = Vector2i.ZERO
var entrance_global_meters: Vector2i = Vector2i.ZERO
var source_terrain_type: int = TerrainType.PLAINS
var site_landform: int = SiteLayoutDataType.Landform.NONE
var travel_exit_mask: int = SiteLayoutDataType.EXIT_ALL
var source_elevation: float = 0.0
var source_moisture: float = 0.0
var source_river_nearby: bool = false
var source_river_strength: float = 0.0
var source_river_connection_offsets: Array[Vector2i] = []
var source_road: bool = false
var source_road_connection_offsets: Array[Vector2i] = []
var source_river_crossing: bool = false
var native_surface_hint: int = SiteContentTypesType.NativeSurface.DIRT
var rock_ratio: float = 0.0
var river_width_class: int = 0
var coast_mask: int = 0
var resource_amounts: PackedInt32Array = PackedInt32Array()
var source_candidate_cell: Vector2i = Vector2i.ZERO
var source_priority: float = 0.0

func _init(
		p_site_id: String = "",
		p_site_name: String = "",
		p_site_type: int = WorldPOIType.VILLAGE,
		p_parent_world_cell: Vector2i = Vector2i(-1, -1),
		p_parent_region_cell: Vector2i = Vector2i(-1, -1),
		p_global_region_cell: Vector2i = Vector2i(-1, -1)
	) -> void:
	site_id = p_site_id
	source_poi_id = p_site_id
	site_name = p_site_name
	site_type = p_site_type
	parent_world_cell = p_parent_world_cell
	parent_region_cell = p_parent_region_cell
	global_region_cell = p_global_region_cell

static func from_poi(poi: WorldPOIData) -> SiteData:
	if poi == null:
		return null
	var definition: SiteData = SiteData.new(
			poi.poi_id,
			poi.site_name,
			poi.poi_type,
			poi.world_cell,
			poi.region_cell,
			poi.global_region_cell
		)
	definition.source_poi_id = poi.poi_id
	definition.site_seed = derive_seed(poi)
	definition.entrance_global_meters = WorldCoordinates.global_region_cell_to_global_meters(
		poi.global_region_cell
	) + Vector2i.ONE * floori(float(WorldCoordinates.REGION_CELL_SIZE_METERS) * 0.5)
	definition.source_terrain_type = poi.terrain_type
	definition.source_elevation = poi.elevation
	definition.source_moisture = poi.moisture
	definition.source_river_nearby = poi.river_nearby
	definition.source_river_strength = 1.0 if poi.river_nearby else 0.0
	definition.native_surface_hint = _surface_hint(poi.terrain_type)
	definition.rock_ratio = 0.82 if poi.terrain_type == TerrainType.MOUNTAIN else 0.08
	definition.river_width_class = 1 if poi.river_nearby else 0
	definition.resource_amounts = _resource_amounts(travel_data_from_poi(poi))
	definition.source_candidate_cell = poi.candidate_cell
	definition.source_priority = poi.deterministic_priority
	return definition

static func from_region_cell(
		world_seed: int,
		world_cell: Vector2i,
		region_cell: Vector2i,
		travel_data: Dictionary
	) -> SiteData:
	if not WorldCoordinates.is_valid_region_cell(region_cell):
		return null
	var global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
		world_cell,
		region_cell
	)
	var definition: SiteData = SiteData.new(
			"site_cell_%d_%d" % [global_cell.x, global_cell.y],
			"Site %03d,%03d" % [global_cell.x, global_cell.y],
			WorldPOIType.VILLAGE,
			world_cell,
			region_cell,
			global_cell
		)
	definition.source_poi_id = ""
	definition.layout_kind = SiteLayoutDataType.LayoutKind.CELL_BASE
	var derived_seed: int = DeterministicHash.value(
			world_seed,
			global_cell,
			SITE_SEED_SALT + BASE_GENERATION_VERSION * 101
		)
	definition.site_seed = derived_seed if derived_seed != 0 else 1
	definition.entrance_global_meters = WorldCoordinates.global_region_cell_to_global_meters(
			global_cell
		) + Vector2i.ONE * floori(float(WorldCoordinates.REGION_CELL_SIZE_METERS) * 0.5)
	definition.source_terrain_type = int(travel_data.get("terrain_type", TerrainType.PLAINS))
	definition.site_landform = int(travel_data.get(
			"site_landform",
			SiteLayoutDataType.Landform.NONE
		))
	definition.travel_exit_mask = int(travel_data.get(
			"travel_exit_mask",
			SiteLayoutDataType.EXIT_ALL
		))
	definition.source_elevation = float(travel_data.get("elevation", 0.0))
	definition.source_moisture = float(travel_data.get("moisture", 0.0))
	definition.source_river_nearby = bool(travel_data.get("river", false))
	# A scalar river confidence is not a rendered water channel.  Only an
	# authoritative reciprocal river edge may make a Site wet.
	definition.source_river_strength = float(travel_data.get("river_strength", 0.0)) \
		if definition.source_river_nearby else 0.0
	definition.source_road = bool(travel_data.get("road", false))
	definition.source_river_crossing = bool(travel_data.get("river_crossing", false))
	definition.native_surface_hint = int(travel_data.get(
		"native_surface_hint",
		_surface_hint(definition.source_terrain_type)
	))
	definition.rock_ratio = float(travel_data.get("rock_ratio", 0.0))
	definition.river_width_class = int(travel_data.get("river_width_class", 0))
	definition.coast_mask = int(travel_data.get("coast_mask", 0))
	definition.resource_amounts = _resource_amounts(travel_data)
	var road_offsets: Variant = travel_data.get("road_connection_offsets", [])
	if road_offsets is Array:
		for offset: Variant in road_offsets as Array:
			if offset is Vector2i and absi((offset as Vector2i).x) + absi((offset as Vector2i).y) == 1:
				definition.source_road_connection_offsets.append(offset as Vector2i)
	var river_offsets: Variant = travel_data.get("river_connection_offsets", [])
	if river_offsets is Array:
		for offset: Variant in river_offsets as Array:
			if offset is Vector2i and absi((offset as Vector2i).x) + absi((offset as Vector2i).y) == 1:
				definition.source_river_connection_offsets.append(offset as Vector2i)
	definition.source_candidate_cell = region_cell
	return definition

static func derive_seed(poi: WorldPOIData) -> int:
	if poi == null:
		return 0
	return DeterministicHash.value(
		poi.generation_seed,
		poi.global_region_cell,
		SITE_SEED_SALT + BASE_GENERATION_VERSION * 101 + poi.poi_type
	)

func apply_content_profile(travel_data: Dictionary) -> void:
	native_surface_hint = int(travel_data.get(
		"native_surface_hint",
		_surface_hint(source_terrain_type)
	))
	rock_ratio = float(travel_data.get("rock_ratio", rock_ratio))
	river_width_class = int(travel_data.get("river_width_class", river_width_class))
	coast_mask = int(travel_data.get("coast_mask", coast_mask))
	if travel_data.has("resource_amounts"):
		resource_amounts = _resource_amounts(travel_data)

func apply_travel_projection(travel_data: Dictionary) -> void:
	# Keep the Site view on the same resolved cell contract as travel.  This is
	# also the single place where a Region Runtime delta can project into a
	# presentation-only Site definition.
	source_terrain_type = int(travel_data.get("terrain_type", source_terrain_type))
	site_landform = int(travel_data.get("site_landform", site_landform))
	travel_exit_mask = int(travel_data.get("travel_exit_mask", travel_exit_mask))
	source_elevation = float(travel_data.get("elevation", source_elevation))
	source_moisture = float(travel_data.get("moisture", source_moisture))
	source_river_nearby = bool(travel_data.get("river", source_river_nearby))
	source_river_strength = float(travel_data.get("river_strength", source_river_strength)) \
		if source_river_nearby else 0.0
	source_road = bool(travel_data.get("road", source_road))
	source_river_crossing = bool(travel_data.get("river_crossing", source_river_crossing))
	# A partial runtime projection may update terrain/resources without carrying
	# the edge topology. Preserve the existing authoritative offsets unless the
	# projection explicitly includes that key; an omitted key is not "no road".
	if travel_data.has("road_connection_offsets"):
		source_road_connection_offsets = _cardinal_offsets(
			travel_data.get("road_connection_offsets", [])
		)
	if travel_data.has("river_connection_offsets"):
		source_river_connection_offsets = _cardinal_offsets(
			travel_data.get("river_connection_offsets", [])
		)
	apply_content_profile(travel_data)

static func _cardinal_offsets(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not value is Array:
		return result
	for offset: Variant in value as Array:
		if offset is Vector2i and absi((offset as Vector2i).x) + absi((offset as Vector2i).y) == 1:
			result.append(offset as Vector2i)
	return result

func local_to_global_meters(local_meters: Vector2i) -> Vector2i:
	return entrance_global_meters + local_meters - entrance_local_meters

func global_to_local_meters(global_meters: Vector2i) -> Vector2i:
	return entrance_local_meters + global_meters - entrance_global_meters

static func _surface_hint(terrain_type: int) -> int:
	if terrain_type == TerrainType.OCEAN:
		return SiteContentTypesType.NativeSurface.SEA_WATER
	if terrain_type == TerrainType.WATER:
		return SiteContentTypesType.NativeSurface.RIVER_WATER
	if terrain_type == TerrainType.MOUNTAIN:
		return SiteContentTypesType.NativeSurface.ROCK
	return SiteContentTypesType.NativeSurface.DIRT

static func _resource_amounts(source: Dictionary) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	result.resize(SiteContentTypesType.RESOURCE_COUNT)
	var stored: Variant = source.get("resource_amounts", PackedInt32Array())
	if stored is PackedInt32Array:
		var values: PackedInt32Array = stored as PackedInt32Array
		for index: int in range(mini(values.size(), result.size())):
			result[index] = values[index]
	return result

static func travel_data_from_poi(poi: WorldPOIData) -> Dictionary:
	var values: PackedInt32Array = PackedInt32Array()
	values.resize(SiteContentTypesType.RESOURCE_COUNT)
	var moisture: float = poi.moisture
	var rock: float = clampf((poi.elevation - 0.45) * 2.0, 0.0, 1.0)
	values[SiteContentTypesType.RESOURCE_GRASS] = roundi(moisture * 120.0)
	values[SiteContentTypesType.RESOURCE_FRUIT_TREE] = roundi(maxf(moisture - 0.35, 0.0) * 20.0)
	values[SiteContentTypesType.RESOURCE_FOREST] = roundi(maxf(moisture - 0.30, 0.0) * 80.0)
	values[SiteContentTypesType.RESOURCE_STONE_ORE] = roundi(rock * 80.0)
	values[SiteContentTypesType.RESOURCE_IRON_ORE] = roundi(rock * 22.0)
	values[SiteContentTypesType.RESOURCE_SILVER_ORE] = roundi(rock * 6.0)
	values[SiteContentTypesType.RESOURCE_GOLD_ORE] = roundi(rock * 2.0)
	return {"resource_amounts": values}
