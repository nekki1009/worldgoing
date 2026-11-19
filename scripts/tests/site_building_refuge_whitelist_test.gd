extends "res://scripts/tests/site_building_economy_upgrade_test.gd"
## Candidate only: reuse paid construction/work, original Army/terrain/Sustain.
const ArmyHelper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const RefugeSustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const APPROVED := ["house", "saltworks", "kiln", "charcoal", "smelter", "smithy", "tannery", "weaver", "fighting_position"]
const CLASSIFICATION_REJECTS := ["", "unknown_future_building", "prison", "stone_wall", "bridge", "dock", "shipyard", "tent", "camp_tent", "warehouse", "barracks", "training_ground", "road", "level", "farm", "fiber_farm", "fodder_farm", "pasture", "horse_ranch", "palisade", "well", "intake", "gate", "wall_stairs", "siege_ladder"]
var completed_groups := 0

func _run() -> void:
	create_timer(55.0).timeout.connect(func() -> void: quit(1))
	if not _approved_paid_features(): return
	if not _planned_and_building_features(): return
	if not _negative_kind_classification(): return
	if not _paid_prisons_and_other_facilities(): return
	if not _destroy_and_paid_repair_same_house(): return
	if not _original_entrance_guards(): return
	if not _legacy_house_and_edge_priority(): return
	TerrainArmy.release_contact_source()
	if not _refuge_check(completed_groups == 7): return
	print("SITE_BUILDING_REFUGE_WHITELIST_PASS: all 9 SOL-approved paid completed features with original geometry/Army; genuine planned/building house and fighting_position denied; explicit synthetic classification negatives; original paid prisons of neutral/same/other faction denied; genuine stone wall/warehouse/barracks denied; same original house body damage and paid repair restoration; unchanged original Actor/enemy-Army/unwalkable entrance guards; legacy house compatibility and true edge priority. Original Sustain collapse and coordinator steps for approved destinations; no Native refuge, GPU, save-file or production-clock claim.")
	quit(0)

func _refuge_fixture(sealed: bool = true) -> TerrainData:
	var data: TerrainData = _fixture(false)
	if not _refuge_check(data != null, "Parent fixture must return its original data"): return null
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
	var army: TerrainArmy = ArmyHelper.create_test_army(data, team_id, faction, 1, start)
	if not _refuge_check(army != null and army.data == data and army.combat_enabled and army.combat_units.size() == 1, "Shared helper must return the original successfully deployed army"): return null
	return army

func _expect_refuge(army: TerrainArmy, key: String, accepted: bool, label: String) -> bool:
	var before := JSON.stringify(army.data.site.features, "", true, true)
	var original_person := army.combat_identity(0)
	var found := {}
	var refuges := army._retreat_refuge_cells()
	for cell: Vector2i in refuges:
		var entry: Dictionary = refuges[cell]
		if str(entry.kind) == "building" and str(entry.target_id) == key:
			found[cell] = entry
	if not _refuge_check(not found.is_empty() == accepted, label): return false
	if accepted:
		var feature: Dictionary = army.data.site.features[key]
		var entrance := army.data.cell_from_index(int(feature.entrance))
		if not _refuge_check(found.has(entrance), label + ": original entrance missing"): return false
		for cell: Vector2i in found:
			if not _refuge_check(army.data.is_walkable(cell), label + ": unwalkable approach"): return false
			if not _refuge_check(cell == entrance or army.data.can_step(entrance, cell), label + ": illegal approach edge"): return false
			if bool(feature.solid):
				if not _refuge_check(not feature.cells.has(army.data.index(cell)), label + ": solid footprint became shelter"): return false
	if not _refuge_check(before == JSON.stringify(army.data.site.features, "", true, true) and original_person == army.combat_identity(0), label + ": selector mutated original feature/person"): return false
	return true

func _paid_planned(data: TerrainData, kind: String, extent: Vector2i = Vector2i.ONE, owner: int = 1) -> String:
	var settings := {"owner_faction": owner}
	var layout := Runtime.building_cells(data, kind, Vector2i(20, 20), extent, settings)
	if not _refuge_check(layout.ok): return ""
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var inventory: Dictionary = data.site.inventory.duplicate(true)
	var paid := Runtime.request_build(data, kind, cells, Callable(), settings)
	if not _refuge_check(paid.ok): return ""
	var key := str(paid.feature)
	var feature: Dictionary = data.site.features[key]
	if not _refuge_check(str(feature.stage) == "planned" and int(feature.owner_faction) == owner): return ""
	for item: String in feature.cost:
		if not _refuge_check(int(data.site.inventory[item]) == int(inventory.get(item, 0)) - int(feature.cost[item])): return ""
	return key

func _collapse_original_sustain(army: TerrainArmy) -> bool:
	var members := {}
	var checkpoints := {}
	for row: Dictionary in army.combat_units:
		members[int(row.person_id)] = row
		checkpoints[str(row.person_id)] = 0
	var state := RefugeSustain.create(Runtime.now(army.data) * 60.0)
	var added: Dictionary = RefugeSustain.add_members(state, members, members.keys())
	if not _refuge_check(added.ok): return false
	if not army.data.site.has("team_supply"): army.data.site["team_supply"] = {}
	army.data.site.team_supply[str(army.team_id)] = {"version": 1, "sustain": state, "inventory": {}, "training_order": false, "training_requester": -1, "revision": 0, "delivery": {}, "life_checkpoint": checkpoints}
	army.sustain_routed_query = func(original: TerrainArmy) -> bool: return bool(original.data.site.team_supply[str(original.team_id)].sustain.routed)
	var outcome := RefugeSustain.advance_to(state, members, {}, float(state.at) + 40.0 * RefugeSustain.HOUR)
	# Fixture clock alignment from the original tactical retreat test, not live time proof.
	army.data.site.minute = int(army.data.site.minute) + 2400
	if not _refuge_check(outcome.ok and outcome.routed_now and outcome.damage.is_empty() and army.is_sustain_routed()): return false
	return true

func _finish_original_retreat(army: TerrainArmy, expected: String, key: String = "") -> bool:
	var coordinator := SiteCombatMovementCoordinator.new()
	coordinator.register_formation(army)
	if not _collapse_original_sustain(army): return false
	var began: Dictionary = army.begin_morale_retreat()
	if not _refuge_check(began.ok): return false
	for _tick: int in range(200):
		var prior: Vector2i = army.cells[0]
		coordinator.combat_logic_tick_if_needed(0.5)
		army.prepare_combat(0.5)
		coordinator.complete_committed_moves()
		army.settle_combat_command()
		if not _refuge_check(army.cells[0] == prior or army.data.can_step(prior, army.cells[0]), "Original retreat crossed an illegal edge"): return false
		if army.morale_retreat_sheltered() or army.morale_retreat_terminal(): break
	if expected == "building":
		if not _refuge_check(army.morale_retreat_sheltered() and not bool(army.combat_hot_get(0, &"site_exited", false)) and not bool(army.combat_hot_get(0, &"surrender_pending", false))): return false
		var entry: Dictionary = army._retreat_refuge_cells().get(army.cells[0], {})
		if not _refuge_check(str(entry.get("kind", "")) == "building" and str(entry.get("target_id", "")) == key): return false
	elif expected == "edge":
		if not _refuge_check(bool(army.combat_hot_get(0, &"site_exited", false)) and army._edge_distance(army.cells[0]) == 0 and army.moving_to[0] == TerrainArmy.INVALID_CELL): return false
	else:
		if not _refuge_check(bool(army.combat_hot_get(0, &"surrender_pending", false)) and not bool(army.combat_hot_get(0, &"captive", false))): return false
	var captured: Dictionary = army.capture_combat_state()
	if not _refuge_check(TerrainArmy.valid_combat_state(captured, army.data)): return false
	coordinator.unregister_formation(army)
	return true

func _approved_paid_features() -> bool:
	if not _refuge_check(APPROVED.size() == 9): return false
	for kind: String in APPROVED:
		var data := _refuge_fixture()
		if _refuge_failed: return false
		if not _refuge_check(data != null, "Fixture helper must return a valid original object or key"): return false
		if kind == "saltworks": _add_sea(data)
		var inventory: Dictionary = data.site.inventory.duplicate(true)
		var key := _build(data, kind, Vector2i(20, 20))
		if _refuge_failed: return false
		if not _refuge_check(key is String and not str(key).is_empty(), "Fixture helper must return a valid original object or key"): return false
		var feature: Dictionary = data.site.features[key]
		for item: String in feature.cost:
			if not _refuge_check(int(data.site.inventory[item]) == int(inventory.get(item, 0)) - int(feature.cost[item]), kind + ": original cost was not paid"): return false
		var army := _new_refuge_army(data)
		if _refuge_failed: return false
		if not _refuge_check(army != null, "Fixture helper must return a valid original object or key"): return false
		if not _expect_refuge(army, key, true, "paid completed " + kind): return false
		if not _finish_original_retreat(army, "building", key): return false
		army.free()
	completed_groups += 1
	return true

func _planned_and_building_features() -> bool:
	for kind: String in ["house", "fighting_position"]:
		var data := _refuge_fixture()
		if _refuge_failed: return false
		if not _refuge_check(data != null, "Fixture helper must return a valid original object or key"): return false
		var key := _paid_planned(data, kind)
		if _refuge_failed: return false
		if not _refuge_check(key is String and not str(key).is_empty(), "Fixture helper must return a valid original object or key"): return false
		var feature: Dictionary = data.site.features[key]
		var army := _new_refuge_army(data)
		if _refuge_failed: return false
		if not _refuge_check(army != null, "Fixture helper must return a valid original object or key"): return false
		if not _refuge_check(str(feature.stage) == "planned"): return false
		if not _expect_refuge(army, key, false, kind + " planned"): return false
		var task := _task(feature, "construct")
		Runtime._feature_work(data, key, float(feature.work) * 0.5, Callable(), Callable(), task, {}, 20, 1)
		if not _refuge_check(str(feature.stage) == "building" and float(feature.progress) > 0.0 and float(feature.progress) < float(feature.work)): return false
		if not _expect_refuge(army, key, false, kind + " original partial construction"): return false
		Runtime._feature_work(data, key, float(feature.work) * 0.5, Callable(), Callable(), task, {}, 20, 1)
		if not _refuge_check(str(feature.stage) == "complete" and Runtime.validate_feature_layout(data, feature).ok): return false
		if not _expect_refuge(army, key, true, kind + " original completed construction"): return false
		army.free()
	completed_groups += 1
	return true

func _negative_kind_classification() -> bool:
	var data := _refuge_fixture()
	if _refuge_failed: return false
	if not _refuge_check(data != null, "Fixture helper must return a valid original object or key"): return false
	var key := _build(data, "house", Vector2i(20, 20))
	if _refuge_failed: return false
	if not _refuge_check(key is String and not str(key).is_empty(), "Fixture helper must return a valid original object or key"): return false
	var original: Dictionary = data.site.features[key]
	var army := _new_refuge_army(data)
	if _refuge_failed: return false
	if not _refuge_check(army != null, "Fixture helper must return a valid original object or key"): return false
	for kind: String in CLASSIFICATION_REJECTS:
		# Deliberate unvalidated selector input, never a legal saved/new built feature.
		var synthetic := original.duplicate(true)
		synthetic.kind = kind
		data.site.features[key] = synthetic
		if not _expect_refuge(army, key, false, "synthetic type classifier " + kind): return false
	data.site.features[key] = original
	if not _expect_refuge(army, key, true, "same original house after synthetic classification"): return false
	army.free()
	completed_groups += 1
	return true

func _paid_prisons_and_other_facilities() -> bool:
	for owner: int in [-1, 1, 2]:
		var data := _refuge_fixture()
		if _refuge_failed: return false
		if not _refuge_check(data != null, "Fixture helper must return a valid original object or key"): return false
		var key := _paid_planned(data, "prison", Vector2i(2, 2), owner)
		if _refuge_failed: return false
		if not _refuge_check(key is String and not str(key).is_empty(), "Fixture helper must return a valid original object or key"): return false
		var feature: Dictionary = data.site.features[key]
		var task := _task(feature, "construct")
		Runtime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, 20, owner)
		if not _refuge_check(str(feature.stage) == "complete" and int(feature.owner_faction) == owner and Runtime.validate_feature_layout(data, feature).ok): return false
		var army := _new_refuge_army(data)
		if _refuge_failed: return false
		if not _refuge_check(army != null, "Fixture helper must return a valid original object or key"): return false
		if not _expect_refuge(army, key, false, "paid prison owner " + str(owner)): return false
		if not _finish_original_retreat(army, "surrender"): return false
		army.free()
	for kind: String in ["stone_wall", "warehouse", "barracks"]:
		var data := _refuge_fixture()
		if _refuge_failed: return false
		if not _refuge_check(data != null, "Fixture helper must return a valid original object or key"): return false
		var key := _build(data, kind, Vector2i(20, 20), Vector2i(10, 10) if kind == "barracks" else Vector2i.ONE)
		if _refuge_failed: return false
		if not _refuge_check(key is String and not str(key).is_empty(), "Fixture helper must return a valid original object or key"): return false
		var army := _new_refuge_army(data)
		if _refuge_failed: return false
		if not _refuge_check(army != null, "Fixture helper must return a valid original object or key"): return false
		if not _expect_refuge(army, key, false, "paid unauthorized " + kind): return false
		army.free()
	completed_groups += 1
	return true

func _destroy_and_paid_repair_same_house() -> bool:
	var data := _refuge_fixture()
	if _refuge_failed: return false
	if not _refuge_check(data != null, "Fixture helper must return a valid original object or key"): return false
	var key := _build(data, "house", Vector2i(20, 20))
	if _refuge_failed: return false
	if not _refuge_check(key is String and not str(key).is_empty(), "Fixture helper must return a valid original object or key"): return false
	var feature: Dictionary = data.site.features[key]
	var cells: Array = feature.cells.duplicate()
	var entrance := int(feature.entrance)
	var army := _new_refuge_army(data)
	if _refuge_failed: return false
	if not _refuge_check(army != null, "Fixture helper must return a valid original object or key"): return false
	if not _expect_refuge(army, key, true, "original intact civil house"): return false
	var damaged_once: Dictionary = Runtime.damage_structure_part(data, key, "body", 40.0)
	if not _refuge_check(damaged_once.ok): return false
	if not _expect_refuge(army, key, true, "original nonzero damaged civil house"): return false
	var destroyed: Dictionary = Runtime.damage_structure_part(data, key, "body", 60.0)
	if not _refuge_check(destroyed.ok and float(feature.parts.body.hp) == 0.0 and str(feature.stage) == "complete"): return false
	if not _refuge_check(not Runtime.feature_usable(feature)): return false
	if not _expect_refuge(army, key, false, "original destroyed civil house"): return false
	var inventory: Dictionary = data.site.inventory.duplicate(true)
	var body_repair: Dictionary = Runtime.request_repair(data, key, "body", 1)
	if not _refuge_check(body_repair.ok): return false
	for item: String in feature.repair.cost:
		if not _refuge_check(int(data.site.inventory[item]) == int(inventory[item]) - int(feature.repair.cost[item])): return false
	var task := _task(feature, "repair")
	var work := float(feature.repair.work)
	Runtime._feature_work(data, key, work * 0.5, Callable(), Callable(), task, {}, 20, 1)
	if not _refuge_check(feature.has("repair") and float(feature.parts.body.hp) == 0.0): return false
	if not _expect_refuge(army, key, false, "original paid repair not yet completed"): return false
	Runtime._feature_work(data, key, work * 0.5, Callable(), Callable(), task, {}, 20, 1)
	if not _refuge_check(not feature.has("repair") and float(feature.parts.body.hp) == Runtime.civil_max_hp(feature) and feature.cells == cells and int(feature.entrance) == entrance): return false
	# Original body collapse also destroyed its supported roof; body repair is not full service restoration.
	if not _refuge_check(feature.parts.has("roof") and float(feature.parts.roof.hp) == 0.0): return false
	if not _refuge_check(Runtime.feature_function_state(feature) == "DISABLED" and not Runtime.feature_usable(feature)): return false
	if not _expect_refuge(army, key, false, "original body repaired but required roof still destroyed"): return false
	inventory = data.site.inventory.duplicate(true)
	var roof_repair: Dictionary = Runtime.request_repair(data, key, "roof", 1)
	if not _refuge_check(roof_repair.ok, str(roof_repair)): return false
	for item: String in feature.repair.cost:
		if not _refuge_check(int(data.site.inventory[item]) == int(inventory[item]) - int(feature.repair.cost[item])): return false
	task = _task(feature, "repair")
	work = float(feature.repair.work)
	Runtime._feature_work(data, key, work * 0.5, Callable(), Callable(), task, {}, 20, 1)
	if not _refuge_check(feature.has("repair") and float(feature.parts.roof.hp) == 0.0): return false
	if not _expect_refuge(army, key, false, "original paid roof repair not yet completed"): return false
	Runtime._feature_work(data, key, work * 0.5, Callable(), Callable(), task, {}, 20, 1)
	var restored_geometry: Dictionary = Runtime.feature_geometry(data, feature)
	if not _refuge_check(not feature.has("repair") and float(feature.parts.roof.hp) == float(restored_geometry.parts.roof.max_hp)): return false
	if not _refuge_check(float(feature.parts.body.hp) == Runtime.civil_max_hp(feature) and feature.cells == cells and int(feature.entrance) == entrance): return false
	if not _refuge_check(Runtime.feature_usable(feature), "Same original house is usable only after all required paid repairs"): return false
	if not _expect_refuge(army, key, true, "same original house after original repair completion"): return false
	if not _finish_original_retreat(army, "building", key): return false
	army.free()
	completed_groups += 1
	return true

func _original_entrance_guards() -> bool:
	var data := _refuge_fixture()
	if _refuge_failed: return false
	if not _refuge_check(data != null, "Fixture helper must return a valid original object or key"): return false
	var key := _build(data, "house", Vector2i(20, 20))
	if _refuge_failed: return false
	if not _refuge_check(key is String and not str(key).is_empty(), "Fixture helper must return a valid original object or key"): return false
	var entrance := data.cell_from_index(int(data.site.features[key].entrance))
	var army := _new_refuge_army(data)
	if _refuge_failed: return false
	if not _refuge_check(army != null, "Fixture helper must return a valid original object or key"): return false
	var actor := TerrainTestCharacter.new()
	actor.data = data
	actor.terrain_cell = entrance
	actor.faction_id = 2
	army.npc = actor
	if not _expect_refuge(army, key, false, "original hostile Actor at entrance"): return false
	army.npc = null
	actor.free()
	var coordinator := SiteCombatMovementCoordinator.new()
	var enemy := _new_refuge_army(data, 42, 2, entrance)
	if _refuge_failed: return false
	if not _refuge_check(enemy != null, "Fixture helper must return a valid original object or key"): return false
	coordinator.register_formation(army)
	coordinator.register_formation(enemy)
	if not _expect_refuge(army, key, false, "original hostile Army at entrance"): return false
	coordinator.unregister_formation(enemy)
	enemy.free()
	coordinator.unregister_formation(army)
	if not _expect_refuge(army, key, true, "same original house after enemy leaves"): return false
	data.flags[data.index(entrance)] = 0
	Runtime.rebuild_terrain_edges(data)
	if not _expect_refuge(army, key, false, "original unwalkable entrance"): return false
	data.flags[data.index(entrance)] = TerrainData.Flag.WALKABLE
	Runtime.rebuild_terrain_edges(data)
	if not _expect_refuge(army, key, true, "same original house with reopened entrance"): return false
	army.free()
	completed_groups += 1
	return true

func _legacy_house_and_edge_priority() -> bool:
	var data := _refuge_fixture(false)
	if _refuge_failed: return false
	if not _refuge_check(data != null, "Fixture helper must return a valid original object or key"): return false
	var key := _build(data, "house", Vector2i(20, 20))
	if _refuge_failed: return false
	if not _refuge_check(key is String and not str(key).is_empty(), "Fixture helper must return a valid original object or key"): return false
	var army := _new_refuge_army(data)
	if _refuge_failed: return false
	if not _refuge_check(army != null, "Fixture helper must return a valid original object or key"): return false
	# Explicit legacy classifier evidence, separate from the paid-layout assertions above.
	var legacy: Dictionary = data.site.features[key].duplicate(true)
	for field: String in ["civil_version", "building_grade", "fire_layout_version", "parts"]: legacy.erase(field)
	var legacy_storage: Dictionary = Runtime.validate_feature_layout(data, legacy)
	if not _refuge_check(legacy_storage.ok, "A real legacy fixture must satisfy the original saved feature layout: " + str(legacy_storage)): return false
	if not _refuge_check(Runtime.feature_service_dependencies(legacy).is_empty(), "Legacy has no invented modern Fire dependencies"): return false
	data.site.features[key] = legacy
	if not _expect_refuge(army, key, true, "original legacy house compatibility"): return false
	if not _finish_original_retreat(army, "edge"): return false
	army.free()
	completed_groups += 1
	return true

var _refuge_failed := false

func _refuge_check(condition: bool, message: String = "Building refuge contract failed") -> bool:
	if _refuge_failed: return false
	var engine_error: String = _refuge_errors.first_error()
	if not engine_error.is_empty():
		_refuge_failed = true
		push_error("BUILDING_REFUGE_SCRIPT_FAIL: " + engine_error)
		quit(1)
		return false
	checks += 1
	if condition: return true
	_refuge_failed = true
	push_error(message)
	quit(1)
	return false

func _build(data: TerrainData, kind: String, anchor: Vector2i, size: Vector2i = Vector2i.ONE, options: Dictionary = {}) -> String:
	var selected: Dictionary = options.duplicate()
	selected["owner_faction"] = 1
	var layout: Dictionary = Runtime.building_cells(data, kind, anchor, size, selected)
	if not _refuge_check(layout.ok, str(layout)): return ""
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var result: Dictionary = Runtime.request_build(data, kind, cells, Callable(), selected)
	if not _refuge_check(result.ok, str(result)): return ""
	var key: String = str(result.feature)
	var feature: Dictionary = data.site.features[key]
	var task: Dictionary = _task(feature, "construct")
	Runtime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	if not _refuge_check(str(feature.stage) == "complete", str(task)): return ""
	return key

class RefugeErrors extends Logger:
	var _mutex := Mutex.new()
	var _first := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		# Logger callbacks may run off-thread; main-loop checks perform the quit.
		_mutex.lock()
		if _first.is_empty(): _first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]
		_mutex.unlock()

	func first_error() -> String:
		_mutex.lock()
		var result := _first
		_mutex.unlock()
		return result

var _refuge_errors := RefugeErrors.new()

func _initialize() -> void:
	OS.add_logger(_refuge_errors)
	super._initialize()

func _finalize() -> void:
	OS.remove_logger(_refuge_errors)

func _process(_delta: float) -> bool:
	if not _refuge_check(true): return false
	return false
