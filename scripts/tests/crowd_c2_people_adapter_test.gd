extends SceneTree
## L1 contract: native hot adapter + original cold references + custody preflight.
const Owner = preload("res://scripts/terrain_lab/crowd_person_owner.gd")
const Actions = preload("res://scripts/terrain_lab/site_person_actions.gd")
const Supply = preload("res://scripts/terrain_lab/site_captivity_supply.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

class NativeFixture extends RefCounted:
	var lab: Variant
	var crowd: Variant = self
	var _steps := 0
	var soldier_reads := 0
	var formation_reads := 0
	var dictionary_reads := 0
	var contact_revision_reads := 0
	var active := true
	var owners: Array = []
	var states: Dictionary = {}
	var solo_formations: Array[int] = []
	func contains_person(identity: int) -> bool:
		return identity in [1, 2]
	func person_owner(identity: int) -> Variant:
		return owners[identity - 1] if contains_person(identity) else null
	func person_owners() -> Array:
		return owners
	func get_soldier_state(index: int) -> PackedFloat64Array:
		soldier_reads += 1
		if not states.has(index): return PackedFloat64Array()
		var fields := ["hp", "stun", "grace", "ko", "getup", "stagger", "captive", "bandaged", "ammo", "tactics", "leadership", "coach", "escape_t", "role", "px", "py", "face", "exch_cd", "ranged_cd", "skill_cd", "knock_t", "act_t", "vx", "vy", "state", "vis_kind", "vis_age"]
		var values := PackedFloat64Array()
		for field: String in fields: values.append(float(states[index].get(field, 0.0)))
		return values
	func get_formation_state(_formation: int) -> PackedFloat64Array:
		formation_reads += 1
		var values := PackedFloat64Array()
		values.resize(28)
		values[2] = 14.0
		return values
	func soldier_state(index: int) -> Dictionary:
		dictionary_reads += 1
		return states.get(index, {}).duplicate()
	func contact_revision(index: int) -> int:
		contact_revision_reads += 1
		assert(states.has(index)) # The original native entry requires a valid soldier.
		return int(states[index].contact_revision)
	func set_soldier_fields(index: int, changes: Dictionary) -> bool:
		if not states.has(index):
			return false
		states[index].merge(changes, true)
		return true
	func formation_state(_formation: int) -> Dictionary:
		return {"fatigue": 14.0, "fatigue_rest": 0.0, "formal_person": 1}
	func team_record(_formation: int) -> Dictionary:
		if _formation in solo_formations:
			return {}
		return {"units": [], "officer_service": [], "officer_order": []}
	func siege_native_supported() -> bool: return false # No siege crew or native siege methods in this fixture.
	func person_fighting(_identity: int) -> bool: return false # No combat state is registered in this fixture; the guard reads the persons as peaceful.

class Fixture extends RefCounted:
	var lab: Variant
	var terrain := TerrainData.new()
	var character := TerrainTestCharacter.new()
	var npc: TerrainTestCharacter
	var combat_armies: Array[TerrainArmy] = []
	var combat_actors: Array[TerrainTestCharacter] = []
	var crowd_site := NativeFixture.new()
	var actions := Actions.new()
	var captivity := Supply.new()
	var first := Owner.new()
	var second := Owner.new()
	var row: Dictionary
	func _init() -> void:
		lab = self
		terrain.allocate(Vector2i(12, 12))
		terrain.flags.fill(TerrainData.Flag.WALKABLE)
		terrain.site = {"minute": 0, "phase": 0.0, "paused": false,
			"manual": {"cargo": {"arrow": 7}}, "worker": {"cargo": {}},
			"captivity": {}, "team_supply": {}, "person_supply": {}}
		assert(Runtime.initialize_item_storage(terrain.site).ok)
		character.person_id = 1
		character.item_state = Runtime.new_item_state("person:1")
		character._saved_appearance = {"marker": "original"}
		combat_actors.append(character)
		row = {"person_id": 2, "hp": 100.0, "ko": 0.0, "captive": false,
			"item_state": Runtime.new_item_state("person:2"), "cargo": {"bolt": 3},
			"appearance": {}, "loot_settled": false, "remains_id": "", "hit_revision": 0}
		crowd_site.lab = self
		crowd_site.states = {0: {"hp": 75.0, "ko": 0.0, "getup": 0.0, "captive": false,
			"state": 0, "stagger": 0.0, "px": 4.5, "py": 4.5, "vx": 0.0, "vy": 0.0, "contact_revision": 0},
			1: {"hp": 0.0, "ko": 0.0, "getup": 0.0, "captive": true,
			"state": 8, "stagger": 0.0, "px": 5.5, "py": 4.5, "vx": 8.0, "vy": 0.0, "contact_revision": 0}}
		first.setup(crowd_site, 0, 1, 0, {}, {0: character})
		second.setup(crowd_site, 1, 2, 1, {1: row})
		crowd_site.owners = [first, second]
		actions.init(self)
		captivity.init(self)
		var members: Dictionary = captivity._all_members()
		for identity in [1, 2]:
			var state := Sustain.create(0.0)
			assert(Sustain.add_members(state, members, [identity]).ok)
			terrain.site.team_supply[str(identity)] = {"version": 1, "sustain": state,
				"inventory": {}, "training_order": false, "training_requester": -1,
				"revision": 0, "delivery": {}, "life_checkpoint": {str(identity): 0}}
	func controlled_person_id() -> int:
		return 1
	func _combat_target(identity: int) -> Dictionary:
		var owner: Variant = crowd_site.person_owner(identity)
		return owner.person(owner.index_for_identity(identity), false) if owner != null else {}
	func _original_person_target(identity: int, _with_bodies: bool = false) -> Dictionary: return _combat_target(identity) # Real lookup returns the same owner row for crowd people.
	func _region_deferring_endpoint() -> bool: return false # No Region point is pending in this fixture.
	func _supply_entry(team: Variant) -> Dictionary:
		return terrain.site.team_supply.get(str(team.team_id), {})
	func _align_supply_clock(state: Dictionary, at: float) -> bool:
		return absf(float(state.at) - at) < 0.00001
	func _life(body: Dictionary) -> int:
		return 2 if float(body.hp) <= 0.0 else 1 if float(body.get("ko", 0.0)) > 0.0 else 0
	func close() -> void:
		actions.lab = null
		captivity.controller = null
		first.crowd_site = null
		second.crowd_site = null
		first.actors.clear()
		first.combat_units.clear()
		crowd_site.lab = null
		crowd_site.crowd = null
		crowd_site.owners.clear()
		combat_actors.clear()
		character.free()
		lab = null

func _initialize() -> void:
	var fixture := Fixture.new()
	_check_packed_views(fixture)
	_check_contact_revision_views(fixture)
	var actor: Dictionary = fixture.actions._person(1)
	var soldier: Dictionary = fixture.actions._person(2)
	assert(float(actor.hp) == 75.0 and float(soldier.hp) == 0.0)
	assert(is_same(actor.body, fixture.character))
	assert(is_same(actor.holder, fixture.character.item_state))
	assert(is_same(actor.cargo, fixture.terrain.site.manual.cargo))
	assert(is_same(soldier.body, fixture.row) and is_same(soldier.cargo, fixture.row.cargo))
	assert(not bool(soldier.moving)) # Death ignores residual native velocity.
	actor.cargo.arrow = 4
	assert(int(fixture.terrain.site.manual.cargo.arrow) == 4)
	fixture.actions._body_set(actor, "loot_settled", true)
	fixture.actions._body_set(actor, "remains_id", "remains:fixture")
	assert(fixture.character.loot_settled and fixture.character.remains_id == "remains:fixture")
	assert(fixture.actions._body_get(actor, "loot_settled"))
	assert(fixture.first.combat_hot_get(0, &"fatigue") == 14.0)
	assert(float(fixture.captivity._all_members()[1].hp) == 75.0)
	assert(float(fixture.row.hp) == 100.0) # Materialization never writes a hot mirror.
	fixture.actions._body_set(actor, "ko", 3.0)
	assert(float(fixture.crowd_site.states[0].ko) == 3.0 and fixture.character.knockout_left == 0.0)
	fixture.actions._body_set(actor, "attack", false)
	assert(fixture.first.ignored_attack_writes == 1)
	assert(fixture.first.unknown_field_accesses == 0 and fixture.second.unknown_field_accesses == 0)
	var blocked: Array[Dictionary] = [
		fixture.actions.lootable(1, "person", "2"),
		fixture.actions.begin_loot(1, "person", "2", {}, []),
		fixture.actions.begin_capture(1, 2, 1), fixture.actions.begin_unbind(1, 2),
		fixture.actions.begin_equipment(1, {}), fixture.actions.begin_escape(1),
		fixture.actions.begin_ransom(1, 2, 1), fixture.actions.begin_ranged_craft(1, "irrelevant")]
	for result: Dictionary in blocked:
		assert(not result.ok and result.code == "CROWD_ACTIVE")
	assert(fixture.actions._jobs.is_empty())

	# Native target is already captive AND dead; ordinary action preflight rejects,
	# event preflight must still transfer its original eaten-meal history.
	assert(not fixture.captivity.change_guard(2, 1, true).ok)
	fixture.terrain.site.team_supply["1"].delivery = {"fixture": true}
	var before: Dictionary = fixture.terrain.site.duplicate(true)
	var refused: Dictionary = fixture.captivity.event_change_guard(2, 1, true)
	assert(not refused.ok and refused.code == "BUSY")
	assert(fixture.terrain.site == before and fixture.captivity._prepared.is_empty())
	fixture.terrain.site.team_supply["1"].delivery.clear()
	assert(fixture.captivity.event_change_guard(2, 1, true).ok)
	fixture.captivity.discard(2)
	assert(fixture.captivity._prepared.is_empty())
	assert(Sustain._ids(fixture.terrain.site.team_supply["2"].sustain) == [2])
	assert(fixture.captivity.event_change_guard(2, 1, true).ok)
	fixture.terrain.site.captivity["2"] = {"captor_id": 1, "guard_id": 1}
	fixture.captivity.commit_change(2, 1, true)
	assert(2 in Sustain._ids(fixture.terrain.site.team_supply["1"].sustain))
	assert(Sustain._ids(fixture.terrain.site.team_supply["2"].sustain).is_empty())
	assert(fixture.captivity._prepared.is_empty())
	fixture.crowd_site.states[1].captive = false
	assert(fixture.captivity.event_change_guard(2, 1, false).ok)
	fixture.terrain.site.captivity.erase("2")
	fixture.captivity.commit_change(2, 1, false)
	assert(Sustain._ids(fixture.terrain.site.team_supply["2"].sustain) == [2])
	assert(not 2 in Sustain._ids(fixture.terrain.site.team_supply["1"].sustain))
	assert(fixture.first.unknown_field_accesses == 0 and fixture.second.unknown_field_accesses == 0)
	_check_scoped_supply_views(fixture)
	fixture.close()
	var solo := Fixture.new()
	solo.crowd_site.solo_formations = [0]
	solo.terrain.site.person_supply["1"] = solo.terrain.site.team_supply["1"].sustain
	solo.terrain.site.team_supply.erase("1")
	assert(not solo.first.cape_role_allowed(0)) # Native solo commander is not an original appointment.
	assert(solo.captivity._original_team(1) == null)
	assert(solo.captivity._home(1).key == "person:1")
	assert(is_same(solo.captivity._home(1).actor, solo.character))
	assert(solo.captivity.event_change_guard(2, 1, true).ok)
	solo.terrain.site.captivity["2"] = {"captor_id": 1, "guard_id": 1}
	solo.captivity.commit_change(2, 1, true)
	assert(not solo.terrain.site.team_supply.has("1"))
	assert(2 in Sustain._ids(solo.terrain.site.person_supply["1"]))
	solo.close()
	print("CROWD_C2_PEOPLE_ADAPTER_PASS")
	quit(0)


func _check_contact_revision_views(fixture: Fixture) -> void:
	var native := fixture.crowd_site
	native.contact_revision_reads = 0
	assert(int(fixture.first.person(0).hit) == 0 and native.contact_revision_reads == 1)
	# Native contact versions are distinct from the original cold row's revision.
	native.states[1].contact_revision = 7
	assert(int(fixture.second.person(1).hit) == 7 and native.contact_revision_reads == 2)
	assert(int(fixture.row.hit_revision) == 0)
	native.states[1].contact_revision = 8
	assert(int(fixture.second.person(1).hit) == 8 and native.contact_revision_reads == 3)
	native.states[1].contact_revision = 0

func _check_packed_views(fixture: Fixture) -> void:
	var native := fixture.crowd_site
	native.soldier_reads = 0
	native.formation_reads = 0
	native.dictionary_reads = 0
	assert(fixture.first.combat_hot_get(0, &"fatigue") == 14.0)
	assert(native.soldier_reads == 0 and native.formation_reads == 1)
	assert(fixture.first.combat_hot_get(0, &"hp") == 75.0)
	assert(native.soldier_reads == 1 and native.dictionary_reads == 0)
	assert(fixture.first.combat_hot_get(999, &"hp", -7.0) == -7.0)
	assert(not fixture.first.combat_hot_get(999, &"captive", true))
	assert(fixture.first.combat_hot_get(999, &"pose") == "down")
	var merged := Owner.new()
	merged.setup(native, 0, 1, 0, {1: fixture.row}, {0: fixture.character})
	native.soldier_reads = 0
	native.formation_reads = 0
	fixture.character.combat_status = "original status"
	var members := merged.original_members()
	assert(native.soldier_reads == 2 and native.formation_reads == 1 and native.dictionary_reads == 0)
	assert(members[1].hp == 75.0 and members[2].hp == 0.0 and members[1].fatigue == 14.0 and members[2].fatigue == 14.0)
	assert(members[1].status == fixture.character.combat_status)
	assert(is_same(members[1].item_state, fixture.character.item_state) and is_same(members[1].cargo, fixture.terrain.site.manual.cargo))
	assert(is_same(members[2].item_state, fixture.row.item_state) and is_same(members[2].cargo, fixture.row.cargo))
	assert(fixture.row.hp == 100.0 and fixture.character.hp == 100.0)
	native.states[0].hp = 74.0
	native.soldier_reads = 0
	native.formation_reads = 0
	var fresh := merged.combat_hot_materialize(0)
	assert(fresh.hp == 74.0 and members[1].hp == 75.0 and native.soldier_reads == 1 and native.formation_reads == 1)
	native.states[0].hp = 75.0
	native.states[0].state = 2
	assert(merged.combat_hot_get(0, &"attack") and merged.combat_hot_get(0, &"pose") == "attack")
	native.states[0].getup = 0.5
	assert(not merged.combat_can_act(0) and merged.combat_hot_get(0, &"pose") == "get_up")
	native.states[0].getup = 0.0
	native.states[0].ko = 3.0
	assert(not merged.combat_can_act(0) and merged.combat_hot_get(0, &"pose") == "unconscious")
	native.states[0].ko = 0.0
	native.states[0].captive = true
	assert(not merged.combat_can_act(0) and bool(merged.combat_hot_get(0, &"captive")))
	native.states[0].captive = false
	native.states[0].state = 0
	assert(merged.combat_can_act(0) and merged.combat_hot_get(0, &"pose") == "idle")
	merged.crowd_site = null
	merged.actors.clear()
	merged.combat_units.clear()

func _check_scoped_supply_views(fixture: Fixture) -> void:
	var supply := fixture.captivity
	var untouched: Dictionary = fixture.terrain.site.team_supply["1"].duplicate(true)
	untouched.sustain = Sustain.create()
	untouched.life_checkpoint = {}
	fixture.terrain.site.team_supply["3"] = untouched
	var context := {"site": fixture.terrain.site, "terrain": fixture.terrain, "native": fixture.crowd_site.crowd,
		"step": fixture.crowd_site._steps, "at": Runtime.now(fixture.terrain) * 60.0}
	# Native already holds the final escaped/dead state for this queued capture -> escape batch.
	assert(not fixture.crowd_site.states[1].captive)
	var before_preflight := fixture.terrain.site.duplicate(true)
	assert(supply.event_change_guard(2, 1, true, context).ok)
	assert(fixture.terrain.site == before_preflight)
	var prepared: Dictionary = supply._prepared[2].states
	assert(is_same(prepared["team:3"].state, untouched.sustain) and not prepared["team:3"].copied)
	assert(not is_same(prepared["team:1"].state, fixture.terrain.site.team_supply["1"].sustain))
	assert(not is_same(prepared["team:2"].state, fixture.terrain.site.team_supply["2"].sustain))
	var members: Dictionary = context.members
	fixture.terrain.site.captivity["2"] = {"captor_id": 1, "guard_id": 1}
	supply.commit_change(2, 1, true)
	assert(2 in Sustain._ids(fixture.terrain.site.team_supply["1"].sustain))
	assert(supply.event_change_guard(2, 1, false, context).ok and is_same(context.members, members))
	fixture.terrain.site.captivity.erase("2")
	supply.commit_change(2, 1, false)
	assert(2 in Sustain._ids(fixture.terrain.site.team_supply["2"].sustain) and not 2 in Sustain._ids(fixture.terrain.site.team_supply["1"].sustain))
	var before := fixture.terrain.site.duplicate(true)
	context.step = -1
	var stale: Dictionary = supply.event_change_guard(2, 1, true, context)
	assert(not stale.ok and stale.code == "BUSY" and context.invalid and not context.has("members"))
	assert(fixture.terrain.site == before and supply._prepared.is_empty())
	fixture.terrain.site.team_supply.erase("3")
	var original := fixture.second.original_members()
	var indexed: Dictionary = supply.feeding_index()
	var legacy: Dictionary = supply.team_members(fixture.second, original)
	var fast: Dictionary = supply.team_members(fixture.second, original, indexed)
	assert(indexed.duplicate_ids.is_empty() and fast == legacy and fast.keys() == legacy.keys() and is_same(fast[2], original[2]))
	# Duplicate team/person ownership is retained as an explicit fact and uses the
	# original ordered path; the original full Sustain preflight must still reject.
	fixture.terrain.site.person_supply["2"] = fixture.terrain.site.team_supply["2"].sustain.duplicate(true)
	indexed = supply.feeding_index()
	assert(2 in indexed.duplicate_ids and indexed.owners[2] == "team:2")
	assert(supply.team_members(fixture.second, original, indexed) == supply.team_members(fixture.second, original))
	var invalid: Dictionary = supply.event_change_guard(2, 1, true)
	assert(not invalid.ok and invalid.code == "INVALID_SUSTAIN")
	fixture.terrain.site.person_supply.erase("2")
