extends "res://scripts/tests/site_fire_shared_step_test.gd"
## OUTPUT-ONLY / NOT_RUN. Inherits genuine full-tree fixture and shared step.

func _run() -> void:
	var signatures: Array[String] = []
	for speed: float in [0.5, 1.0, 2.0, 4.0]:
		for slow_frame: bool in [false, true]:
			var lab := _new_fire_lab()
			var data := lab.terrain
			var cell := Vector2i(40, 40)
			var key := _add_test_timber(data, cell)
			var unit := _test_burning_unit(data, key, lab.fire_action_cursor)
			Env.change(data, key, {"remaining": 0, "cleared": true})
			Env.rebuild_indexes(data)
			unit.residue_q = 256 * Runtime.FIRE_Q # Isolated finite walkable residue genesis.
			Runtime.fire_hazard_invalidate(data)
			if not _check_fire(lab.character.place(cell, true), "Original Actor stands on walkable residue"): _finish_fire(false, "fixture"); return
			lab.simulation_speed = speed
			data.site.combat_left = 0.0
			var game_begin := Runtime.now(data) * 60.0
			var action_begin := lab.fire_action_cursor
			var hp_begin := lab.character.hp
			if slow_frame:
				# Original retained outer clock subdivides into real shared slices.
				lab._advance_action_time(0.6)
				if not _check_fire(lab.site_controller.original_step_fault_guard().ok and absf(lab._action_time_remainder) < 0.0000001,
					"Original slow frame drains its real retained action clock"): _finish_fire(false, "slow"); return
			elif not _shared(lab, 18): _finish_fire(false, "shared"); return
			if not _check_fire(absf(lab.fire_action_cursor - action_begin - 0.6) < 0.0000001
				and absf(Runtime.now(data) * 60.0 - game_begin - 0.6 * speed) < 0.0000001,
				"Action exposure remains 0.6 while original game seconds retain selected multiplier"): _finish_fire(false, "clock"); return
			var before := var_to_bytes([lab.character.hp, lab.character.fire_body, data.site.fire, lab.fire_action_cursor])
			data.site.paused = true
			var paused := lab._advance_original_shared_step(FIRE_STEP)
			if not _check_fire(not paused.ok and var_to_bytes([lab.character.hp, lab.character.fire_body, data.site.fire, lab.fire_action_cursor]) == before,
				"Original pause rejects without dose/HP/time mutation"): _finish_fire(false, "pause"); return
			data.site.paused = false
			signatures.append(JSON.stringify([snappedf(hp_begin - lab.character.hp, 0.000001), snappedf(float(lab.character.fire_body.dose), 0.000001),
				float(lab.character.fire_body.burn_left), float(lab.character.fire_body.episode_left)]))
	for signature: String in signatures:
		if not _check_fire(signature == signatures[0], "0.5/1/2/4 multipliers and original slow frame have identical exposure"): _finish_fire(false, "parity"); return
	_finish_fire(not fire_failed, "P3-A TM-01 original shared clock; no GPU/Native/FPS/M1 acceptance")
