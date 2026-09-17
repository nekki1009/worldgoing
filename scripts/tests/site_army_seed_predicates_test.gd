extends "res://scripts/tests/site_army_scale_rules_test.gd"
## Compare canonical fast predicates and custom-terrain fallback with phase21.
const FROZEN := "res://scripts/tests/fixtures/terrain_army_encirclement_phase21.gd.txt"

class ObservedTerrain extends TerrainData:
	var probes: Array = []
	func is_walkable(cell: Vector2i) -> bool:
		probes.append(["walkable", cell])
		return super.is_walkable(cell)
	func can_attack_across(from: Vector2i, to: Vector2i) -> bool:
		probes.append(["attack", from, to])
		return super.can_attack_across(from, to)

func _run() -> void:
	var source := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	assert(source.source_code.count("selected.size() > MAX_ROSTER_SIZE") == 1)
	source.source_code = source.source_code.replace("selected.size() > MAX_ROSTER_SIZE", "selected.size() > 2500")
	assert(source.reload(true) == OK)
	var baseline := GDScript.new()
	baseline.source_code = "extends TerrainArmy\n" + FileAccess.get_file_as_string(FROZEN)
	assert(baseline.reload() == OK)
	for count in [100, 2500]:
		for native_front in [false, true]:
			_check_seed(baseline, count, native_front, false)
	_check_seed(baseline, 100, true, true)
	print("ARMY_SEED_PREDICATES_PASS canonical 200/5000 native and fallback; custom terrain calls; original state/claims/RNG/external order")
	quit(0)

func _check_seed(baseline: GDScript, count: int, native_front: bool, custom_terrain: bool) -> void:
	var before := _fixture(false, count, true, baseline)
	var after := _fixture(false, count, true)
	var external_probes: Array = [[], []]
	var labs: Array[TerrainLab] = [before, after]
	for lab_index in range(labs.size()):
		var lab := labs[lab_index]
		if custom_terrain:
			var observed := ObservedTerrain.new()
			for property: Dictionary in lab.terrain.get_property_list():
				if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
					observed.set(property.name, lab.terrain.get(property.name))
			lab.terrain = observed
		for side in range(2):
			var team := lab.combat_armies[side]
			team.data = lab.terrain
			team.native_front_enabled = native_front
			team.external_blocker = func(cell: Vector2i, owner: TerrainLab, log: Array, opponent: int) -> bool:
				log.append([opponent, cell])
				return owner.combat_armies[opponent].blocks_cell(cell)
			team.external_blocker = team.external_blocker.bind(lab, external_probes[lab_index], 1 - side)
	assert(after.combat_armies[0].get_script() == TerrainArmy)
	assert((after.terrain.get_script() == TerrainData) == not custom_terrain)
	for step in range(90 if count == 100 else 36):
		for lab: TerrainLab in labs:
			if step == 12: lab.terrain.static_blocked[lab.terrain.index(Vector2i(50, 12))] = 1
			if step == 18: lab.terrain.flags[lab.terrain.index(Vector2i(50, 13))] = 0
			if step == 24:
				lab.terrain.static_blocked[lab.terrain.index(Vector2i(50, 12))] = 0
				lab.terrain.flags[lab.terrain.index(Vector2i(50, 13))] = TerrainData.Flag.WALKABLE
				lab.terrain.height_levels[lab.terrain.index(Vector2i(50, 14))] = 1
			lab._advance_combat(1.0 / 30.0)
		assert(var_to_bytes(_state(before)) == var_to_bytes(_state(after)), "Seed predicates changed people/state")
		assert(var_to_bytes(external_probes[0]) == var_to_bytes(external_probes[1]), "External callback order changed")
		for side in range(2):
			for field: String in ["command_reference", "command_reference_valid", "current_commander", "acting_commander", "formal_commander", "combat_slots", "_reserved_cells", "_cell_owners", "_vacancy_assignments", "_unit_rescues", "encirclement_reviews", "encirclement_steps", "combat_order"]:
				assert(var_to_bytes(before.combat_armies[side].get(field)) == var_to_bytes(after.combat_armies[side].get(field)), "Changed " + field)
			assert(before.combat_armies[side].command_rng.state == after.combat_armies[side].command_rng.state)
		if custom_terrain:
			assert(var_to_bytes(before.terrain.probes) == var_to_bytes(after.terrain.probes), "Custom terrain call order changed")
	assert(not external_probes[1].is_empty() and after.combat_armies[0].encirclement_reviews > 0)
	assert((after.combat_armies[0].native_front_cells > 0) == native_front)
	print("ARMY_SEED_OWNER_PASS people=", count * 2, " native_front=", native_front, " custom_terrain=", custom_terrain, " callbacks=", external_probes[1].size())
	_dispose(before)
	_dispose(after)
