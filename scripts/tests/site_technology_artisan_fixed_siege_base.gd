extends "res://scripts/tests/site_technology_artisan_production_base.gd"
## Real ORIGINAL fixed world, full checked pin, no generated soil or handoff.
## Hypothetical admission is isolated; original default policy remains [].

func _finite_stock(f: Dictionary, extra: Dictionary = {}) -> void:
	# Named finite SUPPLY precondition, never birth/product/payment evidence.
	var stock := {"wood": 30, "stone": 30, "clay": 10, "tools": 4, "grain": 100}
	for key: String in extra: stock[key] = int(extra[key])
	_require(Runtime.inventory_size(stock) <= int(f.data.site.capacity), "Actual finite input fits original camp")
	var history: PackedByteArray = var_to_bytes(f.data.site.technology_artisans)
	f.data.site.inventory.clear()
	f.data.site.inventory.merge(stock)
	f.data.site.depot_items.version = int(f.data.site.depot_items.version) + 1
	_require(var_to_bytes(f.data.site.technology_artisans) == history and int(f.data.site.next_item) == int(f.next_item_birth), "Finite supplied resources cannot issue a second birth or product")

func _gated_pause(f: Dictionary, key: String, label: String) -> void:
	var vehicle: Dictionary = f.data.site.vehicles[key]
	var progress: float = float(vehicle.build.progress)
	var paid: Dictionary = vehicle.build.paid_cost.duplicate(true)
	var effective: float = _work_effective
	var actual: float = _work_actual
	var result: Dictionary = _interval(f)
	_require(float(vehicle.build.progress) == progress and vehicle.build.paid_cost == paid, label + ": full paid original engineering identity/progress retained")
	_require(_work_effective == effective and _work_actual == actual and float(result.effective) == 0.0 and float(result.actual) == 0.0, label + ": helpers gain zero work or effort without an actual master")
	_case.gated_pauses = int(_case.get("gated_pauses", 0)) + 1

func _begin_original_siege_ui(f: Dictionary, kind: String, anchor: Vector2i) -> Dictionary:
	var controller: SiteController = f.lab.site_controller
	var form: Dictionary = controller._siege_construction_form
	_require(form.has("siege_builder"), "Original formal construction panel has the thin explicit-person selector")
	controller.select_cell(anchor)
	form.siege_facing.select(0)
	for index: int in form.siege_kind.item_count:
		if str(form.siege_kind.get_item_metadata(index)) == kind: form.siege_kind.select(index)
	controller._refresh_siege_build_people(form)
	_require(form.siege_builder.selected == 0 and int(form.siege_builder.get_item_metadata(0)) == 0, "Original UI never auto-selects a skilled master")
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
	_two_true_masters(f, kind)
	_basic_siege_use_repair(f, key)

func _two_true_masters(f: Dictionary, kind: String) -> void:
	# Strict named known Family archive is a teaching precondition only. Parent
	# proves real register/head/Store and real 300-second joint lesson; no learned
	# assignment or replay of the birth helper creates the second master.
	_teach_second_master(f)
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
	_station_named_member(f, assistant, anchor + Vector2i(-4, 2))
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
	_case.two_masters = {"vehicle": key, "teacher": f.master, "student": f.helper, "lesson_seconds": 300, "assistant": assistant, "fixed_policy_gated": true}
	_idle_all(f)
	_require(Runtime.cancel_siege_job(f.data, key, int(f.team.team_id), Callable(f.lab.site_controller, "reserves_cell")).ok, "Actual second unfinished product cancels/refunds through original owner before basic repair")

func _run() -> void:
	var category: String = _g06_category()
	_require(category in ["F11", "F12"], "Named fixed-world original siege acceptance only")
	_case = {"category": category, "hypothetical_fixed_policy": [category], "formal_release": false, "fixed_production": true, "generated_soil_or_crossworld_input": false}
	var source: RegionData = _g06_source()
	_require(source != null, "Original checksummed full geographic source")
	var f: Dictionary = _birth(source, category)
	_case.fixed_world = f.world
	_fixed_policy_guard(f)
	_no_reissue(f)
	await _siege(f)
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
	print("TECH_AI_02_FIXED_D10_REPORT: " + JSON.stringify({"checks": checks, "failures": failures, "cases": report, "fixture": root_path}, "", true, true))
	print("TECH_AI_02_FIXED_D10_", _g06_category(), "_", "PASS" if failures.is_empty() else "FAILED", " scope=truefullpin_birth_product_cold_master_station_teacher_student_repair; hypothetical_single_category_admission; F04_F06_allG03_edges_Native_GPU_autonomous_AI_FULL40_release_excluded")
	quit(0 if failures.is_empty() else 1)
