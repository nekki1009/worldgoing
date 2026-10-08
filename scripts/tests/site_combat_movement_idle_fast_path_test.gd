extends SceneTree

const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")

class FormationWithPlans:
	extends RefCounted
	var formation_runtime_id := 0
	var member_id := 101
	var cells: Array[Vector2i] = [Vector2i(2, 2)]
	var moving_to: Array[Vector2i] = [Vector2i(-1, -1)]
	var _cell_owners: Dictionary = {Vector2i(2, 2): 0}
	var step_ready := false
	var cell: Vector2i:
		get:
			return cells[0]
		set(value):
			_cell_owners.erase(cells[0])
			cells[0] = value
			_cell_owners[value] = 0
	var destination := Vector2i(-1, -1)
	var move_active := false
	var stages: Array[String] = []
	var occupancy_reads := 0

	func set_formation_id(id: int) -> void:
		formation_runtime_id = id

	func try_get_formation_id() -> int:
		return formation_runtime_id

	func get_active_move_plan() -> Variant:
		return self if move_active else null

	func get_active_deployment_plan() -> Variant:
		return null

	func get_active_members_occupancy() -> Dictionary:
		occupancy_reads += 1
		var occupancy := {}
		occupancy[member_id] = cell
		return occupancy

	func prepare_combat_movement_tick(_delta: float, _budget: Object, _registry: Object) -> void:
		stages.append("prepare")

	func propose_combat_moves(grid: Object) -> void:
		stages.append("propose")
		if move_active and moving_to[0] == Vector2i(-1, -1):
			var proposal_id: int = grid.propose_move(formation_runtime_id, member_id, 0, cell, destination)
			assert(proposal_id > 0)

	func can_begin_committed_move(id: int, from_cell: Vector2i, to_cell: Vector2i, _participants: Dictionary) -> bool:
		return id == member_id and from_cell == cell and to_cell == destination \
			and moving_to[0] == Vector2i(-1, -1)

	func begin_committed_move(id: int, from_cell: Vector2i, to_cell: Vector2i) -> void:
		assert(id == member_id and from_cell == cell and to_cell == destination)
		moving_to[0] = to_cell
		step_ready = false

	func committed_move_terrain_invalid(_id: int) -> bool:
		return false

	func can_finish_committed_move(id: int) -> bool:
		return id == member_id and step_ready and moving_to[0] != Vector2i(-1, -1)

	func index_for_identity(id: int) -> int:
		return 0 if id == member_id else -1

	func finish_committed_move(id: int) -> void:
		assert(can_finish_committed_move(id))
		cell = moving_to[0]
		moving_to[0] = Vector2i(-1, -1)
		step_ready = false

	func finalize_combat_movement_tick(_delta: float, _grid: Object, _registry: Object) -> void:
		stages.append("finalize")

class FormationWithoutPlanInterface:
	extends RefCounted
	var team_id := 2
	var stages: Array[String] = []

	func get_active_members_occupancy() -> Dictionary:
		return {202: Vector2i(6, 6)}

	func prepare_combat_movement_tick(_delta: float, _budget: Object, _registry: Object) -> void:
		stages.append("prepare")

	func propose_combat_moves(_grid: Object) -> void:
		stages.append("propose")

	func finalize_combat_movement_tick(_delta: float, _grid: Object, _registry: Object) -> void:
		stages.append("finalize")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var coordinator := Coordinator.new()
	var formation := FormationWithPlans.new()
	coordinator.register_formation(formation)

	coordinator.combat_logic_tick_if_needed(1.0 / 30.0)
	assert(coordinator.current_logic_tick == 1)
	assert(formation.stages.is_empty())
	assert(coordinator.movement_reservation_grid.committed_occupancy.is_empty())

	# A legacy action may move a soldier while no formation plan exists.
	formation.cell = Vector2i(3, 2)
	formation.destination = Vector2i(4, 2)
	formation.move_active = true
	coordinator.combat_logic_tick_if_needed(1.0 / 30.0)
	assert(coordinator.current_logic_tick == 2)
	assert(formation.stages == ["prepare", "propose", "finalize"])
	assert(formation.cell == Vector2i(3, 2))
	assert(formation.moving_to[0] == Vector2i(4, 2))
	assert(coordinator.movement_reservation_grid.committed_occupancy.get(formation.cell) == formation.member_id)
	assert(not coordinator.movement_reservation_grid.committed_occupancy.has(Vector2i(4, 2)))
	assert(coordinator.get_inflight_batches_for_formation(formation).size() == 1)
	coordinator.complete_committed_moves()
	assert(formation.cell == Vector2i(3, 2), "An unfinished physical step must keep its source occupied")
	formation.step_ready = true
	coordinator.complete_committed_moves()
	assert(formation.cell == Vector2i(4, 2))
	assert(formation.moving_to[0] == Vector2i(-1, -1))
	assert(coordinator.get_inflight_batches_for_formation(formation).is_empty())
	assert(coordinator.movement_reservation_grid.committed_occupancy.get(formation.cell) == formation.member_id)
	assert(not coordinator.movement_reservation_grid.committed_occupancy.has(Vector2i(3, 2)))

	formation.move_active = false
	formation.stages.clear()
	var ghost := Vector2i(8, 8)
	coordinator.movement_reservation_grid.committed_occupancy.clear()
	coordinator.movement_reservation_grid.committed_occupancy[ghost] = formation.member_id
	coordinator.request_occupancy_rebuild()
	coordinator.combat_logic_tick_if_needed(1.0 / 30.0)
	assert(coordinator.current_logic_tick == 3)
	assert(not coordinator.is_occupancy_rebuild_pending())
	assert(formation.stages == ["prepare", "propose", "finalize"])
	assert(not coordinator.movement_reservation_grid.committed_occupancy.has(ghost))
	assert(coordinator.movement_reservation_grid.committed_occupancy.get(formation.cell) == formation.member_id)

	# Generic formations retain the original full-tick contract.
	var unknown_coordinator := Coordinator.new()
	var unknown := FormationWithoutPlanInterface.new()
	unknown_coordinator.register_formation(unknown)
	unknown_coordinator.combat_logic_tick_if_needed(1.0 / 30.0)
	assert(unknown.stages == ["prepare", "propose", "finalize"])
	assert(unknown_coordinator.movement_reservation_grid.committed_occupancy.get(Vector2i(6, 6)) == 202)

	var full_coordinator := Coordinator.new()
	var full_formation := FormationWithPlans.new()
	full_coordinator.register_formation(full_formation)
	full_coordinator.idle_tick_skip_enabled = false
	full_coordinator.combat_logic_tick_if_needed(1.0 / 30.0)
	assert(full_formation.stages == ["prepare", "propose", "finalize"])
	assert(full_coordinator.movement_reservation_grid.committed_occupancy.get(full_formation.cell) == full_formation.member_id)
	# One synchronous owner snapshot serves retained-ID cleanup and publication.
	# A later rebuild must read the owner again; no snapshot survives this call.
	var old_cell := full_formation.cell
	var retained_cell := Vector2i(9, 9)
	full_coordinator._retained_occupancy[old_cell] = full_formation.member_id
	full_coordinator._retained_occupancy[retained_cell] = 909
	full_formation.cell = Vector2i(7, 2)
	var reads_before := full_formation.occupancy_reads
	full_coordinator._rebuild_occupancy()
	assert(full_formation.occupancy_reads == reads_before + 1, "Read each original formation exactly once per rebuild")
	assert(not full_coordinator._retained_occupancy.has(old_cell) and not full_coordinator._current_occupancy.has(old_cell))
	assert(full_coordinator._current_occupancy.get(retained_cell) == 909, "An unrelated retained person still occupies its original cell")
	assert(full_coordinator._member_lookup[full_formation.member_id].cell == full_formation.cell)
	full_formation.cell = Vector2i(8, 2)
	full_coordinator._rebuild_occupancy()
	assert(full_formation.occupancy_reads == reads_before + 2 and not full_coordinator._current_occupancy.has(Vector2i(7, 2)))
	assert(full_coordinator._current_occupancy.get(full_formation.cell) == full_formation.member_id)

	print("SITE_COMBAT_MOVEMENT_IDLE_FAST_PATH_PASS")
	quit(0)
