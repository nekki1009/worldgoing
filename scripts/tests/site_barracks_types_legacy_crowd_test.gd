extends "res://scripts/tests/site_barracks_dense_garrison_crowd_test.gd"
## Run against the previous formal DLL, before publishing set_recovery_input.
## Only existing fixtures and the central admission/step paths are exercised.

func _run() -> void:
	deadline = Time.get_ticks_msec() + 220000
	var args := OS.get_cmdline_user_args()
	assert(args.has("--crowd-test") and args.has("--crowd-atlas-root") and args.has("--grid"))
	assert(DisplayServer.get_name() != "headless" and ClassDB.class_exists(&"ArmyCrowd"))
	assert(not ClassDB.class_has_method(&"ArmyCrowd", &"set_recovery_input"), "This acceptance requires the previous formal DLL")
	await _ordinary_and_empty_chinese()
	_registered_and_stale_mirrors()
	TerrainArmy.release_contact_source()
	print("SITE_BARRACKS_TYPES_LEGACY_CROWD_PASS: old DLL lacks recovery input; real ordinary deploy/step works with empty Chinese facility; registered Chinese central guard rejects before deployment; live formal form reference supersedes stale mirror while a load candidate retains its own reference")
	quit(0)

func _ordinary_and_empty_chinese() -> void:
	var data := _building_fixture()
	var standard := _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(10, 10), {"camp_type": "standard"})
	var chinese := _formal_feature(data, "barracks", Vector2i(36, 20), Vector2i(10, 10), {"camp_type": "chinese"})
	var lab := _building_lab(data)
	var team: TerrainArmy = lab.army
	_make_garrison_team(lab, team, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)])
	var captain := team.combat_identity(0)
	assert(Garrison.admit(lab, standard, team.team_id).ok)
	assert(Garrison.query(lab, chinese).registered_count == 0)
	var row: Dictionary = team.combat_units[0]
	assert(await CrowdHost.prepare_captivity_recipe(lab, Runtime.equipment_appearance(data, row.item_state, row.appearance)))
	lab.crowd_site = CrowdHost.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	var host: Node = lab.crowd_site
	assert(host.siege_admission_guard().ok, "An empty Chinese feature cannot exclude an ordinary old-DLL Site")
	var imported := lab.deploy_trial_armies([{"faction": 1, "count": 1, "female_percent": 0,
		"attack": false, "ai_enabled": false, "spawn": Vector2i(44, 40)}])
	assert(imported.ok and host.active, str(imported))
	var formation: int = host.person_owner(captain).formation_index
	assert(host.set_formation_fields(formation, {"fatigue": 60.0, "fatigue_rest": PersonFatigue.REST_DELAY}))
	var before := float(host.formation_state(formation).fatigue)
	var steps := int(host._steps)
	host.step(TerrainLab.ACTION_STEP, 6.0, 0.0)
	assert(host.last_event_error.is_empty() and int(host._steps) == steps + 1, str(host.last_event_error))
	var recovered := before - float(host.formation_state(formation).fatigue)
	assert(absf(recovered - PersonFatigue.RECOVERY_RATE * 6.0) < 0.00000001, str(recovered))
	assert(host.siege_admission_guard().ok)
	print("SITE_BARRACKS_TYPES_LEGACY_ORDINARY_PASS recovered=", recovered, " empty_chinese=", chinese)
	for _frame: int in range(3): await process_frame
	lab.free()
	await process_frame
	TerrainArmy.release_contact_source()

func _registered_and_stale_mirrors() -> void:
	var data := _building_fixture()
	var chinese := _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(10, 10), {"camp_type": "chinese"})
	var lab := _building_lab(data)
	var source: TerrainArmy = lab.army
	_make_garrison_team(lab, source, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)])
	var identities: Array[int] = []
	for row: Dictionary in source.combat_units: identities.append(int(row.person_id))
	var captain := source.combat_identity(0)
	assert(Garrison.admit(lab, chinese, source.team_id).ok)
	# Capture the real A registration before its formal complete transfer into B.
	lab.site_controller._capture_positions()
	var saved_source_id := source.team_id
	var source_mirror: Dictionary = {}
	for mirror: Dictionary in data.site.armies:
		if int(mirror.team_id) == saved_source_id: source_mirror = mirror
	assert(not source_mirror.is_empty() and source_mirror.garrison_feature_id == chinese)
	lab.crowd_site = CrowdHost.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	var host: Node = lab.crowd_site
	var before_site := JSON.stringify(data.site)
	var before_people := source.capture_combat_state()
	var rejected: Dictionary = host.siege_admission_guard()
	assert(not rejected.ok and rejected.code == "CROWD_BUILD_MISMATCH", str(rejected))
	var deploy_rejected: Dictionary = host.deploy([{"faction": 1, "count": 1}], [[Vector2i(44, 40)]])
	assert(not deploy_rejected.ok and deploy_rejected.code == "CROWD_BUILD_MISMATCH", str(deploy_rejected))
	assert(not host.active and JSON.stringify(data.site) == before_site and source.capture_combat_state() == before_people)
	# Use the formal original-person form transaction, then emulate its old disk mirror only.
	var formed := Garrison.form(lab, chinese, identities, captain)
	assert(formed.ok, str(formed))
	var ordinary: TerrainArmy = Garrison._team(lab, int(formed.team_id))
	assert(ordinary.garrison_feature_id.is_empty() and ordinary.combat_identity(ordinary.current_commander) == captain)
	assert(not source.has_army() and not source.combat_enabled and source.garrison_feature_id.is_empty())
	assert(source_mirror.garrison_feature_id == chinese and data.site.armies.has(source_mirror), "The old real A mirror must still be present")
	assert(host.siege_admission_guard().ok, "The emptied original A slot must supersede its real pre-form Chinese mirror")
	print("SITE_BARRACKS_TYPES_LEGACY_EMPTY_SOURCE_PASS: actual complete A-to-B form leaves stale real A mirror; empty live A registration wins")
	lab.site_controller._capture_positions()
	var stale_found := false
	for mirror: Dictionary in data.site.armies:
		if int(mirror.team_id) == ordinary.team_id:
			mirror.garrison_feature_id = chinese
			stale_found = true
	assert(stale_found)
	assert(host.siege_admission_guard().ok, "A live formally formed roster must supersede its stale saved registration")
	var candidate := TerrainGenerator.generate(data.preset, data.seed_value, data.parameters)
	candidate.site = data.site.duplicate(true)
	var candidate_before := JSON.stringify(candidate.site)
	rejected = host.siege_admission_guard(candidate)
	assert(not rejected.ok and rejected.code == "CROWD_BUILD_MISMATCH", "The candidate must retain its own Chinese reference: " + str(rejected))
	assert(JSON.stringify(candidate.site) == candidate_before and ordinary.garrison_feature_id.is_empty())
	for mirror: Dictionary in candidate.site.armies: mirror.garrison_feature_id = ""
	assert(host.siege_admission_guard(candidate).ok, "An ordinary candidate cannot inherit the live Site's stale mirror")
	print("SITE_BARRACKS_TYPES_LEGACY_GUARD_PASS: registered rejection; original formal form; stale live override; independent candidate references")
	lab.free()
