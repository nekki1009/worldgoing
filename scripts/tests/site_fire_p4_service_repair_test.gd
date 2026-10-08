extends "res://scripts/tests/site_fire_building_parts_test.gd"
## Original service consumers and paid part repair/upgrade owner transactions.
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")
const Garrison = preload("res://scripts/terrain_lab/site_garrison.gd")
const Training = preload("res://scripts/terrain_lab/site_training_ground.gd")

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	var file := FileAccess.open(OUTPUT + "/service_repair_result.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "evidence": evidence}, "\t"))
	print("SITE_FIRE_P4_SERVICE_REPAIR_", "PASS" if ok else "FAIL", ": checks=", checks)
	await process_frame
	quit(0 if ok else 1)

func _repair_original_roof(f: Fixture, key: String, part: String) -> bool:
	var feature: Dictionary = f.data.site.features[key]
	var unit_key := SiteRuntime._fire_unit_key("feature", key, part)
	var unit: Dictionary = f.data.site.fire.units[unit_key]
	var generation := int(unit.generation)
	var fuel := int(unit.fuel_q)
	var stock: Dictionary = f.data.site.inventory
	var before := stock.duplicate(true)
	var requested := SiteRuntime.request_repair(f.data, key, part, int(feature.owner_faction))
	if not _check(requested.ok and feature.has("repair"), "Original cold roof repair admits one paid job", requested): return false
	var job: Dictionary = feature.repair
	for item: String in job.cost:
		if not _check(int(before[item]) - int(stock[item]) == int(job.cost[item]), "Original repair debits only its actual part quote", item): return false
	if not _check(int(unit.fuel_q) == fuel and float(feature.parts[part].hp) == 0.0,
		"Request and payment cannot refill original fuel or restore HP before actual labor"): return false
	var task: Dictionary = f.data.site.worker
	SiteRuntime.assign_task(f.data, SiteRuntime.ok("", {"target": "feature:" + key, "action": "repair", "cell": int(job.work_cell)}))
	task.cell = int(job.work_cell)
	task.mode = "work"
	SiteRuntime._feature_work(f.data, key, float(job.work), Callable(), Callable(), task, {}, 20, int(feature.owner_faction))
	unit = f.data.site.fire.units[unit_key]
	if not _check(not feature.has("repair") and float(feature.parts[part].hp) == float(SiteRuntime.feature_geometry(f.data, feature).parts[part].max_hp)
		and int(unit.generation) == generation + 1 and not unit.has("debris_version") and int(unit.fuel_q) >= fuel
		and int(unit.fuel_q) <= int(unit.fuel_max_q) and is_same(stock, f.data.site.inventory),
		"Actual original paid labor restores one roof generation and bounded standing fuel"): return false
	var after := var_to_bytes([stock, feature, unit])
	SiteRuntime._feature_work(f.data, key, float(job.work), Callable(), Callable(), task, {}, 20, int(feature.owner_faction))
	if not _check(var_to_bytes([stock, feature, unit]) == after, "Duplicate completed repair cannot repeat HP, fuel or stock"): return false
	return true

func _house_lodging_upgrade() -> bool:
	var f := _fixture()
	var key := _paid_feature(f, "house", Vector2i(20, 20), Vector2i.ONE, {"owner_faction": 1})
	if key.is_empty(): return false
	var feature: Dictionary = f.data.site.features[key]
	var layout := SiteRuntime.house_layout(f.data, key)
	var cell := f.data.cell_from_index(int(layout.slots[0]))
	var team := _team(f, [cell], 1, 1, TerrainArmy.TROOP_TYPE_ID)
	if failed: return false
	var identity := team.combat_identity(0)
	# Isolated legal attendance genesis in the original Site housing owner.
	f.data.site["housing"] = {str(identity): {"version": 1, "house_id": key, "cell": int(layout.slots[0])}}
	var registration: Dictionary = f.data.site.housing[str(identity)]
	var holder: Dictionary = team.combat_units[0].item_state
	if not _check(Housing._attends(f.lab, identity) and Housing.recovery_multiplier(f.lab, team.combat_units) > 1.0,
		"Original housing consumer grants actual registered stationary member its normal recovery"): return false
	f.lab.siege_apply_damage_batch({key + "|roof": {"feature": key, "part": "roof", "damage": 10000.0}}, {})
	if not _check(not Housing._attends(f.lab, identity) and Housing.recovery_multiplier(f.lab, team.combat_units) == 1.0
		and SiteRuntime.feature_function_state(feature, "lodging") == "DISABLED"
		and is_same(registration, f.data.site.housing[str(identity)]) and is_same(holder, team.combat_units[0].item_state),
		"Original roof failure stops lodging bonus while preserving exact housing and item references"): return false
	if not _repair_original_roof(f, key, "roof"): return false
	if not _check((not Housing._attends(f.lab, identity) and float(f.data.site.combat_left) > 0.0 and SiteRuntime.feature_usable(feature, "lodging")), "Original combat grace still gates recovery after completed roof repair"): return false
	SiteRuntime.advance(f.data, float(f.data.site.combat_left) + 0.01)
	if not _check(Housing._attends(f.lab, identity) and Housing.recovery_multiplier(f.lab, team.combat_units) > 1.0
		and is_same(registration, f.data.site.housing[str(identity)]), "Original paid roof repair resumes the same actual housing consumer"): return false
	var fuel := int(f.data.site.fire.units["feature:" + key + ":roof"].fuel_q)
	var generation := int(f.data.site.fire.units["feature:" + key + ":roof"].generation)
	var upgraded := SiteRuntime.request_upgrade(f.data, key, 1)
	if not _check(upgraded.ok and SiteRuntime.building_grade(feature) == 1
		and int(f.data.site.fire.units["feature:" + key + ":roof"].fuel_q) == fuel,
		"Original paid upgrade request retains completed grade and roof fuel until labor", upgraded): return false
	var work := float(feature.pending_build.work)
	var task: Dictionary = f.data.site.worker
	SiteRuntime.assign_task(f.data, SiteRuntime.ok("", {"target": "feature:" + key, "action": "construct", "cell": int(feature.entrance)}))
	task.cell = int(feature.entrance)
	task.mode = "work"
	SiteRuntime._feature_work(f.data, key, work, Callable(), Callable(), task, {}, 20, 1)
	var unit: Dictionary = f.data.site.fire.units["feature:" + key + ":roof"]
	if not _check(not feature.has("pending_build") and SiteRuntime.building_grade(feature) == 2 and int(unit.generation) > generation
		and int(unit.fuel_q) >= fuel and int(unit.fuel_q) <= int(unit.fuel_max_q)
		and is_same(holder, team.combat_units[0].item_state) and is_same(registration, f.data.site.housing[str(identity)])
		and team.cells[0] == cell and Housing._attends(f.lab, identity),
		"Actual same-ID paid grade upgrade preserves original person, housing/holder refs and finite roof fuel"): return false
	_close(f)
	return true

func _barracks_consumers(kind: String) -> bool:
	var f := _fixture()
	var key := _paid_feature(f, "barracks", Vector2i(20, 20), Vector2i(10, 10), {"owner_faction": 1, "camp_type": "chinese" if kind == "chinese" else "standard"})
	if key.is_empty(): return false
	var feature: Dictionary = f.data.site.features[key]
	var standing := SiteRuntime.military_walkable_cells(f.data, feature)
	var team := _team(f, [f.data.cell_from_index(int(standing[0])), f.data.cell_from_index(int(standing[1]))], 1, 1, TerrainArmy.TROOP_TYPE_ID)
	if failed: return false
	var holder: Dictionary = team.combat_units[1].item_state
	if kind == "chinese":
		if not _check(Garrison.recovery_multiplier(f.lab, key, 1, team.combat_units) > 1.0, "Original Chinese garrison recovery consumer is active"): return false
	else:
		if not _check(Training.inspect(f.controller, team.team_id, key).ok, "Original western training consumer is active"): return false
	f.lab.siege_apply_damage_batch({key + "|roof:hq": {"feature": key, "part": "roof:hq", "damage": 10000.0}}, {})
	if not _check(SiteRuntime.feature_function_state(feature) == "DEGRADED"
		and SiteRuntime.feature_usable(feature, "recovery") and not SiteRuntime.feature_usable(feature, "training"),
		"Original HQ-only failure retains independent quarters while disabling its training service"): return false
	if kind == "western" and not _check(not Training.inspect(f.controller, team.team_id, key).ok, "Actual western training consumer rejects failed original HQ"): return false
	f.lab.siege_apply_damage_batch({key + "|roof:quarters": {"feature": key, "part": "roof:quarters", "damage": 10000.0}}, {})
	if not _check(SiteRuntime.feature_function_state(feature) == "DISABLED"
		and Garrison.recovery_multiplier(f.lab, key, 1, team.combat_units) == 1.0,
		"Original failed quarters disable the actual garrison recovery consumer without replacing members"): return false
	if not _repair_original_roof(f, key, "roof:hq") or not _repair_original_roof(f, key, "roof:quarters"): return false
	if not _check(SiteRuntime.feature_function_state(feature) == "OPERATIONAL" and is_same(holder, team.combat_units[1].item_state)
		and (Garrison.recovery_multiplier(f.lab, key, 1, team.combat_units) > 1.0 if kind == "chinese" else Training.inspect(f.controller, team.team_id, key).ok),
		"Original paid multipart repairs resume the actual corresponding service with the same original holder"): return false
	_close(f)
	return true

func _run() -> void:
	if not _house_lodging_upgrade(): _finish(false, "original house lodging/repair/upgrade"); return
	for kind: String in ["chinese", "western"]:
		if not _barracks_consumers(kind): _finish(false, "original barracks consumers: " + kind); return
	_finish(not failed, "P4 original housing, recovery/training consumers, paid roof repair and grade upgrade; isolated attendance/earned-labor transactions, no full UI/Native/persistence/performance claim")
