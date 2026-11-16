extends Node
## Weather sound (時間與氣候 TC5; reports/day-weather-season-plan.md §4.4 「雨聲、風聲、雷聲由同一個查詢驅動」;
## Nekki 2026-11-16 09:43Z A: licensed sounds by Codex CC-20261116-195, credits in assets/audio/WEATHER_CREDITS.md).
## One looping ambience per 2-hour weather slot: drizzle the light rain, rain the heavy rain, a storm the storm loop, a
## strong wind (0.6 and above, e.g. the north-east monsoon) the wind loop; clear calm and fog are quiet. In a storm a
## thunder clap sounds every THUNDER_MIN..THUNDER_MAX real seconds. Changes cross-fade over FADE_SECONDS. Everything plays
## on the SFX bus, so the game's sound volume and mute apply. Climate off: silent.
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")

const LOOPS := {
	"rain_light": "res://assets/audio/weather_rain_light_loop.wav",
	"rain_heavy": "res://assets/audio/weather_rain_heavy_loop.wav",
	"storm": "res://assets/audio/weather_storm_loop.wav",
	"wind": "res://assets/audio/weather_wind_loop.wav",
}
const THUNDER := ["res://assets/audio/weather_thunder_01.wav", "res://assets/audio/weather_thunder_02.wav", "res://assets/audio/weather_thunder_03.wav"]
const AMBIENCE_DB := -10.0
const SILENT_DB := -60.0
const FADE_SECONDS := 2.5
const THUNDER_MIN := 12.0
const THUNDER_MAX := 40.0
const WINDY := 0.6

var lab: Variant = null
var current := ""
var _players := {}
var _thunder: AudioStreamPlayer = null
var _thunder_wait := 0.0
var _rng := RandomNumberGenerator.new()
var _slot_key := "<none>"

## The loop for a climate answer: "" for quiet.
static func loop_for(now: Dictionary) -> String:
	if now.is_empty(): return ""
	match str(now.get("weather", "clear")):
		"drizzle": return "rain_light"
		"rain": return "rain_heavy"
		"storm": return "storm"
		"fog": return ""
	var wind: Vector2 = now.get("wind", Vector2.ZERO)
	return "wind" if wind.length() >= WINDY else ""

## The four ambience files loop by their import settings (edit/loop_mode = forward).
static func _stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path): return null
	var stream: Variant = load(path)
	return stream if stream is AudioStream else null

func _ready() -> void:
	name = "SiteWeatherAudio"
	_rng.seed = 20261116
	for key: String in LOOPS:
		var player := AudioStreamPlayer.new()
		player.name = "Weather_" + key
		player.bus = &"SFX"
		player.stream = _stream(str(LOOPS[key]))
		player.volume_db = SILENT_DB
		add_child(player)
		_players[key] = player
	_thunder = AudioStreamPlayer.new()
	_thunder.name = "WeatherThunder"
	_thunder.bus = &"SFX"
	_thunder.volume_db = AMBIENCE_DB + 2.0
	add_child(_thunder)
	_thunder_wait = _rng.randf_range(THUNDER_MIN, THUNDER_MAX)

## The weather loop that should play now ("" quiet), looked up once per slot.
func target() -> String:
	var data: TerrainData = lab.terrain if lab != null else null
	var key := "" if data == null or not Climate.enabled(data) else "%s:%d" % [str(data.site.get("id", "")), int(float(data.site.get("minute", 0)) / float(Climate.SLOT_MINUTES))]
	if key != _slot_key:
		_slot_key = key
		current = loop_for(Climate.for_site(data) if data != null else {})
	return current

func step(delta: float) -> void:
	var wanted := target()
	var rate := delta / FADE_SECONDS * (AMBIENCE_DB - SILENT_DB)
	for key: String in _players:
		var player: AudioStreamPlayer = _players[key]
		if player.stream == null: continue
		var goal := AMBIENCE_DB if key == wanted else SILENT_DB
		player.volume_db = move_toward(player.volume_db, goal, rate) if delta > 0.0 else goal
		if key == wanted and not player.playing: player.play()
		elif key != wanted and player.playing and player.volume_db <= SILENT_DB + 0.01: player.stop()
	if wanted == "storm":
		_thunder_wait -= delta
		if _thunder_wait <= 0.0:
			_thunder.stream = _stream(str(THUNDER[_rng.randi_range(0, THUNDER.size() - 1)]))
			if _thunder.stream != null: _thunder.play()
			_thunder_wait = _rng.randf_range(THUNDER_MIN, THUNDER_MAX)

func _process(delta: float) -> void:
	step(delta)
