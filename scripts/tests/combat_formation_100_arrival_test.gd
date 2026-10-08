extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const MEMBERS := 100
const STEP := 0.05
const MAX_TICKS := 4500

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func _run() -> void:
	var preset := "loose"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--preset="):
			preset = argument.trim_prefix("--preset=")
	if not _require(Destination.is_valid_preset(preset) and preset != "auto", "Unknown fixed formation preset"): return
	var terrain := Helper.build_flat_map(90, 75)
	var army := Helper.create_test_army(terrain, 1, 0, MEMBERS, Vector2i(5, 28))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var goal := Vector2i(62, 36)
	var preview: Dictionary = army.preview_combat_move(goal, Vector2i.RIGHT, preset)
	if not _require(bool(preview.get("ok", false)) and preview.platform_slots.size() == MEMBERS and preview.approach_queue_slots.is_empty(), "Hundred-person %s preview needs one complete template" % preset): return
	if not _require(bool(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, goal, -1, Vector2i.RIGHT, preset).get("ok", false)), "Hundred-person %s order was refused" % preset): return
	var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
	if not _require(plan.platform_slots == preview.platform_slots and plan.formation_preset_id == preset, "Preview and submitted fixed formation differ"): return
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
			if not _require(terrain.is_walkable(cell) and not occupied.has(cell), "Physical cells overlap or leave terrain at tick %d" % tick): return
			occupied[cell] = true
			if cell != previous[index] and not _require(terrain.can_step(previous[index], cell), "A member skipped a legal edge at tick %d" % tick): return
			previous[index] = cell
			var claim: Vector2i = army.moving_to[index]
			if claim != TerrainArmy.INVALID_CELL:
				if not _require(not claims.has(claim), "Two members claimed the same step at tick %d" % tick): return
				claims[claim] = true
		if army.combat_order == TerrainArmy.CombatOrder.HOLD:
			completed_tick = tick
			break
	if not _require(completed_tick >= 0 and army.command_status.begins_with("已抵達"), "The full wide formation did not arrive within the original movement tick budget: " + army.command_status): return
	if not _require(Destination.is_settled(plan, army.get_active_members_occupancy()) and plan.member_slot_map.size() == MEMBERS, "Not all 100 original members occupy their own final slots"): return
	var expected: Dictionary = {}
	for slot in Destination.shape_slots(preset, MEMBERS, plan.resolved_anchor, plan.final_facing):
		expected[slot] = true
	for slot: Vector2i in plan.member_slot_map.values():
		if not _require(expected.erase(slot), "Final slot differs from the fixed template"): return
		var lease = coordinator.deployment_registry.owner_of(slot)
		if not _require(lease != null and lease.formation_id == army.team_id and lease.order_serial == plan.order_serial, "Final wide slot lost its lease"): return
	if not _require(expected.is_empty(), "An expected fixed slot was not assigned"): return
	var final_cells: Array[Vector2i] = army.cells.duplicate()
	for tick in range(100):
		coordinator.combat_logic_tick(STEP)
		army.prepare_combat(STEP)
		coordinator.complete_committed_moves()
		if not _require(army.combat_order == TerrainArmy.CombatOrder.HOLD and army.cells == final_cells and coordinator.get_inflight_batches_for_formation(army).is_empty(), "Fixed HOLD drifted during five simulated seconds"): return
	print("COMBAT FORMATION 100 ARRIVAL PASS: preset=", preset, " tick=", completed_tick)
	coordinator.unregister_formation(army)
	army.free()
	quit(0)
