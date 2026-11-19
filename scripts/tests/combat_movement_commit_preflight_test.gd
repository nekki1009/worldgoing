extends SceneTree

const Grid = preload("res://scripts/terrain_lab/site_movement_reservation_grid.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	var grid = Grid.new()
	var first := Vector2i(1, 1)
	var second := Vector2i(2, 1)
	var third := Vector2i(3, 1)
	grid.begin_tick({first: 11, second: 12})
	var head: int = grid.propose_move(1, 12, 7, second, third)
	var follower: int = grid.propose_move(1, 11, 7, first, second)
	grid.resolve_all()
	if not _require(grid.proposal_lookup[head].status == Types.MoveProposalStatus.ACCEPTED, "The open-tail chain must resolve"): return
	if not _require(grid.proposal_lookup[follower].status == Types.MoveProposalStatus.ACCEPTED, "The follower must resolve"): return

	# The owner vanished between Resolve and Commit. Neither member may move,
	# including the dependent follower, and no destination may be fabricated.
	grid.commit_all({}, 1)
	if not _require(grid.proposal_lookup[head].status != Types.MoveProposalStatus.ACCEPTED, "Missing owner must invalidate the head"): return
	if not _require(grid.proposal_lookup[follower].status != Types.MoveProposalStatus.ACCEPTED, "Missing owner must invalidate the follower"): return
	var occupancy: Dictionary = grid.get_committed_occupancy()
	if not _require(occupancy.size() == 2 and occupancy.get(first) == 11 and occupancy.get(second) == 12, "Owner loss must preserve both sources"): return
	if not _require(not occupancy.has(third), "Missing owner must not leave a phantom destination"): return

	# A proposal for a source absent even at BeginTick is invalid before commit.
	grid.begin_tick({})
	var phantom: int = grid.propose_move(1, 13, 7, first, second)
	grid.resolve_all()
	if not _require(grid.proposal_lookup[phantom].status != Types.MoveProposalStatus.ACCEPTED, "Missing source must be rejected"): return
	print("COMBAT MOVEMENT COMMIT PREFLIGHT PASS")
	quit(0)
