extends "res://scripts/tests/site_building_crowd_integration_test.gd"
## CORE-P2-007 / OFFICE-ROOT-F02 regression, Crowd version. With the Crowd host
## active, the shared step accepts the native checked prefix and calls
## _advance_fatigue(seconds, true) once per frame. The original captive escort must
## advance exactly once per accepted interval (its scheduling cursor follows the
## shared game clock 1:1) and the escort must still deliver the first captive.
## Fixture: site_prison_crowd_corridor_test.gd. Needs --crowd-test/--crowd-atlas-root and a GPU.

func _run() -> void:
	deadline = Time.get_ticks_msec() + 220000
	var args := OS.get_cmdline_user_args()
	assert(args.has("--crowd-test") and args.has("--crowd-atlas-root") and not args.has("--crowd"))
	assert(DisplayServer.get_name() != "headless")
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var escort: SiteCaptiveEscort = controller.captive_escort
	var guard: TerrainTestCharacter = lab.character
	var guard_id := int(guard.person_id)
	var prison_key := _formal_feature(data, "prison", Vector2i(35, 35), Vector2i(3, 3))
	var layout := Runtime.prison_layout(data, prison_key)
	assert(layout.ok and layout.slots.size() == 4)
	var deployed := lab.deploy_trial_armies([
		{"faction": 2, "count": 1, "female_percent": 0, "attack": false, "ai_enabled": false, "spawn": Vector2i(34, 40)},
		{"faction": 2, "count": 1, "female_percent": 0, "attack": false, "ai_enabled": false, "spawn": Vector2i(38, 40)}])
	assert(deployed.ok, str(deployed))
	var originals: Array[TerrainArmy] = []
	var identities: Array[int] = []
	var holders: Array[Dictionary] = []
	var holder_values: Array[Dictionary] = []
	var cargos: Array[Dictionary] = []
	var cargo_values: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		if not team.has_army(): continue
		originals.append(team)
		team.set_process(false)
		team.combat_hot_set(0, &"hp", 63.0)
		team.combat_hot_set(0, &"ko", 30.0)
	assert(originals.size() == 2)
	for team: TerrainArmy in originals:
		var identity := team.combat_identity(0)
		identities.append(identity)
		var contact := team.cells[0] + (Vector2i.RIGHT if team.cells[0].x < 36 else Vector2i.LEFT)
		assert(guard.place(contact, true))
		var capture_started := actions.begin_capture(guard_id, identity, guard_id)
		assert(capture_started.ok, str(capture_started))
		actions.advance(4.0)
		var captured := actions.settle_after_contacts()
		assert(captured.size() == 1 and captured[0].ok, str(captured))
	# Both real captures are complete before recovery or native ownership transfer.
	assert(guard.place(Vector2i(36, 40), true))
	for team: TerrainArmy in originals:
		team.combat_hot_set(0, &"ko", 0.0)
		team.combat_hot_set(0, &"stun", 0.0)
		team.combat_hot_set(0, &"pose", "idle")
		team.combat_hot_set(0, &"age", 0.0)
		var row: Dictionary = team.combat_units[0]
		holders.append(row.item_state)
		holder_values.append(row.item_state.duplicate(true))
		cargos.append(row.cargo)
		cargo_values.append(row.cargo.duplicate(true))
		var appearance := Runtime.equipment_appearance(data, row.item_state, row.appearance)
		var started_at := Time.get_ticks_msec()
		var prepared: bool = await CrowdHost.prepare_captivity_recipe(lab, appearance)
		var preparation := {"ok": prepared, "person_id": team.combat_identity(0), "seconds": (Time.get_ticks_msec() - started_at) / 1000.0,
			"appearance": appearance, "recipe_key": Atlas._mixed_key(appearance), "directory": Atlas._mixed_directory(Atlas._mixed_key(appearance))}
		var report_path := "res://output/site_building_implementation_20261003/crowd_preparation_" + str(args[args.find("--crowd-test") + 1]) + "_person_" + str(team.combat_identity(0)) + ".json"
		assert(not FileAccess.file_exists(report_path))
		var report := FileAccess.open(report_path, FileAccess.WRITE)
		assert(report != null)
		report.store_string(JSON.stringify(preparation, "\t", true, true))
		report.close()
		print("SITE_PRISON_CROWD_PREPARATION ", JSON.stringify(preparation))
		assert(prepared, str(preparation))
	lab.crowd_site = CrowdHost.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	var imported := lab.deploy_trial_armies([{"faction": 1, "count": 1, "female_percent": 0,
		"attack": false, "ai_enabled": false, "spawn": Vector2i(20, 20)}])
	assert(imported.ok, str(imported))
	var host: Node = lab.crowd_site
	assert(host.active)
	var feeding_before := _feeding_owners(controller).duplicate()
	for at: int in range(identities.size()):
		assert(host.owns_original_team(originals[at]) and str(feeding_before[identities[at]]) == "person:%d" % guard_id)
		assert(is_same(actions._person(identities[at]).holder, holders[at]))
		assert(is_same(actions._person(identities[at]).cargo, cargos[at]))
	# Known production issue (reported 2026-10-09, not fixed here): in visual mode
	# SiteController._ecology_person_signature calls Node.get(key, default) on a combat
	# body and raises a SCRIPT ERROR. This escort regression does not test the ecology
	# panel, so the panel label is detached; every escort/clock assertion is unchanged.
	controller.ecology_status = null
	var escort_started := escort.begin_prison(guard_id, guard_id, prison_key)
	assert(escort_started.ok, str(escort_started))

	# --- regression: native checked prefix, exactly once per accepted interval ------
	# Diagnostic only: state around the first accepted Crowd frames (pre-step guards of
	# _finish_native_checked_body_prefixes) and the first latched shared-step fault.
	var state_line := func(label: String) -> String:
		return "%s fire_host_active=%s physical_ranged_enabled=%s exchange_enabled=%s pending=%s consuming=%s deferring=%s native_published=%s work_point_active=%s crowd_error=%s fault=%s" % [label,
			str(lab.crowd_site.fire_host_active()), str(lab.physical_ranged_enabled), str(lab.exchange_enabled),
			JSON.stringify(lab._region_point_pending.keys()), str(lab._region_point_consuming), str(lab._region_deferring_endpoint()),
			str(lab._native_begin_shared_window_prepared.get("published", false)), str(lab.crowd_site.work_fatigue_point_active()),
			JSON.stringify(lab.crowd_site.last_event_error), JSON.stringify(controller._original_step_fault)]
	for probe_frame: int in range(3):
		printerr("SITE_ESCORT_CROWD_PREFIX_PROBE " + str(state_line.call("before_%d" % probe_frame)))
		var probe_step: Dictionary = lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP)
		printerr("SITE_ESCORT_CROWD_PREFIX_PROBE result_%d %s" % [probe_frame, JSON.stringify(probe_step)])
		printerr("SITE_ESCORT_CROWD_PREFIX_PROBE " + str(state_line.call("after_%d" % probe_frame)))
	# Diagnostic only (option A): call each candidate that can latch a plain CLOCK_NOT_READY
	# directly, with the still-pending accepted interval. Reads/prepares only; results printed.
	var pend: Dictionary = lab._region_point_pending
	if not pend.is_empty():
		var a_begin := float(pend.get("fire_action_begin", 0.0))
		var a_end := float(pend.get("fire_action_end", 0.0))
		var g_secs := float(pend.get("game_end", 0.0)) - float(pend.get("game_begin", 0.0))
		printerr("SITE_ESCORT_CROWD_CANDIDATE interval begin=%f end=%f game_seconds=%f work_point_active=%s work_fatigue_tick=%s held_requests=%d" % [a_begin, a_end, g_secs,
			str(lab.crowd_site.work_fatigue_point_active()), str(lab.crowd_site._work_fatigue_tick), lab._shared_work_requests.size()])
		var c_training: Dictionary = controller.prepare_shared_native_training_requests(g_secs, float(data.site.get("combat_left", 0.0)))
		printerr("SITE_ESCORT_CROWD_CANDIDATE prepare_shared_native_training_requests " + JSON.stringify({"ok": c_training.get("ok"), "code": c_training.get("code"), "message": c_training.get("message")}))
		var c_point: Dictionary = lab._prepare_native_shared_point_finish(lab._shared_work_requests, a_begin, a_end, g_secs)
		printerr("SITE_ESCORT_CROWD_CANDIDATE _prepare_native_shared_point_finish " + JSON.stringify({"ok": c_point.get("ok"), "code": c_point.get("code"), "message": c_point.get("message")}))
		var priors: Array = []
		if bool(c_point.get("ok", false)):
			var c_checked: Dictionary = lab._check_original_shared_prefixes(lab._native_begin_shared_window_prepared.get("captured", {}), c_point.plan, c_point.requests, priors)
			printerr("SITE_ESCORT_CROWD_CANDIDATE _check_original_shared_prefixes " + JSON.stringify({"ok": c_checked.get("ok"), "code": c_checked.get("code"), "message": c_checked.get("message")}))
			var c_ready: Dictionary = lab.crowd_site.prepare_work_fatigue_point_finish(c_point.plan, c_point.requests, a_end - a_begin, g_secs)
			printerr("SITE_ESCORT_CROWD_CANDIDATE prepare_work_fatigue_point_finish " + JSON.stringify({"ok": c_ready.get("ok"), "code": c_ready.get("code"), "message": c_ready.get("message")}))
		else:
			printerr("SITE_ESCORT_CROWD_CANDIDATE _check_original_shared_prefixes/prepare_work_fatigue_point_finish skipped: point not ok")
		var c_supplies: Dictionary = controller.validate_native_sustain_point(lab._native_begin_shared_window_prepared.get("sustain", {}), priors)
		printerr("SITE_ESCORT_CROWD_CANDIDATE validate_native_sustain_point " + JSON.stringify({"ok": c_supplies.get("ok"), "code": c_supplies.get("code"), "message": c_supplies.get("message")}))
		printerr("SITE_ESCORT_CROWD_CANDIDATE after work_point_active=%s work_fatigue_tick=%s" % [str(lab.crowd_site.work_fatigue_point_active()), str(lab.crowd_site._work_fatigue_tick)])
	var clock := func() -> float: return (float(data.site.minute) + float(data.site.get("phase", 0.0))) * 60.0
	# Block of frames with the escort never due: its cursor must drop by exactly the
	# game time the accepted native intervals advanced (0 = skipped, 2x = double call).
	escort._check_left = 1000000.0
	var before: float = clock.call()
	for _frame: int in range(300):
		lab._advance_action_time(STEP)
	var elapsed: float = clock.call() - before
	var consumed := 1000000.0 - escort._check_left
	if elapsed <= 0.0:
		# Diagnostic only: report why the accepted shared step is not advancing the clock.
		var probe: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		printerr("SITE_ESCORT_CROWD_PREFIX_STEP_RESULT " + JSON.stringify(probe))
		printerr("SITE_ESCORT_CROWD_PREFIX_STATE crowd_active=%s fixed_steps=%s exchange=%s paused=%s region_pending=%s crossing_blocks=%s" % [str(lab.crowd_site.active), str(lab.fixed_action_steps_enabled), str(lab.exchange_enabled), str(data.site.get("paused", false)), str(controller.region_operation_pending()), str(controller.ground_crossing_blocks_clock())])
	print("SITE_ESCORT_CROWD_PREFIX_MEASURE elapsed_game_seconds=%f escort_cursor_consumed=%f" % [elapsed, consumed])
	assert(elapsed > 0.0, "Accepted native intervals advanced the shared game clock")
	assert(absf(consumed - elapsed) <= maxf(0.000001, elapsed * 0.000001), "Crowd native prefix advanced the escort exactly once per accepted interval")
	# Then the escort runs normally and still delivers the first captive.
	escort._check_left = 0.0
	var admitted := false
	for _frame: int in range(3600):
		lab._advance_action_time(STEP)
		if actions.prison_slot(identities[0]).ok:
			admitted = true
			break
	assert(admitted, "Escort still delivers the first captive with the Crowd host active")
	print("SITE_ESCORT_CROWD_PREFIX_REGRESSION_PASS: Crowd native prefix advances the original escort exactly once per accepted interval (%f game seconds over 300 frames); escort delivered the first captive" % elapsed)
	lab.free()
	quit()
