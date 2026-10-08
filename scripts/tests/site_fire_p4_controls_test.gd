extends "res://scripts/tests/site_fire_m1_complete_test.gd"
## Real original Window controls, finite original IGNITE job and weather history.

func _run() -> void:
	var created := TerrainLab.create_fire_lab_fixture(root, 12345, false)
	if not _check(created.ok, "Original P4 isolated Lab initializes"): _finish(false, "fixture"); return
	lab = created.lab
	lab.set_process(false)
	if DisplayServer.get_name() != "headless":
		lab.site_test_window.open()
		lab.site_test_window.tabs.current_tab = 2
	if not _scene_contract(): _finish(false, "original M1 topology"); return
	var ui: Dictionary = lab.site_controller._trial_fire_ui
	var cursor := lab.fire_action_cursor
	var game := SiteRuntime.now(lab.terrain)
	if not _press("TrialFirePause"): _finish(false, "unpause"); return
	ui.wind.select(1)
	ui.rain.select(1)
	if not _press("TrialFireWeather"): _finish(false, "weather button"); return
	var weather := SiteRuntime.fire_weather_at(lab.terrain, cursor)
	if not _check(float(weather.wind_x) == 1.0 and float(weather.rain) == 0.25 and lab.fire_action_cursor == cursor
		and SiteRuntime.now(lab.terrain) == game, "Real wind/rain controls publish only original completed weather input without advancing A/G"):
		_finish(false, "weather history"); return
	if not _press("TrialFirePause"): _finish(false, "weather capture pause"); return
	if not await _capture_visual("weather_controls"): _finish(false, "weather capture"); return
	if not _press("TrialFirePause"): _finish(false, "weather resume"); return
	ui.wind.select(0)
	ui.rain.select(0)
	if not _press("TrialFireWeather") or not _press("TrialFirePause"): _finish(false, "dry weather"); return
	if not _select_team(lab.third_army, 1): _finish(false, "original worker"); return
	ui.target.select(2)
	lab.site_controller.select_cell(Vector2i(20, 20))
	if not _press("TrialSuppressCaptureTarget"): _finish(false, "cold target"); return
	var executor := lab.third_army.combat_identity(1)
	var holder: Dictionary = lab.third_army.combat_units[1].item_state
	var supply := int(holder.fire_lab_ignition_q)
	var before := JSON.stringify(lab.terrain.site.get("fire", {}), "", false, true)
	if not _check(supply == 30720 and lab.site_controller._trial_fire_ui.suppress_binding.key == "resource:0:1300",
		"Real cold-target capture retains one original bounded ignition supply and target"): _finish(false, "target capture"); return
	lab.site_controller.select_cell(Vector2i(20, 21))
	if not _press("TrialFirePause") or not _press("TrialIgniteBegin"): _finish(false, "ignite control"); return
	var job: Dictionary = lab.site_controller.person_actions.job_for(executor)
	if not _check(job.get("fire_work_mode", "") == "IGNITE" and int(holder.fire_lab_ignition_q) == supply
		and JSON.stringify(lab.terrain.site.get("fire", {}), "", false, true) == before,
		"Real IGNITE control admits original job/lease without premature heat or supply debit"): _finish(false, "job admission"); return
	if not _press("TrialFirePause"): _finish(false, "pause"); return
	var burned := false
	for tick in range(900):
		if not _single(): _finish(false, "original shared work interval"); return
		var unit: Dictionary = lab.terrain.site.fire.units.get("resource:0:1300", {})
		burned = burned or str(unit.get("state", "")) == "BURNING"
		if burned and lab.site_controller.person_actions.job_for(executor).is_empty(): break
	if not _check(burned and lab.ranged_shots == 0 and int(holder.fire_lab_ignition_q) < supply
		and int(holder.fire_lab_ignition_q) > 0 and is_same(holder, lab.third_army.combat_units[1].item_state)
		and lab.site_controller.person_actions.job_for(executor).is_empty(),
		"Actual arrived finite IGNITE work burns original timber, ends job and retains original holder without any scripted heat or arrow"):
		_finish(false, "actual ignition"); return
	for tick in range(60):
		if not _single(): _finish(false, "original smoke boundary"); return
	if not _check(not lab.terrain.site.fire.smoke.is_empty() and lab.get_node("FirePresentation").get_parent() == lab,
		"Logical smoke and heat project through the one original Lab presentation canvas"): _finish(false, "smoke"); return
	if not await _capture_visual("ignite_work_completed"): _finish(false, "actual smoke/control capture"); return
	events.append({"case": "P4_real_UI_IGNITE_weather", "executor": executor, "spent_q": supply - int(holder.fire_lab_ignition_q),
		"shots": lab.ranged_shots, "smoke_cells": lab.terrain.site.fire.smoke.size(), "smoke": lab.terrain.site.fire.smoke.duplicate(true), "action_cursor": lab.fire_action_cursor})
	var house_id := str(lab.terrain.get_meta(&"fire_lab_house"))
	var house: Dictionary = lab.terrain.site.features[house_id]
	var roof: Dictionary = SiteRuntime.feature_geometry(lab.terrain, house).parts.roof
	if not _check(not roof.is_empty() and not roof.cells.is_empty(), "Original paid house exposes its roof part"): _finish(false, "roof target"); return
	if not _select_team(lab.army): _finish(false, "original archer"); return
	ui.ammo.select(1)
	ui.target.select(1)
	lab.site_controller.select_cell(lab.terrain.cell_from_index(int(roof.cells[0])))
	lab.site_controller._refresh_trial_fire_targets()
	var roof_selected := false
	for choice in range(ui.part.item_count):
		var target: Dictionary = ui.part.get_item_metadata(choice)
		if str(target.get("feature_id", "")) == house_id and str(target.get("part_id", "")) == "roof":
			ui.part.select(choice)
			roof_selected = true
			break
	if not _check(roof_selected, "Real original part selector targets the house roof"): _finish(false, "roof selector"); return
	var arrows_before := 0
	for row: Dictionary in lab.army.combat_units: arrows_before += int(row.cargo.fire_arrow)
	var shots_before := lab.ranged_shots
	if not _press("TrialFirePause") or not _press("TrialFireIssue") or not _press("TrialFirePause"):
		_finish(false, "roof fire order"); return
	var roof_key := SiteRuntime._fire_unit_key("feature", house_id, "roof")
	var roof_burning := false
	var shooters_stopped := false
	for tick in range(1800):
		if not _single(): _finish(false, "roof fire step"); return
		var unit: Dictionary = lab.terrain.site.fire.units.get(roof_key, {})
		roof_burning = roof_burning or str(unit.get("state", "")) == "BURNING"
		if roof_burning and not shooters_stopped:
			if not _press("TrialFirePause") or not _press("TrialFireStop") or not _press("TrialFirePause"):
				_finish(false, "stop roof volley"); return
			shooters_stopped = true
		if roof_burning: break
	var roof_contact := false
	for impact: Dictionary in lab.fire_impact_recorder:
		if str(impact.get("type", "")) == "structure" and str(impact.get("feature", "")) == house_id and str(impact.get("part", "")) == "roof":
			roof_contact = true
	var arrows_after := 0
	for row: Dictionary in lab.army.combat_units: arrows_after += int(row.cargo.fire_arrow)
	if not _check(roof_burning and roof_contact and lab.ranged_shots > shots_before
		and arrows_before - arrows_after == lab.ranged_shots - shots_before and shooters_stopped,
		"Actual finite fire arrows hit and ignite the original paid wooden roof part"):
		_finish(false, "roof ignition"); return
	var rain_cursor := lab.fire_action_cursor
	var rain_game_time := SiteRuntime.now(lab.terrain)
	ui.wind.select(1)
	ui.rain.select(1)
	if not _press("TrialFirePause") or not _press("TrialFireWeather"):
		_finish(false, "rain over burning roof"); return
	var rainy_weather := SiteRuntime.fire_weather_at(lab.terrain, lab.fire_action_cursor)
	var rainy_roof: Dictionary = lab.terrain.site.fire.units.get(roof_key, {})
	if not _check(float(rainy_weather.wind_x) == 1.0 and float(rainy_weather.rain) == 0.25
		and str(rainy_roof.get("state", "")) == "BURNING" and lab.fire_action_cursor == rain_cursor
		and SiteRuntime.now(lab.terrain) == rain_game_time,
		"Real east-wind/rain controls apply to the burning original roof without advancing its action or game time"):
		_finish(false, "rainy roof boundary"); return
	if not _press("TrialFirePause"): _finish(false, "rain capture pause"); return
	if not await _capture_visual("weather_controls"): _finish(false, "burning roof under rain capture"); return
	events.append({"case": "P4_real_roof_fire_under_rain", "house": house_id, "part": "roof", "weather": rainy_weather,
		"shots": lab.ranged_shots - shots_before, "spent_arrows": arrows_before - arrows_after,
		"unit": rainy_roof.duplicate(true), "action_cursor": lab.fire_action_cursor, "capture": "weather_controls"})
	_finish(failures.is_empty(), "P4 actual original IGNITE, roof-fire/rain controls and bounded smoke projection; no persistence/performance claim")

func _finish(ok: bool, reason: String) -> void:
	if finished: return
	finished = true
	paused = false
	if is_instance_valid(lab): lab.free()
	TerrainArmy.release_contact_source()
	var file := FileAccess.open("res://output/fire_implementation_20261006/fire_p4_controls_result.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "events": events, "failures": failures}, "\t"))
	print("SITE_FIRE_P4_CONTROLS_", "PASS" if ok else "FAIL", " checks=", checks)
	quit(0 if ok else 1)
