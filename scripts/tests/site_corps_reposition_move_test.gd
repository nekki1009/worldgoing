extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/corps-reposition-move.json"
const STEP := 0.05

var _teams: Array[TerrainArmy] = []
var _coordinators: Array[SiteCombatMovementCoordinator] = []
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		push_error("CORPS REPOSITION MOVE: " + message)
	return condition

func _run() -> void:
	create_timer(45.0).timeout.connect(func() -> void: push_error("CORPS REPOSITION MOVE timed out"); quit(1))
	var passed := _move_and_resume() and _no_route()
	for coordinator: SiteCombatMovementCoordinator in _coordinators:
		for team in coordinator.get_active_formations():
			coordinator.unregister_formation(team)
	for team: TerrainArmy in _teams:
		team.free()
	if passed:
		print("SITE CORPS REPOSITION MOVE PASS: %d checks; direct original authority, MOVE takeover, committed edge, SiteStore resume/arrival, no-route remains non-routed" % _checks)
	quit(0 if passed else 1)

func _team(data: TerrainData, coordinator: SiteCombatMovementCoordinator, identity: int, origin: Vector2i) -> TerrainArmy:
	var team := Helper.create_test_army(data, identity, 0, 3, origin)
	coordinator.register_formation(team)
	_teams.append(team)
	return team

func _advance(coordinator: SiteCombatMovementCoordinator) -> bool:
	var previous := {}
	for team: TerrainArmy in coordinator.get_active_formations():
		previous[team.team_id] = team.cells.duplicate()
	coordinator.combat_logic_tick(STEP)
	for team: TerrainArmy in coordinator.get_active_formations():
		team.prepare_combat(STEP)
	coordinator.complete_committed_moves()
	var occupied := {}
	var destinations := {}
	for team: TerrainArmy in coordinator.get_active_formations():
		for index in range(team.combat_units.size()):
			var cell: Vector2i = team.cells[index]
			if not _check(team.data.is_walkable(cell) and not occupied.has(cell), "Original movement produced an illegal or overlapping cell"): return false
			occupied[cell] = true
			if cell != previous[team.team_id][index] and not _check(team.data.can_step(previous[team.team_id][index], cell), "Original movement teleported instead of completing a legal edge"): return false
			var destination: Vector2i = team.moving_to[index]
			if destination != TerrainArmy.INVALID_CELL:
				if not _check(team.data.can_step(cell, destination) and not destinations.has(destination), "Original movement produced conflicting or illegal destination claims"): return false
				destinations[destination] = true
	return true

func _room(data: TerrainData) -> Vector2i:
	for y in range(2, data.size.y - 9):
		for x in range(2, data.size.x - 23):
			var legal := true
			for dy in range(8):
				for dx in range(22):
					if not data.is_walkable(Vector2i(x + dx, y + dy)):
						legal = false
						break
				if not legal: break
			if legal: return Vector2i(x, y)
	return TerrainArmy.INVALID_CELL

func _move_and_resume() -> bool:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581, {"size": Vector2i(80, 65)})
	SiteEnvironment.initialize(data, "corps-reposition-fixture")
	for index in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	SiteRuntime.rebuild_terrain_edges(data)
	var room := _room(data)
	if not _check(room != TerrainArmy.INVALID_CELL, "No persistent legal fixture room"): return false
	var coordinator := Coordinator.new()
	_coordinators.append(coordinator)
	var source := _team(data, coordinator, 1, room + Vector2i(1, 1))
	var target := _team(data, coordinator, 2, room + Vector2i(5, 3))
	var commander := source.combat_identity(0)
	data.site.corps = {"first": {"version": 1, "commander_person_id": commander, "team_ids": [1, 2]}}
	var sustain := SiteSustain.create()
	var sustain_before := sustain.duplicate(true)
	target.sustain_routed_query = func(_team_value: TerrainArmy) -> bool: return bool(sustain.routed)
	var order := target.issue_combat_order(target.current_commander, TerrainArmy.CombatOrder.MOVE, room + Vector2i(14, 3), -1, Vector2i.RIGHT)
	if not _check(order.ok, "Initial captain MOVE failed: " + str(order)): return false
	if not _check(target.set_tactical_ai_enabled(target.current_commander, true).ok, "Cannot enable original AI before authority rejection"): return false
	var inflight := -1
	for tick in range(400):
		if not _advance(coordinator): return false
		for index in range(target.combat_units.size()):
			if target.moving_to[index] != TerrainArmy.INVALID_CELL and target.move_progress[index] > 0.0 and target.move_progress[index] < 1.0:
				inflight = index
				break
		if inflight >= 0: break
	if not _check(inflight >= 0, "No real in-flight original MOVE within twenty simulated seconds"): return false
	var before := target.capture_combat_state()
	var batches: Array = coordinator.get_inflight_batches_for_formation(target).duplicate(true)
	var goal := room + Vector2i(18, 4)
	for impostor: int in [target.combat_identity(target.current_commander), source.combat_identity(1)]:
		var refused := target.issue_corps_reposition(impostor, goal, Vector2i.RIGHT)
		if not _check(refused.code == "NO_AUTHORITY" and target.capture_combat_state() == before and coordinator.get_inflight_batches_for_formation(target) == batches, "Same-faction captain/bystander changed order, AI, or committed step: " + str(refused)): return false
	if not _check(not target.combat_target_query.is_valid(), "Fixture must exercise original Coordinator identity lookup, not a Lab callback"): return false
	var cells: Array[Vector2i] = target.cells.duplicate()
	var moving: Array[Vector2i] = target.moving_to.duplicate()
	var progress := target.move_progress.duplicate()
	var serial := target.get_order_serial()
	order = target.issue_corps_reposition(commander, goal, Vector2i.RIGHT)
	if not _check(order.ok and order.corps_id == "first", "Real corps reposition failed: " + str(order)): return false
	if not _check(target.combat_order == TerrainArmy.CombatOrder.MOVE and target.get_active_move_plan() != null and target.get_active_deployment_plan() != null and target.get_order_serial() == serial + 1 and not target.tactical_ai_enabled, "Accepted reposition must use original MOVE and manual takeover"): return false
	if not _check(target.cells == cells and target.moving_to == moving and target.move_progress == progress and coordinator.get_inflight_batches_for_formation(target) == batches, "Reposition must preserve the already committed physical edge and barrier"): return false
	var expected_source := {"version": 1, "corps_id": "first", "commander_person_id": commander, "team_id": target.team_id}
	var snapshot := target.capture_combat_state()
	if not _check(snapshot.get("corps_reposition_source", {}) == expected_source and not snapshot.has("retreat_resolution") and sustain == sustain_before, "Ordered MOVE must save the real issuer without modifying morale or starting retreat"): return false
	data.site.actors = {}
	data.site.armies = [source.capture_combat_state(), snapshot]
	var saved := Store.save(data, SAVE)
	if not _check(saved.ok, "Original SiteStore rejected the accepted in-flight corps MOVE: " + str(saved)): return false
	var loaded := Store.load_site(SAVE)
	if not _check(loaded.ok, "Original SiteStore rejected reload: " + str(loaded)): return false
	var restored_coordinator := Coordinator.new()
	_coordinators.append(restored_coordinator)
	var restored: TerrainArmy
	for team_snapshot: Dictionary in loaded.data.site.armies:
		var copy := TerrainArmy.new()
		# Production armies live in the scene tree; fixtures step them explicitly.
		root.add_child(copy)
		copy.set_process(false)
		copy.roster_size = team_snapshot.units.size()
		copy.exchange_enabled = true
		restored_coordinator.register_formation(copy)
		copy.restore_combat_state(team_snapshot, loaded.data, null, null)
		_teams.append(copy)
		if copy.team_id == target.team_id: restored = copy
	if not _check(restored != null, "Restore lost the target original team"): return false
	var restored_source: Dictionary = restored.capture_combat_state().get("corps_reposition_source", {})
	if not _check(restored_source == expected_source, "Restore changed the original issuer: actual=%s expected=%s commander_type=%s" % [restored_source, expected_source, typeof(restored_source.get("commander_person_id"))]): return false
	if not _check(restored.cells == cells and restored.moving_to == moving, "Restore changed original source/destination cells: actual=%s / %s expected=%s / %s" % [restored.cells, restored.moving_to, cells, moving]): return false
	for index in range(progress.size()):
		if not _check(absf(restored.move_progress[index] - progress[index]) < 0.000000000000001, "Restore changed committed interpolation progress"): return false
	if not _check(restored_coordinator.get_inflight_batches_for_formation(restored).size() == batches.size(), "Restore lost the original committed-step barrier"): return false
	var plan := restored.get_active_deployment_plan()
	var completed_original_edge := false
	for tick in range(1200):
		if not _advance(restored_coordinator): return false
		if restored.cells[inflight] == moving[inflight]: completed_original_edge = true
		if restored.combat_order == TerrainArmy.CombatOrder.HOLD: break
	if not _check(completed_original_edge, "Restored MOVE skipped its original committed edge"): return false
	if not _check(restored.combat_order == TerrainArmy.CombatOrder.HOLD and restored.command_status.begins_with("已抵達") and Destination.is_settled(plan, restored.get_active_members_occupancy()), "Restored corps MOVE did not physically reach its final slots within sixty simulated seconds: " + restored.command_status): return false
	if not _check(restored._corps_reposition_source.is_empty() and restored._retreat_resolution.is_empty() and sustain == sustain_before, "Arrival must clear completed order provenance without becoming a rout"): return false
	for index in range(restored.combat_units.size()):
		if not _check(not bool(restored.combat_hot_get(index, &"site_exited", false)) and not bool(restored.combat_hot_get(index, &"surrender_pending", false)), "In-Site MOVE cannot exit or surrender a person"): return false
	return true

func _no_route() -> bool:
	var data := Helper.build_flat_map(24, 20)
	for y in range(data.size.y):
		data.flags[data.index(Vector2i(12, y))] = 0
		data.static_blocked[data.index(Vector2i(12, y))] = 1
	var coordinator := Coordinator.new()
	_coordinators.append(coordinator)
	var source := _team(data, coordinator, 1, Vector2i(2, 2))
	var target := _team(data, coordinator, 2, Vector2i(3, 8))
	var commander := source.combat_identity(0)
	data.site.corps = {"first": {"version": 1, "commander_person_id": commander, "team_ids": [1, 2]}}
	var sustain := SiteSustain.create()
	var sustain_before := sustain.duplicate(true)
	target.sustain_routed_query = func(_team_value: TerrainArmy) -> bool: return bool(sustain.routed)
	if not _check(target.set_tactical_ai_enabled(target.current_commander, true).ok, "Cannot enable no-route fixture AI"): return false
	var before := target.capture_combat_state()
	var result := target.issue_corps_reposition(commander, Vector2i(19, 8), Vector2i.RIGHT)
	if not _check(not result.ok and result.code == "BLOCKED", "Unreachable in-Site goal must fail original MOVE preflight: " + str(result)): return false
	if not _check(target.capture_combat_state() == before and target._retreat_resolution.is_empty() and sustain == sustain_before and not target.is_sustain_routed(), "No-route reposition changed the original order/AI or invented a morale collapse"): return false
	for index in range(target.combat_units.size()):
		if not _check(not bool(target.combat_hot_get(index, &"surrender_pending", false)) and not bool(target.combat_hot_get(index, &"site_exited", false)), "No-route reposition cannot surrender or exit original people"): return false
	return true
