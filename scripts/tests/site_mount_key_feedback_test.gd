extends "res://scripts/tests/site_movement_input_clock_test.gd"
## Original F-key branch, actual mount transition and committed movement.

func _run() -> void:
	await _fresh(false)
	assert(not lab.character.is_mounted())
	_key(KEY_F, true)
	assert(lab.character.is_mounted() and lab.status.text.begins_with("Mounted horse"))
	_key(KEY_D, true)
	lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(lab.character.is_moving())
	_key(KEY_F, true)
	assert(lab.character.is_mounted() and lab.status.text == "移動或忙碌中，請停下再上下馬",
		"Rejected in-flight F must not falsely report dismounting")
	_key(KEY_D, false)
	_advance(60, 2)
	assert(not lab.character.is_moving())
	_key(KEY_F, true)
	assert(not lab.character.is_mounted() and lab.status.text == "Dismounted.")
	lab.character.action_time = 0.25 # Explicit busy-state fixture; no fabricated movement.
	_key(KEY_F, true)
	assert(not lab.character.is_mounted() and lab.status.text == "移動或忙碌中，請停下再上下馬")
	lab.character.action_time = 0.0
	await _fresh(true)
	var before := lab.army.capture_combat_state()
	_key(KEY_F, true)
	assert(lab.status.text == "目前接管人物不支援原騎乘快捷測試" and lab.army.capture_combat_state() == before)
	assert(not lab.character.is_mounted(), "A controlled Army row cannot mount the unrelated original player")
	lab.queue_free()
	await process_frame
	print("SITE MOUNT KEY FEEDBACK PASS: real mount/dismount, rejected committed movement/busy state, unsupported controlled row retains original body")
	quit(0)
