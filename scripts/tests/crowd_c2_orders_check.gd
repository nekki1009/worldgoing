extends SceneTree
## L1 only: real Godot binding / CrowdSite / SiteController command methods.
## Synthetic flat terrain, four manual teams (2 v 2), four soldiers per team.
## Only result display and UI repaint are replaced; command/preflight/AI code is real.
## No atlas, textures, render kits, fake frames or visual acceptance are provided.
## The RETURN case explicitly drives a kinematic enemy fixture at 2 cells/second.
const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const DT := 1.0 / 30.0
const CODE_NAMES := ["OK", "NOT_OWNER", "BAD_FORMATION", "BAD_ARGS", "NO_TARGET", "BLOCKED", "NOT_ROUTED", "ROUTED", "NO_ORDERS"]
const CENTRES := [Vector2(15.5, 20.5), Vector2(15.5, 60.5), Vector2(40.5, 20.5), Vector2(21.5, 60.5)]
const PEOPLE := 4
const EQUIP := 1 | (3 << 8) | (2 << 16) # Native iron longsword / leather fixture.

class ControllerFixture extends SiteController:
	var result: Dictionary = {}
	var result_serial := 0
	func show_result(value: Dictionary) -> void:
		result = value.duplicate(true)
		result_serial += 1
	func _update_combat_window() -> void:
		pass # L1 surface only. _trial_team_order/_ai and their callees are inherited.

class LabFixture extends Node2D:
	var terrain := TerrainData.new()
	var crowd_site: Node
	func controlled_person_id() -> int:
		return 100

class Fixture extends RefCounted:
	var lab := LabFixture.new()
	var site: Node = CrowdSite.new()
	var controller := ControllerFixture.new()
	var workers := 1
	var baseline := PackedByteArray()
	func create(worker_count: int) -> bool:
		workers = worker_count
		lab.terrain.allocate(Vector2i(96, 80))
		lab.terrain.flags.fill(TerrainData.Flag.WALKABLE)
		lab.terrain.flags[lab.terrain.index(Vector2i(90, 75))] = 0
		lab.terrain.site = {"manual": {"cargo": {}}, "worker": {"cargo": {}}, "captivity": {}}
		if not Runtime.initialize_item_storage(lab.terrain.site).ok: return false
		lab.crowd_site = site
		site.lab = lab
		site.crowd = ClassDB.instantiate("ArmyCrowd")
		if not site.crowd.setup(workers, 7113): return false
		if not site.crowd.set_terrain(96, 80, lab.terrain.height_levels, lab.terrain.flags, lab.terrain.ramp_edges, lab.terrain.static_blocked, PackedByteArray()): return false
		for formation in range(4):
			var point: Vector2 = CENTRES[formation]
			var faction := 0 if formation < 2 else 1
			if int(site.crowd.add_formation(faction, point.x, point.y, 0.0, 4, 1.0, 0, 50.0)) != formation: return false
			var ids := PackedInt64Array()
			var equipment := PackedInt32Array()
			var roles := PackedByteArray()
			var ammo := PackedInt32Array()
			for member in range(PEOPLE):
				var identity := 100 + formation * PEOPLE + member
				ids.append(identity)
				equipment.append(EQUIP)
				roles.append(1 if member == 0 else 0)
				ammo.append(0)
				site._records[identity] = {"person_id": identity, "hp": 100.0, "appearance": {"parts": {}}, "item_state": Runtime.new_item_state("person:%d" % identity), "cargo": {}, "loot_settled": false}
			if int(site.crowd.add_soldiers(formation, ids, equipment, roles, ammo)) != formation * PEOPLE: return false
			site.teams.append({"slot": formation, "team_id": formation + 1, "formation": formation, "faction": faction, "troop": 0, "person_ids": Array(ids), "solo": false})
		if not site.crowd.set_hostile(0, 1, true) or not site.crowd.finalize(): return false
		for formation in range(4):
			if not site.crowd.set_order_owner(formation, false): return false
		site._bind_people()
		site.active = true
		controller.lab = lab
		controller.trial_command_team = OptionButton.new()
		controller.add_child(controller.trial_command_team)
		controller._sync_crowd_choices()
		site.crowd.stats() # Establish derived counters before saving the common baseline.
		baseline = site.crowd.save_state()
		return site.crowd.validate() and site.command_teams().size() == 4
	func reset() -> bool:
		site.test_order_failure = -1
		site.order_calls = 0
		controller.result.clear()
		return site.crowd.load_state(baseline) and site.crowd.validate()
	func close() -> void:
		controller.free()
		site._dispose()
		site.free()
		lab.free()

var worlds: Array[Fixture] = []
var failed := false
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var out_dir := ""
var case_name := "setup"
var case_tick := 0
var total_steps := 0
var started_ms := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = null) -> bool:
	checks.append({"ok": ok, "case": case_name, "check": label, "detail": detail})
	print("C2_ORDERS ", "OK " if ok else "FAIL ", label, " ", str(detail) if detail != null else "")
	if not ok: failed = true
	return ok

func _state(fixture: Fixture, formation: int) -> Dictionary:
	return fixture.site.formation_state(formation)

func _centre(fixture: Fixture, formation: int) -> Vector2:
	var state := _state(fixture, formation)
	return Vector2(float(state.cx), float(state.cy))

func _snapshot(fixture: Fixture) -> Dictionary:
	var native: RefCounted = fixture.site.crowd
	var stats: PackedFloat64Array = native.stats()
	var result := {"stats": Array(stats.slice(0, 18)) + Array(stats.slice(33, 40)), "soldiers": [], "formations": []}
	for index in range(int(native.soldier_count())):
		result.soldiers.append([native.get_soldier_state(index), native.soldier_refs(index)])
	for index in range(int(native.formation_count())):
		result.formations.append([native.get_formation_state(index), native.formation_refs(index)])
	result.blob = native.save_state()
	result.hash = native.state_hash()
	return result

func _sample(fixture: Fixture, label: String, result: Variant = null) -> void:
	var stats: PackedFloat64Array = fixture.site.crowd.stats()
	var teams: Array[Dictionary] = []
	for formation in range(4):
		var state := _state(fixture, formation)
		teams.append({"team": formation + 1, "centre": [state.cx, state.cy], "order": int(state.order), "ai_enabled": bool(state.ai_enabled), "routed": bool(state.routed), "target_person": int(state.target_person), "goal": [state.goal_x, state.goal_y]})
	samples.append({"case": case_name, "label": label, "workers": fixture.workers, "tick": case_tick, "action_seconds": case_tick * DT, "teams": teams, "exchange_pairs": stats[10], "illegal_cell": stats[14], "illegal_step": stats[15], "result": result, "state_hash": str(fixture.site.crowd.state_hash())})

func _same_worlds(label: String) -> bool:
	return _check(worlds[0].site.crowd.state_hash() == worlds[1].site.crowd.state_hash(), label + " 1/4 worker hash equal", {"one": str(worlds[0].site.crowd.state_hash()), "four": str(worlds[1].site.crowd.state_hash())})

func _begin(name: String) -> bool:
	case_name = name
	case_tick = 0
	print("C2_ORDERS CASE ", name)
	for fixture: Fixture in worlds:
		if not _check(fixture.reset(), "restore four-team manual baseline", fixture.workers): return false
		for formation in range(4):
			if not _check(not bool(_state(fixture, formation).ai_enabled), "baseline manual team", [fixture.workers, formation + 1]): return false
		_sample(fixture, "baseline")
	return _same_worlds("baseline")

func _ui(fixture: Fixture, formation: int, kind: int, goal: Vector2i = Vector2i(-1, -1)) -> String:
	fixture.controller.trial_command_team.select(formation)
	fixture.controller.selected = goal
	var before := fixture.controller.result_serial
	fixture.controller._trial_team_order(kind)
	var code := "MISSING_RESULT" if before == fixture.controller.result_serial else ("OK" if bool(fixture.controller.result.get("ok", false)) else str(fixture.controller.result.get("code", "MISSING_CODE")))
	_sample(fixture, "UI command", {"team": formation + 1, "kind": kind, "code": code})
	return code

func _ui_both(formation: int, kind: int, goal: Vector2i, expected: String) -> bool:
	for fixture: Fixture in worlds:
		if not _check(_ui(fixture, formation, kind, goal) == expected, "UI exact " + expected, [fixture.workers, formation + 1, kind]): return false
	return _same_worlds("UI command")

func _ai_both(formation: int, enabled: bool) -> bool:
	for fixture: Fixture in worlds:
		fixture.controller.trial_command_team.select(formation)
		fixture.controller._trial_team_ai(enabled)
		if not _check(bool(fixture.controller.result.get("ok", false)) and bool(_state(fixture, formation).ai_enabled) == enabled, "UI AI ownership", [fixture.workers, formation + 1, enabled]): return false
		_sample(fixture, "UI AI", fixture.controller.result)
	return _same_worlds("AI ownership")

func _raw_reject(label: String, formation: int, kind: int, x: float, y: float, value: float, expected: int) -> bool:
	for fixture: Fixture in worlds:
		var before := _snapshot(fixture)
		var code := int(fixture.site.crowd.order(formation, kind, x, y, value))
		var after := _snapshot(fixture)
		_sample(fixture, label, {"raw_code": code, "expected": expected})
		if not _check(code == expected and after == before, label + " exact code + every exported field/blob/hash unchanged", {"workers": fixture.workers, "expected": expected, "actual": code, "hash_unchanged": after.hash == before.hash, "all_fields_unchanged": after == before}): return false
	return _same_worlds(label)

func _ui_reject(formation: int, kind: int, goal: Vector2i, expected: String, calls: int, injected: bool = false) -> bool:
	for fixture: Fixture in worlds:
		fixture.site.test_order_failure = 5 if injected else -1
		var before := _snapshot(fixture)
		var old_calls := int(fixture.site.order_calls)
		var code := _ui(fixture, formation, kind, goal)
		var after := _snapshot(fixture)
		fixture.site.test_order_failure = -1
		if not _check(code == expected and after == before and int(fixture.site.order_calls) == old_calls + calls, "UI rejected transaction restores all fields and ownership", {"workers": fixture.workers, "team": formation + 1, "expected": expected, "actual": code, "call_delta": int(fixture.site.order_calls) - old_calls, "expected_calls": calls, "injected_native_result": injected, "all_fields_unchanged": after == before}): return false
	return _same_worlds("UI rollback")

func _step_pair() -> bool:
	for fixture: Fixture in worlds:
		# Explicit L1 combat-clock input; no fake Site clock owner or frame renderer.
		if not fixture.site.crowd.step_clock(DT, DT, 1000.0) or not fixture.site.crowd.validate():
			return _check(false, "valid native binding step", [fixture.workers, case_tick])
		var stats: PackedFloat64Array = fixture.site.crowd.stats()
		if stats[14] != 0.0 or stats[15] != 0.0:
			return _check(false, "zero illegal cells/edges every step", [fixture.workers, case_tick, stats[14], stats[15]])
	case_tick += 1
	total_steps += 1
	if worlds[0].site.crowd.state_hash() != worlds[1].site.crowd.state_hash():
		return _check(false, "every-step 1/4 worker hash", case_tick)
	if Time.get_ticks_msec() - started_ms > 240000:
		return _check(false, "script 240 second deadline", case_tick)
	for fixture: Fixture in worlds: _sample(fixture, "step")
	return true

func _advance(ticks: int) -> bool:
	for tick in range(ticks):
		if not _step_pair(): return false
		if tick % 60 == 0: await process_frame
	return true

func _movement_matrix() -> bool:
	if not _begin("1_MOVE_20_cells"): return false
	var goal := Vector2i(35, 20)
	if not _check(_centre(worlds[0], 0).distance_to(Vector2(goal) + Vector2.ONE * 0.5) >= 20.0, "MOVE fixture distance >= 20 cells"): return false
	if not _ui_both(0, TerrainArmy.CombatOrder.MOVE, goal, "OK"): return false
	var arrived := -1
	for tick in range(750):
		if not _step_pair(): return false
		if _centre(worlds[0], 0).distance_to(Vector2(goal) + Vector2.ONE * 0.5) <= 1.5 and int(_state(worlds[0], 0).order) == 0:
			arrived = case_tick
			break
		if tick % 60 == 0: await process_frame
	if not _check(arrived > 0 and arrived <= 750, "MOVE <= 1.5 cells and HOLD within 25 seconds", {"arrival_seconds": arrived * DT, "distance": _centre(worlds[0], 0).distance_to(Vector2(goal) + Vector2.ONE * 0.5)}): return false
	if not _begin("2_HOLD_enemy_6_cells"): return false
	var start := _centre(worlds[0], 1)
	if not _check(absf(start.distance_to(_centre(worlds[0], 3)) - 6.0) <= 0.000001, "enemy formation centre exactly six cells away"): return false
	if not _ui_both(1, TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), "OK"): return false
	var maximum := 0.0
	for tick in range(600):
		if not _step_pair(): return false
		maximum = maxf(maximum, start.distance_to(_centre(worlds[0], 1)))
		if tick % 60 == 0: await process_frame
	if not _check(maximum <= 1.5, "HOLD every centre displacement <= 1.5 for 20 seconds", maximum): return false
	if not _begin("3_ATTACK_nearest_active"): return false
	# Independent distance oracle using public hot states, not native nearest_enemy.
	var leader: Dictionary = worlds[0].site.soldier_state(0)
	var origin := Vector2(float(leader.px), float(leader.py))
	var nearest: Array[int] = []
	var best := INF
	for index in range(8, 16):
		var person: Dictionary = worlds[0].site.soldier_state(index)
		if person.hp <= 0.0 or person.ko > 0.0 or person.getup > 0.0 or bool(person.captive): continue
		var distance := origin.distance_squared_to(Vector2(float(person.px), float(person.py)))
		if distance < best - 0.000001:
			best = distance
			nearest.assign([int(person.person_id)])
		elif absf(distance - best) <= 0.000001: nearest.append(int(person.person_id))
	if not _ui_both(0, TerrainArmy.CombatOrder.ATTACK, Vector2i(-1, -1), "OK"): return false
	if not _check(int(_state(worlds[0], 0).target_person) in nearest, "ATTACK no explicit target chooses nearest actionable enemy", {"nearest": nearest, "selected": _state(worlds[0], 0).target_person}): return false
	var before: PackedFloat64Array = worlds[0].site.crowd.stats()
	var contact_at := -1
	for tick in range(600):
		if not _step_pair(): return false
		var now: PackedFloat64Array = worlds[0].site.crowd.stats()
		if now[10] > before[10]:
			contact_at = case_tick
			break
		if tick % 60 == 0: await process_frame
	return _check(contact_at > 0 and contact_at <= 600, "ATTACK actual exchange count increases within 20 seconds", contact_at * DT)

func _rejection_matrix() -> bool:
	if not _begin("4_5_7_8_9_10_command_matrix"): return false
	# Team 3's selected enemy captain is exactly 25 cells away.
	var target: Dictionary = worlds[0].site.soldier_state(0)
	var target_cell := Vector2i(floori(float(target.px)), floori(float(target.py)))
	var reference := _centre(worlds[0], 2)
	if not _check(reference.distance_to(Vector2(float(target.px), float(target.py))) >= 25.0, "PURSUE fixture enemy >= 25 cells"): return false
	if not _ui_reject(2, TerrainArmy.CombatOrder.PURSUE, target_cell, "NO_TARGET", 0): return false
	if not _raw_reject("binding PURSUE > 20", 2, 4, 0.0, 0.0, 0.0, 4): return false
	if not _ui_reject(0, TerrainArmy.CombatOrder.RETREAT, Vector2i(-1, -1), "NOT_ROUTED", 0): return false
	if not _raw_reject("binding normal RETREAT", 0, 3, 0.0, 0.0, 0.0, 6): return false
	if not _ai_both(3, true): return false
	if not _ui_both(3, TerrainArmy.CombatOrder.MOVE, Vector2i(24, 60), "OK"): return false
	for fixture: Fixture in worlds:
		if not _check(not bool(_state(fixture, 3).ai_enabled), "successful UI command takes AI ownership", fixture.workers): return false
	if not _ai_both(3, true): return false
	for kind in range(5):
		if not _raw_reject("AI raw command NOT_OWNER kind %d" % kind, 3, kind, 24.5, 60.5, 0.0, 1): return false
	for formation in [3, 0]:
		if not _ui_reject(formation, TerrainArmy.CombatOrder.MOVE, Vector2i(-10, -10), "BLOCKED", 0): return false
		if not _ui_reject(formation, TerrainArmy.CombatOrder.MOVE, Vector2i(90, 75), "BLOCKED", 0): return false
		if not _ui_reject(formation, TerrainArmy.CombatOrder.MOVE, Vector2i(24, 60), "BLOCKED", 1, true): return false
	for formation in [-1, 4, 2147483647]:
		if not _raw_reject("bad formation %d" % formation, formation, 0, 0.0, 0.0, 0.0, 2): return false
	for target_index in [-1, 16, 2147483647]:
		for kind in [2, 4]:
			if not _raw_reject("bad target %d kind %d" % [target_index, kind], 0, kind, 0.0, 0.0, float(target_index), 4): return false
	for value in [NAN, INF, -INF]:
		for component in range(3):
			if not _raw_reject("nonfinite coordinate component %d" % component, 0, 1, value if component == 0 else 30.5, value if component == 1 else 20.5, value if component == 2 else 0.0, 3): return false
	if not _raw_reject("outside map MOVE", 0, 1, -1.0, 20.5, 0.0, 5): return false
	if not _raw_reject("blocked terrain MOVE", 0, 1, 90.5, 75.5, 0.0, 5): return false
	return true

func _retreat() -> bool:
	if not _begin("6_ROUTED_RETREAT"): return false
	for fixture: Fixture in worlds:
		if not _check(fixture.site.set_formation_fields(1, {"routed": true, "morale": 10.0}), "explicit routed flag plus low morale via Godot binding", fixture.workers): return false
	var before := _centre(worlds[0], 1).distance_to(_centre(worlds[0], 3))
	if not _ui_both(1, TerrainArmy.CombatOrder.RETREAT, Vector2i(25, 60), "OK"): return false
	if not await _advance(300): return false
	var after := _centre(worlds[0], 1).distance_to(_centre(worlds[0], 3))
	if not _check(after - before >= 5.0, "RETREAT gains >= 5 cells from nearest enemy within 10 seconds", {"before": before, "after": after, "gain": after - before}): return false
	if not _ui_reject(1, TerrainArmy.CombatOrder.MOVE, Vector2i(25, 60), "ROUTED", 0): return false
	for kind in [1, 2, 4]:
		if not _raw_reject("routed raw kind %d" % kind, 1, kind, 25.5, 60.5, 12.0, 7): return false
	return true

func _place_running_enemy(seconds: float) -> bool:
	# Fixture input only: translate the whole enemy squad, keeping real native state.
	var centre := Vector2(25.5 + 2.0 * seconds, 20.5)
	for fixture: Fixture in worlds:
		if not fixture.site.set_formation_fields(2, {"cx": centre.x, "cy": centre.y, "goal_x": centre.x, "goal_y": centre.y, "ref_x": centre.x, "ref_y": centre.y, "ref_valid": true}): return _check(false, "kinematic enemy formation input")
		for member in range(PEOPLE):
			if not fixture.site.set_soldier_fields(8 + member, {"px": centre.x, "py": centre.y + member - 1.5}): return _check(false, "kinematic enemy soldier input")
	return true

func _pursue_return() -> bool:
	if not _begin("PURSUE_automatic_RETURN"): return false
	if not _place_running_enemy(0.0): return false
	var target: Dictionary = worlds[0].site.soldier_state(8)
	if not _ui_both(0, TerrainArmy.CombatOrder.PURSUE, Vector2i(floori(float(target.px)), floori(float(target.py))), "OK"): return false
	var issued := _state(worlds[0], 0)
	var origin := Vector2(float(issued.origin_x), float(issued.origin_y))
	var ended_at := -1
	var saw_return := false
	var limit_evidence := {}
	for tick in range(750):
		if not _place_running_enemy(tick * DT) or not _step_pair(): return false
		var order := int(_state(worlds[0], 0).order)
		if order == 5: saw_return = true
		if ended_at < 0 and order != 3:
			ended_at = case_tick
			var person: Dictionary = worlds[0].site.soldier_state(8)
			var target_distance := origin.distance_to(Vector2(float(person.px), float(person.py)))
			var centre_distance := origin.distance_to(_centre(worlds[0], 0))
			limit_evidence = {"action_seconds": case_tick * DT, "target_distance": target_distance, "centre_distance": centre_distance,
				"target_can_act": float(person.hp) > 0.0 and float(person.ko) <= 0.0 and float(person.getup) <= 0.0 and not bool(person.captive)}
			break # The RETURN deadline starts at this actual transition, not at 25 seconds.
		if tick % 60 == 0: await process_frame
	if not _check(saw_return and ended_at > 0 and ended_at <= 601 and bool(limit_evidence.get("target_can_act", false)) and (float(limit_evidence.get("target_distance", 0.0)) > 20.0 or float(limit_evidence.get("centre_distance", 0.0)) > 20.0 or ended_at * DT >= 20.0), "PURSUE automatically enters RETURN on time/range limit with target still actionable", limit_evidence): return false
	var returned_at := -1
	for tick in range(900):
		if not _step_pair(): return false
		if _centre(worlds[0], 0).distance_to(origin) <= 1.5 and int(_state(worlds[0], 0).order) == 0:
			returned_at = case_tick
			break
		if tick % 60 == 0: await process_frame
	return _check(returned_at > ended_at and returned_at - ended_at <= 900, "automatic RETURN reaches origin <= 1.5 cells and HOLD within 30 seconds of transition", {"origin": [origin.x, origin.y], "distance": _centre(worlds[0], 0).distance_to(origin), "order": _state(worlds[0], 0).order, "return_duration": (returned_at - ended_at) * DT if returned_at >= 0 else -1.0})

func _write_result() -> void:
	if out_dir.is_empty(): return
	var file := FileAccess.open(out_dir.path_join("orders.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"ok": not failed, "scope": "L1 synthetic flat-terrain four-team command matrix; real binding and production controller command chain", "result_codes": CODE_NAMES, "teams": 4, "factions": [0, 0, 1, 1], "people_per_team": PEOPLE, "workers": [1, 4], "seed": 7113, "dt": DT, "total_paired_steps": total_steps, "checks": checks, "samples": samples, "fixture_disclosures": ["Only SiteController.show_result and _update_combat_window are replaced with result capture/no-op", "No atlas, textures, render kits, fake images or GPU visual evidence", "PURSUE RETURN uses explicit kinematic enemy input at 2 cells/second", "Command scenarios independently restore the same four-team all-manual baseline", "16 people compare worker configurations; L0 owns large multi-chunk parallel determinism"], "not_covered": ["Formal TerrainLab deployment and complete UI rendering", "Site persistence and item transactions", "Performance gates", "GPU rendering acceptance"]}, "\t", true, true))
	file.close()

func _finish() -> void:
	_write_result()
	for fixture: Fixture in worlds: fixture.close()
	worlds.clear()
	print("CROWD_C2_ORDERS_CHECK ", "FAIL" if failed else "PASS", " paired_steps=", total_steps, " result=", out_dir.path_join("orders.json"))
	print("GATE FAIL: C2 L1 orders" if failed else "GATE OK")
	quit(2 if failed else 0)

func _run() -> void:
	started_ms = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	var base := "res://output/crowd_c2_c3_20261001"
	var at := args.find("--crowd-output")
	if at >= 0 and at + 1 < args.size(): base = args[at + 1]
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	out_dir = base.path_join("orders_l1_%s_%d" % [stamp, Time.get_ticks_msec()])
	if not _check((base.begins_with("res://output/") or base.begins_with("res://native/crowd10k/out_c2/")) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(out_dir)), "new isolated evidence folder", out_dir): _finish(); return
	if not _check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir)) == OK, "create evidence folder"): _finish(); return
	var ignore := FileAccess.open(out_dir.path_join(".gdignore"), FileAccess.WRITE)
	if ignore != null: ignore.close()
	create_timer(240.0).timeout.connect(func() -> void:
		_check(false, "script 240 second timeout")
		_finish())
	if not _check(ClassDB.class_exists("ArmyCrowd"), "real native binding available"): _finish(); return
	for workers in [1, 4]:
		var fixture := Fixture.new()
		worlds.append(fixture)
		if not _check(fixture.create(workers), "create four genuine native formations", workers): _finish(); return
	if not _same_worlds("initial deployment"): _finish(); return
	if not await _movement_matrix(): _finish(); return
	if not _rejection_matrix(): _finish(); return
	if not await _retreat(): _finish(); return
	if not await _pursue_return(): _finish(); return
	_check(true, "all native steps validated, no illegal cells/edges, every paired step hash equal", total_steps)
	_finish()
