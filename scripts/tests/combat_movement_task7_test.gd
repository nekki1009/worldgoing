extends SceneTree
## Unit test suite for Task 7: HOLD Deployment Maintenance,
## vacancy promotion, queue shifting, and temporary absence lease grace periods.

const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const DeploymentPlan = preload("res://scripts/terrain_lab/combat_deployment_plan.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Task 7 HOLD Maintenance & Promotion Test ---")
	
	# 1. Setup deployment plan: 60 platform + 40 queue
	var plan = DeploymentPlan.new()
	plan.formation_id = 1
	plan.order_serial = 100
	
	for y in range(6):
		for x in range(10):
			plan.platform_slots.append(Vector2i(20 + x, 20 + y))
	for y in range(40):
		plan.approach_queue_slots.append(Vector2i(20, 19 - y))
		
	plan.structural_platform_capacity = 60
	plan.available_platform_capacity = 60
	plan.queue_capacity = 40
	plan.requested_count = 100
	
	# Assign 60 platform members (IDs 1001..1060) and 40 queue members (IDs 1061..1100)
	for i in range(60):
		var mid := 1001 + i
		plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		plan.member_slot_map[mid] = plan.platform_slots[i]
		plan.slot_owner_map[plan.platform_slots[i]] = mid
		plan.settled_platform_member_ids.append(mid)
		
	for i in range(40):
		var mid := 1061 + i
		plan.member_role_map[mid] = Types.CombatDestinationRole.APPROACH_QUEUE
		plan.member_slot_map[mid] = plan.approach_queue_slots[i]
		plan.slot_owner_map[plan.approach_queue_slots[i]] = mid
		plan.queue_member_ids.append(mid)
		
	plan.queue_released = true
	assert(plan.queue_member_ids.size() == 40)
	assert(plan.promotion_count == 0)
	
	# 2. Test permanent casualty/removal: remove 2 platform members
	var dead_1 := 1005
	var dead_2 := 1010
	var slot_1: Vector2i = plan.member_slot_map[dead_1]
	var slot_2: Vector2i = plan.member_slot_map[dead_2]
	
	# Removing dead_1: queue front 1061 should be promoted immediately
	plan.remove_member(dead_1, Types.SlotVacancyReason.MEMBER_DEAD)
	assert(plan.promotion_count == 1, "First promotion must be recorded")
	assert(plan.member_role_map[1061] == Types.CombatDestinationRole.PLATFORM)
	assert(plan.member_slot_map[1061] == slot_1)
	assert(plan.slot_owner_map[slot_1] == 1061)
	assert(plan.queue_member_ids.size() == 39)
	# 1062 is now at queue front and shifted to approach_queue_slots[0]
	assert(plan.queue_member_ids[0] == 1062)
	assert(plan.member_slot_map[1062] == plan.approach_queue_slots[0])
	
	# Removing dead_2: queue front 1062 should be promoted immediately
	plan.remove_member(dead_2, Types.SlotVacancyReason.MEMBER_DEAD)
	assert(plan.promotion_count == 2, "Second promotion must be recorded")
	assert(plan.member_role_map[1062] == Types.CombatDestinationRole.PLATFORM)
	assert(plan.member_slot_map[1062] == slot_2)
	assert(plan.queue_member_ids.size() == 38)
	assert(plan.queue_member_ids[0] == 1063)
	assert(plan.member_slot_map[1063] == plan.approach_queue_slots[0])
	print("TASK 7: Permanent removal & immediate 2-member queue promotion verified")
	
	# 3. Temporary absence lease test (4.0 seconds grace period)
	var absent_mid := 1015
	var absent_slot: Vector2i = plan.member_slot_map[absent_mid]
	plan.remove_member(absent_mid, Types.SlotVacancyReason.TEMPORARY_ABSENCE)
	
	# Slot lease timer should be active
	assert(plan.slot_lease_timers.has(absent_slot))
	assert(abs(plan.slot_lease_timers[absent_slot] - 4.0) < 0.001)
	# Queue member should NOT have been promoted yet
	assert(plan.promotion_count == 2)
	assert(plan.queue_member_ids[0] == 1063)
	
	# Advance time by 2.0 seconds (within grace period)
	plan.update_leases(2.0)
	assert(plan.slot_lease_timers.has(absent_slot))
	assert(plan.slot_lease_timers[absent_slot] <= 2.0)
	assert(plan.promotion_count == 2, "Must not promote while grace period is active")
	
	# Member returns before lease expires!
	var returned := plan.member_return_from_absence(absent_mid, absent_slot)
	assert(returned, "Member return must succeed")
	assert(not plan.slot_lease_timers.has(absent_slot), "Lease timer must be cleared on return")
	assert(plan.member_slot_map[absent_mid] == absent_slot)
	assert(plan.promotion_count == 2, "Promotion count unchanged after return")
	print("TASK 7: Temporary absence return within grace period verified")
	
	# 4. Temporary absence expiration test
	var expire_mid := 1020
	var expire_slot: Vector2i = plan.member_slot_map[expire_mid]
	plan.remove_member(expire_mid, Types.SlotVacancyReason.TEMPORARY_ABSENCE)
	assert(plan.slot_lease_timers.has(expire_slot))
	
	# Advance time by 4.5 seconds (exceeding 4.0 seconds)
	plan.update_leases(4.5)
	assert(not plan.slot_lease_timers.has(expire_slot), "Lease timer must be erased upon expiration")
	assert(plan.promotion_count == 3, "Queue front must be promoted upon lease expiration")
	assert(plan.member_role_map[1063] == Types.CombatDestinationRole.PLATFORM)
	assert(plan.member_slot_map[1063] == expire_slot)
	print("TASK 7: Temporary absence lease expiration promotion verified")
	
	print("TASK 7 COMPLETE: HOLD Maintenance & Vacancy Promotion fully operational!")
	quit(0)
