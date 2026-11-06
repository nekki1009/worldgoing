extends "res://scripts/tests/site_settlement_first_earned_base.gd"
## Isolated admitted Catalog; true natural source, original people/work/Store
## and shared replay. No fixed-map, Native, GPU or whole-Region acceptance.
const ColdFatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
var cold_serial := 0

func _settlement_earned_id() -> String:
	return "S07"

func _p4_project(f: Dictionary) -> Dictionary:
	var owner: Dictionary = f.data.site.settlement if f.scope == "settlement" else f.data.site.family
	return Technology.active_project(owner.technology)

func _p4_body(f: Dictionary) -> Variant:
	return f.actions._person(int(f.worker)).body

func _p4_body_snapshot(f: Dictionary) -> Dictionary:
	var body: Variant = _p4_body(f)
	return body.duplicate(true) if body is Dictionary else body.capture_state()

func _p4_context(f: Dictionary) -> Dictionary:
	var fire: Dictionary = f.data.site.get("fire_settlement", {})
	return {"purpose": "region_checkpoint", "mode": "cold_exact" if f.lab.restore_only else "live",
		"source_generation": 0, "runtime_revision": 0, "token": "p4_original_" + str(Time.get_ticks_usec()),
		"game_seconds": Runtime.now(f.data) * 60.0, "action_seconds": float(f.lab.fire_action_cursor),
		"fire_epoch": str(fire.get("epoch", "")), "fire_sequence": int(fire.get("sequence", 0)),
		"interval_complete": true, "effects_complete": true, "mode_revision": 0, "backend": "gd", "events": [], "endpoint_payload": {}}

func _p4_checkpoint(f: Dictionary) -> String:
	# Actual existing non-Fire Region codec, never export_fire_jobs or manually
	# authored cold jobs. Zero revisions name the independent non-Slot fixture.
	f.controller._capture_positions()
	var context := _p4_context(f)
	var stamp: Dictionary = RegionSaveSlot.attach_settlement(f.data.site, context.game_seconds)
	_check(stamp.ok, "Original legacy migration stamps the actual completed Site endpoint, without retrospective work")
	var captured: Dictionary = f.lab.capture_region_owner_state(context)
	_check(captured.ok, "Actual Scene captures SAME original full owner graph: " + str(captured))
	var path := "user://p4_original_" + str(cold_serial) + "_" + str(Time.get_ticks_usec()) + ".json"
	cold_serial += 1
	var saved: Dictionary = Store.save_region_snapshot(f.data, path, context, captured.owner_states)
	_check(saved.ok, "Original Store admits actual NPC research mid-work/REST without a Fire exception: " + str(saved))
	return path

func _p4_open(f: Dictionary, path: String, retire: bool = true) -> Dictionary:
	var loaded: Dictionary = Store.load_site(path)
	_check(loaded.ok and loaded.data.site.has("region_snapshot"), "Actual Store checksum/source/body/owner cold read: " + str(loaded))
	_check(loaded.data.fingerprint() == f.data.fingerprint() and _earned_source_bytes(loaded.data) == _earned_source_bytes(f.data),
		"Original natural fingerprint and all five land-condition arrays reconstruct unchanged")
	var lab := TerrainLab.new()
	lab.restore_only = true # Original cold initializer, before ready: no live scene/input/default world.
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(loaded.data)
	_check(lab.region_bind_receipt(loaded.data).get("complete", false), "Original cold bind restores actual body/task/source aliases")
	while float(lab.simulation_speed) < 4.0: lab.change_simulation_speed(1)
	var result := f.duplicate()
	result.merge({"lab": lab, "data": lab.terrain, "controller": lab.site_controller, "actions": lab.site_controller.person_actions}, true)
	result.team = result.actions._technology_team(result.actions._person(int(f.worker)))
	_check(result.team is TerrainArmy and int(result.team.team_id) == int(f.team.team_id)
		and not is_same(result.data.site, f.data.site) and not is_same(_p4_body(result), _p4_body(f)),
		"Original cold graph renews true references and preserves original person/team identity")
	if retire:
		var previous_teams: Array = f.lab.combat_armies.duplicate()
		f.lab.free()
		for team: TerrainArmy in previous_teams:
			if is_instance_valid(team): team.free()
	return result

func _p4_advance(f: Dictionary, game_seconds: float) -> void:
	var target := Runtime.now(f.data) * 60.0 + game_seconds
	var result: Dictionary = f.lab.replay_site_to(target)
	_check(result.ok and result.get("status") == "COMPLETE" and absf(Runtime.now(f.data) * 60.0 - target) < 0.0000001,
		"Original replay consumes the one fixed endpoint and produces a non-Fire cold checkpoint: " + str(result))
	var prior := var_to_bytes([_p4_body_snapshot(f), f.data.site.inventory, f.data.site.family, f.data.site.settlement, f.actions._jobs])
	var cursor := float(f.lab.fire_action_cursor)
	var repeated: Dictionary = f.lab.replay_site_to(target)
	_check(repeated.ok and repeated.get("steps") == 0 and float(f.lab.fire_action_cursor) == cursor
		and var_to_bytes([_p4_body_snapshot(f), f.data.site.inventory, f.data.site.family, f.data.site.settlement, f.actions._jobs]) == prior,
		"Original replay watermark cannot duplicate effort, material, phase, product or knowledge")

func _p4_register_worker(f: Dictionary) -> void:
	f.worker = f.team.combat_identity(1)
	var refs: Array = f.data.site.family.members.duplicate(true)
	refs.append({"site_id": str(f.data.site.id), "person_id": int(f.worker), "path": "", "label": "原冷科研工匠", "age_years": -1})
	_check(f.controller.family_continuity.register_members(refs, true, int(f.control)).ok,
		"Original roster registers the SAME existing Army worker; no created research person")
	f.data.site.family = f.actions._technology_candidate()
	f.family_id = str(f.data.site.family.family_id)
	_check(Family.validate_family(f.data.site.family, str(f.data.site.id)), "Strict original stable Family v3 remains valid")

func _p4_station(f: Dictionary, cell: Vector2i) -> void:
	# Explicit physical fixture placement excludes travel acceptance. Actual
	# subsequent work uses this SAME Army row and its original fixed work slot.
	_check(f.data.is_walkable(cell), "Original generated physical work station")
	f.team.cells[f.team.index_for_identity(int(f.worker))] = cell
	var row: Variant = _p4_body(f)
	if not row.get("work_task", {}).is_empty(): row.work_task.cell = f.data.index(cell)

func _p4_f07_ranged() -> Dictionary:
	var f := _settlement_fixture()
	f.scope = "family"
	f.initial_depot_items = f.data.site.depot_items.item_ids.size()
	_p4_register_worker(f)
	var depot = f.data.cell_from_index(int(f.data.site.depot_cell))
	var contact := Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell: Vector2i = depot + direction
		if f.data.is_walkable(cell) and f.data.can_step(depot, cell) and not f.controller.reserves_cell(cell): contact = cell; break
	_check(contact.x >= 0, "Actual unoccupied original camp contact for the original NPC")
	_p4_station(f, contact)
	# The grant is a hand-craft action of the controlled person: he stands on another legal cell next to the camp.
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell: Vector2i = depot + direction
		if cell != contact and f.data.is_walkable(cell) and f.data.can_step(depot, cell) and not f.controller.reserves_cell(cell) and f.lab.character.place(cell, true): break
	var f07_prepared: Dictionary = f.actions.prepare_technology(int(f.control), int(f.worker))
	var f07_consent: Dictionary = f.actions.request_technology_consent(int(f.control), int(f.worker)) if f07_prepared.ok else {}
	var f07_grant: Dictionary = f.actions.grant_technology_budget(int(f.control), {"wood": 12, "fiber": 6}) if f07_consent.get("ok", false) else {}
	_check(f07_prepared.ok and f07_consent.get("ok", false) and f07_grant.get("ok", false),
		"Original F07 selects genuine unknown NPC, real team consent and finite material grant: %s %s %s" % [str(f07_prepared), str(f07_consent), str(f07_grant)])
	_check(f.actions.begin_technology_trial(int(f.control), int(f.worker)).ok, "Actual original NPC bow job starts")
	for index: int in 8:
		var point: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		_check(point.ok and point.get("completed", false), "Original warm main point")
	var job: Dictionary = f.actions._jobs[str(f.worker)]
	_check(float(job.elapsed) > 0.0 and float(job.elapsed) < 120.0 and f.actions.save_guard().code == "BUSY"
		and not f.actions.export_fire_jobs(float(f.lab.fire_action_cursor)).ok and not f.lab.capture_fire_owner_state().ok
		and not Technology.learned(_p4_body(f).get("technology", {}), "F07"), "Partial original job does not fabricate a bow or permit ordinary manual save")
	var path := _p4_checkpoint(f)
	var left := _p4_open(f, path, false)
	var right := _p4_open(f, path, false)
	var start := float(left.actions._jobs[str(left.worker)].elapsed)
	var fatigue := ColdFatigue.read(_p4_body(left))
	_p4_advance(left, 12.0)
	_p4_advance(right, 6.0)
	_p4_advance(right, 6.0)
	_check(absf(float(left.actions._jobs[str(left.worker)].elapsed) - start - 6.0) < 0.000001
		and absf(float(right.actions._jobs[str(right.worker)].elapsed) - float(left.actions._jobs[str(left.worker)].elapsed)) < 0.000001
		and absf(ColdFatigue.read(_p4_body(left)) - ColdFatigue.read(_p4_body(right))) < 0.000001,
		"Ranged research effective time is half; original long/split effort and fatigue agree")
	_check(absf(ColdFatigue.read(_p4_body(left)) - fatigue - 12.0 * ColdFatigue.effort_rate(_p4_body(left))) < 0.000001,
		"Half research never halves the original NPC's actual fatigue")
	var inherited_jobs := var_to_bytes(left.actions._jobs)
	var inherited_body := var_to_bytes(_p4_body(left))
	_check(not left.lab.replay_site_to(Runtime.now(left.data) * 60.0 - 1.0).ok
		and var_to_bytes(left.actions._jobs) == inherited_jobs and var_to_bytes(_p4_body(left)) == inherited_body,
		"An earlier endpoint cannot erase paid job/body/clock history")
	var rest := left
	ColdFatigue.write(_p4_body(rest), "fatigue", ColdFatigue.WORK_REST_AT)
	_p4_body(rest).work_resting = true # Explicit legal REST starting-state input, not invented work evidence.
	_p4_advance(rest, 2.0)
	_check(rest.actions._jobs[str(rest.worker)].paused == "REST" and absf(float(rest.actions._jobs[str(rest.worker)].elapsed) - start - 6.0) < 0.000001,
		"Original REST interval retains the job without productive work")
	var rest_elapsed := float(rest.actions._jobs[str(rest.worker)].elapsed)
	var rest_fatigue := ColdFatigue.read(_p4_body(rest))
	var rest_budget: Dictionary = _p4_project(rest).budget.duplicate(true)
	rest = _p4_open(rest, _p4_checkpoint(rest))
	_check(float(rest.actions._jobs[str(rest.worker)].elapsed) == rest_elapsed and ColdFatigue.read(_p4_body(rest)) == rest_fatigue
		and _p4_project(rest).budget == rest_budget and _p4_body(rest).work_resting,
		"Actual Store load/bind retains REST/body/finite grant and the SAME job attempt")
	# Finish using only original replay and original PA completion. The large
	# window includes original rest/cooldown; it never assigns elapsed/progress.
	while rest.actions.is_busy(int(rest.worker)):
		_check(Time.get_ticks_msec() < deadline, "Bounded true REST/resume fixture")
		_p4_advance(rest, 30.0)
	for stage: int in range(1, 3):
		_check(rest.actions.begin_technology_trial(int(rest.control), int(rest.worker)).ok, "Same original NPC explicitly starts the next finite attempt")
		while rest.actions.is_busy(int(rest.worker)):
			_p4_advance(rest, 30.0)
	_check(Technology.learned(_p4_body(rest).get("technology", {}), "F07") and Technology.scope_known(rest.data.site.family.technology, "F07")
		and _p4_project(rest).is_empty(), "Three real bows teach the original cold NPC; no active project is left")
	var completed: Dictionary = rest.data.site.family.technology.projects[0]
	_check(completed.receipts.size() == 3 and completed.budget.spent == {"wood": 12, "fiber": 6}
		and rest.data.site.depot_items.item_ids.size() == int(rest.initial_depot_items) + 3, "Exactly three original products/receipts and one finite aggregate material use")
	var finished := _p4_open(rest, _p4_checkpoint(rest))
	var bytes := var_to_bytes([finished.data.site, _p4_body(finished)])
	_check(not finished.actions.begin_technology_trial(int(finished.control), int(finished.worker)).ok
		and var_to_bytes([finished.data.site, _p4_body(finished)]) == bytes, "True final cold replay cannot regrant or duplicate the completed research")
	right.lab.free()
	f.lab.free()
	return finished

func _p4_feature(f: Dictionary, identity: String, key: String) -> Dictionary:
	f.scope = "settlement" if identity == "S07" else "family"
	f.tech_id = identity
	f.scope_id = str(f.data.site.settlement.settlement_id) if f.scope == "settlement" else str(f.family_id)
	if identity == "F04":
		var archive: Dictionary = f.data.site.family.technology.duplicate(true)
		if int(archive.version) == 1: archive.version = 2
		if not archive.known.has("F03"): archive.known.append("F03") # Explicit prerequisite archive only, never target F04; retain all real F07 history.
		_check(Technology.valid_scope_record(archive, "family"), "Strict extended archive preserves all original real F07 receipts")
		f.data.site.family.technology = archive
	var node := EarnedCatalog.get_node(identity)
	_check(node.enabled and not Technology.scope_known(f.data.site.settlement.get("technology", {}) if f.scope == "settlement" else f.data.site.family.technology, identity),
		"Independently admitted isolated node is genuinely unknown")
	_check(f.lab.character.place(f.data.cell_from_index(int(f.data.site.depot_cell)), true), "Original grantor physically contacts the camp")
	_check(f.actions.prepare_scope_technology(int(f.control), int(f.worker), identity, str(f.scope_id)).ok, "Original current authority prepares one named unknown project")
	var cap := {}
	for phase: Dictionary in node.research.routes[0].phases:
		for material: String in phase.materials: cap[material] = int(cap.get(material, 0)) + int(phase.materials[material]) * int(phase.repeat)
	_check(f.actions.grant_scope_technology_budget(int(f.control), str(f.scope), str(f.scope_id), cap).ok
		and f.actions.request_scope_technology_consent(int(f.control), str(f.scope), str(f.scope_id), int(f.worker)).ok,
		"Original finite grant and current original team's named consent remain the only authority")
	var prior_receipts = _p4_project(f).receipts.size()
	var phase := Technology.scope_next_phase(_p4_project(f), _p4_project(f).executor)
	_p4_station(f, f.data.cell_from_index(int(f.data.site.features[key].entrance)))
	var started: Dictionary = f.actions.begin_scope_technology_phase(int(f.control), str(f.scope), str(f.scope_id), str(phase.binding), "feature:" + key)
	_check(started.ok and f.data.site.features[key].batch_paid, "Original SAME feature/named WT task pays the full input once: " + str(started))
	var row: Variant = _p4_body(f)
	_check(row.work_task.version == 3 and row.work_task.named and f.controller.work_team.is_assigned(int(f.worker)), "Only the original v3 Army job holds the real physical work")
	row.work_task.cell = f.data.index(f.actions._person(int(f.worker)).cell)
	row.work_task.mode = "work"
	var preflight: Dictionary = Runtime.work_preflight(f.data, row.work_task, row.cargo, Runtime.CARRY_CAPACITY, 1, int(f.worker))
	_check(preflight.ok and float(preflight.progress_multiplier) == 0.5, "Cold research physical preflight scales effective progress only: " + str(preflight))
	var production := float(f.data.site.features[key].production)
	var effort := float(f.data.site.features[key].tech_batch.work_seconds)
	var fatigue := ColdFatigue.read(row)
	var spent: Dictionary = _p4_project(f).budget.spent.duplicate(true)
	_p4_advance(f, 12.0)
	var productive := ColdFatigue.work_seconds(fatigue, 12.0, ColdFatigue.effort_rate(row))
	_check(absf((float(f.data.site.features[key].production) - production) * 60.0 - productive * 0.5 * float(preflight.productivity)) < 0.000001
		and absf(float(f.data.site.features[key].tech_batch.work_seconds) - effort - productive) < 0.000001
		and absf(ColdFatigue.read(row) - fatigue - 12.0 * ColdFatigue.effort_rate(row)) < 0.000001
		and _p4_project(f).budget.spent == spent, "Original feature retains unweighted canonical work/full effort fatigue, half output and one actual payment")
	var progress := float(f.data.site.features[key].production)
	var payment: Dictionary = f.data.site.features[key].tech_batch.duplicate(true)
	var original_task: Dictionary = row.work_task.duplicate(true)
	f = _p4_open(f, _p4_checkpoint(f))
	_check(float(f.data.site.features[key].production) == progress and f.data.site.features[key].tech_batch == payment
		and _p4_body(f).work_task == original_task and _p4_project(f).budget.spent == spent,
		"Actual Store preserves original feature/one paid token/v3 task/fatigue/project identity mid-work")
	var malformed := TerrainLab._region_detached_bind_data(f.data)
	malformed.site.features[key].tech_trial.attempt += 1
	var retained_path := _p4_checkpoint(f)
	var prior_file := FileAccess.get_sha256(retained_path)
	var corrupt := Runtime.validate_technology_trial_project_storage(malformed, malformed.site.features[key])
	_check(not corrupt.ok and not Store._validate_state(malformed, malformed.site).ok and not prior_file.is_empty() and FileAccess.get_sha256(retained_path) == prior_file,
		"Malformed cold attempt is refused by original target/project/Store before bind")
	var rest_progress := float(f.data.site.features[key].production)
	ColdFatigue.write(_p4_body(f), "fatigue", ColdFatigue.WORK_REST_AT)
	_p4_body(f).work_resting = true # Explicit REST state, never elapsed or progress.
	_p4_advance(f, 2.0)
	_check(_p4_body(f).work_task.mode == "rest" and float(f.data.site.features[key].production) == rest_progress,
		"Original physical REST pauses output while retaining the actual paid target")
	f = _p4_open(f, _p4_checkpoint(f))
	_check(_p4_body(f).work_resting and _p4_body(f).work_task.mode == "rest"
		and float(f.data.site.features[key].production) == rest_progress and _p4_project(f).budget.spent == spent,
		"Original Store and graph bind preserve physical REST without recharging source")
	while f.data.site.features[key].has("tech_trial"):
		_check(Time.get_ticks_msec() < deadline, "Finite genuine original physical phase finishes")
		_p4_advance(f, 30.0)
	var retained := _p4_project(f)
	if retained.is_empty(): retained = f.data.site.settlement.technology.projects[0] if f.scope == "settlement" else f.data.site.family.technology.projects[-1]
	_check(retained.receipts.size() == prior_receipts + 1 and float(retained.receipts[-1].work_seconds) >= float(phase.seconds) * 2.0 - 0.000001,
		"True cold output receipts contain original actual effort rather than nominal half work")
	return f

func _p4_siege_token(f: Dictionary, target: String) -> Dictionary:
	var record: Dictionary = f.data.site.family.technology
	var project := _p4_project(f)
	var phase := Technology.scope_next_phase(project, project.executor, record.get("person_links", []))
	return {"scope": "family", "scope_id": str(f.family_id), "project_id": int(project.id), "epoch": int(record.epoch),
		"purpose": str(project.purpose), "tech_id": str(project.tech_id), "phase_id": str(phase.id), "attempt": int(project.next_attempt),
		"person": project.executor.duplicate(), "binding": str(phase.binding), "target_id": target, "materials": phase.materials.duplicate(true)}

func _p4_siege_geometry(f: Dictionary, token: Dictionary) -> Dictionary:
	for y: int in range(f.data.size.y):
		for x: int in range(f.data.size.x):
			var anchor := Vector2i(x, y)
			var probe := {"kind": "ballista", "cell": f.data.index(anchor), "facing": [1, 0]}
			var slots := Runtime.siege_work_slots(f.data, probe)
			if slots.size() != 4: continue
			var station = f.data.cell_from_index(int(slots[0].cell))
			if not f.data.is_walkable(station) or f.controller.reserves_cell(station): continue
			_p4_station(f, station)
			var request := {"anchor": anchor, "facing": Vector2i.RIGHT, "team_id": int(f.team.team_id)}
			var before := var_to_bytes([f.data.site, _p4_body(f), f.actions._jobs])
			var preview := Runtime.begin_technology_operation(f.data, token, true, request)
			_check(var_to_bytes([f.data.site, _p4_body(f), f.actions._jobs]) == before, "Pure original full geometry/source/consent preview")
			if preview.ok: return request
	_check(false, "True natural terrain must supply one full bounded original ballista/work footprint")
	return {}

func _p4_siege(f: Dictionary) -> Dictionary:
	f.scope = "family"
	f.scope_id = str(f.family_id)
	var archive: Dictionary = f.data.site.family.technology.duplicate(true)
	if not archive.known.has("F09"): archive.known.append("F09") # Explicit unrelated prerequisite archive; never target F11.
	_check(Technology.valid_scope_record(archive, "family"), "Real F07/F04 histories remain valid alongside the F09 prerequisite")
	f.data.site.family.technology = archive
	_check(f.lab.character.place(f.data.cell_from_index(int(f.data.site.depot_cell)), true), "Actual original human grantor contacts the camp")
	_check(f.actions.prepare_scope_technology(int(f.control), int(f.worker), "F11", str(f.family_id)).ok
		and f.actions.grant_scope_technology_budget(int(f.control), "family", str(f.family_id), {"wood": 144, "iron": 36, "fiber": 34, "cloth": 20}).ok
		and f.actions.request_scope_technology_consent(int(f.control), "family", str(f.family_id), int(f.worker)).ok,
		"Unknown actual NPC F11 project receives original finite authority and team consent")
	var key := str(f.data.site.next_vehicle)
	var token := _p4_siege_token(f, "vehicle:" + key)
	var request := _p4_siege_geometry(f, token)
	var started: Dictionary = f.actions.begin_scope_technology_phase(int(f.control), "family", str(f.family_id), "ballista_build", "vehicle:" + key, request)
	_check(started.ok and _p4_body(f).work_task.version == 3 and _p4_body(f).work_task.named,
		"Original true paid vehicle construction and SAME WT row start atomically: " + str(started))
	var task: Dictionary = _p4_body(f).work_task
	_p4_station(f, f.data.cell_from_index(int(task.work_cell)))
	task.mode = "work"
	var facts := Runtime.work_preflight(f.data, task, _p4_body(f).cargo, Runtime.CARRY_CAPACITY, 1, int(f.worker), f.controller.reserves_cell)
	_check(facts.ok and is_equal_approx(float(facts.progress_multiplier), 0.5), "Vehicle cold work uses half effective progress without a second effort multiplier")
	var vehicle: Dictionary = f.data.site.vehicles[key]
	var before := float(vehicle.build.progress)
	var effort := float(vehicle.tech_batch.work_seconds)
	var fatigue := ColdFatigue.read(_p4_body(f))
	var rate := ColdFatigue.effort_rate(_p4_body(f))
	var budget: Dictionary = _p4_project(f).budget.duplicate(true)
	_p4_advance(f, 12.0)
	_check(absf(float(vehicle.build.progress) - before - ColdFatigue.work_seconds(fatigue, 12.0, rate) * 0.5) < 0.000001
		and absf(float(vehicle.tech_batch.work_seconds) - effort - ColdFatigue.work_seconds(fatigue, 12.0, rate)) < 0.000001
		and absf(ColdFatigue.read(_p4_body(f)) - fatigue - 12.0 * rate) < 0.000001,
		"One actual vehicle prefix preserves canonical unweighted work/full fatigue with half physical construction")
	var progress := float(vehicle.build.progress)
	ColdFatigue.write(_p4_body(f), "fatigue", ColdFatigue.WORK_REST_AT)
	_p4_body(f).work_resting = true
	_p4_advance(f, 2.0)
	_check(_p4_body(f).work_task.mode == "rest" and float(vehicle.build.progress) == progress, "Original siege REST has no productive progress")
	f = _p4_open(f, _p4_checkpoint(f))
	vehicle = f.data.site.vehicles[key]
	_check(_p4_body(f).work_resting and _p4_body(f).work_task.mode == "rest" and float(vehicle.build.progress) == progress
		and _p4_project(f).budget == budget, "True Store/body/graph restore retains the original siege paid REST state")
	_check(f.controller.work_team.cancel(int(f.worker)).ok, "Only the original worker job stops; paid vehicle/project remain")
	_p4_advance(f, 2.0)
	_check(float(vehicle.build.progress) == progress and _p4_project(f).budget == budget, "No true at-work executor means no research work or new payment")
	f = _p4_open(f, _p4_checkpoint(f))
	vehicle = f.data.site.vehicles[key]
	var resumed: Dictionary = f.actions.begin_scope_technology_phase(int(f.control), "family", str(f.family_id), "ballista_build", "vehicle:" + key)
	_check(resumed.ok and resumed.resumed and _p4_project(f).budget == budget,
		"Current original authority explicitly resumes the SAME cold paid attempt without another source charge: " + str(resumed))
	while vehicle.has("tech_trial"):
		_check(Time.get_ticks_msec() < deadline, "Bounded actual half-rate original ballista completion")
		_p4_advance(f, 60.0)
	_check(vehicle.phase == "idle" and vehicle.build.is_empty() and vehicle.technology_construction.binding == "ballista_build"
		and float(vehicle.technology_construction.work_seconds) >= 10800.0 - 0.000001
		and _p4_project(f).receipts.size() == 1 and _p4_project(f).budget.spent == {"wood": 24, "iron": 12, "fiber": 10}
		and not Technology.learned(_p4_body(f).get("technology", {}), "F11")
		and Technology.scope_next_phase(_p4_project(f), _p4_project(f).executor).binding == "tower_build",
		"One genuine cold ballista completion advances only this same person's next tower phase; never a whole F11 acceptance")
	return _p4_open(f, _p4_checkpoint(f))

func _run() -> void:
	deadline = Time.get_ticks_msec() + 600000
	var f := _p4_f07_ranged()
	f = _p4_feature(f, "S07", str(f.keys.smithy))
	f = _p4_feature(f, "S07", str(f.keys.smithy))
	_check(Technology.scope_known(f.data.site.settlement.technology, "S07")
		and f.data.site.settlement.technology.projects[0].receipts.size() == 2
		and f.data.site.settlement.technology.projects[0].budget.spent == {"wood": 8, "fiber": 4},
		"Only two real distinct cold workshop bows complete S07 with one cumulative budget")
	f = _p4_open(f, _p4_checkpoint(f))
	# F04 exercises a different Family purpose after the actual F07 receipt and
	# actual S07 first phase. Host setup reuses only legal natural original owners.
	var smelter := _earned_host(f.data, "smelter", Vector2i(40, 40))
	_earned_host(f.data, "well", f.data.cell_from_index(int(f.data.site.features[smelter].cells[0])), Vector2i.ONE, 5)
	Runtime.rebuild_water(f.data)
	f = _p4_feature(f, "F04", smelter)
	_check(not Technology.learned(_p4_body(f).get("technology", {}), "F04") and Technology.scope_next_phase(_p4_project(f), _p4_project(f).executor).binding == "steel",
		"Real first iron output advances only the same person's next phase, not target knowledge")
	f = _p4_feature(f, "F04", smelter)
	_check(not Technology.learned(_p4_body(f).get("technology", {}), "F04")
		and Technology.scope_next_phase(_p4_project(f), _p4_project(f).executor).binding == "steel_tools",
		"True second cold steel phase advances the same original purpose, not knowledge")
	f = _p4_feature(f, "F04", str(f.keys.smithy))
	_check(Technology.scope_known(f.data.site.family.technology, "F04")
		and Technology.learned(_p4_body(f).get("technology", {}), "F04")
		and f.data.site.family.technology.projects[-1].receipts.size() == 3
		and f.data.site.family.technology.projects[-1].budget.spent == {"iron_ore": 3, "charcoal": 5, "iron": 2, "steel": 1, "wood": 1},
		"Only all three real cold material/output phases teach F04 to this actual executor")
	f = _p4_open(f, _p4_checkpoint(f))
	f = _p4_siege(f)
	_cleanup_fixture(f.lab, f.team)
	await _p4_controlled_lane("F04")
	await _p4_controlled_lane("F11")
	print("P4_COLD_ORIGINAL_RESEARCH_COMPONENT_PASS checks=", checks, " source=nature+originalStore/Region-owner/shared-replay noNative/fixed/GPU/fullRegion")
	quit(0)

func _p4_controlled_target(f: Dictionary, identity: String) -> Dictionary:
	if identity == "F04":
		var key := _earned_host(f.data, "smelter", Vector2i(40, 40))
		_earned_host(f.data, "well", f.data.cell_from_index(int(f.data.site.features[key].cells[0])), Vector2i.ONE, 5)
		Runtime.rebuild_water(f.data)
		_check(f.lab.character.place(f.data.cell_from_index(int(f.data.site.features[key].entrance)), true),
			"Original controlled Actor stands at this real generated smelter entrance")
		return {"target": "feature:" + key, "key": key, "binding": "iron", "request": {}}
	var key := str(f.data.site.next_vehicle)
	var token := _p4_siege_token(f, "vehicle:" + key)
	for y: int in range(f.data.size.y):
		for x: int in range(f.data.size.x):
			var anchor := Vector2i(x, y)
			var probe := {"kind": "ballista", "cell": f.data.index(anchor), "facing": [1, 0]}
			var slots := Runtime.siege_work_slots(f.data, probe)
			if slots.size() != 4: continue
			var station = f.data.cell_from_index(int(slots[0].cell))
			if not f.data.is_walkable(station) or f.controller.reserves_cell(station): continue
			if not f.lab.character.place(station, true): continue # Explicit physical fixture input, no travel claim.
			var request := {"anchor": anchor, "facing": Vector2i.RIGHT, "team_id": int(f.team.team_id)}
			var before := var_to_bytes([f.data.site, f.lab.character.capture_state(), f.actions._jobs])
			var preview := Runtime.begin_technology_operation(f.data, token, true, request)
			_check(var_to_bytes([f.data.site, f.lab.character.capture_state(), f.actions._jobs]) == before,
				"Original controlled full-geometry preview is pure")
			if preview.ok: return {"target": "vehicle:" + key, "key": key, "binding": "ballista_build", "request": request}
	_check(false, "True natural source must supply an original controlled full ballista footprint")
	return {}

func _p4_controlled_lane(identity: String) -> void:
	var f := _settlement_fixture()
	f.scope = "family"
	_p4_register_worker(f)
	var next_control := int(f.worker) # SAME registered living Army person, never a manufactured controller.
	f.worker = int(f.control) # SAME original Actor starts the genuine PA physical research job.
	f.scope_id = str(f.family_id)
	var archive: Dictionary = f.data.site.family.technology.duplicate(true)
	if int(archive.version) == 1: archive.version = 2
	archive.known.append("F03" if identity == "F04" else "F09") # Explicit prerequisite archive; tested target remains unknown.
	_check(Technology.valid_scope_record(archive, "family"), "Controlled research prerequisite archive uses strict original Family v3")
	f.data.site.family.technology = archive
	var idle_path := _p4_checkpoint(f)
	f = _p4_open(f, idle_path) # True Store/read/bind establishes cold mode before the public manual command.
	_check(f.lab.controlled_person_id() == int(f.worker) and not Technology.scope_known(f.data.site.family.technology, identity)
		and not Technology.learned(f.lab.character.technology, identity), "Actual cold Actor starts unknown, with only named prerequisite knowledge")
	_check(f.lab.character.place(f.data.cell_from_index(int(f.data.site.depot_cell)), true), "Original grantor contacts the actual finite camp source")
	var cap := {"iron_ore": 3, "charcoal": 5, "iron": 2, "steel": 1, "wood": 1} if identity == "F04" else {"wood": 144, "iron": 36, "fiber": 34, "cloth": 20}
	_check(f.actions.prepare_scope_technology(int(f.worker), int(f.worker), identity, str(f.scope_id)).ok
		and f.actions.grant_scope_technology_budget(int(f.worker), "family", str(f.scope_id), cap).ok
		and f.actions.request_scope_technology_consent(int(f.worker), "family", str(f.scope_id), int(f.worker)).ok,
		"Original controlled Actor explicitly prepares, funds and consents to its own finite project")
	var selected := _p4_controlled_target(f, identity)
	var begun: Dictionary = f.actions.begin_scope_technology_phase(int(f.worker), "family", str(f.scope_id), str(selected.binding), str(selected.target), selected.request)
	_check(begun.ok, "Actual original paid operation publishes its SAME PA physical job: " + str(begun))
	var job: Dictionary = f.actions._jobs.get(str(f.worker), {})
	var target: Dictionary = f.data.site.features[selected.key] if identity == "F04" else f.data.site.vehicles[selected.key]
	_check(job.get("kind") == ("technology_feature" if identity == "F04" else "technology_vehicle")
		and float(job.duration) == 0.0 and is_same(job.operation_selector.token, target.tech_trial)
		and not f.controller.work_team.is_assigned(int(f.worker)), "Only the original zero-timer PA envelope owns this true controlled physical work")
	var original_token: Dictionary = target.tech_trial
	var file_before := FileAccess.get_sha256(idle_path)
	var bytes_before := var_to_bytes([f.data.site, f.lab.character.capture_state(), f.actions._jobs])
	var manual_guard: Dictionary = f.actions.cold_technology_checkpoint_guard()
	var manual_capture: Dictionary = f.lab.capture_region_owner_state(_p4_context(f))
	_check(not manual_guard.ok and manual_guard.code == "BUSY" and not manual_capture.ok and manual_capture.code == "BUSY"
		and var_to_bytes([f.data.site, f.lab.character.capture_state(), f.actions._jobs]) == bytes_before
		and FileAccess.get_sha256(idle_path) == file_before, "Current manual physical research is BUSY and preserves original scene/file")
	var switched: Dictionary = f.controller._control_family_person(null, next_control)
	_check(switched.ok and f.lab.controlled_person_id() == next_control and not bool(f.actions._person(int(f.worker)).player)
		and is_same(f.actions._jobs.get(str(f.worker)), job) and is_same(job.operation_selector.token, original_token),
		"Original living-person control switch leaves the SAME paid executor/body/selector job intact: " + str(switched))
	f.control = next_control
	_check(f.actions.cold_technology_checkpoint_guard().ok, "Original NPC physical envelope passes its own paid endpoint guard, not a duration-zero timer guard")
	job.operation_selector.token = original_token.duplicate(true)
	var copied: Dictionary = f.actions.cold_technology_checkpoint_guard()
	job.operation_selector.token = original_token
	_check(not copied.ok and FileAccess.get_sha256(idle_path) == file_before, "An equal copied selector cannot impersonate the SAME physical research token")
	var request: Dictionary = f.actions._controlled_feature_work_request(str(f.worker), job, 12.0)
	_check(not request.is_empty() and request.participants.size() == 1, "Original PA request admits the proved cold physical factor without a dummy hook")
	var paid: Dictionary = _p4_project(f).budget.duplicate(true)
	var progress := float(target.production) * 60.0 if identity == "F04" else float(target.build.progress)
	var effort := float(target.tech_batch.work_seconds)
	var person: Dictionary = f.actions._person(int(f.worker))
	var fatigue := ColdFatigue.read(person.body)
	var rate := ColdFatigue.effort_rate(person.body)
	var checked: Dictionary = Runtime.work_preflight(f.data, job.work_task, person.cargo, Runtime.CARRY_CAPACITY, int(person.faction), int(f.worker))
	_check(checked.ok and float(checked.progress_multiplier) == 0.5, "Original Runtime independently proves this SAME NPC cold research factor")
	_p4_advance(f, 12.0)
	var advanced := float(target.production) * 60.0 if identity == "F04" else float(target.build.progress)
	_check(absf(advanced - progress - ColdFatigue.work_seconds(fatigue, 12.0, rate) * float(checked.productivity) * 0.5) < 0.000001
		and absf(float(target.tech_batch.work_seconds) - effort - ColdFatigue.work_seconds(fatigue, 12.0, rate)) < 0.000001
		and absf(ColdFatigue.read(person.body) - fatigue - 12.0 * rate) < 0.000001 and _p4_project(f).budget == paid,
		"One real PA/Runtime shared point applies half progress, original unweighted work/full fatigue and one payment")
	progress = advanced
	ColdFatigue.write(person.body, "fatigue", ColdFatigue.WORK_REST_AT)
	f.actions._body_set(person, "work_resting", true) # Explicit legal REST starting body, never forged elapsed/progress.
	_p4_advance(f, 2.0)
	var rest_request: Dictionary = f.actions._controlled_feature_work_request(str(f.worker), f.actions._jobs[str(f.worker)], 2.0)
	_check((float(target.production) * 60.0 if identity == "F04" else float(target.build.progress)) == progress
		and not rest_request.is_empty() and rest_request.paused == "REST" and bool(f.actions._body_get(person, "work_resting"))
		and ColdFatigue.read(person.body) < ColdFatigue.WORK_REST_AT, "Original PA physical REST recovers real fatigue and produces no progress")
	var paused_before := str(f.actions._jobs[str(f.worker)].paused) # Original physical envelope may retain an empty presentation string; body owns REST.
	f = _p4_open(f, _p4_checkpoint(f))
	job = f.actions._jobs.get(str(f.worker), {})
	target = f.data.site.features[selected.key] if identity == "F04" else f.data.site.vehicles[selected.key]
	_check(not job.is_empty() and float(job.duration) == 0.0 and is_same(job.operation_selector.token, target.tech_trial)
		and str(job.paused) == paused_before and bool(f.actions._body_get(f.actions._person(int(f.worker)), "work_resting"))
		and _p4_project(f).budget == paid, "True original full graph Store/read/bind preserves PA REST/zero envelope/SAME token/paid history")
	var loops := 0
	while target.has("tech_trial"):
		_check(Time.get_ticks_msec() < deadline, "Finite original resumed PA physical endpoint")
		_p4_advance(f, 60.0)
		loops += 1
		if loops % 8 == 0: await process_frame
	var project := _p4_project(f)
	_check(not f.actions.is_busy(int(f.worker)) and project.receipts.size() == 1
		and project.budget.spent == ({"iron_ore": 3, "charcoal": 2} if identity == "F04" else {"wood": 24, "iron": 12, "fiber": 10})
		and not Technology.scope_known(f.data.site.family.technology, identity) and not Technology.learned(f.lab.character.technology, identity),
		"Only one real physical completion clears its PA envelope and advances the original next phase; target remains unknown")
	_check(int(f.actions._person(int(f.worker)).cargo.get("iron", 0)) >= 2 if identity == "F04" else target.phase == "idle" and target.build.is_empty(),
		"Original output owner contains the actual smelted iron or complete ballista, not a timer receipt")
	f = _p4_open(f, _p4_checkpoint(f))
	_check(not f.actions.is_busy(int(f.worker)) and _p4_project(f).receipts.size() == 1, "Original final endpoint cold save does not resurrect a physical PA envelope or duplicate a receipt")
	_cleanup_fixture(f.lab, f.team)
