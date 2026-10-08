extends "res://scripts/tests/site_fire_projectile_pipeline_test.gd"
## OUTPUT CANDIDATE / NOT_RUN. Original Army/Controller/Coordinator lifecycle.
## Test fire genesis is named arithmetic input, not actual M1 fire-arrow proof.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_SUPPRESSION_PERSON_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _worker_fixture(start: Vector2i, supply: int = 1024, house: bool = false) -> Dictionary:
	var f := _fixture()
	var team := _team(f, [Vector2i(8, 8), start], 1, 0, TerrainArmy.TROOP_TYPE_ID)
	if failed: return {}
	f.lab.combat_movement_coordinator = SiteCombatMovementCoordinator.new()
	f.lab.combat_movement_coordinator.register_formation(team)
	if not _check(f.lab.combat_movement_coordinator.resolve_occupancy_rebuild_checked().ok, "Original coordinator owns original worker occupancy"): return {}
	var target_cell := Vector2i(15, 12)
	var target_key := ""
	var descriptor := {}
	var feature_key := ""
	if house:
		var layout := SiteRuntime.building_cells(f.data, "house", target_cell, Vector2i(2, 2), {"owner_faction": 0})
		if not _check(layout.ok, "Original house layout admits fixture"): return {}
		var cells: Array[int] = []
		cells.assign(layout.cells)
		var built := SiteRuntime.request_build(f.data, "house", cells, Callable(), {"owner_faction": 0})
		if not _check(built.ok, "Original house consumes actual construction stock"): return {}
		feature_key = str(built.feature)
		var feature: Dictionary = f.data.site.features[feature_key]
		var task := {"version": 2, "zone": -1, "target": "feature:" + feature_key, "action": "construct",
			"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
		SiteRuntime._feature_work(f.data, feature_key, float(feature.work), Callable(), Callable(), task, {}, 20, 0)
		if not _check(feature.stage == "complete", "Original house construction completes"): return {}
		f.lab.siege_queue_damage({feature_key + "|body": {"feature": feature_key, "part": "body", "damage": 20.0}}, {}, 0.0)
		descriptor = SiteRuntime._fire_feature_descriptor(f.data, feature_key, "body")
		target_key = "feature:" + feature_key + ":body"
	else:
		SiteEnvironment._add_resource(f.data, SiteEnvironment.Kind.TIMBER, f.data.index(target_cell), 4, 0)
		SiteEnvironment.rebuild_indexes(f.data)
		var resource := "%d:%d" % [SiteEnvironment.Kind.TIMBER, f.data.index(target_cell)]
		descriptor = SiteRuntime._fire_resource_descriptor(f.data, resource)
		target_key = "resource:" + resource
	var fire := SiteRuntime._fire_state(f.data, 0.0)
	var unit := SiteRuntime._fire_unit(f.data, fire, descriptor)
	unit.merge({"profile": "TEST_HEAT_100", "heat": 20.0, "state": "HEATING", "intensity": 0.0, "moisture": 0.0}, true)
	fire.active[target_key] = true
	team.combat_units[1].item_state.fire_lab_suppression_q = supply # Only genesis supply.
	return {"fixture": f, "team": team, "worker": team.combat_identity(1), "holder": team.combat_units[1].item_state,
		"key": target_key, "slot": Vector2i(14, 12), "unit": unit, "feature": feature_key}

func _begin_worker(c: Dictionary) -> bool:
	var result: Dictionary = c.fixture.controller.person_actions.begin_fire_suppress(c.team.combat_identity(c.team.current_commander), c.worker, c.key, c.slot)
	return _check(result.ok, "Original commander starts original PersonActions SUPPRESS job", result)

func _half_step_cancel() -> bool:
	var c := _worker_fixture(Vector2i(10, 12))
	if c.is_empty() or not _begin_worker(c): return false
	var f: Fixture = c.fixture
	_step(f, STEP)
	if not _check(c.team.moving_to[1] != TerrainArmy.INVALID_CELL and c.holder.fire_lab_suppression_q == 1024,
		"WK-03 original coordinator starts real half-step; no arrival means zero supply debit"): return false
	var destination: Vector2i = c.team.moving_to[1]
	var position: Vector2 = c.team.combat_ground(1)
	var cancelled := f.controller.person_actions.cancel(c.worker)
	if not _check(cancelled.ok and c.team.moving_to[1] == destination and c.team.combat_ground(1) == position,
		"WK-05 cancellation never snaps a committed original half-step"): return false
	for tick in range(60):
		_step(f, STEP)
		if not f.controller.person_actions.is_busy(c.worker): break
	return _check(not f.controller.person_actions.is_busy(c.worker) and c.team.cells[1] == destination
		and c.team.moving_to[1] == TerrainArmy.INVALID_CELL and c.holder.fire_lab_suppression_q == 1024
		and f.lab.combat_movement_coordinator.deployment_registry.owner_of(c.slot) == null,
		"Original committed move finishes; exact SUPPRESS lease releases with zero unpaid cooling")

func _clock_and_final_supply() -> bool:
	var signatures: Array[String] = []
	for speed: float in [0.5, 1.0, 2.0, 4.0]:
		var c := _worker_fixture(Vector2i(14, 12))
		if c.is_empty(): return false
		var f: Fixture = c.fixture
		f.lab.simulation_speed = speed
		if not _begin_worker(c): return false
		_step(f, 0.2)
		var unit: Dictionary = f.data.site.fire.units[c.key]
		if not _check(c.holder.fire_lab_suppression_q == 820 and is_equal_approx(float(unit.heat), 7.25),
			"TM-01 six original action slices debit exactly204 quanta and cool12.75 at every game speed", speed): return false
		signatures.append(JSON.stringify([c.holder.fire_lab_suppression_q, unit.heat, unit.scorch]))
		if not _check(f.controller.person_actions.cancel(c.worker).ok, "Original cancellation releases stationary job"): return false
		_close(f)
	for value: String in signatures:
		if not _check(value == signatures[0], "Action-time cooling signature is speed independent"): return false
	var c := _worker_fixture(Vector2i(14, 12), 5)
	if c.is_empty() or not _begin_worker(c): return false
	_step(c.fixture, 0.2)
	return _check(c.holder.fire_lab_suppression_q == 0 and not c.fixture.controller.person_actions.is_busy(c.worker)
		and is_equal_approx(float(c.fixture.data.site.fire.units[c.key].heat), 20.0 - 5.0 / 16.0),
		"WK-04 original job debits last five quanta once, keeps paid effect, then stops")

func _partial_interval() -> bool:
	var c := _worker_fixture(Vector2i(14, 12), 17)
	if c.is_empty() or not _begin_worker(c): return false
	var f: Fixture = c.fixture
	var holder: Dictionary = c.holder
	var version := int(holder.version)
	var inventory := var_to_bytes(f.data.site.inventory)
	var fatigue := PersonFatigue.read(c.team.combat_units[1])
	var rate := PersonFatigue.effort_rate(c.team.combat_units[1])
	var game_ratio := SiteRuntime.game_seconds(STEP, SiteRuntime.COMBAT_GRACE) * f.lab.simulation_speed / STEP
	_step(f, STEP)
	var queue: Array = f.data.site.fire.get("suppression_pending", [])
	if not _check(queue.size() == 1 and int(queue[0].total_q) == 17
		and absf(float(queue[0].end) - float(queue[0].begin) - 17.0 / 1024.0) < 0.000000001,
		"WK-04 final seventeen quanta end at actual partial action interval, before whole slice ends", queue): return false
	if not _check(is_same(holder, c.team.combat_units[1].item_state) and holder.fire_lab_suppression_q == 0
		and int(holder.version) == version + 1 and var_to_bytes(f.data.site.inventory) == inventory
		and absf(PersonFatigue.read(c.team.combat_units[1]) - fatigue - 17.0 / 1024.0 * game_ratio * rate) < 0.000000001,
		"Original holder debits once; shared inventory untouched; fatigue charges only productive finite remainder"): return false
	var fire_before := var_to_bytes(f.data.site.fire)
	var holder_before := var_to_bytes(holder)
	f.controller.person_actions.settle_after_contacts()
	if not _check(var_to_bytes(f.data.site.fire) == fire_before and var_to_bytes(holder) == holder_before,
		"Replayed contact settlement cannot debit or enqueue finite remainder twice"): return false
	_step(f, 0.2 - STEP)
	if not _check(absf(float(f.data.site.fire.units[c.key].heat) - 18.9375) < 0.000000001
		and f.data.site.fire.suppression_pending.is_empty() and not f.controller.person_actions.is_busy(c.worker),
		"Original fire boundary applies exactly1.0625 paid cooling after exhausted job ends"): return false
	_close(f)
	return true

func _hurt_half_step(kind: String) -> bool:
	var c := _worker_fixture(Vector2i(10, 12))
	if c.is_empty() or not _begin_worker(c): return false
	var f: Fixture = c.fixture
	var army: TerrainArmy = c.team
	_step(f, STEP)
	var source := army.cells[1]
	var endpoint := army.moving_to[1]
	var ground := army.combat_ground(1)
	if not _check(endpoint != TerrainArmy.INVALID_CELL and army.move_progress[1] > 0.0 and army.move_progress[1] < 1.0,
		"WK-05 death/KO fixture has actual committed half-step", kind): return false
	army.apply_unit_contact(1, {"environmental": true, "shield": false, "result": {
		"hp": float(army.combat_hot_get(1, &"hp")) + 1.0 if kind == "death" else 0.0,
		"stun": SiteCombatRules.STUN_LIMIT if kind == "ko" else 0.0, "guard_break": false}})
	f.controller.person_actions.settle_after_contacts()
	if not _check(not army.combat_can_act(1) and f.controller.person_actions.is_busy(c.worker)
		and f.controller.person_actions.job_for(c.worker).phase == "SETTLING"
		and army.cells[1] == source and army.moving_to[1] == endpoint and army.combat_ground(1) == ground
		and army._cell_owners.get(source) == 1 and army._reserved_cells.get(endpoint) == 1
		and c.holder.fire_lab_suppression_q == 1024 and f.lab.combat_movement_coordinator.deployment_registry.owner_of(c.slot) == null,
		"Original PersonActions cancels after original KO/death and retains both physical claims", kind): return false
	for tick in range(60):
		_step(f, STEP)
		if not f.controller.person_actions.is_busy(c.worker): break
	if not _check(not f.controller.person_actions.is_busy(c.worker) and army.cells[1] == endpoint
		and army.moving_to[1] == TerrainArmy.INVALID_CELL and army._reserved_cells.is_empty()
		and c.holder.fire_lab_suppression_q == 1024 and f.data.site.fire.get("suppression_pending", []).is_empty(),
		"Original movement barrier finishes deceased/unconscious worker once with no unpaid cooling", kind): return false
	_close(f)
	return true

func _accepted_hold_and_stale_lease() -> bool:
	var c := _worker_fixture(Vector2i(14, 12))
	if c.is_empty() or not _begin_worker(c): return false
	var f: Fixture = c.fixture
	var army: TerrainArmy = c.team
	var serial := army.get_order_serial()
	var ranged := army.ranged_order_serial
	var fire_before := var_to_bytes(f.data.site.fire)
	var holder_before := var_to_bytes(c.holder)
	# Original pre-contact job owner creates uncommitted work; interrupt it before
	# its original contact settlement. No test-written pending job or fire input.
	f.controller.person_actions.advance_fire_jobs(0.0, STEP, STEP)
	if not _check(not f.controller.person_actions.job_for(c.worker).pending.is_empty(), "Actual arrived job prepared work before command interruption"): return false
	var rejected := army.issue_combat_order(-999, TerrainArmy.CombatOrder.HOLD)
	if not _check(not rejected.ok and army.ranged_order_serial == ranged and f.controller.person_actions.is_busy(c.worker),
		"Rejected original command leaves work intent intact"): return false
	var accepted := army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.HOLD)
	if not _check(accepted.ok and army.get_order_serial() == serial and army.ranged_order_serial > ranged,
		"Accepted original HOLD changes ranged epoch even when main serial stays equal", accepted): return false
	f.controller.person_actions.settle_after_contacts()
	if not _check(not f.controller.person_actions.is_busy(c.worker) and var_to_bytes(c.holder) == holder_before
		and var_to_bytes(f.data.site.fire) == fire_before and army.combat_order == TerrainArmy.CombatOrder.HOLD,
		"WK-05 accepted HOLD cancels prepared unpaid work through original ranged epoch"): return false
	_close(f)
	c = _worker_fixture(Vector2i(14, 12))
	if c.is_empty() or not _begin_worker(c): return false
	f = c.fixture
	army = c.team
	var job: Dictionary = f.controller.person_actions._jobs[str(c.worker)]
	var registry: SiteDeploymentReservationRegistry = f.lab.combat_movement_coordinator.deployment_registry
	if not _check(registry.release_work_slot(job.lease).ok, "Original Registry releases exact work lease for reuse test"): return false
	var replaced := registry.reserve_work_slot(army.team_id, army.get_order_serial(), c.worker + 1000, c.slot)
	if not _check(replaced.ok, "Original Registry reuses slot with different member lease", replaced): return false
	f.controller.person_actions.settle_after_contacts()
	if not _check(not f.controller.person_actions.is_busy(c.worker) and is_same(registry.owner_of(c.slot), replaced.lease)
		and c.holder.fire_lab_suppression_q == 1024, "Old job cancellation cannot erase replacement slot owner or debit supply"): return false
	registry.release_work_slot(replaced.lease)
	_close(f)
	return true

func _accepted_move_half_step() -> bool:
	var c := _worker_fixture(Vector2i(10, 12))
	if c.is_empty() or not _begin_worker(c): return false
	var f: Fixture = c.fixture
	var army: TerrainArmy = c.team
	_step(f, STEP)
	var endpoint := army.moving_to[1]
	if not _check(endpoint != TerrainArmy.INVALID_CELL, "New MOVE arrives during actual SUPPRESS half-step"): return false
	var accepted := army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(20, 20))
	if not _check(accepted.ok, "Original formation accepts replacement MOVE", accepted): return false
	var plan := army.get_active_move_plan()
	var snapshot := {"paths": plan.member_paths.duplicate(true), "to": plan.member_pending_to_cell.duplicate(true),
		"from": plan.member_pending_from_cell.duplicate(true), "ids": plan.member_pending_proposal_id.duplicate(true),
		"slots": army.get_active_deployment_plan().member_slot_map.duplicate(true)}
	f.controller.person_actions.settle_after_contacts()
	for tick in range(60):
		army.prepare_combat(STEP, STEP)
		f.lab.combat_movement_coordinator.complete_committed_moves()
		f.controller.person_actions.settle_after_contacts()
		if not f.controller.person_actions.is_busy(c.worker): break
	if not _check(not f.controller.person_actions.is_busy(c.worker) and army.cells[1] == endpoint
		and army.combat_order == TerrainArmy.CombatOrder.MOVE and is_same(plan, army.get_active_move_plan())
		and snapshot.paths == plan.member_paths and snapshot.to == plan.member_pending_to_cell
		and snapshot.from == plan.member_pending_from_cell and snapshot.ids == plan.member_pending_proposal_id
		and snapshot.slots == army.get_active_deployment_plan().member_slot_map and c.holder.fire_lab_suppression_q == 1024,
		"WK-05 old PersonActions settlement preserves all replacement MOVE plan state"): return false
	_close(f)
	return true

func _slot_becomes_hot() -> bool:
	var c := _worker_fixture(Vector2i(10, 12))
	if c.is_empty(): return false
	var f: Fixture = c.fixture
	SiteEnvironment._add_resource(f.data, SiteEnvironment.Kind.TIMBER, f.data.index(c.slot), 1, 0)
	var resource := "%d:%d" % [SiteEnvironment.Kind.TIMBER, f.data.index(c.slot)]
	SiteEnvironment.rebuild_indexes(f.data)
	var slot_unit := SiteRuntime._fire_unit(f.data, f.data.site.fire, SiteRuntime._fire_resource_descriptor(f.data, resource))
	slot_unit.fuel_remainder_q = 1023 # Genesis finite remnant; no new supply after admission.
	SiteEnvironment.change(f.data, resource, {"remaining": 0})
	SiteEnvironment.rebuild_indexes(f.data)
	if not _check(f.data.is_walkable(c.slot) and SiteRuntime.fire_hazard_at(f.data, c.slot) == 0.0,
		"Actual depleted timber slot is walkable and safe before original job admission"): return false
	if not _begin_worker(c): return false
	var nav_revision := int(f.data.navigation_revision)
	var injected := SiteRuntime.fire_receive_impact(f.data, {"site_id": str(f.data.site.id), "projectile_id": 1, "event_id": "arrow:1",
		"action_time": f.lab.fire_action_cursor, "type": "ground", "cell": c.slot, "remaining_heat_budget": 80.0,
		"heat_rate": 400.0, "max_seconds": 0.2, "heat_transfer": 1.0, "contact_scale": 1.0})
	if not _check(injected.ok and injected.accepted, "Original Runtime admits finite environmental contact after work admission"): return false
	_step(f, 0.2)
	if not _check(f.data.is_walkable(c.slot) and int(f.data.navigation_revision) == nav_revision
		and SiteRuntime.fire_hazard_at(f.data, c.slot) > 0.0 and c.holder.fire_lab_suppression_q == 1024,
		"WK-05 original fire boundary ignites future slot without changing occupancy topology or pre-arrival stock"): return false
	var endpoint: Vector2i = c.team.moving_to[1]
	var position: Vector2 = c.team.combat_ground(1)
	f.controller.person_actions.settle_after_contacts()
	if not _check(c.team.moving_to[1] == endpoint and c.team.combat_ground(1) == position
		and f.lab.combat_movement_coordinator.deployment_registry.owner_of(c.slot) == null
		and c.holder.fire_lab_suppression_q == 1024, "Unsafe slot cancellation releases lease without snapping original committed body"): return false
	for tick in range(60):
		_step(f, STEP)
		if not f.controller.person_actions.is_busy(c.worker): break
	if not _check(not f.controller.person_actions.is_busy(c.worker) and c.holder.fire_lab_suppression_q == 1024,
		"Approach to newly ignited slot settles without producing any suppression"): return false
	_close(f)
	return true

func _original_rest_cycle() -> bool:
	var c := _worker_fixture(Vector2i(14, 12))
	if c.is_empty(): return false
	var f: Fixture = c.fixture
	var army: TerrainArmy = c.team
	var body: Dictionary = army.combat_units[1]
	PersonFatigue.write(body, "fatigue", 80.0) # Explicit fatigue genesis, before job starts.
	PersonFatigue.write(body, "fatigue_rest", 0.0)
	if not _begin_worker(c): return false
	_step(f, STEP)
	if not _check(f.controller.person_actions.job_for(c.worker).phase == "REST"
		and bool(body.work_resting) and c.holder.fire_lab_suppression_q == 1024,
		"TM-04 original80 threshold enters safe stopped job REST without paid work"): return false
	var cursor := f.lab.fire_action_cursor
	var fire_before := var_to_bytes(f.data.site.fire)
	var holder_before := var_to_bytes(c.holder)
	# This is an explicit original-fatigue-owner integration check, not a claim
	# that90minutes of every Lab owner ran. The shared team rest gate is real.
	f.lab._advance_team_fatigue(army, 5429.0, {}, {})
	if not _check(PersonFatigue.read(body) > 50.0 and PersonFatigue.read(body) < 50.01
		and c.holder.fire_lab_suppression_q == 1024 and f.lab.fire_action_cursor == cursor
		and var_to_bytes(f.data.site.fire) == fire_before, "Original whole-team rest owner recovers toward50 without action-time work"): return false
	_step(f, STEP)
	if not _check(f.controller.person_actions.job_for(c.worker).phase == "REST" and var_to_bytes(c.holder) == holder_before,
		"Original hysteresis retains REST immediately above50"): return false
	var intervening_game_seconds := SiteRuntime.game_seconds(STEP, SiteRuntime.COMBAT_GRACE) * f.lab.simulation_speed
	f.lab._advance_team_fatigue(army, 1.0 - intervening_game_seconds, {}, {})
	if not _check(PersonFatigue.read(body) <= 50.0 and var_to_bytes(c.holder) == holder_before,
		"Original recovery reaches50 after actual5430 game seconds"): return false
	_step(f, STEP)
	if not _check(f.controller.person_actions.job_for(c.worker).phase == "WORKING"
		and not bool(body.work_resting) and int(c.holder.fire_lab_suppression_q) < 1024
		and PersonFatigue.read(body) > 50.0, "TM-04 original shared step resumes paid work at50 and charges original fatigue pool"): return false
	_close(f)
	return true

func _cold_never_repairs_building() -> bool:
	var c := _worker_fixture(Vector2i(14, 12), 1024, true)
	if c.is_empty(): return false
	var f: Fixture = c.fixture
	var feature: Dictionary = f.data.site.features[c.feature]
	var hp := float(feature.parts.body.hp)
	var fuel := int(c.unit.fuel_q)
	var inventory := var_to_bytes(f.data.site.inventory)
	if not _check(hp < SiteRuntime.civil_max_hp(feature) and hp > 0.0, "Original damage owner reduced house HP before suppression"): return false
	if not _begin_worker(c): return false
	for tick in range(60):
		_step(f, STEP)
		if not f.controller.person_actions.is_busy(c.worker): break
	var unit: Dictionary = f.data.site.fire.units[c.key]
	if not _check(not f.controller.person_actions.is_busy(c.worker) and float(unit.heat) == 0.0
		and c.holder.fire_lab_suppression_q == 704 and float(feature.parts.body.hp) == hp
		and int(unit.fuel_q) == fuel and float(unit.scorch) >= float(c.unit.scorch)
		and var_to_bytes(f.data.site.inventory) == inventory and f.lab.combat_movement_coordinator.deployment_registry.owner_of(c.slot) == null,
		"WK-06 original paid cooling reaches cold, releases exact lease, never repairs original HP or replenishes fuel"): return false
	_close(f)
	return true

func _run() -> void:
	if not _half_step_cancel(): _finish(false, "half-step/cancel"); return
	if not _clock_and_final_supply(): _finish(false, "action clock/final supply"); return
	if not _partial_interval(): _finish(false, "partial original-holder interval"); return
	for kind: String in ["death", "ko"]:
		if not _hurt_half_step(kind): _finish(false, kind); return
	if not _accepted_hold_and_stale_lease() or not _accepted_move_half_step(): _finish(false, "command/lease replacement"); return
	if not _slot_becomes_hot(): _finish(false, "slot ignition"); return
	if not _original_rest_cycle(): _finish(false, "original fatigue owner80to50"); return
	if not _cold_never_repairs_building(): _finish(false, "cold preserves building damage/fuel"); return
	_finish(not failed)
