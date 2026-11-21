extends SceneTree
## OUTPUT CANDIDATE: original GD Army/Registry/Grid work approach, not P3 phase proof.
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const STEP := 1.0 / 30.0
var checks := 0
var finished := false
var fixtures: Array[Dictionary] = []

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void: _finish(false, "internal deadline"))
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = null) -> bool:
	checks += 1
	if not ok: push_error("SUPPRESS_NAV_FAIL: " + label + " " + str(detail))
	return ok

func _fixture() -> Dictionary:
	var data := Helper.build_flat_map(24, 20)
	# A different runtime formation ID catches confusing Grid and Registry IDs.
	var army := Helper.create_test_army(data, 7, 0, 2, Vector2i(5, 5))
	var coordinator := SiteCombatMovementCoordinator.new()
	coordinator.register_formation(army)
	var result := {"data": data, "army": army, "coordinator": coordinator, "member": army.combat_identity(1), "token": 31}
	fixtures.append(result)
	return result

func _close(f: Dictionary) -> void:
	if not is_instance_valid(f.army): return
	f.coordinator.unregister_formation(f.army)
	f.army.clear()
	f.army.free()
	fixtures.erase(f)

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Dictionary in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_SUPPRESS_NAVIGATION_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _tick(f: Dictionary, seconds: float = STEP) -> void:
	f.coordinator.combat_logic_tick_if_needed(seconds)
	f.army.prepare_combat(seconds, seconds)
	f.coordinator.complete_committed_moves()

func _begin(f: Dictionary, target: Vector2i) -> Dictionary:
	return f.army.begin_suppress_approach(f.member, f.token, target, f.army.get_order_serial())

func _registry() -> bool:
	var registry := SiteDeploymentReservationRegistry.new()
	if not _check(registry.try_replace_reservations(7, 0, 9, [Vector2i(3, 3)]).ok, "Original same-team lease created"): return false
	if not _check(registry.try_replace_reservations(8, 0, 2, [Vector2i(9, 9)]).ok, "Original foreign lease created"): return false
	var retained: Variant = registry.owner_of(Vector2i(3, 3))
	var foreign: Variant = registry.owner_of(Vector2i(9, 9))
	var work := registry.reserve_work_slot(7, 9, 701, Vector2i(4, 3))
	if not _check(work.ok and is_same(retained, registry.owner_of(Vector2i(3, 3))) and is_same(foreign, registry.owner_of(Vector2i(9, 9))), "Additive work lease preserves all old objects"): return false
	var before := registry.capture_handoff_state()
	if not _check(not registry.reserve_work_slot(7, 10, 702, Vector2i(5, 3)).ok and registry.capture_handoff_state() == before, "Stale serial cannot add a conflicting epoch"): return false
	if not _check(not registry.reserve_work_slot(7, 9, 703, Vector2i(9, 9)).ok and registry.capture_handoff_state() == before, "Foreign conflict changes nothing"): return false
	if not _check(registry.release_work_slot(work.lease).released and is_same(retained, registry.owner_of(Vector2i(3, 3))), "Release affects exact work lease only"): return false
	var replacement := registry.reserve_work_slot(8, 2, 801, Vector2i(4, 3))
	if not _check(replacement.ok and not registry.release_work_slot(work.lease).ok and is_same(replacement.lease, registry.owner_of(Vector2i(4, 3))), "Old job cannot erase new owner at reused slot"): return false
	return true

func _arrival() -> bool:
	var f := _fixture()
	var army: TerrainArmy = f.army
	var source := army.cells[1]
	var target := source + Vector2i(2, 0)
	var serial := army.get_order_serial()
	var ranged_serial := army.ranged_order_serial
	var admitted := _begin(f, target)
	if not _check(admitted.ok and admitted.phase == "APPROACHING", "Original idle member admits one real approach", admitted): return false
	var frozen: Dictionary = f.coordinator.deployment_registry.capture_handoff_state()
	army._prepare_suppress_approach(SiteRouteBudget.new())
	if not _check(army.suppress_approach_query(f.member, f.token).route_status == "SCHEDULER_DEFERRED" and army.cells[1] == source and army.moving_to[1] == TerrainArmy.INVALID_CELL and f.coordinator.deployment_registry.capture_handoff_state() == frozen, "No allocation is deferred without motion or lease changes"): return false
	_tick(f)
	if not _check(army.cells[1] == source and army.moving_to[1] == source + Vector2i.RIGHT and army.is_suppress_committed_move(f.member) and army._cell_owners.get(source) == 1 and army._reserved_cells.get(source + Vector2i.RIGHT) == 1 and not f.coordinator.get_inflight_batches_for_formation(army).is_empty(), "Original Grid commit retains source and destination claim"): return false
	if not _check(f.coordinator.route_budget.site_calls_used == 1 and f.coordinator.route_budget.site_expansions_used > 0 and f.coordinator.route_budget.site_expansions_used <= SiteRouteBudget.LOCAL_ROUTE_MAX_EXPANSIONS, "Actual work search charged once to original budget"): return false
	for tick in range(60):
		_tick(f)
		if army.suppress_approach_query(f.member, f.token).phase == "ARRIVED": break
	var query := army.suppress_approach_query(f.member, f.token)
	if not _check(query.ok and query.phase == "ARRIVED" and army.cells[1] == target and army.combat_ground(1) == (Vector2(target) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS and army.moving_to[1] == TerrainArmy.INVALID_CELL and army._reserved_cells.is_empty() and army.combat_order == TerrainArmy.CombatOrder.HOLD and army.get_order_serial() == serial and army.ranged_order_serial == ranged_serial, "ARRIVED is original cell center with unchanged main command and both serials", query): return false
	if not _check(army.release_suppress_approach(f.member, f.token).done and f.coordinator.deployment_registry.owner_of(target) == null and army.cells[1] == target, "Arrival release preserves actual occupancy"): return false
	_close(f)
	return true

func _cancel_or_hurt(kind: String) -> bool:
	var f := _fixture()
	var army: TerrainArmy = f.army
	var source := army.cells[1]
	var target := source + Vector2i(2, 0)
	var admitted := _begin(f, target)
	if not _check(admitted.ok, "Real work accepted before interruption", kind): return false
	_tick(f)
	var endpoint := army.moving_to[1]
	if not _check(endpoint != TerrainArmy.INVALID_CELL and army.move_progress[1] > 0.0 and army.move_progress[1] < 1.0, "Interruption occurs in real physical half-step", kind): return false
	if kind in ["ko", "death"]:
		army.apply_unit_contact(1, {"environmental": true, "shield": false, "result": {
			"hp": float(army.combat_hot_get(1, &"hp")) + 1.0 if kind == "death" else 0.0,
			"stun": SiteCombatRules.STUN_LIMIT if kind == "ko" else 0.0, "guard_break": false}})
		if not _check(not army.combat_can_act(1), "Original contact owner performs KO/death", kind): return false
	var release := army.release_suppress_approach(f.member, f.token)
	if not _check(release.phase == "SETTLING" and not release.done and army.cells[1] == source and army.moving_to[1] == endpoint and army._cell_owners.get(source) == 1 and army._reserved_cells.get(endpoint) == 1 and f.coordinator.deployment_registry.owner_of(target) == null, "Cancellation releases only lease; original half-step keeps both claims", release): return false
	for tick in range(20): _tick(f)
	if not _check(army.cells[1] == endpoint and army.moving_to[1] == TerrainArmy.INVALID_CELL and army._reserved_cells.is_empty() and army.suppress_approach_query(f.member, f.token).done and f.coordinator.get_inflight_batches_for_formation(army).is_empty(), "Original barrier finishes once at endpoint after interruption", kind): return false
	if not _check(army._cell_owners.has(endpoint) == (kind == "cancel"), "KO/death release occupancy only at original endpoint", kind): return false
	_close(f)
	return true

func _new_move() -> bool:
	var f := _fixture()
	var army: TerrainArmy = f.army
	var source := army.cells[1]
	var target := source + Vector2i(2, 0)
	var admitted := _begin(f, target)
	if not _check(admitted.ok, "Work admitted before new command"): return false
	_tick(f)
	var endpoint := army.moving_to[1]
	var serial := army.get_order_serial()
	var ranged_serial := army.ranged_order_serial
	var rejected := army.issue_combat_order(-999, TerrainArmy.CombatOrder.MOVE, Vector2i(10, 8))
	if not _check(not rejected.ok and army.get_order_serial() == serial and army.ranged_order_serial == ranged_serial and is_same(admitted.lease, f.coordinator.deployment_registry.owner_of(target)) and army.suppress_approach_query(f.member, f.token).ok, "Rejected manual command preserves exact active work and lease"): return false
	var accepted := army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(10, 8))
	if not _check(accepted.ok and army.get_order_serial() > serial and army.ranged_order_serial > ranged_serial, "Original accepted MOVE replaces work through original registry transaction", accepted): return false
	var plan := army.get_active_move_plan()
	var snapshot := {"paths": plan.member_paths.duplicate(true), "to": plan.member_pending_to_cell.duplicate(true), "from": plan.member_pending_from_cell.duplicate(true), "ids": plan.member_pending_proposal_id.duplicate(true), "slots": army.get_active_deployment_plan().member_slot_map.duplicate(true)}
	var release := army.release_suppress_approach(f.member, f.token)
	if not _check(release.phase == "SETTLING", "Old work remains physical while new MOVE is current"): return false
	# Advance only the original body and completion barrier: no next planner tick
	# may legitimately update the new plan while this assertion takes its snapshot.
	for tick in range(20):
		army.prepare_combat(STEP, STEP)
		f.coordinator.complete_committed_moves()
	if not _check(army.cells[1] == endpoint and army.combat_order == TerrainArmy.CombatOrder.MOVE and is_same(plan, army.get_active_move_plan()) and snapshot.paths == plan.member_paths and snapshot.to == plan.member_pending_to_cell and snapshot.from == plan.member_pending_from_cell and snapshot.ids == plan.member_pending_proposal_id and snapshot.slots == army.get_active_deployment_plan().member_slot_map and not army._move_landed_members.has(f.member), "Old work completion cannot pop or invalidate new MOVE state"): return false
	_close(f)
	return true

func _policy() -> bool:
	var f := _fixture()
	var army: TerrainArmy = f.army
	var nav_revision: int = int(f.data.navigation_revision)
	var blockers: PackedByteArray = f.data.static_blocked.duplicate()
	var native_before := army.native_local_route_enabled
	var expensive := Vector2i(11, 10)
	var policy := func(_from: Vector2i, to: Vector2i) -> int: return 30 if to == expensive else 0
	var status := {}
	var route := army._find_local_route(Vector2i(10, 10), Vector2i(12, 10), 256, false, -1, 0, false, null, false, status, policy)
	if not _check(route.size() == 5 and not route.has(expensive) and status.outcome == "success" and f.data.navigation_revision == nav_revision and f.data.static_blocked == blockers and army.native_local_route_enabled == native_before, "Same original A* chooses finite cheaper detour without changing terrain or global native mode", route): return false
	var capped := {}
	var capped_route := army._find_local_route(Vector2i(10, 10), Vector2i(11, 10), 1, false, -1, 0, false, null, false, capped, func(_from: Vector2i, _to: Vector2i) -> int: return 0)
	if not _check(capped_route.is_empty() and capped.capped and capped.outcome == "capped", "Discovered but unexpanded weighted goal stays deferred at cap", capped): return false
	_close(f)
	return true

func _run() -> void:
	if not _registry() or not _arrival(): _finish(false); return
	for kind: String in ["cancel", "ko", "death"]:
		if not _cancel_or_hurt(kind): _finish(false, kind); return
	if not _new_move() or not _policy(): _finish(false); return
	_finish(true)
