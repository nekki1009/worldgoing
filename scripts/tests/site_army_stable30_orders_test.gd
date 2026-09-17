extends "res://scripts/tests/site_army_scale_rules_test.gd"
const FROZEN := "res://output/site_army_stable30_20260915/baseline/terrain_army.gd.txt"

func _run() -> void:
	var army_script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	var matcher := RegEx.new()
	assert(matcher.compile("(?ms)^func _try_exchange_encirclement\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
	var old := matcher.search(FileAccess.get_file_as_string(FROZEN)).get_string()
	var source := army_script.source_code
	assert(source.count("selected.size() > MAX_ROSTER_SIZE") == 1)
	source = source.replace("selected.size() > MAX_ROSTER_SIZE", "selected.size() > 2500")
	source = source.replace("func _try_exchange_encirclement() -> bool:\n", "var stable30_reference := false\nfunc _try_exchange_encirclement() -> bool:\n\tif stable30_reference: return _stable30_reference_encirclement()\n")
	army_script.source_code = source + "\n" + old.replace("func _try_exchange_encirclement(", "func _stable30_reference_encirclement(")
	assert(army_script.reload(true) == OK)
	for count in [100, 2500]:
		for native_queries in [true, false] if count == 100 else [true]:
			var before := _fixture(false, count, true)
			var after := _fixture(false, count, true)
			for team: TerrainArmy in before.combat_armies: team.set("stable30_reference", true)
			for team: TerrainArmy in after.combat_armies: team.native_queries_enabled = native_queries
			for step in range(120 if count == 100 else 60):
				for lab: TerrainLab in [before, after]:
					if step == 12: lab.terrain.static_blocked[lab.terrain.index(Vector2i(50, 12))] = 1
					if step == 24: lab.terrain.static_blocked[lab.terrain.index(Vector2i(50, 12))] = 0
					lab._advance_combat(1.0 / 30.0)
				assert(var_to_bytes(_state(before)) == var_to_bytes(_state(after)), "Changed original state at step " + str(step))
				for side in range(2):
					for field: String in ["combat_slots", "_reserved_cells", "_cell_owners", "_vacancy_assignments", "_unit_rescues", "encirclement_reviews", "encirclement_steps", "combat_order"]:
						assert(var_to_bytes(before.combat_armies[side].get(field)) == var_to_bytes(after.combat_armies[side].get(field)), "Changed " + field)
					assert(before.combat_armies[side].command_rng.state == after.combat_armies[side].command_rng.state)
			assert(after.combat_armies[0].encirclement_reviews > 0)
			print("STABLE30_ORDERS_PASS people=", count * 2, " native_queries=", native_queries, " exact state/claims/RNG; terrain edit during battle")
			_dispose(before)
			_dispose(after)
	var custom_lab := GDScript.new()
	custom_lab.source_code = "extends TerrainLab\nvar custom_queries := 0\nfunc _exchange_people(readiness: bool = true) -> Array[Dictionary]:\n\tcustom_queries += 1\n\treturn super._exchange_people(readiness)\n"
	assert(custom_lab.reload() == OK)
	var before := _fixture(false, 100, true, null, custom_lab)
	var after := _fixture(false, 100, true, null, custom_lab)
	var probes := [[], []]
	for side in range(2):
		before.combat_armies[side].set("stable30_reference", true)
		before.combat_armies[side].external_blocker = _block_probe.bind(before.combat_armies[1 - side], probes[0])
		after.combat_armies[side].external_blocker = _block_probe.bind(after.combat_armies[1 - side], probes[1])
	for step in range(60):
		before._advance_combat(1.0 / 30.0)
		after._advance_combat(1.0 / 30.0)
		assert(var_to_bytes(_state(before)) == var_to_bytes(_state(after)))
		assert(probes[0] == probes[1], "Custom blocker order must remain unchanged")
	assert(int(after.get("custom_queries")) > 0 and before.get("custom_queries") == after.get("custom_queries"))
	_dispose(before)
	_dispose(after)
	print("STABLE30_CUSTOM_QUERY_PASS original query/blocker calls, order and state")
	quit(0)

func _block_probe(cell: Vector2i, team: TerrainArmy, probes: Array) -> bool:
	probes.append(cell)
	return team.blocks_cell(cell)
