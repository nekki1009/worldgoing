class_name RegionGrid
extends RefCounted

const CONTRACT_VERSION := 1
const CELL_MM := 2000
const SITE_CELLS := 100
const REGION_SITES := 100
const SITE_MM := CELL_MM * SITE_CELLS
const ATLAS_ID := "earth_tw_tm2_121_v1"

# Scalar int64 millimetres: Taiwan northings overflow Vector2i at this precision.
static func floor_div(value: int, divisor: int) -> int:
	assert(divisor > 0)
	@warning_ignore("integer_division")
	var quotient: int = value / divisor
	return quotient - (1 if value % divisor < 0 else 0)

static func site_from_mm(easting_mm: int, northing_mm: int) -> Vector2i:
	return Vector2i(floor_div(easting_mm, SITE_MM), floor_div(northing_mm, SITE_MM))

static func site_from_meters(easting: float, northing: float) -> Vector2i:
	assert(is_finite(easting) and is_finite(northing))
	return Vector2i(floori(easting / 200.0), floori(northing / 200.0))

static func local_from_mm(easting_mm: int, northing_mm: int) -> Vector2i:
	return Vector2i(posmod(floor_div(easting_mm, CELL_MM), SITE_CELLS),
		SITE_CELLS - 1 - posmod(floor_div(northing_mm, CELL_MM), SITE_CELLS))

static func cell_center_mm(site: Vector2i, local: Vector2i) -> Dictionary:
	assert(local.x >= 0 and local.x < SITE_CELLS and local.y >= 0 and local.y < SITE_CELLS)
	return {"easting_mm": int(site.x) * SITE_MM + local.x * CELL_MM + 1000,
		"northing_mm": int(site.y) * SITE_MM + (SITE_CELLS - 1 - local.y) * CELL_MM + 1000}

static func region_of(site: Vector2i) -> Vector2i:
	return Vector2i(floor_div(site.x, REGION_SITES), floor_div(site.y, REGION_SITES))

static func site_in_region(site: Vector2i) -> Vector2i:
	return Vector2i(posmod(site.x, REGION_SITES), posmod(site.y, REGION_SITES))

static func site_id(atlas_id: String, site: Vector2i) -> String:
	return "%s:%d:%d" % [atlas_id, site.x, site.y]

static func region_id(atlas_id: String, region: Vector2i) -> String:
	return "%s:region:%d:%d" % [atlas_id, region.x, region.y]

static func cell_corner_mm(site: Vector2i, corner: Vector2i) -> Dictionary:
	assert(corner.x >= 0 and corner.x <= SITE_CELLS and corner.y >= 0 and corner.y <= SITE_CELLS)
	return {"easting_mm": int(site.x) * SITE_MM + corner.x * CELL_MM,
		"northing_mm": int(site.y) * SITE_MM + (SITE_CELLS - corner.y) * CELL_MM}
