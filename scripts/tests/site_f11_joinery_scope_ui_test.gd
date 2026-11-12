extends "res://scripts/tests/site_family_first_earned_base.gd"
## Genuine original Actor/Army/Family and original controlled/WT registries.
## F09 is an explicit legal prerequisite. F11 must be earned from both real
## ballista/tower outputs before the ordinary UI selects the new joinery method.
## Genuine first research uses the original local shared caller and cold bind.
## Ordinary once-factor probes are explicit PA/WT components; Region/Native/
## combat-contact geometry, GPU/performance/default policy remain unverified.
const JoineryStore = preload("res://scripts/terrain_lab/site_store.gd")
const JoineryCatalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")

func _f11_team(lab: TerrainLab) -> TerrainArmy:
	var cells: Array[Vector2i] = []
	# Deploy beside the controlled Actor: a joined member counts as present only
	# within the formation's command radius.
	var origin: Vector2i = lab.character.terrain_cell
	for radius: int in range(1, 20):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius or cells.size() == 2: continue
				var cell := origin + Vector2i(x, y)
				if lab.terrain.contains(cell) and lab.terrain.is_walkable(cell) and not lab.site_controller.reserves_cell(cell): cells.append(cell)
		if cells.size() == 2: break
	_check(cells.size() == 2, "Two distinct original generated NPC deployment cells exist")
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 301
	team.roster_size = 2
	team.faction_id = 1
	team.person_id_allocator = Callable(lab, "_allocate_army_person_ids")
	_check(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false), "Original finite Army uses the SAME actual Actor/NPC refs before join")
	for row: Dictionary in team.combat_units:
		row.cargo = {}
		row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
	lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	team.settle_combat_command()
	_check(team.set_duty_ai_enabled(team.combat_identity(team.formal_commander), true).ok
		and team.join_player(lab.character).ok, "Actual Actor legally joins the original enabled living team")
	return team

func _f11_geometry(f: Dictionary, kind: String, near: Vector2i) -> Dictionary:
	var data: TerrainData = f.data
	for radius: int in range(201):
		for y: int in range(maxi(0, near.y-radius), mini(data.size.y, near.y+radius+1)):
			for x: int in range(maxi(0, near.x-radius), mini(data.size.x, near.x+radius+1)):
				if absi(x-near.x)+absi(y-near.y) != radius: continue
				var anchor := Vector2i(x,y)
				var proposed := {"kind":kind,"cell":data.index(anchor),"facing":[1,0]}
				var slots := Runtime.siege_work_slots(data, proposed)
				if slots.size() != 4: continue
				var before := var_to_bytes([data.site,f.actions._jobs,f.lab.character.technology])
				var checked := Runtime.begin_siege_build(data,kind,anchor,Vector2i.RIGHT,int(f.team.team_id),int(f.control),f.controller.reserves_cell,true)
				_check(var_to_bytes([data.site,f.actions._jobs,f.lab.character.technology]) == before, "Every original natural geometry preview is pure")
				if not checked.ok: continue
				var station := data.cell_from_index(int(slots[0].cell))
				_check(_f11_place(f.lab, station), "Actual named operator reaches this real prospective station")
				before = var_to_bytes([data.site,f.actions._jobs,f.lab.character.technology])
				checked = Runtime.begin_siege_build(data,kind,anchor,Vector2i.RIGHT,int(f.team.team_id),int(f.control),f.controller.reserves_cell,true,{},{},int(f.control))
				_check(var_to_bytes([data.site,f.actions._jobs,f.lab.character.technology]) == before, "Actual operator preview pays or publishes nothing")
				if checked.ok: return {"anchor":anchor,"station":station}
	_check(false,"Original finite natural scan must find one full legal paid vehicle footprint")
	return {}

func _f11_cold(f: Dictionary, keys: Array[String]) -> void:
	var retained := {}
	for key: String in keys: retained[key] = f.data.site.vehicles[key].duplicate(true)
	await _earned_cold(f,true)
	f.team = f.lab.player_army()
	# Grid simulation retired (Option C): the cold bind restores this grid team as a roster container; the data-only
	# fixture enables its original combat rows again exactly as its first deployment did.
	if f.team != null and not f.team.combat_enabled: _check(f.team.enable_combat(false), "The restored original team re-enables its real rows for the data-only work points")
	_check(f.team != null and f.team.index_for_identity(int(f.control)) == TerrainArmy.PLAYER_MEMBER, "Cold bind renews the SAME original Actor membership from the new owner graph")
	for key: String in keys: _check(f.data.site.vehicles[key] == retained[key], "Original cold graph retains exact paid vehicle geometry, marker, effort and history")

func _f11_fixture() -> Dictionary:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS,12345,{"max_height":1,"micro_strength":0.0})
	Env.initialize(data,"f11-original-first-earned-natural")
	for material: String in Env.ITEM_NAMES: data.site.inventory[material] = 10000
	data.site.capacity = 1000000
	var lab := _earned_natural_lab(data)
	lab.restore_only = false
	while float(lab.simulation_speed) < 4.0: lab.change_simulation_speed(1)
	# Grid data-only fixture (Option C): its cold reloads keep the grid roster instead of converting the Site to the crowd.
	lab.crowd_startup_requested = false
	var team := _f11_team(lab)
	var actions = lab.site_controller.person_actions
	var control := int(lab.controlled_person_id())
	var offices := team.team_offices()
	_check(team.apply_office_plan(team.combat_identity(team.formal_commander), int(offices.revision), [{"op": "appoint", "position_id": str(offices.duties["team.work"]), "person_id": control}]).ok, "Actual living original captain delegates its existing team.work office through the original transaction")
	_check(team.duty_resolve_readonly("team.work", team).decider == control, "Actual original work decider is the same joined controlled Actor")
	var refs: Array = []
	for identity: int in [control, int(lab.npc.person_id), team.combat_identity(0), team.combat_identity(1)]:
		refs.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "原人物", "age_years": -1})
	_check(lab.site_controller.family_continuity.register_members(refs, true, control).ok and lab.site_controller.family_continuity.appoint_head(control, control).ok, "Actual Family owner registers the real original people and current head")
	data.site.family = actions._technology_candidate()
	data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known = ["F09"]
	_check(Family.validate_family(data.site.family, str(data.site.id)) and not Technology.learned(lab.character.technology, "F11"), "Strict original family_id and only legitimate F09 prerequisite; F11 starts unlearned")
	_check(bool(JoineryCatalog.get_node("F11").get("enabled", false)), "Only an isolated enabled F11 candidate may run this positive source fixture")
	return {"data": data, "lab": lab, "team": team, "actions": actions, "control": control, "family_id": str(data.site.family.family_id), "controller": lab.site_controller, "tech_id": "F11", "cold_count": 0}

func _f11_point(f: Dictionary, seconds: float) -> Dictionary:
	var requests: Array = f.actions.work_requests(seconds)
	_check(requests.size() == 1, "One original controlled work request participates in this point")
	# As the original collector: the WorkTeam prepares its interval (none of its own here) first.
	var team_requests: Array = f.lab.site_controller.work_team.prepare_work_requests(seconds, seconds / 60.0, requests)
	var shared: Array = team_requests.duplicate()
	shared.append_array(requests)
	f.lab._shared_work_requests = shared
	_check(f.lab._refresh_shared_work_preflight().ok, "Actual original task/station/source revalidates before the held interval")
	requests = f.lab._shared_work_requests
	var captured = f.actions.prepare_shared_work_prefix(requests, seconds)
	var plan := PersonalFatigue.plan_work_interval(requests, seconds)
	_check(captured.ok and plan.ok, "Original provider captures true start refs and the original Fatigue planner admits effort")
	var before := var_to_bytes([f.data.site, f.lab.character.capture_state()])
	var admitted = f.actions.validate_shared_work_prefix(captured, plan, requests)
	var priors: Array = []
	# The original registry registers the allocation first, then validates the Runtime prefix.
	var registered = f.actions.prepare_checked_controlled_prefix_allocations(admitted, priors) if admitted.ok else admitted
	var checked = f.actions.validate_checked_controlled_runtime_prefixes(registered) if registered.ok else registered
	_check(checked.ok and var_to_bytes([f.data.site, f.lab.character.capture_state()]) == before, "All true Runtime work candidates are pure before original pool/material publication")
	f.lab._shared_work_plan = plan
	f.lab.site_controller._shared_work_plan = plan
	f.lab._shared_work_pools_committed = false
	f.lab._commit_shared_work_pools()
	f.actions.begin_shared_work_prefix_consumption(admitted)
	f.actions.publish_checked_controlled_prefixes(checked)
	var committed := var_to_bytes([f.data.site, f.lab.character.capture_state()])
	f.actions.publish_checked_controlled_prefixes(checked)
	f.lab._commit_shared_work_pools()
	_check(var_to_bytes([f.data.site, f.lab.character.capture_state()]) == committed, "Same true effort/fatigue/progress prefix publishes exactly once")
	f.actions.finish_checked_controlled_prefixes(checked)
	f.actions.end_shared_work_prefix_consumption()
	f.lab._clear_shared_work_step()
	return {"plan": plan, "checked": checked}

func _f11_finish(f: Dictionary, key: String) -> void:
	# Grid simulation retired (Option C): this fixture's team is a grid roster, so the whole-Lab step would run the retired
	# grid exchange. The same original controlled work runs through the explicit original shared-prefix point (_f11_point,
	# the PA/WT registry, Fatigue planner and Runtime prefix publication) until its true completed endpoint.
	var points := 0
	while f.actions.is_busy(int(f.control)) and points < 2000:
		_check(Time.get_ticks_msec() < deadline, "True original work stays within the named deadline")
		_f11_point(f, 90.0)
		points += 1
		if points % 64 == 0: await process_frame
	_check(f.data.site.vehicles[key].phase == "idle" and f.data.site.vehicles[key].build.is_empty(), "Original complete body/REST/work/contact caller reaches the true completed vehicle endpoint")

func _f11_bind_ordinary(f: Dictionary, key: String) -> void:
	var vehicle: Dictionary = f.data.site.vehicles[key]
	var stations := Runtime.siege_work_slots(f.data, vehicle)
	_check(_f11_place(f.lab, f.data.cell_from_index(int(stations[0].cell))), "Actual original Actor stands at the retained vehicle's true construction station")
	var prepared = f.actions.prepare_controlled_vehicle_work({}, vehicle, f.data.site.vehicles, int(f.control))
	_check(prepared.ok, "Original pure PA admission binds the retained ordinary paid vehicle without another payment")
	f.actions.publish_controlled_vehicle_work(prepared)
	_check(f.actions.is_busy(int(f.control)), "Original PA owns the genuine resumed same vehicle task")

func _f11_unlearned_helper_point(f: Dictionary, key: String) -> void:
	var workers = f.lab.site_controller.work_team
	var identity: int = f.team.combat_identity(1)
	var row: Dictionary = f.team.combat_units[1]
	_check(not Technology.learned(row.get("technology", {}), "F11"), "The original assisting NPC remains unlearned; no copied skill")
	var assigned = workers.prepare_assign_vehicle(f.team, [identity], int(f.control), key, f.data.site.vehicles[key], {}, {}, f.data.site.vehicles)
	_check(assigned.ok, "Original current work decider admits this genuine helper through the ordinary vehicle owner: " + str(assigned).left(300) + " decider=" + str(f.team.duty_resolve_readonly("team.work", f.team)).left(200)
		+ " enabled=%s order=%s combat_left=%s moving=%d player_moving=%s routed=%s plan=%s moving_to=%s" % [str(f.team.combat_enabled), str(f.team.combat_order), str(f.data.site.get("combat_left")),
		f.team.moving_member_count(), str(f.team.player_member.is_moving() if is_instance_valid(f.team.player_member) else null), str(f.team.is_sustain_routed()), str(f.team.get_active_move_plan()), str(f.team.moving_to)])
	workers.publish_assign_vehicle(assigned)
	var task: Dictionary = row.work_task
	f.team.cells[1] = f.data.cell_from_index(int(task.work_cell))
	# The placed body has no pending step or walking pose left from its cancelled route.
	f.team.moving_to[1] = TerrainArmy.INVALID_CELL
	f.team.combat_hot_set(1, &"pose", "idle")
	task.cell = int(task.work_cell)
	task.mode = "work"
	var facts := Runtime.work_preflight(f.data, task, row.cargo, 100, 1, identity, f.lab.site_controller.reserves_cell)
	_check(facts.ok and is_equal_approx(float(facts.productivity), 1.0), "True original unlearned helper gets basic productivity on the improved paid target")
	# This helper point starts rested: the earlier research pooled the team fatigue up to its 80 rest line.
	f.team.team_fatigue.fatigue = 0.0
	row["work_resting"] = false
	f.lab._shared_work_requests = workers.prepare_work_requests(30.0)
	_check(f.lab._refresh_shared_work_preflight().ok, "The true original NPC helper request is admitted at its exact original station")
	var captured = workers.prepare_shared_work_prefix(30.0)
	var plan := PersonalFatigue.plan_work_interval(f.lab._shared_work_requests, 30.0)
	var priors: Array = []
	var admitted = workers.validate_shared_work_prefix(captured, plan, priors)
	_check(captured.ok and plan.ok and admitted.ok, "Original WT registry and original Fatigue planner admit only this real helper effort")
	f.lab._shared_work_plan = plan
	f.lab.site_controller._shared_work_plan = plan
	f.lab._shared_work_pools_committed = false
	var before := float(f.data.site.vehicles[key].build.progress)
	f.lab._commit_shared_work_pools()
	workers.publish_shared_work_prefix(admitted)
	workers.finish_shared_work_prefix(admitted)
	_check(is_equal_approx(float(f.data.site.vehicles[key].build.progress) - before, 30.0), "Actual30helper effort adds only30physical work, never the learned master's factor")
	f.lab._clear_shared_work_step()
	_check(workers.cancel(identity).ok and not Technology.learned(row.get("technology", {}), "F11"), "Original helper can stop without any awarded research or skill")

func _f11_true_research_then_ordinary_ui() -> void:
	var f := _f11_fixture()
	var data: TerrainData = f.data
	var lab: TerrainLab = f.lab
	var controller := lab.site_controller
	var control := int(f.control)
	var original := _f11_geometry(f,"ram",Vector2i(20,35))
	var before := var_to_bytes([data.site, lab.character.technology, f.actions._jobs])
	_check(not Runtime.begin_siege_build(data, "ram", original.anchor, Vector2i.RIGHT, int(f.team.team_id), control, Callable(), true, {}, {}, control, "joinery").ok and var_to_bytes([data.site, lab.character.technology, f.actions._jobs]) == before, "Unlearned actual operator cannot obtain the improved new method or pay any cost")
	_check(_f11_place(lab, original.station), "True Actor reaches the original basic pre-learning ram station")
	var old_key := str(data.site.next_vehicle)
	_check(Runtime.begin_siege_build(data, "ram", original.anchor, Vector2i.RIGHT, int(f.team.team_id), control, controller.reserves_cell, false, {}, {}, control).ok, "Original eleven-argument basic admission starts one genuine pre-learning paid job")
	_check(not data.site.vehicles[old_key].has("technology_siege_method") and f.actions.cancel(control).ok, "Retained original paid job has no marker; stopping its person does not apply a future skill")
	_check(_f11_camp_contact(lab), "Same original grantor returns to the real camp contact")
	_check(f.actions.prepare_scope_technology(control, control, "F11").ok and f.actions.grant_scope_technology_budget(control, "family", str(f.family_id), {"wood": 144, "iron": 36, "fiber": 34, "cloth": 20}).ok and f.actions.request_scope_technology_consent(control, "family", str(f.family_id), control).ok, "Original head/source/actual work decider bind exactly the two full actual F11 phases")
	var stock = data.site.inventory.duplicate()
	for stage: Dictionary in [{"kind": "ballista", "binding": "ballista_build", "anchor": Vector2i(20, 20), "seconds": 5400.0}, {"kind": "siege_tower", "binding": "tower_build", "anchor": Vector2i(36, 20), "seconds": 28800.0}]:
		var real := _f11_geometry(f,str(stage.kind),stage.anchor)
		stage.anchor = real.anchor
		var key := str(data.site.next_vehicle)
		var request := {"anchor": stage.anchor, "facing": Vector2i.RIGHT, "team_id": int(f.team.team_id)}
		_check(_f11_place(lab, real.station), "Actual same unlearned trial executor stands at the distinct real phase station")
		_check(f.actions.begin_scope_technology_phase(control, "family", str(f.family_id), str(stage.binding), "vehicle:" + key, request).ok, "Original Scope phase admits this one genuine paid basic construction before F11 learning")
		var vehicle: Dictionary = data.site.vehicles[key]
		_check(float(vehicle.build.total_work) == float(stage.seconds) and not vehicle.has("technology_siege_method") and not vehicle.has("tech_work_credit"), "True research keeps the complete immutable baseline and no pre-awarded improved/analysis method")
		await _f11_finish(f, key)
		_check(vehicle.technology_construction.binding == stage.binding and is_equal_approx(float(vehicle.technology_construction.work_seconds), float(stage.seconds)), "Completed original witness records this same person's actual full baseline work")
		_check(not f.actions.is_busy(control), "Original actual phase endpoint retires its named person work")
	var project: Dictionary = data.site.family.technology.projects[0]
	_check(project.receipts.size() == 2 and project.budget.payments.size() == 2 and project.budget.spent == {"wood": 144, "iron": 36, "fiber": 34, "cloth": 20} and Technology.scope_known(data.site.family.technology, "F11") and Technology.learned(lab.character.technology, "F11"), "Only both true ballista/tower outputs and exact full payments teach original F11 and archive its family")
	for resource: String in project.budget.spent:
		_check(int(data.site.inventory[resource]) == int(stock[resource]) - int(project.budget.spent[resource]), "True original full research material conservation: " + resource)
	_f11_bind_ordinary(f, old_key)
	var old_job: Dictionary = f.actions._jobs[str(control)]
	var old_facts := Runtime.work_preflight(data, old_job.work_task, lab.character.ammo_inventory, 100, 1, control, controller.reserves_cell)
	_check(old_facts.ok and is_equal_approx(float(old_facts.productivity), 1.0), "Learning never retimes the already-started original basic job")
	_check(f.actions.cancel(control).ok, "Retain the old paid job without continuing it as improved")
	var column := VBoxContainer.new()
	root.add_child(column)
	var form := {"trial": false}
	controller._build_siege_construction_controls(column, form)
	for index: int in form.siege_kind.item_count:
		if form.siege_kind.get_item_metadata(index) == "ram": form.siege_kind.select(index)
	controller._refresh_siege_build_people(form)
	for index: int in form.siege_builder.item_count:
		if int(form.siege_builder.get_item_metadata(index)) == control: form.siege_builder.select(index)
	form.siege_method.select(1)
	var improved := _f11_geometry(f,"ram",Vector2i(40,35))
	controller.selected = improved.anchor
	_check(_f11_place(lab, improved.station), "Actual human-selected learned operator stands at the new original ram station")
	before = var_to_bytes([data.site, lab.character.technology, f.actions._jobs])
	controller._build_siege_ui(form, true)
	_check(var_to_bytes([data.site, lab.character.technology, f.actions._jobs]) == before, "Actual original UI preview gives no marker, stock debit, task or extra knowledge")
	var key := str(data.site.next_vehicle)
	await controller._build_siege_ui(form, false)
	var vehicle: Dictionary = data.site.vehicles[key]
	_check(vehicle.technology_siege_method == {"version": 1} and float(vehicle.build.total_work) == float(Runtime.SIEGE_DEFINITIONS.ram.work_seconds) and f.actions.is_busy(control), "Actual original UI starts one immutable improved marker and original paid construction task")
	var task: Dictionary = f.actions._jobs[str(control)].work_task
	var facts := Runtime.work_preflight(data, task, lab.character.ammo_inventory, 100, 1, control, controller.reserves_cell)
	_check(facts.ok and is_equal_approx(float(facts.productivity), 10.0 / 9.0) and is_equal_approx(float(facts.progress_multiplier), 1.0), "True current learned person receives only one method factor; no T6 double multiplier")
	var progress := float(vehicle.build.progress)
	var step := _f11_point(f, 90.0)
	var actual_effort := float(step.checked.checked.runtime[0].prefix_ref.productive_seconds)
	_check(actual_effort > 0.0 and actual_effort <= 90.0 and is_equal_approx(float(vehicle.build.progress) - progress, actual_effort * 10.0 / 9.0), "Actual original Fatigue-admitted effort receives the method factor exactly once; logical90 seconds never forge productive90")
	var observed_progress := float(vehicle.build.progress)
	_check(f.actions.cancel(control).ok, "Only the original held person job stops before the genuine cold checkpoint")
	await _f11_cold(f,[old_key,key])
	data = f.data
	vehicle = data.site.vehicles[key]
	_check(vehicle.technology_siege_method == {"version":1} and is_equal_approx(float(vehicle.build.progress),observed_progress), "True Controller cold bind preserves the observed original paid work; no target progress is fabricated")
	_f11_unlearned_helper_point(f, key)
	var malformed: Dictionary = vehicle.duplicate(true)
	malformed.technology_siege_method.extra = true
	_check(not Runtime.validate_technology_target_storage(data, key, malformed, "vehicle").ok, "Strict original target rejects extra method authority fields")
	malformed = vehicle.duplicate(true)
	malformed.kind = "siege_tower"
	_check(not Runtime.validate_technology_target_storage(data, key, malformed, "vehicle").ok, "Wood joinery marker never gates or improves a different original siege kind")
	_f11_bind_ordinary(f, key)
	await _f11_finish(f, key)
	_check(data.site.family.technology.projects[0].receipts.size() == 2 and not vehicle.has("tech_trial"), "Ordinary improved production does not issue another research receipt or a new skill")
	await _f11_cold(f,[old_key,key])
	data = f.data
	before = var_to_bytes([data.site,f.actions._jobs,lab.character.technology])
	_check(not f.actions.prepare_scope_technology(control,control,"F11").ok and var_to_bytes([data.site,f.actions._jobs,lab.character.technology]) == before, "Cold completed original F11 cannot repay, relearn or duplicate its first project")
	column.free()
	_cleanup_fixture(lab, f.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 540000
	await _f11_true_research_then_ordinary_ui()
	TerrainArmy.release_contact_source()
	print("SITE_F11_FIRST_EARNED_NATURAL_SHARED_COLD_FIXTURE: checks=%d; true shared research vehicles and Controller cold; ordinary UI/oncefactor components; NOT_RUN until canonical launch" % checks)
	quit(0)



## Camp contact is a walkable side cell of the depot (the depot cell itself is not adjacent).
func _f11_camp_contact(lab: TerrainLab) -> bool:
	var depot: Vector2i = lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))
	for side: Vector2i in TerrainData.DIRECTIONS:
		var cell := depot + side
		if lab.terrain.contains(cell) and lab.terrain.is_walkable(cell) and lab.terrain.can_step(cell, depot) and _f11_place(lab, cell): return true
	return false


## The joined Actor is present (and keeps its delegated office) only within the
## formation's command radius; the fixture keeps the small team beside it.
func _f11_place(lab: TerrainLab, cell: Vector2i) -> bool:
	# Move the team beside the target first, so none of it stands on the target cell.
	for team: TerrainArmy in lab.combat_armies:
		if int(team.team_id) != 301: continue
		var used := {cell: true}
		for index: int in team.combat_units.size():
			if not team.is_member(index): continue
			var placed := false
			for radius: int in range(1, 6):
				for y: int in range(-radius, radius + 1):
					for x: int in range(-radius, radius + 1):
						if placed or absi(x) + absi(y) != radius: continue
						var near := cell + Vector2i(x, y)
						if used.has(near) or not lab.terrain.contains(near) or not lab.terrain.is_walkable(near) or lab.site_controller.reserves_cell(near): continue
						team.cells[index] = near
						team.moving_to[index] = TerrainArmy.INVALID_CELL
						used[near] = true
						placed = true
	if not lab.character.place(cell, true): return false
	for team: TerrainArmy in lab.combat_armies:
		if int(team.team_id) == 301: team._refresh_reference_presence()
	return true
