extends SceneTree
## Real Lab contact prepass and exchange settlement with original Army owners.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("SITE MOVE ENCOUNTER LAB timed out")
		quit(1))
	_run.call_deferred()

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
	return ok

func _fixture(positions: Array[Vector2i]) -> Dictionary:
	var data := Helper.build_flat_map(24, 24)
	var lab := TerrainLab.new()
	lab.terrain = data
	var coordinator := Coordinator.new()
	var armies: Array[TerrainArmy] = []
	for i in range(positions.size()):
		var team := Helper.create_test_army(data, i + 1, i, 1, positions[i])
		coordinator.register_formation(team)
		armies.append(team)
		lab.combat_armies.append(team)
		assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD).ok)
	return {"data": data, "lab": lab, "coordinator": coordinator, "armies": armies}

func _dispose(fixture: Dictionary) -> void:
	for team: TerrainArmy in fixture.armies:
		fixture.coordinator.unregister_formation(team)
		team.free()
	(fixture.lab as TerrainLab).free()

func _move(team: TerrainArmy, goal: Vector2i) -> bool:
	return _require(bool(team.issue_combat_order(team.current_commander,
		TerrainArmy.CombatOrder.MOVE, goal).get("ok", false)), "MOVE order rejected")

func _move_hold_and_resume() -> bool:
	var f := _fixture([Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6)])
	var lab: TerrainLab = f.lab
	var a: TerrainArmy = f.armies[0]
	var b: TerrainArmy = f.armies[1]
	var c: TerrainArmy = f.armies[2]
	var a_id := a.combat_identity(0)
	var b_id := b.combat_identity(0)
	var c_id := c.combat_identity(0)
	lab._resolve_exchanges()
	var ok := _require(lab.exchange_count == 0 and not b.exchange_initiates(0, a_id, true),
		"HOLD neighbours cannot initiate without a MOVE contact")
	if not _move(a, Vector2i(12, 5)):
		_dispose(f)
		return false
	var plan := a.get_active_move_plan()
	# Contact must publish even when the mover is still cooling down.
	a.combat_hot_set(0, &"exchange_cooldown", 2.0)
	lab._resolve_exchanges()
	ok = _require(lab.exchange_count == 0 and plan.tactical_overlay == Types.TacticalOverlay.ENGAGING
		and a.exchange_initiates(0, b_id, true) and a.exchange_initiates(0, c_id, true)
		and not b.exchange_initiates(0, a_id, true),
		"MOVE must discover both HOLD contacts independently of cooldown") and ok
	a.combat_hot_set(0, &"exchange_cooldown", 0.0)
	var events: Array[Dictionary] = []
	lab.exchange_resolved.connect(func(left: int, right: int, _result: Dictionary) -> void:
		events.append({"left": left, "right": right,
			"a_cooldown": a.combat_hot_get(0, &"exchange_cooldown", 0.0),
			"b_cooldown": b.combat_hot_get(0, &"exchange_cooldown", 0.0),
			"c_cooldown": c.combat_hot_get(0, &"exchange_cooldown", 0.0)}))
	lab._resolve_exchanges()
	ok = _require(lab.exchange_count == 2 and events.size() == 2,
		"One MOVE must settle both adjacent HOLD opponents in the same round") and ok
	for event: Dictionary in events:
		ok = _require(float(event.a_cooldown) == SiteCombatRules.EXCHANGE_ROUND_SECONDS
			and float(event.b_cooldown) == SiteCombatRules.EXCHANGE_ROUND_SECONDS
			and float(event.c_cooldown) == SiteCombatRules.EXCHANGE_ROUND_SECONDS,
			"Each callback must observe the fully settled simultaneous round") and ok
	lab._resolve_exchanges()
	ok = _require(lab.exchange_count == 2 and plan.tactical_overlay == Types.TacticalOverlay.ENGAGING,
		"Cooldown must suppress another exchange without clearing contact") and ok
	# Remove both opponents from adjacency using the original Army position stores.
	b._cell_owners.erase(b.cells[0])
	b.cells[0] = Vector2i(18, 18)
	b._cell_owners[b.cells[0]] = 0
	c._cell_owners.erase(c.cells[0])
	c.cells[0] = Vector2i(19, 18)
	c._cell_owners[c.cells[0]] = 0
	lab._resolve_exchanges()
	ok = _require(plan == a.get_active_move_plan() and plan.tactical_overlay == Types.TacticalOverlay.NONE
		and a._move_encounters.is_empty(), "Contact removal must clear ENGAGING on the original plan") and ok
	var coordinator: SiteCombatMovementCoordinator = f.coordinator
	var paused_cell := a.cells[0]
	var resumed := false
	for tick in range(40):
		coordinator.combat_logic_tick_if_needed(0.05)
		a.prepare_combat(0.05)
		coordinator.complete_committed_moves()
		if a.cells[0] != paused_cell or a.moving_to[0] != TerrainArmy.INVALID_CELL:
			resumed = true
			break
	ok = _require(resumed, "Coordinator must resume the original MOVE after contact clears") and ok
	_dispose(f)
	return ok

func _move_move_and_geometry() -> bool:
	var f := _fixture([Vector2i(5, 5), Vector2i(6, 5)])
	var lab: TerrainLab = f.lab
	var a: TerrainArmy = f.armies[0]
	var b: TerrainArmy = f.armies[1]
	if not (_move(a, Vector2i(12, 5)) and _move(b, Vector2i(12, 7))):
		_dispose(f)
		return false
	# The wall is installed after legal orders so this tests contact geometry.
	var data: TerrainData = f.data
	data.static_blocked[data.index(b.cells[0])] = 1
	lab._resolve_exchanges()
	var ok := _require(lab.exchange_count == 0 and a._move_encounters.is_empty()
		and b._move_encounters.is_empty(), "Adjacent enemies across blocked geometry cannot engage")
	data.static_blocked[data.index(b.cells[0])] = 0
	lab._resolve_exchanges()
	ok = _require(lab.exchange_count == 1 and a.exchange_initiates(0, b.combat_identity(0), true)
		and b.exchange_initiates(0, a.combat_identity(0), true)
		and a.get_active_move_plan().tactical_overlay == Types.TacticalOverlay.ENGAGING
		and b.get_active_move_plan().tactical_overlay == Types.TacticalOverlay.ENGAGING,
		"MOVE/MOVE must publish reciprocal contact and settle once") and ok
	_dispose(f)
	return ok

func _landing_before_query() -> bool:
	var f := _fixture([Vector2i(5, 5), Vector2i(7, 5)])
	var lab: TerrainLab = f.lab
	var a: TerrainArmy = f.armies[0]
	var b: TerrainArmy = f.armies[1]
	var coordinator: SiteCombatMovementCoordinator = f.coordinator
	lab.combat_movement_coordinator = coordinator
	a.exchange_people_query = lab._exchange_people.bind(false)
	if not _move(a, Vector2i(12, 5)):
		_dispose(f)
		return false
	var mid := a.combat_identity(0)
	var landing := Vector2i(6, 5)
	a.begin_committed_move(mid, a.cells[0], landing)
	a.move_progress[0] = 1.0
	coordinator.restore_inflight_batches_for_formation(a, [[mid]])
	lab._exchange_phase = 0.0
	lab._advance_combat(1.0 / 30.0)
	var ok := _require(a.cells[0] == landing and a.moving_to[0] == TerrainArmy.INVALID_CELL
		and lab.exchange_count == 0, "Committed MOVE must land between scheduled exchange queries")
	lab._advance_combat(1.0 / 30.0)
	ok = _require(a.moving_to[0] == TerrainArmy.INVALID_CELL and a.get_active_move_plan() != null
		and a.get_active_move_plan().tactical_overlay == Types.TacticalOverlay.ENGAGING
		and lab.exchange_count == 0, "Fresh hostile adjacency must block the next step before the 10 Hz query") and ok
	lab._advance_combat(1.0 / 30.0)
	ok = _require(lab.exchange_count == 1 and a.exchange_initiates(0, b.combat_identity(0), true),
		"Next scheduled query must settle the adjacent MOVE/HOLD exchange") and ok
	_dispose(f)
	return ok

func _run() -> void:
	if not _move_hold_and_resume() or not _move_move_and_geometry() or not _landing_before_query():
		quit(1)
		return
	print("SITE MOVE ENCOUNTER LAB PASS")
	quit(0)
