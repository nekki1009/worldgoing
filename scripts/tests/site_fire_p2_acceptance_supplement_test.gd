extends "res://scripts/tests/site_fire_shared_step_test.gd"
## OUTPUT_ONLY / NOT_RUN. Inherits the real Lab tree and original shared step.
## Never edits a released trajectory, collision event, HP, heat or ammo after
## fixture genesis. The wall is paid/completed only through original Runtime.
const FireCollision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const SUPPLEMENT_OUT := "res://output/fire_implementation_20261006/p2_supplement"
var supplemental_evidence: Array[Dictionary] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	create_timer(120.0, true).timeout.connect(func() -> void: _finish_fire(false, "120-second supplement deadline"))
	_run.call_deferred()

func _finish_fire(ok: bool, reason: String) -> void:
	if fire_finished: return
	fire_finished = true
	for lab: TerrainLab in fire_labs:
		if not is_instance_valid(lab): continue
		if lab.terrain != null:
			for hook: StringName in [&"fire_event_guard", &"fire_pending_projectile_query"]: lab.terrain.remove_meta(hook)
		lab.free()
	fire_labs.clear()
	TerrainArmy.release_contact_source()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SUPPLEMENT_OUT))
	var file := FileAccess.open(SUPPLEMENT_OUT + "/acceptance_supplement_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": ok and not fire_failed, "checks": fire_checks, "reason": reason,
			"evidence": supplemental_evidence, "scope": "P2 real FIRE_ARROW obstruction and no-metadata history guards; no P3/P5/GPU/Native simulation claim"}, "\t"))
		file.close()
	print("SITE_FIRE_P2_ACCEPTANCE_SUPPLEMENT_", "PASS" if ok and not fire_failed else "FAIL", ": checks=", fire_checks, " ", reason)
	await process_frame
	quit(0 if ok and not fire_failed else 1)

func _arm_one_arrow(lab: TerrainLab, cell: Vector2i) -> bool:
	var actor := lab.character
	actor.combat_ability = 100.0
	actor.training = 100.0
	if not _check_fire(actor.place(cell, true), "Original archer starts on its legal original surface"): return false
	actor.item_state.equipped.erase("weapon")
	var made := Runtime.create_equipment(lab.terrain, actor.item_state, "p2_supplement_bow",
		{"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, actor.person_id, "weapon")
	if not _check_fire(made.ok, "Original item registry owns the one-shot archer bow"): return false
	actor.ammo_inventory.fire_arrow = 1 # Initial finite original cargo; no refill.
	return true

func _future_legal_wall(lab: TerrainLab, flight: Dictionary) -> Dictionary:
	# Read future chords of the immutable original shot, then choose a legal
	# full original wall cell. The next helper must construct its real geometry.
	var begin := float(flight.elapsed)
	for tick in range(1, ceili(float(flight.total) / FIRE_STEP)):
		var a := begin + tick * FIRE_STEP
		var b := a + FIRE_STEP
		if b >= float(flight.total): break
		var from := SiteCombatRules.fire_position(flight, a)
		var to := SiteCombatRules.fire_position(flight, b)
		var bounds := Rect2(Vector2(from.x, from.y), Vector2.ZERO).expand(Vector2(to.x, to.y)).grow(0.015)
		for y in range(floori(bounds.position.y), floori(bounds.end.y) + 1):
			for x in range(floori(bounds.position.x), floori(bounds.end.x) + 1):
				var cell := Vector2i(x, y)
				if cell.distance_squared_to(lab.character.terrain_cell) <= 2: continue
				var placement := Runtime.building_cells(lab.terrain, "stone_wall", cell, Vector2i.ONE, {"owner_faction": 1})
				if not placement.ok: continue
				var hit := FireCollision.segment_prism_contact(from, to, Rect2(Vector2(cell), Vector2.ONE),
					float(lab.terrain.effective_height(cell)), float(lab.terrain.effective_height(cell)) + 2.0, 0.015)
				if not hit.is_empty(): return {"cell": cell, "from": from, "to": to, "begin": a, "end": b}
	return {}

func _paid_supplement_wall(data: TerrainData, cell: Vector2i) -> String:
	var options := {"owner_faction": 1}
	var placement := Runtime.building_cells(data, "stone_wall", cell, Vector2i.ONE, options)
	if not _check_fire(placement.ok, "Original wall layout admits the future crossing cell"): return ""
	var cells: Array[int] = []
	cells.assign(placement.cells)
	var requested := Runtime.request_build(data, "stone_wall", cells, Callable(), options)
	if not _check_fire(requested.ok, "Original depot pays the future blocking wall"): return ""
	var key := str(requested.feature)
	var wall: Dictionary = data.site.features[key]
	var task := {"version": 2, "zone": -1, "target": "feature:" + key, "action": "construct",
		"work_cell": int(wall.entrance), "cell": int(wall.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	Runtime._feature_work(data, key, float(wall.work), Callable(), Callable(), task, {}, 20, 1)
	return key

func _real_arrow_stopped_before_house() -> bool:
	var lab := _new_fire_lab()
	var data := lab.terrain
	var house_key := _formal_feature(data, "house", Vector2i(20, 20))
	var house: Dictionary = data.site.features[house_key]
	var house_before := var_to_bytes(house)
	if not _arm_one_arrow(lab, Vector2i(21, 15)): return false
	var target := {"type": "structure", "feature_id": house_key, "part_id": "body"}
	if not _check_fire(lab.issue_fire_order(lab.character.person_id, lab.character, target, "FIRE_ARROW").ok,
		"AT-01 original clear-lane FIRE_ARROW order targets original paid wooden house"): return false
	for tick in range(90):
		if not _shared(lab): return false
		if lab.ranged_shots == 1: break
	if not _check_fire(lab.ranged_shots == 1 and lab.character.ammo_inventory.fire_arrow == 0
		and lab.fire_projectiles.size() == 1 and lab.fire_impact_recorder.is_empty(),
		"AT-01 original arrow really released before any obstruction is installed"): return false
	if not _check_fire(lab.stop_fire_order(lab.character.person_id, lab.character).ok, "Original cease command preserves the already paid flight"): return false
	var flight: Dictionary = lab.fire_projectiles[0]
	var immutable := var_to_bytes([flight.origin, flight.velocity, flight.total, flight.profile, flight.projectile_id, flight.spawn_action])
	var crossing := _future_legal_wall(lab, flight)
	if not _check_fire(not crossing.is_empty(), "Actual immutable bow flight has a future legal original wall prism crossing"): return false
	var wood_before := int(data.site.inventory.wood)
	var stone_before := int(data.site.inventory.stone)
	var wall_key := _paid_supplement_wall(data, crossing.cell)
	if wall_key.is_empty(): return false
	var wall: Dictionary = data.site.features[wall_key]
	if not _check_fire(wall.stage == "complete" and Runtime.validate_feature_layout(data, wall).ok
		and int(data.site.inventory.stone) < stone_before and int(data.site.inventory.wood) <= wood_before,
		"AT-01 original request_build and completion pay and publish the new complete stone wall"): return false
	lab._capture_fire_static()
	var collider := {}
	for value: Dictionary in lab._fire_static_buckets.get(crossing.cell, []):
		if str(value.get("feature", "")) == wall_key: collider = value; break
	if not _check_fire(not collider.is_empty() and not FireCollision.segment_prism_contact(crossing.from, crossing.to,
		collider.bounds, float(collider.lower), float(collider.upper), 0.015).is_empty(),
		"The actual authored wall part, not a synthetic collider, intersects the already released arrow"): return false
	for tick in range(120):
		if lab.ranged_resolutions == 1: break
		if not _shared(lab): return false
	if not _check_fire(lab.ranged_resolutions == 1 and lab.fire_impact_recorder.size() == 1 and lab.fire_projectiles.is_empty(),
		"Original physical first-contact owner resolves exactly one terminal"): return false
	var event: Dictionary = lab.fire_impact_recorder[0]
	if not _check_fire(event.type == "structure" and str(event.feature) == wall_key and str(event.part) == str(collider.part)
		and float(event.remaining_heat_budget) > 0.0 and var_to_bytes(house) == house_before
		and not data.site.fire.units.has("feature:" + house_key + ":body") and data.site.fire.contacts.is_empty(),
		"AT-01 live ember stops at real stone wall; rear wood receives zero heat/contact/kinetic damage"): return false
	if not _shared(lab, 66): return false
	if not _check_fire(var_to_bytes(house) == house_before and data.site.fire.units.is_empty() and data.site.fire.contacts.is_empty()
		and immutable == var_to_bytes([flight.origin, flight.velocity, flight.total, flight.profile, flight.projectile_id, flight.spawn_action])
		and lab.ranged_shots == 1 and lab.character.ammo_inventory.fire_arrow == 0,
		"Delayed heat callbacks cannot bypass the wall, alter the trajectory, or replenish ammunition"): return false
	supplemental_evidence.append({"case": "AT-01", "wall": wall_key, "house": house_key,
		"actual_contact": event, "wall_cell": crossing.cell, "shot": flight.projectile_id,
		"boundary": "Legal wall completion after real release bypasses preventive LOS rejection while preserving physical first-contact oracle"})
	return true

func _history_live_bytes(lab: TerrainLab) -> PackedByteArray:
	var rosters: Array = []
	for team: TerrainArmy in lab.combat_armies:
		rosters.append([team.get_instance_id(), team.capture_combat_state(), team.cells, team.moving_to,
			team.move_progress, team.move_duration, team.facing, team._reserved_cells])
	return var_to_bytes([lab.terrain.get_instance_id(), lab.terrain.site, lab.terrain.flags, lab.terrain.static_blocked,
		lab.terrain.navigation_revision, lab.character.get_instance_id(), lab.character.capture_state(), lab.character.item_state,
		lab.character.ammo_inventory, lab.npc.get_instance_id(), lab.npc.capture_state(), lab.npc.item_state, rosters,
		lab.fire_projectiles, lab.fire_reservations, lab.fire_impact_recorder, lab.fire_action_cursor, lab._fire_release_sequence,
		lab.ranged_shots, lab.ranged_resolutions, lab._fire_unsaved, lab._replay_target,
		lab._cold_replay_id, lab._cold_replay_signature, lab._cold_replay_target,
		lab._cold_replay_lab.get_instance_id() if is_instance_valid(lab._cold_replay_lab) else 0])

func _busy_unchanged(result: Dictionary, label: String, lab: TerrainLab, before: PackedByteArray,
		path: String, saved: PackedByteArray) -> bool:
	return _check_fire(not result.ok and str(result.code) == "BUSY" and _history_live_bytes(lab) == before
		and FileAccess.get_file_as_bytes(path) == saved and not lab.terrain.has_meta(&"fire_event_guard"), label)

func _history_guard_matrix(lab: TerrainLab, path: String, saved: PackedByteArray, phase: String) -> bool:
	var data := lab.terrain
	for hook: StringName in [&"fire_event_guard", &"fire_pending_projectile_query"]: data.remove_meta(hook)
	var before := _history_live_bytes(lab)
	if not _busy_unchanged(SiteStore.fire_event_guard(data), phase + " Runtime history blocks Store without live metadata", lab, before, path, saved): return false
	if not _busy_unchanged(SiteStore.save(data, path), phase + " Store refuses actual preexisting valid save overwrite", lab, before, path, saved): return false
	if not _busy_unchanged(lab.site_controller.save_to(path), phase + " original Controller save preserves live owners and saved bytes", lab, before, path, saved): return false
	if not _busy_unchanged(lab.site_controller.load_from(path), phase + " actual Controller load refuses valid baseline before any live replacement", lab, before, path, saved): return false
	var detached := Env.navigation_for_state(data, data.site.duplicate(true))
	var detached_before := var_to_bytes(detached.site)
	if not _busy_unchanged(SiteStore._validate_state(detached, detached.site), phase + " detached Store validation cannot drop history before restoration", lab, before, path, saved): return false
	var slot := RegionSaveSlot.new()
	var called := [0]
	slot.cold_site_advance = func(_source: TerrainData, _target: float) -> Dictionary:
		called[0] += 1
		return Runtime.fail("TEST_UNEXPECTED_COLD_CALLBACK")
	var region_before := var_to_bytes([slot.control, slot._prepared, slot._marker])
	var target_seconds := Runtime.now(data) * 60.0 + 10.0
	if not _busy_unchanged(slot._settle_cold_candidate(detached, target_seconds), phase + " Region rejects before cloning or calling cold clock", lab, before, path, saved): return false
	if not _check_fire(called[0] == 0 and var_to_bytes([slot.control, slot._prepared, slot._marker]) == region_before
		and var_to_bytes(detached.site) == detached_before, "Original Region control, journal and detached fire source are unchanged"): return false
	if not _busy_unchanged(lab.advance_cold_site(detached, target_seconds), phase + " original Lab refuses cold-child creation for detached history", lab, before, path, saved): return false
	var was_restore := lab.restore_only
	lab.restore_only = true # Exercise the original replay API in its explicitly required mode.
	var replayed := lab.replay_site_to(target_seconds, 1000, 1)
	lab.restore_only = was_restore
	if not _busy_unchanged(replayed, phase + " original replay rejects before cursor, debt or world time changes", lab, before, path, saved): return false
	var clean := _new_fire_lab()
	var clean_before := _history_live_bytes(clean)
	clean.restore_only = true
	if not _busy_unchanged(clean.restore_original_site(detached), phase + " incoming original restore rejects unsaved history", lab, before, path, saved): return false
	clean.restore_only = false
	clean.bind_terrain(detached)
	lab.bind_terrain(clean.terrain)
	if not _check_fire(_history_live_bytes(clean) == clean_before and _history_live_bytes(lab) == before
		and var_to_bytes(detached.site) == detached_before, "Both incoming and outgoing original bind guards preserve their exact worlds"): return false
	var crowd := preload("res://scripts/terrain_lab/crowd_site.gd").new()
	crowd.lab = clean # Clean live source isolates admission of the detached history candidate.
	var admitted: Dictionary = crowd.siege_admission_guard(detached)
	var prepared: Dictionary = crowd.prepare_load(detached)
	var untouched := crowd.crowd == null and not crowd.active and crowd._staged_data == null
	crowd.free()
	if not _busy_unchanged(admitted, phase + " Native admission rejects history-only candidate without metadata", lab, before, path, saved): return false
	if not _busy_unchanged(prepared, phase + " Native prepare_load cannot allocate a replacement owner for history", lab, before, path, saved): return false
	if not _check_fire(untouched and _history_live_bytes(clean) == clean_before and var_to_bytes(detached.site) == detached_before,
		"Native handoff rejection preserves clean live owners, candidate bytes and unallocated native state"): return false
	supplemental_evidence.append({"case": "SV-09", "phase": phase, "no_metadata": true,
		"live_sha256": before.hex_encode().sha256_text(), "save_sha256": FileAccess.get_sha256(path), "native": admitted})
	lab._wire_fire_ranged() # Restore the original live hooks for subsequent real shared steps.
	return true

func _actual_history_guards() -> bool:
	var lab := _new_fire_lab()
	var data := lab.terrain
	var cell := Vector2i(20, 20)
	if not _arm_one_arrow(lab, Vector2i(20, 15)): return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SUPPLEMENT_OUT))
	var path := SUPPLEMENT_OUT + "/valid_before_fire.json"
	lab.site_controller.save_root = SUPPLEMENT_OUT
	lab.site_controller.save_path = path
	if not _check_fire(lab.site_controller.save_to(path).ok, "Original Controller creates a valid actual pre-fire baseline"): return false
	lab.site_controller._auto_save_blocked = true
	if not _check_fire(SiteStore.load_site(path).ok, "Original Store independently accepts that unmodified baseline"): return false
	var saved := FileAccess.get_file_as_bytes(path)
	var resource := _add_test_timber(data, cell) # Explicit original resource genesis after the valid baseline is established.
	var target := {"type": "ground", "cell": [cell.x, cell.y]}
	if not _check_fire(lab.issue_fire_order(lab.character.person_id, lab.character, target, "FIRE_ARROW").ok, "Real one-arrow order starts the guarded fire history"): return false
	for tick in range(180):
		if not _shared(lab): return false
		if float(data.site.get("fire", {}).get("units", {}).get("resource:" + resource, {}).get("heat", 0.0)) > 0.0: break
	if not _check_fire(lab.ranged_shots == 1 and lab.ranged_resolutions == 1 and lab.character.ammo_inventory.fire_arrow == 0
		and Runtime.fire_active(data) and float(data.site.fire.units.get("resource:" + resource, {}).get("heat", 0.0)) > 0.0,
		"Actual original terminal creates active heat on the real original timber resource"): return false
	if not _check_fire(lab.stop_fire_order(lab.character.person_id, lab.character).ok
		and lab.issue_fire_order(lab.character.person_id, lab.character, target, "NORMAL").ok
		and lab.stop_fire_order(lab.character.person_id, lab.character).ok, "Original command returns to inactive NORMAL without deleting history"): return false
	if not _history_guard_matrix(lab, path, saved, "active_heat"): return false
	for tick in range(900):
		if not _shared(lab): return false
		if not Runtime.fire_active(data) and float(data.site.combat_left) == 0.0: break
	if not _check_fire(not Runtime.fire_active(data) and float(data.site.fire.units["resource:" + resource].heat) == 0.0
		and float(data.site.combat_left) == 0.0 and lab.fire_projectiles.is_empty() and lab.fire_reservations.is_empty()
		and not lab.character.ranged_enabled and lab.character.ranged_ammo_mode == "NORMAL",
		"Actual shared cooling and grace expiry leave history with no heat, flight, command or combat-timer substitute"): return false
	return _history_guard_matrix(lab, path, saved, "cooled_history_combat_zero")

func _run() -> void:
	if not _real_arrow_stopped_before_house(): _finish_fire(false, "AT-01 actual obstructed FIRE_ARROW"); return
	if not _actual_history_guards(): _finish_fire(false, "SV-09 original no-metadata guard matrix"); return
	_finish_fire(not fire_failed, "P2 actual first-contact wall and original guarded history entries")
