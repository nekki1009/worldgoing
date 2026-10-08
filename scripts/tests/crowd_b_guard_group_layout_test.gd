extends SceneTree
## Pure original-owner geometry contracts. Natural DR acceptance remains separate.
const Handoff = preload("res://scripts/terrain_lab/crowd_clear_handoff.gd")
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
var checks: int = 0
var owned: Array[Node] = []

class GuardLab extends Node:
	var terrain: TerrainData

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	print("B_GUARD_GROUP ", "PASS " if ok else "FAIL ", label, " ", details if details != null else "")
	if not ok: push_error(label)
	return ok

func _fixture(captive_count: int = 1) -> Dictionary:
	var map: TerrainData = Helper.build_flat_map(40, 20)
	var cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(25, 5), Vector2i(4, 4),
		Vector2i(5, 4), Vector2i(6, 4), Vector2i(6, 5), Vector2i(5, 6)]
	var army: TerrainArmy = Helper.create_test_army(map, 2, 0, cells.size(), Vector2i(3, 3))
	owned.append(army)
	var snapshot: Dictionary = army.capture_combat_state()
	snapshot.command_radius = 8.0
	snapshot.formal_commander = 0
	snapshot.acting_commander = 1
	snapshot.current_commander = 1
	snapshot.needs_attack_order = false
	snapshot.combat_order = TerrainArmy.CombatOrder.HOLD
	snapshot.combat_attacking = false
	var people: Array = []
	for index in range(cells.size()):
		var row: Dictionary = snapshot.units[index]
		row.person_id = 102 if index == 0 else (142 if index == 1 else 200 + index)
		row.cell = [cells[index].x, cells[index].y]
		row.slot = row.cell.duplicate()
		row.crowd_position = [cells[index].x + 0.5, cells[index].y + 0.5]
		row.hp = 41.125 if index == 0 else 73.25
		row.ko = 0.0
		row.pose = "idle"
		row.captive = false
		row.departed = false
		row.present = index != 0
		row.cargo = {"grain": index + 1}
		row.item_state = {}
		var seeded: Dictionary = SiteRuntime.seed_person_equipment(map, row.item_state, int(row.person_id), row.get("appearance", {}))
		assert(seeded.ok and not row.item_state.item_ids.is_empty(), "geometry fixture requires the original real item holder and item IDs")
		people.append({"person_id": int(row.person_id), "position": Vector2(cells[index]) + Vector2.ONE * 0.5, "standing": true})
	var guard_lab: GuardLab = GuardLab.new()
	guard_lab.terrain = map
	owned.append(guard_lab)
	var actions: SitePersonActions = SitePersonActions.new()
	actions.lab = guard_lab
	var guards: Dictionary = {}
	var captive_army: TerrainArmy = Helper.create_test_army(map, 40, 1, captive_count, Vector2i(3, 12))
	owned.append(captive_army)
	var captive_snapshot: Dictionary = captive_army.capture_combat_state()
	var captivity: Dictionary = {}
	var captive_cells: Array[Vector2i] = [Vector2i(5, 7), Vector2i(4, 7), Vector2i(6, 7), Vector2i(5, 8)]
	for index in range(captive_count):
		var identity: int = 3903 + index
		guards[identity] = 102
		var row: Dictionary = captive_snapshot.units[index]
		row.person_id = identity
		row.cell = [captive_cells[index].x, captive_cells[index].y]
		row.slot = row.cell.duplicate()
		row.crowd_position = [captive_cells[index].x + 0.5, captive_cells[index].y + 0.5]
		row.hp = 37.125
		row.stun = 21.25
		row.ko = 0.0
		row.captive = true
		row.cargo = {"grain": 3}
		row.item_state = {}
		var seeded: Dictionary = SiteRuntime.seed_person_equipment(map, row.item_state, identity, row.get("appearance", {}))
		assert(seeded.ok and not row.item_state.item_ids.is_empty(), "companion fixture requires its original real item holder and IDs")
		captivity[str(identity)] = {"guard_id": 102, "captor_id": 102, "captor_faction": 0}
		people.append({"person_id": identity, "position": Vector2(captive_cells[index]) + Vector2.ONE * 0.5, "standing": true})
	# An unrelated standing owner near the destination is occupancy, not terrain.
	people.append({"person_id": 90001, "position": Vector2(24.5, 5.5), "standing": true})
	var layout: Dictionary = Handoff.plan_legal_positions(map, people, {}, guards, {}, actions._within_guard_range)
	return {"map": map, "snapshot": snapshot, "actors": {}, "people": people,
		"guards": guards, "layout": layout, "actions": actions, "captive_snapshot": captive_snapshot, "captivity": captivity}

func _sources(fixture: Dictionary) -> Dictionary:
	return {"snapshot": fixture.snapshot.duplicate(true), "actors": fixture.actors.duplicate(true),
		"people": fixture.people.duplicate(true), "guards": fixture.guards.duplicate(true), "layout": fixture.layout.duplicate(true),
		"captive_snapshot": fixture.captive_snapshot.duplicate(true), "captivity": fixture.captivity.duplicate(true), "site": fixture.map.site.duplicate(true)}

func _repair(fixture: Dictionary, fixed: Dictionary = {}, budget: int = -1) -> Dictionary:
	return Handoff.prepare_guarded_presence(fixture.snapshot, fixture.map, fixture.actors, fixed,
		fixture.guards, fixture.people, fixture.layout, fixture.actions._within_guard_range, {}, budget)

func _non_geometry_unchanged(before: Dictionary, after: Dictionary) -> bool:
	var old: Dictionary = before.duplicate(true)
	var current: Dictionary = after.duplicate(true)
	for snapshot: Dictionary in [old, current]:
		snapshot.erase("reference")
		snapshot.erase("command_reference_valid")
		for row: Dictionary in snapshot.units:
			for field: String in ["cell", "slot", "crowd_position", "present"]: row.erase(field)
	return old == current

func _result_valid(fixture: Dictionary, result: Dictionary) -> bool:
	if not result.ok or not TerrainArmy.prepare_handoff_geometry(result.snapshot, fixture.map, fixture.actors).ok: return false
	var expected_claims: Dictionary = {}
	for person: Dictionary in fixture.people:
		var identity: int = int(person.person_id)
		if not result.cells.has(identity): return false
		var cell: Vector2i = result.cells[identity]
		if not fixture.map.is_walkable(cell): return false
		if bool(person.standing):
			if expected_claims.has(cell): return false
			expected_claims[cell] = identity
		var source := Vector2i((person.position as Vector2).floor())
		if not TerrainArmy._handoff_presence_reachable(fixture.map, source, cell, {}, {}): return false
	for captive: int in fixture.guards:
		if not fixture.actions._within_guard_range(result.cells[int(fixture.guards[captive])], result.cells[captive]): return false
	return expected_claims == result.claimed

func _cases() -> bool:
	var fixture: Dictionary = _fixture()
	if not _check(fixture.layout.ok, "source guard102/captive3903 has a legal original all-person layout"): return false
	var before: Dictionary = _sources(fixture)
	var source_holder: Dictionary = fixture.snapshot.units[0].item_state
	var source_cargo: Dictionary = fixture.snapshot.units[0].cargo
	var original_positions: Dictionary = {}
	for person: Dictionary in fixture.people: original_positions[int(person.person_id)] = person.position
	var original: Dictionary = TerrainArmy.prepare_handoff_presence(fixture.snapshot, fixture.map, {}, {},
		{102: true, 3903: true}, original_positions)
	if not _check(not original.ok and original.code == "PRESENCE_CONFLICT", "old one-row swap cannot relocate the effective guarded commander"): return false
	var repaired: Dictionary = _repair(fixture)
	if not _check(_result_valid(fixture, repaired), "guarded original formal and cross-team captive move together legally", repaired.get("reason", "")): return false
	if not _check(repaired.snapshot.units[0].cell == [25, 5] and repaired.snapshot.units[1].cell == [5, 5]
		and repaired.cells[102] == Vector2i(25, 5) and repaired.cells[142] == Vector2i(5, 5),
		"formal/current keep their original identities while taking the same-team swapped cells"): return false
	if not _check(repaired.cells[3903] != fixture.layout.cells[3903] and repaired.cells[90001] == fixture.layout.cells[90001],
		"the captive follows its original guard and unrelated ownership stays fixed"): return false
	if not _check(_non_geometry_unchanged(before.snapshot, repaired.snapshot),
		"all person/item/cargo/AI/order/ability/RNG/radius fields outside geometry remain exact"): return false
	if not _check(_sources(fixture) == before and is_same(fixture.snapshot.units[0].item_state, source_holder)
		and is_same(fixture.snapshot.units[0].cargo, source_cargo), "accepted candidate leaves source values and holder/cargo aliases untouched"): return false
	var repeated: Dictionary = _repair(fixture)
	if not _check(repeated == repaired, "candidate ordering and nearest-cell BFS are deterministic"): return false
	fixture = _fixture(4)
	before = _sources(fixture)
	var fixed: Dictionary = {Vector2i(25, 4): true, Vector2i(25, 6): true}
	var fixed_before: Dictionary = fixed.duplicate()
	repaired = _repair(fixture, fixed)
	if not _check(_result_valid(fixture, repaired) and repaired.relocations.size() == 6,
		"all four cross-team captives are retained in one guard group and all six moves are reported"): return false
	for identity: int in fixture.guards:
		if not _check(not fixed.has(repaired.cells[identity]), "group respects every foreign fixed claim", identity): return false
	if not _check(_sources(fixture) == before and fixed == fixed_before and fixture.guards.size() == 4,
		"multiple-captive preparation never rewrites inputs or guard cardinality"): return false
	var limited: Dictionary = _repair(fixture, {}, 1)
	if not _check(not limited.ok and limited.get("code", "") == "SEARCH_LIMIT" and _sources(fixture) == before and int(limited.get("searched_cells", 0)) <= 1,
		"bounded failed search leaves every candidate input unchanged", limited.get("reason", limited.get("code", ""))): return false
	fixed = {}
	for y in range(fixture.map.size.y): fixed[Vector2i(15, y)] = true
	fixed_before = fixed.duplicate()
	var blocked: Dictionary = _repair(fixture, fixed)
	if not _check(not blocked.ok and _sources(fixture) == before and fixed == fixed_before,
		"group cannot cross a foreign fixed wall and failed attempts leave no partial moves"): return false
	for y in range(fixture.map.size.y): fixture.map.static_blocked[fixture.map.index(Vector2i(15, y))] = 1
	blocked = _repair(fixture)
	if not _check(not blocked.ok and _sources(fixture) == before,
		"the original can_step topology rejects crossing a real terrain wall"): return false
	return _dense_first_donor() and _free_cell_group() and _seeded_claims() and _move_goal_layout() and _zero_platform_queue()

func _dense_first_donor() -> bool:
	var fixture: Dictionary = _fixture()
	var cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5), Vector2i(25, 5),
		Vector2i(32, 5), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)]
	for index in range(cells.size()):
		var row: Dictionary = fixture.snapshot.units[index]
		row.cell = [cells[index].x, cells[index].y]
		row.slot = row.cell.duplicate()
		row.crowd_position = [cells[index].x + 0.5, cells[index].y + 0.5]
		fixture.people[index].position = Vector2(cells[index]) + Vector2.ONE * 0.5
	var occupied: Dictionary = {}
	for person: Dictionary in fixture.people: occupied[Vector2i((person.position as Vector2).floor())] = true
	var next_id: int = 91000
	for x in range(21, 30):
		for y in range(1, 10):
			var cell := Vector2i(x, y)
			if absi(x - 25) + absi(y - 5) > 4 or occupied.has(cell): continue
			fixture.people.append({"person_id": next_id, "position": Vector2(cell) + Vector2.ONE * 0.5, "standing": true})
			occupied[cell] = true
			next_id += 1
	fixture.layout = Handoff.plan_legal_positions(fixture.map, fixture.people, {}, fixture.guards, {}, fixture.actions._within_guard_range)
	if not _check(fixture.layout.ok, "dense first-donor fixture starts with all original standing owners in unique cells"): return false
	var before: Dictionary = _sources(fixture)
	var first: Dictionary = TerrainArmy._handoff_presence_candidate(fixture.snapshot, fixture.map, {}, Vector2i(0, 2))
	if not _check(first.ok, "nearest distant donor has valid command geometry before companion-space validation"): return false
	var repaired: Dictionary = _repair(fixture)
	return _check(_result_valid(fixture, repaired) and int(repaired.guard_group.donor_id) == int(fixture.snapshot.units[3].person_id)
		and int(repaired.presence_attempts) > 1 and int(repaired.presence_attempts) <= fixture.snapshot.units.size() - 1
		and _sources(fixture) == before,
		"a full first guard-group destination does not prevent a later complete bounded candidate", repaired.get("guard_group", {}))
func _free_cell_group() -> bool:
	var fixture: Dictionary = _fixture()
	var cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5), Vector2i(25, 5),
		Vector2i(32, 5), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)]
	for index in range(cells.size()):
		var row: Dictionary = fixture.snapshot.units[index]
		row.cell = [cells[index].x, cells[index].y]
		row.slot = row.cell.duplicate()
		row.crowd_position = [cells[index].x + 0.5, cells[index].y + 0.5]
		fixture.people[index].position = Vector2(cells[index]) + Vector2.ONE * 0.5
	var occupied: Dictionary = {}
	for person: Dictionary in fixture.people: occupied[Vector2i((person.position as Vector2).floor())] = true
	var next_id: int = 92000
	for centre in [25, 32]:
		for x in range(centre - 4, centre + 5):
			for y in range(1, 10):
				var cell := Vector2i(x, y)
				if absi(x - centre) + absi(y - 5) > 4 or occupied.has(cell): continue
				fixture.people.append({"person_id": next_id, "position": Vector2(cell) + Vector2.ONE * 0.5, "standing": true})
				occupied[cell] = true
				next_id += 1
	fixture.layout = Handoff.plan_legal_positions(fixture.map, fixture.people, {}, fixture.guards, {}, fixture.actions._within_guard_range)
	if not _check(fixture.layout.ok, "free-cell fixture begins with a legal full standing layout"): return false
	var strict_pairs: int = 0
	for other in range(1, fixture.snapshot.units.size()):
		var pair: Dictionary = TerrainArmy._handoff_presence_candidate(fixture.snapshot, fixture.map, {}, Vector2i(0, other))
		if not pair.ok: continue
		strict_pairs += 1
		var guard_cell: Vector2i = Handoff._cell(pair.snapshot.units[0].cell)
		var free_companion: bool = false
		for x in range(maxi(0, guard_cell.x - 4), mini(fixture.map.size.x, guard_cell.x + 5)):
			for y in range(maxi(0, guard_cell.y - 4), mini(fixture.map.size.y, guard_cell.y + 5)):
				var candidate := Vector2i(x, y)
				if not fixture.map.is_walkable(candidate) or (fixture.layout.claimed.has(candidate) and int(fixture.layout.claimed[candidate]) != 3903): continue
				if fixture.actions._within_guard_range(guard_cell, candidate): free_companion = true
		if not _check(not free_companion, "every strict same-team donor lacks an available companion cell", other): return false
	if not _check(strict_pairs == 2, "all donor candidates were examined and both strict pairs lack companion space"): return false
	var before: Dictionary = _sources(fixture)
	var captive_holder: Dictionary = fixture.captive_snapshot.units[0].item_state
	var captive_cargo: Dictionary = fixture.captive_snapshot.units[0].cargo
	var repaired: Dictionary = _repair(fixture)
	if not _check(_result_valid(fixture, repaired) and repaired.guard_group.mode == "free_cell" and int(repaired.guard_group.donor_id) == -1,
		"bounded free-cell fallback places the original guard and captive after all swaps fail", repaired.get("guard_group", {})): return false
	for index in range(1, fixture.snapshot.units.size()):
		if not _check(repaired.snapshot.units[index].cell == fixture.snapshot.units[index].cell,
			"free-cell fallback does not move a donor or another member", fixture.snapshot.units[index].person_id): return false
	if not _check(_non_geometry_unchanged(before.snapshot, repaired.snapshot)
		and _sources(fixture) == before and is_same(fixture.captive_snapshot.units[0].item_state, captive_holder)
		and is_same(fixture.captive_snapshot.units[0].cargo, captive_cargo),
		"free-cell success preserves command identities radius RNG body fields captive items and every source alias"): return false
	if not _check(repaired.claimed.size() == fixture.layout.claimed.size() and int(repaired.guard_searched_cells) <= fixture.map.size.x * fixture.map.size.y
		and int(repaired.pair_attempts) <= fixture.snapshot.units.size() - 1,
		"free placement retains full exclusive occupancy within explicit pair and map-cell bounds"): return false
	var repeated: Dictionary = _repair(fixture)
	if not _check(repeated == repaired, "free-cell nearest-source BFS is stable for identical inputs"): return false
	if not _guard_goal_exclusions(fixture, repaired): return false
	# Only the small source component remains reachable; its every cell lies
	# inside the unchanged command radius. Farther legal empty cells cannot help.
	var fixed: Dictionary = {}
	for y in range(fixture.map.size.y): fixed[Vector2i(10, y)] = true
	for x in range(11): fixed[Vector2i(x, 10)] = true
	var blocked: Dictionary = _repair(fixture, fixed)
	if not _check(not blocked.ok and _sources(fixture) == before,
		"foreign fixed walls cannot be crossed to find a free group placement"): return false
	for cell: Vector2i in fixed: fixture.map.static_blocked[fixture.map.index(cell)] = 1
	blocked = _repair(fixture)
	return _check(not blocked.ok and _sources(fixture) == before,
		"free-cell failure preserves all inputs when real source topology excludes every valid destination")
func _seeded_claims() -> bool:
	var map: TerrainData = Helper.build_flat_map(8, 1)
	var guard_lab: GuardLab = GuardLab.new()
	guard_lab.terrain = map
	owned.append(guard_lab)
	var actions: SitePersonActions = SitePersonActions.new()
	actions.lab = guard_lab
	var claimed: Dictionary = {Vector2i(6, 0): 20}
	for x in range(1, 5): claimed[Vector2i(x, 0)] = 100 + x
	claimed[Vector2i(3, 0)] = 0 # A temporary empty MOVE anchor still permits traversal.
	var before: Dictionary = claimed.duplicate()
	var people: Array = [{"person_id": 30, "position": Vector2(0.5, 0.5), "standing": true}]
	var result: Dictionary = Handoff.plan_legal_positions(map, people, {}, {30: 20}, {20: Vector2i(6, 0)},
		actions._within_guard_range, claimed, 256)
	return _check(result.ok and result.cells[30] == Vector2i(5, 0) and result.claimed.size() == claimed.size() + 1
		and claimed == before, "standing claims and an empty MOVE anchor restrict placement while remaining traversable")

func _guard_goal_exclusions(fixture: Dictionary, first: Dictionary) -> bool:
	var sources: Dictionary = _sources(fixture)
	var plans: Array = []
	for identity in [102, 3903]:
		var cell: Vector2i = first.cells[identity]
		if not _check(not fixture.layout.claimed.has(cell), "the prior guard-group free destination can be reserved without a phantom person", identity): return false
		var snapshot: Dictionary = fixture.snapshot.duplicate(true)
		snapshot.combat_order = TerrainArmy.CombatOrder.MOVE
		snapshot.goal = [cell.x, cell.y]
		plans.append({"snapshot": snapshot})
	var goals: Dictionary = Handoff._move_goal_exclusions(plans, fixture.map, {})
	if not _check(goals.ok and goals.claimed.size() == 2, "original resolver selects the declared guard and captive destination exclusions"): return false
	var reserved: Dictionary = fixture.duplicate()
	reserved.layout = fixture.layout.duplicate(true)
	reserved.layout.claimed.merge(goals.claimed)
	var before: Dictionary = _sources(reserved)
	var next: Dictionary = _repair(reserved)
	if not _check(next.ok and next.guard_group.mode == "free_cell", "free guard-group fallback remains possible around the bounded empty anchors", next.get("reason", "")): return false
	for cell: Vector2i in goals.claimed:
		if not _check(next.claimed.get(cell, -1) == 0 and not next.cells.values().has(cell),
			"neither the free guard nor captive BFS steals an empty MOVE anchor", cell): return false
	var rebuilt: Dictionary = Handoff._presence_claims(reserved.people, next.cells, {}, goals.claimed)
	if not _check(rebuilt.ok and rebuilt.claimed == next.claimed, "rebuilding all standing claims retains every temporary placement exclusion"): return false
	var overlap: Dictionary = next.cells.duplicate()
	overlap[102] = goals.claimed.keys()[0]
	var rejected: Dictionary = Handoff._presence_claims(reserved.people, overlap, {}, goals.claimed)
	if not _check(not rejected.ok, "the final standing-claim check rejects an exclusion overlap before removing sentinels"): return false
	var real: Dictionary = next.duplicate(true)
	for cell: Vector2i in goals.claimed: real.claimed.erase(cell)
	return _check(_result_valid(reserved, real) and _non_geometry_unchanged(fixture.snapshot, next.snapshot)
		and _sources(reserved) == before and _sources(fixture) == sources,
		"guard/captive constraints preserve all real sources and yield only real claims after temporary markers are removed")

func _move_goal_layout() -> bool:
	var fixture: Dictionary = _fixture()
	fixture.snapshot.combat_order = TerrainArmy.CombatOrder.MOVE
	fixture.snapshot.goal = [20, 10]
	fixture.snapshot.formal_commander = 0
	fixture.snapshot.acting_commander = -1
	fixture.snapshot.current_commander = 0
	fixture.snapshot.units[1].cell = [6, 6]
	fixture.snapshot.units[1].slot = [6, 6]
	fixture.snapshot.units[1].crowd_position = [6.5, 6.5]
	fixture.people[1].position = Vector2(6.5, 6.5)
	var army: TerrainArmy = Helper.create_test_army(fixture.map, 60, 1, 49, Vector2i(17, 7))
	owned.append(army)
	var dense: Dictionary = army.capture_combat_state()
	for index in range(dense.units.size()):
		var cell := Vector2i(17 + index % 7, 7 + floori(float(index) / 7.0))
		var row: Dictionary = dense.units[index]
		row.person_id = 50000 + index
		row.cell = [cell.x, cell.y]
		row.slot = row.cell.duplicate()
		row.crowd_position = [cell.x + 0.5, cell.y + 0.5]
		row.hp = 63.125
		row.stun = 7.75
		row.ko = 0.0
		row.cargo = {"grain": 2}
		row.item_state = {}
		var seeded: Dictionary = SiteRuntime.seed_person_equipment(fixture.map, row.item_state, int(row.person_id), row.get("appearance", {}))
		assert(seeded.ok and not row.item_state.item_ids.is_empty(), "dense goal fixture retains real original item holders")
		fixture.people.append({"person_id": int(row.person_id), "position": Vector2(cell) + Vector2.ONE * 0.5, "standing": true})
	var sources: Dictionary = _sources(fixture)
	var dense_before: Dictionary = dense.duplicate(true)
	var holder: Dictionary = dense.units[24].item_state
	var cargo: Dictionary = dense.units[24].cargo
	var ordinary: Dictionary = Handoff.plan_legal_positions(fixture.map, fixture.people, {}, fixture.guards, {}, fixture.actions._within_guard_range)
	var goal := Vector2i(20, 10)
	var blocked_goal: Dictionary = TerrainArmy._resolve_combat_goal_at(fixture.map, goal, func(cell: Vector2i) -> bool: return ordinary.claimed.has(cell))
	if not _check(ordinary.ok and not blocked_goal.ok, "all 49 original resolver goal cells are occupied by real standing people before exclusions"): return false
	var plans: Array = [{"snapshot": fixture.snapshot}, {"snapshot": fixture.snapshot.duplicate(true)}, {"snapshot": dense}]
	var goals: Dictionary = Handoff._move_goal_exclusions(plans, fixture.map, {})
	if not _check(goals.ok and goals.goals.size() == 1 and goals.claimed.size() == 1 and goals.claimed.get(goal, -1) == 0,
		"repeated MOVE goals reserve exactly one original resolver anchor and HOLD reserves none"): return false
	var layout: Dictionary = Handoff.plan_legal_positions(fixture.map, fixture.people, {}, fixture.guards, {}, fixture.actions._within_guard_range, goals.claimed)
	if not _check(layout.ok and layout.claimed.get(goal, -1) == 0 and not layout.cells.values().has(goal),
		"one local placement exclusion opens the requested goal without clearing its region"): return false
	var completed: Dictionary = Handoff._presence_claims(fixture.people, layout.cells, {}, goals.claimed)
	if not _check(completed.ok and completed.claimed == layout.claimed, "all-person final validation retains the single empty goal claim"): return false
	for cell: Vector2i in goals.claimed: completed.claimed.erase(cell)
	var all_real: bool = completed.claimed.size() == fixture.people.size()
	for identity: int in completed.claimed.values(): all_real = all_real and identity >= 1
	if not _check(all_real and not completed.claimed.has(goal), "no temporary sentinel remains in the claims passed to the original MOVE owner"): return false
	var snapshot: Dictionary = fixture.snapshot.duplicate(true)
	var own: Dictionary = {}
	for row: Dictionary in snapshot.units:
		var identity: int = int(row.person_id)
		own[identity] = true
		var cell: Vector2i = layout.cells[identity]
		row.cell = [cell.x, cell.y]
		row.slot = row.cell.duplicate()
		row.crowd_position = [cell.x + 0.5, cell.y + 0.5]
	var geometry: Dictionary = TerrainArmy.prepare_handoff_geometry(snapshot, fixture.map, {})
	if not _check(geometry.ok, "the original strict command geometry still accepts the complete goal-space layout", geometry.get("code", "OK")): return false
	var blockers: Dictionary = {}
	for cell: Vector2i in completed.claimed:
		if not own.has(int(completed.claimed[cell])): blockers[cell] = true
	var resolved: Dictionary = TerrainArmy._resolve_combat_goal_at(fixture.map, goal, func(cell: Vector2i) -> bool: return blockers.has(cell))
	if not _check(resolved.ok and resolved.cell == goal, "the unchanged original resolver now accepts the exact original MOVE goal"): return false
	var registry := SiteDeploymentReservationRegistry.new()
	var movement: Dictionary = TerrainArmy.prepare_handoff_move(geometry.snapshot, fixture.map, {}, blockers, registry)
	if not _check(movement.ok and movement.snapshot.goal == fixture.snapshot.goal and movement.runtime_move.requested_goal == goal,
		"the original route destination egress and MOVE owner accept the unchanged request", movement.get("message", "")): return false
	return _check(_sources(fixture) == sources and dense == dense_before and is_same(dense.units[24].item_state, holder)
		and is_same(dense.units[24].cargo, cargo) and registry.slot_owners.is_empty(),
		"goal-space preparation leaves original bodies items cargo command RNG and live leases untouched")
func _zero_platform_queue() -> bool:
	var map: TerrainData = Helper.build_flat_map(80, 65)
	var army: TerrainArmy = Helper.create_test_army(map, 11, 0, 100, Vector2i(4, 4))
	owned.append(army)
	var coordinator := SiteCombatMovementCoordinator.new()
	coordinator.register_formation(army)
	for index in range(army.combat_units.size()):
		var row: Dictionary = army.combat_units[index]
		row.cargo = {"grain": index + 1}
		row.item_state = {}
		var seeded: Dictionary = SiteRuntime.seed_person_equipment(map, row.item_state, army.combat_identity(index), row.get("appearance", {}))
		assert(seeded.ok and not row.item_state.item_ids.is_empty(), "queue fixture keeps real original body item holders")
	army.combat_hot_set(3, &"hp", 61.125)
	army.combat_hot_set(3, &"stun", 7.75)
	var holder: Dictionary = army.combat_units[3].item_state
	var cargo: Dictionary = army.combat_units[3].cargo
	var roster: Array[int] = army._get_active_member_ids()
	var goal := Vector2i(50, 20)
	var profile: FormationMovementProfile = FormationMovementProfile.from_members(roster, army)
	var path: Array[Vector2i] = FormationTransitPlanner.build_macro_path(map, army._get_combat_route_anchor_cell(), goal, profile)
	var footprint: Dictionary = FormationDestinationPlanner.build_platform_footprint(map, goal, path,
		FormationDestinationPlanner.preset_footprint_radius("auto", roster.size()), profile)
	var registry: SiteDeploymentReservationRegistry = coordinator.deployment_registry
	var foreign: Dictionary = registry.try_replace_reservations(9901, -1, 1, footprint.platform_cells)
	if not _check(foreign.ok and not path.is_empty() and roster.size() == 100,
		"the ordinary queue-only fixture reserves the real destination footprint with original foreign leases"): return false
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, goal,
		-1, Vector2i.RIGHT, "auto")
	if not _check(order.ok, "the actual ordinary MOVE owner accepts a destination whose platform is fully leased", order.get("message", "")): return false
	var plan: CombatDeploymentPlan = army.get_active_deployment_plan()
	if not _check(plan != null and plan.platform_slots.is_empty() and plan.queue_member_ids.size() == 100
		and plan.member_slot_map.size() == 100 and plan.following_member_ids.is_empty()
		and plan.shape_version == 3 and plan.final_width == 1 and plan.final_depth == 1,
		"the actual planner marks zero platform and one hundred queued members with the existing v3 contract"): return false
	var snapshot: Dictionary = army.capture_combat_state()
	var site_before: Dictionary = map.site.duplicate(true)
	var leases_before: Dictionary = registry.capture_handoff_state()
	if not _check(SiteStore._valid_combat_movement_snapshot(map, snapshot, {}),
		"the complete original Store movement validator accepts the actual serialized queue-only plan"): return false
	var prepared: Dictionary = TerrainArmy.preflight_handoff_restore(snapshot, map, registry, army.get_active_move_plan())
	if not _check(prepared.ok, "the actual restore preflight accepts queue-only runtime and serialized plans together", prepared.get("message", "")): return false
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(snapshot, "", true, true))
	var restored: CombatDeploymentPlan = TerrainArmy._deserialize_deployment_plan(parsed.combat_deployment_plan)
	if not _check(SiteStore._valid_combat_movement_snapshot(map, parsed, {})
		and TerrainArmy.preflight_handoff_restore(parsed, map, registry).ok and restored.shape_version == 3
		and restored.member_slot_map == plan.member_slot_map and restored.member_role_map == plan.member_role_map
		and restored.queue_member_ids == plan.queue_member_ids and restored.following_member_ids.is_empty(),
		"ordinary JSON readback preserves every queue identity role slot and the accepted v3 schema"): return false
	var complete: CombatDeploymentPlan = FormationDestinationPlanner.plan_deployment(12, 1, map, goal, path, roster,
		null, [], army.get_active_members_occupancy(), Vector2i.RIGHT, profile)
	if not _check(complete != null and complete.platform_slots.size() == 100 and complete.following_member_ids.is_empty()
		and complete.shape_version == 2, "a fully available original platform retains its unchanged v2 contract"): return false
	var blocked: Dictionary = {}
	for y in range(map.size.y):
		for x in range(map.size.x): blocked[Vector2i(x, y)] = true
	var following: CombatDeploymentPlan = FormationDestinationPlanner.plan_deployment(13, 1, map, goal, path, roster,
		null, [], army.get_active_members_occupancy(), Vector2i.RIGHT, profile, "auto", blocked)
	if not _check(following != null and following.platform_slots.is_empty() and following.member_slot_map.is_empty()
		and following.following_member_ids.size() == 100 and following.shape_version == 3
		and following.final_width == 1 and following.final_depth == 1,
		"the established zero-slot all-following case still retains every member under v3"): return false
	var unchanged: bool = army.capture_combat_state() == snapshot and map.site == site_before
	unchanged = unchanged and registry.capture_handoff_state() == leases_before
	unchanged = unchanged and is_same(army.combat_units[3].item_state, holder) and is_same(army.combat_units[3].cargo, cargo)
	coordinator.unregister_formation(army)
	return _check(unchanged, "schema roundtrip and pure planner checks preserve original body cold references commands RNG and existing leases")
func _run() -> void:
	var ok: bool = _cases()
	for node: Node in owned:
		if is_instance_valid(node): node.free()
	print("CROWD_B_GUARD_GROUP_LAYOUT_", "PASS" if ok else "FAIL", " checks=", checks)
	quit(0 if ok else 2)
