extends "res://scripts/tests/site_building_ui_test.gd"

const CrowdHost = preload("res://scripts/terrain_lab/crowd_site.gd")
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const STEP := 1.0 / 30.0

func _feeding_owners(controller: SiteController) -> Dictionary:
	var states: Dictionary = controller.captivity_supply._states(false)
	var pools: Array = []
	var keys: Array[String] = []
	var at := Runtime.now(controller.lab.terrain) * 60.0
	for key: String in states:
		var pool: Dictionary = states[key].state
		if not pool.cohorts.is_empty():
			assert(absf(float(pool.at) - at) < 0.00001, str({"owner": key, "supply_at": pool.at, "site_at": at}))
		pools.append(pool)
		keys.append(key)
	var checked := SiteController.Sustain.validate_owner_index(pools, controller.captivity_supply._all_members(), keys)
	assert(checked.ok, str(checked))
	return checked.owners

func _escort_trace(lab: TerrainLab, captive_id: int, prison_key: String, frame: int) -> void:
	var actions: SitePersonActions = lab.site_controller.person_actions
	var escort: SiteCaptiveEscort = lab.site_controller.captive_escort
	var captive: Dictionary = actions._person(captive_id)
	var guard: Dictionary = actions._person(int(lab.terrain.site.captivity[str(captive_id)].guard_id))
	var layout := Runtime.prison_layout(lab.terrain, prison_key)
	var contacts := actions.prison_contacts(prison_key, [int(guard.person_id), captive_id])
	var route: Array[Vector2i] = escort._route(guard, layout.slots[0].contact_cell, false, [], contacts)
	var next := route[0] if not route.is_empty() else TerrainArmy.INVALID_CELL
	print("SITE_BUILDING_CROWD_ESCORT ", JSON.stringify({"frame": frame, "guard": str(guard.cell), "captive": str(captive.cell),
		"guard_ready": actions._ready(guard, true), "guard_stopped": actions._prison_stopped(guard),
		"guard_busy": actions.is_busy(int(guard.person_id)), "threat": actions._threat(guard, {}),
		"captive_awake": escort._awake_captive(captive), "effective_guard": actions.has_effective_guard(captive_id),
		"route_length": route.size(), "next": str(next), "edge": lab.terrain.can_step(guard.cell, next),
		"range": actions._within_guard_range(captive.cell, next), "blocked": actions.prison_blocked(next, [int(guard.person_id)], contacts),
		"guard_escort": Array(lab.crowd_site.crowd.escort_state(int(guard.unit))),
		"captive_escort": Array(lab.crowd_site.crowd.escort_state(int(captive.unit)))}))

func _run() -> void:
	deadline = Time.get_ticks_msec() + 220000
	var args := OS.get_cmdline_user_args()
	assert(args.has("--crowd-test") and args.has("--crowd-atlas-root") and args.has("--grid"))
	assert(DisplayServer.get_name() != "headless", "The exact captured appearance is prepared by the original GPU atlas owner")
	var data: TerrainData = _building_fixture()
	var lab: TerrainLab = _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var guard: TerrainTestCharacter = lab.character
	var guard_id := int(guard.person_id)
	var prison_key := _formal_feature(data, "prison", Vector2i(35, 35))
	var wall_key := _formal_feature(data, "palisade", Vector2i(20, 20), Vector2i(3, 1))
	_formal_feature(data, "wall_stairs", Vector2i(20, 21))
	var gate_key := _formal_feature(data, "gate", Vector2i(24, 28))
	assert(guard.place(Vector2i(35, 38), true))
	var deployed: Dictionary = lab.deploy_trial_armies([{"faction": 2, "count": 1, "female_percent": 0,
		"attack": false, "ai_enabled": false, "spawn": Vector2i(34, 38)}])
	assert(deployed.ok, str(deployed))
	var original: TerrainArmy = lab.army
	original.set_process(false)
	var captive_id := original.combat_identity(0)
	var original_cell: Vector2i = original.cells[0]
	assert(original_cell == Vector2i(34, 38))
	original.combat_hot_set(0, &"hp", 63.0)
	original.combat_hot_set(0, &"ko", 30.0)
	assert(actions.begin_capture(guard_id, captive_id, guard_id).ok)
	actions.advance(4.0)
	var captured: Array[Dictionary] = actions.settle_after_contacts()
	assert(captured.size() == 1 and captured[0].ok)
	# Recovery belongs to this fixture, before the native ownership transfer.
	original.combat_hot_set(0, &"ko", 0.0)
	original.combat_hot_set(0, &"stun", 0.0)
	original.combat_hot_set(0, &"pose", "idle")
	original.combat_hot_set(0, &"age", 0.0)
	var row: Dictionary = original.combat_units[0]
	var holder: Dictionary = row.item_state
	var cargo: Dictionary = row.cargo
	var holder_copy := holder.duplicate(true)
	var cargo_copy := cargo.duplicate(true)
	var relation_copy: Dictionary = data.site.captivity[str(captive_id)].duplicate(true)
	var supply_copy: Dictionary = data.site.person_supply.duplicate(true)
	# Prepare only this original person's actual post-capture appearance. The
	# ordinary recipe owner keeps strict source, pixels and dye-mask admission.
	var captured_appearance := Runtime.equipment_appearance(data, holder, row.appearance)
	assert(captured_appearance.parts.weapon == "none" and captured_appearance.parts.shield == "none")
	var was_prepared := not Atlas.mixed_recipe(captured_appearance).is_empty() and not Atlas.dye_entry(captured_appearance).is_empty()
	var prepare_started := Time.get_ticks_msec()
	var prepared: bool = await CrowdHost.prepare_captivity_recipe(lab, captured_appearance)
	var preparation := {"ok": prepared, "already_prepared": was_prepared, "seconds": (Time.get_ticks_msec() - prepare_started) / 1000.0,
		"appearance": captured_appearance, "recipe_key": Atlas._mixed_key(captured_appearance),
		"directory": Atlas._mixed_directory(Atlas._mixed_key(captured_appearance))}
	var report_path := "res://output/site_building_implementation_20261003/crowd_preparation_" + str(args[args.find("--crowd-test") + 1]) + ".json"
	assert(not FileAccess.file_exists(report_path), "Each verification keeps its own preparation cost evidence")
	var report := FileAccess.open(report_path, FileAccess.WRITE)
	assert(report != null)
	report.store_string(JSON.stringify(preparation, "\t", true, true))
	report.close()
	print("SITE_BUILDING_CROWD_PREPARATION ", JSON.stringify(preparation))
	assert(prepared, str(preparation))
	assert(holder == holder_copy and cargo == cargo_copy and data.site.person_supply == supply_copy)
	assert(Runtime.equipment_appearance(data, holder, row.appearance) == captured_appearance)
	lab.crowd_site = CrowdHost.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	var imported: Dictionary = lab.deploy_trial_armies([{"faction": 1, "count": 1, "female_percent": 0,
		"attack": false, "ai_enabled": false, "spawn": Vector2i(20, 20)}])
	assert(imported.ok, str(imported))
	var host: Node = lab.crowd_site
	assert(host.active and host.owns_original_team(original) and not original.combat_enabled)
	assert(is_same(host._records[captive_id], row))
	var captive_index: int = host.crowd.soldier_index(captive_id)
	var person: Dictionary = actions._person(captive_id)
	assert(is_same(person.holder, holder) and is_same(person.cargo, cargo))
	assert(person.hp == 63.0 and person.ko == 0.0 and person.captive and person.cell == original_cell)
	assert(host.crowd.soldier_refs(captive_index)[2] == 0)
	var feeding_before := _feeding_owners(controller).duplicate()
	assert(str(feeding_before[captive_id]) == "person:%d" % guard_id)
	assert(data.can_step(Vector2i(20, 21), Vector2i(20, 20)) and data.effective_height(Vector2i(20, 20)) == 2)
	var surface_id: int = int(host.teams[0].person_ids[0])
	_assert_native_worker_unavailable(lab, surface_id)
	var surface_index: int = host.crowd.soldier_index(surface_id)
	var before_fall: Dictionary = host.soldier_state(surface_index)
	var surface_holder: Dictionary = host._records[surface_id].item_state
	var surface_cargo: Dictionary = host._records[surface_id].cargo
	var natural_heights := data.height_levels.duplicate()
	var damage: Dictionary = Runtime.damage_structure_part(data, wall_key, "c:" + str(data.index(Vector2i(20, 20))), 100.0)
	assert(damage.ok, str(damage))
	lab.resolve_structure_change(damage)
	var fallen: Dictionary = host.soldier_state(surface_index)
	assert(fallen.hp == before_fall.hp - 30.0 and fallen.ko > 0.0)
	assert(fallen.px == before_fall.px and fallen.py == before_fall.py and fallen.ammo == before_fall.ammo)
	assert(is_same(host._records[surface_id].item_state, surface_holder) and is_same(host._records[surface_id].cargo, surface_cargo))
	assert(data.height_levels == natural_heights and data.effective_height(Vector2i(20, 20)) == 0)
	assert(host.sync_terrain() and host.soldier_state(surface_index).hp == fallen.hp, "Repeated sync must not apply a second fall")
	print("SITE_BUILDING_CROWD_STAGE D5_and_single_fall")
	var started: Dictionary = controller.captive_escort.begin_prison(guard_id, guard_id, prison_key)
	assert(started.ok, str(started))
	for frame: int in range(1800):
		lab._advance_action_time(STEP)
		if frame <= 300 and frame % 30 == 0: _escort_trace(lab, captive_id, prison_key, frame)
		if str(data.site.captivity[str(captive_id)].get("prison_id", "")) == prison_key: break
		if frame % 120 == 0: await process_frame
	var admitted: Dictionary = actions.prison_slot(captive_id)
	assert(admitted.ok, str({"result": admitted, "target": host.soldier_state(captive_index),
		"guard": host.soldier_state(int(host.crowd.soldier_index(guard_id))),
		"guard_escort": host.crowd.escort_state(int(host.crowd.soldier_index(guard_id))),
		"captive_escort": host.crowd.escort_state(captive_index), "orders": data.site.escort_orders}))
	assert(host.crowd.soldier_refs(captive_index)[2] == int(prison_key))
	var contacts := actions.prison_contacts(prison_key, [guard_id, captive_id])
	assert(actions.prison_blocked(admitted.slot.cell, [guard_id], contacts), "The captive's physical cell remains occupied")
	assert(not actions.prison_blocked(admitted.slot.contact_cell, [guard_id], contacts), "The adjacent contact cell is reachable")
	assert(actions.prison_blocked(Vector2i(20, 20), [guard_id], contacts), "Unrelated native people keep their full occupancy")
	assert(original.cells[0] == original_cell, "Disabled source Army is retained, never used as native position authority")
	assert(not actions.prison_blocked(original_cell), "Retained cold source must not reserve the old native position")
	assert(holder == holder_copy and cargo == cargo_copy)
	assert(_feeding_owners(controller) == feeding_before, "Admission keeps each original feeding owner while the shared game clock advances")
	assert(int(admitted.relation.captor_id) == int(relation_copy.captor_id))
	assert(int(admitted.relation.guard_id) == int(relation_copy.guard_id))
	assert(not actions.is_guarding(guard_id) and not actions.begin_escape(captive_id).ok)
	print("SITE_BUILDING_CROWD_STAGE automatic_admission")
	var confined: Dictionary = host.soldier_state(captive_index)
	var confinement_at := Runtime.now(data) * 60.0
	for frame: int in range(1050):
		lab._advance_action_time(STEP)
		if Runtime.now(data) * 60.0 - confinement_at >= 35.0: break
		if frame % 120 == 0: await process_frame
	assert(Runtime.now(data) * 60.0 - confinement_at >= 35.0)
	var after_wait: Dictionary = host.soldier_state(captive_index)
	assert(after_wait.captive and after_wait.escape_t == 0.0 and after_wait.hp == 63.0)
	assert(after_wait.px == confined.px and after_wait.py == confined.py)
	assert(_feeding_owners(controller) == feeding_before and holder == holder_copy and cargo == cargo_copy)
	print("SITE_BUILDING_CROWD_STAGE confined_35_game_seconds")
	assert(controller._capture_for_save().ok)
	assert(Store._validate_captivity(data, data.site).ok)
	var one: Dictionary = Store._validate_crowd(data, data.site, 1)
	var four: Dictionary = Store._validate_crowd(data, data.site, 4)
	assert(one.ok and four.ok, str({"one": one, "four": four}))
	var saved_bytes: PackedByteArray = host.crowd.save_state()
	assert(one.native.save_state() == saved_bytes and four.native.save_state() == saved_bytes)
	for _frame: int in range(60):
		assert(one.native.step_clock(STEP, STEP, 0.0) and four.native.step_clock(STEP, STEP, 0.0))
		assert(one.native.state_hash() == four.native.state_hash())
	var broken: Dictionary = data.site.duplicate(true)
	broken.features[gate_key].gate.open = true
	var candidate: TerrainData = Env.navigation_for_state(data, broken)
	var rejected: Dictionary = Store._validate_crowd(candidate, broken)
	assert(not rejected.ok and rejected.code == "INVALID_CROWD" and str(rejected.message).contains("地形"), str(rejected))
	broken = data.site.duplicate(true)
	broken.captivity[str(captive_id)].prison_id = ""
	assert(not Store._validate_crowd(data, broken).ok)
	assert(host.crowd.save_state() == saved_bytes and holder == holder_copy and cargo == cargo_copy)
	print("SITE_BUILDING_CROWD_STAGE store_load_workers_and_rejections")
	var released_start: Dictionary = actions.begin_prison_release(guard_id, captive_id)
	assert(released_start.ok, str(released_start))
	var release_at := Runtime.now(data) * 60.0
	for _frame: int in range(600):
		lab._advance_action_time(TerrainLab.ACTION_STEP)
		if not data.site.captivity.has(str(captive_id)): break
		assert(not actions.job_for(guard_id).is_empty(), controller.message.text)
	var release_elapsed := Runtime.now(data) * 60.0 - release_at
	assert(not data.site.captivity.has(str(captive_id)) and release_elapsed >= 4.0 - 0.00001, str({"elapsed": release_elapsed, "message": controller.message.text}))
	assert(release_elapsed <= 4.0 + Runtime.game_seconds(TerrainLab.ACTION_STEP, 0.0) * lab.simulation_speed + 0.00001)
	var after_release: Dictionary = host.soldier_state(captive_index)
	assert(not after_release.captive and after_release.prison_id == 0 and after_release.hp == after_wait.hp)
	assert(after_release.ko == after_wait.ko and after_release.px == after_wait.px and after_release.py == after_wait.py)
	assert(not data.site.captivity.has(str(captive_id)) and int(holder.version) == int(holder_copy.version) + 1)
	assert(is_same(actions._person(captive_id).holder, holder) and is_same(actions._person(captive_id).cargo, cargo))
	var feeding_after := _feeding_owners(controller)
	assert(feeding_after.size() == feeding_before.size() and feeding_after[captive_id] == "team:%d" % original.team_id)
	for identity: int in feeding_before:
		if identity != captive_id: assert(feeding_after[identity] == feeding_before[identity])
	var supply_after: Dictionary = data.site.person_supply.duplicate(true)
	var team_supply_after: Dictionary = data.site.team_supply.duplicate(true)
	assert(actions.settle_after_contacts().is_empty() and host.crowd.validate())
	assert(data.site.person_supply == supply_after and data.site.team_supply == team_supply_after and int(holder.version) == int(holder_copy.version) + 1)
	print("SITE_BUILDING_CROWD_INTEGRATION_PASS original D5 owners, native surface/fall sync, actual prison escort, confined clock, original items/supply, 1/4-worker load parity, Store terrain/mirror rejection, single native release")
	# Let the original two-frame visual warmup finish before removing its Lab.
	for _frame: int in range(3): await process_frame
	lab.free()
	quit()
