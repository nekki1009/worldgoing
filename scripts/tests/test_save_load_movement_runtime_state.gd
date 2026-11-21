extends SceneTree
## Test: Save / Load Movement Runtime State and Persistent Arbitration
## Verifies:
## 1. capture_combat_state serializes formation_persistent_serial, but excludes ephemeral runtime ID.
## 2. restore_combat_state restores formation_persistent_serial and resets formation_runtime_id to 0.
## 3. Fresh coordinator registration allocates new runtime IDs without state pollution.
## 4. Deterministic conflict arbitration ordering relies strictly on formation_persistent_serial,
##    invariant to the order of registration or runtime IDs.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Grid = preload("res://scripts/terrain_lab/site_movement_reservation_grid.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Test: Save/Load Movement Runtime State ---")

	var data := Helper.build_flat_map(50, 50)
	var armyA := Helper.create_test_army(data, 1, 0, 5, Vector2i(5, 5))
	var armyB := Helper.create_test_army(data, 2, 0, 5, Vector2i(15, 15))

	armyA.formation_persistent_serial = 200
	armyB.formation_persistent_serial = 100

	var coord1 := Coordinator.new()
	var ridA1 := coord1.register_formation(armyA)
	var ridB1 := coord1.register_formation(armyB)

	assert(ridA1 == 1 and ridB1 == 2, "Coordinator 1 runtime IDs should be 1 and 2")

	# 1. Capture snapshot
	var snapA: Dictionary = armyA.capture_combat_state()
	var snapB: Dictionary = armyB.capture_combat_state()

	assert(snapA.get("formation_persistent_serial") == 200, "Snapshot A must contain persistent serial 200")
	assert(snapB.get("formation_persistent_serial") == 100, "Snapshot B must contain persistent serial 100")
	assert(not snapA.has("formation_runtime_id"), "Snapshot must NOT save ephemeral formation_runtime_id")
	assert(not snapB.has("formation_runtime_id"), "Snapshot must NOT save ephemeral formation_runtime_id")

	# Unload site coordinator 1
	coord1.unregister_formation(armyA, Types.FormationUnregisterReason.SITE_UNLOAD)
	coord1.unregister_formation(armyB, Types.FormationUnregisterReason.SITE_UNLOAD)

	# 2. Restore combat state
	armyA.formation_runtime_id = 999
	armyB.formation_runtime_id = 888

	armyA.restore_combat_state(snapA, data, null, null)
	armyB.restore_combat_state(snapB, data, null, null)

	assert(armyA.formation_persistent_serial == 200, "Army A persistent serial restored")
	assert(armyB.formation_persistent_serial == 100, "Army B persistent serial restored")
	assert(armyA.formation_runtime_id == 0, "Army A runtime ID reset to 0 on restore")
	assert(armyB.formation_runtime_id == 0, "Army B runtime ID reset to 0 on restore")

	# 3. Register in fresh Coordinator 2 in reverse order (Army B first, then Army A)
	var coord2 := Coordinator.new()
	assert(not coord2.is_occupancy_rebuild_pending(), "Fresh coordinator pending barrier must be false")

	var ridB2 := coord2.register_formation(armyB)
	var ridA2 := coord2.register_formation(armyA)

	assert(ridB2 == 1, "Army B gets runtime ID 1 in coord 2")
	assert(ridA2 == 2, "Army A gets runtime ID 2 in coord 2")

	# 4. Deterministic arbitration check
	# Independent grid fixture: both restored identities own a legal source cell.
	var test_grid := Grid.new()
	var member_a := armyA.combat_identity(0)
	var member_b := armyB.combat_identity(0)
	assert(member_a != member_b)
	var source_a := Vector2i(5, 6)
	var source_b := Vector2i(7, 6)
	var target_cell := Vector2i(6, 6)
	test_grid.begin_tick({source_a: member_a, source_b: member_b}, data)
	assert(data.can_step(source_a, target_cell) and data.can_step(source_b, target_cell))
	var pidA: int = test_grid.propose_move(armyA.formation_runtime_id, member_a, 1, source_a, target_cell, 0, 0, 0, 0, armyA.formation_persistent_serial)
	var pidB: int = test_grid.propose_move(armyB.formation_runtime_id, member_b, 1, source_b, target_cell, 0, 0, 0, 0, armyB.formation_persistent_serial)

	test_grid.resolve_all()

	var pA = test_grid.proposal_lookup[pidA]
	var pB = test_grid.proposal_lookup[pidB]

	# In arbitration, lower persistent serial wins: army B (100) < army A (200)
	assert(pB.status == Types.MoveProposalStatus.ACCEPTED, "Army B with persistent serial 100 must win arbitration, got status: " + str(pB.status))
	assert(pA.status == Types.MoveProposalStatus.REJECTED_CONFLICT, "Army A with persistent serial 200 must lose arbitration, got status: " + str(pA.status))
	assert(test_grid.get_committed_occupancy() == {source_a: member_a, source_b: member_b}, "Resolve must not move either source before physical commitment")

	print("TEST PASSED: Save/Load Movement Runtime State verified!")
	coord2.unregister_formation(armyA)
	coord2.unregister_formation(armyB)
	armyA.free()
	armyB.free()
	quit(0)
