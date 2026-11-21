extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false

func _fixture(second_waiter: bool, third_waiter: bool = false) -> Dictionary:
	var terrain := Helper.build_flat_map(20, 15)
	var plan := CombatDeploymentPlan.new()
	plan.resolved_anchor = Vector2i(8, 6)
	plan.ingress_cell = Vector2i(2, 6)
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	var first := 999
	var second := 998
	var third := 1000
	var first_vacancy := Vector2i(8, 6)
	var second_vacancy := Vector2i(8, 5)
	var third_vacancy := Vector2i(8, 4)
	var cells: Dictionary = {first: Vector2i(18, 6)}
	if second_waiter:
		cells[second] = Vector2i(18, 5)
	if third_waiter:
		cells[third] = Vector2i(18, 4)
	var occupied: Dictionary = {}
	for cell in cells.values():
		occupied[cell] = true
	var allowed: Dictionary = {}
	var next_id := 1
	for x in range(3, 14):
		for y in range(1, 12):
			var slot := Vector2i(x, y)
			var mid := first if slot == first_vacancy else third if third_waiter and slot == third_vacancy else second if second_waiter and slot == second_vacancy else next_id
			if mid == next_id:
				next_id += 1
			plan.platform_slots.append(slot)
			plan.platform_footprint.append(slot)
			allowed[slot] = true
			plan.member_slot_map[mid] = slot
			plan.slot_owner_map[slot] = mid
			plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
			plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FLEX
			var free_corridor: bool = y == 1 and x >= 8 or x == 8 and y <= 6
			if mid == first or second_waiter and mid == second or third_waiter and mid == third:
				plan.admitted_platform_member_ids.append(mid)
			elif not free_corridor:
				cells[mid] = slot
				occupied[slot] = true
				plan.admitted_platform_member_ids.append(mid)
				plan.settled_platform_member_ids.append(mid)
				plan.member_slot_locked[mid] = true
	move.member_route_retry_count[first] = 20
	move.member_pending_proposal_id[first] = 17
	if second_waiter:
		move.member_route_retry_count[second] = 20
	if third_waiter:
		move.member_route_retry_count[third] = 20
	return {"terrain": terrain, "plan": plan, "move": move, "cells": cells, "occupied": occupied, "allowed": allowed, "first_vacancy": first_vacancy, "second_vacancy": second_vacancy, "third_vacancy": third_vacancy}

func _run() -> void:
	# Two legal vacancy exits compete: the near free edge needs four settled
	# soldiers to shift; the slightly farther free edge needs only one.
	var edge_terrain := Helper.build_flat_map(24, 16)
	edge_terrain.static_blocked[edge_terrain.index(Vector2i(7, 6))] = 1
	var edge_plan := CombatDeploymentPlan.new()
	edge_plan.ingress_cell = Vector2i(2, 6)
	edge_plan.centered_platform_handoff = Vector2i(10, 3)
	var edge_move := CombatMovePlan.new()
	edge_move.destination_plan = edge_plan
	var edge_cells: Dictionary = {999: Vector2i(12, 3), 998: Vector2i(20, 14)}
	var edge_occupied: Dictionary = {Vector2i(12, 3): true, Vector2i(20, 14): true}
	var edge_allowed: Dictionary = {}
	var edge_mid := 1
	for x in range(8, 13):
		for y in range(4, 9):
			var slot := Vector2i(x, y)
			var mid := 999 if slot == Vector2i(8, 6) else 998 if slot == Vector2i(8, 4) else edge_mid
			if mid == edge_mid:
				edge_mid += 1
			edge_plan.platform_slots.append(slot)
			edge_plan.platform_footprint.append(slot)
			edge_allowed[slot] = true
			edge_plan.member_slot_map[mid] = slot
			edge_plan.slot_owner_map[slot] = mid
			edge_plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
			edge_plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FLEX
			if mid == 999:
				edge_plan.pending_platform_member_ids.append(mid)
			elif mid != 998:
				edge_cells[mid] = slot
				edge_occupied[slot] = true
				edge_plan.admitted_platform_member_ids.append(mid)
				edge_plan.settled_platform_member_ids.append(mid)
				edge_plan.member_slot_locked[mid] = true
	edge_plan.admitted_platform_member_ids.append(998)
	edge_plan.ever_admitted_platform_member_ids[999] = true
	edge_move.member_route_retry_count[999] = 20
	if not _require(Destination._prior_entrant_final_isolated(edge_plan, 999, edge_cells, edge_terrain, edge_occupied)
		and Destination._recover_isolated_final_vacancy(edge_move, edge_plan, edge_cells, edge_terrain, edge_occupied, edge_allowed),
		"Competing vacancy exits must be eligible for isolated returned-entrant recovery"): return
	if not _require(edge_move.active_vacancy_chain_actors.size() == 1 and edge_cells[edge_move.active_vacancy_chain_actors[0]] == Vector2i(8, 5),
		"Choose the one-actor free-edge vacancy chain over a physically longer settled cascade"): return
	var case: Dictionary = _fixture(true, true)
	var plan: CombatDeploymentPlan = case.plan
	var move: CombatMovePlan = case.move
	var cells: Dictionary = case.cells
	var before: Dictionary = cells.duplicate()
	if not _require(Destination._recover_isolated_final_vacancy(move, plan, cells, case.terrain, case.occupied, case.allowed),
		"A stationary stranded owner must be served before another owner's in-flight proposal"): return
	if not _require(cells == before and plan.get_slot_for_member(1000) != case.third_vacancy and plan.get_slot_for_member(998) == case.second_vacancy and plan.get_slot_for_member(999) == case.first_vacancy and not move.active_vacancy_chain_actors.has(999),
		"Stationary peers must keep admission order, even when the earlier member ID is larger; all physical cells stay unchanged"): return
	var unique: Dictionary = {}
	for mid in plan.member_slot_map.keys():
		var slot: Vector2i = plan.get_slot_for_member(mid)
		if not _require(not unique.has(slot) and int(plan.slot_owner_map.get(slot, -1)) == mid,
			"A selected vacancy chain must retain unique final ownership"): return
		unique[slot] = true
	for actor in move.active_vacancy_chain_actors:
		if not _require(case.terrain.can_step(cells[actor], plan.get_slot_for_member(actor)),
			"Vacancy-chain actors must move later through ordinary legal Grid steps"): return
	var only: Dictionary = _fixture(false)
	var only_plan: CombatDeploymentPlan = only.plan
	var only_move: CombatMovePlan = only.move
	var only_cells: Dictionary = only.cells
	var before_only: Dictionary = only_cells.duplicate()
	if not _require(Destination._recover_isolated_final_vacancy(only_move, only_plan, only_cells, only.terrain, only.occupied, only.allowed),
		"An in-flight sole candidate must retain its existing temporary hold"): return
	if not _require(only_move.member_recovery_hold.has(999) and only_move.active_vacancy_chain_actors.is_empty() and only_cells == before_only and only_plan.get_slot_for_member(999) == only.first_vacancy,
		"The hold must not rewrite a final or physical cell before its proposal completes"): return
	var returning: Dictionary = _fixture(true, true)
	var returning_plan: CombatDeploymentPlan = returning.plan
	var returning_move: CombatMovePlan = returning.move
	var returning_cells: Dictionary = returning.cells
	returning_plan.admitted_platform_member_ids.erase(998)
	returning_plan.pending_platform_member_ids.append(998)
	returning_plan.ever_admitted_platform_member_ids[998] = true
	if not _require(not Destination._prior_entrant_final_isolated(returning_plan, 998, returning_cells, returning.terrain, returning.occupied),
		"A high-retry returned entrant still has a free-only route around this open block"): return
	var before_returning: Dictionary = returning_cells.duplicate()
	if not _require(Destination._is_prior_platform_entrant_beyond_handoff(returning_plan, 998, returning_cells) and Destination._recover_isolated_final_vacancy(returning_move, returning_plan, returning_cells, returning.terrain, returning.occupied, returning.allowed),
		"A stationary admitted peer must retain priority over a returned entrant with a free-only route"): return
	if not _require(returning_plan.get_slot_for_member(998) == returning.second_vacancy and returning_plan.get_slot_for_member(1000) != returning.third_vacancy and returning_cells == before_returning and returning_plan.pending_platform_member_ids.has(998),
		"High retry count alone cannot pull a reachable returned entrant ahead of admitted peers"): return
	var isolated_return: Dictionary = _fixture(true, true)
	var isolated_plan: CombatDeploymentPlan = isolated_return.plan
	var isolated_move: CombatMovePlan = isolated_return.move
	var isolated_cells: Dictionary = isolated_return.cells
	isolated_plan.admitted_platform_member_ids.erase(998)
	isolated_plan.pending_platform_member_ids.append(998)
	isolated_plan.ever_admitted_platform_member_ids[998] = true
	isolated_return.terrain.static_blocked[isolated_return.terrain.index(Vector2i(8, 1))] = 1
	if not _require(Destination._prior_entrant_final_isolated(isolated_plan, 998, isolated_cells, isolated_return.terrain, isolated_return.occupied)
		and Destination._recover_isolated_final_vacancy(isolated_move, isolated_plan, isolated_cells, isolated_return.terrain, isolated_return.occupied, isolated_return.allowed)
		and isolated_plan.get_slot_for_member(998) != isolated_return.second_vacancy and isolated_plan.get_slot_for_member(1000) == isolated_return.third_vacancy,
		"A repeatedly failed returned entrant with no free-only route must receive the reachable vacancy chain first"): return
	var fresh_return: Dictionary = _fixture(true, true)
	var fresh_plan: CombatDeploymentPlan = fresh_return.plan
	var fresh_move: CombatMovePlan = fresh_return.move
	var fresh_cells: Dictionary = fresh_return.cells
	fresh_plan.admitted_platform_member_ids.erase(998)
	fresh_plan.pending_platform_member_ids.append(998)
	fresh_plan.ever_admitted_platform_member_ids[998] = true
	fresh_move.member_route_retry_count[998] = 2
	fresh_return.terrain.static_blocked[fresh_return.terrain.index(Vector2i(8, 1))] = 1
	if not _require(Destination._recover_isolated_final_vacancy(fresh_move, fresh_plan, fresh_cells, fresh_return.terrain, fresh_return.occupied, fresh_return.allowed)
		and fresh_plan.get_slot_for_member(1000) != fresh_return.third_vacancy and fresh_plan.get_slot_for_member(998) == fresh_return.second_vacancy,
		"A newly returned entrant with few failed routes must not displace a stationary stranded peer"): return
	var unentered: Dictionary = _fixture(true, true)
	var unentered_plan: CombatDeploymentPlan = unentered.plan
	unentered_plan.admitted_platform_member_ids.erase(998)
	unentered_plan.pending_platform_member_ids.append(998)
	if not _require(Destination._recover_isolated_final_vacancy(unentered.move, unentered_plan, unentered.cells, unentered.terrain, unentered.occupied, unentered.allowed) and unentered_plan.get_slot_for_member(998) == unentered.second_vacancy and unentered_plan.get_slot_for_member(1000) != unentered.third_vacancy,
		"A never-admitted pending soldier must not use the returned-entrant priority"): return
	print("COMBAT MOVEMENT ISOLATED RECOVERY FAIRNESS PASS")
	quit(0)
