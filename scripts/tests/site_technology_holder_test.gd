extends SceneTree
## Pure candidate contract. Actual Region extraction/journal tests remain separate.
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _family(known: bool = false) -> Dictionary:
	var purpose := "F07:relearn:" + JSON.stringify(["A", 1]) if known else "F07:first"
	return {"version": 3, "complete": true, "members": [], "offices": {}, "family_id": "0123456789abcdef0123456789abcdef", "technology": {
		"version": 1, "known": ["F07"] if known else [], "holder_site_id": "A", "epoch": 1, "next_project": 2, "active": 1, "projects": [{
			"id": 1, "purpose": purpose, "tech_id": "F07", "rules_version": 1, "closed": false, "executor": {"site_id": "A", "person_id": 1},
			"next_attempt": 3, "receipts": [{"site_id": "A", "person_id": 1, "attempt": 1}, {"site_id": "A", "person_id": 1, "attempt": 2}],
			"budget": {"authorization_id": 1, "source_site_id": "A", "holder": "depot", "grantor": {"site_id": "A", "person_id": 1}, "status": "granted", "cap": {"wood": 12, "fiber": 6}, "spent": {"wood": 8, "fiber": 4}},
			"consents": [{"site_id": "A", "team_id": 0, "person_id": 1, "purpose": purpose, "decider_id": 1, "revision": 0, "status": "accepted"}]
		}]}}

func _run() -> void:
	for known: bool in [false, true]:
		var original := _family(known)
		var before := original.duplicate(true)
		_expect(Technology.valid_family_tech(original.technology), "source schema")
		var departure := Technology.prepare_holder_departure("A", original, {1: true, 2: true}, "player", "first-trip")
		_expect(bool(departure.ok), "original departure candidate")
		if not departure.ok: continue
		_expect(original == before, "departure cannot mutate caller")
		_expect(Technology.is_holder_reference(departure.source_family.technology), "source keeps reference")
		_expect(not Technology.is_holder_reference(departure.moving_family.technology), "only party carries full archive")
		_expect(departure.source_family.technology.epoch == 2 and departure.moving_family.technology.epoch == 2, "departure epoch")
		_expect(departure.moving_family.technology.active == 0, "no implicit job at new holder")
		var old_project: Dictionary = original.technology.projects[0]
		var transit_project: Dictionary = departure.moving_family.technology.projects[0]
		_expect(transit_project.receipts == old_project.receipts, "immutable paid evidence")
		_expect(transit_project.budget.spent == old_project.budget.spent and transit_project.budget.status == "revoked", "same spent, revoked source")
		_expect(transit_project.consents[0].status == "revoked", "arrival must obtain actual team approval")
		var reference := {"type": "family", "namespace": "family:" + original.family_id, "lineage": 1}
		var arrival := Technology.prepare_holder_arrival(reference, departure.moving_family, {}, "B", {"maps": {"person": {"1": 11, "2": 12}}})
		_expect(bool(arrival.ok), "true original ID map arrival")
		if not arrival.ok: continue
		var holder: Dictionary = arrival.destination_family.technology
		_expect(Technology.local_holder(holder, "B") and holder.epoch == 3, "destination only full holder")
		_expect(Technology.is_holder_reference(arrival.moving_family.technology), "consumed party now reference")
		_expect(holder.projects[0].receipts == old_project.receipts, "arrival immutable evidence")
		_expect(Technology.stages(holder.projects[0], {"site_id": "B", "person_id": 11}, holder.person_links) == 2, "actual mover keeps 2 of 3")
		_expect(Technology.stages(holder.projects[0], {"site_id": "B", "person_id": 12}, holder.person_links) == 0, "other original mover gets no trial credit")
		_expect(Technology.project_purpose_matches(holder.projects[0], {"site_id": "B", "person_id": 11}, holder.person_links) == known, "same immutable relearn purpose")
		var resumed := holder.duplicate(true)
		resumed.active = 1
		resumed.projects[0].executor = {"site_id": "B", "person_id": 11}
		resumed.projects[0].budget.source_site_id = "B"
		resumed.projects[0].budget.grantor = {"site_id": "B", "person_id": 11}
		resumed.projects[0].budget.status = "granted"
		_expect(Technology.valid_family_tech(resumed), "same project real destination regrant")
		resumed.projects[0].next_attempt = 4
		resumed.projects[0].receipts.append({"site_id": "B", "person_id": 11, "attempt": 3})
		resumed.projects[0].budget.spent = {"wood": 12, "fiber": 6}
		_expect(Technology.valid_family_tech(resumed) and Technology.stages(resumed.projects[0], resumed.projects[0].executor, resumed.person_links) == 3, "third actual receipt completes same person")
		var duplicate := Technology.prepare_holder_arrival(reference, departure.moving_family, arrival.destination_family, "B", {"maps": {"person": {"1": 11, "2": 12}}})
		_expect(not duplicate.ok and duplicate.code == "DUPLICATE_HOLDER", "cannot overwrite another full holder")
		var forked: Dictionary = departure.source_family.duplicate(true)
		forked.technology.holder_site_id = "travel:other-party"
		var conflict := Technology.prepare_holder_arrival(reference, departure.moving_family, forked, "B", {"person": {"1": 11, "2": 12}})
		_expect(not conflict.ok and conflict.code == "HOLDER_CONFLICT", "same epoch cannot name a different holder")
		var wrong: Dictionary = arrival.destination_family.duplicate(true)
		wrong.family_id = "1123456789abcdef0123456789abcdef"
		_expect(not Technology.prepare_holder_arrival(reference, departure.moving_family, wrong, "B", {"person": {"1": 11, "2": 12}}).ok, "different families do not merge")
		_expect(not Technology.prepare_holder_arrival(reference, departure.moving_family, {}, "B", {"person": {"1": 11, "2": 11}}).ok, "injective original mapping required")
		_expect(not Technology.prepare_holder_arrival(reference, departure.moving_family, {}, "B", {"person": {"1": 11}}).ok, "missing real mover rejected")
		_expect(not Technology.prepare_holder_arrival(reference, departure.moving_family, {}, "B", {"person": {"1": 11, "2": 12, "9": 99}}).ok, "bystander mapping rejected")
		var second_departure := Technology.prepare_holder_departure("B", arrival.destination_family, [11, 12], "player", "return-trip")
		_expect(bool(second_departure.ok), "second original departure")
		if second_departure.ok:
			var returned := Technology.prepare_holder_arrival(reference, second_departure.moving_family, departure.source_family, "A", {"person": {"11": 1, "12": 2}})
			_expect(bool(returned.ok), "return to earlier original local ID without cycle")
			if returned.ok:
				var tech: Dictionary = returned.destination_family.technology
				_expect(Technology.valid_family_tech(tech) and Technology.stages(tech.projects[0], {"site_id": "A", "person_id": 1}, tech.person_links) == 2, "return preserves original 2 of 3")
		var npc := Technology.prepare_holder_departure("A", original, [2], "npc", "npc-trip")
		_expect(bool(npc.ok) and npc.source_family == original and Technology.is_holder_reference(npc.moving_family.technology), "NPC traveler cannot clone source holder")
		_expect(not Technology.scope_known(npc.moving_family.technology, "F07"), "reference never advertises empty or known archive")
		var departing_executor := Technology.prepare_holder_departure("A", original, [1], "npc", "prepared-researcher-trip")
		_expect(bool(departing_executor.ok), "NPC prepared researcher departure has a valid original source candidate")
		if departing_executor.ok:
			var retained: Dictionary = departing_executor.source_family.technology
			_expect(retained.active == 0 and retained.projects[0].executor.is_empty(), "departing prepared selection no longer points at an absent local person")
			_expect(retained.projects[0].budget.status == "revoked" and retained.projects[0].consents[0].status == "revoked", "departing prepared selection requires new actual budget and consent")
			_expect(retained.epoch == original.technology.epoch and retained.known == original.technology.known and retained.projects[0].receipts == original.technology.projects[0].receipts and retained.projects[0].budget.spent == original.technology.projects[0].budget.spent, "source keeps holder generation and true paid historical work")
			_expect(Technology.is_holder_reference(departing_executor.moving_family.technology) and original == before, "NPC still carries only a reference and preparation leaves original family unchanged")
	_expect(not Technology.valid_person_links([{"from": {"site_id": "A", "person_id": 1}, "to": {"site_id": "B", "person_id": 2}}, {"from": {"site_id": "B", "person_id": 2}, "to": {"site_id": "A", "person_id": 1}}]), "alias cycle rejected")
	_expect(not Technology.valid_person_links([{"from": {"site_id": "A", "person_id": 1}, "to": {"site_id": "B", "person_id": 2}}, {"from": {"site_id": "A", "person_id": 3}, "to": {"site_id": "B", "person_id": 2}}]), "alias merge rejected")
	_expect(not Technology.valid_family_tech({"version": 3, "holder_site_id": "B", "epoch": 1, "known": []}), "reference cannot store copied archive fields")
	print("TECHNOLOGY_HOLDER_CANDIDATE %s %d checks" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
