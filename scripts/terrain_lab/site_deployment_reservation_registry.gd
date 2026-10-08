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

## A synchronous handoff borrows this owner; it does not replace the Site registry.
## Keep original lease objects for rollback and compare their fields as well as identity.
func capture_handoff_state() -> Dictionary:
	var values: Dictionary = {}
	for cell: Vector2i in slot_owners:
		values[cell] = _lease_values(slot_owners[cell])
	return {"slot_owners": slot_owners.duplicate(), "formation_slots": _formation_slots.duplicate(true),
		"next_token": next_token, "lease_values": values}

static func _lease_values(lease: Variant) -> Array:
	if lease == null: return []
	return [lease.formation_id, lease.order_serial, lease.member_id, lease.role,
		lease.cell, lease.temporary_absence_remaining_sec]

func prepare_handoff(returning_team_ids: Array) -> Dictionary:
	var returning: Dictionary = {}
	for identity: Variant in returning_team_ids:
		if not identity is int or int(identity) <= 0 or returning.has(identity):
			return {"ok": false, "reason": "INVALID_RETURNING_TEAM"}
		returning[identity] = true
	var source: Dictionary = capture_handoff_state()
	var candidate := SiteDeploymentReservationRegistry.new()
	candidate.next_token = next_token
	candidate._formation_slots = _formation_slots.duplicate(true)
	for cell: Vector2i in slot_owners:
		var old: Variant = slot_owners[cell]
		if old == null:
			candidate.slot_owners[cell] = null
			continue
		var lease := Types.DeploymentSlotLease.new(old.formation_id, old.member_id, old.role, old.cell)
		lease.order_serial = old.order_serial
		lease.temporary_absence_remaining_sec = old.temporary_absence_remaining_sec
		candidate.slot_owners[cell] = lease
	for identity: int in returning:
		candidate.release_order(identity)
	return {"ok": true, "candidate": candidate, "source": source, "returning": returning}

func publish_handoff(prepared: Dictionary) -> Dictionary:
	var candidate: Variant = prepared.get("candidate")
	if not candidate is SiteDeploymentReservationRegistry or not prepared.get("source") is Dictionary or not prepared.get("returning") is Dictionary:
		return {"ok": false, "reason": "INVALID_HANDOFF_RESERVATIONS"}
	var source: Dictionary = prepared.source
	if capture_handoff_state() != source:
		return {"ok": false, "reason": "STALE_RESERVATIONS"}
	var returning: Dictionary = prepared.returning
	var slots: Dictionary = source.slot_owners.duplicate()
	var indexes: Dictionary = source.formation_slots.duplicate(true)
	var foreign_values: Dictionary = source.lease_values.duplicate(true)
	for cell: Vector2i in source.slot_owners:
		var lease: Variant = source.slot_owners[cell]
		if lease != null and returning.has(lease.formation_id):
			slots.erase(cell)
			foreign_values.erase(cell)
	for identity: int in returning:
		indexes.erase(identity)
	var candidate_foreign: Dictionary = {}
	var candidate_indexes: Dictionary = candidate._formation_slots.duplicate(true)
	for cell: Vector2i in candidate.slot_owners:
		var lease: Variant = candidate.slot_owners[cell]
		if lease != null and returning.has(lease.formation_id):
			if lease.cell != cell or not candidate._formation_slots.get(lease.formation_id, []).has(cell):
				return {"ok": false, "reason": "INVALID_HANDOFF_RESERVATIONS"}
			slots[cell] = lease
		else:
			candidate_foreign[cell] = _lease_values(lease)
	for identity: int in returning:
		candidate_indexes.erase(identity)
	if candidate_foreign != foreign_values or candidate_indexes != indexes or candidate.next_token < next_token:
		return {"ok": false, "reason": "FOREIGN_RESERVATIONS_CHANGED"}
	for identity: int in returning:
		if not candidate._formation_slots.has(identity): continue
		var cells: Array = candidate._formation_slots[identity]
		for cell: Vector2i in cells:
			var lease: Variant = candidate.slot_owners.get(cell)
			if lease == null or lease.formation_id != identity:
				return {"ok": false, "reason": "INVALID_HANDOFF_RESERVATIONS"}
		indexes[identity] = cells.duplicate()
	# No admission can fail below this point. Foreign leases are the original objects.
	slot_owners.clear()
	slot_owners.merge(slots)
	_formation_slots.clear()
	_formation_slots.merge(indexes)
	next_token = candidate.next_token
	return {"ok": true, "rollback": source}

func restore_handoff_state(snapshot: Dictionary) -> void:
	# Only the caller's synchronous rollback boundary may restore this snapshot.
	slot_owners.clear()
	slot_owners.merge(snapshot.slot_owners)
	_formation_slots.clear()
	_formation_slots.merge(snapshot.formation_slots.duplicate(true))
	next_token = int(snapshot.next_token)

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

# Additive work leases stay in the original slot_owners/_formation_slots owner.
func reserve_work_slot(formation_id: int, order_serial: int, member_id: int, cell: Vector2i) -> Dictionary:
	if formation_id <= 0 or order_serial <= 0 or member_id <= 0:
		return {"ok": false, "code": "INVALID_WORK_LEASE"}
	if owner_of(cell) != null:
		return {"ok": false, "code": "WORK_SLOT_BUSY"}
	for current: Variant in slot_owners.values():
		if current != null and current.formation_id == formation_id and current.order_serial != order_serial:
			return {"ok": false, "code": "STALE_ORDER"}
	var lease := Types.DeploymentSlotLease.new(formation_id, member_id, Types.CombatDestinationRole.SUPPRESS_WORK, cell)
	lease.order_serial = order_serial
	slot_owners[cell] = lease
	var slots: Array = _formation_slots.get(formation_id, [])
	if not slots.has(cell): slots.append(cell)
	_formation_slots[formation_id] = slots
	return {"ok": true, "lease": lease}

func release_work_slot(lease: Variant) -> Dictionary:
	if lease == null or not lease is Types.DeploymentSlotLease or lease.role != Types.CombatDestinationRole.SUPPRESS_WORK:
		return {"ok": false, "code": "INVALID_WORK_LEASE"}
	var current: Variant = owner_of(lease.cell)
	if current == null: return {"ok": true, "released": false}
	if not is_same(current, lease):
		return {"ok": false, "code": "STALE_WORK_LEASE", "released": false}
	release_slots(lease.formation_id, lease.order_serial, [lease.cell])
	return {"ok": true, "released": true}

# The caller first suspends the original unsafe obligation. A failure never
# recreates it. Safe leases stay the SAME objects in this original Registry.
func release_fire_unsafe_leases(formation_id: int, order_serial: int, expected: Array) -> Dictionary:
	var cells: Array[Vector2i] = []
	var seen := {}
	for lease: Variant in expected:
		if lease == null or not lease is Types.DeploymentSlotLease or lease.formation_id != formation_id \
			or lease.order_serial != order_serial or not is_same(owner_of(lease.cell), lease):
			return {"ok": false, "code": "STALE_UNSAFE_LEASE"}
		if seen.has(lease.cell): continue
		seen[lease.cell] = true
		cells.append(lease.cell)
	release_slots(formation_id, order_serial, cells)
	return {"ok": true, "released": cells}

func try_replace_hazard_subset(formation_id: int, order_serial: int, expected: Array, assignments: Array) -> Dictionary:
	if formation_id <= 0 or order_serial <= 0: return {"ok": false, "code": "INVALID_HAZARD_LEASE"}
	for lease: Variant in slot_owners.values():
		if lease != null and lease.formation_id == formation_id and lease.order_serial != order_serial:
			return {"ok": false, "code": "STALE_HAZARD_ORDER"}
	var removed := {}
	for lease: Variant in expected:
		if lease == null or not lease is Types.DeploymentSlotLease or lease.formation_id != formation_id \
			or lease.order_serial != order_serial or not is_same(owner_of(lease.cell), lease):
			return {"ok": false, "code": "STALE_HAZARD_LEASE"}
		removed[lease.cell] = lease
	var cells := {}
	var members := {}
	for value: Variant in assignments:
		if not value is Dictionary or not value.get("cell") is Vector2i or not value.get("member_id") is int \
			or int(value.member_id) <= 0 or not value.get("role") is int \
			or int(value.role) not in [Types.CombatDestinationRole.PLATFORM, Types.CombatDestinationRole.APPROACH_QUEUE]:
			return {"ok": false, "code": "INVALID_HAZARD_ASSIGNMENT"}
		if cells.has(value.cell) or members.has(value.member_id): return {"ok": false, "code": "DUPLICATE_HAZARD_ASSIGNMENT"}
		var occupied: Variant = owner_of(value.cell)
		if occupied != null and not removed.has(value.cell): return {"ok": false, "code": "RESERVATION_CONFLICT"}
		cells[value.cell] = true
		members[value.member_id] = true
	# Validation is complete; no callback or fallible admission follows mutation.
	var old_cells: Array = removed.keys()
	release_slots(formation_id, order_serial, old_cells)
	var owned: Array = _formation_slots.get(formation_id, [])
	var leases := {}
	for value: Dictionary in assignments:
		var lease := Types.DeploymentSlotLease.new(formation_id, int(value.member_id), int(value.role), value.cell)
		lease.order_serial = order_serial
		slot_owners[value.cell] = lease
		if not owned.has(value.cell): owned.append(value.cell)
		leases[int(value.member_id)] = lease
	if not owned.is_empty(): _formation_slots[formation_id] = owned
	return {"ok": true, "leases": leases}

# Pure durable values; the original Registry remains the only lease owner.
func fire_lease_snapshot(formation_ids: Array = []) -> Dictionary:
	var rows: Array[Dictionary] = []
	var cells: Array = slot_owners.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
	for cell: Vector2i in cells:
		var lease: Variant = slot_owners[cell]
		if lease == null or not formation_ids.is_empty() and not formation_ids.has(lease.formation_id): continue
		rows.append({"team_id":int(lease.formation_id),"order_serial":int(lease.order_serial),
			"member_id":int(lease.member_id),"role":int(lease.role),"cell":[cell.x,cell.y],
			"absence_left":float(lease.temporary_absence_remaining_sec)})
	return {"version":1,"next_token":next_token,"leases":rows}

static func _fire_saved_integer(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

func prepare_fire_lease_restore(snapshot: Dictionary, returning_team_ids: Array, terrain: TerrainData) -> Dictionary:
	if terrain == null or not _fire_saved_integer(snapshot.get("version"), 1, 1) \
		or not _fire_saved_integer(snapshot.get("next_token"), 1) or not snapshot.get("leases") is Array \
		or snapshot.leases.size() > terrain.size.x * terrain.size.y:
		return {"ok":false,"reason":"INVALID_FIRE_LEASE_SNAPSHOT"}
	var normalized: Array[int] = []
	for raw: Variant in returning_team_ids:
		if not _fire_saved_integer(raw, 1) or normalized.has(int(raw)): return {"ok":false,"reason":"INVALID_RETURNING_TEAM"}
		normalized.append(int(raw))
	var prepared := prepare_handoff(normalized)
	if not prepared.ok: return prepared
	var candidate: SiteDeploymentReservationRegistry = prepared.candidate
	var seen := {}
	var epochs := {}
	var members := {}
	for raw: Variant in snapshot.leases:
		if not raw is Dictionary: return {"ok":false,"reason":"INVALID_FIRE_LEASE_ROW"}
		var row: Dictionary = raw
		if not _fire_saved_integer(row.get("team_id"),1) or not normalized.has(int(row.team_id)) \
			or not _fire_saved_integer(row.get("order_serial"),1) or not _fire_saved_integer(row.get("member_id")) \
			or not _fire_saved_integer(row.get("role"),0,Types.CombatDestinationRole.SUPPRESS_WORK) \
			or not row.get("cell") is Array or row.cell.size() != 2 \
			or not _fire_saved_integer(row.cell[0],0,terrain.size.x-1) or not _fire_saved_integer(row.cell[1],0,terrain.size.y-1) \
			or not (row.get("absence_left") is float or row.get("absence_left") is int) \
			or not is_finite(float(row.absence_left)) or float(row.absence_left) < 0.0:
			return {"ok":false,"reason":"INVALID_FIRE_LEASE_ROW"}
		var fid := int(row.team_id)
		var serial := int(row.order_serial)
		var mid := int(row.member_id)
		var cell := Vector2i(int(row.cell[0]),int(row.cell[1]))
		if seen.has(cell) or candidate.owner_of(cell) != null: return {"ok":false,"reason":"FIRE_LEASE_CONFLICT"}
		if epochs.has(fid) and int(epochs[fid]) != serial: return {"ok":false,"reason":"MIXED_FIRE_LEASE_EPOCH"}
		if int(row.role) == Types.CombatDestinationRole.SUPPRESS_WORK:
			if mid <= 0 or members.has(mid): return {"ok":false,"reason":"DUPLICATE_FIRE_WORK_MEMBER"}
			members[mid] = true
		seen[cell] = true
		epochs[fid] = serial
		var lease := Types.DeploymentSlotLease.new(fid,mid,int(row.role),cell)
		lease.order_serial = serial
		lease.temporary_absence_remaining_sec = float(row.absence_left)
		candidate.slot_owners[cell] = lease
		if not candidate._formation_slots.has(fid): candidate._formation_slots[fid] = []
		candidate._formation_slots[fid].append(cell)
	# Monotonic tokens preserve the original publish_handoff contract even when
	# restoring a saved formation into an already active Site registry.
	candidate.next_token = maxi(candidate.next_token,int(snapshot.next_token))
	return prepared
