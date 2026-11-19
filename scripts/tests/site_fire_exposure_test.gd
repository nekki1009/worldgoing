extends "res://scripts/tests/site_fire_projectile_pipeline_test.gd"
## OUTPUT-ONLY CANDIDATE / NOT_RUN. Original P1 fixture, Lab, Army, Grid and
## damage/death entries. Direct fire writes below are isolated arithmetic genesis.
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const TOL := 0.00001

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	var file := FileAccess.open(OUTPUT + "/exposure_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "evidence": evidence,
			"scope": "P3-A GD exposure only; excludes navigation policy, suppression, M1, Native and GPU"}, "\t"))
	print("SITE_FIRE_EXPOSURE_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _hot_fixture(f: Fixture, cell: Vector2i) -> Dictionary:
	# Original cleared timber residue is walkable; finite isolated fixture fuel.
	var key := "%d:%d" % [SiteEnvironment.Kind.TIMBER, f.data.index(cell)]
	SiteEnvironment._add_resource(f.data, SiteEnvironment.Kind.TIMBER, f.data.index(cell), 256, 0)
	var state := SiteRuntime._fire_state(f.data, f.lab.fire_action_cursor)
	var unit := SiteRuntime._fire_unit(f.data, state, SiteRuntime._fire_resource_descriptor(f.data, key))
	SiteEnvironment.change(f.data, key, {"remaining": 0, "cleared": true})
	SiteEnvironment.rebuild_indexes(f.data)
	unit.merge({"profile": "TEST_HEAT_100", "heat": 100.0, "state": "BURNING", "intensity": 1.0,
		"moisture": 0.0, "residue_q": 256 * SiteRuntime.FIRE_Q}, true)
	state.active["resource:" + key] = true
	SiteRuntime.fire_hazard_invalidate(f.data)
	return unit

func _protection(team: TerrainArmy) -> float:
	return 1.0 / (1.0 + SiteCombatRules.armor_level(str(team.ranged_defense(0).armor)))

func _stationary_and_ko() -> bool:
	for ko: bool in [false, true]:
		var f := _fixture()
		var cell := Vector2i(10, 10)
		var team := _team(f, [cell])
		_hot_fixture(f, cell)
		if ko: team.apply_unit_contact(0, {"result": {"hp": 0.0, "stun": SiteCombatRules.STUN_LIMIT, "guard_break": false}, "shield": false})
		var hit_revision := int(team.combat_units[0].get("hit_revision", 0))
		var expected := float(SiteCombatRules.FIRE_BODY.hazard_hp_rate) * _protection(team) * 0.1
		_step(f, 0.1)
		if not _check(f.lab.fire_projectiles.is_empty() and absf(float(team.combat_hot_get(0, &"hp")) - (100.0 - expected)) < TOL,
			"No-flight original Lab exposure damages stationary and KO owner", {"ko": ko, "expected_hp": 100.0 - expected}): return false
		if not _check(not ko or not team._cell_owners.has(cell), "KO remains exposed after original occupancy removal"): return false
		if not _check(int(team.combat_units[0].get("hit_revision", 0)) == hit_revision and f.lab._fire_body_buckets.is_empty(),
			"Environmental damage does not fake hostile hit revision or leave materialized body buckets"): return false
		var body: Dictionary = team.combat_units[0].fire_body
		var hp := float(team.combat_hot_get(0, &"hp"))
		var duplicate := team.advance_fire_exposure(0, int(body.last_interval), 0.0, float(body.last_action_end), [{"begin": 0.0, "end": float(body.last_action_end), "risk": 1.0, "wet": false}])
		if not _check(duplicate.ok and duplicate.duplicate and float(team.combat_hot_get(0, &"hp")) == hp, "Same original interval cannot charge HP twice"): return false
		if not _check(not f.lab.fire_save_guard().ok and not SiteRuntime.fire_save_guard(f.data).ok and not SiteStore.fire_event_guard(f.data).ok,
			"Original Lab/Runtime/Store remain BUSY for body and fire history"): return false
		_close(f)
	return true

func _rejected_original_proposal() -> bool:
	var f := _fixture()
	var cell := Vector2i(10, 10)
	var team := _team(f, [cell])
	f.data.site.controlled_person_id = f.character.person_id
	var coordinator := SiteCombatMovementCoordinator.new()
	f.lab.combat_movement_coordinator = coordinator
	coordinator.register_formation(team)
	if not _check(coordinator.resolve_occupancy_rebuild_checked().ok, "Original Coordinator reconstructs exact live occupancy"): return false
	var grid := coordinator.movement_reservation_grid
	var identity := team.combat_identity(0)
	grid.begin_tick({cell: identity}, f.data)
	var proposal := grid.propose_move(int(coordinator._registered_formations[team.get_instance_id()]), identity, team.get_order_serial(), cell, cell + Vector2i.RIGHT)
	grid.resolve_all()
	# The real HOLD owner rejects this proposed MOVE in its original preflight.
	grid.commit_all(coordinator._member_lookup, coordinator.current_logic_tick)
	if not _check(grid.proposal_lookup[proposal].status != Types.MoveProposalStatus.ACCEPTED and team.moving_to[0] == TerrainArmy.INVALID_CELL,
		"Actual original Grid proposal is rejected by original owner preflight"): return false
	_hot_fixture(f, cell)
	# Explicit static fixture genesis AFTER observing a genuine original Grid
	# rejection. P3-B remains enabled: there is now no legal escaping edge.
	for direction: Vector2i in TerrainData.DIRECTIONS:
		SiteEnvironment._add_resource(f.data, SiteEnvironment.Kind.STONE, f.data.index(cell + direction), 120, 0)
	SiteEnvironment.rebuild_indexes(f.data)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if not _check(not f.data.can_step(cell, cell + direction), "Original blocking stone closes each escape edge after rejected proposal"): return false
	var expected := float(SiteCombatRules.FIRE_BODY.hazard_hp_rate) * _protection(team) * 0.1
	_step(f, 0.1)
	var ok := _check(team.cells[0] == cell and team.moving_to[0] == TerrainArmy.INVALID_CELL
		and absf(float(team.combat_hot_get(0, &"hp")) - 100.0 + expected) < TOL,
		"Rejected proposal remains at true source and takes full source exposure")
	_close(f)
	return ok

func _original_half_step(chunk: float) -> bool:
	var f := _fixture()
	var source := Vector2i(10, 10)
	var team := _team(f, [source])
	f.data.site.controlled_person_id = f.character.person_id
	f.lab.combat_movement_coordinator = SiteCombatMovementCoordinator.new()
	f.lab.combat_movement_coordinator.register_formation(team)
	if not _check(f.lab.combat_movement_coordinator.resolve_occupancy_rebuild_checked().ok, "Original movement owner starts with a legal source"): return false
	if not _check(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, source + Vector2i.RIGHT).ok, "Original MOVE accepted"): return false
	for tick in range(60):
		_step(f, STEP)
		if team.moving_to[0] != TerrainArmy.INVALID_CELL: break
	if not _check(team.moving_to[0] == source + Vector2i.RIGHT and team.move_curve[0] == 0, "Original Grid starts the real quadratic Army step"): return false
	var progress := float(team.move_progress[0])
	var duration := float(team.move_duration[0])
	var crossing := 1.0 - sqrt(0.5) # Independent analytic solution of p(2-p)=0.5.
	if not _check(progress < crossing and duration > 0.0, "Fixture observes original committed step before its source-cell crossing"): return false
	var paths := var_to_bytes(team._combat_move_plan.member_paths)
	_hot_fixture(f, source)
	var to_finish := (1.0 - progress) * duration
	_step(f, to_finish - 0.005, chunk)
	if not _check(team.cells[0] == source and team.moving_to[0] != TerrainArmy.INVALID_CELL and var_to_bytes(team._combat_move_plan.member_paths) == paths,
		"No new proposal replaces the half-step; path cursor waits for original completion barrier"): return false
	_step(f, 0.025, chunk)
	var expected := (crossing - progress) * duration * float(SiteCombatRules.FIRE_BODY.hazard_hp_rate) * _protection(team)
	var ok := _check(team.cells[0] == source + Vector2i.RIGHT and team.moving_to[0] == TerrainArmy.INVALID_CELL
		and absf(float(team.combat_hot_get(0, &"hp")) - 100.0 + expected) < TOL,
		"Original quadratic dwell and arrived safe tail match analytic exposure", {"chunk": chunk, "expected_loss": expected, "hp": team.combat_hot_get(0, &"hp")})
	evidence.append({"case": "original_half_step", "chunk": chunk, "progress": progress, "duration": duration, "analytic_hp_loss": expected, "actual_hp": team.combat_hot_get(0, &"hp")})
	_close(f)
	return ok

func _actor_fixture(f: Fixture, cell: Vector2i, mounted: bool = false) -> TerrainTestCharacter:
	var actor := f.character
	actor.person_id = 1
	actor.site_exited = false
	actor.exchange_enabled = true
	f.data.site.controlled_person_id = actor.person_id
	actor.visual_state.mounted = mounted
	var appearance := HumanCharacter3DEditor.default_appearance()
	appearance.parts.armor = "none"
	appearance.parts.shield = "none"
	actor._saved_appearance = appearance.duplicate(true)
	_check(SiteRuntime.seed_person_equipment(f.data, actor.item_state, actor.person_id, appearance).ok, "Original actor equipment registry owns test clothing")
	_check(actor.place(cell, true), "Original Actor placed at fixture source")
	f.lab.combat_actors.append(actor)
	return actor

func _actor_curve(mounted: bool) -> bool:
	var f := _fixture()
	var source := Vector2i(10, 10)
	var actor := _actor_fixture(f, source, mounted)
	_hot_fixture(f, source)
	if not _check(actor.step(Vector2i.RIGHT, true), "Original Actor accepts running/riding input"): return false
	var duration := float(actor._movement_duration)
	var crossing := 1.0 - sqrt(0.5)
	if mounted:
		# An independent high-resolution oracle samples only the original public
		# curve, not the candidate interval integrator or presentation offsets.
		var low := 0.0
		var high := 1.0
		for iteration in range(40):
			var middle := (low + high) * 0.5
			if TerrainTestCharacter.riding_weight(middle, actor._ride_start_speed, actor._ride_end_speed, duration, 1.0) < 0.5: low = middle
			else: high = middle
		crossing = (low + high) * 0.5
	_step(f, duration + 0.05)
	var expected := crossing * duration * float(SiteCombatRules.FIRE_BODY.hazard_hp_rate)
	var ok := _check(not actor.is_moving() and absf(actor.hp - 100.0 + expected) < TOL,
		"Original running/riding curve plus arrived tail yields correct HP", {"mounted": mounted, "duration": duration, "expected_loss": expected, "hp": actor.hp})
	_close(f)
	return ok

func _finite_burning_water_height() -> bool:
	var f := _fixture()
	var cell := Vector2i(10, 10)
	var actor := _actor_fixture(f, cell)
	_hot_fixture(f, cell)
	var navigation := f.data.navigation_revision
	var snapshot := SiteRuntime.fire_hazard_snapshot(f.data)
	if not _check(SiteRuntime.fire_exposure_at(snapshot, cell, 0.0) == 1.0 and SiteRuntime.fire_exposure_at(snapshot, cell, 2.0) == 0.0,
		"Ground residue does not expose a different raised surface at same XY"): return false
	_step(f, 10.5)
	if not _check(actor.hp > 0.0 and float(actor.fire_body.burn_left) == 0.0 and not bool(actor.fire_body.armed)
		and float(actor.fire_body.dose) > float(SiteCombatRules.FIRE_BODY.dose_threshold), "Continuous heat cannot refresh one body-burning episode beyond finite cap"): return false
	if not _check(f.data.navigation_revision == navigation and SiteRuntime.fire_hazard_revision(f.data) == int(snapshot.revision),
		"Heat stays in one risk band without changing hazard or navigation revision"): return false
	var water := cell + Vector2i.RIGHT
	f.data.surface_types[f.data.index(water)] = TerrainData.Surface.WATER
	f.data.water_kind[f.data.index(water)] = 1
	f.data.flags[f.data.index(water)] = TerrainData.Flag.WALKABLE # Isolated shallow-water fixture genesis.
	if not _check(actor.step(Vector2i.RIGHT), "Original Actor enters fixture shallow water"): return false
	_step(f, actor._movement_duration + STEP)
	var ok := _check(float(actor.fire_body.dose) == 0.0 and float(actor.fire_body.burn_left) == 0.0 and actor.fire_body.contacts.is_empty()
		and not f.lab._fire_exposure_wet(water, 2.0), "Actual water-foot contact quenches body; raised surface does not")
	_close(f)
	return ok

func _actual_body_and_shield() -> bool:
	for shield: bool in [false, true]:
		var f := _fixture()
		var shooter := _team(f, [Vector2i(10, 10)])
		var friend := _team(f, [Vector2i(13, 10)], 2, 0, TerrainArmy.TROOP_TYPE_ID if shield else &"bow")
		var target := _team(f, [Vector2i(16, 10)], 3, 1)
		friend.facing[0] = Vector2i.LEFT
		if shield:
			if not _check(friend.set_unit_guard(0, true), "Original shield stance accepts"): return false
			_step(f, SiteCombatRules.GUARD_TRANSITION + STEP)
		shooter.combat_units[0].cargo.fire_arrow = 1
		if not _geometry_preflight(f, shooter, friend, shield): return false
		if not _order(f, shooter, {"type": "person", "person_id": target.combat_identity(0)}, "FIRE_ARROW") or not _await_release(f) or not _stop(f, shooter): return false
		_step(f, 1.4)
		if not _check(f.contacts.size() == 1 and int(f.contacts[0].target) == friend.combat_identity(0) and f.lab.fire_impact_recorder.size() == 1,
			"One genuine released arrow reaches original friendly body/shield"): return false
		var body: Dictionary = friend.combat_units[0].get("fire_body", {})
		if not _check(not body.is_empty() and (shield or float(body.dose) > 0.0), "Original contact feeds finite body state after kinetic settlement"): return false
		if shield and not _check(str(f.contacts[0].result.kind) == "shield" and friend.combat_hot_get(0, &"hp") == 100.0,
			"Shield heat reduction does not invent kinetic or burning damage"): return false
		var payload: Dictionary = f.lab.fire_impact_recorder[0]
		var bytes := var_to_bytes(body)
		var duplicate := SiteRuntime.fire_receive_impact(f.data, payload)
		if not _check(duplicate.ok and duplicate.duplicate and var_to_bytes(body) == bytes, "Original consumed receipt cannot refill body contact"): return false
		_step(f, 3.0)
		if not _check(friend.combat_units[0].fire_body.contacts.is_empty(), "Original finite contact expires without ground fuel or new arrow"): return false
		_close(f)
	return true

func _run() -> void:
	if not _stationary_and_ko(): _finish(false, "stationary / KO / dedup / save"); return
	if not _rejected_original_proposal(): _finish(false, "original rejected Grid proposal"); return
	for chunk: float in [STEP, 1.0 / 240.0]:
		if not _original_half_step(chunk): _finish(false, "original accepted and half-finished movement"); return
	for mounted: bool in [false, true]:
		if not _actor_curve(mounted): _finish(false, "original Actor curve"); return
	if not _finite_burning_water_height(): _finish(false, "finite body / water / height / revision"); return
	if not _actual_body_and_shield(): _finish(false, "real original body and shield contacts"); return
	_finish(not failed, "P3-A original-owner exposure; named scope only")
