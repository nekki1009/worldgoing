extends "res://scripts/tests/site_work_team_clock_test.gd"
## Bounded original-owner regression, not GPU/FPS or a replacement death clock.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const ORIGINAL_SAVE := "res://.godot-temp/site_resources_contract/opened-retention-original.json"
const LEGACY_SAVE := "res://.godot-temp/site_resources_contract/opened-retention-legacy.json"
const MIGRATED_SAVE := "res://.godot-temp/site_resources_contract/opened-retention-migrated.json"

func _deploy(lab: TerrainLab, female_count: int = 0) -> TerrainArmy:
	var fixture := _work_fixture()
	lab.bind_terrain(fixture.data)
	lab.site_controller._auto_save_blocked = true
	lab.site_controller.release_worker()
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	var cells: Array[Vector2i] = []
	cells.assign(fixture.cells)
	assert(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false, female_count))
	team.set_process(false)
	team.settle_combat_command()
	lab.site_controller.initialize_team_items(team)
	lab.terrain.site.army_next_team = team.team_id + 1
	return team

func _private(lab: TerrainLab, identity: int, amount: float, feed: bool = true) -> Dictionary:
	var pool := Sustain.create(Runtime.now(lab.terrain) * 60.0)
	pool.open_rations = amount # Explicit initial fixture stock, never integer grain.
	if feed:
		assert(Sustain.add_members(pool, lab.site_controller.captivity_supply._all_members(), [identity]).ok)
	if not lab.terrain.site.has("person_supply"):
		lab.terrain.site.person_supply = {}
	lab.terrain.site.person_supply[str(identity)] = pool
	return pool

func _take_and_clear(data: TerrainData, reference: String) -> void:
	var bag: Dictionary = data.site.ground_loot[reference]
	assert(Runtime.transfer_items(data, bag, bag.cargo, data.site.depot_items, data.site.inventory,
		bag.cargo, bag.item_ids.duplicate(), int(bag.version), int(data.site.depot_items.version), int(data.site.capacity)).ok)
	assert(Runtime.clear_empty_ground_loot(data, reference).ok)

func _opened_total(state: Dictionary) -> float:
	var total := 0.0
	for pool: Dictionary in state.get("person_supply", {}).values():
		total += float(pool.open_rations)
	for bag: Dictionary in state.ground_loot.values():
		total += float(bag.get("open_rations", 0.0))
	return total

func _write_fixture(path: String, payload: Dictionary) -> void:
	# A checksummed historical format-3 fixture; production save deliberately
	# rejects this old settled-open shape, while load must migrate it losslessly.
	var serialized := JSON.stringify(payload, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"checksum": serialized.sha256_text(), "payload": serialized}))
	file.close()

func _legacy(lab: TerrainLab, female_count: int) -> void:
	var team := _deploy(lab, female_count)
	for row: Dictionary in team.combat_units:
		assert(int(row.appearance.body) == (1 if female_count == 3 else 0), "Exercise actual all-female and all-male original death rows")
	var controller: SiteController = lab.site_controller
	var data: TerrainData = lab.terrain
	var first_id := team.combat_identity(1)
	var second_id := team.combat_identity(2)
	var npc_id := lab.npc.person_id
	_private(lab, first_id, 0.0)
	_private(lab, second_id, 0.0)
	_private(lab, npc_id, 0.0)
	var lethal := {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false, "environmental": true}
	team.apply_unit_contact(1, lethal)
	team.apply_unit_contact(2, lethal)
	lab.npc.apply_contact(lethal)
	# The common 30 Hz clock retains fractional time. Reach the first complete
	# action step after the authored down pose, rather than assuming 0.01s is
	# enough to cross the pending settlement boundary.
	var down_seconds := float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"])
	lab._process((ceilf(down_seconds / TerrainLab.EXCHANGE_ACTION_STEP) + 1.0) * TerrainLab.EXCHANGE_ACTION_STEP)
	assert(controller._pending_deaths.is_empty())
	var first_reference := str(team.combat_units[1].remains_id)
	var second_reference := str(team.combat_units[2].remains_id)
	var npc_reference := str(lab.npc.remains_id)
	assert(not first_reference.is_empty() and not second_reference.is_empty() and not npc_reference.is_empty())
	_take_and_clear(data, second_reference)
	_take_and_clear(data, npc_reference)
	controller.equipment_changed(second_id)
	controller.equipment_changed(npc_id)
	controller._capture_positions()
	assert(Store.save(data, ORIGINAL_SAVE).ok)
	var old_file := FileAccess.get_file_as_string(ORIGINAL_SAVE)
	var decoded := Store._read(ORIGINAL_SAVE)
	assert(decoded.ok)
	var payload: Dictionary = decoded.payload
	payload.state.person_supply[str(first_id)].open_rations = 0.375
	payload.state.person_supply[str(second_id)].open_rations = 0.125
	payload.state.person_supply[str(npc_id)].open_rations = 0.625
	payload.state.ground_loot[first_reference].open_rations = 0.25
	_write_fixture(LEGACY_SAVE, payload)
	var legacy_file := FileAccess.get_file_as_string(LEGACY_SAVE)
	Store._normalize_state(payload.state) # Compare the same typed JSON boundary, not float IDs against integer IDs.
	var history: Dictionary = payload.state.person_supply.duplicate(true)
	var items: Dictionary = payload.state.item_records.duplicate(true)
	var original_bag: Dictionary = payload.state.ground_loot[first_reference].duplicate(true)
	var original_count: int = payload.state.ground_loot.size()
	var original_next := int(payload.state.next_loot)
	# Exercise the whole migration preflight on the original snapshot owner.
	# Two missing bags need two IDs, although each individual preview can see
	# the same one final available ID. Failure must not merge the earlier bag.
	data.site = payload.state.duplicate(true)
	Store._normalize_state(data.site)
	data.site.next_loot = 2147483646
	var before := JSON.stringify(data.site)
	assert(not Runtime.migrate_settled_opened_food(data).ok)
	assert(JSON.stringify(data.site) == before)
	data.site.next_loot = original_next
	var original_version := int(data.site.ground_loot[first_reference].version)
	data.site.ground_loot[first_reference].version = 2147483646
	before = JSON.stringify(data.site)
	assert(not Runtime.migrate_settled_opened_food(data).ok)
	assert(JSON.stringify(data.site) == before)
	data.site.ground_loot[first_reference].version = original_version
	data.site.ground_loot[first_reference].open_rations = 1000000.0
	before = JSON.stringify(data.site)
	assert(not Runtime.migrate_settled_opened_food(data).ok)
	assert(JSON.stringify(data.site) == before)
	data.site.ground_loot[first_reference].open_rations = 0.25
	assert(Store.save(data, ORIGINAL_SAVE).code == "CORRUPT_SAVE")
	assert(FileAccess.get_file_as_string(ORIGINAL_SAVE) == old_file)
	var loaded := Store.load_site(LEGACY_SAVE)
	assert(loaded.ok, str(loaded))
	var migrated: TerrainData = loaded.data
	assert(FileAccess.get_file_as_string(LEGACY_SAVE) == legacy_file, "Loading must not rewrite the original old file")
	assert(migrated.site.ground_loot.size() == original_count + 2 and int(migrated.site.next_loot) == original_next + 2)
	assert(migrated.site.item_records == items and migrated.site.ground_loot[first_reference].item_ids == original_bag.item_ids)
	assert(migrated.site.ground_loot[first_reference].equipped == original_bag.equipped)
	assert(migrated.site.ground_loot[first_reference].open_rations == 0.625)
	_near(_opened_total(migrated.site), 1.375, "legacy opened food conserved")
	for identity: int in [first_id, second_id, npc_id]:
		var pool: Dictionary = migrated.site.person_supply[str(identity)]
		assert(float(pool.open_rations) == 0.0 and pool.cohorts == history[str(identity)].cohorts, "Dead meal history is retained exactly")
	assert(migrated.site.armies[0].units[1].remains_id == first_reference)
	assert(str(migrated.site.armies[0].units[2].remains_id) != second_reference)
	assert(str(migrated.site.actors.npc.remains_id) != npc_reference)
	for person: Dictionary in [migrated.site.armies[0].units[2], migrated.site.actors.npc]:
		var bag: Dictionary = migrated.site.ground_loot[str(person.remains_id)]
		assert(bag.kind == "remains" and int(bag.original_owner) == int(person.person_id) and bag.item_ids.is_empty() and bag.cargo.is_empty())
		assert(int(bag.cell) == migrated.index(Vector2i(int(person.cell[0]), int(person.cell[1]))))
	var repeat := Store.load_site(LEGACY_SAVE)
	assert(repeat.ok and repeat.data.site == migrated.site, "Re-reading the untouched old file is deterministic, not cumulative")
	var migrated_before := JSON.stringify(migrated.site)
	assert(Runtime.migrate_settled_opened_food(migrated).migrated == 0)
	assert(JSON.stringify(migrated.site) == migrated_before)
	assert(Store.save(migrated, MIGRATED_SAVE).ok)
	var roundtrip := Store.load_site(MIGRATED_SAVE)
	assert(roundtrip.ok and roundtrip.data.site == migrated.site)
	# Binding uses the original Actor and original saved rows; no second corpse.
	var original_actor: TerrainTestCharacter = lab.npc
	lab.bind_terrain(roundtrip.data)
	controller._auto_save_blocked = true
	assert(lab.npc == original_actor and float(lab.npc.hp) == 0.0 and lab.npc.loot_settled)
	assert(controller._pending_deaths.is_empty() and lab.army.combat_identity(1) == first_id)
	assert(lab.terrain.site.ground_loot.size() == original_count + 2)

func _clear(lab: TerrainLab, female_count: int) -> void:
	var team := _deploy(lab, female_count)
	var controller: SiteController = lab.site_controller
	var data: TerrainData = lab.terrain
	var ids: Array[int] = []
	for index: int in range(team.combat_units.size()):
		ids.append(team.combat_identity(index))
	var first_id := team.combat_identity(1)
	var first: Dictionary = team.combat_units[1]
	first.cargo["stone"] = 2
	var pool := _private(lab, first_id, 0.375)
	var original_pool: Dictionary = pool
	var original_cargo: Dictionary = first.cargo
	var original_holder: Dictionary = first.item_state
	var player_pool := _private(lab, lab.character.person_id, 0.125)
	# Keep a genuine third person's history at this owner, without duplicates.
	var members := controller.captivity_supply._all_members()
	assert(Sustain.move_members(player_pool, pool, members, [lab.character.person_id]).ok)
	var before := JSON.stringify([data.site, team.capture_combat_state()])
	assert(controller.before_clear_team_items().code == "BUSY")
	assert(JSON.stringify([data.site, team.capture_combat_state()]) == before)
	assert(Sustain.move_members(pool, player_pool, members, [lab.character.person_id]).ok)
	# Each of three real rows has gear: whole-batch ID exhaustion must fail
	# before any earlier source, private pool or item location changes.
	var previous_next := int(data.site.next_loot)
	data.site.next_loot = 2147483646
	before = JSON.stringify([data.site, team.capture_combat_state()])
	assert(not controller.before_clear_team_items().ok)
	assert(JSON.stringify([data.site, team.capture_combat_state()]) == before)
	data.site.next_loot = previous_next
	var broken_holder: Dictionary = team.combat_units[2].item_state
	var previous_version := int(broken_holder.version)
	for invalid_version: int in [-1, 2147483646]:
		broken_holder.version = invalid_version
		before = JSON.stringify([data.site, team.capture_combat_state()])
		assert(not controller.before_clear_team_items().ok)
		assert(JSON.stringify([data.site, team.capture_combat_state()]) == before)
	broken_holder.version = previous_version
	var count := int(data.site.item_records.size())
	var expected_items: Array = original_holder.item_ids.duplicate()
	var actor_pool_before := player_pool.duplicate(true)
	lab.clear_army()
	assert(not team.has_army() and team.combat_units.is_empty())
	assert(int(data.site.item_records.size()) == count and data.site.ground_loot.size() == 3)
	assert(is_same(player_pool, data.site.person_supply[str(lab.character.person_id)]) and player_pool == actor_pool_before)
	assert(is_same(first.cargo, original_cargo) and is_same(first.item_state, original_holder))
	assert(first.cargo.is_empty() and first.item_state.item_ids.is_empty() and original_pool.open_rations == 0.0)
	for identity: int in ids:
		assert(not data.site.person_supply.has(str(identity)))
	var own_bag := {}
	for bag: Dictionary in data.site.ground_loot.values():
		if int(bag.original_owner) == first_id:
			own_bag = bag
	assert(not own_bag.is_empty() and own_bag.open_rations == 0.375 and own_bag.cargo == {"stone": 2} and own_bag.item_ids == expected_items)
	_near(_opened_total(data.site), 0.5, "clear preserves Actor and original row food")
	controller._capture_positions()
	assert(Store.save(data, MIGRATED_SAVE).ok)
	var loaded := Store.load_site(MIGRATED_SAVE)
	assert(loaded.ok and loaded.data.site.armies.is_empty())
	assert(loaded.data.site.person_supply.keys() == [str(lab.character.person_id)])
	_near(_opened_total(loaded.data.site), 0.5, "cleared scene remains saveable without orphan owners")
	var after := JSON.stringify(data.site)
	lab.clear_army()
	assert(JSON.stringify(data.site) == after, "Repeated clear cannot duplicate any bag or food")

func _female_death(lab: TerrainLab) -> void:
	var team := _deploy(lab, 3)
	var controller: SiteController = lab.site_controller
	var data := lab.terrain
	var items_before := int(data.site.item_records.size())
	var holders: Array[Dictionary] = []
	for index in range(3):
		var row: Dictionary = team.combat_units[index]
		assert(int(row.appearance.body) == 1)
		_private(lab, team.combat_identity(index), 0.125 * (index + 1))
		row.cargo.stone = index + 1
		holders.append(row.item_state.duplicate(true))
		team.apply_unit_contact(index, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false, "environmental": true})
	var down_seconds := float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"])
	lab._process((ceilf(down_seconds / TerrainLab.EXCHANGE_ACTION_STEP) + 1.0) * TerrainLab.EXCHANGE_ACTION_STEP)
	assert(controller._pending_deaths.is_empty() and data.site.ground_loot.size() == 3)
	assert(int(data.site.item_records.size()) == items_before)
	for index in range(3):
		var row: Dictionary = team.combat_units[index]
		var bag: Dictionary = data.site.ground_loot[str(row.remains_id)]
		assert(row.loot_settled and row.item_state.item_ids.is_empty() and row.cargo.is_empty())
		assert(bag.item_ids == holders[index].item_ids and bag.equipped == holders[index].equipped)
		assert(bag.cargo == {"stone": index + 1} and float(bag.open_rations) == 0.125 * (index + 1))
	_near(_opened_total(data.site), 0.75, "Female deaths preserve all real opened food")
	controller._capture_positions()
	var saved := Store.save(data, MIGRATED_SAVE)
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(MIGRATED_SAVE)
	assert(loaded.ok, str(loaded))
	assert(loaded.data.site.ground_loot == data.site.ground_loot)
	lab.bind_terrain(loaded.data)
	controller._auto_save_blocked = true
	assert(controller._pending_deaths.is_empty() and lab.army.combat_units.size() == 3)
	for row: Dictionary in lab.army.combat_units:
		assert(int(row.appearance.body) == 1 and row.hp == 0.0 and row.loot_settled)
	_near(_opened_total(lab.terrain.site), 0.75, "Female opened food survives original save/load/bind")

func _run() -> void:
	for female_count: int in [0, 3]:
		# Independent fixtures must not reuse the intentionally dead, restored NPC
		# from the previous gender's migration/bind verification.
		var lab := TerrainLab.new()
		lab.pause_when_unfocused = false
		root.add_child(lab)
		lab.set_process(false)
		lab.character.set_process(false)
		lab.npc.set_process(false)
		lab.npc_retaliates = false
		if female_count == 0:
			_legacy(lab, female_count)
		else:
			_female_death(lab)
		_clear(lab, female_count)
		lab.free()
	print("SITE OPENED FOOD RETENTION PASS: all-male legacy migration and legal all-female death/opened-food save/load/bind; both genders' clear preflight and exact food/item conservation; format-3 missing-bag migration preserves meal history/source file, bounded-ID atomic failures and idempotence")
	quit(0)
