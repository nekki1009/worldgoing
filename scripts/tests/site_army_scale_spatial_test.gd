extends "res://scripts/tests/site_army_scale_rules_test.gd"
## CPU equivalence, not an FPS test or an alternative gameplay scene.

func _run() -> void:
	if not _check_rest_claims(): quit(1); return
	var script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	var guard := "selected.size() > MAX_ROSTER_SIZE"
	if script.source_code.count(guard) != 1:
		push_error("Expected unique in-memory scale deployment guard"); quit(1); return
	script.source_code = script.source_code.replace(guard, "selected.size() > 2500")
	if script.reload(true) != OK:
		push_error("Could not load scale fixture"); quit(1); return
	for count in [100, 2500]:
		var original := _fixture(true, count, true)
		var candidate := _fixture(false, count, true)
		for step in range(36):
			for lab: TerrainLab in [original, candidate]:
				for team: TerrainArmy in lab.combat_armies:
					team.prepare_combat(1.0 / 30.0)
					team.settle_combat_command()
			if step % 6 != 5: continue
			var same := var_to_bytes(_state(original)) == var_to_bytes(_state(candidate))
			for side in range(2):
				var a: TerrainArmy = original.combat_armies[side]
				var b: TerrainArmy = candidate.combat_armies[side]
				same = same and a.combat_slots == b.combat_slots and a._reserved_cells == b._reserved_cells and a._cell_owners == b._cell_owners and a.encirclement_steps == b.encirclement_steps and a.command_rng.state == b.command_rng.state
			if not same:
				push_error("Spatial lookup changed original state: %d people, step %d" % [count * 2, step])
				_dispose(original); _dispose(candidate); quit(1); return
		print("SCALE_SPATIAL_PASS people=", count * 2, " steps=36 full rows, slots, claims and RNG; flanking=", candidate.combat_armies[0].encirclement_steps + candidate.combat_armies[1].encirclement_steps)
		_dispose(original)
		_dispose(candidate)
	quit(0)

func _check_rest_claims() -> bool:
	var original := _fixture(true)
	var candidate := _fixture(false)
	var query := Vector2i(50, 58)
	for phase in range(6):
		for lab: TerrainLab in [original, candidate]:
			var team: TerrainArmy = lab.combat_armies[1]
			match phase:
				1: assert(team._reserve_combat_step(90, Vector2i(50, 50)))
				2: team.apply_unit_contact(90, {"shield": false, "result": {"hp": 0.0, "stun": 110.0, "guard_break": false}})
				3:
					team.prepare_combat(1.0)
					team._wake_unit(90)
				4: team.prepare_combat(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"get_up"]) + 1.0 / 30.0)
				5:
					query = Vector2i(10, 10)
					lab.combat_armies[0].projectiles.append({"mode": "cell", "source_cell": Vector2i(10, 9), "target_cell": Vector2i(10, 11)})
		var before := original._fatigue_threat(query, 0, original.combat_armies[0], 0, {})
		var after := candidate._fatigue_threat(query, 0, candidate.combat_armies[0], 0, {})
		if before != after or before != (phase in [1, 4, 5]):
			push_error("Rest claims changed: phase %d original=%s new=%s" % [phase, before, after])
			_dispose(original); _dispose(candidate); return false
	_dispose(original)
	_dispose(candidate)
	print("SCALE_REST_CLAIMS_PASS 8/9 cells, in-flight KO, get-up, wake and friendly arrow")
	return true
