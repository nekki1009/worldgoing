extends SceneTree
## 時間與氣候 TC11 (day-weather-season plan §4.7, D9 A): typhoons on a Site. A world opens; the Site's climate is turned on
## in memory and two test-only stand-ins (an unfinished building and an expansion in progress) are added and removed
## before anything saves. Checks:
## - the day before a typhoon day writes the omen and touches nothing;
## - the typhoon day halves the work done on both unfinished buildings, leaves a complete one alone, and takes a tenth of
##   each kind of open stock (coin excepted) with no warehouse; the day is recorded and a second pass the same day does
##   nothing; the record passes the save rules (malformed ones are refused);
## - with the climate off nothing happens.
## Output: SITE_TYPHOON_TC11_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Typhoon = preload("res://scripts/terrain_lab/site_typhoon.gd")
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("SITE_TYPHOON_TC11_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_TYPHOON_TC11 OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "颱風世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(900):
		await process_frame
		if _finished: return
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if not _check(lab != null, "the new world opens", RegionEntry.menu_message): return
	var data: TerrainData = lab.terrain
	var climate_before: Variant = data.site.get("climate_enabled")
	data.site["climate_enabled"] = true # test-only, in memory
	var keys := Climate.site_keys(data)
	var days: Array = Climate.typhoon_days(str(keys.world), str(keys.region), 1).keys()
	days.sort()
	var strike := -1
	for day: Variant in days:
		if not Typhoon.typhoon_on(data, int(day) - 1): strike = int(day); break
	if not _check(strike > 0 and Typhoon.typhoon_on(data, strike), "year 1 has a typhoon day after a calm one", days): return
	if not _check(not Typhoon.sheltered(data), "the new Site has no warehouse"): return
	data.site.features["typhoon_new"] = {"kind": "house", "stage": "building", "progress": 40.0, "work": 100.0}
	data.site.features["typhoon_grow"] = {"kind": "farm", "stage": "complete", "pending_build": {"progress": 20.0, "work": 50.0}}
	data.site.features["typhoon_done"] = {"kind": "house", "stage": "complete", "progress": 100.0, "work": 100.0}
	var inventory: Dictionary = data.site.inventory
	var before := inventory.duplicate(true)
	inventory["grain"] = int(inventory.get("grain", 0)) + 100
	var grain := int(inventory.grain)
	var coin := int(inventory.get("coin", 0))

	var eve := Typhoon.day(data, strike - 1)
	if not _check(eve.omen and not eve.struck and float(data.site.features.typhoon_new.progress) == 40.0 and int(inventory.grain) == grain, "the day before: an omen, nothing touched", eve): return
	var hit := Typhoon.day(data, strike)
	if not _check(hit.struck and float(data.site.features.typhoon_new.progress) == 20.0 and float(data.site.features.typhoon_grow.pending_build.progress) == 10.0
		and float(data.site.features.typhoon_done.progress) == 100.0, "the typhoon halves the unfinished work and spares the complete house", hit): return
	if not _check(int(hit.lost.get("grain", 0)) == grain / 10 and int(inventory.grain) == grain - grain / 10 and int(inventory.get("coin", 0)) == coin and not hit.lost.has("coin"), "a tenth of the open stock is lost, coin excepted", hit.lost): return
	var again := Typhoon.day(data, strike)
	if not _check(not again.struck and int(data.site.get(Typhoon.KEY, -1)) == strike and float(data.site.features.typhoon_new.progress) == 20.0, "the day strikes once", again): return
	if not _check(Typhoon.validate(data.site).ok, "the record passes the save rules"): return
	for bad: Variant in [-1, 1.5, "x"]:
		if not _check(not Typhoon.validate({Typhoon.KEY: bad}).ok, "a malformed record is refused", bad): return
	data.site.erase(Typhoon.KEY)
	data.site.erase("climate_enabled")
	var off := Typhoon.day(data, strike)
	if not _check(not off.struck and not off.omen, "with the climate off nothing happens", off): return
	for key: String in ["typhoon_new", "typhoon_grow", "typhoon_done"]: data.site.features.erase(key)
	inventory.clear()
	inventory.merge(before)
	if climate_before != null: data.site["climate_enabled"] = climate_before
	_finished = true
	print("SITE_TYPHOON_TC11_PASS: ", checks, " checks; typhoons warn, then damage works and open stock")
	quit(0)
