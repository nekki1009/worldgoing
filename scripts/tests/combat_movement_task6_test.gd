extends SceneTree
## Unit test suite for Task 6: FormationDestinationPlanner,
## 60-platform + 40-approach queue partitioning, deep-to-shallow assignment,
## and Ingress Admission Gate.

const DestinationPlanner = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const TransitPlanner = preload("res://scripts/terrain_lab/formation_transit_planner.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Task 6 Destination Planner & Ingress Gate Test ---")
	
	# 1. Setup mountain platform map and macro path leading up to peak
	var map_info = Helper.build_mountain_platform_map(Vector2i(60, 60), Vector2i(30, 30), 5)
	var test_data: TerrainData = map_info["data"]
	var platform_center: Vector2i = map_info["platform_center"]
	var start_pos := Vector2i(30, 10)
	
	var macro_path = TransitPlanner.build_macro_path(test_data, start_pos, platform_center)
	assert(not macro_path.is_empty(), "Macro path to platform center must exist")
	
	# 2. Plan deployment for 100 members
	var member_ids: Array[int] = []
	for i in range(100):
		member_ids.append(2000 + i)
		
	var dep_plan = DestinationPlanner.plan_deployment(
		1, 1001, test_data, platform_center, macro_path, member_ids
	)
	assert(dep_plan != null, "Deployment plan must succeed for 100 members")
	
	var platform_count := 0
	var queue_count := 0
	for mid in member_ids:
		var role = dep_plan.member_role_map[mid]
		if role == Types.CombatDestinationRole.PLATFORM:
			platform_count += 1
		elif role == Types.CombatDestinationRole.APPROACH_QUEUE:
			queue_count += 1
			
	print("TASK 6: Allocated %d platform members and %d queue members" % [platform_count, queue_count])
	assert(platform_count > 0, "Platform members must be allocated")
	assert(queue_count > 0, "Approach queue members must be allocated")
	assert(platform_count + queue_count == 100, "All 100 members must have a designated role")
	
	# Verify no overlap between platform slots, queue slots, and ingress buffer
	var all_slots: Dictionary = {}
	for c in dep_plan.platform_slots:
		assert(not all_slots.has(c), "Platform slot duplicate at %s!" % str(c))
		all_slots[c] = "platform"
		
	for b in dep_plan.ingress_buffer_cells:
		assert(not all_slots.has(b), "Ingress buffer must not overlap platform slots!")
		all_slots[b] = "buffer"
		
	for q in dep_plan.approach_queue_slots:
		assert(not all_slots.has(q), "Queue slot %s overlaps with platform or buffer!" % str(q))
		all_slots[q] = "queue"
	print("TASK 6: Zero overlap between platform, buffer, and queue slots verified")
	
	# 3. Verify deep-to-shallow slot assignment
	# Earlier platform slots must be further from ingress_cell than later platform slots
	var ingress: Vector2i = dep_plan.ingress_cell
	var dist_first: int = absi(dep_plan.platform_slots[0].x - ingress.x) + absi(dep_plan.platform_slots[0].y - ingress.y)
	var dist_last: int = absi(dep_plan.platform_slots[dep_plan.platform_slots.size() - 1].x - ingress.x) + absi(dep_plan.platform_slots[dep_plan.platform_slots.size() - 1].y - ingress.y)
	assert(dist_first >= dist_last, "First platform slot must be deeper than last platform slot")
	print("TASK 6: Deep-to-shallow platform slot assignment verified")
	
	# 4. Ingress Admission Gate verification
	assert(not dep_plan.queue_released, "Queue must be initially held at ingress gate")
	assert(dep_plan.pending_platform_member_ids.size() == platform_count)
	
	# Ingress buffer check: queue members must be directed to queue_hold_cross_section, NOT into buffer
	var first_queue_mid: int = dep_plan.queue_member_ids[0]
	var held_target = DestinationPlanner.get_member_current_target(dep_plan, first_queue_mid)
	assert(held_target == dep_plan.queue_hold_cross_section[0], "Queue member must be held behind hold cross section")
	for b in dep_plan.ingress_buffer_cells:
		assert(held_target != b, "Queue member target must not be in ingress buffer while gate is closed")
		
	# Simulate platform members reaching platform footprint
	var current_cells: Dictionary = {}
	for mid in dep_plan.member_slot_map.keys():
		current_cells[mid] = start_pos
		
	# Only half the platform members arrive
	for i in range(platform_count / 2):
		var mid: int = dep_plan.pending_platform_member_ids[i]
		current_cells[mid] = dep_plan.member_slot_map[mid]
		
	DestinationPlanner.update_ingress_gate(dep_plan, current_cells)
	assert(not dep_plan.queue_released, "Gate must remain closed while platform members are still pending")
	
	# All platform members arrive on platform
	for mid in dep_plan.pending_platform_member_ids:
		current_cells[mid] = dep_plan.member_slot_map[mid]
		
	DestinationPlanner.update_ingress_gate(dep_plan, current_cells)
	assert(dep_plan.queue_released, "Gate must open when all platform members have entered platform")
	
	# Now queue members receive their formal queue slot targets
	var released_target = DestinationPlanner.get_member_current_target(dep_plan, first_queue_mid)
	assert(released_target == dep_plan.member_slot_map[first_queue_mid], "Queue member must advance to assigned queue slot once gate is open")
	print("TASK 6: Ingress Admission Gate lifecycle verified")
	
	# 5. Settled check
	assert(not DestinationPlanner.is_settled(dep_plan, current_cells), "Plan should not be settled while queue members haven't arrived")
	
	for mid in member_ids:
		current_cells[mid] = dep_plan.member_slot_map[mid]
		
	assert(DestinationPlanner.is_settled(dep_plan, current_cells), "Plan must report settled when all members occupy assigned slots")
	print("TASK 6: Settled status detection verified")
	
	print("TASK 6 COMPLETE: Destination Planner & Ingress Gate fully operational!")
	quit(0)
