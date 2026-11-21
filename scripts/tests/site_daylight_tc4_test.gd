extends SceneTree
## 時間與氣候 TC4 (氣候 S1; reports/day-weather-season-plan.md §4.2, N1 A). Checks:
## - the clock's light: night blue at about 45% of daylight from 19:00 to 05:00, rising through dawn to white by
##   07:00, white until 17:00, through dusk orange back to night by 19:00; weather dims it;
## - climate off: white (the old fixed daylight) and no glow;
## - the node: with climate on at 23:00 it becomes the night colour, glows sit on the camp, a settlement centre and a
##   burning fire unit; a jump of the clock to noon eases instead of snapping (fast-forward) and settles on the noon light.
## Output: SITE_DAYLIGHT_TC4_PASS on success; quit(1) on failure.
const Daylight = preload("res://scripts/terrain_lab/site_daylight.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
var checks := 0

class FakeLab extends RefCounted:
	var terrain: TerrainData

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_DAYLIGHT_TC4 OK ", checks, ": ", message)
		return true
	printerr("SITE_DAYLIGHT_TC4_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _brightness(color: Color) -> float:
	return (color.r + color.g + color.b) / 3.0

func _run() -> void:
	var night := Daylight.light_at(23 * 60)
	var noon := Daylight.light_at(12 * 60)
	var dawn := Daylight.light_at(6 * 60)
	var dusk := Daylight.light_at(18 * 60)
	if not _ok(noon == Color(1, 1, 1) and night == Daylight.NIGHT and Daylight.light_at(4 * 60) == Daylight.NIGHT and Daylight.light_at(19 * 60) == Daylight.NIGHT, "noon is white; 19:00–05:00 is night"): return
	if not _ok(absf(_brightness(night) - 0.537) < 0.05 and _brightness(night) < _brightness(dawn) and _brightness(dawn) < 1.0 and dusk.r > dusk.b, "night is about half daylight; dawn in between; dusk is warm", [night, dawn, dusk]): return
	if not _ok(_brightness(Daylight.light_at(12 * 60, "storm")) < _brightness(Daylight.light_at(12 * 60, "rain")) and _brightness(Daylight.light_at(12 * 60, "rain")) < 1.0, "weather dims the day"): return
	var data := TerrainData.new()
	data.size = Vector2i(40, 40)
	data.site = {"id": "s1", "minute": Calendar.day_start_minute(Calendar.day_of(1, 6, 10)) + 23 * 60, "phase": 0.0, "depot_cell": data.index(Vector2i(5, 5)),
		"features": {"c": {"kind": "settlement_center", "entrance": data.index(Vector2i(10, 10))}, "b": {"kind": "house", "entrance": data.index(Vector2i(20, 20))}},
		"settlement": {"center_id": "c"}, "fire": {"units": {"u1": {"feature": "b", "intensity": 0.8}, "u2": {"feature": "c", "intensity": 0.0}}}}
	if not _ok(Daylight.target_color(data) == Color(1, 1, 1), "climate off: white"): return
	var lab := FakeLab.new()
	lab.terrain = data
	var node: CanvasModulate = Daylight.new()
	node.lab = lab
	root.add_child(node)
	node.set_process(false)
	node.step(0.0)
	if not _ok(node.color == Color(1, 1, 1) and not node._glow.visible, "the node stays white with no glow while climate is off"): return
	data.site["climate_enabled"] = true
	node.step(0.0)
	var cells := Daylight.glow_cells(data)
	if not _ok(_brightness(node.color) < 0.6 and node._glow.visible and cells == [Vector2i(5, 5), Vector2i(10, 10), Vector2i(20, 20)], "23:00 with climate on: night, glows on the camp, the centre and the burning house", [node.color, cells]): return
	if not _ok(node._glow.get_child_count() == 3 and (node._glow.get_child(2) as Sprite2D).position == Vector2(20 * 64 + 32, 20 * 64 + 32), "glow sprites sit on their cells"): return
	var before := _brightness(node.color)
	data.site.minute = Calendar.day_start_minute(Calendar.day_of(1, 6, 11)) + 12 * 60
	node.step(0.1)
	var eased := _brightness(node.color)
	var noon_light := _brightness(Daylight.target_color(data))
	if not _ok(eased > before + 0.01 and eased < noon_light - 0.05, "a jump to noon eases instead of snapping", [before, eased, noon_light]): return
	for _i: int in range(60): node.step(0.1)
	var target := Daylight.target_color(data)
	if not _ok(absf(_brightness(node.color) - _brightness(target)) < 0.01 and _brightness(target) >= 0.7 and node._glow.visible == (Daylight.darkness(target) > 0.05), "after a few seconds it reaches the noon light (weather-dimmed at most to 0.7); glows only if the weather darkens it", [node.color, target]): return
	node.queue_free()
	await process_frame
	print("SITE_DAYLIGHT_TC4_PASS checks=", checks)
	quit(0)
