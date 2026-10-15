extends "res://scripts/tests/site_army_scale_rules_test.gd"
# The phase9 historical fixture stays unchanged; compare current canonical GD with the original native-front branch.
const FROZEN := "res://scripts/tests/fixtures/terrain_army_encirclement_canonical.gd.txt"

func _run() -> void:
	var passed: bool = _check()
	TerrainArmy.release_contact_source()
	quit(0 if passed else 1)

func _prepare_front(team: TerrainArmy) -> bool:
	# R1b successors must hold real posts before the fixture's 1-HP captain falls.
	var held: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD)
	assert(bool(held.ok), "Fixture HOLD before appointment: " + str(held))
	if not bool(held.ok): return false
	var cadre: Array[int] = [1, 2, 3]
	for member: int in cadre:
		var promoted: Dictionary = team.set_military_role(team.combat_identity(member), "officer")
		assert(bool(promoted.ok), "Fixture officer promotion: " + str(promoted))
		if not bool(promoted.ok): return false
	var appointed: Dictionary = team.record_officer_service(cadre, true)
	assert(bool(appointed.ok), "Fixture officer appointment: " + str(appointed))
	if not bool(appointed.ok): return false
	var attacking: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.ATTACK)
	assert(bool(attacking.ok), "Fixture ATTACK after appointment: " + str(attacking))
	if not bool(attacking.ok): return false

	return true

func _initial_front_review(before: TerrainLab, after: TerrainLab) -> bool:
	for lab: TerrainLab in [before, after]:
		assert(lab.exchange_enabled and lab.physical_ranged_enabled, "Keep current Lab combat modes explicit")
		var people: Array[Dictionary] = lab._exchange_people(false)
		for team: TerrainArmy in lab.combat_armies:
			var enemies: Dictionary = {}
			for person: Dictionary in people:
				if int(person.faction) != team.faction_id: enemies[Vector2i(person.cell)] = true
			var own_bodies: int = 0
			var contacts: int = 0
			for person: Dictionary in people:
				if person.owner != team: continue
				own_bodies += 1
				for direction: Vector2i in TerrainData.DIRECTIONS:
					var next: Vector2i = Vector2i(person.cell) + direction
					if enemies.has(next) and lab.terrain.can_attack_across(person.cell, next):
						contacts += 1
						break
			print("FRONT_SETUP_DIAG ", {"side": team.team_id, "exchange": team.exchange_enabled,
				"query_valid": team.exchange_people_query.is_valid(), "paused": lab.terrain.site.get("paused", false),
				"commander": team.current_commander, "eligible": team.command_eligible(team.current_commander),
				"order": team.combat_order, "attacking": team.combat_attacking, "needs_order": team.needs_attack_order,
				"routed": team.is_sustain_routed(), "people": people.size(), "own_bodies": own_bodies,
				"enemy_cells": enemies.size(), "contacts": contacts, "reviews": team.encirclement_reviews})
			assert(team.command_eligible(team.current_commander) and team.combat_attacking
				and team.combat_order == TerrainArmy.CombatOrder.ATTACK and not team.needs_attack_order)
			var reviews: int = team.encirclement_reviews
			team._try_exchange_encirclement()
			assert(team.encirclement_reviews == reviews + 1, "The actual valid front must execute one real review")
	assert(var_to_bytes(_state(before)) == var_to_bytes(_state(after)))
	for side: int in range(2):
		for field: String in ["blocker_probes", "combat_slots", "_reserved_cells", "_cell_owners", "_vacancy_assignments", "_unit_rescues", "encirclement_reviews", "encirclement_steps", "combat_order"]:
			assert(var_to_bytes(before.combat_armies[side].get(field)) == var_to_bytes(after.combat_armies[side].get(field)), "Initial review changed " + field)
		assert(before.combat_armies[side].command_rng.state == after.combat_armies[side].command_rng.state)
	return true

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
	var original: GDScript = GDScript.new()
	var candidate: GDScript = GDScript.new()
	var probes: String = "\nvar blocker_probes: Array[Vector2i] = []\nfunc _is_external_cell(cell: Vector2i, ignore_operator: int = 0, from: Vector2i = INVALID_CELL, goal: Vector2i = INVALID_CELL, origin: Vector2i = INVALID_CELL) -> bool:\n\tblocker_probes.append(cell)\n\treturn super._is_external_cell(cell, ignore_operator, from, goal, origin)\n"
	original.source_code = "extends TerrainArmy\n" + FileAccess.get_file_as_string(FROZEN) + probes
	candidate.source_code = "extends TerrainArmy\n" + probes
	assert(original.reload() == OK and candidate.reload() == OK)
	for count in [100, 2500]:
		for accelerated in [false, true]:
			var before := _fixture(false, count, true, original)
			var after: TerrainLab = _fixture(false, count, true, candidate)
			for lab: TerrainLab in [before, after]:
				for team: TerrainArmy in lab.combat_armies:
					if not _prepare_front(team): return false
					team.native_front_enabled = accelerated if lab == after else false
			if not _initial_front_review(before, after): return false
			var initial_reviews: Array[int] = [after.combat_armies[0].encirclement_reviews, after.combat_armies[1].encirclement_reviews]
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
			for side: int in range(2):
				assert(after.combat_armies[side].encirclement_reviews > initial_reviews[side], "Original common clock must execute further front reviews")
			assert(not after.combat_armies[0].get("blocker_probes").is_empty(), "The original external blocker must be exercised")
			print("ARMY_FRONT_OWNER_PASS people=", count * 2, " native=", accelerated, " cells=", checked_cells, " exact state/claims/RNG/external callback order")
			_dispose(before)
			_dispose(after)
	print("ARMY_FRONT_PASS 200 seeded geometry layouts; int32 extremes/radius/empty/type/budget/COW; current canonical GD/native-front owner parity native/fallback")
	return true
