extends SceneTree
## One 25-person team traverses every directed pair of the six fixed formations.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const STEP := 0.05
const MAX_TICKS := 6000 # 300 simulated seconds per change.
const ANCHOR := Vector2i(48, 40)
const TOUR := [
	"square", "wedge", "square", "goose", "square", "circle", "square", "hook",
	"square", "loose", "wedge", "goose", "wedge", "circle", "wedge", "hook",
	"wedge", "loose", "goose", "circle", "goose", "hook", "goose", "loose",
	"circle", "hook", "circle", "loose", "hook", "loose", "square"
]

var _army: TerrainArmy
var _coordinator: SiteCombatMovementCoordinator
var _terrain: TerrainData

func _initialize() -> void:
	call_deferred("_run")

func _cleanup() -> void:
	if is_instance_valid(_army):
		if _coordinator != null:
			_coordinator.unregister_formation(_army)
		_army.free()
	_army = null
	_coordinator = null

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		_cleanup()
		quit(1)
	return ok

func _tick_and_check(previous: Array[Vector2i], label: String, tick: int) -> bool:
	_coordinator.combat_logic_tick(STEP)
	_army.prepare_combat(STEP)
	_coordinator.complete_committed_moves()
	var occupied: Dictionary = {}
	var claims: Dictionary = {}
	for i in range(25):
		var cell: Vector2i = _army.cells[i]
		if not _require(_terrain.contains(cell) and _terrain.is_walkable(cell) and not occupied.has(cell), "%s: duplicate or illegal cell at tick %d" % [label, tick]): return false
		occupied[cell] = true
		if cell != previous[i] and not _require(_terrain.can_step(previous[i], cell), "%s: member %d skipped a physical edge at tick %d" % [label, i, tick]): return false
		previous[i] = cell
		var claim: Vector2i = _army.moving_to[i]
		if claim != TerrainArmy.INVALID_CELL:
			if not _require(_terrain.can_step(cell, claim) and not claims.has(claim), "%s: duplicate or illegal step claim at tick %d" % [label, tick]): return false
			claims[claim] = true
	return true

func _arrive(label: String) -> bool:
	var previous: Array[Vector2i] = _army.cells.duplicate()
	for tick in range(MAX_TICKS):
		if not _tick_and_check(previous, label, tick): return false
		if _army.combat_order == TerrainArmy.CombatOrder.HOLD:
			if not _require(_army.command_status.begins_with("已抵達"), "%s: stopped without completing at tick %d: %s" % [label, tick, _army.command_status]): return false
			return true
	var plan: CombatDeploymentPlan = _army.get_active_deployment_plan()
	var unresolved: Array[String] = []
	if plan != null:
		for mid: int in plan.member_slot_map.keys():
			var index := _army.index_for_identity(mid)
			if index >= 0 and _army.cells[index] != plan.get_slot_for_member(mid):
				unresolved.append("%d:%s>%s" % [mid, _army.cells[index], plan.get_slot_for_member(mid)])
				if unresolved.size() >= 6:
					break
	return _require(false, "%s: timed out after 300 simulated seconds; status=%s unresolved=%s" % [label, _army.command_status, str(unresolved)])

func _settled_and_stable(preset: String, label: String) -> bool:
	var plan: CombatDeploymentPlan = _army.get_active_deployment_plan()
	if not _require(plan != null and plan.formation_preset_id == preset and plan.requested_count == 25 and plan.resolved_anchor == ANCHOR and plan.final_facing == Vector2i.RIGHT, "%s: wrong retained deployment, anchor, or facing" % label): return false
	if not _require(plan.platform_slots.size() == 25 and plan.member_slot_map.size() == 25 and plan.queue_member_ids.is_empty() and Destination.is_settled(plan, _army.get_active_members_occupancy()), "%s: not all 25 original members reached exact platform slots" % label): return false
	var expected: Dictionary = {}
	for cell in Destination.shape_slots(preset, 25, plan.resolved_anchor, plan.final_facing):
		expected[cell] = true
	var leased: Array[Vector2i] = _coordinator.deployment_registry.get_formation_reserved_slots(_army.team_id)
	if not _require(expected.size() == 25 and leased.size() == 25, "%s: missing template slots or final leases" % label): return false
	for slot: Vector2i in plan.platform_slots:
		if not _require(expected.erase(slot) and leased.has(slot), "%s: final slot differs from the selected template or lease" % label): return false
		var lease = _coordinator.deployment_registry.owner_of(slot)
		if not _require(lease != null and lease.formation_id == _army.team_id and lease.order_serial == plan.order_serial, "%s: wrong final lease owner or serial" % label): return false
	if not _require(expected.is_empty(), "%s: template has unassigned slots" % label): return false
	var final_cells: Array[Vector2i] = _army.cells.duplicate()
	var final_mapping: Dictionary = plan.member_slot_map.duplicate()
	var final_epoch: int = plan.assignment_epoch
	var previous: Array[Vector2i] = final_cells.duplicate()
	for tick in range(100):
		if not _tick_and_check(previous, label + " stable", tick): return false
		if not _require(_army.combat_order == TerrainArmy.CombatOrder.HOLD and _army.cells == final_cells and _army.get_active_deployment_plan() == plan and plan.member_slot_map == final_mapping and plan.assignment_epoch == final_epoch and _army.get_active_movement_claims().is_empty() and _army._combat_batch_members.is_empty() and _coordinator.get_inflight_batches_for_formation(_army).is_empty(), "%s: drift, reassignment, or pending step during five stable seconds at tick %d" % [label, tick]): return false
		for i in range(25):
			if not _require(_army.moving_to[i] == TerrainArmy.INVALID_CELL and _army.cells[i] == plan.get_slot_for_member(_army.combat_identity(i)) and _army.facing[i] == plan.get_facing_for_slot(_army.cells[i]), "%s: member %d has wrong final cell/facing at stable tick %d" % [label, i, tick]): return false
	var leases_after: Array[Vector2i] = _coordinator.deployment_registry.get_formation_reserved_slots(_army.team_id)
	if not _require(leases_after.size() == leased.size(), "%s: final lease count changed during stable window" % label): return false
	for slot in leased:
		if not _require(leases_after.has(slot), "%s: final lease disappeared during stable window" % label): return false
	return true

func _run() -> void:
	_terrain = Helper.build_flat_map(96, 80)
	_army = Helper.create_test_army(_terrain, 1, 0, 25, Vector2i(24, 38))
	_coordinator = Coordinator.new()
	_coordinator.register_formation(_army)
	var start: Dictionary = _army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.MOVE, ANCHOR, -1, Vector2i.RIGHT, TOUR[0])
	if not _require(bool(start.get("ok", false)), "initial square command rejected: %s" % str(start)): return
	if not _arrive("initial square"): return
	if not _settled_and_stable("square", "initial square"): return
	var visited: Dictionary = {}
	for edge in range(TOUR.size() - 1):
		var from_preset: String = TOUR[edge]
		var to_preset: String = TOUR[edge + 1]
		var label := "%s->%s" % [from_preset, to_preset]
		if not _require(from_preset != to_preset and not visited.has(label) and _army.formation_preset_id == from_preset, "%s: Eulerian pair sequence is invalid" % label): return
		visited[label] = true
		var before: Array[Vector2i] = _army.cells.duplicate()
		var serial: int = _army.get_order_serial()
		var command: Dictionary = _army.issue_formation_change(_army.current_commander, to_preset)
		if not _require(bool(command.get("ok", false)) and _army.cells == before and _army.get_order_serial() == serial + 1 and _army.formation_preset_id == to_preset, "%s: command rejected, teleported, or failed to commit: %s" % [label, str(command)]): return
		if not _arrive(label): return
		if not _settled_and_stable(to_preset, label): return
		print("FORMATION PAIR PASS ", label)
	if not _require(visited.size() == 30 and TOUR[-1] == "square", "Did not cover all 30 directed preset pairs"): return
	_cleanup()
	print("COMBAT FORMATION 25 PAIRWISE SWITCH PASS: 30 directed pairs")
	quit(0)
