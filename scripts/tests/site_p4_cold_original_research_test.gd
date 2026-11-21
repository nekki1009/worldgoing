extends "res://scripts/tests/site_settlement_first_earned_base.gd"
## Isolated admitted Catalog; true natural source, original people/work/Store
## and shared replay. No fixed-map, Native, GPU or whole-Region acceptance.
const ColdFatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const PersonSkills = preload("res://scripts/terrain_lab/person_skills.gd") # 技能 K1b: progress follows proficiency
var cold_serial := 0

func _settlement_earned_id() -> String:
	return "S07"

func _p4_project(f: Dictionary) -> Dictionary:
	var owner: Dictionary = f.data.site.settlement if f.scope == "settlement" else f.data.site.family
	return Technology.active_project(owner.technology)

func _p4_body(f: Dictionary) -> Variant:
	return f.actions._person(int(f.worker)).body

## Fatigue and the REST flag of the cold worker through the original PA body accessor: a grid row's own pool, or the crowd
## formation's shared pool (the native world has no per-person pool; crowd_fixture_port_guide).
func _p4_fatigue(f: Dictionary) -> float:
	return float(f.actions._body_get(f.actions._person(int(f.worker)), "fatigue"))

func _p4_fatigue_set(f: Dictionary, value: float) -> void:
	f.actions._body_set(f.actions._person(int(f.worker)), "fatigue", value)

func _p4_resting(f: Dictionary) -> bool:
	return bool(f.actions._body_get(f.actions._person(int(f.worker)), "work_resting"))

func _p4_rest_set(f: Dictionary) -> void:
	f.actions._body_set(f.actions._person(int(f.worker)), "work_resting", true)

## The worker's effort spread over its fatigue pool: 1 for a grid row's own pool; on the crowd the formation's shared pool
## averages the effort over its fatigue_count members.
## A crowd roster row stores its v3 task with the explicit default "manual": false; the same task without the key is equal.
func _p4_task_same(now: Dictionary, was: Dictionary) -> bool:
	var a := now.duplicate(true)
	var b := was.duplicate(true)
	if not bool(a.get("manual", false)): a.erase("manual")
	if not bool(b.get("manual", false)): b.erase("manual")
	return a == b

func _p4_operator_diag(f: Dictionary, task: Dictionary) -> String:
	var person: Dictionary = f.actions._person(int(f.worker))
	if person.is_empty() or task.is_empty(): return "empty"
	var u := int(person.unit)
	return "walk=%s fat_ready=%s cell=%d task_cell=%s work_cell=%s body_dict=%s same_task=%s assigned=%s can_act=%s attack=%s pose=%s stagger=%s" % [
		str(f.actions._person_walking(person)), str(person.owner.crowd_site.work_fatigue_work_start_ready(int(f.worker))) if person.owner is CrowdPersonOwner else "-",
		f.data.index(person.cell), str(task.get("cell")), str(task.get("work_cell")), str(person.body is Dictionary),
		str(is_same(person.body.get("work_task", {}), task)) if person.body is Dictionary else "-", str(f.lab.site_controller.work_team.is_assigned(int(f.worker))),
		str(person.owner.combat_can_act(u)), str(f.actions._body_get(person, "attack")), str(f.actions._body_get(person, "pose")), str(f.actions._body_get(person, "exchange_stagger"))]

func _p4_pool_share(f: Dictionary) -> float:
	var person: Dictionary = f.actions._person(int(f.worker))
	if f.lab.crowd_site == null or not f.lab.crowd_site.active or not person.owner is CrowdPersonOwner: return 1.0
	# A bodied roster member (the former controlled Actor keeps its own body) carries individual fatigue, not the pool.
	if f.lab.crowd_site._actor(int(f.worker)) != null: return 1.0
	var state: Dictionary = f.lab.crowd_site.formation_state(int(person.owner.formation_index))
	return 1.0 / maxf(1.0, float(state.get("fatigue_count", 1.0)))

func _p4_body_snapshot(f: Dictionary) -> Dictionary:
	var body: Variant = _p4_body(f)
	return body.duplicate(true) if body is Dictionary else body.capture_state()

func _p4_context(f: Dictionary) -> Dictionary:
	var fire: Dictionary = f.data.site.get("fire_settlement", {})
	return {"purpose": "region_checkpoint", "mode": "cold_exact" if f.lab.restore_only else "live",
		"source_generation": 0, "runtime_revision": 0, "token": "p4_original_" + str(Time.get_ticks_usec()),
		"game_seconds": Runtime.now(f.data) * 60.0, "action_seconds": float(f.lab.fire_action_cursor),
		"fire_epoch": str(fire.get("epoch", "")), "fire_sequence": int(fire.get("sequence", 0)),
		"interval_complete": true, "effects_complete": true, "mode_revision": 0,
		"backend": f.lab.region_backend_expected(), "events": [], "endpoint_payload": {}} # G6: "native" while the crowd is active.

func _p4_checkpoint(f: Dictionary) -> String:
	# Actual existing non-Fire Region codec, never export_fire_jobs or manually
	# authored cold jobs. Zero revisions name the independent non-Slot fixture.
	# A live crowd joins the checkpoint as the controller's capture_region_checkpoint does: the same synchronous native
	# capture writes the Site's crowd section first, then the owner graph is captured as crowd-admitted.
	var crowd_admitted: bool = f.lab.crowd_site != null and f.lab.crowd_site.active
	var crowd_captured := {}
	if crowd_admitted:
		crowd_captured = f.lab.crowd_site.capture_save(true)
		_check(crowd_captured.ok, "Actual native crowd capture for the checkpoint: " + str(crowd_captured).left(300))
	f.controller._capture_positions()
	if crowd_admitted and crowd_captured.get("ok", false): f.controller._apply_region_crowd_capture(crowd_captured)
	var context := _p4_context(f)
	var stamp: Dictionary = RegionSaveSlot.attach_settlement(f.data.site, context.game_seconds)
	_check(stamp.ok, "Original legacy migration stamps the actual completed Site endpoint, without retrospective work")
	var captured: Dictionary = f.lab.capture_region_owner_state(context, crowd_admitted)
	_check(captured.ok, "Actual Scene captures SAME original full owner graph: " + str(captured))
	var path := "user://p4_original_" + str(cold_serial) + "_" + str(Time.get_ticks_usec()) + ".json"
	cold_serial += 1
	var saved: Dictionary = Store.save_region_snapshot(f.data, path, context, captured.get("owner_states", {}), crowd_admitted)
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
	# A region snapshot binds only through a region bind ticket (REGION_BIND_TICKET_REQUIRED). The cold replay owner's own
	# bootstrap bind issues it and stages the saved native crowd section, as a cold catch-up does.
	var bootstrap: Dictionary = lab._region_bootstrap_bind_child(lab, loaded.data, loaded.data.site.has("crowd"))
	_check(bootstrap.get("ok", false), "Original cold bootstrap bind of the region snapshot: " + str(bootstrap).left(400))
	var bind_receipt: Dictionary = lab.region_bind_receipt(loaded.data)
	_check(bind_receipt.get("complete", false), "Original cold bind restores actual body/task/source aliases: " + str(bind_receipt).left(200)
		+ " refused=" + str(lab.get_meta(&"last_refused_result", {})).left(400))
	if not bind_receipt.get("complete", false):
		quit(1) # Fail fast (2026-11-12): nothing after an unbound cold owner can pass; do not spin to the 600 s deadline.
		return f
	while float(lab.simulation_speed) < 4.0: lab.change_simulation_speed(1)
	var result := f.duplicate()
	result.merge({"lab": lab, "data": lab.terrain, "controller": lab.site_controller, "actions": lab.site_controller.person_actions}, true)
	result.team = result.actions._technology_team(result.actions._person(int(f.worker)))
	# Crowd: the restored worker is a native crowd person; its original team is the crowd team's roster holder.
	if lab.crowd_site != null and lab.crowd_site.active and not result.team is TerrainArmy:
		result.team = lab.crowd_site.team_holder(int(f.team.team_id))
	_check(result.team is TerrainArmy and int(result.team.team_id) == int(f.team.team_id)
		and not is_same(result.data.site, f.data.site) and not is_same(_p4_body(result), _p4_body(f)),
		"Original cold graph renews true references and preserves original person/team identity: team=%s body_same=%s" % [str(result.team), str(is_same(_p4_body(result), _p4_body(f)))])
	if retire:
		var previous_teams: Array = f.lab.combat_armies.duplicate()
		f.lab.free()
		for team: Variant in previous_teams: # Untyped: a team the Lab already freed must not be assigned to a typed variable.
			if is_instance_valid(team): team.free()
	return result

var _p4_profile_calls := 0
var _p4_phase_loops := 0

var _p4_clock_tag := ""

func _p4_nonzero(spent: Dictionary) -> Dictionary:
	var used := {}
	for material: Variant in spent:
		if int(spent[material]) != 0: used[material] = spent[material]
	return used

var _p4_aborted := false

func _p4_abort(f: Dictionary, where: String, result: Dictionary, target: float) -> void:
	# Fail fast (2026-11-14): the canonical verifier writes stdout/stderr only when the process ends, and every later
	# replay of a refused cold owner only repeats BUSY until the 1800 s deadline. Write the refusal and its creation sites
	# (--diag-fail) to a flushed file now, end every loop, and quit.
	_p4_aborted = true
	deadline = 0
	var text := "P4_ABORT where=%s target=%s now=%s tag=%s calls=%d loops=%d ms=%d\nresult=%s\ndiag_fail_sites=%s\n" % [where, target,
		Runtime.now(f.data) * 60.0, _p4_clock_tag, _p4_profile_calls, _p4_phase_loops, Time.get_ticks_msec(), str(result), str(SiteRuntime._diag_fail_seen.keys())]
	printerr(text)
	var file := FileAccess.open(ProjectSettings.globalize_path("res://output/project_command_center/p4_runs/P4_LIVE_ABORT.txt"), FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
	quit(1)

func _p4_advance(f: Dictionary, game_seconds: float) -> void:
	if _p4_aborted: return
	var target := Runtime.now(f.data) * 60.0 + game_seconds
	var result: Dictionary = f.lab.replay_site_to(target)
	# Crowd: the cold owner's last native point stays pending until its endpoint is consumed (the slot-less cold replay
	# leaves that to its caller, as advance_region_cold_actual_fixed does); then the same replay finishes at the target.
	for attempt: int in 4:
		if result.ok or str(result.get("code", "")) != "REGION_REPLAY_PENDING" or f.lab._region_point_pending.is_empty(): break
		var consumed: Dictionary = f.lab.consume_region_point(false)
		_check(consumed.ok, "Original cold owner consumes its pending replay endpoint: " + str(consumed).left(300))
		if not consumed.ok: break
		result = f.lab.replay_site_to(target)
	# The finished replay agrees with its target at the product's own clock agreement tolerance (relative, as the journal):
	# found 2026-11-14, after 17 h of game time a zero-step finish sat 1.3e-7 s short of the target the Site clock gave.
	var replay_ok: bool = result.ok and result.get("status") == "COMPLETE" and absf(Runtime.now(f.data) * 60.0 - target) <= f.lab._replay_clock_agreement_tolerance()
	_check(replay_ok, "Original replay consumes the one fixed endpoint and produces a non-Fire cold checkpoint: " + str(result))
	if not replay_ok:
		_p4_abort(f, "replay", result, target)
		return
	var prior := var_to_bytes([_p4_body_snapshot(f), f.data.site.inventory, f.data.site.family, f.data.site.settlement, f.actions._jobs])
	var cursor := float(f.lab.fire_action_cursor)
	var repeated: Dictionary = f.lab.replay_site_to(target)
	_p4_profile_calls += 1
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

func _p4_station(f: Dictionary, cell: Vector2i, settle_cold: bool = true) -> void:
	# Explicit physical fixture placement excludes travel acceptance. Actual
	# subsequent work uses this SAME Army row and its original fixed work slot.
	_check(f.data.is_walkable(cell), "Original generated physical work station")
	# The grid roster cell is the grid fixture's station; a crowd holder's roster carries no live cells.
	if f.lab.crowd_site == null or not f.lab.crowd_site.active: f.team.cells[f.team.index_for_identity(int(f.worker))] = cell
	# Crowd port: the same native person stands on the station (a placement only moves it); a few real points let it settle.
	if f.lab.crowd_site != null and f.lab.crowd_site.active:
		var native := int(f.lab.crowd_site.crowd.soldier_index(int(f.worker)))
		_check(native >= 0 and f.lab.crowd_site.set_soldier_fields(native, {"px": cell.x + 0.5, "py": cell.y + 0.5}), "Crowd fixture station of the same native worker")
		if f.lab.restore_only:
			# A cold owner advances only through its own replay; a couple of short real replays let the worker settle.
			# A geometry probe places only (settle_cold=false): settling every probed anchor cost 711 replays, 2026-11-14.
			for settle: int in (3 if settle_cold else 0):
				f.lab.crowd_site.siege_approach_step(int(f.worker), cell)
				_p4_advance(f, 1.0)
			return
		for settle: int in 4:
			f.lab.crowd_site.siege_approach_step(int(f.worker), cell)
			f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		var owner: Variant = f.lab.crowd_site.person_owner(int(f.worker))
		# Named-work consent reads the whole team standing (the crowd settle rule): wait for the others with real points while
		# the worker holds its station (a hold on its own cell is standing, not a move goal).
		for settle: int in 600:
			if owner == null or owner.moving_member_count() == 0: break
			f.lab.crowd_site.siege_approach_step(int(f.worker), cell)
			f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
	var row: Variant = _p4_body(f)
	if not row.get("work_task", {}).is_empty(): row.work_task.cell = f.data.index(cell)

func _p4_f07_ranged() -> Dictionary:
	var f := _settlement_fixture()
	# The F04 smelter/well hosts are fixture setup and are built here, before the first cold checkpoint stamps the Site:
	# the setup construction advance moves the Site clock, which after a stamp leaves the settlement watermark behind
	# (found 2026-11-13: built before F04 they left a 2040 s gap and the next 30 s replay ran 2070 s).
	f.keys.smelter = _earned_host(f.data, "smelter", Vector2i(40, 40))
	_earned_host(f.data, "well", f.data.cell_from_index(int(f.data.site.features[f.keys.smelter].cells[0])), Vector2i.ONE, 5)
	Runtime.rebuild_water(f.data)
	f.scope = "family"
	f.initial_depot_items = f.data.site.depot_items.item_ids.size()
	_p4_register_worker(f)
	var depot = f.data.cell_from_index(int(f.data.site.depot_cell))
	var contact := Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell: Vector2i = depot + direction
		# Crowd bodies cover the cells beside them: the fixture's own two people never count as occupying.
		if f.data.is_walkable(cell) and f.data.can_step(depot, cell) and not f.controller.reserves_cell(cell, [int(f.worker), int(f.control)]): contact = cell; break
	_check(contact.x >= 0, "Actual unoccupied original camp contact for the original NPC")
	_p4_station(f, contact)
	# The grant is a hand-craft action of the controlled person: he stands on another legal cell next to the camp.
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell: Vector2i = depot + direction
		if cell != contact and f.data.is_walkable(cell) and f.data.can_step(depot, cell) and not f.controller.reserves_cell(cell, [int(f.worker), int(f.control)]) and _settlement_place(f, cell): break
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
	var fatigue := _p4_fatigue(left)
	_p4_advance(left, 12.0)
	_p4_advance(right, 6.0)
	_p4_advance(right, 6.0)
	_check(absf(float(left.actions._jobs[str(left.worker)].elapsed) - start - 6.0) < 0.000001
		and absf(float(right.actions._jobs[str(right.worker)].elapsed) - float(left.actions._jobs[str(left.worker)].elapsed)) < 0.000001
		and absf(_p4_fatigue(left) - _p4_fatigue(right)) < 0.000001,
		"Ranged research effective time is half; original long/split effort and fatigue agree")
	_check(absf(_p4_fatigue(left) - fatigue - 12.0 * ColdFatigue.effort_rate(_p4_body(left)) * _p4_pool_share(left)) < 0.000001,
		"Half research never halves the original NPC's actual fatigue: before=%.9f after=%.9f expected_delta=%.9f rate=%.9f" % [fatigue, _p4_fatigue(left), 12.0 * ColdFatigue.effort_rate(_p4_body(left)), ColdFatigue.effort_rate(_p4_body(left))])
	var inherited_jobs := var_to_bytes(left.actions._jobs)
	var inherited_body := var_to_bytes(_p4_body(left))
	_check(not left.lab.replay_site_to(Runtime.now(left.data) * 60.0 - 1.0).ok
		and var_to_bytes(left.actions._jobs) == inherited_jobs and var_to_bytes(_p4_body(left)) == inherited_body,
		"An earlier endpoint cannot erase paid job/body/clock history")
	var rest := left
	_p4_fatigue_set(rest, ColdFatigue.WORK_REST_AT)
	_p4_rest_set(rest) # Explicit legal REST starting-state input, not invented work evidence.
	_p4_advance(rest, 2.0)
	_check(rest.actions._jobs[str(rest.worker)].paused == "REST" and absf(float(rest.actions._jobs[str(rest.worker)].elapsed) - start - 6.0) < 0.000001,
		"Original REST interval retains the job without productive work")
	var rest_elapsed := float(rest.actions._jobs[str(rest.worker)].elapsed)
	var rest_fatigue := _p4_fatigue(rest)
	var rest_budget: Dictionary = _p4_project(rest).budget.duplicate(true)
	rest = _p4_open(rest, _p4_checkpoint(rest))
	_check(float(rest.actions._jobs[str(rest.worker)].elapsed) == rest_elapsed and _p4_fatigue(rest) == rest_fatigue
		and _p4_project(rest).budget == rest_budget and _p4_resting(rest),
		"Actual Store load/bind retains REST/body/finite grant and the SAME job attempt")
	# Finish using only original replay and original PA completion. The large
	# window includes original rest/cooldown; it never assigns elapsed/progress.
	var rest_loops := 0
	while rest.actions.is_busy(int(rest.worker)):
		var in_time: bool = Time.get_ticks_msec() < deadline
		_check(in_time, "Bounded true REST/resume fixture: loops=%d fatigue=%.4f resting=%s ms=%d" % [rest_loops, _p4_fatigue(rest), str(_p4_resting(rest)), Time.get_ticks_msec()])
		if not in_time: break
		# Each cold replay ends in a full validated cold checkpoint (~0.8 s here) whatever its length, so the long rest
		# replays in 300 s pieces; the endpoint is exact either way.
		_p4_advance(rest, 300.0)
		rest_loops += 1
	for stage: int in range(1, 3):
		# The worker rested off its camp station (a resting crowd crafter gives up its hold); the next attempt starts from
		# the same real camp contact, as the first one did.
		if rest.lab.crowd_site != null and rest.lab.crowd_site.active: _p4_station(rest, contact)
		var trial: Dictionary = rest.actions.begin_technology_trial(int(rest.control), int(rest.worker))
		var me: Dictionary = rest.actions._person(int(rest.worker))
		_check(trial.ok, "Same original NPC explicitly starts the next finite attempt: %s cell=%s contact=%s moving=%s ready=%s combat_left=%s busy=%s" % [str(trial).left(120),
			str(me.get("cell")), str(contact), str(me.get("moving")), str(rest.actions._ready(me)), str(rest.data.site.get("combat_left")), str(rest.actions.is_busy(int(rest.worker)))])
		if not trial.ok: break # Fail fast: the later stages cannot run without this attempt.
		var stage_loops := 0
		while rest.actions.is_busy(int(rest.worker)) and stage_loops < 400 and Time.get_ticks_msec() < deadline:
			_p4_advance(rest, 120.0 if stage_loops > 0 else 0.5)
			stage_loops += 1
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
	_p4_clock_tag = "feature_" + identity + "_start"
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
	_p4_grantor_contact(f)
	var prepared_scope: Dictionary = f.actions.prepare_scope_technology(int(f.control), int(f.worker), identity, str(f.scope_id))
	return _p4_feature_after_contact(f, identity, key, node, prepared_scope)

func _p4_grantor_contact(f: Dictionary) -> void:
	# Crowd: the controlled grantor is a native body too; the same placement moves it (a placement only, then real replays).
	if f.lab.crowd_site != null and f.lab.crowd_site.active and f.lab.crowd_site.contains_person(int(f.control)):
		# The grantor's real camp contact: a free walkable cell orthogonally beside the depot (the craft contact rule).
		var depot_at: Vector2i = f.data.cell_from_index(int(f.data.site.depot_cell))
		var worker_at: Vector2i = f.actions._person(int(f.worker)).cell
		var depot_cell := TerrainArmy.INVALID_CELL
		for side: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT]:
			var candidate: Vector2i = depot_at + side
			if f.data.is_walkable(candidate) and candidate != worker_at and f.data.can_step(candidate, depot_at):
				depot_cell = candidate
				break
		_check(depot_cell != TerrainArmy.INVALID_CELL, "A free camp contact cell beside the depot exists for the grantor")
		var grantor := int(f.lab.crowd_site.crowd.soldier_index(int(f.control)))
		_check(grantor >= 0 and f.lab.crowd_site.set_soldier_fields(grantor, {"px": depot_cell.x + 0.5, "py": depot_cell.y + 0.5}), "Crowd grantor body contacts the camp")
		_p4_advance(f, 30.0)
		# The worker released by a finished batch may still be walking back to its slot; it stands before the next project.
		for settle: int in 40:
			if f.actions._ready(f.actions._person(int(f.worker))) and not f.lab.crowd_site.person_fighting(int(f.worker)): break
			_p4_advance(f, 30.0)
	# Crowd: a finished camp craft releases its station hold and the worker walks back to its formation slot; the next
	# project is prepared once it stands (a few short real replays).
	for settle: int in 40:
		if f.lab.crowd_site == null or not f.lab.crowd_site.active or f.actions._ready(f.actions._person(int(f.worker))): break
		_p4_advance(f, 30.0)
	# Named-work consent reads the whole team standing (the crowd settle rule): the grantor's placement can set the others
	# moving; wait for them with real replays (found 2026-11-14 in the controlled lanes: consent BUSY).
	var team_owner: Variant = f.actions._person(int(f.worker)).get("owner") if f.lab.crowd_site != null and f.lab.crowd_site.active else null
	for settle: int in 40:
		if not team_owner is CrowdPersonOwner or team_owner.moving_member_count() == 0: break
		_p4_advance(f, 60.0)

func _p4_feature_after_contact(f: Dictionary, identity: String, key: String, node: Variant, prepared_scope: Dictionary) -> Dictionary:
	if not prepared_scope.ok:
		var pw: Dictionary = f.actions._person(int(f.worker))
		printerr("P4_PREPARE_DIAG ", str(prepared_scope).left(200), " ms=", Time.get_ticks_msec(), " ready=", f.actions._ready(pw), " moving=", pw.get("moving"), " cell=", pw.get("cell"), " busy=", f.actions.is_busy(int(f.worker)),
			" fatigue_ready=", pw.owner.crowd_site.work_fatigue_work_start_ready(int(f.worker)) if pw.get("owner") is CrowdPersonOwner else "-", " fatigue=", f.actions._body_get(pw, "fatigue"), " resting=", f.actions._body_get(pw, "work_resting"),
			" siege=", pw.owner.native_siege_state(int(pw.unit)) if pw.get("owner") is CrowdPersonOwner else "-", " combat_left=", f.data.site.get("combat_left"), " fighting=", f.lab.crowd_site.person_fighting(int(f.worker)) if f.lab.crowd_site != null and f.lab.crowd_site.active else "-")
	_check(prepared_scope.ok, "Original current authority prepares one named unknown project")
	var cap := {}
	for phase: Dictionary in node.research.routes[0].phases:
		for material: String in phase.materials: cap[material] = int(cap.get(material, 0)) + int(phase.materials[material]) * int(phase.repeat)
	var granted: Dictionary = f.actions.grant_scope_technology_budget(int(f.control), str(f.scope), str(f.scope_id), cap)
	var consented: Dictionary = f.actions.request_scope_technology_consent(int(f.control), str(f.scope), str(f.scope_id), int(f.worker)) if granted.ok else {}
	if granted.ok and not consented.get("ok", false):
		var wp: Dictionary = f.actions._person(int(f.worker))
		var tm: Variant = wp.owner._command_owner(int(wp.unit)) if wp.get("owner") is CrowdPersonOwner else f.actions._technology_team(wp)
		var phys: Variant = wp.get("owner")
		printerr("P4_CONSENT_DIAG controlled=", f.lab.controlled_person_id(), " control=", f.control, " resolved=", str(tm.duty_resolve_readonly("team.work", phys if phys is CrowdPersonOwner else null)).left(400) if tm != null else "no team", " offices_ai=", tm.offices.get("duty_ai") if tm != null else "-", " commander=", tm.current_commander if tm != null else "-", " player_index=", tm.index_for_identity(int(f.control)) if tm != null else "-", " player_present=", tm.player_present if tm != null else "-", " player_member=", is_instance_valid(tm.player_member) if tm != null else "-", " offices=", JSON.stringify(tm.offices).left(700) if tm != null else "-")
	_check(granted.ok and consented.get("ok", false),
		"Original finite grant and current original team's named consent remain the only authority: %s %s" % [str(granted).left(200), str(consented).left(200)])
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
	var fatigue := _p4_fatigue(f)
	var spent: Dictionary = _p4_project(f).budget.spent.duplicate(true)
	_p4_advance(f, 12.0)
	# Crowd: the formation's shared pool rises at the pooled share of this effort, so output integrates over that rise.
	var productive := ColdFatigue.work_seconds(fatigue, 12.0, ColdFatigue.effort_rate(row) * _p4_pool_share(f))
	# 技能 K1b: output also follows the worker's proficiency on the task's line (x1.0 at 50; it grows with his work).
	var task_for_line: Dictionary = row.work_task.duplicate(true)
	var skill_factor := Runtime._skill_work_factor(f.data, task_for_line, int(f.worker))
	_check(absf((float(f.data.site.features[key].production) - production) * 60.0 - productive * 0.5 * float(preflight.productivity) * skill_factor) < 0.000001
		and absf(float(f.data.site.features[key].tech_batch.work_seconds) - effort - productive) < 0.000001
		and absf(_p4_fatigue(f) - fatigue - 12.0 * ColdFatigue.effort_rate(row) * _p4_pool_share(f)) < 0.000001
		and _p4_project(f).budget.spent == spent, "Original feature retains unweighted canonical work/full effort fatigue, half output and one actual payment")
	var progress := float(f.data.site.features[key].production)
	var payment: Dictionary = f.data.site.features[key].tech_batch.duplicate(true)
	var original_task: Dictionary = row.work_task.duplicate(true)
	f = _p4_open(f, _p4_checkpoint(f))
	if not (float(f.data.site.features[key].production) == progress and f.data.site.features[key].tech_batch == payment and _p4_task_same(_p4_body(f).work_task, original_task) and _p4_project(f).budget.spent == spent):
		printerr("P4_MIDWORK_DIAG production=", float(f.data.site.features[key].production) == progress, " batch=", f.data.site.features[key].tech_batch == payment, " task=", _p4_task_same(_p4_body(f).work_task, original_task), " spent=", _p4_project(f).budget.spent == spent,
			"
 batch_now=", JSON.stringify(f.data.site.features[key].tech_batch).left(400), "
 batch_was=", JSON.stringify(payment).left(400), "
 task_now=", JSON.stringify(_p4_body(f).work_task).left(400), "
 task_was=", JSON.stringify(original_task).left(400))
	_check(float(f.data.site.features[key].production) == progress and f.data.site.features[key].tech_batch == payment
		and _p4_task_same(_p4_body(f).work_task, original_task) and _p4_project(f).budget.spent == spent,
		"Actual Store preserves original feature/one paid token/v3 task/fatigue/project identity mid-work")
	var malformed := TerrainLab._region_detached_bind_data(f.data)
	malformed.site.features[key].tech_trial.attempt += 1
	var retained_path := _p4_checkpoint(f)
	var prior_file := FileAccess.get_sha256(retained_path)
	var corrupt := Runtime.validate_technology_trial_project_storage(malformed, malformed.site.features[key])
	_check(not corrupt.ok and not Store._validate_state(malformed, malformed.site).ok and not prior_file.is_empty() and FileAccess.get_sha256(retained_path) == prior_file,
		"Malformed cold attempt is refused by original target/project/Store before bind")
	var rest_progress := float(f.data.site.features[key].production)
	_p4_fatigue_set(f, ColdFatigue.WORK_REST_AT)
	_p4_rest_set(f) # Explicit REST state, never elapsed or progress.
	_p4_advance(f, 2.0)
	_check(_p4_body(f).work_task.mode == "rest" and float(f.data.site.features[key].production) == rest_progress,
		"Original physical REST pauses output while retaining the actual paid target")
	f = _p4_open(f, _p4_checkpoint(f))
	_check(_p4_resting(f) and _p4_body(f).work_task.mode == "rest"
		and float(f.data.site.features[key].production) == rest_progress and _p4_project(f).budget.spent == spent,
		"Original Store and graph bind preserve physical REST without recharging source")
	_p4_clock_tag = "phase_loop"
	while f.data.site.features[key].has("tech_trial"):
		_check(Time.get_ticks_msec() < deadline, "Finite genuine original physical phase finishes")
		if Time.get_ticks_msec() >= deadline: break # Fail fast: one refusal, not one per remaining piece.
		_p4_advance(f, 300.0) # Each cold replay ends in a full checkpoint; long work replays in 300 s pieces.
		_p4_phase_loops += 1
	_p4_clock_tag = "phase_done"
	var retained := _p4_project(f)
	if retained.is_empty(): retained = f.data.site.settlement.technology.projects[0] if f.scope == "settlement" else f.data.site.family.technology.projects[-1]
	# 技能 K1b: at half output a worker of factor k works 2/k of the nominal phase; his line only grows during the phase.
	var end_factor := PersonSkills.work_factor(_p4_body(f), PersonSkills.line_for_task(f.data.site, task_for_line))
	_check(retained.receipts.size() == prior_receipts + 1 and float(retained.receipts[-1].work_seconds) * end_factor >= float(phase.seconds) * 2.0 - 0.000001,
		"True cold output receipts contain original actual effort rather than nominal half work (x proficiency)")
	return f

func _p4_siege_token(f: Dictionary, target: String) -> Dictionary:
	var record: Dictionary = f.data.site.family.technology
	var project := _p4_project(f)
	var phase := Technology.scope_next_phase(project, project.executor, record.get("person_links", []))
	return {"scope": "family", "scope_id": str(f.family_id), "project_id": int(project.id), "epoch": int(record.epoch),
		"purpose": str(project.purpose), "tech_id": str(project.tech_id), "phase_id": str(phase.id), "attempt": int(project.next_attempt),
		"person": project.executor.duplicate(), "binding": str(phase.binding), "target_id": target, "materials": phase.materials.duplicate(true)}

func _p4_siege_geometry(f: Dictionary, token: Dictionary) -> Dictionary:
	# Crowd cold owner: probe every anchor with a placement only (settling each cost 711 replays), then settle the worker
	# for at most a few refused anchors; the refusal codes are printed when none passes (2026-11-14).
	var codes := {}
	var settled_retry: Array[Vector2i] = []
	var quick := _p4_siege_geometry_scan(f, token, false, codes, settled_retry, [])
	if not quick.is_empty(): return quick
	printerr("P4_GEOMETRY_DIAG quick_codes=", codes, " candidates=", settled_retry.size(), " ms=", Time.get_ticks_msec())
	var retry_codes := {}
	var settled := _p4_siege_geometry_scan(f, token, true, retry_codes, [], settled_retry.slice(0, 6))
	printerr("P4_GEOMETRY_DIAG settled_codes=", retry_codes, " found=", not settled.is_empty(), " ms=", Time.get_ticks_msec())
	if settled.is_empty(): _p4_abort(f, "siege_geometry", {"quick": codes, "settled": retry_codes}, Runtime.now(f.data) * 60.0)
	return settled

func _p4_siege_geometry_scan(f: Dictionary, token: Dictionary, settle: bool, codes: Dictionary, refused: Array[Vector2i], only: Array) -> Dictionary:
	# Nearest anchors to the camp first: a crowd body walks its cold replay at action time (1/60 of peaceful game time), so a
	# footprint in the map corner cost thousands of replayed seconds of walking each way (2026-11-14).
	var depot: Vector2i = f.data.cell_from_index(int(f.data.site.depot_cell))
	var anchors: Array[Vector2i] = []
	for y: int in range(f.data.size.y):
		for x: int in range(f.data.size.x): anchors.append(Vector2i(x, y))
	anchors.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return absi(a.x - depot.x) + absi(a.y - depot.y) < absi(b.x - depot.x) + absi(b.y - depot.y))
	for anchor: Vector2i in anchors:
		if true:
			if not only.is_empty() and not only.has(anchor): continue
			var probe := {"kind": "ballista", "cell": f.data.index(anchor), "facing": [1, 0]}
			var slots := Runtime.siege_work_slots(f.data, probe)
			if slots.size() != 4: continue
			var station = f.data.cell_from_index(int(slots[0].cell))
			if not f.data.is_walkable(station) or f.controller.reserves_cell(station): continue
			_p4_station(f, station, settle) # A probe places only; settled retries and the chosen work cell settle.
			var request := {"anchor": anchor, "facing": Vector2i.RIGHT, "team_id": int(f.team.team_id)}
			var before := var_to_bytes([f.data.site, _p4_body(f), f.actions._jobs])
			var preview := Runtime.begin_technology_operation(f.data, token, true, request)
			_check(var_to_bytes([f.data.site, _p4_body(f), f.actions._jobs]) == before, "Pure original full geometry/source/consent preview")
			if preview.ok: return request
			var code := str(preview.get("code", "")) + ":" + str(preview.get("message", "")).right(40)
			codes[code] = int(codes.get(code, 0)) + 1
			refused.append(anchor)
	_check(settle == false or not only.is_empty(), "True natural terrain must supply one full bounded original ballista/work footprint")
	return {}

func _p4_siege(f: Dictionary) -> Dictionary:
	f.scope = "family"
	f.scope_id = str(f.family_id)
	var archive: Dictionary = f.data.site.family.technology.duplicate(true)
	if not archive.known.has("F09"): archive.known.append("F09") # Explicit unrelated prerequisite archive; never target F11.
	_check(Technology.valid_scope_record(archive, "family"), "Real F07/F04 histories remain valid alongside the F09 prerequisite")
	f.data.site.family.technology = archive
	_check(f.lab.character.place(f.data.cell_from_index(int(f.data.site.depot_cell)), true), "Actual original human grantor contacts the camp")
	_p4_clock_tag = "siege_F11"
	_p4_grantor_contact(f) # Crowd: the same native camp contact as each feature project.
	var f11_prepared: Dictionary = f.actions.prepare_scope_technology(int(f.control), int(f.worker), "F11", str(f.family_id))
	var f11_granted: Dictionary = f.actions.grant_scope_technology_budget(int(f.control), "family", str(f.family_id), {"wood": 144, "iron": 36, "fiber": 34, "cloth": 20}) if f11_prepared.ok else {}
	var f11_consent: Dictionary = f.actions.request_scope_technology_consent(int(f.control), "family", str(f.family_id), int(f.worker)) if f11_granted.get("ok", false) else {}
	var f11_ok: bool = f11_prepared.ok and f11_granted.get("ok", false) and f11_consent.get("ok", false)
	_check(f11_ok, "Unknown actual NPC F11 project receives original finite authority and team consent: prepare=%s grant=%s consent=%s" % [str(f11_prepared).left(300), str(f11_granted).left(300), str(f11_consent).left(300)])
	if not f11_ok:
		_p4_abort(f, "siege_F11_authority", {"prepare": f11_prepared, "grant": f11_granted, "consent": f11_consent}, Runtime.now(f.data) * 60.0)
		return f
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
	var fatigue := _p4_fatigue(f)
	var rate := ColdFatigue.effort_rate(_p4_body(f))
	var budget: Dictionary = _p4_project(f).budget.duplicate(true)
	_p4_advance(f, 12.0)
	# Crowd: the team's shared fatigue pool grows at the builder's share, so the fatigue-weighted work integral uses the
	# shared rate (the same rule as the feature check); the pool's own growth is compared with rate * share below.
	var pooled_rate := rate * _p4_pool_share(f)
	_check(absf(float(vehicle.build.progress) - before - ColdFatigue.work_seconds(fatigue, 12.0, pooled_rate) * 0.5) < 0.000001
		and absf(float(vehicle.tech_batch.work_seconds) - effort - ColdFatigue.work_seconds(fatigue, 12.0, pooled_rate)) < 0.000001
		and absf(_p4_fatigue(f) - fatigue - 12.0 * rate * _p4_pool_share(f)) < 0.000001,
		"One actual vehicle prefix preserves canonical unweighted work/full fatigue with half physical construction: progress_delta=%.12f expect=%.12f work_delta=%.12f expect_work=%.12f fatigue_delta=%.12f expect_fatigue=%.12f share=%s" % [float(vehicle.build.progress) - before,
			ColdFatigue.work_seconds(fatigue, 12.0, pooled_rate) * 0.5, float(vehicle.tech_batch.work_seconds) - effort, ColdFatigue.work_seconds(fatigue, 12.0, pooled_rate),
			_p4_fatigue(f) - fatigue, 12.0 * rate * _p4_pool_share(f), _p4_pool_share(f)])
	var progress := float(vehicle.build.progress)
	_p4_fatigue_set(f, ColdFatigue.WORK_REST_AT)
	_p4_rest_set(f)
	_p4_advance(f, 2.0)
	_check(_p4_body(f).work_task.mode == "rest" and float(vehicle.build.progress) == progress, "Original siege REST has no productive progress")
	f = _p4_open(f, _p4_checkpoint(f))
	vehicle = f.data.site.vehicles[key]
	_check(_p4_resting(f) and _p4_body(f).work_task.mode == "rest" and float(vehicle.build.progress) == progress
		and _p4_project(f).budget == budget, "True Store/body/graph restore retains the original siege paid REST state")
	_check(f.controller.work_team.cancel(int(f.worker)).ok, "Only the original worker job stops; paid vehicle/project remain")
	_p4_advance(f, 2.0)
	_check(float(vehicle.build.progress) == progress and _p4_project(f).budget == budget, "No true at-work executor means no research work or new payment")
	f = _p4_open(f, _p4_checkpoint(f))
	vehicle = f.data.site.vehicles[key]
	# Crowd: a cancelled siege builder releases its station hold and walks back to its formation slot; the explicit resume
	# is given once it stands (the same settle rule as each feature project; 2026-11-14 the resume was refused BUSY).
	# Peaceful crowd walking advances at action time (1/60 of game time), so the walk back takes long replayed pieces.
	for settle: int in 40:
		if f.lab.crowd_site == null or not f.lab.crowd_site.active or f.actions._ready(f.actions._person(int(f.worker))) and not f.lab.crowd_site.person_fighting(int(f.worker)): break
		_p4_advance(f, 300.0)
	var resumed: Dictionary = f.actions.begin_scope_technology_phase(int(f.control), "family", str(f.family_id), "ballista_build", "vehicle:" + key)
	_check(resumed.ok and resumed.resumed and _p4_project(f).budget == budget,
		"Current original authority explicitly resumes the SAME cold paid attempt without another source charge: " + str(resumed))
	if not resumed.ok:
		var rw: Dictionary = f.actions._person(int(f.worker))
		_p4_abort(f, "siege_resume", {"resumed": resumed, "ready": f.actions._ready(rw), "busy": f.actions.is_busy(int(f.worker)), "moving": rw.get("moving"), "cell": str(rw.get("cell")),
			"fighting": f.lab.crowd_site.person_fighting(int(f.worker)) if f.lab.crowd_site != null and f.lab.crowd_site.active else "-", "jobs": str(f.actions._jobs.get(str(f.worker), {})).left(300)}, Runtime.now(f.data) * 60.0)
		return f
	var ballista_loops := 0
	while vehicle.has("tech_trial"):
		_check(Time.get_ticks_msec() < deadline, "Bounded actual half-rate original ballista completion")
		if Time.get_ticks_msec() >= deadline: break # Fail fast: one refusal, not one per remaining piece.
		_p4_advance(f, 60.0)
		ballista_loops += 1
	_check(vehicle.phase == "idle" and vehicle.build.is_empty() and vehicle.technology_construction.binding == "ballista_build"
		and float(vehicle.technology_construction.work_seconds) >= 10800.0 - 0.000001
		and _p4_project(f).receipts.size() == 1 and _p4_nonzero(_p4_project(f).budget.spent) == {"wood": 24, "iron": 12, "fiber": 10} # Granted cloth stays 0.
		and not Technology.learned(_p4_body(f).get("technology", {}), "F11")
		and Technology.scope_next_phase(_p4_project(f), _p4_project(f).executor).binding == "tower_build",
		"One genuine cold ballista completion advances only this same person's next tower phase; never a whole F11 acceptance: phase=%s build=%s construction=%s receipts=%s spent=%s learned=%s next=%s" % [vehicle.get("phase"), str(vehicle.get("build")).left(120),
			str(vehicle.get("technology_construction", {})).left(200), _p4_project(f).get("receipts", []).size(), str(_p4_project(f).get("budget", {}).get("spent")),
			Technology.learned(_p4_body(f).get("technology", {}), "F11"), str(Technology.scope_next_phase(_p4_project(f), _p4_project(f).executor)).left(160)])
	return _p4_open(f, _p4_checkpoint(f))

func _run() -> void:
	# Nekki 2026-11-13 09:20Z (照建議, A): on the crowd each cold replay ends in a full validated checkpoint (~0.8 s), so the
	# whole cold research chain runs in-file 1800 s, outer 1860 s. 2026-11-14: the chain now reaches F11 at ~24 min and the
	# ballista alone is ~180 replays; widened to in-file 2700 s, outer 2760 s (standing rule: loosen test timeouts directly).
	deadline = Time.get_ticks_msec() + 2700000
	if OS.get_cmdline_user_args().has("--p4-lanes-only"):
		# Debug only (fast iteration, 2026-11-14): the controlled lanes build their own fixtures; acceptance runs the whole chain.
		await _p4_controlled_lane("F04")
		await _p4_controlled_lane("F11")
		print("P4_LANES_ONLY_DONE checks=", checks)
		quit(1) # Never an acceptance pass.
		return
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
	var smelter := str(f.keys.smelter) # Built with the fixture, before any cold stamp.
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
		var key := str(f.keys.smelter) # Built with the fixture, before any cold stamp.
		var entrance: Vector2i = f.data.cell_from_index(int(f.data.site.features[key].entrance))
		_check(f.lab.character.place(entrance, true), "Original controlled Actor stands at this real generated smelter entrance")
		# Crowd: the controlled Actor's native body stands there too (a placement, then short real replays).
		if f.lab.crowd_site != null and f.lab.crowd_site.active: _p4_station(f, entrance)
		return {"target": "feature:" + key, "key": key, "binding": "iron", "request": {}}
	var key := str(f.data.site.next_vehicle)
	var token := _p4_siege_token(f, "vehicle:" + key)
	# The same nearest-first, placement-only probe as the NPC ballista (a crowd body walks cold replays at action time).
	var codes := {}
	var refused: Array[Vector2i] = []
	var request := _p4_siege_geometry_scan(f, token, false, codes, refused, [])
	if request.is_empty():
		printerr("P4_LANE_GEOMETRY_DIAG codes=", codes)
		_check(false, "True natural source must supply an original controlled full ballista footprint")
		return {}
	var slots := Runtime.siege_work_slots(f.data, {"kind": "ballista", "cell": f.data.index(request.anchor), "facing": [1, 0]})
	var station: Vector2i = f.data.cell_from_index(int(slots[0].cell))
	_check(f.lab.character.place(station, true), "Original controlled Actor stands at its real ballista work slot")
	_p4_station(f, station)
	return {"target": "vehicle:" + key, "key": key, "binding": "ballista_build", "request": request}

func _p4_controlled_lane(identity: String) -> void:
	var f := _settlement_fixture()
	if identity == "F04":
		# Host setup before the first cold stamp (see _p4_f07_ranged): its construction advance moves the Site clock.
		f.keys.smelter = _earned_host(f.data, "smelter", Vector2i(40, 40))
		_earned_host(f.data, "well", f.data.cell_from_index(int(f.data.site.features[f.keys.smelter].cells[0])), Vector2i.ONE, 5)
		Runtime.rebuild_water(f.data)
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
	_p4_grantor_contact(f) # Crowd: the controlled Actor's native body contacts the camp too.
	var cap := {"iron_ore": 3, "charcoal": 5, "iron": 2, "steel": 1, "wood": 1} if identity == "F04" else {"wood": 144, "iron": 36, "fiber": 34, "cloth": 20}
	var lane_prepared: Dictionary = f.actions.prepare_scope_technology(int(f.worker), int(f.worker), identity, str(f.scope_id))
	var lane_granted: Dictionary = f.actions.grant_scope_technology_budget(int(f.worker), "family", str(f.scope_id), cap) if lane_prepared.ok else {}
	var lane_consent: Dictionary = f.actions.request_scope_technology_consent(int(f.worker), "family", str(f.scope_id), int(f.worker)) if lane_granted.get("ok", false) else {}
	if not lane_consent.get("ok", false) and f.lab.crowd_site != null and f.lab.crowd_site.active:
		var lp: Dictionary = f.actions._person(int(f.worker))
		printerr("P4_LANE_CONSENT_DIAG moving=", lp.owner.moving_member_count() if lp.get("owner") is CrowdPersonOwner else "-", " ready=", f.actions._ready(lp), " busy=", f.actions.is_busy(int(f.worker)),
			" fatigue_ready=", f.lab.crowd_site.work_fatigue_work_start_ready(int(f.worker)), " fighting=", f.lab.crowd_site.person_fighting(int(f.worker)), " order=", f.lab.crowd_site.formation_state(int(lp.owner.formation_index)).get("order") if lp.get("owner") is CrowdPersonOwner else "-",
			" readonly=", f.actions._technology_native_consent_readonly(lp, [{"site_id": str(f.data.site.id), "team_id": int(lp.owner.team_id), "person_id": int(f.worker), "purpose": "family", "decider_id": int(f.worker), "revision": 0, "status": "accepted"}], "family", {}, {}) if lp.get("owner") is CrowdPersonOwner else "-")
	_check(lane_prepared.ok and lane_granted.get("ok", false) and lane_consent.get("ok", false),
		"Original controlled Actor explicitly prepares, funds and consents to its own finite project: prepare=%s grant=%s consent=%s" % [str(lane_prepared).left(300), str(lane_granted).left(300), str(lane_consent).left(300)])
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
	# Crowd: the PA request reads the team's native work-fatigue snapshot, which exists only inside a shared step (begin
	# window), so an out-of-step probe is empty by design; the real shared point below proves the same factor and effort.
	var crowd_lane: bool = f.lab.crowd_site != null and f.lab.crowd_site.active
	_check(crowd_lane or not request.is_empty() and request.participants.size() == 1, "Original PA request admits the proved cold physical factor without a dummy hook")
	if request.is_empty() and not crowd_lane:
		# Failure diagnostics only: which step of the PA request refused the executor.
		var ctx: Dictionary = f.actions._controlled_feature_job_context(job) if job.get("kind") != "technology_vehicle" else {"ok": "vehicle"}
		var rp: Dictionary = ctx.get("person", f.actions._person(int(f.worker))) if ctx.get("ok") is bool and ctx.ok else f.actions._person(int(f.worker))
		var pre: Dictionary = Runtime.work_preflight(f.data, job.work_task, rp.cargo, Runtime.CARRY_CAPACITY, int(rp.faction), int(f.worker), f.actions._work_occupied(int(f.worker)))
		_p4_abort(f, "lane_request", {"kind": job.get("kind"), "context": str(ctx).left(300), "preflight": str(pre).left(500),
			"expected_factor": Runtime.technology_cold_work_multiplier(f.data, job.get("feature_ref", ""), job.work_task) if job.has("feature_ref") else "-",
			"skills": str(f.controller.work_team._work_skill_facts(pre)).left(200) if pre.get("ok", false) else "-",
			"participant": str(f.actions._shared_work_participant(rp)).left(300), "task": str(job.work_task).left(300)}, Runtime.now(f.data) * 60.0)
		return
	var paid: Dictionary = _p4_project(f).budget.duplicate(true)
	var progress := float(target.production) * 60.0 if identity == "F04" else float(target.build.progress)
	var effort := float(target.tech_batch.work_seconds)
	var person: Dictionary = f.actions._person(int(f.worker))
	var fatigue := float(f.actions._body_get(person, "fatigue"))
	var rate := ColdFatigue.effort_rate(person.body)
	var checked: Dictionary = Runtime.work_preflight(f.data, job.work_task, person.cargo, Runtime.CARRY_CAPACITY, int(person.faction), int(f.worker))
	_check(checked.ok and float(checked.progress_multiplier) == 0.5, "Original Runtime independently proves this SAME NPC cold research factor")
	_p4_advance(f, 12.0)
	var advanced := float(target.production) * 60.0 if identity == "F04" else float(target.build.progress)
	var pooled := rate * _p4_pool_share(f) # Crowd shared fatigue pool: the work integral uses the shared growth (as the NPC checks).
	_check(absf(advanced - progress - ColdFatigue.work_seconds(fatigue, 12.0, pooled) * float(checked.productivity) * 0.5) < 0.000001
		and absf(float(target.tech_batch.work_seconds) - effort - ColdFatigue.work_seconds(fatigue, 12.0, pooled)) < 0.000001
		and absf(float(f.actions._body_get(person, "fatigue")) - fatigue - 12.0 * pooled) < 0.000001 and _p4_project(f).budget == paid,
		"One real PA/Runtime shared point applies half progress, original unweighted work/full fatigue and one payment: progress_delta=%.12f expect=%.12f work_delta=%.12f expect_work=%.12f fatigue_delta=%.12f expect_fatigue=%.12f paid_same=%s" % [
			advanced - progress, ColdFatigue.work_seconds(fatigue, 12.0, pooled) * float(checked.productivity) * 0.5, float(target.tech_batch.work_seconds) - effort,
			ColdFatigue.work_seconds(fatigue, 12.0, pooled), float(f.actions._body_get(person, "fatigue")) - fatigue, 12.0 * pooled, _p4_project(f).budget == paid])
	progress = advanced
	f.actions._body_set(person, "fatigue", ColdFatigue.WORK_REST_AT)
	f.actions._body_set(person, "work_resting", true) # Explicit legal REST starting body, never forged elapsed/progress.
	_p4_advance(f, 60.0 if crowd_lane else 2.0) # Crowd: REST recovery is applied per shared point; one real minute shows it.
	var rest_request: Dictionary = f.actions._controlled_feature_work_request(str(f.worker), f.actions._jobs[str(f.worker)], 2.0)
	_check((float(target.production) * 60.0 if identity == "F04" else float(target.build.progress)) == progress
		and (crowd_lane or not rest_request.is_empty() and rest_request.paused == "REST") and bool(f.actions._body_get(person, "work_resting"))
		and float(f.actions._body_get(person, "fatigue")) < ColdFatigue.WORK_REST_AT, "Original PA physical REST recovers real fatigue and produces no progress: progress=%s/%s resting=%s fatigue=%s" % [
			float(target.production) * 60.0 if identity == "F04" else float(target.build.progress), progress, f.actions._body_get(person, "work_resting"), f.actions._body_get(person, "fatigue")])
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
		if Time.get_ticks_msec() >= deadline: break # Fail fast: one refusal, not one per remaining piece.
		_p4_advance(f, 300.0) # Each cold replay ends in a full checkpoint; long work replays in 300 s pieces.
		loops += 1
		if loops % 8 == 0: await process_frame
	var project := _p4_project(f)
	_check(not f.actions.is_busy(int(f.worker)) and project.receipts.size() == 1
		and _p4_nonzero(project.budget.spent) == ({"iron_ore": 3, "charcoal": 2} if identity == "F04" else {"wood": 24, "iron": 12, "fiber": 10}) # The budget lists every granted material; unused ones stay 0.
		and not Technology.scope_known(f.data.site.family.technology, identity) and not Technology.learned(f.lab.character.technology, identity),
		"Only one real physical completion clears its PA envelope and advances the original next phase; target remains unknown: busy=%s receipts=%s spent=%s known=%s learned=%s job=%s" % [f.actions.is_busy(int(f.worker)), project.get("receipts", []).size(),
			str(project.get("budget", {}).get("spent")), Technology.scope_known(f.data.site.family.technology, identity), Technology.learned(f.lab.character.technology, identity), str(f.actions._jobs.get(str(f.worker), {})).left(200)])
	_check(int(f.actions._person(int(f.worker)).cargo.get("iron", 0)) >= 2 if identity == "F04" else target.phase == "idle" and target.build.is_empty(),
		"Original output owner contains the actual smelted iron or complete ballista, not a timer receipt")
	f = _p4_open(f, _p4_checkpoint(f))
	_check(not f.actions.is_busy(int(f.worker)) and _p4_project(f).receipts.size() == 1, "Original final endpoint cold save does not resurrect a physical PA envelope or duplicate a receipt")
	_cleanup_fixture(f.lab, f.team)
