extends SceneTree
## A capped search spends its expanded nodes, even when no route is returned.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Budget = preload("res://scripts/terrain_lab/site_route_budget.gd")
const Profile = preload("res://scripts/terrain_lab/formation_movement_profile.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var terrain := Helper.build_flat_map(70, 70)
	var armies: Array[TerrainArmy] = []
	for team in range(2):
		var army := Helper.create_test_army(terrain, team + 1, team, 16, Vector2i(4 + team * 20, 4))
		army.formation_runtime_id = team + 1
		army._formation_movement_profile = Profile.default_infantry()
		army._combat_move_plan = CombatMovePlan.new()
		army._combat_move_plan.current_width = 4
		army.combat_order = TerrainArmy.CombatOrder.MOVE
		army.combat_profile_enabled = true
		var mids: Array[int] = army._get_active_member_ids()
		for i in range(mids.size()):
			var goal := Vector2i(35 + i % 4, 40 + int(i / 4))
			terrain.static_blocked[terrain.index(goal)] = 1
			army.combat_slots[army.index_for_identity(mids[i])] = goal
			army._combat_move_plan.member_sequence_rank[mids[i]] = i
		armies.append(army)
	var budget := Budget.new()
	budget.begin_tick([armies[0], armies[1]])
	var actual_total := 0
	var records: Array[Dictionary] = []
	for army in armies:
		army._refresh_member_route_caches(budget)
		var fid := army.try_get_formation_id()
		var allocation: Dictionary = budget.get_allocation(fid)
		var actual: int = army.expanded_nodes
		var billed: int = int(allocation.get("expansions_used", -1))
		var calls: int = int(allocation.get("calls_used", -1))
		var pools: Dictionary = army.profiled_scheduler_metrics
		print("ACTUAL_ROUTE_BUDGET team=", fid, " actual=", actual, " billed=", billed,
			" calls=", calls, " capped=", army.profiled_search_cap_failures,
			" rear_calls=", pools.get("pass1_rear_calls", 0), " front_calls=", pools.get("pass2_front_calls", 0))
		actual_total += actual
		records.append({"actual": actual, "billed": billed, "calls": calls,
			"capped": army.profiled_search_cap_failures,
			"rear_calls": int(pools.get("pass1_rear_calls", 0)),
			"front_calls": int(pools.get("pass2_front_calls", 0))})
	print("ACTUAL_ROUTE_BUDGET site_actual=", actual_total,
		" site_billed=", budget.site_expansions_used, " site_calls=", budget.site_calls_used)
	for record in records:
		if not _require(int(record.capped) >= 2 and int(record.actual) >= 512,
			"Fixture must exercise multiple 256-node capped empty routes"): return
		if not _require(int(record.calls) <= Budget.MAX_LOCAL_ROUTE_CALLS_PER_FORMATION_TICK
				and int(record.rear_calls) >= 1 and int(record.front_calls) >= 1,
			"The existing eight-call ceiling and rear/front pool guarantee must remain intact"): return
		if not _require(int(record.billed) == int(record.actual),
			"Formation budget must charge actual expanded nodes; a capped empty route costs 256, not 32"): return
		if not _require(int(record.actual) <= Budget.MAX_LOCAL_EXPANSIONS_PER_FORMATION_TICK,
			"Formation search must stay within its actual 1024-node tick budget"): return
	if not _require(budget.site_expansions_used == actual_total
			and budget.site_expansions_used <= Budget.SITE_MAX_EXPANSIONS_PER_TICK,
		"Site budget must equal actual expanded nodes across both formations"): return
	print("COMBAT MOVEMENT ROUTE BUDGET ACTUAL EXPANSIONS PASS")
	for army in armies:
		army.free()
	quit(0)

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false
