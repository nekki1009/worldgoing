extends "res://scripts/tests/site_building_ui_test.gd"
## Requires the isolated F15 activation candidate and owner patches. NOT_RUN.
## Real original Family, Army, PersonActions, finite depot and shared fatigue.
## This bounded fixture does not assert Native, whole-point, GPU or tuning close.
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
var checks := 0

func _check(condition: bool, message: String) -> void:
	checks += 1
	assert(condition, message)

func _project(context: Dictionary) -> Dictionary:
	return Technology.active_project(context.data.site.family.technology)

func _scope_fixture() -> Dictionary:
	_check(Catalog.get_node("F15").enabled, "Positive fixture requires explicit isolated F15 candidate activation; formal false is preserved until acceptance")
	var data := _building_fixture()
	var lab := _building_lab(data)
	_check(lab.character.place(Vector2i(9, 10), true), "Actual controlled grantor is at the real camp")
	var control: int = lab.controlled_person_id()
	var team := TerrainArmy.new()
	lab.add_child(team)
	team.set_process(false)
	team.team_id = 401
	team.roster_size = 9
	team.faction_id = 1
	team.exchange_enabled = true
	var cells: Array[Vector2i] = [Vector2i(10, 11), Vector2i(9, 8), Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(10, 12), Vector2i(11, 12), Vector2i(12, 12), Vector2i(13, 12)]
	_check(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false), "Original Army creates real named NPC rows and commander")
	for row: Dictionary in team.combat_units:
		row.cargo = {}
		row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
	lab.combat_armies.append(team)
	team.vehicle_transport = lab.site_controller.vehicles
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	team.settle_combat_command()
	_check(team.set_duty_ai_enabled(team.combat_identity(team.current_commander), true).ok, "Actual source commander enables original NPC request admission")
	var executor := team.combat_identity(1)
	var refs: Array = []
	for identity: int in [control, executor, team.combat_identity(0)]:
		refs.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "原 F15 fixture 人物", "age_years": -1})
	_check(lab.site_controller.family_continuity.register_members(refs, true, control).ok and lab.site_controller.family_continuity.appoint_head(control, control).ok, "Actual registry/head owners establish this family")
	var actions: Variant = lab.site_controller.person_actions
	var family: Dictionary = actions._technology_candidate()
	family.technology = Technology.empty_scope_record(str(data.site.id))
	family.technology.known = ["F03"] # Explicit legitimate prerequisite archive.
	_check(Family.validate_family(family, str(data.site.id)), "Original family validator accepts the prerequisite precondition")
	data.site.family = family
	_check(actions.prepare_scope_technology(control, executor, "F15").ok, "Unlearned original Army member prepares the actual F15 route")
	var family_id := str(data.site.family.family_id)
	_check(actions.grant_scope_technology_budget(control, "family", family_id, {"arrow": 5, "cloth": 3, "charcoal": 3, "pottery": 2}).ok, "Original controlled camp owner grants the exact finite three craft costs")
	_check(actions.request_scope_technology_consent(control, "family", family_id, executor).ok, "Original team.work resolves and accepts the named purpose")
	return {"data": data, "lab": lab, "team": team, "actions": actions, "control": control, "executor": executor, "family_id": family_id}

func _close_scope(context: Dictionary) -> void:
	context.lab.site_controller.work_team.discard_prepared_interval()
	context.lab.free()

func _begin(context: Dictionary, binding: String) -> void:
	var begun: Dictionary = context.actions.begin_scope_technology_phase(context.control, "family", context.family_id, binding, "ranged:" + str(context.executor))
	_check(begun.ok, "Actual original named phase starts: " + str(begun))

func _advance_job(context: Dictionary, seconds: float) -> Dictionary:
	var requests: Array[Dictionary] = context.actions.work_requests(seconds)
	_check(requests.size() == 1, "Exactly the true original active craft request enters this fixture interval")
	var plan := PersonFatigue.plan_work_interval(requests, seconds)
	_check(plan.ok, "Original pure full-pool planner admits the actual finite interval")
	context.lab._shared_work_plan = plan
	context.lab._shared_work_pools_committed = false
	context.lab._commit_shared_work_pools()
	var own: Dictionary = plan.jobs.person_actions
	context.actions.advance(seconds, {"jobs": own})
	context.actions.settle_after_contacts()
	return plan

func _complete_job(context: Dictionary) -> void:
	var before := 0
	while context.actions.is_busy(context.executor):
		before += 1
		_check(before < 30, "Finite original craft must complete without a replacement timer")
		_advance_job(context, 30.0)

func _craft_all(context: Dictionary) -> void:
	var stock: Dictionary = context.data.site.inventory
	var old := stock.duplicate()
	_begin(context, "fire_arrow")
	_complete_job(context)
	_check(_project(context).receipts.size() == 1 and int(stock.arrow) == int(old.arrow) - 5 and int(stock.fire_arrow) == int(old.fire_arrow) + 5, "Actual baseline costs/output/receipt occur once")
	for batch: int in 2:
		_begin(context, "fire_pot")
		_complete_job(context)
		_check(_project(context).receipts.size() == batch + 2 and int(stock.fire_pot) == int(old.fire_pot) + batch + 1, "Two distinct original 90-second fire-pot batches each produce once")
	_check(int(stock.pottery) == int(old.pottery) - 2 and int(stock.cloth) == int(old.cloth) - 3 and int(stock.charcoal) == int(old.charcoal) - 3, "All actual F15 materials conserve the Catalog costs")

func _run() -> void:
	var context := _scope_fixture()
	var stock: Dictionary = context.data.site.inventory
	_begin(context, "fire_arrow")
	_complete_job(context)
	var baseline := stock.duplicate()
	_begin(context, "fire_pot")
	context.lab.restore_only = true
	var pool: Dictionary = PersonFatigue.pool(context.team.combat_units[1])
	_check(not pool.is_empty(), "Original Army binds the real shared fatigue pool")
	var fatigue := float(pool.fatigue)
	var plan := _advance_job(context, 40.0)
	var job: Dictionary = context.actions.job_for(context.executor)
	_check(is_equal_approx(float(job.elapsed), 20.0) and stock == baseline and _project(context).budget.payments.size() == 1, "Cold NPC research progresses at 0.5 with real effort, no premature material/output/payment")
	_check(plan.pools.size() == 1 and float(pool.fatigue) > fatigue, "One true Army pool is charged once; no detached proxy")
	PersonFatigue.write(context.team.combat_units[1], "fatigue", 80.0)
	context.team.combat_units[1].work_resting = true
	plan = _advance_job(context, 30.0)
	job = context.actions.job_for(context.executor) # job_for() returns a copy; read the current job.
	_check(job.paused == "REST" and float(job.elapsed) == 20.0 and float(plan.pools[0].effort_seconds) == 0.0 and stock == baseline, "Original 80 REST state pauses cold work and preserves unfinished progress with zero effort/materials")
	var captured: Dictionary = context.actions.export_cold_technology_jobs()
	_check(captured.ok and captured.state.version == 2 and captured.state.config_version == Technology.F15_COLD_CONFIG, "Original cold export carries the strict typed F15 job")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(captured.state))
	_check(context.actions.cancel(context.executor).ok, "Original cancellation removes the transient job without refunding earlier paid phases")
	for value: Variant in [89.0, INF, NAN, -1.0]:
		var invalid: Dictionary = decoded.duplicate(true)
		invalid.jobs[0].duration = value
		_check(not context.actions.prepare_restore_cold_technology_jobs(invalid).ok, "Invalid finite/duration field rejects independently while the original phase is still current")
	var before := var_to_bytes(context.data.site)
	var prepared: Dictionary = context.actions.prepare_restore_cold_technology_jobs(decoded)
	_check(prepared.ok and context.actions.can_publish_restore_cold_technology_jobs(prepared) and var_to_bytes(context.data.site) == before, "Restore candidate is pure and holds original people/material references")
	var holder: Dictionary = context.team.combat_units[1].item_state
	holder.version = int(holder.version) + 1
	_check(not context.actions.can_publish_restore_cold_technology_jobs(prepared), "A real original holder-version change invalidates the held restore before publication")
	holder.version = int(holder.version) - 1 # Fixture restores its prior source epoch only.
	_check(context.actions.publish_restore_cold_technology_jobs(prepared).ok and float(context.actions.job_for(context.executor).elapsed) == 20.0 and stock == baseline, "Publication restores exact unfinished work without advancing time, debit or output")
	_check(not context.actions.publish_restore_cold_technology_jobs(prepared).ok, "Same restore candidate cannot replace an already published original job")
	PersonFatigue.write(context.team.combat_units[1], "fatigue", 50.0) # Original recovered state precondition; no recovery clock claim.
	context.lab.restore_only = false
	_complete_job(context)
	_check(_project(context).receipts.size() == 2 and int(stock.fire_pot) == int(baseline.fire_pot) + 1 and int(stock.pottery) == int(baseline.pottery) - 1, "Resumed true batch consumes one complete cost and grants one receipt")
	_begin(context, "fire_pot")
	_complete_job(context)
	_check(_project(context).receipts.size() == 3 and _project(context).budget.payments.size() == 3 and not Technology.learned(context.team.combat_units[1].get("technology", {}), "F15"), "Craft repetition completes in order; actual shot/burn evidence still required for learning")
	var corrupt: Dictionary = decoded.duplicate(true)
	corrupt.jobs[0].duration = 89.0
	_check(not context.actions.prepare_restore_cold_technology_jobs(corrupt).ok, "Stale/short original work cannot be imported as a second batch")
	_close_scope(context)
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_FIRE_POT_SCOPE_PASS checks=", checks, " original finite 60/90/90 crafts, one-pool cold0.5, exact JSON restore and holder CAS; no shot/Native/GPU claim")
	quit(0)

## Every previous lifetime cap and spend entry is unchanged; the original budget candidate may only add a
## zero spend entry for the newly granted material.
func _lifetime_budget_preserved(prior: Dictionary, now: Dictionary) -> bool:
	for material: String in prior.spent:
		if not now.spent.has(material) or int(now.spent[material]) != int(prior.spent[material]): return false
	for material: String in now.spent:
		if not prior.spent.has(material) and int(now.spent[material]) != 0: return false
	for material: String in prior.cap:
		if not now.cap.has(material) or int(now.cap[material]) != int(prior.cap[material]): return false
	return true
