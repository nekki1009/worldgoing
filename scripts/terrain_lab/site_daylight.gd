extends CanvasModulate
## Day and night light (時間與氣候 TC4 = 氣候 S1; reports/day-weather-season-plan.md §4.2, §7 risk 2;
## reports/time-and-climate-plan.md N1 A). A CanvasModulate over the Site world (UI layers are untouched) whose colour
## follows the clock: night 19:00–05:00 a deep blue at about 45% of daylight (units stay readable), dawn 05:00–07:00
## rising to white, day white, dusk 17:00–19:00 through orange back to the night blue. Weather dims it (TC3 slot).
## Fast-forward (×8 / ×16 sleep) stays smooth: the shown colour eases toward the clock's colour over EASE_SECONDS of
## real time instead of jumping. Night glows (the camp, a settlement centre, burning fire units) are additive radial
## sprites on their own canvas layer that follows the camera, so the darkness does not dim them. Climate off (old
## saves, tests): white and no glow.
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")

const NIGHT := Color(0.45, 0.5, 0.66)
const DAWN := Color(0.78, 0.72, 0.86)
const DUSK := Color(1.0, 0.76, 0.6)
const DAY := Color(1, 1, 1)
## (minute of day, colour) keyframes, interpolated linearly.
const KEYS := [[0, NIGHT], [300, NIGHT], [360, DAWN], [420, DAY], [1020, DAY], [1080, DUSK], [1140, NIGHT], [1440, NIGHT]]
const WEATHER_DIM := {"clear": 1.0, "cloudy": 0.92, "drizzle": 0.88, "rain": 0.8, "storm": 0.7, "fog": 0.95}
const FOG_TINT := Color(0.86, 0.88, 0.9)
const EASE_SECONDS := 1.5
const GLOW_RADIUS := 3.5 # cells
const GLOW_MAX := 48

var lab: Variant = null
var glow_layer: CanvasLayer = null
var _glow: Node2D = null
var _glow_texture: GradientTexture2D = null

## The clock's light for a minute of the day and a weather (pure).
static func light_at(minute_in_day: float, weather: String = "clear") -> Color:
	var at := fposmod(minute_in_day, 1440.0)
	var result := DAY
	for index: int in range(KEYS.size() - 1):
		var a: Array = KEYS[index]
		var b: Array = KEYS[index + 1]
		if at >= float(a[0]) and at <= float(b[0]):
			var span := maxf(1.0, float(b[0]) - float(a[0]))
			result = (a[1] as Color).lerp(b[1] as Color, (at - float(a[0])) / span)
			break
	var dim := float(WEATHER_DIM.get(weather, 1.0))
	result = Color(result.r * dim, result.g * dim, result.b * dim)
	if weather == "fog": result = result.lerp(FOG_TINT, 0.35)
	return result

## The target colour of a Site now: white while its climate is off.
static func target_color(data: TerrainData) -> Color:
	if data == null or not Climate.enabled(data): return DAY
	var minute := float(data.site.get("minute", 0)) + float(data.site.get("phase", 0.0))
	var now := Climate.for_site(data)
	return light_at(float(Calendar.minute_of_day(minute)) + fposmod(float(data.site.get("phase", 0.0)), 1.0), str(now.get("weather", "clear")))

## Darkness 0 (day) .. 1 (deepest night) of a colour: drives the glow strength.
static func darkness(light: Color) -> float:
	return clampf((1.0 - (light.r + light.g + light.b) / 3.0) / (1.0 - (NIGHT.r + NIGHT.g + NIGHT.b) / 3.0), 0.0, 1.0)

func _ready() -> void:
	name = "SiteDaylight"
	color = DAY
	glow_layer = CanvasLayer.new()
	glow_layer.name = "SiteNightGlow"
	glow_layer.follow_viewport_enabled = true
	glow_layer.layer = 1
	add_child(glow_layer)
	_glow = Node2D.new()
	_glow.name = "Glows"
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = material
	glow_layer.add_child(_glow)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.72, 0.38, 0.55))
	gradient.set_color(1, Color(1.0, 0.6, 0.3, 0.0))
	_glow_texture = GradientTexture2D.new()
	_glow_texture.gradient = gradient
	_glow_texture.fill = GradientTexture2D.FILL_RADIAL
	_glow_texture.fill_from = Vector2(0.5, 0.5)
	_glow_texture.fill_to = Vector2(1.0, 0.5)
	_glow_texture.width = 128
	_glow_texture.height = 128

## One frame: ease toward the clock's colour and refresh the glows.
func step(delta: float) -> void:
	var data: TerrainData = lab.terrain if lab != null else null
	var target := target_color(data)
	color = color.lerp(target, clampf(delta / EASE_SECONDS * 3.0, 0.0, 1.0)) if delta > 0.0 else target
	var dark := darkness(color)
	_glow.visible = dark > 0.05 and data != null and Climate.enabled(data)
	if _glow.visible:
		_glow.modulate = Color(1, 1, 1, dark)
		_glow.queue_redraw()
		_place_glows(data)

func _process(delta: float) -> void:
	step(delta)

## The cells that glow at night: the camp, a settlement centre, burning fire units.
static func glow_cells(data: TerrainData) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if data == null: return result
	if int(data.site.get("depot_cell", -1)) >= 0: result.append(data.cell_from_index(int(data.site.depot_cell)))
	var center: Variant = data.site.get("features", {}).get(str(data.site.get("settlement", {}).get("center_id", "")))
	if center is Dictionary and center.has("entrance"): result.append(data.cell_from_index(int(center.entrance)))
	var fire: Variant = data.site.get("fire", {})
	if fire is Dictionary:
		for unit: Variant in fire.get("units", {}).values():
			if result.size() >= GLOW_MAX: break
			if not unit is Dictionary or float(unit.get("intensity", 0.0)) <= 0.0: continue
			if unit.has("resource"):
				var resource := Env.resource(data, str(unit.resource))
				if not resource.is_empty(): result.append(data.cell_from_index(int(resource.cell)))
			elif unit.has("feature"):
				var feature: Variant = data.site.get("features", {}).get(str(unit.feature))
				if feature is Dictionary and feature.has("entrance"): result.append(data.cell_from_index(int(feature.entrance)))
	return result

func _place_glows(data: TerrainData) -> void:
	var cells := glow_cells(data)
	while _glow.get_child_count() < cells.size():
		var sprite := Sprite2D.new()
		sprite.texture = _glow_texture
		sprite.scale = Vector2.ONE * (GLOW_RADIUS * 2.0 * 64.0 / 128.0)
		_glow.add_child(sprite)
	for index: int in _glow.get_child_count():
		var sprite: Sprite2D = _glow.get_child(index)
		sprite.visible = index < cells.size()
		if sprite.visible: sprite.position = Vector2(cells[index]) * 64.0 + Vector2(32.0, 32.0)
