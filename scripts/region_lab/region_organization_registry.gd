extends RefCounted
## Stateless migration/codec for the original Slot. Not an independent owner. P6-B1 private preflight only.
## Logical records are private candidates; this module never publishes or binds.
const Travel = preload("res://scripts/region_lab/region_travel.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Equipment = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const WIRE_KEY := "world_organization_refs"

static func fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func whole(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= upper and float(value) == floorf(float(value))

## Data-only canonical typed Variant bytes. No String coercion or JSON loss.
static func canonical(value: Variant) -> Dictionary:
	if value is Dictionary:
		var keys: Array = value.keys()
		for key: Variant in keys:
			if not key is String: return fail("UNSUPPORTED_ORGANIZATION_TYPE")
		keys.sort()
		var result: Dictionary = {}
		for key: String in keys:
			var child: Dictionary = canonical(value[key])
			if not child.ok: return child
			result[key] = child.value
		return {"ok": true, "value": result}
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			var child: Dictionary = canonical(entry)
			if not child.ok: return child
			result.append(child.value)
		return {"ok": true, "value": result}
	if value == null or value is bool or value is int or value is String or value is float and is_finite(value): return {"ok": true, "value": value}
	return fail("UNSUPPORTED_ORGANIZATION_TYPE")

static func same(left: Variant, right: Variant) -> bool:
	var a: Dictionary = canonical(left)
	var b: Dictionary = canonical(right)
	return a.ok and b.ok and var_to_bytes(a.value) == var_to_bytes(b.value)

static func empty(world: String, revision: int) -> Dictionary:
	return {"version": 1, "world_instance_id": world, "revision": revision, "nations": {}, "families": {}, "retired": {}}

static func digest(registry: Dictionary) -> String:
	var normalized: Dictionary = canonical(registry)
	return var_to_bytes(normalized.value).hex_encode().sha256_text() if normalized.ok else ""

static func reference_valid(reference: Variant, kind: String) -> bool:
	return reference is Dictionary and reference.size() == 3 and reference.get("type") == kind and reference.get("namespace") is String and not str(reference.namespace).is_empty() and whole(reference.get("lineage"), 1, Travel.MAX_IDENTITY_SEQUENCE)

static func valid(registry: Variant, world: String) -> bool:
	if not registry is Dictionary or registry.size() != 6 or not whole(registry.get("version"), 1, 1) or world.is_empty() or registry.get("world_instance_id") != world or not whole(registry.get("revision"), 0, 2147483647) or not registry.get("nations") is Dictionary or not registry.get("families") is Dictionary or not registry.get("retired") is Dictionary: return false
	for kind: String in ["nation", "family"]:
		var table: Dictionary = registry.nations if kind == "nation" else registry.families
		for key: Variant in table:
			var entry: Variant = table[key]
			if not key is String or not entry is Dictionary or entry.size() != 3 or not entry.get("record") is Dictionary or not entry.get("home_site_id") is String or str(entry.home_site_id).is_empty() or not reference_valid(entry.get("reference"), kind) or Travel.stable_key(entry.reference) != key: return false
			if kind == "family":
				if not Family.validate_family(entry.record, str(entry.home_site_id)): return false
			else:
				var nation: Dictionary = entry.record
				if not nation.get("members") is Array or not nation.get("standards") is Dictionary: return false
				for member: Variant in nation.members:
					if not whole(member, 1, 2147483646) or int(member) == 1000000000: return false
				if nation.has("offices"):
					if not SiteOffices.validate(nation.offices, "nation"): return false
				elif not whole(nation.get("military_head"), 1, 2147483646) or not nation.members.has(int(nation.military_head)): return false
	for key: Variant in registry.retired:
		var reference: Variant = registry.retired[key]
		if not key is String or not reference is Dictionary or reference.get("type") not in ["nation", "family"] or not reference_valid(reference, str(reference.type)) or Travel.stable_key(reference) != key or registry.nations.has(key) or registry.families.has(key): return false
	return canonical(registry).ok

static func known_person(people: Dictionary, person_id: Variant) -> bool:
	if not whole(person_id, 1, 2147483646) or int(person_id) == 1000000000: return false
	if people.locations.has(str(int(person_id))): return true
	for value: Variant in people.aliases.values():
		if int(value) == int(person_id): return true
	return false

static func add_record(registry: Dictionary, kind: String, reference: Dictionary, record: Dictionary, site_id: String) -> Dictionary:
	if not reference_valid(reference, kind): return fail("ORGANIZATION_IDENTITY_REQUIRED")
	var key: String = Travel.stable_key(reference)
	var table: Dictionary = registry.nations if kind == "nation" else registry.families
	if table.has(key):
		if not same(table[key].record, record): return fail("ORGANIZATION_IDENTITY_COLLISION")
	else:
		table[key] = {"reference": reference.duplicate(true), "home_site_id": site_id, "record": record.duplicate(true)}
	return {"ok": true, "id": key}

static func migrate(world: String, revision: int, sources: Array, people: Dictionary, person_validator: Callable) -> Dictionary:
	if not whole(revision, 0, 2147483647) or not person_validator.is_valid() or not person_validator.call(people, world): return fail("INVALID_PERSON_ALLOCATOR")
	var registry: Dictionary = empty(world, revision)
	var candidates: Array[Dictionary] = []
	var memberships: Dictionary = {"nation": {}, "family": {}}
	var sites: Dictionary = {}
	for raw: Variant in sources:
		if not raw is Dictionary or not raw.get("id") is String or str(raw.id).is_empty() or raw.has(WIRE_KEY) or sites.has(raw.id): return fail("ORGANIZATION_MIGRATION_SOURCE")
		sites[raw.id] = true
		if raw.has("family") and not Family.validate_family(raw.family, str(raw.id)): return fail("INVALID_ORIGINAL_FAMILY")
		# This is the original lineage issuer, on a private transaction candidate.
		var prepared: Dictionary = Travel.prepare_identity(raw)
		if not prepared.ok: return prepared
		var state: Dictionary = prepared.state
		var wire: Dictionary = {"nation_refs": {}, "family_ref": null}
		if not Equipment.valid_nations(state.get("equipment_nations", {}), state.get("item_definitions", {}), Travel._body_records(state), state): return fail("INVALID_ORIGINAL_NATIONS")
		for local: String in state.get("equipment_nations", {}):
			var nation: Dictionary = state.equipment_nations[local]
			var added: Dictionary = add_record(registry, "nation", state.travel_identity.refs.nation[local], nation, str(state.id))
			if not added.ok: return added
			for id: Variant in nation.members:
				if not known_person(people, id): return fail("UNKNOWN_ORGANIZATION_PERSON")
				if memberships.nation.has(str(int(id))) and memberships.nation[str(int(id))] != added.id: return fail("DUPLICATE_NATION_MEMBERSHIP")
				memberships.nation[str(int(id))] = added.id
			wire.nation_refs[local] = added.id
		if state.has("family"):
			if state.family is Dictionary and preload("res://scripts/terrain_lab/site_technology.gd").is_holder_reference(state.family.get("technology")): return fail("ORGANIZATION_TECHNOLOGY_HOLDER_CONTEXT_REQUIRED")
			if not Family.validate_family(state.family, str(state.id)): return fail("INVALID_ORIGINAL_FAMILY")
			var added: Dictionary = add_record(registry, "family", state.travel_identity.refs.family.get("controlled", {}), state.family, str(state.id))
			if not added.ok: return added
			var local_members: Dictionary = {}
			for member: Dictionary in state.family.members:
				if local_members.has(str(int(member.person_id))): return fail("AMBIGUOUS_ORGANIZATION_PERSON")
				local_members[str(int(member.person_id))] = true
				if not known_person(people, member.person_id): return fail("UNKNOWN_ORGANIZATION_PERSON")
				var key: String = str(int(member.person_id))
				if memberships.family.has(key) and memberships.family[key] != added.id: return fail("DUPLICATE_FAMILY_MEMBERSHIP")
				memberships.family[key] = added.id
			wire.family_ref = added.id
		state.erase("equipment_nations")
		state.erase("family")
		state[WIRE_KEY] = wire
		candidates.append(state)
	if not valid(registry, world): return fail("INVALID_ORGANIZATION_REGISTRY")
	return {"ok": true, "registry": registry, "states": candidates}


## Full original domain schemas are mandatory when building or using a context.
static func validate_records(registry: Dictionary, people: Dictionary, pin: Dictionary, states: Array, person_validator: Callable) -> Dictionary:
	for state: Variant in states:
		if not state is Dictionary or not RegionSaveSlot._same_pin(state.get("world_pin"), pin): return fail("ORGANIZATION_PIN_MISMATCH")
	var admitted: Dictionary = migrate(str(pin.get("world_instance_id", "")), int(registry.get("revision", -1)), states, people, person_validator)
	if not admitted.ok: return admitted
	if not same(admitted.registry.nations, registry.get("nations")) or not same(admitted.registry.families, registry.get("families")): return fail("ORGANIZATION_SCHEMA_CONTEXT_MISMATCH")
	return {"ok": true}

static func context(registry: Dictionary, pin: Dictionary, generation: int, people: Dictionary, validator: Callable) -> Dictionary:
	if not RegionSaveSlot._same_pin(pin, pin) or not valid(registry, str(pin.get("world_instance_id", ""))) or generation < 1 or generation > 2147483647 or int(registry.revision) != generation: return fail("INVALID_ORGANIZATION_CONTEXT")
	if not validator.is_valid(): return fail("ORGANIZATION_SCHEMA_CONTEXT_REQUIRED")
	var admitted: Variant = validator.call(registry, people, pin)
	if not admitted is Dictionary or not admitted.get("ok", false): return fail("ORGANIZATION_SCHEMA_CONTEXT_MISMATCH")
	return {"ok": true, "descriptor": {"version": 1, "world_instance_id": pin.world_instance_id, "slot_id": pin.slot_id, "generation": generation, "registry_sha256": digest(registry)}, "registry": registry.duplicate(true), "pin": pin.duplicate(true), "people": people.duplicate(true), "records_validator": validator}

static func context_valid(value: Variant, descriptor: Variant) -> bool:
	if not value is Dictionary or not descriptor is Dictionary or descriptor.size() != 5 or not whole(descriptor.get("version"), 1, 1) or not whole(descriptor.get("generation"), 1, 2147483647): return false
	if not value.get("pin") is Dictionary or not RegionSaveSlot._same_pin(value.pin, value.pin) or descriptor.get("world_instance_id") != value.pin.world_instance_id or descriptor.get("slot_id") != value.pin.slot_id: return false
	if not valid(value.get("registry"), str(descriptor.world_instance_id)) or int(value.registry.revision) != int(descriptor.generation) or not same(value.get("descriptor"), descriptor) or digest(value.registry) != descriptor.get("registry_sha256"): return false
	var validator: Variant = value.get("records_validator")
	if not validator is Callable or not validator.is_valid() or not value.get("people") is Dictionary: return false
	var admitted: Variant = validator.call(value.registry, value.people, value.pin)
	return admitted is Dictionary and admitted.get("ok", false)

static func decode(state: Dictionary, selected: Dictionary) -> Dictionary:
	if not state.has(WIRE_KEY): return {"ok": true, "legacy": true, "state": state.duplicate(true)}
	if state.has("family") or state.has("equipment_nations"): return fail("DUAL_ORGANIZATION_AUTHORITY")
	var refs: Variant = state[WIRE_KEY]
	if not refs is Dictionary or refs.size() != 3 or not refs.get("nation_refs") is Dictionary or not refs.has("family_ref") or not context_valid(selected, refs.get("source")): return fail("ORGANIZATION_CONTEXT_REQUIRED")
	if not RegionSaveSlot._same_pin(state.get("world_pin"), selected.pin): return fail("ORGANIZATION_PIN_MISMATCH")
	var identity: Variant = state.get("travel_identity")
	if not Travel.validate_identity(identity): return fail("ORGANIZATION_IDENTITY_REQUIRED")
	var result: Dictionary = state.duplicate(true)
	result.equipment_nations = {}
	for local: Variant in refs.nation_refs:
		var key: Variant = refs.nation_refs[local]
		if not local is String or not key is String: return fail("UNKNOWN_ORGANIZATION_REFERENCE")
		if not reference_valid(identity.refs.nation.get(local), "nation") or Travel.stable_key(identity.refs.nation[local]) != key: return fail("ORGANIZATION_IDENTITY_REQUIRED")
		if selected.registry.retired.has(key):
			if selected.registry.retired[key].type != "nation": return fail("UNKNOWN_ORGANIZATION_REFERENCE")
			continue
		if not selected.registry.nations.has(key): return fail("UNKNOWN_ORGANIZATION_REFERENCE")
		result.equipment_nations[local] = selected.registry.nations[key].record.duplicate(true)
	if refs.family_ref != null:
		if not refs.family_ref is String or not reference_valid(identity.refs.family.get("controlled"), "family") or Travel.stable_key(identity.refs.family.controlled) != refs.family_ref: return fail("ORGANIZATION_IDENTITY_REQUIRED")
		if selected.registry.retired.has(refs.family_ref):
			if selected.registry.retired[refs.family_ref].type != "family": return fail("UNKNOWN_ORGANIZATION_REFERENCE")
			return {"ok": true, "legacy": false, "state": result}
		if not refs.family_ref is String or not selected.registry.families.has(refs.family_ref): return fail("UNKNOWN_ORGANIZATION_REFERENCE")
		result.family = selected.registry.families[refs.family_ref].record.duplicate(true)
	return {"ok": true, "legacy": false, "state": result}

static func encode(logical: Dictionary, selected: Dictionary, bindings: Dictionary) -> Dictionary:
	if not context_valid(selected, selected.get("descriptor")) or bindings.size() != 2 or not bindings.get("nation_refs") is Dictionary or not bindings.has("family_ref"): return fail("INVALID_ORGANIZATION_CONTEXT")
	if not RegionSaveSlot._same_pin(logical.get("world_pin"), selected.pin): return fail("ORGANIZATION_PIN_MISMATCH")
	var identity: Variant = logical.get("travel_identity")
	if not Travel.validate_identity(identity): return fail("ORGANIZATION_IDENTITY_REQUIRED")
	for local: String in bindings.nation_refs:
		if not reference_valid(identity.refs.nation.get(local), "nation") or Travel.stable_key(identity.refs.nation[local]) != bindings.nation_refs[local]: return fail("ORGANIZATION_IDENTITY_REQUIRED")
	if bindings.family_ref != null and (not reference_valid(identity.refs.family.get("controlled"), "family") or Travel.stable_key(identity.refs.family.controlled) != bindings.family_ref): return fail("ORGANIZATION_IDENTITY_REQUIRED")
	var candidate: Dictionary = logical.duplicate(true)
	candidate.erase("equipment_nations")
	candidate.erase("family")
	candidate[WIRE_KEY] = bindings.duplicate(true)
	candidate[WIRE_KEY].source = selected.descriptor.duplicate(true)
	var resolved: Dictionary = decode(candidate, selected)
	if not resolved.ok: return resolved
	if not same(logical.get("equipment_nations", {}), resolved.state.equipment_nations) or not same(logical.get("family"), resolved.state.get("family")): return fail("ORGANIZATION_BODY_CONTEXT_MISMATCH")
	return {"ok": true, "state": candidate}


## Source states are private snapshots returned by the original Slot readers.
## Historical files contribute aliases only; their old bodies never return live.
static func migrate_sources(world: String, revision: int, sources: Array, people: Dictionary, person_validator: Callable) -> Dictionary:
	if not whole(revision, 1, 2147483647) or not person_validator.is_valid() or not person_validator.call(people, world): return fail("INVALID_PERSON_ALLOCATOR")
	var registry: Dictionary = empty(world, revision)
	var bindings: Dictionary = {}
	var identities: Dictionary = {}
	var aliases: Dictionary = {}
	var seen: Dictionary = {}
	for raw: Variant in sources:
		if not raw is Dictionary or not raw.get("owner") is String or raw.owner.is_empty() or not raw.get("historical") is bool or raw.get("kind") not in ["site", "party"] or not raw.get("state") is Dictionary: return fail("ORGANIZATION_MIGRATION_SOURCE")
		var source: Dictionary = raw
		var source_key: String = source.owner + (":history" if source.historical else ":live")
		if seen.has(source_key): return fail("DUPLICATE_ORGANIZATION_OWNER")
		seen[source_key] = true
		if source.historical:
			if source.kind != "party" or not Travel.validate_identity(source.state.get("travel_identity")): return fail("ORGANIZATION_HISTORICAL_IDENTITY_REQUIRED")
			for kind: String in ["nation", "family"]:
				for reference: Dictionary in source.state.travel_identity.refs[kind].values(): aliases[Travel.stable_key(reference)] = reference.duplicate(true)
			continue
		if source.kind == "party" and (source.state.has("family") or not source.state.get("equipment_nations", {}).is_empty()): return fail("ORGANIZATION_PARTY_BODY_CONTEXT_REQUIRED")
		var admitted: Dictionary = migrate(world, revision, [source.state], people, person_validator)
		if not admitted.ok: return admitted
		for kind: String in ["nation", "family"]:
			var table: Dictionary = admitted.registry.nations if kind == "nation" else admitted.registry.families
			for entry: Dictionary in table.values():
				var added: Dictionary = add_record(registry, kind, entry.reference, entry.record, str(entry.home_site_id))
				if not added.ok: return added
		bindings[source.owner] = admitted.states[0][WIRE_KEY].duplicate(true)
		identities[source.owner] = admitted.states[0].travel_identity.duplicate(true)
	for kind: String in ["nation", "family"]:
		var members: Dictionary = {}
		var table: Dictionary = registry.nations if kind == "nation" else registry.families
		for key: String in table:
			for member: Variant in table[key].record.members:
				var id: int = int(member.person_id) if kind == "family" else int(member)
				if members.has(str(id)) and members[str(id)] != key: return fail("DUPLICATE_" + kind.to_upper() + "_MEMBERSHIP")
				members[str(id)] = key
	for key: String in aliases:
		if not registry.nations.has(key) and not registry.families.has(key): registry.retired[key] = aliases[key]
	if not valid(registry, world): return fail("INVALID_ORGANIZATION_REGISTRY")
	return {"ok": true, "registry": registry, "bindings": bindings, "identities": identities, "historical_aliases": aliases}
