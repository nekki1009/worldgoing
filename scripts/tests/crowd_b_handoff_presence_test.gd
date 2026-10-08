extends SceneTree
## Original Army presence repair: detached swaps preserve identity and topology.
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
var checks: int = 0
var owned: Array[Node] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> bool:
	checks += 1
	print("B_PRESENCE ", "PASS " if ok else "FAIL ", label)
	if not ok: push_error(label)
	return ok

func _fixture(map: TerrainData, cells: Array[Vector2i], acting: bool) -> Dictionary:
	var army: TerrainArmy = Helper.create_test_army(map, 1, 0, cells.size(), Vector2i(3, 3))
	owned.append(army)
	var state: Dictionary = army.capture_combat_state()
	state.command_radius = 8.0
	state.formal_commander = 0
	state.acting_commander = 1 if acting else -1
	state.current_commander = 1 if acting else 0
	state.needs_attack_order = false
	state.combat_order = TerrainArmy.CombatOrder.HOLD
	state.combat_attacking = false
	var positions: Dictionary = {}
	for index in range(cells.size()):
		var row: Dictionary = state.units[index]
		var cell: Vector2i = cells[index]
		row.cell = [cell.x, cell.y]
		row.slot = row.cell.duplicate()
		row.crowd_position = [cell.x + 0.5, cell.y + 0.5]
		row.hp = 100.0
		row.ko = 0.0
		row.pose = "idle"
		row.captive = false
		row.departed = false
		row.present = not acting or index != 0
		positions[int(row.person_id)] = Vector2(cell) + Vector2(0.5, 0.5)
	return {"state": state, "positions": positions}

func _unchanged_people(before: Dictionary, after: Dictionary) -> bool:
	var before_cells: Array = []
	var after_cells: Array = []
	for index in range(before.units.size()):
		var old: Dictionary = before.units[index].duplicate(true)
		var new: Dictionary = after.units[index].duplicate(true)
		before_cells.append(str(old.cell))
		after_cells.append(str(new.cell))
		for key: String in ["cell", "slot", "crowd_position", "present"]:
			old.erase(key)
			new.erase(key)
		if old != new: return false
	before_cells.sort()
	after_cells.sort()
	for key: String in ["formal_commander", "acting_commander", "current_commander", "officers", "rng", "command_radius", "goal", "combat_order", "tactical_ai"]:
		if before[key] != after[key]: return false
	return before_cells == after_cells

func _run() -> void:
	var ok: bool = _cases()
	for node: Node in owned:
		if is_instance_valid(node): node.free()
	print("CROWD_B_HANDOFF_PRESENCE_", "PASS" if ok else "FAIL", " checks=", checks)
	quit(0 if ok else 2)

func _cases() -> bool:
	var map: TerrainData = Helper.build_flat_map(40, 20)
	var fixture: Dictionary = _fixture(map, [Vector2i(5, 5), Vector2i(25, 5), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(6, 5), Vector2i(5, 6)], true)
	var state: Dictionary = fixture.state
	var baseline: Dictionary = state.duplicate(true)
	if not _check(not TerrainArmy.prepare_handoff_geometry(state, map, {}).ok, "fixture requires original current near and original formal outside"): return false
	var repaired: Dictionary = TerrainArmy.prepare_handoff_presence(state, map, {}, {}, {}, fixture.positions)
	if not _check(repaired.ok and repaired.relocations.size() == 2 and repaired.presence_attempts == 1, "direct formal/current swap resolves both constraints first"): return false
	if not _check(repaired.snapshot.units[0].cell == baseline.units[1].cell and repaired.snapshot.units[1].cell == baseline.units[0].cell, "direct swap exchanges only the two original legal cells"): return false
	if not _check(TerrainArmy.prepare_handoff_geometry(repaired.snapshot, map, {}).ok and _unchanged_people(baseline, repaired.snapshot), "strict original validator accepts with identity items wounds orders radius RNG untouched"): return false
	if not _check(state == baseline, "success never mutates its source snapshot"): return false
	var unchanged: Dictionary = TerrainArmy.prepare_handoff_presence(repaired.snapshot, map, {}, {}, {}, fixture.positions)
	if not _check(unchanged.ok and unchanged.relocations.is_empty() and unchanged.presence_attempts == 0, "already valid geometry needs no search or relocation"): return false
	var guarded: Dictionary = {int(state.units[0].person_id): true, int(state.units[1].person_id): true}
	var blocked: Dictionary = TerrainArmy.prepare_handoff_presence(state, map, {}, {}, guarded, fixture.positions)
	if not _check(not blocked.ok and blocked.relocations.is_empty() and state == baseline, "effective guard/guarded commanders are never moved"): return false
	var fixed: Dictionary = {}
	for y in range(map.size.y): fixed[Vector2i(15, y)] = true
	blocked = TerrainArmy.prepare_handoff_presence(state, map, {}, fixed, {}, fixture.positions)
	if not _check(not blocked.ok and state == baseline, "foreign fixed claims form a wall that swaps cannot cross"): return false
	for y in range(map.size.y): map.static_blocked[map.index(Vector2i(15, y))] = 1
	blocked = TerrainArmy.prepare_handoff_presence(state, map, {}, {}, {}, fixture.positions)
	if not _check(not blocked.ok and state == baseline, "real terrain wall prevents cross-component swaps"): return false
	map.static_blocked.fill(0)
	var no_sources: Dictionary = TerrainArmy.prepare_handoff_presence(state, map, {}, {}, {}, {})
	if not _check(not no_sources.ok and state == baseline, "missing original positions cannot authorize relocation"): return false
	var actor: TerrainTestCharacter = TerrainTestCharacter.new()
	owned.append(actor)
	actor.person_id = 90001
	actor.position = Vector2(5.5, 5.5) * TerrainRenderer.CELL_PIXELS
	var actor_state: Dictionary = actor.capture_state()
	var actor_before: Dictionary = actor_state.duplicate(true)
	var joined: Dictionary = state.duplicate(true)
	joined.player_member = {"id": actor.person_id, "present": true, "goal": [5, 5]}
	var actors: Dictionary = {actor.person_id: actor_state}
	repaired = TerrainArmy.prepare_handoff_presence(joined, map, actors, {}, {}, fixture.positions)
	if not _check(repaired.ok and actor_state == actor_before and repaired.snapshot.player_member == joined.player_member and _unchanged_people(joined, repaired.snapshot), "joined original Actor remains untouched while original row commanders swap"): return false
	fixture = _fixture(map, [Vector2i(25, 5), Vector2i(5, 5), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(6, 5), Vector2i(5, 6)], false)
	baseline = fixture.state.duplicate(true)
	repaired = TerrainArmy.prepare_handoff_presence(fixture.state, map, {}, {}, {}, fixture.positions)
	if not _check(repaired.ok and repaired.relocations.size() == 2 and _unchanged_people(baseline, repaired.snapshot), "single distant formal commander uses an existing same-team legal cell"): return false
	if not _check(fixture.state == baseline, "single swap leaves source dictionaries unchanged"): return false
	var source_fixed: Dictionary = {Vector2i(25, 5): true}
	var components: Dictionary = {}
	if not _check(TerrainArmy._handoff_presence_reachable(map, Vector2i(25, 5), Vector2i(5, 5), source_fixed, components), "original person may leave a fixed source through a real legal edge"): return false
	if not _check(not TerrainArmy._handoff_presence_reachable(map, Vector2i(5, 5), Vector2i(25, 5), source_fixed, components), "a fixed destination is never accepted"): return false
	return true
