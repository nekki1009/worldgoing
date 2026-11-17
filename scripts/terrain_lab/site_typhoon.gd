extends RefCounted
## 時間與氣候 TC11 (day-weather-season plan §4.7, D9 A): typhoons on a Site with the climate on. A typhoon day is a storm
## day of the Region (SiteClimate.typhoon_days, 2–4 a year in July–September). The day before, the Site gets a warning
## (the 1-day omen). On the day itself, once:
## - every unfinished building loses half of its work done (a new building in stage planned/building, an expansion or
##   upgrade in pending_build), completed buildings are not touched;
## - goods stored in the open lose a tenth of each kind (coin excepted) unless the Site has a usable warehouse;
## - ships cannot put out (the storm gate, RegionSaveSlot.region_storm_port).
## The struck day is saved (Site key `typhoon_struck`), so a reload never strikes twice.
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

const KEY := "typhoon_struck"
const WORK_KEPT := 0.5
const OPEN_LOSS := 0.1
const SHELTERED := ["warehouse"]

static func typhoon_on(data: TerrainData, day: int) -> bool:
	if not Climate.enabled(data) or day < 0: return false
	var keys := Climate.site_keys(data)
	var year := int(Calendar.date(float(Calendar.day_start_minute(day))).year)
	return Climate.typhoon_days(str(keys.world), str(keys.region), year).has(day)

static func sheltered(data: TerrainData) -> bool:
	for feature: Dictionary in data.site.get("features", {}).values():
		if str(feature.get("kind", "")) in SHELTERED and str(feature.get("stage", "complete")) == "complete" and Runtime.feature_usable(feature): return true
	return false

## Today's typhoon pass: {omen: bool, struck: bool, buildings: [key], lost: {item: n}}.
static func day(data: TerrainData, today: int) -> Dictionary:
	var result := {"omen": false, "struck": false, "buildings": [], "lost": {}}
	if not Climate.enabled(data): return result
	if typhoon_on(data, today + 1) and not typhoon_on(data, today):
		result.omen = true
		if data.site.get("notices") is Array: data.site.notices.append("天色有異，明日恐有颱風；未完工的建築與露天存物將受損，船不能出海")
	if not typhoon_on(data, today) or int(data.site.get(KEY, -1)) == today: return result
	data.site[KEY] = today
	result.struck = true
	var keys: Array = data.site.get("features", {}).keys()
	keys.sort()
	for key: String in keys:
		var feature: Dictionary = data.site.features[key]
		if feature.get("pending_build") is Dictionary:
			var pending: Dictionary = feature.pending_build
			if float(pending.get("progress", 0.0)) > 0.0:
				pending["progress"] = float(pending.progress) * WORK_KEPT
				result.buildings.append(key)
		elif str(feature.get("stage", "complete")) in ["planned", "building"] and float(feature.get("progress", 0.0)) > 0.0:
			feature["progress"] = float(feature.progress) * WORK_KEPT
			result.buildings.append(key)
	if not sheltered(data):
		var inventory: Dictionary = data.site.get("inventory", {})
		var items: Array = inventory.keys()
		items.sort()
		for item: Variant in items:
			if str(item) == "coin": continue
			var have := int(inventory[item])
			var lost := floori(float(have) * OPEN_LOSS)
			if lost <= 0: continue
			inventory[item] = have - lost
			result.lost[str(item)] = lost
	if data.site.get("notices") is Array:
		data.site.notices.append("颱風過境：%d 處工程受損%s" % [result.buildings.size(), "，露天存物受損" if not result.lost.is_empty() else ""])
	if not result.buildings.is_empty(): data.environment_revision += 1
	return result

static func validate(state: Dictionary) -> Dictionary:
	if not state.has(KEY): return Runtime.ok()
	var value: Variant = state[KEY]
	if not (value is int or value is float) or float(value) != floorf(float(value)) or float(value) < 0.0: return Runtime.fail("CORRUPT_SAVE", "颱風紀錄")
	return Runtime.ok()

static func normalize(state: Dictionary) -> void:
	if state.get(KEY) is float: state[KEY] = int(state[KEY])
