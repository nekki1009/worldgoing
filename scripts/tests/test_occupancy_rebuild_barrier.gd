extends SceneTree
## Test: Occupancy Rebuild Barrier & Authoritative Restoration
## Verifies:
## 1. request_occupancy_rebuild sets the pending barrier flag.
## 2. Tick boundary resolves the barrier and resets is_occupancy_rebuild_pending() to false.
## 3. Any corrupted/desynced grid occupancy is completely restored to match authoritative pawn cells.
## 4. Retained occupancy (dissolved formations) is preserved across rebuilds.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Test: Occupancy Rebuild Barrier ---")

	var data := Helper.build_flat_map(50, 50)
	var coord := Coordinator.new()

	var army := Helper.create_test_army(data, 1, 0, 5, Vector2i(10, 10))
	coord.register_formation(army)

	# Initial tick to register initial occupancy
	coord.combat_logic_tick(0.1)

	var auth_cells := army.get_active_members_occupancy()
	assert(auth_cells.size() == 5, "Army must have 5 active pawns")

	# Corrupt grid occupancy deliberately (e.g. simulate desync ghost or missing cell)
	var ghost_cell := Vector2i(42, 42)
	coord.movement_reservation_grid.committed_occupancy[ghost_cell] = 9999
	var first_pawn_cell: Vector2i = auth_cells.values()[0]
	coord.movement_reservation_grid.committed_occupancy.erase(first_pawn_cell)

	# Verify grid is currently corrupted
	assert(coord.movement_reservation_grid.committed_occupancy.has(ghost_cell), "Ghost cell exists before rebuild")
	assert(not coord.movement_reservation_grid.committed_occupancy.has(first_pawn_cell), "Pawn cell is missing before rebuild")

	# Request rebuild barrier
	coord.request_occupancy_rebuild()
	assert(coord.is_occupancy_rebuild_pending(), "Pending flag must be true after request")

	# Run tick boundary
	coord.combat_logic_tick(0.1)

	# Verify barrier was resolved
	assert(not coord.is_occupancy_rebuild_pending(), "Pending flag must be cleared after tick resolution")

	# Verify ghost cell is removed and pawn cell is restored
	assert(not coord.movement_reservation_grid.committed_occupancy.has(ghost_cell), "Ghost cell must be wiped by rebuild barrier")
	assert(coord.movement_reservation_grid.committed_occupancy.has(first_pawn_cell), "Missing pawn cell must be restored by rebuild barrier")

	for mid in auth_cells.keys():
		var cell: Vector2i = auth_cells[mid]
		assert(coord.movement_reservation_grid.committed_occupancy.get(cell) == mid, "Every pawn cell must exactly match authoritative location")

	# Test with retained occupancy from dissolved formation
	var army2 := Helper.create_test_army(data, 2, 0, 3, Vector2i(20, 20))
	coord.register_formation(army2)
	coord.combat_logic_tick(0.1)
	var army2_cells := army2.get_active_members_occupancy()
	coord.unregister_formation(army2, Types.FormationUnregisterReason.FORMATION_DISSOLVED)

	# Request rebuild barrier again
	coord.request_occupancy_rebuild()
	coord.combat_logic_tick(0.1)

	# Verify both army1 and dissolved army2 cells are present in committed_occupancy
	for mid in auth_cells.keys():
		assert(coord.movement_reservation_grid.committed_occupancy.get(auth_cells[mid]) == mid, "Army 1 cells preserved")
	for mid in army2_cells.keys():
		assert(coord.movement_reservation_grid.committed_occupancy.get(army2_cells[mid]) == mid, "Dissolved army 2 cells preserved")

	print("TEST PASSED: Occupancy Rebuild Barrier verified!")
	coord.unregister_formation(army, Types.FormationUnregisterReason.LEAVE_SITE)
	army.free()
	army2.free()
	quit(0)
