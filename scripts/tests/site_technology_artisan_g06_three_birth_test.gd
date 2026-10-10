extends "res://scripts/tests/site_technology_artisan_production_base.gd"
## Actual original THREE_FACTIONS first transaction with isolated all-four policy.
## Not the ordinary release/default, nor production/navigation proof for three teams.

func _three_facts(lab: TerrainLab, state: Dictionary) -> void:
	_require(Artisans.validate_receipt(state.get("technology_artisans"), state) and state.technology_artisans.scenario_id == Artisans.THREE_FACTIONS and state.technology_artisans.categories == Artisans.CATEGORIES, "Original strict finite three-faction birth receipt preserves actual full policy")
	_require(state.technology_artisans.grants.size() == 12 and lab.combat_armies.size() == 3 and state.armies.size() == 3 and not state.has("family"), "Exactly original 15 NPCs/12 named grants across three original teams, with no automatic family")
	var ids := {}
	for team: TerrainArmy in lab.combat_armies:
		_require(team.combat_units.size() == 5 and team.faction_id in [0, 1, 2], "Each original configured faction has exactly five true rows")
		for index: int in team.combat_units.size():
			var identity: int = team.combat_identity(index)
			_require(identity > 1 and not ids.has(identity), "True allocator gives each original faction row one globally unique person ID")
			ids[identity] = true
			var learned: Dictionary = team.combat_units[index].get("technology", {})
			_require(learned.is_empty() if index == 0 else learned == {"version": 1, "learned": [Artisans.CATEGORIES[index - 1]]}, "Precisely the original configured named row learned one category; original commander learns none")
	_require(ids.size() == 15 and lab.character.person_id == 1 and lab.character.technology.is_empty(), "Original Actor is preserved as person one with no faction skill flag")


func _run() -> void:
	var source: RegionData = _g06_source()
	var lab: TerrainLab = _source_lab("g06_three_actual")
	var world: String = _world("g06_three_actual")
	var slot := CandidatePolicySlot.new()
	slot.candidate_categories = Artisans.CATEGORIES.duplicate() # Isolated hypothetical accepted release input only.
	slot.folder = "user://region_lab/worlds/%s/slots/%s" % [world, SLOT]
	lab.site_controller._initial_world_candidate = slot
	var begun: Dictionary = lab.site_controller.open_fixed_world(manifest_path, world, SLOT, START, true, Artisans.THREE_FACTIONS)
	_require(begun.ok and int(slot._marker.generation) == 1 and not slot.initialization_pending(), "Original Controller/Slot actual three-faction first transaction commits once", begun)
	_freeze(lab)
	var data: TerrainData = lab.terrain
	var pin: Dictionary = data.site.world_pin.duplicate(true)
	_require(pin.size() >= 9 and pin.manifest_sha256 == source.manifest_hash and pin.base_revision == source.manifest.base_revision and data.parameters.has("fixed_base") and pin.technology_policy.categories == Artisans.CATEGORIES, "Actual complete checked geographic pin and all-four immutable policy")
	_require(int(birth_counts[lab.get_instance_id()]) == 1 and lab.region_bind_receipt(data).get("complete", false), "Exactly one original disposable birth transaction publishes all three actual armies with complete formal bind")
	_three_facts(lab, data.site)
	_require(lab.site_controller._capture_for_save().ok, "Actual all-three owners capture every original row/item")
	var facts: String = _facts(data.site)
	var birth: Dictionary = data.site.technology_artisans.duplicate(true)
	var before: PackedByteArray = var_to_bytes(data.site)
	var replay: Dictionary = lab.prepare_initial_artisan_birth(data, Artisans.THREE_FACTIONS, Artisans.CATEGORIES)
	_require(replay.ok and not replay.changed and var_to_bytes(data.site) == before, "Actual original all-four three-faction birth cannot be replayed")
	_require(lab.site_controller.save_to(lab.site_controller.save_path).ok, "Original Store/Slot saves full-pin all-three state")
	var cold: Dictionary = slot._load_checked(slot.site_path(START), START)
	_require(cold.ok and cold.data.site.world_pin == pin and cold.data.site.technology_artisans == birth and _facts(cold.data.site) == facts, "True original read strictly preserves pin/all actors/all three armies/items and bounded grants", cold)
	var reopened: TerrainLab = _source_lab("g06_three_reopen")
	var loaded: Dictionary = reopened.site_controller.open_fixed_world(manifest_path, world, SLOT, Vector2i(-1, -1), false)
	_require(loaded.ok, "Actual original full-graph cold reopen/bind", loaded)
	_freeze(reopened)
	_require(int(birth_counts[reopened.get_instance_id()]) == 0 and _facts(reopened.terrain.site) == facts and reopened.region_bind_receipt(reopened.terrain).get("complete", false), "Reopen issues no person/skill/item or replacement birth")
	_three_facts(reopened, reopened.terrain.site)
	var actual_before: PackedByteArray = var_to_bytes(reopened.terrain.site)
	var again: Dictionary = reopened.prepare_initial_artisan_birth(reopened.terrain, Artisans.PRIMARY, Artisans.CATEGORIES)
	_require(again.ok and not again.changed and var_to_bytes(reopened.terrain.site) == actual_before, "Later different configuration cannot rewrite frozen historical three-faction receipt")
	report.three_factions = {"categories": Artisans.CATEGORIES, "actual_npcs": 15, "named_grants": 12, "pin": pin, "one_generation": true, "no_auto_family": true, "source_rule_unmodified": true, "not_three_team_production_or_default_admission": true}
	_finish()


func _finish(reason: String = "") -> void:
	if finished: return
	finished = true
	if not reason.is_empty(): failures.append(reason)
	for lab: TerrainLab in labs:
		if is_instance_valid(lab): lab.free()
	TerrainArmy.release_contact_source()
	print("TECH_AI_02_G06_THREE_BIRTH_REPORT: " + JSON.stringify({"checks": checks, "failures": failures, "cases": report, "fixture": root_path, "formal_release": false, "default_policy": []}, "", true, true))
	print("TECH_AI_02_G06_THREE_BIRTH_", "PASS" if failures.is_empty() else "FAILED", " scope=true_original_first_birth_full_pin_cold_no_regrant_not_production_FULL_G06_or_release")
	quit(0 if failures.is_empty() else 1)
