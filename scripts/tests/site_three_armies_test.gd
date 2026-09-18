extends SceneTree
## Original main scene and original owners: three-way matching, not fabricated hits.
const OUT := "res://output/three_armies_20260918/logic"
var lab: TerrainLab
var people := {}
var pairs := {}
var used := {}
var last_round := -1
var events := 0
var hp_before := {}
var hits_before := {}
var deadline := 0
var progress_msec := 0
var report := {}

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 110000
	progress_msec = Time.get_ticks_msec()
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline or Time.get_ticks_msec() - progress_msec > 15000:
		push_error("THREE_ARMIES internal deadline")
		quit(1)
	return false

func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var main_scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = main_scene.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	lab.exchange_resolved.connect(_exchange)
	assert(lab.combat_armies.size() == 3)
	var setup := {"third_enabled": true, "third_faction": 2,
		"friendly_count": 100, "enemy_count": 100, "third_count": 100,
		"friendly_female_percent": 50, "enemy_female_percent": 50, "third_female_percent": 50}
	var deployed := lab.start_melee_trial(setup)
	if not deployed.ok:
		push_error("Three-team main-scene deployment failed: " + str(deployed))
		quit(1)
		return
	_index_people()
	assert(people.size() == 300)
	for team: TerrainArmy in lab.combat_armies:
		var women := 0
		for row: Dictionary in team.combat_units: women += int(row.appearance.body == 1)
		assert(team.combat_units.size() == 100 and women == 50)
		assert(team.formal_commander >= 0 and team.command_abilities.has(team.formal_commander))
	var merged_shape := lab.army.capture_combat_state()
	for index in [1, 2]:
		merged_shape.units[index].visual_role = "female_live" if merged_shape.units[index].appearance.body == 1 else "male_live"
	assert(TerrainArmy.valid_combat_state(merged_shape, lab.terrain), "A merged roster may retain three original live captain roles")
	merged_shape.units[3].visual_role = "female_live" if merged_shape.units[3].appearance.body == 1 else "male_live"
	assert(not TerrainArmy.valid_combat_state(merged_shape, lab.terrain), "Fourth live presenter remains rejected")
	_save_round_trip("deployed_300")
	for tick in range(600):
		_step()
		if tick % 60 == 0: await process_frame
	assert(pairs.has("0:1") and pairs.has("0:2") and pairs.has("1:2"), str(pairs))
	assert(events == lab.exchange_count and events > 0)
	_claims_do_not_overlap()
	lab.site_controller._capture_positions()
	assert(SiteStore.save(lab.terrain, OUT + "/active_must_reject.json").code == "BUSY")
	report["main_scene_300"] = {"action_seconds": 20.0, "pairs": pairs.duplicate(), "events": events,
		"factions": [lab.army.faction_id, lab.opposing_army.faction_id, lab.third_army.faction_id]}
	print("THREE_ARMIES_300: ", JSON.stringify(report.main_scene_300))
	# A new isolated main scene for explicit edge-case placement. The first
	# trial is still fighting/moving; do not bypass its legitimate clear guard.
	lab.queue_free()
	await process_frame
	lab = main_scene.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	lab.exchange_resolved.connect(_exchange)
	setup.merge({"friendly_count": 2, "enemy_count": 2, "third_count": 2,
		"friendly_female_percent": 0, "enemy_female_percent": 0, "third_female_percent": 0,
		"friendly_attack": false, "enemy_attack": false, "third_attack": false}, true)
	assert(lab.start_melee_trial(setup).ok)
	var origin := _clear_patch()
	assert(origin != TerrainArmy.INVALID_CELL)
	_place(lab.army, [origin, origin + Vector2i(0, 1)])
	_place(lab.opposing_army, [origin + Vector2i(1, 0), origin + Vector2i(2, 0)])
	_place(lab.third_army, [origin + Vector2i(1, 1), origin + Vector2i(2, 1)])
	_index_people()
	_selection_and_blockers()
	# Weak initial health/fatigue are fixture inputs. Every injury/death below
	# must still come through the production resolver, weapon rules and life owner.
	lab.army.training = 100.0
	lab.third_army.training = 100.0
	lab.opposing_army.team_fatigue.fatigue = 100.0
	for row: Dictionary in lab.opposing_army.combat_units: row.hp = 0.5
	for team: TerrainArmy in lab.combat_armies:
		assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.ATTACK).ok)
	pairs.clear()
	var dead_at := -1
	for tick in range(450):
		_step()
		if _all_dead(lab.opposing_army):
			dead_at = tick
			break
		if tick % 60 == 0: await process_frame
	assert(dead_at >= 0, "The weakened middle team must die through real exchanges")
	var ac_after_defeat := int(pairs.get("0:2", 0))
	for tick in range(90): _step()
	assert(int(pairs.get("0:2", 0)) > ac_after_defeat, "Remaining hostile teams must continue after the other enemy dies")
	for person: Dictionary in lab._exchange_people(false):
		assert(person.owner != lab.opposing_army, "Dead team cannot remain in the exchange snapshot")
	report["defeat_continuation"] = {"defeated_faction": 1, "defeat_action_seconds": float(dead_at + 1) / 30.0,
		"remaining_pair_before": ac_after_defeat, "remaining_pair_after": pairs.get("0:2", 0), "pairs": pairs.duplicate()}
	# The original retreat command separates survivors; never clear combat_left
	# or bypass the normal save/settlement guards to fabricate a passing save.
	assert(lab.army.issue_combat_order(lab.army.current_commander, TerrainArmy.CombatOrder.RETREAT, origin + Vector2i(-4, 0)).ok)
	assert(lab.third_army.issue_combat_order(lab.third_army.current_commander, TerrainArmy.CombatOrder.RETREAT, origin + Vector2i(6, 1)).ok)
	for tick in range(900):
		_step()
		if tick % 60 == 0: await process_frame
	assert(float(lab.terrain.site.combat_left) <= 0.0, "Original withdrawal must expire combat naturally")
	assert(lab.site_controller.supply_save_guard().ok)
	_save_round_trip("postcombat_three_teams")
	assert(_all_dead(lab.opposing_army))
	_claims_do_not_overlap()
	report["postcombat_saved"] = true
	var file := FileAccess.open(OUT + "/result.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	lab.queue_free()
	await process_frame
	print("SITE_THREE_ARMIES_PASS: original 100x3, all hostile pairs, unique per-round participants, actual HP/stun, target selection/KO/dead, third-team blockers, one-side defeat continuation, 300-person and postcombat save/load")
	quit(0)

func _index_people() -> void:
	people.clear()
	for team: TerrainArmy in lab.combat_armies:
		for index in range(team.combat_units.size()):
			var identity := team.combat_identity(index)
			assert(identity > 2 and not people.has(identity))
			people[identity] = {"team": team, "index": index}

func _step() -> void:
	progress_msec = Time.get_ticks_msec()
	hp_before.clear()
	hits_before.clear()
	for identity: int in people:
		var entry: Dictionary = people[identity]
		hp_before[identity] = float(entry.team.combat_units[entry.index].hp)
		hits_before[identity] = int(entry.team.combat_units[entry.index].get("hit_revision", 0))
	lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(not paused and not bool(lab.terrain.site.paused))
	_claims_do_not_overlap()

func _exchange(first: int, second: int, outcome: Dictionary) -> void:
	assert(people.has(first) and people.has(second), "Autonomous trial must not engage the distant player/NPC")
	if lab._exchange_round != last_round:
		last_round = lab._exchange_round
		used.clear()
	assert(not used.has(first) and not used.has(second), "A person cannot duel twice in one decision tick")
	used[first] = true
	used[second] = true
	var a: Dictionary = people[first]
	var b: Dictionary = people[second]
	var faction_a: int = a.team.faction_id
	var faction_b: int = b.team.faction_id
	assert(faction_a != faction_b, "Same faction cannot be selected for a melee exchange")
	var key := "%d:%d" % [mini(faction_a, faction_b), maxi(faction_a, faction_b)]
	pairs[key] = int(pairs.get(key, 0)) + 1
	events += 1
	for side in range(2):
		var identity := first if side == 0 else second
		var person: Dictionary = a if side == 0 else b
		var row: Dictionary = person.team.combat_units[person.index]
		var damage := float(outcome.hp_a if side == 0 else outcome.hp_b)
		var stun := float(outcome.stun_a if side == 0 else outcome.stun_b)
		assert(is_equal_approx(float(row.hp), maxf(0.0, float(hp_before[identity]) - damage)), "HP must be applied exactly once to the original row")
		assert(int(row.get("hit_revision", 0)) == int(hits_before[identity]) + int(damage > 0.0 or stun > 0.0), "Exactly one real hit revision per affected original row")
		assert(float(row.stun) >= stun, "Weapon stun reaches the original row")
		assert(is_equal_approx(float(row.exchange_cooldown), SiteCombatRules.EXCHANGE_ROUND_SECONDS))
		assert(int(row.target) == (second if side == 0 else first))

func _claims_do_not_overlap() -> void:
	var claimed := {}
	for team: TerrainArmy in lab.combat_armies:
		for cell: Vector2i in team._cell_owners:
			assert(not claimed.has(cell), "Different armies cannot share an occupied cell")
			claimed[cell] = team
		for cell: Vector2i in team._reserved_cells:
			assert(not claimed.has(cell), "A reservation cannot overlap any army's person/claim")
			claimed[cell] = team

func _save_round_trip(name: String) -> void:
	lab.site_controller._capture_positions()
	var state := lab.terrain.site.duplicate(true)
	var path := OUT + "/" + name + ".json"
	var saved := SiteStore.save(lab.terrain, path)
	assert(saved.ok, str(saved))
	var loaded := SiteStore.load_site(path)
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	lab.site_controller._auto_save_blocked = true
	lab.site_controller._capture_positions()
	assert(lab.terrain.site.armies.size() == 3)
	for index in range(3):
		var before: Dictionary = state.armies[index]
		var after: Dictionary = lab.terrain.site.armies[index]
		assert(before.team_id == after.team_id and before.faction_id == after.faction_id)
		assert(before.units.size() == after.units.size())
		for row in range(before.units.size()):
			for field: String in ["person_id", "hp", "stun", "ko", "cell", "destination", "appearance", "item_state"]:
				assert(before.units[row].get(field) == after.units[row].get(field), "Saved row changed: " + field)
	_index_people()

func _clear_patch() -> Vector2i:
	for y in range(8, lab.terrain.size.y - 8):
		for x in range(8, lab.terrain.size.x - 10):
			var origin := Vector2i(x, y)
			var valid := true
			for dy in range(-2, 4):
				for dx in range(-5, 8):
					var cell := origin + Vector2i(dx, dy)
					if not lab.terrain.is_walkable(cell) or cell in [lab.character.terrain_cell, lab.npc.terrain_cell]: valid = false
					for direction: Vector2i in TerrainData.DIRECTIONS:
						if not lab.terrain.can_step(cell, cell + direction): valid = false
			if valid: return origin
	return TerrainArmy.INVALID_CELL

func _place(team: TerrainArmy, positions: Array[Vector2i]) -> void:
	# Position only before this small test's first combat tick. Original rows,
	# gear, roles and claim arrays remain the production owners.
	team.cells.assign(positions)
	team.combat_slots.assign(positions)
	team._cell_owners.clear()
	team._reserved_cells.clear()
	team.moving_to.fill(TerrainArmy.INVALID_CELL)
	team.command_reference = Vector2(positions[0]) + Vector2.ONE * 0.5
	for index in range(positions.size()): team._cell_owners[positions[index]] = index

func _selection_and_blockers() -> void:
	var a := lab.army
	var b := lab.opposing_army
	var c := lab.third_army
	lab.site_controller.selected = c.cells[0]
	assert(lab.site_controller._selected_enemy_identity(a) == c.combat_identity(0))
	assert(lab.site_controller._actor_blocked(c.cells[0], lab.character))
	assert(lab.site_controller.reserves_cell(c.cells[0]))
	# A[1] is equally close to B[0] and C[0]; nearest wins before low ID.
	assert(lab._nearest_unit_enemy(a, 1).identity == c.combat_identity(0))
	var original := c.cells[0]
	c.cells[0] = a.cells[0] + Vector2i.UP
	assert(lab._nearest_unit_enemy(a, 0).identity == mini(b.combat_identity(0), c.combat_identity(0)))
	a.combat_units[0].target = c.combat_identity(0)
	assert(lab._nearest_unit_enemy(a, 0).identity == c.combat_identity(0), "Retained valid target outranks equal-distance alternative")
	c.combat_units[0].ko = 1.0
	assert(lab._nearest_unit_enemy(a, 0).identity == b.combat_identity(0))
	assert(lab._army_target(a, c.combat_identity(0)).is_empty())
	c.combat_units[0].ko = 0.0
	c.combat_units[0].hp = 0.0
	assert(lab._nearest_unit_enemy(a, 0).identity == b.combat_identity(0))
	c.combat_units[0].hp = 100.0
	c.faction_id = a.faction_id
	assert(lab._nearest_unit_enemy(a, 0).identity == b.combat_identity(0))
	assert(lab._army_target(a, c.combat_identity(0)).is_empty())
	lab.site_controller.selected = c.cells[0]
	assert(lab.site_controller._selected_enemy_identity(a) == -1, "UI target follows selected faction, not team number")
	c.faction_id = 2
	c.cells[0] = original
	a.combat_units[0].target = -1
	assert(not a._reserve_combat_step(1, c.cells[0]), "Third army occupied cell blocks first army")
	assert(not c._reserve_combat_step(0, b.cells[0]), "Second army occupied cell blocks third army")
	var claim := c.cells[1] + Vector2i.RIGHT
	assert(c._reserve_combat_step(1, claim))
	assert(bool(a.external_blocker.call(claim)) and bool(b.external_blocker.call(claim)), "Third army in-flight claim blocks both other armies")
	assert(lab.site_controller._actor_blocked(claim, lab.character) and lab.site_controller.reserves_cell(claim))
	c.prepare_combat(TerrainArmy.MOVE_DURATION)
	assert(c.cells[1] == claim)
	assert(c._reserve_combat_step(1, claim + Vector2i.LEFT))
	c.prepare_combat(TerrainArmy.MOVE_DURATION)
	report["selection_and_claims"] = "PASS"

func _all_dead(team: TerrainArmy) -> bool:
	for row: Dictionary in team.combat_units:
		if float(row.hp) > 0.0: return false
	return true
