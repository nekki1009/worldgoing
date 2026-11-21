extends SceneTree
# Downstream activity is an explicit seam; all source/epoch/sequence/action guards are real.
class GuardLab extends TerrainLab:
	func _fire_step_guard() -> Dictionary: return {"ok": true}
	func _fire_activity() -> bool: return false
	func _siege_tactical_active() -> bool: return false
	func _region_melee_tactical_demand() -> bool: return false

var failed: bool = false

func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error("CC154_OWNER_RESIDUE_FAIL " + label)

func _initialize() -> void:
	# Contract seam: no bound world is advanced; downstream activity is stubbed.
	var lab: TerrainLab = GuardLab.new()
	lab.terrain = TerrainData.new()
	lab.site_controller = SiteController.new()
	lab.add_child(lab.site_controller)
	lab.simulation_speed = 1.0
	lab.fire_action_cursor = 256.049999999988
	var world: float = 15438.000000000002
	var interval: Dictionary = {"epoch": "fire_bcd50399df0a8d8abd75816202bbadda", "sequence": 7721, "action_begin": 256.049999999988, "action_end": 256.0833333333214,
		"game_begin": world, "game_end": world + 2.0, "tactical_seconds": 0.0, "scale": 1.0}
	lab.terrain.site = {"combat_left": 0.0, "simulation_settlement": {"version": 1, "last_settled_game_seconds": 15438.0},
		"fire_settlement": {"version": 1, "epoch": "fire_bcd50399df0a8d8abd75816202bbadda", "sequence": 7720,
			"action_seconds": 256.049999999988, "game_seconds": 15438.0}}
	var before: PackedByteArray = var_to_bytes(lab.terrain.site)
	var small: Dictionary = lab._region_original_interval_guard(interval)
	check(small.ok and before == var_to_bytes(lab.terrain.site), "actual peaceful settlement and fire GAME residues pass the real source guards without mutation")
	for field: String in ["epoch", "sequence", "action_seconds", "game_seconds"]:
		var prior: Variant = lab.terrain.site.fire_settlement[field]
		lab.terrain.site.fire_settlement[field] = "other" if field == "epoch" else (world + 0.000001 if field == "game_seconds" else float(prior) + 1.0)
		before = var_to_bytes(lab.terrain.site)
		var rejected: Dictionary = lab._region_original_interval_guard(interval)
		check(not rejected.ok and rejected.code == "REGION_OWNER_FIRE_SOURCE" and before == var_to_bytes(lab.terrain.site), "wrong epoch/sequence/action or genuine future fire stamp still rejects without mutation: " + field)
		lab.terrain.site.fire_settlement[field] = prior
	lab.terrain.site.simulation_settlement.last_settled_game_seconds = world - 0.000001
	before = var_to_bytes(lab.terrain.site)
	var debt: Dictionary = lab._region_original_interval_guard(interval)
	check(not debt.ok and debt.code == "REGION_OWNER_SOURCE" and before == var_to_bytes(lab.terrain.site), "larger genuine debt remains rejected without stamping or clearing")
	lab.terrain.site.simulation_settlement.last_settled_game_seconds = 15438.0
	lab.terrain.site.combat_left = 1.0
	before = var_to_bytes(lab.terrain.site)
	var combat: Dictionary = lab._region_original_interval_guard(interval)
	check(not combat.ok and combat.code == "REGION_OWNER_SOURCE" and before == var_to_bytes(lab.terrain.site), "same GAME residue exceeds the original combat ACTION conversion and remains rejected")
	lab.terrain.site.erase("simulation_settlement")
	var legacy: Dictionary = lab._region_original_interval_guard(interval)
	check(not legacy.ok and legacy.code == "REGION_OWNER_SOURCE", "legacy settlement remains rejected")
	lab.free()
	print("CC154_OWNER_RESIDUE_", "FAILED" if failed else "PASS", " scope=source guard contract; no world advancement")
	quit(1 if failed else 0)
