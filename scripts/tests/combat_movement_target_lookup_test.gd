extends SceneTree
## Target lookup is local; claims, leases and terrain remain live for every intent.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Planner = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

var _army: TerrainArmy

func _initialize() -> void:
	call_deferred("_run")
	create_timer(45.0).timeout.connect(func() -> void:
		push_error("COMBAT MOVEMENT TARGET LOOKUP timed out")
		quit(1))

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error("COMBAT MOVEMENT TARGET LOOKUP: " + message)
		if is_instance_valid(_army): _army.free()
		quit(1)
	return ok

func _compare(mid: int, cell: Vector2i, kind: String) -> bool:
	var move := _army._combat_move_plan
	var plan := _army._combat_deployment_plan
	var context := _army._movement_target_context()
	var plain := Planner.resolve_member_target(move, plan, mid, cell)
	var cached := Planner.resolve_member_target(move, plan, mid, cell, context)
	var repeated := Planner.resolve_member_target(move, plan, mid, cell, context)
	return _require(plain == cached and cached == repeated and plain.kind == kind
		and context.targets.size() == 1 and is_same(cached, repeated),
		"Original and local target results must match for " + kind)

func _target_equivalence(first: int, second: int) -> bool:
	var move := _army._combat_move_plan
	var plan := _army._combat_deployment_plan
	var outside := Vector2i(1, 5)
	var inside := Vector2i(13, 5)
	if not _compare(first, outside, "transit"): return false
	if not _compare(first, plan.member_slot_map[first], "settled"): return false
	plan.admitted_platform_member_ids.append(first)
	plan.ever_admitted_platform_member_ids[first] = true
	if not _compare(first, inside, "platform") or not _compare(first, outside, "platform_return"): return false
	plan.admitted_platform_member_ids.clear()
	plan.ever_admitted_platform_member_ids.clear()
	move.member_entry_waypoint[first] = Vector2i(11, 5)
	if not _compare(first, outside, "entry_waypoint"): return false
	move.member_entry_waypoint.clear()
	move.member_crossed_swap_hold[first] = true
	if not _compare(first, outside, "crossed_swap_hold"): return false
	move.member_crossed_swap_hold.clear()
	move.member_vacancy_chain_target[first] = Vector2i(14, 5)
	if not _compare(first, outside, "vacancy_chain"): return false
	move.member_vacancy_chain_target.clear()
	move.member_recovery_hold[first] = true
	if not _compare(first, outside, "recovery_hold"): return false
	move.member_recovery_hold.clear()
	move.member_entry_hold[first] = true
	if not _compare(first, outside, "ingress_wait"): return false
	move.member_entry_hold.clear()
	plan.member_role_map[first] = Types.CombatDestinationRole.APPROACH_QUEUE
	if not _compare(first, outside, "queue"): return false
	move.member_queue_egress_waypoint[first] = Vector2i(10, 4)
	if not _compare(first, outside, "queue_egress"): return false
	move.member_queue_egress_waypoint.clear()
	plan.member_role_map[first] = Types.CombatDestinationRole.PLATFORM
	if not _compare(999999, outside, "invalid"): return false
	var context := _army._movement_target_context()
	var old := Planner.resolve_member_target(move, plan, first, outside, context)
	Planner.resolve_member_target(move, plan, first, inside, context)
	Planner.resolve_member_target(move, plan, second, outside, context)
	if not _require(context.targets.size() == 2 and context.targets[first].size() == 2,
		"Member identity and physical cell must both key the local result"): return false
	var wide_identity: int = first + 4294967296
	plan.member_slot_map[wide_identity] = Vector2i(18, 5)
	move.member_transit_slots[wide_identity] = Vector2i(8, 5)
	var wide := Planner.resolve_member_target(move, plan, wide_identity, outside, context)
	if not _require(wide == Planner.resolve_member_target(move, plan, wide_identity, outside)
		and wide.target != old.target and context.targets.size() == 3,
		"Full-width member IDs cannot collide in a narrowed vector key"): return false
	plan.member_slot_map.erase(wide_identity)
	move.member_transit_slots.erase(wide_identity)
	# A new invocation observes all changed original inputs; context never lives on Army.
	move.member_transit_slots[first] = Vector2i(9, 5)
	move.note_assignment_change(first)
	var fresh := _army._movement_target_context()
	var new_target := Planner.resolve_member_target(move, plan, first, outside, fresh)
	if not _require(new_target == Planner.resolve_member_target(move, plan, first, outside)
		and new_target.target != old.target and new_target.assignment_epoch > old.assignment_epoch,
		"Next local phase must see the new target and assignment epoch"): return false
	plan.ever_admitted_platform_member_ids[first] = true
	plan.platform_footprint.erase(inside)
	if not _compare(first, inside, "platform_return"): return false
	plan.platform_footprint.append(inside)
	plan.ever_admitted_platform_member_ids.clear()
	return true

func _live_intents(first: int, second: int, coordinator: SiteCombatMovementCoordinator) -> bool:
	var grid := coordinator.movement_reservation_grid
	var data := _army.data
	var start: Vector2i = _army.cells[0]
	var next: Vector2i = _army.cells[1]
	grid.begin_tick({start: first, next: second}, data)
	_army.combat_profile_enabled = true
	_army.begin_combat_movement_read_scope()
	var context := _army._movement_target_context()
	var plain := _army._transit_field_intent(first, 0, grid)
	var cached := _army._transit_field_intent(first, 0, grid, context)
	if not _require(plain == cached and cached.get("step") == next and context.targets.size() == 2,
		"Same-direction occupied neighbor must keep the original dependency intent"): return false
	if not _require(int(_army.profiled_scheduler_metrics.get("field_static_hits", 0)) > 0,
		"An unchanged source must reuse static candidates inside one movement call"): return false
	grid.blocked_destinations[next] = true
	cached = _army._transit_field_intent(first, 0, grid, context)
	if not _require(cached == _army._transit_field_intent(first, 0, grid)
		and bool(cached.get("handled", false)) and cached.get("step") == TerrainArmy.INVALID_CELL,
		"New Grid claim must change the live intent despite reused pure targets"): return false
	grid.blocked_destinations.clear()
	var lease: Dictionary = coordinator.deployment_registry.try_replace_reservations(99, -1, 1, [next])
	if not _require(bool(lease.ok), "Fixture foreign lease"): return false
	cached = _army._transit_field_intent(first, 0, grid, context)
	if not _require(cached == _army._transit_field_intent(first, 0, grid) and cached.is_empty(), "Foreign lease stays live"): return false
	coordinator.deployment_registry.release_order(99)
	_army.external_blocker = func(cell: Vector2i) -> bool: return cell == next
	cached = _army._transit_field_intent(first, 0, grid, context)
	if not _require(cached == _army._transit_field_intent(first, 0, grid) and cached.is_empty(), "External person stays live"): return false
	_army.external_blocker = Callable()
	data.navigation_revision += 1
	if not _require(_army._transit_field_intent(first, 0, grid, context).is_empty(), "Stale terrain revision cannot reuse an intent"): return false
	data.navigation_revision -= 1
	var expected: Dictionary = {}
	for index in range(2):
		var mid := _army.combat_identity(index)
		expected[mid] = _army._transit_field_intent(mid, index, grid).get("step", TerrainArmy.INVALID_CELL)
	_army.propose_combat_moves(grid)
	if not _require(grid.get_proposals().size() == 2, "Original proposal owner must submit both dependency members"): return false
	for proposal in grid.get_proposals():
		if not _require(proposal.to_cell == expected[proposal.member_id], "Locally reused targets must preserve exact original proposal edges"): return false
	_army.end_combat_movement_read_scope()
	_army.combat_profile_enabled = false
	return true

func _member_read_scope(first: int, second: int) -> bool:
	_army.combat_profile_enabled = true
	var scans_before: int = int(_army.profiled_scheduler_metrics.get("roster_full_scans", 0))
	var hits_before: int = int(_army.profiled_scheduler_metrics.get("roster_scope_hits", 0))
	_army.begin_combat_movement_read_scope()
	var original := _army._get_active_member_ids()
	if not _require(original == [first, second], "Read scope must retain the original active-member rule"): return false
	var independently_sorted := _army._get_active_member_ids()
	independently_sorted.reverse()
	if not _require(_army._get_active_member_ids() == original,
		"A caller sorting its returned array must not reorder the shared result"): return false
	if not _require(int(_army.profiled_scheduler_metrics.get("roster_full_scans", 0)) == scans_before + 1
		and int(_army.profiled_scheduler_metrics.get("roster_scope_hits", 0)) == hits_before + 2,
		"An unchanged movement scope scans once and reuses subsequent reads"): return false
	_army.combat_hot_set(1, &"pose", "get_up")
	if not _require(_army._get_active_member_ids() == [first],
		"A qualifying hot-field change must invalidate the current scope"): return false
	_army.combat_hot_set(1, &"pose", "idle")
	if not _require(_army._get_active_member_ids() == original,
		"The member must return when the original qualifying state returns"): return false
	_army.end_combat_movement_read_scope()
	_army.combat_hot_set(1, &"ko", 1.0)
	if not _require(_army._get_active_member_ids() == [first],
		"A later action must not reuse the previous scope"): return false
	_army.combat_hot_set(1, &"ko", 0.0)
	var result := _require(_army._get_active_member_ids() == original,
		"Leaving the read scope preserves ordinary live lookup")
	_army.combat_profile_enabled = false
	return result

func _run() -> void:
	var data := Helper.build_flat_map(24, 20)
	_army = Helper.create_test_army(data, 1, 0, 2, Vector2i(1, 5))
	var coordinator := SiteCombatMovementCoordinator.new()
	_army.set_coordinator(coordinator)
	_army.combat_order = TerrainArmy.CombatOrder.MOVE
	_army._order_delay = 0.0
	_army._formation_movement_profile = FormationMovementProfile.new()
	var move := CombatMovePlan.new()
	move.order_serial = 1
	move.terrain_revision = data.navigation_revision
	move.phase = Types.CombatMovePhase.TRANSIT
	for x in range(1, 17): move.macro_path.append(Vector2i(x, 5))
	var plan := CombatDeploymentPlan.new()
	plan.order_serial = 1
	plan.resolved_anchor = Vector2i(14, 5)
	plan.ingress_cell = Vector2i(12, 5)
	for y in range(3, 8):
		for x in range(12, 19): plan.platform_footprint.append(Vector2i(x, y))
	for index in range(2):
		var mid := _army.combat_identity(index)
		var final_slot := Vector2i(14 + index, 5)
		plan.member_slot_map[mid] = final_slot
		plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		plan.platform_slots.append(final_slot)
		plan.slot_owner_map[final_slot] = mid
		move.member_transit_slots[mid] = Vector2i(10 + index, 5)
		move.member_path_s[mid] = 9.0 + index
		move.member_sequence_rank[mid] = index
		_army.combat_slots[index] = move.member_transit_slots[mid]
	move.destination_plan = plan
	_army._combat_move_plan = move
	_army._combat_deployment_plan = plan
	var first := _army.combat_identity(0)
	var second := _army.combat_identity(1)
	if not _member_read_scope(first, second): return
	if not _target_equivalence(first, second): return
	if not _live_intents(first, second, coordinator): return
	_army.free()
	print("COMBAT MOVEMENT TARGET LOOKUP PASS: target branches, identity/cell/epoch, fresh footprint, live Grid/leases/people/terrain and exact proposal edges")
	quit(0)
