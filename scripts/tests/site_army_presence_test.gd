extends "res://scripts/tests/site_army_scale_rules_test.gd"
const FROZEN := "res://scripts/tests/fixtures/terrain_army_presence_phase10.gd.txt"

func _presence_state(team: TerrainArmy) -> Array:
	return [team.command_reference, team.command_reference_valid, team.combat_units]

func _run() -> void:
	var kernel := TerrainArmy._get_idle_kernel()
	assert(kernel != null and kernel.has_method("command_presence"))
	# Exercise worker boundaries, shared read-only rows and atomic rejection.
	var shared := {"hp": 100.0, "ko": 0.0, "pose": "idle", "person_id": (1 << 40), "captive": false, "departed": false}
	shared.make_read_only()
	for count in [1023, 1024, 2500, 10000]:
		var rows: Array = []
		var line: Array[Vector2i] = []
		var expected_distances := PackedFloat64Array()
		var anchor := floori(float(count - 1) / 2.0)
		for index in count:
			rows.append(shared)
			line.append(Vector2i(index - 5000, 0))
			expected_distances.append(float(absi(index - anchor)))
		var before_bytes := var_to_bytes([rows, line])
		var expected := [PackedVector2Array([Vector2(anchor - 5000 + 0.5, 0.5)]), expected_distances]
		var retained: Array = kernel.call("command_presence", rows, line, {})
		for repeat in 8:
			assert(var_to_bytes(kernel.call("command_presence", rows, line, {})) == var_to_bytes(expected), "Parallel repeated aliased projection")
		for index: int in [0, floori(float(count) / 4.0), floori(float(count) / 2.0), count - 1]:
			rows[index] = shared.duplicate()
			rows[index].ko = NAN
			assert(kernel.call("command_presence", rows, line, {}).is_empty(), "Any rejected range must reject the whole projection")
			rows[index] = shared
			assert(kernel.call("command_presence", rows, line, {index: Vector2(INF, 0.0)}).is_empty())
		assert(var_to_bytes(retained) == var_to_bytes(expected) and var_to_bytes([rows, line]) == before_bytes)
	print("ARMY_PRESENCE_RANGES_PASS 1023/1024/2500/10000 shared read-only rows, ties, repeated calls, each-range rejection, retained outputs")
	var tie_rows: Array = [
		{"hp": 100.0, "ko": 0.0, "pose": "idle", "person_id": (1 << 40), "captive": false, "departed": false},
		{"hp": 100.0, "ko": 1.0, "pose": "get_up", "person_id": (1 << 40) - 1, "captive": false, "departed": false}]
	var tie_cells: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0)]
	var tied: Array = kernel.call("command_presence", tie_rows, tie_cells, {})
	assert(tied[0] == PackedVector2Array([Vector2(1.5, 0.5)]), "KO/get_up still anchors, 64-bit tie chooses lower ID")
	assert(tied[1] == PackedFloat64Array([2.0, -1.0]))
	tie_rows[0].make_read_only()
	assert(var_to_bytes(tied) == var_to_bytes(kernel.call("command_presence", tie_rows, tie_cells, {})), "Read-only inputs are never mutated")
	var typed: Dictionary[String, Variant] = {}
	typed.assign(tie_rows[1])
	assert(kernel.call("command_presence", [typed], [Vector2i.ZERO], {}).size() == 2)
	var bad: Dictionary = tie_rows[1].duplicate()
	bad.ko = INF
	assert(kernel.call("command_presence", [bad], [Vector2i.ZERO], {}).is_empty())
	assert(kernel.call("command_presence", tie_rows, [Vector2i(10001, 0), Vector2i.ZERO], {}).is_empty())
	var matcher := RegEx.new()
	assert(matcher.compile("(?ms)^func _refresh_command_presence\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
	var original := GDScript.new()
	original.source_code = "extends TerrainArmy\n" + matcher.search(FileAccess.get_file_as_string(FROZEN)).get_string()
	assert(original.reload() == OK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5814911
	var before := _fixture(false, 100, true, original)
	var after := _fixture(false, 100, true)
	var a: TerrainArmy = before.combat_armies[0]
	var b: TerrainArmy = after.combat_armies[0]
	for trial in range(100):
		for i in range(100):
			var row: Dictionary = a.combat_units[i].duplicate(true)
			row.person_id = (1 << 40) + rng.randi_range(-100, 100)
			row.hp = 0.0 if i % 13 == trial % 13 else 100.0
			row.ko = 1.0 if i % 7 == trial % 7 else 0.0
			row.pose = "get_up" if i % 11 == trial % 11 else "idle"
			row.captive = i % 19 == trial % 19
			row.departed = i % 23 == trial % 23
			row.present = rng.randf() < 0.5
			row.member = i % 17 != trial % 17
			if i % 5 == 0: row.erase("member")
			a.combat_units[i] = row
			a.cells[i] = Vector2i(rng.randi_range(-100, 100), rng.randi_range(-100, 100))
			a.moving_to[i] = a.cells[i] + Vector2i(1, 0) if i % 3 == 0 else TerrainArmy.INVALID_CELL
			a.move_progress[i] = rng.randf_range(-0.01, 1.01)
			a.move_curve[i] = i % 2
			b.combat_units[i] = row.duplicate(true)
			b.cells[i] = a.cells[i]
			b.moving_to[i] = a.moving_to[i]
			b.move_progress[i] = a.move_progress[i]
			b.move_curve[i] = a.move_curve[i]
		# Aliases must see earlier present writes, including hysteresis changes.
		a.combat_units[99] = a.combat_units[0]
		b.combat_units[99] = b.combat_units[0]
		a.command_radius = rng.randf_range(-2.0, 120.0)
		b.command_radius = a.command_radius
		a._refresh_command_presence()
		b.native_presence_rows = 0
		b._refresh_command_presence()
		assert(b.native_presence_rows == 100)
		assert(var_to_bytes(_presence_state(a)) == var_to_bytes(_presence_state(b)), "Presence trial " + str(trial))
		# Exact boundary and both sides of the original sqrt result.
		for offset in [-0.000000001, 0.0, 0.000000001]:
			a.command_radius = a.command_reference.distance_to(a.combat_ground(1) / 64.0) + offset
			b.command_radius = a.command_radius
			a._refresh_command_presence(); b._refresh_command_presence()
			assert(var_to_bytes(_presence_state(a)) == var_to_bytes(_presence_state(b)))
	# Empty reference keeps the previous reference vector, but clears presence.
	for team: TerrainArmy in [a, b]:
		for row: Dictionary in team.combat_units: row.member = false
		team._refresh_command_presence()
	assert(not b.command_reference_valid and var_to_bytes(_presence_state(a)) == var_to_bytes(_presence_state(b)))
	var input_bytes := var_to_bytes([b.combat_units, b.cells])
	var projection: Array = kernel.call("command_presence", b.combat_units, b.cells, {})
	assert(projection.size() == 2 and projection[0].is_empty())
	assert(input_bytes == var_to_bytes([b.combat_units, b.cells]))
	var retained := var_to_bytes(projection)
	assert(kernel.call("command_presence", [], [], {}).size() == 2)
	assert(retained == var_to_bytes(projection))
	assert(kernel.call("command_presence", b.combat_units, [], {}).is_empty())
	assert(kernel.call("command_presence", b.combat_units, b.cells, {0: Vector2(NAN, 0.0)}).is_empty())
	# Coercion and a live player use the untouched old function.
	for team: TerrainArmy in [a, b]: team.combat_units[1].member = 1
	b.native_presence_rows = 0
	a._refresh_command_presence(); b._refresh_command_presence()
	assert(b.native_presence_rows == 0 and var_to_bytes(_presence_state(a)) == var_to_bytes(_presence_state(b)))
	for team: TerrainArmy in [a, b]:
		team.combat_units[1].member = true
		team.player_member = TerrainTestCharacter.new()
		team.player_member.position = Vector2(80.25, -10.125)
		team._refresh_command_presence()
	assert(b.native_presence_rows == 0 and a.player_present == b.player_present)
	assert(var_to_bytes(_presence_state(a)) == var_to_bytes(_presence_state(b)))
	a.player_member.free(); b.player_member.free()
	_dispose(before); _dispose(after)
	var custom := GDScript.new()
	var custom_original := GDScript.new()
	var hook := "\nfunc combat_ground(index: int) -> Vector2:\n\treturn super.combat_ground(index) + Vector2(index * 0.125, 0.25)\n"
	custom.source_code = "extends TerrainArmy\n" + hook
	custom_original.source_code = original.source_code + hook
	assert(custom.reload() == OK and custom_original.reload() == OK)
	before = _fixture(false, 100, true, custom_original)
	after = _fixture(false, 100, true, custom)
	for side in range(2):
		before.combat_armies[side]._refresh_command_presence()
		after.combat_armies[side]._refresh_command_presence()
		assert(after.combat_armies[side].native_presence_rows == 0)
		assert(var_to_bytes(_presence_state(before.combat_armies[side])) == var_to_bytes(_presence_state(after.combat_armies[side])))
	_dispose(before); _dispose(after)
	var army_script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	var current_presence := matcher.search(army_script.source_code).get_string()
	var body_marker := "\tvar positions: Array[Vector2] = []"
	assert(current_presence.substr(current_presence.find(body_marker)).strip_edges() == original.source_code.substr(original.source_code.find(body_marker)).strip_edges(), "Canonical GD fallback must still be the exact frozen presence body")
	assert(army_script.source_code.count("selected.size() > MAX_ROSTER_SIZE") == 1)
	army_script.source_code = army_script.source_code.replace("selected.size() > MAX_ROSTER_SIZE", "selected.size() > 2500")
	assert(army_script.reload(true) == OK)
	for count in [100, 2500]:
		for accelerated in [false, true]:
			# Both owners must keep the approved canonical tactical staggering.
			# A subclass disables it; use the byte-identical GD fallback above.
			before = _fixture(false, count, true)
			after = _fixture(false, count, true)
			for team: TerrainArmy in before.combat_armies:
				team.native_presence_enabled = false
			for team: TerrainArmy in after.combat_armies:
				team.native_presence_enabled = accelerated
				team.native_presence_rows = 0
			for step in range(120 if count == 100 else 36):
				before._advance_combat(1.0 / 30.0); after._advance_combat(1.0 / 30.0)
				if var_to_bytes(_state(before)) != var_to_bytes(_state(after)):
					for side in 2:
						for index in count:
							var left: Dictionary = before.combat_armies[side].combat_units[index]
							var right: Dictionary = after.combat_armies[side].combat_units[index]
							if var_to_bytes(left) != var_to_bytes(right):
								for key: Variant in left:
									if left[key] != right.get(key): print("PRESENCE_DIFF ", side, "/", index, " ", key, " before=", left[key], " after=", right.get(key))
								break
					push_error("Presence owner mismatch people=%d native=%s step=%d" % [count * 2, accelerated, step])
					_dispose(before); _dispose(after); quit(1); return
				for side in range(2):
					for field: String in ["command_reference", "command_reference_valid", "command_radius", "current_commander", "acting_commander", "formal_commander", "officer_order", "officer_service", "command_abilities", "combat_slots", "_reserved_cells", "_cell_owners", "_vacancy_assignments", "_unit_rescues", "combat_order"]:
						assert(var_to_bytes(before.combat_armies[side].get(field)) == var_to_bytes(after.combat_armies[side].get(field)), "Changed " + field)
					assert(before.combat_armies[side].command_rng.state == after.combat_armies[side].command_rng.state)
			var rows := after.combat_armies[0].native_presence_rows + after.combat_armies[1].native_presence_rows
			assert((rows > 0) == accelerated)
			print("ARMY_PRESENCE_OWNER_PASS people=", count * 2, " native=", accelerated, " rows=", rows)
			_dispose(before); _dispose(after)
	print("ARMY_PRESENCE_PASS 100 seeded layouts/movement/KO/get_up/captive/departed/member/64-bit ties/alias/hysteresis/empty/COW/coercion/player; exact frozen phase10 owner state/claims/RNG")
	quit(0)
