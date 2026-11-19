extends SceneTree

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_building_close_20261004/economy_upgrade.json"
var checks := 0

class CrewFixture extends RefCounted:

	var terrain: TerrainData
	var army := TerrainArmy.new()
	var combat_armies: Array[TerrainArmy] = []
	var combat_actors: Array[TerrainTestCharacter] = []
	var crew := SiteWorkTeam.new()

	func setup(tree_root: Node, data: TerrainData, positions: Array[Vector2i], snapshot: Dictionary = {}) -> void:
		terrain = data
		tree_root.add_child(army)
		army.set_process(false)
		army.team_id = 1
		army.faction_id = 1
		army.roster_size = positions.size()
		if snapshot.is_empty():
			assert(army.deploy_at(terrain, null, null, positions))
			assert(army.enable_combat(false))
			for row: Dictionary in army.combat_units:
				row["cargo"] = {}
				row["item_state"] = Runtime.new_item_state("person:" + str(row.person_id))
		else:
			army.restore_combat_state(snapshot, terrain, null, null)
		combat_armies.append(army)
		crew.init(self)

	func _combat_target(identity: int) -> Dictionary:
		var index := army.index_for_identity(identity)
		return {"owner": army, "unit": index, "cell": army.cells[index], "hp": army.combat_units[index].hp} if index >= 0 else {}

	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return false

	func controlled_person_id() -> int:
		return -1

	func tick(seconds: float) -> void:
		Runtime.advance(terrain, seconds / 60.0, false, false, Callable(), Callable(), func(elapsed: float) -> void: crew.advance(elapsed))
		army.prepare_combat(TerrainArmy.MOVE_DURATION + 0.00001)

	func close() -> void:
		crew.lab = null
		army.free()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(55.0).timeout.connect(func() -> void: quit(1))
	_check_material_chains()
	_check_paid_batch_store_and_guards()
	_check_upgrade_refunds_damage_and_store()
	_check_legacy_and_corrupt_saves()
	_check_real_workers_and_in_transit_guard()
	TerrainArmy.release_contact_source()
	assert(checks == 5, "Economy/upgrade contract ended before all phases")
	print("SITE_BUILDING_ECONOMY_UPGRADE_PASS: natural wood/clay/ore harvest and original deposit; fiber crop/real sheep to rope/wool cloth; pottery/steel recipes to same-ID upgrade, tools and original camp_tent consumption; paid batch once with water/tools/full-cargo preservation and Store resume; grade 1/2/3 real work/materials, half-job floor refunds and JSON resume; proportional existing damage, ruined-body navigation/water/repair occupancy; legacy prospective fields and corrupt-file refusal; original Army workers walk/work/fatigue/deposit and in-transit guards. No visual, native crowd or performance claim.")
	quit(0)

func _fixture(saved_base: bool = false) -> TerrainData:
	var data: TerrainData
	if saved_base:
		data = TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(48, 48)})
		Env.initialize(data, "building-economy-upgrade-store")
		for source: String in data.resource_base:
			Env.change(data, source, {"cleared": true, "remaining": 0})
		for y: int in range(2, 46):
			for x: int in range(2, 46):
				var index := data.index(Vector2i(x, y))
				data.height_levels[index] = 0
				data.site.terrain_changes[str(index)] = 0
	else:
		data = TerrainData.new()
		data.allocate(Vector2i(48, 48))
		data.spawn_cell = Vector2i(3, 3)
		data.flags.fill(TerrainData.Flag.WALKABLE)
		Env.initialize(data, "building-economy-upgrade")
		data.resource_base.clear()
		data.site.changes.clear()
		data.height_levels.fill(0)
		data.flags.fill(TerrainData.Flag.WALKABLE)
		data.ramp_edges.fill(0)
		data.water_kind.fill(0)
		data.water_body.fill(-1)
		data.surface_types.fill(TerrainData.Surface.GRASS)
		data.foundation.fill(80)
		data.fertility.fill(60)
		data.moisture.fill(70)
		data.groundwater.fill(80)
		data.drainage.fill(70)
	data.site.depot_cell = data.index(Vector2i(3, 3))
	data.site.worker.cell = data.index(Vector2i(3, 4))
	data.site["worker_enabled"] = false
	data.site.inventory = {"wood": 300, "stone": 300, "clay": 100, "tools": 4, "seeds": 2, "fodder": 4, "sheep": 1,
		"pottery": 8, "rope": 8, "brick": 12, "steel": 6, "fiber": 12, "wool": 12, "charcoal": 12, "iron": 8}
	data.site.capacity = 5000
	assert(Runtime.initialize_item_storage(data.site).ok)
	Runtime.rebuild_terrain_edges(data)
	Env.rebuild_indexes(data)
	return data

func _task(feature: Dictionary, action: String, slot: int = -1, data: TerrainData = null) -> Dictionary:
	var cell := int(feature.entrance)
	if action == "repair": cell = int(feature.repair.work_cell)
	if action == "construct" and feature.has("pending_build"): cell = int(feature.pending_build.entrance)
	if slot >= 0: cell = int(Runtime.feature_work_slots(data, feature)[slot].cell)
	return {"target": "", "action": action, "cell": cell, "mode": "work", "status": "", "progress": 0.0, "work_slot": slot}

func _build(data: TerrainData, kind: String, anchor: Vector2i, size: Vector2i = Vector2i.ONE, options: Dictionary = {}) -> String:
	var selected := options.duplicate()
	selected["owner_faction"] = 1
	var layout := Runtime.building_cells(data, kind, anchor, size, selected)
	assert(layout.ok, str(layout))
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var result := Runtime.request_build(data, kind, cells, Callable(), selected)
	assert(result.ok, str(result))
	var key := str(result.feature)
	var feature: Dictionary = data.site.features[key]
	var task := _task(feature, "construct")
	Runtime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	assert(str(feature.stage) == "complete", str(task))
	assert(Runtime.validate_feature_layout(data, feature).ok, str(Runtime.validate_feature_layout(data, feature)))
	return key

func _stop(data: TerrainData, key: String) -> void:
	Runtime._stop_feature_zones(data, key, "operate")

func _batch(data: TerrainData, key: String, recipe: String = "") -> Dictionary:
	var feature: Dictionary = data.site.features[key]
	_stop(data, key)
	if Runtime.FEATURE_RECIPES.has(str(feature.kind)):
		assert(Runtime.request_feature_recipe(data, key, recipe, 1).ok)
	assert(Runtime.operate_feature(data, key).ok)
	var definition := Runtime.feature_recipe(feature)
	var slot := 0 if str(feature.kind) in Runtime.FARM_KINDS + Runtime.PASTURE_KINDS else -1
	var task := _task(feature, "operate", slot, data)
	var cargo := {}
	if slot >= 0: Runtime.set_operating_slots(data, [{"task": {"target": "feature:" + key, "work_slot": slot}}])
	var before: Dictionary = data.site.inventory.duplicate()
	Runtime._feature_work(data, key, 1.0, Callable(), Callable(), task, cargo, 20, 1)
	assert(bool(feature.batch_paid) and float(feature.production) > 0.0, str(task))
	for item: String in definition.input:
		assert(int(data.site.inventory.get(item, 0)) == int(before.get(item, 0)) - int(definition.input[item]), "Inputs must debit exactly once")
	Runtime._feature_work(data, key, float(definition.cycle), Callable(), Callable(), task, cargo, 20, 1)
	assert(not bool(feature.batch_paid) and float(feature.production) == 0.0)
	assert(cargo == definition.output, str(cargo))
	for item: String in definition.input:
		assert(int(data.site.inventory.get(item, 0)) == int(before.get(item, 0)) - int(definition.input[item]), "Completing batch paid input twice")
	var output := cargo.duplicate()
	assert(Runtime.deposit(data, cargo, Vector2i(3, 4)).ok)
	assert(cargo.is_empty())
	_stop(data, key)
	return output

func _gather(data: TerrainData, kind: int, count: int, cell: Vector2i) -> void:
	var key := "economy-source-%d" % kind
	var index := data.index(cell)
	data.resource_base[key] = {"kind": kind, "cell": index, "cells": [index], "capacity": 100, "variant": 0, "water": -1,
		"blocks": kind in [Env.Kind.TIMBER, Env.Kind.STONE], "recover": 0}
	Env.rebuild_indexes(data)
	if kind == Env.Kind.IRON: assert(Runtime.harvest(data, key, cell + Vector2i.DOWN, {}, "survey").ok)
	var item := str(Env.ITEMS[kind])
	var before := int(data.site.inventory.get(item, 0))
	var total := 0
	for _iteration: int in count:
		var cargo := {}
		assert(Runtime.harvest(data, key, cell + Vector2i.DOWN, cargo).ok)
		total += int(cargo[item])
		assert(Runtime.deposit(data, cargo, Vector2i(3, 4)).ok)
	assert(int(data.site.inventory.get(item, 0)) == before + total)
	assert(int(Env.resource(data, key).remaining) == 100 - total)

func _check_material_chains() -> void:
	var data := _fixture()
	data.site.inventory = {"wood": 32, "stone": 34, "clay": 10, "tools": 4, "sheep": 1, "seeds": 1, "fodder": 3}
	var well := _build(data, "well", Vector2i(9, 12))
	var kiln := _build(data, "kiln", Vector2i(11, 12))
	var smelter := _build(data, "smelter", Vector2i(17, 12))
	var weaver := _build(data, "weaver", Vector2i(11, 19))
	var smithy := _build(data, "smithy", Vector2i(17, 19))
	var charcoal := _build(data, "charcoal", Vector2i(17, 7))
	var pasture := _build(data, "pasture", Vector2i(4, 16), Vector2i(3, 3))
	var fiber := _build(data, "fiber_farm", Vector2i(4, 12), Vector2i(2, 2))
	var house := _build(data, "house", Vector2i(22, 7), Vector2i.ONE, {"variant": "small"})
	assert(int(data.site.inventory.wood) == 0 and int(data.site.inventory.clay) == 0)
	_gather(data, Env.Kind.TIMBER, 5, Vector2i(40, 4))
	_gather(data, Env.Kind.CLAY, 1, Vector2i(40, 8))
	_gather(data, Env.Kind.IRON, 3, Vector2i(40, 12))
	Runtime.rebuild_water(data)
	assert(data.site.water_links.has(well))
	assert(_batch(data, fiber) == {"fiber": 5})
	assert(_batch(data, weaver, "rope") == {"rope": 2})
	for _iteration: int in 3: assert(_batch(data, pasture) == {"wool": 2})
	for _iteration: int in 2: assert(_batch(data, weaver, "wool_cloth") == {"cloth": 2})
	assert(Runtime.ranged_craft(data, "camp_tent", 1).ok)
	assert(int(data.site.inventory.get("camp_tent", 0)) == 1 and int(data.site.inventory.get("cloth", 0)) == 0 and int(data.site.inventory.get("wool", 0)) == 0)
	assert(_batch(data, kiln, "pottery") == {"pottery": 2})
	for _iteration: int in 3: assert(_batch(data, charcoal) == {"charcoal": 2})
	assert(_batch(data, smelter) == {"iron": 2})
	assert(_batch(data, smelter, "steel") == {"steel": 1})
	var tools := int(data.site.inventory.tools)
	assert(_batch(data, smithy, "steel_tools") == {"tools": 2})
	assert(int(data.site.inventory.tools) == tools + 2 and int(data.site.inventory.steel) == 0)
	var original: Dictionary = data.site.features[house]
	assert(Runtime.request_upgrade(data, house, 1).ok)
	assert(int(data.site.inventory.pottery) == 0 and int(data.site.inventory.rope) == 0)
	var builder := _task(original, "construct")
	Runtime._feature_work(data, house, float(original.pending_build.work), Callable(), Callable(), builder, {}, 20, 1)
	assert(is_same(original, data.site.features[house]) and int(original.building_grade) == 2)
	assert(not original.has("pending_build") and Runtime.validate_feature_layout(data, original).ok)
	checks += 1

func _check_paid_batch_store_and_guards() -> void:
	var data := _fixture(true)
	_build(data, "well", Vector2i(8, 12))
	var key := _build(data, "kiln", Vector2i(11, 12))
	var initial := JSON.stringify(data.site)
	assert(not Runtime.request_feature_recipe(data, key, "pottery", 2).ok and not Runtime.request_feature_recipe(data, key, "steel", 1).ok)
	assert(JSON.stringify(data.site) == initial)
	assert(Runtime.request_feature_recipe(data, key, "pottery", 1).ok)
	var feature: Dictionary = data.site.features[key]
	Runtime.rebuild_water(data)
	var worker := _task(feature, "operate")
	var cargo := {}
	var clay := int(data.site.inventory.clay)
	Runtime._feature_work(data, key, 5.0, Callable(), Callable(), worker, cargo, 20, 1)
	assert(bool(feature.batch_paid) and is_equal_approx(float(feature.production), 5.0) and int(data.site.inventory.clay) == clay - 2)
	var before := JSON.stringify(data.site)
	assert(not Runtime.request_feature_recipe(data, key, "", 1).ok)
	assert(not Runtime.request_upgrade(data, key, 1).ok)
	assert(not Runtime.cancel_feature(data, key, Callable(), 1).ok)
	assert(JSON.stringify(data.site) == before, "Rejected command changed an original paid batch")
	assert(Store.save(data, SAVE + ".paid").ok)
	var loaded := Store.load_site(SAVE + ".paid")
	assert(loaded.ok, str(loaded))
	var resumed: TerrainData = loaded.data
	var saved: Dictionary = resumed.site.features[key]
	assert(saved.civil_version is int and saved.building_grade is int and str(saved.recipe_id) == "pottery")
	assert(bool(saved.batch_paid) and is_equal_approx(float(saved.production), 5.0))
	var task := _task(saved, "operate")
	var tool_count := int(resumed.site.inventory.tools)
	resumed.site.inventory.tools = 0
	Runtime._feature_work(resumed, key, 1.0, Callable(), Callable(), task, cargo, 20, 1)
	assert(is_equal_approx(float(saved.production), 5.0) and cargo.is_empty())
	resumed.site.inventory.tools = tool_count
	resumed.site.water_status[key] = {"demand": 0.02, "supplied": 0.0}
	Runtime._feature_work(resumed, key, 1.0, Callable(), Callable(), task, cargo, 20, 1)
	assert(is_equal_approx(float(saved.production), 5.0) and bool(saved.batch_paid))
	Runtime.rebuild_water(resumed)
	cargo = {"stone": 20}
	Runtime._feature_work(resumed, key, 5.0, Callable(), Callable(), task, cargo, 20, 1)
	assert(is_equal_approx(float(saved.production), 10.0) and bool(saved.batch_paid) and cargo == {"stone": 20})
	assert(Runtime.damage_structure_part(resumed, key, "body", 100.0).ok)
	resumed.site.inventory.tools = 0
	resumed.site.water_status[key] = {"demand": 0.02, "supplied": 0.0}
	cargo.clear()
	Runtime._feature_work(resumed, key, 0.0, Callable(), Callable(), task, cargo, 20, 1)
	assert(cargo == {"pottery": 2} and not bool(saved.batch_paid) and float(saved.production) == 0.0)
	assert(int(resumed.site.inventory.clay) == clay - 2, "Store resume repaid the original batch")
	checks += 1

func _check_upgrade_refunds_damage_and_store() -> void:
	var data := _fixture(true)
	var key := _build(data, "kiln", Vector2i(13, 12))
	var feature: Dictionary = data.site.features[key]
	var cells: Array = feature.cells.duplicate()
	var damage_first: Dictionary = Runtime.damage_structure_part(data, key, "body", 40.0)
	assert(damage_first.ok)
	var before: Dictionary = data.site.inventory.duplicate()
	var preview := Runtime.request_upgrade(data, key, 1, Callable(), true)
	assert(preview.ok and preview.target_grade == 2 and before == data.site.inventory)
	var upgrade_first: Dictionary = Runtime.request_upgrade(data, key, 1)
	assert(upgrade_first.ok)
	var cost: Dictionary = feature.pending_build.cost.duplicate()
	var work := float(feature.pending_build.work)
	var task := _task(feature, "construct")
	Runtime._feature_work(data, key, work * 0.5, Callable(), Callable(), task, {}, 20, 1)
	assert(float(feature.parts.body.hp) == 60.0 and int(feature.building_grade) == 1)
	var saved_upgrade: Dictionary = Store.save(data, SAVE + ".upgrade")
	assert(saved_upgrade.ok)
	var upgrade_text := FileAccess.get_file_as_string(SAVE + ".upgrade")
	_write_corrupt(upgrade_text, key, func(row: Dictionary) -> void: row.pending_build.target_grade = 3, "skip_upgrade_grade")
	_write_corrupt(upgrade_text, key, func(row: Dictionary) -> void: row.pending_build.work += 0.25, "wrong_upgrade_work")
	_write_corrupt(upgrade_text, key, func(row: Dictionary) -> void: row.pending_build.cost.pottery += 0.25, "fractional_upgrade_material")
	_write_corrupt(upgrade_text, key, func(row: Dictionary) -> void: row.pending_build.added_cells = [row.cells[0]], "upgrade_moves_footprint")
	var loaded := Store.load_site(SAVE + ".upgrade")
	assert(loaded.ok, str(loaded))
	var resumed: TerrainData = loaded.data
	var restored: Dictionary = resumed.site.features[key]
	assert(restored.pending_build.target_grade is int and int(restored.pending_build.target_grade) == 2)
	assert(float(restored.parts.body.hp) == 60.0 and restored.cells == cells)
	var continuing := Store.load_site(SAVE + ".upgrade")
	assert(continuing.ok)
	var continued: TerrainData = continuing.data
	var continued_feature: Dictionary = continued.site.features[key]
	var continued_stock: Dictionary = continued.site.inventory.duplicate()
	var continuation_task := _task(continued_feature, "construct")
	Runtime._feature_work(continued, key, work * 0.5, Callable(), Callable(), continuation_task, {}, 20, 1)
	assert(not continued_feature.has("pending_build") and int(continued_feature.building_grade) == 2 and float(continued_feature.parts.body.hp) == 90.0)
	assert(continued.site.inventory == continued_stock, "Resuming an already-paid upgrade debited twice")
	var paid: Dictionary = resumed.site.inventory.duplicate()
	var cancel_result: Dictionary = Runtime.cancel_feature(resumed, key, Callable(), 1)
	assert(cancel_result.ok)
	for item: String in cost:
		assert(int(resumed.site.inventory[item]) == int(paid[item]) + floori(float(cost[item]) * 0.5), "Half-stage upgrade refund must floor original unused materials")
	assert(is_same(restored, resumed.site.features[key]) and float(restored.parts.body.hp) == 60.0 and int(restored.building_grade) == 1)
	var upgrade_again: Dictionary = Runtime.request_upgrade(resumed, key, 1)
	assert(upgrade_again.ok)
	var resumed_task := _task(restored, "construct")
	Runtime._feature_work(resumed, key, float(restored.pending_build.work), Callable(), Callable(), resumed_task, {}, 20, 1)
	assert(int(restored.building_grade) == 2 and float(restored.parts.body.hp) == 90.0 and restored.cells == cells)
	assert(Runtime.validate_feature_layout(resumed, restored).ok)
	var upgrade_third: Dictionary = Runtime.request_upgrade(resumed, key, 1)
	assert(upgrade_third.ok)
	resumed_task = _task(restored, "construct")
	var grade_three_work := float(restored.pending_build.work)
	Runtime._feature_work(resumed, key, grade_three_work * 0.5, Callable(), Callable(), resumed_task, {}, 20, 1)
	var damage_mid: Dictionary = Runtime.damage_structure_part(resumed, key, "body", 15.0)
	assert(damage_mid.ok)
	Runtime._feature_work(resumed, key, grade_three_work * 0.5, Callable(), Callable(), resumed_task, {}, 20, 1)
	assert(int(restored.building_grade) == 3 and float(restored.parts.body.hp) == 100.0, "Upgrade healed damage received while construction was underway")
	var upgrade_refused: Dictionary = Runtime.request_upgrade(resumed, key, 1)
	assert(not upgrade_refused.ok and is_equal_approx(Runtime.building_productivity(restored), 1.5))
	var operation := _task(restored, "operate")
	var cargo := {}
	Runtime._feature_work(resumed, key, 1.0, Callable(), Callable(), operation, cargo, 20, 1)
	assert(is_equal_approx(float(restored.production), 1.5), "Grade must change effective work, not only metadata")
	var damage_destroyed: Dictionary = Runtime.damage_structure_part(resumed, key, "body", 200.0)
	assert(damage_destroyed.ok)
	assert(not Runtime.feature_usable(restored) and Runtime.feature_geometry(resumed, restored).blocked.is_empty())
	var stock: Dictionary = resumed.site.inventory.duplicate()
	Runtime._feature_work(resumed, key, 30.0, Callable(), Callable(), operation, cargo, 20, 1)
	assert(is_equal_approx(float(restored.production), 1.5) and resumed.site.inventory == stock and cargo.is_empty())
	var operate_refused: Dictionary = Runtime.operate_feature(resumed, key)
	var upgrade_refused_again: Dictionary = Runtime.request_upgrade(resumed, key, 1)
	assert(not operate_refused.ok and not upgrade_refused_again.ok)
	var repair_first: Dictionary = Runtime.request_repair(resumed, key, "body", 1)
	assert(repair_first.ok)
	var repairing := _task(restored, "repair")
	var occupied_cell := resumed.cell_from_index(int(restored.cells[0]))
	var repair_paid: Dictionary = resumed.site.inventory.duplicate()
	Runtime._feature_work(resumed, key, float(restored.repair.work), func(cell: Vector2i) -> bool: return cell == occupied_cell, Callable(), repairing, {}, 20, 1)
	assert(restored.has("repair") and float(restored.parts.body.hp) == 0.0 and resumed.site.inventory == repair_paid)
	Runtime._feature_work(resumed, key, 0.0, Callable(), Callable(), repairing, {}, 20, 1)
	assert(not restored.has("repair") and float(restored.parts.body.hp) == 200.0)
	# The fire-layout roof lost its support with the body (damage_structure_part zeroes _fire_supported_parts),
	# and save validation requires it to stay at 0 until its own paid repair: body repair alone leaves the kiln DISABLED.
	assert(float(restored.parts.roof.hp) == 0.0 and not Runtime.feature_usable(restored))
	var roof_repair: Dictionary = Runtime.request_repair(resumed, key, "roof", 1)
	assert(roof_repair.ok)
	var roofing: Dictionary = _task(restored, "repair")
	Runtime._feature_work(resumed, key, float(restored.repair.work), Callable(), Callable(), roofing, {}, 20, 1)
	assert(not restored.has("repair") and is_equal_approx(float(restored.parts.roof.hp), float(Runtime.feature_geometry(resumed, restored).parts.roof.max_hp)) and Runtime.feature_usable(restored))
	assert(not Runtime.feature_geometry(resumed, restored).blocked.is_empty() and bool(restored.batch_paid) and is_equal_approx(float(restored.production), 1.5))
	var saved_repaired: Dictionary = Store.save(resumed, SAVE + ".repaired")
	assert(saved_repaired.ok)
	var repaired_load := Store.load_site(SAVE + ".repaired")
	assert(repaired_load.ok and int(repaired_load.data.site.features[key].building_grade) == 3)
	var well := _build(resumed, "well", Vector2i(10, 12))
	var water_source: Dictionary = resumed.site.features[well]
	assert(resumed.site.water_links.has(well))
	var damage_well: Dictionary = Runtime.damage_structure_part(resumed, well, "body", 100.0)
	assert(damage_well.ok)
	assert(not Runtime.feature_usable(water_source) and not resumed.site.water_links.has(well), "Ruined well continued supplying water")
	var repair_well: Dictionary = Runtime.request_repair(resumed, well, "body", 1)
	assert(repair_well.ok)
	var water_repair := _task(water_source, "repair")
	Runtime._feature_work(resumed, well, float(water_source.repair.work), Callable(), Callable(), water_repair, {}, 20, 1)
	assert(Runtime.feature_usable(water_source) and resumed.site.water_links.has(well))
	checks += 1

func _write_corrupt(valid_text: String, key: String, change: Callable, suffix: String) -> void:
	var wrapper: Dictionary = JSON.parse_string(valid_text)
	var payload: Dictionary = JSON.parse_string(str(wrapper.payload))
	change.call(payload.state.features[key])
	var body := JSON.stringify(payload, "", true, true)
	var file := FileAccess.open(SAVE + ".bad_" + suffix, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	file.close()
	assert(not Store.load_site(SAVE + ".bad_" + suffix).ok, "Corrupt new semantics accepted: " + suffix)

func _check_legacy_and_corrupt_saves() -> void:
	var data := _fixture(true)
	var key := _build(data, "weaver", Vector2i(13, 12))
	var feature: Dictionary = data.site.features[key]
	var recipe_set: Dictionary = Runtime.request_feature_recipe(data, key, "rope", 1)
	assert(recipe_set.ok)
	var saved_valid: Dictionary = Store.save(data, SAVE + ".valid")
	assert(saved_valid.ok)
	var valid_text := FileAccess.get_file_as_string(SAVE + ".valid")
	var live := JSON.stringify(data.site)
	_write_corrupt(valid_text, key, func(row: Dictionary) -> void: row.recipe_id = "steel", "wrong_recipe_kind")
	_write_corrupt(valid_text, key, func(row: Dictionary) -> void: row.recipe_id = 1, "recipe_type")
	_write_corrupt(valid_text, key, func(row: Dictionary) -> void: row.production = 0.1, "unpaid_progress")
	_write_corrupt(valid_text, key, func(row: Dictionary) -> void: row.merge({"batch_paid": true, "production": 8.1}, true), "past_recipe_cycle")
	_write_corrupt(valid_text, key, func(row: Dictionary) -> void: row.building_grade = 1.5, "fractional_grade")
	_write_corrupt(valid_text, key, func(row: Dictionary) -> void: row.civil_version = 2, "unknown_civil_version")
	_write_corrupt(valid_text, key, func(row: Dictionary) -> void: row.parts.body.hp = 101.0, "wrong_max_hp")
	assert(JSON.stringify(data.site) == live and FileAccess.get_file_as_string(SAVE + ".valid") == valid_text)
	feature.erase("recipe_id")
	feature.erase("civil_version")
	feature.erase("building_grade")
	feature.erase("parts")
	# A pre-civil save predates the fire layout too: fire_layout_version must go with the civil fields.
	# Keeping it made validate_feature_layout demand parts (site_runtime.gd:2041-2043), which is not a legacy state.
	feature.erase("fire_layout_version")
	assert(Runtime.validate_feature_layout(data, feature).ok and Runtime.feature_usable(feature))
	var saved_legacy: Dictionary = Store.save(data, SAVE + ".legacy")
	assert(saved_legacy.ok)
	var legacy_load := Store.load_site(SAVE + ".legacy")
	assert(legacy_load.ok, str(legacy_load))
	var old: Dictionary = legacy_load.data.site.features[key]
	assert(not old.has("civil_version") and not old.has("building_grade") and not old.has("parts"), "Loading an old building gave it new free durability")
	assert(Runtime.feature_recipe(old).input == {"fiber": 3} and Runtime.feature_geometry(legacy_load.data, old).blocked == old.cells)
	var legacy_upgrade: Dictionary = Runtime.request_upgrade(legacy_load.data, key, 1)
	assert(legacy_upgrade.ok)
	var pending: Dictionary = old.pending_build
	var builder := _task(old, "construct")
	Runtime._feature_work(legacy_load.data, key, float(pending.work), Callable(), Callable(), builder, {}, 20, 1)
	assert(int(old.civil_version) == 1 and int(old.building_grade) == 2 and float(old.parts.body.hp) == 150.0)
	assert(Runtime.validate_feature_layout(legacy_load.data, old).ok)
	checks += 1

func _check_real_workers_and_in_transit_guard() -> void:
	# This movement phase needs the existing flat contract fixture, not a save-base terrain projection.
	var data := _fixture()
	var key := _build(data, "weaver", Vector2i(13, 12))
	assert(Runtime.request_feature_recipe(data, key, "rope", 1).ok)
	assert(Runtime.operate_feature(data, key).ok)
	var feature: Dictionary = data.site.features[key]
	var entrance := data.cell_from_index(int(feature.entrance))
	var fixture := CrewFixture.new()
	fixture.setup(root, data, [entrance + Vector2i(-2, 2), entrance + Vector2i(0, 2), entrance + Vector2i(3, 2)])
	assert(fixture.army.command_eligible(fixture.army.current_commander), "Original commander must be present before worker assignment")
	var ids: Array[int] = [fixture.army.combat_identity(1), fixture.army.combat_identity(2)]
	var requester := fixture.army.combat_identity(0)
	var assigned: Dictionary = fixture.crew.assign(fixture.army, ids, requester)
	assert(assigned.ok, str(assigned))
	fixture.crew.advance(0.01)
	var first: Dictionary = fixture.army.combat_units[1]
	assert(first.work_task.target == "feature:" + key and fixture.army.moving_to[1] != TerrainArmy.INVALID_CELL, str({"task": first.work_task, "cell": fixture.army.cells[1], "moving_to": fixture.army.moving_to[1], "entrance": entrance, "walkable": data.is_walkable(entrance), "path": data.path_between(fixture.army.cells[1], entrance), "faction": fixture.army.faction_id, "owner": feature.owner_faction}))
	assert(float(feature.production) == 0.0 and not bool(feature.batch_paid), "A travelling original person worked remotely")
	_stop(data, key)
	var before := JSON.stringify(data.site)
	assert(not Runtime.request_feature_recipe(data, key, "wool_cloth", 1).ok and not Runtime.request_upgrade(data, key, 1).ok)
	assert(JSON.stringify(data.site) == before, "In-transit refusal changed existing worker or stock")
	fixture.crew.cancel(ids[0])
	fixture.crew.cancel(ids[1])
	fixture.army.prepare_combat(TerrainArmy.MOVE_DURATION + 0.00001)
	assert(Runtime.operate_feature(data, key).ok)
	assert(fixture.crew.assign(fixture.army, [ids[0]], requester).ok)
	var fiber := int(data.site.inventory.fiber)
	var rope := int(data.site.inventory.rope)
	var reached := false
	var carried := false
	for _step: int in range(120):
		fixture.tick(30.0)
		reached = reached or fixture.army.cells[1] == entrance
		carried = carried or int(first.cargo.get("rope", 0)) == 2
		if int(data.site.inventory.rope) > rope: break
	assert(reached and carried and int(data.site.inventory.rope) == rope + 2)
	assert(int(data.site.inventory.fiber) == fiber - 2 and first.cargo.is_empty())
	assert(PersonFatigue.read(first) > 0.0 and fixture.army.cells[1] != entrance, "Real worker did not own effort and return delivery")
	fixture.close()
	checks += 1
