extends SceneTree
## Exercises the production B candidate planner without people/items/asset stubs.
const Handoff = preload("res://scripts/terrain_lab/crowd_clear_handoff.gd")
const Actions = preload("res://scripts/terrain_lab/site_person_actions.gd")
var checks: int = 0

class GuardLab extends Node:
	var terrain: TerrainData

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, label: String) -> bool:
	checks += 1
	if value: return true
	printerr("GATE FAIL: handoff layout ", label)
	quit(2)
	return false

func _map(size: Vector2i) -> TerrainData:
	var data: TerrainData = TerrainData.new()
	data.allocate(size)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	return data

func _person(identity: int, position: Vector2, standing: bool = true) -> Dictionary:
	return {"person_id": identity, "position": position, "standing": standing}

func _run() -> void:
	var data: TerrainData = _map(Vector2i(8, 8))
	var people: Array = [_person(1, Vector2(1.625, 1.75)), _person(2, Vector2(1.75, 1.125)),
		_person(3, Vector2(2.5, 1.5)), _person(4, Vector2(1.5, 1.5), false)]
	var before: Array = people.duplicate(true)
	var result: Dictionary = Handoff.plan_legal_positions(data, people, {})
	if not _check(result.ok and result.cells[1] != result.cells[2] and result.cells[3] == Vector2i(2, 1), "off-center/shared cells preserve all people and the legal unshared cell"): return
	if not _check(result.cells[4] == Vector2i(1, 1) and result.claimed.size() == 3, "KO/dead body cell does not invent a standing claim"): return
	if not _check(people == before and result.movements.size() == 4 and result.moved_count == 2, "planning only reads sources and reports actual displacement"): return
	var reversed: Array = people.duplicate()
	reversed.reverse()
	var repeated: Dictionary = Handoff.plan_legal_positions(data, reversed, {})
	if not _check(repeated == result, "stable identity order does not depend on caller array order"): return
	var fixed: Dictionary = {Vector2i(1, 1): true, Vector2i(1, 0): true}
	var fixed_before: Dictionary = fixed.duplicate()
	var avoided: Dictionary = Handoff.plan_legal_positions(data, people, fixed)
	if not _check(avoided.ok and not fixed.has(avoided.cells[1]) and not fixed.has(avoided.cells[2]) and fixed == fixed_before, "foreign source/destination/vehicle/lease claims stay fixed"): return
	var split: TerrainData = _map(Vector2i(8, 1))
	split.flags[2] = 0
	var packed: Array = [_person(10, Vector2(0.5, 0.5)), _person(11, Vector2(0.5, 0.5)), _person(12, Vector2(0.5, 0.5))]
	var packed_before: Array = packed.duplicate(true)
	var disconnected: Dictionary = Handoff.plan_legal_positions(split, packed, {})
	if not _check(not disconnected.ok and disconnected.reason == "NO_LEGAL_LAYOUT" and packed == packed_before, "free cells across a wall cannot make an impossible component succeed"): return
	var cliff: TerrainData = _map(Vector2i(2, 1))
	cliff.height_levels[1] = 1
	var across: Dictionary = Handoff.plan_legal_positions(cliff, packed.slice(0, 2), {})
	if not _check(not across.ok and across.reason == "NO_LEGAL_LAYOUT", "a cliff without a reciprocal ramp is not a placement edge"): return
	cliff.ramp_edges[0] = 1 << 1
	cliff.ramp_edges[1] = 1 << 3
	var ramp: Dictionary = Handoff.plan_legal_positions(cliff, packed.slice(0, 2), {})
	if not _check(ramp.ok and ramp.cells[10] != ramp.cells[11], "the original legal ramp permits an adjacent candidate"): return
	var guard_lab: GuardLab = GuardLab.new()
	guard_lab.terrain = data
	var actions: RefCounted = Actions.new()
	actions.lab = guard_lab
	var captives: Array = [_person(20, Vector2(4.5, 4.5))]
	var guards: Dictionary = {}
	for identity in range(21, 25):
		captives.append(_person(identity, Vector2(4.5, 4.5)))
		guards[identity] = 20
	var watched: Dictionary = Handoff.plan_legal_positions(data, captives, {}, guards, {}, actions._within_guard_range)
	if not _check(watched.ok and watched.claimed.size() == 5, "one guard and four captives get distinct candidate cells"): return
	for identity in range(21, 25):
		if not _check(actions._within_guard_range(watched.cells[20], watched.cells[identity]), "each effective guard pair uses the original range/path rule"): return
	var external: Dictionary = Handoff.plan_legal_positions(data, [_person(25, Vector2(4.5, 4.5))],
		{Vector2i(4, 4): true}, {25: 20}, {20: Vector2i(4, 4)}, actions._within_guard_range)
	if not _check(external.ok and actions._within_guard_range(external.cells[20], external.cells[25]), "a foreign guard stays fixed and effective"): return
	guard_lab.terrain = _map(Vector2i(6, 1))
	var corridor: Array = [_person(1, Vector2(0.5, 0.5)), _person(2, Vector2(5.5, 0.5))]
	for identity in range(3, 7): corridor.append(_person(identity, Vector2(0.5, 0.5)))
	var released: Dictionary = Handoff.plan_legal_positions(guard_lab.terrain, corridor, {}, {2: 1}, {}, actions._within_guard_range)
	if not _check(released.ok and released.claimed.size() == 6 and released.cells[2] != Vector2i(5, 0), "a guarded person releases its vacated reserved home for later people"): return
	guard_lab.free()
	var dense: Array = []
	for identity in range(100, 228): dense.append(_person(identity, Vector2(0.5, 0.5)))
	var full: Dictionary = Handoff.plan_legal_positions(data, dense, {})
	if not _check(not full.ok and full.reason == "NO_LEGAL_LAYOUT", "exhausting every cell proves the component has no legal layout"): return
	var larger: TerrainData = _map(Vector2i(16, 16))
	for identity in range(228, 612): dense.append(_person(identity, Vector2(0.5, 0.5)))
	var limited: Dictionary = Handoff.plan_legal_positions(larger, dense, {})
	if not _check(not limited.ok and limited.reason == "SEARCH_LIMIT", "bounded search exhaustion is distinct from a proven full component"): return
	print("CROWD_B_LAYOUT_PASS checks=", checks)
	quit(0)
