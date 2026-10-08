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
	assert(args.has("--crowd-test") and args.has("--crowd-atlas-root") and not args.has("--crowd"))
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
	# A real military operation uses the original lossless clear-to-GD handoff.
	var formed := Garrison.form(lab, key, [captain, soldier], captain)
	assert(formed.ok and not host.active, str(formed))
	assert(_actual_ids(lab) == all_ids_before, "A returning native roster must not be overwritten by a previously empty GD slot")
	assert(_meal_history(controller) == meals)
	var formed_team: TerrainArmy = Garrison._team(lab, int(formed.team_id))
	assert(formed_team.combat_identity(formed_team.current_commander) == captain)
	assert(source.garrison_feature_id == key and source.combat_units.size() == 1)
	for identity: int in original:
		var person: Dictionary = controller.person_actions._person(identity)
		assert(is_same(person.body, original[identity].row) and is_same(person.holder, original[identity].holder) and is_same(person.cargo, original[identity].cargo))
		assert(person.cell == original[identity].cell and person.holder == original[identity].items and person.cargo == original[identity].cargo_copy)
		if identity == patient: assert(person.hp == after_patient.hp and person.ko == after_patient.ko)
	# The guarded clear disposes a non-startup host. Re-enter through a fresh
	# original CrowdSite, just as this fixture's first explicit native entry.
	assert(lab.crowd_site == null)
	await process_frame
	lab.crowd_site = CrowdHost.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	host = lab.crowd_site
	imported = lab.deploy_trial_armies([{"faction": 1, "count": 1, "female_percent": 0,
		"attack": false, "ai_enabled": false, "spawn": Vector2i(44, 40)}])
	assert(imported.ok and host.active, str(imported))
	assert(bool(host.crowd.get_garrisoned(host.person_owner(patient).formation_index)))
	assert(not bool(host.crowd.get_garrisoned(host.person_owner(captain).formation_index)))
	assert(controller._capture_for_save().ok)
	assert(Store._validate_crowd(data, data.site, 1).ok)
	all_ids_before = _actual_ids(lab)
	var returned := Garrison.admit(lab, key, int(formed.team_id))
	assert(returned.ok and not host.active, str(returned))
	assert(_actual_ids(lab) == all_ids_before)
	var queried := Garrison.query(lab, key)
	assert(queried.people_count == 3 and queried.officers.size() == 1 and queried.soldier_count == 2)
	for identity: int in original:
		var person: Dictionary = controller.person_actions._person(identity)
		assert(is_same(person.body, original[identity].row) and is_same(person.holder, original[identity].holder) and is_same(person.cargo, original[identity].cargo))
		if identity == patient: assert(person.hp == after_patient.hp and person.ko == after_patient.ko)
	controller._capture_positions()
	var final_save: Dictionary = Store._validate_state(data, data.site)
	assert(final_save.ok, str(final_save))
	for _warmup: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_GARRISON_CROWD_PASS: original garrison D5, native qualification/membership/lifecycle, stationary positions, 1/4-worker save parity, corrupt mirrors rejected, actual form/admit via clear, original rows/items/meals survive re-D5")
	quit(0)
