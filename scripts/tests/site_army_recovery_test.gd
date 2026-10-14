extends "res://scripts/tests/site_army_scale_rules_test.gd"
const FROZEN := "res://scripts/tests/fixtures/terrain_army_prepare_phase11.gd.txt"

func _row() -> Dictionary:
	return {"age": 0.0, "think": 0.5, "pose": "idle", "hp": 100.0, "ko": 0.0, "stun": 80.0, "grace": 0.1}

func _reference(rows: Array, delta: float, recovery: float) -> void:
	for unit: Dictionary in rows:
		unit.age = float(unit.age) + delta
		var zero_state: bool = unit.stun == 0.0 and unit.grace == 0.0
		for field: String in ["exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "ranged_cooldown"]:
			zero_state = zero_state and unit.get(field, 0.0) == 0.0
		for field: String in ["exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "ranged_cooldown"]:
			var remaining := maxf(0.0, float(unit.get(field, 0.0)) - delta)
			unit[field] = 0.0 if remaining <= 0.000000001 else remaining
		if zero_state:
			unit.grace = 0.0
			unit.stun = 0.0
		else:
			var decay := maxf(0.0, delta - float(unit.grace))
			unit.grace = maxf(0.0, float(unit.grace) - delta)
			unit.stun = maxf(0.0, float(unit.stun) - decay * recovery)
		unit.think = maxf(0.0, float(unit.think) - delta)

func _reference_ko(rows: Array, delta: float) -> void:
	for unit: Dictionary in rows:
		unit.age = float(unit.age) + delta
		for field: String in ["exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "ranged_cooldown"]:
			var remaining := maxf(0.0, float(unit.get(field, 0.0)) - delta)
			unit[field] = 0.0 if remaining <= 0.000000001 else remaining
		unit.ko = maxf(0.0, float(unit.ko) - delta)

func _run() -> void:
	var kernel := TerrainArmy._get_idle_kernel()
	assert(kernel != null and kernel.has_method("advance_recovery_prefix"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5814912
	var negative_zero := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	for trial in range(100):
		var delta: float = [1.0 / 30.0, 0.001, 1.0, 1e-9][trial % 4]
		var rate: float = [10.0, 0.0, 1e9][trial % 3]
		var rows: Array[Dictionary] = []
		var moving: Array[Vector2i] = []
		for i in range(50):
			var row := _row()
			row.age = rng.randf_range(0.0, 100.0)
			row.think = rng.randf_range(-1.0, 3.0)
			row.stun = rng.randf_range(-10.0, 100.0)
			row.grace = rng.randf_range(-1.0, 3.0)
			if i % 7 == 0: row.grace = delta; row.stun = negative_zero
			if i % 11 == 0: row.grace = negative_zero; row.stun = negative_zero
			for field: String in ["exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "ranged_cooldown"]:
				if i % 5 != 0: row[field] = rng.randf_range(-0.1, 5.0)
			if i % 13 == 0: row.exchange_cooldown = delta + 1e-9
			if i % 3 == 0: row.exchange_visual = {}
			rows.append(row); moving.append(TerrainArmy.INVALID_CELL)
		# Preserve real row aliasing and sequential reads of previously written timers.
		rows[49] = rows[0]
		var expected: Array[Dictionary] = rows.duplicate(true)
		expected[49] = expected[0]
		_reference(expected, delta, rate)
		var shared := rows[0]
		assert(kernel.advance_recovery_prefix(rows, moving, {}, 0, 50, delta, rate) == 50)
		assert(is_same(rows[0], shared) and is_same(rows[49], shared))
		assert(var_to_bytes(rows) == var_to_bytes(expected), "Recovery floats/keys/aliases trial=" + str(trial))
	for trial in range(100):
		var delta: float = [1.0 / 30.0, 0.001, 1.0, 1e-9][trial % 4]
		var rows: Array[Dictionary] = []
		var moving: Array[Vector2i] = []
		for i in range(50):
			var row := _row()
			row.pose = "unconscious"
			row.ko = delta + rng.randf_range(0.001, 5.0)
			row.age = negative_zero if i % 9 == 0 else rng.randf_range(0.0, 100.0)
			row.think = rng.randf_range(-1.0, 3.0)
			row.stun = rng.randf_range(-10.0, 100.0)
			row.grace = rng.randf_range(-1.0, 3.0)
			for field: String in ["exchange_cooldown", "exchange_stagger", "exchange_skill_cooldown", "ranged_cooldown"]:
				if i % 5 != 0: row[field] = negative_zero if i % 7 == 0 else rng.randf_range(-0.1, 5.0)
			if i % 13 == 0: row.exchange_cooldown = delta + 1e-9
			rows.append(row); moving.append(TerrainArmy.INVALID_CELL)
		rows[0].ko = delta * 2.0 + 1.0 # Shared row must remain above wake threshold on its second visit.
		rows[49] = rows[0]
		var expected: Array[Dictionary] = rows.duplicate(true)
		expected[49] = expected[0]
		_reference_ko(expected, delta)
		var shared := rows[0]
		var processed := int(kernel.advance_recovery_prefix(rows, moving, {}, 0, 50, delta, 10.0))
		if processed != 50:
			push_error("Unconscious KO prefix stopped trial=%d index=%d row=%s" % [trial, processed, str(rows[processed])])
			quit(1); return
		assert(is_same(rows[0], shared) and is_same(rows[49], shared))
		assert(var_to_bytes(rows) == var_to_bytes(expected), "Unconscious KO floats/keys/aliases trial=" + str(trial))
	for condition in range(11):
		var rows: Array[Dictionary] = [_row(), _row(), _row()]
		var moving: Array[Vector2i] = [TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL]
		var rescues := {}
		for row: Dictionary in rows:
			row.pose = "unconscious"
			row.ko = 1.0
		match condition:
			0: rows[1].ko = 1.0 / 30.0
			1: rows[1].ko = 0.01
			2: rows[1].exchange_visual = {}
			3: rows[1].exchange_visual = {"age": 0.0}
			4: moving[1] = Vector2i.ZERO
			5: rescues[1] = {"patient": 2}
			6: rows[1].pose = "down"
			7: rows[1].hp = 0.0
			8: rows[1].pose = "dead"
			9: rows[1].make_read_only()
			10:
				var typed: Dictionary[String, Variant] = {}
				typed.assign(rows[1]); rows[1] = typed
		var untouched := var_to_bytes(rows.slice(1))
		assert(kernel.advance_recovery_prefix(rows, moving, rescues, 0, 3, 1.0 / 30.0, 10.0) == 1)
		assert(untouched == var_to_bytes(rows.slice(1)), "Rejected unconscious row/later row changed condition=" + str(condition))
	for condition in range(12):
		var rows: Array[Dictionary] = [_row(), _row(), _row()]
		var moving: Array[Vector2i] = [TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL]
		var rescues := {}
		match condition:
			0: rows[1].pose = "walk"
			1: rows[1].hp = 0.0
			2: rows[1].ko = 0.1
			3: moving[1] = Vector2i.ZERO
			4: rescues[1] = {"patient": 2}
			5: rows[1].exchange_visual = {"age": 0.0}
			6: rows[1].exchange_pose_duration = 0.1
			7: rows[1].make_read_only()
			8: rows[1].grace = NAN
			9: rows[1].exchange_cooldown = null
			10: rows[1].erase("stun")
			11:
				var typed: Dictionary[String, Variant] = {}
				typed.assign(rows[1]); rows[1] = typed
		var untouched := var_to_bytes(rows.slice(1))
		assert(kernel.advance_recovery_prefix(rows, moving, rescues, 0, 3, 1.0 / 30.0, 10.0) == 1)
		assert(untouched == var_to_bytes(rows.slice(1)), "Rejected row/later row changed")
	var bad_rows: Array[Dictionary] = [_row()]
	var bad_bytes := var_to_bytes(bad_rows)
	for rate: float in [-1.0, NAN, INF]:
		assert(kernel.advance_recovery_prefix(bad_rows, [TerrainArmy.INVALID_CELL], {}, 0, 1, 0.1, rate) == 0)
		assert(bad_bytes == var_to_bytes(bad_rows))
	var matcher := RegEx.new()
	assert(matcher.compile("(?ms)^func prepare_combat\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
	var original := GDScript.new()
	# Keep the archived algorithm byte-for-byte; only adapt its in-memory override signature.
	original.source_code = "extends TerrainArmy\n" + matcher.search(FileAccess.get_file_as_string(FROZEN)).get_string().replace("func prepare_combat(delta: float) -> void:", "func prepare_combat(delta: float, _game_seconds: float = -1.0) -> void:")
	assert(original.reload() == OK)
	var custom := GDScript.new()
	var custom_original := GDScript.new()
	var hook := "\nvar pose_calls := 0\nfunc _advance_exchange_pose(index: int) -> void:\n\tpose_calls += 1\n\tsuper._advance_exchange_pose(index)\n"
	custom.source_code = "extends TerrainArmy\n" + hook
	custom_original.source_code = original.source_code + hook
	assert(custom.reload() == OK and custom_original.reload() == OK)
	var before := _fixture(false, 100, true, custom_original)
	var after := _fixture(false, 100, true, custom)
	for side in range(2):
		for team: TerrainArmy in [before.combat_armies[side], after.combat_armies[side]]:
			for row: Dictionary in team.combat_units: row.stun = 80.0
			team.prepare_combat(1.0 / 30.0)
		assert(after.combat_armies[side].native_recovery_rows == 0)
		assert(before.combat_armies[side].pose_calls == after.combat_armies[side].pose_calls and after.combat_armies[side].pose_calls > 0)
	assert(var_to_bytes(_state(before)) == var_to_bytes(_state(after)))
	_dispose(before); _dispose(after)
	var army_script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	# The frozen body predates game-hour KO and rescue, so byte equality is no longer
	# a valid oracle. The current-owner native/GD parity below covers both paths.
	assert(army_script.source_code.count("selected.size() > MAX_ROSTER_SIZE") == 1)
	army_script.source_code = army_script.source_code.replace("selected.size() > MAX_ROSTER_SIZE", "selected.size() > 2500")
	assert(army_script.reload(true) == OK)
	for count in [100, 2500]:
		for accelerated in [false, true]:
			# A subclass bypasses the approved tactical staggering. Use the
			# exact frozen GD body verified above, within both canonical owners.
			before = _fixture(false, count, true)
			after = _fixture(false, count, true)
			before.terrain.site.combat_left = 5.0
			after.terrain.site.combat_left = 5.0
			for team: TerrainArmy in before.combat_armies:
				team.native_idle_enabled = false
			for team: TerrainArmy in after.combat_armies:
				team.native_recovery_enabled = accelerated
				team.native_recovery_rows = 0
			for step in range(120 if count == 100 else 36):
				before._advance_combat(1.0 / 30.0); after._advance_combat(1.0 / 30.0)
				if var_to_bytes(_state(before)) != var_to_bytes(_state(after)):
					push_error("Recovery owner mismatch people=%d native=%s step=%d" % [count * 2, accelerated, step])
					_dispose(before); _dispose(after); quit(1); return
				for side in range(2):
					for field: String in ["command_reference", "command_reference_valid", "current_commander", "acting_commander", "formal_commander", "combat_slots", "_reserved_cells", "_cell_owners", "_vacancy_assignments", "_unit_rescues", "combat_order", "_command_dirty", "_visual_dirty"]:
						assert(var_to_bytes(before.combat_armies[side].get(field)) == var_to_bytes(after.combat_armies[side].get(field)), "Changed " + field)
					assert(before.combat_armies[side].command_rng.state == after.combat_armies[side].command_rng.state)
			var rows := after.combat_armies[0].native_recovery_rows + after.combat_armies[1].native_recovery_rows
			assert((rows > 0) == accelerated)
			print("ARMY_RECOVERY_OWNER_PASS people=", count * 2, " native=", accelerated, " rows=", rows)
			_dispose(before); _dispose(after)
	print("ARMY_RECOVERY_PASS 5000 idle and 5000 unconscious numeric rows, signed-zero/grace/cooldown/KO boundaries/key types/aliasing; rejection/subclass; same-clock state/claims/RNG native and GD parity; archived phase11 body retained")
	# Headless skips the production release at tree exit (_retain_contact_sources_until_exit);
	# free the static contact rigs before the first draw so the dummy renderer never
	# updates their material instances. Runs after every check.
	TerrainArmy.release_contact_source()
	quit(0)
