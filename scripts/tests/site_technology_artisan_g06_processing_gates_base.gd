extends "res://scripts/tests/site_technology_artisan_fixed_processing_base.gd"
## Requires paired Eco/Region checked fixed source admission, never a soil/pin bypass.

func _g06_ensure_actor_expansion(f: Dictionary) -> void:
	_idle_all(f)
	var controller: SiteController = f.lab.site_controller
	_require(controller._control_family_person(null, 1).ok, "Actual Actor controls its own personal equipment")
	var actions: SitePersonActions = controller.person_actions
	var records: String = _normalized(f.data.site.item_records)
	var item_ids: Array = f.lab.character.item_state.item_ids.duplicate()
	var born: PackedByteArray = var_to_bytes(f.data.site.technology_artisans)
	var next_item: int = int(f.data.site.next_item)
	if not str(f.lab.character.item_state.equipped.get("weapon", "")).is_empty():
		var begun: Dictionary = controller.equipment_orders.begin_personal(1, "weapon", "")
		_require(begun.ok and is_equal_approx(float(begun.seconds), 5.0), "Original five-second personal unequip, without replacing gear or allocating items", begun)
		for tick: int in 4000:
			if not actions.is_busy(1): break
			var job: Dictionary = actions._jobs.get(actions._job_key_for(1), {})
			if bool(job.get("preparing", false)):
				await process_frame # Genuine original atlas preparation, no fake await/completion.
				continue
			var stepped: Dictionary = f.lab._advance_original_shared_step(0.02)
			_require(stepped.ok, "Equipment consumes the original whole main caller and accepted interval", stepped)
		_require(not actions.is_busy(1) and str(f.lab.character.item_state.equipped.get("weapon", "")).is_empty(), "Actual equipment owner settled original unequip")
	_require(_normalized(f.data.site.item_records) == records and f.lab.character.item_state.item_ids == item_ids and int(f.data.site.next_item) == next_item and var_to_bytes(f.data.site.technology_artisans) == born and f.lab.character.technology.is_empty(), "Unequip changes only original equipped slot; no free product or background skill")
	_require(controller._control_family_person(null, int(f.commander)).ok, "Original decider control restored after personal action")


func _g06_original_hazard(f: Dictionary, identity: int, lethal: bool) -> void:
	# Named normalized environmental contact INPUT, not hit/flight geometry proof.
	# Original Army owns life, KO, count, removal, remains signals and hot fields.
	var index: int = f.team.index_for_identity(identity)
	var learned: Dictionary = f.team.combat_units[index].get("technology", {}).duplicate(true)
	var hp: float = float(f.team.combat_hot_get(index, &"hp"))
	# Crowd: the native World takes this named contact input through its melee-contact writer (it refuses an
	# environmental flag); the same hp/stun result reaches the same native life owner.
	f.team.apply_unit_contact(index, {"environmental": not _crowd(f), "shield": false,
		"result": {"hp": hp + 1.0 if lethal else 0.0, "stun": 0.0 if lethal else SiteCombatRules.STUN_LIMIT, "guard_break": false}})
	_require(float(f.team.combat_hot_get(index, &"hp")) == 0.0 if lethal else float(f.team.combat_hot_get(index, &"ko")) > 0.0, "Original lethal/KO source applied by existing contact owner")
	_require(f.team.combat_units[index].get("technology", {}) == learned, "Life change never issues/erases individual learned history")


func _g06_rest_source(f: Dictionary) -> void:
	# Explicit existing shared-pool state input; NOT proof of work-to-80.
	# All SAME-team masters share this pool. We never make one master immune.
	_fatigue_set(f, int(f.master), "fatigue", Fatigue.WORK_REST_AT)
	_fatigue_set(f, int(f.master), "fatigue_rest", 0.0)
	_require(_fatigue_get(f, int(f.master)) == Fatigue.WORK_REST_AT, "Actual original pool receives named REST-boundary input")


func _g06_recover(f: Dictionary) -> void:
	for tick: int in 1200:
		if _fatigue_get(f, int(f.helper)) <= Fatigue.WORK_RESUME_AT: break
		_interval(f, 30.0) # Original shared recovery/provider, no direct reset.
	_require(_fatigue_get(f, int(f.helper)) <= Fatigue.WORK_RESUME_AT, "Original provider genuinely recovers shared masters to resume boundary")

func _no_reissue(f: Dictionary) -> void:
	await _g06_ensure_actor_expansion(f)
	_idle_all(f)
	var receipt: PackedByteArray = var_to_bytes(f.data.site.get("technology_artisans", {}))
	var next_item := int(f.data.site.next_item)
	var next_person := int(f.data.site.next_person_id)
	var skills := {}
	for row: Dictionary in _team_rows(f.team): skills[int(row.person_id)] = row.get("technology", {}).duplicate(true)
	for identity: int in [1, int(f.master), int(f.helper), int(f.commander)]:
		var person_index: int = f.team.index_for_identity(identity)
		var dead: bool = person_index >= 0 and float(f.team.combat_hot_get(person_index, &"hp")) <= 0.0
		var old_control: int = int(f.lab.controlled_person_id())
		var selected: Dictionary = f.lab.site_controller._control_family_person(null, identity)
		_require(not selected.ok and selected.code == "NO_TARGET" and int(f.lab.controlled_person_id()) == old_control if dead else selected.ok, "Actual dead control rejects; true surviving person control succeeds", selected)
		_require(var_to_bytes(f.data.site.get("technology_artisans", {})) == receipt and int(f.data.site.next_item) == next_item and int(f.data.site.next_person_id) == next_person, "Control switch issues no birth or free items")
		for row: Dictionary in _team_rows(f.team): _require(row.get("technology", {}) == skills[int(row.person_id)], "Control switch cannot teach a faction member")
	_require(f.lab.site_controller._control_family_person(null, int(f.helper)).ok, "Original member controls their own roster consent")
	_require(f.lab.leave_player_army().ok and f.lab.join_player_army().ok, "Actual existing NPC leaves/joins same original faction roster")
	_require(var_to_bytes(f.data.site.get("technology_artisans", {})) == receipt and int(f.data.site.next_item) == next_item and int(f.data.site.next_person_id) == next_person, "Actual membership join issues no skills/items/people")
	_require(f.lab.site_controller._control_family_person(null, 1).ok, "Actual original Actor controls explicit army expansion")
	var expansion_before: PackedByteArray = var_to_bytes([f.data.site, _combat_state(f), f.lab.character.capture_state()])
	var expanded: Dictionary = f.lab.join_player_army()
	# Crowd: an Actor joining a native crowd army is not supported yet (S4); it is refused atomically (production base rule).
	var crowd_unsupported: bool = _crowd(f) and not expanded.ok and expanded.code == "UNSUPPORTED"
	_require(expanded.ok or crowd_unsupported and var_to_bytes([f.data.site, _combat_state(f), f.lab.character.capture_state()]) == expansion_before, "Original neutral unequipped Actor genuinely expands the original roster", expanded)
	if crowd_unsupported: _case["actor_expansion_" + str(f.kind)] = "crowd UNSUPPORTED atomic refusal; positive roster expansion NOT_VERIFIED"
	else: _require(f.lab.character.technology.is_empty() and f.team.player_member == f.lab.character and int(f.data.site.next_person_id) == next_person and int(f.data.site.next_item) == next_item, "Real expansion preserves SAME Actor and gives zero skills/products/people")
	if not crowd_unsupported:
		_require(f.lab.leave_player_army().ok, "Original Actor legally leaves expanded original army")
		_case["actor_expansion_" + str(f.kind)] = "true original unequip/join/leave; no skill or product allocation"
	_require(var_to_bytes(f.data.site.technology_artisans) == receipt, "Positive roster expansion cannot replay original birth")
	_require(f.lab.site_controller._control_family_person(null, int(f.commander)).ok, "Original command control restored")
	var before := var_to_bytes([f.data.site, _combat_state(f)])
	var replay: Dictionary = f.lab.prepare_initial_artisan_birth(f.data, Artisans.PRIMARY, Artisans.CATEGORIES)
	if f.kind == "fixed_birth":
		_require(replay.ok and not replay.changed and var_to_bytes([f.data.site, _combat_state(f)]) == before, "Actual historical birth cannot replay under later all-category release")
	else:
		_require(not replay.ok and var_to_bytes([f.data.site, _combat_state(f)]) == before, "Generated restored input has no original first-world birth authority and cannot regrant")
	_cold_resume(f, "no_reissue")
	if f.kind == "fixed_birth":
		_completed_open_refuses(f)
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
	_g06_rest_source(f)
	_feature_paused(f, key, "Original last ordinary master at shared REST boundary")
	_g06_recover(f)
	_interval(f)
	_require(is_same(ledger, feature.tech_batch) and f.data.site.inventory == paid_stock and feature.batch_paid, "REST/recovery retains original full paid ledger/source without charging again")
	prior_work = float(ledger.work_seconds)
	started = float(feature.production)
	_g06_original_hazard(f, int(f.master), false)
	_feature_paused(f, key, "Original last ordinary master KO; no processing work/effort/payment/output")
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
	var stalled := 0
	for tick: int in 2500:
		if output.keys().all(func(name: Variant) -> bool: return int(student.cargo.get(name, 0)) == int(prior_cargo.get(name, 0)) + int(output[name])): break
		var produced: float = float(feature.production)
		_interval(f)
		# Twenty whole intervals without production are a stuck replacement; report it instead of spending the deadline.
		stalled = stalled + 1 if float(feature.production) == produced else 0
		if stalled >= 20: break
	for name: String in output: _require(int(student.cargo.get(name, 0)) == int(prior_cargo.get(name, 0)) + int(output[name]), "True taught replacement produces exactly original bounded output",
		{"cargo": student.cargo, "prior": prior_cargo, "production": feature.production, "batch_paid": feature.batch_paid, "task": _task_of(f, int(f.helper)), "cell": str(_cell_of(f, int(f.helper))), "station": str(station),
		"worker_status_hex": str(_task_of(f, int(f.helper)).get("status", "")).to_utf8_buffer().hex_encode(), "feature_status_hex": str(feature.get("status", "")).to_utf8_buffer().hex_encode(),
		"cycle": Runtime.feature_recipe(feature).get("cycle", -1.0)})
	for name: String in definition.input: _require(int(prior_stock.get(name, 0)) - int(f.data.site.inventory.get(name, 0)) == int(definition.input[name]), "Teacher/student reuse one original paid material charge")
	_require(_work_effective - effective >= float(expected.seconds) - 0.0001 and not feature.batch_paid, "Combined true work reaches full duration without a second clock")
	var receipt: Dictionary = feature.technology_output.receipts[0]
	_require(receipt.operator_id == int(f.helper) and receipt.recipe_id == recipe and receipt.resources == output and int(receipt.id) == int(paid_history.id) and float(receipt.work_seconds) >= float(expected.seconds) - 0.0001, "Canonical completion names actual replacement/full combined original work with one paid sequence")
	_idle_all(f)
	_g06_original_hazard(f, int(f.master), true)
	_feature_paused(f, key, "Actual dead original teacher gives no future processing work to unlearned members")
	# The down pose and remains transfer settle only through the original main
	# caller's real elapsed steps (the work interval does not advance them); a
	# save is refused while the death is pending.
	var deaths: SiteController = f.lab.site_controller
	for tick: int in 2000:
		if not deaths._pending_deaths.has(int(f.master)): break
		var stepped: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		_require(stepped.ok, "Original main caller settles the actual death's down pose and remains", stepped)
	var dead: Dictionary = deaths.person_actions._person(int(f.master))
	_require(not deaths._pending_deaths.has(int(f.master)) and not dead.is_empty() and bool(deaths.person_actions._body_get(dead, "loot_settled")), "Actual original death settles its remains before any save")
	_case.ordinary_lifecycle = {"shared_rest_source_and_original_recovery": true, "original_contact_ko_then_true_taught_replacement": true, "original_contact_death": true, "no_second_payment": true, "normalized_environment_input_not_hit_geometry": true}
	_case.true_taught_replacement = {"teacher": f.master, "student": f.helper, "lesson_seconds": 300, "one_original_slot_legal_reassignment": true, "output": output}
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
	await _no_reissue(f)
	_processing(f)
	await _no_reissue(f)
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
	print("TECH_AI_02_G06_INCREMENT_REPORT: " + JSON.stringify({"checks": checks, "failures": failures, "cases": report, "fixture": root_path,
		"scope": "isolated_checked_fixed_birth_true_products_original_300s_teaching_actual_lifecycle_input_subsequent_intervals_positive_roster_expansion_full_pin_cold",
		"formal_release": false, "default_world_policy": [], "not_full_g06": true,
		"source_epochs": {"runtime": FileAccess.get_sha256("res://scripts/terrain_lab/site_runtime.gd"), "lab": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_lab.gd"), "controller": FileAccess.get_sha256("res://scripts/terrain_lab/site_controller.gd"), "slot": FileAccess.get_sha256("res://scripts/region_lab/region_save_slot.gd"), "env": FileAccess.get_sha256("res://scripts/terrain_lab/site_environment.gd"), "catalog": FileAccess.get_sha256("res://scripts/terrain_lab/site_technology_catalog.gd")}}, "", true, true))
	print("TECH_AI_02_G06_INCREMENT_", _g06_category(), "_", "PASS" if failures.is_empty() else "FAILED", " scope=named_increment_only_not_FULL_G06_default_Taiwan_midframe_Native_GPU_or_release")
	quit(0 if failures.is_empty() else 1)

## Crowd port (2026-11-12): the G06 processing gates step the whole Lab, so they run on the native crowd.
func _crowd_port() -> bool:
	return not OS.get_cmdline_user_args().has("--grid")
