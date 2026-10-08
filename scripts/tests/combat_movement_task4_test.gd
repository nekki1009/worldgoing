extends SceneTree
## Unit test suite for Task 4: SiteDeploymentReservationRegistry,
## non-overlapping dual-formation platform reservation, conflict detection,
## and transactional rollback.

const Registry = preload("res://scripts/terrain_lab/site_deployment_reservation_registry.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Task 4 Deployment Registry & Transactional Switch Test ---")
	
	var reg = Registry.new()
	
	# 1. Dual-formation non-overlapping platform reservation
	# Formation 1 reserves 60 platform slots
	var f1_slots: Array[Vector2i] = []
	for y in range(10, 16):
		for x in range(10, 20):
			f1_slots.append(Vector2i(x, y))
	assert(f1_slots.size() == 60)
	
	var res1 = reg.try_replace_reservations(1, 0, 101, f1_slots)
	assert(res1.ok, "Formation 1 initial reservation must succeed")
	assert(reg.get_formation_reserved_slots(1).size() == 60)
	
	# Formation 2 reserves 40 approach slots adjacent to platform
	var f2_slots: Array[Vector2i] = []
	for y in range(16, 20):
		for x in range(10, 20):
			f2_slots.append(Vector2i(x, y))
	assert(f2_slots.size() == 40)
	
	var res2 = reg.try_replace_reservations(2, 0, 201, f2_slots)
	assert(res2.ok, "Formation 2 non-overlapping reservation must succeed")
	assert(reg.get_formation_reserved_slots(2).size() == 40)
	
	# Verify ownership of slots
	for cell in f1_slots:
		var lease = reg.owner_of(cell)
		assert(lease != null and lease.formation_id == 1)
		assert(reg.is_slot_reserved(cell, 2))
		assert(not reg.is_slot_reserved(cell, 1))
		
	for cell in f2_slots:
		var lease = reg.owner_of(cell)
		assert(lease != null and lease.formation_id == 2)
		assert(reg.is_slot_reserved(cell, 1))
		assert(not reg.is_slot_reserved(cell, 2))
	print("TASK 4: Dual-formation non-overlapping reservation verified")
	
	# 2. Conflict rejection & transactional rollback
	# Formation 3 attempts to reserve slots overlapping with Formation 1
	var f3_slots: Array[Vector2i] = [
		Vector2i(15, 15), # Overlaps with Formation 1!
		Vector2i(15, 25), # Non-overlapping
		Vector2i(16, 25)
	]
	var res3 = reg.try_replace_reservations(3, 0, 301, f3_slots)
	assert(not res3.ok, "Conflicting reservation must fail")
	assert(res3.conflicts == [Vector2i(15, 15)], "Conflict cell must be correctly identified")
	assert(reg.get_formation_reserved_slots(3).is_empty(), "Formation 3 must have zero registered slots on failure")
	
	# Formation 1's slot at (15, 15) must STILL belong to Formation 1!
	assert(reg.owner_of(Vector2i(15, 15)).formation_id == 1)
	assert(reg.get_formation_reserved_slots(1).size() == 60)
	print("TASK 4: Conflict rejection and rollback verified")
	
	# 3. Same-formation re-planning (order replacement)
	# Formation 1 switches from order 101 to order 102 with 50 shifted slots
	# (overlapping its own old slots)
	var f1_new_slots: Array[Vector2i] = []
	for y in range(11, 16):
		for x in range(10, 20):
			f1_new_slots.append(Vector2i(x, y)) # 50 slots
	assert(f1_new_slots.size() == 50)
	
	var res1_update = reg.try_replace_reservations(1, 101, 102, f1_new_slots)
	assert(res1_update.ok, "Same-formation slot replacement must succeed")
	assert(reg.get_formation_reserved_slots(1).size() == 50)
	
	# Old row y=10 should now be freed!
	for x in range(10, 20):
		assert(not reg.is_slot_reserved(Vector2i(x, 10)), "Old row 10 slots must be freed")
		
	# New rows should have order_serial = 102
	for cell in f1_new_slots:
		assert(reg.owner_of(cell).order_serial == 102)
	print("TASK 4: Same-formation order update verified")
	
	# 4. Failed update preserves current order intact
	# Formation 1 tries order 103, but includes one of Formation 2's slots at (10, 16)
	var f1_bad_slots: Array[Vector2i] = [
		Vector2i(10, 11),
		Vector2i(10, 16) # Collides with Formation 2!
	]
	var res1_bad = reg.try_replace_reservations(1, 102, 103, f1_bad_slots)
	assert(not res1_bad.ok, "Colliding update must fail")
	# Formation 1 must still have all 50 slots under order 102!
	assert(reg.get_formation_reserved_slots(1).size() == 50)
	assert(reg.owner_of(Vector2i(10, 11)).order_serial == 102)
	assert(reg.owner_of(Vector2i(10, 16)).formation_id == 2)
	print("TASK 4: Failed update preserves existing reservations intact")
	
	# 5. A stale caller cannot replace or untrack a newer order's leases.
	var stale_update = reg.try_replace_reservations(1, 101, 104, [Vector2i(10, 11), Vector2i(40, 40)])
	assert(not stale_update.ok and stale_update.get("reason", "") == "STALE_ORDER")
	assert(reg.get_formation_reserved_slots(1).size() == 50)
	assert(reg.owner_of(Vector2i(10, 11)).order_serial == 102)
	assert(not reg.is_slot_reserved(Vector2i(40, 40)))
	reg.release_slots(1, 101, [Vector2i(10, 11)])
	assert(reg.owner_of(Vector2i(10, 11)).order_serial == 102)
	assert(reg.get_formation_reserved_slots(1).has(Vector2i(10, 11)))
	print("TASK 4: Stale serial preserves owner and tracking index")
	
	# 6. Release order
	reg.release_order(1, 102)
	assert(reg.get_formation_reserved_slots(1).is_empty())
	for cell in f1_new_slots:
		assert(not reg.is_slot_reserved(cell))
	# Formation 2 still has its 40 slots
	assert(reg.get_formation_reserved_slots(2).size() == 40)
	# An orphaned lease from an older registry state must still be releasable.
	var orphan_cell := Vector2i(40, 40)
	assert(reg.try_replace_reservations(3, 0, 301, [orphan_cell]).ok)
	reg._formation_slots.erase(3)
	reg.release_order(3)
	assert(not reg.is_slot_reserved(orphan_cell))
	print("TASK 4: Release order verified")
	
	print("TASK 4 COMPLETE: Persistent Deployment Registry fully operational!")
	quit(0)
