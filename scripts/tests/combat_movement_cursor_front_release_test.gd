extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	var terrain := Helper.build_flat_map(150, 15)
	var army := Helper.create_test_army(terrain, 1, 0, 4, Vector2i(5, 5))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	if not _require(bool(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(140, 5)).get("ok", false)), "Long flat MOVE must start"): return
	army._order_delay = 0.0
	var plan = army.get_active_move_plan()
	if not _require(plan.macro_path.size() > 125, "Fixture needs a long enough verified centerline"): return
	plan.current_width = 4
	plan.pending_width = 4
	plan.width_confirm_counter = 0
	var current_k := 10
	plan.macro_cursor = current_k
	var front: Array[int] = [14, 14, 12, 10]
	if not _require(army._can_release_saturated_front(current_k, current_k + 1, 4, 3, front), "Two saturated leaders and quorum-minus-one must release one verified cursor step"): return
	if not _require(not army._can_release_saturated_front(current_k, current_k + 2, 4, 3, front), "Fallback must never skip a cursor step"): return
	var one_saturated: Array[int] = [14, 13, 12, 10]
	if not _require(not army._can_release_saturated_front(current_k, current_k + 1, 4, 3, one_saturated), "One saturated leader cannot release the front"): return
	if not _require(not army._can_release_saturated_front(current_k, current_k + 1, 4, 2, front) and not army._can_release_saturated_front(current_k, current_k + 1, 2, 1, front), "Missing two soldiers or a two-person quorum cannot be relaxed"): return
	var single_width_checks := 0
	var one_lane_front: Array[int] = [14, 10, 9, 8]
	var one_lane_target: Vector2i = plan.macro_path[current_k + 1]
	var one_lane_saturated: Vector2i = plan.macro_path[current_k + 4]
	for cell: Vector2i in [one_lane_target, one_lane_saturated]:
		for side: Vector2i in [Vector2i.UP, Vector2i.DOWN]:
			terrain.static_blocked[terrain.index(cell + side)] = 1
	if not _require(not army._can_release_saturated_front(current_k, current_k + 1, 2, 1, one_lane_front, 1), "Projected front alone cannot release a one-cell row"): return
	single_width_checks += 1
	var front_index := 1
	var front_mid: int = army.combat_identity(front_index)
	var original_cell: Vector2i = army.cells[front_index]
	army._cell_owners.erase(original_cell)
	army.cells[front_index] = one_lane_saturated
	army._cell_owners[one_lane_saturated] = front_index
	plan.member_projected_path_k[front_mid] = current_k + 4
	if not _require(army._can_release_saturated_front(current_k, current_k + 1, 2, 1, one_lane_front, 1), "One actual leader at the verified single-cell soft row may release only one cursor step"): return
	single_width_checks += 1
	if not _require(not army._can_release_saturated_front(current_k, current_k + 2, 2, 1, one_lane_front, 1), "Single-cell release may not skip a cursor step"): return
	single_width_checks += 1
	plan.member_projected_path_k[front_mid] = current_k
	if not _require(not army._can_release_saturated_front(current_k, current_k + 1, 2, 1, one_lane_front, 1), "A physical row occupant without a matching observed front cannot release"): return
	single_width_checks += 1
	plan.member_projected_path_k[front_mid] = current_k + 4
	if not _require(not army._can_release_saturated_front(current_k, current_k + 1, 2, 1, one_lane_front, 2), "A width-two target still requires two leaders"): return
	single_width_checks += 1
	var original_target_block: int = terrain.static_blocked[terrain.index(one_lane_target)]
	terrain.static_blocked[terrain.index(one_lane_target)] = 1
	if not _require(not army._can_release_saturated_front(current_k, current_k + 1, 2, 1, one_lane_front, 1), "A newly blocked target row cannot release"): return
	single_width_checks += 1
	terrain.static_blocked[terrain.index(one_lane_target)] = original_target_block
	if not _require(army.cells[front_index] == one_lane_saturated and army.moving_to[front_index] == TerrainArmy.INVALID_CELL and plan.macro_cursor == current_k, "Cursor probe must not move a body or start a physical step"): return
	var saturated: Array[int] = [127, 127, 127, 127]
	if not _require(army._can_release_elastic_front(123, 42, 100, 1, saturated), "A 100-person single-file convoy may advance at the observed 82-cell percentile gap"): return
	if not _require(not army._can_release_elastic_front(123, 17, 100, 1, saturated), "The full-roster physical bound must still stop excessive stretch"): return
	if not _require(not army._can_release_elastic_front(123, 42, 100, 4, saturated), "A genuinely wide route must retain its tighter physical bound"): return
	var one_elastic_leader: Array[int] = [127, 126, 125, 124]
	if not _require(not army._can_release_elastic_front(123, 42, 100, 1, one_elastic_leader), "A wide saturated row still needs two leaders"): return
	var saturated_cell: Vector2i = plan.macro_path[127]
	for side in [Vector2i.UP, Vector2i.DOWN]:
		terrain.static_blocked[terrain.index(saturated_cell + side)] = 1
	if not _require(army._can_release_elastic_front(123, 42, 100, 1, one_elastic_leader), "One physically observed leader at a verified one-cell soft row may release one step"): return
	var unsaturated_leaders: Array[int] = [126, 125, 124, 123]
	if not _require(not army._can_release_elastic_front(123, 42, 100, 1, unsaturated_leaders), "A leader short of the soft row may not release the cursor"): return
	if not _require(not army._can_release_elastic_front(123, 17, 100, 1, one_elastic_leader), "Single-file release must still stop beyond the 106-cell physical span"): return
	if not _require(not army._can_release_elastic_front(123, 42, 100, 4, one_elastic_leader), "Narrow soft row does not relax a wide convoy"): return
	# One leader in the front row and one in the preceding row are physically
	# ordered even when no two bodies fit in the same saturated cross-section.
	var adjacent_front_index := 2
	var adjacent_follow_index := 3
	var adjacent_front_mid: int = army.combat_identity(adjacent_front_index)
	var adjacent_follow_mid: int = army.combat_identity(adjacent_follow_index)
	var adjacent_front_cell: Vector2i = plan.macro_path[127]
	var adjacent_follow_cell: Vector2i = plan.macro_path[126]
	army._cell_owners.erase(army.cells[adjacent_front_index])
	army._cell_owners.erase(army.cells[adjacent_follow_index])
	army.cells[adjacent_front_index] = adjacent_front_cell
	army.cells[adjacent_follow_index] = adjacent_follow_cell
	army._cell_owners[adjacent_front_cell] = adjacent_front_index
	army._cell_owners[adjacent_follow_cell] = adjacent_follow_index
	plan.member_observed_path_k[adjacent_front_mid] = 127
	plan.member_observed_path_k[adjacent_follow_mid] = 126
	if not _require(army._front_has_adjacent_physical_pair(123) and army._can_release_elastic_front(123, 42, 100, 1, one_elastic_leader),
		"Two authoritative bodies in adjacent verified rows may release one elastic cursor step"): return
	if not _require(not army._can_release_elastic_front(123, 17, 100, 1, one_elastic_leader)
		and not army._can_release_elastic_front(123, 42, 100, 4, one_elastic_leader),
		"Adjacent physical leaders cannot bypass the roster stretch bound or wide-convoy rule"): return
	plan.member_observed_path_k[adjacent_follow_mid] = 125
	if not _require(not army._front_has_adjacent_physical_pair(123), "A following body without observed progress to its physical row cannot release"): return
	plan.member_observed_path_k[adjacent_follow_mid] = 126
	army._cell_owners.erase(adjacent_follow_cell)
	if not _require(not army._front_has_adjacent_physical_pair(123), "An unowned apparent follower is not an authoritative physical row occupant"): return
	army._cell_owners[adjacent_follow_cell] = adjacent_follow_index
	var same_row_cell := adjacent_front_cell + Vector2i.DOWN
	army._cell_owners.erase(adjacent_follow_cell)
	army.cells[adjacent_follow_index] = same_row_cell
	army._cell_owners[same_row_cell] = adjacent_follow_index
	if not _require(not army._front_has_adjacent_physical_pair(123), "Two bodies on the same saturated row cannot impersonate adjacent-row progress"): return
	army._cell_owners.erase(same_row_cell)
	army.cells[adjacent_follow_index] = adjacent_follow_cell
	army._cell_owners[adjacent_follow_cell] = adjacent_follow_index
	# A front body can be held at its own soft cell immediately ahead of the
	# cursor while the next lookahead row is empty. The body behind proves order.
	plan.current_width = 1
	plan.pending_width = 1
	var near_k := 50
	var near_rear: Vector2i = plan.macro_path[near_k]
	var near_front: Vector2i = plan.macro_path[near_k + 1]
	var near_empty: Vector2i = plan.macro_path[near_k + 2]
	for cell: Vector2i in [near_rear, near_front]:
		for side: Vector2i in [Vector2i.UP, Vector2i.DOWN]:
			terrain.static_blocked[terrain.index(cell + side)] = 1
	army._cell_owners.erase(adjacent_front_cell)
	army._cell_owners.erase(adjacent_follow_cell)
	army.cells[adjacent_front_index] = near_front
	army.cells[adjacent_follow_index] = near_rear
	army._cell_owners[near_front] = adjacent_front_index
	army._cell_owners[near_rear] = adjacent_follow_index
	plan.member_observed_path_k[adjacent_front_mid] = near_k + 1
	plan.member_observed_path_k[adjacent_follow_mid] = near_k
	plan.member_transit_slots[adjacent_front_mid] = near_front
	plan.member_path_s[adjacent_front_mid] = float(near_k + 1)
	plan.member_observed_path_s[adjacent_front_mid] = float(near_k + 1)
	var near_cohort: Array[int] = [near_k + 1, near_k, near_k - 1, near_k - 2]
	if not _require(army._front_has_one_step_physical_pair(near_k) \
		and army._can_release_saturated_front(near_k, near_k + 1, 2, 1, near_cohort, 1) \
		and army._can_release_elastic_front(near_k, 0, 100, 1, near_cohort),
		"Adjacent authoritative bodies at current and current+1 may release one narrow step with current+2 empty"): return
	if not _require(not army._can_release_saturated_front(near_k, near_k + 2, 2, 1, near_cohort, 1) \
		and not army._can_release_elastic_front(near_k, -60, 100, 1, near_cohort),
		"The adjacent-row proof cannot skip a step or exceed the physical roster length"): return
	for side: Vector2i in [Vector2i.UP, Vector2i.DOWN]:
		terrain.static_blocked[terrain.index(near_front + side)] = 0
	var local_width := FormationTransitPlanner.detect_corridor_width(terrain, near_front, near_empty - near_front, army.get_formation_movement_profile())
	if not _require(local_width > 1 and army._front_has_one_step_physical_pair(near_k) \
		and army._can_release_saturated_front(near_k, near_k + 1, 2, 1, near_cohort, local_width) \
		and army._can_release_elastic_front(near_k, 0, 100, 1, near_cohort),
		"A historical single-file convoy must release the adjacent pair even when the local front row widens"): return
	plan.current_width = 2
	plan.pending_width = 2
	if not _require(not army._front_has_one_step_physical_pair(near_k) \
		and not army._can_release_saturated_front(near_k, near_k + 1, 2, 1, near_cohort, local_width) \
		and not army._can_release_elastic_front(near_k, 0, 100, 2, near_cohort),
		"A genuinely wide convoy cannot use the single-file adjacent-pair exception"): return
	plan.current_width = 1
	plan.pending_width = 1
	plan.member_observed_path_k[adjacent_follow_mid] = near_k - 1
	if not _require(not army._front_has_one_step_physical_pair(near_k),
		"A rear body without observed progress to its occupied row cannot count"): return
	plan.member_observed_path_k[adjacent_follow_mid] = near_k
	army._cell_owners.erase(near_rear)
	if not _require(not army._front_has_one_step_physical_pair(near_k),
		"A lone front body cannot release the cursor"): return
	army._cell_owners[near_rear] = adjacent_follow_index
	plan.member_transit_slots[adjacent_front_mid] = near_empty
	plan.member_path_s[adjacent_front_mid] = float(near_k + 2)
	if not _require(not army._front_has_one_step_physical_pair(near_k),
		"A front member with a forward soft target is not held in the cursor-target loop"): return
	plan.member_transit_slots[adjacent_front_mid] = near_front
	plan.member_path_s[adjacent_front_mid] = float(near_k + 1)
	coordinator.movement_reservation_grid.blocked_destinations[near_empty] = true
	if not _require(not army._front_has_one_step_physical_pair(near_k),
		"A blocked forward vacancy cannot justify releasing the cursor"): return
	coordinator.movement_reservation_grid.blocked_destinations.erase(near_empty)
	coordinator.deployment_registry.try_replace_reservations(99, -1, 1, [near_empty])
	if not _require(not army._front_has_one_step_physical_pair(near_k),
		"Another formation's leased destination cannot release the cursor"): return
	coordinator.deployment_registry.release_order(99)
	plan.current_width = 4
	plan.pending_width = 4
	var next_cell: Vector2i = plan.macro_path[current_k + 1]
	terrain.static_blocked[terrain.index(next_cell)] = 1
	if not _require(not army._can_release_saturated_front(current_k, current_k + 1, 4, 3, front), "New terrain obstruction must block front release"): return
	var elastic_next_cell: Vector2i = plan.macro_path[124]
	terrain.static_blocked[terrain.index(elastic_next_cell)] = 1
	if not _require(not army._can_release_elastic_front(123, 42, 100, 1, one_elastic_leader), "A blocked next path edge must prevent single-file release"): return
	print("COMBAT MOVEMENT CURSOR FRONT RELEASE PASS single_width_checks=", single_width_checks, " accepted=1")
	coordinator.unregister_formation(army)
	army.free()
	quit(0)
