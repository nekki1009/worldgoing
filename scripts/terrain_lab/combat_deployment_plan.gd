class_name CombatDeploymentPlan
extends RefCounted
## Authoritative destination deployment plan decoupled from movement execution.
## Holds platform slots (deep-to-shallow), approach queue slots, ingress admission gate state,
## and vacancy promotion logic. Keyed strictly by persistent member_id.

const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

var formation_id: int = 0
var order_serial: int = 0
var resolved_anchor: Vector2i = Vector2i(-1, -1)
var terrain_revision: int = 0
var roster_revision: int = 0
var final_facing: Vector2i = Vector2i(1, 0)
var final_width: int = 1
var final_depth: int = 1
var shape_version: int = 1
var formation_preset_id: String = "auto"
var assignment_epoch: int = 0
var slot_tactical_roles: Dictionary = {} # Vector2i -> TacticalSlotRole
var member_slot_locked: Dictionary = {} # member_id -> bool
var admitted_platform_member_ids: Array[int] = []
# An entrant may briefly step outside the footprint while navigating around
# occupied final slots. Keep its arrival history for target resolution.
var ever_admitted_platform_member_ids: Dictionary = {} # member_id -> true

var platform_footprint: Array[Vector2i] = []
var ingress_path: Array[Vector2i] = []
var ingress_cell: Vector2i = Vector2i(-1, -1)
var queue_hold_path_s: float = -1.0
var queue_hold_cross_section: Array[Vector2i] = []
var ingress_buffer_cells: Array[Vector2i] = []

var platform_slots: Array[Vector2i] = []
var centered_platform_handoff: Vector2i = Vector2i(-1, -1) # Derived from immutable final cells; rebuilt after load.
var approach_bottlenecked: int = -1 # -1 unknown after load; 0 broad-open, 1 contains a width-one route edge.
var approach_last_bottleneck_cell: Vector2i = Vector2i(-1, -1) # Derived from current macro path.
var approach_queue_slots: Array[Vector2i] = []
var ingress_staging_slots: Array[Vector2i] = []

var structural_platform_capacity: int = 0
var available_platform_capacity: int = 0
var queue_capacity: int = 0
var requested_count: int = 0

# Member mappings strictly keyed by member_id (int)
var member_role_map: Dictionary = {}      # member_id -> Types.CombatDestinationRole
var member_slot_map: Dictionary = {}      # member_id -> Vector2i
var queue_member_ids: Array[int] = []     # front to rear
var pending_platform_member_ids: Array[int] = []
var settled_platform_member_ids: Array[int] = []
var settled_queue_member_ids: Array[int] = []

var ingress_staging_required: bool = false
var ingress_staging_complete: bool = false
var queue_released: bool = false

var slot_owner_map: Dictionary = {}       # Vector2i slot -> member_id
var slot_lease_timers: Dictionary = {}    # Vector2i slot -> float seconds remaining
var slot_lease_owner_map: Dictionary = {} # Vector2i slot -> original member_id
var slot_lease_role_map: Dictionary = {} # Vector2i slot -> CombatDestinationRole
var slot_lease_queue_index_map: Dictionary = {} # Vector2i slot -> prior queue index
var promotion_count: int = 0
var reservation_token: int = 0

func set_approach_bottlenecked(value: bool, last_bottleneck_cell: Vector2i = Vector2i(-1, -1)) -> void:
	approach_bottlenecked = 1 if value else 0
	approach_last_bottleneck_cell = last_bottleneck_cell if value else Vector2i(-1, -1)
	centered_platform_handoff = Vector2i(-1, -1)

func get_platform_handoff_cell() -> Vector2i:
	if centered_platform_handoff != Vector2i(-1, -1):
		return centered_platform_handoff
	var handoff: Vector2i = resolved_anchor
	if platform_slots.size() >= 20 and platform_footprint.size() >= platform_slots.size() * 2:
		var shallow_offset := 0
		for slot in platform_slots:
			var offset: Vector2i = slot - resolved_anchor
			shallow_offset = mini(shallow_offset, offset.x * final_facing.x + offset.y * final_facing.y)
		if shallow_offset < 0:
			var shallow_approach: Vector2i = handoff + final_facing * (shallow_offset - 1)
			var after_choke: int = (shallow_approach.x - approach_last_bottleneck_cell.x) * final_facing.x + (shallow_approach.y - approach_last_bottleneck_cell.y) * final_facing.y
			if approach_bottlenecked == 0 or (approach_last_bottleneck_cell != Vector2i(-1, -1) and after_choke >= 2):
				handoff = shallow_approach
	centered_platform_handoff = handoff
	return handoff

func needs_transit_soft_target(member_id: int, current_cell: Vector2i) -> bool:
	if not is_platform_member(member_id) or not platform_footprint.has(current_cell):
		return false
	var final_slot: Vector2i = get_slot_for_member(member_id)
	var distance_to_final: int = absi(current_cell.x - final_slot.x) + absi(current_cell.y - final_slot.y)
	if distance_to_final <= 2:
		return false
	var entry_distance: int = absi(final_slot.x - ingress_cell.x) + absi(final_slot.y - ingress_cell.y)
	if entry_distance <= 8:
		return false
	var handoff: Vector2i = get_platform_handoff_cell()
	var approach: Vector2i = handoff - ingress_cell
	return (current_cell.x - handoff.x) * approach.x + (current_cell.y - handoff.y) * approach.y < 0

func get_slot_for_member(member_id: int) -> Vector2i:
	return member_slot_map.get(member_id, Vector2i(-1, -1))

## Circle facing belongs to the final cell, so role exchanges never move it.
func get_facing_for_slot(cell: Vector2i) -> Vector2i:
	if formation_preset_id != "circle" or not platform_slots.has(cell):
		return final_facing
	var side := Vector2i(-final_facing.y, final_facing.x)
	var offset := cell - resolved_anchor
	var lateral: int = offset.x * side.x + offset.y * side.y
	var forward: int = offset.x * final_facing.x + offset.y * final_facing.y
	if absi(lateral) > absi(forward):
		return side if lateral > 0 else -side
	return final_facing if forward >= 0 else -final_facing

func get_role_for_member(member_id: int) -> int:
	return member_role_map.get(member_id, Types.CombatDestinationRole.PLATFORM)

func is_platform_member(member_id: int) -> bool:
	return get_role_for_member(member_id) == Types.CombatDestinationRole.PLATFORM

func is_queue_member(member_id: int) -> bool:
	return get_role_for_member(member_id) == Types.CombatDestinationRole.APPROACH_QUEUE

func is_slot_locked(member_id: int) -> bool:
	return bool(member_slot_locked.get(member_id, false))

func lock_member_slot(member_id: int) -> void:
	if member_slot_map.has(member_id):
		member_slot_locked[member_id] = true

func swap_member_slots(first_id: int, second_id: int) -> bool:
	if first_id == second_id or is_slot_locked(first_id) or is_slot_locked(second_id):
		return false
	if not member_slot_map.has(first_id) or not member_slot_map.has(second_id):
		return false
	if get_role_for_member(first_id) != get_role_for_member(second_id):
		return false
	var first_slot: Vector2i = member_slot_map[first_id]
	var second_slot: Vector2i = member_slot_map[second_id]
	if first_slot == second_slot or slot_owner_map.get(first_slot, -1) != first_id or slot_owner_map.get(second_slot, -1) != second_id:
		return false
	# Tactical identity belongs to the member. A target exchange must not turn
	# an ordinary soldier into the commander merely because their cells trade.
	var first_tactical: int = int(slot_tactical_roles.get(first_slot, Types.TacticalSlotRole.FLEX))
	var second_tactical: int = int(slot_tactical_roles.get(second_slot, Types.TacticalSlotRole.FLEX))
	member_slot_map[first_id] = second_slot
	member_slot_map[second_id] = first_slot
	slot_owner_map[first_slot] = second_id
	slot_owner_map[second_slot] = first_id
	slot_tactical_roles[first_slot] = second_tactical
	slot_tactical_roles[second_slot] = first_tactical
	assignment_epoch += 1
	return true

## Reserves a vacancy-terminated sequence of ordinary final targets in one assignment epoch.
## The caller supplies each physical occupant and its adjacent next cell; no cell moves here.
func rotate_vacancy_chain_targets(actors: Array[int], targets: Array[Vector2i]) -> Array[int]:
	var changed: Array[int] = []
	if actors.is_empty() or actors.size() != targets.size():
		return changed
	var actor_set: Dictionary = {}
	var target_set: Dictionary = {}
	var affected: Dictionary = {}
	for i in range(actors.size()):
		var actor: int = actors[i]
		var target: Vector2i = targets[i]
		if actor_set.has(actor) or target_set.has(target) or not member_slot_map.has(actor) or not slot_owner_map.has(target):
			return []
		actor_set[actor] = true
		target_set[target] = true
		affected[actor] = true
		affected[int(slot_owner_map[target])] = true
	var remaining_slots: Array[Vector2i] = []
	var remaining_members: Array[int] = []
	var new_member_slots: Dictionary = member_slot_map.duplicate()
	var new_owners: Dictionary = slot_owner_map.duplicate()
	var tactical_by_member: Dictionary = {}
	for mid in affected.keys():
		var old_slot: Vector2i = member_slot_map[mid]
		if not is_platform_member(mid):
			return []
		tactical_by_member[mid] = slot_tactical_roles.get(old_slot, Types.TacticalSlotRole.FLEX)
		if is_slot_locked(mid) and not actor_set.has(mid):
			return []
		if not actor_set.has(mid):
			remaining_members.append(mid)
		if not target_set.has(old_slot):
			remaining_slots.append(old_slot)
	if remaining_members.size() != remaining_slots.size():
		return []
	remaining_members.sort()
	remaining_slots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	for mid in affected.keys():
		new_owners.erase(member_slot_map[mid])
	for i in range(actors.size()):
		new_member_slots[actors[i]] = targets[i]
	for i in range(remaining_members.size()):
		new_member_slots[remaining_members[i]] = remaining_slots[i]
	for mid in affected.keys():
		var new_slot: Vector2i = new_member_slots[mid]
		new_owners[new_slot] = mid
		if new_slot != member_slot_map[mid]:
			changed.append(mid)
	if changed.is_empty():
		return changed
	member_slot_map = new_member_slots
	slot_owner_map = new_owners
	for mid in affected.keys():
		slot_tactical_roles[new_member_slots[mid]] = tactical_by_member[mid]
	for actor in actors:
		member_slot_locked.erase(actor)
		settled_platform_member_ids.erase(actor)
	assignment_epoch += 1
	return changed

func exchange_queue_platform_roles(queue_id: int, platform_id: int) -> bool:
	if queue_id == platform_id or not is_queue_member(queue_id) or not is_platform_member(platform_id):
		return false
	if is_slot_locked(queue_id) or is_slot_locked(platform_id) or not pending_platform_member_ids.has(platform_id) or admitted_platform_member_ids.has(platform_id):
		return false
	var queue_index := queue_member_ids.find(queue_id)
	if queue_index < 0 or not member_slot_map.has(queue_id) or not member_slot_map.has(platform_id):
		return false
	var queue_slot: Vector2i = member_slot_map[queue_id]
	var platform_slot: Vector2i = member_slot_map[platform_id]
	if slot_owner_map.get(queue_slot, -1) != queue_id or slot_owner_map.get(platform_slot, -1) != platform_id:
		return false
	var queue_tactical: int = int(slot_tactical_roles.get(queue_slot, Types.TacticalSlotRole.FLEX))
	var platform_tactical: int = int(slot_tactical_roles.get(platform_slot, Types.TacticalSlotRole.FLEX))
	queue_member_ids[queue_index] = platform_id
	pending_platform_member_ids.erase(platform_id)
	pending_platform_member_ids.append(queue_id)
	settled_queue_member_ids.erase(queue_id)
	settled_platform_member_ids.erase(platform_id)
	member_role_map[queue_id] = Types.CombatDestinationRole.PLATFORM
	member_role_map[platform_id] = Types.CombatDestinationRole.APPROACH_QUEUE
	member_slot_map[queue_id] = platform_slot
	member_slot_map[platform_id] = queue_slot
	slot_owner_map[platform_slot] = queue_id
	slot_owner_map[queue_slot] = platform_id
	slot_tactical_roles[platform_slot] = queue_tactical
	slot_tactical_roles[queue_slot] = platform_tactical
	member_slot_locked.erase(queue_id)
	member_slot_locked.erase(platform_id)
	queue_released = false
	promotion_count += 1
	assignment_epoch += 1
	return true

## Marks a platform member as fully arrived and settled at its designated slot.
func mark_platform_member_settled(member_id: int) -> void:
	if not is_platform_member(member_id) or not member_slot_map.has(member_id):
		return
	pending_platform_member_ids.erase(member_id)
	if not admitted_platform_member_ids.has(member_id):
		admitted_platform_member_ids.append(member_id)
	if not settled_platform_member_ids.has(member_id):
		settled_platform_member_ids.append(member_id)
	lock_member_slot(member_id)
	_evaluate_ingress_gate()

## Checks if all platform members have settled or passed the bottleneck, allowing queue release.
func _evaluate_ingress_gate() -> void:
	if pending_platform_member_ids.is_empty() and not queue_released:
		queue_released = true

## Handles casualty, retreat, or removal of a member from the deployment plan.
## If a platform member leaves, it frees a platform slot and immediately promotes the front queue member.
func remove_member(member_id: int, reason: int = Types.SlotVacancyReason.MEMBER_DEAD) -> void:
	if reason != Types.SlotVacancyReason.TEMPORARY_ABSENCE:
		ever_admitted_platform_member_ids.erase(member_id)
	if not member_slot_map.has(member_id):
		if reason != Types.SlotVacancyReason.TEMPORARY_ABSENCE:
			for leased_slot in slot_lease_owner_map.keys():
				if int(slot_lease_owner_map[leased_slot]) == member_id:
					var leased_role: int = int(slot_lease_role_map.get(leased_slot, Types.CombatDestinationRole.PLATFORM))
					slot_lease_timers.erase(leased_slot)
					slot_lease_owner_map.erase(leased_slot)
					slot_lease_role_map.erase(leased_slot)
					slot_lease_queue_index_map.erase(leased_slot)
					if leased_role == Types.CombatDestinationRole.PLATFORM and int(slot_tactical_roles.get(leased_slot, Types.TacticalSlotRole.FLEX)) == Types.TacticalSlotRole.FLEX and not queue_member_ids.is_empty():
						promote_queue_member_to_platform(queue_member_ids.pop_front(), leased_slot)
					elif leased_role == Types.CombatDestinationRole.APPROACH_QUEUE:
						_shift_queue_forward()
		return

	var vacated_slot: Vector2i = member_slot_map[member_id]
	var role: int = member_role_map.get(member_id, Types.CombatDestinationRole.PLATFORM)
	var old_queue_index: int = queue_member_ids.find(member_id)

	member_slot_map.erase(member_id)
	member_role_map.erase(member_id)
	member_slot_locked.erase(member_id)
	admitted_platform_member_ids.erase(member_id)
	pending_platform_member_ids.erase(member_id)
	settled_platform_member_ids.erase(member_id)
	settled_queue_member_ids.erase(member_id)
	queue_member_ids.erase(member_id)
	slot_owner_map.erase(vacated_slot)

	if reason == Types.SlotVacancyReason.TEMPORARY_ABSENCE:
		# Keep lease timer (4.0 seconds grace period)
		slot_lease_timers[vacated_slot] = 4.0
		slot_lease_owner_map[vacated_slot] = member_id
		slot_lease_role_map[vacated_slot] = role
		if role == Types.CombatDestinationRole.APPROACH_QUEUE:
			slot_lease_queue_index_map[vacated_slot] = old_queue_index
		return

	slot_lease_timers.erase(vacated_slot)
	slot_lease_owner_map.erase(vacated_slot)
	slot_lease_role_map.erase(vacated_slot)
	slot_lease_queue_index_map.erase(vacated_slot)

	# If a platform slot was vacated and there is someone waiting in the queue, promote the front queue member
	if role == Types.CombatDestinationRole.PLATFORM and int(slot_tactical_roles.get(vacated_slot, Types.TacticalSlotRole.FLEX)) == Types.TacticalSlotRole.FLEX and not queue_member_ids.is_empty():
		var candidate_id: int = queue_member_ids.pop_front()
		promote_queue_member_to_platform(candidate_id, vacated_slot)
	elif role == Types.CombatDestinationRole.APPROACH_QUEUE:
		_shift_queue_forward()

## Updates temporary absence leases and promotes queue members when leases expire
func update_leases(delta: float) -> void:
	var expired_slots: Array[Vector2i] = []
	for slot in slot_lease_timers.keys():
		var remaining: float = float(slot_lease_timers[slot]) - delta
		if remaining <= 0.0:
			expired_slots.append(slot)
		else:
			slot_lease_timers[slot] = remaining

	for slot in expired_slots:
		var role: int = int(slot_lease_role_map.get(slot, Types.CombatDestinationRole.PLATFORM))
		slot_lease_timers.erase(slot)
		slot_lease_owner_map.erase(slot)
		slot_lease_role_map.erase(slot)
		slot_lease_queue_index_map.erase(slot)
		if role == Types.CombatDestinationRole.PLATFORM and int(slot_tactical_roles.get(slot, Types.TacticalSlotRole.FLEX)) == Types.TacticalSlotRole.FLEX and not queue_member_ids.is_empty():
			var candidate_id: int = queue_member_ids.pop_front()
			promote_queue_member_to_platform(candidate_id, slot)
		elif role == Types.CombatDestinationRole.APPROACH_QUEUE:
			_shift_queue_forward()

## Handles return of a member before its lease expired
func member_return_from_absence(member_id: int, slot: Vector2i) -> bool:
	if not slot_lease_timers.has(slot):
		return false
	if int(slot_lease_owner_map.get(slot, -1)) != member_id or slot_owner_map.has(slot):
		return false
	var role: int = int(slot_lease_role_map.get(slot, Types.CombatDestinationRole.PLATFORM))
	var queue_index: int = int(slot_lease_queue_index_map.get(slot, queue_member_ids.size()))
	slot_lease_timers.erase(slot)
	slot_lease_owner_map.erase(slot)
	slot_lease_role_map.erase(slot)
	slot_lease_queue_index_map.erase(slot)
	member_role_map[member_id] = role
	member_slot_map[member_id] = slot
	slot_owner_map[slot] = member_id
	if role == Types.CombatDestinationRole.PLATFORM:
		if not pending_platform_member_ids.has(member_id):
			pending_platform_member_ids.append(member_id)
	else:
		queue_member_ids.insert(clampi(queue_index, 0, queue_member_ids.size()), member_id)
	return true

## Read-only candidate for a returning member; lets Army reserve across teams first.
func preview_returning_member_slot(member_id: int, previous_slot: Vector2i, registry: Object = null) -> Vector2i:
	if member_slot_map.has(member_id):
		return member_slot_map[member_id]
	var owns_lease: bool = slot_lease_timers.has(previous_slot) and int(slot_lease_owner_map.get(previous_slot, -1)) == member_id
	if owns_lease and not slot_owner_map.has(previous_slot) and (registry == null or not registry.is_slot_reserved(previous_slot, formation_id)):
		return previous_slot
	if (platform_slots.has(previous_slot) or approach_queue_slots.has(previous_slot)) and not slot_owner_map.has(previous_slot) and not slot_lease_timers.has(previous_slot) and (registry == null or not registry.is_slot_reserved(previous_slot, formation_id)):
		return previous_slot
	for candidate in approach_queue_slots:
		if not slot_owner_map.has(candidate) and not slot_lease_timers.has(candidate) and (registry == null or not registry.is_slot_reserved(candidate, formation_id)):
			return candidate
	return Vector2i(-1, -1)

## Rejoins the same MOVE after its temporary lease expired, using only an unowned slot.
func reassign_returning_member(member_id: int, previous_slot: Vector2i, registry: Object = null) -> bool:
	if member_slot_map.has(member_id):
		return true
	var slot: Vector2i = preview_returning_member_slot(member_id, previous_slot, registry)
	if slot == Vector2i(-1, -1):
		return false
	if slot == previous_slot and member_return_from_absence(member_id, previous_slot):
		return true
	var role: int = Types.CombatDestinationRole.PLATFORM if platform_slots.has(slot) else Types.CombatDestinationRole.APPROACH_QUEUE
	member_role_map[member_id] = role
	member_slot_map[member_id] = slot
	slot_owner_map[slot] = member_id
	member_slot_locked.erase(member_id)
	if role == Types.CombatDestinationRole.PLATFORM:
		pending_platform_member_ids.append(member_id)
		queue_released = false
	else:
		queue_member_ids.append(member_id)
	assignment_epoch += 1
	return true

## Moves the COMMANDER tactical marker to the newly elected platform member's
## existing final cell, making the departed commander's rear slot ordinary again.
func rebind_commander_slot(new_commander_id: int, vacant_commander_slot: Vector2i) -> bool:
	if slot_owner_map.has(vacant_commander_slot) or int(slot_tactical_roles.get(vacant_commander_slot, Types.TacticalSlotRole.FLEX)) != Types.TacticalSlotRole.COMMANDER:
		return false
	if is_platform_member(new_commander_id) and member_slot_map.has(new_commander_id):
		var successor_slot: Vector2i = member_slot_map[new_commander_id]
		slot_tactical_roles[successor_slot] = Types.TacticalSlotRole.COMMANDER
		slot_tactical_roles[vacant_commander_slot] = Types.TacticalSlotRole.FLEX
		assignment_epoch += 1
		if not queue_member_ids.is_empty():
			promote_queue_member_to_platform(queue_member_ids.pop_front(), vacant_commander_slot)
		return true
	if is_queue_member(new_commander_id) and queue_member_ids.has(new_commander_id):
		queue_member_ids.erase(new_commander_id)
		promote_queue_member_to_platform(new_commander_id, vacant_commander_slot)
		return true
	return false


## Promotes a member from queue role to platform role, assigning the target platform slot.
func promote_queue_member_to_platform(candidate_id: int, target_slot: Vector2i) -> void:
	var old_queue_slot: Vector2i = member_slot_map.get(candidate_id, Vector2i(-1, -1))
	if old_queue_slot != Vector2i(-1, -1):
		slot_owner_map.erase(old_queue_slot)

	member_role_map[candidate_id] = Types.CombatDestinationRole.PLATFORM
	member_slot_locked.erase(candidate_id)
	settled_queue_member_ids.erase(candidate_id)
	member_slot_map[candidate_id] = target_slot
	slot_owner_map[target_slot] = candidate_id
	slot_lease_timers.erase(target_slot)
	slot_lease_owner_map.erase(target_slot)
	slot_lease_role_map.erase(target_slot)
	slot_lease_queue_index_map.erase(target_slot)

	if not settled_platform_member_ids.has(candidate_id) and not pending_platform_member_ids.has(candidate_id):
		pending_platform_member_ids.append(candidate_id)
	queue_released = false

	promotion_count += 1
	assignment_epoch += 1
	_shift_queue_forward()

## Compacts the queue in order without assigning a temporarily leased slot.
func _shift_queue_forward() -> void:
	var available_slots: Array[Vector2i] = []
	for slot in approach_queue_slots:
		if not slot_lease_timers.has(slot):
			available_slots.append(slot)
	if available_slots.size() < queue_member_ids.size():
		return
	for mid in queue_member_ids:
		var old_slot: Vector2i = member_slot_map.get(mid, Vector2i(-1, -1))
		if slot_owner_map.get(old_slot, -1) == mid:
			slot_owner_map.erase(old_slot)
	for i in range(queue_member_ids.size()):
		var mid: int = queue_member_ids[i]
		var old_slot: Vector2i = member_slot_map.get(mid, Vector2i(-1, -1))
		var new_slot: Vector2i = available_slots[i]
		if old_slot != new_slot:
			member_slot_map[mid] = new_slot
			assignment_epoch += 1
		slot_owner_map[new_slot] = mid
