extends "res://scripts/tests/site_fire_exposure_surface_death_test.gd"
## P4 output-only named original geometry/material/collapse/service test.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_BUILDING_PARTS_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _parts() -> bool:
	for kind: String in SiteRuntime.FIRE_LAYOUT_KINDS:
		var f := _fixture()
		if kind == "well": f.data.groundwater.fill(80)
		if kind in ["saltworks", "intake"]:
			var water := f.data.index(Vector2i(19, 20))
			f.data.surface_types[water] = TerrainData.Surface.WATER
			f.data.water_kind[water] = 2 if kind == "saltworks" else 1
			f.data.water_body[water] = water
			f.data.flags[water] = TerrainData.Flag.BLOCKED
			SiteRuntime.rebuild_terrain_edges(f.data)
			SiteEnvironment.rebuild_indexes(f.data)
		var key := _paid_feature(f, kind, Vector2i(20, 20), Vector2i(10, 10) if kind in SiteRuntime.MILITARY_KINDS else Vector2i.ONE)
		if key.is_empty(): return false
		var feature: Dictionary = f.data.site.features[key]
		var geometry := SiteRuntime.feature_geometry(f.data, feature)
		if not _check(SiteRuntime.validate_feature_layout(f.data, feature).ok and geometry.parts.size() == SiteRuntime._fire_layout_parts(feature).size(), "Original paid part shape remains strict", kind): return false
		var fuel := 0
		for id: String in geometry.parts:
			var part: Dictionary = geometry.parts[id]
			fuel += int(part.fuel_max_q)
			if not _check(part.lower <= part.aim_point.z and part.aim_point.z <= part.upper and part.lower < part.upper, "Original aim lies inside the same part prism", {"kind": kind, "part": id}): return false
			if int(part.fuel_max_q) > 0:
				var cold_before := var_to_bytes(f.data.site.get("fire", {}))
				var cold_key := SiteRuntime._fire_unit_key("feature", key, id)
				var cold := SiteRuntime.fire_work_target(f.data, cold_key, "IGNITE", 1)
				if not _check(cold.ok and str(cold.descriptor.part) == id and not cold.complete and cold.unit.is_empty() and var_to_bytes(f.data.site.get("fire", {})) == cold_before, "Every original cold paid combustible part is queried without creating heat, including colon component IDs", {"kind": kind, "part": id}): return false
			if id.begins_with("roof") and not _check(float(geometry.parts.body.upper) == float(part.lower), "Roof/body prisms meet without duplicate volume", kind): return false
		if not _check(fuel == int(feature.cost.get("wood", 0)) * SiteRuntime.FIRE_Q, "All parts partition one actually paid wood cost", kind): return false
		var corrupt := feature.duplicate(true)
		corrupt.parts["invented"] = {"hp": 1.0}
		if not _check(not SiteRuntime.validate_feature_layout(f.data, corrupt).ok, "Unknown part remains rejected", kind): return false
		_close(f)
	return true

func _warehouse() -> bool:
	var f := _fixture()
	var stock_before := int(f.data.site.inventory.stone)
	var wood_before := int(f.data.site.inventory.wood)
	var key := _paid_feature(f, "warehouse", Vector2i(20, 20), Vector2i.ONE, {"material": "stone"})
	if key.is_empty(): return false
	var feature: Dictionary = f.data.site.features[key]
	var geometry := SiteRuntime.feature_geometry(f.data, feature)
	if not _check(stock_before - int(f.data.site.inventory.stone) == 24 and wood_before - int(f.data.site.inventory.wood) == 8 and int(geometry.parts.body.fuel_max_q) == 0 and int(geometry.parts.roof.fuel_max_q) == 8192, "Original stone warehouse has paid stone body and finite wood roof"): return false
	var storage := SiteStockpiles.ensure_storage(f.data, key, 1)
	if not _check(storage.ok, "Original stockpile initializes once"): return false
	var stock: Dictionary = storage.stock
	stock.cargo["wood"] = 7 # Explicit fixture genesis in the real stock owner.
	var holder: Dictionary = stock.holder
	var cargo: Dictionary = stock.cargo
	var roof_aim := f.lab.siege_target({"type": "structure", "feature_id": key, "part_id": "roof"})
	if not _check(float(roof_aim.height) > float(geometry.parts.body.upper), "Original structure target aims at roof volume"): return false
	f.lab._capture_fire_static()
	var cells: Array = geometry.parts.roof.cells
	var entries: Array = f.lab._fire_static_buckets[f.data.cell_from_index(int(cells[0]))]
	var roof_entry: Dictionary = {}
	var body_entry: Dictionary = {}
	for entry: Dictionary in entries:
		if str(entry.part) == "roof": roof_entry = entry
		if str(entry.part) == "body": body_entry = entry
	if not _check(not roof_entry.is_empty() and not body_entry.is_empty() and roof_entry.lower == body_entry.upper and str(roof_entry.material) == "wood" and str(body_entry.material) == "stone", "Original static first-contact records retain component material and nonoverlap"): return false
	var result := f.lab.siege_apply_damage_batch({key + "|roof": {"feature": key, "part": "roof", "damage": 50.0}}, {})
	if not _check(result.results[key + "|roof"].ok and float(feature.parts.body.hp) == 100.0 and float(feature.parts.roof.hp) == 0.0 and not f.data.is_walkable(f.data.cell_from_index(int(feature.cells[0]))), "Roof-only original damage leaves stone obstruction and body intact"): return false
	var endpoint := SiteStockpiles.stock_endpoint(f.data, key)
	if not _check(endpoint.withdraw_only and is_same(holder, endpoint.holder) and is_same(cargo, endpoint.cargo) and int(cargo.wood) == 7 and SiteRuntime.feature_function_state(feature) == "DISABLED", "Original intake stops; real cargo/holder references survive first roof failure"): return false
	var unit_key := SiteRuntime._fire_unit_key("feature", key, "roof")
	var unit: Dictionary = f.data.site.fire.units[unit_key]
	var before := var_to_bytes(f.data.site.fire)
	f.lab.siege_apply_damage_batch({key + "|roof": {"feature": key, "part": "roof", "damage": 50.0}}, {})
	if not _check(int(unit.debris_version) == 1 and int(unit.fuel_q) == 8192 and var_to_bytes(f.data.site.fire) == before, "Duplicate dead part does not refill debris or repeat collapse receipt"): return false
	_close(f)
	return true

func _warning_and_debris() -> bool:
	var f := _fixture()
	var key := _paid_feature(f, "palisade", Vector2i(20, 20), Vector2i(1, 1))
	if key.is_empty(): return false
	var part := "c:" + str(f.data.index(Vector2i(20, 20)))
	var unit := _hot_feature(f, key, part)
	unit.profile = "WOOD_COMPONENT"
	unit.heat = 100.0
	var unit_key := SiteRuntime._fire_unit_key("feature", key, part)
	f.lab.siege_apply_damage_batch({key + "|" + part: {"feature": key, "part": part, "damage": 68.0}}, {})
	for tick: int in range(1, 4):
		if not _check(SiteRuntime.fire_advance(f.data, tick * 0.2, 0, f.lab.siege_queue_damage).ok, "Original 5Hz fire damage uses actual structure sink"): return false
	var state: Dictionary = f.data.site.fire
	if not _check(state.get("collapse_warnings", {}).has(unit_key), "Actual finite burn crossing quarter HP creates one warning"): return false
	var warning: Dictionary = state.collapse_warnings[unit_key].duplicate(true)
	var version := f.data.navigation_revision
	var holders: Array[Dictionary] = []
	for index: int in range(3):
		var holder := SiteRuntime.new_item_state("fire-warning-test-" + str(index))
		holder["fire_lab_suppression_q"] = 30720
		holders.append(holder)
	# Real original suppression transactions, with their own finite holder debit.
	for tick: int in range(4, int(warning.due_step)):
		var begin := (tick - 1) * 0.2
		for sub: int in range(6):
			var a := begin + sub / 30.0
			# Each preparation interval starts at the original observed boundary.
			if a > float(state.observed_action_end) + 0.0000001:
				if not _check(SiteRuntime.fire_advance(f.data, a, 0, f.lab.siege_queue_damage).ok, "Original subinterval observed watermark"): return false
			for holder: Dictionary in holders:
				var prepared := SiteRuntime.fire_prepare_suppression(f.data, unit_key, int(state.units[unit_key].generation), a, a + 1.0 / 30.0, 34, holder, int(holder.version))
				if prepared.ok and prepared.has("state_owner"):
					if not _check(SiteRuntime.fire_commit_suppression(f.data, prepared).ok, "Original holder cooling commits"): return false
		if not _check(SiteRuntime.fire_advance(f.data, tick * 0.2, 0, f.lab.siege_queue_damage).ok, "Original warning time continues"): return false
		if float(f.data.site.features[key].parts[part].hp) <= 0.0: break
	if not _check(float(f.data.site.features[key].parts[part].hp) > 0.0 and float(state.units[unit_key].heat) == 0.0 and state.collapse_warnings[unit_key] == warning, "Actual finite suppression extinguishes before due without cancelling structural warning", {"hp": f.data.site.features[key].parts[part].hp, "heat": state.units[unit_key].heat, "warnings": state.collapse_warnings, "expected_warning": warning, "remaining_supply": [holders[0].fire_lab_suppression_q, holders[1].fire_lab_suppression_q, holders[2].fire_lab_suppression_q], "pending": state.get("suppression_pending", []), "cursor": state.observed_action_end}): return false
	if float(f.data.site.features[key].parts[part].hp) > 0.0:
		var saved_warning: Dictionary = state.collapse_warnings[unit_key].duplicate(true)
		f.lab.siege_apply_damage_batch({key + "|" + part: {"feature": key, "part": part, "damage": 0.1}}, {})
		if not _check(state.collapse_warnings[unit_key] == saved_warning and f.data.navigation_revision == version, "Nonfatal ordinary damage retains warning and static topology"): return false
		if not _check(SiteRuntime.fire_advance(f.data, int(warning.due_step) * 0.2, 0, f.lab.siege_queue_damage).ok, "Due warning reaches original HP transaction"): return false
	if not _check(float(f.data.site.features[key].parts[part].hp) == 0.0 and state.collapse_warnings.is_empty() and state.collapse_receipts.size() == 1 and int(state.units[unit_key].debris_version) == 1 and f.data.effective_height(Vector2i(20, 20)) == 0, "One original collapse consumes warning and moves finite material to ground"): return false
	var receipt := var_to_bytes(state.collapse_receipts)
	if not _check(SiteRuntime.fire_advance(f.data, int(warning.due_step) * 0.2, 0, f.lab.siege_queue_damage).ok and var_to_bytes(state.collapse_receipts) == receipt, "Same completed boundary cannot repeat collapse"): return false
	_close(f)
	return true

func _run() -> void:
	if not _parts(): _finish(false, "parts / paid material / strict geometry"); return
	if not _warehouse(): _finish(false, "stone warehouse / roof-only original structure path"); return
	if not _warning_and_debris(): _finish(false, "original warning / actual sink / one debris transfer"); return
	_finish(not failed, "P4 named geometry/material/structure receipt scope; no visual or performance acceptance")
