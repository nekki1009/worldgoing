extends SceneTree
## Formal TerrainLab integration. All save paths are restricted before Site construction.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const DT := 1.0 / 30.0
var lab: TerrainLab
var checks := 0
var results: Array[Dictionary] = []
var suite := "integration"
var failed := false
var output_root := "res://output/crowd_c2_c3_20261001"
var fixture := ""
var event_people := {}
var event_fields_error := {}
var event_rows := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--crowd-suite")
	if at >= 0 and at + 1 < args.size(): suite = args[at + 1]
	at = args.find("--crowd-output")
	if at >= 0 and at + 1 < args.size(): output_root = args[at + 1]
	at = args.find("--crowd-fixture")
	if at >= 0 and at + 1 < args.size(): fixture = args[at + 1]
	_run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null, stop_on_failure: bool = true) -> bool:
	checks += 1
	results.append({"ok": ok, "check": label, "details": details})
	print("C2/C3 ", "OK " if ok else "FAIL ", checks, ": ", label, " ", str(details) if details != null else "")
	if not ok:
		failed = true
		_write_result()
		printerr("GATE FAIL: ", label, " ", str(details))
		if stop_on_failure: quit(2)
	return ok

func _write_result() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	var path := output_root.path_join(suite + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": not failed, "suite": suite, "checks": checks, "results": results}, "\t"))
		file.close()

func _run() -> void:
	# 11/15: the 5,000-person B/D fixtures run about 1-2 s per melee step (outer 1860 s); the normal suite keeps 600 s.
	create_timer(1800.0 if not fixture.is_empty() else (600.0 if suite == "normal" else 180.0)).timeout.connect(func() -> void:
		failed = true
		_write_result()
		printerr("GATE FAIL: script deadline")
		quit(3))
	var args := OS.get_cmdline_user_args()
	if not _check(args.has("--crowd-test") and (suite in ["normal", "c3-restart"] or args.has("--crowd")), "isolated crowd flags required"): return
	var baseline_copy := args.find("--crowd-baseline-copy")
	var copy_arg := args.find("--crowd-reload-copy")
	if baseline_copy >= 0: copy_arg = baseline_copy
	if copy_arg >= 0:
		if not _check(copy_arg + 1 < args.size(), "reload copy requires a source fixture"): return
		var source := args[copy_arg + 1]
		var paths: Node = load("res://scripts/terrain_lab/site_controller.gd").new()
		var configured: Dictionary = paths.configure_test_paths(args)
		if not _check(configured.ok and not paths.crowd_test_run_id.is_empty() and paths._save_path_guard(paths.save_path).ok and (source.begins_with("res://output/") or source.begins_with("res://.godot-temp/") or source.begins_with("res://native/crowd10k/out_c2/") or source.begins_with("res://native/crowd10k/out_c3/")), "copy preflight requires named test root and project evidence source", configured):
			paths.free()
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(paths.save_root))
		var destination: String = paths.save_root.path_join("baseline.json") if baseline_copy >= 0 else paths.save_path
		var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination))
		paths.free()
		if not _check(copied == OK, "copied prior isolated save into this run before Site creation", error_string(copied)): return
	lab = TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.character.set_process(false)
	var controller: Node = lab.site_controller
	if not _check(not controller.crowd_test_run_id.is_empty() and str(lab.terrain.site.id).begins_with("crowd_test_"), "test root and Site ID isolated before startup"): return
	if not _check(not controller._save_path_guard(Store.DEFAULT_PATH).ok, "formal save path rejected"): return
	if suite == "c3-legacy":
		var source: Dictionary = Store._read(controller.save_path)
		if not _check(source.ok and not source.payload.state.has("crowd") and (lab.crowd_site == null or not lab.crowd_site.active), "ordinary snapshot loads under crowd startup without inventing a crowd", source.get("code", "")): return
		if not _ordinary_state_check(source.payload.state): return
		_write_result()
		lab.queue_free()
		await process_frame
		print("GATE OK: ordinary snapshot compatibility under crowd startup")
		quit(0)
		return
	if suite == "c3-restart":
		await _restart_run()
		return
	if suite == "normal":
		await _normal_regression()
		return
	if not fixture.is_empty():
		await _large_fixture()
		return
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 8, "training": 80.0, "ai_enabled": true, "attack": false, "entry": "west"},
		{"faction": 1, "count": 8, "training": 0.0, "ai_enabled": false, "attack": false, "entry": "east"}])
	if not _check(deployed.ok, "formal scene deployment", deployed): return
	var site: Node = lab.crowd_site
	if not _check(site.active and int(site.crowd.soldier_count()) == 17, "native soldiers and original actor registered", site.crowd.soldier_count()): return
	if not _check(site.crowd.stats().size() == 40, "stats ABI has 40 fields"): return
	var teams: Array[Dictionary] = site.command_teams()
	var team: Dictionary = teams[0]
	var enemy: Dictionary = teams[1]
	if not lab.terrain.site.has("team_supply"): lab.terrain.site.team_supply = {}
	var at_seconds := (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0
	for owner in site.person_owners():
		if site.team_record(owner.formation_index).is_empty(): continue
		var members: Dictionary = owner.original_members()
		var supply: Dictionary = Sustain.create(at_seconds)
		if not _check(Sustain.add_members(supply, members, members.keys()).ok, "fixture enables original meal cohorts", owner.team_id): return
		var life := {}
		for identity: int in members: life[str(identity)] = 0
		lab.terrain.site.team_supply[str(owner.team_id)] = {"version": 1, "sustain": supply, "inventory": {"grain": 1000},
			"training_order": false, "training_requester": -1, "revision": 0, "delivery": {}, "life_checkpoint": life}
	var before: Dictionary = site.formation_state(int(team.formation))
	var orders := int(site.order_calls)
	var invalid: Dictionary = site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.MOVE, Vector2i(-1, -1), -1, "test")
	if not _check(not invalid.ok and site.formation_state(int(team.formation)) == before and int(site.order_calls) == orders, "invalid MOVE preflight preserves AI and formation without a native call", invalid): return
	var commander: Dictionary = site.soldier_state(int(site.crowd.soldier_index(int(before.current_person))))
	var legal_goal := Vector2i(floori(float(commander.px)), floori(float(commander.py)))
	site.test_order_failure = 5
	var rejected: Dictionary = site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.MOVE, legal_goal, -1, "test")
	site.test_order_failure = -1
	if not _check(not rejected.ok and rejected.code == "BLOCKED" and site.formation_state(int(team.formation)) == before and int(site.order_calls) == orders + 1, "failed manual order restores AI and all formation state", rejected): return
	var held: Dictionary = site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "test")
	if not _check(held.ok and not bool(site.formation_state(int(team.formation)).ai_enabled), "manual HOLD disables AI only after successful transaction", held): return
	var patient_id := int(site._team_by_id(int(enemy.team_id)).person_ids[1])
	var guard_id := int(site._team_by_id(int(team.team_id)).person_ids[0])
	var patient_index := int(site.crowd.soldier_index(patient_id))
	if not _check(not controller.person_actions._person(patient_id).is_empty(), "formal person resolver finds native soldier"): return
	var patient: Dictionary = controller.person_actions._person(patient_id)
	var old_holder: Dictionary = patient.holder.duplicate(true)
	var old_cargo: Dictionary = patient.cargo.duplicate(true)
	if not _check(site.set_soldier_fields(patient_index, {"captive": 1.0, "captor_person": guard_id, "ko": 14400.0}), "native captured state fixture admitted"): return
	site.pending_captivity.append({"kind": 4, "person": patient_id, "other": guard_id, "ammo_synced": false})
	var guard_supply: Dictionary = lab.terrain.site.team_supply[str(team.team_id)]
	guard_supply.delivery = {"fixture": true}
	var before_supply: Dictionary = lab.terrain.site.team_supply.duplicate(true)
	site.settle_events()
	if not _check(site.pending_captivity.size() == 1 and lab.terrain.site.team_supply == before_supply and patient.holder == old_holder and patient.cargo == old_cargo and controller.captivity_supply._prepared.is_empty(), "supply preflight rejection leaves all original cohorts and items unchanged", site.last_event_error): return
	guard_supply.delivery = {}
	site.test_seal_failure = true
	site.settle_events()
	if not _check(site.pending_captivity.size() == 1 and patient.holder == old_holder and patient.cargo == old_cargo and not lab.terrain.site.captivity.has(str(patient_id)) and controller.captivity_supply._prepared.is_empty(), "seal failure leaves original items and relation unchanged", site.last_event_error): return
	if not _check(not controller.supply_save_guard().ok, "pending captivity blocks save"): return
	site.test_seal_failure = false
	site.settle_events()
	if not _check(site.pending_captivity.is_empty() and lab.terrain.site.captivity.has(str(patient_id)), "captivity retry commits original Site relation once", site.last_event_error): return
	var relation: Dictionary = lab.terrain.site.captivity[str(patient_id)]
	if not _check(not str(relation.sealed_container).is_empty() and lab.terrain.site.ground_loot.has(str(relation.sealed_container)), "captured equipment stays in original sealed container"): return
	var container_count: int = lab.terrain.site.ground_loot.size()
	site.settle_events()
	if not _check(container_count == lab.terrain.site.ground_loot.size(), "settling an empty queue cannot duplicate sealed equipment"): return
	# A still-KO captive cannot escape while this independent transaction fixture
	# exercises two real game hours through the common action/supply clock.
	var supply_start := _game_time()
	var supply_steps := 0
	var supply_difference := {}
	while _game_time() - supply_start < 7200.0 - 0.00001:
		lab._advance_action_time(DT)
		supply_steps += 1
		for entry: Dictionary in lab.terrain.site.team_supply.values():
			if not entry.sustain.cohorts.is_empty() and absf(float(entry.sustain.at) - _game_time()) > 0.00001:
				supply_difference = {"site": _game_time(), "sustain": entry.sustain.at, "step": supply_steps}
		if not supply_difference.is_empty() or supply_steps > 9000: break
		if supply_steps % 120 == 0: await process_frame
	if not _check(supply_difference.is_empty() and _game_time() - supply_start >= 7200.0 - 0.00001 and lab.terrain.site.captivity.has(str(patient_id)), "every supply clock stays aligned for two game hours after first capture", {"game_seconds": _game_time() - supply_start, "steps": supply_steps, "difference": supply_difference}): return
	# Escape then recapture exercises the valid empty selection (no second container).
	if not _check(site.set_soldier_fields(patient_index, {"captive": 0.0, "captor_person": -1}), "native escape fixture admitted"): return
	site.pending_captivity.append({"kind": 5, "person": patient_id, "other": guard_id, "ammo_synced": true})
	site.settle_events()
	if not _check(site.pending_captivity.is_empty() and not lab.terrain.site.captivity.has(str(patient_id)), "escape commits original relation removal"): return
	if not _check(site.set_soldier_fields(patient_index, {"captive": 1.0, "captor_person": guard_id}), "native recapture fixture admitted"): return
	site.pending_captivity.append({"kind": 4, "person": patient_id, "other": guard_id, "ammo_synced": false})
	site.settle_events()
	if not _check(site.pending_captivity.is_empty() and lab.terrain.site.captivity[str(patient_id)].sealed_container == "" and container_count == lab.terrain.site.ground_loot.size(), "empty recapture commits without creating or duplicating container"): return
	# The formal common tail advances meals on exactly the same Site game-time slices.
	for tick in range(3): lab._advance_action_time(DT)
	var expected_at := (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0
	for entry: Dictionary in lab.terrain.site.team_supply.values():
		if not _check(absf(float(entry.sustain.at) - expected_at) < 0.00001, "native meal clock matches original Site clock", {"site": expected_at, "sustain": entry.sustain.at}): return
	# A native actor may be anywhere inside a legal cell, never forced to its grid centre.
	var actor_index := int(site.crowd.soldier_index(lab.character.person_id))
	var actor_state: Dictionary = site.soldier_state(actor_index)
	if not _check(site.set_soldier_fields(actor_index, {"px": floorf(float(actor_state.px)) + 0.37, "py": floorf(float(actor_state.py)) + 0.61, "hp": 71.25}), "continuous actor position and wounds fixture admitted"): return
	var actor_expected: Dictionary = site.soldier_state(actor_index)
	lab.terrain.site.combat_left = 0.0
	var save: Dictionary = controller.save_to(controller.save_path)
	if not _check(save.ok, "full SiteStore saves native actors, rosters, items and custody", save): return
	var path: String = controller.save_path
	var save_hash := FileAccess.get_sha256(path)
	var expected_hash: int = site.crowd.state_hash()
	var expected_stats: PackedFloat64Array = site.crowd.stats()
	var expected_ids: PackedInt64Array = site.crowd.person_ids()
	lab.crowd_startup_requested = false
	var loaded: Dictionary = controller.load_from(path)
	if not _check(loaded.ok and lab.crowd_site.active, "full load activates crowd even without startup crowd preference", loaded): return
	site = lab.crowd_site
	if not _check(site.crowd.state_hash() == expected_hash and site.crowd.person_ids() == expected_ids, "full load preserves first-frame hash and person identities"): return
	if not _check(lab.character.position == Vector2(float(actor_expected.px), float(actor_expected.py)) * 64.0 and lab.character.hp == 71.25, "first frame preserves exact actor subcell position and HP", lab.character.position): return
	if not _check(_stats_equal(expected_stats, site.crowd.stats()), "full load preserves stats groups A and C"): return
	if suite == "c3":
		if not await _baseline_roundtrip(): return
		site = lab.crowd_site
		# Baseline continuation deliberately exercises current.json autosaves.
		save_hash = FileAccess.get_sha256(path)
	# Two independent native worlds resume the saved Site blob under the same inputs.
	var copy: RefCounted = ClassDB.instantiate("ArmyCrowd")
	copy.setup(1, 581)
	if not _check(copy.load_state(site.crowd.save_state()), "continuation reference accepts native snapshot"): return
	for index in range(90):
		site.crowd.step_clock(DT, DT, 0.0)
		copy.step_clock(DT, DT, 0.0)
	if not _check(site.crowd.state_hash() == copy.state_hash() and _stats_equal(site.crowd.stats(), copy.stats()), "90-step continued hash and independent A/C counters match"): return
	var native_before: int = site.crowd.state_hash()
	var site_before: Dictionary = lab.terrain.site.duplicate(true)
	var bad: Dictionary = Store._read(path)
	bad.payload.state.crowd.dll_sha256 = "0".repeat(64)
	var body := JSON.stringify(bad.payload, "", true, true)
	var bad_path: String = controller.save_root.path_join("fixtures/bad_dll.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(bad_path).get_base_dir())
	var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
	bad_file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	bad_file.close()
	var failure: Dictionary = controller.load_from(bad_path)
	if not _check(not failure.ok and bool(controller._auto_save_blocked) and site.crowd.state_hash() == native_before and lab.terrain.site == site_before and FileAccess.get_sha256(path) == save_hash, "bad DLL load preserves live Site, native state and original file; suspends autosave", failure): return
	if not await _save_flag_regression(): return
	if not _archive_paths_check(): return
	var st: PackedFloat64Array = site.crowd.stats()
	if not _check(st[14] == 0.0 and st[15] == 0.0 and st[16] == 0.0, "illegal cell, illegal edge and cooldown violations are zero", [st[14], st[15], st[16]]): return
	for owner in site.person_owners():
		if not _check(owner.unknown_field_accesses == 0, "person adapter has no unknown field fallbacks", owner.unknown_field_accesses): return
	if _close_test_requested():
		if not _close_path_check(): return
		_write_result()
		print("GATE OK: formal crowd close-request saving path")
		quit(0)
		return
	_write_result()
	lab.queue_free()
	await process_frame
	print("GATE OK: formal TerrainLab C2/C3 integration ", checks, " checks")
	quit(0)

func _stats_equal(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != 40 or b.size() != 40: return false
	for index in range(40):
		if index >= 18 and index <= 32: continue
		if a[index] != b[index]:
			print("stats first mismatch index=", index, " expected=", a[index], " actual=", b[index])
			return false
	return true

func _normal_regression() -> void:
	if not _check(lab.crowd_site == null, "ordinary startup has no crowd owner"): return
	if OS.get_cmdline_user_args().has("--crowd-reload-only"):
		var original: Dictionary = Store._read(lab.site_controller.save_path)
		if not _check(original.ok, "existing isolated ordinary snapshot available", original.get("code", "")): return
		if not _ordinary_state_check(original.payload.state): return
		_write_result()
		lab.queue_free()
		await process_frame
		print("GATE OK: ordinary reload diagnostic")
		quit(0)
		return
	var setup: Dictionary = lab.start_melee_trial({"friendly_count": 4, "enemy_count": 1,
		"friendly_training": 100.0, "enemy_training": 0.0, "friendly_ai_enabled": true,
		"enemy_ai_enabled": false, "friendly_attack": true, "enemy_attack": false})
	if not _check(setup.ok, "ordinary strong-versus-weak melee deployment", setup): return
	var fought := false
	var disengaged := false
	for tick in range(9000):
		lab._advance_action_time(DT)
		fought = fought or float(lab.terrain.site.combat_left) > 0.0
		var defeated := true
		for unit in range(lab.opposing_army.combat_units.size()):
			defeated = defeated and not lab.opposing_army.combat_can_act(unit)
		if fought and defeated and float(lab.terrain.site.combat_left) <= 0.0 and lab.site_controller.supply_save_guard().ok:
			disengaged = true
			break
		if tick % 120 == 0: await process_frame
	if not _check(fought and disengaged, "ordinary melee naturally disengages within 300 action seconds", {"combat_left": lab.terrain.site.combat_left, "guard": lab.site_controller.supply_save_guard()}): return
	var saved: Dictionary = lab.site_controller.save_to(lab.site_controller.save_path)
	if not _check(saved.ok, "ordinary full save after disengagement", saved): return
	var snapshot: Dictionary = lab.terrain.site.duplicate(true)
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	if not _check(loaded.ok and lab.crowd_site == null and not lab.terrain.site.has("crowd"), "ordinary save reload stays on original owner", loaded): return
	if not _ordinary_state_check(snapshot): return
	if not await _save_flag_regression(): return
	if not _archive_paths_check(): return
	if _close_test_requested():
		if not _close_path_check(): return
		_write_result()
		print("GATE OK: formal ordinary close-request saving path")
		quit(0)
		return
	_write_result()
	lab.queue_free()
	await process_frame
	print("GATE OK: ordinary mode regression ", checks, " checks")
	quit(0)

func _archive_paths_check() -> bool:
	var controller: Node = lab.site_controller
	for route: String in ["replace", "family"]:
		controller._auto_save_blocked = true
		var saved: bool = controller.archive_before_replace() if route == "replace" else bool(controller._archive_family_site().ok)
		if not _check(saved and not controller._auto_save_blocked, route + " archive uses save_to and clears autosave suspension"): return false
		if not _saved_original_records_check(controller._archive_path(), route + " archive"): return false
	return true

func _saved_original_records_check(path: String, label: String) -> bool:
	var saved: Dictionary = Store._read(path)
	if not saved.ok: return _check(false, label + " saved original records", saved)
	var expected := {"actors": lab.terrain.site.actors, "armies": lab.terrain.site.armies, "item_records": lab.terrain.site.item_records, "ground_loot": lab.terrain.site.ground_loot}
	var actual := {"actors": saved.payload.state.actors, "armies": saved.payload.state.armies, "item_records": saved.payload.state.item_records, "ground_loot": saved.payload.state.ground_loot}
	var difference := _first_difference(expected, actual)
	return _check(lab.site_controller._save_path_guard(path).ok and difference.is_empty(), label + " preserves exact original actors, rosters, items and remains under isolated root", {"path": path, "difference": difference})

func _close_test_requested() -> bool:
	var args := OS.get_cmdline_user_args()
	return args.has("--crowd-close-current") or args.has("--crowd-close-archive")

func _close_path_check() -> bool:
	var controller: Node = lab.site_controller
	controller._auto_save_blocked = OS.get_cmdline_user_args().has("--crowd-close-archive")
	var destination: String = controller._archive_path() if controller._auto_save_blocked else controller.save_path
	if not _check(controller._save_path_guard(destination).ok, "window close destination is confined to this test root", destination): return false
	if FileAccess.file_exists(destination):
		var renamed := DirAccess.rename_absolute(ProjectSettings.globalize_path(destination), ProjectSettings.globalize_path(destination + ".before_close"))
		if not _check(renamed == OK, "preserve prior isolated snapshot before exercising close request", error_string(renamed)): return false
	root.close_requested.emit()
	if not _check(FileAccess.file_exists(destination) and not is_instance_valid(controller._exit_dialog) and not controller._auto_save_blocked,
		"real root close-request handler saves chosen test destination successfully", destination): return false
	return _saved_original_records_check(destination, "window close")

func _save_flag_regression() -> bool:
	var controller: Node = lab.site_controller
	var bad_path: String = controller.save_root.path_join("fixtures/invalid_save.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(bad_path).get_base_dir())
	var file := FileAccess.open(bad_path, FileAccess.WRITE)
	if not _check(file != null, "isolated invalid-save fixture can be created"): return false
	file.store_string("{\"fixture\":\"invalid isolated envelope\"}")
	file.close()
	var before: Dictionary = lab.terrain.site.duplicate(true)
	var refused: Dictionary = controller.load_from(bad_path)
	if not _check(not refused.ok and controller._auto_save_blocked and lab.terrain.site == before, "invalid load preserves current Site and suspends autosave", refused): return false
	var saved: Dictionary = controller.save_to(controller.save_path)
	if not _check(saved.ok and not controller._auto_save_blocked, "successful explicit save resumes autosave after load failure", saved): return false
	var prior_sha: String = FileAccess.get_sha256(controller.save_path)
	var prior_mtime: int = FileAccess.get_modified_time(controller.save_path)
	# FileAccess reports integral seconds; cross its resolution before exercising the clock.
	await create_timer(1.05).timeout
	for tick in range(930):
		lab._advance_action_time(DT)
		controller.finish_tick()
		if tick % 30 == 0: await process_frame
	return _check(FileAccess.get_sha256(controller.save_path) != prior_sha and FileAccess.get_modified_time(controller.save_path) > prior_mtime and not controller._auto_save_blocked,
		"31 action seconds produce a changed isolated autosave with a newer modification time", {"path": controller.save_path, "before_mtime": prior_mtime, "after_mtime": FileAccess.get_modified_time(controller.save_path), "combat_left": lab.terrain.site.combat_left})

func _large_fixture() -> void:
	if not _check(fixture in ["B", "D"], "large fixture name B or D required"): return
	var setups: Array[Dictionary] = []
	for index in range(50):
		var strong := index < 25 if fixture == "B" else index % 5 < 4
		setups.append({"faction": 0 if strong else 1, "count": 100,
			"training": 100.0 if strong else (50.0 if fixture == "B" else 0.0),
			"ai_enabled": fixture == "B" or strong, "attack": fixture == "B" or strong,
			"troop_type": "bow" if fixture == "B" and index % 5 == 4 else "melee_infantry",
			"entry": "west" if strong or fixture == "D" else "east"})
	var deployed: Dictionary = lab.deploy_trial_armies(setups)
	if not _check(deployed.ok, "large formal deployment", deployed): return
	var site: Node = lab.crowd_site
	if not _check(site.crowd.soldier_count() >= 5000 and site.crowd.stats().size() == 40, "large scenario meets 5000-person and ABI gates", site.crowd.soldier_count()): return
	if fixture == "B":
		# Begin with some wounded but conscious original troops. Ordinary contact
		# must cause any DEATH; no event or combat-clock value is injected.
		var wounded: Array[int] = []
		for owner in site.person_owners():
			if site.team_record(owner.formation_index).is_empty(): continue
			var indices: Array = owner.combat_units.keys()
			indices.sort()
			for offset in range(0, indices.size(), 10):
				var index := int(indices[offset])
				if not site.set_soldier_fields(index, {"hp": 12.5}):
					_check(false, "B wounded original soldier initialization", owner.combat_identity(index))
					return
				wounded.append(owner.combat_identity(index))
		if not _check(wounded.size() == 500, "B begins with 500 wounded conscious original soldiers", {"count": wounded.size(), "hp": 12.5, "ko": 0.0}): return
		results.append({"B_initial_wounded": {"hp": 12.5, "ko": 0.0, "count": wounded.size(), "person_ids": wounded}})
	if fixture == "D":
		# Fixture-only un-equipping keeps every original item in its original holder.
		var capture_appearances: Array = []
		for owner in site.person_owners():
			if owner.faction_id != 1: continue
			for index: int in owner.combat_units:
				var person: Dictionary = owner.person(index)
				person.holder.equipped.erase("armor")
				person.holder.equipped.erase("helmet")
				person.holder.version = int(person.holder.version) + 1
				site.equipment_changed(int(person.person_id))
				capture_appearances.append(site._appearance(int(person.person_id)))
		# D changes gear after deployment admission. Admit these exact resulting
		# capture kits before timing, using published pages and the original guard.
		site._prewarm_captivity_atlases(capture_appearances, false)
		var occupied := {}
		for index in range(int(site.crowd.soldier_count())):
			var state: Dictionary = site.soldier_state(index)
			occupied[Vector2i(floori(float(state.px)), floori(float(state.py)))] = true
		# An actual forward soldier starts at the enemy's legal outer edge.
		# This establishes physical contact before peaceful 60x game time can
		# consume the whole deadline; combat_left is set only by real combat.
		var forward := -1
		for owner in site.person_owners():
			if owner.faction_id == 0 and not site.team_record(owner.formation_index).is_empty():
				forward = int(owner.combat_units.keys().back())
				break
		var contact := Vector2i(-1, -1)
		var opponent := -1
		for owner in site.person_owners():
			if owner.faction_id != 1: continue
			for index: int in owner.combat_units:
				var body: Dictionary = site.soldier_state(index)
				var cell := Vector2i(floori(float(body.px)), floori(float(body.py)))
				for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var adjacent := cell + direction
					if not occupied.has(adjacent) and lab.terrain.can_step(cell, adjacent):
						contact = adjacent
						opponent = index
						break
				if opponent >= 0: break
			if opponent >= 0: break
		if not _check(forward >= 0 and opponent >= 0, "D has a legal adjacent contact line", {"forward": forward, "opponent": opponent, "cell": contact}): return
		var prior: Dictionary = site.soldier_state(forward)
		if not _check(site.set_soldier_fields(forward, {"px": contact.x + 0.5, "py": contact.y + 0.5}), "D original forward soldier occupies contact line"): return
		occupied.erase(Vector2i(floori(float(prior.px)), floori(float(prior.py))))
		occupied[contact] = true
		results.append({"D_contact_line": {"forward_id": site.crowd.person_ids()[forward], "opponent_id": site.crowd.person_ids()[opponent], "cell": contact}})
		var rear := Vector2i(-1, -1)
		for x in range(lab.terrain.size.x - 8):
			for y in range(lab.terrain.size.y):
				var cell := Vector2i(x, y)
				if not lab.terrain.is_walkable(cell) or occupied.has(cell): continue
				var legal := true
				var previous := cell
				for offset in range(1, 9):
					var next := cell + Vector2i.RIGHT * offset
					if occupied.has(next) or not lab.terrain.can_step(previous, next):
						legal = false
						break
					previous = next
				if legal:
					rear = cell
					break
			if rear.x >= 0: break
		if not _check(rear.x >= 0, "D has an unoccupied western rear corridor with eight legal rightward edges", rear): return
		var player: int = site.crowd.soldier_index(lab.character.person_id)
		if not _check(site.set_soldier_fields(player, {"px": rear.x + 0.5, "py": rear.y + 0.5}), "D player positioned at western rear"): return
		var player_owner: RefCounted = site.person_owner(lab.character.person_id)
		if not _check(site.set_formation_fields(player_owner.formation_index, {"cx": rear.x + 0.5, "cy": rear.y + 0.5, "goal_x": rear.x + 0.5, "goal_y": rear.y + 0.5, "ai_enabled": false}), "D player team stays manual behind strong side"): return
	_begin_event_model(site)
	var initial_items: int = lab.terrain.site.item_records.size()
	var initial_locations := _item_location_report()
	if not _check(initial_locations.ok, "large deployment items have exactly one original location", initial_locations): return
	var equipment_mix := {}
	for owner in site.person_owners():
		for index: int in owner.combat_units:
			var person: Dictionary = owner.person(index)
			var appearance: Dictionary = SiteRuntime.equipment_appearance(lab.terrain, person.holder, owner.combat_hot_get(index, &"appearance", {}))
			var key := "%s | %s | %s" % [str(appearance.get("body", -1)), str(appearance.get("parts", {}).get("weapon", "none")), str(appearance.get("parts", {}).get("armor", "none"))]
			equipment_mix[key] = int(equipment_mix.get(key, 0)) + 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	var csv := FileAccess.open(output_root.path_join("large_" + fixture + ".csv"), FileAccess.WRITE)
	var headings := PackedStringArray(["action_seconds", "game_seconds", "pending_deaths", "item_count", "event_mean_ms", "event_max_ms", "host_mean_ms", "host_max_ms"])
	for index in range(40): headings.append("stat_" + str(index))
	if csv != null: csv.store_csv_line(headings)
	var start_game := _game_time()
	var game_elapsed := 0.0
	var elapsed := 0.0
	var next_sample := 0.0
	var busy_load_checked := false
	var pending_since := {}
	var fought := false
	var first_combat_action_seconds := -1.0
	var first_combat_game_seconds := -1.0
	var disengaged := false
	var timings: Array[float] = []
	var duration := 120.0 if fixture == "B" else 300.0
	while (elapsed < duration if fixture == "B" else game_elapsed < duration):
		var started := Time.get_ticks_usec()
		lab._advance_action_time(DT)
		timings.append(float(Time.get_ticks_usec() - started) / 1000.0)
		elapsed += DT
		game_elapsed = _game_time() - start_game
		if not fought and float(lab.terrain.site.combat_left) > 0.0:
			first_combat_action_seconds = elapsed
			first_combat_game_seconds = game_elapsed
			fought = true
		if fixture == "D" and fought and not busy_load_checked:
			var live_hash: int = site.crowd.state_hash()
			var rejected: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
			if not _check(not rejected.ok and rejected.code == "BUSY" and site.crowd.state_hash() == live_hash, "D refuses load during combat without changing native state", rejected): return
			busy_load_checked = true
		for identity: int in lab.site_controller._pending_deaths:
			if not pending_since.has(identity): pending_since[identity] = elapsed
			if elapsed - float(pending_since[identity]) > float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 1.0:
				var stuck: Dictionary = lab.site_controller.person_actions._person(identity)
				_check(false, "new death settles within down pose plus one action second", {"person_id": identity, "pending_seconds": elapsed - float(pending_since[identity]),
					"timer": lab.site_controller._pending_deaths[identity], "pending_capture": site.has_pending_capture(identity),
					"hp": stuck.get("hp"), "moving": stuck.get("moving"), "cell": stuck.get("cell"),
					"loot_settled": lab.site_controller.person_actions._body_get(stuck, "loot_settled") if not stuck.is_empty() else null,
					"native": site.soldier_state(int(site.crowd.soldier_index(identity))) if site.contains_person(identity) else {},
					"last_refused_step": lab.get_meta(&"last_refused_result", {})})
				return
		for identity: int in pending_since.keys():
			if not lab.site_controller._pending_deaths.has(identity): pending_since.erase(identity)
		if elapsed + 0.000001 >= next_sample:
			if not _compare_event_model(site, elapsed): return
			var sampled: PackedFloat64Array = site.crowd.stats()
			var row := PackedStringArray([str(elapsed), str(game_elapsed), str(lab.site_controller._pending_deaths.size()), str(lab.terrain.site.item_records.size()),
				str(float(site.event_cost_total_us) / float(maxi(1, int(site.event_cost_count))) / 1000.0), str(float(site.event_cost_max_us) / 1000.0),
				str(float(lab.crowd_host_cost_total_us) / float(maxi(1, lab.crowd_host_cost_count)) / 1000.0), str(float(lab.crowd_host_cost_max_us) / 1000.0)])
			for value: float in sampled: row.append(str(value))
			if csv != null:
				csv.store_csv_line(row)
				csv.flush()
			next_sample += 5.0
		if fixture == "D" and fought:
			var weak_active := 0
			for owner in site.person_owners():
				if owner.faction_id != 1: continue
				for index: int in owner.combat_units:
					if owner.combat_can_act(index): weak_active += 1
			if weak_active == 0 and float(lab.terrain.site.combat_left) <= 0.0 and lab.site_controller.supply_save_guard().ok:
				disengaged = true
				break
		if timings.size() % 60 == 0: await process_frame
	var stats: PackedFloat64Array = site.crowd.stats()
	if csv != null: csv.close()
	var costs := {"event_count": site.event_cost_count, "event_mean_ms": float(site.event_cost_total_us) / float(maxi(1, int(site.event_cost_count))) / 1000.0,
		"event_max_ms": float(site.event_cost_max_us) / 1000.0, "host_count": lab.crowd_host_cost_count,
		"host_mean_ms": float(lab.crowd_host_cost_total_us) / float(maxi(1, lab.crowd_host_cost_count)) / 1000.0, "host_max_ms": float(lab.crowd_host_cost_max_us) / 1000.0,
		"host_scope": "supply, outside actors, original shared life-order-family tail and crowd event commit; native simulation excluded"}
	results.append({"large_run": {"fixture": fixture, "action_seconds": elapsed, "game_seconds": game_elapsed, "stats_40": Array(stats), "events": site.event_counts.duplicate(), "equipment_mix": equipment_mix, "costs": costs,
		"first_combat_action_seconds": first_combat_action_seconds, "first_combat_game_seconds": first_combat_game_seconds}})
	var total_ms := 0.0
	for value: float in timings: total_ms += value
	timings.sort()
	results.append({"summary": {"fixture": fixture, "action_seconds": elapsed, "game_seconds": game_elapsed,
		"step_count": timings.size(), "step_total_ms": total_ms, "step_mean_ms": total_ms / float(timings.size()),
		"step_p50_ms": timings[maxi(0, ceili(float(timings.size()) * 0.5) - 1)],
		"step_p95_ms": timings[maxi(0, ceili(float(timings.size()) * 0.95) - 1)],
		"step_p99_ms": timings[maxi(0, ceili(float(timings.size()) * 0.99) - 1)], "step_max_ms": timings.back(),
		"timing_scope": "full TerrainLab action step CPU time, excluding rendering and test assertions; nearest-rank percentiles",
		"costs": costs, "stats_a": Array(stats.slice(0, 18)), "stats_c": Array(stats.slice(33, 40))}})
	_write_result() # Preserve all completed-loop costs before any later gate can fail.
	if not _compare_event_model(site, elapsed): return
	_check(stats[14] == 0.0 and stats[15] == 0.0 and stats[16] == 0.0, "large scenario simulation invariants", [stats[14], stats[15], stats[16]], false)
	if fixture == "B":
		for kind in [0, 1, 4, 10]:
			_check(int(site.event_counts.get(kind, 0)) > 0, "large B required event " + str(kind), site.event_counts.get(kind, 0), false)
	else:
		if not _check(disengaged and game_elapsed <= 300.0, "large D disengages within 300 GAME seconds", {"action_seconds": elapsed, "game_seconds": game_elapsed, "combat_left": lab.terrain.site.combat_left, "guard": lab.site_controller.supply_save_guard(), "fighting": stats[4]}): return
		var player_state: Dictionary = site.soldier_state(int(site.crowd.soldier_index(lab.character.person_id)))
		if not _check(float(player_state.hp) > 0.0 and float(player_state.ko) <= 0.0 and not bool(player_state.captive), "D rear player remains alive, conscious and free", player_state): return
		if not _check(lab.site_controller._pending_deaths.is_empty(), "D death settlement queue is empty"): return
		for owner in site.person_owners():
			for index: int in owner.combat_units:
				if float(owner.combat_hot_get(index, &"hp")) <= 0.0:
					if not _check(not str(owner.combat_hot_get(index, &"remains_id", "")).is_empty(), "D dead original person has remains container", owner.combat_identity(index)): return
		if not await _baseline_roundtrip(): return
		site = lab.crowd_site
	if not _compare_original_people(site): return
	var final_locations := _item_location_report()
	_check(final_locations.ok and int(initial_locations.ammo) == int(final_locations.ammo) + int(site.event_counts.get(10, 0)), "large unique item locations and shot ammunition conservation", {"initial": initial_locations, "final": final_locations, "shots": site.event_counts.get(10, 0)}, false)
	_check(lab.terrain.site.item_records.size() == initial_items, "large scenario item identities conserved", {"initial": initial_items, "final": lab.terrain.site.item_records.size()}, false)
	_check(float(costs.event_mean_ms) <= 0.1 and float(costs.event_max_ms) <= 2.0, "event commit average <= 0.1 ms and maximum <= 2 ms", costs, false)
	_check(float(costs.host_mean_ms) <= 0.3, "all non-native crowd host work average <= 0.3 ms per step", costs, false)
	_write_result()
	lab.queue_free()
	await process_frame
	print("GATE FAIL: large fixture " if failed else "GATE OK: large fixture ", fixture, " ", checks, " checks")
	quit(2 if failed else 0)

func _begin_event_model(site: Node) -> void:
	event_people.clear()
	event_fields_error.clear()
	event_rows = 0
	for owner in site.person_owners():
		for index: int in owner.combat_units:
			var values: PackedFloat64Array = site.crowd.get_soldier_state(index)
			var refs: PackedInt64Array = site.crowd.soldier_refs(index)
			event_people[int(refs[0])] = {"down": values[0] > 0.0 and values[3] > 0.0, "dead": values[0] <= 0.0,
				"captive": bool(values[6]), "guard": int(refs[1]), "formation": owner.formation_index}
	site.events_received.connect(_observe_events)


func _observe_events(events: PackedInt64Array) -> void:
	if not event_fields_error.is_empty(): return
	for offset in range(0, events.size(), 4):
		var kind := int(events[offset])
		var identity := int(events[offset + 1])
		var other := int(events[offset + 2])
		var formation := int(events[offset + 3])
		var valid: bool = kind >= 0 and kind <= 10 and formation >= 0 and formation < lab.crowd_site.teams.size()
		if kind in [7, 8, 9]: valid = valid and identity == -1
		else: valid = valid and event_people.has(identity) and int(event_people.get(identity, {}).get("formation", -1)) == formation
		if kind in [1, 2, 5, 8, 9, 10]: valid = valid and other == -1
		elif kind in [3, 4, 7]: valid = valid and event_people.has(other)
		else: valid = valid and (other == -1 or event_people.has(other))
		if not valid:
			event_fields_error = {"kind": kind, "person": identity, "other": other, "formation": formation}
			return
		event_rows += 1
		if not event_people.has(identity): continue
		var state: Dictionary = event_people[identity]
		if bool(state.dead) and kind in [0, 1, 2, 4]:
			event_fields_error = {"kind": kind, "person": identity, "reason": "duplicate death or life event after death"}
			return
		match kind:
			0:
				state.dead = true
				state.down = false
				state.captive = false
				state.guard = -1
			1: state.down = true
			2: state.down = false
			4:
				state.captive = true
				state.guard = other
			5:
				state.captive = false
				state.guard = -1


func _compare_event_model(site: Node, elapsed: float) -> bool:
	if not _check(event_fields_error.is_empty(), "native event fields, deployed references and death ordering", {"action_seconds": elapsed, "events": event_rows, "difference": event_fields_error}): return false
	var mismatch := {}
	var excluded := 0
	var people := 0
	for owner in site.person_owners():
		for index: int in owner.combat_units:
			var identity: int = owner.combat_identity(index)
			var actual: PackedFloat64Array = site.crowd.get_soldier_state(index)
			var refs: PackedInt64Array = site.crowd.soldier_refs(index)
			var expected: Dictionary = event_people[identity]
			if bool(expected.dead) != (actual[0] <= 0.0) or bool(expected.down) != (actual[0] > 0.0 and actual[3] > 0.0) or bool(expected.captive) != bool(actual[6]) or bool(actual[6]) and int(expected.guard) != int(refs[1]):
				mismatch = {"person": identity, "event_model": expected, "native_life": [actual[0], actual[3], actual[6]], "guard": refs[1]}
				break
			people += 1
			if lab.site_controller._pending_deaths.has(identity) or site.has_pending_capture(identity):
				excluded += 1
				continue
			var relation: Dictionary = lab.terrain.site.captivity.get(str(identity), {})
			if bool(actual[6]) != not relation.is_empty() or not relation.is_empty() and int(relation.guard_id) != int(refs[1]):
				mismatch = {"person": identity, "site_relation": relation, "native_captive": actual[6], "native_guard": refs[1]}
				break
		if not mismatch.is_empty(): break
	return _check(mismatch.is_empty() and people == site.crowd.soldier_count(), "every person event model and committed Site captivity match native", {"action_seconds": elapsed, "people": people, "site_pending_excluded": excluded, "difference": mismatch})


func _compare_original_people(site: Node) -> bool:
	# This is a documented synchronization point after the measured action loop.
	# Compare original records/actors against packed native values, including guard
	# references. No additional step or new person is created by this observation.
	if not _check(site.pending_captivity.is_empty(), "all capture/escape events committed before person comparison", site.last_event_error): return false
	var before: int = site.crowd.state_hash()
	var sync: Dictionary = site.sync_to_site()
	if not _check(sync.ok and site.crowd.state_hash() == before, "synchronization preserves native state", sync): return false
	var count := 0
	var mismatch := {}
	var roster_fields := {"hp": 0, "stun": 1, "grace": 2, "ko": 3, "getup": 4, "exchange_stagger": 5,
		"escape_t": 12, "face": 16, "exchange_cooldown": 17, "ranged_cooldown": 18, "exchange_skill_cooldown": 19,
		"knock_t": 20, "act_t": 21}
	for owner in site.person_owners():
		var formation: PackedFloat64Array = site.crowd.get_formation_state(owner.formation_index)
		for index: int in owner.combat_units:
			var identity: int = owner.combat_identity(index)
			var hot: PackedFloat64Array = site.crowd.get_soldier_state(index)
			var row: Dictionary
			var fields := roster_fields
			if owner.actors.has(index):
				var actor: TerrainTestCharacter = owner.actors[index]
				row = actor.capture_state()
				fields = {"hp": 0, "stun": 1, "stun_grace": 2, "knockout_left": 3, "exchange_stagger": 5,
					"exchange_cooldown": 17, "ranged_cooldown": 18, "exchange_skill_cooldown": 19}
				# Exchange timers are actor properties; its legacy capture schema omits them.
				for field: String in fields: row[field] = actor.get(field)
			else: row = owner.records[index]
			for field: String in fields:
				if not row.has(field) or float(row[field]) != hot[int(fields[field])]:
					mismatch = {"person_id": identity, "field": field, "original": row.get(field), "native": hot[int(fields[field])]}
					break
			if mismatch.is_empty() and (bool(row.captive) != bool(hot[6]) or float(row.fatigue) != formation[2] or float(row.fatigue_rest) != formation[3]):
				mismatch = {"person_id": identity, "field": "captive/fatigue"}
			var relation: Dictionary = lab.terrain.site.captivity.get(str(identity), {})
			var refs: PackedInt64Array = site.crowd.soldier_refs(index)
			if mismatch.is_empty() and hot[0] > 0.0 and (bool(hot[6]) != not relation.is_empty() or not relation.is_empty() and refs[1] >= 1 and int(relation.guard_id) != refs[1]):
				mismatch = {"person_id": identity, "field": "captivity/guard", "relation": relation, "native_guard": refs[1]}
			if not mismatch.is_empty(): break
			count += 1
		if not mismatch.is_empty(): break
	if not _check(mismatch.is_empty() and count == site.crowd.soldier_count(), "all original people match native life, timers, fatigue, captivity and guard", {"people": count, "difference": mismatch}): return false
	var captivity: Dictionary = Store._validate_captivity(lab.terrain, lab.terrain.site)
	return _check(captivity.ok, "formal SiteStore captivity validation after large run", captivity)


func _ordinary_state_check(before: Dictionary) -> bool:
	var expected := {"actors": before.actors, "armies": before.armies, "item_records": before.item_records}
	var actual := {"actors": lab.terrain.site.actors, "armies": lab.terrain.site.armies, "item_records": lab.terrain.site.item_records}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	for entry: Dictionary in [{"name": "ordinary_before.json", "value": expected}, {"name": "ordinary_after.json", "value": actual}]:
		var file := FileAccess.open(output_root.path_join(entry.name), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(entry.value, "\t", true, true))
			file.close()
	var difference := _first_difference(expected, actual)
	return _check(difference.is_empty(), "ordinary actor, roster and item snapshots unchanged by roundtrip", difference)

func _first_difference(expected: Variant, actual: Variant, path: String = "state") -> String:
	if (expected is int or expected is float) and (actual is int or actual is float):
		return "" if absf(float(expected) - float(actual)) <= 0.000001 else "%s expected=%s actual=%s" % [path, str(expected), str(actual)]
	if expected is Dictionary and actual is Dictionary:
		for key: Variant in expected:
			if not actual.has(key): return "%s.%s missing; expected=%s" % [path, str(key), str(expected[key])]
			var difference := _first_difference(expected[key], actual[key], path + "." + str(key))
			if not difference.is_empty(): return difference
		for key: Variant in actual:
			if not expected.has(key): return "%s.%s unexpected=%s" % [path, str(key), str(actual[key])]
		return ""
	if expected is Array and actual is Array:
		if expected.size() != actual.size(): return "%s size expected=%d actual=%d" % [path, expected.size(), actual.size()]
		for index in range(expected.size()):
			var difference := _first_difference(expected[index], actual[index], path + "[%d]" % index)
			if not difference.is_empty(): return difference
		return ""
	return "" if expected == actual else "%s expected=%s actual=%s" % [path, str(expected), str(actual)]

func _game_time() -> float:
	return (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0

func _item_location_report() -> Dictionary:
	var holders: Array[Dictionary] = [lab.terrain.site.depot_items]
	var ammunition := int(lab.terrain.site.inventory.get("arrow", 0)) + int(lab.terrain.site.inventory.get("bolt", 0))
	for owner in lab.crowd_site.person_owners():
		for index: int in owner.combat_units:
			var person: Dictionary = owner.person(index)
			holders.append(person.holder)
			ammunition += int(person.cargo.get("arrow", 0)) + int(person.cargo.get("bolt", 0))
	for container: Dictionary in lab.terrain.site.ground_loot.values():
		holders.append(container)
		ammunition += int(container.cargo.get("arrow", 0)) + int(container.cargo.get("bolt", 0))
	for vehicle: Dictionary in lab.terrain.site.get("vehicles", {}).values():
		holders.append(vehicle.holder)
		ammunition += int(vehicle.cargo.get("arrow", 0)) + int(vehicle.cargo.get("bolt", 0))
	var locations := {}
	for holder: Dictionary in holders:
		for identity: String in holder.item_ids:
			if locations.has(identity): return {"ok": false, "item": identity, "first": locations[identity], "second": holder.holder}
			locations[identity] = holder.holder
			if lab.terrain.site.item_records.get(identity, {}).get("holder", "") != holder.holder: return {"ok": false, "item": identity, "holder": holder.holder, "record": lab.terrain.site.item_records.get(identity, {})}
	return {"ok": locations.size() == lab.terrain.site.item_records.size(), "locations": locations.size(), "records": lab.terrain.site.item_records.size(), "ammo": ammunition}

func _restart_snapshot() -> Dictionary:
	var site: Node = lab.crowd_site
	var people := {}
	for owner in site.person_owners():
		for index: int in owner.combat_units:
			var person: Dictionary = owner.person(index)
			people[str(person.person_id)] = {"hot": Array(site.crowd.get_soldier_state(index)).slice(0, 25), "refs": Array(site.crowd.soldier_refs(index)), "holder": person.holder.duplicate(true), "cargo": person.cargo.duplicate(true)}
	var formations: Array = []
	for index in range(int(site.crowd.formation_count())):
		formations.append({"hot": Array(site.crowd.get_formation_state(index)), "refs": Array(site.crowd.formation_refs(index)), "info": Array(site.crowd.formation_info(index))})
	return {"hash": str(site.crowd.state_hash()), "person_ids": Array(site.crowd.person_ids()), "people": people, "formations": formations,
		"stats": Array(site.crowd.stats()), "captivity": lab.terrain.site.captivity.duplicate(true), "item_records": lab.terrain.site.item_records.duplicate(true),
		"ground_loot": lab.terrain.site.ground_loot.duplicate(true), "controlled_person_id": lab.controlled_person_id(), "team_count": site.command_teams().size()}

func _baseline_roundtrip() -> bool:
	var controller: Node = lab.site_controller
	var baseline: String = controller.save_root.path_join("baseline.json")
	if not _check(not FileAccess.file_exists(baseline), "baseline is created once and never overwritten", baseline): return false
	var started := Time.get_ticks_usec()
	var saved: Dictionary = controller.save_to(baseline)
	var save_ms := float(Time.get_ticks_usec() - started) / 1000.0
	if not _check(saved.ok, "save immutable baseline after disengagement", saved): return false
	var reference := _restart_snapshot()
	var checksum := FileAccess.get_sha256(baseline)
	var reader := FileAccess.open(baseline, FileAccess.READ)
	var bytes := reader.get_length()
	reader.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	var exported := output_root.path_join("baseline.json")
	if not _check(not FileAccess.file_exists(exported) and DirAccess.copy_absolute(ProjectSettings.globalize_path(baseline), ProjectSettings.globalize_path(exported)) == OK, "export immutable baseline for independent process fixtures"): return false
	var envelope := {"baseline_sha256": checksum, "baseline_source": exported, "baseline_user_path": baseline, "save_ms": save_ms, "save_bytes": bytes, "reference": reference}
	var file := FileAccess.open(output_root.path_join("baseline_reference.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope, "\t", true, true))
	file.close()
	if not _check(FileAccess.get_sha256(baseline) == checksum, "baseline hash unchanged before same-process load", checksum): return false
	started = Time.get_ticks_usec()
	var loaded: Dictionary = controller.load_from(baseline)
	var load_ms := float(Time.get_ticks_usec() - started) / 1000.0
	results.append({"saveload": {"save_ms": save_ms, "load_ms": load_ms, "save_bytes": bytes, "baseline_sha256": checksum, "baseline": baseline}})
	if not _check(loaded.ok, "same-process baseline load", loaded): return false
	return await _after_baseline_load(reference, baseline, checksum)

func _after_baseline_load(reference: Dictionary, baseline: String, checksum: String) -> bool:
	if not _check(OS.get_cmdline_user_args().has("--site-test-ui"), "--site-test-ui required for loaded UI command choices"): return false
	# Presentation event caches (hot[25:27]) intentionally restart on load; they
	# are not serialized simulation state. Check the plan's rebuilt first frame.
	var loaded_site: Node = lab.crowd_site
	loaded_site.render(0.0)
	var render_difference := {}
	for index in range(int(loaded_site.crowd.soldier_count())):
		var view: PackedFloat32Array = loaded_site.crowd.soldier_view(index)
		if view[0] != view[9] * 64.0 or view[1] != view[10] * 64.0 or (view[5] <= 0.0 and int(view[3]) != 9) or (view[5] > 0.0 and view[6] > 0.0 and int(view[3]) not in [9, 10]):
			render_difference = {"person": Array(loaded_site.crowd.soldier_refs(index))[0], "view": Array(view)}
			break
	if not _check(render_difference.is_empty(), "first rebuilt frame uses native positions and dead or KO poses", render_difference): return false
	var actual := _restart_snapshot()
	if not _check(actual.hash == reference.hash, "first-frame native hash exactly matches baseline", {"expected": reference.hash, "actual": actual.hash}): return false
	if not _check(_stats_equal(PackedFloat64Array(reference.stats), PackedFloat64Array(actual.stats)), "baseline stats A and C exactly match"): return false
	reference = reference.duplicate(true)
	reference.erase("stats")
	actual.erase("stats")
	var difference := _first_difference(reference, actual)
	if not _check(difference.is_empty(), "every native person, formation, original holder and custody record matches baseline", difference): return false
	var site: Node = lab.crowd_site
	lab.site_controller._sync_trial_team_choices()
	if not _check(lab.site_controller.trial_command_team.item_count == int(reference.team_count), "loaded UI command team count matches baseline", lab.site_controller.trial_command_team.item_count): return false
	var player: int = site.crowd.soldier_index(lab.controlled_person_id())
	var before: Dictionary = site.soldier_state(player)
	lab.movement_input_enabled = true
	var event := InputEventKey.new()
	event.keycode = KEY_D
	event.pressed = true
	lab._unhandled_input(event)
	if not _check(lab._held_directions.has(KEY_D), "loaded player accepts original keyboard input"): return false
	for tick in range(60):
		lab._advance_action_time(DT)
		if tick % 15 == 0: await process_frame
	event = InputEventKey.new()
	event.keycode = KEY_D
	event.pressed = false
	lab._unhandled_input(event)
	if not _check(not lab._held_directions.has(KEY_D), "loaded player releases original keyboard input"): return false
	var after: Dictionary = site.soldier_state(player)
	var distance := Vector2(float(before.px), float(before.py)).distance_to(Vector2(float(after.px), float(after.py)))
	if not _check(distance > 3.0, "loaded player host input moves more than three cells in two action seconds", {"distance_cells": distance, "before": [before.px, before.py], "after": [after.px, after.py]}): return false
	var current_path: String = lab.site_controller.save_path
	var current_sha := FileAccess.get_sha256(current_path) if FileAccess.file_exists(current_path) else ""
	var current_mtime := FileAccess.get_modified_time(current_path) if FileAccess.file_exists(current_path) else 0
	if current_mtime > 0: await create_timer(1.05).timeout
	for tick in range(900):
		lab._advance_action_time(DT)
		lab.site_controller.finish_tick()
		if tick % 30 == 0: await process_frame
	if not _check(site.crowd.person_ids() == PackedInt64Array(reference.person_ids), "30 action seconds after load preserve all person identities"): return false
	var stats: PackedFloat64Array = site.crowd.stats()
	if not _check(stats[14] == 0.0 and stats[15] == 0.0 and stats[16] == 0.0, "post-load 30-second invariants remain zero", [stats[14], stats[15], stats[16]]): return false
	if not _check(FileAccess.file_exists(current_path) and FileAccess.get_sha256(current_path) != current_sha and FileAccess.get_modified_time(current_path) > current_mtime and FileAccess.get_sha256(baseline) == checksum, "autosave changes current.json with newer modification time while baseline stays immutable", {"current": current_path, "before_mtime": current_mtime, "after_mtime": FileAccess.get_modified_time(current_path), "message": lab.site_controller.message.text, "save_elapsed": lab.site_controller._save_elapsed, "combat_left": lab.terrain.site.combat_left, "paused": lab.terrain.site.paused, "auto_blocked": lab.site_controller._auto_save_blocked, "supply_guard": lab.site_controller.supply_save_guard(), "baseline_sha256": FileAccess.get_sha256(baseline)}): return false
	return true

func _restart_run() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--crowd-reference")
	if not _check(at >= 0 and at + 1 < args.size(), "restart requires immutable reference fixture"): return
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[at + 1]))
	if not _check(decoded is Dictionary and decoded.has("reference") and decoded.has("baseline_sha256"), "restart reference has expected shape"): return
	var baseline: String = lab.site_controller.save_root.path_join("baseline.json")
	if not _check(FileAccess.get_sha256(baseline) == str(decoded.baseline_sha256), "baseline hash unchanged before independent process load", {"expected": decoded.baseline_sha256, "actual": FileAccess.get_sha256(baseline)}): return
	var ordinary := args.has("--grid")
	if ordinary and not _check(lab.crowd_site == null, "fresh ordinary process starts without crowd owner"): return
	if args.has("--crowd-corrupt-load"):
		var bad: Dictionary = Store._read(baseline)
		bad.payload.state.crowd.blob_sha256 = "0".repeat(64)
		var body := JSON.stringify(bad.payload, "", true, true)
		var bad_path: String = lab.site_controller.save_root.path_join("bad_crowd.json")
		var file := FileAccess.open(bad_path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
		file.close()
		var original: Dictionary = lab.terrain.site.duplicate(true)
		var refused: Dictionary = lab.site_controller.load_from(bad_path)
		if not _check(not refused.ok and lab.crowd_site == null and lab.terrain.site == original and bool(lab.site_controller._auto_save_blocked) and FileAccess.get_sha256(baseline) == str(decoded.baseline_sha256), "ordinary bad crowd load preserves original mode, Site and baseline", refused): return
	else:
		var started := Time.get_ticks_usec()
		var loaded: Dictionary = lab.site_controller.load_from(baseline)
		if not _check(loaded.ok and lab.crowd_site != null and lab.crowd_site.active, "independent process activates saved native world", {"code": loaded.get("code", ""), "load_ms": float(Time.get_ticks_usec() - started) / 1000.0, "ordinary_startup": ordinary}): return
		if not await _after_baseline_load(decoded.reference, baseline, str(decoded.baseline_sha256)): return
	_write_result()
	lab.queue_free()
	await process_frame
	print("GATE OK: independent C3 restart and mode boundary")
	quit(0)
