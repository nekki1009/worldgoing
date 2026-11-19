extends "res://scripts/tests/site_ecology_reservation_fire_test.gd"
## STAGED / NOT_RUN. Three committed E0-E2 gaps; original GD owners only.
## Inherited fixtures are setup only; the inherited eight-case _run is not called.
const GapSettlement = preload("res://scripts/terrain_lab/site_settlement.gd")
var gap_groups := 0
var gap_deadline := 0
var gap_rows: Array[Dictionary] = []

func _initialize() -> void:
	gap_deadline = Time.get_ticks_msec() + 120000
	create_timer(120.0, true).timeout.connect(func() -> void: _finish(false, "bounded deadline"))
	_run.call_deferred()
	_gap_completion.call_deferred()

func _gap_completion() -> void:
	if not finished: _finish(false, "a nested acceptance assertion interrupted the fixture")

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	ok = ok and not failed and gap_groups == 3
	for original: TerrainLab in rf_labs:
		if is_instance_valid(original): original.free()
	rf_labs.clear()
	TerrainArmy.release_contact_source()
	print("SITE_ECOLOGY_ACCEPTANCE_GAP_", "PASS" if ok else "FAIL", " groups=", gap_groups,
		" checks=", checks, " ", reason, " rows=", JSON.stringify(gap_rows),
		"; scoped ECO05/ECO06 original GD; no 13-case rerun, GPU, Native, performance or release claim")
	quit(0 if ok else 1)

func _gap_fixture(cold_history: bool = false, bow: bool = false) -> Dictionary:
	var data := _data()
	var key := _timber(data, Vector2i(20, 20))
	var standing := Env.work_cells(data, key)[0]
	var scene := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(scene != null, "Original scene exists"): return {}
	var original := scene.instantiate() as TerrainLab
	if not _check(original != null, "Original scene instantiates"): return {}
	original.restore_only = true
	original.npc = TerrainTestNPC.new() # Original optional command-test NPC, before _ready.
	original.pause_when_unfocused = false
	root.add_child(original)
	rf_labs.append(original)
	if bow:
		var appearance := HumanCharacter3DEditor.default_appearance()
		appearance.parts.weapon = "bow_01"
		appearance.parts.shield = "none"
		original.character._saved_appearance = appearance.duplicate(true)
		if original.character.editor != null and not _check(original.character.editor.restore_appearance(appearance), "Original bow appearance seeds through bind"): return {}
	original.bind_terrain(data)
	if not _check(original.terrain == data and original.actor_present(original.character) and original.actor_present(original.npc), "Original actor and item owners bind"): return {}
	original.restore_only = false
	original.simulation_speed = 4.0
	original.site_controller._auto_save_blocked = true
	original.set_process(false)
	original.set_process_input(false)
	original.set_process_unhandled_input(false)
	original.site_controller.set_process(false)
	for actor: TerrainTestCharacter in original.combat_actors:
		actor.set_process(false)
		if actor.editor != null:
			actor.editor.set_process(false)
			actor.editor.animation_player.pause()
	original.site_controller.release_worker()
	if cold_history:
		if not _check(bow and original.character.place(Vector2i(18, 20), true), "Real bow fixture starts before any Fire history exists"): return {}
		if not _gap_cold_history(original, key): return {}
	if not _check(original.character.place(standing, true), "Original clearing work cell"): return {}
	for _batch in range(3):
		if bool(Env.resource(data, key).cleared): break
		if not _check(Runtime.harvest(data, key, standing, data.site.manual.cargo, "clear").ok, "Original harvest then depleted-source clear"): return {}
	if not _check(bool(Env.resource(data, key).cleared) and int(Env.resource(data, key).remaining) == 0 and int(Env.resource(data, key).next_recovery) == -1, "Actual clear, zero stock, no growth deadline"): return {}
	if not _check(original.character.place(Vector2i(10, 10), true) and original.npc.place(standing, true), "Actual original people occupy distinct legal cells"): return {}
	original.site_controller.source_key = key
	if not _check(original.site_controller._control_family_person(null, original.character.person_id).ok, "Original family control entry selects player"): return {}
	return {"lab": original, "data": data, "key": key, "standing": standing}

func _gap_shoot(original: TerrainLab, target: Vector2i, with_work: bool) -> bool:
	var data := original.terrain
	original.physical_ranged_enabled = true
	original.character.ammo_inventory = data.site.manual.cargo
	original.character.ammo_inventory.fire_arrow = 1 # Original finite-ammo fixture genesis.
	if not _check(str(Runtime.equipment_appearance(data, original.character.item_state, original.character._saved_appearance, {}).parts.weapon) == "bow_01", "Original seeded item holder supplies the actual bow"): return false
	var prior := original.ranged_shots
	if not _check(original.issue_fire_order(original.character.person_id, original.character, {"type": "ground", "cell": [target.x, target.y]}, "FIRE_ARROW").ok, "Actual original FIRE_ARROW order accepted"): return false
	for _shot in range(45):
		if with_work:
			# The original bounded Fire fixture owner releases while the accepted
			# worker task remains at 59; it never advances Runtime work progress.
			original._advance_combat(1.0 / 30.0, 0.0)
		elif not _gap_step(original): return false
		if original.ranged_shots == prior + 1: break
	if not _check(original.ranged_shots == prior + 1 and not original.fire_projectiles.is_empty() and int(original.character.ammo_inventory.fire_arrow) == 0, "One real original projectile and one ammo debit"): return false
	return _check(original.stop_fire_order(original.character.person_id, original.character).ok, "Stop future shooting; airborne original projectile remains")

func _gap_cold_history(original: TerrainLab, key: String) -> bool:
	var data := original.terrain
	if not _gap_shoot(original, data.cell_from_index(int(Env.resource(data, key).cell)), false): return false
	var heated := false
	for _contact in range(600):
		if float(_unit(data, key).get("heat", 0.0)) > 0.0:
			heated = true
			break
		if not _gap_step(original): return false
	if not _check(heated and not _unit(data, key).is_empty(), "Actual original ground contact heats the uncleared timber"): return false
	if not _check(Runtime.fire_set_weather(data, original.fire_action_cursor, Vector2.ZERO, 1.0).ok, "Original rain owner cools the actual Fire history"): return false
	for _cooling in range(9000):
		if original.fire_projectiles.is_empty() and not Runtime.fire_active(data): break
		if not _gap_step(original): return false
	return _check(original.fire_projectiles.is_empty() and not Runtime.fire_active(data) and float(_unit(data, key).heat) == 0.0 and str(_unit(data, key).profile) == "TIMBER" and Runtime.fire_save_guard(data).ok, "Original shared Fire owner settles genuine cold timber history; no synthetic heat, profile or transport")

func _gap_conservation(original: TerrainLab, key: String) -> PackedByteArray:
	var data := original.terrain
	return var_to_bytes([data.resource_base, Env.resource(data, key), data.site.changes.get(key, {}),
		data.site.manual.cargo, data.site.worker.cargo, data.site.total_produced])

func _gap_people(original: TerrainLab) -> PackedByteArray:
	var people: Array = []
	for actor: TerrainTestCharacter in [original.character, original.npc]:
		people.append([actor.person_id, actor.terrain_cell, actor.movement_from_cell, actor.is_moving(), actor.item_state])
	return var_to_bytes(people)

func _gap_step(original: TerrainLab, elapsed: float = 1.0 / 30.0) -> bool:
	if not _check(Time.get_ticks_msec() < gap_deadline, "Synchronous fixture deadline"): return false
	var before := Runtime.now(original.terrain)
	# Diagnostic reads only; original owners still receive exactly one unchanged step.
	var clock_before := PackedFloat64Array([elapsed, before, float(original.terrain.site.minute), float(original.terrain.site.phase),
		float(original.terrain.site.combat_left), float(original.site_controller._work_elapsed),
		original._shared_work_action_seconds, original._shared_work_game_seconds, original.fire_action_cursor,
		float(original.terrain.site.worker.progress), PersonFatigue.read(original.character), PersonFatigue.read(original.character, "fatigue_rest"),
		original.character.hp, original.character.knockout_left, original.character.action_time, original.character.ranged_cooldown,
		PersonFatigue.read(original.npc), PersonFatigue.read(original.npc, "fatigue_rest"),
		original.npc.hp, original.npc.knockout_left, original.npc.action_time, original.npc.ranged_cooldown])
	var flags_before: Dictionary = {"controller_bound": original.site_controller.lab == original, "site_paused": original.terrain.site.paused,
		"world_paused": paused, "restore_only": original.restore_only, "worker_enabled": original.terrain.site.worker_enabled,
		"worker": original.terrain.site.worker.duplicate(true), "cached_inputs": original.site_controller._shared_worker_inputs.duplicate(true),
		"actor_flags": [original.character.captive, original.character.surrender_pending, original.character.site_exited, original.character._getting_up,
			original.character.work_resting, original.character.visible, original.character.guarding,
			original.npc.captive, original.npc.surrender_pending, original.npc.site_exited, original.npc._getting_up,
			original.npc.work_resting, original.npc.visible, original.npc.guarding]}
	var accepted := original._advance_original_shared_step(elapsed)
	if not (accepted.ok and bool(accepted.get("completed", false)) and Runtime.now(original.terrain) > before):
		var names := PackedStringArray(["requested_action", "now_minutes", "minute", "phase", "combat_left", "controller_work_elapsed",
			"cached_shared_action", "cached_shared_game", "fire_action", "worker_progress", "character_fatigue", "character_fatigue_rest",
			"character_hp", "character_ko", "character_action", "character_ranged_cooldown",
			"npc_fatigue", "npc_fatigue_rest", "npc_hp", "npc_ko", "npc_action", "npc_ranged_cooldown"])
		var clock_after := PackedFloat64Array([elapsed, Runtime.now(original.terrain), float(original.terrain.site.minute), float(original.terrain.site.phase),
			float(original.terrain.site.combat_left), float(original.site_controller._work_elapsed),
			original._shared_work_action_seconds, original._shared_work_game_seconds, original.fire_action_cursor,
			float(original.terrain.site.worker.progress), PersonFatigue.read(original.character), PersonFatigue.read(original.character, "fatigue_rest"),
			original.character.hp, original.character.knockout_left, original.character.action_time, original.character.ranged_cooldown,
			PersonFatigue.read(original.npc), PersonFatigue.read(original.npc, "fatigue_rest"),
			original.npc.hp, original.npc.knockout_left, original.npc.action_time, original.npc.ranged_cooldown])
		var precision: Dictionary = {}
		for index: int in names.size():
			precision[names[index]] = {"before_24": "%.24f" % clock_before[index], "after_24": "%.24f" % clock_after[index],
				"before_float64": PackedFloat64Array([clock_before[index]]).to_byte_array().hex_encode(),
				"after_float64": PackedFloat64Array([clock_after[index]]).to_byte_array().hex_encode()}
		for field: String in ["action_seconds", "game_seconds"]:
			var value := float(accepted.get(field, -1.0))
			precision["returned_" + field] = {"decimal_24": "%.24f" % value, "float64": PackedFloat64Array([value]).to_byte_array().hex_encode()}
		print("SITE_ECOLOGY_GAP_STEP_FAILURE_SOURCE_ONLY ", JSON.stringify({"precision": precision, "before": flags_before, "accepted": accepted,
			"worker_after": original.terrain.site.worker, "cached_inputs_after": original.site_controller._shared_worker_inputs,
			"actor_flags_after": [original.character.captive, original.character.surrender_pending, original.character.site_exited, original.character._getting_up,
				original.character.work_resting, original.character.visible, original.character.guarding,
				original.npc.captive, original.npc.surrender_pending, original.npc.site_exited, original.npc._getting_up,
				original.npc.work_resting, original.npc.visible, original.npc.guarding],
			"fire_projectiles": original.fire_projectiles.size(), "fire_reservations": original.fire_reservations.size(),
			"fire_boundary_error": original._fire_boundary_error, "original_step_fault": original.site_controller._original_step_fault,
			"pending_region_point": original._region_point_pending, "groups": gap_groups, "rows": gap_rows}))
	return _check(accepted.ok and bool(accepted.get("completed", false)) and Runtime.now(original.terrain) > before, "Actual original shared step: " + str(accepted))

func _gap_progress(original: TerrainLab, wanted: float, feature_key: String = "") -> bool:
	for _step in range(4000):
		var progress := float(original.terrain.site.worker.progress) if feature_key.is_empty() else float(original.terrain.site.features[feature_key].progress)
		if absf(progress - wanted) < 0.000001: return true
		if not _check(progress < wanted, "Original work does not overshoot requested boundary"): return false
		var elapsed := minf(1.0 / 30.0, (wanted - progress) / original.simulation_speed)
		if not _gap_step(original, elapsed): return false
	return _check(false, "Bounded original work reaches " + str(wanted))

func _gap_autonomous_restore(original: TerrainLab, key: String) -> bool:
	var data := original.terrain
	var area := Rect2i(data.cell_from_index(int(Env.resource(data, key).cell)), Vector2i.ONE)
	if not _check(GapSettlement.restore_ecology_zone(original, original.controlled_person_id(), area, Env.Kind.TIMBER).ok, "Original authorized restore zone"): return false
	original.site_controller.enable_worker()
	var inputs: Dictionary = original.site_controller._prepare_original_work_inputs()
	return _check(bool(inputs.worker_ready) and str(data.site.worker.target) == key and str(data.site.worker.action) == "restore" and not bool(data.site.worker.manual_control), "Original autonomous worker chooses restoration")

func _gap_zero_pool_step(original: TerrainLab, worker_target: String) -> bool:
	var elapsed := 1.0 / 30.0
	var data := original.terrain
	var game := Runtime.game_seconds(elapsed, float(data.site.combat_left)) * original.simulation_speed
	var fatigue := PersonFatigue.read(original.npc)
	var progress := float(data.site.worker.progress)
	var prepared := original._prepare_shared_work_step(elapsed, game, minf(elapsed, float(data.site.combat_left)))
	if not _check(prepared.ok, "Original shared pool prepares blocked work: " + str(prepared)): return false
	var plan: Dictionary = prepared.work_plan
	var allocation: Dictionary = plan.jobs.get("runtime", {}).get("worker", {})
	if not _check(float(allocation.get("actual_seconds", 0.0)) == 0.0 and float(allocation.get("effective_seconds", 0.0)) == 0.0 and float(allocation.get("participant_seconds", {}).get(original.npc.person_id, 0.0)) == 0.0, "Blocked original worker has zero actual/effective/participant effort"): return false
	for pool: Dictionary in plan.pools:
		if not _check(float(pool.effort_seconds) == 0.0, "No ineffective shared body-pool effort"): return false
	if not _check(str(data.site.worker.target) == worker_target and absf(float(data.site.worker.progress) - progress) < 0.000001, "Preview keeps the original task and progress"): return false
	# Discard through the original owner; the full step prepares/consumes its own pool.
	original._clear_shared_work_step()
	if not _gap_step(original, elapsed): return false
	return _check(PersonFatigue.read(original.npc) <= fatigue + 0.000001 and absf(float(data.site.worker.progress) - progress) < 0.000001, "Actual shared step charges no ineffective fatigue; legitimate rest may reduce fatigue")

func _gap_control_interruption() -> bool:
	for boundary: int in [7, 59]:
		var fixture := _gap_fixture()
		if not _check(not fixture.is_empty(), "Control-interruption fixture exists"): return false
		var original: TerrainLab = fixture.lab
		var data: TerrainData = fixture.data
		var key := str(fixture.key)
		if not _check(GapSettlement.set_ecology_modes(original, original.controlled_person_id(), [key], "protected").ok, "Protected cleared source still permits legal restoration"): return false
		if not _check(original.site_controller._control_family_person(null, original.npc.person_id).ok, "Actual original NPC becomes controlled"): return false
		original.site_controller.manual_work("restore")
		if not _check(str(data.site.worker.target) == key and str(data.site.worker.action) == "restore" and bool(data.site.worker.manual_control), "Actual controlled NPC restoration accepted"): return false
		if not _gap_progress(original, float(boundary)): return false
		var conservation := _gap_conservation(original, key)
		var people := _gap_people(original)
		if not _check(original.site_controller.work_team.reserved_targets().has(key), "Original in-progress source claim exists"): return false
		if not _check(original.site_controller._control_family_person(null, original.character.person_id).ok, "Actual family handoff selects original player"): return false
		if not _gap_step(original): return false
		if not _check(original.controlled_person_id() == original.character.person_id and str(data.site.worker.target).is_empty() and float(data.site.worker.progress) == 0.0 and not bool(data.site.worker.manual_control), "Original NPC manual task stops on loss of control"): return false
		if not _check(not original.site_controller.work_team.reserved_targets().has(key) and _gap_conservation(original, key) == conservation and _gap_people(original) == people, "7/59 handoff releases only work claim; source/cargo/deadline/base/person holders do not jump"): return false
		gap_rows.append({"case": "ECO06_actual_control_handoff", "progress_minutes": boundary})
		rf_labs.erase(original)
		original.free()
	gap_groups += 1
	return true

func _gap_late_completion() -> bool:
	for blocker: String in ["construction", "FIRE_ARROW_pending"]:
		var fixture := _gap_fixture(blocker == "FIRE_ARROW_pending", blocker == "FIRE_ARROW_pending")
		if not _check(not fixture.is_empty(), "Late-completion fixture exists"): return false
		var original: TerrainLab = fixture.lab
		var data: TerrainData = fixture.data
		var key := str(fixture.key)
		if not _gap_autonomous_restore(original, key) or not _gap_progress(original, 59.0): return false
		if blocker == "construction":
			var cells: Array[int] = [int(Env.resource(data, key).cell)]
			var paid := Runtime.request_build(data, "road", cells, original.site_controller.reserves_cell)
			if not _check(paid.ok and data.feature_at[cells[0]] != 0, "Original paid construction arrives after restore acceptance"): return false
		else:
			if not _gap_shoot(original, Vector2i(16, 10), true): return false
		var pending: Callable = data.get_meta(&"fire_pending_projectile_query")
		if blocker == "FIRE_ARROW_pending" and not _check(pending.is_valid() and pending.call("resource:" + key), "Original Lab pending callback blocks the accepted restoration"): return false
		if not _check(absf(float(data.site.worker.progress) - 59.0) < 0.000001 and str(data.site.worker.target) == key, "New blocker does not fabricate/complete original 59-minute task"): return false
		var conservation := _gap_conservation(original, key)
		var fire := var_to_bytes(data.site.get("fire", {}))
		var unit := _unit(data, key).duplicate(true)
		var fuel := _fuel(data, key)
		var final := Runtime.harvest(data, key, original.npc.terrain_cell, data.site.worker.cargo, "restore", false)
		if not _check(not final.ok and str(final.code) == ("OCCUPIED" if blocker == "construction" else "FIRE_HOT"), "Original completion commit revalidates the late blocker"): return false
		if not _check(_gap_conservation(original, key) == conservation and var_to_bytes(data.site.get("fire", {})) == fire, "Rejected final commit changes neither source/cargo/deadline nor any Fire history"): return false
		if not _gap_zero_pool_step(original, key): return false
		if not _check(_gap_conservation(original, key) == conservation and _fuel(data, key) == fuel, "Original blocked shared step cannot clear/replenish/arm growth or grant cargo"): return false
		if blocker == "FIRE_ARROW_pending":
			var after := _unit(data, key)
			for field: String in ["profile", "generation", "scorch", "heat", "residue_q", "fuel_remainder_q"]:
				if not _check(after[field] == unit[field], "Pending-blocked restore preserves original cold Fire " + field): return false
			if not _check(pending.call("resource:" + key) and Runtime.fire_save_guard(data).ok, "Real pending projectile survives the test step; original cold unit leaf codec stays valid"): return false
		gap_rows.append({"case": "ECO06_late_restore_completion_revalidation", "blocker": blocker, "progress_minutes": 59})
		rf_labs.erase(original)
		original.free()
	gap_groups += 1
	return true

func _gap_paid_construction() -> bool:
	var fixture := _gap_fixture()
	if not _check(not fixture.is_empty(), "Paid-construction fixture exists"): return false
	var original: TerrainLab = fixture.lab
	var data: TerrainData = fixture.data
	var key := str(fixture.key)
	var cells: Array[int] = [int(Env.resource(data, key).cell)]
	var stone := int(data.site.inventory.stone)
	var paid := Runtime.request_build(data, "road", cells, original.site_controller.reserves_cell)
	if not _check(paid.ok, "Original road payment accepted"): return false
	var feature_key := str(paid.feature)
	var feature: Dictionary = data.site.features[feature_key]
	if not _check(int(data.site.inventory.stone) == stone - int(feature.cost.stone), "Construction debits its real cost exactly once"): return false
	if not _check(original.npc.place(data.cell_from_index(int(feature.entrance)), true), "Actual original NPC occupies original construction entrance"): return false
	original.site_controller.enable_worker()
	var inputs: Dictionary = original.site_controller._prepare_original_work_inputs()
	if not _check(bool(inputs.worker_ready) and str(data.site.worker.target) == "feature:" + feature_key and str(data.site.worker.action) == "construct", "Original worker chooses the paid construction zone"): return false
	if not _gap_progress(original, 1.0, feature_key): return false
	if not _check(GapSettlement.set_ecology_modes(original, original.controlled_person_id(), [key], "protected").ok, "Original policy owner protects the source after payment/progress"): return false
	var frozen := var_to_bytes(feature)
	var source := _gap_conservation(original, key)
	var claim: Dictionary = original.site_controller.work_team.reserved_targets().duplicate(true)
	var paid_stone := int(data.site.inventory.stone)
	if not _gap_zero_pool_step(original, "feature:" + feature_key): return false
	if not _check(var_to_bytes(feature) == frozen and _gap_conservation(original, key) == source and original.site_controller.work_team.reserved_targets() == claim and int(data.site.inventory.stone) == paid_stone and str(data.feature_at[cells[0]]) == feature_key, "Protected paid construction keeps payment/progress/task claim/occupied cells/source/cargo"): return false
	if not _check(GapSettlement.set_ecology_modes(original, original.controlled_person_id(), [key], "general").ok, "Original policy owner removes construction block"): return false
	if not _gap_progress(original, float(feature.work), feature_key): return false
	if not _check(str(feature.stage) == "complete" and not feature.has("pending_build") and int(data.site.inventory.stone) == paid_stone and str(data.feature_at[cells[0]]) == feature_key, "Same original paid construction resumes to completion with no second debit"): return false
	gap_rows.append({"case": "ECO05_actual_shared_pool_protected_paid_construction", "progress_before_protection": 1, "completed": true})
	rf_labs.erase(original)
	original.free()
	gap_groups += 1
	return true

func _run() -> void:
	assert(_gap_control_interruption())
	assert(_gap_late_completion())
	assert(_gap_paid_construction())
	assert(not failed and gap_groups == 3)
	_finish(true)
