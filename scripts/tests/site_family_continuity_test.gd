extends "res://scripts/tests/site_workflow_test.gd"

const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const REMOTE := "res://.godot-temp/site_family_continuity/remote.json"
const ARCHIVE := "res://.godot-temp/site_family_continuity/current.json"
var archive_calls := 0
var archived_before_bind := false

func _reference(site_id: String, identity: int, path: String = "", age: int = -1) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": path,
		"label": "Explicit test fixture relative #%d" % identity, "age_years": age}

func _remote_fixture() -> TerrainData:
	# These are explicitly authored TEST people, not a production heir generator.
	# Actual original actor snapshots are persisted and fully validated by Store.
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 54321)
	Env.initialize(data, "family-remote-fixture")
	var cells: Array[Vector2i] = []
	for offset in range(data.size.x * data.size.y):
		var cell := data.cell_from_index(offset)
		if data.is_walkable(cell):
			cells.append(cell)
		if cells.size() == 2:
			break
	assert(cells.size() == 2)
	var person := TerrainTestCharacter.new()
	var guard := TerrainTestNPC.new()
	person.person_id = 1
	person.faction_id = 1
	guard.person_id = 2
	guard.faction_id = 2
	guard.visual_state.body_index = 1
	for actor: TerrainTestCharacter in [person, guard]:
		actor.data = data
		assert(actor.place(cells[actor.person_id - 1], true))
		var appearance := HumanCharacter3DEditor.default_appearance(actor.visual_state.body_index)
		assert(Runtime.seed_person_equipment(data, actor.item_state, actor.person_id, appearance).ok)
	person.hp = 67.0
	person.fatigue = 21.5
	person.captive = true
	person.knockout_left = 2.0
	data.site.player_cell = data.index(person.terrain_cell)
	data.site.worker.cell = data.index(guard.terrain_cell)
	data.site.manual.cargo = {"grain": 3}
	data.site.worker.cargo = {"fish": 7}
	data.site.actors = {"player": person.capture_state(), "npc": guard.capture_state()}
	data.site.armies = []
	data.site.controlled_person_id = 1
	data.site.captivity = {"1": {"version": 1, "captor_id": 2, "guard_id": 2,
		"captor_faction": 2, "sealed_container": ""}}
	var supply := Sustain.create()
	assert(Sustain.add_members(supply, {1: data.site.actors.player, 2: data.site.actors.npc}, [1, 2]).ok)
	supply.cohorts[0].hunger = 7.5
	supply.cohorts[0].coverage = 0.5
	supply.cohorts[0].meal_until = 21600.0
	data.site.person_supply = {"2": supply}
	person.free()
	guard.free()
	return data

func _kill_and_settle(controller: SiteController, identity: int) -> void:
	# Use the actual owner death entrypoint, including down pose and item callback.
	# Geometry and animation timing have their own directed tests.
	var person: Dictionary = controller.person_actions._person(identity)
	var packet := {"result": {"hp": float(person.hp), "stun": 0.0, "guard_break": false}, "shield": false, "environmental": true}
	if int(person.unit) >= 0:
		person.owner.apply_unit_contact(int(person.unit), packet)
	else:
		person.owner.apply_contact(packet)
	controller.settle_person_deaths(3.0)
	for team: TerrainArmy in controller.lab.combat_armies:
		team.settle_combat_command() # Original same-step death/office/presence phase.
	assert(controller.supply_save_guard().ok)
	assert(controller.person_actions._body_get(person, "loot_settled"))

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(data, "family-current-fixture")
	lab.bind_terrain(data)
	data.site.controlled_person_id = lab.character.person_id
	data.site.manual.cargo = {"grain": 5}
	data.site.worker.cargo = {"fish": 4}
	var team: TerrainArmy = lab.combat_armies[0]
	team.roster_size = 3
	assert(team.deploy(data, lab.character, lab.npc))
	assert(team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	controller.initialize_team_items(team)
	var soldier: Dictionary = team.combat_units[1]
	soldier.hp = 58.0
	soldier.fatigue = 32.5
	soldier.cargo = {"wood": 2}
	var soldier_id := int(soldier.person_id)
	var helper := Family.new()
	helper.init(lab)
	helper.load_site_query = Store.load_site
	helper.control_selected = controller._control_family_person
	assert(str(helper.inspect().status) == "UNREGISTERED")
	assert(not data.site.has("family"), "Inspection must not manufacture a family")
	assert(not Family.validate_family({"version": true, "complete": true, "members": []}))
	var members := [_reference(str(data.site.id), lab.npc.person_id, ARCHIVE, 14),
		_reference(str(data.site.id), soldier_id, ARCHIVE)]
	assert(helper.register_members(members, false).ok)
	var family_before: Dictionary = data.site.family.duplicate(true)
	assert(not helper.register_members(members + [members[0]], true).ok)
	assert(not helper.register_members([_reference(str(data.site.id), 99999)], true).ok)
	assert(data.site.family == family_before)
	lab.character.knockout_left = 30.0
	lab.character.captive = true
	assert(str(helper.death_tick().status) == "ALIVE")
	assert(str(helper.choose(str(data.site.id), lab.npc.person_id).code) == "NOT_DEAD")
	lab.character.knockout_left = 0.0
	lab.character.captive = false
	lab.npc.hp = 44.0
	lab.npc.fatigue = 12.0
	lab.npc.captive = true
	data.site.captivity[str(lab.npc.person_id)] = {"version": 1, "captor_id": team.combat_identity(0),
		"guard_id": team.combat_identity(0), "captor_faction": team.faction_id, "sealed_container": ""}
	var original_player := lab.character
	var original_npc := lab.npc
	var npc_gear: Dictionary = lab.npc.item_state.duplicate(true)
	var roles := [team.formal_commander, team.current_commander, team.acting_commander, team.officer_order.duplicate()]
	_kill_and_settle(controller, lab.character.person_id)
	assert(helper.death_tick().changed and not helper.death_tick().changed)
	var choice := helper.inspect()
	assert(str(choice.status) == "CHOOSE" and int(choice.living_relatives) == 2)
	assert(int(choice.members[0].age_years) == 14 and int(choice.members[1].age_years) == -1)
	assert(helper.choose(str(data.site.id), lab.npc.person_id).ok)
	assert(lab.character == original_player and lab.npc == original_npc)
	assert(lab.controlled_target().owner == original_npc and lab.controlled_person_id() == original_npc.person_id)
	assert(original_npc.hp == 44.0 and original_npc.fatigue == 12.0 and original_npc.captive)
	assert(original_npc.item_state == npc_gear and data.site.worker.cargo == {"fish": 4})
	assert(data.site.manual.cargo.is_empty(), "The dead original actor's cargo stays in original remains")
	assert(data.site.family == family_before and not helper.choose(str(data.site.id), soldier_id).ok)
	_kill_and_settle(controller, original_npc.person_id)
	var soldier_before := soldier.duplicate(true)
	assert(helper.choose(str(data.site.id), soldier_id).ok)
	assert(lab.controlled_target().owner == team and int(lab.controlled_target().unit) == 1)
	assert(team.combat_units[1] == soldier_before and is_same(team.combat_units[1], soldier))
	assert(lab.character == original_player and lab.npc == original_npc and not is_instance_valid(team.player_member))
	assert(roles == [team.formal_commander, team.current_commander, team.acting_commander, team.officer_order])
	assert(data.site.family == family_before)
	_kill_and_settle(controller, soldier_id)
	assert(helper.register_members([], false).ok and str(helper.inspect().status) == "DATA_MISSING")
	assert(helper.register_members([], true).ok and str(helper.inspect().status) == "GAME_OVER")
	data.site.family.members = [_reference("missing-family-site", 1, "res://.godot-temp/site_family_continuity/missing.json")]
	var unknown := helper.inspect()
	assert(str(unknown.status) == "DATA_MISSING" and int(unknown.unknown_relatives) == 1)
	assert(not helper.choose("missing-family-site", 1).ok and lab.terrain == data)
	var remote := _remote_fixture()
	var remote_save := Store.save(remote, REMOTE)
	assert(remote_save.ok, str(remote_save))
	var readback := Store.load_site(REMOTE)
	assert(readback.ok, str(readback))
	assert(Family._saved_person(readback.data, 1).captive)
	data.site.family.members = [_reference("wrong-site", 1, REMOTE)]
	assert(str(helper.choose("wrong-site", 1).code) == "STALE_SITE" and lab.terrain == data)
	members = [_reference(str(data.site.id), soldier_id, ARCHIVE), _reference(str(remote.site.id), 1, REMOTE, 12)]
	assert(helper.register_members(members, true).ok)
	assert(str(helper.inspect().status) == "CHOOSE", "A minor/captive/KO relative in another Site remains living")
	var original_remains: Dictionary = data.site.ground_loot.duplicate(true)
	var original_records: Dictionary = data.site.item_records.duplicate(true)
	var original_family: Dictionary = data.site.family.duplicate(true)
	helper.archive_current = func() -> Dictionary:
		archive_calls += 1
		return controller._archive_family_site()
	data.site.combat_left = 1.0
	var busy := helper.choose(str(remote.site.id), 1)
	assert(str(busy.code) == "BUSY" and archive_calls == 1)
	assert(lab.terrain == data and lab.controlled_person_id() == soldier_id)
	assert(data.site.ground_loot == original_remains and data.site.item_records == original_records)
	assert(data.site.family == original_family and data.site.combat_left == 1.0)
	# Test fixture advances the already-existing grace clock; helper never does.
	Runtime.advance(data, 1.0, true)
	assert(data.site.combat_left == 0.0)
	helper.archive_current = func() -> Dictionary:
		archive_calls += 1
		var guard_result := controller.supply_save_guard()
		if not guard_result.ok:
			return guard_result
		controller._capture_positions()
		var saved := Store.save(data, ARCHIVE)
		if saved.ok:
			var archived := Store.load_site(ARCHIVE)
			archived_before_bind = archived.ok and archived.data.site.ground_loot == original_remains
		return saved
	helper.control_selected = func(validated: Variant, identity: int) -> Dictionary:
		assert(archived_before_bind and lab.terrain == data, "Archive must finish before the original bind")
		return controller._control_family_person(validated, identity)
	var switched := helper.choose(str(remote.site.id), 1)
	assert(switched.ok, str(switched))
	assert(archive_calls == 2 and archived_before_bind and lab.terrain != data)
	assert(str(lab.terrain.site.id) == str(remote.site.id) and lab.controlled_person_id() == 1)
	assert(lab.character == original_player and lab.npc == original_npc, "Original physical actor slots are restored, never exchanged")
	assert(lab.character.hp == 67.0 and lab.character.fatigue == 21.5 and lab.character.captive and lab.character.knockout_left == 2.0)
	assert(lab.terrain.site.manual.cargo == {"grain": 3} and lab.terrain.site.worker.cargo == {"fish": 7})
	assert(lab.character.item_state == remote.site.actors.player.item_state)
	assert(lab.terrain.site.person_supply == remote.site.person_supply and lab.terrain.site.captivity == remote.site.captivity)
	assert(lab.terrain.site.family == original_family and int(lab.terrain.site.family.members[1].age_years) == 12)
	assert(not helper.choose(str(data.site.id), soldier_id).ok)
	var old_site := Store.load_site(ARCHIVE)
	assert(old_site.ok and old_site.data.site.ground_loot == original_remains and old_site.data.site.item_records == original_records)
	assert(int(old_site.data.site.controlled_person_id) == soldier_id)
	lab.queue_free()
	await process_frame
	print("SITE FAMILY CONTINUITY PASS: explicit composite original-person registry; missing data never false Game Over; death-only local NPC and real Army row control keeps bodies/cargo/gear/captive/age/offices; validated remote captive minor and original meal history; BUSY preserves old Site; original remains archived before bind; UI/keyboard/GPU separately required")
	quit(0)
