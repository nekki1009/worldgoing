extends SceneTree
## Headless exact scalar/original-events contract, not FPS or live hit acceptance.
const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const Rules = preload("res://scripts/terrain_lab/site_combat_rules.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const CALLS := 41501

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var deadline := Time.get_ticks_usec() + 18000000
	assert(Timings.ATTACKS.size() == 12)
	var source_before := FileAccess.get_sha256("res://scripts/terrain_lab/character_combat_timings.gd")
	var requests: Array[Array] = []
	var duration_checks := 0
	var sample_checks := 0
	var event_checks := 0
	for clip: StringName in Timings.ATTACKS:
		var event := Timings.events(clip)
		var second := Timings.events(clip)
		assert(event == second and not is_same(event, second))
		assert(event.size() == 4 and event.has("release"))
		event.duration = -123.0
		event.erase("release")
		assert(Timings.events(clip) == second, "Public events must remain a fresh caller-owned Dictionary")
		event = second
		event_checks += 1
		for training: float in [0.0, 60.0, 10000.0, 1000000000000.0]:
			var reduction := Rules.diminishing(training, 0.15)
			for fatigue: float in [0.0, 30.0 - 0.000000001, 30.0, 30.0 + 0.000000001, 65.0, 100.0]:
				assert(Time.get_ticks_usec() < deadline)
				var slowdown := Fatigue.slowdown(fatigue)
				var duration := _original_duration(clip, reduction, slowdown)
				assert(Timings.action_duration(clip, reduction, slowdown) == duration, "Exact action duration changed")
				duration_checks += 1
				var speed := (1.0 - reduction) * (1.0 + slowdown)
				var windup: float = event.active_start * speed
				var active_end: float = windup + event.active_end - event.active_start
				var elapsed_values: Array[float] = [-1.0, duration + 10.0, duration * 0.37,
					windup * 0.5, windup + (active_end - windup) * 0.5]
				for boundary: float in [0.0, windup, active_end, duration]:
					for epsilon: float in [-0.000000001, 0.0, 0.000000001]:
						elapsed_values.append(boundary + epsilon)
				for elapsed: float in elapsed_values:
					var expected := _original_sample(clip, elapsed, reduction, slowdown)
					assert(Timings.sample_time(clip, elapsed, reduction, slowdown) == expected,
						"Exact sample changed at %s / %.17f / %.17f / %.17f" % [clip, elapsed, reduction, slowdown])
					requests.append([clip, elapsed, reduction, slowdown])
					sample_checks += 1
	# The public invalid-clip API stays {}; the two scalar functions' original
	# error-producing cold branches are preserved in production, not invoked in
	# this success-oriented verifier (which must reject any SCRIPT ERROR).
	var invalid := Timings.events(&"__not_an_authored_attack")
	var invalid_again := Timings.events(&"__not_an_authored_attack")
	assert(invalid.is_empty() and invalid_again.is_empty() and not is_same(invalid, invalid_again))
	invalid["duration"] = 9.0
	assert(Timings.events(&"__not_an_authored_attack").is_empty())
	var timings: Array[Dictionary] = []
	for scalar: bool in [false, true]:
		var started := Time.get_ticks_usec()
		var sample_checksum := 0.0
		var duration_checksum := 0.0
		for index in range(CALLS):
			var request: Array = requests[index % requests.size()]
			sample_checksum += Timings.sample_time(request[0], request[1], request[2], request[3]) if scalar else _original_sample(request[0], request[1], request[2], request[3])
			duration_checksum += Timings.action_duration(request[0], request[2], request[3]) if scalar else _original_duration(request[0], request[2], request[3])
		timings.append({"scalar": scalar, "sample_calls": CALLS, "duration_calls": CALLS,
			"elapsed_usec": Time.get_ticks_usec() - started,
			"sample_checksum": sample_checksum, "duration_checksum": duration_checksum})
		assert(Time.get_ticks_usec() < deadline)
	assert(timings[0].sample_checksum == timings[1].sample_checksum and timings[0].duration_checksum == timings[1].duration_checksum)
	assert(FileAccess.get_sha256("res://scripts/terrain_lab/character_combat_timings.gd") == source_before)
	var report := {"clips": Timings.ATTACKS.size(), "duration_checks": duration_checks,
		"sample_checks": sample_checks, "fresh_valid_event_checks": event_checks,
		"fresh_invalid_events": true, "invalid_scalar_error_calls_executed": false,
		"maximum_error": 0.0, "passes": timings, "source_sha256": source_before,
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_combat_timing_scalar_test.gd"),
		"scope": "All original 12 clips, actual training/fatigue curves, windup/active/end boundaries +/-1e-9, exact == against original events arithmetic; public events remain fresh. Local scalar timings, not FPS or live collision acceptance."}
	var path := "res://output/site_combat_performance_20260913/scalar_timings/%d_%d/measurements.json" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE_COMBAT_TIMING_SCALAR_PASS ", JSON.stringify(report))
	quit(0)

static func _original_duration(clip: StringName, reduction: float, fatigue_slowdown: float = 0.0) -> float:
	var event := Timings.events(clip)
	var active: float = event.active_end - event.active_start
	return active + (float(event.duration) - active) * (1.0 - reduction) * (1.0 + fatigue_slowdown)

static func _original_sample(clip: StringName, elapsed: float, reduction: float, fatigue_slowdown: float = 0.0) -> float:
	var event := Timings.events(clip)
	var speed := (1.0 - reduction) * (1.0 + fatigue_slowdown)
	var windup: float = event.active_start * speed
	var active_end: float = windup + event.active_end - event.active_start
	if elapsed < windup:
		return elapsed / speed
	if elapsed <= active_end:
		return event.active_start + elapsed - windup
	return minf(event.duration, event.active_end + (elapsed - active_end) / speed)
