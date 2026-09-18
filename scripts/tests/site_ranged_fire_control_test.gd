extends SceneTree
## Fire discipline uses original owners and actual ground cells. Arrival keeps
## the original interception rule when a friend enters after launch.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(15.0).timeout.connect(func() -> void: quit(1))
	var data := TerrainData.new()
	data.allocate(Vector2i(20, 20))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.resize(400)
	data.feature_at.resize(400)
	data.site = {"paused": false, "features": {}, "combat_left": 0.0}
	var lab := TerrainLab.new()
	lab.terrain = data
	var source := TerrainTestCharacter.new()
	var enemy := TerrainTestCharacter.new()
	var friend := TerrainTestCharacter.new()
	var actors: Array[TerrainTestCharacter] = [source, enemy, friend]
	lab.character = source
	lab.combat_actors = actors
	for index in range(actors.size()):
		var actor := actors[index]
		actor.data = data
		actor.exchange_enabled = true
		actor.person_id = index + 1
		actor.faction_id = 1 if actor == enemy else 0
		actor.combatants = func() -> Array[TerrainTestCharacter]: return actors
		actor.combat_target_query = lab._combat_target
	source._saved_appearance = {"parts": {"weapon": "bow_01"}}
	source.ammo_inventory = {"arrow": 10}
	assert(source.place(Vector2i(3, 5), true))
	assert(enemy.place(Vector2i(9, 5), true))
	assert(friend.place(Vector2i(6, 5), true))
	assert(source.start_attack(enemy))
	lab._resolve_exchanges()
	assert(lab.ranged_shots == 0 and source.ammo_inventory.arrow == 10,
		"An already visible friend in the ray prevents firing and ammunition debit")
	friend.apply_contact({"result": {"hp": 0.0, "stun": 100.0, "guard_break": false}, "shield": false})
	assert(friend.knockout_left > 0.0)
	lab._resolve_exchanges()
	assert(lab.ranged_shots == 0 and source.ammo_inventory.arrow == 10,
		"An unconscious living friend must also prevent an automatic shot")
	friend.reset_combat()
	assert(friend.place(Vector2i(6, 6), true))
	lab._resolve_exchanges()
	assert(lab.ranged_shots == 1 and source.ammo_inventory.arrow == 9,
		"A clear lane resumes the same original attack without changing its target")
	var impacts: Array[int] = []
	lab.ranged_resolved.connect(func(_shooter: int, target: int, _result: Dictionary) -> void: impacts.append(target))
	assert(friend.place(Vector2i(6, 5), true))
	lab._advance_ranged(1.0)
	assert(impacts == [friend.person_id] and not lab.has_ranged_projectiles(),
		"A later crossing still intercepts; fire discipline does not create homing or friendly immunity")
	var cells := {Vector2i(4, 5): true}
	assert(not SiteCombatRules.ranged_friendly_clear(Vector2i(3, 5), Vector2i(4, 6), cells),
		"A friend touching a diagonal corner blocks the same supercover used by impact")
	assert(SiteCombatRules.ranged_friendly_clear(Vector2i(3, 5), Vector2i(9, 5), {Vector2i(3, 5): true}),
		"The shooter's source cell does not block its own ray")
	for actor: TerrainTestCharacter in actors: actor.free()
	lab.free()
	_selection_checks()
	print("SITE RANGED FIRE CONTROL PASS: standing/KO allies, no ammo debit, lane clears, post-launch interception, diagonal coverage, nearest legal/tie order, late adjacent threat, range exclusion and passive melee authorization")
	quit(0)

func _selection_checks() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(30, 30))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.resize(900)
	data.feature_at.resize(900)
	data.site = {"paused": false, "features": {}, "combat_left": 0.0}
	var lab := TerrainLab.new()
	lab.terrain = data
	var source := TerrainTestNPC.new()
	var far := TerrainTestCharacter.new()
	var near := TerrainTestCharacter.new()
	var other := TerrainTestCharacter.new()
	var friend := TerrainTestCharacter.new()
	var actors: Array[TerrainTestCharacter] = [source, far, near, other, friend]
	lab.npc = source
	lab.npc_retaliates = true # Original NPC authorization permits selecting any hostile.
	lab.combat_actors = actors
	for index in range(actors.size()):
		var actor := actors[index]
		actor.data = data
		actor.exchange_enabled = true
		actor.person_id = index + 1
		actor.faction_id = 0 if actor in [source, friend] else 1
		actor.combatants = func() -> Array[TerrainTestCharacter]: return actors
		actor.combat_target_query = lab._combat_target
	source._saved_appearance = {"parts": {"weapon": "bow_01"}}
	source.ammo_inventory = {"arrow": 20}
	assert(source.place(Vector2i(10, 10), true) and far.place(Vector2i(17, 10), true))
	assert(near.place(Vector2i(14, 10), true) and other.place(Vector2i(10, 16), true) and friend.place(Vector2i(4, 4), true))
	lab._resolve_ranged_fire(lab._exchange_people(false))
	assert(source.projectiles.size() == 1 and source.projectiles[0].target_cell == near.terrain_cell,
		"A later but nearer legal enemy replaces the first in-range candidate")
	source.reset_combat()
	assert(friend.place(Vector2i(12, 10), true))
	lab._resolve_ranged_fire(lab._exchange_people(false))
	assert(source.projectiles.size() == 1 and source.projectiles[0].target_cell == other.terrain_cell,
		"The nearest blocked enemy cannot exclude a farther legal firing lane")
	source.reset_combat()
	assert(friend.place(Vector2i(4, 4), true) and far.place(Vector2i(14, 10), true))
	assert(near.place(Vector2i(10, 14), true) and other.place(Vector2i(25, 10), true))
	lab._resolve_ranged_fire(lab._exchange_people(false))
	assert(source.projectiles.size() == 1 and source.projectiles[0].target_cell == far.terrain_cell,
		"Equal-distance choices retain the original people order")
	source.reset_combat()
	lab.combat_actors.assign([source, near, far, other, friend])
	lab._resolve_ranged_fire(lab._exchange_people(false))
	assert(source.projectiles.size() == 1 and source.projectiles[0].target_cell == near.terrain_cell,
		"Reversing equal-distance people order reverses the chosen target")
	source.reset_combat()
	lab.combat_actors.assign([source, far, near, other, friend])
	assert(near.place(Vector2i(25, 15), true) and other.place(Vector2i(10, 11), true))
	other.exchange_cooldown = 0.8
	var before := lab.ranged_shots
	var ammunition := int(source.ammo_inventory.arrow)
	lab._resolve_ranged_fire(lab._exchange_people(false))
	assert(source.projectiles.is_empty() and lab.ranged_shots == before and source.ammo_inventory.arrow == ammunition,
		"An adjacent enemy later in the list vetoes an already selected ranged shot even during its melee cooldown")
	lab.npc_retaliates = false
	other.reset_combat()
	lab._resolve_exchanges()
	assert(lab.exchange_count == 0 and lab.ranged_shots == before,
		"Passive neighbours do not receive invented attack authorization")
	assert(other.start_attack(source))
	lab._resolve_exchanges()
	assert(lab.exchange_count == 1 and source.projectiles.is_empty(),
		"The same passive shooter may still defend against an explicitly attacking adjacent enemy")
	for actor: TerrainTestCharacter in actors: actor.reset_combat()
	lab.npc_retaliates = true
	assert(far.place(Vector2i(19, 10), true) and near.place(Vector2i(20, 15), true) and other.place(Vector2i(10, 19), true))
	ammunition = int(source.ammo_inventory.arrow)
	lab._resolve_ranged_fire(lab._exchange_people(false))
	assert(source.projectiles.is_empty() and source.ammo_inventory.arrow == ammunition and lab.ranged_shots == before,
		"Enemies beyond the bow's eight-cell radius never become firing candidates")
	for actor: TerrainTestCharacter in actors:
		actor.combatants = Callable()
		actor.combat_target_query = Callable()
		actor.free()
	lab.combat_actors.clear()
	lab.npc = null
	lab.free()
