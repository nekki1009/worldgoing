extends "res://scripts/tests/site_garrison_test.gd"

const CrowdHost = preload("res://scripts/terrain_lab/crowd_site.gd")
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")

func _actual_ids(lab: TerrainLab) -> Array[int]:
	var seen := {}
	for actor: TerrainTestCharacter in lab.combat_actors: seen[actor.person_id] = true
	for team: Dictionary in Garrison._armies(lab):
		for row: Dictionary in team.rows:
			assert(not seen.has(int(row.person_id)))
			seen[int(row.person_id)] = true
	var ids: Array[int] = []
	for identity: int in seen: ids.append(identity)
	ids.sort()
	return ids

func _run() -> void:
	deadline = Time.get_ticks_msec() + 220000
	var args := OS.get_cmdline_user_args()
	assert(args.has("--crowd-test") and args.has("--crowd-atlas-root") and args.has("--grid"))
	assert(DisplayServer.get_name() != "headless")
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var key := _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(10, 10))
	var source: TerrainArmy = lab.army
	source.roster_size = 3
	source.faction_id = 1
	assert(source.deploy_at(data, lab.character, lab.npc, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)]))
	assert(source.enable_combat(false, 0))
	source.set_process(false)
	source.settle_combat_command()
	var captain := source.combat_identity(0)
	var soldier := source.combat_identity(1)
	var patient := source.combat_identity(2)
	var original := {}
	for index in range(source.combat_units.size()):
		var row: Dictionary = source.combat_units[index]
		original[int(row.person_id)] = {"row": row, "holder": row.item_state, "cargo": row.cargo,
			"items": row.item_state.duplicate(true), "cargo_copy": row.cargo.duplicate(true), "cell": source.cells[index]}
	var supply: Dictionary = controller._enable_team_supply(source)
	assert(not supply.is_empty())
	supply.sustain.open_rations = 0.375
	source.combat_hot_set(2, &"hp", 63.0)
	source.combat_hot_set(2, &"ko", 30.0)
	source.combat_hot_set(2, &"pose", "unconscious")
	source._cell_owners.erase(source.cells[2])
	assert(Garrison.admit(lab, key, source.team_id).ok)
	var appearance := Runtime.equipment_appearance(data, original[captain].holder, original[captain].row.appearance)
	var prepare_started := Time.get_ticks_msec()
	var prepared: bool = await CrowdHost.prepare_captivity_recipe(lab, appearance)
	print("SITE_GARRISON_CROWD_PREPARATION ", JSON.stringify({"ok": prepared, "seconds": (Time.get_ticks_msec() - prepare_started) / 1000.0, "key": Atlas._mixed_key(appearance)}))
	assert(prepared)
	lab.crowd_site = CrowdHost.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	# This explicit extra person is only the existing deployment entry's fixture.
	# Every soldier admitted/forming below is one of the three original IDs.
	var imported: Dictionary = lab.deploy_trial_armies([{"faction": 1, "count": 1, "female_percent": 0,
		"attack": false, "ai_enabled": false, "spawn": Vector2i(40, 40)}])
	assert(imported.ok, str(imported))
	var host: Node = lab.crowd_site
	var formation: int = host.person_owner(captain).formation_index
	assert(bool(host.crowd.get_garrisoned(formation)))
	assert(int(host.crowd.get_military_role(int(host.crowd.soldier_index(captain)))) == 1)
	assert(int(host.crowd.get_military_role(int(host.crowd.soldier_index(soldier)))) == 0)
	var roles: Dictionary = host.formation_state(formation)
	assert(int(roles.formal_person) == -1 and int(roles.current_person) == -1 and roles.officer_persons.is_empty())
	assert(not controller.person_actions._prison_officer(controller.person_actions._person(captain)).is_empty())
	assert(controller.person_actions._prison_officer(controller.person_actions._person(soldier)).is_empty())
	assert(not host.issue_order(source.team_id, TerrainArmy.CombatOrder.MOVE, Vector2i(24, 28)).ok)
	var before_patient: Dictionary = host.soldier_state(int(host.crowd.soldier_index(patient)))
	var clock_before := Runtime.now(data)
	for _frame: int in range(3): lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
	var after_patient: Dictionary = host.soldier_state(int(host.crowd.soldier_index(patient)))
	var game_elapsed := (Runtime.now(data) - clock_before) * 60.0
	# native/crowd10k/src/rules.hpp and World::bleed_stage: an unbandaged,
	# free KO person loses 25 HP per game hour while the original KO clock runs.
	assert(game_elapsed > 0.0 and game_elapsed < float(before_patient.ko) and not before_patient.bandaged and not before_patient.captive)
	var expected_hp := float(before_patient.hp) - 25.0 * game_elapsed / 3600.0
	var expected_ko := float(before_patient.ko) - game_elapsed
	assert(absf(float(after_patient.hp) - expected_hp) < 0.00000001 and absf(float(after_patient.ko) - expected_ko) < 0.00000001,
		str({"before": before_patient, "after": after_patient, "game_elapsed": game_elapsed, "expected_hp": expected_hp, "expected_ko": expected_ko}))
	assert(after_patient.px == before_patient.px and after_patient.py == before_patient.py)
	for identity: int in original:
		var person: Dictionary = controller.person_actions._person(identity)
		assert(person.cell == original[identity].cell and is_same(person.holder, original[identity].holder) and is_same(person.cargo, original[identity].cargo))
		assert(is_same(host._records[identity], original[identity].row))
	var captured: Dictionary = controller._capture_for_save()
	assert(captured.ok, str(captured))
	var one: Dictionary = Store._validate_crowd(data, data.site, 1)
	var four: Dictionary = Store._validate_crowd(data, data.site, 4)
	assert(one.ok and four.ok, str({"one": one, "four": four}))
	assert(one.native.save_state() == host.crowd.save_state() and four.native.save_state() == host.crowd.save_state())
	for _frame: int in range(30):
		assert(one.native.step_clock(TerrainLab.ACTION_STEP, TerrainLab.ACTION_STEP, 0.0))
		assert(four.native.step_clock(TerrainLab.ACTION_STEP, TerrainLab.ACTION_STEP, 0.0))
		assert(one.native.state_hash() == four.native.state_hash())
	var broken: Dictionary = data.site.duplicate(true)
	for roster: Dictionary in broken.armies:
		if str(roster.get("garrison_feature_id", "")) == key:
			roster.garrison_feature_id = ""
			break
	assert(not Store._validate_crowd(data, broken).ok)
	broken = data.site.duplicate(true)
	for roster: Dictionary in broken.armies:
		for row: Dictionary in roster.units:
			if int(row.person_id) == soldier: row.military_role = "officer"
	assert(not Store._validate_crowd(data, broken).ok)
	var before_failure: PackedByteArray = host.crowd.save_state()
	assert(not Garrison.form(lab, key, [soldier], soldier).ok)
	assert(host.active and host.crowd.save_state() == before_failure)
	var meals := _meal_history(controller)
	var all_ids_before := _actual_ids(lab)
	# G5 S3: form runs on the native roster. The crowd stays active; reserves leave the garrison by absence.
	var formed := Garrison.form(lab, key, [captain, soldier], captain)
	assert(formed.ok and host.active, str(formed))
	assert(_actual_ids(lab) == all_ids_before, "A returning native roster must not be overwritten by a previously empty GD slot")
	assert(_meal_history(controller) == meals)
	var formed_owner: Variant = host.person_owner(captain)
	var formed_formation: int = int(formed_owner.formation_index)
	var garrison_formation: int = int(host.person_owner(patient).formation_index)
	assert(int(formed.team_id) == int(formed_owner.team_id) and formed_formation != garrison_formation)
	assert(int(host.person_owner(soldier).formation_index) == formed_formation)
	assert(not bool(host.crowd.get_garrisoned(formed_formation)) and int(host.formation_state(formed_formation).formal_person) == captain)
	assert(bool(host.crowd.get_garrisoned(garrison_formation)))
	var garrison_roster: Dictionary = host.team_record(garrison_formation)
	assert(garrison_roster.garrison_feature_id == key and garrison_roster.units.size() == 1)
	var returned_roster: Dictionary = host.team_record(formed_formation)
	assert(returned_roster.garrison_feature_id == "" and returned_roster.units.size() == 2)
	for identity: int in [captain, soldier]:
		assert(int(host.crowd.site_person_absent_state(int(host.crowd.soldier_index(identity)))[0]) == 0)
	# Mid-garrison save: the native blob and the GD mirror validate together.
	assert(controller._capture_for_save().ok)
	var mid_save: Dictionary = Store._validate_crowd(data, data.site, 1)
	assert(mid_save.ok and mid_save.native.save_state() == host.crowd.save_state(), str(mid_save))
	for identity: int in original:
		var person: Dictionary = controller.person_actions._person(identity)
		assert(is_same(host._records[identity], original[identity].row) and is_same(person.holder, original[identity].holder) and is_same(person.cargo, original[identity].cargo))
		assert(person.cell == original[identity].cell and person.holder == original[identity].items and person.cargo == original[identity].cargo_copy)
		if identity == patient: assert(person.hp == after_patient.hp and person.ko == after_patient.ko)
	# G5 S3: the native roster stays authoritative; there is no clear-to-grid round trip after a native form
	# (the grid command contract cannot re-place a natively formed team: PRESENCE_CONFLICT). Continue in the crowd.
	assert(bool(host.crowd.get_garrisoned(host.person_owner(patient).formation_index)))
	assert(not bool(host.crowd.get_garrisoned(host.person_owner(captain).formation_index)))
	assert(controller._capture_for_save().ok)
	assert(Store._validate_crowd(data, data.site, 1).ok)
	all_ids_before = _actual_ids(lab)
	# G5 S3: admit of the formed native team garrisons its formation in place; the crowd stays active.
	var returned := Garrison.admit(lab, key, int(formed.team_id))
	assert(returned.ok and host.active, str(returned))
	assert(_actual_ids(lab) == all_ids_before)
	assert(bool(host.crowd.get_garrisoned(int(host.person_owner(captain).formation_index))))
	var queried := Garrison.query(lab, key)
	assert(queried.people_count == 3 and queried.officers.size() == 1 and queried.soldier_count == 2)
	for identity: int in original:
		var person: Dictionary = controller.person_actions._person(identity)
		assert(is_same(host._records[identity], original[identity].row) and is_same(person.holder, original[identity].holder) and is_same(person.cargo, original[identity].cargo))
		if identity == patient: assert(person.hp == after_patient.hp and person.ko == after_patient.ko)
	# Under the crowd the save capture is _capture_for_save (grid positions plus the native rosters and blob).
	assert(controller._capture_for_save().ok)
	var final_save: Dictionary = Store._validate_state(data, data.site)
	assert(final_save.ok, str(final_save))
	for _warmup: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_GARRISON_CROWD_PASS: original garrison D5, native qualification/membership/lifecycle, stationary positions, 1/4-worker save parity, corrupt mirrors rejected, native form/admit keep the crowd active with absent reserves, mid-garrison save parity, original rows/items/meals survive re-D5")
	quit(0)
