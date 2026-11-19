extends "res://scripts/tests/site_fire_lab_ui_test.gd"
## UNRUN full M1 fixture leaf. Every heat unit must originate in a real arrow.
## Uses the existing test-Window signals and original shared single-step entry.

func _initialize() -> void:
	create_timer(600.0, true).timeout.connect(func() -> void: _finish(false, "600-second full M1 functional deadline"))
	_run.call_deferred()

func _scene_contract() -> bool:
	var data := lab.terrain
	if not _check(lab.army.combat_units.size() == 100 and lab.opposing_army.combat_units.size() == 100 and lab.third_army.combat_units.size() == 2, "M1 has 100 original bow rows, 100 original infantry rows and two original support rows"): return false
	var identities := {}
	for team: TerrainArmy in [lab.army, lab.opposing_army, lab.third_army]:
		for index in range(team.combat_units.size()):
			var mid := team.combat_identity(index)
			var row: Dictionary = team.combat_units[index]
			if not _check(mid > 0 and not identities.has(mid) and row.item_state.holder == "person:%d" % mid and data.is_walkable(team.cells[index]), "Every M1 person has its original unique holder and legal deployed cell"): return false
			identities[mid] = true
			if team == lab.army and not _check(not team.ranged_profile(index, "NORMAL").is_empty() and not team.ranged_profile(index, "FIRE_ARROW").is_empty() and int(row.cargo.arrow) == 20 and int(row.cargo.fire_arrow) == 20, "Every original archer supports both modes with finite personal ammunition"): return false
	if not _check(lab.third_army.faction_id == lab.opposing_army.faction_id and lab.third_army.role == "work", "Finite original suppression workers belong to the defender"): return false
	# Genesis must honor the original enemy threat radius along the whole
	# shortest east approach, including either tie-break of the last turn.
	var threats := {}
	for y: int in [21, 22]:
		for x: int in range(20, 25):
			var approach := Vector2i(x, y)
			if not _check(data.is_walkable(approach) and not lab._fatigue_threat(approach, lab.third_army.faction_id, lab.third_army, 1, threats), "M1 original threat owner accepts each east work approach cell %s" % approach): return false
	var feature_ids: Dictionary = data.get_meta(&"fire_lab_features")
	var house: Dictionary = data.site.features[str(feature_ids.house)]
	var house_body: Dictionary = SiteRuntime.feature_geometry(data, house).parts.body
	var house_target := data.cell_from_index(int(house_body.cells[0]))
	for index: int in range(2, 10):
		if not _check(SiteCombatRules.ranged_in_range(lab.army.cells[index], house_target, float(lab.army.ranged_profile(index, "FIRE_ARROW").range)), "Every original house-facing M1 archer remains in the real profile range"): return false
	var gate: Dictionary = data.site.features[str(feature_ids.gate)]
	var gate_geometry := SiteRuntime.feature_geometry(data, gate)
	if not _check(feature_ids.size() == 4 and str(house.stage) == "complete" and str(gate.stage) == "complete" and str(gate.material) == "stone"
		and gate_geometry.parts.has("frame:left") and gate_geometry.parts.has("leaf:left") and gate_geometry.parts.has("frame:right") and gate_geometry.parts.has("leaf:right"), "Original paid stone gate keeps independent combustible leaf parts"): return false
	if not _check(SiteRuntime._fire_feature_descriptor(data, str(feature_ids.gate), "frame:left").is_empty() and not SiteRuntime._fire_feature_descriptor(data, str(feature_ids.gate), "leaf:left").is_empty(), "Stone frame cannot acquire wood fuel while original gate leaf can"): return false
	if not _check(int(data.site.inventory.stone) == 6 and int(data.site.inventory.wood) == 84, "All M1 buildings consumed the single original paid material stock"): return false
	if not _check(data.surface_types[data.index(Vector2i(18, 31))] == TerrainData.Surface.DIRT
		and data.surface_types[data.index(Vector2i(8, 36))] == TerrainData.Surface.WATER and data.water_kind[data.index(Vector2i(8, 36))] == 1
		and not data.is_walkable(Vector2i(8, 36)) and not data.resources_at.get(data.index(Vector2i(20, 20)), []).is_empty(), "Original owners provide bare soil, freshwater and combustible vegetation"): return false
	if not _check(not data.is_walkable(Vector2i(47, 45)) and not data.is_walkable(Vector2i(50, 45)) and data.is_walkable(Vector2i(48, 45)) and data.is_walkable(Vector2i(49, 45))
		and data.effective_height(Vector2i(48, 43)) == 0 and data.effective_height(Vector2i(48, 44)) == 1 and data.can_step(Vector2i(48, 43), Vector2i(48, 44)), "Original two-cell narrow passage crosses a real height difference on a legal ramp"): return false
	return _check(not SiteRuntime.fire_active(data) and lab.fire_projectiles.is_empty() and lab.fire_reservations.is_empty(), "Scene genesis contains no scripted heat or pre-launched projectile")

func _house_and_original_escape() -> bool:
	var controller := lab.site_controller
	var ui: Dictionary = controller._trial_fire_ui
	var house_id := str(lab.terrain.get_meta(&"fire_lab_house"))
	var house: Dictionary = lab.terrain.site.features[house_id]
	var source := lab.terrain.cell_from_index(int(house.entrance))
	var defender := lab.opposing_army
	var index := 99
	var identity := defender.combat_identity(index)
	var holder: Dictionary = defender.combat_units[index].item_state
	var original_order := defender.get_order_serial()
	if not _check(defender.cells[index] == source and defender.combat_order == TerrainArmy.CombatOrder.HOLD, "A real original defender starts at the house entrance"): return false
	if not _select_team(lab.army): return false
	ui.ammo.select(1)
	ui.target.select(1)
	var part: Dictionary = SiteRuntime.feature_geometry(lab.terrain, house).parts.body
	controller.select_cell(lab.terrain.cell_from_index(int(part.cells[0])))
	controller._refresh_trial_fire_targets()
	var selected := false
	for choice in range(ui.part.item_count):
		var target: Dictionary = ui.part.get_item_metadata(choice)
		if str(target.feature_id) == house_id and str(target.part_id) == "body": ui.part.select(choice); selected = true; break
	if not _check(selected, "Actual part selector contains the same original paid house body"): return false
	var ammo_before := 0
	for row: Dictionary in lab.army.combat_units: ammo_before += int(row.cargo.fire_arrow)
	var shots_before := lab.ranged_shots
	if not _press("TrialFirePause") or not _press("TrialFireIssue") or not _press("TrialFirePause"): return false
	var burning := false
	var stopped := false
	var committed_escape := false
	var completed_escape := false
	var actual_house_contact := false
	var key := SiteRuntime._fire_unit_key("feature", house_id, "body")
	for tick in range(1800):
		if not _single(): return false
		var unit: Dictionary = lab.terrain.site.get("fire", {}).get("units", {}).get(key, {})
		if str(unit.get("state", "")) == "BURNING": burning = true
		if burning and not stopped:
			if not _press("TrialFirePause") or not _press("TrialFireStop") or not _press("TrialFirePause"): return false
			stopped = true
		var to: Vector2i = defender.moving_to[index]
		if to != TerrainArmy.INVALID_CELL and defender._committed_intent_order(identity) == TerrainArmy.FIRE_HAZARD_STEP:
			if not _check(defender._cell_owners.get(defender.cells[index], -1) == index and defender._reserved_cells.has(to), "Actual hazard move owns both original source occupancy and destination reservation"): return false
			committed_escape = true
		if committed_escape and to == TerrainArmy.INVALID_CELL and defender.cells[index] != source:
			var snapshot := SiteRuntime.fire_hazard_snapshot(lab.terrain)
			completed_escape = SiteRuntime.fire_exposure_at(snapshot, defender.cells[index], float(lab.terrain.effective_height(defender.cells[index])) + 0.5) == 0.0
		if burning and completed_escape and lab.fire_projectiles.is_empty() and lab.fire_reservations.is_empty(): break
	for event: Dictionary in lab.fire_impact_recorder:
		if str(event.type) == "structure" and str(event.get("feature", "")) == house_id and str(event.get("part", "")) == "body": actual_house_contact = true
	var ammo_after := 0
	for row: Dictionary in lab.army.combat_units: ammo_after += int(row.cargo.fire_arrow)
	if not _check(burning and actual_house_contact and lab.ranged_shots > shots_before and ammo_before - ammo_after == lab.ranged_shots - shots_before, "Real paid arrows hit and ignite the paid wooden house; every original release debits once"): return false
	if not _check(committed_escape and completed_escape and is_same(holder, defender.combat_units[index].item_state) and defender.combat_order == TerrainArmy.CombatOrder.HOLD and defender.get_order_serial() == original_order, "Original hazard overlay reaches a cold legal endpoint without replacing the defender or HOLD command"): return false
	events.append({"m1_house": house_id, "shots": lab.ranged_shots - shots_before, "burning_seen": burning,
		"defender": identity, "source": [source.x, source.y], "escaped_to": [defender.cells[index].x, defender.cells[index].y], "action_cursor": lab.fire_action_cursor})
	return true

func _original_move_hold() -> bool:
	var team := lab.opposing_army
	if not _select_team(team): return false
	lab.site_controller.select_cell(Vector2i(34, 31))
	if not _press("TrialFirePause") or not _press("TrialTeamMove") or not _press("TrialFirePause"): return false
	if not _check(team.combat_order == TerrainArmy.CombatOrder.MOVE and team._combat_move_plan != null and team._combat_deployment_plan != null, "Real M1 MOVE button creates original plan and deployment owners"): return false
	var moved := false
	for tick in range(180):
		if not _single(): return false
		for index in range(team.combat_units.size()):
			if team.moving_to[index] != TerrainArmy.INVALID_CELL:
				if not _check(team._reserved_cells.has(team.moving_to[index]) and team._cell_owners.get(team.cells[index], -1) == index, "Real M1 MOVE reaches original committed reservation"): return false
				moved = true
		if moved: break
	if not _check(moved, "M1 MOVE actually advances at least one original member"): return false
	if not _press("TrialFirePause") or not _press("TrialTeamHold") or not _press("TrialFirePause"): return false
	return _check(team.combat_order == TerrainArmy.CombatOrder.HOLD, "Real M1 HOLD button stops the original tactical order")

func _run() -> void:
	var created := TerrainLab.create_fire_lab_fixture(root, 12345, false)
	if not _check(created.ok, "Original full M1 Lab fixture initializes"): _finish(false, str(created)); return
	lab = created.lab
	lab.set_process(false)
	if DisplayServer.get_name() != "headless":
		lab.site_test_window.open()
		lab.site_test_window.tabs.current_tab = 2
	if not _scene_contract(): _finish(false, "M1 scene topology and original owner census"); return
	if not _buttons_and_targets(): _finish(false, "real typed UI controls"); return
	if not await _real_arrow_suppress(): _finish(false, "real arrows and finite arrived SUPPRESS"); return
	if not _house_and_original_escape(): _finish(false, "real house ignition and original hazard move"); return
	if not await _capture_visual("house_hazard_complete"): _finish(false, "actual M1 house visual capture"); return
	if not _original_move_hold(): _finish(false, "actual original MOVE and HOLD"); return
	if not await _reset_and_boundary(): _finish(false, "M1 original isolated reset"); return
	if not _scene_contract(): _finish(false, "reset preserves complete M1 recipe"); return
	_finish(failures.is_empty(), "M1 scene/control/arrow/house/hazard/SUPPRESS leaf; UNRUN until actual Engine succeeds")

func _finish(ok: bool, reason: String) -> void:
	if finished: return
	finished = true
	paused = false
	if is_instance_valid(lab): lab.free()
	TerrainArmy.release_contact_source()
	var path := "res://output/fire_implementation_20261006/fire_m1_complete_result.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "failures": failures, "events": events,
		"scope": "M1 original 100 bow/100 infantry scene and real controls; no P4/P5/full P3/performance acceptance"}, "\t"))
	print("SITE_FIRE_M1_COMPLETE_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	quit(0 if ok else 1)
