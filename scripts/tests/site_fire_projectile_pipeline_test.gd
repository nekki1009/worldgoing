extends SceneTree
## P1 original Lab/Controller/Army pipeline. Real admitted Army contact geometry;
## no synthetic body, replacement projectile, copied scheduler or alternative clock.
## Only fixture genesis writes stock/terrain. Every flight is an original release.
const STEP := 1.0 / 30.0
const Snapshot = preload("res://scripts/terrain_lab/site_exchange_snapshot.gd")
const Collision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const Crowd = preload("res://scripts/terrain_lab/crowd_site.gd")
const OUTPUT := "res://output/fire_implementation_20261006"
var checks := 0
var failed := false
var finished := false
var evidence: Array[Dictionary] = []
var fixtures: Array[Fixture] = []

class Fixture extends RefCounted:
	var data: TerrainData
	var lab: TerrainLab
	var controller: SiteController
	var character: TerrainTestCharacter
	var teams: Array[TerrainArmy] = []
	var contacts: Array[Dictionary] = []
	var ignition: Array[Dictionary] = []

func _initialize() -> void:
	create_timer(120.0, true).timeout.connect(func() -> void: _finish(false, "120-second pipeline deadline"))
	_run.call_deferred()

func _check(value: bool, label: String, detail: Variant = null) -> bool:
	checks += 1
	if value: return true
	failed = true
	push_error("FIRE_PIPELINE_FAIL: " + label + " " + str(detail))
	evidence.append({"failure": label, "detail": str(detail)})
	return false

func _fixture() -> Fixture:
	var f := Fixture.new()
	fixtures.append(f)
	f.data = TerrainData.new()
	f.data.allocate(Vector2i(64, 64))
	f.data.spawn_cell = Vector2i(3, 3)
	f.data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(f.data, "fire-projectile-pipeline")
	f.data.height_levels.fill(0)
	f.data.ramp_edges.fill(0)
	f.data.static_blocked.fill(0)
	f.data.water_kind.fill(0)
	f.data.water_body.fill(-1)
	f.data.flags.fill(TerrainData.Flag.WALKABLE)
	f.data.foundation.fill(80)
	f.data.resource_base.clear()
	f.data.site.changes.clear()
	for item: String in SiteEnvironment.ITEM_NAMES: f.data.site.inventory[item] = 1000
	f.data.site.capacity = 100000
	SiteEnvironment.rebuild_indexes(f.data)
	_check(SiteRuntime.initialize_item_storage(f.data.site).ok, "Original item registry initializes")
	f.lab = TerrainLab.new()
	f.lab.terrain = f.data
	f.lab.restore_only = true
	f.lab.exchange_enabled = true
	f.lab.physical_ranged_enabled = true
	# Family continuity's original fallback expects the original character node.
	# This absent template is not a combatant and supplies no collision geometry.
	f.character = TerrainTestCharacter.new()
	f.character.data = f.data
	f.character.person_id = 1000000000
	f.character.site_exited = true
	f.lab.character = f.character
	f.controller = SiteController.new()
	root.add_child(f.controller)
	f.controller.lab = f.lab
	f.lab.site_controller = f.controller
	f.controller.message = Label.new()
	f.controller.add_child(f.controller.message)
	f.controller.food_delivery.init(f.controller)
	f.controller.vehicles.init(f.controller)
	f.controller.person_actions.init(f.lab)
	f.controller.equipment_orders.init(f.lab, f.controller.person_actions)
	f.controller.work_team.init(f.lab)
	f.controller.captive_escort.init(f.lab, f.controller.person_actions)
	f.controller.captivity_supply.init(f.controller)
	f.controller.family_continuity.init(f.lab)
	f.lab.ranged_resolved.connect(func(source: int, target: int, result: Dictionary) -> void:
		f.contacts.append({"source": source, "target": target, "result": result.duplicate(true)}))
	f.lab.fire_ignition_sink = func(payload: Dictionary) -> void: f.ignition.append(payload.duplicate(true))
	return f

func _team(f: Fixture, cells: Array[Vector2i], team_id: int = 1, faction: int = 0, troop: StringName = &"bow") -> TerrainArmy:
	var team := TerrainArmy.new()
	f.teams.append(team)
	root.add_child(team)
	team.set_process(false)
	team.team_id = team_id
	team.faction_id = faction
	team.exchange_enabled = true
	team.roster_size = cells.size()
	team.training = 100.0
	if not _check(team.deploy_at(f.data, null, null, cells) and team.enable_combat(false, 0, troop), "Original Army admits fixture roster", troop): return team
	for row: Dictionary in team.combat_units:
		row.item_state = {}
		row.cargo = {"arrow": 0, "fire_arrow": 0, "bolt": 0}
		if not _check(SiteRuntime.seed_person_equipment(f.data, row.item_state, int(row.person_id), row.appearance).ok, "Each original row owns registered equipment"): return team
	team.command_abilities[0].tactics = 0
	f.lab.combat_armies.append(team)
	f.controller.wire_combat_team(team)
	# Publish the original registered equipment through its existing Controller owner.
	f.controller.initialize_team_items(team)
	team.target_query = f.lab._army_target
	team.exchange_people_query = f.lab._exchange_people.bind(false)
	team.ranged_tactics_query = f.lab._ranged_tactics
	team.external_blocker = func(cell: Vector2i) -> bool:
		for other: TerrainArmy in f.teams:
			if other != team and other.blocks_cell(cell): return true
		return false
	if f.teams.size() == 1:
		f.lab.army = team
		f.data.site.controlled_person_id = team.combat_identity(0)
	f.lab._wire_fire_ranged()
	return team

func _close(f: Fixture) -> void:
	if not is_instance_valid(f.lab): return
	if f.lab.combat_movement_coordinator != null:
		for team: TerrainArmy in f.teams:
			f.lab.combat_movement_coordinator.unregister_formation(team)
		f.lab.combat_movement_coordinator = null
	f.data.remove_meta(&"fire_event_guard")
	f.lab.fire_ignition_sink = Callable()
	f.lab.fire_reservations.clear()
	f.lab.fire_projectiles.clear()
	f.lab.combat_actors.clear()
	f.lab.combat_armies.clear()
	for team: TerrainArmy in f.teams:
		team.external_blocker = Callable()
		team.target_query = Callable()
		team.exchange_people_query = Callable()
		team.ranged_tactics_query = Callable()
		team.ranged_target_validate = Callable()
		team.equipment_appearance_query = Callable()
		team.equipment_appearance_batch_query = Callable()
		team.clear()
		team.free()
	f.teams.clear()
	f.character.ranged_target_validate = Callable()
	f.character.exchange_skill_authorized = Callable()
	f.character.free()
	f.controller.free()
	f.lab.free()
	fixtures.erase(f)

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT + "/pipeline_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "evidence": evidence,
			"scope": "P1 headless original GD pipeline; no Native flight, GPU, FPS, persistence restoration, fire propagation or complete phase acceptance"}, "\t"))
		file.close()
	print("SITE_FIRE_PROJECTILE_PIPELINE_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _step(f: Fixture, seconds: float, chunk: float = STEP, combat_clock: float = 0.0) -> void:
	var left := seconds
	var spent := 0.0
	while left > 0.000000001:
		var elapsed := minf(left, chunk)
		f.lab._advance_combat(elapsed, maxf(0.0, combat_clock - spent))
		spent += elapsed
		left = maxf(0.0, left - elapsed)

func _person(team: TerrainArmy, index: int = 0) -> Dictionary:
	return {"owner": team, "unit": index, "id": team.combat_identity(index), "cell": team.cells[index], "faction": team.faction_id}

func _ground(cell: Vector2i) -> Dictionary:
	return {"type": "ground", "cell": [cell.x, cell.y]}

func _order(f: Fixture, team: TerrainArmy, target: Dictionary, mode: String = "NORMAL") -> bool:
	var result := f.lab.issue_fire_order(team.current_commander, team, target, mode)
	return _check(result.ok, "Original Lab typed order is accepted", result)

func _await_release(f: Fixture, expected: int = 1, limit: float = 1.5) -> bool:
	for tick in range(ceili(limit / STEP)):
		_step(f, STEP)
		if f.lab.ranged_shots >= expected: return _check(f.lab.ranged_shots == expected, "Release count has no duplicate", f.lab.ranged_shots)
	return _check(false, "Original pipeline release reached deadline", {"shots": f.lab.ranged_shots, "reservations": f.lab.fire_reservations})

func _stop(f: Fixture, team: TerrainArmy) -> bool:
	return _check(f.lab.stop_fire_order(team.current_commander, team).ok, "Original stop order accepted")

func _flight_result(f: Fixture) -> Dictionary:
	return {"shots": f.lab.ranged_shots, "resolutions": f.lab.ranged_resolutions,
		"events": f.lab.fire_impact_recorder.duplicate(true), "contacts": f.contacts.duplicate(true)}

func _geometry_preflight(f: Fixture, shooter: TerrainArmy, target: TerrainArmy, needs_shield: bool = false) -> bool:
	var geometry := target.incoming_geometry(0)
	var aim := f.lab._fire_target_aim({"type": "person", "person_id": target.combat_identity(0)})
	var source_ground := shooter.combat_ground(0) / TerrainRenderer.CELL_PIXELS
	var target_ground := target.combat_ground(0) / TerrainRenderer.CELL_PIXELS
	return _check(not geometry.body.is_empty() and (not needs_shield or not geometry.shield.is_empty())
		and not aim.is_empty() and (aim.point as Vector3).is_finite()
		and Vector2(aim.point.x, aim.point.y).distance_to(target_ground) < 0.000001
		and Vector2i(source_ground.floor()) == shooter.cells[0] and Vector2i(target_ground.floor()) == target.cells[0]
		and f.data.effective_height(shooter.cells[0]) == 0 and f.data.effective_height(target.cells[0]) == 0
		and is_equal_approx(float(aim.point.z), 1.0),
		"Preflight real Army geometry, nominal aim and both original navigation surfaces agree",
		{"shield": needs_shield, "aim": aim, "source_ground": source_ground, "target_ground": target_ground})

func _actor_paths() -> bool:
	for kind: String in ["bow", "crossbow", "fire"]:
		var f := _fixture()
		var actor := f.character
		actor.person_id = 1
		actor.site_exited = false
		actor.exchange_enabled = true
		actor.exchange_skill_authorized = func() -> bool: return actor.person_id == f.lab.controlled_person_id()
		actor.training = 100.0
		f.data.site.controlled_person_id = actor.person_id
		if not _check(actor.place(Vector2i(10, 10), true), "AR-17 original Actor is placed on original surface"): return false
		var appearance := HumanCharacter3DEditor.default_appearance()
		appearance.parts.weapon = "crossbow_01" if kind == "crossbow" else "bow_01"
		appearance.parts.shield = "none"
		actor._saved_appearance = appearance.duplicate(true)
		if not _check(SiteRuntime.seed_person_equipment(f.data, actor.item_state, actor.person_id, appearance).ok, "AR-16 Actor weapon is an original registered item"): return false
		actor.ammo_inventory = f.data.site.manual.cargo
		var ammo := "bolt" if kind == "crossbow" else ("fire_arrow" if kind == "fire" else "arrow")
		actor.ammo_inventory[ammo] = 1
		f.lab.combat_actors.append(actor)
		actor.combat_event.connect(f.controller._combat_event)
		f.lab._wire_fire_ranged()
		var accepted := f.lab.issue_fire_order(actor.person_id, actor, _ground(Vector2i(16, 10)), "FIRE_ARROW" if kind == "fire" else "NORMAL")
		if not _check(accepted.ok, "AR-16/17 original Lab accepts Actor bow/crossbow/fire order", accepted): return false
		if not _await_release(f): return false
		if not _check(f.lab.stop_fire_order(actor.person_id, actor).ok, "Original Actor stop retains emitted flight"): return false
		_step(f, 1.4)
		if not _check(f.lab.ranged_shots == 1 and f.lab.ranged_resolutions == 1 and int(actor.ammo_inventory[ammo]) == 0
			and actor.projectiles.is_empty() and f.ignition.size() == (1 if kind == "fire" else 0),
			"AR-16/17 original Actor owns one debit while Lab owns one finite flight/contact", _flight_result(f)): return false
		evidence.append({"case": "actor_" + kind, "result": _flight_result(f)})
		_close(f)
	return true

func _static_and_moving() -> bool:
	for moving: bool in [false, true]:
		var f := _fixture()
		var shooter := _team(f, [Vector2i(10, 10)])
		var target := _team(f, [Vector2i(16, 10)], 2, 1)
		if failed: return false
		if moving:
			# Match the original TerrainLab admission before issuing MOVE.
			f.lab.combat_movement_coordinator = SiteCombatMovementCoordinator.new()
			for team: TerrainArmy in f.teams: f.lab.combat_movement_coordinator.register_formation(team)
			var occupancy := f.lab.combat_movement_coordinator.resolve_occupancy_rebuild_checked()
			if not _check(occupancy.ok and target._coordinator == f.lab.combat_movement_coordinator,
				"AR-04 original Coordinator and Reservation Grid own target movement", occupancy): return false
		shooter.combat_units[0].cargo.arrow = 1
		if not _geometry_preflight(f, shooter, target): return false
		if not _order(f, shooter, {"type": "person", "person_id": target.combat_identity(0)}): return false
		if not _await_release(f): return false
		if not _check(f.lab.fire_projectiles.size() == 1 and float(target.combat_units[0].hp) == 100.0, "AR-01 release has flight time and no prepaid target damage"): return false
		var flight: Dictionary = f.lab.fire_projectiles[0]
		var trajectory := var_to_bytes([flight.origin, flight.velocity, flight.total, flight.aim_key])
		if not _stop(f, shooter): return false
		if moving:
			var move := target.issue_combat_order(target.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(16, 7))
			if not _check(move.ok, "AR-04 target moves through original Army order", move): return false
		if moving:
			var motion_trace: Array[Dictionary] = []
			var original_grid_commit_seen := false
			for tick in range(42): # Same original 1.4 action seconds as the control.
				_step(f, STEP)
				var batches := f.lab.combat_movement_coordinator.get_inflight_batches_for_formation(target)
				if target.moving_to[0] != TerrainArmy.INVALID_CELL and not batches.is_empty():
					original_grid_commit_seen = original_grid_commit_seen or (target._cell_owners.get(target.cells[0], -1) == 0
						and target._reserved_cells.get(target.moving_to[0], -1) == 0)
				motion_trace.append({"action_time": f.lab.fire_action_cursor, "cell": target.cells[0],
					"moving_to": target.moving_to[0], "progress": float(target.move_progress[0]),
					"ground": target.combat_ground(0), "order_delay": target._order_delay,
					"grid_batches": batches.size(), "hp": float(target.combat_units[0].hp), "resolutions": f.lab.ranged_resolutions})
			evidence.append({"case": "moving_original_owner_trace", "trace": motion_trace})
			if not _check(original_grid_commit_seen, "AR-04 target physically advances through original reserved movement", motion_trace): return false
		else:
			_step(f, 1.4)
		if not _check(trajectory == var_to_bytes([flight.origin, flight.velocity, flight.total, flight.aim_key]), "AR-04 emitted trajectory never follows target"): return false
		if not _check(f.lab.ranged_shots == 1 and f.lab.ranged_resolutions == 1 and f.lab.fire_projectiles.is_empty()
			and int(shooter.combat_units[0].cargo.arrow) == 0 and shooter.projectiles.is_empty(), "AR-01/09 exactly one original debit and one physical settlement"): return false
		if moving:
			if not _check(target.cells[0] != Vector2i(16, 10) and float(target.combat_units[0].hp) == 100.0
				and int(f.contacts[0].target) != target.combat_identity(0), "AR-04 moved original target is missed, never hit at old cell", _flight_result(f)): return false
		else:
			if not _check(int(f.contacts[0].target) == target.combat_identity(0) and float(target.combat_units[0].hp) < 100.0
				and is_equal_approx(100.0 - float(target.combat_units[0].hp), float(f.contacts[0].result.hp)), "AR-01 actual body contact applies precisely one kinetic packet", _flight_result(f)): return false
		var settled := var_to_bytes([target.combat_units[0].hp, f.contacts, f.lab.fire_impact_recorder])
		_step(f, 1.0)
		if not _check(settled == var_to_bytes([target.combat_units[0].hp, f.contacts, f.lab.fire_impact_recorder]), "AR-09 settled flight cannot damage twice"): return false
		evidence.append({"case": "moving" if moving else "static_body", "result": _flight_result(f)})
		_close(f)
	return true

func _shield_owner_evidence(f: Fixture, friend: TerrainArmy, phase: String) -> void:
	var geometry := friend.incoming_geometry(0)
	evidence.append({"case": "real_shield_owner", "phase": phase, "action_time": f.lab.fire_action_cursor,
		"seed": f.data.seed_value, "pose": str(friend.combat_hot_get(0, &"pose")), "facing": friend.facing[0],
		"sample": friend.contact_sample(0), "ground": friend.combat_ground(0),
		"body": geometry.body, "shield": geometry.shield, "hp": float(friend.combat_units[0].hp)})

func _intervening_people() -> bool:
	for shield: bool in [false, true]:
		var f := _fixture()
		var shooter := _team(f, [Vector2i(10, 10)])
		var friend := _team(f, [Vector2i(13, 10)], 2, 0, TerrainArmy.TROOP_TYPE_ID if shield else &"bow")
		var target := _team(f, [Vector2i(16, 10)], 3, 1)
		if failed: return false
		friend.facing[0] = Vector2i.LEFT
		if shield:
			# Carrying a shield only supplies its actual silhouette. Ask the
			# original Army owner to raise it before testing frontal blocking.
			if not _check(friend.set_unit_guard(0, true), "AR-16 original Army accepts frontal shield stance"): return false
			_step(f, SiteCombatRules.GUARD_TRANSITION + STEP)
			if not _check(str(friend.combat_hot_get(0, &"pose")) == "guard" and friend.facing[0] == Vector2i.LEFT,
				"AR-16 original action clock completes shield raise before release"): return false
			_shield_owner_evidence(f, friend, "raised")
		shooter.combat_units[0].cargo.fire_arrow = 1
		if not _geometry_preflight(f, shooter, friend, shield) or not _geometry_preflight(f, shooter, target): return false
		if not _order(f, shooter, {"type": "person", "person_id": target.combat_identity(0)}, "FIRE_ARROW"): return false
		if not _await_release(f) or not _stop(f, shooter): return false
		if shield: _shield_owner_evidence(f, friend, "released")
		_step(f, 1.4)
		if shield: _shield_owner_evidence(f, friend, "terminal")
		if not _check(f.contacts.size() == 1 and int(f.contacts[0].target) == friend.combat_identity(0)
			and float(target.combat_units[0].hp) == 100.0, "AR-05 earliest real friendly interception protects later target", _flight_result(f)): return false
		if shield:
			if not _check(str(f.contacts[0].result.kind) == "shield" and float(friend.combat_units[0].hp) == 100.0
				and is_equal_approx(float(f.contacts[0].result.heat_transfer), 0.1), "AR-16 actual shield blocks kinetic and retains reduced contact heat", _flight_result(f)): return false
		else:
			if not _check(float(friend.combat_units[0].hp) < 100.0 and str(f.contacts[0].result.kind) in ["hit", "graze"], "AR-16 geometric body contact has no second miss roll", _flight_result(f)): return false
		if not _check(f.ignition.size() == 1 and float(f.ignition[0].remaining_heat_budget) > 0.0
			and float(f.ignition[0].remaining_heat_budget) < 20.0, "AR-16 burning contact carries one finite decayed ember budget"): return false
		evidence.append({"case": "real_shield" if shield else "real_friend", "result": _flight_result(f)})
		_close(f)
	return true

func _wall() -> bool:
	var f := _fixture()
	var shooter := _team(f, [Vector2i(10, 10)])
	var target := _team(f, [Vector2i(16, 10)], 2, 1)
	if failed: return false
	shooter.combat_units[0].cargo.arrow = 1
	var options := {"owner_faction": 1}
	var layout := SiteRuntime.building_cells(f.data, "stone_wall", Vector2i(13, 9), Vector2i(1, 3), options)
	if not _check(layout.ok, "Original wall layout is legal", layout): return false
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var requested := SiteRuntime.request_build(f.data, "stone_wall", cells, Callable(), options)
	if not _check(requested.ok, "Original wall consumes original depot construction stock", requested): return false
	var key := str(requested.feature)
	var feature: Dictionary = f.data.site.features[key]
	var work := {"version": 2, "zone": -1, "target": "feature:" + key, "action": "construct",
		"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(f.data, key, float(feature.work), Callable(), Callable(), work, {}, 20, 1)
	if not _check(str(feature.stage) == "complete" and SiteRuntime.validate_feature_layout(f.data, feature).ok, "Wall completes through original Runtime owner"): return false
	if not _order(f, shooter, {"type": "person", "person_id": target.combat_identity(0)}): return false
	if not _await_release(f) or not _stop(f, shooter): return false
	_step(f, 1.4, 0.4)
	if not _check(f.lab.fire_impact_recorder.size() == 1 and str(f.lab.fire_impact_recorder[0].type) == "structure"
		and str(f.lab.fire_impact_recorder[0].feature) == key and float(target.combat_units[0].hp) == 100.0,
		"AR-03 original curved flight is intercepted by original high wall before rear body", _flight_result(f)): return false
	var thin := Collision.segment_prism_contact(Vector3(0, 0.5, 1), Vector3(10, 0.5, 1), Rect2(4, 0, 0.001, 1), 0.0, 2.0)
	if not _check(not thin.is_empty() and absf(float(thin.fraction) - 0.4) < 0.000001, "AR-02 original continuous query catches substep thin prism at earliest fraction", thin): return false
	evidence.append({"case": "original_wall_and_thin_query", "result": _flight_result(f), "thin_fraction": thin.fraction})
	_close(f)
	return true

func _cancel_and_modes() -> bool:
	for reason: String in ["stop", "move", "death", "mode", "inventory"]:
		var f := _fixture()
		var shooter := _team(f, [Vector2i(10, 10)])
		if failed: return false
		shooter.combat_units[0].cargo.fire_arrow = 1
		shooter.combat_units[0].cargo.arrow = 1
		if not _order(f, shooter, _ground(Vector2i(16, 10)), "FIRE_ARROW"): return false
		var reserved := f.lab.request_fire_release(_person(shooter), shooter.ranged_target)
		if not _check(reserved.ok and f.lab.fire_reservations.size() == 1 and f.lab.ranged_shots == 0
			and int(shooter.combat_units[0].cargo.fire_arrow) == 1, "AR-07 preparation reserves without debit", reason): return false
		match reason:
			"stop":
				if not _stop(f, shooter): return false
			"move":
				if not _check(shooter.issue_combat_order(shooter.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(10, 8)).ok, "Original move cancels fire preparation"): return false
			"death": shooter.combat_hot_set(0, &"hp", 0.0) # Genesis fault injection; no fabricated death/hit packet.
			"mode":
				if not _order(f, shooter, _ground(Vector2i(16, 10)), "NORMAL"): return false
			"inventory":
				shooter.combat_units[0].item_state.version = int(shooter.combat_units[0].item_state.version) + 1
				if not _stop(f, shooter): return false
		_step(f, 1.2)
		if not _check(int(shooter.combat_units[0].cargo.fire_arrow) == 1 and f.lab.fire_reservations.is_empty(), "AR-07/18 invalidated preparation never consumes fire arrow", reason): return false
		if reason == "mode":
			if not _check(f.lab.ranged_shots == 1 and int(shooter.combat_units[0].cargo.arrow) == 0, "AR-18 replacement NORMAL consumes only original normal arrow"): return false
		elif not _check(f.lab.ranged_shots == 0 and int(shooter.combat_units[0].cargo.arrow) == 1, "Cancelled preparation publishes no release", reason): return false
		_close(f)
	return true

func _roster_windows() -> bool:
	for limited: bool in [false, true]:
		var f := _fixture()
		var cells: Array[Vector2i] = []
		for index in range(100): cells.append(Vector2i(25 + index % 10 * 2, 25 + floori(float(index) / 10.0) * 2))
		cells[1] = Vector2i(10, 8)
		cells[17] = Vector2i(10, 10)
		cells[63] = Vector2i(10, 12)
		var shooter := _team(f, cells)
		if failed: return false
		for index: int in [1, 17, 63]: shooter.combat_units[index].cargo.fire_arrow = 1
		if limited: shooter.combat_hot_set(63, &"exchange_cooldown", 10.0)
		if not _order(f, shooter, _ground(Vector2i(16, 10)), "FIRE_ARROW"): return false
		var snapshot := Snapshot.new()
		snapshot.capture(f.lab.combat_actors, f.lab.combat_armies)
		if not _check(snapshot.ranged_people().size() == 100, "AR-06 upstream original snapshot retains fire-only cargo without ordinary arrow"): return false
		var expected := 2 if limited else 3
		_step(f, 2.2)
		if not _stop(f, shooter): return false
		if not _check(f.lab.ranged_shots == expected and f.lab.fire_projectiles.is_empty(), "AR-06/12 exact legal window releases without waiting for other 98 rows", {"limited": limited, "shots": f.lab.ranged_shots}): return false
		for index in range(100):
			var expected_ammo := 1 if limited and index == 63 else 0
			if not _check(int(shooter.combat_units[index].cargo.fire_arrow) == expected_ammo and shooter.projectiles.is_empty(), "AR-06 original cargo never borrows ammunition", index): return false
		evidence.append({"case": "two_eligible_window" if limited else "100_people_three_fire_arrows", "result": _flight_result(f)})
		_close(f)
	return true

func _capacity_and_fairness() -> bool:
	var f := _fixture()
	var a := _team(f, [Vector2i(10, 8), Vector2i(10, 10), Vector2i(10, 12)])
	var b := _team(f, [Vector2i(20, 8), Vector2i(20, 10)], 2, 0)
	if failed: return false
	f.lab.fire_projectile_capacity = 1
	for team: TerrainArmy in [a, b]:
		for row: Dictionary in team.combat_units: row.cargo.fire_arrow = 1
		if not _order(f, team, _ground(Vector2i(16, 10)), "FIRE_ARROW"): return false
	var first := f.lab.request_fire_release(_person(a), a.ranged_target)
	var cargo_before := var_to_bytes(b.combat_units[0].cargo)
	var deferred := f.lab.request_fire_release(_person(b), b.ranged_target)
	if not _check(first.ok and str(deferred.code) == "CAPACITY_DEFERRED" and cargo_before == var_to_bytes(b.combat_units[0].cargo)
		and f.lab.fire_reservations.size() == 1, "AR-08 full reserved capacity explicitly defers without stealing/debit", deferred): return false
	var owners := {}
	for tick in range(360):
		_step(f, STEP)
		if not _check(f.lab.fire_projectiles.size() + f.lab.fire_reservations.size() <= 1, "AR-08 original pool never exceeds capacity"): return false
		for flight: Dictionary in f.lab.fire_projectiles: owners[int(flight.source_formation_id)] = true
		if f.lab.ranged_shots == 5 and f.lab.fire_projectiles.is_empty() and f.lab.fire_reservations.is_empty(): break
	if not _check(f.lab.ranged_shots == 5 and owners.size() == 2, "AR-08 multiple capacity windows eventually serve both original teams and all five holders", {"shots": f.lab.ranged_shots, "owners": owners}): return false
	for team: TerrainArmy in [a, b]:
		for row: Dictionary in team.combat_units:
			if not _check(int(row.cargo.fire_arrow) == 0, "AR-08 fairness releases each original member's own last arrow"): return false
	evidence.append({"case": "capacity_fairness", "result": _flight_result(f)})
	_close(f)
	return true

func _clock_and_guards() -> bool:
	var baseline := {}
	for speed: float in [0.5, 1.0, 2.0, 4.0]:
		for slow: bool in [false, true]:
			var f := _fixture()
			var shooter := _team(f, [Vector2i(10, 10)])
			if failed: return false
			f.lab.simulation_speed = speed
			shooter.visible = not slow # Presentation visibility cannot own flight state.
			shooter.combat_units[0].cargo.fire_arrow = 1
			if not _order(f, shooter, _ground(Vector2i(16, 10)), "FIRE_ARROW"): return false
			if not _check(f.lab.request_fire_release(_person(shooter), shooter.ranged_target).ok, "TM-01 original preparation starts at shared action zero"): return false
			_step(f, 1.0, 0.5 if slow else STEP, 0.4)
			if not _check(f.lab.fire_projectiles.size() == 1, "TM-01 released arrow is still flying at matched action sample", _flight_result(f)): return false
			var flight: Dictionary = f.lab.fire_projectiles[0]
			var sample := {"position": flight.position, "elapsed": flight.elapsed, "ember": flight.ember, "spawn_action": flight.spawn_action}
			if baseline.is_empty(): baseline = sample.duplicate(true)
			if not _check((sample.position as Vector3).distance_to(baseline.position) < 0.000001
				and absf(float(sample.elapsed) - float(baseline.elapsed)) < 0.000001
				and absf(float(sample.ember) - float(baseline.ember)) < 0.000001
				and absf(float(sample.spawn_action) - float(baseline.spawn_action)) < 0.000001,
				"TM-01/AR-15 action flight and ember ignore game speed, slow frames and combat clock crossing zero", {"speed": speed, "slow": slow, "sample": sample, "baseline": baseline}): return false
			if not _stop(f, shooter): return false
			var after_stop := var_to_bytes(f.lab.fire_projectiles)
			if not _check(not f.lab.fire_projectiles.is_empty() and int(shooter.combat_units[0].cargo.fire_arrow) == 0, "AR-07 stop after release preserves paid original flight"): return false
			if speed == 1.0 and not slow:
				if not _guards(f, after_stop): return false
			_step(f, 1.0, 0.5 if slow else STEP)
			if not _check(f.lab.ranged_shots == 1 and f.lab.ranged_resolutions == 1 and f.ignition.size() == 1, "TM-01 same action interval produces one paid finite contact"): return false
			if not _check(not f.lab.fire_save_guard().ok, "SV-09 cooled impact remains guarded before complete persistence"): return false
			evidence.append({"case": "action_clock", "speed": speed, "slow_frame": slow, "sample": sample, "result": _flight_result(f)})
			_close(f)
	return true

func _state_bytes(f: Fixture) -> PackedByteArray:
	var teams: Array = []
	for team: TerrainArmy in f.teams: teams.append(team.capture_combat_state())
	return var_to_bytes([f.data.site, f.data.flags, f.data.height_levels, teams, f.lab.fire_projectiles,
		f.lab.fire_reservations, f.lab.fire_impact_recorder, f.lab.fire_action_cursor, f.lab._fire_release_sequence])

func _guards(f: Fixture, flight_before: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var path := OUTPUT + "/pipeline_save_guard_sentinel.json"
	var sentinel := "original save must remain byte-identical".to_utf8_buffer()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null, "Save guard sentinel opens"): return false
	file.store_buffer(sentinel)
	file.close()
	var before := _state_bytes(f)
	var save := SiteStore.save(f.data, path)
	if not _check(not save.ok and str(save.code) == "BUSY" and FileAccess.get_file_as_bytes(path) == sentinel
		and before == _state_bytes(f), "SV-09 original SiteStore rejects before any bytes or live state mutate", save): return false
	var guard := f.controller.supply_save_guard()
	if not _check(not guard.ok and str(guard.code) == "BUSY" and before == _state_bytes(f), "SV-09 original Controller save/switch guard preserves people/items", guard): return false
	var replacement := TerrainData.new()
	replacement.allocate(Vector2i(8, 8))
	f.lab.bind_terrain(replacement)
	if not _check(f.lab.terrain == f.data and before == _state_bytes(f), "SV-09 actual bind_terrain rejects candidate before replacing original Site"): return false
	var crowd := Crowd.new()
	crowd.lab = f.lab
	var admitted := crowd.siege_admission_guard()
	crowd.free()
	if not _check(not admitted.ok and str(admitted.code) == "BUSY" and before == _state_bytes(f)
		and flight_before == var_to_bytes(f.lab.fire_projectiles), "AR-17/SV-09 original Crowd admission rejects new event without handoff or mutation", admitted): return false
	return true

func _normal_synchronous_guard() -> bool:
	var f := _fixture()
	var shooter := _team(f, [Vector2i(10, 10), Vector2i(10, 12)])
	var target := _team(f, [Vector2i(16, 12)], 2, 1)
	if failed: return false
	shooter.combat_units[1].cargo.arrow = 1
	var ordered := shooter.issue_combat_order(shooter.current_commander, TerrainArmy.CombatOrder.ATTACK)
	if not _check(ordered.ok and shooter.exchange_initiates(1, target.combat_identity(0))
		and not shooter.ranged_enabled and shooter.ranged_ammo_mode == "NORMAL", "Original automatic NORMAL authority without a typed order", ordered): return false
	var observed: Array[Dictionary] = []
	var callback := func(_seconds: float) -> void:
		observed.append({"committing": f.lab._fire_committing, "reservations": f.lab.fire_reservations.size(),
			"flights": f.lab.fire_projectiles.size(), "unsaved": f.lab._fire_unsaved,
			"typed": shooter.ranged_enabled, "mode": shooter.ranged_ammo_mode,
			"lab_guard": f.lab.fire_save_guard(), "store_guard": SiteStore.fire_event_guard(f.data)})
	shooter.combat_event.connect(callback)
	var reserved := f.lab.request_fire_release(_person(shooter, 1), {"type": "person", "person_id": target.combat_identity(0)})
	if not _check(reserved.ok, "Original automatic NORMAL reservation", reserved): return false
	f.lab._commit_fire_releases()
	shooter.combat_event.disconnect(callback)
	if not _check(observed.size() == 1, "Exactly one synchronous release callback", observed): return false
	var event: Dictionary = observed[0]
	if not _check(event.committing and event.reservations == 0 and event.flights == 0 and not event.unsaved
		and not event.typed and event.mode == "NORMAL", "Callback witnesses the exact unpublished NORMAL commit interval", event): return false
	if not _check(not event.lab_guard.ok and event.lab_guard.code == "BUSY"
		and not event.store_guard.ok and event.store_guard.code == "BUSY",
		"Lab and original Store synchronously reject save/handoff while release publication is incomplete", event): return false
	if not _check(shooter.combat_units[1].cargo.arrow == 0 and f.lab.fire_projectiles.size() == 1
		and f.lab.ranged_shots == 1, "Callback inspection neither duplicates nor interrupts the legal debit/publication"): return false
	evidence.append({"case": "normal_synchronous_commit_guard", "callback": event})
	_close(f)
	return true

func _run() -> void:
	for action: Callable in [_normal_synchronous_guard, _actor_paths, _static_and_moving, _intervening_people, _wall, _cancel_and_modes, _roster_windows, _capacity_and_fairness, _clock_and_guards]:
		if not action.call() or failed:
			_finish(false, str(action.get_method()))
			return
	_finish(true)
