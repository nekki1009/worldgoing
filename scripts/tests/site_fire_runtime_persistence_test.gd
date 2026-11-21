extends "res://scripts/tests/site_fire_runtime_test.gd"
## Pure Runtime schema plus identical continuation through JSON.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	print("SITE_FIRE_RUNTIME_PERSISTENCE_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _json(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed if parsed is Dictionary else {}

func _same_fire(a: TerrainData, b: TerrainData, cursor: float) -> bool:
	var left := Runtime.capture_fire_snapshot(a, cursor)
	var right := Runtime.capture_fire_snapshot(b, cursor)
	return left.ok and right.ok and JSON.stringify(left.state) == JSON.stringify(right.state) \
		and JSON.stringify(a.site.changes) == JSON.stringify(b.site.changes)

func _store_roundtrip() -> bool:
	var data: TerrainData = TerrainGenerator.generate(0, 4106, {"size": Vector2i(64, 64)})
	SiteEnvironment.initialize(data, "site-fire-store-roundtrip")
	var state := Runtime._fire_state(data, 0.0)
	state.smoke = {"650:0": {"cell": 650, "layer": 0, "density": 4.0}}
	data.site.fire = state
	data.set_meta(&"fire_event_guard", func() -> Dictionary: return Runtime.ok("test owner approved settled snapshot"))
	var path := "user://site_fire_roundtrip_%d.json" % Time.get_ticks_usec()
	var saved := SiteStore.save(data, path)
	if not _check(saved.ok, "Original Store writes validated settled fire snapshot: " + str(saved)): return false
	var loaded := SiteStore.load_site(path)
	var captured := Runtime.capture_fire_snapshot(loaded.data, 0.0) if loaded.ok else Runtime.fail("LOAD_FAILED")
	var expected := Runtime.capture_fire_snapshot(data, 0.0)
	var result: bool = bool(loaded.get("ok", false)) and bool(captured.get("ok", false)) \
		and bool(expected.get("ok", false)) and JSON.stringify(captured.get("state", {})) == JSON.stringify(expected.get("state", {}))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return _check(result, "Original Store load validates and normalizes fire state for identical continuation: " + str(loaded))

func _roundtrip_and_rejections() -> bool:
	var data := _data()
	var cell := Vector2i(20, 20)
	var resource := _timber(data, cell)
	var key := "resource:" + resource
	if not _check(Runtime.fire_set_weather(data, 0.0, Vector2.RIGHT, 0.0).ok, "Original weather genesis"): return false
	if not _check(Runtime.fire_receive_impact(data, _payload(data, cell, 1, 0.0, 100.0, 100.0, 1.0)).ok, "Original finite contact and receipt"): return false
	if not _advance(data, 0.6): return false
	if not _check(Runtime.fire_set_weather(data, 0.6, Vector2.LEFT, 0.3).ok, "Original weather switch at real barrier"): return false
	var holder := Runtime.new_item_state("person:123")
	holder.fire_lab_suppression_q = 31
	var prepared := Runtime.fire_prepare_suppression(data, key, int(_unit(data, resource).generation), 0.6, 0.63, 30, holder, int(holder.version))
	if not _check(prepared.ok and Runtime.fire_commit_suppression(data, prepared).ok, "Original finite paid input commits before next thermal boundary"): return false
	if not _advance(data, 0.63): return false
	var live := var_to_bytes(data.site)
	var captured := Runtime.capture_fire_snapshot(data, 0.63)
	var capture_json := bool(captured.ok) and Runtime._fire_snapshot_json(captured.get("state", {}))
	var capture_pure := var_to_bytes(data.site) == live
	var capture_ok := bool(captured.get("ok", false)) and capture_json and capture_pure
	if not capture_ok: push_error("FIRE_CAPTURE_DIAGNOSTIC: " + str({"capture": captured.get("code", ""), "message": captured.get("message", ""), "json": capture_json, "pure": capture_pure, "state": captured.get("state", {}), "raw": data.site.get("fire", {})}))
	if not _check(capture_ok, "Capture is pure, preserves unconsumed input and emits JSON scalars"): return false
	var wire := _json(captured.state)
	if not _store_roundtrip(): return false
	var restored := _data()
	restored.resource_base = data.resource_base.duplicate(true)
	restored.site = data.site.duplicate(true)
	restored.site.erase("fire")
	Env.rebuild_indexes(restored)
	var validated := Runtime.validate_fire_snapshot(restored, wire, 0.63)
	if not _check(validated.ok and not restored.site.has("fire"), "JSON validation is pure and resolves original resource owners"): return false
	restored.site.fire = validated.state # Only this test's explicit original publication.
	var bads: Array[Dictionary] = []
	var bad: Dictionary = wire.duplicate(true); bad.owner_shadow = {}; bads.append(bad)
	bad = wire.duplicate(true); bad.step_index = 2; bads.append(bad)
	bad = wire.duplicate(true); bad.units[key].fuel_remainder_q = 1024; bads.append(bad)
	bad = wire.duplicate(true); bad.units[key].heat = NAN; bads.append(bad)
	bad = wire.duplicate(true); bad.units[key].profile = "TEST_HEAT_100"; bads.append(bad)
	bad = wire.duplicate(true); bad.receipt_ids["01"] = true; bads.append(bad)
	bad = wire.duplicate(true); bad.active.erase(key); bads.append(bad)
	bad = wire.duplicate(true); bad.contacts["arrow:1"].generation += 1; bads.append(bad)
	bad = wire.duplicate(true); bad.weather.history[1].action_time = 0.7; bads.append(bad)
	bad = wire.duplicate(true); bad.suppression_pending[0].remaining_q += 1.0; bads.append(bad)
	bad = wire.duplicate(true); bad.smoke = {"1:0": {"cell": 1, "layer": 0, "density": 1.0, "second_owner": true}}; bads.append(bad)
	for malformed: Dictionary in bads:
		var raw_before := var_to_bytes(malformed)
		if not _check(not Runtime.validate_fire_snapshot(data, malformed, 0.63).ok and var_to_bytes(data.site) == live and var_to_bytes(malformed) == raw_before,
			"Malformed JSON rejects without mutating live original owners or source payload"): return false
	var leaf_guard := Runtime.fire_save_guard(data)
	var unowned_save := SiteStore.save(data, "user://fire_runtime_unowned_guard.json")
	if not _check(leaf_guard.ok and not unowned_save.ok and unowned_save.code == "BUSY" and var_to_bytes(data.site) == live,
		"Validated fire history passes its leaf codec, while Store still requires the original Lab owner"): return false
	var prior := var_to_bytes(restored.site.fire)
	var replay := Runtime.fire_receive_impact(restored, _payload(restored, cell, 1, 0.63, 100.0, 100.0, 1.0))
	if not _check(replay.ok and replay.duplicate and var_to_bytes(restored.site.fire) == prior, "Loaded receipt suppresses old projectile without refilling contact"): return false
	for index in range(4, 36):
		var cursor := index * 0.2
		if not _advance(data, cursor, 1) or not _advance(restored, cursor, 1): return false
		if not _check(_same_fire(data, restored, cursor), "Loaded heat/fuel/fractions/weather/smoke continue identically through original steps"): return false
	return true

func _cold_smoke_and_empty() -> bool:
	var data := _data()
	if not _check(Runtime.validate_fire_snapshot(data, {}, 0.0).ok and Runtime.capture_fire_snapshot(data, 0.0).state.is_empty(), "Legacy no-fire state remains empty"): return false
	var state := Runtime._fire_state(data, 0.0)
	state.smoke = {"650:0": {"cell": 650, "layer": 0, "density": 4.0}} # Explicit finite smoke-only genesis.
	var captured := Runtime.capture_fire_snapshot(data, 0.0)
	if not _check(captured.ok and Runtime.fire_active(data), "Cold smoke remains active original work"): return false
	var before := var_to_bytes(data.site)
	var restored := Runtime.validate_fire_snapshot(data, _json(captured.state), 0.0)
	if not _check(restored.ok and restored.state.smoke.size() == 1 and var_to_bytes(data.site) == before, "Cold smoke JSON retains finite density without heating/materializing fuel"): return false
	data.set_meta(&"fire_boundary", {"pending": true})
	return _check(not Runtime.capture_fire_snapshot(data, 0.0).ok and var_to_bytes(data.site) == before, "Incomplete original shared boundary refuses capture")

func _paid_warning_roundtrip() -> bool:
	var data := _data()
	var layout := Runtime.building_cells(data, "house", Vector2i(30, 30), Vector2i(3, 3), {"owner_faction": 1})
	if not _check(layout.ok, "Original house layout"): return false
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var built := Runtime.request_build(data, "house", cells, Callable(), {"owner_faction": 1})
	if not _check(built.ok, "Original stock pays for house"): return false
	var feature_id := str(built.feature)
	var feature: Dictionary = data.site.features[feature_id]
	var task := {"version": 2, "zone": -1, "target": "feature:" + feature_id, "action": "construct", "work_cell": int(feature.entrance),
		"cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	Runtime._feature_work(data, feature_id, float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	if not _check(feature.stage == "complete" and feature.get("fire_layout_version") == 1, "Original multi-part house completes"): return false
	# Explicit damage-event fixture genesis, through original HP/guard/outcome.
	# This case tests warning persistence; it is not a projectile/burn source test.
	var amount := float(feature.parts.body.hp) * 0.8
	var request := {"feature": feature_id, "part": "body", "generation": 1, "damage": amount, "fire_damage": amount, "collapse_generation": 0}
	if not _check(Runtime.fire_structure_request_guard(data, request).ok, "Original finite damage request passes preflight"): return false
	var hit := Runtime.damage_structure_part(data, feature_id, "body", amount)
	if not _check(hit.ok, "Original HP owner accepts initial finite event"): return false
	Runtime.fire_structure_outcome(data, request, hit)
	var key := "feature:" + feature_id + ":body"
	var captured := Runtime.capture_fire_snapshot(data, 0.0)
	if not _check(captured.ok and captured.state.collapse_warnings.has(key), "Cold fire-caused warning persists until due step"): return false
	var target := _data()
	target.resource_base = data.resource_base.duplicate(true)
	target.site = data.site.duplicate(true)
	target.site.erase("fire")
	Env.rebuild_indexes(target)
	var wire := _json(captured.state)
	var checked := Runtime.validate_fire_snapshot(target, wire, 0.0)
	if not _check(checked.ok, "Exact original part/due warning survives JSON"): return false
	target.site.fire = checked.state
	var bad: Dictionary = wire.duplicate(true)
	bad.collapse_warnings[key].due_step += 1
	if not _check(not Runtime.validate_fire_snapshot(target, bad, 0.0).ok, "Impossible postponed original collapse deadline rejects"): return false
	for candidate: TerrainData in [data, target]:
		var sink := func(damage: Dictionary, _water: Dictionary, _serial: int) -> Dictionary:
			var results := {}
			for part_key: String in damage:
				var row: Dictionary = damage[part_key]
				var guard := Runtime.fire_structure_request_guard(candidate, row)
				if not guard.ok: results[part_key] = guard; continue
				results[part_key] = Runtime.damage_structure_part(candidate, str(row.feature), str(row.part), float(row.damage))
			return {"ok": true, "results": results}
		if not _check(Runtime.fire_advance(candidate, 1.8, 0, sink).ok and float(candidate.site.features[feature_id].parts.body.hp) > 0.0,
			"Warning waits through original pre-due steps"): return false
		if not _check(Runtime.fire_advance(candidate, 2.0, 0, sink).ok and float(candidate.site.features[feature_id].parts.body.hp) == 0.0,
			"Original due step causes exactly one actual collapse"): return false
	if not _check(_same_fire(data, target, 2.0), "Loaded due collapse retains original fuel and identical receipts"): return false
	var debris := Runtime.capture_fire_snapshot(target, 2.0)
	if not _check(debris.ok and debris.state.units[key].debris_version == 1 and debris.state.units[key].generation == 2,
		"Original debris generation has one matching standing-generation receipt"): return false
	bad = _json(debris.state); bad.collapse_receipts.erase(key + "@1")
	return _check(not Runtime.validate_fire_snapshot(target, bad, 2.0).ok, "Missing original debris receipt cannot create a second collapse")

func _run() -> void:
	if not _roundtrip_and_rejections() or not _cold_smoke_and_empty() or not _paid_warning_roundtrip(): _finish(false, "Runtime JSON contract"); return
	_finish(not failed, "original Runtime persistence leaf only; no all-owner save or performance proof")
