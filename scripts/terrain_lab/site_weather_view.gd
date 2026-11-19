extends CanvasLayer
## Weather on screen (時間與氣候 TC5a = 氣候 S2 picture part; reports/day-weather-season-plan.md §4.4: 「雨是一層全畫面
## 的著色器加一個調色，不逐格畫」). A full-screen layer over the Site world, under the UI: animated rain streaks whose
## density and slant follow the slot's rain and wind (drizzle light, rain dense, storm dense and slanted), and a pale
## fog veil in the early-morning fog. Darkening for cloud and rain is SiteDaylight's. Climate off: nothing is shown.
## Sounds wait for their audio assets.
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")

const RAIN_SHADER := """
shader_type canvas_item;
uniform float density = 0.0;
uniform vec2 slant = vec2(0.0, 1.0);
uniform float speed = 1.6;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV * vec2(80.0, 24.0);
	uv.x += uv.y * slant.x * 0.35;
	uv.y -= TIME * speed * 6.0;
	vec2 cell = floor(uv);
	vec2 local = fract(uv);
	float drop = step(1.0 - density, hash(cell)) * (1.0 - smoothstep(0.0, 0.08, abs(local.x - 0.5))) * smoothstep(0.0, 0.6, local.y) * (1.0 - local.y);
	COLOR = vec4(0.78, 0.84, 0.95, drop * 0.55);
}
"""
## Per weather: streak density (0..1) and fog veil alpha.
const LOOK := {"clear": [0.0, 0.0], "cloudy": [0.0, 0.0], "drizzle": [0.12, 0.0], "rain": [0.32, 0.0], "storm": [0.5, 0.0], "fog": [0.0, 0.32]}

var lab: Variant = null
var rain_rect: ColorRect = null
var fog_rect: ColorRect = null
var current := "clear"

## {density, fog, slant} of a climate answer ({} = climate off).
static func look_of(now: Dictionary) -> Dictionary:
	if now.is_empty(): return {"density": 0.0, "fog": 0.0, "slant": Vector2(0.0, 1.0)}
	var look: Array = LOOK.get(str(now.get("weather", "clear")), [0.0, 0.0])
	var wind: Vector2 = now.get("wind", Vector2.ZERO)
	return {"density": float(look[0]), "fog": float(look[1]), "slant": Vector2(clampf(wind.x, -1.0, 1.0), 1.0)}

func _ready() -> void:
	name = "SiteWeatherView"
	layer = 1
	rain_rect = ColorRect.new()
	rain_rect.name = "Rain"
	rain_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = RAIN_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	rain_rect.material = material
	add_child(rain_rect)
	fog_rect = ColorRect.new()
	fog_rect.name = "Fog"
	fog_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog_rect.color = Color(0.92, 0.93, 0.95, 0.0)
	add_child(fog_rect)
	step()

var _slot_key := "<none>"

## Applies the Site's current weather (looked up once per 2-hour slot).
func step() -> void:
	var data: TerrainData = lab.terrain if lab != null else null
	var key := "" if data == null or not Climate.enabled(data) else "%s:%d" % [str(data.site.get("id", "")), int(float(data.site.get("minute", 0)) / float(Climate.SLOT_MINUTES))]
	if key == _slot_key and rain_rect != null: return
	_slot_key = key
	var now := Climate.for_site(data) if data != null else {}
	current = str(now.get("weather", "clear")) if not now.is_empty() else "clear"
	var look := look_of(now)
	rain_rect.visible = float(look.density) > 0.0
	if rain_rect.visible:
		(rain_rect.material as ShaderMaterial).set_shader_parameter("density", float(look.density))
		(rain_rect.material as ShaderMaterial).set_shader_parameter("slant", look.slant)
	fog_rect.visible = float(look.fog) > 0.0
	fog_rect.color.a = float(look.fog)

func _process(_delta: float) -> void:
	step()
