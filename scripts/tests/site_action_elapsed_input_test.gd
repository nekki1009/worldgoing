extends SceneTree
## Real engine callbacks exercise only elapsed ingress and the original retained
## 30/120 Hz loops. Combat work is counted, not a claim about gameplay or FPS.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const DEADLINE_SECONDS := 20.0

class InputLab extends TerrainLab:
	var samples: Array[Dictionary] = []
	var stepped_seconds := 0.0
	var steps := 0
	var last_input := 0.0
	var last_entry_usec := -1
	var stall_after_next_callback := false
	var costly_steps_after_stall := 0
	var costly_steps_remaining := 0
	var costly_steps_completed := 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		pause_when_unfocused = false

	func _action_elapsed_input(delta: float) -> float:
		last_input = super._action_elapsed_input(delta)
		return last_input

	func _process(delta: float) -> void:
		var entry_usec := Time.get_ticks_usec()
		var before := stepped_seconds + _action_time_remainder
		var before_processed := stepped_seconds
		var before_debt := _action_time_remainder
		var before_costly := costly_steps_completed
		super._process(delta)
		samples.append({"frame": Engine.get_process_frames(), "engine_delta": delta,
			"input": last_input, "accepted": stepped_seconds + _action_time_remainder - before,
			"processed": stepped_seconds - before_processed,
			"debt_before": before_debt, "debt_after": _action_time_remainder,
			"callback_cpu_usec": Time.get_ticks_usec() - entry_usec,
			"costly_steps": costly_steps_completed - before_costly,
			"wall": float(entry_usec - last_entry_usec) / 1000000.0 if last_entry_usec >= 0 else 0.0,
			"scale": Engine.time_scale, "paused": get_tree().paused or bool(terrain.site.get("paused", false)),
			"steps": steps, "remainder": _action_time_remainder})
		last_entry_usec = entry_usec
		if stall_after_next_callback:
			stall_after_next_callback = false
			OS.delay_msec(350) # Intentional bounded stall; next engine delta is capped.
			costly_steps_remaining = costly_steps_after_stall
			costly_steps_after_stall = 0

	func _advance_combat(delta: float, _combat_clock: float = -1.0) -> void:
		if costly_steps_remaining > 0:
			OS.delay_usec(TerrainLab.ACTION_FRAME_BUDGET_USEC + 2000)
			costly_steps_remaining -= 1
			costly_steps_completed += 1
		stepped_seconds += delta
		steps += 1

	func _advance_movement_input() -> void:
		pass

	func _update_info() -> void:
		pass

var _lab: InputLab
var _started := 0
var _folder := ""
var _checks := 0
var _failures: Array[String] = []
var _cases: Array[Dictionary] = []
var _finished := false
var _previous_fps := 0
var _previous_scale := 1.0
var _virtual_delta := false

func _initialize() -> void:
	_started = Time.get_ticks_usec()
	_previous_fps = Engine.max_fps
	_previous_scale = Engine.time_scale
	_folder = "res://output/three_faction_ai_20260928/elapsed_input/run_%d_%d" % [int(Time.get_unix_time_from_system()), _started]
	DirAccess.make_dir_recursive_absolute(_folder)
	_virtual_delta = OS.get_cmdline_args().has("--fixed-fps") or not Engine.get_write_movie_path().is_empty()
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not _finished and float(Time.get_ticks_usec() - _started) / 1000000.0 > DEADLINE_SECONDS:
		_check(false, "Elapsed input test exceeded its wall-clock deadline")
		_finish()
	return false

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures.append(message)
		push_error(message)

func _near(actual: float, expected: float, message: String, tolerance: float = 0.000001) -> void:
	_check(absf(actual - expected) <= tolerance, "%s: %.9f != %.9f" % [message, actual, expected])

func _frames(count: int) -> void:
	var target := _lab.samples.size() + count
	while _lab.samples.size() < target and not _finished:
		await process_frame

func _action_seconds() -> float:
	return _lab.stepped_seconds + _lab._action_time_remainder

func _record(label: String, first: int) -> void:
	_cases.append({"case": label, "samples": _lab.samples.slice(first)})

func _budget_recovery(clock_hz: int) -> void:
	var step := 1.0 / float(clock_hz)
	_lab.exchange_enabled = clock_hz == 30
	_lab.fixed_action_steps_enabled = clock_hz == 120
	Engine.time_scale = 1.0
	await _frames(3)
	var first := _lab.samples.size()
	var before_processed := _lab.stepped_seconds
	var before_debt := _lab._action_time_remainder
	if _virtual_delta:
		# A deliberately large virtual frame must finish even when two complete
		# original steps each cost more than the live frame budget.
		Engine.time_scale = 12.0
		await _frames(2)
		first = _lab.samples.size()
		_lab.costly_steps_remaining = 2
		await _frames(1)
		var virtual_sample: Dictionary = _lab.samples.back()
		_check(int(virtual_sample.costly_steps) == 2, "Virtual callback must complete both costly original steps in one frame")
		_check(float(virtual_sample.processed) >= step * 2.0, "Virtual frame cannot yield after the live CPU budget")
		_near(float(virtual_sample.accepted), float(virtual_sample.engine_delta), "Virtual frame retains all supplied delta")
		_check(float(virtual_sample.debt_after) < step, "Virtual frame must process all complete supplied steps")
		Engine.time_scale = 1.0
		_record("virtual_costly_%d" % clock_hz, first)
		await _frames(2)
	else:
		_lab.costly_steps_after_stall = 2
		_lab.stall_after_next_callback = true
		await _frames(2)
		var yielded: Dictionary = _lab.samples.back()
		_check(float(yielded.input) >= 0.34, "Costly catch-up fixture must accept the real 350 ms stall")
		_check(int(yielded.costly_steps) == 1, "Live budget yields after the first complete costly atomic step")
		_near(float(yielded.processed), step, "Live callback completes exactly one original fixed step before yielding")
		_check(float(yielded.debt_after) >= step, "Yield must retain outstanding complete action steps")
		_check(int(yielded.callback_cpu_usec) >= TerrainLab.ACTION_FRAME_BUDGET_USEC,
			"Fixture must actually cross the live CPU budget")
		var frozen_debt := _lab._action_time_remainder
		var frozen_processed := _lab.stepped_seconds
		# Freeze the same genuinely accepted debt at each authoritative boundary.
		# No active callback occurs between these three pause mechanisms.
		for boundary: String in ["tree", "site", "zero_scale"]:
			paused = boundary == "tree"
			_lab.terrain.site.paused = boundary == "site"
			Engine.time_scale = 0.0 if boundary == "zero_scale" else 1.0
			await _frames(2)
			_near(_lab.stepped_seconds, frozen_processed, "%s cannot process previously accepted debt" % boundary)
			_near(_lab._action_time_remainder, frozen_debt, "%s cannot erase previously accepted debt" % boundary)
		paused = false
		_lab.terrain.site.paused = false
		Engine.time_scale = 1.0
		await _frames(1)
		var resumed: Dictionary = _lab.samples.back()
		_check(int(resumed.costly_steps) == 1, "Resume must finish the second costly original step")
		_near(float(resumed.processed), step, "Resume still yields only after a complete original step")
		for _frame in range(60):
			if _lab._action_time_remainder < step:
				break
			await _frames(1) # Natural callbacks alone must actually finish the debt.
		_check(_lab._action_time_remainder < step, "Natural callbacks must repay whole-step debt within the bounded recovery")
		_check(_lab.costly_steps_remaining == 0, "Both planned costly steps must really execute")
		var accepted_sum := 0.0
		for sample: Dictionary in _lab.samples.slice(first):
			accepted_sum += float(sample.accepted)
			_near(float(sample.processed) + float(sample.debt_after) - float(sample.debt_before),
				float(sample.accepted), "Each callback conserves processed plus retained time")
			var expected := 0.0 if bool(sample.paused) or is_zero_approx(float(sample.scale)) else float(sample.input)
			_near(float(sample.accepted), expected, "Only active callback input is admitted, exactly once")
		_near(_lab.stepped_seconds - before_processed,
			accepted_sum + before_debt - _lab._action_time_remainder,
			"Actual processed time, not admission plus debt, must match fully recovered work")
		_check(_lab.stepped_seconds - before_processed >= 0.34 - step,
			"The stalled interval must be physically processed before this case passes")
		_record("budget_recovery_%d" % clock_hz, first)
	# Existing explicit-delta tests are not subject to real-time frame budgets.
	first = _lab.samples.size()
	_lab.set_process(false)
	_lab.costly_steps_remaining = 2
	_lab._process(0.35)
	var manual: Dictionary = _lab.samples.back()
	_check(int(manual.costly_steps) == 2, "Manual callback must complete both costly steps without budget yielding")
	_near(float(manual.accepted), 0.35, "Manual costly callback accepts its exact supplied time")
	_check(float(manual.debt_after) < step and float(manual.processed) >= 0.35 - step,
		"Manual callback must process all complete supplied steps immediately")
	_record("manual_costly_%d" % clock_hz, first)
	_lab.set_process(true)
	await _frames(2)

func _run() -> void:
	Engine.max_fps = 60
	Engine.time_scale = 1.0
	_check(Engine.max_physics_steps_per_frame == 8 and Engine.physics_ticks_per_second == 60,
		"Regression must exercise the original 8/60 engine cap")
	_lab = InputLab.new()
	_lab.terrain = Helper.build_flat_map(8, 8)
	root.add_child(_lab)
	await _frames(3)
	var first := _lab.samples.size()
	var before := _action_seconds()
	_lab.stall_after_next_callback = true
	await _frames(5)
	var wall_sum := 0.0
	var engine_sum := 0.0
	var input_sum := 0.0
	var largest_wall := 0.0
	for sample: Dictionary in _lab.samples.slice(first):
		wall_sum += float(sample.wall)
		engine_sum += float(sample.engine_delta)
		input_sum += float(sample.input)
		largest_wall = maxf(largest_wall, float(sample.wall))
		_near(float(sample.accepted), float(sample.input), "Original clock accepts each active input exactly once")
	_check(largest_wall >= 0.34, "Intentional stall must be observed by a real later callback")
	if _virtual_delta:
		_near(input_sum, engine_sum, "Fixed-fps/Movie Maker preserves deliberate virtual delta")
	else:
		_check(wall_sum - engine_sum > 0.15, "Fixture must expose engine elapsed clipping")
		_near(input_sum, wall_sum, "Uninterrupted input recovers wall elapsed without double counting", 0.003)
	_near(_action_seconds() - before, input_sum, "Only original common clock advances")
	_check(_lab._action_time_remainder >= -TerrainLab.ACTION_TIME_EPSILON
		and _lab._action_time_remainder < TerrainLab.EXCHANGE_ACTION_STEP,
		"Common clock retains only its existing fractional tick")
	_record("real_callback_stall", first)

	for site_only: bool in [false, true]:
		first = _lab.samples.size()
		before = _action_seconds()
		var previous_remainder := _lab._action_time_remainder
		if site_only:
			_lab.terrain.site.paused = true
		else:
			paused = true
		await _frames(4)
		_near(_action_seconds(), before, "Site/tree pause advances no original action time")
		_near(_lab._action_time_remainder, previous_remainder, "Pause preserves partial original tick")
		_lab.terrain.site.paused = false
		paused = false
		await _frames(1)
		var resumed: Dictionary = _lab.samples.back()
		_near(float(resumed.input), float(resumed.engine_delta), "Resume boundary uses supplied delta, not paused duration")
		_record("site_pause" if site_only else "tree_pause", first)

	first = _lab.samples.size()
	_lab.set_process(false)
	before = _action_seconds()
	Engine.time_scale = 2.0
	for supplied: float in [0.007, 0.003, 0.25, 0.5]:
		_lab._process(supplied)
		_near(float(_lab.samples.back().input), supplied, "Manual disabled-process call preserves explicit delta at scale 2")
	_near(_action_seconds() - before, 0.76, "Manual calls preserve original accumulated clock")
	Engine.time_scale = 1.0
	_record("manual_process", first)
	_lab.set_process(true)
	await _frames(2)
	first = _lab.samples.size()
	var previous_frame := int(_lab.samples.back().frame)
	_lab.set_process(false)
	before = _action_seconds()
	for _skipped in range(4):
		await process_frame
	_near(_action_seconds(), before, "Disabled callbacks do not advance action time")
	_lab.set_process(true)
	await _frames(1)
	var restarted: Dictionary = _lab.samples.back()
	_check(int(restarted.frame) > previous_frame + 1, "Fixture must skip real engine frames")
	_near(float(restarted.input), float(restarted.engine_delta), "Skipped-frame restart must not repay disabled interval")
	_record("disabled_gap", first)

	for scale: float in [0.5, 2.0, 0.0, 1.0]:
		Engine.time_scale = scale
		_lab.simulation_speed = 4.0 # Game-minute multiplier must not change action ingress.
		await _frames(1)
		first = _lab.samples.size()
		before = _action_seconds()
		await _frames(3)
		for sample: Dictionary in _lab.samples.slice(first):
			var expected := float(sample.engine_delta) if _virtual_delta else float(sample.wall) * scale
			_near(float(sample.input), expected, "Engine scale applied once; game-minute speed excluded", 0.003)
			_near(float(sample.accepted), float(sample.input), "Scaled input retains original action ownership")
		if is_zero_approx(scale):
			_near(_action_seconds(), before, "Zero engine scale must not advance the common clock")
		_record("engine_scale_%s" % scale, first)

	for clock_hz: int in [30, 120]:
		await _budget_recovery(clock_hz)
	_lab.exchange_enabled = true
	_lab.fixed_action_steps_enabled = false

	first = _lab.samples.size()
	var retained := _lab._action_time_remainder
	_lab._reset_action_elapsed_input()
	_near(_lab._action_time_remainder, retained, "Reanchoring elapsed does not erase original action remainder")
	await _frames(1)
	var reset_sample: Dictionary = _lab.samples.back()
	_near(float(reset_sample.input), float(reset_sample.engine_delta), "Fresh Site anchor starts with supplied delta")
	_record("fresh_anchor", first)
	_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	paused = false
	Engine.max_fps = _previous_fps
	Engine.time_scale = _previous_scale
	if is_instance_valid(_lab):
		_lab.set_process(false)
	var report := {"passed": _failures.is_empty(), "checks": _checks, "failures": _failures,
		"wall_seconds": float(Time.get_ticks_usec() - _started) / 1000000.0,
		"virtual_delta": _virtual_delta, "cases": _cases,
		"scope": "Real engine callback elapsed ingress, original 30/120 Hz retained loops, budget yielding and actual debt recovery; not gameplay or performance acceptance"}
	var file := FileAccess.open(_folder.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	var log_file := FileAccess.open(_folder.path_join("elapsed_input.log"), FileAccess.WRITE)
	if log_file != null:
		log_file.store_string("SITE ACTION ELAPSED INPUT %s\nchecks=%d\n%s\n" % ["PASS" if _failures.is_empty() else "FAIL", _checks, "\n".join(_failures)])
	print("SITE ACTION ELAPSED INPUT %s checks=%d report=%s" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _folder])
	quit(0 if _failures.is_empty() else 1)
