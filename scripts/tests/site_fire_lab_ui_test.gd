extends SceneTree
## OUTPUT_ONLY / NOT_RUN. Actual original test-Window button signals and original
## Lab fixture creation. Fire can enter solely through real original arrows.
const OUTPUT := "res://output/fire_implementation_20261006/fire_lab_ui_result.json"
var lab: TerrainLab
var checks := 0
var failures: Array[String] = []
var events: Array[Dictionary] = []
var finished := false

func _initialize() -> void:
	create_timer(240.0, true).timeout.connect(func() -> void: _finish(false, "240-second UI fixture deadline"))
	_run.call_deferred()

func _check(value: bool, text: String) -> bool:
	checks += 1
	if not value:
		failures.append(text)
		push_error("FIRE_LAB_UI_FAIL: " + text)
	return value

func _press(name: String) -> bool:
	var control := lab.site_test_window.find_child(name, true, false) as Button
	if not _check(control != null and not control.disabled, "Real enabled original Window button: " + name): return false
	control.pressed.emit()
	return true

func _select_team(team: TerrainArmy, index: int = 0) -> bool:
	var controller := lab.site_controller
	controller._sync_trial_team_choices()
	for choice in range(controller.trial_command_team.item_count):
		if int(controller.trial_command_team.get_item_metadata(choice)) == team.team_id:
			controller.trial_command_team.select(choice)
			controller._refresh_trial_fire_status()
			for shooter in range(controller._trial_fire_ui.shooter.item_count):
				if int(controller._trial_fire_ui.shooter.get_item_metadata(shooter)) == team.combat_identity(index):
					controller._trial_fire_ui.shooter.select(shooter)
					controller._refresh_trial_fire_status()
					return true
	return _check(false, "Original team and stable person appear in real UI choices")

func _single() -> bool:
	var at := lab.fire_action_cursor
	var pending := lab._action_time_remainder
	var game := SiteRuntime.now(lab.terrain)
	var world_paused := paused
	var site_paused := bool(lab.terrain.site.paused)
	if not _press("TrialFireSingleStep"): return false
	return _check(absf(lab.fire_action_cursor - at - TerrainLab.EXCHANGE_ACTION_STEP) < 0.000001
		and paused == world_paused and bool(lab.terrain.site.paused) == site_paused
		and lab._action_time_remainder == pending and SiteRuntime.now(lab.terrain) > game,
		"Single actual button consumes exactly one complete shared action interval and restores both pauses")

func _buttons_and_targets() -> bool:
	var controller := lab.site_controller
	var ui: Dictionary = controller._trial_fire_ui
	if not _check(not ui.debug.button_pressed and not ui.status.text.contains("heat"), "Unknown heat remains behind explicit full-observation checkbox"): return false
	if not _select_team(lab.army): return false
	if not _press("TrialFirePause"): return false # Original initial fixture is paused.
	if not _check(not paused and not bool(lab.terrain.site.paused), "Pause button uses original shared pause"): return false
	var house := str(lab.terrain.get_meta(&"fire_lab_house"))
	var feature: Dictionary = lab.terrain.site.features[house]
	var part: Dictionary = SiteRuntime.feature_geometry(lab.terrain, feature).parts.body
	for kind in range(4):
		ui.target.select(kind)
		var cell := lab.opposing_army.cells[0] if kind == 0 else (lab.terrain.cell_from_index(int(part.cells[0])) if kind == 1 else Vector2i(20, 20))
		controller.select_cell(cell)
		controller._refresh_trial_fire_targets()
		ui.ammo.select(0)
		var ammo: Dictionary = lab.army.combat_units[0].cargo.duplicate(true)
		if not _press("TrialFireIssue"): return false
		if not _check(lab.army.ranged_enabled and str(lab.army.ranged_target.type) == ["person", "structure", "ground", "area"][kind], "Real UI typed target reaches original ranged owner"): return false
		if not _press("TrialFireStop"): return false
		if not _check(not lab.army.ranged_enabled and lab.army.combat_units[0].cargo == ammo and lab.fire_reservations.is_empty(), "Stop before completed preparation never consumes own ammo"): return false
	ui.target.select(3)
	controller.select_cell(Vector2i(63, 63))
	ui.width.value = 2
	ui.height.value = 2
	var order := var_to_bytes([lab.army.ranged_enabled, lab.army.ranged_target, lab.army.ranged_order_serial])
	if not _press("TrialFireIssue"): return false
	if not _check(var_to_bytes([lab.army.ranged_enabled, lab.army.ranged_target, lab.army.ranged_order_serial]) == order, "Out-of-map UI area leaves original order untouched"): return false
	if not _select_team(lab.opposing_army): return false
	ui.ammo.select(1)
	ui.target.select(2)
	controller.select_cell(Vector2i(20, 20))
	var stock: Dictionary = lab.opposing_army.combat_units[0].cargo.duplicate(true)
	if not _press("TrialFireIssue"): return false
	return _check(not lab.opposing_army.ranged_enabled and lab.opposing_army.combat_units[0].cargo == stock,
		"Fire-arrow UI on original melee infantry is rejected without ammo mutation")

func _real_arrow_suppress() -> bool:
	var controller := lab.site_controller
	var ui: Dictionary = controller._trial_fire_ui
	if not _select_team(lab.army): return false
	ui.ammo.select(1)
	ui.target.select(2)
	var cell := Vector2i(20, 20)
	var resource := "%d:%d" % [SiteEnvironment.Kind.TIMBER, lab.terrain.index(cell)]
	var key := "resource:" + resource
	controller.select_cell(cell)
	var start_stock := 0
	for row: Dictionary in lab.army.combat_units: start_stock += int(row.cargo.fire_arrow)
	if not _press("TrialFireIssue") or not _press("TrialFirePause"): return false
	var burning := false
	for tick in range(1800):
		if not _single(): return false
		if str(lab.terrain.site.get("fire", {}).get("units", {}).get(key, {}).get("state", "")) == "BURNING": burning = true; break
	if not _check(burning and lab.ranged_shots > 0, "Only actual UI-released fire arrows ignite original timber"): return false
	var stock := 0
	for row: Dictionary in lab.army.combat_units: stock += int(row.cargo.fire_arrow)
	if not _check(start_stock - stock == lab.ranged_shots, "Each released arrow debits an original shooter's own finite cargo exactly once"): return false
	ui.debug.button_pressed = true
	ui.debug.toggled.emit(true)
	if not _check(ui.status.text.contains("heat"), "Explicit complete observation shows original heat"): return false
	if not await _capture_visual("real_arrow_fire"): return false
	if not _press("TrialFirePause") or not _press("TrialFireStop") or not _press("TrialFirePause"): return false
	for tick in range(180):
		if lab.fire_projectiles.is_empty(): break
		if not _single(): return false
	if not _check(lab.fire_projectiles.is_empty() and lab.fire_reservations.is_empty(), "Stopped order preserves all paid flights until terminal settlement"): return false
	var contact_seen := false
	for contact: Dictionary in lab.fire_impact_recorder:
		if str(contact.type) == "ground" and contact.get("cell") == cell: contact_seen = true
	if not _check(contact_seen, "Original impact receipts include actual timber contact"): return false
	if not _select_team(lab.third_army, 1): return false
	controller.select_cell(cell)
	if not _press("TrialSuppressCaptureTarget"): return false
	controller.select_cell(Vector2i(20, 21))
	var worker := lab.third_army.combat_identity(1)
	var holder: Dictionary = lab.third_army.combat_units[1].item_state
	var supply := int(holder.fire_lab_suppression_q)
	if not _press("TrialFirePause") or not _press("TrialSuppressBegin") or not _press("TrialFirePause"): return false
	if not _check(str(controller.person_actions.job_for(worker).get("kind", "")) == "fire_suppress" and holder.fire_lab_suppression_q == supply,
		"Real SUPPRESS button creates original job without arrival-time supply debit"): return false
	# Retain the original job object only as evidence; cancellation mutates it
	# before the owner removes its index. Do not reconstruct an erased job.
	var admitted_job: Dictionary = controller.person_actions._jobs.get(str(worker), {})
	var paid := false
	for tick in range(900):
		if not _single(): return false
		if int(holder.fire_lab_suppression_q) < supply: paid = true; break
		if not controller.person_actions.is_busy(worker): break
	if not paid: events.append(_suppress_failure_diagnostic(worker, admitted_job, "arrival"))
	if not _check(paid and ui.suppress_status.text.contains(str(worker)), "Original safe work slot consumes finite owner supply and UI shows same person"): return false
	if not _press("TrialSuppressCancel"): return false
	if not _check(not controller.person_actions.is_busy(worker), "Real cancel button releases original SUPPRESS job"): return false
	if not _press("TrialFirePause") or not _press("TrialSuppressBegin") or not _press("TrialFirePause"): return false
	var resumed_job: Dictionary = controller.person_actions._jobs.get(str(worker), {})
	for tick in range(1800):
		if not _single(): return false
		if not controller.person_actions.is_busy(worker):
			if not bool(SiteRuntime.fire_suppression_target(lab.terrain, key).get("complete", false)):
				events.append(_suppress_failure_diagnostic(worker, resumed_job, "completion"))
			break
	if not await _capture_visual("suppression_completed"): return false
	var unit: Dictionary = lab.terrain.site.fire.units[key]
	events.append({"shots": lab.ranged_shots, "remaining_fire_arrows": stock, "remaining_supply_q": holder.fire_lab_suppression_q,
		"target_state": unit.state, "target_heat": unit.heat, "action_cursor": lab.fire_action_cursor})
	return _check(float(unit.heat) <= SiteRuntime.FIRE_EPS and not controller.person_actions.is_busy(worker)
		and int(holder.fire_lab_suppression_q) >= 0 and int(holder.fire_lab_suppression_q) < supply,
		"Same original hot unit completes finite suppression and cooling without synthetic heat edits")

func _suppress_failure_diagnostic(worker: int, original_job: Dictionary, stage: String) -> Dictionary:
	# Read the retained original object so an already removed job still reports
	# its real cancellation result; never synthesize a job or alter the lease.
	var actions: RefCounted = lab.site_controller.person_actions
	var person: Dictionary = actions._person(worker, false)
	var result := {"suppress_failure_stage": stage, "worker": worker, "action_cursor": lab.fire_action_cursor,
		"job_still_indexed": actions.is_busy(worker), "job_phase": str(original_job.get("phase", "")),
		"job_paused": str(original_job.get("paused", "")), "job_cancelled": bool(original_job.get("cancelled", false)),
		"cancel_result": original_job.get("cancel_result", {}).duplicate(true), "job_token": int(original_job.get("job_token", -1)),
		"supply_q": int(original_job.get("supply_q", -1)), "committed_q": int(original_job.get("committed_q", -1)),
		"ui": str(lab.site_controller._trial_fire_ui.suppress_status.text)}
	if person.is_empty(): result["person_missing"] = true; return result
	var team: TerrainArmy = person.owner
	var index := int(person.unit)
	var cell: Vector2i = person.cell
	var moving_to: Vector2i = team.moving_to[index]
	var movement := team.suppress_approach_query(worker, int(original_job.get("job_token", -1)))
	result.merge({"cell": [cell.x, cell.y], "moving_to": [moving_to.x, moving_to.y], "hp": float(person.hp),
		"ko": float(person.ko), "hit": int(person.hit), "job_hp": float(original_job.get("executor_hp", -1.0)),
		"job_hit": int(original_job.get("executor_hit", -1)), "body_supply_q": int(person.holder.get("fire_lab_suppression_q", -1)),
		"holder_version": int(person.holder.get("version", -1)), "job_holder_version": int(original_job.get("executor_version", -1)),
		"order_serial": team.get_order_serial(), "job_order_serial": int(original_job.get("order_serial", -1)),
		"ranged_serial": team.ranged_order_serial, "job_ranged_serial": int(original_job.get("ranged_order_serial", -1)),
		"movement_ok": bool(movement.get("ok", false)), "movement_code": str(movement.get("code", "")),
		"movement_phase": str(movement.get("phase", "")), "route_status": str(movement.get("route_status", "")),
		"lease_matches": is_same(movement.get("lease"), original_job.get("lease")),
		"registry_matches": is_same(movement.get("registry"), original_job.get("registry")),
		"fire_risk": SiteRuntime.fire_hazard_at(lab.terrain, cell),
		"original_threat": lab._fatigue_threat(cell, team.faction_id, team, index, {})})
	var nearest := 2147483647
	var nearest_record := {}
	for enemy: TerrainArmy in lab.combat_armies:
		if not enemy.combat_enabled or enemy.faction_id == team.faction_id: continue
		for enemy_index in range(enemy.combat_units.size()):
			if not enemy.combat_can_act(enemy_index): continue
			for claim: Vector2i in [enemy.cells[enemy_index], enemy.moving_to[enemy_index]]:
				if claim == TerrainArmy.INVALID_CELL: continue
				var distance := absi(claim.x - cell.x) + absi(claim.y - cell.y)
				if distance >= nearest: continue
				nearest = distance
				nearest_record = {"person": enemy.combat_identity(enemy_index), "cell": [claim.x, claim.y], "manhattan": distance}
	result["nearest_awake_enemy_claim"] = nearest_record
	return result

func _reset_and_boundary() -> bool:
	var old := lab
	var old_data := lab.terrain
	var stock: int = old_data.site.item_records.size()
	var controller := lab.site_controller
	if not _check(not controller._save_path_guard(controller.save_path).ok, "Isolated fixture cannot overwrite a formal save path"): return false
	current_scene = lab
	controller._trial_fire_ui.fixture_seed.value = 9876
	if not _press("TrialFireResetFixture"): return false
	lab = current_scene as TerrainLab
	if not _check(lab != null and lab != old and lab.terrain != old_data and lab.terrain.seed_value == 9876
		and lab.fire_projectiles.is_empty() and lab.fire_reservations.is_empty() and not SiteRuntime.fire_active(lab.terrain),
		"Reset button replaces only isolated Lab using same original initializer and requested seed"): return false
	if not _check(old_data.site.item_records.size() == stock, "Reset does not mutate the discarded Site's registered inventory"): return false
	await process_frame
	if not _check(not is_instance_valid(old), "Old fixture and Window are released after successful replacement"): return false
	var regular := TerrainLab.new()
	var refused := regular.step_fire_lab_fixture()
	var reset_refused := regular.reset_fire_lab_fixture(1)
	regular.free()
	return _check(not refused.ok and not reset_refused.ok, "Ordinary Lab cannot call isolated step/reset adapters")

func _run() -> void:
	var created := TerrainLab.create_fire_lab_fixture(root, 12345, false)
	if not _check(created.ok, "Original Lab creates explicit isolated own-item fixture"): _finish(false, str(created)); return
	lab = created.lab
	lab.set_process(false) # The test drives only actual single-step button signals.
	if DisplayServer.get_name() != "headless":
		lab.site_test_window.open()
		lab.site_test_window.tabs.current_tab = 2
	if not _buttons_and_targets(): _finish(false, "buttons and typed targets"); return
	if not await _real_arrow_suppress(): _finish(false, "actual arrow / suppression UI"); return
	var reset_ok: bool = await _reset_and_boundary()
	if not reset_ok: _finish(false, "isolated reset boundary"); return
	_finish(failures.is_empty(), "Actual original fire Lab UI functional scope only")

func _finish(ok: bool, reason: String) -> void:
	if finished: return
	finished = true
	paused = false
	if is_instance_valid(lab): lab.free()
	TerrainArmy.release_contact_source()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "failures": failures, "events": events,
		"scope": "M1 original-UI arrow ignition / single-slot finite suppression / isolated full-step-reset; excludes P4/P5/GPU pixels/performance"}, "\t"))
	print("SITE_FIRE_LAB_UI_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _capture_visual(name: String) -> bool:
	if DisplayServer.get_name() == "headless": return true
	# Render the same paused original state; never advance action or game time.
	var cursor := lab.fire_action_cursor
	var page := lab.site_test_window.pages.command.get_parent() as ScrollContainer
	var control: Control = lab.site_controller._trial_fire_ui.wind if name == "weather_controls" else (lab.site_controller._trial_fire_ui.ammo if name == "real_arrow_fire" else lab.site_controller._trial_fire_ui.suppress_status)
	# Let deferred Window layout settle before choosing the capture scroll.
	await process_frame
	await process_frame
	page.ensure_control_visible(control)
	if name == "weather_controls": page.scroll_vertical = int(page.get_v_scroll_bar().max_value)
	await process_frame
	await RenderingServer.frame_post_draw
	var captured := root.get_texture().get_image()
	var folder := "res://output/fire_implementation_20261006/fire_lab_ui_visual"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var error := captured.save_png(folder.path_join(name + ".png")) if captured != null and not captured.is_empty() else ERR_INVALID_DATA
	var window_image := lab.site_test_window.get_texture().get_image()
	var window_error := window_image.save_png(folder.path_join(name + "_window.png")) if window_image != null and not window_image.is_empty() else ERR_INVALID_DATA
	return _check(error == OK and window_error == OK and lab.fire_action_cursor == cursor, "Actual original viewport and Window captures preserve completed action time: " + name)
