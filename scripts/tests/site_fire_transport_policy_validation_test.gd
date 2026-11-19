extends "res://scripts/tests/site_fire_runtime_test.gd"
## Original profile/trajectory math and JSON transport validation only.
## This is not the full-owner save/load or a new projectile gameplay proof.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	print("SITE_FIRE_TRANSPORT_POLICY_VALIDATION_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _wire(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value, "", true, true))
	return parsed if parsed is Dictionary else {}

func _raw(weapon: String = "bow_01", mode: String = "FIRE_ARROW", depth: float = 25.0, distance: float = 8.0) -> Dictionary:
	var profile := SiteCombatRules.fire_ranged_profile(weapon, mode)
	var environment := SiteCombatRules.fire_environment_profile()
	profile.nominal_distance = distance
	profile.smoke_optical_depth = depth
	profile.scatter_multiplier = float(profile.scatter_multiplier) * clampf(1.0 + depth * float(environment.smoke_scatter_per_depth), 1.0, float(environment.smoke_scatter_max))
	var flight := SiteCombatRules.fire_trajectory(Vector3(10.5, 10.5, 1.0), Vector3(10.5 + distance, 10.5, 1.0), profile)
	flight.merge({"projectile_id": 1, "source_member_id": 123, "source_formation_id": 1, "order_serial": 1, "spawn_action": 10.0,
		"source_cell": [10, 10], "shooter": {"ability": 50.0, "training": 50.0, "fatigue": 0.0, "morale": 100.0,
		"armorbonus": 0.0, "weapon": weapon, "armor": "none", "skill": ""}, "profile": profile,
		"elapsed": 0.6, "ember": 0.0, "resolved": false, "aim_key": "ground:660", "position": SiteCombatRules.fire_position(flight, 0.6),
		"config_version": SiteCombatRules.FIRE_RANGED_CONFIG_VERSION})
	for field: String in ["origin", "velocity", "position"]:
		var vector: Vector3 = flight[field]
		flight[field] = [vector.x, vector.y, vector.z]
	return {"version": 1, "config_version": SiteCombatRules.FIRE_RANGED_CONFIG_VERSION, "action_cursor": 10.6, "release_sequence": 1,
		"exposure_sequence": 20, "round_robin": 0, "member_cursor": [], "physical_ranged_enabled": true, "projectiles": [flight], "reservations": [], "orders": []}

func _validation_cases() -> bool:
	var data := _data()
	for raw: Dictionary in [_raw(), _raw("bow_01", "FIRE_ARROW", 1000.0), _raw("crossbow_01", "NORMAL", 0.0, 10.2)]:
		var wire := _wire(raw)
		var before := var_to_bytes(wire)
		var site_before := var_to_bytes(data.site)
		var result := TerrainLab.validate_fire_transport(data, wire)
		if not _check(result.ok and var_to_bytes(wire) == before and var_to_bytes(data.site) == site_before,
			"P4 smoke formula and rain-exhausted/normal flights survive JSON without live/source mutation"): return false
		if not _check(result.state.release_sequence is int and result.state.projectiles[0].projectile_id is int
			and result.state.projectiles[0].position is Vector3 and result.state.projectiles[0].source_cell is Vector2i,
			"JSON integral scalars normalize to original int/vector fields"): return false
	var source := _raw()
	var bads: Array[Dictionary] = []
	var bad: Dictionary = source.duplicate(true); bad.projectiles[0].profile.scatter_multiplier = 1.15; bads.append(bad)
	bad = source.duplicate(true); bad.projectiles[0].profile.smoke_optical_depth = NAN; bads.append(bad)
	bad = source.duplicate(true); bad.projectiles[0].profile.rain_decay = 0.0; bads.append(bad)
	bad = source.duplicate(true); bad.projectiles[0].profile.environment_config_version = "future"; bads.append(bad)
	bad = source.duplicate(true); bad.projectiles[0].resolved = 0; bads.append(bad)
	bad = source.duplicate(true); bad.projectiles[0].projectile_id = 1.25; bads.append(bad)
	bad = source.duplicate(true); bad.projectiles[0].ember = 20.0; bads.append(bad)
	bad = source.duplicate(true); bad.action_cursor = 1.0e12; bads.append(bad)
	bad = source.duplicate(true); bad.projectiles[0].elapsed = 4.0; bads.append(bad)
	bad = source.duplicate(true); bad.projectiles[0].position[0] = -1.0; bads.append(bad)
	bad = source.duplicate(true); bad.projectiles[0].profile.extra_owner = {}; bads.append(bad)
	for malformed: Dictionary in bads:
		var before := var_to_bytes(malformed)
		if not _check(not TerrainLab.validate_fire_transport(data, malformed).ok and var_to_bytes(malformed) == before,
			"Corrupt profile, physics, numeric type or phase rejects without normalization of source"): return false
	var target := {"type": "ground", "cell": [20, 10]}
	source.orders = [{"group": 1, "serial": 1, "issuer_id": 123, "enabled": true, "mode": "FIRE_ARROW", "target": target.duplicate(true), "release_ids": [[123, 1]], "ranged_fire_policy": {}}]
	source.reservations = [{"person_id": 124, "formation_id": 1, "target": target.duplicate(true), "mode": "FIRE_ARROW", "serial": 1,
		"stamp": {"holder": "person:124", "version": 2, "cargo": {"fire_arrow": 2}}, "source": [10, 10], "ready_at": 11.4, "deadline": 11.65}]
	var result := TerrainLab.validate_fire_transport(data, _wire(source))
	if not _check(result.ok and result.state.reservations[124].stamp.cargo.fire_arrow is int,
		"Unpaid preparation retains exact original finite cargo stamp after JSON"): return false
	bad = source.duplicate(true); bad.reservations[0].serial = 2
	if not _check(not TerrainLab.validate_fire_transport(data, bad).ok, "Preparation cannot attach to another original order generation"): return false
	bad = source.duplicate(true); bad.reservations[0].stamp.cargo.fire_arrow = 0.5
	if not _check(not TerrainLab.validate_fire_transport(data, bad).ok, "Fractional source ammunition rejected"): return false
	bad = source.duplicate(true); bad.reservations[0].ready_at = 10.7; bad.reservations[0].deadline = 10.95; bad.reservations[0].mode = "NORMAL"; bad.orders[0].mode = "NORMAL"
	return _check(not TerrainLab.validate_fire_transport(data, bad).ok, "NORMAL cannot gain an unversioned future preparation delay")

func _capture_barrier() -> bool:
	var lab := TerrainLab.new()
	lab.terrain = _data()
	lab._siege_collect_contacts = true
	var collect := lab.capture_fire_transport()
	lab._siege_collect_contacts = false
	lab._siege_contact_batch.append({"type": "direct_structure"})
	var queue := lab.capture_fire_transport()
	lab._siege_contact_batch.clear()
	var complete := lab.capture_fire_transport()
	lab.free()
	return _check(not collect.ok and not queue.ok and complete.ok, "Only completed original contact collection/flush admits transport capture")

func _run() -> void:
	if not _validation_cases() or not _capture_barrier() or not _policy_cases() or not _policy_capture(): _finish(false, "transport and policy validation"); return
	_finish(not failed, "schema/math leaf only; full-owner load, body clocks and Store admission remain required")

# UNRUN additions to the previous transport schema/math leaf.
func _policy(target: Dictionary, mode: String = "IGNITE_ONLY") -> Dictionary:
	return {"version": "fire_policy_v1", "serial": 1, "main_serial": 7, "mode": mode, "service": "",
		"last_decision_step": -1, "allow": true, "reason": "EVALUATING", "confirmations": {},
		"wait_deadline": 10.6, "pending_threshold": 100.0 if target.type == "structure" else 40.0}

func _policy_order(target: Dictionary, mode: String = "IGNITE_ONLY") -> Dictionary:
	return {"group": 1, "serial": 1, "issuer_id": 123, "enabled": true, "mode": "FIRE_ARROW",
		"target": target.duplicate(true), "release_ids": [[123, 1]], "ranged_fire_policy": _policy(target, mode)}

func _policy_cases() -> bool:
	var data := _data()
	var ground := {"type": "ground", "cell": [20, 10]}
	var structure := {"type": "structure", "feature_id": "9", "part_id": "roof"}
	var area := {"type": "area", "cells": [[20, 10], [21, 10]]}
	var valid: Array[Dictionary] = []
	var raw := _raw(); raw.orders = [_policy_order(ground)]; valid.append(raw)
	raw = _raw(); raw.orders = [_policy_order(structure, "DESTROY_FUNCTION")]
	raw.orders[0].ranged_fire_policy.merge({"last_decision_step": 53, "allow": false,
		"reason": "OBSERVED_FUNCTION_DISABLED", "service": "production"}, true); valid.append(raw)
	raw = _raw(); raw.orders = [_policy_order(area)]
	var confirmations := {}
	for cell: Array in area.cells:
		confirmations["ground:%d" % data.index(Vector2i(int(cell[0]), int(cell[1])))] = {"step": 53, "count": 3}
	raw.orders[0].ranged_fire_policy.merge({"last_decision_step": 53, "allow": false,
		"reason": "OBSERVED_STABLE_BURNING", "confirmations": confirmations}, true); valid.append(raw)
	for reason: String in ["PAID_FLIGHTS_PENDING", "OBSERVATION_WAIT"]:
		raw = _raw(); raw.orders = [_policy_order(ground)]
		raw.orders[0].ranged_fire_policy.merge({"last_decision_step": 53, "allow": false,
			"reason": reason, "wait_deadline": 14.8}, true); valid.append(raw)
	raw = _raw(); raw.orders = [_policy_order(ground)]; raw.orders[0].ranged_fire_policy = {}; valid.append(raw)
	raw = _raw(); raw.orders = [_policy_order(structure)]
	raw.orders[0].group = -123; raw.orders[0].ranged_fire_policy.main_serial = 0; valid.append(raw)
	for source: Dictionary in valid:
		var wire := _wire(source)
		var before := var_to_bytes(wire)
		var site_before := var_to_bytes(data.site)
		var result := TerrainLab.validate_fire_transport(data, wire)
		if not _check(result.ok and var_to_bytes(wire) == before and var_to_bytes(data.site) == site_before,
			"Original continuous/ignite/function policy progress round-trips JSON without consulting live heat"): return false
		var group := int(source.orders[0].group)
		var policy: Dictionary = result.state.orders[group].ranged_fire_policy
		if not policy.is_empty() and not _check(policy.serial is int and policy.main_serial is int
			and policy.last_decision_step is int and policy.pending_estimate.is_empty(),
			"Policy generation/progress normalize privately and derived forecast starts empty"): return false
	var source := valid[0]
	var bads: Array[Dictionary] = []
	var bad: Dictionary = source.duplicate(true); bad.orders[0].ranged_fire_policy.serial = 2; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].ranged_fire_policy.main_serial = 0.5; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].ranged_fire_policy.version = "future"; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].ranged_fire_policy.last_decision_step = 54; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].ranged_fire_policy.wait_deadline = INF; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].ranged_fire_policy.wait_deadline = 14.9; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].ranged_fire_policy.pending_threshold = 100.0; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].ranged_fire_policy.pending_estimate = {}; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].ranged_fire_policy.allow = 1; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].ranged_fire_policy.allow = false; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].ranged_fire_policy.mode = "DESTROY_FUNCTION"; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].ranged_fire_policy.mode = "CONTINUOUS"; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].ranged_fire_policy.service = "parallel_owner"; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].mode = "NORMAL"; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].target = {"type": "person", "person_id": 77}; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].target.cell.append(0); bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].group = -123; bads.append(bad)
	bad = source.duplicate(true); bad.orders[0].ranged_fire_policy.erase("reason"); bads.append(bad)
	bad = valid[2].duplicate(true); bad.orders[0].ranged_fire_policy.confirmations["ground:0"] = {"step": 53, "count": 3}; bads.append(bad)
	var target_key := "ground:%d" % data.index(Vector2i(20, 10))
	bad = valid[2].duplicate(true); bad.orders[0].ranged_fire_policy.confirmations[target_key].step = 54; bads.append(bad)
	bad = valid[2].duplicate(true); bad.orders[0].ranged_fire_policy.confirmations[target_key].count = 4; bads.append(bad)
	bad = valid[2].duplicate(true); bad.orders[0].ranged_fire_policy.confirmations[target_key].count = 2; bads.append(bad)
	bad = valid[2].duplicate(true); bad.orders[0].ranged_fire_policy.confirmations[target_key].extra = true; bads.append(bad)
	bad = valid[3].duplicate(true); bad.orders[0].ranged_fire_policy.wait_deadline = 10.6; bads.append(bad)
	for malformed: Dictionary in bads:
		var before := var_to_bytes(malformed)
		var site_before := var_to_bytes(data.site)
		if not _check(not TerrainLab.validate_fire_transport(data, malformed).ok and var_to_bytes(malformed) == before
			and var_to_bytes(data.site) == site_before, "Corrupt policy shape/generation/typed target/progress rejected atomically"): return false
	return true

func _policy_capture() -> bool:
	var lab := TerrainLab.new()
	lab.terrain = _data()
	lab.fire_action_cursor = 10.6
	var army := TerrainArmy.new()
	army.team_id = 1
	army.combat_enabled = true
	army.ranged_order_serial = 1
	army.ranged_order_issuer_id = 123
	army.ranged_enabled = true
	army.ranged_ammo_mode = "FIRE_ARROW"
	army.ranged_target = {"type": "ground", "cell": [20, 10]}
	army.ranged_fire_policy = _policy(army.ranged_target)
	army.ranged_fire_policy.pending_estimate = {"ground:660": 99.0}
	lab.combat_armies.append(army)
	var before := var_to_bytes(army.ranged_fire_policy)
	var result := lab.capture_fire_transport()
	var original_same := var_to_bytes(army.ranged_fire_policy) == before
	var original_after: Dictionary = army.ranged_fire_policy.duplicate(true)
	var expected_policy: Dictionary = army.ranged_fire_policy.duplicate(true)
	expected_policy.erase("pending_estimate")
	var wire_only: bool = bool(result.get("ok", false)) and result.state.orders.size() == 1 \
		and result.state.orders[0].ranged_fire_policy == expected_policy
	lab.combat_armies.clear()
	army.free()
	lab.free()
	return _check(original_same and wire_only, "Capture strips only cloned derived forecast and preserves original owner command progress: %s" % str({
		"capture": result, "original_policy": original_after, "expected_policy": expected_policy}))
