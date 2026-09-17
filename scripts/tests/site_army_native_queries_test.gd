extends SceneTree
const Snapshot = preload("res://scripts/terrain_lab/site_exchange_snapshot.gd")

class OverriddenArmy extends TerrainArmy:
	var calls := 0
	func combat_can_act(index: int) -> bool:
		calls += 1
		return index % 2 == 0
	func combat_identity(index: int) -> int:
		return 123456789 + index

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var passed := _check()
	if passed and "--benchmark" in OS.get_cmdline_user_args():
		_benchmark()
	quit(0 if passed else 1)

func _benchmark() -> void:
	# Original deployed person dictionaries; CPU query timing, not main-scene FPS.
	var army_script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	var guard := "selected.size() > MAX_ROSTER_SIZE"
	assert(army_script.source_code.count(guard) == 1)
	army_script.source_code = army_script.source_code.replace(guard, "selected.size() > 2500")
	assert(army_script.reload(true) == OK)
	var fixture: SceneTree = load("res://scripts/tests/site_army_scale_rules_test.gd").new()
	var lab: TerrainLab = fixture._fixture(false, 2500, true)
	var kernel := TerrainArmy._get_idle_kernel()
	var source := var_to_bytes([lab.combat_armies[0].combat_units, lab.combat_armies[1].combat_units])
	var samples: Array[float] = []
	var rows := 0
	for batch in range(7):
		var started := Time.get_ticks_usec()
		for repeat in range(400):
			for team: TerrainArmy in lab.combat_armies:
				var columns: Array = kernel.call("capture_columns", team.combat_units, team.cells)
				assert(columns.size() == 4 and columns[0].size() == 2500)
				rows += columns[0].size()
		if batch > 0: samples.append(float(Time.get_ticks_usec() - started) / 400000.0)
	assert(source == var_to_bytes([lab.combat_armies[0].combat_units, lab.combat_armies[1].combat_units]))
	print("ARMY_CAPTURE_BENCHMARK ", JSON.stringify({"ms_per_5000_capture": samples, "checked_rows": rows,
		"dll_sha256": FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll")}))
	fixture._dispose(lab)
	fixture.free()

func _row(identity: int) -> Dictionary:
	return {"person_id": identity, "hp": 100.0, "ko": 0.0, "pose": "idle", "captive": false, "departed": false, "member": false}

func _columns(snapshot: RefCounted) -> Array:
	return [snapshot.owner_slots, snapshot.units, snapshot.identities, snapshot.xs, snapshot.ys, snapshot.factions]

func _compare(team: TerrainArmy) -> bool:
	var actors: Array[TerrainTestCharacter] = []
	var teams: Array[TerrainArmy] = [team]
	var before := Snapshot.new()
	var after := Snapshot.new()
	var lab := TerrainLab.new()
	lab.combat_armies = teams
	var aliases := team.combat_units.duplicate()
	var original := var_to_bytes([team.combat_units, team.cells])
	team.native_queries_enabled = false
	before.capture(actors, teams)
	var old_people := lab._exchange_people(false)
	team.native_queries_enabled = true
	after.capture(actors, teams)
	var new_people := lab._exchange_people(false)
	assert(var_to_bytes(_columns(before)) == var_to_bytes(_columns(after)), "Original query columns changed")
	assert(before.owners == after.owners and var_to_bytes(old_people) == var_to_bytes(new_people), "Owner/order/key/type changed")
	for ordinal in range(before.units.size()):
		assert(before.person(ordinal) == after.person(ordinal))
		assert(new_people[ordinal].owner == team and new_people[ordinal].keys() == old_people[ordinal].keys())
		assert(new_people[ordinal].ready == null and new_people[ordinal].receive == null)
	assert(original == var_to_bytes([team.combat_units, team.cells]), "Original rows/cells mutated")
	for index in range(aliases.size()): assert(is_same(aliases[index], team.combat_units[index]))
	# Captures remain frozen but never become authoritative/cross-query state.
	var retained := var_to_bytes(_columns(after))
	if not team.cells.is_empty(): team.cells[0] += Vector2i.RIGHT
	var next := Snapshot.new()
	next.capture(actors, teams)
	assert(retained == var_to_bytes(_columns(after)), "A later query changed a retained PackedArray")
	if not team.cells.is_empty(): team.cells[0] -= Vector2i.RIGHT
	lab.free()
	return true

func _check() -> bool:
	var kernel := TerrainArmy._get_idle_kernel()
	assert(kernel != null and kernel.has_method("capture_columns") and kernel.has_method("capture_people"), "Actual new native methods required")
	var team := TerrainArmy.new()
	team.combat_enabled = true
	team.faction_id = 9223372036854775700
	var checked := 0
	for count in [0, 1, 200, 1023, 1024, 1025, 5000]:
		team.combat_units.clear()
		team.cells.clear()
		for i in range(count):
			var row := _row(9007199254740993 + i)
			match i % 11:
				0: row.hp = 0.0
				1: row.ko = 1.0
				2: row.pose = "get_up"
				3: row.captive = true
				4: row.departed = true
				5: row.pose = "guard"
				6: row.pose = "rescue"
				7: row.hp = 100; row.ko = 0
				8: row.make_read_only()
			team.combat_units.append(row)
			team.cells.append(Vector2i(i % 100 - 50, i % 77 - 38))
		assert(_compare(team))
		checked += count
	assert(team.native_query_rows > 0, "Do not silently accept GD fallback as native verification")
	# Missing and explicit null fields must reject silently without writes.
	for key in ["hp", "ko", "pose", "captive", "departed", "person_id"]:
		for missing in [true, false]:
			var row := _row(9007199254740999)
			if missing: row.erase(key)
			else: row[key] = null
			var untouched := var_to_bytes(row)
			assert(kernel.call("capture_columns", [row], [Vector2i.ZERO]).is_empty())
			assert(kernel.call("capture_people", [row], [Vector2i.ZERO], team, team.faction_id).is_empty())
			assert(untouched == var_to_bytes(row))
	var original_rows := team.combat_units.duplicate(true)
	for condition in range(10):
		team.combat_units[1] = _row(9223372036854775700)
		match condition:
			0: team.combat_units[1].pose = &"get_up"
			1: team.combat_units[1].hp = INF
			2: team.combat_units[1].ko = NAN
			3: team.combat_units[1].captive = 0
			4: team.combat_units[1].departed = 1
			5: team.combat_units[1].person_id = 100.0
			6: team.combat_units[1].hp = "100"
			7: team.combat_units[1].pose = 123
			8: team.combat_units[1].ko = -INF
			9: team.combat_units[1].captive = 0.0
		var source := var_to_bytes([team.combat_units, team.cells])
		assert(kernel.call("capture_columns", team.combat_units, team.cells).is_empty())
		assert(kernel.call("capture_people", team.combat_units, team.cells, team, team.faction_id).is_empty())
		assert(source == var_to_bytes([team.combat_units, team.cells]), "Rejected capture partially mutated input")
		assert(_compare(team))
	team.combat_units = original_rows
	# Validate every joined range rejects atomically, not only the first one.
	for bad_index in [0, 1023, 1024, 2500, 4999]:
		var saved: Dictionary = team.combat_units[bad_index]
		team.combat_units[bad_index] = _row(9007199254740999)
		team.combat_units[bad_index].person_id = null
		var unchanged := var_to_bytes([team.combat_units, team.cells])
		assert(kernel.call("capture_columns", team.combat_units, team.cells).is_empty())
		assert(kernel.call("capture_people", team.combat_units, team.cells, team, team.faction_id).is_empty())
		assert(unchanged == var_to_bytes([team.combat_units, team.cells]))
		team.combat_units[bad_index] = saved
	var keyed := TerrainArmy.new()
	keyed.combat_enabled = true
	var named: Dictionary[StringName, Variant] = {}
	for key: String in _row(9007199254740999): named[StringName(key)] = _row(9007199254740999)[key]
	named.make_read_only()
	keyed.combat_units.assign([named, named])
	keyed.cells.assign([Vector2i.ZERO, Vector2i.LEFT])
	assert(_compare(keyed) and keyed.native_query_rows > 0)
	keyed.free()
	# Aliased rows retain both original ordinals and identities, without writes.
	team.combat_units[1] = team.combat_units[9]
	assert(_compare(team))
	var same := team.combat_units[1]
	assert(is_same(same, team.combat_units[9]))
	assert(kernel.call("capture_columns", team.combat_units, []).is_empty())
	var too_many: Array[Dictionary] = []
	too_many.resize(10001)
	assert(kernel.call("capture_columns", too_many, []).is_empty())
	# Earlier disqualification must not inspect missing fields further right.
	var short_circuit := TerrainArmy.new()
	short_circuit.combat_enabled = true
	short_circuit.combat_units.assign([{"hp": 0.0}, {"hp": 100.0, "ko": 1.0},
		{"hp": 100.0, "ko": 0.0, "pose": "get_up"}, _row(9007199254740999)])
	short_circuit.cells.assign([Vector2i.ZERO, Vector2i.LEFT, Vector2i.UP, Vector2i(3, -4)])
	assert(_compare(short_circuit) and short_circuit.native_query_rows > 0)
	short_circuit.free()
	var overridden := OverriddenArmy.new()
	overridden.combat_enabled = true
	overridden.combat_units = team.combat_units
	overridden.cells = team.cells
	assert(_compare(overridden))
	assert(overridden.calls > 0 and overridden.native_query_rows == 0, "Subclass callbacks were bypassed")
	overridden.free()
	team.free()
	print("ARMY_NATIVE_QUERIES_PASS base_rows=", checked, " missing_or_null=12 coercion_fallbacks=10 short_circuit=3 exact columns/people/owners/order/types/64bit IDs; unchanged bytes/aliases/COW; subclass fallback")
	return true
