extends "res://scripts/tests/site_technology_targeted_vehicle_test.gd"
## True Runtime paid/completed ballista followed by ORIGINAL Region identity
## remapper and ORIGINAL Store cold-target validator. NOT_RUN.
## The direct original construct interval is not Fatigue/Native/full Lab proof;
## pure remap is not departure permission, Region route/clock or arrival publish.
const LineageTravel = preload("res://scripts/region_lab/region_travel.gd")
const LineageStore = preload("res://scripts/terrain_lab/site_store.gd")

func _completed_vehicle_historical_source() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var team := _vehicle_team(lab, false)
	var control := lab.controlled_person_id()
	var executor := team.combat_identity(1)
	var actions = lab.site_controller.person_actions
	var refs: Array = []
	for identity: int in [control, executor]: refs.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "真來源人物", "age_years": -1})
	_check(lab.site_controller.family_continuity.register_members(refs, true, control).ok and lab.site_controller.family_continuity.appoint_head(control, control).ok, "Actual original registry/head authorize this real executor")
	data.site.family = actions._technology_candidate()
	data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known = ["F09"]
	_check(Family.validate_family(data.site.family, str(data.site.id)), "Original schema admits the genuine registered source family")
	var family_id := str(data.site.family.family_id)
	_check(lab.character.place(Vector2i(9, 10), true) and actions.prepare_scope_technology(control, executor, "F11", family_id).ok and actions.grant_scope_technology_budget(control, "family", family_id, {"wood": 300, "iron": 100, "fiber": 100, "cloth": 50}).ok and actions.request_scope_technology_consent(control, "family", family_id, executor).ok, "True source scope/camp finite grant/original team consent precede material transaction")
	var key := str(data.site.next_vehicle)
	_check(actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", "vehicle:" + key, {"anchor": Vector2i(20, 20), "facing": Vector2i.RIGHT, "team_id": int(team.team_id)}).ok, "Actual original Runtime creates the one real paid named ballista")
	var vehicle: Dictionary = data.site.vehicles[key]
	var task: Dictionary = team.combat_units[1].work_task
	team.cells[1] = data.cell_from_index(int(task.work_cell))
	task.cell = int(task.work_cell)
	task.mode = "work"
	var active := vehicle.duplicate(true)
	_check(Runtime.advance_siege_work(data, key, "construct", float(vehicle.build.total_work), team.cells[1], int(task.work_slot), int(team.team_id), task, executor).ok, "Real original named person completes the original paid construction interval at the original station")
	_check(vehicle.phase == "idle" and vehicle.build.is_empty() and vehicle.has("technology_construction") and not vehicle.has("tech_trial") and not vehicle.has("tech_batch"), "Real original completion produces its immutable source event and removes active permission/payment")
	var event = vehicle.technology_construction.duplicate(true)
	var maps := {"person": {str(executor): str(executor + 100)}, "team": {str(team.team_id): str(team.team_id + 1)}, "vehicle": {key: "77"}, "item": {}, "loot": {}, "nation": {}, "corps": {}, "family": {}}
	var content := {"vehicles": {key: vehicle.duplicate(true)}}
	var before := var_to_bytes(content)
	var arrived := LineageTravel._remap_content(content, maps)
	_check(var_to_bytes(content) == before and arrived.vehicles.has("77") and arrived.vehicles["77"].id == "77" and arrived.vehicles["77"].holder.holder == "vehicle:77" and arrived.vehicles["77"].team_id == int(team.team_id) + 1, "Original pure arrival mapper changes actual local vehicle/holder/team references without modifying source")
	_check(arrived.vehicles["77"].technology_construction == event, "Original completed event keeps source Site/target/operator/work/materials byte-equivalent after person and vehicle collisions")
	var destination := _building_fixture()
	destination.site.id = "technology-lineage-arrival"
	destination.site.next_vehicle = 78
	destination.site.vehicles = arrived.vehicles
	_check(Runtime.validate_technology_target_storage(destination, "77", destination.site.vehicles["77"], "vehicle").ok and LineageStore._validate_fs_targets(destination, destination.site, {}).ok, "Original cold target validator admits the true completed vehicle with historical source Site and source local ID")
	Runtime.normalize_technology_target_storage(destination.site.vehicles["77"])
	_check(destination.site.vehicles["77"].technology_construction == event, "Cold normalization preserves immutable event identity and payment lineage")
	var valid = destination.site.vehicles["77"].duplicate(true)
	for malformed: Dictionary in [{"site_id": ""}, {"target_id": "vehicle:077"}, {"target_id": "feature:77"}]:
		var candidate = valid.duplicate(true)
		candidate.technology_construction.merge(malformed, true)
		_check(not Runtime.validate_technology_target_storage(destination, "77", candidate, "vehicle").ok, "Malformed historical source string or noncanonical/wrong target prefix is rejected")
	var forged_active := active.duplicate(true)
	forged_active.id = "77"
	forged_active.holder.holder = "vehicle:77"
	_check(not Runtime.validate_technology_target_storage(destination, "77", forged_active, "vehicle").ok, "An original active paid/trial token cannot become foreign travel permission by changing current local ID")
	var unfinished = valid.duplicate(true)
	unfinished.phase = "building"
	unfinished.build = active.build.duplicate(true)
	_check(not Runtime.validate_technology_target_storage(destination, "77", unfinished, "vehicle").ok, "Completed history cannot claim a still-building original geometry is complete")
	_cleanup_fixture(lab, team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	await _completed_vehicle_historical_source()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_COMPLETED_VEHICLE_LINEAGE_PASS: %d checks; real paid/completed vehicle/original pure Region remap/immutable source event/strict cold target; no fulltravel clock Native all40" % checks)
	quit(0)
