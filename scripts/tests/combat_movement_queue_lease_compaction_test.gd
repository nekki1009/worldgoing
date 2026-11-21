extends SceneTree
## A temporary queue vacancy must remain leased during another casualty's compaction.

const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const DeploymentPlan = preload("res://scripts/terrain_lab/combat_deployment_plan.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var plan: CombatDeploymentPlan = DeploymentPlan.new()
	var slots: Array[Vector2i] = [Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 7)]
	var members: Array[int] = [1001, 1002, 1003]
	plan.approach_queue_slots.assign(slots)
	plan.queue_member_ids.assign(members)
	for i in range(members.size()):
		plan.member_role_map[members[i]] = Types.CombatDestinationRole.APPROACH_QUEUE
		plan.member_slot_map[members[i]] = slots[i]
		plan.slot_owner_map[slots[i]] = members[i]
	plan.remove_member(members[0], Types.SlotVacancyReason.TEMPORARY_ABSENCE)
	assert(plan.slot_lease_timers.has(slots[0]) and not plan.slot_owner_map.has(slots[0]))
	plan.remove_member(members[1], Types.SlotVacancyReason.MEMBER_DEAD)
	assert(plan.queue_member_ids == [members[2]])
	assert(plan.member_slot_map[members[2]] == slots[1] and plan.slot_owner_map[slots[1]] == members[2])
	assert(plan.slot_lease_timers.has(slots[0]) and not plan.slot_owner_map.has(slots[0]),
		"Another casualty cannot assign a living queue member to the KO lease")
	assert(plan.member_return_from_absence(members[0], slots[0]))
	assert(plan.queue_member_ids == [members[0], members[2]])
	assert(plan.member_slot_map[members[0]] == slots[0] and plan.slot_owner_map[slots[0]] == members[0]
		and plan.member_slot_map[members[2]] == slots[1] and plan.slot_owner_map[slots[1]] == members[2]
		and plan.slot_lease_timers.is_empty(), "Return must reclaim the lease without changing queue order")
	plan.remove_member(members[0], Types.SlotVacancyReason.TEMPORARY_ABSENCE)
	plan.update_leases(4.1)
	assert(not plan.slot_lease_timers.has(slots[0]) and plan.member_slot_map[members[2]] == slots[0]
		and plan.slot_owner_map[slots[0]] == members[2], "Expired lease must let the remaining queue close the gap")
	print("COMBAT MOVEMENT QUEUE LEASE COMPACTION PASS")
	quit(0)
