extends SceneTree
## A real RETREAT order may let a blocked front member pass one adjacent ally.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if not condition:
		push_error("RETREAT PAIR SWAP FAIL: " + message)
		quit(1)
	return condition

func _run() -> void:
	var terrain: TerrainData = Helper.build_flat_map(24, 16)
	var army: TerrainArmy = Helper.create_test_army(terrain, 1, 0, 2, Vector2i(5, 5))
	var coordinator: SiteCombatMovementCoordinator = Coordinator.new()
	coordinator.register_formation(army)
	var rear: Vector2i = army.cells[0]
	var front: Vector2i = army.cells[1]
	if not _require(rear + Vector2i.RIGHT == front, "fixture members must be adjacent"): return
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.RETREAT,
		Vector2i(army.command_reference.floor()) + Vector2i.LEFT)
	if not _require(bool(order.get("ok", false)), "the real RETREAT command must be accepted"): return
	if not _require(army.combat_slots[0] == rear + Vector2i.LEFT and army.combat_slots[1] == rear,
		"both retreat destinations must come from the original command"): return
	# The rear exit closes after the order, so ordinary one-person steps cannot
	# move either member. The front member still has a legal adjacent retreat edge.
	terrain.static_blocked[terrain.index(rear + Vector2i.LEFT)] = 1
	var started := false
	for tick in range(30):
		coordinator.combat_logic_tick_if_needed(0.05)
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
		if army.moving_to[0] == front and army.moving_to[1] == rear:
			started = true
			break
	if not _require(started, "the RETREAT command must create a reciprocal Grid batch before falling back to HOLD"): return
	if not _require(army.cells[0] == rear and army.cells[1] == front and army._combat_batch_members.size() == 2,
		"the batch must retain both authoritative source cells"): return
	if not _require(army.combat_slots[0] == rear + Vector2i.LEFT and army.combat_slots[1] == rear,
		"the crossing must not exchange final retreat targets"): return
	army.prepare_combat(0.14)
	coordinator.complete_committed_moves()
	if not _require(army.cells[0] == rear and army.cells[1] == front,
		"neither source may commit at the animation midpoint"): return
	if not _require(army.combat_visual_ground(0).distance_to(army.combat_visual_ground(1)) > TerrainRenderer.CELL_PIXELS * 0.5,
		"visual sidesteps must separate the two bodies while crossing"): return
	army.prepare_combat(0.18)
	coordinator.complete_committed_moves()
	if not _require(army.cells[0] == rear and army.cells[1] == front,
		"both sources must remain occupied before the 0.38-second barrier"): return
	army.prepare_combat(0.02)
	coordinator.complete_committed_moves()
	if not _require(army.cells[0] == front and army.cells[1] == rear and army.moving_to[0] == TerrainArmy.INVALID_CELL and army.moving_to[1] == TerrainArmy.INVALID_CELL,
		"both members must exchange cells together after the physical step"): return
	if not _require(army._cell_owners.size() == 2 and army._cell_owners.get(rear, -1) == 1 and army._cell_owners.get(front, -1) == 0 \
		and army._reserved_cells.is_empty(), "finished occupancy and claims must remain unique"): return
	if not _require(army.combat_visual_ground(0) == army.combat_ground(0) and army.combat_visual_ground(1) == army.combat_ground(1),
		"both visuals must return to their final cell centers"): return
	for tick in range(25):
		coordinator.combat_logic_tick_if_needed(0.05)
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
	if not _require(army.cells[1] == rear and army._cell_owners.size() == 2,
		"the same two members must not reverse the forced crossing repeatedly"): return
	print("COMBAT MOVEMENT RETREAT PAIR SWAP PASS")
	coordinator.unregister_formation(army)
	army.free()
	quit(0)
