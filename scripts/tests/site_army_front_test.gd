extends "res://scripts/tests/site_army_scale_rules_test.gd"
const FROZEN := "res://scripts/tests/fixtures/terrain_army_commands_phase9.gd.txt"

func _run() -> void:
	quit(0 if _check() else 1)

func _check() -> bool:
	var kernel := TerrainArmy._get_idle_kernel()
	assert(kernel != null and kernel.has_method("near_front"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5814910
	for trial in range(200):
		var enemies: Array[Vector2i] = []
		var contacts: Array[Vector2i] = []
		for i in range(rng.randi_range(0, 200)): enemies.append(Vector2i(rng.randi_range(-100, 100), rng.randi_range(-100, 100)))
		for i in range(rng.randi_range(0, 100)): contacts.append(Vector2i(rng.randi_range(-100, 100), rng.randi_range(-100, 100)))
		# Exact radius edges, duplicates, and subtraction spanning all int32.
		contacts.append(Vector2i(-2147483648, 2147483647))
		enemies.append(Vector2i(2147483647, -2147483648))
		enemies.append(contacts[-1])
		enemies.append(Vector2i(-2147483640, 2147483647))
		enemies.append(Vector2i(-2147483639, 2147483647))
		var before := var_to_bytes([enemies, contacts])
		var expected := PackedByteArray()
		for enemy: Vector2i in enemies:
			var near := false
			for contact: Vector2i in contacts:
				if absi(enemy.x - contact.x) + absi(enemy.y - contact.y) <= 8: near = true; break
			expected.append(int(near))
		var actual: PackedByteArray = kernel.call("near_front", enemies, contacts, 8)
		assert(actual == expected and before == var_to_bytes([enemies, contacts]))
		var retained := actual.duplicate()
		kernel.call("near_front", [Vector2i.ZERO], [], 0)
		assert(actual == retained, "A later query changed old output")
	assert(kernel.call("near_front", [Vector2.ZERO], [Vector2i.ZERO], 8).is_empty())
	assert(kernel.call("near_front", [Vector2i.ZERO], [Vector2i.ZERO], -1).is_empty())
	assert(kernel.call("near_front", [Vector2i.ZERO], [Vector2i.ZERO], 9).is_empty())
	var many: Array[Vector2i] = []
	many.resize(2001)
	var front: Array[Vector2i] = []
	front.resize(1000)
	assert(kernel.call("near_front", many, front, 8).is_empty(), "Bound the native comparison product")
	var army_script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	assert(army_script.source_code.count("selected.size() > MAX_ROSTER_SIZE") == 1)
	army_script.source_code = army_script.source_code.replace("selected.size() > MAX_ROSTER_SIZE", "selected.size() > 2500")
	assert(army_script.reload(true) == OK)
	var matcher := RegEx.new()
	assert(matcher.compile("(?ms)^func _try_exchange_encirclement\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
	var original := GDScript.new()
	var candidate := GDScript.new()
	var probes := "\nvar blocker_probes: Array[Vector2i] = []\nfunc _is_external_cell(cell: Vector2i) -> bool:\n\tblocker_probes.append(cell)\n\treturn super._is_external_cell(cell)\n"
	original.source_code = "extends TerrainArmy\n" + matcher.search(FileAccess.get_file_as_string(FROZEN)).get_string() + probes
	candidate.source_code = "extends TerrainArmy\n" + probes
	assert(original.reload() == OK and candidate.reload() == OK)
	for count in [100, 2500]:
		for accelerated in [false, true]:
			var before := _fixture(false, count, true, original)
			var after := _fixture(false, count, true, candidate)
			for team: TerrainArmy in after.combat_armies: team.native_front_enabled = accelerated
			for step in range(120 if count == 100 else 36):
				for lab: TerrainLab in [before, after]:
					if step == 12: lab.terrain.static_blocked[lab.terrain.index(Vector2i(50, 12))] = 1
					if step == 24: lab.terrain.static_blocked[lab.terrain.index(Vector2i(50, 12))] = 0
					lab._advance_combat(1.0 / 30.0)
				assert(var_to_bytes(_state(before)) == var_to_bytes(_state(after)))
				for side in range(2):
					for field: String in ["blocker_probes", "combat_slots", "_reserved_cells", "_cell_owners", "_vacancy_assignments", "_unit_rescues", "encirclement_reviews", "encirclement_steps", "combat_order"]:
						assert(var_to_bytes(before.combat_armies[side].get(field)) == var_to_bytes(after.combat_armies[side].get(field)), "Changed " + field)
					assert(before.combat_armies[side].command_rng.state == after.combat_armies[side].command_rng.state)
			var checked_cells := after.combat_armies[0].native_front_cells + after.combat_armies[1].native_front_cells
			assert((checked_cells > 0) == accelerated)
			assert(after.combat_armies[0].encirclement_reviews > 0)
			print("ARMY_FRONT_OWNER_PASS people=", count * 2, " native=", accelerated, " cells=", checked_cells, " exact state/claims/RNG/external callback order")
			_dispose(before)
			_dispose(after)
	print("ARMY_FRONT_PASS 200 seeded geometry layouts; int32 extremes/radius/empty/type/budget/COW; phase9 owner parity native/fallback")
	return true
