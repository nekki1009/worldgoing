extends SceneTree
## Original keyboard handler + original shared clock. Formal scene uses explicit
## flat legal ground; this is input scheduling, not a generated-map route claim.
const OUT := "res://output/movement_clock_20260918/input"
var lab: TerrainLab
var deadline := 0
var report := {}

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 60000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Movement keyboard clock test deadline")
		quit(90)
	return false

func _fresh(row: bool, clock_hz: int = 30) -> void:
	if is_instance_valid(lab):
		lab.queue_free()
		await process_frame
	lab = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	lab.terrain.height_levels.fill(0)
	lab.terrain.flags.fill(TerrainData.Flag.WALKABLE)
	lab.terrain.static_blocked.fill(0)
	lab.terrain.ramp_edges.fill(0)
	assert(lab.character.place(Vector2i(20, 20), true))
	assert(lab.npc.place(Vector2i(85, 85), true))
	if row:
		assert(lab.character.place(Vector2i(80, 80), true))
		lab.army.roster_size = 2
		var cells: Array[Vector2i] = [Vector2i(20, 25), Vector2i(20, 20)]
		assert(lab.army.deploy_at(lab.terrain, lab.character, lab.npc, cells) and lab.army.enable_combat(false, 0))
		lab.terrain.site.controlled_person_id = lab.army.combat_identity(1)
		lab.army.sync_shared_fatigue(true)
	assert(lab.controlled_target().cell == Vector2i(20, 20))
	# The legacy-clock layer exercises its original retained 120Hz scheduler,
	# without claiming the historical geometric-combat renderer is tested here.
	lab.exchange_enabled = clock_hz == 30
	lab.fixed_action_steps_enabled = clock_hz == 120

func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	lab._unhandled_input(event)

func _advance(fps: int, seconds: int) -> void:
	for tick in range(fps * seconds): lab._process(1.0 / fps)

func _snapshot() -> Dictionary:
	var person := lab.controlled_target()
	var row := int(person.unit)
	return {"cell": person.cell, "position": person.owner.combat_ground(row) if row >= 0 else person.owner.position,
		"moving": person.owner.moving_to[row] != TerrainArmy.INVALID_CELL if row >= 0 else person.owner.is_moving(),
		"phase": float(person.owner.move_progress[row]) if row >= 0 else float(person.owner._movement_elapsed),
		"remainder": lab._action_time_remainder}

func _same(a: Dictionary, b: Dictionary) -> bool:
	return a.cell == b.cell and a.moving == b.moving and (a.position as Vector2).distance_to(b.position) < 0.0001 \
		and absf(float(a.phase) - float(b.phase)) < 0.00001 and absf(float(a.remainder) - float(b.remainder)) < 0.000000001

func _trial(row: bool, running: bool, fps: int, clock_hz: int) -> Array[Dictionary]:
	await _fresh(row, clock_hz)
	var checkpoints: Array[Dictionary] = []
	if running: _key(KEY_SHIFT, true)
	_key(KEY_D, true)
	_advance(fps, 1)
	checkpoints.append(_snapshot())
	_key(KEY_D, true, true) # OS echo is not another movement impulse.
	_advance(fps, 1)
	checkpoints.append(_snapshot())
	_key(KEY_W, true) # Last held direction wins at the next original tick.
	_advance(fps, 1)
	checkpoints.append(_snapshot())
	_key(KEY_W, false)
	_advance(fps, 1)
	checkpoints.append(_snapshot())
	_key(KEY_D, false)
	_key(KEY_SHIFT, false)
	_advance(fps, 1)
	checkpoints.append(_snapshot())
	assert(not checkpoints.back().moving, "Key release finishes only its committed step")
	_advance(fps, 1)
	assert(_same(checkpoints.back(), _snapshot()), "No held direction must not reserve another cell")
	return checkpoints

func _boundaries(row: bool, clock_hz: int) -> void:
	await _fresh(row, clock_hz)
	var step := 1.0 / clock_hz
	var before := _snapshot()
	_key(KEY_D, true)
	assert(_same(before, _snapshot()), "Key event queues intent; it cannot independently advance or reserve a body")
	lab._process(step * 0.5)
	assert(not _snapshot().moving, "First half tick cannot move early")
	lab._process(step * 0.5)
	assert(_snapshot().moving, "First complete common tick must start the original step")
	_key(KEY_D, false)
	_advance(60, 1)
	assert(not _snapshot().moving and _snapshot().cell == Vector2i(21, 20), "Release finishes exactly the original committed cell")
	before = _snapshot()
	var blocked := Vector2i(22, 20)
	lab.terrain.static_blocked[lab.terrain.index(blocked)] = 1
	_key(KEY_D, true)
	_advance(144, 2)
	assert(_same(before, _snapshot()), "Held blocked movement must stay at its original cell")
	lab.terrain.static_blocked[lab.terrain.index(blocked)] = 0
	lab._process(step * 0.5)
	assert(not _snapshot().moving)
	lab._process(step * 0.5)
	assert(_snapshot().moving, "Obstacle release resumes next common tick, without a failed full-step cooldown")
	# True UI pause clears intent, freezes the committed original movement, and
	# refuses fresh keys. Resume completes only that prior step, no latent press.
	lab.site_controller.toggle_pause()
	before = _snapshot()
	_key(KEY_W, true)
	_key(KEY_SHIFT, true)
	lab._process(1.0)
	assert(_same(before, _snapshot()) and lab._held_directions.is_empty() and not lab._run_held)
	lab.site_controller.toggle_pause()
	_advance(60, 1)
	assert(not _snapshot().moving and _snapshot().cell == blocked)
	before = _snapshot()
	lab.terrain.site.paused = true # The Site's own pause boundary is also authoritative.
	_key(KEY_D, true)
	lab._try_move(Vector2i.RIGHT)
	lab._process(1.0)
	assert(_same(before, _snapshot()) and lab._held_directions.is_empty())
	lab.terrain.site.paused = false
	_advance(60, 1)
	assert(_same(before, _snapshot()), "No paused keyboard press may become a later movement")
	report["boundaries_%d_%s" % [clock_hz, "row" if row else "actor"]] = "PASS: first tick, release, held obstruction/recovery, tree/Site pause"

func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var parity := true
	for clock_hz: int in [30, 120]:
		for row: bool in [false, true]:
			for running: bool in [false, true]:
				var key := str(clock_hz) + "_" + ("row" if row else "actor") + ("_run" if running else "_walk")
				var samples := {}
				for fps: int in [30, 60, 144]:
					var checkpoints := await _trial(row, running, fps, clock_hz)
					samples[str(fps)] = checkpoints
					print("KEYBOARD_CLOCK ", key, " ", fps, " ", checkpoints)
					await process_frame
				for fps: int in [60, 144]:
					for index in range(samples["30"].size()):
						parity = _same(samples["30"][index], samples[str(fps)][index]) and parity
				report[key] = samples
			await _boundaries(row, clock_hz)
	var file := FileAccess.open(OUT + "/frame_samples.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	assert(parity, "Original held keyboard movement differs at 30/60/144 rendered FPS; see frame_samples.json")
	lab.queue_free()
	await process_frame
	print("SITE MOVEMENT INPUT CLOCK PASS: original keyboard actor/controlled-row walk/run, direction/echo/release, 30/120Hz shared-clock layers at 30/60/144 FPS; first-tick/pause/held obstruction-recovery boundaries")
	quit(0)
