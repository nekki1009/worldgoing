extends RefCounted
## Weather on the Region map (時間與氣候 TC9 = 氣候 S4; reports/day-weather-season-plan.md §4.7, D7 A; Nekki 2026-11-15).
## Pure helpers over SiteClimate for a world position and a Region game time:
## - travel speed: drizzle ×0.9, rain ×0.75, storm ×0.5, night ×0.85 (multiplied); on a road only half the penalty;
## - scouting: the distance at which parties are seen shrinks at night (×0.6) and in fog (×0.5);
## - open-air rest: in rain or at night without a tent or a house, fatigue recovers ×0.7.
## The weather of a Site position is its Region's (D1 A), keyed exactly as SiteClimate.site_keys keys a Site, so the
## map and the Site agree. Climate is a world switch: the faction registry's optional `climate` {version, enabled}.
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")

const VERSION := 1
const RAIN_SPEED := {"clear": 1.0, "cloudy": 1.0, "fog": 1.0, "drizzle": 0.9, "rain": 0.75, "storm": 0.5}
const NIGHT_SPEED := 0.85
const ROAD_SHARE := 0.5
const NIGHT_SCOUT := 0.6
const FOG_SCOUT := 0.5
const OPEN_REST := 0.7
const WET := ["drizzle", "rain", "storm"]

static func enabled(registry: Dictionary) -> bool:
	var value: Variant = registry.get("climate")
	return value is Dictionary and value.get("enabled") == true

static func valid(value: Variant) -> bool:
	return value is Dictionary and value.size() == 2 and (value.get("version") is int or value.get("version") is float) and int(value.version) == VERSION and value.get("enabled") is bool

## The SiteClimate region key of a Site coordinate of an atlas ("atlas:rx:ry").
static func region_key(atlas_id: String, site: Vector2i) -> String:
	var region := RegionGrid.region_of(site)
	return "%s:%d:%d" % [atlas_id, region.x, region.y]

## The climate answer at a Site coordinate and a Region time in game seconds.
static func at(world: String, atlas_id: String, site: Vector2i, game_seconds: float) -> Dictionary:
	return Climate.at(world, region_key(atlas_id, site), 0.0, game_seconds / 60.0)

## The travel speed factor of a climate answer (1.0 for an empty answer).
static func speed_factor(now: Dictionary, on_road: bool = false) -> float:
	if now.is_empty(): return 1.0
	var factor := float(RAIN_SPEED.get(str(now.get("weather", "clear")), 1.0)) * (NIGHT_SPEED if str(now.get("band", "")) == "night" else 1.0)
	return 1.0 - (1.0 - factor) * ROAD_SHARE if on_road else factor

static func scout_factor(now: Dictionary) -> float:
	if now.is_empty(): return 1.0
	var factor := 1.0
	if str(now.get("band", "")) == "night": factor *= NIGHT_SCOUT
	if str(now.get("weather", "")) == "fog": factor *= FOG_SCOUT
	return factor

## Open-air rest: ×0.7 in rain or at night unless sheltered (a tent or a house).
static func rest_factor(now: Dictionary, sheltered: bool) -> float:
	if now.is_empty() or sheltered: return 1.0
	return OPEN_REST if str(now.get("weather", "")) in WET or str(now.get("band", "")) == "night" else 1.0

## The end of the 2-hour weather slot containing `game_seconds` (world minute 0 is 06:00, an even hour).
static func slot_end(game_seconds: float) -> float:
	var slot := float(Climate.SLOT_MINUTES) * 60.0
	return (floorf(game_seconds / slot) + 1.0) * slot

## A party carrying a camp tent rests sheltered (searches its content for a positive "camp_tent" count).
static func sheltered(party: Dictionary) -> bool:
	return _has_tent(party.get("content", {}), 0)

static func _has_tent(value: Variant, depth: int) -> bool:
	if depth > 6: return false
	if value is Dictionary:
		var count: Variant = value.get("camp_tent")
		if (count is int or count is float) and float(count) > 0.0: return true
		for child: Variant in value.values():
			if (child is Dictionary or child is Array) and _has_tent(child, depth + 1): return true
	elif value is Array:
		for child: Variant in value:
			if (child is Dictionary or child is Array) and _has_tent(child, depth + 1): return true
	return false

