extends SceneTree
## Production Lab launch / due-event / occupancy path, with original actor owners.

var events: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(1))
	var data := TerrainData.new()
	data.allocate(Vector2i(20, 20))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.resize(400)
	data.feature_at.resize(400)
	data.site = {"paused": false, "features": {}, "combat_left": 0.0}
	var lab := TerrainLab.new()
	lab.terrain = data
	var a := TerrainTestCharacter.new()
	var b := TerrainTestCharacter.new()
	var c := TerrainTestCharacter.new()
	var actors: Array[TerrainTestCharacter] = [a, b, c]
	lab.character = a
	lab.npc = null
	lab.combat_actors = actors
	for index in range(actors.size()):
		var actor := actors[index]
		actor.data = data
		actor.exchange_enabled = true
		actor.person_id = index + 1
		actor.faction_id = 1 if index == 1 else 0
		actor.combatants = func() -> Array[TerrainTestCharacter]: return actors
		actor.combat_target_query = lab._combat_target
	a._saved_appearance = {"parts": {"weapon": "bow_01"}}
	a.ammo_inventory = {"arrow": 20}
	assert(a.place(Vector2i(3, 5), true) and b.place(Vector2i(9, 5), true) and c.place(Vector2i(3, 8), true))
	lab.ranged_resolved.connect(func(shooter: int, target: int, result: Dictionary) -> void:
		events.append({"shooter": shooter, "target": target, "result": result.duplicate()}))
	lab._resolve_exchanges()
	assert(lab.ranged_shots == 0, "No automatic aggression without an order")
	assert(a.start_attack(b))
	lab._resolve_exchanges()
	assert(lab.ranged_shots == 1 and a.ammo_inventory.arrow == 19 and lab.has_ranged_projectiles())
	assert(b.hp == 100.0, "Launch does not cause immediate damage")
	lab._advance_ranged(0.2)
	assert(events.is_empty() and a.projectiles.size() == 1)
	var controller := preload("res://scripts/terrain_lab/site_controller.gd").new()
	controller.lab = lab
	assert(controller.supply_save_guard().code == "BUSY")
	var replacement := TerrainData.new()
	lab.bind_terrain(replacement)
	assert(lab.terrain == data, "Direct replacement cannot discard active events")
	lab._advance_ranged(0.4)
	assert(events.size() == 1 and events[0].target == b.person_id and not lab.has_ranged_projectiles())
	var first_damage := 100.0 - b.hp
	assert(first_damage in [0.0, 4.0, 8.0] and b.terrain_cell == Vector2i(9, 5))
	lab._advance_ranged(2.0)
	assert(events.size() == 1 and b.hp == 100.0 - first_damage, "A consumed event never resolves twice")
	# The locked target leaves before arrival. There is no homing or old body sweep.
	a.reset_combat()
	assert(a.ranged_fire(b.terrain_cell, 2))
	assert(b.place(Vector2i(9, 6), true))
	lab._advance_ranged(1.0)
	assert(events.back().result.kind == "empty" and events.back().target == 0)
	# A friend enters the old impact cell and is selected regardless of faction.
	a.reset_combat()
	assert(a.ranged_fire(Vector2i(9, 5), 3))
	assert(c.place(Vector2i(9, 5), true))
	lab._advance_ranged(1.0)
	assert(events.back().target == c.person_id)
	# A nearer friend intercepts; the arrow cannot pass through after a miss.
	a.reset_combat()
	assert(c.place(Vector2i(6, 5), true) and b.place(Vector2i(9, 5), true))
	assert(a.ranged_fire(b.terrain_cell, 4))
	lab._advance_ranged(1.0)
	assert(events.back().target == c.person_id)
	# A wall appearing after release blocks arrival, without refunding ammunition.
	a.reset_combat()
	assert(c.place(Vector2i(3, 8), true))
	assert(a.ranged_fire(b.terrain_cell, 5))
	data.static_blocked[data.index(Vector2i(6, 5))] = 1
	lab._advance_ranged(1.0)
	assert(events.back().result.kind == "blocked" and a.ammo_inventory.arrow == 15)
	data.static_blocked[data.index(Vector2i(6, 5))] = 0
	# Leaving the shooter incapacitated must not erase a previously launched arrow.
	a.reset_combat()
	assert(a.ranged_fire(b.terrain_cell, 6))
	a.apply_contact({"result": {"hp": 0.0, "stun": 100.0, "guard_break": false}, "shield": false})
	assert(a.knockout_left > 0.0 and a.projectiles.size() == 1)
	lab._advance_ranged(1.0)
	assert(events.back().shooter == a.person_id and events.back().target == b.person_id)
	assert(a.ammo_inventory.arrow == 14 and lab.ranged_resolutions == 6)
	# Independent stun and the original life owner: a second arrow can hit during a cooldown.
	b.reset_combat()
	b.exchange_cooldown = 1.5
	b.ranged_apply_hit(a.terrain_cell, {"result": {"kind": "hit", "hp": 2.0, "stun": 12.0, "stagger": 0.35, "guard_break": false}, "shield": false})
	assert(b.hp == 98.0 and b.stun == 12.0 and b.exchange_cooldown == 1.5)
	b.ranged_apply_hit(a.terrain_cell, {"result": {"kind": "graze", "hp": 1.0, "stun": 6.0, "stagger": 0.2, "guard_break": false}, "shield": false})
	assert(b.hp == 97.0 and b.stun == 18.0 and b.exchange_stagger >= 0.35)
	# An off-ray wall must not become an obstruction by re-aiming at a prefix cell.
	a.reset_combat()
	b.reset_combat()
	assert(b.place(Vector2i(7, 7), true))
	data.static_blocked[data.index(Vector2i(3, 6))] = 1
	assert(a.ranged_fire(b.terrain_cell, 7))
	lab._advance_ranged(1.0)
	assert(events.back().target == b.person_id and events.back().result.kind != "blocked")
	data.static_blocked[data.index(Vector2i(3, 6))] = 0
	_tiered_arrivals(lab, a, b)
	controller.free()
	for actor: TerrainTestCharacter in actors:
		actor.free()
	lab.free()
	print("SITE_RANGED_FLOW_PASS orders, flight timing, save/replace guard, dodge, friendly interception, walls, KO, independent hits; 16 real-item tiered arrivals preserve launch weapon and read arrival armor, including fractional HP")
	quit(0)

func _tiered_arrivals(lab: TerrainLab, source: TerrainTestCharacter, target: TerrainTestCharacter) -> void:
	var data := lab.terrain
	for actor: TerrainTestCharacter in [source, target]:
		var appearance := HumanCharacter3DEditor.default_appearance()
		appearance.parts.armor = "none"
		appearance.parts.shield = "none"
		actor._saved_appearance = appearance
		assert(SiteRuntime.seed_person_equipment(data, actor.item_state, actor.person_id, appearance).ok)
	var original_weapon := str(source.item_state.equipped.weapon)
	var armor := SiteRuntime.create_equipment(data, target.item_state, "ranged_tier_arrival_armor",
		{"slot": "armor", "asset": "armor_mingguang_01", "tint": [1.0, 1.0, 1.0, 1.0]}, target.person_id)
	assert(armor.ok)
	source.ammo_inventory = {"arrow": 20, "bolt": 20}
	var suffixes := ["_wood", "_stone", "", "_steel"]
	var shot_id := 8
	for family: String in ["bow_01", "crossbow_01"]:
		for material_index in range(suffixes.size()):
			var asset := family + str(suffixes[material_index])
			var weapon := SiteRuntime.create_equipment(data, source.item_state, "ranged_tier_" + asset,
				{"slot": "weapon", "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}, source.person_id)
			assert(weapon.ok)
			for graze: bool in [false, true]:
				source.reset_combat()
				target.reset_combat()
				source.fatigue = 0.0
				assert(source.place(Vector2i(3, 5), true) and target.place(Vector2i(9, 5), true))
				source.item_state.equipped.weapon = str(weapon.item_id)
				target.item_state.equipped.erase("armor")
				# Select a deterministic hit or graze through the production event roll.
				data.seed_value = (source.person_id * 73856093) ^ (shot_id * 83492791) ^ (target.person_id * 19349663) ^ (3000 if graze else 0)
				assert(source.ranged_fire(target.terrain_cell, shot_id))
				var flight: Dictionary = source.projectiles.back()
				assert(flight.shooter.weapon == asset and target.hp == 100.0)
				# Both changes use real fixture-owned items. Rendering/saved appearance
				# remains stale deliberately; it cannot dictate damage or armor level.
				source.item_state.equipped.weapon = original_weapon
				target.item_state.equipped.armor = str(armor.item_id)
				assert(source.exchange_stats().weapon == "longsword_01" and target.ranged_defense().armor == "armor_mingguang_01")
				lab._advance_ranged(1.0)
				var expected_hp := pow(2.0, material_index + 1 - 4) * (0.5 if graze else 1.0)
				assert(events.back().target == target.person_id and events.back().result.kind == ("graze" if graze else "hit"))
				assert(events.back().result.hp == expected_hp and target.hp == 100.0 - expected_hp)
				assert(target.stun == (4.0 if graze else 8.0) and not lab.has_ranged_projectiles())
				var settled_hp := target.hp
				lab._advance_ranged(1.0)
				assert(target.hp == settled_hp, "Fractional HP settles once, without rounding or duplicate arrival")
				shot_id += 1
