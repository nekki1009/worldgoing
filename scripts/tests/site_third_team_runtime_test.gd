extends SceneTree
## Original Lab deployment boundaries, including late-failure rollback and append.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUT := "res://output/site_third_team_20260918/runtime"
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 70000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Third team runtime deadline")
		quit(1)
	return false

func _stable(lab: TerrainLab) -> Dictionary:
	return {"site": lab.terrain.site.duplicate(true), "first": lab.army.capture_combat_state() if lab.army.combat_enabled else {},
		"second": lab.opposing_army.capture_combat_state() if lab.opposing_army.combat_enabled else {},
		"third": lab.third_army.capture_combat_state() if lab.third_army.combat_enabled else {}}

func _aliases(lab: TerrainLab) -> Dictionary:
	var borrowed := {"site": lab.terrain.site, "fields": lab.terrain.site.duplicate(),
		"records": lab.terrain.site.item_records.duplicate(), "definitions": lab.terrain.site.item_definitions.duplicate(),
		"manual_cargo": lab.terrain.site.manual.cargo, "worker_cargo": lab.terrain.site.worker.cargo,
		"player_holder": lab.character.item_state, "npc_holder": lab.npc.item_state,
		"appearances": lab.site_controller._equipment_appearances, "rows": []}
	for team: TerrainArmy in lab.combat_armies:
		for row: Dictionary in team.combat_units:
			borrowed.rows.append({"row": row, "holder": row.item_state, "cargo": row.cargo})
	return borrowed

func _assert_aliases(lab: TerrainLab, borrowed: Dictionary) -> void:
	assert(is_same(lab.terrain.site, borrowed.site), "Rejected deployment must not replace the live Site")
	for field: String in borrowed.fields:
		if borrowed.fields[field] is Dictionary or borrowed.fields[field] is Array:
			assert(is_same(lab.terrain.site[field], borrowed.fields[field]), "Existing Site reference changed: " + field)
	for identity: String in borrowed.records:
		assert(is_same(lab.terrain.site.item_records[identity], borrowed.records[identity]))
	for identity: String in borrowed.definitions:
		assert(is_same(lab.terrain.site.item_definitions[identity], borrowed.definitions[identity]))
	assert(is_same(lab.character.ammo_inventory, borrowed.manual_cargo) and is_same(lab.character.ammo_inventory, lab.terrain.site.manual.cargo))
	assert(is_same(lab.npc.ammo_inventory, borrowed.worker_cargo) and is_same(lab.npc.ammo_inventory, lab.terrain.site.worker.cargo))
	assert(is_same(lab.character.item_state, borrowed.player_holder) and is_same(lab.npc.item_state, borrowed.npc_holder))
	assert(is_same(lab.site_controller._equipment_appearances, borrowed.appearances))
	for person: Dictionary in borrowed.rows:
		assert(is_same(person.row.item_state, person.holder) and is_same(person.row.cargo, person.cargo))

func _shot_goal(lab: TerrainLab, actor: TerrainTestCharacter) -> Vector2i:
	var occupied := lab._ranged_occupants()
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var cell := actor.terrain_cell + Vector2i(dx, dy)
			if not SiteCombatRules.ranged_in_range(actor.terrain_cell, cell, 8.0) or not SiteCombatRules.ranged_line_clear(lab.terrain, actor.terrain_cell, cell): continue
			var empty := true
			for crossed: Vector2i in SiteCombatRules.ranged_cells(actor.terrain_cell, cell):
				if crossed != actor.terrain_cell and occupied.has(crossed): empty = false
			if empty: return cell
	return TerrainArmy.INVALID_CELL

func _ammo_after_rejection(lab: TerrainLab) -> void:
	var depot_bolts := int(lab.terrain.site.inventory.get("bolt", 0))
	for actor: TerrainTestCharacter in [lab.character, lab.npc]:
		var player := actor == lab.character
		var weapon := "bow_01" if player else "crossbow_01"
		var ammo := "arrow" if player else "bolt"
		var created := SiteRuntime.create_equipment(lab.terrain, actor.item_state, "weapon:" + weapon,
			{"slot": "weapon", "asset": weapon, "tint": [1.0, 1.0, 1.0, 1.0]}, actor.person_id)
		assert(created.ok)
		actor.item_state.equipped.weapon = created.item_id
		lab.site_controller.equipment_changed(actor.person_id)
		actor.ammo_inventory[ammo] = 5
		var goal := _shot_goal(lab, actor)
		assert(goal != TerrainArmy.INVALID_CELL and actor.ranged_fire(goal, 100 + actor.person_id))
		var activity: Dictionary = lab.terrain.site.manual if player else lab.terrain.site.worker
		assert(int(actor.ammo_inventory[ammo]) == 4 and int(activity.cargo[ammo]) == 4, "A real released shot must debit the original saved cargo")
	lab._advance_ranged(2.0)
	for tick in range(450): lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(not lab.has_ranged_projectiles() and float(lab.terrain.site.combat_left) == 0.0)
	lab.site_controller._capture_positions()
	assert(Store.save(lab.terrain, OUT + "/rollback_consumption.json").ok)
	var loaded := Store.load_site(OUT + "/rollback_consumption.json")
	assert(loaded.ok and int(loaded.data.site.manual.cargo.arrow) == 4)
	# The original worker may deliver its remaining bolts while the combat
	# clock expires. Count the real destination as well, never freeze its job.
	assert(int(loaded.data.site.worker.cargo.get("bolt", 0)) + int(loaded.data.site.inventory.get("bolt", 0)) == depot_bolts + 4)

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	assert(lab.combat_armies.size() == 3 and not lab.third_army.has_army())
	var setup := {"friendly_count": 4, "enemy_count": 4, "third_count": 4, "third_enabled": true,
		"friendly_female_percent": 0, "enemy_female_percent": 0, "third_female_percent": 0,
		"friendly_attack": false, "enemy_attack": false, "third_attack": false}
	for invalid: Dictionary in [{"third_enabled": 1}, {"third_count": 0}, {"third_count": 101}, {"third_count": 2.5},
		{"third_faction": -1}, {"third_faction": 3}, {"third_faction": true}, {"third_female_percent": NAN},
		{"third_female_percent": 101}, {"third_training": 0.5}, {"third_coach": -1}, {"third_attack": 1},
		{"third_spawn": Vector2(1, 1)}, {"third_spawn": Vector2i(1, 1)}]:
		var trial := setup.duplicate()
		trial.merge(invalid, true)
		var before := _stable(lab)
		assert(not lab.start_melee_trial(trial).ok)
		assert(_stable(lab) == before, "Rejected third-team setup must leave original state unchanged")
	var before := _stable(lab)
	var borrowed := _aliases(lab)
	var allocator := lab.opposing_army.person_id_allocator
	lab.opposing_army.person_id_allocator = func(_count: int) -> Array[int]: return []
	assert(lab.start_melee_trial(setup).code == "DEPLOY_FAILED")
	assert(_stable(lab) == before, "A failure after the first team initialized must not leak IDs/items/loot")
	_assert_aliases(lab, borrowed)
	lab.opposing_army.person_id_allocator = allocator
	assert(lab.army.external_blocker.get_method() == &"blocks_cell")
	# An item-allocation failure is also atomic, despite the original initializer reporting through UI.
	var original_next_item: int = lab.terrain.site.next_item
	lab.terrain.site.next_item = 2147483646
	before = _stable(lab)
	borrowed = _aliases(lab)
	assert(lab.start_melee_trial(setup).code == "DEPLOY_FAILED")
	assert(_stable(lab) == before)
	_assert_aliases(lab, borrowed)
	lab.terrain.site.next_item = original_next_item
	setup.third_enabled = false
	assert(lab.start_melee_trial(setup).ok)
	assert(not lab.third_army.has_army() and lab.army.external_blocker.get_method() == &"blocks_cell")
	before = _stable(lab)
	borrowed = _aliases(lab)
	allocator = lab.third_army.person_id_allocator
	lab.third_army.person_id_allocator = func(_count: int) -> Array[int]: return []
	assert(lab.add_melee_trial_team(setup).code == "DEPLOY_FAILED")
	assert(_stable(lab) == before, "Failed append must preserve the entire original pair")
	_assert_aliases(lab, borrowed)
	lab.third_army.person_id_allocator = allocator
	# Existing armies must retain their borrowed gear/cargo even if the new
	# team's equipment fails before, or after, one complete person was seeded.
	original_next_item = int(lab.terrain.site.next_item)
	for exhausted in [2147483646, 2147483640]:
		lab.terrain.site.next_item = exhausted
		before = _stable(lab)
		borrowed = _aliases(lab)
		assert(lab.add_melee_trial_team(setup).code == "DEPLOY_FAILED")
		assert(_stable(lab) == before, "Failed item-seeding append must preserve the original two armies and all actual items")
		_assert_aliases(lab, borrowed)
		lab.terrain.site.next_item = original_next_item
	_ammo_after_rejection(lab)
	before = _stable(lab)
	var appended := lab.add_melee_trial_team(setup)
	assert(appended.ok and lab.third_army.faction_id == 2)
	assert(lab.army.capture_combat_state() == before.first and lab.opposing_army.capture_combat_state() == before.second,
		"Successful append must not reset original positions, combat orders, body state or inventories")
	assert(lab.third_army.combat_units.size() == 4 and lab._armies_block_cell(lab.third_army.cells[0]))
	assert(lab.army.external_blocker.call(lab.third_army.cells[0]) and lab.third_army.external_blocker.call(lab.army.cells[0]))
	before = _stable(lab)
	assert(lab.add_melee_trial_team(setup).code == "BUSY" and _stable(lab) == before)
	lab.site_controller._capture_positions()
	assert(Store.save(lab.terrain, OUT + "/three.json").ok)
	var loaded := Store.load_site(OUT + "/three.json")
	assert(loaded.ok and loaded.data.site.armies.size() == 3)
	lab.bind_terrain(loaded.data)
	assert(lab.third_army.combat_units.size() == 4 and lab.third_army.faction_id == 2)
	assert(lab.opposing_army.external_blocker.call(lab.third_army.cells[0]))
	lab.clear_army()
	assert(not lab.has_combat_armies() and lab.third_army.cells.is_empty())
	assert(lab.army.external_blocker.get_method() == &"blocks_cell")
	for faction in range(3):
		setup.third_enabled = true
		setup.third_faction = faction
		setup.third_training = 345
		setup.third_tactics = 12
		setup.third_leadership = 34
		setup.third_coach = 56
		assert(lab.start_melee_trial(setup).ok)
		assert(lab.third_army.faction_id == faction and lab.third_army.training == 345.0)
		assert(lab.third_army.command_abilities[0] == {"tactics": 12, "leadership": 34, "coach": 56})
		assert(lab._army_target(lab.third_army, lab.army.combat_identity(0)).is_empty() == (faction == 0))
		assert(lab._army_target(lab.third_army, lab.opposing_army.combat_identity(0)).is_empty() == (faction == 1))
		lab.clear_army()
	var layout := lab.find_melee_trial_layout(100, 100, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 100)
	assert(not layout.is_empty(), "Original generated terrain must fit three real 100-person connected formations")
	print("THIRD TEAM RUNTIME PASS: invalid setup, late ID/item rollback with original references, real post-rejection bow/crossbow ammo saved, append preservation, blockers, three factions, save/load, clear, original terrain 300-cell layout")
	lab.queue_free()
	await process_frame
	quit(0)
