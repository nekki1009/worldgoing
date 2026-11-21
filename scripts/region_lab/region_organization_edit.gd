extends RefCounted
## Stateless operations on a Slot-owned private draft, never a live authority.
const Registry = preload("res://scripts/region_lab/region_organization_registry.gd")
const Equipment = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")

static func fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func table(registry: Dictionary, kind: String) -> Dictionary:
	return registry.nations if kind == "nation" else registry.families

static func create(base: Dictionary, contexts: Dictionary) -> Dictionary:
	return {"registry": base.duplicate(true), "base": base.duplicate(true), "contexts": contexts, "revision": 0, "epochs": {}, "views": {}, "checkpoints": {}}

static func identity_same(kind: String, original: Dictionary, candidate: Dictionary) -> bool:
	var fields: Array = ["version", "family_id", "lineage_id"] if kind == "family" else ["faction_version", "faction_id"]
	for field: String in fields:
		if original.has(field) != candidate.has(field): return false
		if original.has(field) and not Registry.same(original[field], candidate[field]): return false
	return true

## Original record schemas + original Person membership only. No caller validator,
## physical holder/role closure, save receipt or publication eligibility is issued.
static func validate(candidate: Dictionary, base: Dictionary, contexts: Dictionary, bindings: Dictionary, identities: Dictionary, people: Dictionary) -> Dictionary:
	var world: String = str(base.get("world_instance_id", ""))
	if not RegionSaveSlot.person_allocator_valid(people, world): return fail("INVALID_PERSON_ALLOCATOR")
	if not Registry.valid(candidate, world): return fail("ORGANIZATION_EDIT_SCHEMA")
	for field: String in ["version", "world_instance_id", "revision"]:
		if not Registry.same(candidate[field], base[field]): return fail("ORGANIZATION_EDIT_IDENTITY")
	for kind: String in ["nation", "family"]:
		var current: Dictionary = table(candidate, kind)
		var original: Dictionary = table(base, kind)
		var members: Dictionary = {}
		for key: String in current:
			if not original.has(key) or not Registry.same(current[key].reference, original[key].reference) or current[key].home_site_id != original[key].home_site_id or not identity_same(kind, original[key].record, current[key].record): return fail("ORGANIZATION_EDIT_IDENTITY")
			for member: Variant in current[key].record.members:
				var id: Variant = member.person_id if kind == "family" else member
				if not Registry.known_person(people, id): return fail("UNKNOWN_ORGANIZATION_PERSON")
				if members.has(str(int(id))): return fail("DUPLICATE_" + kind.to_upper() + "_MEMBERSHIP")
				members[str(int(id))] = key
		for key: String in original:
			if not current.has(key) and not Registry.same(candidate.retired.get(key), original[key].reference): return fail("ORGANIZATION_EDIT_IDENTITY")
	for key: String in candidate.retired:
		if base.retired.has(key):
			if not Registry.same(candidate.retired[key], base.retired[key]): return fail("ORGANIZATION_EDIT_IDENTITY")
		else:
			var original: Dictionary = base.nations if base.nations.has(key) else base.families
			if not original.has(key) or not Registry.same(candidate.retired[key], original[key].reference): return fail("ORGANIZATION_EDIT_IDENTITY")
	for key: String in base.retired:
		if not Registry.same(candidate.retired.get(key), base.retired[key]): return fail("ORGANIZATION_EDIT_IDENTITY")
	var covered: Dictionary = {}
	for owner: String in contexts:
		var state: Dictionary = contexts[owner].duplicate(true)
		var refs: Dictionary = bindings[owner]
		state.travel_identity = identities[owner].duplicate(true)
		state.equipment_nations = {}
		for local: String in refs.nation_refs:
			var key: String = str(refs.nation_refs[local])
			if candidate.nations.has(key):
				state.equipment_nations[local] = candidate.nations[key].record.duplicate(true)
				covered[key] = true
		if refs.family_ref != null and candidate.families.has(refs.family_ref):
			state.family = candidate.families[refs.family_ref].record.duplicate(true)
			covered[str(refs.family_ref)] = true
		else: state.erase("family")
		var bodies: Dictionary = RegionTravel._body_records(state)
		if not Equipment.valid_nations(state.equipment_nations, state.get("item_definitions", {}), bodies, state): return fail("INVALID_ORIGINAL_NATIONS")
		if state.has("family"):
			if not Family.validate_family(state.family, str(state.id)): return fail("INVALID_ORIGINAL_FAMILY")
			if Technology.is_holder_reference(state.family.get("technology")): return fail("ORGANIZATION_TECHNOLOGY_HOLDER_CONTEXT_REQUIRED")
			if state.family.has("technology") and not Technology.valid_family_tech_for_site(state.family, str(state.id), bodies, state.get("armies", [])): return fail("INVALID_ORIGINAL_FAMILY_TECHNOLOGY")
	for kind: String in ["nation", "family"]:
		for key: String in table(candidate, kind):
			if not covered.has(key): return fail("ORGANIZATION_EDIT_CONTEXT_REQUIRED")
	return {"ok": true}

static func replace_record(edit: Dictionary, kind: String, key: String, candidate: Dictionary) -> void:
	var replacement: Dictionary = candidate.duplicate(true)
	var record: Dictionary = table(edit.registry, kind)[key].record
	record.clear()
	record.merge(replacement, true)
	edit.revision = int(edit.revision) + 1

static func delete_record(edit: Dictionary, kind: String, key: String) -> void:
	var records: Dictionary = table(edit.registry, kind)
	edit.registry.retired[key] = records[key].reference.duplicate(true)
	records.erase(key)
	edit.epochs[key] = int(edit.epochs.get(key, 0)) + 1
	edit.views.erase(key)
	edit.revision = int(edit.revision) + 1

static func checkpoint(edit: Dictionary) -> Dictionary:
	return {"snapshot": edit.registry.duplicate(true), "nations": edit.registry.nations.duplicate(), "families": edit.registry.families.duplicate()}

static func rollback(edit: Dictionary, checkpoint_value: Dictionary) -> void:
	for kind: String in ["nations", "families"]:
		var current: Dictionary = edit.registry[kind]
		var restored: Dictionary = {}
		for key: String in current:
			if not checkpoint_value.snapshot[kind].has(key):
				edit.epochs[key] = int(edit.epochs.get(key, 0)) + 1
				edit.views.erase(key)
		for key: String in checkpoint_value.snapshot[kind]:
			var original: Dictionary = checkpoint_value[kind][key]
			if not current.has(key) or not is_same(current[key], original):
				edit.epochs[key] = int(edit.epochs.get(key, 0)) + 1
				edit.views.erase(key)
			var body: Dictionary = checkpoint_value.snapshot[kind][key].record.duplicate(true)
			original.record.clear()
			original.record.merge(body, true)
			restored[key] = original
		edit.registry[kind] = restored
	edit.registry.retired = checkpoint_value.snapshot.retired.duplicate(true)
	edit.revision = int(edit.revision) + 1
