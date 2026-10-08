extends SceneTree
## Simultaneous 2x100 open-field and 3x100 split-route MOVE on one coordinator.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const STEP := 0.05
const MAX_TICKS := 2400
const WALL_LIMIT_MS := 150000

var _armies: Array[TerrainArmy] = []
var _coordinator: SiteCombatMovementCoordinator = null

func _initialize() -> void:
	call_deferred("_run")

func _dispose() -> void:
	for army in _armies:
		if is_instance_valid(army):
			if _coordinator != null:
				_coordinator.unregister_formation(army)
			army.free()
	_armies.clear()
	_coordinator = null

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	_dispose()
	quit(1)
	return false

func _status(label: String, tick: int) -> String:
	var teams: Array[String] = []
	for army in _armies:
		var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
		var move: CombatMovePlan = army.get_active_move_plan()
		var unresolved: Array[String] = []
		if plan != null:
			for identity: int in plan.member_slot_map.keys():
				var index := army.index_for_identity(identity)
				if index >= 0 and army.cells[index] != plan.get_slot_for_member(identity):
					unresolved.append("%d:%s>%s" % [identity, army.cells[index], plan.get_slot_for_member(identity)])
					if unresolved.size() >= 8:
						break
		teams.append("%d:%s accepted=%d settled=%d/%d phase=%d cursor=%d unresolved=%s" % [army.team_id, army.command_status, army.accepted_count,
			plan.settled_platform_member_ids.size() + plan.settled_queue_member_ids.size() if plan != null else -1,
			plan.member_slot_map.size() if plan != null else -1,
			move.phase if move != null else -1, move.macro_cursor if move != null else -1, str(unresolved)])
	return "%s tick=%d %s" % [label, tick, " | ".join(teams)]

func _build_map(split_routes: bool) -> TerrainData:
	var data: TerrainData = Helper.build_flat_map(70, 106 if split_routes else 70)
	if split_routes:
		for wall_y in [35, 70]:
			for x in range(data.size.x):
				var index := data.index(Vector2i(x, wall_y))
				data.flags[index] = 0
				data.static_blocked[index] = 1
		data.navigation_revision += 1
	return data

func _reverse_edge_probe(army: TerrainArmy, plan: CombatDeploymentPlan, mid: int, include_unsettled: bool) -> String:
	var index := army.index_for_identity(mid)
	if index < 0:
		return "absent"
	var start: Vector2i = army.cells[index]
	var vacancy: Vector2i = plan.get_slot_for_member(mid)
	var occupied: Dictionary = {}
	for i in range(100):
		occupied[army.cells[i]] = army.combat_identity(i)
	if occupied.has(vacancy):
		return "occupied"
	var min_x := start.x
	var max_x := start.x
	var min_y := start.y
	var max_y := start.y
	for slot in plan.platform_slots:
		min_x = mini(min_x, slot.x)
		max_x = maxi(max_x, slot.x)
		min_y = mini(min_y, slot.y)
		max_y = maxi(max_y, slot.y)
	var reachable: Dictionary = {start: true}
	var free_distance: Dictionary = {start: 0}
	var free_frontier: Array[Vector2i] = [start]
	while not free_frontier.is_empty() and reachable.size() <= 512:
		var cell: Vector2i = free_frontier.pop_front()
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = cell + direction
			if reachable.has(next) or occupied.has(next) or next.x < min_x - 4 or next.x > max_x + 4 or next.y < min_y - 4 or next.y > max_y + 4 or not army.data.contains(next) or not army.data.can_step(cell, next):
				continue
			reachable[next] = true
			free_distance[next] = int(free_distance[cell]) + 1
			free_frontier.append(next)
	var movable: Dictionary = {}
	for actor in plan.admitted_platform_member_ids:
		var actor_index := army.index_for_identity(actor)
		if actor_index < 0 or (not include_unsettled and not plan.settled_platform_member_ids.has(actor)):
			continue
		var actor_cell: Vector2i = army.cells[actor_index]
		if plan.slot_owner_map.has(actor_cell) and actor_cell == plan.get_slot_for_member(actor) and int(plan.slot_tactical_roles.get(actor_cell, 0)) == 0 and not army.get_active_move_plan().member_pending_proposal_id.has(actor):
			movable[actor_cell] = actor
	var seen: Dictionary = {vacancy: true}
	var frontier: Array[Vector2i] = [vacancy]
	var edge := false
	while not frontier.is_empty() and seen.size() <= 128:
		var cell: Vector2i = frontier.pop_front()
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var blocker: Vector2i = cell + direction
			if seen.has(blocker) or not movable.has(blocker) or not army.data.can_step(blocker, cell):
				continue
			seen[blocker] = true
			frontier.append(blocker)
			for free_direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if reachable.has(blocker + free_direction) and army.data.can_step(blocker + free_direction, blocker):
					edge = true
	return "free=%d distance=%d capped=%s actors=%d chain=%d edge=%s" % [reachable.size(), int(free_distance.get(vacancy, -1)), str(reachable.size() > 512), movable.size(), seen.size(), str(edge)]

func _print_cross_team_diagnostics(label: String, tick: int) -> void:
	var physical_owner: Dictionary = {}
	for army in _armies:
		for index in range(100):
			physical_owner[army.cells[index]] = [army.team_id, army.combat_identity(index)]
	var diagnostics: Array[String] = []
	for army in _armies:
		var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
		var move: CombatMovePlan = army.get_active_move_plan()
		if plan == null:
			continue
		var min_x := 999999
		var max_x := -999999
		var min_y := 999999
		var max_y := -999999
		var foreign_on_final := 0
		var foreign_locked_on_final := 0
		var locked := 0
		var waiting := 0
		var nearest_entry := 999999
		var vacant_final := 0
		var broad_eligible := 0
		var broad_seed := 0
		var unfinished: Array[String] = []
		var own_occupants: Dictionary = {}
		for index in range(100):
			own_occupants[army.cells[index]] = army.combat_identity(index)
		for slot in plan.platform_slots:
			min_x = mini(min_x, slot.x)
			max_x = maxi(max_x, slot.x)
			min_y = mini(min_y, slot.y)
			max_y = maxi(max_y, slot.y)
			nearest_entry = mini(nearest_entry, absi(slot.x - plan.ingress_cell.x) + absi(slot.y - plan.ingress_cell.y))
			if not own_occupants.has(slot):
				vacant_final += 1
			if physical_owner.has(slot):
				var holder: Array = physical_owner[slot]
				if int(holder[0]) != army.team_id:
					foreign_on_final += 1
					for other in _armies:
						if other.team_id == int(holder[0]) and other.get_active_deployment_plan() != null and other.get_active_deployment_plan().is_slot_locked(int(holder[1])):
							foreign_locked_on_final += 1
		for mid in plan.member_slot_map.keys():
			if plan.is_slot_locked(mid):
				locked += 1
			if move != null and move.member_entry_hold.has(mid):
				waiting += 1
		for mid in plan.admitted_platform_member_ids:
			if plan.is_slot_locked(mid):
				continue
			var index := army.index_for_identity(mid)
			if index < 0:
				continue
			var cell: Vector2i = army.cells[index]
			var final: Vector2i = plan.get_slot_for_member(mid)
			if unfinished.size() < 6:
				unfinished.append("%d:%s>%s retry%d prop=%s" % [mid, cell, final, int(move.member_route_retry_count.get(mid, 0)), str(move.member_pending_proposal_id.has(mid))])
			if move.member_pending_proposal_id.has(mid) or own_occupants.has(final) or int(plan.slot_tactical_roles.get(final, 0)) != 0:
				continue
			broad_eligible += 1
			for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var neighbor: Vector2i = cell + direction
				if own_occupants.has(neighbor) and plan.slot_owner_map.has(neighbor):
					broad_seed += 1
					break
		diagnostics.append("%d bbox=(%d..%d,%d..%d) ingress=%s nearest=%d vacant=%d broad=%d/%d foreign_final=%d foreign_locked=%d own_locked=%d waiting=%d pending=%d unfinished=%s" % [army.team_id, min_x, max_x, min_y, max_y, plan.ingress_cell, nearest_entry, vacant_final, broad_eligible, broad_seed, foreign_on_final, foreign_locked_on_final, locked, waiting, plan.pending_platform_member_ids.size(), str(unfinished)])
		if tick >= 1000 and army.team_id == 1:
			var late: Array[String] = []
			for mid in [1156, 1145, 1165, 1127]:
				var index := army.index_for_identity(mid)
				if index < 0 or not plan.member_slot_map.has(mid):
					continue
				var cell: Vector2i = army.cells[index]
				var final: Vector2i = plan.get_slot_for_member(mid)
				var target: Dictionary = Destination.resolve_member_target(move, plan, mid, cell)
				late.append("%d:%s>%s occupied=%s role=%d kind=%s target=%s route=%d status=%d moving=%s prop=%s hold=%s" % [mid, cell, final, str(physical_owner.get(final, [])), int(plan.slot_tactical_roles.get(final, 0)), str(target.get("kind", "")), str(target.get("target", cell)), move.member_paths.get(mid, []).size(), int(move.member_route_status.get(mid, -1)), army.moving_to[index], str(move.member_pending_proposal_id.has(mid)), str(move.member_recovery_hold.has(mid))])
			print("MULTI_TEAM_LATE tick=", tick, " epoch=", plan.assignment_epoch, " chain=", move.active_vacancy_chain_actors, " chain_last=", move.vacancy_chain_last_progress_sec, " platform_progress=", move.last_platform_progress_time_sec, " ", " | ".join(late))
			if tick >= 1600:
				print("MULTI_TEAM_REVERSE_EDGE tick=", tick, " 1156 settled_only=", _reverse_edge_probe(army, plan, 1156, false), " own_final_admitted=", _reverse_edge_probe(army, plan, 1156, true))
				var isolated_order: Array[String] = []
				for candidate in plan.admitted_platform_member_ids:
					if plan.is_slot_locked(candidate) or not plan.member_slot_map.has(candidate):
						continue
					var slot: Vector2i = plan.get_slot_for_member(candidate)
					if own_occupants.has(slot):
						continue
					var probe := _reverse_edge_probe(army, plan, candidate, false)
					if not probe.ends_with("edge=true"):
						continue
					isolated_order.append("%d prop=%s hold=%s retry=%d" % [candidate, str(move.member_pending_proposal_id.has(candidate)), str(move.member_recovery_hold.has(candidate)), int(move.member_route_retry_count.get(candidate, 0))])
					if isolated_order.size() >= 8:
						break
				print("MULTI_TEAM_ISOLATED_ORDER tick=", tick, " time=", move.planning_time_sec, " next=", move.next_platform_recovery_time_sec, " held=", move.member_recovery_hold.keys(), " first=", isolated_order)
	print("MULTI_TEAM_CROSS_FINAL ", label, " tick=", tick, " ", " | ".join(diagnostics))

func _print_commander_tail(tick: int) -> void:
	var physical_owner: Dictionary = {}
	for army in _armies:
		for index in range(100):
			physical_owner[army.cells[index]] = [army.team_id, army.combat_identity(index)]
	for army in _armies:
		if army.team_id < 2:
			continue
		var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
		var move: CombatMovePlan = army.get_active_move_plan()
		if plan == null or move == null:
			continue
		var commander: int = army.combat_identity(army.current_commander)
		var index: int = army.index_for_identity(commander)
		if index < 0 or not plan.member_slot_map.has(commander):
			continue
		var cell: Vector2i = army.cells[index]
		var final_slot: Vector2i = plan.get_slot_for_member(commander)
		var target: Dictionary = Destination.resolve_member_target(move, plan, commander, cell)
		var route: Array = move.member_paths.get(commander, [])
		var next_step: Vector2i = route[1] if route.size() > 1 else TerrainArmy.INVALID_CELL
		var neighbors: Array[String] = []
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var neighbor: Vector2i = final_slot + direction
			var owner: Array = physical_owner.get(neighbor, [])
			neighbors.append("%s:step=%s owner=%s locked=%s" % [neighbor, str(army.data.contains(neighbor) and army.data.can_step(neighbor, final_slot)), str(owner), str(plan.is_slot_locked(int(owner[1]))) if owner.size() == 2 and int(owner[0]) == army.team_id else "-"])
		print("MULTI_TEAM_COMMANDER_TARGET tick=", tick, " team=", army.team_id, " cell=", cell, " final=", final_slot, " target=", target.get("target", cell), " kind=", target.get("kind", ""), " reason=", target.get("wait_reason", ""), " route_status=", int(move.member_route_status.get(commander, -1)), " route_size=", route.size(), " next=", next_step, " moving=", army.moving_to[index], " final_owner=", physical_owner.get(final_slot, []), " final_locked=", plan.is_slot_locked(commander), " neighbors=", neighbors)

func _print_team_one_pending(tick: int) -> void:
	if _armies.is_empty():
		return
	var army: TerrainArmy = _armies[0]
	var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
	var move: CombatMovePlan = army.get_active_move_plan()
	if plan == null or move == null:
		return
	var current_cells: Dictionary = army.get_active_members_occupancy()
	var pending: Array[String] = []
	for mid in plan.pending_platform_member_ids:
		var cell: Vector2i = current_cells.get(mid, TerrainArmy.INVALID_CELL)
		var slot: Vector2i = plan.get_slot_for_member(mid)
		pending.append("%d cell=%s ever=%s beyond=%s slot=%s role=%d locked=%s" % [mid, cell, str(plan.ever_admitted_platform_member_ids.has(mid)), str(Destination._is_prior_platform_entrant_beyond_handoff(plan, mid, current_cells)), slot, int(plan.slot_tactical_roles.get(slot, 0)), str(plan.is_slot_locked(mid))])
	var commander: int = army.combat_identity(army.current_commander)
	var commander_cell: Vector2i = current_cells.get(commander, TerrainArmy.INVALID_CELL)
	var commander_target: Dictionary = Destination.resolve_member_target(move, plan, commander, commander_cell)
	var compact_reject: Array[String] = []
	if plan.approach_bottlenecked != 0:
		compact_reject.append("bottleneck")
	if plan.platform_slots.size() < 20:
		compact_reject.append("capacity")
	if plan.settled_platform_member_ids.size() * 5 < plan.platform_slots.size() * 3:
		compact_reject.append("settled_threshold")
	if Destination._never_crossed_platform_count(plan, current_cells) > 1:
		compact_reject.append("never_crossed")
	print("MULTI_TEAM_TEAM1_PENDING tick=", tick, " pending=", pending, " bottlenecked=", plan.approach_bottlenecked, " last_choke=", plan.approach_last_bottleneck_cell, " compact_gate_reject=", compact_reject, " commander=", commander, " cell=", commander_cell, " target=", commander_target.get("target", commander_cell), " kind=", commander_target.get("kind", ""), " reason=", commander_target.get("wait_reason", ""))
	if tick >= 1200 and plan.member_slot_map.has(1146) and current_cells.has(1146):
		_print_team_one_exterior_probe(tick, army, plan, move, current_cells, 1146)

func _print_team_one_chain_stall(tick: int) -> void:
	if _armies.is_empty():
		return
	var army: TerrainArmy = _armies[0]
	var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
	var move: CombatMovePlan = army.get_active_move_plan()
	if plan == null or move == null:
		return
	var current_cells: Dictionary = army.get_active_members_occupancy()
	var actors: Array[String] = []
	var physically_arrived := 0
	for mid in move.active_vacancy_chain_actors:
		var cell: Vector2i = current_cells.get(mid, TerrainArmy.INVALID_CELL)
		var target: Vector2i = plan.get_slot_for_member(mid)
		if cell == target:
			physically_arrived += 1
		var index: int = army.index_for_identity(mid)
		var moving: Vector2i = army.moving_to[index] if index >= 0 else TerrainArmy.INVALID_CELL
		actors.append("%d:%s>%s move=%s proposal=%s" % [mid, cell, target, moving, str(move.member_pending_proposal_id.has(mid))])
	print("MULTI_TEAM_CHAIN_STALL tick=", tick, " time=", move.planning_time_sec, " stall=", move.active_stall_total_sec, " settled=", plan.settled_platform_member_ids.size(), " settled_highwater=", move.platform_settled_highwater, " recovery_previous=", move.previous_platform_settled, " chain_start=", move.vacancy_chain_started_sec, " chain_last=", move.vacancy_chain_last_progress_sec, " chain_arrived_recorded=", move.vacancy_chain_arrived_count, " chain_arrived_physical=", physically_arrived, " chain_actors=", actors, " accepted=", army.accepted_count)

func _print_team_one_exterior_probe(tick: int, army: TerrainArmy, plan: CombatDeploymentPlan, move: CombatMovePlan, current_cells: Dictionary, a: int) -> void:
	var ca: Vector2i = current_cells[a]
	var sa: Vector2i = plan.get_slot_for_member(a)
	var occupied: Dictionary = {}
	for cell in current_cells.values():
		occupied[cell] = true
	var lane: Dictionary = {}
	for cell in move.macro_path:
		if plan.platform_footprint.has(cell):
			lane[cell] = true
	var min_x := 2147483647
	var max_x := -2147483647
	var min_y := 2147483647
	var max_y := -2147483647
	for slot in plan.platform_slots:
		min_x = mini(min_x, slot.x)
		max_x = maxi(max_x, slot.x)
		min_y = mini(min_y, slot.y)
		max_y = maxi(max_y, slot.y)
	var free_cells: Dictionary = {}
	for x in range(mini(min_x, ca.x) - 4, maxi(max_x, ca.x) + 5):
		for y in range(mini(min_y, ca.y) - 4, maxi(max_y, ca.y) + 5):
			var cell := Vector2i(x, y)
			if army.data.contains(cell) and army.data.is_walkable(cell) and not occupied.has(cell):
				free_cells[cell] = true
	free_cells[ca] = true
	var own_free_steps: int = Destination._platform_distance(ca, sa, army.data, free_cells, 512)
	var terrain_only: Dictionary = {}
	for x in range(mini(min_x, ca.x) - 4, maxi(max_x, ca.x) + 5):
		for y in range(mini(min_y, ca.y) - 4, maxi(max_y, ca.y) + 5):
			var terrain_cell := Vector2i(x, y)
			if army.data.contains(terrain_cell) and army.data.is_walkable(terrain_cell):
				terrain_only[terrain_cell] = true
	var current_static_steps: int = Destination._platform_distance(ca, sa, army.data, terrain_only, 512)
	var nearer_waypoints: Array[String] = []
	for waypoint in plan.platform_footprint:
		if waypoint.x < 35 or waypoint.x > 40 or waypoint.y < 13 or waypoint.y > 18 or occupied.has(waypoint) or plan.slot_owner_map.has(waypoint) or plan.slot_lease_timers.has(waypoint) or lane.has(waypoint):
			continue
		var free_steps: int = Destination._platform_distance(ca, waypoint, army.data, free_cells, 512)
		var final_steps: int = Destination._platform_distance(waypoint, sa, army.data, terrain_only, 512)
		if free_steps >= 0 and final_steps >= 0 and final_steps < current_static_steps:
			nearer_waypoints.append("%s free=%d final_static=%d" % [waypoint, free_steps, final_steps])
	var occupied_by: Dictionary = {}
	for mid in current_cells.keys():
		occupied_by[current_cells[mid]] = mid
	var own_physical_owner: int = int(occupied_by.get(sa, -1))
	var own_owner_slot: Vector2i = plan.get_slot_for_member(own_physical_owner) if own_physical_owner >= 0 else TerrainArmy.INVALID_CELL
	var occupant_chain: Array[String] = []
	var visited_occupants: Dictionary = {}
	var chain_slot: Vector2i = sa
	for chain_index in range(8):
		var chain_mid: int = int(occupied_by.get(chain_slot, -1))
		if chain_mid < 0:
			occupant_chain.append("free:%s" % chain_slot)
			break
		if visited_occupants.has(chain_mid):
			occupant_chain.append("cycle:%d@%s" % [chain_mid, chain_slot])
			break
		visited_occupants[chain_mid] = true
		var next_slot: Vector2i = plan.get_slot_for_member(chain_mid)
		occupant_chain.append("%d:%s>%s role=%d locked=%s proposal=%s" % [chain_mid, chain_slot, next_slot, int(plan.slot_tactical_roles.get(next_slot, -1)), str(plan.is_slot_locked(chain_mid)), str(move.member_pending_proposal_id.has(chain_mid))])
		chain_slot = next_slot
	var vacant_flex: Array[String] = []
	for vacant_slot in plan.platform_slots:
		if occupied.has(vacant_slot) or int(plan.slot_tactical_roles.get(vacant_slot, -1)) != Types.TacticalSlotRole.FLEX:
			continue
		var owner: int = int(plan.slot_owner_map.get(vacant_slot, -1))
		var owner_cell: Vector2i = current_cells.get(owner, TerrainArmy.INVALID_CELL)
		var owner_free: Dictionary = free_cells.duplicate()
		owner_free[owner_cell] = true
		owner_free[sa] = true
		var owner_steps: int = Destination._platform_distance(owner_cell, sa, army.data, owner_free, 512) if owner_cell != TerrainArmy.INVALID_CELL else -1
		vacant_flex.append("%s owner=%d at=%s locked=%s a_steps=%d owner_to_old=%d" % [vacant_slot, owner, owner_cell, str(plan.is_slot_locked(owner)), Destination._platform_distance(ca, vacant_slot, army.data, free_cells, 512), owner_steps])
	var free_first_steps: Array[String] = []
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var neighbor: Vector2i = ca + direction
		free_first_steps.append("%s:free=%s step=%s occupied=%s" % [neighbor, str(free_cells.has(neighbor)), str(army.data.contains(neighbor) and army.data.can_step(ca, neighbor)), str(occupied.has(neighbor))])
	var compact_reject: Array[String] = []
	var never_crossed: Array[String] = []
	for pending_mid in plan.pending_platform_member_ids:
		if not Destination._is_prior_platform_entrant_beyond_handoff(plan, pending_mid, current_cells):
			var pending_slot: Vector2i = plan.get_slot_for_member(pending_mid)
			never_crossed.append("%d:%s role=%d" % [pending_mid, str(current_cells.get(pending_mid, TerrainArmy.INVALID_CELL)), int(plan.slot_tactical_roles.get(pending_slot, -1))])
	if plan.approach_bottlenecked != 0:
		compact_reject.append("bottleneck")
	if plan.platform_slots.size() < 20:
		compact_reject.append("capacity")
	if plan.settled_platform_member_ids.size() * 5 < plan.platform_slots.size() * 3:
		compact_reject.append("settled_threshold")
	if Destination._never_crossed_platform_count(plan, current_cells) > 1:
		compact_reject.append("never_crossed")
	if plan.platform_footprint.has(ca):
		compact_reject.append("still_inside")
	if ca.x < min_x - 12 or ca.x > max_x + 12 or ca.y < min_y - 12 or ca.y > max_y + 12:
		compact_reject.append("outside_apron")
	if occupied.has(sa):
		compact_reject.append("own_final_occupied")
	if lane.has(sa):
		compact_reject.append("own_final_entry_lane")
	if int(plan.slot_tactical_roles.get(sa, -1)) != Types.TacticalSlotRole.FLEX:
		compact_reject.append("own_final_role")
	if int(move.member_route_retry_count.get(a, 0)) < 3:
		compact_reject.append("retry_below_three")
	var counters: Dictionary = {"owners": 0, "vacant": 0, "gain": 0, "a_route": 0, "both_route": 0}
	var examples: Array[String] = []
	for b in plan.admitted_platform_member_ids:
		if a == b or not current_cells.has(b) or plan.is_slot_locked(b) or move.member_pending_proposal_id.has(b) or move.planning_time_sec < float(move.member_swap_cooldown_until_sec.get(b, 0.0)):
			continue
		counters.owners += 1
		var sb: Vector2i = plan.get_slot_for_member(b)
		if occupied.has(sb) or lane.has(sb) or int(plan.slot_tactical_roles.get(sb, 0)) != 0:
			continue
		counters.vacant += 1
		var cb: Vector2i = current_cells[b]
		var old_cost: int = absi(ca.x - sa.x) + absi(ca.y - sa.y) + absi(cb.x - sb.x) + absi(cb.y - sb.y)
		var new_cost: int = absi(ca.x - sb.x) + absi(ca.y - sb.y) + absi(cb.x - sa.x) + absi(cb.y - sa.y)
		var gain: int = old_cost - new_cost
		if gain < 4:
			continue
		counters.gain += 1
		free_cells[cb] = true
		var a_steps: int = Destination._platform_distance(ca, sb, army.data, free_cells, 512)
		var b_steps: int = Destination._platform_distance(cb, sa, army.data, free_cells, 512) if a_steps >= 0 else -1
		free_cells.erase(cb)
		if a_steps >= 0:
			counters.a_route += 1
		if b_steps >= 0:
			counters.both_route += 1
		if examples.size() < 5:
			examples.append("%d %s>%s gain=%d routes=%d/%d" % [b, cb, sb, gain, a_steps, b_steps])
	print("MULTI_TEAM_EXTERIOR_PROBE tick=", tick, " a=", a, " cell=", ca, " slot=", sa, " pending=", plan.pending_platform_member_ids.has(a), " ever=", plan.ever_admitted_platform_member_ids.has(a), " beyond=", Destination._is_prior_platform_entrant_beyond_handoff(plan, a, current_cells), " never_crossed=", never_crossed, " locked=", plan.is_slot_locked(a), " proposal=", move.member_pending_proposal_id.has(a), " moving=", army.moving_to[army.index_for_identity(a)], " retry=", move.member_route_retry_count.get(a, 0), " cooldown=", move.member_swap_cooldown_until_sec.get(a, 0.0), " own_free_steps=", own_free_steps, " current_static_steps=", current_static_steps, " nearer_nonfinal=", nearer_waypoints.slice(0, 24), " own_physical_owner=", own_physical_owner, " owner_slot=", own_owner_slot, " occupant_chain=", occupant_chain, " free_first_steps=", free_first_steps, " vacant_flex=", vacant_flex.slice(0, 16), " compact_reject=", compact_reject, " old_occupied=", occupied.has(sa), " old_lane=", lane.has(sa), " old_role=", plan.slot_tactical_roles.get(sa, -1), " chain=", move.active_vacancy_chain_actors.size(), " recovery_ready=", move.planning_time_sec - move.last_platform_progress_time_sec >= 1.75 and move.planning_time_sec >= move.next_platform_recovery_time_sec, " reverse_edge=", _reverse_edge_probe(army, plan, a, false), " isolated_chain=", _probe_isolated_chain(army, plan, move, current_cells, a), " counts=", counters, " examples=", examples)

func _probe_isolated_chain(army: TerrainArmy, plan: CombatDeploymentPlan, move: CombatMovePlan, current_cells: Dictionary, waiting: int) -> String:
	var start: Vector2i = current_cells[waiting]
	var vacancy: Vector2i = plan.get_slot_for_member(waiting)
	var occupied: Dictionary = {}
	for cell in current_cells.values():
		occupied[cell] = true
	if occupied.has(vacancy):
		return "occupied"
	var min_x: int = start.x
	var max_x: int = start.x
	var min_y: int = start.y
	var max_y: int = start.y
	for slot in plan.platform_slots:
		min_x = mini(min_x, slot.x)
		max_x = maxi(max_x, slot.x)
		min_y = mini(min_y, slot.y)
		max_y = maxi(max_y, slot.y)
	var reachable: Dictionary = {start: true}
	var free_distance: Dictionary = {start: 0}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty() and reachable.size() <= 512:
		var cell: Vector2i = frontier.pop_front()
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = cell + direction
			if reachable.has(next) or occupied.has(next) or next.x < min_x - 4 or next.x > max_x + 4 or next.y < min_y - 4 or next.y > max_y + 4 or not army.data.contains(next) or not army.data.can_step(cell, next):
				continue
			reachable[next] = true
			free_distance[next] = int(free_distance[cell]) + 1
			frontier.append(next)
	var movable: Dictionary = {}
	for mid in plan.settled_platform_member_ids:
		if not current_cells.has(mid) or move.member_pending_proposal_id.has(mid):
			continue
		var cell: Vector2i = current_cells[mid]
		if cell == plan.get_slot_for_member(mid) and int(plan.slot_tactical_roles.get(cell, -1)) == 0:
			movable[cell] = mid
	var predecessor: Dictionary = {vacancy: vacancy}
	var depth: Dictionary = {vacancy: 0}
	var vacancy_frontier: Array[Vector2i] = [vacancy]
	var best: String = "none"
	var best_free_distance := 999999
	var edge_count := 0
	var valid_count := 0
	var shortest_valid := 999999
	while not vacancy_frontier.is_empty() and predecessor.size() <= 128:
		var opening: Vector2i = vacancy_frontier.pop_front()
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var blocker: Vector2i = opening + direction
			if predecessor.has(blocker) or not movable.has(blocker) or not army.data.can_step(blocker, opening):
				continue
			predecessor[blocker] = opening
			depth[blocker] = int(depth[opening]) + 1
			for free_direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var adjacent: Vector2i = blocker + free_direction
				if not reachable.has(adjacent) or not army.data.can_step(adjacent, blocker):
					continue
				edge_count += 1
				var owner_inflight := false
				var reverse := false
				var chain_cell: Vector2i = blocker
				while chain_cell != vacancy:
					var next_cell: Vector2i = predecessor[chain_cell]
					var actor: int = int(movable[chain_cell])
					if move.member_pending_proposal_id.has(int(plan.slot_owner_map[next_cell])):
						owner_inflight = true
					if move.member_recovery_vacated_cell.get(actor, TerrainArmy.INVALID_CELL) == next_cell:
						reverse = true
					chain_cell = next_cell
				var distance: int = int(free_distance[adjacent])
				if distance < best_free_distance:
					best_free_distance = distance
					best = "edge=%s free=%d depth=%d owner_flight=%s reverse=%s" % [blocker, distance, int(depth[blocker]), str(owner_inflight), str(reverse)]
				if not owner_inflight and not reverse:
					valid_count += 1
					shortest_valid = mini(shortest_valid, distance + int(depth[blocker]))
			if int(depth[blocker]) < 32:
				vacancy_frontier.append(blocker)
	return "free=%d direct=%d movable=%d edges=%d valid=%d shortest_valid=%d chosen=%s" % [reachable.size(), int(free_distance.get(vacancy, -1)), movable.size(), edge_count, valid_count, shortest_valid if valid_count > 0 else -1, best]

func _check_world(data: TerrainData, previous: Dictionary, label: String, tick: int) -> bool:
	var source_owners: Dictionary = {}
	var destination_claims: Dictionary = {}
	for army in _armies:
		for index in range(100):
			var identity := army.combat_identity(index)
			var cell: Vector2i = army.cells[index]
			if not data.is_walkable(cell) or source_owners.has(cell):
				return _require(false, _status(label, tick) + " duplicate or illegal source " + str(cell))
			if cell != previous[identity] and not data.can_step(previous[identity], cell):
				return _require(false, _status(label, tick) + " skipped edge for " + str(identity))
			previous[identity] = cell
			source_owners[cell] = identity
			var target: Vector2i = army.moving_to[index]
			if target != TerrainArmy.INVALID_CELL:
				if not data.can_step(cell, target) or destination_claims.has(target):
					return _require(false, _status(label, tick) + " duplicate or illegal claim " + str(target))
				destination_claims[target] = identity
	if source_owners.size() != 100 * _armies.size():
		return _require(false, _status(label, tick) + " source count changed")
	for cell: Vector2i in source_owners.keys():
		if _coordinator._current_occupancy.get(cell, -1) != source_owners[cell]:
			return _require(false, _status(label, tick) + " coordinator source owner disagrees at " + str(cell))
	return true

func _check_leases(label: String, tick: int) -> bool:
	var all_slots: Dictionary = {}
	for army in _armies:
		var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
		if not _require(plan != null, _status(label, tick) + " lost its deployment plan"): return false
		var leases: Array[Vector2i] = _coordinator.deployment_registry.get_formation_reserved_slots(army.team_id)
		if not _require(leases.size() == 100, _status(label, tick) + " lost a final lease"): return false
		for slot in leases:
			if all_slots.has(slot):
				return _require(false, _status(label, tick) + " cross-team final lease overlap at " + str(slot))
			all_slots[slot] = true
			var lease = _coordinator.deployment_registry.owner_of(slot)
			if lease == null or lease.formation_id != army.team_id or lease.order_serial != plan.order_serial:
				return _require(false, _status(label, tick) + " wrong lease owner at " + str(slot))
	if all_slots.size() != 100 * _armies.size() or _coordinator.deployment_registry.slot_owners.size() != all_slots.size():
		return _require(false, _status(label, tick) + " global lease count differs")
	return true

func _check_compact_final_regions(label: String) -> bool:
	var previous_max_y := -1
	for army in _armies:
		var slots: Array[Vector2i] = army.get_active_deployment_plan().platform_slots
		var min_x := 999999
		var max_x := -999999
		var min_y := 999999
		var max_y := -999999
		for slot in slots:
			min_x = mini(min_x, slot.x)
			max_x = maxi(max_x, slot.x)
			min_y = mini(min_y, slot.y)
			max_y = maxi(max_y, slot.y)
		if not _require(slots.size() == 100 and max_x - min_x <= 10 and max_y - min_y <= 10, label + " open final formation must fit an 11x11 anchor-centered region; team=" + str(army.team_id) + " bbox=" + str(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))): return false
		if not _require(min_y > previous_max_y, label + " adjacent teams' final regions interleave; team=" + str(army.team_id) + " min_y=" + str(min_y) + " previous_max_y=" + str(previous_max_y)): return false
		previous_max_y = max_y
	return true

func _run_case(split_routes: bool, single_team: bool = false) -> bool:
	var label := "1x100 open control" if single_team else ("3x100 split" if split_routes else "2x100 open")
	var three_team_only := OS.get_cmdline_user_args().has("--three-team")
	var data := _build_map(split_routes)
	var origin_rows: Array[int] = [9, 44, 79]
	var goal_rows: Array[int] = [16, 51, 86]
	if single_team:
		origin_rows.assign([12])
		goal_rows.assign([17])
	elif not split_routes:
		origin_rows.assign([12, 32])
		goal_rows.assign([17, 37])
	_coordinator = Coordinator.new()
	for team_index in range(origin_rows.size()):
		var army := Helper.create_test_army(data, team_index + 1, team_index, 100, Vector2i(5, origin_rows[team_index]))
		_armies.append(army)
		_coordinator.register_formation(army)
	var previous: Dictionary = {}
	for army in _armies:
		for index in range(100):
			previous[army.combat_identity(index)] = army.cells[index]
	for team_index in range(_armies.size()):
		var army: TerrainArmy = _armies[team_index]
		var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(30, goal_rows[team_index]), -1, Vector2i.RIGHT)
		if not _require(bool(order.get("ok", false)), label + " team " + str(army.team_id) + " MOVE failed: " + str(order)): return false
		var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
		if not _require(plan != null and plan.member_slot_map.size() == 100, label + " must assign 100 final slots to each team"): return false
	if not _check_compact_final_regions(label): return false
	if not _check_leases(label, -1): return false
	var first_progress: Dictionary = {}
	var completed_tick := -1
	var started_ms := Time.get_ticks_msec()
	var late_epoch := -1
	var late_slots: Dictionary = {}
	var late_settled := -1
	var late_trace_count := 0
	var late_locked: Dictionary = {}
	var late_settled_ids: Array[int] = []
	var late_unlock_trace_count := 0
	var two_waypoint_hits := 0
	var two_waypoint_examples: Array[String] = []
	var two_epoch_previous := -1
	var two_bbox := Rect2i()
	if not split_routes and not single_team:
		var two_plan: CombatDeploymentPlan = _armies[0].get_active_deployment_plan()
		var bx0 := 2147483647
		var by0 := 2147483647
		var bx1 := -2147483647
		var by1 := -2147483647
		for slot in two_plan.platform_slots:
			bx0 = mini(bx0, slot.x)
			by0 = mini(by0, slot.y)
			bx1 = maxi(bx1, slot.x)
			by1 = maxi(by1, slot.y)
		two_bbox = Rect2i(bx0, by0, bx1 - bx0 + 1, by1 - by0 + 1)
	for tick in range(MAX_TICKS):
		_coordinator.combat_logic_tick(STEP)
		for army in _armies:
			army.prepare_combat(STEP)
		_coordinator.complete_committed_moves()
		if split_routes and three_team_only and tick >= 2199:
			var late_army: TerrainArmy = _armies[0]
			var late_plan: CombatDeploymentPlan = late_army.get_active_deployment_plan()
			var late_move: CombatMovePlan = late_army.get_active_move_plan()
			if late_plan != null and late_move != null:
				if late_settled >= 0 and late_unlock_trace_count < 30:
					var unlocked: Array[int] = []
					var unsettled: Array[int] = []
					for mid in late_locked.keys():
						if not late_plan.member_slot_locked.has(mid):
							unlocked.append(int(mid))
					for mid in late_settled_ids:
						if not late_plan.settled_platform_member_ids.has(mid):
							unsettled.append(mid)
					if not unlocked.is_empty() or not unsettled.is_empty():
						var lane: Dictionary = {}
						for cell in late_move.macro_path:
							if late_plan.platform_footprint.has(cell):
								lane[cell] = true
						var details: Array[String] = []
						var physical_cells: Dictionary = late_army.get_active_members_occupancy()
						for mid in unlocked:
							var cell: Vector2i = physical_cells.get(mid, TerrainArmy.INVALID_CELL)
							details.append("%d:%s slot=%s entry_lane=%s" % [mid, cell, str(late_plan.get_slot_for_member(mid)), str(lane.has(cell))])
						print("MULTI_TEAM_LATE_UNLOCK tick=", tick, " epoch=", late_epoch, ">", late_plan.assignment_epoch, " settled=", late_settled, ">", late_plan.settled_platform_member_ids.size(), " unlocked=", details.slice(0, 18), " unsettled=", unsettled.slice(0, 18), " chain=", late_move.active_vacancy_chain_actors)
						late_unlock_trace_count += 1
				if late_epoch >= 0 and late_plan.assignment_epoch != late_epoch and late_trace_count < 40:
					var changed_slots: Array[String] = []
					for mid in late_plan.member_slot_map.keys():
						var before: Vector2i = late_slots.get(mid, TerrainArmy.INVALID_CELL)
						var after: Vector2i = late_plan.get_slot_for_member(mid)
						if before != after:
							changed_slots.append("%d:%s>%s cd=%.2f vacated=%s" % [mid, before, after, float(late_move.member_swap_cooldown_until_sec.get(mid, 0.0)), str(late_move.member_recovery_vacated_cell.get(mid, TerrainArmy.INVALID_CELL))])
					var vacant: Array[Vector2i] = []
					var physical: Dictionary = {}
					for cell in late_army.get_active_members_occupancy().values():
						physical[cell] = true
					for slot in late_plan.platform_slots:
						if not physical.has(slot):
							vacant.append(slot)
					print("MULTI_TEAM_LATE_EPOCH tick=", tick, " epoch=", late_epoch, ">", late_plan.assignment_epoch, " settled=", late_settled, ">", late_plan.settled_platform_member_ids.size(), " actors=", late_move.active_vacancy_chain_actors, " hold=", late_move.member_recovery_hold.keys(), " changed=", changed_slots.slice(0, 18), " vacant=", vacant.slice(0, 18))
					late_trace_count += 1
				late_epoch = late_plan.assignment_epoch
				late_slots = late_plan.member_slot_map.duplicate()
				late_settled = late_plan.settled_platform_member_ids.size()
				late_locked = late_plan.member_slot_locked.duplicate()
				late_settled_ids = late_plan.settled_platform_member_ids.duplicate()
		if not _check_world(data, previous, label, tick): return false
		if tick % 50 == 0 and not _check_leases(label, tick): return false
		if not split_routes and not single_team and tick >= 1000:
			var two_army: TerrainArmy = _armies[0]
			var two_move: CombatMovePlan = two_army.get_active_move_plan()
			var two_plan_now: CombatDeploymentPlan = two_army.get_active_deployment_plan()
			if two_move != null and two_plan_now != null:
				var two_cells: Dictionary = two_army.get_active_members_occupancy()
				for mid in two_move.member_entry_waypoint.keys():
					var cell: Vector2i = two_cells.get(mid, TerrainArmy.INVALID_CELL)
					var wp: Vector2i = two_move.member_entry_waypoint[mid]
					if two_plan_now.is_platform_member(mid) and not two_bbox.has_point(cell) and not two_plan_now.platform_slots.has(wp) and int(two_move.member_route_retry_count.get(mid, 0)) >= 12:
						two_waypoint_hits += 1
						if two_waypoint_examples.size() < 12:
							two_waypoint_examples.append("%d:%s>%s final=%s retry=%d" % [mid, cell, wp, str(two_plan_now.get_slot_for_member(mid)), int(two_move.member_route_retry_count.get(mid, 0))])
				if tick % 200 == 0:
					var watched: Array[String] = []
					for mid in [1191, 1166, 1187, 1100]:
						var cell: Vector2i = two_cells.get(mid, TerrainArmy.INVALID_CELL)
						var target: Dictionary = Destination.resolve_member_target(two_move, two_plan_now, mid, cell)
						watched.append("%d:%s>%s target=%s kind=%s retry=%d" % [mid, cell, str(two_plan_now.get_slot_for_member(mid)), str(target.get("target", TerrainArmy.INVALID_CELL)), str(target.get("kind", "")), int(two_move.member_route_retry_count.get(mid, 0))])
					print("MULTI_TEAM_TWO_OUTER tick=", tick, " bbox=", two_bbox, " hits_since_previous=", two_waypoint_hits, " examples=", two_waypoint_examples, " epoch=", two_epoch_previous, ">", two_plan_now.assignment_epoch, " chain=", two_move.active_vacancy_chain_actors, " settled=", two_plan_now.settled_platform_member_ids.size(), " watched=", watched)
					two_waypoint_hits = 0
					two_waypoint_examples.clear()
					two_epoch_previous = two_plan_now.assignment_epoch
		if tick % 200 == 0:
			print("MULTI_TEAM_PROGRESS ", _status(label, tick))
			_print_cross_team_diagnostics(label, tick)
		if split_routes and tick in [2000, 2100]:
			_print_commander_tail(tick)
		if split_routes and three_team_only and tick in [1200, 1600, 2000]:
			_print_team_one_pending(tick)
		if split_routes and three_team_only and tick >= 1700 and tick % 20 == 0:
			_print_team_one_chain_stall(tick)
		if split_routes and three_team_only and tick in [2200, 2300, 2350, 2390]:
			var exterior_army: TerrainArmy = _armies[0]
			var exterior_plan: CombatDeploymentPlan = exterior_army.get_active_deployment_plan()
			var exterior_move: CombatMovePlan = exterior_army.get_active_move_plan()
			var exterior_cells: Dictionary = exterior_army.get_active_members_occupancy()
			if exterior_plan != null and exterior_move != null and exterior_cells.has(1112):
				_print_team_one_exterior_probe(tick, exterior_army, exterior_plan, exterior_move, exterior_cells, 1112)
		var all_arrived := true
		for army in _armies:
			if army.accepted_count > 0 and not first_progress.has(army.team_id):
				first_progress[army.team_id] = tick
			if army.combat_order == TerrainArmy.CombatOrder.HOLD:
				if not _require(army.command_status.begins_with("已抵達"), _status(label, tick) + " stopped before arrival"): return false
			else:
				all_arrived = false
		if tick == 600:
			if not _require(first_progress.size() == _armies.size(), _status(label, tick) + " a team received no physical step in 30 simulated seconds"): return false
		if tick % 50 == 0 and Time.get_ticks_msec() - started_ms > WALL_LIMIT_MS:
			if split_routes and tick not in [2000, 2100]:
				_print_commander_tail(tick)
			return _require(false, _status(label, tick) + " exceeded wall-time bound")
		if all_arrived:
			completed_tick = tick
			break
	if split_routes and completed_tick < 0:
		_print_commander_tail(MAX_TICKS)
	if not _require(completed_tick >= 0, _status(label, MAX_TICKS) + " did not finish in 120 simulated seconds"): return false
	var first_ticks: Array = first_progress.values()
	first_ticks.sort()
	if not _require(first_ticks.size() == _armies.size() and first_ticks[-1] - first_ticks[0] <= 200, _status(label, completed_tick) + " early progress was unfair"): return false
	var final_claims: Dictionary = {}
	for army in _armies:
		var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
		if not _require(plan != null and Destination.is_settled(plan, army.get_active_members_occupancy()), label + " team " + str(army.team_id) + " is not exactly settled"): return false
		var leases: Array[Vector2i] = _coordinator.deployment_registry.get_formation_reserved_slots(army.team_id)
		if not _require(leases.size() == 100, label + " team " + str(army.team_id) + " must retain 100 final leases"): return false
		for index in range(100):
			var identity := army.combat_identity(index)
			var slot: Vector2i = plan.get_slot_for_member(identity)
			if not _require(army.cells[index] == slot and army.moving_to[index] == TerrainArmy.INVALID_CELL and army.facing[index] == Vector2i.RIGHT, label + " person " + str(identity) + " did not finish at the exact slot and facing"): return false
			if not _require(not final_claims.has(slot), label + " two teams claimed final slot " + str(slot)): return false
			final_claims[slot] = identity
			var lease = _coordinator.deployment_registry.owner_of(slot)
			if not _require(lease != null and lease.formation_id == army.team_id and lease.order_serial == plan.order_serial, label + " wrong final lease at " + str(slot)): return false
		if not _require(army._reserved_cells.is_empty() and _coordinator.get_inflight_batches_for_formation(army).is_empty(), label + " left physical claims after arrival"): return false
	if not _require(final_claims.size() == 100 * _armies.size() and _coordinator.deployment_registry.slot_owners.size() == final_claims.size(), label + " cross-team lease set is incomplete or overlapping"): return false
	var settled_cells: Dictionary = previous.duplicate()
	for stable_tick in range(100):
		_coordinator.combat_logic_tick(STEP)
		for army in _armies:
			army.prepare_combat(STEP)
		_coordinator.complete_committed_moves()
		if not _check_world(data, previous, label, completed_tick + stable_tick + 1): return false
		if not _require(previous == settled_cells, label + " shifted after completing all final slots"): return false
		if not _check_leases(label, completed_tick + stable_tick + 1): return false
		if stable_tick % 50 == 0 and Time.get_ticks_msec() - started_ms > WALL_LIMIT_MS:
			return _require(false, label + " exceeded wall-time bound during the stable interval")
	print("MULTI_TEAM_ARRIVAL ", label, " completed_tick=", completed_tick, " first_progress=", first_progress)
	_dispose()
	return true

func _run() -> void:
	if OS.get_cmdline_user_args().has("--single-team"):
		if not _run_case(false, true): return
		print("COMBAT MOVEMENT SINGLE TEAM CONTROL PASS")
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--three-team"):
		if not _run_case(true): return
		print("COMBAT MOVEMENT THREE TEAM ARRIVAL PASS")
		quit(0)
		return
	if not _run_case(false): return
	if not _run_case(true): return
	print("COMBAT MOVEMENT MULTI TEAM ARRIVAL PASS")
	quit(0)
