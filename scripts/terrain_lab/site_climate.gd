extends RefCounted
## Climate (時間與氣候 TC3 = 氣候 S0; reports/time-and-climate-plan.md §1, §3, reports/day-weather-season-plan.md §4.1–§4.5,
## D1–D4 all A). A pure query with no clock and no save state: the same world, region and minute always give the same
## answer, so a cold Site needs no weather catch-up and a reload cannot reroll it.
## at(world_key, region_key, altitude, minute) → {band, light, season, weather, rain, wind, drying, slot, day}
## - band: dawn 05–07 / day 07–17 / dusk 17–19 / night 19–05 (sunrise 06, sunset 18 all year; SiteCalendar.day_part).
## - season: the calendar's (spring 3–5, summer 6–8, autumn 9–11, winter 12–2).
## - weather: one per region per 2-hour slot (12 a day): clear, cloudy, drizzle, rain, storm or fog. Each day first
##   draws its type from the month's table (rainy days tend to follow rainy days), then its 12 slots.
## - the subtropical monsoon table of the Taiwan map: spring rain Feb–Apr, the plum rains mid May–mid Jun, two to
##   four typhoons of one or two days Jul–Sep, the north-east monsoon Oct–Mar (strong wind, drizzle); summer
##   afternoon thunderstorms; fog only in the early morning. No snow on the plains.
## - rain 0..1, wind a Vector2 of length ≤ 1 (where the air moves to; +y is south), drying 0..0.02 (fire's inputs).
## - a high Site rains a little more often (altitude in metres).
## TC3 only answers and shows (the clock line); no rule reads it yet. Climate is off unless the Site's
## `climate_enabled` is true (tests and old saves: off = the old fixed clear daylight).
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")

const VERSION := 1
const SLOT_MINUTES := 120
const SLOTS := 12
const WEATHERS := ["clear", "cloudy", "drizzle", "rain", "storm", "fog"]
const WEATHER_NAMES := {"clear": "晴", "cloudy": "陰", "drizzle": "小雨", "rain": "大雨", "storm": "暴風雨", "fog": "霧"}
const BAND_NAMES := {"dawn": "黎明", "day": "白天", "dusk": "黃昏", "night": "夜"}
## Per weather: rain, wind strength (0..1), drying (§4.4).
const EFFECTS := {
	"clear": {"rain": 0.0, "wind": 0.25, "drying": 0.02},
	"cloudy": {"rain": 0.0, "wind": 0.4, "drying": 0.01},
	"drizzle": {"rain": 0.3, "wind": 0.4, "drying": 0.0},
	"rain": {"rain": 0.7, "wind": 0.6, "drying": 0.0},
	"storm": {"rain": 1.0, "wind": 1.0, "drying": 0.0},
	"fog": {"rain": 0.0, "wind": 0.0, "drying": 0.005},
}
## Day types per month (weights of clear, cloudy, drizzle, rain): the subtropical monsoon table (§4.5, real months).
const MONTH_WEIGHTS := {
	1: [30, 35, 30, 5], 2: [25, 35, 32, 8], 3: [25, 35, 30, 10], 4: [30, 35, 25, 10], 5: [35, 25, 20, 20],
	6: [40, 20, 15, 25], 7: [60, 20, 10, 10], 8: [60, 20, 10, 10], 9: [55, 25, 10, 10], 10: [45, 30, 20, 5],
	11: [40, 35, 20, 5], 12: [35, 35, 25, 5]}
const DAY_TYPES := ["clear", "cloudy", "drizzle", "rain"]
## Chance (percent) that a day repeats yesterday's type, so wet spells last.
const PERSIST := 45
## The plum rains: mid May to mid June, mostly rain.
const PLUM_FROM := [5, 15]
const PLUM_TO := [6, 15]
const PLUM_DAYS := [10, 20, 30, 40]
## Typhoons: TYPHOONS_MIN..MAX a year, each 1–2 days, between 1 Jul and 30 Sep.
const TYPHOONS_MIN := 2
const TYPHOONS_MAX := 4
## Summer afternoon thunderstorms (Jun–Sep clear days, slots 7–8 = 14:00–18:00), percent.
const THUNDER := 30
## Early-morning fog (slots 2–3 = 04:00–08:00) on clear or cloudy days of Nov–Apr, percent.
const FOG := 15
## Prevailing wind (where the air moves to) by month: the NE monsoon Oct–Mar blows to the south-west, the SW monsoon
## May–Aug to the north-east; April and September turn between them.
const NE := Vector2(-0.70710678, 0.70710678)
const SW := Vector2(0.70710678, -0.70710678)
const PREVAILING := {1: NE, 2: NE, 3: NE, 4: Vector2(-0.5, 0.5), 5: SW, 6: SW, 7: SW, 8: SW, 9: Vector2(0.0, 0.0), 10: NE, 11: NE, 12: NE}
const MONSOON_MONTHS := [10, 11, 12, 1, 2, 3]
const LIGHT := {"dawn": Color(0.82, 0.8, 0.92), "day": Color(1, 1, 1), "dusk": Color(1.0, 0.78, 0.62), "night": Color(0.45, 0.5, 0.66)}

static var _typhoons := {}

## A stable 31-bit hash of the parts (FNV-1a over their text).
static func _hash(parts: Array) -> int:
	var value := 2166136261
	for part: Variant in parts:
		for byte: int in str(part).to_utf8_buffer():
			value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
		value = ((value ^ 0x7C) * 16777619) & 0xFFFFFFFF
	return value & 0x7FFFFFFF

static func _pick(weights: Array, roll: int) -> int:
	var total := 0
	for weight: Variant in weights: total += int(weight)
	var at := roll % maxi(1, total)
	for index: int in weights.size():
		at -= int(weights[index])
		if at < 0: return index
	return weights.size() - 1

## The typhoon days of a year: {day_index: true}.
static func typhoon_days(world_key: String, region_key: String, year: int) -> Dictionary:
	var key := "%s|%s|%d" % [world_key, region_key, year]
	if _typhoons.has(key): return _typhoons[key]
	var days := {}
	var first := Calendar.day_of(year, 7, 1)
	var span := Calendar.day_of(year, 9, 30) - first + 1
	var count := TYPHOONS_MIN + _hash([world_key, region_key, year, "typhoons"]) % (TYPHOONS_MAX - TYPHOONS_MIN + 1)
	for index: int in count:
		var start := first + _hash([world_key, region_key, year, "typhoon", index]) % span
		var length := 1 + _hash([world_key, region_key, year, "typhoon_length", index]) % 2
		for offset: int in length:
			if start + offset - first < span: days[start + offset] = true
	if _typhoons.size() > 64: _typhoons.clear()
	_typhoons[key] = days
	return days

static func _plum(month: int, day: int) -> bool:
	var at := month * 100 + day
	return at >= int(PLUM_FROM[0]) * 100 + int(PLUM_FROM[1]) and at <= int(PLUM_TO[0]) * 100 + int(PLUM_TO[1])

## The day's type (clear / cloudy / drizzle / rain / storm), from the month's table; wet spells persist.
static func day_type(world_key: String, region_key: String, altitude: float, day: int, depth: int = 0) -> String:
	var at := Calendar.date(float(Calendar.day_start_minute(maxi(0, day))))
	if typhoon_days(world_key, region_key, int(at.year)).has(day): return "storm"
	if depth < 3 and day > 0 and _hash([world_key, region_key, day, "persist"]) % 100 < PERSIST:
		var yesterday := day_type(world_key, region_key, altitude, day - 1, depth + 1)
		if yesterday != "storm": return yesterday
	var weights: Array = (PLUM_DAYS if _plum(int(at.month), int(at.day)) else MONTH_WEIGHTS[int(at.month)]).duplicate()
	# A high Site rains a little more: up to +10 points moved from clear to drizzle at 2000 m.
	var shift := mini(int(weights[0]), int(clampf(altitude / 2000.0, 0.0, 1.0) * 10.0))
	weights[0] = int(weights[0]) - shift
	weights[2] = int(weights[2]) + shift
	return DAY_TYPES[_pick(weights, _hash([world_key, region_key, day, "type"]))]

## The weather of one 2-hour slot (0..11 from midnight) of a day.
static func slot_weather(world_key: String, region_key: String, altitude: float, day: int, slot: int) -> String:
	var kind := day_type(world_key, region_key, altitude, day)
	var at := Calendar.date(float(Calendar.day_start_minute(maxi(0, day))))
	var month := int(at.month)
	var roll := _hash([world_key, region_key, day, slot, "slot"]) % 100
	match kind:
		"storm": return "storm" if roll < 80 else "rain"
		"rain": return "rain" if roll < 60 else ("drizzle" if roll < 90 else "cloudy")
		"drizzle": return "drizzle" if roll < 55 else "cloudy"
		"cloudy":
			if slot in [2, 3] and (month >= 11 or month <= 4) and _hash([world_key, region_key, day, "fog"]) % 100 < FOG: return "fog"
			return "cloudy" if roll < 75 else ("drizzle" if month in MONSOON_MONTHS and roll < 90 else "clear")
	if slot in [2, 3] and (month >= 11 or month <= 4) and _hash([world_key, region_key, day, "fog"]) % 100 < FOG: return "fog"
	if slot in [7, 8] and month >= 6 and month <= 9 and _hash([world_key, region_key, day, "thunder"]) % 100 < THUNDER: return "storm" if slot == 7 else "rain"
	return "clear" if roll < 85 else "cloudy"

## The wind of a slot: the month's prevailing direction swung by up to ±30° a day, scaled by the weather's strength.
## The NE monsoon months blow at least moderately.
static func wind(world_key: String, region_key: String, day: int, month: int, weather: String) -> Vector2:
	var prevailing: Vector2 = PREVAILING[month]
	var strength := float(EFFECTS[weather].wind)
	if month in MONSOON_MONTHS and weather != "fog": strength = maxf(strength, 0.6)
	if prevailing == Vector2.ZERO:
		var angle := float(_hash([world_key, region_key, day, "calm_wind"]) % 360) * PI / 180.0
		return Vector2.from_angle(angle) * strength * 0.5
	var swing := (float(_hash([world_key, region_key, day, "swing"]) % 61) - 30.0) * PI / 180.0
	return prevailing.normalized().rotated(swing) * strength

## The full answer for a world minute.
static func at(world_key: String, region_key: String, altitude: float, minute: float) -> Dictionary:
	var day := Calendar.day_index(minute)
	var in_day := Calendar.minute_of_day(minute)
	var slot := clampi(in_day / SLOT_MINUTES, 0, SLOTS - 1)
	var date := Calendar.date(maxf(0.0, minute))
	var weather := slot_weather(world_key, region_key, altitude, day, slot)
	var band := Calendar.day_part(in_day)
	return {"band": band, "light": LIGHT[band], "season": str(date.season), "weather": weather,
		"rain": float(EFFECTS[weather].rain), "wind": wind(world_key, region_key, day, int(date.month), weather),
		"drying": float(EFFECTS[weather].drying), "slot": slot, "day": day}

## The keys a Site asks with: the world's instance (or the terrain seed) and the Site's region (or its own id).
static func site_keys(data: TerrainData) -> Dictionary:
	var pin: Variant = data.site.get("world_pin", {})
	var world_key := str(pin.get("world_instance_id", "")) if pin is Dictionary else ""
	if world_key.is_empty(): world_key = "seed:%d" % int(data.seed_value)
	# One weather per Region (D1 A): a world Site id is "atlas:x:y"; its Region is RegionGrid.region_of(x, y).
	var site_id := str(data.site.get("id", ""))
	var parts := site_id.split(":")
	var region_key := "site:" + site_id
	if parts.size() >= 3 and parts[parts.size() - 2].is_valid_int() and parts[parts.size() - 1].is_valid_int():
		var region := RegionGrid.region_of(Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1])))
		region_key = "%s:%d:%d" % [":".join(parts.slice(0, parts.size() - 2)), region.x, region.y]
	return {"world": world_key, "region": region_key, "altitude": float(data.parameters.get("altitude_m", 0.0))}

static func enabled(data: TerrainData) -> bool:
	return data != null and data.site.get("climate_enabled") == true

## The Site's climate now, or {} when climate is off.
static func for_site(data: TerrainData) -> Dictionary:
	if not enabled(data): return {}
	var keys := site_keys(data)
	return at(str(keys.world), str(keys.region), float(keys.altitude), float(data.site.get("minute", 0)) + float(data.site.get("phase", 0.0)))

## 「白天　小雨」 for the clock line, or "" when climate is off.
static func clock_suffix(data: TerrainData) -> String:
	var now := for_site(data)
	if now.is_empty(): return ""
	return "　%s　%s" % [str(BAND_NAMES[now.band]), str(WEATHER_NAMES[now.weather])]
