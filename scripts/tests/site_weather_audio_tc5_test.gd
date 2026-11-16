extends SceneTree
## 時間與氣候 TC5 weather sound. Checks:
## - the loop for each weather: drizzle light rain, rain heavy rain, storm the storm loop, a strong wind the wind loop,
##   calm clear and fog quiet;
## - the seven licensed files load and the four loops loop;
## - climate off: silent; in a storm slot the storm loop fades in and the others stay silent; thunder sounds in a storm.
## Output: SITE_WEATHER_AUDIO_TC5_PASS on success; quit(1) on failure.
const Audio = preload("res://scripts/terrain_lab/site_weather_audio.gd")
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
var checks := 0

class FakeLab extends RefCounted:
	var terrain: TerrainData

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_WEATHER_AUDIO_TC5 OK ", checks, ": ", message)
		return true
	printerr("SITE_WEATHER_AUDIO_TC5_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

func _run() -> void:
	var picks := [Audio.loop_for({"weather": "drizzle", "wind": Vector2.ZERO}), Audio.loop_for({"weather": "rain", "wind": Vector2.ZERO}),
		Audio.loop_for({"weather": "storm", "wind": Vector2(1, 0)}), Audio.loop_for({"weather": "clear", "wind": Vector2(0.7, 0)}),
		Audio.loop_for({"weather": "clear", "wind": Vector2(0.2, 0)}), Audio.loop_for({"weather": "fog", "wind": Vector2.ZERO}), Audio.loop_for({})]
	if not _ok(picks == ["rain_light", "rain_heavy", "storm", "wind", "", "", ""], "the loop for each weather", picks): return
	var loaded := 0
	for path: String in Audio.LOOPS.values() + Audio.THUNDER:
		if Audio._stream(path) != null: loaded += 1
	if not _ok(loaded == 7, "the seven licensed files load", loaded): return
	var looping := true
	for path: String in Audio.LOOPS.values(): looping = looping and (Audio._stream(path) as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	if not _ok(looping, "the four ambience files loop"): return
	var data := TerrainData.new()
	data.site = {"id": "s1", "minute": 0, "phase": 0.0}
	var lab := FakeLab.new()
	lab.terrain = data
	var node: Node = Audio.new()
	node.lab = lab
	root.add_child(node)
	node.set_process(false)
	node.step(0.0)
	var playing := 0
	for player: AudioStreamPlayer in node._players.values():
		if player.playing: playing += 1
	if not _ok(playing == 0 and node.current == "", "climate off: silent"): return
	data.site["climate_enabled"] = true
	var keys := Climate.site_keys(data)
	var storm := -1
	for minute: int in range(0, 400 * 1440, 120):
		if str(Climate.at(str(keys.world), str(keys.region), 0.0, float(minute + 30)).weather) == "storm":
			storm = minute + 30
			break
	if not _ok(storm >= 0, "a storm slot exists within 400 days"): return
	data.site.minute = storm
	for _i: int in range(12): node.step(0.5)
	var storm_player: AudioStreamPlayer = node._players["storm"]
	var others_quiet := true
	for key: String in node._players:
		if key != "storm": others_quiet = others_quiet and not (node._players[key] as AudioStreamPlayer).playing
	if not _ok(node.current == "storm" and storm_player.playing and is_equal_approx(storm_player.volume_db, Audio.AMBIENCE_DB) and others_quiet, "a storm fades its loop in; the others stay silent", [node.current, storm_player.volume_db]): return
	node._thunder_wait = 0.0
	node.step(0.1)
	if not _ok(node._thunder.stream != null and node._thunder.playing, "thunder sounds in a storm"): return
	node.queue_free()
	await process_frame
	print("SITE_WEATHER_AUDIO_TC5_PASS checks=", checks)
	quit(0)
