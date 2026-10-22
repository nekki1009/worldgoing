extends RefCounted
## Pure deterministic runtime ID admission. Immutable source IDs remain lineage.
const Checkpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const DOMAINS := ["fire_projectile", "fire_job", "formation_runtime", "proposal", "lease_token"]
const SOURCE_FIELDS := ["namespace", "owner", "token", "source_generation", "party_hash", "maps", "fire_receipts", "prior"]

static func valid(mapping: Variant, destination_namespace: String = "", generation: int = -1, depth: int = 0) -> bool:
	if depth > 8 or not mapping is Dictionary or mapping.size() != 5 or mapping.get("version") != 1 \
			or not mapping.get("destination_namespace") is String or str(mapping.destination_namespace).is_empty() \
			or not Checkpoint.integer(mapping.get("generation")) or not mapping.get("sources") is Array \
			or mapping.sources.is_empty() or mapping.sources.size() > 64 or not mapping.get("next") is Dictionary \
			or mapping.next.size() != DOMAINS.size(): return false
	if not destination_namespace.is_empty() and mapping.destination_namespace != destination_namespace: return false
	if generation >= 0 and int(mapping.generation) != generation: return false
	var owners := {}
	var destinations := {}
	for domain: String in DOMAINS:
		if not Checkpoint.integer(mapping.next.get(domain), 1) or int(mapping.next[domain]) > 2147483647: return false
		destinations[domain] = {}
	for source: Variant in mapping.sources:
		if not source is Dictionary or source.size() != SOURCE_FIELDS.size(): return false
		for field: String in SOURCE_FIELDS:
			if not source.has(field): return false
		if not source.namespace is String or str(source.namespace).is_empty() or str(source.namespace).length() > 256 \
				or not source.owner is String or source.owner != "travel:" + str(source.token) \
				or not source.token is String or str(source.token).is_empty() or owners.has(str(source.owner)) \
				or not Checkpoint.integer(source.source_generation) or not source.party_hash is String \
				or str(source.party_hash).length() != 64 or not source.maps is Dictionary or source.maps.size() != DOMAINS.size() \
				or not _valid_receipts(source.fire_receipts) or not source.prior is Dictionary: return false
		if not _valid_prior(source.prior): return false
		owners[str(source.owner)] = true
		for domain: String in DOMAINS:
			var ids: Variant = source.maps.get(domain)
			if not ids is Dictionary or ids.size() > 100000: return false
			for original: Variant in ids:
				if not original is String or not str(original).is_valid_int() or str(int(original)) != original \
						or int(original) < 1 or int(original) > 2147483647 or not Checkpoint.integer(ids[original], 1) \
						or int(ids[original]) >= int(mapping.next[domain]) or destinations[domain].has(int(ids[original])): return false
				destinations[domain][int(ids[original])] = source.owner
	return true

static func _valid_receipts(receipts: Variant) -> bool:
	if not receipts is Dictionary or receipts.size() != 2 or not Checkpoint.integer(receipts.get("floor")) \
			or not receipts.get("ids") is Dictionary or receipts.ids.size() > 100000: return false
	for key: Variant in receipts.ids:
		if not key is String or not str(key).is_valid_int() or str(int(key)) != key or int(key) <= int(receipts.floor) \
				or receipts.ids[key] != true: return false
	return true

## Sources carry actual captured current ID sets and immutable receipt lineage.
## Destination source is first; subsequent sources are sorted by original owner.
static func allocate(sources: Array, destination_namespace: String, generation: int) -> Dictionary:
	if sources.is_empty() or destination_namespace.is_empty() or generation < 0: return Runtime.fail("INVALID_REGION_RUNTIME_MAPPING")
	var originals: Array = sources.duplicate(true)
	if originals.size() > 1:
		var incoming := originals.slice(1)
		incoming.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("owner", "")) < str(b.get("owner", "")))
		originals = [originals[0]] + incoming
	var result := {"version": 1, "destination_namespace": destination_namespace, "generation": generation, "sources": [], "next": {}}
	var used := {}
	for domain: String in DOMAINS: used[domain] = {}; result.next[domain] = 1
	var identities := {}
	for source_index: int in originals.size():
		var raw: Variant = originals[source_index]
		if not raw is Dictionary or raw.size() not in [8, 9] or not raw.get("ids") is Dictionary \
				or raw.ids.size() != DOMAINS.size() or not raw.get("highwater") is Dictionary \
				or raw.highwater.size() != DOMAINS.size(): return Runtime.fail("INVALID_REGION_RUNTIME_MAPPING")
		var source := {"namespace": raw.get("namespace"), "owner": raw.get("owner"), "token": raw.get("token"),
			"source_generation": raw.get("source_generation"), "party_hash": raw.get("party_hash"), "maps": {},
			"fire_receipts": raw.get("fire_receipts"), "prior": raw.get("prior", {})}
		if identities.has(source.owner): return Runtime.fail("DUPLICATE_REGION_RUNTIME_SOURCE")
		identities[source.owner] = true
		for domain: String in DOMAINS:
			if not raw.ids[domain] is Array or not Checkpoint.integer(raw.highwater[domain]): return Runtime.fail("INVALID_REGION_RUNTIME_MAPPING")
			var ids: Array = raw.ids[domain].duplicate()
			ids.sort()
			var local := {}
			source.maps[domain] = {}
			for old: Variant in ids:
				if not Checkpoint.integer(old, 1) or local.has(int(old)) or int(old) > int(raw.highwater[domain]):
					return Runtime.fail("INVALID_REGION_RUNTIME_MAPPING")
				local[int(old)] = true
				var current := int(old) if source_index == 0 else int(result.next[domain])
				while used[domain].has(current): current += 1
				if current >= 2147483647: return Runtime.fail("REGION_RUNTIME_SEQUENCE_EXHAUSTED")
				source.maps[domain][str(int(old))] = current
				used[domain][current] = true
				result.next[domain] = maxi(int(result.next[domain]), current + 1)
			# Retain monotonic headroom even when no current record references old IDs.
			if source_index == 0: result.next[domain] = maxi(int(result.next[domain]), int(raw.highwater[domain]) + 1)
		result.sources.append(source)
	if not valid(result, destination_namespace, generation): return Runtime.fail("INVALID_REGION_RUNTIME_MAPPING")
	return Runtime.ok("", {"mapping": result})

static func source(mapping: Dictionary, owner: String, source_namespace: String, party_hash: String) -> Dictionary:
	if not valid(mapping): return Runtime.fail("INVALID_REGION_RUNTIME_MAPPING")
	for row: Dictionary in mapping.sources:
		if row.owner != owner: continue
		if row.namespace != source_namespace or row.party_hash != party_hash: return Runtime.fail("REGION_RUNTIME_SOURCE_SCOPE")
		return Runtime.ok("", {"source": row})
	return Runtime.fail("REGION_RUNTIME_SOURCE_SCOPE")

static func current(row: Dictionary, domain: String, old: int) -> int:
	if old <= 0: return old
	return int(row.get("maps", {}).get(domain, {}).get(str(old), -1))
static func remap_transport(raw: Dictionary, mapping: Dictionary, owner: String,
		source_namespace: String, party_hash: String, identity_maps: Dictionary = {}) -> Dictionary:
	var admitted := source(mapping, owner, source_namespace, party_hash)
	if not admitted.ok: return admitted
	var row: Dictionary = admitted.source
	if raw.size() != 11 or not raw.get("projectiles") is Array or not raw.get("reservations") is Array \
			or not raw.get("orders") is Array or not raw.get("member_cursor") is Array:
		return Runtime.fail("INVALID_REGION_FIRE_RUNTIME_MAPPING")
	var result := raw.duplicate(true)
	for flight: Dictionary in result.projectiles:
		var identity := current(row, "fire_projectile", int(flight.get("projectile_id", -1)))
		if identity <= 0: return Runtime.fail("UNMAPPED_REGION_FIRE_FLIGHT")
		flight.projectile_id = identity
		flight.source_member_id = _identity(identity_maps, "person", flight.source_member_id)
		flight.source_formation_id = _identity(identity_maps, "team", flight.source_formation_id)
	for order: Dictionary in result.orders:
		order.group = _group(identity_maps, int(order.group))
		order.issuer_id = _identity(identity_maps, "person", order.issuer_id)
		for release: Array in order.release_ids:
			if release.size() != 2: return Runtime.fail("INVALID_REGION_FIRE_RUNTIME_MAPPING")
			release[0] = _identity(identity_maps, "person", release[0])
			if int(release[1]) <= 0: continue
			release[1] = current(row, "fire_projectile", int(release[1]))
			if int(release[1]) <= 0: return Runtime.fail("UNMAPPED_REGION_FIRE_RELEASE")
		if order.target.get("type") == "person": order.target.person_id = _identity(identity_maps, "person", order.target.person_id)
	for reservation: Dictionary in result.reservations:
		reservation.person_id = _identity(identity_maps, "person", reservation.person_id)
		reservation.formation_id = _identity(identity_maps, "team", reservation.formation_id)
		reservation.stamp.holder = "person:" + str(int(reservation.person_id))
		if reservation.target.get("type") == "person": reservation.target.person_id = _identity(identity_maps, "person", reservation.target.person_id)
	for pair: Array in result.member_cursor:
		if pair.size() != 2: return Runtime.fail("INVALID_REGION_FIRE_RUNTIME_MAPPING")
		pair[0] = _group(identity_maps, int(pair[0]))
		pair[1] = _identity(identity_maps, "person", pair[1])
	result["release_sequence"] = int(mapping.next.fire_projectile) - 1
	return Runtime.ok("", {"transport": result})

static func _identity(maps: Dictionary, kind: String, old: Variant) -> Variant:
	if int(old) <= 0: return old
	var value: Variant = maps.get(kind, {}).get(str(old), old)
	return int(value) if old is int else str(value)

static func _group(maps: Dictionary, old: int) -> int:
	return -int(_identity(maps, "person", -old)) if old < 0 else int(_identity(maps, "team", old))

static func merge_transports(transports: Array) -> Dictionary:
	if transports.is_empty(): return Runtime.fail("INVALID_REGION_FIRE_RUNTIME_MAPPING")
	var result: Dictionary = transports[0].duplicate(true)
	for field: String in ["projectiles", "reservations", "orders", "member_cursor"]: result[field] = []
	var seen := {"projectiles": {}, "reservations": {}, "orders": {}, "member_cursor": {}}
	for raw: Variant in transports:
		if not raw is Dictionary: return Runtime.fail("INVALID_REGION_FIRE_RUNTIME_MAPPING")
		for field: String in ["version", "config_version", "action_cursor", "physical_ranged_enabled", "release_sequence"]:
			if raw.get(field) != result.get(field): return Runtime.fail("REGION_FIRE_CLOCK_CONFLICT")
		result["exposure_sequence"] = maxi(int(result.exposure_sequence), int(raw.exposure_sequence))
		for pair: Array in [["projectiles", "projectile_id"], ["reservations", "person_id"], ["orders", "group"], ["member_cursor", ""]]:
			for value: Variant in raw[pair[0]]:
				var identity: int = int(value[0]) if str(pair[1]).is_empty() else int(value[pair[1]])
				if seen[pair[0]].has(identity): return Runtime.fail("DUPLICATE_REGION_FIRE_RUNTIME_OWNER")
				seen[pair[0]][identity] = true
				result[pair[0]].append(value)
	return Runtime.ok("", {"transport": result})

# Current source IDs are collected from the original validated graph. The
# previous map is immutable lineage; another join never re-labels its origin.
const HISTORY_FIELDS := ["history", "receipts", "inventory_receipts", "paid_receipts", "hit_receipts", "episodes",
	"completed_events", "original_owner", "travel_identity", "family", "family_refs", "organization_refs", "technology", "rule", "_region_legacy_noise"]
const PERSON_VALUES := ["person_id", "member_id", "operator_id", "commander_person_id", "leader_person_id", "controlled_person_id",
	"captor_id", "guard_id", "patient_id", "carrier_id", "military_head", "requester_id", "executor_id", "target_id",
	"source_member_id", "head_person_id", "training_requester", "borrower_id", "rider_id", "vacancy_waiting_id",
	"representative_id", "player_id", "original_person_id", "attack_target_id", "ranged_order_issuer_id", "shooter_id", "actor", "waiting"]
const PERSON_KEYS := ["actor_hot", "_jobs", "_results", "_pending_deaths", "_active_ids",
	"_retry_left", "_working", "_manual_hits", "_release_walks", "_fire_body_active", "_fire_motion", "_member_lookup",
	"person_supply", "carriers", "patients", "life_checkpoint", "member_cursor", "_move_landed_members", "_combat_absent_slots", "_suppress_approaches"]
const PERSON_LISTS := ["person_ids", "members", "active_mids", "active_member_ids", "following_member_ids",
	"active_vacancy_chain_actors", "verified_chain_arrival_members", "_region_point_wakes", "_combat_batch_members",
	"_move_landed_members", "patient_ids", "crew_ids", "target_ids", "participants"]
const TEAM_KEYS := ["army_hot", "plans", "deliveries", "team_supply", "_supply_rout_review"]
const RUNTIME_FIELDS := {"formation_id": "formation_runtime", "formation_runtime_id": "formation_runtime",
	"runtime_id": "formation_runtime", "projectile_id": "fire_projectile", "job_token": "fire_job",
	"proposal_id": "proposal", "dependency_proposal_id": "proposal", "lease_token": "lease_token"}

static func _clone(value: Variant, originals: Array, copies: Array) -> Variant:
	if not (value is Dictionary or value is Array): return value
	for index: int in originals.size():
		if is_same(originals[index], value): return copies[index]
	var copy: Variant = {} if value is Dictionary else value.duplicate(false)
	if copy is Array: copy.clear()
	originals.append(value); copies.append(copy)
	if value is Dictionary:
		for key: Variant in value: copy[key] = _clone(value[key], originals, copies)
	else:
		for item: Variant in value: copy.append(_clone(item, originals, copies))
	return copy

static func _collect(value: Variant, field: String, ids: Dictionary, seen: Array) -> void:
	if field in HISTORY_FIELDS: return
	if value is int and value > 0 and RUNTIME_FIELDS.has(field): ids[RUNTIME_FIELDS[field]][value] = true
	if not (value is Dictionary or value is Array): return
	for prior: Variant in seen:
		if is_same(prior, value): return
	seen.append(value)
	if value is Dictionary:
		for key: Variant in value:
			if field in ["egress", "formation_slots"] and int(key) > 0: ids.formation_runtime[int(key)] = true
			if field == "member_pending_proposal_id" and int(value[key]) > 0: ids.proposal[int(value[key])] = true
			_collect(value[key], str(key), ids, seen)
	else:
		if field == "leases":
			for pair: Variant in value:
				if pair is Array and pair.size() == 2 and pair[1] is Array and pair[1].size() == 6:
					ids.formation_runtime[int(pair[1][0])] = true
		for item: Variant in value: _collect(item, "", ids, seen)

static func collect_source(party: Dictionary, roots: Dictionary, transport: Dictionary, fire: Dictionary,
		generation: int, prior: Dictionary = {}) -> Dictionary:
	if not prior.is_empty() and not valid(prior, str(party.content.travel_identity.namespace)): return Runtime.fail("INVALID_REGION_RUNTIME_LINEAGE")
	var ids := {}
	for domain: String in DOMAINS: ids[domain] = {}
	_collect(roots, "", ids, [])
	# Fire reservation.formation_id names a TEAM; only paid flight/release
	# IDs belong to runtime projectile space. No recursive transport field walk.
	for flight: Dictionary in transport.get("projectiles", []):
		if int(flight.get("projectile_id", 0)) > 0: ids.fire_projectile[int(flight.projectile_id)] = true
	for order: Dictionary in transport.get("orders", []):
		for release: Array in order.get("release_ids", []):
			if release.size() == 2 and int(release[1]) > 0: ids.fire_projectile[int(release[1])] = true
	for key: Variant in fire.get("receipt_ids", {}): ids.fire_projectile[int(key)] = true
	for value: Dictionary in fire.get("contacts", {}).values(): ids.fire_projectile[int(value.projectile_id)] = true
	var highwater := {"fire_projectile": maxi(int(transport.get("release_sequence", 0)), int(fire.get("receipt_floor", 0))),
		"fire_job": int(roots.get("actions", {}).get("_next_fire_job_token", 1)) - 1,
		"formation_runtime": int(roots.get("coordinator", {}).get("_next_formation_runtime_id", 1)) - 1,
		"proposal": 0, "lease_token": int(roots.get("registry", {}).get("next_token", 1)) - 1}
	var lists := {}
	for domain: String in DOMAINS:
		lists[domain] = ids[domain].keys()
		lists[domain].sort()
		for identity: int in lists[domain]: highwater[domain] = maxi(int(highwater[domain]), identity)
	var receipts := {}
	for key: Variant in fire.get("receipt_ids", {}): receipts[str(int(key))] = true
	var raw := {"namespace": str(party.content.travel_identity.namespace), "owner": "travel:" + str(party.party_id),
		"token": str(party.party_id), "source_generation": generation,
		"party_hash": Marshalls.raw_to_base64(var_to_bytes(party)).sha256_text(), "ids": lists, "highwater": highwater,
		"fire_receipts": {"floor": int(fire.get("receipt_floor", 0)), "ids": receipts}, "prior": _prior_epochs(prior)}
	return Runtime.ok("", {"source": raw})

static func _symbol_key(key: String, row: Dictionary, maps: Dictionary, options: Dictionary) -> String:
	var parts := key.split(":")
	if parts.size() >= 2 and parts[0] in ["person", "team", "fire_flight"]:
		var kind := str(parts[0])
		parts[1] = str(current(row, "fire_projectile", int(parts[1]))) if kind == "fire_flight" else str(_identity(maps, kind, parts[1]))
		if kind == "team" and parts.size() >= 4 and parts[2] in ["batch", "fire_lease"]: parts[3] = str(_identity(maps, "person", parts[3]))
		return ":".join(parts)
	if parts.size() == 3 and parts[0] == "lease" and parts[1].is_valid_int() and parts[2].is_valid_int():
		var offset: Array = options.get("default_offset", [0, 0])
		return "lease:%d:%d" % [int(parts[1]) + int(offset[0]), int(parts[2]) + int(offset[1])]
	if key.begins_with("site:"):
		var parsed: Variant = JSON.parse_string(key.trim_prefix("site:"))
		if not Checkpoint.valid_wire(parsed): return ""
		var path: Variant = Checkpoint.unwire(parsed)
		if not path is Array: return ""
		for index: int in path.size() - 1:
			var kind: String = {"vehicles": "vehicle", "team_supply": "team", "person_supply": "person",
				"item_records": "item", "ground_loot": "loot", "equipment_nations": "nation", "corps": "corps"}.get(str(path[index]), "")
			if not str(kind).is_empty(): path[index + 1] = _identity(maps, kind, path[index + 1])
			elif str(path[index]) == "armies":
				var old := str(path[index + 1])
				if not options.get("army_indices", {}).has(old): return ""
				path[index + 1] = int(options.army_indices[old])
		return "site:" + JSON.stringify(Checkpoint.wire(path))
	return key

static func _map_value(value: Variant, field: String, row: Dictionary, maps: Dictionary, options: Dictionary,
		seen: Array, error: Dictionary) -> Variant:
	if field in HISTORY_FIELDS: return value
	# A body read back from saved JSON carries whole-number ids as floats; an id
	# field maps such a value as the int it is. Any other field keeps its value.
	if value is float and is_finite(value) and value == floorf(value) and (RUNTIME_FIELDS.has(field) or field in PERSON_VALUES \
			or field in ["team_id", "source_formation_id", "group", "vehicle_id", "embarked_vehicle_id", "bound_vehicle_id", "ship_vehicle_id",
			"source_vehicle", "item_id", "equipment_item_id", "holder"]):
		value = int(value)
	if value is int or value is String:
		if RUNTIME_FIELDS.has(field) and int(value) > 0:
			var mapped := current(row, RUNTIME_FIELDS[field], int(value))
			if mapped <= 0: error.code = "UNMAPPED_REGION_RUNTIME_REFERENCE"
			return mapped if value is int else str(mapped)
		if field in PERSON_VALUES: return _identity(maps, "person", value)
		if field in ["team_id", "source_formation_id"]: return _identity(maps, "team", value)
		if field == "group": return _group(maps, int(value))
		if field in ["vehicle_id", "embarked_vehicle_id", "bound_vehicle_id", "ship_vehicle_id", "source_vehicle"]: return _identity(maps, "vehicle", value)
		if field in ["item_id", "equipment_item_id"]: return _identity(maps, "item", value)
		if field == "holder": return _identity(maps, "person", value) if value is int else _holder(str(value), maps)
		if field == "site_id" and str(value) == str(options.get("source_owner", "")): return str(options.get("destination_owner", value))
		return value
	if not (value is Dictionary or value is Array): return value
	for prior: Variant in seen:
		if is_same(prior, value): return value
	seen.append(value)
	if value is Array:
		if field == "leases":
			for lease: Array in value:
				if lease.size() != 2 or not lease[1] is Array or lease[1].is_empty(): continue
				lease[1][0] = current(row, "formation_runtime", int(lease[1][0]))
				lease[1][2] = int(_identity(maps, "person", lease[1][2]))
			return value
		if field == "fatigue_work":
			for work: Array in value: work[0] = int(_identity(maps, "person", work[0]))
			return value
		for index: int in value.size():
			if field == "retreat_pairs_used": value[index] = _person_pair(str(value[index]), maps, error)
			elif (field in PERSON_LISTS or field.ends_with("_member_ids") or field in ["active", "hold", "verified"]) and (value[index] is int or value[index] is String):
				value[index] = _identity(maps, "person", value[index])
			elif field in ["item_ids"]: value[index] = _identity(maps, "item", value[index])
			else: value[index] = _map_value(value[index], "", row, maps, options, seen, error)
		return value
	if value.size() == 2 and value.get("@region_reference") is String:
		var key := _symbol_key(value["@region_reference"], row, maps, options)
		if key.is_empty() or key.ends_with(":-1"): error.code = "UNMAPPED_REGION_SYMBOL"
		value["@region_reference"] = key
		return value
	var entries: Dictionary = value.duplicate(false)
	var original_person := entries.has("owner") and entries.get("unit") is int and entries.get("id") is int
	value.clear()
	for key: Variant in entries:
		var new_key: Variant = key
		if field == "_retreat_pairs_used": new_key = _person_pair(str(key), maps, error)
		elif field in PERSON_KEYS or field.begins_with("member_") or field in ["pre_route_staging_slots", "verified_chain_arrival_members", "start_cells", "targets", "ever_admitted_platform_member_ids"]:
			new_key = _identity(maps, "person", key)
		elif field in TEAM_KEYS: new_key = _identity(maps, "team", key)
		elif field == "vehicles": new_key = _identity(maps, "vehicle", key)
		elif field in ["egress", "formation_slots"]: new_key = current(row, "formation_runtime", int(key))
		elif field == "reference_objects": new_key = _symbol_key(str(key), row, maps, options)
		elif field in ["slot_owner_map", "slot_lease_owner_map"] or field in ["_current_occupancy", "_retained_occupancy", "grid_committed_occupancy"]:
			entries[key] = _identity(maps, "person", entries[key])
		var next: Variant = entries[key]
		if field == "equipped": next = _identity(maps, "item", next)
		elif field == "crew_slots": next = _identity(maps, "person", next)
		elif (field == "player_member" or original_person) and str(key) == "id": next = _identity(maps, "person", next)
		if field == "_fire_body_buckets": next = _map_value(next, "person_ids", row, maps, options, seen, error)
		elif field == "member_pending_proposal_id" and int(next) > 0: next = current(row, "proposal", int(next))
		else: next = _map_value(next, str(key), row, maps, options, seen, error)
		if value.has(new_key): error.code = "REGION_RUNTIME_KEY_COLLISION"
		value[new_key] = next
	return value

static func _person_pair(value: String, maps: Dictionary, error: Dictionary) -> String:
	var parts := value.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		error["code"] = "INVALID_REGION_RETREAT_PAIR"
		return value
	var first := int(_identity(maps, "person", parts[0]))
	var second := int(_identity(maps, "person", parts[1]))
	return "%d:%d" % [mini(first, second), maxi(first, second)]

static func _holder(value: String, maps: Dictionary) -> String:
	var parts := value.split(":")
	if parts.size() != 2: return value
	var kind := "loot" if parts[0] == "ground" else str(parts[0])
	return str(parts[0]) + ":" + str(_identity(maps, kind, parts[1]))

static func remap_owner_roots(roots: Dictionary, row: Dictionary, maps: Dictionary, options: Dictionary = {}) -> Dictionary:
	var copy: Dictionary = _clone(roots, [], [])
	var error := {"code": ""}
	_map_value(copy, "", row, maps, options, [], error)
	if not str(error.code).is_empty(): return Runtime.fail(str(error.code))
	copy.actions._next_fire_job_token = int(options.get("next", {}).get("fire_job", copy.actions._next_fire_job_token))
	copy.coordinator._next_formation_runtime_id = int(options.get("next", {}).get("formation_runtime", copy.coordinator.get("_next_formation_runtime_id", 1)))
	copy.registry.next_token = int(options.get("next", {}).get("lease_token", copy.registry.get("next_token", 1)))
	return Runtime.ok("", {"roots": copy})

## Body projection is exact and current-runtime-only. Typed person/body IDs
## have already been admitted by the original arrival allocator.
static func remap_original_runtime_body(content: Dictionary, row: Dictionary, identity_maps: Dictionary = {}) -> Dictionary:
	var copy: Dictionary = _clone(content, [], [])
	var error := {"code": ""}
	_map_value(copy, "", row, identity_maps, {}, [], error)
	return Runtime.ok("", {"content": copy}) if str(error.code).is_empty() else Runtime.fail(str(error.code))

static func merge_owner_roots(inputs: Array, destination_owner: String) -> Dictionary:
	if inputs.is_empty(): return Runtime.fail("INVALID_REGION_PARTY_GRAPH")
	var result: Dictionary = inputs[0]
	var error := {"code": ""}
	for incoming: Dictionary in inputs.slice(1):
		for field: String in ["army_hot", "actor_hot", "plans", "reference_objects", "deliveries"]:
			_union(result[field], incoming[field], error)
		# These original timers are shared phases. A true mismatch cannot be
		# hidden by replacing an incoming accepted phase with a fresh baseline.
		for pair: Array in [["controller", ["_work_elapsed", "_settlement_elapsed", "_settlement_game_seconds", "_save_elapsed", "_family_wait"]],
				["lab", ["_action_time_remainder", "_exchange_phase", "_exchange_round", "_tactical_ai_elapsed", "_duty_ai_elapsed", "fire_action_cursor", "_region_point_pending", "_region_point_consuming", "_fire_motion_delta"]]]:
			for field: String in pair[1]:
				if result[pair[0]][field] != incoming[pair[0]][field]: error["code"] = "REGION_PARTY_CADENCE_CONFLICT"
		for field: String in ["_pending_deaths", "_supply_rout_review"]: _union(result.controller[field], incoming.controller[field], error)
		for field: String in ["_settlement_capture_sample", "_crew_handled", "_ground_crossing", "_ship_journey"]:
			if result.controller[field] != incoming.controller[field]: error["code"] = "REGION_PARTY_ENDPOINT_CONFLICT"
		_union(result.actions._jobs, incoming.actions._jobs, error)
		result.actions._results.append_array(incoming.actions._results)
		for field: String in result.work:
			if result.work[field] is Dictionary: _union(result.work[field], incoming.work[field], error)
			elif result.work[field] is Array: result.work[field].append_array(incoming.work[field])
			elif result.work[field] != incoming.work[field]: error["code"] = "REGION_PARTY_WORK_CONFLICT"
		_union(result.escort._release_walks, incoming.escort._release_walks, error)
		if result.escort._check_left != incoming.escort._check_left: error["code"] = "REGION_PARTY_CADENCE_CONFLICT"
		for field: String in ["siege_projectiles", "_siege_contact_batch", "_region_point_contacts", "_region_point_wakes"]:
			result.lab[field].append_array(incoming.lab[field])
		for field: String in ["exchange_results", "ranged_results"]:
			for key: String in incoming.lab[field]: result.lab[field][key] += incoming.lab[field][key]
		for field: String in ["exchange_count", "ranged_shots", "ranged_resolutions", "siege_shots", "siege_contacts"]:
			result.lab[field] += incoming.lab[field]
		for field: String in ["_fire_body_active", "_fire_motion"]: _union(result.lab[field], incoming.lab[field], error)
		result.lab._fire_exposure_sequence = maxi(int(result.lab._fire_exposure_sequence), int(incoming.lab._fire_exposure_sequence))
		result.lab._fire_unsaved = bool(result.lab._fire_unsaved) or bool(incoming.lab._fire_unsaved)
		for field: String in ["_siege_collect_contacts", "_fire_boundary_error", "_fire_exposure_snapshot"]:
			if result.lab[field] != incoming.lab[field]: error["code"] = "REGION_PARTY_ENDPOINT_CONFLICT"
		for cell: Variant in incoming.lab._fire_body_buckets:
			if not result.lab._fire_body_buckets.has(cell): result.lab._fire_body_buckets[cell] = []
			result.lab._fire_body_buckets[cell].append_array(incoming.lab._fire_body_buckets[cell])
		for field: String in ["_current_occupancy", "_retained_occupancy", "grid_committed_occupancy", "_member_lookup", "egress"]:
			_union(result.coordinator[field], incoming.coordinator[field], error)
		for field: String in ["_inflight_batches", "egress_retry"]: result.coordinator[field].append_array(incoming.coordinator[field])
		for field: String in ["current_logic_tick", "_occupancy_rebuild_pending"]:
			if result.coordinator[field] != incoming.coordinator[field]: error["code"] = "REGION_PARTY_MOVEMENT_CONFLICT"
		_union(result.registry.formation_slots, incoming.registry.formation_slots, error)
		var occupied := {}
		for lease: Array in result.registry.leases: occupied[lease[0]] = true
		for lease: Array in incoming.registry.leases:
			if occupied.has(lease[0]): error["code"] = "REGION_PARTY_LEASE_CONFLICT"
			result.registry.leases.append(lease)
		result.fatigue_work.append_array(incoming.fatigue_work)
		if result.duty != incoming.duty: error["code"] = "REGION_PARTY_DUTY_CONFLICT"
		if result.fire_meta != incoming.fire_meta: error["code"] = "REGION_PARTY_FIRE_BOUNDARY_CONFLICT"
	if not str(error.code).is_empty(): return Runtime.fail(str(error.code))
	result["site_id"] = destination_owner
	return Runtime.ok("", {"roots": result})

static func _union(destination: Dictionary, incoming: Dictionary, error: Dictionary) -> void:
	for key: Variant in incoming:
		if destination.has(key):
			if not is_same(destination[key], incoming[key]): error["code"] = "REGION_PARTY_OWNER_COLLISION"
		else: destination[key] = incoming[key]


static func compose_candidate(candidate: Dictionary, sources: Array, mapping: Dictionary) -> Dictionary:
	if not valid(mapping, str(candidate.content.travel_identity.namespace)): return Runtime.fail("INVALID_REGION_RUNTIME_MAPPING")
	var result := candidate.duplicate(true)
	var actors := {}
	var armies: Array = []
	var vehicles := {}
	for record: Dictionary in sources:
		var admitted := source(mapping, "travel:" + str(record.party.party_id),
			str(record.party.content.travel_identity.namespace), Marshalls.raw_to_base64(var_to_bytes(record.party)).sha256_text())
		if not admitted.ok: return admitted
		var remapped := remap_original_runtime_body(record.projected.content, admitted.source, record.get("maps", {}))
		if not remapped.ok: return remapped
		for key: String in remapped.content.get("actors", {}):
			if actors.has(key): return Runtime.fail("PARTY_ACTOR_CAPACITY")
			actors[key] = remapped.content.actors[key]
		armies.append_array(remapped.content.get("armies", []))
		for old: String in remapped.content.get("vehicles", {}):
			var key := old
			if vehicles.has(key): return Runtime.fail("PARTY_VEHICLE_COLLISION")
			var vehicle: Dictionary = remapped.content.vehicles[old]
			if vehicle.has("id"): vehicle["id"] = key
			vehicles[key] = vehicle
	result.content.actors = actors
	result.content.armies = armies
	result.content.vehicles = vehicles
	result.upkeep.original_runtime_mapping = mapping.duplicate(true)
	return Runtime.ok("", {"party": result})

static func project_transport(raw: Dictionary, projection: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	var fallback: Array = projection.get("default_offset", [0, 0])
	for flight: Dictionary in result.projectiles:
		var offset: Array = projection.get("people", {}).get(str(int(flight.source_member_id)), {}).get("offset", fallback)
		for field: String in ["origin", "position"]:
			if not flight[field] is Array or flight[field].size() != 3: return Runtime.fail("INVALID_REGION_FIRE_POSITION")
			flight[field][0] += int(offset[0]); flight[field][1] += int(offset[1])
		flight.source_cell[0] += int(offset[0]); flight.source_cell[1] += int(offset[1])
	for reservation: Dictionary in result.reservations:
		var offset: Array = projection.get("people", {}).get(str(int(reservation.person_id)), {}).get("offset", fallback)
		if reservation.get("source") is Array and reservation.source.size() == 2:
			reservation.source[0] += int(offset[0]); reservation.source[1] += int(offset[1])
		if reservation.get("target", {}).get("cell") is Array:
			reservation.target.cell[0] += int(offset[0]); reservation.target.cell[1] += int(offset[1])
	for order: Dictionary in result.orders:
		var offset: Array = projection.get("people", {}).get(str(int(order.issuer_id)), {}).get("offset", fallback)
		if order.get("target", {}).get("cell") is Array:
			order.target.cell[0] += int(offset[0]); order.target.cell[1] += int(offset[1])
	return Runtime.ok("", {"transport": result})

static func merge_fire_states(sources: Array, mapping: Dictionary, destination_owner: String) -> Dictionary:
	var result := {}
	for index: int in sources.size():
		var record: Dictionary = sources[index]
		var raw: Dictionary = record.fire
		if raw.is_empty(): continue
		# World resources/structures stay with their original physical Site.
		# Parties may retain their own empty receiver and immutable paid receipts.
		for field: String in ["units", "active", "contacts", "repair_generations", "suppression_pending",
				"collapse_warnings", "collapse_receipts", "structure_pending", "contents_remainders", "inventory_pending", "inventory_receipts"]:
			if raw.has(field) and not raw[field].is_empty(): return Runtime.fail("REGION_PARTY_SITE_FIRE_DEPENDENCY")
		if result.is_empty():
			result = raw.duplicate(true)
			result["site_id"] = destination_owner
			result["receipt_floor"] = int(raw.receipt_floor) if index == 0 else 0
			result["receipt_ids"] = {}
		for field: String in ["config_version", "step_index", "observed_action_end"]:
			if result[field] != raw[field]: return Runtime.fail("REGION_FIRE_CLOCK_CONFLICT")
		var row: Dictionary = mapping.sources[index]
		for old: String in row.maps.fire_projectile:
			if int(old) <= int(raw.receipt_floor):
				var alias := current(row, "fire_projectile", int(old))
				if alias > int(result.receipt_floor): result.receipt_ids[str(alias)] = true
		for old: Variant in raw.receipt_ids:
			var identity := current(row, "fire_projectile", int(old))
			if identity < 1: return Runtime.fail("UNMAPPED_REGION_FIRE_RECEIPT")
			if identity > int(result.receipt_floor): result.receipt_ids[str(identity)] = true
		result["dirty"] = bool(result.dirty) or bool(raw.dirty)
	return Runtime.ok("", {"state": result})


# Prior epochs are flat immutable mapping receipts. Flattening avoids a
# recursive save graph growing one level for every legitimate encounter.
static func _valid_prior(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.size() != 2 or value.get("version") != 1 or not value.get("epochs") is Array or value.epochs.size() > 100000:
		return false
	var seen := {}
	for epoch: Variant in value.epochs:
		if not epoch is Dictionary or not epoch.get("sources") is Array: return false
		for row: Variant in epoch.sources:
			if not row is Dictionary or not row.get("prior") is Dictionary or not row.prior.is_empty(): return false
		if not valid(epoch, "", -1, 1): return false
		var key := Marshalls.raw_to_base64(var_to_bytes(epoch)).sha256_text()
		if seen.has(key): return false
		seen[key] = true
	return true

static func _prior_epochs(mapping: Dictionary) -> Dictionary:
	if mapping.is_empty(): return {}
	if not valid(mapping): return {}
	var epochs: Array = []
	var seen := {}
	for row: Dictionary in mapping.sources:
		for prior: Dictionary in row.prior.get("epochs", []):
			var hash := Marshalls.raw_to_base64(var_to_bytes(prior)).sha256_text()
			if not seen.has(hash): seen[hash] = true; epochs.append(prior.duplicate(true))
	var receipt := mapping.duplicate(true)
	for row: Dictionary in receipt.sources: row.prior = {}
	var hash := Marshalls.raw_to_base64(var_to_bytes(receipt)).sha256_text()
	if not seen.has(hash): epochs.append(receipt)
	epochs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.generation) != int(b.generation): return int(a.generation) < int(b.generation)
		if str(a.destination_namespace) != str(b.destination_namespace): return str(a.destination_namespace) < str(b.destination_namespace)
		return Marshalls.raw_to_base64(var_to_bytes(a)).sha256_text() < Marshalls.raw_to_base64(var_to_bytes(b)).sha256_text())
	return {"version": 1, "epochs": epochs}
