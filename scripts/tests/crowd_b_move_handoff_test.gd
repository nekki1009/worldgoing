extends SceneTree
## B handoff's original Army/registry/coordinator contracts, without Crowd UI.
## The formal all-person clear, item identity, and save/redeploy tests are separate.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
var _checks := 0
var _owned: Array[Node] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> bool:
	_checks += 1
	if condition:
		print("PASS B helper: ", label)
		return true
	push_error("FAIL B helper: " + label)
	return false

func _run() -> void:
	var passed := _registry_admission() and _army_move() and _barrier()
	for node: Node in _owned:
		if is_instance_valid(node): node.free()
	print("CROWD B MOVE HANDOFF ", "PASS" if passed else "FAIL", " checks=", _checks)
	quit(0 if passed else 1)

func _registry_admission() -> bool:
	var registry := SiteDeploymentReservationRegistry.new()
	var foreign_cell := Vector2i(24, 12)
	var old_return := Vector2i(8, 8)
	if not _check(bool(registry.try_replace_reservations(9, -1, 45, [foreign_cell]).ok), "foreign lease fixture"): return false
	if not _check(bool(registry.try_replace_reservations(1, -1, 12, [old_return]).ok), "returning lease fixture"): return false
	var original_lease: Variant = registry.owner_of(foreign_cell)
	original_lease.member_id = 909
	original_lease.temporary_absence_remaining_sec = 3.25
	var baseline: Dictionary = registry.capture_handoff_state()
	var prepared: Dictionary = registry.prepare_handoff([1, 2])
	if not _check(bool(prepared.ok), "candidate prepared for complete returning set"): return false
	var candidate: SiteDeploymentReservationRegistry = prepared.candidate
	if not _check(not candidate.is_slot_reserved(old_return) and registry.is_slot_reserved(old_return), "candidate releases only its returning leases"): return false
	if not _check(not is_same(candidate.owner_of(foreign_cell), original_lease), "foreign candidate lease is isolated"): return false
	if not _check(bool(candidate.try_replace_reservations(1, -1, 13, [Vector2i(10, 8)]).ok), "first returning candidate admitted"): return false
	if not _check(not bool(candidate.try_replace_reservations(2, -1, 6, [foreign_cell]).ok), "last returning candidate conflict rejected"): return false
	if not _check(registry.capture_handoff_state() == baseline, "last-team failure leaves live leases indexes and token unchanged"): return false
	candidate.owner_of(foreign_cell).temporary_absence_remaining_sec = 0.0
	if not _check(original_lease.temporary_absence_remaining_sec == 3.25 and not bool(registry.publish_handoff(prepared).ok), "foreign candidate mutation cannot leak or publish"): return false
	prepared = registry.prepare_handoff([1, 2])
	candidate = prepared.candidate
	if not _check(bool(candidate.try_replace_reservations(1, -1, 13, [Vector2i(10, 8)]).ok) and bool(candidate.try_replace_reservations(2, -1, 6, [Vector2i(11, 8)]).ok), "complete candidate admitted"): return false
	var published: Dictionary = registry.publish_handoff(prepared)
	if not _check(bool(published.ok) and is_same(registry.owner_of(foreign_cell), original_lease), "publish preserves original foreign lease object"): return false
	if not _check(registry.owner_of(foreign_cell).order_serial == 45 and registry.owner_of(foreign_cell).member_id == 909 and registry.owner_of(foreign_cell).temporary_absence_remaining_sec == 3.25, "publish preserves foreign serial member and absence timer"): return false
	registry.restore_handoff_state(published.rollback)
	if not _check(registry.capture_handoff_state() == baseline and is_same(registry.owner_of(foreign_cell), original_lease), "rollback restores original lease references and token"): return false
	prepared = registry.prepare_handoff([1])
	registry.try_replace_reservations(7, -1, 1, [Vector2i(29, 20)])
	var changed: Dictionary = registry.capture_handoff_state()
	if not _check(str(registry.publish_handoff(prepared).get("reason", "")) == "STALE_RESERVATIONS" and registry.capture_handoff_state() == changed, "stale candidate cannot overwrite a live change"): return false
	return true

func _army_move() -> bool:
	var data: TerrainData = Helper.build_flat_map(40, 30)
	var army: TerrainArmy = Helper.create_test_army(data, 1, 0, 4, Vector2i(4, 8))
	_owned.append(army)
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var registry: SiteDeploymentReservationRegistry = coordinator.deployment_registry
	var foreign_cell := Vector2i(25, 12)
	if not _check(bool(registry.try_replace_reservations(9, -1, 71, [foreign_cell]).ok), "foreign MOVE lease exists before either original or handoff planning"): return false
	var foreign_lease: Variant = registry.owner_of(foreign_cell)
	army.tactical_ai_enabled = true
	if not _check(bool(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(25, 12)).ok) and not army.tactical_ai_enabled, "ordinary manual MOVE retains its AI-stop semantics"): return false
	army.tactical_ai_enabled = true
	army.tactical_ai_recovering = false
	army.tactical_ai_order_cooldown = 1.25
	army.tactical_ai_chase_cooldown = 2.5
	var live_before: Dictionary = army.capture_combat_state()
	var returning: Dictionary = live_before.duplicate(true)
	for key: String in ["combat_move_plan", "combat_deployment_plan", "combat_batches", "combat_absent_slots", "combat_batch_move_members", "combat_batch_retreat_members"]: returning.erase(key)
	for row: Dictionary in returning.units:
		row.cell = [int(row.cell[0]) + 3, int(row.cell[1]) + 3]
		row.slot = row.cell.duplicate()
		row.destination = [TerrainArmy.INVALID_CELL.x, TerrainArmy.INVALID_CELL.y]
		row.progress = 0.0
		row.duration = TerrainArmy.MOVE_DURATION
	returning["crowd_state"] = {"goal_facing": 0.0}
	var input_hash: String = JSON.stringify(returning).sha256_text()
	var geometry: Dictionary = TerrainArmy.prepare_handoff_geometry(returning, data, {})
	if not _check(bool(geometry.ok), "final Army cells produce consistent original commander geometry"): return false
	var snapshot: Dictionary = geometry.snapshot
	if not _check(snapshot.reference != live_before.reference and snapshot.current_commander == live_before.current_commander and snapshot.officers == live_before.officers and snapshot.rng == live_before.rng, "only command geometry changes while officers commander and RNG remain exact"): return false
	var live_registry: Dictionary = registry.capture_handoff_state()
	var reservations: Dictionary = registry.prepare_handoff([1])
	var candidate: SiteDeploymentReservationRegistry = reservations.candidate
	var blocked := {Vector2i(24, 12): true, Vector2i(26, 12): true}
	var planned: Dictionary = TerrainArmy.prepare_handoff_move(snapshot, data, {}, blocked, candidate)
	if not _check(bool(planned.ok), "unfinished MOVE prepares original destination and transit plans"): return false
	snapshot = planned.snapshot
	if not _check(snapshot.combat_order == TerrainArmy.CombatOrder.MOVE and snapshot.goal == returning.goal and snapshot.tactical_ai == returning.tactical_ai and snapshot.combat_order_serial == returning.combat_order_serial, "handoff preserves MOVE goal serial and AI timers"): return false
	if not _check(JSON.stringify(returning).sha256_text() == input_hash and army.capture_combat_state() == live_before and registry.capture_handoff_state() == live_registry, "geometry and MOVE preparation leave original source and live owners unchanged"): return false
	var destination: CombatDeploymentPlan = TerrainArmy._deserialize_deployment_plan(snapshot.combat_deployment_plan)
	var leases: Array = destination.member_slot_map.values()
	var legal := true
	for cell: Vector2i in leases:
		legal = legal and data.is_walkable(cell) and not blocked.has(cell) and cell != foreign_cell
	if not _check(legal and destination.member_slot_map.size() == 4, "all final MOVE slots avoid external cells and foreign leases: count=%d slots=%s" % [destination.member_slot_map.size(), str(leases)]): return false
	var admission: Dictionary = candidate.try_replace_reservations(1, -1, int(snapshot.combat_order_serial), leases)
	if not _check(bool(admission.ok), "prepared MOVE leases admitted to candidate"): return false
	var runtime_move: CombatMovePlan = planned.runtime_move
	var preflight: Dictionary = TerrainArmy.preflight_handoff_restore(snapshot, data, candidate, runtime_move)
	if not _check(bool(preflight.ok), "prepared snapshot passes original movement schema and ingress preflight"): return false
	var tampered: Dictionary = snapshot.duplicate(true)
	tampered.goal[0] = int(tampered.goal[0]) + 1
	if not _check(str(army.restore_handoff_state(tampered, data, null, null, preflight).get("code", "")) == "STALE_HANDOFF" and army.capture_combat_state() == live_before, "changed preflight snapshot is rejected before owner write"): return false
	var first_mid: int = int(snapshot.units[0].person_id)
	var first_rank: int = int(runtime_move.member_sequence_rank[first_mid])
	runtime_move.member_sequence_rank[first_mid] = first_rank + 7
	if not _check(str(army.restore_handoff_state(snapshot, data, null, null, preflight).get("code", "")) == "STALE_HANDOFF" and army.capture_combat_state() == live_before, "changed transient MOVE seed is rejected before owner write"): return false
	runtime_move.member_sequence_rank[first_mid] = first_rank
	var coordinator_before: Dictionary = coordinator.capture_handoff_state()
	if not _check(bool(army.restore_handoff_state(snapshot, data, null, null, preflight).ok), "checked original Army restore installs prepared MOVE"): return false
	if not _check(is_same(army.get_active_move_plan(), runtime_move) and runtime_move.member_sequence_rank.size() == 4 and runtime_move.pre_route_staging_slots.size() == 4 and runtime_move.member_path_s.size() == 4, "prepared BFS egress order staging and path seeds survive handoff"): return false
	if not _check(registry.capture_handoff_state() == live_registry and coordinator.capture_handoff_state() == coordinator_before, "Army install does not mutate live registry or coordinator"): return false
	if not _check(bool(registry.publish_handoff(reservations).ok) and is_same(registry.owner_of(foreign_cell), foreign_lease), "all leases publish after Army install with foreign identity intact"): return false
	army.get_active_deployment_plan().reservation_token = int(admission.token)
	coordinator.register_formation(army)
	if not _check(bool(coordinator.resolve_occupancy_rebuild_checked().ok), "checked occupancy barrier accepts restored cells"): return false
	if not _check(army._capture_tactical_ai_state() == snapshot.tactical_ai and army.combat_goal == Vector2i(25, 12), "ordinary owner has exact handed-off AI and MOVE goal"): return false
	var start_cells: Array[Vector2i] = army.cells.duplicate()
	var previous: Array[Vector2i] = army.cells.duplicate()
	var advanced := false
	var legal_steps := true
	for tick in range(240):
		coordinator.combat_logic_tick(0.05)
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
		var seen: Dictionary = {}
		for index in range(army.cells.size()):
			var cell: Vector2i = army.cells[index]
			legal_steps = legal_steps and not seen.has(cell) and (cell == previous[index] or data.can_step(previous[index], cell))
			seen[cell] = true
			previous[index] = cell
		advanced = advanced or army.cells != start_cells
		if army.combat_order == TerrainArmy.CombatOrder.HOLD: break
	if not _check(advanced and legal_steps, "restored unfinished MOVE physically resumes with unique legal steps"): return false
	coordinator.unregister_formation(army)
	return true

func _barrier() -> bool:
	var data: TerrainData = Helper.build_flat_map(30, 24)
	var first: TerrainArmy = Helper.create_test_army(data, 3, 0, 2, Vector2i(4, 6))
	var second: TerrainArmy = Helper.create_test_army(data, 4, 0, 2, Vector2i(18, 6))
	_owned.append_array([first, second])
	var coordinator := Coordinator.new()
	coordinator.register_formation(first)
	coordinator.register_formation(second)
	if not _check(bool(coordinator.resolve_occupancy_rebuild_checked().ok), "initial checked occupancy accepted"): return false
	var original: Vector2i = second.cells[0]
	second._cell_owners.erase(original)
	second.cells[0] = first.cells[0]
	second._cell_owners[second.cells[0]] = 0
	if not _check(second.get_active_members_occupancy().get(second.combat_identity(0)) == first.cells[0], "conflict fixture enters the original Army occupancy authority"): return false
	coordinator.request_occupancy_rebuild()
	var baseline: Dictionary = coordinator.capture_handoff_state()
	if not _check(str(coordinator.resolve_occupancy_rebuild_checked().get("reason", "")) == "CELL_CONFLICT" and coordinator.capture_handoff_state() == baseline, "last formation cell conflict leaves complete coordinator checkpoint untouched"): return false
	second._cell_owners.erase(second.cells[0])
	second.cells[0] = original
	second._cell_owners[original] = 0
	var retained_cell := Vector2i(25, 20)
	coordinator._retained_occupancy[retained_cell] = 900001
	coordinator._retained_occupancy[Vector2i(26, 20)] = first.combat_identity(0)
	if not _check(bool(coordinator.resolve_occupancy_rebuild_checked().ok) and coordinator._retained_occupancy.get(retained_cell) == 900001 and not coordinator._retained_occupancy.has(Vector2i(26, 20)), "barrier preserves foreign retained person and releases only rejoined person's stale cell"): return false
	var foreign_group: Array = [{"formation": second, "member_id": second.combat_identity(0)}]
	coordinator._inflight_batches.append(foreign_group)
	var checkpoint: Dictionary = coordinator.capture_handoff_state()
	if not _check(bool(coordinator.validate_handoff_formations([first]).ok), "pure foreign in-flight group allowed"): return false
	coordinator._inflight_batches.append([{"formation": first, "member_id": first.combat_identity(0)}, {"formation": second, "member_id": second.combat_identity(1)}])
	if not _check(str(coordinator.validate_handoff_formations([first]).get("reason", "")) == "RETURN_BATCH_CONFLICT", "mixed returning and foreign atomic group rejected"): return false
	coordinator.restore_handoff_state(checkpoint)
	if not _check(coordinator.capture_handoff_state() == checkpoint and is_same(coordinator._inflight_batches[0], foreign_group), "rollback preserves foreign in-flight group object and contents"): return false
	coordinator._inflight_batches.clear()
	coordinator.unregister_formation(first, Types.FormationUnregisterReason.LEAVE_SITE)
	coordinator.unregister_formation(second, Types.FormationUnregisterReason.LEAVE_SITE)
	return true
