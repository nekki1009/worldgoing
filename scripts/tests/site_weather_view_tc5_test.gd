extends SceneTree
## 時間與氣候 TC5a (氣候 S2, the picture). Checks:
## - the look of each weather: drizzle light rain, rain denser, a storm densest and slanted by the wind, fog a pale
##   veil, clear and cloudy nothing;
## - climate off: no rain and no fog on screen;
## - climate on in a rain slot: the rain layer shows at the rain density; in a fog slot the veil shows.
## Output: SITE_WEATHER_VIEW_TC5_PASS on success; quit(1) on failure.
const View = preload("res://scripts/terrain_lab/site_weather_view.gd")
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
var checks := 0

class FakeLab extends RefCounted:
	var terrain: TerrainData

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_WEATHER_VIEW_TC5 OK ", checks, ": ", message)
		return true
	printerr("SITE_WEATHER_VIEW_TC5_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _find(data: TerrainData, weather: String) -> int:
	var keys := Climate.site_keys(data)
	for minute: int in range(0, 400 * 1440, 120):
		if str(Climate.at(str(keys.world), str(keys.region), 0.0, float(minute + 30)).weather) == weather: return minute + 30
	return -1

func _run() -> void:
	var drizzle := View.look_of({"weather": "drizzle", "wind": Vector2.ZERO})
	var rain := View.look_of({"weather": "rain", "wind": Vector2.ZERO})
	var storm := View.look_of({"weather": "storm", "wind": Vector2(0.8, 0.2)})
	var fog := View.look_of({"weather": "fog", "wind": Vector2.ZERO})
	var clear := View.look_of({"weather": "clear", "wind": Vector2.ZERO})
	if not _ok(0.0 < float(drizzle.density) and float(drizzle.density) < float(rain.density) and float(rain.density) < float(storm.density) and float(storm.slant.x) > 0.5 and float(fog.fog) > 0.0 and float(clear.density) == 0.0 and float(clear.fog) == 0.0, "each weather's look"): return
	var data := TerrainData.new()
	data.site = {"id": "s1", "minute": 0, "phase": 0.0}
	var lab := FakeLab.new()
	lab.terrain = data
	var view: CanvasLayer = View.new()
	view.lab = lab
	root.add_child(view)
	view.set_process(false)
	if not _ok(not view.rain_rect.visible and not view.fog_rect.visible, "climate off: nothing on screen"): return
	data.site["climate_enabled"] = true
	var wet := _find(data, "rain")
	var misty := _find(data, "fog")
	if not _ok(wet >= 0 and misty >= 0, "rain and fog slots exist within 400 days", [wet, misty]): return
	data.site.minute = wet
	view.step()
	if not _ok(view.rain_rect.visible and not view.fog_rect.visible and is_equal_approx(float((view.rain_rect.material as ShaderMaterial).get_shader_parameter("density")), float(rain.density)), "a rain slot shows the rain"): return
	data.site.minute = misty
	view.step()
	if not _ok(view.fog_rect.visible and not view.rain_rect.visible and view.fog_rect.color.a > 0.2, "a fog slot shows the veil"): return
	view.queue_free()
	await process_frame
	print("SITE_WEATHER_VIEW_TC5_PASS checks=", checks)
	quit(0)
