extends SceneTree
const Store = preload("res://scripts/terrain_lab/site_store.gd")
var failed: bool = false
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("REGION_RANGED_SIEGE_SNAPSHOT_CONTRACT_FAIL " + label)

func _initialize() -> void:
	var data: TerrainData = TerrainData.new()
	data.size = Vector2i(4, 4)
	var state: Dictionary = {"id": "site:test", "features": {}, "vehicles": {}}
	for kind: String in ["ballista", "traction_trebuchet", "counterweight_trebuchet"]:
		for stage: String in ["loading", "aiming", "recovering"]:
			var rule: Dictionary = SiteCombatRules.siege_attack(kind)
			var vehicle: Dictionary = {"id": "1", "kind": kind, "phase": stage, "move": {}, "rng_state": 100,
				"holder": {"version": 8 if stage == "recovering" else 7}, "next_attack_seq": 2 if stage == "recovering" else 1,
				"action": {"stage": stage, "elapsed": float(rule[stage]) * 0.5, "cargo_version": 7, "rng_state": 100,
				"multiplier": 0.5, "target": {"type": "ground", "cell": [0, 0]}}}
			var before: PackedByteArray = var_to_bytes([state, vehicle])
			check(Store._region_siege_transient(data, state, vehicle, {}), "genuine original ranged partial shape " + kind + "/" + stage)
			check(before == var_to_bytes([state, vehicle]), "schema admission does not progress or mutate partial work")
			for field: String in ["cargo_version", "rng_state", "multiplier", "target"]:
				var missing: Dictionary = vehicle.duplicate(true)
				missing["action"].erase(field)
				check(not Store._region_siege_transient(data, state, missing, {}), "missing original source field rejects: " + field)
			var excessive: Dictionary = vehicle.duplicate(true)
			excessive["action"]["elapsed"] = float(rule[stage]) + 1.0
			check(not Store._region_siege_transient(data, state, excessive, {}), "future action work rejects")
			var native: Dictionary = vehicle.duplicate(true)
			native["action"]["native_token"] = 1
			check(not Store._region_siege_transient(data, state, native, {}), "native transaction cannot enter GD snapshot")
			var invalid_target: Dictionary = vehicle.duplicate(true)
			invalid_target["action"]["target"] = {"type": "ground", "cell": [99, 99]}
			check(not Store._region_siege_transient(data, state, invalid_target, {}), "out of Site target rejects")
			var stale: Dictionary = vehicle.duplicate(true)
			if stage == "recovering": stale["holder"]["version"] = 7
			else: stale["action"]["cargo_version"] = 6
			check(not Store._region_siege_transient(data, state, stale, {}), "unpaid recovery or stale unspent holder rejects")
			if stage != "recovering":
				stale = vehicle.duplicate(true)
				stale["action"]["rng_state"] = 101
				check(not Store._region_siege_transient(data, state, stale, {}), "changed unspent RNG source rejects")
			var wrong_kind: Dictionary = vehicle.duplicate(true)
			wrong_kind["kind"] = "ram"
			check(not Store._region_ranged_siege_action(data, state, wrong_kind, {}), "ranged schema cannot authorize ram")
			var due: Dictionary = vehicle.duplicate(true)
			due["action"]["elapsed"] = float(rule[stage]) + 0.001
			var context: Dictionary = {"effects_complete": false, "fire_epoch": "fire:test", "fire_sequence": 7,
				"game_seconds": 200.0, "action_seconds": 2.0, "endpoint_payload": {"interval_complete": true,
				"epoch": "fire:test", "sequence": 7, "game_end": 200.0, "action_end": 2.0, "fire_action_begin": 1.99, "fire_action_end": 2.0}}
			check(Store._region_siege_transient(data, state, due, {}, context), "deferred due work retains only its original paid interval budget")
			check(not Store._region_siege_transient(data, state, due, {}), "due overshoot cannot invent an absent pending point")
			context["endpoint_payload"]["sequence"] = 8
			check(not Store._region_siege_transient(data, state, due, {}, context), "foreign pending sequence cannot authorize due work")
			if stage == "recovering":
				var wrong_phase: Dictionary = vehicle.duplicate(true)
				wrong_phase["phase"] = "idle"
				check(not Store._region_siege_transient(data, state, wrong_phase, {}), "idle cannot carry a paid recovery stage")
				wrong_phase["phase"] = "wrecked"
				check(Store._region_siege_transient(data, state, wrong_phase, {}), "original wrecked paid-recovery exception remains")
	print("REGION_RANGED_SIEGE_SNAPSHOT_CONTRACT_", "FAILED" if failed else "PASS", " checks=", checks)
	quit(1 if failed else 0)
