extends SceneTree
const Battle = preload("res://scripts/region_lab/region_gameplay_battle.gd")
const Clock = preload("res://scripts/region_lab/region_gameplay_clock.gd")
var failed := false
var checks := 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failed = true
		push_error("CC151_ARRIVAL_MODE_FAIL: " + label)
	return ok

func _initialize() -> void:
	var raw: Variant = str_to_var(FileAccess.get_file_as_string("res://scripts/tests/fixtures/cc151_registry_reject.variant"))
	if not check(raw is Dictionary and raw.get("battle") is Dictionary, "actual typed rejection fixture loads"): quit(1); return
	var original: Dictionary = raw.battle.duplicate(true)
	# Restore only the pre-arrival admitted mode to exercise the producer that changed it.
	original["mode"] = "cold_exact"
	# A printed diagnostic is not the original hash-preserving transport.
	original.siege["source_sha256"] = Battle._siege_source_hash(original.siege)
	var metadata: Dictionary = Battle.validate_siege_metadata(original.siege)
	if not check(metadata.ok, "reconstructed typed source passes original metadata admission " + str(metadata)): quit(1); return
	var invalid: Dictionary = original.siege.duplicate(true)
	invalid["source_sha256"] = "0".repeat(64)
	var invalid_before: PackedByteArray = var_to_bytes(invalid)
	var invalid_result: Dictionary = Battle.validate_siege_metadata(invalid)
	check(not invalid_result.ok and invalid_before == var_to_bytes(invalid), "original metadata validator still rejects a changed digest without mutation")
	var registry: Dictionary = Clock.empty_registry()
	registry.battles[str(original.id)] = original
	var slot: RegionSaveSlot = RegionSaveSlot.new()
	slot.control = {"logical_game_seconds": 200.0, "active_site_id": "other", "region_gameplay": registry}
	var attackers: Array[Dictionary] = []
	var defenders: Array[Dictionary] = []
	for identity: Variant in original.attackers: attackers.append({"person_id": int(identity)})
	for identity: Variant in original.defenders: defenders.append({"person_id": int(identity)})
	var incoming: int = 1
	for identity: Variant in original.attackers + original.defenders: incoming = maxi(incoming, int(identity) + 1)
	attackers.append({"person_id": incoming})
	var state: Dictionary = {"id": str(original.site_id), "actors": {}, "armies": [
		{"faction_id": int(original.siege.attacker_faction), "units": attackers},
		{"faction_id": int(original.siege.defender_faction), "units": defenders}]}
	var party: Dictionary = {"person_ids": [incoming]}
	var mapping: Dictionary = {"maps": {"person": {str(incoming): incoming}}}
	var before: PackedByteArray = var_to_bytes(slot.control)
	var witnessed: Dictionary = {"resolve_battle_people": func(_battle: Dictionary) -> Dictionary:
		return {"ok": true, "people": {"unit": {"legal_targets": [1]}}}}
	var result: Dictionary = slot._region_arrival_battle_candidate(state, state, party, mapping, "cc151", witnessed, false)
	if not check(result.ok and result.battle.mode == "cold_exact" and result.battle.attackers.has(incoming), "normal arrival at200 retains the exact siege consumer and incoming membership"): quit(1); return
	check(before == var_to_bytes(slot.control), "candidate preparation preserves original control registry and source")
	check(var_to_bytes(result.battle.siege) == var_to_bytes(original.siege), "candidate keeps the original accepted siege metadata and epoch")
	var admitted: Dictionary = registry.duplicate(true)
	admitted.battles[str(original.id)] = result.battle
	var accepted: Dictionary = Clock.validate_registry(admitted, 200.0)
	check(accepted.ok, "same original registry validator admits exact siege at200 " + str(accepted))
	var bytes: PackedByteArray = var_to_bytes(admitted)
	var rejected: Dictionary = Clock.validate_registry(admitted, 198.0)
	check(not rejected.ok and str(rejected.code) == "INVALID_SIEGE_SOURCE" and bytes == var_to_bytes(admitted), "genuine future siege remains rejected without mutation")
	var no_contact: Dictionary = {"resolve_battle_people": func(_battle: Dictionary) -> Dictionary:
		return {"ok": true, "people": {"unit": {"legal_targets": []}}}}
	result = slot._region_arrival_battle_candidate(state, state, party, mapping, "cc151", no_contact, false)
	check(result.ok and var_to_bytes(result.battle) == var_to_bytes(original) and before == var_to_bytes(slot.control), "no-contact fallback returns the unchanged prior battle")
	var bad: Dictionary = {"resolve_battle_people": func(_battle: Dictionary) -> Dictionary:
		return {"ok": false, "code": "CC151_WITNESS_REJECT"}}
	result = slot._region_arrival_battle_candidate(state, state, party, mapping, "cc151", bad, false)
	check(not result.ok and str(result.code) == "CC151_WITNESS_REJECT" and before == var_to_bytes(slot.control), "witness rejection preserves original control and battle")
	var ordinary: Dictionary = Battle.create({"id": "ordinary", "site_id": str(original.site_id), "attackers": original.attackers,
		"defenders": original.defenders, "game_time": 100.0})
	registry.battles = {"ordinary": ordinary.battle}
	result = slot._region_arrival_battle_candidate(state, state, party, mapping, "cc151", witnessed, false)
	check(result.ok and result.battle.mode == "formula_active", "ordinary two-side battle retains its existing formula consumer")
	print("CC151_ARRIVAL_MODE_", "FAILED" if failed else "PASS", " checks=", checks, " scope=producer unit at200; not full Region runtime")
	quit(1 if failed else 0)
