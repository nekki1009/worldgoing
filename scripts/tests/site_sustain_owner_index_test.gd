extends SceneTree
## Transaction-local feeding index: the same full owner validation, once.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Adapter = preload("res://scripts/tests/crowd_c2_people_adapter_test.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
var checks := 0
var failed := false

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed = true
	print("SUSTAIN_OWNER_INDEX ", "OK " if ok else "FAIL ", checks, ": ", label)

func _states(members: Dictionary) -> Array:
	var states: Array = [Sustain.create(60.0), Sustain.create(60.0)]
	assert(Sustain.add_members(states[0], members, [1, 2]).ok)
	assert(Sustain.add_members(states[1], members, [3]).ok)
	return states

func _legacy_valid(states: Array, members: Dictionary) -> bool:
	# The pre-optimization owner loop, retaining its independent second ID pass.
	var seen := {}
	for state: Variant in states:
		if not state is Dictionary or not Sustain.validate(state, members): return false
		for identity: int in Sustain._ids(state):
			if seen.has(identity): return false
			seen[identity] = true
	return true

func _validator_cases() -> void:
	var keys: Array[String] = ["team:7", "person:3"]
	var kinds := ["valid", "local_duplicate", "cohort_duplicate", "global_duplicate", "negative_hp", "nan_hp", "infinite_hp", "string_hp", "missing_person", "invalid_person", "version", "at", "open_rations", "morale", "regroup", "routed", "commander", "event", "cohorts", "cohort", "ids", "empty_ids", "fractional_id", "zero_id", "unknown_id", "hunger", "coverage", "past_meal", "future_meal", "bonus_paid", "bonus_pending"]
	for kind: String in kinds:
		var members := {1: {"hp": 17.0}, 2: {"hp": 0.0}, 3: {"hp": 20.0}}
		var states := _states(members)
		var state: Dictionary = states[0]
		var cohort: Dictionary = state.cohorts[0]
		match kind:
			"local_duplicate": cohort.ids.append(1)
			"cohort_duplicate": state.cohorts.append(cohort.duplicate(true))
			"global_duplicate": states[1].cohorts[0].ids.append(2)
			"negative_hp": members[3].hp = -1.0
			"nan_hp": members[3].hp = NAN
			"infinite_hp": members[3].hp = INF
			"string_hp": members[3].hp = "20"
			"missing_person": members.erase(3)
			"invalid_person": members[3] = 20
			"version": state.version = 2
			"at": state.at = -1.0
			"open_rations": state.open_rations = INF
			"morale": state.morale = 101.0
			"regroup": state.regroup_seconds = 1801.0
			"routed": state.routed = 1
			"commander": state.commander_present = 1
			"event": state.last_combat_event = 0.5
			"cohorts": state.cohorts = {}
			"cohort": state.cohorts[0] = 1
			"ids": cohort.ids = {}
			"empty_ids": cohort.ids = []
			"fractional_id": cohort.ids = [1.5]
			"zero_id": cohort.ids = [0]
			"unknown_id": cohort.ids = [99]
			"hunger": cohort.hunger = -1.0
			"coverage": cohort.coverage = 1.01
			"past_meal": cohort.meal_until = 59.0
			"future_meal": cohort.meal_until = 21601.0
			"bonus_paid": cohort.bonus_paid = 0
			"bonus_pending": cohort.bonus_pending = 1
		var before := var_to_bytes([states, members])
		var result := Sustain.validate_owner_index(states, members, keys)
		var old_valid := _legacy_valid(states, members)
		_check(bool(result.ok) == old_valid and old_valid == (kind == "valid"), kind + " retains original full validation")
		_check(var_to_bytes([states, members]) == before, kind + " leaves every original record unchanged")
		if kind == "valid":
			_check(result.owners == {1: "team:7", 2: "team:7", 3: "person:3"}, "index includes dead members and both owner kinds")
		else:
			_check(not result.has("owners"), kind + " exposes no partial index")
	_check(Sustain.validate_owner_index([], {}, []).ok, "empty Site remains valid")
	_check(not Sustain.validate_owner_index([Sustain.create()], {}, keys).ok, "mismatched owner labels cannot publish an index")

func _native_cases() -> void:
	var kernel := TerrainArmy._get_idle_kernel()
	if kernel == null:
		print("SUSTAIN_OWNER_INDEX SKIP native-only cases: optional ArmyIdleKernel is unavailable; original GDScript cases still run")
		return
	_check(kernel.has_method("sustain_owner_index"), "native read-only owner-index entry is installed")
	if not kernel.has_method("sustain_owner_index"): return
	var members := {1: {"hp": 17.0}, 2: {"hp": 0.0}, 3: {"hp": 20.0}}
	var states := _states(members)
	var keys: Array[String] = ["team:7", "person:3"]
	var ids: Array = states[0].cohorts[0].ids
	var before := var_to_bytes([states, members, keys])
	var packet: Array = kernel.sustain_owner_index(states, members, keys)
	_check(ids.get_typed_builtin() == TYPE_INT and keys.get_typed_builtin() == TYPE_STRING, "normal inputs retain typed Array[int] IDs and Array[String] keys")
	_check(packet.size() == 1 and packet[0] is Dictionary and packet[0] == {1: "team:7", 2: "team:7", 3: "person:3"} and packet[0].keys() == [1, 2, 3], "native admits normal typed arrays with complete ordered owners including dead members")
	_check(_legacy_valid(states, members) and Sustain.validate_owner_index(states, members, keys).owners == packet[0], "native result agrees with the untouched original validation loop")
	_check(var_to_bytes([states, members, keys]) == before and is_same(ids, states[0].cohorts[0].ids), "native and public entries leave original records and ID array identity unchanged")
	var typed_members: Dictionary[int, Dictionary] = {}
	for id: int in members: typed_members[id] = members[id]
	before = var_to_bytes([states, typed_members, keys])
	packet = kernel.sustain_owner_index(states, typed_members, keys)
	var result := Sustain.validate_owner_index(states, typed_members, keys)
	_check(packet.is_empty(), "typed Dictionary requests whole-call GDScript fallback")
	_check(result.ok and _legacy_valid(states, typed_members) and result.owners == {1: "team:7", 2: "team:7", 3: "person:3"}, "typed Dictionary fallback retains original validation and owners")
	_check(var_to_bytes([states, typed_members, keys]) == before, "typed Dictionary fallback never changes inputs")
	members[3].hp = -1.0
	before = var_to_bytes([states, members, keys])
	packet = kernel.sustain_owner_index(states, members, keys)
	result = Sustain.validate_owner_index(states, members, keys)
	_check(packet == [false] and result == Sustain._fail("Invalid or duplicate original feeding ownership") and not _legacy_valid(states, members), "later invalid HP exposes only rejection, never partial owners")
	_check(var_to_bytes([states, members, keys]) == before, "failed native and public validation leave inputs unchanged")
	members[3].hp = 20.0
	for state: Dictionary in states:
		for cohort: Dictionary in state.cohorts:
			cohort.ids.make_read_only()
			cohort.make_read_only()
		state.cohorts.make_read_only()
		state.make_read_only()
	for member: Dictionary in members.values(): member.make_read_only()
	states.make_read_only()
	members.make_read_only()
	keys.make_read_only()
	before = var_to_bytes([states, members, keys])
	packet = kernel.sustain_owner_index(states, members, keys)
	result = Sustain.validate_owner_index(states, members, keys)
	_check(packet.size() == 1 and packet[0] is Dictionary and result.ok and _legacy_valid(states, members) and result.owners == packet[0], "read-only containers are admitted for full read-only validation")
	_check(var_to_bytes([states, members, keys]) == before and ids.is_read_only() and states.is_read_only() and members.is_read_only() and keys.is_read_only() and is_same(ids, states[0].cohorts[0].ids), "read-only metadata, content and ID identity remain intact")

func _mixed_cases() -> void:
	for kind: String in ["valid", "local_duplicate", "global_duplicate", "ordinary_hp", "crowd_hp", "record"]:
		var fixture := Adapter.Fixture.new()
		var supply = fixture.captivity
		var ordinary := TerrainArmy.new()
		ordinary.team_id = 3
		ordinary.combat_enabled = true
		var row := {"person_id": 3, "hp": 17.0, "ko": 0.0, "captive": false, "cargo": {"grain": 2}}
		ordinary.combat_units.append(row)
		fixture.combat_armies.append(ordinary)
		var state := Sustain.create()
		assert(Sustain.add_members(state, supply._all_members(), [3]).ok)
		fixture.terrain.site.team_supply["3"] = {"sustain": state, "inventory": {}, "delivery": {}, "revision": 0, "life_checkpoint": {"3": 0}}
		if kind == "local_duplicate": state.cohorts[0].ids.append(3)
		if kind == "global_duplicate": state.cohorts[0].ids.append(2)
		if kind == "ordinary_hp": row.hp = -1.0
		if kind == "crowd_hp": fixture.crowd_site.states[1].hp = NAN
		if kind == "record": state.cohorts[0].coverage = 2.0
		var context := {"site": fixture.terrain.site, "terrain": fixture.terrain, "native": fixture.crowd_site.crowd,
			"step": fixture.crowd_site._steps, "at": Runtime.now(fixture.terrain) * 60.0}
		var before := var_to_bytes([fixture.terrain.site, row, fixture.crowd_site.states])
		var result: Dictionary = supply.event_change_guard(2, 1, true, context)
		_check(bool(result.ok) == (kind == "valid"), "mixed ordinary/crowd transaction " + kind)
		_check(var_to_bytes([fixture.terrain.site, row, fixture.crowd_site.states]) == before, "mixed preflight keeps original sources unchanged: " + kind)
		if kind == "valid":
			var prepared: Dictionary = supply._prepared[2].states
			_check(is_same(prepared["team:3"].state, state) and not prepared["team:3"].copied, "unrelated ordinary owner remains borrowed and unchanged")
			fixture.terrain.site.captivity["2"] = {"captor_id": 1, "guard_id": 1}
			supply.commit_change(2, 1, true)
			_check(2 in Sustain._ids(fixture.terrain.site.team_supply["1"].sustain), "capture commits to original crowd feeding owner")
			var escaped: Dictionary = supply.event_change_guard(2, 1, false, context)
			_check(escaped.ok, "next event rebuilds the index from the just-committed cohorts")
			if escaped.ok:
				fixture.terrain.site.captivity.erase("2")
				supply.commit_change(2, 1, false)
				_check(2 in Sustain._ids(fixture.terrain.site.team_supply["2"].sustain) and not 2 in Sustain._ids(fixture.terrain.site.team_supply["1"].sustain), "escape restores original owner without a stale index")
		else:
			_check(result.code == "INVALID_SUSTAIN" and supply._prepared.is_empty(), "invalid mixed transaction leaves no prepared commit: " + kind)
		fixture.combat_armies.clear()
		ordinary.free()
		fixture.close()

func _initialize() -> void:
	_validator_cases()
	_native_cases()
	_mixed_cases()
	print("SUSTAIN_OWNER_INDEX_RESULT checks=", checks, " failed=", failed)
	quit(1 if failed else 0)
