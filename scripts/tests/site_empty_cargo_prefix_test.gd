extends SceneTree
const Snapshot = preload("res://scripts/terrain_lab/site_exchange_snapshot.gd")
const Frozen := "res://scripts/tests/fixtures/site_exchange_snapshot_phase22.gd.txt"

class CustomArmy extends TerrainArmy:
	var calls: Array[int] = []
	func ranged_profile(index: int) -> Dictionary:
		calls.append(index)
		return super.ranged_profile(index)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var kernel := TerrainArmy._get_idle_kernel()
	assert(kernel != null and kernel.has_method("empty_cargo_prefix"))
	var empty := {}
	empty.make_read_only()
	var typed: Dictionary[StringName, Variant] = {&"cargo": empty}
	var rows: Array = [{}, {"cargo": empty}, typed, {"cargo": {"arrow": 1}}]
	var indices := PackedInt32Array([0, 1, 2, 3])
	var slots := PackedInt32Array([0, 0, 0, 0])
	var untouched := var_to_bytes([rows, indices, slots])
	assert(kernel.empty_cargo_prefix(rows, indices, slots, 0) == 3)
	assert(kernel.empty_cargo_prefix(rows, indices, PackedInt32Array([0, 0, 1, 1]), 0) == 2)
	assert(kernel.empty_cargo_prefix(rows, PackedInt32Array([2, 0, 2, 3]), slots, 1) == 3)
	assert(kernel.empty_cargo_prefix(rows, indices, slots, -1) == -1)
	assert(kernel.empty_cargo_prefix(rows, indices, slots, 4) == 4)
	assert(kernel.empty_cargo_prefix(rows, indices, slots, 9) == 9)
	assert(kernel.empty_cargo_prefix(rows, indices, PackedInt32Array(), 0) == 0)
	assert(kernel.empty_cargo_prefix([], PackedInt32Array(), PackedInt32Array(), 0) == 0)
	assert(kernel.empty_cargo_prefix(rows, PackedInt32Array([0, -1, 2, 3]), slots, 0) == 1)
	assert(kernel.empty_cargo_prefix(rows, PackedInt32Array([0, 99, 2, 3]), slots, 0) == 1)
	assert(var_to_bytes([rows, indices, slots]) == untouched)
	for cargo: Variant in [null, false, 0, "", [], {"arrow": 0}, {"stone": 1}]:
		var unusual: Array = [{"cargo": {}}, {"cargo": cargo}, {"cargo": {}}]
		var before := var_to_bytes(unusual)
		assert(kernel.empty_cargo_prefix(unusual, PackedInt32Array([0, 1, 2]), PackedInt32Array([0, 0, 0]), 0) == 1)
		assert(before == var_to_bytes(unusual))
	assert(kernel.empty_cargo_prefix([{}, 1], PackedInt32Array([0, 1]), PackedInt32Array([0, 0]), 0) == 1)
	var many := PackedInt32Array()
	many.resize(10001)
	assert(kernel.empty_cargo_prefix(rows, many, many, 0) == 0)
	print("EMPTY_CARGO_BOUNDARY_PASS missing/StringName/readonly/typed/alias/order/owner split/invalid prefix/bounds/budget; inputs unchanged")
	var old := GDScript.new()
	old.source_code = FileAccess.get_file_as_string(Frozen)
	assert(old.reload() == OK)
	for custom in [false, true]:
		for native_queries in [false, true]:
			for mode in range(7):
				var before := _case(old, custom, native_queries, mode)
				var after := _case(Snapshot, custom, native_queries, mode)
				assert(var_to_bytes(before) == var_to_bytes(after), "Ranged query changed callback/order/state: " + str([custom, native_queries, mode]))
	print("EMPTY_CARGO_OWNER_PASS 28 canonical/custom and enabled/disabled cases; post-capture ammo, current/future/other-owner callback mutation, original targets/cells/order")
	quit(0)

func _case(kind: GDScript, custom: bool, native_queries: bool, mode: int) -> Array:
	var teams: Array[TerrainArmy] = []
	var callbacks: Array = []
	for side in range(2):
		var team: TerrainArmy = CustomArmy.new() if custom else TerrainArmy.new()
		team.native_queries_enabled = native_queries
		for index in range(5):
			team.combat_units.append({"person_id": 4294967296 + side * 10 + index, "cargo": {}})
		teams.append(team)
	var query: RefCounted = kind.new()
	for side in range(2):
		query.owners.append(teams[side])
		for index in range(5):
			query._append(side, index, teams[side].combat_identity(index), Vector2i(index, side), side)
	# All writes occur after capture. The same snapshot must read fresh cargo.
	assert(query.ranged_people().is_empty())
	if mode == 1: teams[1].combat_units[4].cargo = {"arrow": 1}
	if mode in [2, 3, 4, 5]: teams[0].combat_units[1].cargo = {"stone": 1}
	if mode == 5: teams[0].combat_units[1].cargo = {"arrow": 1}
	if mode == 6:
		teams[0].combat_units[0].cargo = {"bolt": 0}
		teams[1].combat_units[3].cargo = {"arrow": 1}
	for side in range(2):
		teams[side].equipment_appearance_query = func(identity: int, which: int) -> Dictionary:
			callbacks.append([which, identity])
			if which == 0 and identity == 4294967297:
				if mode == 2: teams[0].combat_units[4].cargo = {"arrow": 1}
				if mode == 3: teams[1].combat_units[4].cargo = {"arrow": 1}
				if mode == 4: teams[0].combat_units[1].cargo["arrow"] = 1
				if mode == 5: teams[0].combat_units[1].cargo.clear()
			return {"parts": {"weapon": "bow_01"}}
		teams[side].equipment_appearance_query = teams[side].equipment_appearance_query.bind(side)
	var actual: Array[Dictionary] = query.ranged_people()
	assert(actual.size() == (0 if mode in [0, 5] else 10))
	var people: Array = []
	for ordinal in range(actual.size()):
		var person: Dictionary = actual[ordinal]
		assert(person.owner == teams[int(person.faction)] and is_same(person, query.person(ordinal)))
		people.append([person.unit, person.id, person.cell, person.faction, person.ready, person.receive])
	var state: Array = [people, callbacks, teams[0].combat_units.duplicate(true), teams[1].combat_units.duplicate(true)]
	if custom: state.append([teams[0].calls.duplicate(), teams[1].calls.duplicate()])
	for team: TerrainArmy in teams:
		team.equipment_appearance_query = Callable()
	query = null
	for team: TerrainArmy in teams: team.free()
	return state
