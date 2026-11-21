extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	var fixture: Dictionary = Helper.build_exact_60_platform_map()
	var data: TerrainData = fixture.data
	var path: Array[Vector2i] = Transit.build_macro_path(data, fixture.start, fixture.anchor)
	if not _require(not path.is_empty(), "The single ramp must lead to the plateau"): return
	if not _require(path.has(fixture.ingress), "The macro route must use the only entrance"): return
	var member_ids: Array[int] = []
	for i in range(100):
		member_ids.append(2000 + i)
	var plan: CombatDeploymentPlan = Destination.plan_deployment(1, 101, data, fixture.anchor, path, member_ids)
	if not _require(plan != null, "The planner must provide 100 distinct, legal final slots"): return
	var expected: Dictionary = {}
	for cell: Vector2i in fixture.final_cells:
		expected[cell] = true
	if not _require(plan.platform_slots.size() == 60, "The ingress cell must remain clear; 60 plateau cells remain"): return
	var assigned: Dictionary = {}
	var platform_count := 0
	var queue_count := 0
	for mid: int in member_ids:
		if not _require(plan.member_slot_map.has(mid), "Every member needs one final slot"): return
		var cell: Vector2i = plan.member_slot_map[mid]
		if not _require(data.contains(cell) and data.is_walkable(cell), "Every slot must be legal terrain"): return
		if not _require(not assigned.has(cell), "Final slots must be unique"): return
		assigned[cell] = mid
		if plan.member_role_map[mid] == Types.CombatDestinationRole.PLATFORM:
			if not _require(expected.has(cell), "Only the 60 plateau final cells may hold platform members"): return
			platform_count += 1
		else:
			if not _require(plan.member_role_map[mid] == Types.CombatDestinationRole.APPROACH_QUEUE, "All non-platform members must be queue members"): return
			if not _require(not plan.ingress_buffer_cells.has(cell), "Queue must not occupy ingress buffer"): return
			if not _require(cell != fixture.ingress and cell != fixture.ramp, "Queue must leave ramp free"): return
			queue_count += 1
	if not _require(platform_count == 60 and queue_count == 40, "Exact-capacity plateau must assign 60 + 40"): return
	var open_data := Helper.build_flat_map(80, 60)
	var open_path: Array[Vector2i] = Transit.build_macro_path(open_data, Vector2i(10, 30), Vector2i(50, 30))
	var open_plan: CombatDeploymentPlan = Destination.plan_deployment(2, 102, open_data, Vector2i(50, 30), open_path, member_ids)
	if not _require(open_plan != null and open_plan.platform_slots.size() == 100 and open_plan.queue_member_ids.is_empty(), "Open ground must assign 100 platform slots and no queue"): return
	if not _require(open_plan.member_slot_map.size() == 100 and open_plan.slot_owner_map.size() == 100, "Open-ground final slots must be unique and fully owned"): return
	var small_data := Helper.build_flat_map(80, 60)
	for y in range(25, 32):
		for x in range(45, 52):
			small_data.height_levels[small_data.index(Vector2i(x, y))] = 2
	var small_ingress := Vector2i(44, 28)
	var small_ramp := Vector2i(43, 28)
	var small_foot := Vector2i(42, 28)
	small_data.height_levels[small_data.index(small_ingress)] = 2
	small_data.height_levels[small_data.index(small_ramp)] = 1
	small_data.ramp_edges[small_data.index(small_foot)] |= 1 << 1
	small_data.ramp_edges[small_data.index(small_ramp)] |= (1 << 3) | (1 << 1)
	small_data.ramp_edges[small_data.index(small_ingress)] |= 1 << 3
	var small_path: Array[Vector2i] = Transit.build_macro_path(small_data, Vector2i(2, 28), Vector2i(48, 28))
	if not _require(small_path.has(small_ingress), "The 49-cell plateau must use its only ramp"): return
	var small_plan: CombatDeploymentPlan = Destination.plan_deployment(3, 103, small_data, Vector2i(48, 28), small_path, member_ids)
	if not _require(small_plan != null and small_plan.platform_slots.size() == 49 and small_plan.queue_member_ids.size() == 51, "A 49-cell plateau must assign 49+51"): return
	print("COMBAT MOVEMENT EXACT CAPACITY PASS: 60+40, 100+0, and 49+51")
	quit(0)
