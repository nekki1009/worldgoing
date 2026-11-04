class_name RegionFactionQuery
extends RefCounted
## Pure candidates only. RegionSaveSlot owns publication; nations stay in Site/party.
const VERSION := 1
const MAX_ID := 100000000
const MAX_REVISION := 9007199254740991
## Reserved neutral side (一人隊 / unaffiliated teams). 255 is inside every faction-id validator range
## (crowd admission is 0..255; registry, army and store are 0..MAX_ID), no fixture or scenario uses it,
## and allocate() skips it so a newly allocated faction can never collide.
const NEUTRAL_FACTION_ID := 255
const NEUTRAL_NAME := "中立"
const ENTRY_FIELDS := ["faction_id", "name", "color", "kind", "leader_ref", "nation_ref", "status", "merged_into", "founded_at", "ended_at"]

static func fail(code: String, message: String = "") -> Dictionary:
	return {"ok": false, "code": code, "message": message}

static func whole(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high

static func keys(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size(): return false
	for field: String in fields:
		if not value.has(field): return false
	return true

static func ref_valid(value: Variant, kind: String) -> bool:
	return value is Dictionary and keys(value, ["type", "namespace", "lineage"]) and value.type == kind and value.namespace is String and not str(value.namespace).is_empty() and whole(value.lineage, 1, MAX_REVISION)

static func ref_key(value: Dictionary) -> String:
	return JSON.stringify([value.type, value.namespace, int(value.lineage)])

static func _time(value: Variant, now: float) -> bool:
	return value == null or (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= now

static func validate(value: Variant, now: float) -> Dictionary:
	# `peerage` (nobility ranks, RegionPeerage) is optional: a registry without it simply has no titled people.
	var registry_fields: Array = ["version", "revision", "next_faction_id", "migration_complete", "entries", "coverage"]
	if value is Dictionary and value.has("peerage"): registry_fields.append("peerage")
	if not value is Dictionary or not keys(value, registry_fields): return fail("CORRUPT_SAVE", "faction registry fields")
	if not whole(value.version, VERSION, VERSION): return fail("SAVE_VERSION", "unknown faction registry version")
	if not whole(value.revision, 0, MAX_REVISION) or not whole(value.next_faction_id, 0, MAX_ID + 1) or not value.migration_complete is bool or value.migration_complete != true or not value.entries is Dictionary or not value.coverage is Dictionary: return fail("CORRUPT_SAVE", "incomplete faction migration")
	var bound := {}
	for key: Variant in value.entries:
		var entry: Variant = value.entries[key]
		if not key is String or not key.is_valid_int() or str(int(key)) != key or not entry is Dictionary: return fail("CORRUPT_SAVE", "faction key")
		var fields: Array = ENTRY_FIELDS.duplicate()
		if entry.get("nation_ref") == null: fields.append("duty_ai")
		if not keys(entry, fields) or not whole(entry.faction_id, 0, MAX_ID) or int(entry.faction_id) != int(key) or int(entry.faction_id) >= int(value.next_faction_id): return fail("CORRUPT_SAVE", "faction high water")
		if not entry.name is String or entry.name != entry.name.strip_edges() or entry.name.length() > 32 or not entry.color is String or entry.color.length() != 8 or not entry.color.is_valid_hex_number(false) or entry.color.right(2).to_lower() != "ff" or entry.kind not in ["player", "npc", "rebel"]: return fail("CORRUPT_SAVE", "faction presentation")
		if entry.status not in ["active", "merged", "extinct"] or not _time(entry.founded_at, now) or not _time(entry.ended_at, now): return fail("CORRUPT_SAVE", "faction status/time")
		if entry.status == "active" and (entry.ended_at != null or entry.merged_into != null): return fail("CORRUPT_SAVE", "active faction endpoint")
		if entry.status != "active" and entry.ended_at == null: return fail("CORRUPT_SAVE", "missing historical endpoint")
		if entry.founded_at != null and entry.ended_at != null and float(entry.ended_at) < float(entry.founded_at): return fail("CORRUPT_SAVE", "reversed faction time")
		if entry.status == "merged":
			if not whole(entry.merged_into, 0, MAX_ID) or int(entry.merged_into) == int(entry.faction_id) or value.entries.get(str(int(entry.merged_into)), {}).get("status") not in ["active", "extinct"]: return fail("CORRUPT_SAVE", "merged endpoint")
		elif entry.merged_into != null: return fail("CORRUPT_SAVE", "unexpected merged endpoint")
		if entry.leader_ref != null and not ref_valid(entry.leader_ref, "person"): return fail("CORRUPT_SAVE", "leader typed ref")
		if entry.nation_ref != null:
			if entry.status != "active" or entry.leader_ref != null or not ref_valid(entry.nation_ref, "nation") or bound.has(ref_key(entry.nation_ref)): return fail("CORRUPT_SAVE", "duplicate nation binding")
			bound[ref_key(entry.nation_ref)] = true
		elif not entry.duty_ai is bool: return fail("CORRUPT_SAVE", "unbound duty switch")
	var coverage: Dictionary = value.coverage
	if not keys(coverage, ["complete", "sources", "counts"]) or coverage.complete != false or not coverage.complete is bool or not coverage.sources is Array or coverage.counts != null: return fail("CORRUPT_SAVE", "unknown coverage must not be zero")
	for source: Variant in coverage.sources:
		if not source is Dictionary or not keys(source, ["owner", "source_generation", "runtime_revision", "checksum", "as_of_game_seconds", "complete"]) or not source.owner is String or source.owner.is_empty() or source.source_generation != null and not whole(source.source_generation, 0, 2147483647) or source.runtime_revision != null and not whole(source.runtime_revision, 0, MAX_REVISION) or not source.checksum is String or source.checksum.length() != 64 or not source.checksum.is_valid_hex_number(false) or not _time(source.as_of_game_seconds, now) or source.as_of_game_seconds == null or source.complete != true: return fail("CORRUPT_SAVE", "faction source receipt")
	if value.has("peerage"):
		var titled: Dictionary = RegionPeerage.validate(value.peerage, value, now)
		if not titled.ok: return titled
	return {"ok": true}

## Same side for hostility, recruiting, garrison, consent and diplomacy. Neutral is never allied with
## neutral: two different neutral teams stay apart. Callers keep same-team identity checks themselves.
static func same_side(a: int, b: int) -> bool:
	return a == b and a != NEUTRAL_FACTION_ID

static func neutral_entry() -> Dictionary:
	return {"faction_id": NEUTRAL_FACTION_ID, "name": NEUTRAL_NAME, "color": "8a897fff", "kind": "npc", "leader_ref": null, "nation_ref": null, "status": "active", "merged_into": null, "founded_at": null, "ended_at": null, "duty_ai": false}

static func resolve(registry: Dictionary, faction_id: int) -> Dictionary:
	if registry.get("version") != VERSION or registry.get("migration_complete") != true: return fail("UNKNOWN", "no complete registry")
	var entry: Dictionary = registry.get("entries", {}).get(str(faction_id), {})
	if entry.is_empty() and faction_id == NEUTRAL_FACTION_ID: entry = neutral_entry()
	if entry.get("status") == "merged":
		var target: Variant = entry.get("merged_into")
		if not whole(target, 0, MAX_ID) or int(target) == faction_id: return fail("CORRUPT_SAVE", "merged endpoint")
		entry = registry.entries.get(str(int(target)), {})
	if entry.get("status") not in ["active", "extinct"]: return fail("NO_FACTION")
	return {"ok": true, "requested_faction_id": faction_id, "faction_id": int(entry.faction_id), "entry": entry.duplicate(true), "revision": int(registry.revision)}

static func active(registry: Dictionary, faction_id: int) -> Dictionary:
	var resolved: Dictionary = resolve(registry, faction_id)
	if not resolved.ok: return resolved
	return resolved if resolved.entry.status == "active" else fail("NO_FACTION")

static func display(registry: Dictionary, faction_id: int) -> Dictionary:
	var entry: Dictionary = registry.get("entries", {}).get(str(faction_id), {})
	if entry.is_empty() and faction_id == NEUTRAL_FACTION_ID: entry = neutral_entry()
	return {"id": faction_id, "name": str(entry.get("name", "")) if not str(entry.get("name", "")).is_empty() else "勢力 %d" % faction_id, "color": entry.get("color"), "status": entry.get("status", "unknown"), "counts": null, "coverage_complete": bool(registry.get("coverage", {}).get("complete", false))}

static func legacy_entry(faction_id: int) -> Dictionary:
	var palette: String = SiteEquipmentOrders.npc_palette_id(faction_id)
	var colors: Dictionary = SiteRuntime.EquipmentDye.PRESETS.get(palette, {}).get("colors", {})
	var color: String = str(colors.get("armor", "8a897fff"))
	return {"faction_id": faction_id, "name": "", "color": color, "kind": "npc", "leader_ref": null, "nation_ref": null, "status": "active", "merged_into": null, "founded_at": null, "ended_at": null, "duty_ai": false}

## Read only named faction fields; never treat every integer as an ID or rewrite history.
static func collect_ids(value: Variant, ids: Dictionary) -> Dictionary:
	if value is Dictionary:
		for key: Variant in value:
			# Non-text keys still contain real nested owners; only field matching is guarded.
			if key is String or key is StringName:
				var field_name: String = str(key)
				if field_name in ["faction_id", "faction", "owner_faction", "captor_faction", "contest_faction"]:
					if not whole(value[key], -1, MAX_ID): return fail("CORRUPT_SAVE", "faction input outside domain")
					if int(value[key]) >= 0: ids[str(int(value[key]))] = true
				elif field_name == "last_fall" and value[key] is Dictionary and not value[key].is_empty():
					for field: String in ["from", "to"]:
						if not whole(value[key].get(field), 0, MAX_ID): return fail("CORRUPT_SAVE", "historical faction")
						ids[str(int(value[key][field]))] = true
			var result: Dictionary = collect_ids(value[key], ids)
			if not result.get("ok", false):
				return result if result.has("ok") else fail("CORRUPT_SAVE", "faction recursion missing result status")
	elif value is Array:
		for row: Variant in value:
			var result: Dictionary = collect_ids(row, ids)
			if not result.get("ok", false):
				return result if result.has("ok") else fail("CORRUPT_SAVE", "faction recursion missing result status")
	return {"ok": true}

static func nation_schema(nation: Dictionary, nation_id: String) -> bool:
	if not nation.has("faction_version") and not nation.has("faction_id"): return true # Unmapped legacy/trial only.
	return not nation_id.begins_with("trial_team_") and whole(nation.get("faction_version"), 1, 1) and whole(nation.get("faction_id"), 0, MAX_ID)

static func reciprocal(registry: Dictionary, states: Array[Dictionary]) -> Dictionary:
	var actual := {}
	for state: Dictionary in states:
		for nation_id: String in state.get("equipment_nations", {}):
			var nation: Dictionary = state.equipment_nations[nation_id]
			if not nation_schema(nation, nation_id): return fail("CORRUPT_SAVE", "nation faction schema")
			if not nation.has("faction_id"): continue
			var ref: Variant = state.get("travel_identity", {}).get("refs", {}).get("nation", {}).get(nation_id)
			if not ref_valid(ref, "nation"): return fail("CORRUPT_SAVE", "bound nation lacks original typed ref")
			var key: String = ref_key(ref)
			var entry: Dictionary = registry.get("entries", {}).get(str(int(nation.faction_id)), {})
			if actual.has(key) or entry.get("status") != "active" or entry.get("nation_ref") != ref: return fail("CORRUPT_SAVE", "nation reciprocal/duplicate authority")
			actual[key] = int(nation.faction_id)
	for entry: Dictionary in registry.get("entries", {}).values():
		if entry.nation_ref != null and actual.get(ref_key(entry.nation_ref), -1) != int(entry.faction_id): return fail("CORRUPT_SAVE", "registry nation owner missing")
	return {"ok": true}

## JSON-loaded numbers are floats, while the in-memory originals are ints. Both
## spellings name the same integer, so the registry stores one canonical int form.
static func whole_or_null(value: Variant) -> Variant:
	if value == null: return null
	return int(value) if (value is int or value is float) else value

static func canonical_receipt(source: Dictionary) -> Dictionary:
	var receipt: Dictionary = source.duplicate(true)
	if receipt.has("source_generation"): receipt.source_generation = whole_or_null(receipt.source_generation)
	if receipt.has("runtime_revision"): receipt.runtime_revision = whole_or_null(receipt.runtime_revision)
	if receipt.get("as_of_game_seconds") is int or receipt.get("as_of_game_seconds") is float: receipt.as_of_game_seconds = float(receipt.as_of_game_seconds)
	return receipt

static func canonical_registry(value: Dictionary) -> Dictionary:
	var registry: Dictionary = value.duplicate(true)
	if registry.get("revision") is int or registry.get("revision") is float: registry.revision = int(registry.revision)
	if registry.get("next_faction_id") is int or registry.get("next_faction_id") is float: registry.next_faction_id = int(registry.next_faction_id)
	if registry.get("coverage") is Dictionary and registry.coverage.get("sources") is Array:
		var sources: Array = []
		for source: Variant in registry.coverage.sources:
			if source is Dictionary: sources.append(canonical_receipt(source))
			else: sources.append(source)
		registry.coverage.sources = sources
	if registry.get("peerage") is Dictionary: registry.peerage = RegionPeerage.canonical(registry.peerage)
	return registry

static func migration(states: Array[Dictionary], receipts: Array[Dictionary], reserved: Array, previous: Dictionary, now: float, complete: bool) -> Dictionary:
	if not complete or states.size() != receipts.size(): return fail("FACTION_SCAN_INCOMPLETE")
	var ids := {}
	if not previous.is_empty():
		var prior: Dictionary = validate(previous, now)
		if not prior.ok: return prior
	# Compare against the canonical form of the previous registry, so a same-source
	# republish (int previously stored, float freshly read) is not a new revision.
	var base: Dictionary = canonical_registry(previous) if not previous.is_empty() else {"version": VERSION, "revision": 0, "next_faction_id": 0, "migration_complete": true, "entries": {}, "coverage": {"complete": false, "sources": [], "counts": null}}
	var registry: Dictionary = base.duplicate(true)
	for id: Variant in reserved:
		if not whole(id, 0, MAX_ID): return fail("INVALID_FACTION")
		ids[str(int(id))] = true
	for state: Dictionary in states:
		var scan: Dictionary = collect_ids(state, ids)
		if not scan.ok: return scan
	for id: String in ids:
		if not registry.entries.has(id): registry.entries[id] = legacy_entry(int(id))
		registry.next_faction_id = maxi(int(registry.next_faction_id), int(id) + 1)
	var canonical_sources: Array = []
	for receipt: Dictionary in receipts: canonical_sources.append(canonical_receipt(receipt))
	registry.coverage = {"complete": false, "sources": canonical_sources, "counts": null}
	if previous.is_empty() or registry != base:
		if int(registry.revision) >= MAX_REVISION: return fail("FACTION_REVISION_EXHAUSTED")
		registry.revision = int(registry.revision) + 1
	# ID coverage is complete; demographic/scenario coverage is deliberately UNKNOWN.
	var validated: Dictionary = validate(registry, now)
	if not validated.ok: return validated
	var bound: Dictionary = reciprocal(registry, states)
	if not bound.ok: return bound
	return {"ok": true, "registry": registry}

## `fields` (name, color, kind, leader_ref, founded_at, duty_ai) overrides the legacy defaults of a founded faction, e.g.
## the player's own faction at the start (kind player, leader the player); the candidate is validated as a whole.
static func allocate(registry: Dictionary, expected_revision: int, now: float, fields: Dictionary = {}) -> Dictionary:
	var checked: Dictionary = validate(registry, now)
	if not checked.ok: return checked
	if int(registry.revision) != expected_revision: return fail("CONFLICT")
	if int(registry.next_faction_id) > MAX_ID: return fail("FACTION_ID_EXHAUSTED")
	if expected_revision >= MAX_REVISION: return fail("FACTION_REVISION_EXHAUSTED")
	var candidate: Variant = registry.duplicate(true)
	var id: int = int(candidate.next_faction_id)
	if id == NEUTRAL_FACTION_ID: id += 1 # reserved neutral side is never allocated
	var entry := legacy_entry(id)
	for key: String in ["name", "color", "kind", "leader_ref", "founded_at", "duty_ai"]:
		if fields.has(key): entry[key] = fields[key]
	candidate.entries[str(id)] = entry
	candidate.next_faction_id = id + 1
	candidate.revision = expected_revision + 1
	if not fields.is_empty():
		var founded: Dictionary = validate(candidate, now)
		if not founded.ok: return founded
	# A founder with a person ref is crowned king of the new faction (RegionPeerage head record).
	if ref_valid(entry.leader_ref, "person"):
		var crowned: Dictionary = RegionPeerage.crown_founder(candidate, id, entry.leader_ref, now)
		if not crowned.ok: return crowned
		candidate = crowned.registry
	return {"ok": true, "registry": candidate, "faction_id": id}

## An unmapped legacy/trial nation cannot acquire a formal faction by inference.
static func bound_faction(registry: Dictionary, state: Dictionary, nation_id: String) -> Dictionary:
	var nation: Dictionary = state.get("equipment_nations", {}).get(nation_id, {})
	if not nation_schema(nation, nation_id) or not nation.has("faction_id"): return fail("NO_FORMAL_NATION")
	var selected: Dictionary = active(registry, int(nation.faction_id))
	if not selected.ok: return selected
	var reference: Variant = state.get("travel_identity", {}).get("refs", {}).get("nation", {}).get(nation_id)
	if not ref_valid(reference, "nation") or selected.entry.nation_ref != reference: return fail("FACTION_BINDING_MISMATCH")
	return {"ok": true, "faction_id": int(nation.faction_id), "nation_ref": reference.duplicate(true), "revision": int(registry.revision)}
