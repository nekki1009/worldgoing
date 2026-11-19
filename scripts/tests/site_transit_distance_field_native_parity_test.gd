extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")

class CustomTerrain extends TerrainData:
	pass

class CustomProfile extends FormationMovementProfile:
	pass

var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func _plan(goal: Vector2i) -> CombatMovePlan:
	var plan := CombatMovePlan.new()
	plan.macro_path.append(goal)
	return plan

func _terrain() -> TerrainData:
	var terrain := Helper.build_flat_map(100, 100)
	for y in range(100):
		if y != 40 and y != 41:
			terrain.static_blocked[terrain.index(Vector2i(50, y))] = 1
	for x in range(10, 31):
		for y in range(10, 31):
			terrain.height_levels[terrain.index(Vector2i(x, y))] = 1
	terrain.ramp_edges[terrain.index(Vector2i(20, 9))] |= 1 << 2
	terrain.ramp_edges[terrain.index(Vector2i(20, 10))] |= 1 << 0
	for y in range(10, 61):
		for x in range(60, 64):
			terrain.flags[terrain.index(Vector2i(x, y))] = 0
	for y in range(45, 56):
		terrain.static_blocked[terrain.index(Vector2i(25, y))] = 1
	return terrain

func _compare(terrain: TerrainData, profile: Object, goal: Vector2i, expected_native: bool = true) -> bool:
	var reference := _plan(goal)
	var candidate := _plan(goal)
	Transit.native_transit_enabled = false
	var started := Time.get_ticks_usec()
	var expected := Transit.get_transit_distance_field(reference, terrain, profile)
	var gd_usec := Time.get_ticks_usec() - started
	Transit.native_transit_enabled = true
	var calls_before: int = Transit.native_distance_field_calls
	started = Time.get_ticks_usec()
	var actual := Transit.get_transit_distance_field(candidate, terrain, profile)
	var native_usec := Time.get_ticks_usec() - started
	if not _require(Transit.native_distance_field_calls - calls_before == (1 if expected_native else 0), "Wrong native hit count at %s" % goal): return false
	if not _require(expected.size() == actual.size(), "Field size differs at %s" % goal): return false
	for y in range(terrain.size.y):
		for x in range(terrain.size.x):
			var cell := Vector2i(x, y)
			if not _require(expected.has(cell) == actual.has(cell), "Reachability differs at %s from %s" % [cell, goal]): return false
			if expected.has(cell) and not _require(int(expected[cell]) == int(actual[cell]), "Distance differs at %s from %s" % [cell, goal]): return false
	if not _require(expected == actual and expected.keys() == actual.keys(), "Field or BFS insertion order differs at %s" % goal): return false
	if not _require(reference.get_meta("_transit_distance_key") == candidate.get_meta("_transit_distance_key"), "Cache key differs at %s" % goal): return false
	if not _require(candidate.get_meta("_transit_distance_field") == actual, "Candidate cache field differs at %s" % goal): return false
	var warm := Transit.get_transit_distance_field(candidate, terrain, profile)
	if not _require(warm == actual and Transit.native_distance_field_calls == calls_before + (1 if expected_native else 0), "Warm cache repeated search at %s" % goal): return false
	_checks += 1
	print("TRANSIT_FIELD_CASE goal=%s cells=%d gd_usec=%d caller_usec=%d native=%s" % [goal, actual.size(), gd_usec, native_usec, expected_native])
	return true

func _run() -> void:
	if not _require(ClassDB.class_exists(&"ArmyIdleKernel"), "ArmyIdleKernel unavailable"): return
	var kernel: RefCounted = ClassDB.instantiate(&"ArmyIdleKernel")
	if not _require(kernel.has_method("transit_distance_field"), "Native transit_distance_field unavailable"): return
	var terrain := _terrain()
	var normal := FormationMovementProfile.new()
	var no_ramp := FormationMovementProfile.new(TerrainData.Flag.WALKABLE, 1, false)
	var no_climb := FormationMovementProfile.new(TerrainData.Flag.WALKABLE, 0, true)
	for profile in [null, normal, no_ramp, no_climb]:
		for goal in [Vector2i(80, 50), Vector2i(15, 25), Vector2i(50, 5), Vector2i(100, 1)]:
			if not _compare(terrain, profile, goal): return
	var plan := _plan(Vector2i(80, 50))
	Transit.get_transit_distance_field(plan, terrain, normal)
	for change in range(5):
		match change:
			0: plan.path_epoch += 1
			1: plan.terrain_revision += 1
			2: terrain.navigation_revision += 1
			3:
				normal.can_use_ramp = false
				normal.recompute_hash()
			4: plan.macro_path[-1] = Vector2i(15, 25)
		var before: int = Transit.native_distance_field_calls
		Transit.get_transit_distance_field(plan, terrain, normal)
		if not _require(Transit.native_distance_field_calls == before + 1, "Cold cache invalidation missed change %d" % change): return
	var custom_terrain := CustomTerrain.new()
	custom_terrain.allocate(terrain.size)
	custom_terrain.flags = terrain.flags.duplicate()
	custom_terrain.height_levels = terrain.height_levels.duplicate()
	custom_terrain.ramp_edges = terrain.ramp_edges.duplicate()
	custom_terrain.static_blocked = terrain.static_blocked.duplicate()
	if not _compare(custom_terrain, normal, Vector2i(80, 50), false): return
	if not _compare(terrain, CustomProfile.new(), Vector2i(15, 25), false): return
	Transit.native_transit_enabled = true
	print("TRANSIT DISTANCE FIELD PARITY PASS cases=%d native_calls=%d" % [_checks, Transit.native_distance_field_calls])
	quit(0)
