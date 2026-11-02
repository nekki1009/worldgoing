extends SceneTree
## Unit test suite for Task 3: SiteMovementReservationGrid, dependency DAG,
## cycle rejection and same-cell arbitration. Physical commit is exercised by
## combat_movement_physical_chain_test.gd (retired 2026-11-02) with real Army owners.

const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const ReservationGrid = preload("res://scripts/terrain_lab/site_movement_reservation_grid.gd")
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Task 3 ReservationGrid & Atomic Commit Test ---")
	
	# 1. Dependency chain success test
	# Setup 3 units in a line: Unit 3 at (1,1), Unit 2 at (1,2), Unit 1 at (1,3)
	# Unit 1 moves to (1,4) which is empty.
	# Unit 2 moves to (1,3) vacated by Unit 1.
	# Unit 3 moves to (1,2) vacated by Unit 2.
	var grid = ReservationGrid.new()
	var occ: Dictionary = {
		Vector2i(1, 1): 103,
		Vector2i(1, 2): 102,
		Vector2i(1, 3): 101,
	}
	grid.begin_tick(occ)
	
	var p1: int = grid.propose_move(1, 101, 1, Vector2i(1, 3), Vector2i(1, 4))
	var p2: int = grid.propose_move(1, 102, 1, Vector2i(1, 2), Vector2i(1, 3))
	var p3: int = grid.propose_move(1, 103, 1, Vector2i(1, 1), Vector2i(1, 2))
	
	grid.resolve_all()
	
	var prop1 = grid.proposal_lookup[p1]
	var prop2 = grid.proposal_lookup[p2]
	var prop3 = grid.proposal_lookup[p3]
	
	assert(prop1.status == Types.MoveProposalStatus.ACCEPTED, "Head of chain into empty cell must be ACCEPTED")
	assert(prop2.status == Types.MoveProposalStatus.ACCEPTED, "Middle of chain must be ACCEPTED")
	assert(prop3.status == Types.MoveProposalStatus.ACCEPTED, "Tail of chain must be ACCEPTED")
	
	# Resolve may accept the chain, but Commit must reject owners that vanished
	# before their original physical movement step could begin.
	grid.commit_all({})
	assert(grid.get_committed_occupancy() == occ)
	print("TASK 3: Dependency chain resolution and missing-owner preflight verified")
	
	# 2. Dependency chain failure test (blocked head)
	# Unit 1 at (1,3) has no proposal (stays still).
	# Unit 2 at (1,2) proposes (1,3).
	# Unit 3 at (1,1) proposes (1,2).
	grid.begin_tick(occ)
	var pf2: int = grid.propose_move(1, 102, 1, Vector2i(1, 2), Vector2i(1, 3))
	var pf3: int = grid.propose_move(1, 103, 1, Vector2i(1, 1), Vector2i(1, 2))
	
	grid.resolve_all()
	var prop_f2 = grid.proposal_lookup[pf2]
	var prop_f3 = grid.proposal_lookup[pf3]
	
	assert(prop_f2.status == Types.MoveProposalStatus.REJECTED_DEPENDENCY, "Moving into static unit must REJECT_DEPENDENCY")
	assert(prop_f3.status == Types.MoveProposalStatus.REJECTED_DEPENDENCY, "Chained to rejected move must REJECT_DEPENDENCY")
	
	grid.commit_all({})
	var committed_fail = grid.get_committed_occupancy()
	assert(committed_fail == occ, "Rejected dependency must leave occupancy 100% unchanged")
	print("TASK 3: Dependency chain failure propagation verified")
	
	# 3. Only one-formation adjacent pairs may exchange; longer cycles still fail.
	# Case A: 2-person head-to-head swap
	var swap_occ: Dictionary = {
		Vector2i(5, 5): 201,
		Vector2i(5, 6): 202
	}
	grid.begin_tick(swap_occ)
	var ps1: int = grid.propose_move(1, 201, 1, Vector2i(5, 5), Vector2i(5, 6))
	var ps2: int = grid.propose_move(1, 202, 1, Vector2i(5, 6), Vector2i(5, 5))
	grid.resolve_all()
	assert(grid.proposal_lookup[ps1].status == Types.MoveProposalStatus.ACCEPTED, "same-formation 2-person swap must be ACCEPTED")
	assert(grid.proposal_lookup[ps2].status == Types.MoveProposalStatus.ACCEPTED, "same-formation 2-person swap must be ACCEPTED")
	grid.commit_all({})
	assert(grid.proposal_lookup[ps1].status != Types.MoveProposalStatus.ACCEPTED and grid.proposal_lookup[ps2].status != Types.MoveProposalStatus.ACCEPTED, "missing participants must cancel both sides of the pair")
	assert(grid.get_committed_occupancy() == swap_occ, "preflight rollback must preserve occupancy")
	
	# Case B: 3-person triangle cycle
	var tri_occ: Dictionary = {
		Vector2i(10, 10): 301,
		Vector2i(10, 11): 302,
		Vector2i(11, 10): 303
	}
	grid.begin_tick(tri_occ)
	var pt1: int = grid.propose_move(1, 301, 1, Vector2i(10, 10), Vector2i(10, 11))
	var pt2: int = grid.propose_move(1, 302, 1, Vector2i(10, 11), Vector2i(11, 10))
	var pt3: int = grid.propose_move(1, 303, 1, Vector2i(11, 10), Vector2i(10, 10))
	grid.resolve_all()
	assert(grid.proposal_lookup[pt1].status == Types.MoveProposalStatus.REJECTED_CYCLE, "Triangle cycle must be REJECTED_CYCLE")
	assert(grid.proposal_lookup[pt2].status == Types.MoveProposalStatus.REJECTED_CYCLE, "Triangle cycle must be REJECTED_CYCLE")
	assert(grid.proposal_lookup[pt3].status == Types.MoveProposalStatus.REJECTED_CYCLE, "Triangle cycle must be REJECTED_CYCLE")
	grid.commit_all({})
	assert(grid.get_committed_occupancy() == tri_occ, "Triangle cycle must preserve occupancy")
	print("TASK 3: same-formation pair acceptance and 3-person cycle rejection verified")
	
	# 4. Same-cell competition arbitration test
	var conflict_occ: Dictionary = {
		Vector2i(20, 20): 401,
		Vector2i(22, 20): 402,
		Vector2i(21, 21): 403
	}
	grid.begin_tick(conflict_occ)
	# All 3 propose to (21, 20) which is empty
	# Unit 401: emergency_priority = 5
	# Unit 402: emergency_priority = 10 (Highest priority -> Winner!)
	# Unit 403: emergency_priority = 0
	var pc1: int = grid.propose_move(1, 401, 1, Vector2i(20, 20), Vector2i(21, 20), 5)
	var pc2: int = grid.propose_move(1, 402, 1, Vector2i(22, 20), Vector2i(21, 20), 10)
	var pc3: int = grid.propose_move(1, 403, 1, Vector2i(21, 21), Vector2i(21, 20), 0)
	grid.resolve_all()
	assert(grid.proposal_lookup[pc2].status == Types.MoveProposalStatus.ACCEPTED, "Highest priority must win conflict")
	assert(grid.proposal_lookup[pc1].status == Types.MoveProposalStatus.REJECTED_CONFLICT, "Lower priority must be REJECTED_CONFLICT")
	assert(grid.proposal_lookup[pc3].status == Types.MoveProposalStatus.REJECTED_CONFLICT, "Lowest priority must be REJECTED_CONFLICT")
	
	grid.commit_all({})
	var comm_conf = grid.get_committed_occupancy()
	assert(comm_conf == conflict_occ)
	print("TASK 3: Same-cell competition priority arbitration verified")
	print("TASK 3 COMPLETE: ReservationGrid arbitration and commit preflight verified!")
	quit(0)
