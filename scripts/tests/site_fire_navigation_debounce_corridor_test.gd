extends "res://scripts/tests/site_fire_hazard_navigation_test.gd"
## OUTPUT CANDIDATE / NOT_RUN. No body/path/lease writes after fixture genesis.
## FM10 uses original finite suppression, impact receipts and Runtime 5 Hz heat.
## FM04 uses deterministic Runtime hazard genesis and original weighted search.
var evidence := {"scope":"FM10 FM04 AT03 original GD navigation only", "status":"NOT_RUN"}

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	evidence.status = "PASS" if ok else "FAIL"
	evidence.reason = reason
	evidence.checks = checks
	var file := FileAccess.open("res://output/fire_implementation_20261006/p3_navigation_debounce_corridor_evidence.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(evidence, "\t")); file.close()
	for f: Dictionary in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_NAVIGATION_DEBOUNCE_CORRIDOR_", evidence.status, ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _risk(f: Dictionary, cell: Vector2i) -> float:
	return SiteRuntime.fire_exposure_at(SiteRuntime.fire_hazard_snapshot(f.data), cell, float(f.data.effective_height(cell)) + 0.5)

func _current_unit(f: Dictionary) -> Dictionary:
	return f.data.site.fire.units[f.key]

func _debounce_tick(f: Dictionary, suppress: bool = false) -> bool:
	var army: TerrainArmy = f.army
	var begin := float(f.now)
	var end := begin + STEP
	if suppress:
		var prepared := SiteRuntime.fire_prepare_suppression(f.data, f.key, f.generation, begin, end, 34, f.holder, int(f.holder.version))
		if not _check(prepared.ok, "Original bounded finite suppression prepares", prepared): return false
		if int(prepared.get("paid_q", 0)) > 0:
			var committed := SiteRuntime.fire_commit_suppression(f.data, prepared)
			if not _check(committed.ok, "Original holder commits finite cooling", committed): return false
			f.paid_q = int(f.paid_q) + int(committed.paid_q)
	var active_before := not army._fire_navigation.is_empty()
	f.now = end
	f.data.set_meta(&"fire_completed_action_end", end)
	f.coordinator.combat_logic_tick_if_needed(STEP)
	army.prepare_combat(STEP, STEP)
	f.coordinator.complete_committed_moves()
	var advanced := SiteRuntime.fire_advance(f.data, end, int(f.prefix))
	if not _check(advanced.ok, "Same completed action interval advances original 5 Hz Runtime", advanced): return false
	var active_after := not army._fire_navigation.is_empty()
	if active_before and not active_after:
		f.exit_count = int(f.exit_count) + 1
		f.exit_at = end
		f.exit_path_epoch = f.move.path_epoch
		if not _check(float(f.second_cool_since) >= 0.0 and end + 0.00000001 >= float(f.second_cool_since) + float(f.safe_seconds),
			"FM10 overlay exits only after the entire SECOND cold window", {"now":end,"second_cool_since":f.second_cool_since}): return false
	if int(f.get("nav_epoch", -1)) >= 0:
		# Original successful MOVE completion calls _clear_member_attack_targets,
		# which legitimately increments ranged_order_serial once on arrival.
		var completed := not active_after and int(f.exit_count) == 1 and army.combat_order == TerrainArmy.CombatOrder.HOLD \
			and army._combat_move_plan == null and army._automatic_deployment_settled()
		if not _check(army._fire_navigation_epoch == int(f.nav_epoch) and army.get_order_serial() == int(f.serial)
			and army.ranged_order_serial == int(f.ranged_serial) + (1 if completed else 0),
			"One fire episode preserves command epochs; only original completed MOVE clears ranged once"): return false
		if not _check(not is_same(f.old_danger_lease, f.coordinator.deployment_registry.owner_of(f.danger)),
			"Suspended original dangerous lease is never resurrected"): return false
		if active_after:
			if not _check(is_same(army._combat_move_plan, f.move) and is_same(army._combat_deployment_plan, f.plan)
				and army.combat_order == TerrainArmy.CombatOrder.MOVE, "Active overlay retains original MOVE owners"): return false
			for index in range(army.cells.size()):
				var mid := army.combat_identity(index)
				if not _check(army.cells[index] != f.danger and army.moving_to[index] != f.danger
					and f.plan.member_slot_map.get(mid, TerrainArmy.INVALID_CELL) != f.danger,
					"During cooling/reignition no body or assignment returns to suspended danger"): return false
	if int(f.exit_count) > 0:
		for index in range(army.cells.size()):
			var destination: Vector2i = army.moving_to[index]
			if destination == TerrainArmy.INVALID_CELL: continue
			var mid := army.combat_identity(index)
			if army._committed_intent_order(mid) != TerrainArmy.CombatOrder.MOVE: continue
			if not _check(army._cell_owners.get(army.cells[index], -1) == index
				and army._reserved_cells.get(destination, -1) == index,
				"Recovered original MOVE has real source and reserved destination claims"): return false
			f.recovery_members[mid] = true
	var unit := _current_unit(f)
	if not _check(int(unit.generation) == int(f.generation) and int(unit.fuel_remainder_q) <= int(f.last_fuel)
		and int(unit.fuel_remainder_q) > 0 and int(f.holder.fire_lab_suppression_q) + int(f.paid_q) == 30720,
		"Original generation and finite fuel/suppression accounting remain intact"): return false
	f.last_fuel = int(unit.fuel_remainder_q)
	if int(f.data.site.fire.step_index) != int(f.last_step):
		f.trace.append({"at":end,"step":f.data.site.fire.step_index,"heat":unit.heat,"state":unit.state,
			"risk":_risk(f,f.danger),"fuel_q":unit.fuel_remainder_q,"supply_q":f.holder.fire_lab_suppression_q,
			"active_overlay":active_after,"cool_since":army._fire_navigation.get("cool_since",-1.0),
			"hazard_revision":SiteRuntime.fire_hazard_snapshot(f.data).revision})
		f.last_step = int(f.data.site.fire.step_index)
	return true

func _cool_to_zero(f: Dictionary) -> bool:
	for tick in range(180):
		if not _debounce_tick(f, true): return false
		if float(_current_unit(f).heat) == 0.0 and _risk(f, f.danger) == 0.0: return true
	return _check(false, "Finite suppression must actually reach cold", _current_unit(f))

func _debounce_reignite() -> bool:
	var f := _fixture(2, Vector2i(56,24))
	var army: TerrainArmy = f.army
	f.data.moisture.fill(0)
	f.data.water_kind.fill(0)
	var ordered := army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(42,12), -1, Vector2i.RIGHT)
	if not _check(ordered.ok and army._combat_move_plan != null and army._combat_deployment_plan != null,
		"FM10 real original MOVE supplies the plan and reservations", ordered): return false
	f.plan = army._combat_deployment_plan
	f.move = army._combat_move_plan
	var mid := army.combat_identity(0)
	if not _check(f.plan.member_slot_map.has(mid) and f.plan.member_slot_map.size() == 2, "Both real members have original destinations"): return false
	f.danger = f.plan.member_slot_map[mid]
	f.old_danger_lease = f.coordinator.deployment_registry.owner_of(f.danger)
	if not _check(f.old_danger_lease != null and army.cells[0].distance_to(f.danger) > 20.0,
		"Original distant dangerous obligation has an actual live lease"): return false
	# The sole thermal genesis: walkable original TIMBER with a legal finite
	# fractional remainder. It remains the same original owner when reheated.
	var resource := "%d:%d" % [SiteEnvironment.Kind.TIMBER, f.data.index(f.danger)]
	SiteEnvironment._add_resource(f.data, SiteEnvironment.Kind.TIMBER, f.data.index(f.danger), 256, 0)
	SiteEnvironment.change(f.data, resource, {"remaining":0,"cleared":false})
	SiteEnvironment.rebuild_indexes(f.data)
	var state := SiteRuntime._fire_state(f.data, 0.0)
	var unit := SiteRuntime._fire_unit(f.data, state, SiteRuntime._fire_resource_descriptor(f.data,resource))
	unit.merge({"heat":40.0,"state":"BURNING","intensity":1.0,"moisture":0.0,"fuel_remainder_q":1023}, true)
	f.key = "resource:" + resource
	state.active[f.key] = true
	SiteRuntime.fire_hazard_invalidate(f.data)
	f.generation = int(unit.generation)
	if not army.combat_units[0].has("item_state"):
		army.combat_units[0].item_state = SiteRuntime.new_item_state("person:%d" % mid)
	f.holder = army.combat_units[0].item_state
	f.holder.fire_lab_suppression_q = 30720
	f.merge({"serial":army.get_order_serial(),"ranged_serial":army.ranged_order_serial,"prefix":0,"paid_q":0,
		"exit_count":0,"exit_at":-1.0,"nav_epoch":-1,"second_cool_since":-1.0,"last_fuel":1023,"last_step":-1,
		"safe_seconds":SiteCombatRules.fire_navigation_profile().safe_seconds,"recovery_members":{},"trace":[],
		"initial_path_epoch":f.move.path_epoch}, true)
	evidence.fm10 = f.trace
	if not _debounce_tick(f): return false
	if not _check(not army._fire_navigation.is_empty() and f.plan.fire_suspended_slots.has(f.danger)
		and not is_same(f.old_danger_lease,f.coordinator.deployment_registry.owner_of(f.danger)),
		"Actual heat suspends the original dangerous obligation"): return false
	f.nav_epoch = army._fire_navigation_epoch
	if not _cool_to_zero(f): return false
	if not _debounce_tick(f): return false # Original coordinator observes the new cold snapshot.
	var first_cold := float(army._fire_navigation.get("cool_since",-1.0))
	if not _check(first_cold >= 0.0, "First actual cold observation starts original safe window"): return false
	for tick in range(9):
		if not _debounce_tick(f): return false
	if not _check(not army._fire_navigation.is_empty() and int(f.exit_count) == 0
		and float(f.now)-first_cold < float(f.safe_seconds), "FM10 short 0.3 s cold interval cannot end overlay"): return false
	var revision := int(SiteRuntime.fire_hazard_snapshot(f.data).revision)
	var impact := SiteRuntime.fire_receive_impact(f.data, {"site_id":str(f.data.site.id),"projectile_id":1,"event_id":"arrow:1",
		"action_time":float(f.now),"type":"ground","cell":f.danger,"remaining_heat_budget":48.0,
		"heat_rate":240.0,"max_seconds":0.2,"heat_transfer":1.0,"contact_scale":1.0})
	if not _check(impact.ok and impact.accepted, "Finite original terminal receipt accepts actual reignition", impact): return false
	f.prefix = 1
	var reignited := false
	for tick in range(18):
		if not _debounce_tick(f): return false
		if str(_current_unit(f).state) == "BURNING" and _risk(f,f.danger) > 0.0:
			reignited = true
			break
	if not _check(reignited and SiteRuntime.fire_hazard_snapshot(f.data).revision > revision,
		"Runtime actually re-enters BURNING with a newer hazard snapshot", _current_unit(f)): return false
	if not _debounce_tick(f): return false
	if not _check(float(army._fire_navigation.get("cool_since",-2.0)) == -1.0 and int(f.exit_count) == 0,
		"Observed reignition resets the first safe window without a new fire episode"): return false
	if not _cool_to_zero(f): return false
	if not _debounce_tick(f): return false
	f.second_cool_since = float(army._fire_navigation.get("cool_since",-1.0))
	if not _check(float(f.second_cool_since) > first_cold, "Second actual cold observation starts a fresh full window"): return false
	for tick in range(120):
		if not _debounce_tick(f): return false
		if army._fire_navigation.is_empty(): break
	if not _check(army._fire_navigation.is_empty() and int(f.exit_count) == 1
		and int(f.exit_path_epoch) > int(f.initial_path_epoch), "Full safe window exits once and invalidates stale original MOVE routes"): return false
	for tick in range(1200):
		if not _debounce_tick(f): return false
		if army.combat_order == TerrainArmy.CombatOrder.HOLD and army._automatic_deployment_settled(): break
	var arrivals := 0
	for index in range(army.cells.size()):
		var member := army.combat_identity(index)
		if army.cells[index] == f.plan.member_slot_map.get(member,TerrainArmy.INVALID_CELL) and army.moving_to[index] == TerrainArmy.INVALID_CELL: arrivals += 1
	if not _check(arrivals == 2 and not f.recovery_members.is_empty() and int(f.exit_count) == 1
		and army.combat_order == TerrainArmy.CombatOrder.HOLD and army._combat_move_plan == null
		and army._settled_deployment_leases_valid() and army._reserved_cells.is_empty(),
		"Original MOVE truly resumes and both members physically settle under the same order generation",
		{"arrivals":arrivals,"recovery_members":f.recovery_members,"order":army.combat_order,"now":f.now}): return false
	evidence.fm10_result = {"first_cold_since":first_cold,"second_cold_since":f.second_cool_since,"exit_at":f.exit_at,
		"exit_count":f.exit_count,"nav_epoch":f.nav_epoch,"paid_q":f.paid_q,"fuel_q":f.last_fuel,
		"actual_arrivals":arrivals,"recovery_members":f.recovery_members.size(),"main_serial":f.serial,
		"overlay_ranged_serial":f.ranged_serial,"completed_ranged_serial":army.ranged_order_serial}
	_close(f)
	return true

func _corridor(normal: bool) -> bool:
	var f := _fixture(1, Vector2i(12,10))
	var army: TerrainArmy = f.army
	var source := Vector2i(2,3) if normal else Vector2i(3,3)
	var hotter := Vector2i(4,3)
	var exit_cell := Vector2i(5,3)
	# Static corridor and body genesis, before the original occupancy barrier.
	f.data.flags.fill(0)
	for x in range(source.x,6): f.data.flags[f.data.index(Vector2i(x,3))] = TerrainData.Flag.WALKABLE
	army.cells[0] = source
	army.combat_slots[0] = source
	army._cell_owners.clear()
	army._cell_owners[source] = 0
	var cold_lease: Variant = null
	if normal:
		var ordered := army.issue_combat_order(army.current_commander,TerrainArmy.CombatOrder.MOVE,exit_cell,-1,Vector2i.RIGHT)
		if not _check(ordered.ok and army._combat_deployment_plan != null and army._combat_move_plan != null,
			"NORMAL original MOVE exists before corridor heating",ordered): return false
		var mid := army.combat_identity(0)
		if not _check(army._combat_deployment_plan.member_slot_map.get(mid,TerrainArmy.INVALID_CELL) == exit_cell,
			"NORMAL original destination is the actual cold corridor exit"): return false
		cold_lease = f.coordinator.deployment_registry.owner_of(exit_cell)
		if not _check(cold_lease != null and army._combat_move_plan.macro_path.has(Vector2i(3,3)),
			"Original cold lease and real macro path cross the soon-hot corridor"): return false
	var revision: int = f.data.navigation_revision
	_heat(f,Vector2i(3,3),0.5)
	_heat(f,hotter,1.0)
	if not _check(f.data.navigation_revision == revision and f.data.can_step(Vector2i(3,3),hotter)
		and f.data.can_step(hotter,exit_cell) and _risk(f,hotter) > _risk(f,Vector2i(3,3))
		and _risk(f,exit_cell) == 0.0, "Real Runtime heat overlays unchanged legal static corridor"): return false
	var serial := army.get_order_serial()
	var ranged_serial := army.ranged_order_serial
	var member := army.combat_identity(0)
	f.coordinator.request_occupancy_rebuild()
	_tick(f)
	if not _check(not army._fire_navigation.is_empty() and army._fire_navigation.members.has(member),
		"Original Coordinator activates real hazard navigation"): return false
	var entry: Dictionary = army._fire_navigation.members[member]
	if normal:
		if not _check(entry.policy == "NORMAL" and entry.reason == "NO_SAFE_ROUTE"
			and army.cells[0] == source and army.moving_to[0] == TerrainArmy.INVALID_CELL
			and army._reserved_cells.is_empty() and is_same(cold_lease,f.coordinator.deployment_registry.owner_of(exit_cell))
			and not army._is_stall_clock_eligible(),
			"FM04/AT03 NORMAL reports NO_SAFE_ROUTE without STATIC_BLOCKED, motion or lease loss",entry): return false
		for tick in range(45): _tick(f)
		entry = army._fire_navigation.members[member]
		if not _check(entry.reason == "NO_SAFE_ROUTE" and army.cells[0] == source
			and army.moving_to[0] == TerrainArmy.INVALID_CELL and army.combat_order == TerrainArmy.CombatOrder.MOVE
			and is_same(cold_lease,f.coordinator.deployment_registry.owner_of(exit_cell)),
			"Original retry retains NORMAL no-safe-route distinction and its cold destination lease",entry): return false
		evidence.fm04_normal = {"reason":entry.reason,"cell":army.cells[0],"lease_retained":true,"policy":entry.policy}
	else:
		if not _check(entry.policy == "EMERGENCY_ESCAPE" and army.moving_to[0] == hotter
			and army._committed_intent_order(member) == army.FIRE_HAZARD_STEP and army._cell_owners.get(source,-1) == 0
			and army._reserved_cells.get(hotter,-1) == 0,
			"FM04/AT03 original weighted A* and Grid commit the unavoidable HIGHER-risk first step",entry): return false
		var first_route: Array = entry.route.duplicate()
		var reached_hotter := false
		var committed_exit := false
		for tick in range(90):
			_tick(f)
			if army.cells[0] == hotter: reached_hotter = true
			if army.cells[0] == hotter and army.moving_to[0] == exit_cell:
				committed_exit = army._reserved_cells.get(exit_cell,-1) == 0 and army._committed_intent_order(member) == army.FIRE_HAZARD_STEP
			if army.cells[0] == exit_cell and army.moving_to[0] == TerrainArmy.INVALID_CELL: break
		if not _check(reached_hotter and committed_exit and army.cells[0] == exit_cell
			and army.moving_to[0] == TerrainArmy.INVALID_CELL and army._reserved_cells.is_empty()
			and army.combat_order == TerrainArmy.CombatOrder.HOLD,
			"Real emergency movement completes both edges and physically arrives at the cold endpoint"):
			return false
		evidence.fm04_escape = {"route":first_route,"higher_first_step":hotter,"arrived":army.cells[0],
			"actual_higher_arrival":reached_hotter,"actual_exit_commit":committed_exit}
	if not _check(army.get_order_serial() == serial and army.ranged_order_serial == ranged_serial,
		"Corridor navigation preserves original main and ranged generations"): return false
	_close(f)
	return true

func _run() -> void:
	if not _debounce_reignite(): _finish(false,"FM10 actual cool/reignite/debounce/recovery"); return
	if not _corridor(false): _finish(false,"FM04 actual higher-risk emergency first step"); return
	if not _corridor(true): _finish(false,"FM04 NORMAL no-safe-route distinction"); return
	_finish(true)
