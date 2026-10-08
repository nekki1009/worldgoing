extends SceneTree
## Unit test suite for Task 1: Data types, FormationMovementProfile, CombatMovePlan,
## CombatDeploymentPlan, and member departure / vacancy promotion handling.

const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const Profile = preload("res://scripts/terrain_lab/formation_movement_profile.gd")
const MovePlan = preload("res://scripts/terrain_lab/combat_move_plan.gd")
const DeploymentPlan = preload("res://scripts/terrain_lab/combat_deployment_plan.gd")
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Task 1 Data Types & Profiles Test ---")
	
	# 1. Verify all enums exist and have expected values
	assert(Types.CombatOrderResultCode.OK == 0)
	assert(Types.CombatOrderResultCode.FORMATION_INCOMPATIBLE > 0)
	assert(Types.LocalRouteStatus.FOUND == 0)
	assert(Types.LocalRouteStatus.BUDGET_EXHAUSTED > 0)
	assert(Types.CombatDestinationRole.PLATFORM == 0)
	assert(Types.CombatDestinationRole.APPROACH_QUEUE == 1)
	assert(Types.SlotVacancyReason.MEMBER_DEAD == 0)
	assert(Types.SlotVacancyReason.MEMBER_REMOVED == 1)
	assert(Types.SlotVacancyReason.TEMPORARY_ABSENCE == 3)
	
	# 2. Verify FormationMovementProfile
	var prof = Profile.default_infantry()
	assert(prof.allowed_terrain_mask == TerrainData.Flag.WALKABLE)
	assert(prof.max_step_height == 1)
	assert(prof.can_use_ramp == true)
	assert(prof.footprint_cells == 1)
	assert(prof.profile_hash != 0)
	
	var copy = prof.duplicate_profile()
	assert(prof.is_compatible_with(copy))
	
	var restricted = Profile.new(TerrainData.Flag.WALKABLE, 0, false, 1)
	assert(not prof.is_compatible_with(restricted))
	print("TASK 1: FormationMovementProfile tests passed")
	
	# 3. Verify CombatDeploymentPlan & Ingress Gate
	var dep := DeploymentPlan.new()
	dep.formation_id = 1
	dep.order_serial = 100
	
	# Setup 60 platform slots and 40 queue slots
	for y in range(6):
		for x in range(10):
			dep.platform_slots.append(Vector2i(20 + x, 20 + y))
	for y in range(40):
		dep.approach_queue_slots.append(Vector2i(20, 19 - y))
		
	dep.structural_platform_capacity = 60
	dep.available_platform_capacity = 60
	dep.queue_capacity = 40
	dep.requested_count = 100
	
	# Assign 60 platform members (IDs 1001 to 1060) and 40 queue members (IDs 1061 to 1100)
	for i in range(60):
		var mid := 1001 + i
		var slot: Vector2i = dep.platform_slots[i]
		dep.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		dep.member_slot_map[mid] = slot
		dep.slot_owner_map[slot] = mid
		dep.pending_platform_member_ids.append(mid)
		
	for i in range(40):
		var mid := 1061 + i
		var slot: Vector2i = dep.approach_queue_slots[i]
		dep.member_role_map[mid] = Types.CombatDestinationRole.APPROACH_QUEUE
		dep.member_slot_map[mid] = slot
		dep.slot_owner_map[slot] = mid
		dep.queue_member_ids.append(mid)
		
	assert(dep.is_platform_member(1001))
	assert(dep.is_queue_member(1061))
	assert(dep.get_slot_for_member(1001) == Vector2i(20, 20))
	assert(dep.get_slot_for_member(1061) == Vector2i(20, 19))
	assert(not dep.queue_released, "Queue must not be released while platform members are pending")
	
	# Settle platform members one by one
	for i in range(59):
		dep.mark_platform_member_settled(1001 + i)
	assert(not dep.queue_released, "Queue must remain held until all 60 are settled")
	
	dep.mark_platform_member_settled(1060)
	assert(dep.queue_released, "Queue must release once all platform members have settled")
	print("TASK 1: Ingress admission gate tests passed")
	
	# 4. Verify Vacancy Promotion (Casualty in platform promotes first queue member)
	var dead_platform_mid := 1010
	var vacated_platform_slot: Vector2i = dep.member_slot_map[dead_platform_mid]
	var expected_promoted_mid: int = dep.queue_member_ids[0] # 1061
	assert(expected_promoted_mid == 1061)
	
	dep.remove_member(dead_platform_mid, Types.SlotVacancyReason.MEMBER_DEAD)
	
	# dead member removed
	assert(dep.get_slot_for_member(dead_platform_mid) == Vector2i(-1, -1))
	assert(not dep.slot_owner_map.values().has(dead_platform_mid))
	
	# queue front promoted to platform slot
	assert(dep.is_platform_member(expected_promoted_mid), "Promoted member must have PLATFORM role")
	assert(dep.get_slot_for_member(expected_promoted_mid) == vacated_platform_slot, "Promoted member must take the vacated platform slot")
	assert(dep.slot_owner_map[vacated_platform_slot] == expected_promoted_mid)
	assert(dep.promotion_count == 1)
	assert(dep.queue_member_ids.size() == 39)
	assert(dep.queue_member_ids[0] == 1062, "Queue front must now be the next member (1062)")
	assert(dep.get_slot_for_member(1062) == dep.approach_queue_slots[0], "Next queue member must have shifted to front slot")
	print("TASK 1: Platform vacancy promotion tests passed")
	
	# 5. Verify CombatMovePlan
	var mv := MovePlan.new()
	mv.formation_id = 1
	mv.order_serial = 100
	mv.destination_plan = dep
	
	# Assign member path_s
	mv.member_path_s[1001] = 10.0
	mv.member_path_s[1002] = 15.0
	mv.member_path_s[1003] = 20.0
	assert(is_equal_approx(mv.calculate_median_path_s(), 15.0))
	
	# Remove member from move plan
	mv.remove_member(1002)
	assert(not mv.member_path_s.has(1002))
	assert(is_equal_approx(mv.calculate_median_path_s(), 15.0)) # (10 + 20) / 2 = 15
	print("TASK 1: CombatMovePlan tests passed")
	
	# 6. Verify TerrainArmy integration
	var data := Helper.build_flat_map(40, 40)
	var army := Helper.create_test_army(data, 1, 0, 100, Vector2i(10, 10))
	army._combat_move_plan = mv
	army._combat_deployment_plan = dep
	army._formation_movement_profile = prof
	
	# Test casualty via apply_unit_contact removes member from plans cleanly
	var casualty_mid := army.combat_identity(5)
	army.apply_unit_contact(5, {"result": {"hp": 0.0, "stun": 100.0, "guard_break": false}, "shield": false})
	assert(not army._combat_move_plan.member_path_s.has(casualty_mid))
	assert(not army._combat_deployment_plan.member_slot_map.has(casualty_mid))
	
	# Test clear() resets sub-plans
	army.clear()
	assert(army._combat_move_plan == null)
	assert(army._combat_deployment_plan == null)
	assert(army._formation_movement_profile == null)
	army.queue_free()
	
	print("TASK 1 COMPLETE: All data structures, member_id mapping, and promotion contracts verified!")
	quit(0)
