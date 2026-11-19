extends "res://scripts/tests/site_fire_projectile_pipeline_test.gd"
## P4 functional candidate. Real original roster/holders/jobs/Registry/Grid.
## Test thermal genesis is explicitly mathematical; this is not the M1 arrow test.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_WORK_MULTI_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _register(f: Fixture, team: TerrainArmy) -> bool:
	if f.lab.combat_movement_coordinator == null: f.lab.combat_movement_coordinator = SiteCombatMovementCoordinator.new()
	f.lab.combat_movement_coordinator.register_formation(team)
	return _check(f.lab.combat_movement_coordinator.resolve_occupancy_rebuild_checked().ok, "Original coordinator owns every original member")

func _four_slots_hundred_roster(mode: String = "SUPPRESS") -> bool:
	var f := _fixture()
	var slots: Array[Vector2i] = [Vector2i(29, 30), Vector2i(31, 30), Vector2i(30, 29), Vector2i(30, 31)]
	var cells: Array[Vector2i] = [Vector2i(5, 5)]
	cells.append_array(slots)
	for y in range(5, 15):
		for x in range(5, 15):
			if cells.size() < 100 and Vector2i(x, y) != Vector2i(5, 5): cells.append(Vector2i(x, y))
	var team := _team(f, cells, 1, 0, TerrainArmy.TROOP_TYPE_ID)
	if failed or not _register(f, team): return false
	var target := Vector2i(30, 30)
	SiteEnvironment._add_resource(f.data, SiteEnvironment.Kind.TIMBER, f.data.index(target), 4, 0)
	SiteEnvironment.rebuild_indexes(f.data)
	var resource := "%d:%d" % [SiteEnvironment.Kind.TIMBER, f.data.index(target)]
	var key := "resource:" + resource
	var state := SiteRuntime._fire_state(f.data, 0.0)
	var unit := SiteRuntime._fire_unit(f.data, state, SiteRuntime._fire_resource_descriptor(f.data, resource))
	unit.merge({"profile": "TEST_HEAT_100", "heat": 200.0 if mode == "SUPPRESS" else 0.0, "state": "HEATING", "intensity": 0.0, "moisture": 0.0}, true)
	state.active[key] = true
	var supply_field := str(SiteCombatRules.fire_work_profile(mode).supply_field)
	for index in range(1, 5):
		team.combat_units[index].item_state[supply_field] = 1024
		var admitted := f.controller.person_actions._begin_fire_work(team.combat_identity(team.current_commander), team.combat_identity(index), key, slots[index - 1], false, mode)
		if not _check(admitted.ok, "WK-01 distinct original member owns one of four legal cardinal contact slots", admitted): return false
	var registration := f.lab.combat_movement_coordinator.deployment_registry.capture_handoff_state()
	team.combat_units[5].item_state[supply_field] = 1024
	var rejected := f.controller.person_actions._begin_fire_work(team.combat_identity(team.current_commander), team.combat_identity(5), key, slots[0], false, mode)
	if not _check(not rejected.ok and not f.controller.person_actions.is_busy(team.combat_identity(5))
		and f.lab.combat_movement_coordinator.deployment_registry.capture_handoff_state() == registration
		and f.controller.person_actions._jobs.size() == 4, "WK-01 hundred-member roster still admits only four distinct work slots", rejected): return false
	var other := _team(f, [Vector2i(35, 25), Vector2i(35, 26)], 2, 0, TerrainArmy.TROOP_TYPE_ID)
	if failed or not _register(f, other): return false
	other.combat_units[1].item_state[supply_field] = 1024
	var other_holder := var_to_bytes(other.combat_units[1].item_state)
	rejected = f.controller.person_actions._begin_fire_work(other.combat_identity(other.current_commander), other.combat_identity(1), key, slots[0], false, mode)
	if not _check(not rejected.ok and var_to_bytes(other.combat_units[1].item_state) == other_holder
		and f.lab.combat_movement_coordinator.deployment_registry.capture_handoff_state() == registration
		and f.controller.person_actions._jobs.size() == 4, "WK-02 second formation cannot acquire or debit another formation's work slot", rejected): return false
	_step(f, 0.2)
	var spent := 0
	for index in range(1, 5):
		spent += 1024 - int(team.combat_units[index].item_state[supply_field])
		if not _check(team.combat_units[index].item_state[supply_field] == 820
			and f.controller.person_actions.job_for(team.combat_identity(index)).phase == "WORKING",
			"Each arrived original worker owns exactly204 quanta of actual action work", index): return false
	if not _check(spent == 816 and absf(float(f.data.site.fire.units[key].heat) - (149.0 if mode == "SUPPRESS" else 51.0)) < 0.000000001
		and team.combat_units[5].item_state[supply_field] == 1024,
		"WK-01 only four real workers contribute51 signed heat; remaining96 original roster members add zero output: " + mode): return false
	var retained: Variant = f.lab.combat_movement_coordinator.deployment_registry.owner_of(slots[1])
	if not _check(f.controller.person_actions.cancel(team.combat_identity(1)).ok
		and f.lab.combat_movement_coordinator.deployment_registry.owner_of(slots[0]) == null
		and is_same(retained, f.lab.combat_movement_coordinator.deployment_registry.owner_of(slots[1]))
		and f.controller.person_actions._jobs.size() == 3, "Cancelling one work member preserves every other original lease/job"): return false
	_close(f)
	return true

func _ignite_real_holder() -> bool:
	var f := _fixture()
	var team := _team(f, [Vector2i(8, 8), Vector2i(14, 12)], 1, 0, TerrainArmy.TROOP_TYPE_ID)
	if failed or not _register(f, team): return false
	var target := Vector2i(15, 12)
	SiteEnvironment._add_resource(f.data, SiteEnvironment.Kind.TIMBER, f.data.index(target), 4, 0)
	SiteEnvironment.rebuild_indexes(f.data)
	var resource := "%d:%d" % [SiteEnvironment.Kind.TIMBER, f.data.index(target)]
	var key := "resource:" + resource
	var holder: Dictionary = team.combat_units[1].item_state
	holder.fire_lab_ignition_q = 1024 # Only original holder genesis; no external supply chain.
	var stock := var_to_bytes(f.data.site.inventory)
	var before := var_to_bytes(f.data.site)
	var queried := SiteRuntime.fire_work_target(f.data, key, "IGNITE")
	if not _check(queried.ok and not queried.complete and not f.data.site.has("fire")
		and var_to_bytes(f.data.site) == before, "IGNITE cold original fuel query does not create heat/state or supply"): return false
	var admitted := f.controller.person_actions.begin_fire_ignite(team.combat_identity(team.current_commander), team.combat_identity(1), key, Vector2i(14, 12))
	if not _check(admitted.ok and not f.data.site.has("fire") and holder.fire_lab_ignition_q == 1024,
		"Original IGNITE job admission reserves real slot without premature heat/debit", admitted): return false
	_step(f, STEP)
	if not _check(f.data.site.has("fire") and float(f.data.site.fire.units[key].heat) == 0.0
		and holder.fire_lab_ignition_q == 990 and f.data.site.fire.suppression_pending[0].mode == "IGNITE",
		"First actual working interval debits34 original ignition quanta and queues finite heat only"): return false
	for tick in range(90):
		_step(f, STEP)
		if not f.controller.person_actions.is_busy(team.combat_identity(1)): break
	if not _check(not f.controller.person_actions.is_busy(team.combat_identity(1)) and str(f.data.site.fire.units[key].state) == "BURNING"
		and int(holder.fire_lab_ignition_q) > 0 and int(holder.fire_lab_ignition_q) < 1024
		and var_to_bytes(f.data.site.inventory) == stock and f.lab.combat_movement_coordinator.deployment_registry.owner_of(Vector2i(14, 12)) == null,
		"Original finite IGNITE reaches burning at original fire boundary then stops without drawing shared inventory"): return false
	var after := var_to_bytes([holder, f.data.site.fire])
	admitted = f.controller.person_actions.begin_fire_ignite(team.combat_identity(team.current_commander), team.combat_identity(1), key, Vector2i(14, 12))
	if not _check(admitted.ok and admitted.complete and var_to_bytes([holder, f.data.site.fire]) == after,
		"Already burning original target is a pure completed work no-op"): return false
	_close(f)
	return true

func _run() -> void:
	for mode: String in ["SUPPRESS", "IGNITE"]:
		if not _four_slots_hundred_roster(mode): _finish(false, "four slots / cross formation: " + mode); return
	if not _ignite_real_holder(): _finish(false, "finite original IGNITE"); return
	_finish(not failed)
