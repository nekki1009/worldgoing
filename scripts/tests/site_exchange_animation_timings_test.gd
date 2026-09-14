extends SceneTree
const Timings = preload("res://scripts/terrain_lab/character_exchange_timings.gd")
const Original = preload("res://scripts/terrain_lab/character_combat_timings.gd")

func _initialize() -> void:
	var samples := 0
	for clip: StringName in Original.ATTACKS.keys() + Timings.REACTION_LENGTHS.keys():
		var length := Timings.authored_duration(clip)
		var duration := Timings.duration(clip)
		assert(length > 0.0 and duration > 0.0)
		var previous := -1.0
		for index: int in 121:
			var elapsed := duration * float(index) / 120.0
			var time := Timings.sample_time(clip, elapsed, length)
			assert(time >= previous and time <= length + 0.0000001)
			assert(is_equal_approx(time, Timings.sample_time(clip, elapsed, 0.0)))
			previous = time
			samples += 1
		assert(is_equal_approx(Timings.sample_time(clip, duration - 1.0 / 30.0, length), length))
		if Timings.STROKE_FRAMES.has(clip):
			assert(Timings.sample_time(clip, 0.0, length) >= float(Original.events(clip).active_start))
	assert(Timings.duration(&"hit") == 0.45 and Timings.duration(&"knockback") == 0.75)
	assert(Timings.reaction_priority(&"hit") == Timings.reaction_priority(&"hit_back"))
	assert(Timings.reaction_priority(&"knockback") > Timings.reaction_priority(&"hit"))
	assert(Timings.duration(&"walk") == 0.0 and Timings.sample_time(&"walk", 0.123, 1.0) == 0.123)
	print("SITE_EXCHANGE_ANIMATION_TIMINGS_PASS: ", samples, " bounded monotonic source samples; complete final pose, shared headless clocks, unchanged authored events")
	quit(0)
