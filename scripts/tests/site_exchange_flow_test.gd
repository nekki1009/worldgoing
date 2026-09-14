extends SceneTree
## Actual Lab pairing/owner integration without rendering or fabricated body shapes.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(12, 12))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.resize(144)
	data.feature_at.resize(144)
	data.site = {"paused": false, "features": {}, "combat_left": 0.0}
	var lab := TerrainLab.new()
	lab.terrain = data
	var a := TerrainTestCharacter.new()
	var b := TerrainTestCharacter.new()
	var c := TerrainTestCharacter.new()
	var people: Array[TerrainTestCharacter] = [a, b, c]
	lab.character = a
	lab.combat_actors = people
	for index in range(3):
		var actor := people[index]
		actor.data = data
		actor.exchange_enabled = true
		actor.person_id = index + 1
		actor.faction_id = 0 if index == 0 else 1
		actor.combatants = func() -> Array[TerrainTestCharacter]: return people
	assert(a.place(Vector2i(5, 5), true) and b.place(Vector2i(6, 5), true) and c.place(Vector2i(5, 6), true))
	a.combat_ability = 100
	b.combat_ability = 0
	c.combat_ability = 0
	lab._resolve_exchanges()
	assert(lab.exchange_count == 0, "Peaceful actor neighbours need an actual attack command")
	a.attack_target_id = b.person_id
	b.attack_target_id = a.person_id
	c.attack_target_id = a.person_id
	lab._resolve_exchanges()
	assert(lab.exchange_count == 1 and b.hp + c.hp == 198.0 and a.hp == 100.0, "One pair per person; not one incoming hit per neighbour")
	lab._resolve_exchanges()
	assert(lab.exchange_count == 1, "Repeated queries cannot bypass owner cooldown")
	for tick in range(30):
		for actor: TerrainTestCharacter in people:
			actor.advance_combat(1.0 / 30.0, true)
	assert(a.exchange_cooldown == 0.0)
	# The first victim may have legally retreated; the other adjacent aggressor
	# still participates without a persistent pair registry or stale positions.
	lab._resolve_exchanges()
	assert(lab.exchange_count == 2)
	for actor: TerrainTestCharacter in people:
		actor.reset_combat()
	assert(a.place(Vector2i(5, 5), true) and b.place(Vector2i(6, 5), true) and c.place(Vector2i(5, 6), true))
	var indexed := {b.terrain_cell: [{"faction": 1}], c.terrain_cell: [{"faction": 1}]}
	var person := {"owner": a, "unit": -1, "id": a.person_id, "cell": a.terrain_cell, "faction": 0}
	assert(lab._exchange_context(person, indexed).encirclement == 2)
	data.static_blocked[data.index(b.terrain_cell)] = 1
	assert(lab._exchange_context(person, indexed).encirclement == 1, "Walls prevent threat sectors and cross-wall exchanges")
	c.faction_id = 0
	a.attack_target_id = b.person_id
	b.attack_target_id = a.person_id
	var before := lab.exchange_count
	lab._resolve_exchanges()
	assert(lab.exchange_count == before and b.hp == 100.0)
	data.site.actors = {"player": {"projectiles": [{"remaining": 1.0}]}}
	assert(lab.exchange_snapshot_guard(data).code == "UNSUPPORTED_ACTIVE_PROJECTILES")
	data.site.actors.player.projectiles.clear()
	assert(lab.exchange_snapshot_guard(data).ok)
	# Retained common action time: render partitions cannot drop slow-frame debt.
	var clock_lab := ClockLab.new()
	clock_lab._advance_action_time(0.017)
	clock_lab._advance_action_time(0.184)
	assert(is_equal_approx(clock_lab.consumed, 0.2))
	assert(absf(clock_lab._action_time_remainder - 0.001) < 0.000000001)
	clock_lab.free()
	for actor: TerrainTestCharacter in people:
		actor.free()
	lab.free()
	print("SITE_EXCHANGE_FLOW_PASS pairing, cooldown, encirclement, terrain, compatibility, common clock")
	quit(0)

class ClockLab extends TerrainLab:
	var consumed := 0.0
	func _advance_combat(delta: float, _combat_clock: float = -1.0) -> void:
		consumed += delta
