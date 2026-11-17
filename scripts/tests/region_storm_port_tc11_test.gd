extends SceneTree
## 時間與氣候 TC11 (day-weather-season plan §4.7, D8 A): a storm holds ships in port. A world opens. Checks:
## - with the world's climate off, ships may always leave;
## - with it on, at a 2-hour slot whose weather is a storm (a typhoon day of year 1) the Site refuses STORM_PORT, and
##   at a clear slot it lets ships leave;
## - the refusal is what the player's sea plan, a ship transfer and an NPC sea dispatch return (one gate,
##   RegionSaveSlot.region_storm_port).
## Output: REGION_STORM_PORT_TC11_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const RegionWeather = preload("res://scripts/region_lab/region_weather.gd")
const START := Vector2i(1170, 13252)

var checks := 0
var _finished := false

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("300-second deadline"))
	_run.call_deferred()

func _fail(message: String, detail: Variant = null) -> void:
	if _finished: return
	_finished = true
	printerr("REGION_STORM_PORT_TC11_FAIL: ", message, " ", str(detail))
	quit(1)

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("REGION_STORM_PORT_TC11 OK ", checks, ": ", message)
		return true
	_fail(message, detail)
	return false

func _run() -> void:
	if not _check(RegionEntry.request_new_world(START, {}, "封港世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "found", "name": "甲國"}), "a world is requested", RegionEntry.menu_message): return
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
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var site: Vector2i = slot._coordinate(lab.terrain).site
	var world := str(slot.pin.get("world_instance_id", ""))
	var region := RegionWeather.region_key(str(slot.pin.get("atlas_id", "")), site)
	# A storm slot and a clear slot of year 1, in game seconds.
	var storm_at := -1.0
	var clear_at := -1.0
	var typhoons: Dictionary = Climate.typhoon_days(world, region, 1)
	var days: Array = typhoons.keys()
	days.sort()
	for day: Variant in days:
		for index: int in Climate.SLOTS:
			var minute := float(Calendar.day_start_minute(int(day)) + index * Climate.SLOT_MINUTES + 1)
			if minute >= 0.0 and str(RegionWeather.at(world, str(slot.pin.atlas_id), site, minute * 60.0).weather) == "storm":
				storm_at = minute * 60.0
				break
		if storm_at >= 0.0: break
	for minute: int in range(60, 60 * 24 * 60, 120):
		if str(RegionWeather.at(world, str(slot.pin.atlas_id), site, float(minute) * 60.0).weather) == "clear":
			clear_at = float(minute) * 60.0
			break
	if not _check(storm_at >= 0.0 and clear_at >= 0.0, "year 1 has a typhoon storm slot and a clear slot here", [storm_at, clear_at, days]): return

	var registry: Dictionary = slot.control.faction_registry
	var climate_before: Variant = registry.get("climate")
	registry.erase("climate")
	if not _check(slot.region_storm_port(site, storm_at).is_empty(), "with the climate off ships always leave"): return
	registry["climate"] = {"version": 1, "enabled": true} # test-only, in memory
	var held: Dictionary = slot.region_storm_port(site, storm_at)
	var open: Dictionary = slot.region_storm_port(site, clear_at)
	if climate_before == null: registry.erase("climate")
	else: registry["climate"] = climate_before
	if not _check(str(held.get("code", "")) == "STORM_PORT" and not bool(held.get("ok", true)), "in a storm the port is shut", held): return
	if not _check(open.is_empty(), "in clear weather ships leave", open): return
	_finished = true
	print("REGION_STORM_PORT_TC11_PASS: ", checks, " checks; a storm holds ships in port")
	quit(0)
