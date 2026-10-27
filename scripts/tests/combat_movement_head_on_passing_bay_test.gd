extends SceneTree
## Two original Army people approach each other through a one-cell passage.
## A five-cell side bay makes a legal physical passing route in the second case.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const STEP := 0.05
const MAX_TICKS := 800
const WALL_LIMIT_MS := 60000

var _armies: Array[TerrainArmy] = []
var _coordinator: SiteCombatMovementCoordinator

func _initialize() -> void:
	call_deferred("_run")

func _dispose() -> void:
	for army in _armies:
		if is_instance_valid(army):
			_coordinator.unregister_formation(army)
			army.free()
	_armies.clear()
	_coordinator = null

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	_dispose()
	TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
	quit(1)
	return false

func _build_map(with_bay: bool) -> TerrainData:
	var data: TerrainData = Helper.build_flat_map(30, 15)
	data.flags.fill(0)
	data.static_blocked.fill(1)
	for x in range(2, 28):
		var corridor := data.index(Vector2i(x, 7))
		data.flags[corridor] = TerrainData.Flag.WALKABLE
		data.static_blocked[corridor] = 0
	if with_bay:
		for x in range(13, 18):
			var pocket := data.index(Vector2i(x, 6))
			data.flags[pocket] = TerrainData.Flag.WALKABLE
			data.static_blocked[pocket] = 0
	data.navigation_revision += 1
	return data

func _status(label: String, tick: int) -> String:
	return "%s tick=%d A=%s %s B=%s %s" % [label, tick, _armies[0].cells[0], _armies[0].command_status,
		_armies[1].cells[0], _armies[1].command_status]

func _advance(data: TerrainData, previous: Array[Vector2i], label: String, tick: int) -> bool:
	_coordinator.combat_logic_tick(STEP)
	for army in _armies:
		army.prepare_combat(STEP)
	_coordinator.complete_committed_moves()
	var a: Vector2i = _armies[0].cells[0]
	var b: Vector2i = _armies[1].cells[0]
	if not _require(a != b and data.is_walkable(a) and data.is_walkable(b), _status(label, tick) + " duplicate or illegal physical occupancy"): return false
	if not _require((a == previous[0] or data.can_step(previous[0], a)) and (b == previous[1] or data.can_step(previous[1], b)),
		_status(label, tick) + " skipped a legal physical edge"): return false
	if not _require(not (a == previous[1] and b == previous[0]), _status(label, tick) + " swapped occupied cells in one tick"): return false
	previous[0] = a
	previous[1] = b
	var claims: Dictionary = {}
	for army in _armies:
		var from: Vector2i = army.cells[0]
		var to: Vector2i = army.moving_to[0]
		if to != TerrainArmy.INVALID_CELL:
			if not _require(data.can_step(from, to) and not claims.has(to), _status(label, tick) + " illegal or duplicate in-flight claim"): return false
			claims[to] = true
	return true

func _setup(data: TerrainData, label: String) -> bool:
	_coordinator = Coordinator.new()
	_armies.append(Helper.create_test_army(data, 1, 0, 1, Vector2i(4, 7)))
	# Both teams are allies (faction 0). Between hostile factions an adjacent able enemy
	# sets the ENGAGING overlay, which by design freezes the stall clock for combat, so
	# a passing/congestion test only applies to allied teams.
	_armies.append(Helper.create_test_army(data, 2, 0, 1, Vector2i(25, 7)))
	for army in _armies:
		_coordinator.register_formation(army)
	for index in range(2):
		var army: TerrainArmy = _armies[index]
		# A one-person auto deployment lands on its anchor (compact platform), so each
		# goal lies beyond the other person's start: the finals genuinely require a pass.
		var goal := Vector2i(26, 7) if index == 0 else Vector2i(3, 7)
		var facing := Vector2i.RIGHT if index == 0 else Vector2i.LEFT
		var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, goal, -1, facing)
		if not _require(bool(order.get("ok", false)), label + " opposing MOVE rejected: " + str(order)): return false
	var a_plan: CombatDeploymentPlan = _armies[0].get_active_deployment_plan()
	var b_plan: CombatDeploymentPlan = _armies[1].get_active_deployment_plan()
	if not _require(a_plan != null and b_plan != null and a_plan.member_slot_map.size() == 1 and b_plan.member_slot_map.size() == 1,
		label + " must assign one real final slot per team"): return false
	var a_final: Vector2i = a_plan.get_slot_for_member(_armies[0].combat_identity(0))
	var b_final: Vector2i = b_plan.get_slot_for_member(_armies[1].combat_identity(0))
	if not _require(a_final.x > _armies[1].cells[0].x and b_final.x < _armies[0].cells[0].x
		and a_final != b_final and _coordinator.deployment_registry.slot_owners.size() == 2,
		label + " assigned finals must genuinely require the two people to pass"): return false
	return true

func _run_case(with_bay: bool) -> bool:
	var label := "side bay" if with_bay else "no pocket"
	var data := _build_map(with_bay)
	if not _require(data.can_step(Vector2i(14, 7), Vector2i(15, 7))
		and (data.can_step(Vector2i(15, 7), Vector2i(15, 6)) == with_bay),
		label + " does not have the intended walkability"): return false
	if not _setup(data, label): return false
	var previous: Array[Vector2i] = [_armies[0].cells[0], _armies[1].cells[0]]
	var moved: Dictionary = {}
	var bay_used := false
	var complete_tick := -1
	var started_ms := Time.get_ticks_msec()
	for tick in range(MAX_TICKS):
		if not _advance(data, previous, label, tick): return false
		for index in range(2):
			if _armies[index].cells[0] != (Vector2i(4, 7) if index == 0 else Vector2i(25, 7)):
				moved[index] = true
			if _armies[index].cells[0].y == 6:
				bay_used = true
		if not with_bay and not _require(_armies[0].cells[0].x < _armies[1].cells[0].x,
			_status(label, tick) + " passed through each other without a pocket"): return false
		if _armies[0].combat_order == TerrainArmy.CombatOrder.HOLD and _armies[1].combat_order == TerrainArmy.CombatOrder.HOLD:
			complete_tick = tick
			break
		if tick % 100 == 0:
			print("HEAD_ON_PROGRESS ", _status(label, tick), " bay_used=", bay_used)
		if tick % 50 == 0 and Time.get_ticks_msec() - started_ms > WALL_LIMIT_MS:
			return _require(false, _status(label, tick) + " exceeded the 60-second wall limit")
	if not _require(not moved.is_empty(), label + " had no real physical progress"): return false
	if not with_bay:
		if not _require(complete_tick >= 0 and (_armies[0].command_status.contains("擁塞") or _armies[1].command_status.contains("擁塞")),
			_status(label, MAX_TICKS) + " must terminate the physically impossible head-on passage as CONGESTED"): return false
	else:
		if not _require(complete_tick >= 0 and bay_used and moved.size() == 2,
			_status(label, MAX_TICKS) + " did not use the legal passing bay and complete both moves"): return false
		for index in range(2):
			var army: TerrainArmy = _armies[index]
			var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
			if not _require(plan != null, _status(label, complete_tick) + " ended without a deployed final plan"): return false
			var identity := army.combat_identity(0)
			var slot: Vector2i = plan.get_slot_for_member(identity)
			var lease = _coordinator.deployment_registry.owner_of(slot)
			if not _require(army.command_status.begins_with("已抵達") and Destination.is_settled(plan, army.get_active_members_occupancy())
				and army.cells[0] == slot and army.moving_to[0] == TerrainArmy.INVALID_CELL
				and army.facing[0] == (Vector2i.RIGHT if index == 0 else Vector2i.LEFT)
				and lease != null and lease.formation_id == army.team_id and lease.order_serial == plan.order_serial,
				_status(label, complete_tick) + " lacks exact final slot/facing/lease"): return false
		var stable: Array[Vector2i] = previous.duplicate()
		for quiet_tick in range(100):
			if not _advance(data, previous, label, complete_tick + quiet_tick + 1): return false
			if not _require(previous == stable, _status(label, complete_tick + quiet_tick + 1) + " drifted after arrival"): return false
	print("HEAD_ON_CASE PASS ", label, " tick=", complete_tick, " bay_used=", bay_used)
	_dispose()
	return true

func _run() -> void:
	if not _run_case(false): return
	if not _run_case(true): return
	print("COMBAT MOVEMENT HEAD ON PASSING BAY PASS")
	TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
	quit(0)
