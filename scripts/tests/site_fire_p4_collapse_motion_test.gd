extends "res://scripts/tests/site_fire_building_parts_test.gd"
## Original paid wall, actual fire warning, Actor motion and original collapse sink.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	var file := FileAccess.open(OUTPUT + "/collapse_motion_result.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "evidence": evidence}, "\t"))
	print("SITE_FIRE_P4_COLLAPSE_MOTION_", "PASS" if ok else "FAIL", ": checks=", checks)
	await process_frame
	quit(0 if ok else 1)

func _moving_warning(early_lethal: bool) -> bool:
	var f := _fixture()
	var source := Vector2i(20, 20)
	var target := source + Vector2i.RIGHT
	var key := _paid_feature(f, "palisade", source, Vector2i(3, 1))
	if key.is_empty(): return false
	var feature: Dictionary = f.data.site.features[key]
	var part := "c:" + str(f.data.index(source))
	var maximum := float(SiteRuntime.feature_geometry(f.data, feature).parts[part].max_hp)
	var unit := _hot_feature(f, key, part)
	unit.profile = "WOOD_COMPONENT" # Isolated finite thermal genesis, never UI ignition proof.
	var unit_key := SiteRuntime._fire_unit_key("feature", key, part)
	f.lab.siege_apply_damage_batch({key + "|" + part: {"feature": key, "part": part, "damage": maximum * 0.68}}, {})
	for tick in range(30):
		_step(f, 0.2)
		if f.data.site.fire.collapse_warnings.has(unit_key): break
	var state: Dictionary = f.data.site.fire
	if not _check(state.collapse_warnings.has(unit_key) and float(feature.parts[part].hp) > 0.0
		and f.data.effective_height(source) == 2, "Actual thermal warning retains original paid wall support"): return false
	var warning: Dictionary = state.collapse_warnings[unit_key].duplicate(true)
	var actor := _actor_fixture(f, source)
	if not _check(actor.step(Vector2i.RIGHT), "Original wall-top Actor may evacuate during real warning"): return false
	_step(f, actor._movement_duration * 0.25)
	if not _check(actor.is_moving() and actor.movement_from_cell == source and actor.terrain_cell == target
		and actor.position != (Vector2(source) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		and state.collapse_warnings[unit_key] == warning and float(feature.parts[part].hp) > 0.0,
		"Real warning does not teleport or cancel original committed half-step"): return false
	if early_lethal:
		# Each completed original old-buffer fire step replaces the unit dictionary.
		unit = state.units[unit_key]
		var hp := actor.hp
		var fuel := int(unit.fuel_q)
		var result := f.lab.siege_apply_damage_batch({key + "|" + part: {
			"feature": key, "part": part, "damage": float(feature.parts[part].hp) + 1.0}}, {})
		if not _check(result.results[key + "|" + part].ok and float(feature.parts[part].hp) == 0.0
			and f.data.effective_height(source) == 0 and not actor.is_moving() and actor.terrain_cell == source
			and absf(hp - actor.hp - 30.0) < TOL and int(unit.fuel_q) == fuel and int(unit.debris_version) == 1
			and not state.collapse_warnings.has(unit_key) and state.collapse_receipts.size() == 1,
			"Early lethal original damage cancels invalid half-step and applies one original two-level fall immediately"):
			return false
		var after := actor.hp
		var receipt := var_to_bytes(state.collapse_receipts)
		f.lab.siege_apply_damage_batch({key + "|" + part: {"feature": key, "part": part, "damage": maximum}}, {})
		if not _check(actor.hp == after and var_to_bytes(state.collapse_receipts) == receipt and int(unit.fuel_q) == fuel,
			"Duplicate dead-part event cannot repeat original fall or finite debris"): return false
		while f.lab.fire_action_cursor < float(warning.due_step) / SiteRuntime.FIRE_HZ + 0.2:
			_step(f, STEP)
		if not _check(var_to_bytes(state.collapse_receipts) == receipt and state.collapse_warnings.is_empty(),
			"Old due warning after early lethal collapse cannot issue another structural receipt"): return false
	else:
		_step(f, actor._movement_duration - actor._movement_elapsed + 0.001)
		if not _check(not actor.is_moving() and actor.terrain_cell == target and f.data.effective_height(target) == 2
			and actor.position == (Vector2(target) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			and float(feature.parts[part].hp) > 0.0, "Original wall-top evacuation arrives before the finite warning deadline"): return false
		var position := actor.position
		var hp := actor.hp
		var thermal_loss := 0.0
		while f.lab.fire_action_cursor < float(warning.due_step) / SiteRuntime.FIRE_HZ + 0.2:
			# Stationary original wall-top oracle permits genuine adjacent heat, but no extra fall packet.
			var risk := SiteRuntime.fire_exposure_at(SiteRuntime.fire_hazard_snapshot(f.data), target, 2.0)
			thermal_loss += risk * STEP * float(SiteCombatRules.FIRE_BODY.hazard_hp_rate)
			_step(f, STEP)
		if not _check(float(feature.parts[part].hp) == 0.0 and actor.terrain_cell == target and actor.position == position
			and absf(hp - actor.hp - thermal_loss) < TOL and actor.knockout_left == 0.0 and float(actor.fire_body.burn_left) == 0.0 and f.data.effective_height(target) == 2 and state.collapse_receipts.size() == 1,
			"Due collapse changes only lost original source surface; escaped Actor does not fall or teleport", {"part_hp": feature.parts[part].hp, "actor_cell": actor.terrain_cell, "target": target, "position": actor.position, "expected_position": position, "hp": actor.hp, "before_hp": hp, "expected_thermal_loss": thermal_loss, "target_height": f.data.effective_height(target), "receipts": state.collapse_receipts, "knockout": actor.knockout_left, "units": state.units}): return false
	evidence.append({"case": "early_lethal_half_step" if early_lethal else "warning_evacuate_then_due",
		"warning": warning, "cursor": f.lab.fire_action_cursor, "hp": actor.hp, "original_collapse_receipts": state.collapse_receipts.duplicate(true)})
	_close(f)
	return true

func _run() -> void:
	if not _moving_warning(false): _finish(false, "real warning evacuation"); return
	if not _moving_warning(true): _finish(false, "early lethal original half-step collapse"); return
	_finish(not failed, "P4 bounded original Actor warning, evacuation, early lethal collapse and exact-once fall; no Army/Native/visual/performance claim")
