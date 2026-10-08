extends "res://scripts/tests/site_building_ui_test.gd"
## CANDIDATE / NOT_RUN. Uses the real Lab tree, original Controller, paid building
## completion, original Army WorkTeam task and _advance_original_shared_step.
## Direct Runtime contact/genesis occurs only in named arithmetic/clock fixtures;
## the material fire case below must ignite from actual released FIRE_ARROWs.
const FIRE_STEP := 1.0 / 30.0
var fire_checks := 0
var fire_failed := false
var fire_finished := false
var fire_labs: Array[TerrainLab] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _check_fire(value: bool, label: String) -> bool:
	fire_checks += 1
	if not value:
		fire_failed = true
		push_error("FIRE_SHARED_STEP_FAIL: " + label)
	return value

func _finish_fire(ok: bool, reason: String) -> void:
	if fire_finished: return
	fire_finished = true
	for lab: TerrainLab in fire_labs:
		if not is_instance_valid(lab): continue
		for hook: StringName in [&"fire_event_guard", &"fire_pending_projectile_query"]:
			lab.terrain.remove_meta(hook)
		lab.free()
	fire_labs.clear()
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_SHARED_STEP_", "PASS" if ok else "FAIL", ": checks=", fire_checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _new_fire_lab() -> TerrainLab:
	var lab := _building_lab(_building_fixture())
	fire_labs.append(lab)
	lab.physical_ranged_enabled = true
	lab.exchange_enabled = true
	lab.character.exchange_enabled = true
	lab.npc_retaliates = false
	lab.simulation_speed = 1.0
	return lab

func _shared(lab: TerrainLab, ticks: int = 1) -> bool:
	for tick in range(ticks):
		var result := lab._advance_original_shared_step(FIRE_STEP)
		if not _check_fire(result.ok and bool(result.get("completed", false))
			and is_equal_approx(float(result.get("action_seconds", 0.0)), FIRE_STEP),
			"Original complete shared step, without replacement projectile/fire clock"): return false
	return true

func _add_test_timber(data: TerrainData, cell: Vector2i) -> String:
	var key := "%d:%d" % [Env.Kind.TIMBER, data.index(cell)]
	Env._add_resource(data, Env.Kind.TIMBER, data.index(cell), 4, 0)
	data.site.changes.erase(key) # Test genesis only: revive the controlled fixture's cleared cell.
	Env.rebuild_indexes(data)
	return key

func _test_burning_unit(data: TerrainData, key: String, action_at: float) -> Dictionary:
	var state := Runtime._fire_state(data, action_at)
	var unit := Runtime._fire_unit(data, state, Runtime._fire_resource_descriptor(data, key))
	unit.merge({"profile": "TEST_HEAT_100", "heat": 100.0, "state": "BURNING", "intensity": 1.0, "moisture": 0.0}, true)
	state.active["resource:" + key] = true
	return unit

func _clock_matrix() -> bool:
	var signatures: Array[String] = []
	for speed: float in [0.5, 1.0, 2.0, 4.0]:
		var lab := _new_fire_lab()
		var data := lab.terrain
		var cell := Vector2i(40, 40)
		var key := _add_test_timber(data, cell)
		if not _check_fire(lab.character.place(cell + Vector2i.UP, true), "Original manual actor arrives adjacent to original resource"): return false
		if not _check_fire(Runtime.begin_manual(data, key, lab.character.terrain_cell).ok, "Original manual task accepted"): return false
		Runtime._work(data, 0.5, false, true, Callable())
		var earned := float(data.site.manual.progress)
		if not _check_fire(earned > 0.0 and str(data.site.manual.target) == key, "Manual progress is earned by original _work before fire continuation"): return false
		_test_burning_unit(data, key, lab.fire_action_cursor)
		lab.simulation_speed = speed
		var game_start := Runtime.now(data) * 60.0
		var action_start := lab.fire_action_cursor
		if not _shared(lab, 6): return false
		var unit: Dictionary = data.site.fire.units["resource:" + key]
		if not _check_fire(is_equal_approx(lab.fire_action_cursor - action_start, 0.2)
			and is_equal_approx(Runtime.now(data) * 60.0 - game_start, 0.2 * speed),
			"TM-01 shared action interval stays0.2 while original game seconds retain simulation multiplier"): return false
		if not _check_fire(Env.resource(data, key).remaining == 3 and unit.fuel_remainder_q == 768
			and unit.heat == 100.0 and str(data.site.manual.target) == key and float(data.site.manual.progress) > earned
			and float(data.site.combat_left) > 0.0,
			"TM-01/TM-02 one fire burn per action boundary and renewal preserves real manual progress"): return false
		if not _check_fire(not lab.fire_save_guard().ok and not lab.site_controller.supply_save_guard().ok
			and not SiteStore.fire_event_guard(data).ok, "SV-09 original Lab/Controller/Store guard active P2 owner state"): return false
		var crowd := preload("res://scripts/terrain_lab/crowd_site.gd").new()
		crowd.lab = lab
		var admission: Dictionary = crowd.siege_admission_guard()
		crowd.free()
		if not _check_fire(not admission.ok and admission.code == "BUSY", "AR-17 original Crowd admission remains guarded for P2 state"): return false
		if not _check_fire(lab.site_controller.fire_resource_owner_guard(data.site.manual, data.site.manual.cargo, lab.character.terrain_cell, true)
			and not lab.site_controller.fire_resource_owner_guard(data.site.manual, {}, lab.character.terrain_cell, true),
			"Original Controller permits exact manual holder and rejects a substituted cargo dictionary"): return false
		signatures.append(JSON.stringify([Env.resource(data, key).remaining, unit.fuel_remainder_q,
			unit.heat, unit.intensity, unit.state, unit.scorch, data.site.fire.step_index]))
	return _check_fire(signatures[0] == signatures[1] and signatures[1] == signatures[2] and signatures[2] == signatures[3],
		"0.5/1/2/4 speed produce identical authoritative fire/fuel state over the same action interval")

func _actual_arrow_and_work() -> bool:
	var lab := _new_fire_lab()
	var data := lab.terrain
	# Original request_build, payment, worker and complete part geometry.
	var house_key := _formal_feature(data, "house", Vector2i(20, 20))
	var house: Dictionary = data.site.features[house_key]
	var maximum_hp := float(house.parts.body.hp)
	var tree_cell := Vector2i(40, 40)
	var tree_key := _add_test_timber(data, tree_cell)
	if not _check_fire(Runtime.add_zone(data, Rect2i(tree_cell, Vector2i.ONE), Env.Kind.TIMBER).ok, "Original collection zone is declared"): return false
	var team := lab.army
	team.roster_size = 2
	team.faction_id = 1
	var cells: Array[Vector2i] = [Vector2i(38, 38), Vector2i(40, 39)]
	if not _check_fire(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false), "Original Army deploys actual worker and captain"): return false
	team.set_process(false)
	team.settle_combat_command()
	var worker_id := team.combat_identity(1)
	var selected_workers: Array[int] = [worker_id]
	if not _check_fire(lab.site_controller.work_team.assign(team, selected_workers, team.combat_identity(team.current_commander)).ok,
		"Original captain assigns the actual ordinary member"): return false
	var actor := lab.character
	actor.combat_ability = 100.0
	actor.training = 100.0
	if not _check_fire(actor.place(Vector2i(21, 15), true), "Original archer stands outside the paid house"): return false
	actor.item_state.equipped.erase("weapon")
	var made := Runtime.create_equipment(data, actor.item_state, "p2_test_bow", {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, actor.person_id, "weapon")
	if not _check_fire(made.ok, "Archer owns an actual registered bow"): return false
	actor.ammo_inventory.fire_arrow = 16 # Initial original holder stock, never replenished during the run.
	var ordered := lab.issue_fire_order(actor.person_id, actor, {"type": "structure", "feature_id": house_key, "part_id": "body"}, "FIRE_ARROW")
	if not _check_fire(ordered.ok, "Original FIRE_ARROW order targets real paid wood geometry"): return false
	var unit_key := "feature:" + house_key + ":body"
	var ignited := false
	for tick in range(1800):
		if not _shared(lab): return false
		if str(data.site.get("fire", {}).get("units", {}).get(unit_key, {}).get("state", "")) == "BURNING":
			ignited = true
			break
	if not _check_fire(ignited and lab.ranged_shots > 0 and actor.ammo_inventory.fire_arrow == 16 - lab.ranged_shots,
		"Actual arrows alone ignite original house wood through the original shared step and own-stock debit"): return false
	var actual_contact := false
	for contact: Dictionary in lab.fire_impact_recorder:
		if str(contact.type) == "structure" and str(contact.get("feature", "")) == house_key and str(contact.get("part", "")) == "body": actual_contact = true
	if not _check_fire(actual_contact and lab.stop_fire_order(actor.person_id, actor).ok, "Recorded actual first-contact geometry reaches the original house body"): return false
	for tick in range(150):
		if lab.fire_projectiles.is_empty(): break
		if not _shared(lab): return false
	if not _check_fire(lab.fire_projectiles.is_empty() and lab.fire_reservations.is_empty(), "All paid flights settle before isolating later fire damage"): return false
	var hp_after_arrows := float(house.parts.body.hp)
	var fuel_after_arrows := int(data.site.fire.units[unit_key].fuel_q)
	if not _shared(lab, 12): return false
	if not _check_fire(float(house.parts.body.hp) < hp_after_arrows and int(data.site.fire.units[unit_key].fuel_q) < fuel_after_arrows
		and float(house.parts.body.hp) < maximum_hp and lab.fire_projectiles.is_empty(),
		"Actual fire causes further original HP/fuel loss after every kinetic arrow has already settled"): return false
	var worker: Dictionary = team.combat_units[1]
	var task: Dictionary = worker.get("work_task", {})
	if not _check_fire(not task.is_empty() and task.target == tree_key and task.mode == "work"
		and int(task.cell) == data.index(team.cells[1]), "Same real Lab has an original arrived and progressing WorkTeam task"): return false
	while posmod(roundi(lab.fire_action_cursor / FIRE_STEP), 6) != 5:
		if not _shared(lab): return false
	# Prepare real labor through the existing owner; the final completion remains
	# inside the next actual shared step, exactly at the due fire boundary.
	var required := float(Env.WORK_MINUTES[Env.Kind.TIMBER])
	var preparation_seconds := (required - float(task.progress)) * 60.0 - FIRE_STEP * 0.5
	if not _check_fire(preparation_seconds > 0.0, "Named task still has unpaid final work before completion boundary"): return false
	lab.site_controller.work_team.advance(preparation_seconds)
	if not _check_fire(task.target == tree_key and task.progress < required and int(worker.cargo.get("wood", 0)) == 0,
		"Original worker earned near-complete progress without harvesting yet"): return false
	_test_burning_unit(data, tree_key, lab.fire_action_cursor)
	var cargo: Dictionary = worker.cargo
	if not _shared(lab): return false
	var burned: Dictionary = data.site.fire.units["resource:" + tree_key]
	return _check_fire(is_same(cargo, worker.cargo) and int(cargo.get("wood", 0)) == 3
		and Env.resource(data, tree_key).remaining == 0 and burned.fuel_remainder_q == 768
		and str(task.target).is_empty() and data.get_meta(&"fire_boundary", {}).is_empty(),
		"Real shared-step WorkTeam completion burns256 before original harvest3; same cargo and residue768")

func _safe_rest_boundary() -> bool:
	var lab := _new_fire_lab()
	var data := lab.terrain
	lab.simulation_speed = 4.0
	var tree_cell := Vector2i(40, 40)
	var key := _add_test_timber(data, tree_cell)
	if not _check_fire(Runtime.add_zone(data, Rect2i(tree_cell, Vector2i.ONE), Env.Kind.TIMBER).ok, "Rest fixture uses original work zone"): return false
	var team := lab.army
	team.roster_size = 2
	team.faction_id = 1
	var positions: Array[Vector2i] = [Vector2i(38, 38), Vector2i(40, 39)]
	if not _check_fire(team.deploy_at(data, lab.character, lab.npc, positions) and team.enable_combat(false), "Rest fixture has a real original shared pool"): return false
	team.set_process(false)
	team.settle_combat_command()
	var worker: Dictionary = team.combat_units[1]
	var identity := team.combat_identity(1)
	var selected_workers: Array[int] = [identity]
	if not _check_fire(lab.site_controller.work_team.assign(team, selected_workers, team.combat_identity(team.current_commander)).ok, "Original commander assigns rest-test worker"): return false
	if not _shared(lab, 2): return false
	var task: Dictionary = worker.work_task
	if not _check_fire(task.target == key and task.mode == "work", "Original worker is at its real station before rest boundary"): return false
	var distant := _add_test_timber(data, Vector2i(20, 20))
	_test_burning_unit(data, distant, lab.fire_action_cursor)
	PersonFatigue.write(worker, "fatigue", 80.0) # Explicit existing 80-boundary fixture.
	PersonFatigue.write(worker, "fatigue_rest", 0.0)
	var progress := float(task.progress)
	if not _shared(lab): return false
	if not _check_fire(worker.work_resting and task.mode == "rest" and task.progress == progress
		and is_equal_approx(PersonFatigue.read(worker), 80.0), "TM-04 at80 stops original work and starts the unchanged rest delay"): return false
	if not _shared(lab, 240): return false
	if not _check_fire(Runtime.fire_active(data) and float(data.site.combat_left) > 0.0
		and PersonFatigue.read(worker) < 80.0 and task.progress == progress,
		"Distant persistent heat keeps the tactical clock while the locally safe original pool recovers after30 game seconds"): return false
	var rate_proof := PersonFatigue.advance(80.0, 0.0, 5430.0, 0.0, true)
	if not _check_fire(is_equal_approx(rate_proof[0], 50.0), "Original unmodified rate arithmetic needs5430 safe game seconds for80→50"): return false
	# This second initial boundary is explicit; it is not a claim that the test
	# has simulated all90 minutes. Actual local transitions still use shared steps.
	PersonFatigue.write(worker, "fatigue", 50.01)
	PersonFatigue.write(worker, "fatigue_rest", PersonFatigue.REST_DELAY)
	if not _shared(lab, 16): return false
	if not _check_fire(not worker.work_resting and task.mode == "work" and float(task.progress) > progress,
		"Actual shared steps cross50 and resume the same original paid progress/task under distant active fire"): return false
	PersonFatigue.write(worker, "fatigue", 60.0)
	PersonFatigue.write(worker, "fatigue_rest", PersonFatigue.REST_DELAY)
	worker.work_resting = true # Original mid-rest60 fixture retains its80→50 hysteresis.
	# Local residual-heat initial condition on an original exhausted timber key.
	# The body remains at its actual walkable cell; no person is teleported.
	var hot_cell: Vector2i = team.cells[0]
	var local := _add_test_timber(data, hot_cell)
	Env.change(data, local, {"remaining": 0})
	Env.rebuild_indexes(data)
	var local_unit := _test_burning_unit(data, local, lab.fire_action_cursor)
	local_unit.merge({"state": "COOLING", "intensity": 0.0, "profile": "TIMBER"}, true)
	if not _check_fire(data.is_walkable(hot_cell) and Runtime.fire_hazard_at(data, hot_cell) > 0.0
		and lab._fatigue_threat(hot_cell, team.faction_id, team, 0, {}),
		"Local original residue is a threat even on walkable terrain without an enemy"): return false
	if not _shared(lab, 12): return false
	if not _check_fire(PersonFatigue.read(worker) >= 60.0 and PersonFatigue.read(worker, "fatigue_rest") == 0.0,
		"One locally threatened member denies recovery to the original whole-team pool"): return false
	# Observe real production cooling, with all time supplied by original shared steps.
	for tick in range(1600):
		if Runtime.fire_hazard_at(data, hot_cell) <= 0.0: break
		if not _shared(lab): return false
	if not _check_fire(Runtime.fire_hazard_at(data, hot_cell) == 0.0 and Runtime.fire_active(data),
		"Local hazard actually cools while a distant original hot unit still keeps the fire clock active"): return false
	return _check_fire(not lab._fatigue_threat(hot_cell, team.faction_id, team, 0, {}),
		"Original local eligibility becomes safe again without clearing the global fire clock")

func _actual_ground_terminals() -> bool:
	for kind: String in ["timber", "bare", "water", "normal"]:
		var lab := _new_fire_lab()
		var data := lab.terrain
		var cell := Vector2i(20, 20)
		var key := _add_test_timber(data, cell) if kind in ["timber", "normal"] else ""
		if kind == "water":
			for y in range(19, 22):
				for x in range(19, 22): data.water_kind[data.index(Vector2i(x, y))] = 1
		var actor := lab.character
		actor.combat_ability = 100.0
		actor.training = 100.0
		if not _check_fire(actor.place(Vector2i(20, 15), true), "Original ground-terminal archer position"): return false
		actor.item_state.equipped.erase("weapon")
		if not _check_fire(Runtime.create_equipment(data, actor.item_state, "p2_ground_bow", {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, actor.person_id, "weapon").ok,
			"Ground terminal uses original registered bow"): return false
		var mode := "NORMAL" if kind == "normal" else "FIRE_ARROW"
		var ammo := "arrow" if kind == "normal" else "fire_arrow"
		actor.ammo_inventory[ammo] = 1
		if not _check_fire(lab.issue_fire_order(actor.person_id, actor, {"type": "ground", "cell": [cell.x, cell.y]}, mode).ok,
			"Original ground aim is admitted for " + kind): return false
		for tick in range(150):
			if lab.ranged_resolutions == 1: break
			if not _shared(lab): return false
		if not _check_fire(lab.ranged_shots == 1 and lab.ranged_resolutions == 1 and actor.ammo_inventory[ammo] == 0
			and lab.fire_impact_recorder.size() == 1, "Actual original single release and terminal for " + kind): return false
		var impact: Dictionary = lab.fire_impact_recorder[0]
		if not _check_fire(impact.type == "ground" and impact.has("cell"), "Ground first-contact geometry owns the terminal cell"): return false
		if not _check_fire(lab.stop_fire_order(actor.person_id, actor).ok, "Ground terminal stops the original typed command"): return false
		if not _shared(lab, 66): return false # Exhaust the original finite two-second contact, through shared steps.
		if kind == "timber":
			var actual_index := data.index(impact.cell)
			if not _check_fire(data.resources_at.get(actual_index, []).has(key)
				and data.site.fire.units.has("resource:" + key) and Env.resource(data, key).remaining == 4,
				"AR-10 real timber contact heats the actual original target without inventing immediate full-product burn"): return false
		else:
			if not _check_fire(data.site.has("fire") and data.site.fire.units.is_empty() and data.site.fire.contacts.is_empty(),
				"AR-10 actual bare/water/NORMAL terminal is consumed without combustible state: " + kind): return false
		if kind == "water" and not _check_fire(data.water_kind[data.index(impact.cell)] != 0
			and float(impact.remaining_heat_budget) == 0.0, "Actual water collision extinguishes the arrow's finite ember before Runtime receipt"): return false
	return true

func _run() -> void:
	if not _clock_matrix(): _finish_fire(false, "TM-01/TM-02 shared-clock matrix"); return
	if not _actual_arrow_and_work(): _finish_fire(false, "Actual arrows, paid wood fire damage and original WorkTeam barrier"); return
	if not _safe_rest_boundary(): _finish_fire(false, "TM-04 original local threat and80/50 rest boundaries"); return
	if not _actual_ground_terminals(): _finish_fire(false, "AR-10 actual timber/bare/water/NORMAL ground terminals"); return
	_finish_fire(not fire_failed, "P2 original shared-step integration; no GPU, native fire, persistence restoration or FPS claim")
