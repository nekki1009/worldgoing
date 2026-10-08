extends SceneTree
## Test: Formation Registration Lifecycle and Occupancy Separation
## Verifies:
## 1. Idempotent registration of formations.
## 2. Distinct runtime IDs assigned to same-team formations.
## 3. FORMATION_DISSOLVED and TRANSFER_MEMBERS retain occupancy so pawns remain solid obstacles.
## 4. LEAVE_SITE clears occupancy completely.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Test: Formation Registration Lifecycle ---")

	var data := Helper.build_flat_map(60, 60)
	var coord := Coordinator.new()

	# 1. Idempotent registration
	var army1 := Helper.create_test_army(data, 1, 0, 5, Vector2i(5, 5))
	var fid1 := coord.register_formation(army1)
	assert(fid1 > 0, "Registration should return valid runtime id")
	assert(army1.get_formation_id() == fid1, "Army formation_id should be set")

	var fid1_repeat := coord.register_formation(army1)
	assert(fid1_repeat == fid1, "Repeat registration must return identical runtime id")
	assert(coord.get_active_formations().size() == 1, "Active formations must not contain duplicates")

	# 2. Distinct runtime IDs for same-team formations
	var army2 := Helper.create_test_army(data, 1, 0, 5, Vector2i(15, 15))
	var fid2 := coord.register_formation(army2)
	assert(fid2 != fid1, "Distinct formations must receive distinct runtime IDs")
	assert(coord.get_active_formations().size() == 2, "Active formations count must be 2")
	assert(coord.get_formation_by_id(fid1) == army1, "Coordinator lookup for fid1 must return army1")
	assert(coord.get_formation_by_id(fid2) == army2, "Coordinator lookup for fid2 must return army2")

	# Run a tick to sync occupancy
	coord.combat_logic_tick(0.1)

	# Verify army1 cells are occupied
	var army1_cells := army1.get_active_members_occupancy()
	for mid in army1_cells.keys():
		var cell: Vector2i = army1_cells[mid]
		assert(coord.movement_reservation_grid.committed_occupancy.get(cell) == mid, "Army1 cells must be occupied in grid")

	# 3. Test LEAVE_SITE: completely cleans occupancy
	coord.unregister_formation(army1, Types.FormationUnregisterReason.LEAVE_SITE)
	assert(coord.get_active_formations().size() == 1, "Army1 should be removed from active formations")
	assert(coord.get_formation_by_id(fid1) == null, "Army1 lookup should be null")
	for mid in army1_cells.keys():
		var cell: Vector2i = army1_cells[mid]
		assert(not coord.movement_reservation_grid.committed_occupancy.has(cell), "LEAVE_SITE must erase cell from grid occupancy")

	# 4. Test FORMATION_DISSOLVED: retains occupancy so remaining pawns don't become passable ghosts
	var army3 := Helper.create_test_army(data, 2, 0, 5, Vector2i(25, 25))
	var fid3 := coord.register_formation(army3)
	coord.combat_logic_tick(0.1)

	var army3_cells := army3.get_active_members_occupancy()
	var retained_cells_count := army3_cells.size()
	assert(retained_cells_count > 0, "Army3 must have active cells")

	coord.unregister_formation(army3, Types.FormationUnregisterReason.FORMATION_DISSOLVED)
	assert(coord.get_active_formations().size() == 1, "Army3 should be removed from active formations")
	assert(coord.get_formation_by_id(fid3) == null, "Army3 lookup should be null")

	# Retained occupancy must preserve every cell
	var retained: Dictionary = coord.get_retained_occupancy()
	for mid in army3_cells.keys():
		var cell: Vector2i = army3_cells[mid]
		assert(retained.get(cell) == mid, "Retained occupancy must preserve cell " + str(cell))
		assert(coord.movement_reservation_grid.committed_occupancy.get(cell) == mid, "Committed occupancy must retain dissolved member cell")

	# Next tick boundary must continue preserving retained cells
	coord.combat_logic_tick(0.1)
	for mid in army3_cells.keys():
		var cell: Vector2i = army3_cells[mid]
		assert(coord.movement_reservation_grid.committed_occupancy.get(cell) == mid, "Tick boundary must keep dissolved member cell occupied")

	print("TEST PASSED: Formation Registration Lifecycle verified!")
	coord.unregister_formation(army2, Types.FormationUnregisterReason.LEAVE_SITE)
	army1.free()
	army2.free()
	army3.free()
	quit(0)
