extends "res://scripts/tests/site_building_ui_test.gd"
## Actual original TerrainLab/Army/Family/material/build owners. Direct Runtime
## interval fixture only: no whole-clock/Fatigue, 600-second capture provenance,
## persistence I/O or full-F11/full40 acceptance is asserted here.
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
var checks := 0

func _check(condition: bool, message: String) -> void:
	checks += 1
	assert(condition, message)

func _project(lab: TerrainLab) -> Dictionary:
	return Technology.active_project(lab.terrain.site.family.technology)

func _token(lab: TerrainLab, executor: int, target: String) -> Dictionary:
	var family: Dictionary = lab.terrain.site.family
	var project := _project(lab)
	var phase := Technology.scope_next_phase(project, project.executor, family.technology.get("person_links", []))
	return {"scope": "family", "scope_id": str(family.family_id), "project_id": int(project.id), "epoch": int(family.technology.epoch),
		"purpose": str(project.purpose), "tech_id": str(project.tech_id), "phase_id": str(phase.id), "attempt": int(project.next_attempt),
		"person": {"site_id": str(lab.terrain.site.id), "person_id": executor}, "binding": str(phase.binding), "target_id": target, "materials": phase.materials.duplicate(true)}

func _army(lab: TerrainLab, data: TerrainData) -> TerrainArmy:
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 301
	team.roster_size = 2
	team.faction_id = 1
	var cells: Array[Vector2i] = [Vector2i(11, 11), Vector2i(12, 11)]
	_check(team.deploy_at(data, null, null, cells) and team.enable_combat(false), "Original finite Army creates and initializes its real NPC rows")
	for row: Dictionary in team.combat_units:
		row.cargo = {}
		row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
	lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	team.settle_combat_command()
	_check(team.set_duty_ai_enabled(team.combat_identity(team.formal_commander), true).ok, "Actual original captain explicitly enables the actual duty flag")
	return team

func _work_task(lab: TerrainLab, team: TerrainArmy, executor: int, key: String) -> Dictionary:
	var work := lab.site_controller.work_team
	_check(work.assign(team, [executor], team.duty_decider("team.work")).ok, "Actual original team.work authority assigns the true member")
	var row: Dictionary = team.combat_units[team.index_for_identity(executor)]
	var slots := Runtime.siege_work_slots(lab.terrain, lab.terrain.site.vehicles[key])
	_check(not slots.is_empty(), "Actual original vehicle computes its original work slots")
	# The fixture places the ORIGINAL Army hot cell at this real station. This
	# excludes travel acceptance; no surrogate body, consent, receipt or validator.
	team.cells[team.index_for_identity(executor)] = lab.terrain.cell_from_index(int(slots[0].cell))
	Runtime.assign_task(lab.terrain, Runtime.ok("原fixture明示真施工工位", {"target": "vehicle:" + key, "action": "construct", "work_slot": int(slots[0].slot), "cell": int(slots[0].cell), "zone": -1}), row.work_task)
	row.work_task.cell = int(slots[0].cell)
	row.work_task.mode = "work"
	_check(not lab.site_controller.person_actions._technology_operator_for_task(row.work_task, executor).is_empty(), "PA resolves the SAME original body/task/assigned member at the real station")
	return row.work_task

func _advance(lab: TerrainLab, team: TerrainArmy, executor: int, key: String, task: Dictionary, seconds: float) -> Dictionary:
	return Runtime.advance_siege_work(lab.terrain, key, "construct", seconds, team.cells[team.index_for_identity(executor)], int(task.work_slot), team.team_id, task, executor)

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	_check(lab.character.place(Vector2i(9, 10), true), "True controlled Actor stands at the actual camp grant contact")
	var control := lab.controlled_person_id()
	var team := _army(lab, data)
	var executor := team.combat_identity(1)
	var row: Dictionary = team.combat_units[1]
	var refs: Array = []
	for identity: int in [control, int(lab.npc.person_id), team.combat_identity(0), executor]:
		refs.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "原fixture人物", "age_years": -1})
	_check(lab.site_controller.family_continuity.register_members(refs, true, control).ok and lab.site_controller.family_continuity.appoint_head(control, control).ok, "Actual registry and office owners explicitly establish this family")
	# A legitimate existing prerequisite archive is the fixture precondition.
	# Earning F09 and analysis capture provenance have separate owner fixtures.
	data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known = ["F09"]
	_check(Family.validate_family(data.site.family, str(data.site.id)), "The original Family validator admits the explicit prerequisite archive")
	var actions := lab.site_controller.person_actions
	_check(actions.prepare_scope_technology(control, executor, "F11").ok, "An unlearned real original member prepares F11")
	var family_id := str(data.site.family.family_id)
	_check(actions.grant_scope_technology_budget(control, "family", family_id, {"wood": 300, "iron": 100, "fiber": 100, "cloth": 50}).ok, "Actual controlled camp user grants finite original material use")
	_check(actions.request_scope_technology_consent(control, "family", family_id, executor).ok, "Original NPC team resolves and accepts the actual named purpose")
	_check(row.get("technology", {}).is_empty(), "Ordinary legitimate F11 research does not require prior analysis or learned skills")
	var before := var_to_bytes(data.site)
	var first_key := str(int(data.site.get("next_vehicle", 1)))
	var request := {"anchor": Vector2i(20, 20), "facing": Vector2i.RIGHT, "team_id": team.team_id}
	var preview := Runtime.begin_technology_operation(data, _token(lab, executor, "vehicle:" + first_key), true, request)
	_check(preview.ok and var_to_bytes(data.site) == before and row.get("technology", {}).is_empty(), "True original preview writes neither materials, attempt, population nor credit")
	var started := actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", "vehicle:" + first_key, request)
	_check(started.ok, "No-analysis original research starts through the actual full geometry/payment guards: " + str(started))
	var first: Dictionary = data.site.vehicles[first_key]
	_check(not first.has("tech_work_credit") and first.build.total_work == Runtime.SIEGE_DEFINITIONS.ballista.work_seconds, "No analysis leaves the original baseline and ordinary effort intact")
	var task := _work_task(lab, team, executor, first_key)
	before = var_to_bytes(first)
	var wrong := Runtime.advance_siege_work(data, first_key, "construct", 300.0, team.cells[1], int(task.work_slot), team.team_id, task, team.combat_identity(0))
	_check(not wrong.ok and var_to_bytes(first) == before, "A different true person's identity cannot borrow the named participant's original task")
	_check(_advance(lab, team, executor, first_key, task, 300.0).ok and first.build.progress == 300.0 and first.tech_batch.work_seconds == 300.0, "Actual original callback advances unassisted progress/effort once")
	_check(lab.site_controller.work_team.cancel(executor).ok, "Original work owner parks the first paid target")
	var original: Dictionary = actions._body_get(actions._person(executor), "technology")
	# Explicit legal saved analysis receipt precondition ONLY. Its actual 600s
	# analysis/capture consumption is verified by the parent's source-job test.
	var allowance := Technology.analysis_candidate(original, "F11", family_id, _project(lab), "previously-consumed-real-engine", "previously-accepted-real-capture")
	_check(not allowance.is_empty(), "The original person's strict historical allowance is a valid fixture precondition")
	row.technology = allowance
	var second_key := str(int(data.site.get("next_vehicle", 1)))
	request = {"anchor": Vector2i(32, 20), "facing": Vector2i.RIGHT, "team_id": team.team_id}
	before = var_to_bytes(data.site)
	var person_before := var_to_bytes(row.technology)
	preview = Runtime.begin_technology_operation(data, _token(lab, executor, "vehicle:" + second_key), true, request)
	_check(preview.ok and var_to_bytes(data.site) == before and var_to_bytes(row.technology) == person_before, "Preview allocates no credit and does not debit the original lifetime receipt")
	started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", "vehicle:" + second_key, request)
	_check(started.ok, "The same person may have a second genuine paid attempt while the first remains parked")
	var second: Dictionary = data.site.vehicles[second_key]
	_check(second.build.total_work == 5400.0 and second.tech_work_credit == {"remaining_work": 5400.0, "credit": 2700.0} and row.technology.analysis[0].used_work == 2700.0, "Credit consumes one finite original allowance, leaving total_work immutable")
	var paid_count := _project(lab).budget.payments.size()
	var attempt := int(_project(lab).next_attempt)
	started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", "vehicle:" + second_key, request)
	_check(started.ok and started.resumed and row.technology.analysis[0].used_work == 2700.0 and _project(lab).budget.payments.size() == paid_count and int(_project(lab).next_attempt) == attempt, "Same paid target resume never charges a second credit/payment/attempt")
	task = _work_task(lab, team, executor, second_key)
	_check(_advance(lab, team, executor, second_key, task, 300.0).ok and second.build.progress == 600.0 and second.tech_batch.work_seconds == 300.0, "Only real build progress receives factor two; personal productive effort stays 300 seconds")
	var remaining := Runtime.technology_remaining_work(data, _project(lab), {"site_id": str(data.site.id), "person_id": executor})
	_check(remaining.ok and remaining.remaining_baseline == 33600.0, "Two retained ballista attempts use the greatest true unfinished unit fraction, never double subtract it")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(second))
	_check(Runtime.validate_technology_target_storage(data, second_key, decoded, "vehicle").ok, "Raw JSON strict optional original credit/ledger/token shape is admitted")
	Runtime.normalize_technology_target_storage(decoded)
	_check(decoded.tech_trial.attempt is int and decoded.tech_batch.source_version is int and decoded.tech_work_credit == second.tech_work_credit, "Store normalization preserves the immutable allocation and original bindings")
	for value: Variant in [NAN, INF, -1.0, 2701.0]:
		var credit_corrupt: Dictionary = second.duplicate(true)
		credit_corrupt.tech_work_credit.credit = value
		_check(not Runtime.validate_technology_target_storage(data, second_key, credit_corrupt, "vehicle").ok, "Malformed or excessive original credit cannot enter a save")
	var corrupt: Dictionary = second.duplicate(true)
	corrupt.erase("tech_trial")
	_check(not Runtime.validate_technology_target_storage(data, second_key, corrupt, "vehicle").ok, "A credit/paid token cannot become an unbound save-side speedup")
	corrupt = second.duplicate(true)
	corrupt.build.total_work = 2700.0
	_check(not Store._valid_siege_job(corrupt.build, Runtime.SIEGE_DEFINITIONS.ballista.cost, 5400.0, false), "Original Store still rejects analysis that rewrites the original baseline job")
	var release_a := Runtime.prepare_release_technology_operation(data, first.tech_trial, true)
	var stale := second.tech_trial.duplicate(true)
	stale.target_id = "vehicle:999999"
	before = var_to_bytes(data.site)
	person_before = var_to_bytes(row.technology)
	_check(release_a.ok and not Runtime.prepare_release_technology_operation(data, stale, true).ok and var_to_bytes(data.site) == before and var_to_bytes(row.technology) == person_before, "All-target stop preflight cannot partially publish when a later original source is stale")
	var released := Runtime.prepare_release_technology_operation(data, second.tech_trial, true)
	_check(released.ok and var_to_bytes(data.site) == before, "Permanent release remains pure until the authorized publisher")
	Runtime.publish_release_technology_operation(released)
	_check(second.build.progress == 600.0 and second.build.total_work == 5400.0 and not second.has("tech_trial") and not second.has("tech_work_credit") and second.tech_batch.token.is_empty() and row.technology.analysis[0].used_work == 2700.0, "Permanent abandonment retains actual paid work and spend, without refund or personal phase evidence")
	_check(_project(lab).receipts.is_empty() and not Technology.learned(row.technology, "F11"), "Abandonment cannot confer knowledge")
	_check(lab.site_controller.work_team.cancel(executor).ok, "Original task ends after this target is abandoned")
	started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", "vehicle:" + first_key)
	_check(started.ok and started.resumed and first.build.progress == 300.0 and first.tech_work_credit == {"remaining_work": 5100.0, "credit": 2550.0} and row.technology.analysis[0].used_work == 5250.0, "The original earlier paid attempt resumes with one allowance from its actual remaining work")
	task = _work_task(lab, team, executor, first_key)
	var completed := _advance(lab, team, executor, first_key, task, 2550.0)
	_check(completed.ok and completed.complete and first.build.is_empty() and first.phase == "idle", "The true original build completes through one physical owner endpoint")
	_check(not first.has("tech_trial") and not first.has("tech_work_credit") and first.technology_construction.work_seconds == 2850.0 and _project(lab).receipts.size() == 1, "Real paid completion keeps actual named effort and grants one personal phase receipt")
	_check(data.site.family.technology.siege_history.size() == 1 and data.site.family.technology.siege_history[0].vehicle_id == first_key and Family.validate_family(data.site.family, str(data.site.id)), "The same original completion atomically adds one bounded real family build history")
	_check(not Runtime.technology_siege_history_source_candidate(data, first_key, executor, task).ok, "Ready/finished vehicle status alone is not another completion source")
	_check(not Technology.learned(row.technology, "F11") and not data.site.family.technology.known.has("F11"), "One ballista does not replace the distinct tower phase or award the whole node")
	_check(Runtime.validate_technology_target_storage(data, first_key, first, "vehicle").ok, "Strict current original completed-event shape saves without an active trial")
	_check(lab.site_controller.work_team.cancel(executor).ok, "Actual worker is released by the original owner")
	var history_before := var_to_bytes(data.site.family.technology.siege_history)
	task = _work_task(lab, team, executor, second_key)
	completed = _advance(lab, team, executor, second_key, task, 4800.0)
	_check(completed.ok and completed.complete and second.build.is_empty() and not second.has("tech_batch") and _project(lab).receipts.size() == 1 and var_to_bytes(data.site.family.technology.siege_history) == history_before and row.technology.analysis[0].used_work == 5250.0, "Ordinary legal finishing of an abandoned paid target earns no personal research/reallocation or duplicate historical binding")
	_check(Runtime.validate_technology_target_storage(data, second_key, second, "vehicle").ok, "The original spent abandoned ledger is cleared at real ordinary completion, so the finished vehicle remains saveable")
	for identity: int in lab.site_controller.work_team.active_ids(): lab.site_controller.work_team.cancel(identity)
	lab.site_controller.work_team.discard_prepared_interval()
	lab.site_controller.work_team.unavailable = Callable()
	lab.site_controller.work_team.vehicle_blocked = Callable()
	team.controlled_person_query = Callable()
	team.person_busy_query = Callable()
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_WORK_CREDIT_PASS: %d checks; true original local payment/build/person credit/history/release; whole clock, 600s analysis provenance and full40 excluded" % checks)
	quit(0)
