extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	var terrain := Helper.build_flat_map(70, 70)
	var anchor := Vector2i(30, 17)
	var path: Array[Vector2i] = Transit.build_macro_path(terrain, Vector2i(5, 17), anchor)
	var member_ids: Array[int] = []
	for i in range(100):
		member_ids.append(1001 + i)
	var officers: Array[int] = []
	var current_cells: Dictionary = {}
	var plan: CombatDeploymentPlan = Destination.plan_deployment(1, 1, terrain, anchor, path, member_ids, null, officers, current_cells, Vector2i.RIGHT)
	if not _require(plan != null and plan.platform_slots.size() == 100 and plan.resolved_anchor == anchor and plan.final_facing == Vector2i.RIGHT,
		"Open-ground final slots must keep the commanded center and facing"): return
	var min_x := 999999
	var max_x := -999999
	var min_y := 999999
	var max_y := -999999
	for slot in plan.platform_slots:
		min_x = mini(min_x, slot.x)
		max_x = maxi(max_x, slot.x)
		min_y = mini(min_y, slot.y)
		max_y = maxi(max_y, slot.y)
	if not _require(min_x == 26 and max_x == 35 and min_y == 12 and max_y == 22 and plan.approach_bottlenecked == 0 and Destination._platform_handoff_cell(plan) == Vector2i(25, 17),
		"The compact final region must stay centered while its approach handoff sits before the shallow edge"): return
	var slot := Vector2i(27, 22)
	if not _require(plan.slot_owner_map.has(slot), "The shallow off-center slot must exist for the handoff counterexample"): return
	var mid: int = int(plan.slot_owner_map[slot])
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	move.macro_path = path
	move.member_transit_slots[mid] = Vector2i(25, 17)
	var before: Dictionary = Destination.resolve_member_target(move, plan, mid, Vector2i(24, 17))
	var at_edge: Dictionary = Destination.resolve_member_target(move, plan, mid, Vector2i(25, 17))
	if not _require(before.get("kind") == "transit" and before.get("target") == Vector2i(25, 17) and at_edge.get("kind") == "platform" and at_edge.get("target") == slot,
		"An entrant must hand over to its exact final at the shallow edge, without marching past it to the macro center"): return
	var wall: TerrainData = Helper.build_bottleneck_map(Vector2i(70, 45), 20, 25, 31, 1)["data"]
	var choke_anchor := Vector2i(45, 20)
	var choke_path: Array[Vector2i] = Transit.build_macro_path(wall, Vector2i(5, 15), choke_anchor)
	var choke: CombatDeploymentPlan = Destination.plan_deployment(3, 3, wall, choke_anchor, choke_path, member_ids, null, officers, current_cells, Vector2i.RIGHT)
	if not _require(choke != null and choke.approach_bottlenecked == 1 and choke.get_platform_handoff_cell() == Vector2i(40, 20) and choke.platform_footprint.has(Vector2i(33, 20)),
		"A real one-cell wall must keep transit through its exit and hand over before the first shallow final"): return
	var choke_slot := Vector2i(50, 20)
	if not _require(choke.slot_owner_map.has(choke_slot), "The deep choke final must be assigned"): return
	var choke_mid: int = int(choke.slot_owner_map[choke_slot])
	var choke_move := CombatMovePlan.new()
	choke_move.destination_plan = choke
	choke_move.macro_path = choke_path
	choke_move.member_transit_slots[choke_mid] = Vector2i(34, 20)
	var before_exit: Dictionary = Destination.resolve_member_target(choke_move, choke, choke_mid, Vector2i(33, 20))
	if not _require(choke.needs_transit_soft_target(choke_mid, Vector2i(33, 20)) and before_exit.get("kind") == "transit" and before_exit.get("target") == Vector2i(34, 20),
		"An admitted soldier still inside the wall must retain a transit target until it physically exits the choke"): return
	choke_move.member_transit_slots[choke_mid] = Vector2i(40, 20)
	var before_final: Dictionary = Destination.resolve_member_target(choke_move, choke, choke_mid, Vector2i(39, 20))
	var at_final_edge: Dictionary = Destination.resolve_member_target(choke_move, choke, choke_mid, Vector2i(40, 20))
	if not _require(before_final.get("kind") == "transit" and before_final.get("target") == Vector2i(40, 20) and at_final_edge.get("kind") == "platform" and at_final_edge.get("target") == choke_slot,
		"The wall entrant must switch to its exact slot only after the choke and before overshooting the shallow edge"): return
	var fixture: Dictionary = Helper.build_exact_60_platform_map()
	var plateau_path: Array[Vector2i] = Transit.build_macro_path(fixture.data, fixture.start, fixture.anchor)
	var plateau: CombatDeploymentPlan = Destination.plan_deployment(2, 2, fixture.data, fixture.anchor, plateau_path, member_ids)
	if not _require(plateau != null and plateau.platform_slots.size() == 60 and Destination._platform_handoff_cell(plateau) == fixture.anchor,
		"The constrained sixty-cell plateau must retain its original anchor handoff and capacity"): return
	print("COMBAT MOVEMENT CENTERED HANDOFF PASS")
	quit(0)
