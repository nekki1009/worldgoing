extends "res://scripts/tests/site_building_economy_upgrade_test.gd"
## Candidate only: reuse paid construction/work, original Army/terrain/Sustain.
const ArmyHelper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const RefugeSustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const APPROVED := ["house", "saltworks", "kiln", "charcoal", "smelter", "smithy", "tannery", "weaver", "fighting_position"]
const CLASSIFICATION_REJECTS := ["", "unknown_future_building", "prison", "stone_wall", "bridge", "dock", "shipyard", "tent", "camp_tent", "warehouse", "barracks", "training_ground", "road", "level", "farm", "fiber_farm", "fodder_farm", "pasture", "horse_ranch", "palisade", "well", "intake", "gate", "wall_stairs", "siege_ladder"]
var completed_groups := 0

func _run() -> void:
	create_timer(55.0).timeout.connect(func() -> void: quit(1))
	_approved_paid_features()
	_planned_and_building_features()
	_negative_kind_classification()
	_paid_prisons_and_other_facilities()
	_destroy_and_paid_repair_same_house()
	_original_entrance_guards()
	_legacy_house_and_edge_priority()
	TerrainArmy.release_contact_source()
	assert(completed_groups == 7)
	print("SITE_BUILDING_REFUGE_WHITELIST_PASS: all 9 SOL-approved paid completed features with original geometry/Army; genuine planned/building house and fighting_position denied; explicit synthetic classification negatives; original paid prisons of neutral/same/other faction denied; genuine stone wall/warehouse/barracks denied; same original house body damage and paid repair restoration; unchanged original Actor/enemy-Army/unwalkable entrance guards; legacy house compatibility and true edge priority. Original Sustain collapse and coordinator steps for approved destinations; no Native refuge, GPU, save-file or production-clock claim.")
	quit(0)

func _refuge_fixture(sealed: bool = true) -> TerrainData:
	var data := _fixture(false)
	if sealed:
		for x: int in range(data.size.x):
			data.flags[data.index(Vector2i(x, 0))] = 0
			data.flags[data.index(Vector2i(x, data.size.y - 1))] = 0
		for y: int in range(data.size.y):
			data.flags[data.index(Vector2i(0, y))] = 0
			data.flags[data.index(Vector2i(data.size.x - 1, y))] = 0
		Runtime.rebuild_terrain_edges(data)
	return data

func _add_sea(data: TerrainData) -> void:
	# The original workflow's real coast case, beside the 4x4 saltworks.
	var index := data.index(Vector2i(24, 21))
	data.surface_types[index] = TerrainData.Surface.WATER
	data.water_kind[index] = 2
	data.water_body[index] = index
	data.flags[index] = TerrainData.Flag.BLOCKED
	Runtime.rebuild_terrain_edges(data)

func _new_refuge_army(data: TerrainData, team_id: int = 41, faction: int = 1, start: Vector2i = Vector2i(6, 6)) -> TerrainArmy:
	return ArmyHelper.create_test_army(data, team_id, faction, 1, start)

func _expect_refuge(army: TerrainArmy, key: String, accepted: bool, label: String) -> void:
	var before := JSON.stringify(army.data.site.features, "", true, true)
	var original_person := army.combat_identity(0)
	var found := {}
	var refuges := army._retreat_refuge_cells()
	for cell: Vector2i in refuges:
		var entry: Dictionary = refuges[cell]
		if str(entry.kind) == "building" and str(entry.target_id) == key:
			found[cell] = entry
	assert(not found.is_empty() == accepted, label)
	if accepted:
		var feature: Dictionary = army.data.site.features[key]
		var entrance := army.data.cell_from_index(int(feature.entrance))
		assert(found.has(entrance), label + ": original entrance missing")
		for cell: Vector2i in found:
			assert(army.data.is_walkable(cell), label + ": unwalkable approach")
			assert(cell == entrance or army.data.can_step(entrance, cell), label + ": illegal approach edge")
			if bool(feature.solid): assert(not feature.cells.has(army.data.index(cell)), label + ": solid footprint became shelter")
	assert(before == JSON.stringify(army.data.site.features, "", true, true) and original_person == army.combat_identity(0), label + ": selector mutated original feature/person")

func _paid_planned(data: TerrainData, kind: String, extent: Vector2i = Vector2i.ONE, owner: int = 1) -> String:
	var settings := {"owner_faction": owner}
	var layout := Runtime.building_cells(data, kind, Vector2i(20, 20), extent, settings)
	assert(layout.ok)
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var inventory: Dictionary = data.site.inventory.duplicate(true)
	var paid := Runtime.request_build(data, kind, cells, Callable(), settings)
	assert(paid.ok)
	var key := str(paid.feature)
	var feature: Dictionary = data.site.features[key]
	assert(str(feature.stage) == "planned" and int(feature.owner_faction) == owner)
	for item: String in feature.cost: assert(int(data.site.inventory[item]) == int(inventory.get(item, 0)) - int(feature.cost[item]))
	return key

func _collapse_original_sustain(army: TerrainArmy) -> void:
	var members := {}
	var checkpoints := {}
	for row: Dictionary in army.combat_units:
		members[int(row.person_id)] = row
		checkpoints[str(row.person_id)] = 0
	var state := RefugeSustain.create(Runtime.now(army.data) * 60.0)
	assert(RefugeSustain.add_members(state, members, members.keys()).ok)
	if not army.data.site.has("team_supply"): army.data.site["team_supply"] = {}
	army.data.site.team_supply[str(army.team_id)] = {"version": 1, "sustain": state, "inventory": {}, "training_order": false, "training_requester": -1, "revision": 0, "delivery": {}, "life_checkpoint": checkpoints}
	army.sustain_routed_query = func(original: TerrainArmy) -> bool: return bool(original.data.site.team_supply[str(original.team_id)].sustain.routed)
	var outcome := RefugeSustain.advance_to(state, members, {}, float(state.at) + 40.0 * RefugeSustain.HOUR)
	# Fixture clock alignment from the original tactical retreat test, not live time proof.
	army.data.site.minute = int(army.data.site.minute) + 2400
	assert(outcome.ok and outcome.routed_now and outcome.damage.is_empty() and army.is_sustain_routed())

func _finish_original_retreat(army: TerrainArmy, expected: String, key: String = "") -> void:
	var coordinator := SiteCombatMovementCoordinator.new()
	coordinator.register_formation(army)
	_collapse_original_sustain(army)
	assert(army.begin_morale_retreat().ok)
	for _tick: int in range(200):
		var prior: Vector2i = army.cells[0]
		coordinator.combat_logic_tick_if_needed(0.5)
		army.prepare_combat(0.5)
		coordinator.complete_committed_moves()
		army.settle_combat_command()
		assert(army.cells[0] == prior or army.data.can_step(prior, army.cells[0]), "Original retreat crossed an illegal edge")
		if army.morale_retreat_sheltered() or army.morale_retreat_terminal(): break
	if expected == "building":
		assert(army.morale_retreat_sheltered() and not bool(army.combat_hot_get(0, &"site_exited", false)) and not bool(army.combat_hot_get(0, &"surrender_pending", false)))
		var entry: Dictionary = army._retreat_refuge_cells().get(army.cells[0], {})
		assert(str(entry.get("kind", "")) == "building" and str(entry.get("target_id", "")) == key)
	elif expected == "edge":
		assert(bool(army.combat_hot_get(0, &"site_exited", false)) and army._edge_distance(army.cells[0]) == 0 and army.moving_to[0] == TerrainArmy.INVALID_CELL)
	else:
		assert(bool(army.combat_hot_get(0, &"surrender_pending", false)) and not bool(army.combat_hot_get(0, &"captive", false)))
	assert(TerrainArmy.valid_combat_state(army.capture_combat_state(), army.data))
	coordinator.unregister_formation(army)

func _approved_paid_features() -> void:
	assert(APPROVED.size() == 9)
	for kind: String in APPROVED:
		var data := _refuge_fixture()
		if kind == "saltworks": _add_sea(data)
		var inventory: Dictionary = data.site.inventory.duplicate(true)
		var key := _build(data, kind, Vector2i(20, 20))
		var feature: Dictionary = data.site.features[key]
		for item: String in feature.cost: assert(int(data.site.inventory[item]) == int(inventory.get(item, 0)) - int(feature.cost[item]), kind + ": original cost was not paid")
		var army := _new_refuge_army(data)
		_expect_refuge(army, key, true, "paid completed " + kind)
		_finish_original_retreat(army, "building", key)
		army.free()
	completed_groups += 1

func _planned_and_building_features() -> void:
	for kind: String in ["house", "fighting_position"]:
		var data := _refuge_fixture()
		var key := _paid_planned(data, kind)
		var feature: Dictionary = data.site.features[key]
		var army := _new_refuge_army(data)
		assert(str(feature.stage) == "planned")
		_expect_refuge(army, key, false, kind + " planned")
		var task := _task(feature, "construct")
		Runtime._feature_work(data, key, float(feature.work) * 0.5, Callable(), Callable(), task, {}, 20, 1)
		assert(str(feature.stage) == "building" and float(feature.progress) > 0.0 and float(feature.progress) < float(feature.work))
		_expect_refuge(army, key, false, kind + " original partial construction")
		Runtime._feature_work(data, key, float(feature.work) * 0.5, Callable(), Callable(), task, {}, 20, 1)
		assert(str(feature.stage) == "complete" and Runtime.validate_feature_layout(data, feature).ok)
		_expect_refuge(army, key, true, kind + " original completed construction")
		army.free()
	completed_groups += 1

func _negative_kind_classification() -> void:
	var data := _refuge_fixture()
	var key := _build(data, "house", Vector2i(20, 20))
	var original: Dictionary = data.site.features[key]
	var army := _new_refuge_army(data)
	for kind: String in CLASSIFICATION_REJECTS:
		# Deliberate unvalidated selector input, never a legal saved/new built feature.
		var synthetic := original.duplicate(true)
		synthetic.kind = kind
		data.site.features[key] = synthetic
		_expect_refuge(army, key, false, "synthetic type classifier " + kind)
	data.site.features[key] = original
	_expect_refuge(army, key, true, "same original house after synthetic classification")
	army.free()
	completed_groups += 1

func _paid_prisons_and_other_facilities() -> void:
	for owner: int in [-1, 1, 2]:
		var data := _refuge_fixture()
		var key := _paid_planned(data, "prison", Vector2i(2, 2), owner)
		var feature: Dictionary = data.site.features[key]
		var task := _task(feature, "construct")
		Runtime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, 20, owner)
		assert(str(feature.stage) == "complete" and int(feature.owner_faction) == owner and Runtime.validate_feature_layout(data, feature).ok)
		var army := _new_refuge_army(data)
		_expect_refuge(army, key, false, "paid prison owner " + str(owner))
		_finish_original_retreat(army, "surrender")
		army.free()
	for kind: String in ["stone_wall", "warehouse", "barracks"]:
		var data := _refuge_fixture()
		var key := _build(data, kind, Vector2i(20, 20), Vector2i(10, 10) if kind == "barracks" else Vector2i.ONE)
		var army := _new_refuge_army(data)
		_expect_refuge(army, key, false, "paid unauthorized " + kind)
		army.free()
	completed_groups += 1

func _destroy_and_paid_repair_same_house() -> void:
	var data := _refuge_fixture()
	var key := _build(data, "house", Vector2i(20, 20))
	var feature: Dictionary = data.site.features[key]
	var cells: Array = feature.cells.duplicate()
	var entrance := int(feature.entrance)
	var army := _new_refuge_army(data)
	_expect_refuge(army, key, true, "original intact civil house")
	assert(Runtime.damage_structure_part(data, key, "body", 40.0).ok)
	_expect_refuge(army, key, true, "original nonzero damaged civil house")
	assert(Runtime.damage_structure_part(data, key, "body", 60.0).ok and float(feature.parts.body.hp) == 0.0 and str(feature.stage) == "complete")
	assert(not Runtime.feature_usable(feature))
	_expect_refuge(army, key, false, "original destroyed civil house")
	var inventory: Dictionary = data.site.inventory.duplicate(true)
	assert(Runtime.request_repair(data, key, "body", 1).ok)
	for item: String in feature.repair.cost: assert(int(data.site.inventory[item]) == int(inventory[item]) - int(feature.repair.cost[item]))
	var task := _task(feature, "repair")
	var work := float(feature.repair.work)
	Runtime._feature_work(data, key, work * 0.5, Callable(), Callable(), task, {}, 20, 1)
	assert(feature.has("repair") and float(feature.parts.body.hp) == 0.0)
	_expect_refuge(army, key, false, "original paid repair not yet completed")
	Runtime._feature_work(data, key, work * 0.5, Callable(), Callable(), task, {}, 20, 1)
	assert(not feature.has("repair") and float(feature.parts.body.hp) == Runtime.civil_max_hp(feature) and feature.cells == cells and int(feature.entrance) == entrance)
	_expect_refuge(army, key, true, "same original house after original repair completion")
	_finish_original_retreat(army, "building", key)
	army.free()
	completed_groups += 1

func _original_entrance_guards() -> void:
	var data := _refuge_fixture()
	var key := _build(data, "house", Vector2i(20, 20))
	var entrance := data.cell_from_index(int(data.site.features[key].entrance))
	var army := _new_refuge_army(data)
	var actor := TerrainTestCharacter.new()
	actor.data = data
	actor.terrain_cell = entrance
	actor.faction_id = 2
	army.npc = actor
	_expect_refuge(army, key, false, "original hostile Actor at entrance")
	army.npc = null
	actor.free()
	var coordinator := SiteCombatMovementCoordinator.new()
	var enemy := _new_refuge_army(data, 42, 2, entrance)
	coordinator.register_formation(army)
	coordinator.register_formation(enemy)
	_expect_refuge(army, key, false, "original hostile Army at entrance")
	coordinator.unregister_formation(enemy)
	enemy.free()
	coordinator.unregister_formation(army)
	_expect_refuge(army, key, true, "same original house after enemy leaves")
	data.flags[data.index(entrance)] = 0
	Runtime.rebuild_terrain_edges(data)
	_expect_refuge(army, key, false, "original unwalkable entrance")
	data.flags[data.index(entrance)] = TerrainData.Flag.WALKABLE
	Runtime.rebuild_terrain_edges(data)
	_expect_refuge(army, key, true, "same original house with reopened entrance")
	army.free()
	completed_groups += 1

func _legacy_house_and_edge_priority() -> void:
	var data := _refuge_fixture(false)
	var key := _build(data, "house", Vector2i(20, 20))
	var army := _new_refuge_army(data)
	# Explicit legacy classifier evidence, separate from the paid-layout assertions above.
	var legacy: Dictionary = data.site.features[key].duplicate(true)
	for field: String in ["civil_version", "building_grade", "parts"]: legacy.erase(field)
	data.site.features[key] = legacy
	_expect_refuge(army, key, true, "original legacy house compatibility")
	_finish_original_retreat(army, "edge")
	army.free()
	completed_groups += 1
