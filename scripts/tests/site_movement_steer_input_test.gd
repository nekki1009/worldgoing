extends "res://scripts/tests/site_movement_input_clock_test.gd"
## Formal scene with explicit legal flat ground, original F/WASD and body ticks.

func _run() -> void:
	var samples := {}
	for fps: int in [30, 60, 144]:
		await _fresh(false)
		_key(KEY_F, true)
		assert(lab.character.is_mounted())
		_key(KEY_SHIFT, true)
		_key(KEY_D, true)
		# Reach a real committed edge with enough momentum and remaining time to
		# inspect the next shared tick. Never fabricate body position or speed.
		var primed := false
		for tick in range(180):
			lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
			if lab.character.is_moving() and lab.character.ride_speed > TerrainTestCharacter.MOUNT_TURN_SPEED \
				and lab.character._movement_duration - lab.character._movement_elapsed > TerrainLab.EXCHANGE_ACTION_STEP:
				primed = true
				break
		assert(primed, "Original held D must accelerate the mounted body")
		var committed: Vector2i = lab.character.terrain_cell
		var prior_position: Vector2 = lab.character.position
		var prior_end: float = lab.character._ride_end_speed
		_key(KEY_W, true)
		_key(KEY_D, false) # W remains held: this must not mean release/stop.
		assert(lab._held_direction() == Vector2i.UP and lab.character._ride_end_speed == prior_end)
		assert(lab.character.position == prior_position)
		lab._process(TerrainLab.EXCHANGE_ACTION_STEP * 0.5)
		assert(lab.character.position == prior_position and lab.character._ride_end_speed == prior_end)
		lab._process(TerrainLab.EXCHANGE_ACTION_STEP * 0.5)
		assert(is_equal_approx(lab.character._ride_end_speed, TerrainTestCharacter.MOUNT_TURN_SPEED),
			"Held perpendicular steering ends the committed edge at 3, not key-up speed 0")
		assert(lab.character.terrain_cell == committed, "Steering cannot reserve another cell before finishing this edge")
		for tick in range(120):
			if lab.character.terrain_cell != committed: break
			lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
		assert(lab.character.terrain_cell == committed + Vector2i.UP)
		assert(is_equal_approx(lab.character._ride_start_speed, TerrainTestCharacter.MOUNT_TURN_SPEED),
			"Original next UP step must retain the completed quarter-turn speed")
		_advance(fps, 1)
		var turned := _snapshot()
		var stop_cell: Vector2i = lab.character.terrain_cell
		_key(KEY_W, false)
		_key(KEY_SHIFT, false)
		assert(lab._held_directions.is_empty() and lab.character._ride_end_speed == 0.0,
			"Last direction release still asks the original body to stop")
		_advance(fps, 2)
		assert(not lab.character.is_moving() and lab.character.ride_speed == 0.0 and lab.character.terrain_cell == stop_cell)
		var stopped := _snapshot()
		_advance(fps, 1)
		assert(_same(stopped, _snapshot()), "Released steering cannot coast into another reserved cell")
		samples[str(fps)] = [turned, stopped]
		print("MOUNTED_HELD_STEER ", fps, " ", samples[str(fps)])
	for fps: int in [60, 144]:
		for index in range(2):
			assert(_same(samples["30"][index], samples[str(fps)][index]), "Mounted steering and release must remain render-FPS independent")
	lab.queue_free()
	await process_frame
	print("SITE MOVEMENT STEER INPUT PASS: original D held -> W down/D up, shared-tick quarter-turn speed 3, next original UP edge, last-key release stop; 30/60/144 FPS parity")
	quit(0)
