extends SceneTree
## Test: Move Cycle Rejection in SiteMovementReservationGrid
## Verifies that:
## 1. One-formation adjacent pairs may exchange; foreign pairs may not.
## 2. 3-person closed loops (A -> B -> C -> A) are strictly marked REJECTED_CYCLE.
## 3. Dependent proposals following a cycle are cascade rejected as REJECTED_DEPENDENCY or REJECTED_CONFLICT.
## 4. Legitimate open-tail chains (A -> B -> C -> Empty) are ACCEPTED.

const ReservationGrid = preload("res://scripts/terrain_lab/site_movement_reservation_grid.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Test: Move Cycle Rejection Test ---")

	var grid = ReservationGrid.new()

	# Scenario 1: 2-person head-on swap
	# A at (10, 10), B at (11, 10)
	var occ1: Dictionary = {
		Vector2i(10, 10): 1,
		Vector2i(11, 10): 2
	}
	grid.begin_tick(occ1)
	var p1: int = grid.propose_move(1, 1, 1, Vector2i(10, 10), Vector2i(11, 10))
	var p2: int = grid.propose_move(1, 2, 1, Vector2i(11, 10), Vector2i(10, 10))
	grid.resolve_all()

	assert(grid.proposal_lookup[p1].status == Types.MoveProposalStatus.ACCEPTED, "same-formation pair member 1 must be ACCEPTED")
	assert(grid.proposal_lookup[p2].status == Types.MoveProposalStatus.ACCEPTED, "same-formation pair member 2 must be ACCEPTED")
	grid.begin_tick(occ1)
	var foreign_1: int = grid.propose_move(1, 1, 1, Vector2i(10, 10), Vector2i(11, 10))
	var foreign_2: int = grid.propose_move(2, 2, 1, Vector2i(11, 10), Vector2i(10, 10))
	grid.resolve_all()
	assert(grid.proposal_lookup[foreign_1].status == Types.MoveProposalStatus.REJECTED_CYCLE, "foreign pair member 1 must be REJECTED_CYCLE")
	assert(grid.proposal_lookup[foreign_2].status == Types.MoveProposalStatus.REJECTED_CYCLE, "foreign pair member 2 must be REJECTED_CYCLE")
	print("same-formation pair acceptance and foreign pair rejection verified")

	# Scenario 2: 3-person cycle (A -> B -> C -> A)
	# A at (10, 10), B at (11, 10), C at (10, 11)
	var occ2: Dictionary = {
		Vector2i(10, 10): 10,
		Vector2i(11, 10): 20,
		Vector2i(10, 11): 30
	}
	grid.begin_tick(occ2)
	var p10: int = grid.propose_move(1, 10, 1, Vector2i(10, 10), Vector2i(11, 10))
	var p20: int = grid.propose_move(1, 20, 1, Vector2i(11, 10), Vector2i(10, 11))
	var p30: int = grid.propose_move(1, 30, 1, Vector2i(10, 11), Vector2i(10, 10))
	grid.resolve_all()

	assert(grid.proposal_lookup[p10].status == Types.MoveProposalStatus.REJECTED_CYCLE, "3-person cycle member 10 must be REJECTED_CYCLE")
	assert(grid.proposal_lookup[p20].status == Types.MoveProposalStatus.REJECTED_CYCLE, "3-person cycle member 20 must be REJECTED_CYCLE")
	assert(grid.proposal_lookup[p30].status == Types.MoveProposalStatus.REJECTED_CYCLE, "3-person cycle member 30 must be REJECTED_CYCLE")
	print("3-person cycle rejection verified")

	# Scenario 3: A tail competing for the pair's destination cannot join it.
	# D at (9, 10) wants to move into (10, 10) (A's cell)
	var occ3: Dictionary = {
		Vector2i(10, 10): 100,
		Vector2i(11, 10): 200,
		Vector2i(9, 10): 300
	}
	grid.begin_tick(occ3)
	var p100: int = grid.propose_move(1, 100, 1, Vector2i(10, 10), Vector2i(11, 10))
	var p200: int = grid.propose_move(1, 200, 1, Vector2i(11, 10), Vector2i(10, 10))
	var p300: int = grid.propose_move(1, 300, 1, Vector2i(9, 10), Vector2i(10, 10)) # wants A's cell
	grid.resolve_all()

	assert(grid.proposal_lookup[p100].status == Types.MoveProposalStatus.ACCEPTED, "Unit 100 in the pair must be ACCEPTED")
	assert(grid.proposal_lookup[p200].status == Types.MoveProposalStatus.ACCEPTED, "Unit 200 in the pair must be ACCEPTED")
	assert(grid.proposal_lookup[p300].status in [Types.MoveProposalStatus.REJECTED_DEPENDENCY, Types.MoveProposalStatus.REJECTED_CONFLICT], "Tail unit 300 must be rejected (conflict/dependency)")
	print("Tail conflict with pair rejected")

	# Scenario 4: Valid open-tail chain (A -> B -> C -> Empty)
	var occ4: Dictionary = {
		Vector2i(1, 1): 1,
		Vector2i(2, 1): 2,
		Vector2i(3, 1): 3
		# (4, 1) is empty!
	}
	grid.begin_tick(occ4)
	var pc3: int = grid.propose_move(1, 3, 1, Vector2i(3, 1), Vector2i(4, 1))
	var pc2: int = grid.propose_move(1, 2, 1, Vector2i(2, 1), Vector2i(3, 1))
	var pc1: int = grid.propose_move(1, 1, 1, Vector2i(1, 1), Vector2i(2, 1))
	grid.resolve_all()

	assert(grid.proposal_lookup[pc3].status == Types.MoveProposalStatus.ACCEPTED, "C must be ACCEPTED into empty cell")
	assert(grid.proposal_lookup[pc2].status == Types.MoveProposalStatus.ACCEPTED, "B must be ACCEPTED following C")
	assert(grid.proposal_lookup[pc1].status == Types.MoveProposalStatus.ACCEPTED, "A must be ACCEPTED following B")
	print("Open-tail chain acceptance verified")

	print("TEST PASSED: Move Cycle Rejection verified!")
	quit(0)
