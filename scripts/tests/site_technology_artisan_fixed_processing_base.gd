extends "res://scripts/tests/site_technology_artisan_fixed_siege_base.gd"
## Candidate TRUE fixed-source G06/D10 F04/F06. No generated production input.
## The new checksum-pinned source rule is an explicit isolated acceptance input,
## original geography/assets remain identical; rule/provider requires Eco/Region
## review and is not the default Taiwan source or a measured soil claim.
const LAND_RULE := "terrain_mapped_potential_v1"
var _legacy_manifest_path := ""
var _legacy_source: RegionData
var _legacy_source_sha := ""
var _source_rule_report: Dictionary = {}

func _bounds(field: PackedByteArray) -> Vector2i:
	var result := Vector2i(255, 0)
	for value: int in field:
		result.x = mini(result.x, value)
		result.y = maxi(result.y, value)
	return result

func _write_source(path: String, body: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_require(file != null, "Named candidate source file can be written")
	file.store_string(JSON.stringify(body, "", true, true))
	file.close()

func _g06_source() -> RegionData:
	_legacy_source = _fixed_source() # Original checksummed helper is unchanged.
	_require(_legacy_source != null, "True original legacy fixed geographic source")
	_legacy_manifest_path = manifest_path
	_legacy_source_sha = FileAccess.get_sha256(_legacy_manifest_path)
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var candidate: Dictionary = original.duplicate(true)
	candidate.base_revision = "g06-fixed-potential-candidate-v3"
	candidate["land_condition_rule"] = LAND_RULE
	candidate.sources.append({"title": "Isolated accepted game potential rule; original fixed terrain, not surveyed soil"})
	var source := RegionData.new()
	var path := root_path.path_join("manifest.potential.v3.json")
	_write_source(path, candidate)
	_require(source.load_manifest(path).ok, "Actual RegionData admits exact candidate source rule")
	var accepted_manifest: PackedByteArray = var_to_bytes(source.manifest)
	var accepted_hash := source.manifest_hash
	for invalid: Variant in [false, 1, [], {}, "", "unknown_potential_v1", "mapped_terrain_potential_v1"]:
		var malformed: Dictionary = candidate.duplicate(true)
		malformed.land_condition_rule = invalid
		var bad_path := root_path.path_join("manifest.bad.v3.json")
		_write_source(bad_path, malformed)
		var rejected: Dictionary = source.load_manifest(bad_path)
		_require(not rejected.ok and source.manifest_hash == accepted_hash and var_to_bytes(source.manifest) == accepted_manifest, "Malformed present source rule rejects before original source publication", rejected)
	var same_fields: Dictionary = candidate.duplicate(true)
	same_fields.erase("land_condition_rule")
	same_fields.base_revision = original.base_revision
	same_fields.sources = original.sources.duplicate(true)
	_require(same_fields == original and FileAccess.get_sha256(_legacy_manifest_path) == _legacy_source_sha, "All original geography/assets and old manifest bytes remain unchanged")
	var old_base: Dictionary = _legacy_source.make_terrain_data(START.x, START.y)
	var new_base: Dictionary = source.make_terrain_data(START.x, START.y)
	_require(old_base.ok and new_base.ok, "Both original fixed sources rebuild through original Adapter")
	var old_data: TerrainData = old_base.data
	var data: TerrainData = new_base.data
	_require(old_data.fingerprint() == data.fingerprint() and old_data.water_kind == data.water_kind and old_data.water_body == data.water_body and old_data.resource_base == data.resource_base, "Rule changes no geographic fingerprint, true water or resource source")
	Env.initialize(old_data, "g06-legacy-rule-proof")
	Env.initialize(data, "g06-potential-rule-proof")
	_require(_bounds(old_data.foundation).x == 0 and _bounds(old_data.foundation).y == 0 and _bounds(old_data.groundwater).y == 0 and _bounds(old_data.moisture).y == 0, "Old fixed source keeps original five-zero eligibility/moisture behavior")
	_require(data.parameters.fixed_base.land_condition_rule == LAND_RULE and data.parameters.fixed_land_condition_rule == LAND_RULE and _bounds(data.foundation).x >= 35 and _bounds(data.groundwater).x >= 35, "Real source-pinned Env potential supplies lawful foundation and groundwater")
	_require(data.moisture != old_data.moisture, "New named source intentionally changes original moisture game potential; existing Fire/Eco reads this actual field")
	_source_rule_report = {"legacy_manifest_sha256": _legacy_source_sha, "candidate_manifest_sha256": accepted_hash, "base_revision": str(candidate.base_revision), "rule": LAND_RULE,
		"geographic_fingerprint_unchanged_not_rule_proof": data.fingerprint(), "new_moisture_min": _bounds(data.moisture).x, "new_moisture_max": _bounds(data.moisture).y, "legacy_moisture": 0,
		"Eco_Fire_behavior_change_intentional_source_candidate": true, "Taiwan_resource_pair_release_not_claimed": true}
	manifest_path = path
	return source

func _cold_rule_guards(f: Dictionary) -> void:
	_idle_all(f)
	var controller: SiteController = f.lab.site_controller
	_require(controller.save_to(controller.save_path).ok, "Actual full-pin original scene checkpoint before cold-rule negatives")
	var path: String = controller.region_slot.site_path(START)
	var decoded: Dictionary = Store._read(path)
	_require(decoded.ok, "Original checksummed payload decoder")
	var original_hash := FileAccess.get_sha256(path)
	var pin_before: PackedByteArray = var_to_bytes(f.data.site.world_pin)
	var scene_before: PackedByteArray = var_to_bytes([f.data.site, f.team.capture_combat_state(), f.data.parameters])
	for attack: String in ["parameter_only", "erase_parameter", "downgrade", "erase_both", "mismatch_base"]:
		var payload: Dictionary = decoded.payload.duplicate(true)
		match attack:
			"parameter_only": payload.parameters.fixed_land_condition_rule = "unknown_potential_v1"
			"erase_parameter": payload.parameters.erase("fixed_land_condition_rule")
			"downgrade": payload.parameters.fixed_land_condition_rule = ""
			"erase_both":
				payload.parameters.erase("fixed_land_condition_rule")
				payload.parameters.fixed_base.erase("land_condition_rule")
			"mismatch_base": payload.parameters.fixed_base.land_condition_rule = "unknown_potential_v1"
		var body := JSON.stringify(payload, "", true, true)
		var bad_path := root_path.path_join("cold_rule_" + attack + ".json")
		_write_source(bad_path, {"checksum": body.sha256_text(), "payload": body})
		var loader := func(base: Dictionary) -> Dictionary: return f.source.make_terrain_data(START.x, START.y)
		var rejected: Dictionary = Store.load_site(bad_path, loader, 1, true)
		_require(not rejected.ok and rejected.code == "SAVE_VERSION" and FileAccess.get_sha256(path) == original_hash and var_to_bytes([f.data.site, f.team.capture_combat_state(), f.data.parameters]) == scene_before, "Checksum-valid malicious rule packet rejects atomically: " + attack, rejected)
	for invalid: Variant in ["unknown_potential_v1", false, StringName(LAND_RULE)]:
		var loader := func(base: Dictionary) -> Dictionary: return f.source.make_terrain_data(START.x, START.y)
		var original_copy: Dictionary = Store.load_site(path, loader, 1, true)
		_require(original_copy.ok, "Direct-save negative starts with true original full-pin checked cold copy")
		var malformed_data: TerrainData = original_copy.data
		malformed_data.parameters.fixed_base.land_condition_rule = invalid
		malformed_data.parameters.fixed_land_condition_rule = invalid
		var target := root_path.path_join("save_invalid_rule_" + str(typeof(invalid)) + ".json")
		var refused: Dictionary = Store.save(malformed_data, target)
		_require(not refused.ok and refused.code == "SAVE_VERSION" and not FileAccess.file_exists(target) and FileAccess.get_sha256(path) == original_hash and var_to_bytes([f.data.site, f.team.capture_combat_state(), f.data.parameters]) == scene_before, "Matching malformed base/parameter values cannot create a save or change original scene", refused)
	_require(var_to_bytes(f.data.site.world_pin) == pin_before and FileAccess.get_sha256(_legacy_manifest_path) == _legacy_source_sha, "No erased/minimal pin or rewritten old source in any negative")
	_cold_resume(f, "source_rule_checked")
	_require(f.data.parameters.fixed_base.land_condition_rule == LAND_RULE and f.data.parameters.fixed_land_condition_rule == LAND_RULE and f.data.site.world_pin.manifest_sha256 == f.source.manifest_hash, "True full-source cold rebind rederives the same named rule")

func _original_feature_ui(f: Dictionary, key: String, recipe: String, identity: int, resume: bool = false) -> void:
	var controller: SiteController = f.lab.site_controller
	var feature: Dictionary = f.data.site.features[key]
	var station: Vector2i = f.data.cell_from_index(int(feature.entrance))
	var selected_body: Dictionary = f.team.combat_units[f.team.index_for_identity(identity)]
	# Real original REST bookkeeping, no fatigue/pool reset or work shortcut.
	if Fatigue.read(selected_body) > Fatigue.WORK_RESUME_AT: _settle_team_for_rest(f, identity)
	for tick: int in 1000:
		if Fatigue.read(selected_body) <= Fatigue.WORK_RESUME_AT: break
		_interval(f, 30.0)
	_require(Fatigue.read(selected_body) <= Fatigue.WORK_RESUME_AT, "True original selected worker recovers before public dispatch")
	_clear_station(f, identity, station)
	_place(f, identity, station)
	_park(f, int(f.commander), station + Vector2i(0, 3))
	controller.select_cell(f.data.cell_from_index(int(feature.cells[0])))
	_require(controller.feature_key == key, "Original formal building selection points to true host")
	if not resume:
		controller._sync_building_economy(feature)
		var found := false
		for index: int in controller.building_recipe.item_count:
			if str(controller.building_recipe.get_item_metadata(index)) == recipe:
				controller.building_recipe.select(index)
				found = true
				break
		_require(found and not controller.building_actions.recipe.disabled, "Original visible recipe selector admits explicit recipe")
		controller.building_actions.recipe.pressed.emit()
		_require(feature.get("recipe_id") == recipe, "Original visible apply command changes only true host recipe")
	# The formal Site UI is the Lab's "SiteUI" layer built by SiteController._build_ui.
	var site_ui: Node = f.lab.get_node_or_null("SiteUI")
	var button: Button = site_ui.find_child("OperateFeature", true, false) as Button if site_ui != null else null
	_require(button != null and f.lab.npc == null, "Original formal operation button exists without parallel default worker")
	button.pressed.emit()
	# A realistic dispatch comes from the team's current work-duty decider.
	# Fixture placements are not landed steps; refresh presence through a real
	# command event (unchanged tactical-AI confirmation) before resolving duty.
	f.team.set_tactical_ai_enabled(f.team.current_commander, f.team.tactical_ai_enabled)
	if f.team.current_commander < 0:
		# Presence is measured from the team's median member, not the station; a
		# commander parked by the station can be out of command radius. Re-park the
		# formal commander at that reference (explicit fixture input) and refresh.
		_park(f, int(f.commander), Vector2i(f.team.command_reference.floor()))
		f.team.set_tactical_ai_enabled(f.team.current_commander, f.team.tactical_ai_enabled)
	var work_decider: int = int(f.team.duty_decider("team.work"))
	_require(work_decider > 0, "The team work duty resolves to an actual present decider", f.team.duty_resolve("team.work", true))
	var dispatcher: Dictionary = controller._control_family_person(null, work_decider)
	_require(dispatcher.ok, "Original command control restored to the team work decider before selected-worker dispatch", dispatcher)
	f.lab.selected_army_target = identity
	controller.update_ui()
	_require(controller._selected_worker_assignment().ok, "Actual current original decider admits named selected original NPC")
	controller.assign_worker_button.pressed.emit()
	var state_before_selection: PackedByteArray = var_to_bytes([feature.production, feature.batch_paid, f.data.site.inventory, f.team.combat_units.map(func(body: Dictionary) -> Dictionary: return body.cargo)])
	# Original prepare selects/settles the original idle task at this real cell.
	# No participant allocation is committed here; no task mode is authored.
	controller.work_team.prepare_work_requests(60.0, 1.0)
	_require(var_to_bytes([feature.production, feature.batch_paid, f.data.site.inventory, f.team.combat_units.map(func(body: Dictionary) -> Dictionary: return body.cargo)]) == state_before_selection, "Original work selection has no material/work/output commit")
	var row: Dictionary = f.team.combat_units[f.team.index_for_identity(identity)]
	_require(row.get("work_task") is Dictionary and row.work_task.target == "feature:" + key and int(row.work_task.work_cell) == int(feature.entrance), "Original selected-worker UI actually assigns exactly this host/station")

func _operate(f: Dictionary, key: String, recipe: String, identity: int) -> void:
	_idle_all(f)
	_original_feature_ui(f, key, recipe, identity)

func _feature_paused(f: Dictionary, key: String, label: String) -> void:
	var feature: Dictionary = f.data.site.features[key]
	var before: PackedByteArray = var_to_bytes([feature.production, feature.batch_paid, feature.get("tech_batch", {}), f.data.site.inventory, f.team.combat_units.map(func(row: Dictionary) -> Dictionary: return row.cargo), feature.get("technology_output", {})])
	var result: Dictionary = _interval(f)
	_require(float(result.effective) == 0.0 and float(result.actual) == 0.0 and var_to_bytes([feature.production, feature.batch_paid, feature.get("tech_batch", {}), f.data.site.inventory, f.team.combat_units.map(func(row: Dictionary) -> Dictionary: return row.cargo), feature.get("technology_output", {})]) == before, label + ": no work, cost, output or effort")

func _unlearned_feature(f: Dictionary, key: String, recipe: String) -> void:
	var feature: Dictionary = f.data.site.features[key]
	_require(not Technology.learned(f.team.combat_units[f.team.index_for_identity(int(f.helper))].get("technology", {}), str(f.category)), "Selected original helper truly unlearned")
	_operate(f, key, recipe, int(f.helper))
	var row: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.helper))]
	var task: Dictionary = row.work_task
	# Selecting/assigning an ordinary stock recipe is legal; true manufacture
	# admission comes from the actual current original person/task, not UI text.
	_require(is_same(task, row.work_task) and int(task.work_cell) == int(feature.entrance) and f.team.cells[f.team.index_for_identity(int(f.helper))] == f.data.cell_from_index(int(task.work_cell)), "Same actual original worker/task is at legal station; fixture does not advance task mode")
	var guard: Dictionary = Runtime.technology_recipe_guard(f.data, key, feature, int(f.helper))
	_require(not guard.ok and guard.code == "NO_TECHNOLOGY", "True fixed-policy original manufacture rejects actual unlearned worker", guard)
	_feature_paused(f, key, "True unlearned same-task original interval")
	_idle_all(f)

func _expected_recipe(recipe: String) -> Dictionary:
	# Named accepted original terms, independent of the runtime definition read.
	match recipe:
		"steel": return {"input": {"iron": 2, "charcoal": 2}, "output": {"steel": 1}, "seconds": 1200.0}
		"wool_cloth": return {"input": {"wool": 3}, "output": {"cloth": 2}, "seconds": 900.0}
		"steel_tools": return {"input": {"steel": 1, "charcoal": 1, "wood": 1}, "output": {"tools": 2}, "seconds": 720.0}
	return {}

func _assert_recipe_terms(recipe: String, definition: Dictionary, output: Dictionary) -> Dictionary:
	var expected: Dictionary = _expected_recipe(recipe)
	_require(not expected.is_empty() and definition.get("input") == expected.input and definition.get("output") == expected.output and output == expected.output and float(definition.get("cycle", -1.0)) * 60.0 == float(expected.seconds), "Exact named original full material/output/duration terms: " + recipe)
	return expected

func _finish_recipe(f: Dictionary, key: String, recipe: String, output: Dictionary) -> void:
	var feature: Dictionary = f.data.site.features[key]
	var definition: Dictionary = Runtime.feature_recipe(feature)
	var expected: Dictionary = _assert_recipe_terms(recipe, definition, output)
	var body: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.master))]
	var prior_cargo: Dictionary = body.cargo.duplicate(true)
	var prior_stock: Dictionary = f.data.site.inventory.duplicate(true)
	var effective := _work_effective
	for tick: int in 2500:
		if output.keys().all(func(name: Variant) -> bool: return int(body.cargo.get(name, 0)) == int(prior_cargo.get(name, 0)) + int(output[name])): break
		_interval(f)
	for name: String in output: _require(int(body.cargo.get(name, 0)) == int(prior_cargo.get(name, 0)) + int(output[name]), "Exactly one actual ordinary recipe product")
	for name: String in definition.input: _require(int(prior_stock.get(name, 0)) - int(f.data.site.inventory.get(name, 0)) == int(definition.input[name]), "Whole original recipe paid exactly once")
	_require(_work_effective - effective >= float(expected.seconds) - 0.0001 and not feature.batch_paid and float(feature.production) == 0.0, "Full original work, no production-clock shortcut")
	var receipt: Dictionary = feature.get("technology_output", {}).get("receipts", [])[0] if not feature.get("technology_output", {}).get("receipts", []).is_empty() else {}
	_require(not receipt.is_empty() and receipt.operator_id == int(f.master) and receipt.recipe_id == recipe and receipt.resources == output, "Actual canonical output recorded by original owner")
	f.lab.selected_army_target = int(f.master)
	var stop: Button = f.lab.get_node("SiteUI").find_child("CancelSelectedWorker", true, false) as Button
	_require(stop != null, "Original formal selected-worker stop exists")
	stop.pressed.emit()
	_require(not f.lab.site_controller.work_team.is_assigned(int(f.master)), "Original public stop preserves completed cargo and receipt")
	_idle_all(f)

func _replacement_recipe(f: Dictionary, key: String, recipe: String, output: Dictionary) -> void:
	_teach_second_master(f) # Real original 300-second lesson, never authored learned.
	var feature: Dictionary = f.data.site.features[key]
	var definition: Dictionary = Runtime.feature_recipe(feature)
	var expected: Dictionary = _assert_recipe_terms(recipe, definition, output)
	for material: String in definition.input: Runtime.add_items(f.data.site.inventory, {material: int(definition.input[material])})
	f.data.site.depot_items.version = int(f.data.site.depot_items.version) + 1
	var prior_stock: Dictionary = f.data.site.inventory.duplicate(true)
	var student: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.helper))]
	var prior_cargo: Dictionary = student.cargo.duplicate(true)
	var effective := _work_effective
	_operate(f, key, recipe, int(f.master))
	_interval(f)
	_require(feature.batch_paid and float(feature.production) > 0.0, "Teacher starts one true fully-paid original batch")
	var paid_stock: Dictionary = f.data.site.inventory.duplicate(true)
	var ledger: Dictionary = feature.tech_batch
	_require(Runtime._technology_unbound_ordinary_feature_ledger(feature, ledger), "Actual current paid ordinary batch has no research/national/settlement/ship binding")
	for marker: String in ["tech_trial", "technology_order", "technology_settlement_order", "settlement_work", "ship_build"]:
		var bounded_projection: Dictionary = feature.duplicate(true)
		bounded_projection[marker] = {}
		_require(not Runtime._technology_unbound_ordinary_feature_ledger(bounded_projection, ledger), "Malformed present named binding never qualifies as ordinary continuation: " + marker)
	var paid_history: Dictionary = ledger.duplicate(true)
	paid_history.erase("operator_id")
	paid_history.erase("work_seconds")
	paid_history.erase("effective_seconds") # Round 16 work-sum field, like work_seconds.
	var prior_work := float(ledger.work_seconds)
	var started := float(feature.production)
	var station: Vector2i = f.data.cell_from_index(int(feature.entrance))
	_require(f.lab.site_controller.work_team.cancel(int(f.master)).ok, "Original teacher legally releases sole processing work slot and its original task before leaving")
	_park(f, int(f.master), station + Vector2i(-3, 0))
	_feature_paused(f, key, "Last actually working learned master physically absent")
	var unlearned_id := 0
	for index: int in f.team.combat_units.size():
		var identity: int = f.team.combat_identity(index)
		if identity not in [int(f.master), int(f.helper), int(f.commander)]:
			unlearned_id = identity
			break
	_require(unlearned_id > 0 and not Technology.learned(f.team.combat_units[f.team.index_for_identity(unlearned_id)].get("technology", {}), str(f.category)), "Independent third original worker remains genuinely unlearned")
	_original_feature_ui(f, key, recipe, unlearned_id, true)
	_feature_paused(f, key, "Unlearned original worker cannot consume existing paid master batch")
	_require(f.lab.site_controller.work_team.cancel(unlearned_id).ok, "Unlearned worker releases the original slot without a new payment or completion")
	_park(f, unlearned_id, station + Vector2i(3, 2))
	# Real Store/Slot full-pin pending-batch cold boundary, with no active task.
	_cold_resume(f, "ordinary_paid_pending_reassignment")
	feature = f.data.site.features[key]
	ledger = feature.tech_batch
	student = f.team.combat_units[f.team.index_for_identity(int(f.helper))]
	station = f.data.cell_from_index(int(feature.entrance))
	var loaded_history: Dictionary = ledger.duplicate(true)
	loaded_history.erase("operator_id")
	loaded_history.erase("work_seconds")
	loaded_history.erase("effective_seconds") # Round 16 work-sum field, like work_seconds.
	_require(loaded_history == paid_history and float(ledger.work_seconds) == prior_work and f.data.site.inventory == paid_stock, "True cold restore retains one exact payment/material/source identity and original work sum")
	_original_feature_ui(f, key, recipe, int(f.helper), true)
	_interval(f)
	_require(float(feature.production) > started and f.data.site.inventory == paid_stock, "Genuine taught replacement at original legal station resumes same paid batch")
	var continued_history: Dictionary = ledger.duplicate(true)
	continued_history.erase("operator_id")
	continued_history.erase("work_seconds")
	continued_history.erase("effective_seconds") # Round 16 work-sum field, like work_seconds.
	_require(is_same(ledger, feature.tech_batch) and continued_history == paid_history and int(ledger.operator_id) == int(f.helper) and float(ledger.work_seconds) > prior_work, "Successful actual replacement prefix updates only same original ledger operator/work sum")
	_require(f.lab.site_controller.work_team.cancel(int(f.helper)).ok, "Real student legally releases original work before leaving")
	_park(f, int(f.helper), station + Vector2i(-3, 2))
	_feature_paused(f, key, "Last taught original master leaves actual station")
	_original_feature_ui(f, key, recipe, int(f.helper), true)
	for tick: int in 2500:
		if output.keys().all(func(name: Variant) -> bool: return int(student.cargo.get(name, 0)) == int(prior_cargo.get(name, 0)) + int(output[name])): break
		_interval(f)
	for name: String in output: _require(int(student.cargo.get(name, 0)) == int(prior_cargo.get(name, 0)) + int(output[name]), "True taught replacement produces exactly original bounded output")
	for name: String in definition.input: _require(int(prior_stock.get(name, 0)) - int(f.data.site.inventory.get(name, 0)) == int(definition.input[name]), "Teacher/student reuse one original paid material charge")
	_require(_work_effective - effective >= float(expected.seconds) - 0.0001 and not feature.batch_paid, "Combined true work reaches full duration without a second clock")
	var receipt: Dictionary = feature.technology_output.receipts[0]
	_require(receipt.operator_id == int(f.helper) and receipt.recipe_id == recipe and receipt.resources == output and int(receipt.id) == int(paid_history.id) and float(receipt.work_seconds) >= float(expected.seconds) - 0.0001, "Canonical completion names actual replacement/full combined original work with one paid sequence")
	_idle_all(f)
	_case.true_taught_replacement = {"teacher": f.master, "student": f.helper, "lesson_seconds": 300, "one_original_slot_legal_reassignment": true, "output": output}

func _basic_feature_repair(f: Dictionary, key: String) -> void:
	var feature: Dictionary = f.data.site.features[key]
	var user: int = int(f.helper)
	_require(not Technology.learned(f.team.combat_units[f.team.index_for_identity(user)].get("technology", {}), str(f.category)), "Basic original repairer truly unlearned before lesson")
	_require(Runtime.damage_structure_part(f.data, key, "body", 1.0).ok and Runtime.request_repair(f.data, key, "body", int(f.team.faction_id), Callable(f.lab.site_controller, "reserves_cell")).ok, "Existing basic repair command has no manufacturing gate")
	_feature_assign(f, key, user, "repair")
	for tick: int in 1000:
		if not feature.has("repair"): break
		_interval(f)
	_require(not feature.has("repair") and float(feature.parts.body.hp) == Runtime.civil_max_hp(feature), "Actual unlearned worker finishes original basic repair")
	_idle_all(f)

func _processing(f: Dictionary) -> void:
	_finite_stock(f, {"iron": 2, "charcoal": 3, "wool": 3})
	var well := _build(f, "well", Vector2i(58, 58))
	f.water_origin = f.data.cell_from_index(int(f.data.site.features[well].cells[0]))
	var key := _build(f, "smelter" if f.category == "F04" else "weaver", Vector2i(60, 58))
	var recipe := "steel" if f.category == "F04" else "wool_cloth"
	var output := {"steel": 1} if f.category == "F04" else {"cloth": 2}
	_unlearned_feature(f, key, recipe)
	_operate(f, key, recipe, int(f.master))
	_finish_recipe(f, key, recipe, output)
	if f.category == "F04":
		var depot: Vector2i = f.data.cell_from_index(int(f.data.site.depot_cell))
		_transfer(f, int(f.master), "person:" + str(f.master), "depot", {"steel": 1}, depot + Vector2i.RIGHT)
		key = _build(f, "smithy", Vector2i(66, 58))
		recipe = "steel_tools"
		output = {"tools": 2}
		_unlearned_feature(f, key, recipe)
		_operate(f, key, recipe, int(f.master))
		_finish_recipe(f, key, recipe, output)
	_require(Stocks.set_local_supply(f.data, key, true, int(f.team.faction_id)).ok, "Actual original product stock endpoint")
	var endpoint: Dictionary = Stocks.stock_endpoint(f.data, key)
	_transfer(f, int(f.master), "person:" + str(f.master), "feature:" + key, output, endpoint.cell)
	_transfer(f, int(f.helper), "feature:" + key, "person:" + str(f.helper), output, endpoint.cell)
	_require(not Technology.learned(f.team.combat_units[f.team.index_for_identity(int(f.helper))].get("technology", {}), str(f.category)), "Real completed-product pickup has no manufacture gate")
	_require(not f.data.site.has("family") and f.data.site.technology_artisans == f.birth, "Independent personal production retains birth history without invented family")
	_basic_feature_repair(f, key)
	# Empty this same student's real cargo by the original physical logistics
	# owner before public default work assignment; no forced cargo clear.
	var depot: Vector2i = f.data.cell_from_index(int(f.data.site.depot_cell))
	_transfer(f, int(f.helper), "person:" + str(f.helper), "depot", output, depot + Vector2i.RIGHT)
	_require(Stocks.set_local_supply(f.data, key, false, int(f.team.faction_id)).ok, "Original public source selection resumes camp inputs")
	_cold_resume(f, "fixed_independent_processing_product_repair")
	_replacement_recipe(f, key, recipe, output)
	_cold_rule_guards(f)
	_case.processing_report = {"final_recipe": recipe, "well": well, "feature": key, "real_fixed_full_pin": true, "source_rule": _source_rule_report}

func _build(f: Dictionary, kind: String, anchor: Vector2i) -> String:
	_idle_all(f)
	var options := {"owner_faction": int(f.team.faction_id)}
	var layout: Dictionary = {}
	# Select through the ORIGINAL preview, with true source-pinned potential,
	# groundwater, height, occupancy and reachable doorway guards unchanged.
	for radius: int in range(0, 30):
		if not layout.is_empty(): break
		for y: int in range(-radius, radius + 1):
			if not layout.is_empty(): break
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius: continue
				var selected := anchor + Vector2i(x, y)
				if f.has("water_origin") and absi(selected.x - int(f.water_origin.x)) + absi(selected.y - int(f.water_origin.y)) > 8: continue
				var candidate: Dictionary = Runtime.building_cells(f.data, kind, selected, Vector2i.ONE, options)
				if not candidate.ok: continue
				var candidate_cells: Array[int] = []
				candidate_cells.assign(candidate.cells)
				var preview: Dictionary = Runtime.preview_build(f.data, kind, candidate_cells, Callable(f.lab.site_controller, "reserves_cell"), options)
				if preview.ok:
					layout = candidate
					break
	_require(not layout.is_empty(), "Actual checked fixed source preview admits " + kind)
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var prior: Dictionary = f.data.site.inventory.duplicate(true)
	var requested: Dictionary = Runtime.request_build(f.data, kind, cells, Callable(f.lab.site_controller, "reserves_cell"), options)
	_require(requested.ok, "Original building command pays full actual cost", requested)
	var key := str(requested.feature)
	var feature: Dictionary = f.data.site.features[key]
	var initial_work := float(feature.work) * 60.0
	_feature_assign(f, key, int(f.master), "construct")
	var effective := _work_effective
	for tick: int in 2500:
		if str(feature.stage) == "complete": break
		_interval(f)
	_require(str(feature.stage) == "complete" and _work_effective - effective >= initial_work - 0.0001, "Real full original construction work completes " + kind)
	_require(prior != f.data.site.inventory and f.data.fingerprint() == f.geography and f.data.parameters.fixed_base == f.fixed_base and f.data.site.world_pin == f.pin and f.data.parameters.fixed_base.land_condition_rule == LAND_RULE, "Construction spends actual stock while preserving true full fixed source/pin")
	_idle_all(f)
	return key

func _run() -> void:
	var category: String = _g06_category()
	_require(category in ["F04", "F06"], "Named true fixed processing category only")
	_require(Catalog.get_node(category).get("enabled") == true, "Original isolated accepted full-content catalog is required for real teaching; fixture never changes activation")
	_case = {"category": category, "hypothetical_fixed_policy": [category], "new_checksum_pinned_land_rule_candidate": true, "formal_release": false, "fixed_production": true, "generated_soil_or_crossworld_input": false}
	var source: RegionData = _g06_source()
	# Original old checksum/pin coexists unchanged; it is not silently upgraded.
	var candidate_path := manifest_path
	manifest_path = _legacy_manifest_path
	var old: Dictionary = _birth(_legacy_source, category)
	_cold_resume(old, "unchanged_legacy_source")
	_require(not old.data.parameters.has("fixed_land_condition_rule") and _bounds(old.data.foundation).y == 0 and FileAccess.get_sha256(manifest_path) == _legacy_source_sha, "Original old pin/zero eligibility survives real Store/Slot cold bind")
	old.lab.free()
	manifest_path = candidate_path
	var f: Dictionary = _birth(source, category)
	f.geography = f.data.fingerprint()
	_case.fixed_world = f.world
	_fixed_policy_guard(f)
	_no_reissue(f)
	_processing(f)
	_no_reissue(f)
	_case.checked_intervals = _work_intervals
	_case.actual_participant_seconds = _work_actual
	_case.effective_work_seconds = _work_effective
	report[category] = _case
	_finish()

func _finish(reason: String = "") -> void:
	if finished: return
	finished = true
	if not reason.is_empty(): failures.append(reason)
	for lab: TerrainLab in labs:
		if is_instance_valid(lab): lab.free()
	TerrainArmy.release_contact_source()
	print("TECH_AI_02_FIXED_PROCESSING_REPORT: " + JSON.stringify({"checks": checks, "failures": failures, "cases": report, "fixture": root_path}, "", true, true))
	print("TECH_AI_02_FIXED_D10_", _g06_category(), "_", "PASS" if failures.is_empty() else "FAILED", " scope=true_fullpin_new_checksum_source_candidate_original_public_recipe_work_products_300s_taught_replacement_basicrepair_cold; legacy_source_unmodified; Eco_Fire_Taiwan_policy_resource_release_Native_GPU_autonomous_AI_FULL40_excluded")
	quit(0 if failures.is_empty() else 1)
