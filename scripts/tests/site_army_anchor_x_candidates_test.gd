extends SceneTree
## TEST ONLY native x-sort/bsearch broad phase, not a production index/grid.
## Original 200-row deployment and committed movement; no contact/HP/FPS claim.
## 17-second synchronous deadline / 18-second timer / canonical helper 20.

var started := 0
var deadline := 0
var checked_queries := 0
var edge_checks := 0

func _initialize() -> void:
	started = Time.get_ticks_usec()
	deadline = started + 17000000
	run.call_deferred()

func _old(grounds: Array[Vector2], bounds: Rect2, excluded: int) -> Array[int]:
	var result: Array[int] = []
	for index: int in grounds.size():
		if index != excluded and (index == 0 or bounds.has_point(grounds[index])):
			result.append(index)
	return result

func _build(grounds: Array[Vector2]) -> Dictionary:
	var entries: Array[Vector3] = []
	for index: int in grounds.size():
		var ground := grounds[index]
		if not ground.is_finite():
			return {"finite": false, "entries": entries}
		entries.append(Vector3(ground.x, ground.y, float(index)))
	entries.sort()
	return {"finite": true, "entries": entries}

func _indexed(grounds: Array[Vector2], sorted: Dictionary, bounds: Rect2, excluded: int) -> Array[int]:
	if not bool(sorted.finite) or not bounds.position.is_finite() or not bounds.end.is_finite():
		return _old(grounds, bounds, excluded)
	var result: Array[int] = []
	if not grounds.is_empty() and excluded != 0:
		result.append(0) # Original index zero bypasses even a distant anchor gate.
	var entries: Array[Vector3] = sorted.entries
	var first := entries.bsearch(Vector3(bounds.position.x, -INF, -INF), true)
	var last := entries.bsearch(Vector3(bounds.end.x, -INF, -INF), true)
	for offset: int in range(first, last):
		var index := int(entries[offset].z)
		if index != 0 and index != excluded and bounds.has_point(grounds[index]):
			result.append(index)
	result.sort() # Preserve the original row order before the real contact sorter.
	return result

func _grounds(lab: TerrainLab) -> Array:
	var result: Array = []
	for team: TerrainArmy in lab.combat_armies:
		var grounds: Array[Vector2] = []
		for index: int in team.combat_units.size():
			grounds.append(team.combat_ground(index))
		result.append(grounds)
	return result

func _queries(grounds: Array, category: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in 500:
		var source_team := index % 2
		var source_unit := index % 20 if category == 0 else index % 100
		var center: Vector2 = grounds[source_team][source_unit]
		var bounds := Rect2(center + Vector2(-8.0, -96.0), Vector2(16.0 + float(index % 4) * 16.0, 96.0)).grow(256.0)
		if category == 1:
			bounds.position += Vector2(float(index % 9 - 4) * 64.0, float(index % 7 - 3) * 64.0)
		elif category == 2:
			# Exact original anchors coincide alternately with the included start
			# or excluded end. These are numerical broad-phase probes, not attacks.
			bounds = Rect2(center - (Vector2(512.0, 512.0) if index % 2 else Vector2.ZERO), Vector2(512.0, 512.0))
		elif category == 3:
			bounds.position += Vector2(4096.0, -4096.0)
		result.append({"bounds": bounds, "source_team": source_team, "source_unit": source_unit})
	return result

func _measure(grounds: Array, queries: Array[Dictionary], indexed: bool) -> Dictionary:
	var results: Array = []
	var builds: Array = []
	var build_usec := 0
	var begin := Time.get_ticks_usec()
	for index: int in queries.size():
		if index % 64 == 0:
			assert(Time.get_ticks_usec() < deadline, "Bounded candidate filter test exceeded 17 seconds")
		if indexed and index % 10 == 0:
			# Include rebuilding both original team arrays every ten queries.
			# This is an explicit diagnostic batch size, not a measured game rate.
			var build_started := Time.get_ticks_usec()
			builds = [_build(grounds[0]), _build(grounds[1])]
			build_usec += Time.get_ticks_usec() - build_started
		var query: Dictionary = queries[index]
		var found: Array = []
		for team_index: int in grounds.size():
			var excluded: int = int(query.source_unit) if team_index == int(query.source_team) else -1
			found.append(_indexed(grounds[team_index], builds[team_index], query.bounds, excluded) if indexed else _old(grounds[team_index], query.bounds, excluded))
		results.append(found)
	return {"elapsed_usec": Time.get_ticks_usec() - begin, "build_usec": build_usec, "results": results}

func _compare(grounds: Array, queries: Array[Dictionary], state: String, category: String) -> Dictionary:
	var original := _measure(grounds, queries, false)
	var candidate := _measure(grounds, queries, true)
	assert(original.results == candidate.results, "Every original per-team candidate index and its order must match exactly")
	# Reverse measurement order once; no FPS inference from allocator/cache luck.
	var candidate_reverse := _measure(grounds, queries, true)
	var original_reverse := _measure(grounds, queries, false)
	assert(original.results == original_reverse.results and original.results == candidate_reverse.results)
	checked_queries += queries.size()
	return {"state": state, "category": category, "queries": queries.size(), "exact": true,
		"original_first_usec": original.elapsed_usec, "candidate_second_usec": candidate.elapsed_usec,
		"candidate_first_usec": candidate_reverse.elapsed_usec, "original_second_usec": original_reverse.elapsed_usec,
		"build_usec": [candidate.build_usec, candidate_reverse.build_usec], "queries_per_build": 10,
		"faster_both_orders": int(candidate.elapsed_usec) < int(original.elapsed_usec) and int(candidate_reverse.elapsed_usec) < int(original_reverse.elapsed_usec)}

func _numerical_edges() -> void:
	# Native Vector2/Vector3 float32 values, including duplicates and signed zero.
	# These are numerical oracle inputs, not deployed/teleported game people.
	var grounds: Array[Vector2] = [Vector2(9000.0, 9000.0), Vector2(0.0, 0.0), Vector2(-0.0, 0.0),
		Vector2(0.0, -0.0), Vector2(1.0, 1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0),
		Vector2(0.00000011920928955078125, 0.0), Vector2(16384.0, -16384.0)]
	var bounds: Array[Rect2] = [Rect2(0.0, 0.0, 1.0, 1.0), Rect2(-1.0, -1.0, 2.0, 2.0),
		Rect2(1.0, 1.0, 1.0, 1.0), Rect2(-0.0, -0.0, 0.0, 1.0), Rect2(-0.0, 0.0, 1.0, 0.0),
		Rect2(-16384.0, -16384.0, 32768.0, 32768.0), Rect2(INF, 0.0, 1.0, 1.0), Rect2(0.0, NAN, 1.0, 1.0)]
	for nonfinite: int in 4:
		var values := grounds.duplicate()
		if nonfinite > 0:
			values[nonfinite] = Vector2([INF, -INF, NAN][nonfinite - 1], 0.0)
		var sorted := _build(values)
		assert(bool(sorted.finite) == (nonfinite == 0))
		for rectangle: Rect2 in bounds:
			for excluded: int in [-1, 0, 1, 5]:
				assert(_old(values, rectangle, excluded) == _indexed(values, sorted, rectangle, excluded),
					"Native duplicate/zero/edge/nonfinite fallback candidate indices differ")
				edge_checks += 1

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	assert(DisplayServer.get_name() == "headless")
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
	var deployment := lab.start_melee_trial()
	assert(deployment.ok, "Use the original connected 200-row deployment without flattening terrain")
	var rows: Array = []
	var identities: Array[int] = []
	for team: TerrainArmy in lab.combat_armies:
		for index: int in team.combat_units.size():
			rows.append(team.combat_units[index])
			identities.append(team.combat_identity(index))
			team.combat_units[index].think = 1000.0
	assert(rows.size() == 200)
	var snapshots: Array = [_grounds(lab)]
	var moved := false
	for team: TerrainArmy in lab.combat_armies:
		for index: int in team.combat_units.size():
			for direction: Vector2i in TerrainData.DIRECTIONS:
				if not moved and team._reserve_combat_step(index, team.cells[index] + direction):
					var original := team.combat_ground(index)
					team.prepare_combat(float(team.move_duration[index]) * 0.25)
					assert(team.combat_ground(index) != original and team.moving_to[index] != TerrainArmy.INVALID_CELL)
					moved = true
	assert(moved, "Fixture needs one actual legal committed movement, never a synthetic moving anchor")
	snapshots.append(_grounds(lab))
	var measurements: Array[Dictionary] = []
	for state: int in snapshots.size():
		for category: int in 4:
			measurements.append(_compare(snapshots[state], _queries(snapshots[state], category),
				"stationary" if state == 0 else "original_committed_quarter_step", ["frontline", "roster_offsets", "exact_edges", "distant"][category]))
	_numerical_edges()
	assert(checked_queries == 4000 and edge_checks == 128 and Time.get_ticks_usec() < deadline)
	var cursor := 0
	for team: TerrainArmy in lab.combat_armies:
		for index: int in team.combat_units.size():
			assert(is_same(rows[cursor], team.combat_units[index]) and identities[cursor] == team.combat_identity(index))
			cursor += 1
	var output := "res://output/site_combat_performance_20260913/anchor_x_candidates/%d_%d" % [int(Time.get_unix_time_from_system()), started]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var report := {"status": "PASS", "checked_queries": checked_queries, "numeric_edge_checks": edge_checks,
		"actual_rows": rows.size(), "measurements": measurements, "elapsed_usec": Time.get_ticks_usec() - started,
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_anchor_x_candidates_test.gd"),
		"scope": "TEST ONLY native x-sort/bsearch candidate filtering. Exact original per-team indices/order, actual deployment/movement, explicit synthetic numerical edges. Timings include rebuild every 10 queries; no production change, geometry/narrow phase, GPU or FPS claim."}
	var file := FileAccess.open(output + "/measurements.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	lab.queue_free()
	await process_frame
	print("SITE_ARMY_ANCHOR_X_CANDIDATES_PASS ", JSON.stringify(report))
	quit(0)
