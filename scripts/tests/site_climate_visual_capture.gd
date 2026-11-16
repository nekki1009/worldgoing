extends "res://scripts/tests/site_building_ui_test.gd"
## 時間與氣候 TC4/TC5a picture capture (visual mode only, not a regression test). A building fixture Site with climate on
## is shown at noon and at night in rain; each frame is saved under res://output/climate_tc4_tc5/.
## Output: SITE_CLIMATE_VISUAL_CAPTURE_DONE with the saved paths; quit(1) on failure.
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const OUT := "res://output/climate_tc4_tc5"

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _slot(data: TerrainData, weather: String, hour_from: int, hour_to: int) -> int:
	var keys := Climate.site_keys(data)
	for minute: int in range(0, 400 * 1440, 120):
		var at := Calendar.minute_of_day(float(minute + 30))
		if at < hour_from * 60 or at >= hour_to * 60: continue
		if str(Climate.at(str(keys.world), str(keys.region), 0.0, float(minute + 30)).weather) == weather: return minute + 30
	return -1

func _capture(lab: TerrainLab, name: String) -> String:
	for _frame: int in range(90): await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	image.save_png(ProjectSettings.globalize_path(path))
	return path

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var data := _building_fixture()
	_formal_feature(data, "warehouse", Vector2i(14, 14))
	var lab := _building_lab(data)
	data.site["climate_enabled"] = true
	var noon := _slot(data, "clear", 11, 13)
	var night_rain := _slot(data, "rain", 21, 24)
	if noon < 0 or night_rain < 0:
		printerr("SITE_CLIMATE_VISUAL_CAPTURE_FAIL: slots ", noon, " ", night_rain)
		quit(1)
		return
	data.site.minute = noon
	var first: String = await _capture(lab, "noon_clear")
	data.site.minute = night_rain
	var second: String = await _capture(lab, "night_rain")
	print("SITE_CLIMATE_VISUAL_CAPTURE_DONE ", first, " ", second)
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
