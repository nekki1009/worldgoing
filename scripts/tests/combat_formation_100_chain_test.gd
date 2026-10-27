extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const MEMBERS := 100
const STEP := 0.05
const MAX_TICKS := 4500
const SEQUENCE := ["square", "wedge", "goose", "circle", "hook", "loose", "square"]

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
		quit(1)
	return ok

func _drive(army: TerrainArmy, coordinator: Object, terrain: TerrainData, preset: String) -> bool:
	var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
	if not _require(plan != null and plan.formation_preset_id == preset, "Missing %s contract" % preset): return false
	var previous: Array[Vector2i] = army.cells.duplicate()
	var completed_tick := -1
	for tick in range(MAX_TICKS):
		coordinator.combat_logic_tick(STEP)
		army.prepare_combat(STEP)
		coordinator.complete_committed_moves()
		var occupied: Dictionary = {}
		var claims: Dictionary = {}
		for index in range(MEMBERS):
			var cell: Vector2i = army.cells[index]
			if not _require(terrain.is_walkable(cell) and not occupied.has(cell), "%s: duplicate or illegal cell at tick %d" % [preset, tick]): return false
			occupied[cell] = true
			if cell != previous[index] and not _require(terrain.can_step(previous[index], cell), "%s: skipped physical edge at tick %d" % [preset, tick]): return false
			previous[index] = cell
			var claim: Vector2i = army.moving_to[index]
			if claim != TerrainArmy.INVALID_CELL:
				if not _require(not claims.has(claim), "%s: duplicate in-flight claim at tick %d" % [preset, tick]): return false
				claims[claim] = true
		if army.combat_order == TerrainArmy.CombatOrder.HOLD:
			completed_tick = tick
			break
	if not _require(completed_tick >= 0 and army.command_status.begins_with("已抵達"), "%s did not complete within %d ticks: %s" % [preset, MAX_TICKS, army.command_status]): return false
	if not _require(Destination.is_settled(plan, army.get_active_members_occupancy()) and plan.member_slot_map.size() == MEMBERS, "%s: not all original members reached their own slots" % preset): return false
	var expected: Dictionary = {}
	for slot: Vector2i in Destination.shape_slots(preset, MEMBERS, plan.resolved_anchor, plan.final_facing):
		expected[slot] = true
	for index in range(MEMBERS):
		var slot: Vector2i = plan.get_slot_for_member(army.combat_identity(index))
		if not _require(expected.erase(slot) and army.cells[index] == slot and army.facing[index] == plan.get_facing_for_slot(slot), "%s: wrong slot or facing for member %d" % [preset, index]): return false
		var lease = coordinator.deployment_registry.owner_of(slot)
		if not _require(lease != null and lease.formation_id == army.team_id and lease.order_serial == plan.order_serial, "%s: missing final lease" % preset): return false
	if not _require(expected.is_empty() and army._reserved_cells.is_empty() and coordinator.get_inflight_batches_for_formation(army).is_empty(), "%s: incomplete shape or remaining in-flight step" % preset): return false
	var settled: Array[Vector2i] = army.cells.duplicate()
	for tick in range(100):
		coordinator.combat_logic_tick(STEP)
		army.prepare_combat(STEP)
		coordinator.complete_committed_moves()
		if not _require(army.combat_order == TerrainArmy.CombatOrder.HOLD and army.cells == settled and coordinator.get_inflight_batches_for_formation(army).is_empty(), "%s: HOLD drifted within five seconds" % preset): return false
	print("COMBAT FORMATION 100 CHAIN STEP PASS: ", preset, " tick=", completed_tick)
	return true

func _run() -> void:
	var sequence: Array = ["hook", "loose"] if OS.get_cmdline_user_args().has("--hook-loose") else SEQUENCE
	var terrain := Helper.build_flat_map(90, 75)
	var army := Helper.create_test_army(terrain, 1, 0, MEMBERS, Vector2i(5, 28))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	if not _require(bool(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(62, 36), -1, Vector2i.RIGHT, sequence[0]).get("ok", false)), "Initial 100-person %s order failed" % sequence[0]): return
	if not _drive(army, coordinator, terrain, sequence[0]): return
	for preset: String in sequence.slice(1):
		army._command_dirty = true
		army.settle_combat_command()
		var command: Dictionary = army.issue_formation_change(army.current_commander, preset)
		if not _require(bool(command.get("ok", false)), "100-person in-place switch to %s was rejected: %s" % [preset, str(command)]): return
		if not _drive(army, coordinator, terrain, preset): return
	print("COMBAT FORMATION 100 CHAIN PASS")
	coordinator.unregister_formation(army)
	army.free()
	TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
	quit(0)
