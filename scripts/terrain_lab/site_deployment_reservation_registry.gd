class_name SiteDeploymentReservationRegistry
extends RefCounted
## Tracks persistent final destination slot reservations across all formations.
## Prevents multiple formations from claiming the same destination slots and
## guarantees transactional rollback when a new deployment plan cannot be reserved.

const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

## Map: cell (Vector2i) -> DeploymentSlotLease
var slot_owners: Dictionary = {}
## Map: formation_id (int) -> Array[Vector2i]
var _formation_slots: Dictionary = {}
var next_token: int = 1

func begin_tick(_delta: float = 0.0) -> void:
	pass

func owner_of(cell: Vector2i) -> Variant:
	return slot_owners.get(cell, null)

func is_slot_reserved(cell: Vector2i, exclude_formation_id: int = -1) -> bool:
	if not slot_owners.has(cell):
		return false
	var lease: Variant = slot_owners[cell]
	if lease == null:
		return false
	if exclude_formation_id >= 0 and lease.formation_id == exclude_formation_id:
		return false
	return true

## Transactional reservation replacement.
## During validation, all existing slots for this formation must belong to old_order_serial.
## If that serial is stale or any new slot is owned by another formation, the transaction is rejected and
## the old reservations are preserved completely (no partial modification).
func try_replace_reservations(
	formation_id: int,
	old_order_serial: int,
	new_order_serial: int,
	new_slots: Array,
	slot_roles: Dictionary = {}
) -> Dictionary:
	var conflicts: Array[Vector2i] = []
	var deduped_new_cells: Array[Vector2i] = []
	var seen_cells: Dictionary = {}
	var old_cells: Array[Vector2i] = []
	var stale_cells: Array[Vector2i] = []
	for cell: Vector2i in slot_owners.keys():
		var lease: Variant = slot_owners[cell]
		if lease == null or lease.formation_id != formation_id:
			continue
		old_cells.append(cell)
		if old_order_serial >= 0 and lease.order_serial != old_order_serial:
			stale_cells.append(cell)
	if not stale_cells.is_empty():
		return {
			"ok": false,
			"conflicts": stale_cells,
			"token": 0,
			"reason": "STALE_ORDER"
		}

	# 1. Validate all new slots against existing leases
	for slot in new_slots:
		var cell: Vector2i = slot if slot is Vector2i else Vector2i(slot.x, slot.y)
		if seen_cells.has(cell):
			continue
		seen_cells[cell] = true
		deduped_new_cells.append(cell)

		if slot_owners.has(cell):
			var existing_lease = slot_owners[cell]
			if existing_lease != null and existing_lease.formation_id != formation_id:
				# Conflict with another formation's lease
				conflicts.append(cell)

	# If any conflict found, rollback and preserve old reservations intact
	if not conflicts.is_empty():
		return {
			"ok": false,
			"conflicts": conflicts,
			"token": 0
		}

	# 2. Release all old slots, including any that lost their tracking index.
	for cell in old_cells:
		slot_owners.erase(cell)

	# 3. Commit new leases
	var token := next_token
	next_token += 1
	var committed_cells: Array[Vector2i] = []
	for cell in deduped_new_cells:
		var role = slot_roles.get(cell, Types.CombatDestinationRole.PLATFORM)
		var lease = Types.DeploymentSlotLease.new(formation_id, 0, role, cell)
		lease.order_serial = new_order_serial
		slot_owners[cell] = lease
		committed_cells.append(cell)

	_formation_slots[formation_id] = committed_cells
	return {
		"ok": true,
		"conflicts": [],
		"token": token
	}

func release_order(formation_id: int, order_serial: int = -1) -> void:
	var remaining_cells: Array[Vector2i] = []
	for cell: Vector2i in slot_owners.keys():
		var lease: Variant = slot_owners[cell]
		if lease == null or lease.formation_id != formation_id:
			continue
		if order_serial < 0 or lease.order_serial == order_serial:
			slot_owners.erase(cell)
		else:
			remaining_cells.append(cell)
	if remaining_cells.is_empty():
		_formation_slots.erase(formation_id)
	else:
		_formation_slots[formation_id] = remaining_cells

func release_slots(formation_id: int, order_serial: int, slots_to_release: Array) -> void:
	var release_set: Dictionary = {}
	for s in slots_to_release:
		var c: Vector2i = s if s is Vector2i else Vector2i(s.x, s.y)
		if slot_owners.has(c):
			var lease = slot_owners[c]
			if lease != null and lease.formation_id == formation_id:
				if order_serial < 0 or lease.order_serial == order_serial:
					slot_owners.erase(c)
					release_set[c] = true

	if not _formation_slots.has(formation_id):
		return
	var remaining: Array[Vector2i] = []
	for c in _formation_slots[formation_id]:
		if not release_set.has(c):
			remaining.append(c)
	if remaining.is_empty():
		_formation_slots.erase(formation_id)
	else:
		_formation_slots[formation_id] = remaining

func get_formation_reserved_slots(formation_id: int) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	if _formation_slots.has(formation_id):
		for c in _formation_slots[formation_id]:
			res.append(c)
	return res
