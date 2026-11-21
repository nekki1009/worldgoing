class_name SiteTechnologyArtisans
extends RefCounted
## Pure, finite birth candidates. Original world/scenario/people/Store owners
## establish the birth transaction, apply candidates and persist the receipt.
## No spawn, control, jobs, clock, mutable registry or automatic read upgrade.

const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Policy = preload("res://scripts/terrain_lab/site_technology_policy.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const CATEGORIES := ["F04", "F06", "F11", "F12"]
const PRIMARY := "existing_primary_army_artisans_v1"
const THREE_FACTIONS := "existing_three_armies_artisans_v1"

## Explicit proposals for owners that ALREADY have these original NPC rows.
## Formal TerrainLab currently creates empty team shells, so neither proposal
## supplies a population nor makes its default scene playable by itself.
static func scenario_config(scenario_id: String) -> Dictionary:
	if scenario_id not in [PRIMARY, THREE_FACTIONS]: return {}
	var sources := [{"source_slot": "DemoArmy", "faction_id": 0}]
	if scenario_id == THREE_FACTIONS:
		sources.append({"source_slot": "OpposingArmy", "faction_id": 1})
		sources.append({"source_slot": "ThirdArmy", "faction_id": 2})
	var assignments: Array = []
	for source: Dictionary in sources:
		for index: int in CATEGORIES.size():
			assignments.append({"slot_id": str(source.source_slot) + ":" + CATEGORIES[index],
				"source_slot": source.source_slot, "faction_id": source.faction_id,
				"unit_index": index + 1, "skills": [CATEGORIES[index]]})
	return {"version": 1, "scenario_id": scenario_id, "assignments": assignments}

static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func _unchanged(state: Dictionary, code: String) -> Dictionary:
	return {"ok": true, "changed": false, "code": code, "state": state.duplicate(true), "grants": [], "expected": []}

static func _config(raw: Variant) -> Dictionary:
	if not Technology.keys(raw, ["version", "scenario_id", "assignments"]) or not raw.scenario_id is String: return {}
	var original := scenario_config(str(raw.scenario_id))
	return original if not original.is_empty() and raw == original else {}

static func _world(state: Dictionary) -> Dictionary:
	var pin: Variant = state.get("world_pin")
	if not pin is Dictionary or not Technology.integer(pin.get("format"), 2, 2) \
		or not pin.get("world_instance_id") is String or str(pin.world_instance_id).is_empty(): return _fail("NOT_NEW_WORLD_FORMAT")
	var checked := Policy.candidate(pin)
	if not checked.ok: return checked
	return {"ok": true, "world_id": str(pin.world_instance_id), "policy": checked.policy}

## Optional strict original Site field. A receipt is historical: a seeded person
## can later die/travel/change owner without invalidating or replaying this birth.
static func validate_receipt(raw: Variant, state: Dictionary = {}) -> bool:
	if not Technology.keys(raw, ["version", "config_version", "scenario_id", "world_id", "site_id", "categories", "grants"]) \
		or not Technology.integer(raw.version, 1, 1) or not Technology.integer(raw.config_version, 1, 1) \
		or not raw.scenario_id is String or not raw.world_id is String or str(raw.world_id).is_empty() \
		or not raw.site_id is String or str(raw.site_id).is_empty() or not raw.grants is Array: return false
	var config := scenario_config(str(raw.scenario_id))
	var categories := Policy.new_policy(raw.categories)
	if config.is_empty() or not categories.ok or categories.policy.categories.is_empty() or categories.policy.categories != raw.categories: return false
	var effective: Array = []
	for assignment: Dictionary in config.assignments:
		if raw.categories.has(assignment.skills[0]): effective.append(assignment)
	if effective.size() != raw.grants.size(): return false
	var people := {}
	var source_teams := {}
	for index: int in effective.size():
		var assignment: Dictionary = effective[index]
		var grant: Variant = raw.grants[index]
		if not Technology.keys(grant, ["slot_id", "source_team_id", "source_faction", "person", "skills"]) \
			or not grant.slot_id is String or grant.slot_id != assignment.slot_id \
			or not Technology.integer(grant.source_faction, 0, 2) or grant.source_faction != assignment.faction_id or not grant.skills is Array \
			or not Technology.integer(grant.source_team_id, 1, 2147483647) or not Technology.valid_ref(grant.person) \
			or grant.person.site_id != raw.site_id or grant.skills != assignment.skills or people.has(int(grant.person.person_id)): return false
		var source_slot := str(assignment.source_slot)
		if source_teams.has(source_slot) and int(source_teams[source_slot]) != int(grant.source_team_id): return false
		for other: String in source_teams:
			if other != source_slot and int(source_teams[other]) == int(grant.source_team_id): return false
		source_teams[source_slot] = int(grant.source_team_id)
		people[int(grant.person.person_id)] = true
	if not state.is_empty():
		var world := _world(state)
		if not world.ok or str(state.get("id", "")) != raw.site_id or world.world_id != raw.world_id or world.policy.categories != raw.categories: return false
	return true

static func _original_body(state: Dictionary, assignment: Dictionary, selected: Dictionary) -> Dictionary:
	if not Technology.keys(selected, ["slot_id", "owner", "unit_index", "person_id"]) \
		or selected.slot_id != assignment.slot_id or not selected.owner is TerrainArmy \
		or not is_instance_valid(selected.owner) or not Technology.integer(selected.unit_index, 1) \
		or int(selected.unit_index) != int(assignment.unit_index) or not Technology.integer(selected.person_id, 1, 2147483647) \
		or int(selected.person_id) == 1000000000: return _fail("INVALID_ORIGINAL_SELECTION")
	var owner: TerrainArmy = selected.owner
	var index := int(selected.unit_index)
	if str(owner.name) != assignment.source_slot or owner.faction_id != int(assignment.faction_id) \
		or owner.team_id <= 0 or owner.data == null or str(owner.data.site.get("id", "")) != str(state.id) \
		or owner.data.site.get("world_pin") != state.world_pin: return _fail("ORIGINAL_SOURCE_MISMATCH")
	if not owner.has_army() or not owner.combat_enabled or index >= owner.combat_units.size() \
		or not owner.is_member(index) or owner.combat_identity(index) != int(selected.person_id): return _fail("MISSING_ORIGINAL_NPC")
	if int(state.get("controlled_person_id", -1)) == int(selected.person_id) \
		or is_instance_valid(owner.player_member) and owner.player_member.person_id == int(selected.person_id): return _fail("SELECTED_CONTROLLED_PERSON")
	var body: Dictionary = owner.combat_units[index]
	if float(body.get("hp", 0.0)) <= 0.0 or float(body.get("ko", 0.0)) > 0.0 \
		or bool(body.get("captive", false)) or bool(body.get("departed", false)) or bool(body.get("site_exited", false)) \
		or bool(body.get("surrender_pending", false)) or not str(body.get("embarked_vehicle_id", "")).is_empty(): return _fail("ORIGINAL_NPC_UNAVAILABLE")
	var found: Dictionary = {}
	var occurrences := 0
	for roster_index: int in state.armies.size():
		var roster: Variant = state.armies[roster_index]
		if not roster is Dictionary or not roster.get("units") is Array: return _fail("INVALID_ORIGINAL_STATE")
		for unit_index: int in roster.units.size():
			var saved: Variant = roster.units[unit_index]
			if not saved is Dictionary: return _fail("INVALID_ORIGINAL_STATE")
			if int(saved.get("person_id", -1)) != int(selected.person_id): continue
			occurrences += 1
			if int(roster.get("team_id", -1)) == owner.team_id and int(roster.get("faction_id", -1)) == owner.faction_id and unit_index == index:
				found = {"roster_index": roster_index, "unit_index": unit_index, "saved": saved}
	for actor: Variant in state.actors.values():
		if actor is Dictionary and int(actor.get("person_id", -1)) == int(selected.person_id): occurrences += 1
	if occurrences != 1 or found.is_empty(): return _fail("DUPLICATE_OR_STALE_PERSON")
	if found.saved.get("technology", {}) != body.get("technology", {}): return _fail("STALE_ORIGINAL_TECHNOLOGY")
	for field: String in ["hp", "ko", "captive", "departed", "site_exited", "surrender_pending", "member"]:
		if found.saved.get(field) != body.get(field): return _fail("STALE_ORIGINAL_BODY")
	return {"ok": true, "roster_index": found.roster_index, "unit_index": index, "owner": owner, "body": body}

static func _family_candidate(candidate: Dictionary, grants: Array) -> Dictionary:
	if not candidate.has("family"): return {"ok": true}
	var family: Variant = candidate.family
	if not Family.validate_family(family, str(candidate.id)): return _fail("INVALID_ORIGINAL_FAMILY")
	var members := Family.member_ids(family, str(candidate.id))
	var known: Array = []
	for grant: Dictionary in grants:
		if members.has(int(grant.person.person_id)) and not known.has(grant.skills[0]): known.append(grant.skills[0])
	if known.is_empty(): return {"ok": true}
	if int(family.version) != 3: return _fail("FAMILY_TECH_UNINITIALIZED")
	if not Technology.local_holder(family.technology, str(candidate.id)): return _fail("REMOTE_FAMILY_HOLDER")
	var tech: Dictionary = Technology.normalize_family_tech(family.technology)
	if int(tech.version) == 1: tech["version"] = 2
	for category: String in known:
		if not tech.known.has(category): tech.known.append(category)
	if not Technology.valid_family_tech(tech): return _fail("INVALID_ORIGINAL_FAMILY_TECHNOLOGY")
	family.technology = tech
	return {"ok": true}

## `original_selection` is assembled ONLY by the original initial-scenario birth
## transaction. A caller string/this candidate never authorizes a world write.
## `admitted_categories` is the owner's accepted release batch; frozen policy is
## intersected by validation, never expanded by later publication or this helper.
static func prepare(state: Dictionary, config: Dictionary, admitted_categories: Variant, original_selection: Dictionary = {}) -> Dictionary:
	if state.has("technology_artisans"):
		if not validate_receipt(state.technology_artisans, state): return _fail("INVALID_ARTISAN_RECEIPT")
		return _unchanged(state, "ALREADY_APPLIED")
	if original_selection.is_empty() or original_selection.get("context") != "initial_scenario_birth": return _unchanged(state, "NO_BIRTH")
	var checked_config := _config(config)
	if checked_config.is_empty(): return _fail("UNKNOWN_OR_CHANGED_SCENARIO")
	if not Technology.keys(original_selection, ["version", "context", "world_id", "site_id", "scenario_id", "sources"]) \
		or not Technology.integer(original_selection.version, 1, 1) or not original_selection.sources is Array \
		or not state.get("id") is String or str(state.id).is_empty() or not state.get("armies") is Array or not state.get("actors") is Dictionary: return _fail("INVALID_BIRTH_SELECTION")
	var world := _world(state)
	if not world.ok: return world
	if original_selection.world_id != world.world_id or original_selection.site_id != state.id \
		or original_selection.scenario_id != checked_config.scenario_id: return _fail("BIRTH_CONTEXT_MISMATCH")
	var admitted := Policy.new_policy(admitted_categories)
	if not admitted.ok: return admitted
	for category: String in world.policy.categories:
		if not admitted.policy.categories.has(category): return _fail("CATEGORY_NOT_ADMITTED")
	if world.policy.categories.is_empty(): return _unchanged(state, "NO_ADMITTED_CLASSES")
	var slots := {}
	for assignment: Dictionary in checked_config.assignments: slots[str(assignment.slot_id)] = assignment
	var selected := {}
	for source: Variant in original_selection.sources:
		if not source is Dictionary or not source.get("slot_id") is String or not slots.has(source.slot_id) or selected.has(source.slot_id): return _fail("INVALID_OR_DUPLICATE_SLOT")
		selected[source.slot_id] = source
	var candidate := state.duplicate(true)
	var grants: Array = []
	var expected: Array = []
	var people := {}
	for assignment: Dictionary in checked_config.assignments:
		if not world.policy.categories.has(assignment.skills[0]): continue
		if not selected.has(assignment.slot_id): return _fail("MISSING_ORIGINAL_NPC")
		var original := _original_body(state, assignment, selected[assignment.slot_id])
		if not original.ok: return original
		var identity := int(selected[assignment.slot_id].person_id)
		if people.has(identity): return _fail("DUPLICATE_OR_STALE_PERSON")
		people[identity] = true
		var technology := Technology.learned_candidate(original.body.get("technology", {}), str(assignment.skills[0]))
		if technology.is_empty(): return _fail("INVALID_ORIGINAL_PERSON_TECHNOLOGY")
		candidate.armies[original.roster_index].units[original.unit_index].technology = technology
		grants.append({"slot_id": assignment.slot_id, "source_team_id": original.owner.team_id,
			"source_faction": original.owner.faction_id, "person": {"site_id": state.id, "person_id": identity}, "skills": assignment.skills.duplicate()})
		expected.append({"owner": original.owner, "body": original.body, "unit_index": original.unit_index,
			"person_id": identity, "technology_before": original.body.get("technology", {}).duplicate(true)})
	var family := _family_candidate(candidate, grants)
	if not family.ok: return family
	candidate["technology_artisans"] = {"version": 1, "config_version": 1, "scenario_id": checked_config.scenario_id,
		"world_id": world.world_id, "site_id": state.id, "categories": world.policy.categories.duplicate(), "grants": grants.duplicate(true)}
	if not validate_receipt(candidate.technology_artisans, candidate): return _fail("INVALID_ARTISAN_RECEIPT")
	return {"ok": true, "changed": true, "code": "PREPARED", "state": candidate, "grants": grants, "expected": expected}
