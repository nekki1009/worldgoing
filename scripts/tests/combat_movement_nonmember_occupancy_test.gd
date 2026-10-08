extends SceneTree
## A living person who leaves a formation remains a physical Site blocker.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
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
	var data: TerrainData = Helper.build_flat_map(20, 20)
	var first: TerrainArmy = Helper.create_test_army(data, 1, 0, 2, Vector2i(5, 5))
	var second: TerrainArmy = Helper.create_test_army(data, 2, 1, 1, Vector2i(6, 6))
	var coordinator: SiteCombatMovementCoordinator = Coordinator.new()
	coordinator.register_formation(first)
	coordinator.register_formation(second)
	var independent_id: int = first.combat_identity(1)
	var independent_cell: Vector2i = first.cells[1]
	first.controlled_person_query = func() -> int: return independent_id
	if not _require(bool(first.leave_row(independent_id).get("ok", false)), "A controlled, idle person must leave the formation"): return
	if not _require(not first.is_member(1) and not first._get_active_member_ids().has(independent_id)
		and first.blocks_cell(independent_cell) and first.get_active_members_occupancy().get(independent_id) == independent_cell,
		"Independent person must leave MOVE planning but remain in physical occupancy"): return
	coordinator._rebuild_occupancy()
	var grid: SiteMovementReservationGrid = coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, data)
	if not _require(grid.initial_occupancy.get(independent_cell) == independent_id,
		"Coordinator and Grid must project the independent person's physical cell"): return
	var proposal_id: int = grid.propose_move(second.formation_runtime_id, second.combat_identity(0), 0,
		second.cells[0], independent_cell)
	grid.resolve_all()
	if not _require(proposal_id >= 0 and grid.proposal_lookup[proposal_id].status == Types.MoveProposalStatus.REJECTED_DEPENDENCY,
		"Grid must reject an unvacated independent person's occupied destination"): return
	coordinator.unregister_formation(first)
	coordinator.unregister_formation(second)
	first.free()
	second.free()
	print("COMBAT MOVEMENT NONMEMBER OCCUPANCY PASS")
	quit(0)
