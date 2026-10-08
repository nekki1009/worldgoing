extends "res://scripts/tests/site_fire_hazard_navigation_test.gd"
## UNRUN candidate: actual 100-formation Coordinator/Army/Grid route scheduling.
## No allocation, cursor, route, readiness, or movement state is injected after genesis.
var scheduler_evidence := {"status":"RUNNING","first_service":[],"ticks":[]}

func _scheduler_100() -> bool:
	var f := _fixture(2, Vector2i(86, 86))
	var coordinator: SiteCombatMovementCoordinator = f.coordinator
	var budget: SiteRouteBudget = coordinator.route_budget
	var armies: Array[TerrainArmy] = [f.army]
	var sources := {}
	var goals := {}
	var main_serials := {}
	var ranged_serials := {}
	var retained_cold_leases := {}
	for team in range(1, 100):
		var army := Helper.create_test_army(f.data, 1000 + team, 0, 2, Vector2i(3, 3))
		coordinator.register_formation(army)
		armies.append(army)
		fixtures.append({"data":f.data,"army":army,"coordinator":coordinator,"now":0.0})
	for team in range(100):
		var army := armies[team]
		var anchor := Vector2i(2 + (team % 10) * 8, 2 + floori(float(team) / 10.0) * 8)
		var cold := anchor + Vector2i(1, 1)
		var hot := anchor + Vector2i(1, 4)
		var goal := anchor + Vector2i(5, 1)
		army._cell_owners.clear()
		army.cells[0] = cold
		army.cells[1] = hot
		army._cell_owners[cold] = 0
		army._cell_owners[hot] = 1
		army.combat_slots[0] = goal
		army.combat_slots[1] = hot
		# The cold Aging route must have the same original destination lease
		# that a real MOVE supplies. A fabricated HOLD slot without a lease is
		# correctly rejected by _can_begin_fire_move and cannot prove motion.
		army.combat_order = TerrainArmy.CombatOrder.MOVE
		var fid := army.get_formation_id()
		var plan := CombatDeploymentPlan.new()
		var move := CombatMovePlan.new()
		plan.formation_id = army.team_id
		plan.order_serial = army.get_order_serial()
		plan.structural_platform_capacity = 2
		plan.available_platform_capacity = 2
		plan.requested_count = 2
		plan.resolved_anchor = goal
		plan.ingress_cell = anchor + Vector2i(0, 1)
		plan.platform_footprint.assign([goal, hot])
		plan.platform_slots.assign([goal, hot])
		for index in range(2):
			var member := army.combat_identity(index)
			var slot := goal if index == 0 else hot
			plan.member_slot_map[member] = slot
			plan.slot_owner_map[slot] = member
			plan.member_role_map[member] = Types.CombatDestinationRole.PLATFORM
			plan.pending_platform_member_ids.append(member)
		move.formation_id = fid
		move.order_serial = plan.order_serial
		move.destination_plan = plan
		move.terrain_revision = f.data.navigation_revision
		move.macro_path.assign([cold, cold + Vector2i.RIGHT, cold + Vector2i.RIGHT * 2,
			cold + Vector2i.RIGHT * 3, goal])
		army._combat_move_plan = move
		army._combat_deployment_plan = plan
		if not _check(coordinator.deployment_registry.try_replace_reservations(army.team_id, 0,
			plan.order_serial, [goal, hot]).ok, "Original MOVE lease genesis precedes heat and all scheduling", fid): return false
		retained_cold_leases[fid] = coordinator.deployment_registry.owner_of(goal)
		sources[fid] = [cold, hot]
		goals[fid] = goal
		main_serials[fid] = army.get_order_serial()
		ranged_serials[fid] = army.ranged_order_serial
		_heat(f, hot)
	coordinator.request_occupancy_rebuild()
	var snapshot := SiteRuntime.fire_hazard_snapshot(f.data)
	for army: TerrainArmy in armies:
		var fid := army.get_formation_id()
		if not _check(army.combat_can_act(0) and army.combat_can_act(1) and not army.is_controlled_person(0) and not army.is_controlled_person(1)
			and SiteRuntime.fire_exposure_at(snapshot, sources[fid][0], 0.5) == 0.0
			and SiteRuntime.fire_exposure_at(snapshot, sources[fid][1], 0.5) == 1.0
			and f.data.is_walkable(goals[fid]), "Each real formation has one cold Aging request and one immediate fire escape", fid): return false
	var first_service := {}
	var first_deferred := {}
	var committed_members := {}
	var completed_escape := {}
	var aging_calls := 0
	var aging_charge := 0
	var aging_actual := 0
	var urgent_calls := 0
	var urgent_charge := 0
	var urgent_actual := 0
	var initial_cursor := budget.epoch_cursor
	# Original 64-of-100 base allocation returns to its initial cursor after
	# 25 ticks. Every formation's first real service must include both demands.
	for tick in range(25):
		f.now += STEP
		f.data.set_meta(&"fire_completed_action_end", f.now)
		coordinator.combat_logic_tick_if_needed(STEP)
		var tick_calls := 0
		var tick_charge := 0
		var deferred_count := 0
		for army: TerrainArmy in armies:
			var fid := army.get_formation_id()
			if not _check(not army._fire_navigation.is_empty(), "Real fire navigation remains active through the scheduler cycle", {"tick":tick,"formation":fid}): return false
			var state: Dictionary = army._fire_navigation
			var metrics: Dictionary = state.metrics
			if not _check(retained_cold_leases[fid] != null
				and is_same(retained_cold_leases[fid], coordinator.deployment_registry.owner_of(goals[fid])),
				"Cold Aging retains the exact original safe destination lease throughout scheduling", fid): return false
			var allocation := budget.get_allocation(fid)
			var local_calls := 0
			var local_charge := 0
			var saw_after_aging := false
			for row: Dictionary in metrics.trace:
				if row.pool == "AFTER_AGING": saw_after_aging = true
				if not _check(not (row.pool == "AGING" and saw_after_aging) and int(row.calls) > 0
					and int(row.actual) >= 0 and int(row.charged) >= int(row.actual),
					"Actual trace serves Aging first and accounts calls/charged/actual expansions independently", row): return false
				local_calls += int(row.calls)
				local_charge += int(row.charged)
			if not _check(local_calls == int(allocation.calls_used) and local_charge == int(allocation.expansions_used)
				and local_calls <= int(metrics.allocation_calls) and local_charge <= int(metrics.allocation_expansions),
				"Trace reconciles exactly to original per-formation owner counters", {"tick":tick,"formation":fid,"metrics":metrics,"allocation":allocation}): return false
			tick_calls += local_calls
			tick_charge += local_charge
			if int(metrics.aging_demand) > 0:
				if not _check(2 * int(metrics.aging_reserved_calls) >= int(metrics.allocation_calls)
					and 2 * int(metrics.aging_reserved_expansions) >= int(metrics.allocation_expansions),
					"Both real Aging reservations independently cover at least half", metrics): return false
			if bool(allocation.deferred):
				deferred_count += 1
				if not first_service.has(fid):
					first_deferred[fid] = true
					for index in range(2):
						var entry: Dictionary = state.members[army.combat_identity(index)]
						if not _check(entry.reason == "SCHEDULER_DEFERRED" and army.moving_to[index] == TerrainArmy.INVALID_CELL
							and army.cells[index] == sources[fid][index],
							"An unallocated original formation waits without STATIC_BLOCKED or invented movement", {"formation":fid,"entry":entry}): return false
			elif not first_service.has(fid):
				var cold_id := army.combat_identity(0)
				var hot_id := army.combat_identity(1)
				if not _check(metrics.aging_demand == 1 and metrics.urgent_demand == 1 and metrics.trace.size() == 2
					and metrics.trace[0].pool == "AGING" and metrics.trace[0].member == cold_id
					and metrics.trace[1].pool == "AFTER_AGING" and metrics.trace[1].member == hot_id,
					"Every formation receives actual Aging then emergency search on its first allocated turn", {"formation":fid,"metrics":metrics}): return false
				if not _check(int(metrics.aging_used.calls) > 0 and int(metrics.aging_used.actual) > 0
					and int(metrics.after_aging_used.calls) > 0 and int(metrics.after_aging_used.actual) > 0
					and int(metrics.aging_used.calls) * 2 >= local_calls
					and int(metrics.aging_used.charged) * 2 >= local_charge
					and int(metrics.aging_used.actual) >= int(metrics.after_aging_used.actual),
					"Both pools really execute; Aging receives at least half of consumed calls, charged and actual expansions", metrics): return false
				aging_calls += int(metrics.aging_used.calls)
				aging_charge += int(metrics.aging_used.charged)
				aging_actual += int(metrics.aging_used.actual)
				urgent_calls += int(metrics.after_aging_used.calls)
				urgent_charge += int(metrics.after_aging_used.charged)
				urgent_actual += int(metrics.after_aging_used.actual)
				first_service[fid] = tick
				scheduler_evidence.first_service.append({"formation":fid,"tick":tick,"metrics":metrics.duplicate(true),
					"cold_live_lease":state.members[cold_id].lease != null,"cold_target":state.members[cold_id].target,
					"cold_reason":state.members[cold_id].reason,"cold_moving_to":army.moving_to[0],
					"escape_live_lease":state.members[hot_id].lease != null,"escape_moving_to":army.moving_to[1]})
			for index in range(2):
				var mid := army.combat_identity(index)
				var entry: Dictionary = state.members[mid]
				if not _check(entry.reason != "STATIC_BLOCKED" and army.combat_order == TerrainArmy.CombatOrder.MOVE
					and army.get_order_serial() == main_serials[fid] and army.ranged_order_serial == ranged_serials[fid],
					"Scheduler preserves original main/ranged generations and MOVE", {"formation":fid,"entry":entry}): return false
				var destination: Vector2i = army.moving_to[index]
				if destination == TerrainArmy.INVALID_CELL: continue
				if not _check(army._cell_owners.get(army.cells[index], -1) == index
					and army._reserved_cells.has(destination) and army._committed_intent_order(mid) == army.FIRE_HAZARD_STEP
					and f.data.can_step(army.cells[index], destination),
					"Every actual fire move has original source ownership, destination claim and legal terrain edge", mid): return false
				committed_members[mid] = true
		if not _check(tick_calls == budget.site_calls_used and tick_charge == budget.site_expansions_used
			and budget.site_expansions_used <= SiteRouteBudget.SITE_MAX_EXPANSIONS_PER_TICK,
			"All 100 formation traces reconcile to the unchanged shared Site cap", {"calls":tick_calls,"expansions":tick_charge}): return false
		scheduler_evidence.ticks.append({"tick":tick,"calls":tick_calls,"charged_expansions":tick_charge,
			"deferred_formations":deferred_count,"cursor":budget.epoch_cursor})
		for army: TerrainArmy in armies: army.prepare_combat(STEP, STEP)
		coordinator.complete_committed_moves()
		for army: TerrainArmy in armies:
			var fid := army.get_formation_id()
			if army.cells[1] != sources[fid][1] and army.moving_to[1] == TerrainArmy.INVALID_CELL:
				if not _check(SiteRuntime.fire_exposure_at(snapshot, army.cells[1], 0.5) == 0.0,
					"Original Grid completes escape on a cold real endpoint", fid): return false
				completed_escape[fid] = true
	if not _check(first_service.size() == 100 and first_deferred.size() == 36 and budget.epoch_cursor == initial_cursor
		and committed_members.size() == 200 and completed_escape.size() == 100,
		"Complete original 25-tick round-robin cycle serves all 100 formations and commits 200 actual moves",
		{"served":first_service.size(),"initial_deferred":first_deferred.size(),"committed":committed_members.size(),"escaped":completed_escape.size(),"cursor":budget.epoch_cursor}): return false
	if not _check(aging_calls > 0 and urgent_calls > 0 and aging_actual > 0 and urgent_actual > 0
		and aging_calls >= urgent_calls and aging_charge >= urgent_charge and aging_actual >= urgent_actual,
		"Whole 100-formation first-service evidence preserves the two independent consumed Aging shares",
		{"aging_calls":aging_calls,"urgent_calls":urgent_calls,"aging_charged":aging_charge,"urgent_charged":urgent_charge,
		"aging_actual":aging_actual,"urgent_actual":urgent_actual}): return false
	scheduler_evidence.merge({"served":first_service.size(),"committed_members":committed_members.size(),
		"completed_escapes":completed_escape.size(),"aging_calls":aging_calls,"urgent_calls":urgent_calls,
		"aging_charged":aging_charge,"urgent_charged":urgent_charge,"aging_actual":aging_actual,"urgent_actual":urgent_actual})
	return true

func _run() -> void:
	var ok := _scheduler_100()
	scheduler_evidence.status = "PASS" if ok else "FAIL"
	var file := FileAccess.open("res://output/fire_implementation_20261006/p3_scheduler_100_evidence.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(scheduler_evidence, "\t"))
		file.close()
	print("SITE_FIRE_SCHEDULER_100_", "PASS" if ok else "FAIL", " checks=", checks)
	_finish(ok, "FM08/AT05 actual 100-formation scheduler; no performance acceptance")
