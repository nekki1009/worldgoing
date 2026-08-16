class_name MapArtCatalog
extends RefCounted

const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")

# Site art is drawn in metres while the generated base is a 256px presentation
# surface.  Keep the visual contract derived from SiteLayoutData so art cannot
# silently drift away from the 50x50 / 2m navigation grid.
const SITE_ART_SURFACE_PIXELS: int = 256
const SITE_SIZE_METERS: float = float(SiteLayoutDataType.SIZE_METERS.x)
const SITE_PIXELS_PER_METER: float = float(SITE_ART_SURFACE_PIXELS) / SITE_SIZE_METERS
const SITE_DETAIL_TILE_PIXELS: int = 16
const SITE_DETAIL_SURFACE_PIXELS: int = SiteLayoutDataType.GRID_SIZE.x * SITE_DETAIL_TILE_PIXELS
const SITE_DETAIL_THEME_PIXELS: int = 128
const SITE_DETAIL_TILE_ACCENT_PIXELS: int = 2
# The data contract remains 1m per generated level. At the near-camera Site
# zoom a literal 1m offset is only a few pixels, so the presentation layer
# exaggerates the vertical screen displacement while navigation keeps the
# real level values.
const SITE_HEIGHT_OFFSET_METERS: float = 3.0
const SITE_TILE_SIZE_METERS: float = float(SiteLayoutDataType.CELL_SIZE_METERS)
const SITE_TILE_SIZE_CENTIMETERS: int = SiteLayoutDataType.CELL_SIZE_METERS * 100
const PERSON_REFERENCE_SIZE_METERS: Vector2 = Vector2(0.60, 1.80)
const LARGE_POI_PLACEHOLDER_SIZE_METERS: Vector2 = Vector2(34.0, 34.0)

const TERRAIN_TEXTURE_PATHS: Dictionary = {
	# v3 is a bare dirt field. Plains Sites need a readable grass floor so a
	# village, path and resource cluster do not look like a brown debug plane.
	TerrainType.PLAINS: "res://assets/map/terrain/plains.png",
	TerrainType.FOREST: "res://assets/map/terrain/forest.png",
	TerrainType.MOUNTAIN: "res://assets/map/terrain/mountain_v3.png",
	TerrainType.WATER: "res://assets/map/terrain/water_v3.png",
	TerrainType.SAND: "res://assets/map/terrain/sand_v2.png",
	TerrainType.SNOW: "res://assets/map/terrain/snow_v2.png",
	TerrainType.SWAMP: "res://assets/map/terrain/swamp_v2.png",
	TerrainType.OCEAN: "res://assets/map/terrain/ocean_v2.png",
}

# Natural Site ground uses the same painterly language as the approved
# strategic reference art, but without roads, stairs, cliffs or platforms
# baked into the floor.  These are presentation-only sources; the generated
# native surface, height levels and facility overlays remain authoritative.
const NATIVE_STYLE_TEXTURE_PATHS: Dictionary = {
	# Native terrain is the ground layer only. Forest is a resource placement,
	# so trees come from the deterministic forest_resource overlay rather than
	# being baked into every Plains/Forest Site floor.
	TerrainType.PLAINS: "res://assets/map/site/scenes/strategic_natural_meadow_ground_v1.png",
	TerrainType.FOREST: "res://assets/map/site/scenes/strategic_natural_meadow_ground_v1.png",
	TerrainType.MOUNTAIN: "res://assets/map/site/scenes/strategic_natural_mountain_ground_v1.png",
	TerrainType.SAND: "res://assets/map/site/scenes/strategic_natural_sand_v1.png",
}

const POI_TEXTURE_PATHS: Dictionary = {
	WorldPOIType.VILLAGE: "res://assets/map/poi/village.png",
	WorldPOIType.TOWN: "res://assets/map/poi/town.png",
	WorldPOIType.CASTLE: "res://assets/map/poi/castle.png",
	WorldPOIType.RUINS: "res://assets/map/poi/ruins.png",
	WorldPOIType.CAVE: "res://assets/map/poi/cave.png",
}
const OUTPOST_TEXTURE_PATH: String = "res://assets/map/poi/outpost.png"

const SITE_ART_TEXTURE_PATHS: Dictionary = {
	"path_straight": "res://assets/map/site/roads/path_straight_v3.png",
	"road_bend": "res://assets/map/site/roads/road_bend_v3.png",
	"road_t_junction": "res://assets/map/site/roads/road_t_junction.png",
	"road_crossing": "res://assets/map/site/roads/road_crossing.png",
	"river_straight": "res://assets/map/site/rivers/river_straight_v2.png",
	"river_bend": "res://assets/map/site/rivers/river_bend.png",
	"river_source": "res://assets/map/site/rivers/river_source.png",
	"river_mouth": "res://assets/map/site/rivers/river_mouth.png",
	"bridge": "res://assets/map/site/transport/bridge_v3.png",
	# Boundary variants are transparent overlays.  They are drawn at the
	# shared edge of two 100m Battle Site cells, so a connection never depends
	# on the interior composition of either authored scene.
	"site_cliff_horizontal": "res://assets/map/site/variants/cliff_path_horizontal_v1.png",
	"site_cliff_vertical": "res://assets/map/site/variants/cliff_path_vertical_v1.png",
	"site_path_horizontal": "res://assets/map/site/variants/path_straight_horizontal_v1.png",
	"site_path_vertical": "res://assets/map/site/variants/path_straight_vertical_v1.png",
	"site_river_horizontal": "res://assets/map/site/variants/river_straight_horizontal_v1.png",
	"site_river_vertical": "res://assets/map/site/variants/river_straight_vertical_v1.png",
	"wood_bridge": "res://assets/map/site/generated/wood_bridge.png",
	"mountain_pass_cliff": "res://assets/map/site/cliffs/mountain_pass_cliff_v3.png",
	"stair": "res://assets/map/site/stairs_v4.png",
	"wood_stair": "res://assets/map/site/generated/wood_stair.png",
	"wood_wall": "res://assets/map/site/generated/wood_wall.png",
	"stone_wall": "res://assets/map/site/generated/stone_wall.png",
	"wood_house": "res://assets/map/site/generated/wood_house.png",
	"grass_resource": "res://assets/map/site/generated/grass_patch.png",
	"fruit_tree_resource": "res://assets/map/site/generated/fruit_tree.png",
	"forest_resource": "res://assets/map/site/generated/forest_cluster.png",
	"stone_ore_resource": "res://assets/map/site/generated/stone_ore.png",
	"iron_ore_resource": "res://assets/map/site/generated/iron_ore.png",
	"silver_ore_resource": "res://assets/map/site/generated/silver_ore.png",
	"gold_ore_resource": "res://assets/map/site/generated/gold_ore.png",
	"entrance_gate": "res://assets/map/site/markers/entrance_gate.png",
	"stone_marker": "res://assets/map/site/landmarks/stone_marker.png",
	"tree_cluster": "res://assets/map/site/decorations/tree_cluster.png",
	"rock_cluster": "res://assets/map/site/decorations/rock_cluster.png",
	"swamp_reeds": "res://assets/map/site/decorations/swamp_reeds.png",
	"snow_dune": "res://assets/map/site/decorations/snow_dune.png",
	"sand_dune": "res://assets/map/site/decorations/sand_dune.png",
	"dry_bush": "res://assets/map/site/decorations/dry_bush.png",
	"snowdrift": "res://assets/map/site/decorations/snowdrift.png",
	"deadwood": "res://assets/map/site/decorations/deadwood.png",
}

# Curated scene paintings are complete Site compositions. They are presentation
# assets only: navigation, height levels, facilities and resources still come
# from SiteLayoutData. A scene can be selected explicitly through
# layout.details["scene_art"]. Strategic CELL_BASE Sites may instead select the
# deterministic Site variant and use the continuous terrain/resource renderer
# only for the fallback variant; a terrain type is never a promise that every
# Site shares one scene.
const SITE_SCENE_TEXTURE_PATHS: Dictionary = {
	"grassland_village": "res://assets/map/site/scenes/grassland_village_v1.png",
	"forest_orchard": "res://assets/map/site/scenes/forest_orchard_v1.png",
	"mountain_mine": "res://assets/map/site/scenes/mountain_mine_v1.png",
	"mountain_pass": "res://assets/map/site/scenes/mountain_pass_v1.png",
	"river_bridge": "res://assets/map/site/scenes/river_bridge_v1.png",
	"river_bridge_vertical": "res://assets/map/site/scenes/river_bridge_vertical_v1.png",
	"sand_dryland": "res://assets/map/site/scenes/sand_dryland_v1.png",
	"snow_ore_shelf": "res://assets/map/site/scenes/snow_ore_shelf_v1.png",
	"swamp_wetland": "res://assets/map/site/scenes/swamp_wetland_v1.png",
	"ocean_coast": "res://assets/map/site/scenes/ocean_coast_v1.png",
	# Natural strategic cells use a small set of authored compositions rather
	# than the old flat terrain texture. They are presentation backgrounds only;
	# roads, rivers, resources and facilities remain generated from Site data.
	"strategic_meadow_v1": "res://assets/map/site/scenes/strategic_meadow_v1.png",
	"strategic_meadow_v2": "res://assets/map/site/scenes/strategic_meadow_v2.png",
	"strategic_river_meadow_v1": "res://assets/map/site/scenes/strategic_river_meadow_v1.png",
	"strategic_river_meadow_vertical_v1": "res://assets/map/site/scenes/strategic_river_meadow_vertical_v1.png",
	"strategic_mountain_v1": "res://assets/map/site/scenes/strategic_mountain_v1.png",
	"strategic_sand_v1": "res://assets/map/site/scenes/strategic_sand_v1.png",
	"strategic_snow_v1": "res://assets/map/site/scenes/strategic_snow_v1.png",
	"strategic_swamp_v1": "res://assets/map/site/scenes/strategic_swamp_v1.png",
	"strategic_ocean_v1": "res://assets/map/site/scenes/strategic_ocean_v1.png",
	# A single continuous no-river grassland/forest footprint.  It is selected
	# only when the visible 3x3 Sites share a compatible native terrain and no
	# river edge, so one child can never fall back to the old low-resolution
	# surface while its neighbours use painted strategic art.
	"strategic_3x3_meadow_v1": "res://assets/map/site/scenes/strategic_3x3_meadow_v1.png",
	# A single seamless 3x3 natural footprint used only when a river meadow
	# composite is shown. Runtime resources/facilities remain data-backed.
	"strategic_3x3_composite_v1": "res://assets/map/site/scenes/strategic_3x3_composite_v1.png",
}

# Sizes are presentation metadata, not a second navigation/collision system.
# Large POI structure images intentionally remain deferred: a future POI is a
# composition of several 2m tiles rather than one oversized single-tile icon.
const SITE_ART_METADATA: Dictionary = {
	"path_straight": {"size_meters": Vector2(3.0, 2.0), "width_meters": 3.0, "category": "connection"},
	"road_bend": {"size_meters": Vector2(3.0, 3.0), "width_meters": 3.0, "category": "connection"},
	"road_t_junction": {"size_meters": Vector2(3.0, 3.0), "width_meters": 3.0, "category": "connection"},
	"road_crossing": {"size_meters": Vector2(3.0, 3.0), "width_meters": 3.0, "category": "connection"},
	"river_straight": {"size_meters": Vector2(8.0, 2.0), "width_meters": 8.0, "category": "connection"},
	"river_bend": {"size_meters": Vector2(8.0, 8.0), "width_meters": 8.0, "category": "connection"},
	"river_source": {"size_meters": Vector2(6.0, 6.0), "category": "connection"},
	"river_mouth": {"size_meters": Vector2(8.0, 8.0), "category": "connection"},
	"bridge": {"size_meters": Vector2(8.0, 12.0), "category": "connection"},
	"site_cliff_horizontal": {"size_meters": Vector2(100.0, 100.0), "category": "boundary_variant"},
	"site_cliff_vertical": {"size_meters": Vector2(100.0, 100.0), "category": "boundary_variant"},
	"site_path_horizontal": {"size_meters": Vector2(50.0, 9.0), "width_meters": 9.0, "category": "boundary_variant"},
	"site_path_vertical": {"size_meters": Vector2(9.0, 50.0), "width_meters": 9.0, "category": "boundary_variant"},
	"site_river_horizontal": {"size_meters": Vector2(50.0, 10.0), "width_meters": 10.0, "category": "boundary_variant"},
	"site_river_vertical": {"size_meters": Vector2(10.0, 50.0), "width_meters": 10.0, "category": "boundary_variant"},
	"wood_bridge": {"size_meters": Vector2(10.0, 3.5), "category": "facility"},
	"mountain_pass_cliff": {"size_meters": Vector2(8.0, 12.0), "category": "landform"},
	"stair": {"size_meters": Vector2(2.2, 5.0), "category": "landform"},
	"wood_stair": {"size_meters": Vector2(2.6, 5.0), "category": "facility"},
	"wood_wall": {"size_meters": Vector2(2.4, 1.4), "category": "facility"},
	"stone_wall": {"size_meters": Vector2(2.4, 1.4), "category": "facility"},
	"wood_house": {"size_meters": Vector2(14.0, 10.0), "category": "building"},
	"grass_resource": {"size_meters": Vector2(5.8, 3.8), "category": "resource"},
	"fruit_tree_resource": {"size_meters": Vector2(5.2, 6.2), "category": "resource"},
	"forest_resource": {"size_meters": Vector2(8.0, 7.2), "category": "resource"},
	"stone_ore_resource": {"size_meters": Vector2(4.2, 3.4), "category": "resource"},
	"iron_ore_resource": {"size_meters": Vector2(4.2, 3.4), "category": "resource"},
	"silver_ore_resource": {"size_meters": Vector2(4.2, 3.4), "category": "resource"},
	"gold_ore_resource": {"size_meters": Vector2(4.2, 3.4), "category": "resource"},
	"entrance_gate": {"size_meters": Vector2(6.0, 4.0), "category": "marker"},
	"stone_marker": {"size_meters": Vector2(1.2, 1.2), "category": "marker"},
	"tree_cluster": {"size_meters": Vector2(7.0, 7.0), "category": "decoration"},
	"rock_cluster": {"size_meters": Vector2(5.0, 5.0), "category": "decoration"},
	"swamp_reeds": {"size_meters": Vector2(4.0, 4.0), "category": "decoration"},
	"snow_dune": {"size_meters": Vector2(5.0, 3.0), "category": "decoration"},
	"sand_dune": {"size_meters": Vector2(5.0, 3.0), "category": "decoration"},
	"dry_bush": {"size_meters": Vector2(2.0, 2.0), "category": "decoration"},
	"snowdrift": {"size_meters": Vector2(3.0, 2.0), "category": "decoration"},
	"deadwood": {"size_meters": Vector2(4.0, 2.0), "category": "decoration"},
}

const ROAD_COLOR: Color = Color("c49a5c")
const PATH_COLOR: Color = Color("d5b777")
const RIVER_COLOR: Color = Color("54b9c9")
const CROSSING_COLOR: Color = Color("e2c17a")
const LANDMARK_COLOR: Color = Color("d7895f")
const HUB_COLOR: Color = Color("f0cf6d")

static var _texture_cache: Dictionary = {}
static var _image_cache: Dictionary = {}
static var _detail_theme_cache: Dictionary = {}
static var _thumbnail_cache: Dictionary = {}
static var _poi_texture_cache: Dictionary = {}
static var _site_art_texture_cache: Dictionary = {}
static var _site_scene_texture_cache: Dictionary = {}
static var _layout_composite_image_cache: Dictionary = {}
static var _native_style_image_cache: Dictionary = {}
static var _outpost_texture: Texture2D

static func terrain_texture(terrain_type: int) -> Texture2D:
	var resolved_type: int = _resolved_terrain(terrain_type)
	if _texture_cache.has(resolved_type):
		return _texture_cache[resolved_type] as Texture2D
	var path: String = str(TERRAIN_TEXTURE_PATHS.get(resolved_type, ""))
	var texture: Texture2D = load(path) as Texture2D if not path.is_empty() else null
	_texture_cache[resolved_type] = texture
	return texture

static func terrain_image(terrain_type: int) -> Image:
	var resolved_type: int = _resolved_terrain(terrain_type)
	if _image_cache.has(resolved_type):
		return _image_cache[resolved_type] as Image
	var texture: Texture2D = terrain_texture(resolved_type)
	if texture == null:
		_image_cache[resolved_type] = null
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		_image_cache[resolved_type] = null
		return null
	image.convert(Image.FORMAT_RGBA8)
	_image_cache[resolved_type] = image
	return image

static func poi_texture(poi_type: int) -> Texture2D:
	if _poi_texture_cache.has(poi_type):
		return _poi_texture_cache[poi_type] as Texture2D
	var path: String = str(POI_TEXTURE_PATHS.get(poi_type, ""))
	var texture: Texture2D = load(path) as Texture2D if not path.is_empty() else null
	_poi_texture_cache[poi_type] = texture
	return texture

static func outpost_texture() -> Texture2D:
	if _outpost_texture != null:
		return _outpost_texture
	_outpost_texture = load(OUTPOST_TEXTURE_PATH) as Texture2D
	return _outpost_texture

static func site_texture(kind: String) -> Texture2D:
	if _site_art_texture_cache.has(kind):
		return _site_art_texture_cache[kind] as Texture2D
	var path: String = str(SITE_ART_TEXTURE_PATHS.get(kind, ""))
	# Variant PNGs are intentionally decoded from bytes first. Calling load()
	# on a just-created Dropbox resource emits a noisy "No loader found" error
	# before the isolated verifier has an import record for it.
	var texture: Texture2D = _load_png_texture(path) \
		if path.contains("/variants/") else (load(path) as Texture2D if not path.is_empty() else null)
	if texture == null and not path.is_empty():
		# New generated variants can be present before an editor import cache is
		# available (notably in Dropbox and in the isolated visual verifier).
		# Keep presentation loading deterministic by decoding the bounded PNG
		# directly, matching site_scene_texture().
		texture = _load_png_texture(path)
	_site_art_texture_cache[kind] = texture
	return texture

static func _load_png_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var image: Image = Image.new()
	image.load_png_from_buffer(file.get_buffer(file.get_length()))
	if image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

static func site_scene_texture(layout: SiteLayoutDataType) -> Texture2D:
	var kind: String = site_scene_kind(layout)
	return site_scene_texture_kind(kind)

static func site_scene_texture_kind(kind: String) -> Texture2D:
	if kind.is_empty():
		return null
	if _site_scene_texture_cache.has(kind):
		return _site_scene_texture_cache[kind] as Texture2D
	var path: String = str(SITE_SCENE_TEXTURE_PATHS.get(kind, ""))
	# These generated scene paintings live in a Dropbox workspace where the
	# editor import cache can lag behind a newly-created PNG. Read the bounded
	# presentation asset from res:// bytes; this works in the editor and in a
	# packed build, while gameplay data and canonical art keep normal resources.
	var texture: Texture2D = null
	if not path.is_empty():
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file != null:
			var image: Image = Image.new()
			image.load_png_from_buffer(file.get_buffer(file.get_length()))
			if not image.is_empty():
				texture = ImageTexture.create_from_image(image)
	_site_scene_texture_cache[kind] = texture
	return texture

static func is_strategic_scene_kind(kind: String) -> bool:
	return kind.begins_with("strategic_")

static func clear_site_scene_texture_cache() -> void:
	_site_scene_texture_cache.clear()

static func site_scene_kind(layout: SiteLayoutDataType) -> String:
	if layout == null:
		return ""
	var explicit: String = str(layout.details.get("scene_art", ""))
	if SITE_SCENE_TEXTURE_PATHS.has(explicit):
		return explicit
	if layout.site_landform == SiteLayoutDataType.Landform.MOUNTAIN_PASS:
		return "mountain_pass"
	var scene_template: String = str(layout.details.get("scene_template", ""))
	var is_generated_strategic_cell: bool = layout.layout_kind == SiteLayoutDataType.LayoutKind.CELL_BASE \
		and layout.details.has("site_visual_archetype")
	# A generated Region cell keeps its native terrain as the background owner.
	# Do not select one of the authored strategic paintings here: those paintings
	# contain decorative terraces and paths for presentation samples, so using
	# them as a Region-cell base makes a flat plain look elevated and makes every
	# tile appear to have a road.  Native terrain, height data, and facility data
	# are rendered by SiteMap as separate layers.  Explicit scene_art and POI
	# scenes below remain available for their own detail previews.
	if is_generated_strategic_cell:
		return ""
	# Forest is a native ground type plus a data-backed wood-resource overlay.
	# Never select the authored forest/orchard painting for a CELL_BASE Site;
	# that image bakes harvestable trees into the floor and duplicates the
	# deterministic RESOURCE_FOREST placements. Explicit scene_art remains an
	# opt-in POI presentation above this guard.
	if layout.layout_kind == SiteLayoutDataType.LayoutKind.CELL_BASE \
		and layout.terrain_type == TerrainType.FOREST:
		return ""
	# A river nearby is a native surface condition, not a bridge.  A bridge
	# scene is reserved for the explicit crossing flag; otherwise the normal
	# terrain renderer draws the water band and keeps the site traversable only
	# where the generated bridge transition exists.
	if layout.river_crossing:
		return _river_scene_kind(layout)
	if scene_template in ["RIVER_DOCK", "BRIDGE"]:
		return ""
	# A CELL_BASE Site is a strategic terrain tile, not a settlement.  The
	# fallback variant intentionally uses the continuous terrain/resource
	# renderer; terrain_type alone is not a complete Site identity.
	if layout.layout_kind == SiteLayoutDataType.LayoutKind.CELL_BASE \
		and str(layout.details.get("site_visual_archetype", "")) == "natural":
		return ""
	match layout.terrain_type:
		TerrainType.WATER:
			return ""
		TerrainType.PLAINS:
			# The house is a settlement POI visual.  A plain strategic tile does
			# not become a village just because its native surface is grassland.
			if layout.layout_kind == SiteLayoutDataType.LayoutKind.POI \
				and layout.site_type in [WorldPOIType.VILLAGE, WorldPOIType.TOWN]:
				return "grassland_village"
			return ""
		TerrainType.FOREST:
			return "forest_orchard"
		TerrainType.MOUNTAIN:
			return "mountain_mine"
		TerrainType.SAND:
			return "sand_dryland"
		TerrainType.SNOW:
			return "snow_ore_shelf"
		TerrainType.SWAMP:
			return "swamp_wetland"
		TerrainType.OCEAN:
			return "ocean_coast"
		_:
			return ""

static func _river_scene_kind(layout: SiteLayoutDataType) -> String:
	var has_vertical: bool = false
	var has_horizontal: bool = false
	for value: Vector2i in layout.river_connection_offsets:
		if value.x != 0:
			has_horizontal = true
		if value.y != 0:
			has_vertical = true
	if has_vertical and not has_horizontal:
		return "river_bridge_vertical"
	return "river_bridge"

static func _strategic_river_scene_kind(layout: SiteLayoutDataType) -> String:
	# Keep the authored river composition aligned with the same cardinal
	# connection contract used by navigation and boundary overlays.  Vertical
	# rivers must never be represented by the horizontal scene (which creates a
	# visually misleading T at a shared Site edge).
	for offset: Vector2i in layout.river_connection_offsets:
		if offset.x != 0:
			return "strategic_river_meadow_v1"
		if offset.y != 0:
			return "strategic_river_meadow_vertical_v1"
	return "strategic_river_meadow_v1" if posmod(layout.site_seed, 2) == 0 \
		else "strategic_river_meadow_vertical_v1"

static func site_art_metadata(kind: String) -> Dictionary:
	var metadata: Variant = SITE_ART_METADATA.get(kind, {})
	return (metadata as Dictionary).duplicate(true) if metadata is Dictionary else {}

static func site_art_size_meters(kind: String) -> Vector2:
	var metadata: Dictionary = site_art_metadata(kind)
	var size: Variant = metadata.get("size_meters", Vector2.ZERO)
	return size as Vector2 if size is Vector2 else Vector2.ZERO

static func site_art_width_meters(kind: String, fallback: float = 0.0) -> float:
	var metadata: Dictionary = site_art_metadata(kind)
	var width: Variant = metadata.get("width_meters", fallback)
	return float(width)

static func site_art_is_large_poi(kind: String) -> bool:
	return bool(site_art_metadata(kind).get("large_poi", false))

static func resource_art_kind(resource_type: int) -> String:
	match resource_type:
		SiteContentTypes.RESOURCE_GRASS:
			return "grass_resource"
		SiteContentTypes.RESOURCE_FRUIT_TREE:
			return "fruit_tree_resource"
		SiteContentTypes.RESOURCE_FOREST:
			return "forest_resource"
		SiteContentTypes.RESOURCE_STONE_ORE:
			return "stone_ore_resource"
		SiteContentTypes.RESOURCE_IRON_ORE:
			return "iron_ore_resource"
		SiteContentTypes.RESOURCE_SILVER_ORE:
			return "silver_ore_resource"
		SiteContentTypes.RESOURCE_GOLD_ORE:
			return "gold_ore_resource"
		_:
			return ""

static func facility_art_kind(facility_type: int, definition_id: String = "") -> String:
	match facility_type:
		SiteContentTypes.Facility.BRIDGE:
			return "wood_bridge"
		SiteContentTypes.Facility.WOOD_STAIR:
			return "wood_stair"
		SiteContentTypes.Facility.STONE_STAIR:
			return "stair"
		SiteContentTypes.Facility.WOOD_WALL:
			return "wood_wall"
		SiteContentTypes.Facility.STONE_WALL:
			return "stone_wall"
		SiteContentTypes.Facility.BUILDING:
			return "wood_house" if definition_id == "rectangular_wood_house" else ""
		_:
			return ""

static func site_structure_size_meters(_poi_type: int) -> Vector2:
	return LARGE_POI_PLACEHOLDER_SIZE_METERS

static func site_structure_is_large_poi(_poi_type: int) -> bool:
	return true

static func site_decor_kind(terrain_type: int, variant: int = 0) -> String:
	var kinds: Array[String] = _site_decor_kinds(terrain_type)
	return kinds[posmod(variant, kinds.size())] if not kinds.is_empty() else ""

static func site_decor_size_meters(terrain_type: int, variant: int = 0) -> Vector2:
	return site_art_size_meters(site_decor_kind(terrain_type, variant))

static func site_structure_texture(poi_type: int) -> Texture2D:
	# Kept as a catalog lookup for the future multi-tile POI composer. SiteMap
	# intentionally does not call this while the large-POI scope is deferred.
	return poi_texture(poi_type)

static func site_decor_texture(terrain_type: int, variant: int = 0) -> Texture2D:
	var kinds: Array[String] = _site_decor_kinds(terrain_type)
	if kinds.is_empty():
		return null
	return site_texture(kinds[posmod(variant, kinds.size())])

static func _site_decor_kinds(terrain_type: int) -> Array[String]:
	match _resolved_terrain(terrain_type):
		TerrainType.FOREST:
			# Forest trees are harvestable resource placements, not native decor.
			return ["dry_bush", "rock_cluster"]
		TerrainType.MOUNTAIN:
			return ["rock_cluster"]
		TerrainType.SAND:
			return ["sand_dune", "dry_bush"]
		TerrainType.SNOW:
			return ["snowdrift", "rock_cluster"]
		TerrainType.SWAMP:
			return ["swamp_reeds", "deadwood"]
		TerrainType.PLAINS:
			return ["tree_cluster", "rock_cluster"]
		_:
			return []

static func thumbnail_color(
		terrain_type: int,
		visual_code: int,
		thumbnail_cell: Vector2i,
		thumbnail_size: int
	) -> Color:
	var base_color: Color = terrain_color(terrain_type)
	var image: Image = _thumbnail_image(terrain_type, thumbnail_size)
	if image != null and thumbnail_size > 0:
		base_color = image.get_pixel(
			clampi(thumbnail_cell.x, 0, image.get_width() - 1),
			clampi(thumbnail_cell.y, 0, image.get_height() - 1)
		)
	return visual_color(base_color, visual_code)

static func build_layout_image(layout: SiteLayoutData, pixel_size: int = 256) -> Image:
	var image: Image = build_layout_base_image(layout, pixel_size)
	if image == null:
		return null
	for y: int in range(pixel_size):
		for x: int in range(pixel_size):
			var local_cell: Vector2i = Vector2i(
				clampi(floori(float(x) * float(SiteLayoutDataType.GRID_SIZE.x) / float(pixel_size)), 0, SiteLayoutDataType.GRID_SIZE.x - 1),
				clampi(floori(float(y) * float(SiteLayoutDataType.GRID_SIZE.y) / float(pixel_size)), 0, SiteLayoutDataType.GRID_SIZE.y - 1)
			)
			image.set_pixel(x, y, visual_color(image.get_pixel(x, y), layout.visual_code_at(local_cell)))
	return image

static func build_layout_base_image(layout: SiteLayoutData, pixel_size: int = 256) -> Image:
	if layout == null or pixel_size <= 0:
		return null
	if pixel_size == SITE_DETAIL_SURFACE_PIXELS:
		return _build_detail_layout_base_image(layout, pixel_size)
	var image: Image = Image.create(pixel_size, pixel_size, false, Image.FORMAT_RGBA8)
	var source: Image = terrain_image(layout.terrain_type)
	for y: int in range(pixel_size):
		for x: int in range(pixel_size):
			var color: Color = terrain_color(layout.terrain_type)
			if source != null:
				var source_x: int = clampi(
					floori(float(x) * float(source.get_width()) / float(pixel_size)),
					0,
					source.get_width() - 1
				)
				var source_y: int = clampi(
					floori(float(y) * float(source.get_height()) / float(pixel_size)),
					0,
					source.get_height() - 1
				)
				color = source.get_pixel(source_x, source_y)
			var local_cell: Vector2i = Vector2i(
				clampi(floori(float(x) * float(SiteLayoutDataType.GRID_SIZE.x) / float(pixel_size)), 0, SiteLayoutDataType.GRID_SIZE.x - 1),
				clampi(floori(float(y) * float(SiteLayoutDataType.GRID_SIZE.y) / float(pixel_size)), 0, SiteLayoutDataType.GRID_SIZE.y - 1)
			)
			var flags: int = layout.navigation_flags_at(local_cell)
			if (flags & SiteLayoutDataType.NAV_BLOCKED) != 0:
				var surface: int = layout.surface_flags_at(local_cell)
				if (surface & SiteLayoutDataType.SURFACE_CLIFF) != 0:
					# Keep the authored mountain texture readable beneath the
					# transparent height overlay; a flat gray blocked mask hid the
					# actual terrain in the Site preview.
					color = color.darkened(0.16).lerp(Color("596067"), 0.08)
				else:
					color = color.darkened(0.44).lerp(Color("596067"), 0.28)
			image.set_pixel(x, y, color)
	return image

static func build_layout_composite_image(layout: SiteLayoutData, pixel_size: int) -> Image:
	# The 3x3 Region preview only needs the final composite resolution. Building
	# nine full 800px Site surfaces first made a navigation round-trip spend
	# most of its time in per-pixel GDScript. Sample the same native 800px
	# coordinate field directly at the requested output size instead; the shared
	# global phase remains identical while the work scales with the visible image.
	if layout == null or pixel_size <= 0:
		return null
	# A World/Region/Site round-trip can ask for the same nine generated cells
	# more than once in one session. The raster is presentation-only and the
	# layout is deterministic, so keep one immutable source image per layout and
	# hand callers a detached copy. This avoids rebuilding the same 418px field
	# while preserving the existing renderer ownership boundary.
	var cache_key: String = "%s|%d|%d|%d|%d|%d|%d" % [
		layout.site_id,
		pixel_size,
		layout.site_seed,
		layout.terrain_type,
		layout.site_landform,
		layout.global_region_cell.x,
		layout.global_region_cell.y,
	]
	if _layout_composite_image_cache.has(cache_key):
		var cached: Image = _layout_composite_image_cache[cache_key] as Image
		return cached.duplicate() as Image if cached != null else null
	var image: Image = Image.create(pixel_size, pixel_size, false, Image.FORMAT_RGBA8)
	var conceptual_size: int = SITE_DETAIL_SURFACE_PIXELS
	for y: int in range(pixel_size):
		var source_y: int = clampi(
			floori(float(y) * float(conceptual_size) / float(pixel_size)),
			0,
			conceptual_size - 1
		)
		for x: int in range(pixel_size):
			var source_x: int = clampi(
				floori(float(x) * float(conceptual_size) / float(pixel_size)),
				0,
				conceptual_size - 1
			)
			var cell: Vector2i = Vector2i(
				mini(floori(float(source_x) / float(SITE_DETAIL_TILE_PIXELS)), SiteLayoutDataType.GRID_SIZE.x - 1),
				mini(floori(float(source_y) / float(SITE_DETAIL_TILE_PIXELS)), SiteLayoutDataType.GRID_SIZE.y - 1)
			)
			var local_pixel: Vector2i = Vector2i(
				posmod(source_x, SITE_DETAIL_TILE_PIXELS),
				posmod(source_y, SITE_DETAIL_TILE_PIXELS)
			)
			var native_surface: int = layout.native_surface_at(cell)
			var color: Color = _site_tile_color(
				layout,
				cell,
				native_surface,
				local_pixel,
				SITE_DETAIL_TILE_PIXELS
			)
			if (layout.surface_flags_at(cell) & SiteLayoutDataType.SURFACE_CLIFF) != 0:
				color = color.darkened(0.08)
			image.set_pixel(x, y, color)
	_layout_composite_image_cache[cache_key] = image
	return image.duplicate() as Image

static func _build_detail_layout_base_image(layout: SiteLayoutData, pixel_size: int) -> Image:
	var image: Image = Image.create(pixel_size, pixel_size, false, Image.FORMAT_RGBA8)
	var pixels_per_tile: int = maxi(1, floori(float(pixel_size) / float(SiteLayoutDataType.GRID_SIZE.x)))
	for y: int in range(pixel_size):
		for x: int in range(pixel_size):
			var cell: Vector2i = Vector2i(
				clampi(floori(float(x) * float(SiteLayoutDataType.GRID_SIZE.x) / float(pixel_size)), 0, SiteLayoutDataType.GRID_SIZE.x - 1),
				clampi(floori(float(y) * float(SiteLayoutDataType.GRID_SIZE.y) / float(pixel_size)), 0, SiteLayoutDataType.GRID_SIZE.y - 1)
			)
			var native_surface: int = layout.native_surface_at(cell)
			# Site is a tile scene, not a zoomed macro texture.  Use a deliberately
			# small palette per cell and only a few deterministic pixel accents so
			# the terrain silhouette stays readable at full view and close zoom.
			var local_pixel: Vector2i = Vector2i(
				posmod(x, pixels_per_tile),
				posmod(y, pixels_per_tile)
			)
			var color: Color = _site_tile_color(layout, cell, native_surface, local_pixel, pixels_per_tile)
			if (layout.surface_flags_at(cell) & SiteLayoutDataType.SURFACE_CLIFF) != 0:
				color = color.darkened(0.08)
			image.set_pixel(x, y, color)
	return image

static func _site_tile_color(
	layout: SiteLayoutDataType,
	cell: Vector2i,
	native_surface: int,
	local_pixel: Vector2i,
	pixels_per_tile: int
) -> Color:
	# A Site is a scene, not a 50x50 checkerboard. Map one authored terrain
	# field across the whole 100m surface and vary it with a low-frequency
	# deterministic field. The former per-cell sample made obvious horizontal
	# repeats at full-map zoom.
	var base: Color = _site_surface_palette(layout.terrain_type, native_surface)
	var texture: Image = _detail_surface_image(layout.terrain_type, native_surface)
	# Sample the native field in Region coordinates, not from (0,0) for every
	# Site.  Adjacent Sites therefore share the same texture phase at their
	# common edge; resetting the sample origin per tile was the source of the
	# visible horizontal/vertical seams in the 3x3 preview.
	var global_pixel: Vector2i = layout.global_region_cell * SITE_DETAIL_SURFACE_PIXELS \
		+ cell * pixels_per_tile + local_pixel
	if texture != null and not texture.is_empty():
		var texture_x: int = _texture_index(
			floori(float(global_pixel.x) * float(texture.get_width()) / float(SITE_DETAIL_SURFACE_PIXELS)),
			texture.get_width()
		)
		var texture_y: int = _texture_index(
			floori(float(global_pixel.y) * float(texture.get_height()) / float(SITE_DETAIL_SURFACE_PIXELS)),
			texture.get_height()
		)
		var sampled: Color = texture.get_pixel(texture_x, texture_y)
		if sampled.a > 0.0:
			base = sampled
	# Do not add a second procedural noise field over authored ground.  The
	# previous macro light/dark blobs and per-cell accent hash read as stray
	# pixels at Site zoom and made adjacent terrain look like unrelated tiles.
	# Natural variation now comes from the shared style plate plus data-backed
	# resources/decorations drawn by SiteMap.
	return base

static func _texture_index(value: int, size: int) -> int:
	if size <= 1:
		return 0
	# Repeat the authored field in one orientation only.  Mirror-repeat made
	# every other texture period reverse tree trunks and rock silhouettes, so a
	# 3x3 Region view looked as if individual objects had been rotated.  The
	# shared global phase is retained; only the directional flip is removed.
	return posmod(value, size)

static func _site_macro_field(layout: SiteLayoutDataType, pixel: Vector2i, salt: int) -> float:
	# The field is evaluated in presentation pixels, not once per 2m cell. This
	# keeps broad patches organic instead of producing a visible 50x50 grid.
	var spacing: int = SITE_DETAIL_TILE_PIXELS * 8
	var coarse: Vector2i = Vector2i(
		floori(float(pixel.x) / float(spacing)),
		floori(float(pixel.y) / float(spacing))
	)
	var local: Vector2 = Vector2(
		float(posmod(pixel.x, spacing)) / float(spacing),
		float(posmod(pixel.y, spacing)) / float(spacing)
	)
	var top_left: float = DeterministicHash.normalized(layout.site_seed, coarse, salt)
	var top_right: float = DeterministicHash.normalized(layout.site_seed, coarse + Vector2i.RIGHT, salt)
	var bottom_left: float = DeterministicHash.normalized(layout.site_seed, coarse + Vector2i.DOWN, salt)
	var bottom_right: float = DeterministicHash.normalized(layout.site_seed, coarse + Vector2i.ONE, salt)
	var top: float = lerpf(top_left, top_right, smoothstep(0.0, 1.0, local.x))
	var bottom: float = lerpf(bottom_left, bottom_right, smoothstep(0.0, 1.0, local.x))
	return lerpf(top, bottom, smoothstep(0.0, 1.0, local.y))

static func _site_surface_palette(terrain_type: int, native_surface: int) -> Color:
	match native_surface:
		SiteContentTypes.NativeSurface.RIVER_WATER:
			return Color("3d91ad")
		SiteContentTypes.NativeSurface.SEA_WATER:
			return Color("23668f")
		SiteContentTypes.NativeSurface.ROCK:
			return Color("68717b")
		_:
			match _resolved_terrain(terrain_type):
				TerrainType.FOREST:
					return Color("4f873f")
				TerrainType.SAND:
					return Color("d8b563")
				TerrainType.SNOW:
					return Color("d9e8e8")
				TerrainType.SWAMP:
					return Color("596543")
				_:
					return Color("79a95b")

static func _detail_surface_image(terrain_type: int, native_surface: int) -> Image:
	match native_surface:
		SiteContentTypes.NativeSurface.RIVER_WATER:
			return _detail_theme_image(TerrainType.WATER)
		SiteContentTypes.NativeSurface.SEA_WATER:
			return _detail_theme_image(TerrainType.OCEAN)
		SiteContentTypes.NativeSurface.ROCK:
			# ROCK is a native navigation surface, but a small outcrop inside a
			# plain/forest Site is not a whole mountain tile. Keep the authored
			# biome ground underneath and let SiteMap place a compact rock cluster
			# on the deterministic rock cells. A Mountain Site uses the walkable
			# rocky-ground plate; the old dense mountain texture is only a fallback.
			var rock_biome: int = _resolved_terrain(terrain_type)
			var rock_natural_style: Image = _native_style_image(rock_biome)
			if rock_natural_style != null and not rock_natural_style.is_empty():
				return rock_natural_style
			if rock_biome == TerrainType.MOUNTAIN:
				return terrain_image(TerrainType.MOUNTAIN)
			return _detail_theme_image(rock_biome)
		_:
			var resolved_type: int = _resolved_terrain(terrain_type)
			var natural_style: Image = _native_style_image(resolved_type)
			if natural_style != null and not natural_style.is_empty():
				return natural_style
			return terrain_image(resolved_type) if resolved_type == TerrainType.MOUNTAIN \
				else _detail_theme_image(resolved_type)

static func _native_style_image(terrain_type: int) -> Image:
	var resolved_type: int = _resolved_terrain(terrain_type)
	if _native_style_image_cache.has(resolved_type):
		return _native_style_image_cache[resolved_type] as Image
	var path: String = str(NATIVE_STYLE_TEXTURE_PATHS.get(resolved_type, ""))
	if path.is_empty():
		_native_style_image_cache[resolved_type] = null
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_native_style_image_cache[resolved_type] = null
		return null
	var image: Image = Image.new()
	image.load_png_from_buffer(file.get_buffer(file.get_length()))
	if image.is_empty():
		_native_style_image_cache[resolved_type] = null
		return null
	image.convert(Image.FORMAT_RGBA8)
	_native_style_image_cache[resolved_type] = image
	return image

static func _detail_theme_image(terrain_type: int) -> Image:
	var resolved_type: int = _resolved_terrain(terrain_type)
	if _detail_theme_cache.has(resolved_type):
		return _detail_theme_cache[resolved_type] as Image
	var source: Image = terrain_image(resolved_type)
	if source == null or source.is_empty():
		_detail_theme_cache[resolved_type] = null
		return null
	if source.get_width() <= SITE_DETAIL_THEME_PIXELS \
		and source.get_height() <= SITE_DETAIL_THEME_PIXELS:
		_detail_theme_cache[resolved_type] = source
		return source
	# Keep the authored pixel-art field intact. The Site renderer maps it once
	# across the 100m surface; downsampling here was the source of the repeated
	# horizontal bands in the old preview.
	_detail_theme_cache[resolved_type] = source
	return source

static func _native_surface_color(native_surface: int) -> Color:
	match native_surface:
		SiteContentTypes.NativeSurface.ROCK:
			return Color("5f6468")
		SiteContentTypes.NativeSurface.RIVER_WATER:
			return Color("2f8495")
		SiteContentTypes.NativeSurface.SEA_WATER:
			return Color("164f78")
		_:
			return Color("886238")

static func terrain_color(terrain_type: int) -> Color:
	return TerrainType.to_color(_resolved_terrain(terrain_type))

static func visual_color(base_color: Color, visual_code: int) -> Color:
	var color: Color = base_color
	if SiteLayoutDataType.visual_has_crossing(visual_code):
		return color.lerp(CROSSING_COLOR, 0.72)
	if (visual_code & SiteLayoutDataType.VISUAL_RIVER) != 0:
		color = color.lerp(RIVER_COLOR, 0.70)
	if (visual_code & SiteLayoutDataType.VISUAL_ROAD) != 0:
		color = color.lerp(ROAD_COLOR, 0.68)
	elif (visual_code & SiteLayoutDataType.VISUAL_PATH) != 0:
		color = color.lerp(PATH_COLOR, 0.62)
	if (visual_code & SiteLayoutDataType.VISUAL_LANDMARK) != 0:
		color = color.lerp(LANDMARK_COLOR, 0.70)
	if (visual_code & SiteLayoutDataType.VISUAL_HUB) != 0:
		color = color.lerp(HUB_COLOR, 0.78)
	return color

static func _resolved_terrain(terrain_type: int) -> int:
	return terrain_type if TerrainType.is_valid(terrain_type) else TerrainType.PLAINS

static func _thumbnail_image(terrain_type: int, thumbnail_size: int) -> Image:
	if thumbnail_size <= 0:
		return null
	var resolved_type: int = _resolved_terrain(terrain_type)
	var cache_key: String = "%d:%d" % [resolved_type, thumbnail_size]
	if _thumbnail_cache.has(cache_key):
		return _thumbnail_cache[cache_key] as Image
	var source: Image = terrain_image(resolved_type)
	if source == null:
		_thumbnail_cache[cache_key] = null
		return null
	var thumbnail: Image = source.duplicate() as Image
	thumbnail.resize(thumbnail_size, thumbnail_size, Image.INTERPOLATE_LANCZOS)
	_thumbnail_cache[cache_key] = thumbnail
	return thumbnail
