extends "res://scripts/tests/site_technology_artisan_fixed_siege_base.gd"
const SiteFamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd") # D/Tech declare no global class_name for it.
## Test-only derivative; no default admission or mutable owner.

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
	f.team.apply_unit_contact(index, {"environmental": true, "shield": false,
		"result": {"hp": hp + 1.0 if lethal else 0.0, "stun": 0.0 if lethal else SiteCombatRules.STUN_LIMIT, "guard_break": false}})
	_require(float(f.team.combat_hot_get(index, &"hp")) == 0.0 if lethal else float(f.team.combat_hot_get(index, &"ko")) > 0.0, "Original lethal/KO source applied by existing contact owner")
	_require(f.team.combat_units[index].get("technology", {}) == learned, "Life change never issues/erases individual learned history")


func _g06_rest_source(f: Dictionary) -> void:
	# Explicit existing shared-pool state input; NOT proof of work-to-80.
	# All SAME-team masters share this pool. We never make one master immune.
	var body: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.master))]
	Fatigue.write(body, "fatigue", Fatigue.WORK_REST_AT)
	Fatigue.write(body, "fatigue_rest", 0.0)
	_require(Fatigue.read(body) == Fatigue.WORK_REST_AT, "Actual original pool receives named REST-boundary input")


func _g06_recover(f: Dictionary) -> void:
	for tick: int in 1200:
		var body: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.helper))]
		if Fatigue.read(body) <= Fatigue.WORK_RESUME_AT: break
		_interval(f, 30.0) # Original shared recovery/provider, no direct reset.
	_require(Fatigue.read(f.team.combat_units[f.team.index_for_identity(int(f.helper))]) <= Fatigue.WORK_RESUME_AT, "Original provider genuinely recovers shared masters to resume boundary")

func _no_reissue(f: Dictionary) -> void:
	await _g06_ensure_actor_expansion(f)
	_idle_all(f)
	var receipt: PackedByteArray = var_to_bytes(f.data.site.get("technology_artisans", {}))
	var next_item := int(f.data.site.next_item)
	var next_person := int(f.data.site.next_person_id)
	var skills := {}
	for row: Dictionary in f.team.combat_units: skills[int(row.person_id)] = row.get("technology", {}).duplicate(true)
	for identity: int in [1, int(f.master), int(f.helper), int(f.commander)]:
		var person_index: int = f.team.index_for_identity(identity)
		var dead: bool = person_index >= 0 and float(f.team.combat_hot_get(person_index, &"hp")) <= 0.0
		var old_control: int = int(f.lab.controlled_person_id())
		var selected: Dictionary = f.lab.site_controller._control_family_person(null, identity)
		_require(not selected.ok and selected.code == "NO_TARGET" and int(f.lab.controlled_person_id()) == old_control if dead else selected.ok, "Actual dead control rejects; true surviving person control succeeds", selected)
		_require(var_to_bytes(f.data.site.get("technology_artisans", {})) == receipt and int(f.data.site.next_item) == next_item and int(f.data.site.next_person_id) == next_person, "Control switch issues no birth or free items")
		for row: Dictionary in f.team.combat_units: _require(row.get("technology", {}) == skills[int(row.person_id)], "Control switch cannot teach a faction member")
	_require(f.lab.site_controller._control_family_person(null, int(f.helper)).ok, "Original member controls their own roster consent")
	_require(f.lab.leave_player_army().ok and f.lab.join_player_army().ok, "Actual existing NPC leaves/joins same original faction roster")
	_require(var_to_bytes(f.data.site.get("technology_artisans", {})) == receipt and int(f.data.site.next_item) == next_item and int(f.data.site.next_person_id) == next_person, "Actual membership join issues no skills/items/people")
	_require(f.lab.site_controller._control_family_person(null, 1).ok, "Actual original Actor controls explicit army expansion")
	var expanded: Dictionary = f.lab.join_player_army()
	_require(expanded.ok, "Original neutral unequipped Actor genuinely expands the original roster", expanded)
	_require(f.lab.character.technology.is_empty() and f.team.player_member == f.lab.character and int(f.data.site.next_person_id) == next_person and int(f.data.site.next_item) == next_item, "Real expansion preserves SAME Actor and gives zero skills/products/people")
	_require(f.lab.leave_player_army().ok, "Original Actor legally leaves expanded original army")
	_require(var_to_bytes(f.data.site.technology_artisans) == receipt, "Positive roster expansion cannot replay original birth")
	_case["actor_expansion_" + str(f.kind)] = "true original unequip/join/leave; no skill or product allocation"
	_require(f.lab.site_controller._control_family_person(null, int(f.commander)).ok, "Original command control restored")
	var before := var_to_bytes([f.data.site, f.team.capture_combat_state()])
	var replay: Dictionary = f.lab.prepare_initial_artisan_birth(f.data, Artisans.PRIMARY, Artisans.CATEGORIES)
	if f.kind == "fixed_birth":
		_require(replay.ok and not replay.changed and var_to_bytes([f.data.site, f.team.capture_combat_state()]) == before, "Actual historical birth cannot replay under later all-category release")
	else:
		_require(not replay.ok and var_to_bytes([f.data.site, f.team.capture_combat_state()]) == before, "Generated restored input has no original first-world birth authority and cannot regrant")
	_cold_resume(f, "no_reissue")
	if f.kind == "fixed_birth":
		var manifest_sha: String = FileAccess.get_sha256(f.slot.folder.path_join("manifest.json"))
		var repeated: Dictionary = f.lab.site_controller.open_fixed_world(manifest_path, str(f.world), SLOT, START, true, Artisans.PRIMARY)
		_require(not repeated.ok and repeated.code == "CONFLICT" and FileAccess.get_sha256(f.slot.folder.path_join("manifest.json")) == manifest_sha, "Actual completed newworld transaction cannot overwrite/reissue", repeated)
func _begin_original_siege_ui(f: Dictionary, kind: String, anchor: Vector2i) -> Dictionary:
	var controller: SiteController = f.lab.site_controller
	var form: Dictionary = controller._siege_construction_form
	_require(form.has("siege_builder"), "Original formal construction panel has the thin explicit-person selector")
	controller.select_cell(anchor)
	form.siege_facing.select(0)
	for index: int in form.siege_kind.item_count:
		if str(form.siege_kind.get_item_metadata(index)) == kind: form.siege_kind.select(index)
	controller._refresh_siege_build_people(form)
	# Presentation is explicitly cleared in this repeat-use test; no authority/state.
	form.siege_builder.select(0)
	_require(int(form.siege_builder.get_item_metadata(0)) == 0, "Original UI has a real no-person placeholder")
	var selection_before: PackedByteArray = var_to_bytes([f.data.site, f.team.capture_combat_state()])
	var empty_selection: Dictionary = controller._siege_build_person_context(form)
	_require(not empty_selection.ok and var_to_bytes([f.data.site, f.team.capture_combat_state()]) == selection_before, "No human selection cannot auto-pick a master or mutate original owners")
	_require(form.has("siege_method"), "Real original SiegeJoinery selector exists")
	var method: String = str(f.get("g06_method", "basic"))
	var found_method := false
	for at: int in form.siege_method.item_count:
		if str(form.siege_method.get_item_metadata(at)) == method:
			form.siege_method.select(at)
			found_method = true
	_require(found_method, "Explicit original visible basic/joinery choice")
	for index: int in form.siege_builder.item_count:
		if int(form.siege_builder.get_item_metadata(index)) == int(f.master): form.siege_builder.select(index)
	var ready: Dictionary = controller._siege_build_person_context(form)
	_require(ready.ok and ready.person_id == int(f.master) and is_same(ready.team, f.team), "Human-selected ID re-queries actual current original team/work authority")
	var before: PackedByteArray = var_to_bytes([f.data.site, f.team.capture_combat_state()])
	controller._build_siege_ui(form, true)
	_require(var_to_bytes([f.data.site, f.team.capture_combat_state()]) == before and controller.view.selection.size.x > 1, "Actual original UI preview calls true geometry/admission without materials or work mutation")
	var expected: int = int(f.data.site.get("next_vehicle", 1))
	await controller._build_siege_ui(form, false)
	_require(f.data.site.get("vehicles", {}).has(str(expected)) and int(f.data.site.next_vehicle) == expected + 1, "Actual original formal UI command publishes exactly one real paid named construction")
	_case.actual_formal_siege_ui = {"named_person": f.master, "vehicle": str(expected), "no_auto_master": true}
	return Runtime.ok("", {"vehicle": str(expected)})

func _g06_joinery_products(f: Dictionary) -> void:
	if str(f.category) != "F11": return
	var assistant: int = f.team.combat_identity(2)
	_require(assistant not in [int(f.master), int(f.helper)] and not Technology.learned(f.team.combat_units[2].get("technology", {}), "F11"), "Actual unlearned joinery helper retains basic productivity")
	var products: Array = []
	for kind: String in ["ballista", "ram", "traction_trebuchet"]:
		_idle_all(f)
		var terms: Dictionary = Runtime.SIEGE_DEFINITIONS[kind]
		for material: String in terms.cost: Runtime.add_items(f.data.site.inventory, {material: int(terms.cost[material])})
		f.data.site.depot_items.version = int(f.data.site.depot_items.version) + 1
		var anchor: Vector2i = _siege_anchor(f, kind, Vector2i(48, 78))
		var prior: Dictionary = f.data.site.inventory.duplicate(true)
		f.g06_method = "joinery"
		var begun: Dictionary = await _begin_original_siege_ui(f, kind, anchor)
		f.erase("g06_method")
		var key: String = str(begun.vehicle)
		var vehicle: Dictionary = f.data.site.vehicles[key]
		_require(vehicle.get("technology_siege_method") == {"version": 1} and not vehicle.has("tech_trial") and float(vehicle.build.total_work) == float(terms.work_seconds), "Actual ordinary joinery marker preserves full immutable physical work terms")
		for material: String in terms.cost: _require(int(prior[material]) - int(f.data.site.inventory[material]) == int(terms.cost[material]), "Joinery actual original cost paid once: " + material)
		var task: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.master))].work_task
		_place(f, int(f.master), f.data.cell_from_index(int(task.work_cell)))
		_siege_assign(f, key, [assistant])
		_interval(f)
		task = f.team.combat_units[f.team.index_for_identity(int(f.master))].work_task
		var other: Dictionary = f.team.combat_units[2].work_task
		var master_factor: Dictionary = Runtime.technology_siege_method_work_facts(f.data, vehicle, task, int(f.master))
		var helper_factor: Dictionary = Runtime.technology_siege_method_work_facts(f.data, vehicle, other, assistant)
		_require(master_factor.ok and is_equal_approx(float(master_factor.factor), 10.0 / 9.0) and helper_factor.ok and helper_factor.factor == 1.0 and float(vehicle.build.progress) > 0.0, "Real SAME tasks apply 10/9 only to actually learned master; unlearned helper stays one")
		_finish_siege_real(f, key)
		_require(vehicle.phase == "idle" and vehicle.build.is_empty(), "Original full shared work produces one real joinery vehicle")
		_cold_resume(f, "joinery_" + kind)
		_require(f.data.site.vehicles[key].get("technology_siege_method") == {"version": 1}, "Full-pin cold rebind preserves chosen original joinery method/product")
		products.append({"kind": kind, "vehicle": key, "cost": terms.cost.duplicate(true), "total_work": terms.work_seconds, "master_factor": 10.0 / 9.0, "helper_factor": 1.0})
	_case.actual_joinery_ui_products = products


func _g06_f12_first_research_refusal(f: Dictionary) -> void:
	if str(f.category) != "F12": return
	var third: int = f.team.combat_identity(2)
	_require(third not in [int(f.master), int(f.helper)] and not Technology.learned(f.team.combat_units[2].get("technology", {}), "F12"), "Actual background F12 birth does not teach other original members")
	var refs: Array = []
	for identity: int in [int(f.commander), int(f.master), int(f.helper), third]:
		refs.append({"site_id": str(f.data.site.id), "person_id": identity, "path": "", "label": "具名未學配重研究原人", "age_years": -1})
	var family: SiteFamilyContinuity = f.lab.site_controller.family_continuity
	_require(family.register_members(refs, true, int(f.commander)).ok and family.appoint_head(int(f.commander), int(f.commander)).ok, "Original actual family/member/head registration for unlearned first-research refusal")
	var actions: SitePersonActions = f.lab.site_controller.person_actions
	f.data.site.family = actions._technology_candidate()
	f.data.site.family.technology = Technology.empty_scope_record(str(f.data.site.id))
	f.data.site.family.technology.known = ["F11"] # Explicit legitimate prior archive, NOT this test's earned knowledge.
	_require(Family.validate_family(f.data.site.family, str(f.data.site.id)) and not Technology.family_traction_recorded(f.data.site.family.technology), "Strict named F11 archive has no invented traction completion")
	var before: PackedByteArray = var_to_bytes([f.data.site, f.team.capture_combat_state()])
	var denied: Dictionary = actions.prepare_scope_technology(int(f.commander), third, "F12")
	_require(not denied.ok and denied.code == "PREREQUISITE" and var_to_bytes([f.data.site, f.team.capture_combat_state()]) == before, "True unlearned F12 first research still requires actual traction history; background manufacture grants no trial shortcut", denied)
	_case.f12_first_research = "actual PREREQUISITE refusal; no traction history fabrication; positive earned G05 remains separate"

func _two_true_masters(f: Dictionary, kind: String) -> void:
	# Strict named known Family archive is a teaching precondition only. Parent
	# proves real register/head/Store and real 300-second joint lesson; no learned
	# assignment or replay of the birth helper creates the second master.
	_g06_f12_first_research_refusal(f)
	_teach_second_master(f)
	await _g06_joinery_products(f)
	var cost: Dictionary = Runtime.SIEGE_DEFINITIONS[kind].cost
	for material: String in cost: Runtime.add_items(f.data.site.inventory, {material: int(cost[material])})
	f.data.site.depot_items.version = int(f.data.site.depot_items.version) + 1
	var anchor: Vector2i = _siege_anchor(f, kind, Vector2i(78, 60))
	var begun: Dictionary = Runtime.begin_siege_build(f.data, kind, anchor, Vector2i.RIGHT, int(f.team.team_id), int(f.commander), Callable(f.lab.site_controller, "reserves_cell"), false, {}, {}, int(f.master))
	_require(begun.ok, "Second actual fixed-world bounded full-cost engineering job", begun)
	var key: String = str(begun.vehicle)
	var vehicle: Dictionary = f.data.site.vehicles[key]
	var teacher_task: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.master))].work_task
	_place(f, int(f.master), f.data.cell_from_index(int(teacher_task.work_cell)))
	_park(f, int(f.commander), anchor + Vector2i(-4, 0))
	_siege_assign(f, key, [int(f.helper)])
	var assistant: int = f.team.combat_identity(2)
	_require(assistant not in [int(f.master), int(f.helper)] and not Technology.learned(f.team.combat_units[2].get("technology", {}), str(f.category)), "Third original assistant truly lacks this manufacturing skill")
	_siege_assign(f, key, [assistant])
	_interval(f)
	var progress: float = float(vehicle.build.progress)
	_park(f, int(f.master), anchor + Vector2i(-6, 0))
	_interval(f)
	_require(float(vehicle.build.progress) > progress and vehicle.build.paid_cost == cost, "Another TRUE taught master still actually participates at its distinct legal original station")
	var student_task: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.helper))].work_task
	_park(f, int(f.helper), anchor + Vector2i(-6, 2))
	_require(f.team.cells[f.team.index_for_identity(int(f.helper))] != f.data.cell_from_index(int(student_task.work_cell)), "Last true taught master physically leaves station")
	_gated_pause(f, key, "Both actual learned masters absent; original unlearned assistant remains")
	# Legally resume the true taught student, not an authored substitute.
	_require(f.lab.site_controller.work_team.cancel(int(f.helper)).ok, "Original taught person releases its former task")
	_siege_assign(f, key, [int(f.helper)])
	_interval(f)
	_require(float(vehicle.build.progress) > progress and vehicle.build.paid_cost == cost, "Genuine taught replacement resumes same paid original work")

	# Subsequent original intervals, not mid-frame contact timing proof.
	var paid_before: Dictionary = vehicle.build.paid_cost.duplicate(true)
	_require(f.lab.site_controller.work_team.cancel(int(f.helper)).ok, "True final master task replacement through original owner")
	_gated_pause(f, key, "Actual last learned task replaced; assistant cannot borrow stale qualification")
	_siege_assign(f, key, [int(f.helper)])
	_interval(f)
	_require(float(vehicle.build.progress) > progress and vehicle.build.paid_cost == paid_before, "Real taught master resumes original paid work after task replacement")
	# Both masters must share original REST; nobody bypasses shared pool state.
	_g06_rest_source(f)
	_gated_pause(f, key, "Original shared masters reach named REST source boundary")
	_g06_recover(f)
	_interval(f)
	_require(vehicle.build.paid_cost == paid_before, "Original recovery resumes with SAME paid materials")
	_require(f.lab.site_controller.work_team.cancel(int(f.helper)).ok, "Student releases true slot for teacher KO/death exercise")
	_require(f.lab.site_controller.work_team.cancel(int(f.master)).ok, "Teacher releases its old off-station task")
	_siege_assign(f, key, [int(f.master)])
	_interval(f)
	_g06_original_hazard(f, int(f.master), false)
	_gated_pause(f, key, "Original last master KO; no helper work or effort in subsequent shared interval")
	_require(f.lab.site_controller.work_team.cancel(int(f.master)).ok, "Original owner cancels unconscious master's task")
	_siege_assign(f, key, [int(f.helper)])
	var before_ko_replacement: float = float(vehicle.build.progress)
	_interval(f)
	_require(float(vehicle.build.progress) > before_ko_replacement and vehicle.build.paid_cost == paid_before, "True learned replacement works while first real master remains unconscious")
	_g06_original_hazard(f, int(f.master), true)
	var before_death_replacement: float = float(vehicle.build.progress)
	_interval(f)
	_require(float(vehicle.build.progress) > before_death_replacement and vehicle.build.paid_cost == paid_before, "Other actually working learned master survives first master's actual death without double payment")
	_require(f.lab.site_controller.work_team.cancel(int(f.helper)).ok, "True survivor releases last actual task")
	_gated_pause(f, key, "Dead teacher plus survivor without task; unlearned original helper has zero effort")
	_siege_assign(f, key, [int(f.helper)])
	_interval(f)
	_case.lifecycle_edges = {"task_replacement": true, "shared_rest_source_and_original_recovery": true, "original_contact_ko": true, "original_contact_death": true, "real_taught_survivor": int(f.helper), "paid_once": paid_before, "subsequent_interval_only_not_midframe_contact_proof": true}
	_case.two_masters = {"vehicle": key, "teacher": f.master, "student": f.helper, "lesson_seconds": 300, "assistant": assistant, "fixed_policy_gated": true}
	_idle_all(f)
	_require(Runtime.cancel_siege_job(f.data, key, int(f.team.team_id), Callable(f.lab.site_controller, "reserves_cell")).ok, "Actual second unfinished product cancels/refunds through original owner before basic repair")
func _siege(f: Dictionary) -> void:
	var kind: String = "siege_tower" if f.category == "F11" else "counterweight_trebuchet"
	var terms: Dictionary = Runtime.SIEGE_DEFINITIONS[kind]
	var supply: Dictionary = terms.cost.duplicate(true)
	for material: String in supply: supply[material] = int(supply[material]) + 4
	_finite_stock(f, supply)
	var anchor: Vector2i = _siege_anchor(f, kind, Vector2i(66, 60))
	var before: PackedByteArray = var_to_bytes([f.data.site, f.team.capture_combat_state(), f.data.fingerprint()])
	var denied: Dictionary = Runtime.begin_siege_build(f.data, kind, anchor, Vector2i.RIGHT, int(f.team.team_id), int(f.commander), Callable(f.lab.site_controller, "reserves_cell"), true, {}, {}, int(f.helper))
	_require(not denied.ok and denied.code == "NO_TECHNOLOGY" and var_to_bytes([f.data.site, f.team.capture_combat_state(), f.data.fingerprint()]) == before, "Actual fixed policy refuses named unlearned construction atomically before materials")
	var inventory: Dictionary = f.data.site.inventory.duplicate(true)
	var begun: Dictionary = await _begin_original_siege_ui(f, kind, anchor)
	_require(begun.ok, "True independent fixed-world artisan admitted at original construction entrance", begun)
	var key: String = str(begun.vehicle)
	var vehicle: Dictionary = f.data.site.vehicles[key]
	for material: String in terms.cost: _require(int(inventory[material]) - int(f.data.site.inventory[material]) == int(terms.cost[material]), "Fixed original full construction cost once: " + material)
	_require(float(vehicle.build.total_work) == float(terms.work_seconds) and float(vehicle.build.progress) == 0.0, "Original full siege work is never shortened")
	var master_task: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.master))].work_task
	# A pending master is not a working master. No auto-move/station shortcut.
	_park(f, int(f.master), anchor + Vector2i(-6, 0))
	_park(f, int(f.commander), anchor + Vector2i(-4, 0))
	_siege_assign(f, key, [int(f.helper)])
	_gated_pause(f, key, "Master holds a true task but has not reached its station")
	_place(f, int(f.master), f.data.cell_from_index(int(master_task.work_cell)))
	var effective: float = _work_effective
	_interval(f)
	_require(float(vehicle.build.progress) > 0.0, "Fixed learned master and original unlearned assistant perform one real shared interval")
	var progress: float = float(vehicle.build.progress)
	_park(f, int(f.master), anchor + Vector2i(-6, 0))
	_require(f.team.cells[f.team.index_for_identity(int(f.master))] != f.data.cell_from_index(int(master_task.work_cell)), "Actual final master leaves the original held station")
	_gated_pause(f, key, "Final qualified master absent")
	_require(f.lab.site_controller.work_team.cancel(int(f.master)).ok, "True master cancels old named task through original owner")
	_siege_assign(f, key, [int(f.master)])
	_interval(f)
	_require(float(vehicle.build.progress) > progress and vehicle.build.paid_cost == terms.cost, "SAME genuine master legally reassigns/resumes without repaying")
	_finish_siege_real(f, key)
	_require(_work_effective - effective >= float(terms.work_seconds) - 0.0001, "Actual participant work totals at least the full immutable construction duration")
	_require(not f.data.site.has("family") and not vehicle.has("tech_trial") and Artisans.validate_receipt(f.data.site.technology_artisans, f.data.site), "Independent background F12/F11 works without family or fictional traction/research history")
	_cold_resume(f, "fixed_independent_product")
	_case.independent_vehicle = key
	_case.full_work_seconds = terms.work_seconds
	_case.paid_cost = terms.cost.duplicate(true)
	await _two_true_masters(f, kind)
	_basic_siege_use_repair(f, key)
func _run() -> void:
	var category: String = _g06_category()
	_require(category in ["F11", "F12"], "Named fixed-world original siege acceptance only")
	_case = {"category": category, "hypothetical_fixed_policy": [category], "formal_release": false, "fixed_production": true, "generated_soil_or_crossworld_input": false}
	var source: RegionData = _g06_source()
	_require(source != null, "Original checksummed full geographic source")
	var f: Dictionary = _birth(source, category)
	_case.fixed_world = f.world
	_fixed_policy_guard(f)
	await _no_reissue(f)
	await _siege(f)
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
