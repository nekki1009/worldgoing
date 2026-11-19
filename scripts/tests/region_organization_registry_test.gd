extends SceneTree
const Registry = preload("res://scripts/region_lab/region_organization_registry.gd")
var failures: Array[String] = []
var checks: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func source_state(site: String, person: int) -> Dictionary:
	return {"id": site, "actors": {"player": {"person_id": person}}, "item_definitions": {}, "equipment_nations": {"original": {"military_head": person, "members": [person], "standards": {}}}, "world_pin": source_pin(), "family": {"version": 1, "complete": true, "members": [{"site_id": site, "person_id": person, "path": "", "label": site, "age_years": -1}]}}

func source_pin() -> Dictionary:
	return {"format": 1, "world_instance_id": "world", "slot_id": "main", "atlas_id": RegionSaveSlot.Grid.ATLAS_ID, "base_revision": "base", "manifest_sha256": "a".repeat(64), "ramp_rule_revision": "ramp", "grid_contract_version": 1}

func _initialize() -> void:
	var a: Dictionary = source_state("site-a", 1)
	var b: Dictionary = source_state("site-b", 2)
	var person_sources: Array = [{"projection": RegionSaveSlot.person_projection(a), "location": {"kind": "site", "id": "site-a"}}, {"projection": RegionSaveSlot.person_projection(b), "location": {"kind": "site", "id": "site-b"}}]
	var people: Dictionary = RegionSaveSlot.person_migration("world", person_sources)
	if not people.ok:
		check(false, "Original person admission fixture")
		finish()
		return
	var inputs: Array = [a, b]
	var before: PackedByteArray = var_to_bytes(inputs)
	var migrated: Dictionary = Registry.migrate("world", 4, inputs, people.allocator, RegionSaveSlot.person_allocator_valid)
	if not migrated.ok:
		check(false, "Original nation/family schemas admitted: " + str(migrated))
		finish()
		return
	check(migrated.registry.nations.size() == 2 and migrated.registry.families.size() == 2, "Two original local nation keys become distinct typed world records")
	check(var_to_bytes(inputs) == before, "Migration never rewrites source states")
	check(not migrated.states[0].has("family") and not migrated.states[0].has("equipment_nations"), "Prepared wire candidate contains references without organization bodies")
	var validator: Callable = Registry.validate_records.bind(inputs, RegionSaveSlot.person_allocator_valid)
	var selected: Dictionary = Registry.context(migrated.registry, source_pin(), 4, people.allocator, validator)
	if not selected.ok:
		check(false, "Actual source-schema callback admits private context: " + str(selected))
		finish()
		return
	var bindings: Dictionary = migrated.states[0][Registry.WIRE_KEY]
	var original_identity: Dictionary = RegionTravel.prepare_identity(a)
	var encoded: Dictionary = Registry.encode(original_identity.state, selected, bindings)
	check(encoded.ok and not encoded.state.has("family") and not encoded.state.has("equipment_nations"), "Encoder verifies exact records before removing body fields")
	var decoded: Dictionary = Registry.decode(encoded.state, selected)
	check(decoded.ok and Registry.same(decoded.state.family, a.family) and Registry.same(decoded.state.equipment_nations, a.equipment_nations), "Exact-context roundtrip restores original logical domain records")
	var old_context: Dictionary = selected.duplicate(true)
	old_context.descriptor.generation = 3
	var rejected: Dictionary = Registry.decode(encoded.state, old_context)
	check(not rejected.ok, "A different generation cannot satisfy the saved descriptor")
	var changed: Dictionary = original_identity.state.duplicate(true)
	changed.family.complete = false
	var registry_before: PackedByteArray = var_to_bytes(selected)
	rejected = Registry.encode(changed, selected, bindings)
	check(not rejected.ok and rejected.code == "ORGANIZATION_BODY_CONTEXT_MISMATCH" and var_to_bytes(selected) == registry_before, "Unsaved mutation cannot be encoded against an older registry context")
	var dual: Dictionary = encoded.state.duplicate(true)
	dual.family = a.family.duplicate(true)
	rejected = Registry.decode(dual, selected)
	check(not rejected.ok and rejected.code == "DUAL_ORGANIZATION_AUTHORITY", "Mixed body/reference wire state rejected")
	var missing: Dictionary = selected.duplicate(true)
	missing.registry.families.clear()
	rejected = Registry.decode(encoded.state, missing)
	check(not rejected.ok, "Missing or changed registry never becomes an empty family")
	var legacy: Dictionary = Registry.decode(a, {})
	check(legacy.ok and legacy.legacy and legacy.state == a and var_to_bytes(inputs) == before, "Legacy logical state remains readable and unchanged")
	var collision_b: Dictionary = RegionTravel.prepare_identity(b)
	var collision_a: Dictionary = RegionTravel.prepare_identity(a)
	collision_b.state.travel_identity.refs.family.controlled = collision_a.state.travel_identity.refs.family.controlled.duplicate(true)
	rejected = Registry.migrate("world", 4, [collision_a.state, collision_b.state], people.allocator, RegionSaveSlot.person_allocator_valid)
	check(not rejected.ok and rejected.code == "ORGANIZATION_IDENTITY_COLLISION", "Conflicting bodies cannot claim the same original family identity")
	var unknown: Dictionary = a.duplicate(true)
	unknown.family.members[0].person_id = 99
	rejected = Registry.migrate("world", 4, [unknown], people.allocator, RegionSaveSlot.person_allocator_valid)
	check(not rejected.ok and rejected.code == "UNKNOWN_ORGANIZATION_PERSON", "Unknown person membership is not guessed from location or number range")
	check(not Registry.same({"n": 1}, {"n": 1.0}), "Typed equality preserves integer/float distinction")
	check(not Registry.same({1: "x"}, {"1": "x"}), "Dictionary key types cannot coerce to String")
	check(not Registry.same({"point": Vector2i(1, 2)}, {"point": "(1, 2)"}), "Unsupported Vector is rejected instead of coerced")
	check(Registry.same({"a": 1, "b": 2}, {"b": 2, "a": 1}), "String key order canonicalization preserves types")
	var schema_required: Dictionary = Registry.context(migrated.registry, source_pin(), 4, people.allocator, Callable())
	check(not schema_required.ok and schema_required.code == "ORGANIZATION_SCHEMA_CONTEXT_REQUIRED", "Digest alone cannot construct an admitted context")
	var wrong_generation: Dictionary = Registry.context(migrated.registry, source_pin(), 5, people.allocator, validator)
	check(not wrong_generation.ok, "Registry revision cannot be selected as another generation")
	var wrong_pin: Dictionary = encoded.state.duplicate(true)
	wrong_pin.world_pin.base_revision = "other"
	rejected = Registry.decode(wrong_pin, selected)
	check(not rejected.ok and rejected.code == "ORGANIZATION_PIN_MISMATCH", "Same World/Slot cannot replace the complete source pin")
	var wrong_identity: Dictionary = encoded.state.duplicate(true)
	wrong_identity.travel_identity.refs.family.controlled.lineage += 100
	rejected = Registry.decode(wrong_identity, selected)
	check(not rejected.ok and rejected.code == "ORGANIZATION_IDENTITY_REQUIRED", "Decoder checks original typed family identity as well as digest")
	var invalid_schema: Dictionary = migrated.registry.duplicate(true)
	invalid_schema.nations[invalid_schema.nations.keys()[0]].record.standards.bad = {"name": "bad", "revision": 1, "slots": {"unsupported": "missing"}}
	var schema_context: Dictionary = Registry.context(invalid_schema, source_pin(), 4, people.allocator, validator)
	check(not schema_context.ok, "A changed body cannot bypass original domain schema/source admission")
	var history_b: Dictionary = RegionTravel.prepare_identity(b)
	var classified: Array = [{"owner": "site:a", "kind": "site", "historical": false, "state": a}, {"owner": "party:old", "kind": "party", "historical": true, "state": history_b.state}]
	var classified_before: PackedByteArray = var_to_bytes(classified)
	var proposal: Dictionary = Registry.migrate_sources("world", 4, classified, people.allocator, RegionSaveSlot.person_allocator_valid)
	check(proposal.ok and proposal.registry.nations.size() == 1 and proposal.registry.families.size() == 1 and proposal.registry.retired.size() == 2 and proposal.bindings.size() == 1, "Historical party contributes original aliases without resurrecting its bodies")
	check(var_to_bytes(classified) == classified_before, "Source classifications and immutable body bytes stay unchanged")
	var missing_history: Dictionary = Registry.migrate_sources("world", 4, [{"owner": "party:missing", "kind": "party", "historical": true, "state": b}], people.allocator, RegionSaveSlot.person_allocator_valid)
	check(not missing_history.ok and missing_history.code == "ORGANIZATION_HISTORICAL_IDENTITY_REQUIRED", "Historical sources cannot synthesize new identities from their old bodies")
	classified[1].historical = false
	proposal = Registry.migrate_sources("world", 4, classified, people.allocator, RegionSaveSlot.person_allocator_valid)
	check(not proposal.ok and proposal.code == "ORGANIZATION_PARTY_BODY_CONTEXT_REQUIRED", "Active party organization bodies require original full context integration")
	var empty_party: Dictionary = b.duplicate(true)
	empty_party.erase("family")
	empty_party.erase("equipment_nations")
	proposal = Registry.migrate_sources("world", 4, [{"owner": "party:empty", "kind": "party", "historical": false, "state": empty_party}], people.allocator, RegionSaveSlot.person_allocator_valid)
	check(proposal.ok and proposal.registry.families.is_empty() and proposal.registry.nations.is_empty(), "An original organization-free party creates no invented organization body")
	var ambiguous: Dictionary = a.duplicate(true)
	var duplicated: Dictionary = ambiguous.family.members[0].duplicate(true)
	duplicated.site_id = "another-site"
	ambiguous.family.members.append(duplicated)
	proposal = Registry.migrate("world", 4, [ambiguous], people.allocator, RegionSaveSlot.person_allocator_valid)
	check(not proposal.ok and proposal.code == "AMBIGUOUS_ORGANIZATION_PERSON", "Two location rows cannot turn one World person into two members")
	var malformed: Dictionary = a.duplicate(true)
	malformed.family = "not-a-family"
	proposal = Registry.migrate("world", 4, [malformed], people.allocator, RegionSaveSlot.person_allocator_valid)
	check(not proposal.ok, "Malformed original family refuses without field access crash")
	proposal = Registry.migrate_sources("world", 4, [{"owner": "site:malformed", "kind": "site", "historical": false, "state": malformed}], people.allocator, RegionSaveSlot.person_allocator_valid)
	check(not proposal.ok and proposal.code == "INVALID_ORIGINAL_FAMILY", "Classified migration reaches original family preflight before the identity issuer")
	var holder_reference: Dictionary = a.duplicate(true)
	holder_reference.family.version = 3
	holder_reference.family.family_id = "b".repeat(32)
	holder_reference.family.offices = SiteOffices.default_offices("family", 1, false)
	holder_reference.family.technology = {"version": 3, "holder_site_id": "site-b", "epoch": 1}
	check(preload("res://scripts/terrain_lab/site_family_continuity.gd").validate_family(holder_reference.family, "site-a"), "Holder-reference refusal fixture is an original valid legacy family")
	proposal = Registry.migrate("world", 4, [holder_reference], people.allocator, RegionSaveSlot.person_allocator_valid)
	check(not proposal.ok and proposal.code == "ORGANIZATION_TECHNOLOGY_HOLDER_CONTEXT_REQUIRED", "A legal holder reference is refused specifically rather than copied as a complete family body")
	check(var_to_bytes(inputs) == before, "All refusal paths retain the original inputs")
	finish()

func finish() -> void:
	print("REGION_ORGANIZATION_REGISTRY_", "PASS" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
