extends RefCounted
## Season economics (時間與氣候 TC8 = 氣候 S3; reports/day-weather-season-plan.md §4.3, §4.7, §4.8, §7 risk 4;
## reports/time-and-climate-plan.md §1 rule 5). Pure multipliers over SiteClimate; all 1.0 while the Site's climate is
## off (old saves and tests). Seasons follow the calendar (spring 3–5, summer 6–8, autumn 9–11, winter 12–2).
## - farm output 1.0 / 1.2 / 1.1 / 0.6; pasture 1.0 / 1.1 / 1.0 / 0.7; wild food and herb recovery 1.2 / 1.0 / 1.2 /
##   0.5; fish recovery 1.0 / 1.0 / 1.0 / 0.8; farm water demand 1.0 / 1.3 / 1.0 / 0.7 (§4.3);
## - rain: in a slot with rain, an open farm or pasture counts rain × its demand as extra water (§4.7);
## - drought: after DROUGHT_DAYS whole days without a rain slot, wells and intakes give DROUGHT_FACTOR (§4.7);
## - forecast: today's slots for anyone; FORECAST_DAYS more days while the settlement's 虞衡 (settlement.ecology)
##   is seated (§4.8, D10 A).
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")

const FARM := {"spring": 1.0, "summer": 1.2, "autumn": 1.1, "winter": 0.6}
const PASTURE := {"spring": 1.0, "summer": 1.1, "autumn": 1.0, "winter": 0.7}
const WILD := {"spring": 1.2, "summer": 1.0, "autumn": 1.2, "winter": 0.5}
const FISH := {"spring": 1.0, "summer": 1.0, "autumn": 1.0, "winter": 0.8}
const WATER := {"spring": 1.0, "summer": 1.3, "autumn": 1.0, "winter": 0.7}
const DROUGHT_DAYS := 10
const DROUGHT_FACTOR := 0.7
const FORECAST_DAYS := 3

static var _dry_cache := {}

static func season(data: TerrainData) -> String:
	return str(Calendar.date(float(data.site.get("minute", 0))).season)

static func _factor(data: TerrainData, table: Dictionary) -> float:
	if not Climate.enabled(data): return 1.0
	return float(table[season(data)])

static func farm_factor(data: TerrainData) -> float: return _factor(data, FARM)
static func pasture_factor(data: TerrainData) -> float: return _factor(data, PASTURE)
static func wild_factor(data: TerrainData) -> float: return _factor(data, WILD)
static func fish_factor(data: TerrainData) -> float: return _factor(data, FISH)
static func water_factor(data: TerrainData) -> float: return _factor(data, WATER)

## The minutes until the next recovery of a wild food / herb / fish resource: `recover` ÷ the season's factor.
static func recover_minutes(data: TerrainData, kind: int, recover: int) -> int:
	var factor := 1.0
	if kind == Env.Kind.FOOD or kind == Env.Kind.HERB: factor = wild_factor(data)
	elif kind == Env.Kind.FISH: factor = fish_factor(data)
	if factor == 1.0 or recover <= 0: return recover
	return maxi(1, roundi(float(recover) / factor))

## The farm factor of a raw Site state (the long-absence catch-up works on the state, not TerrainData).
static func farm_factor_of_state(state: Dictionary) -> float:
	if state.get("climate_enabled") != true: return 1.0
	return float(FARM[str(Calendar.date(float(state.get("minute", 0))).season)])

## Rain now (0..1), 0 while climate is off.
static func rain(data: TerrainData) -> float:
	var now := Climate.for_site(data)
	return float(now.get("rain", 0.0)) if not now.is_empty() else 0.0

## Did any slot of calendar day `day` rain?
static func rained(world_key: String, region_key: String, altitude: float, day: int) -> bool:
	for slot: int in range(Climate.SLOTS):
		if str(Climate.slot_weather(world_key, region_key, altitude, day, slot)) in ["drizzle", "rain", "storm"]: return true
	return false

## Whole days since the last rain before today (capped at DROUGHT_DAYS + 1).
static func dry_days(data: TerrainData) -> int:
	if not Climate.enabled(data): return 0
	var keys := Climate.site_keys(data)
	var today := Calendar.day_index(float(data.site.get("minute", 0)))
	var cache_key := "%s|%s|%d" % [keys.world, keys.region, today]
	if _dry_cache.has(cache_key): return int(_dry_cache[cache_key])
	var count := 0
	for back: int in range(1, DROUGHT_DAYS + 2):
		if today - back < 0 or rained(str(keys.world), str(keys.region), float(keys.altitude), today - back): break
		count += 1
	if _dry_cache.size() > 256: _dry_cache.clear()
	_dry_cache[cache_key] = count
	return count

static func drought(data: TerrainData) -> bool:
	return dry_days(data) >= DROUGHT_DAYS

## The supply factor of wells and intakes: DROUGHT_FACTOR in a drought, else 1.0.
static func supply_factor(data: TerrainData) -> float:
	return DROUGHT_FACTOR if drought(data) else 1.0

## The farm/pasture water ratio with rain: (supplied + rain × demand) / demand, at most 1.
static func wet_ratio(data: TerrainData, supplied: float, demand: float) -> float:
	if demand <= 0.0: return 1.0
	return clampf((supplied + rain(data) * demand) / demand, 0.0, 1.0)

## What changes the water allocation: the season and the drought (a new value means re-allocate).
static func water_key(data: TerrainData) -> String:
	if not Climate.enabled(data): return ""
	return "%s:%s" % [season(data), str(drought(data))]

## Forecast: [{day, weathers: [12 slot names]}], today first; with the 虞衡 seated FORECAST_DAYS more days.
static func forecast(data: TerrainData, ecology_seated: bool) -> Array:
	var result: Array = []
	if not Climate.enabled(data): return result
	var keys := Climate.site_keys(data)
	var today := Calendar.day_index(float(data.site.get("minute", 0)))
	for offset: int in range(1 + (FORECAST_DAYS if ecology_seated else 0)):
		var weathers: Array = []
		for slot: int in range(Climate.SLOTS): weathers.append(Climate.slot_weather(str(keys.world), str(keys.region), float(keys.altitude), today + offset, slot))
		result.append({"day": today + offset, "weathers": weathers})
	return result
