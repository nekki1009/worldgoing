extends "res://scripts/tests/site_building_ui_test.gd"
## SETTLEMENT_CENTER_LEVELS_PLAN P0 contract. Named checks print as they pass.

const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const SETTLEMENT_SAVE := "res://.godot-temp/site_settlement_center_20261007/settlement.json"
const LEGACY_SAVE := "res://.godot-temp/site_settlement_center_20261007/legacy.json"
const CENTER_ANCHOR := Vector2i(20, 20)
var passed: Array[String] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 110000
	_run.call_deferred()

func _pass(name: String) -> void:
	passed.append(name)
	print("SETTLEMENT_CHECK_PASS ", name)

func _center_cells(data: TerrainData, anchor: Vector2i = CENTER_ANCHOR) -> Array[int]:
	var placement := Runtime.building_cells(data, "settlement_center", anchor, Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	assert(placement.ok, str(placement))
	var cells: Array[int] = []
	cells.assign(placement.cells)
	return cells

func _upgrade_house(data: TerrainData, key: String) -> void:
	var upgraded := Runtime.request_upgrade(data, key, 1)
	assert(upgraded.ok, str(upgraded))
	_complete_key(data, key)

func _register(data: TerrainData, people: Array[int], houses: Array[String]) -> Dictionary:
	var relations := {}
	var slot_list: Array[Dictionary] = []
	for key: String in houses:
		var layout := Runtime.house_layout(data, key)
		assert(layout.ok, str(layout))
		for cell: int in layout.slots: slot_list.append({"house_id": key, "cell": cell})
	assert(slot_list.size() >= people.size(), "Fixture houses must hold every original resident")
	for index: int in range(people.size()):
		relations[str(people[index])] = {"version": 1, "house_id": str(slot_list[index].house_id), "cell": int(slot_list[index].cell)}
	return relations

func _json_equal(left: Variant, right: Variant) -> bool:
	return JSON.stringify(JSON.parse_string(JSON.stringify(left)), "", true) == JSON.stringify(JSON.parse_string(JSON.stringify(right)), "", true)

func _people_projection(lab: TerrainLab) -> Dictionary:
	var people := {}
	for actor: TerrainTestCharacter in lab.combat_actors: people[int(actor.person_id)] = {"_housing_faction": int(actor.faction_id)}
	for team: TerrainArmy in lab.combat_armies:
		for unit in range(team.combat_units.size()): people[team.combat_identity(unit)] = {"_housing_faction": int(team.faction_id)}
	return people

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var founder := int(lab.character.person_id)
	var team: TerrainArmy = lab.army
	team.roster_size = 12
	team.faction_id = 1
	var rows: Array[Vector2i] = []
	for x: int in range(10, 22): rows.append(Vector2i(x, 48))
	assert(team.deploy_at(data, lab.character, lab.npc, rows) and team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	var residents: Array[int] = []
	for unit in range(team.combat_units.size()): residents.append(team.combat_identity(unit))

	# 1. Legacy / un-founded Site: no record, original upgrade rules, bit-stable store.
	var house_a := _formal_feature(data, "house", Vector2i(12, 30), Vector2i.ONE, {"variant": "standard"})
	var house_b := _formal_feature(data, "house", Vector2i(12, 36), Vector2i.ONE, {"variant": "standard"})
	_upgrade_house(data, house_a)
	assert(Runtime.building_grade(data.site.features[house_a]) == 2)
	assert(Runtime.request_upgrade(data, house_a, 1, Callable(), true).ok, "Un-founded Site keeps grade 3 upgrades")
	assert(controller.settlement_grade_cap(data.site.features[house_b]) == Runtime.CIVIL_MAX_GRADE)
	controller._capture_positions()
	var legacy: Dictionary = data.site.duplicate(true)
	assert(not legacy.has("settlement") and Store._validate_state(data, legacy).ok)
	var normalized := legacy.duplicate(true)
	Settlement.normalize(normalized)
	assert(normalized == legacy, "Legacy normalization adds nothing")
	var legacy_saved := Store.save(data, LEGACY_SAVE)
	assert(legacy_saved.ok, str(legacy_saved))
	var legacy_loaded := Store.load_site(LEGACY_SAVE)
	assert(legacy_loaded.ok and not legacy_loaded.data.site.has("settlement") and _json_equal(legacy_loaded.data.site.features, data.site.features), str(legacy_loaded.get("message", "")))
	_pass("legacy_load_unchanged")

	# 2. Formal entry: build window choice; missing formal art is an explicit refusal.
	assert(controller._building_choice("settlement_center") >= 0, "Construction window lists the settlement center")
	var probe := {"kind": "settlement_center", "layout_version": 1, "quarter": 0}
	assert(controller.view.building_art_key(probe) == "settlement_center_l1_south")
	if not controller.view.building_art_available(probe):
		_choose(controller, "settlement_center", CENTER_ANCHOR, Vector2i(5, 5))
		controller.build_cells = _center_cells(data)
		var before_features: Dictionary = data.site.features.duplicate(true)
		controller.build_selected()
		assert(not data.site.has("settlement") and data.site.features == before_features, "Missing formal art refuses founding without placeholder")
		assert(str(controller.message.text).contains("美術"), str(controller.message.text))
		_pass("missing_art_explicit_refusal")
	else:
		_pass("formal_art_present")

	# 3. Founding: the head must be present; direct Runtime builds are refused.
	var far := Settlement.found(lab, founder, _center_cells(data, Vector2i(40, 40)))
	assert(not far.ok and str(far.code) == "TOO_FAR", str(far))
	assert(not Runtime.request_build(data, "settlement_center", _center_cells(data), Callable(), {"layout_version": 1, "quarter": 0, "owner_faction": 1}).ok)
	assert(not Settlement.found(lab, residents[0], _center_cells(data)).ok, "Only the controlled founder may found")
	var wood_before := int(data.site.inventory.wood)
	var founded := Settlement.found(lab, founder, _center_cells(data), {"layout_version": 1, "quarter": 0}, Callable(), "河口聚落")
	assert(founded.ok, str(founded))
	var center_key := str(founded.feature)
	assert(int(data.site.inventory.wood) == wood_before - 30)
	var record: Dictionary = data.site.settlement
	assert(int(record.level) == 0 and str(record.center_id) == center_key and int(record.owner_faction) == 1)
	assert(int(SiteOffices.head_position(record.offices).holder) == founder and record.offices.duty_ai == false, "Player founder holds the head seat; duty AI defaults off")
	assert(not Settlement.found(lab, founder, _center_cells(data, Vector2i(30, 40))).ok, "One center per Site")
	assert(not Runtime.preview_build(data, "settlement_center", _center_cells(data, Vector2i(30, 40))).ok)
	assert(Settlement.status(lab).effective == false and Settlement.status(lab).reasons.has("中心尚未完工"))
	_complete_key(data, center_key)
	assert(int(record.level) == 1 and bool(Settlement.status(lab).effective), str(Settlement.status(lab)))
	assert(Settlement.radius(1) == 12 and Settlement.cell_in_jurisdiction(data, Vector2i(36, 22)) and not Settlement.cell_in_jurisdiction(data, Vector2i(37, 22)))
	assert(not Runtime.cancel_feature(data, center_key, Callable(), 1).ok, "A founded center cannot be demolished")
	_pass("found_level_1")

	# 4. Grade cap: only new upgrades are capped; grade 2 already built stays.
	assert(Runtime.building_grade(data.site.features[house_a]) == 2)
	var capped := Runtime.request_upgrade(data, house_b, 1, Callable(), true)
	assert(not capped.ok and str(capped.code) == "SETTLEMENT_LEVEL", str(capped))
	assert(str(Runtime.request_upgrade(data, house_a, 1, Callable(), true).code) == "SETTLEMENT_LEVEL")
	_pass("grade_cap_level_1")

	# 5. Upgrade refused while people / buildings / materials are missing.
	var short := Settlement.request_upgrade(lab, founder)
	assert(not short.ok and str(short.code) == "REQUIREMENTS" and str(short.message).contains("登記居民 0／12"), str(short))
	assert(str(Settlement.request_upgrade(lab, residents[0]).code) == "NO_AUTHORITY", "Only the head may order the upgrade")
	var houses: Array[String] = []
	for anchor: Vector2i in [Vector2i(26, 8), Vector2i(32, 8), Vector2i(26, 28), Vector2i(32, 28)]:
		houses.append(_formal_feature(data, "house", anchor, Vector2i.ONE, {"variant": "large"}))
	_formal_feature(data, "well", Vector2i(28, 20))
	_formal_feature(data, "farm", Vector2i(12, 14), Vector2i(2, 2))
	data.site.housing = _register(data, residents, houses)
	assert(Settlement.residents(lab).size() == 12, str(Settlement.residents(lab)))
	var stock := int(data.site.inventory.pottery)
	data.site.inventory.pottery = 0
	var no_materials := Settlement.request_upgrade(lab, founder)
	assert(not no_materials.ok and str(no_materials.message).contains("材料"), str(no_materials))
	data.site.inventory.pottery = stock
	_pass("upgrade_requirements_refused")

	# 6. In-place paid upgrade through pending_build; cancel refunds by unused share.
	var inventory_before: Dictionary = data.site.inventory.duplicate()
	var center: Dictionary = data.site.features[center_key]
	var cells_before: Array = center.cells.duplicate()
	var entrance_before := int(center.entrance)
	var upgrade := Settlement.request_upgrade(lab, founder)
	assert(upgrade.ok and int(center.pending_build.target_level) == 2, str(upgrade))
	assert(int(data.site.inventory.rope) == int(inventory_before.rope) - 4 and int(data.site.inventory.pottery) == int(inventory_before.pottery) - 4)
	controller._capture_positions()
	assert(Store._validate_state(data, data.site.duplicate(true)).ok, "A pending level upgrade is a valid save")
	assert(Runtime.cancel_feature(data, center_key, Callable(), 1).ok and not center.has("pending_build"))
	assert(data.site.inventory == inventory_before and int(record.level) == 1)
	assert(Settlement.request_upgrade(lab, founder).ok)
	_complete_key(data, center_key)
	assert(int(record.level) == 2 and center.cells == cells_before and int(center.entrance) == entrance_before and str(center.kind) == "settlement_center")
	assert(str(SiteOffices.head_position(record.offices).name) == "村長" and Settlement.radius(2) == 20)
	assert(bool(Settlement.status(lab).effective))
	assert(Runtime.request_upgrade(data, house_b, 1, Callable(), true).ok, "Level 2 allows grade 2")
	assert(str(Runtime.request_upgrade(data, house_a, 1, Callable(), true).code) == "SETTLEMENT_LEVEL", "Level 2 still blocks grade 3")
	_pass("upgrade_level_2_in_place")

	# 7. Suspension and recovery: population below threshold, center body at 0.
	var saved_relation: Dictionary = data.site.housing[str(residents[11])]
	data.site.housing.erase(str(residents[11]))
	var suspended := Settlement.status(lab)
	assert(not bool(suspended.effective) and int(suspended.level) == 2 and str(suspended.reasons).contains("11／12"), str(suspended))
	assert(str(Runtime.request_upgrade(data, house_b, 1, Callable(), true).code) == "SETTLEMENT_LEVEL", "Suspended settlement pauses its grade effect")
	data.site.housing[str(residents[11])] = saved_relation
	assert(bool(Settlement.status(lab).effective))
	assert(Runtime.damage_structure_part(data, center_key, "body", float(center.parts.body.hp)).ok)
	assert(not bool(Settlement.status(lab).effective) and int(record.level) == 2 and data.site.features.has(center_key), "Destroyed center only suspends")
	var repair := Runtime.request_repair(data, center_key, "body", 1)
	assert(repair.ok, str(repair))
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + center_key, "action": "repair", "cell": int(center.repair.work_cell)}))
	data.site.worker.cell = int(center.repair.work_cell)
	data.site.worker.mode = "work"
	Runtime.advance(data, float(center.repair.work) + 1.0, true, false, Callable(), Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1)
	data.site.worker.mode = "idle"
	assert(not center.has("repair") and bool(Settlement.status(lab).effective), str(Settlement.status(lab)))
	_pass("suspend_and_recover")

	# 8. Level 3 still needs 40 residents and new buildings.
	var level_3 := Settlement.next_level(lab)
	assert(not bool(level_3.ok) and int(level_3.target) == 3 and str(level_3.missing).contains("12／40") and str(level_3.missing).contains("倉庫 0／1"), str(level_3))
	_pass("level_3_requirements_reported")

	# 9. Strict store contract.
	controller._capture_positions()
	var valid: Dictionary = data.site.duplicate(true)
	assert(Store._validate_state(data, valid).ok)
	var corrupt_cases := {
		"level_4": func(state: Dictionary) -> void: state.settlement.level = 4,
		"level_text": func(state: Dictionary) -> void: state.settlement.level = "2",
		"level_mismatch": func(state: Dictionary) -> void: state.settlement.level = 3,
		"missing_center": func(state: Dictionary) -> void: state.settlement.center_id = "999",
		"duplicate_center": func(state: Dictionary) -> void:
			var copy: Dictionary = state.features[center_key].duplicate(true)
			state.features[str(state.next_feature)] = copy
			state.next_feature = int(state.next_feature) + 1,
		"orphan_center": func(state: Dictionary) -> void: state.erase("settlement"),
		"owner_mismatch": func(state: Dictionary) -> void: state.settlement.owner_faction = 7,
		"unknown_field": func(state: Dictionary) -> void: state.settlement["population"] = 12,
		"bad_version": func(state: Dictionary) -> void: state.settlement.version = 2,
		"bad_timer": func(state: Dictionary) -> void: state.settlement.fall_record.contest_seconds = 61.0,
	}
	for case: String in corrupt_cases:
		var corrupt := valid.duplicate(true)
		corrupt_cases[case].call(corrupt)
		assert(not Store._validate_state(data, corrupt).ok, "Corrupt settlement accepted: " + case)
	var settlement_saved := Store.save(data, SETTLEMENT_SAVE)
	assert(settlement_saved.ok, str(settlement_saved))
	var settlement_loaded := Store.load_site(SETTLEMENT_SAVE)
	assert(settlement_loaded.ok and _json_equal(settlement_loaded.data.site.settlement, data.site.settlement), str(settlement_loaded.get("message", "")))
	assert(settlement_loaded.data.site.settlement.level is int and settlement_loaded.data.site.settlement.owner_faction is int)
	_pass("store_strict_and_roundtrip")

	# 10. Settlement page (formal UI).
	controller._open_settlement()
	assert(controller._ui_dialogs.has("settlement"))
	var summary := lab.find_child("SettlementSummary", true, false) as Label
	assert(summary != null and summary.text.contains("2 級村") and summary.text.contains("登記居民 12"), summary.text if summary != null else "")
	assert(lab.find_child("SettlementUpgrade", true, false) != null)
	_pass("settlement_page")

	# 11. Capture: timer, interruption, completion, faction scope, residents.
	var third := _formal_feature(data, "house", Vector2i(44, 20), Vector2i.ONE, {"variant": "small"})
	data.site.features[third].owner_faction = 3 # Fixture: an unregistered third-party house in jurisdiction.
	var outside := _formal_feature(data, "house", Vector2i(47, 46), Vector2i.ONE, {"variant": "small"})
	assert(Settlement.feature_in_jurisdiction(data, data.site.features[third]) and not Settlement.feature_in_jurisdiction(data, data.site.features[outside]))
	var attackers := TerrainArmy.new()
	root.add_child(attackers)
	attackers.set_process(false)
	attackers.team_id = 9
	attackers.faction_id = 2
	attackers.roster_size = 2
	var attack_cells: Array[Vector2i] = [Vector2i(20, 18), Vector2i(21, 18)]
	assert(attackers.deploy_at(data, null, null, attack_cells) and attackers.enable_combat(false))
	lab.combat_armies.append(attackers)
	var zone := Settlement.capture_zone(data)
	assert(zone.has(Vector2i(20, 18)) and not zone.has(Vector2i(20, 20)))
	assert(Settlement.advance_capture(lab, 30.0).is_empty())
	assert(int(record.fall_record.contest_faction) == 2 and is_equal_approx(float(record.fall_record.contest_seconds), 30.0))
	assert(lab.npc.place(Vector2i(19, 19), true))
	assert(Settlement.advance_capture(lab, 30.0).is_empty())
	assert(int(record.fall_record.contest_faction) == -1 and float(record.fall_record.contest_seconds) == 0.0, "A conscious defender interrupts the timer")
	assert(lab.npc.place(Vector2i(10, 9), true))
	assert(Settlement.advance_capture(lab, 59.0).is_empty() and int(record.fall_record.contest_faction) == 2)
	var houses_before: int = data.site.housing.size()
	var fallen := Settlement.advance_capture(lab, 1.5)
	assert(not fallen.is_empty() and fallen.ok, str(fallen))
	_pass("capture_timer_interrupt_and_complete")
	assert(int(record.owner_faction) == 2 and int(data.site.features[center_key].owner_faction) == 2)
	for key: String in houses: assert(int(data.site.features[key].owner_faction) == 2)
	assert(int(data.site.features[third].owner_faction) == 3, "Third-party buildings keep their owner")
	assert(int(data.site.features[outside].owner_faction) == 1, "Buildings outside jurisdiction keep their owner")
	assert(int(record.level) == 2 and not bool(Settlement.status(lab).effective), "Level kept; new faction lacks residents")
	_pass("capture_faction_scope")
	assert(houses_before == 12 and data.site.housing.is_empty() and Settlement.residents(lab).is_empty())
	for unit in range(team.combat_units.size()): assert(int(team.faction_id) == 1 and float(team.combat_hot_get(unit, &"hp")) > 0.0, "Residents keep their own faction")
	_pass("capture_releases_residents")
	var leader := int(SiteOffices.head_position(record.offices).holder)
	assert(leader == attackers.combat_identity(0) and int(record.fall_record.last_fall.from) == 1 and int(record.fall_record.last_fall.to) == 2)
	assert(record.offices.duty_ai == true, "NPC provisional head defaults duty AI on")
	assert(Settlement.validate(data, data.site, _people_projection(lab)).ok)
	_pass("capture_provisional_head")

	lab.combat_armies.erase(attackers)
	attackers.free()
	controller.invalidate_ui_context()
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_SETTLEMENT_CENTER_PASS: %d named checks: %s" % [passed.size(), ", ".join(passed)])
	quit(0)
