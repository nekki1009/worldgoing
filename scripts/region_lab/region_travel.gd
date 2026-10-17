class_name RegionTravel
extends RefCounted
## Travelling party on the Region map (package R1).
##
## A party is the exact closure of original records lifted out of one Site:
## the controlled person, optionally the whole team they captain, the team's
## carts/wagons, carried items, team/personal meal ledgers and fire command rows.
## While travelling these records live ONLY in the party document referenced by
## the slot's commit record; no Site holds them, so nothing is duplicated or lost.
## The same format is meant for NPC parties (R3): `controller` names the owner.
##
## The original feeding and fatigue owners advance on the same Slot interval.

const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")

const VERSION := 2
const IDENTITY_VERSION := 1
const MAX_IDENTITY_SEQUENCE := 9007199254740991 # Exact integer JSON range.
const IDENTITY_TYPES := ["person", "team", "vehicle", "item", "loot", "nation", "corps", "family"]
const ID_COUNTERS := {"person": "next_person_id", "team": "army_next_team", "vehicle": "next_vehicle", "item": "next_item", "loot": "next_loot"}
const PATIENT_SEATS := {"cart": 1, "wagon": 2}
const PATIENT_CAPACITY := 50
const EPS := 0.0000001
const KIND := "region_travel"
## Region map rate: one real second is ten game minutes at speed ×1.
const GAME_SECONDS_PER_REAL := 600.0
## Travel time is published as ordinary peace-time fire-journal steps at the
## fastest existing scale, so cold Sites replay it with their original step.
const STEP_ACTION_SECONDS := 1.0 / 30.0
const STEP_SCALE := 4.0
const WALK_MPS := 4000.0 / 3600.0
const VEHICLE_MPS := {"cart": 3500.0 / 3600.0, "wagon": 3000.0 / 3600.0}
const CONTENT_DICTS := ["actors", "vehicles", "team_supply", "person_supply", "item_records",
	"item_definitions", "equipment_nations", "corps", "ground_loot"]

static func fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}

static func stable_key(reference: Dictionary) -> String:
	var lineage: Variant = reference.get("lineage")
	return JSON.stringify([reference.get("type"), reference.get("namespace"), int(lineage) if _identity_integer(lineage, 1, MAX_IDENTITY_SEQUENCE) else lineage])

static func _identity_integer(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= upper and float(value) == floorf(float(value))

static func validate_identity(value: Variant) -> bool:
	if not value is Dictionary or value.size() not in [4, 5] or not _identity_integer(value.get("version"), IDENTITY_VERSION, IDENTITY_VERSION) \
			or not value.get("namespace") is String or str(value.namespace).is_empty() \
			or not _identity_integer(value.get("next_sequence"), 1, MAX_IDENTITY_SEQUENCE) or not value.get("refs") is Dictionary:
		return false
	for field: Variant in value:
		if field not in ["version", "namespace", "next_sequence", "refs", "family_members"]: return false
	var seen := {}
	for kind: Variant in value.refs:
		if kind not in IDENTITY_TYPES or not value.refs[kind] is Dictionary: return false
		for local: Variant in value.refs[kind]:
			var reference: Variant = value.refs[kind][local]
			if not local is String or str(local).is_empty() or not reference is Dictionary or reference.size() != 3 \
					or reference.get("type") != kind or not reference.get("namespace") is String \
					or str(reference.namespace).is_empty() or not _identity_integer(reference.get("lineage"), 1, MAX_IDENTITY_SEQUENCE):
				return false
			var key := stable_key(reference)
			if seen.has(key): return false
			seen[key] = true
	if value.has("family_members"):
		if not value.family_members is Dictionary: return false
		var family_seen := {}
		var family_locations := {}
		for member: Variant in value.family_members:
			var reference: Variant = value.family_members[member]
			var parsed: Variant = JSON.parse_string(str(member))
			if not member is String or not parsed is Array or parsed.size() != 2 or not parsed[0] is String \
					or str(parsed[0]).is_empty() or not _identity_integer(parsed[1], 1, 2147483647) or int(parsed[1]) == 1000000000 \
					or not reference is Dictionary or reference.size() != 3 \
					or reference.get("type") != "person" or not reference.get("namespace") is String or str(reference.namespace).is_empty() \
					or not _identity_integer(reference.get("lineage"), 1, MAX_IDENTITY_SEQUENCE): return false
			var location := JSON.stringify([str(parsed[0]), int(parsed[1])])
			if family_locations.has(location): return false
			family_locations[location] = true
			var key := stable_key(reference)
			if family_seen.has(key): return false
			family_seen[key] = true
	return true

## Strict admission first, then canonical int metadata. Never repair malformed
## present identity, synthesize missing refs, or touch the original body here.
static func normalize_identity(value: Variant) -> Dictionary:
	if not validate_identity(value): return {}
	var identity: Dictionary = value.duplicate(true)
	identity.version = int(identity.version)
	identity.next_sequence = int(identity.next_sequence)
	for kind: String in identity.refs:
		for reference: Dictionary in identity.refs[kind].values(): reference.lineage = int(reference.lineage)
	if identity.has("family_members"):
		var members := {}
		for key: String in identity.family_members:
			var parsed: Array = JSON.parse_string(key)
			var reference: Dictionary = identity.family_members[key]
			reference.lineage = int(reference.lineage)
			members[JSON.stringify([str(parsed[0]), int(parsed[1])])] = reference
		identity.family_members = members
	return identity

static func _identity_ids(state: Dictionary) -> Dictionary:
	var ids := {"person": {}, "team": {}, "vehicle": {}, "item": {}, "loot": {}, "nation": {}, "corps": {}, "family": {}}
	for actor: Dictionary in state.get("actors", {}).values(): ids.person[str(int(actor.person_id))] = true
	for army: Dictionary in state.get("armies", []):
		ids.team[str(int(army.team_id))] = true
		for row: Dictionary in army.get("units", []): ids.person[str(int(row.person_id))] = true
	for key: String in state.get("organization_refs", {}).get("remote_people", {}): ids.person[key] = true
	for key: String in state.get("organization_refs", {}).get("remote_teams", {}): ids.team[key] = true
	for pair: Array in [["vehicle", "vehicles"], ["item", "item_records"], ["loot", "ground_loot"], ["nation", "equipment_nations"], ["corps", "corps"]]:
		for key: Variant in state.get(pair[1], {}): ids[pair[0]][str(key)] = true
	if state.has("family"): ids.family["controlled"] = true
	return ids

## Detached original-owner metadata only; bodies/items remain in their old fields.
## The Slot supplies its world/site creation namespace, never a generation number.
static func prepare_identity(state: Dictionary, identity_namespace: String = "") -> Dictionary:
	var result := state.duplicate(true)
	var identity: Dictionary = result.get("travel_identity", {})
	if identity.is_empty():
		if identity_namespace.is_empty(): identity_namespace = "site:" + str(result.get("id", ""))
		if identity_namespace == "site:": return fail("INVALID_IDENTITY", "缺少原 Site 建立 namespace")
		identity = {"version": IDENTITY_VERSION, "namespace": identity_namespace, "next_sequence": 1, "refs": {}}
	else:
		identity = normalize_identity(identity)
		if identity.is_empty(): return fail("INVALID_IDENTITY", "原資產身分索引無法驗證")
	var ids := _identity_ids(result)
	for kind: String in IDENTITY_TYPES:
		if not identity.refs.has(kind): identity.refs[kind] = {}
		var locals: Array = ids[kind].keys()
		locals.sort()
		for local: String in locals:
			if identity.refs[kind].has(local): continue
			if int(identity.next_sequence) >= MAX_IDENTITY_SEQUENCE: return fail("IDENTITY_ALLOCATOR_EXHAUSTED", "原 identity sequence 已到精確JSON整數邊界")
			var family_id := str(result.get("family", {}).get("family_id", "")) if kind == "family" else ""
			identity.refs[kind][local] = {"type": kind, "namespace": "family:" + family_id if not family_id.is_empty() else str(identity.namespace), "lineage": 1 if not family_id.is_empty() else int(identity.next_sequence)}
			identity.next_sequence = int(identity.next_sequence) + 1
	result.travel_identity = identity
	if not identity.has("family_members"): identity.family_members = {}
	for member: Dictionary in result.get("family", {}).get("members", []):
		var key := JSON.stringify([str(member.site_id), int(member.person_id)])
		if str(member.site_id) == str(result.get("id", "")) and identity.refs.person.has(str(int(member.person_id))): identity.family_members[key] = identity.refs.person[str(int(member.person_id))].duplicate(true)
	return {"ok": true, "state": result}

static func _retain_identity(state: Dictionary) -> void:
	if not state.has("travel_identity"): return
	var ids := _identity_ids(state)
	for kind: String in IDENTITY_TYPES:
		for local: String in state.travel_identity.refs.get(kind, {}).keys():
			if not ids[kind].has(local): state.travel_identity.refs[kind].erase(local)
	var members := {}
	for member: Dictionary in state.get("family", {}).get("members", state.get("family_refs", {}).get("members", [])): members[JSON.stringify([str(member.site_id), int(member.person_id)])] = true
	for key: String in state.travel_identity.get("family_members", {}).keys():
		if not members.has(key): state.travel_identity.family_members.erase(key)

static func _mapped(value: Variant, kind: String, maps: Dictionary) -> Variant:
	var mapped: Variant = maps.get(kind, {}).get(str(value), value)
	return int(mapped) if value is int else str(mapped)

static func _remap_holder(holder: String, maps: Dictionary) -> String:
	var split := holder.find(":")
	if split < 0: return holder
	var kind := holder.substr(0, split)
	var type := "loot" if kind == "ground" else kind
	return kind + ":" + str(_mapped(holder.substr(split + 1), type, maps))

## Remap only current semantic references. Receipts/episodes keep stable history.
static func _remap_current(value: Variant, maps: Dictionary, field: String = "") -> Variant:
	if field in ["receipts", "inventory_receipts", "history", "episodes", "completed_events", "paid_receipts", "hit_receipts", "travel_identity", "source_token", "family", "family_refs", "organization_refs", "original_owner", "technology_construction"]:
		return value
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _mapped(value[key], "item", maps) if field == "equipped" else _remap_current(value[key], maps, str(key))
		return result
	if value is Array:
		var result: Array = []
		var type := "person" if field in ["person_ids", "ids", "captives", "carriers", "patient_ids", "members"] else ("team" if field in ["team_ids", "teams"] else ("item" if field == "item_ids" else ""))
		for member: Variant in value:
			var whole_member: bool = member is float and is_finite(member) and member == floorf(member)
			result.append(_mapped(int(member) if whole_member else member, type, maps) if not type.is_empty() and (member is int or member is String or whole_member) else _remap_current(member, maps, field))
		return result
	# A body read back from a saved Site carries JSON numbers: a whole-number
	# float id maps as the int it is. Every non-id field keeps its own value.
	var whole: bool = value is float and is_finite(value) and value == floorf(value)
	if not (value is int or value is String or whole): return value
	var original_value: Variant = value
	if whole: value = int(value)
	if field in ["person_id", "operator_id", "commander_person_id", "leader_person_id", "controlled_person_id", "captor_id", "guard_id", "patient_id", "carrier_id", "military_head", "requester_id", "executor_id", "head_person_id", "training_requester", "borrower_id", "rider_id"]:
		return _mapped(value, "person", maps)
	if field == "holder": return _mapped(value, "person", maps) if value is int else _remap_holder(str(value), maps)
	if field in ["team_id", "group"]:
		if field == "group" and int(value) < 0: return -int(_mapped(-int(value), "person", maps))
		return _mapped(value, "team", maps)
	if field in ["vehicle_id", "embarked_vehicle_id", "bound_vehicle_id", "ship_vehicle_id"]: return _mapped(value, "vehicle", maps)
	if field == "remains_id": return _mapped(value, "loot", maps)
	if field in ["item_id", "equipment_item_id"]: return _mapped(value, "item", maps)
	if field in ["nation_id", "equipment_nation_id"]: return _mapped(value, "nation", maps)
	if field == "corps_id": return _mapped(value, "corps", maps)
	return original_value

static func _remap_content(content: Dictionary, maps: Dictionary) -> Dictionary:
	var result: Dictionary = _remap_current(content.duplicate(true), maps)
	for pair: Array in [["vehicles", "vehicle"], ["item_records", "item"], ["ground_loot", "loot"], ["team_supply", "team"], ["person_supply", "person"], ["equipment_nations", "nation"], ["corps", "corps"]]:
		var rows := {}
		for old: Variant in result.get(pair[0], {}):
			var key := str(_mapped(old, pair[1], maps))
			var record: Dictionary = result[pair[0]][old]
			if pair[0] in ["vehicles", "ground_loot"] and record.has("id"): record.id = key
			rows[key] = record
		result[pair[0]] = rows
	for vehicle: Dictionary in result.get("vehicles", {}).values():
		for slot: Variant in vehicle.get("crew_slots", {}): vehicle.crew_slots[slot] = _mapped(vehicle.crew_slots[slot], "person", maps)
	for supply: Dictionary in result.get("team_supply", {}).values():
		var locations := {}
		for old: String in supply.get("locations", {}): locations[_remap_holder(old, maps)] = supply.locations[old]
		if supply.has("locations"): supply.locations = locations
		if supply.has("life_checkpoint"):
			var checkpoint := {}
			for old: Variant in supply.life_checkpoint: checkpoint[str(_mapped(old, "person", maps))] = supply.life_checkpoint[old]
			supply.life_checkpoint = checkpoint
	for army: Dictionary in result.get("armies", []):
		if not army.get("player_member", {}).is_empty(): army.player_member.id = int(_mapped(army.player_member.id, "person", maps))
	for order: Dictionary in result.get("fire_orders", []):
		for pair: Array in order.get("release_ids", []):
			if pair.size() == 2: pair[0] = int(_mapped(pair[0], "person", maps))
	for body: Dictionary in _body_records(result).values():
		for holder: Dictionary in [body.get("holder", {}), body.get("item_holder", {})]:
			for slot: Variant in holder.get("equipped", {}): holder.equipped[slot] = _mapped(holder.equipped[slot], "item", maps)
	if result.has("travel_identity"):
		for kind: String in IDENTITY_TYPES:
			var refs := {}
			for old: String in result.travel_identity.refs.get(kind, {}): refs[str(_mapped(old, kind, maps))] = result.travel_identity.refs[kind][old]
			result.travel_identity.refs[kind] = refs
	if not _faction_nations_remapped(content, result, maps): return {}
	return result

static func _faction_nations_remapped(content: Dictionary, result: Dictionary, maps: Dictionary) -> bool:
	# Binding is a typed identity; a missing mapped nation/ref is a refusal.
	for old: String in content.get("equipment_nations", {}):
		var nation: Dictionary = content.equipment_nations[old]
		if not nation.has("faction_id"): continue
		if not validate_identity(content.get("travel_identity")): return false
		var local: String = str(_mapped(old, "nation", maps))
		if result.get("equipment_nations", {}).get(local, {}).get("faction_id") != nation.faction_id or result.get("travel_identity", {}).get("refs", {}).get("nation", {}).get(local) != content.travel_identity.refs.nation.get(old): return false
	return true

## Reservation is deterministic and returned to the Slot for the same commit.
static func validate_arrival_mapping(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 5 or int(value.get("version", 0)) != 1 \
			or not value.get("token") is String or str(value.token).is_empty() \
			or not value.get("destination_namespace") is String or str(value.destination_namespace).is_empty() \
			or not (value.get("generation") is int or value.get("generation") is float) \
			or not is_finite(float(value.generation)) or float(value.generation) < 0.0 or float(value.generation) != floorf(float(value.generation)) \
			or not value.get("maps") is Dictionary or value.maps.size() != IDENTITY_TYPES.size(): return false
	for kind: String in IDENTITY_TYPES:
		if not value.maps.get(kind) is Dictionary: return false
		var targets := {}
		for source_id: Variant in value.maps[kind]:
			var target: Variant = value.maps[kind][source_id]
			if not source_id is String or str(source_id).is_empty() or not target is String or str(target).is_empty() or targets.has(target): return false
			if kind in ID_COUNTERS and (not source_id.is_valid_int() or str(int(source_id)) != source_id or int(source_id) <= 0 \
					or not target.is_valid_int() or str(int(target)) != target or int(target) <= 0): return false
			targets[target] = true
	return true

## A family identity arriving with a party is reserved at the destination: the
## destination counter never reissues its lineage id (max merge, like the other counters).
static func merge_lineage_counter(destination: Dictionary, incoming: Dictionary) -> void:
	var family: Variant = incoming.get("family", {})
	if not family is Dictionary or not family.has("lineage_id"): return
	destination.next_lineage = maxi(int(destination.get("next_lineage", 1)), int(family.lineage_id) + 1)

static func prepare_arrival(destination_state: Dictionary, party: Dictionary, generation: int = 0) -> Dictionary:
	var prepared := prepare_identity(destination_state)
	if not prepared.ok: return prepared
	var destination: Dictionary = prepared.state
	# A fresh/marine destination may not hold item storage yet. Create it before
	# any ID counter (next_item/next_loot) is reserved on the arrival candidate;
	# otherwise the counters exist without item_storage_version and the first
	# save refuses the Site as CORRUPT_SAVE. Same non-failing call as insert():
	# a legacy body that already has item fields is left exactly as before.
	Runtime.initialize_item_storage(destination)
	var incoming: Dictionary = party.get("content", {})
	if not validate_identity(incoming.get("travel_identity")): return fail("INVALID_IDENTITY", "旅隊缺少原資產穩定引用")
	merge_lineage_counter(destination, incoming)
	var maps := {}
	var operation_maps := {}
	var prior: Dictionary = party.get("arrival_mapping", {})
	if not prior.is_empty() and not validate_arrival_mapping(prior): return fail("INVALID_MAPPING", "到站原預留映射不是必要單射 schema")
	if not prior.is_empty() and (prior.get("destination_namespace") != destination.travel_identity.namespace or prior.get("token") != party.get("party_id")):
		return fail("STALE_MAPPING", "到站身分映射不屬此目標／旅隊")
	for kind: String in IDENTITY_TYPES:
		maps[kind] = {}
		operation_maps[kind] = {}
		if kind == "family": continue
		var used: Dictionary = destination.travel_identity.refs[kind].duplicate(true)
		var originals: Dictionary = incoming.travel_identity.refs.get(kind, {})
		var locals := originals.keys()
		locals.sort()
		var prior_map: Dictionary = prior.get("maps", {}).get(kind, {})
		var inverse := {}
		for old: String in prior_map: inverse[str(prior_map[old])] = old
		var mapped_input: bool = not prior_map.is_empty() and locals.all(func(local: String) -> bool: return inverse.has(local)) \
			and not locals.all(func(local: String) -> bool: return prior_map.has(local))
		for local: String in locals:
			var reference: Dictionary = originals[local]
			var returning_local := ""
			for existing_local: String in used:
				if stable_key(used[existing_local]) != stable_key(reference): continue
				var remote_field := "remote_people" if kind == "person" else "remote_teams" if kind == "team" else ""
				if remote_field.is_empty() or not destination.get("organization_refs", {}).get(remote_field, {}).has(existing_local):
					return fail("DUPLICATE_OWNER", "同一原資產已由目的地持有")
				# A remote membership reserves its former number; it owns no body.
				if kind == "person" and _body_records(destination).has(int(existing_local)):
					return fail("DUPLICATE_OWNER", "遠端引用與真本地身體不能重複")
				if kind == "team":
					for army: Dictionary in destination.get("armies", []):
						if int(army.team_id) == int(existing_local): return fail("DUPLICATE_OWNER", "遠端引用與真本地隊容器不能重複")
				returning_local = existing_local
			var original_local := str(inverse[local]) if mapped_input else local
			var wanted := returning_local if not returning_local.is_empty() else str(prior_map.get(original_local, original_local))
			if not returning_local.is_empty() and not prior.is_empty() and str(prior_map.get(original_local, "")) != wanted:
				return fail("STALE_MAPPING", "原返鄉預留與原遠端登錄不同")
			if used.has(wanted) and returning_local.is_empty():
				if not prior.is_empty(): return fail("STALE_MAPPING", "預留到站編號已被其他原資產占用")
				var next := maxi(1, int(destination.get(ID_COUNTERS.get(kind, ""), 1)))
				while used.has(str(next)) or originals.has(str(next)): next += 1
				wanted = str(next)
			if not wanted.is_valid_int() and kind in ID_COUNTERS: return fail("INVALID_IDENTITY", "原編號必須為整數")
			if wanted.is_valid_int() and int(wanted) >= (999999 if kind == "team" else 2147483647): return fail("ID_LIMIT", "目的地原編號已達上限")
			maps[kind][original_local] = wanted
			operation_maps[kind][local] = wanted
			used[wanted] = reference.duplicate(true)
			if ID_COUNTERS.has(kind): destination[ID_COUNTERS[kind]] = maxi(int(destination.get(ID_COUNTERS[kind], 1)), int(wanted) + 1)
		# Only the prepared candidate receives the reserved owner projection.
		destination.travel_identity.refs[kind] = used
	var remapped := party.duplicate(true)
	remapped.content = _remap_content(incoming, operation_maps)
	remapped.person_ids = []
	for person: Variant in party.get("person_ids", []): remapped.person_ids.append(int(_mapped(person, "person", operation_maps)))
	remapped.team_ids = []
	for team: Variant in party.get("team_ids", []): remapped.team_ids.append(int(_mapped(team, "team", operation_maps)))
	remapped.vehicle_ids = []
	for vehicle: Variant in party.get("vehicle_ids", []): remapped.vehicle_ids.append(str(_mapped(vehicle, "vehicle", operation_maps)))
	remapped.leader_person_id = int(_mapped(party.leader_person_id, "person", operation_maps))
	remapped.arrival_mapping = {"version": 1, "token": str(party.party_id), "destination_namespace": str(destination.travel_identity.namespace), "generation": generation, "maps": maps}
	return {"ok": true, "state": destination, "party": remapped, "mapping": remapped.arrival_mapping}

## The original player party remains the sole travelling owner. This detached
## operation reserves through the same typed arrival allocator as a Site; it
## neither places bodies nor retires the incoming party. Only the Slot's joint
## marker may publish the returned body closure and source retirement.
static func join_party(destination_party: Dictionary, incoming_party: Dictionary, generation: int = 0) -> Dictionary:
	var destination_token := str(destination_party.get("party_id", ""))
	var incoming_token := str(incoming_party.get("party_id", ""))
	if destination_token.is_empty() or incoming_token.is_empty() or destination_token == incoming_token \
			or destination_party.get("controller") not in ["player", "npc"] or incoming_party.get("controller") != "npc":
		return fail("INVALID_PARTY_JOIN", "須是兩個不同的原完整旅隊")
	if destination_party.get("controller") == "npc":
		for original: Dictionary in [destination_party, incoming_party]:
			if original.get("mode") != "sea" or int(original.get("content", {}).get("controlled_person_id", -1)) != -1 or not original.get("content", {}).get("actors", {}).is_empty():
				return fail("NPC_PARTY_AUTHORITY", "原 NPC 海上交接不能攜帶玩家或 Actor 控制")
	for original: Dictionary in [destination_party, incoming_party]:
		if not original.get("content") is Dictionary or not validate_identity(original.content.get("travel_identity")) \
				or not original.get("upkeep") is Dictionary or not is_finite(float(original.upkeep.get("at", NAN))):
			return fail("INVALID_PARTY_JOIN", "原旅隊身分或共同端點非法")
		var people := _body_records(original.content)
		var bodies := {}
		for identity: Variant in original.get("person_ids", []):
			if not identity is int or int(identity) <= 0 or bodies.has(identity) or not people.has(identity): return fail("PARTY_BODY_CLOSURE", "原人物閉包不唯一")
			bodies[identity] = true
		if bodies.size() != people.size(): return fail("PARTY_BODY_CLOSURE", "原人物閉包遺漏身體")
		var teams := {}
		for army: Dictionary in original.content.get("armies", []):
			if teams.has(int(army.team_id)): return fail("PARTY_BODY_CLOSURE", "原隊容器不唯一")
			teams[int(army.team_id)] = true
		if teams.size() != original.get("team_ids", []).size(): return fail("PARTY_BODY_CLOSURE", "原隊容器閉包不完整")
		for identity: Variant in original.get("team_ids", []):
			if not teams.has(int(identity)): return fail("PARTY_BODY_CLOSURE", "原隊容器閉包不完整")
		if original.content.get("vehicles", {}).size() != original.get("vehicle_ids", []).size(): return fail("PARTY_BODY_CLOSURE", "原車船閉包不完整")
		for identity: Variant in original.get("vehicle_ids", []):
			if not original.content.get("vehicles", {}).has(str(identity)): return fail("PARTY_BODY_CLOSURE", "原車船閉包不完整")
	if absf(float(destination_party.upkeep.at) - float(incoming_party.upkeep.at)) > EPS \
			or absf(float(destination_party.upkeep.get("owner_action_seconds", 0.0)) - float(incoming_party.upkeep.get("owner_action_seconds", 0.0))) > EPS:
		return fail("TIME_MISMATCH", "原旅隊未到同一 GAME／ACTION 端點")
	if destination_party.get("upkeep", {}).get("joined_sources", {}).has(incoming_token): return fail("ALREADY_JOINED", "原 NPC 旅隊只退休一次")
	var state: Dictionary = destination_party.content.duplicate(true)
	state.id = "travel:" + destination_token
	for field: String in ID_COUNTERS.values(): state[field] = int(state.get("counters", {}).get(field, 1))
	var prepared := prepare_arrival(state, incoming_party, generation)
	if not prepared.ok: return prepared
	var destination: Dictionary = prepared.state
	var incoming: Dictionary = prepared.party.content.duplicate(true)
	# Original Actor slots have fixed consumers. A team join may not overwrite
	# an existing player/NPC Actor or invent an additional Actor authority.
	for key: String in incoming.get("actors", {}):
		if destination.get("actors", {}).has(key): return fail("ACTOR_CONTAINER_OPEN", "原 Actor 容器仍有持有人")
	for field: String in CONTENT_DICTS:
		if not destination.has(field): destination[field] = {}
		for key: String in incoming.get(field, {}):
			if destination[field].has(key):
				if field == "item_definitions" and destination[field][key] == incoming[field][key]: continue
				return fail("DUPLICATE_OWNER", "原旅隊紀錄仍有持有人：" + field)
			destination[field][key] = incoming[field][key]
	for army: Dictionary in incoming.get("armies", []): destination.armies.append(army)
	for field: String in ["fire_orders", "fire_member_cursor"]:
		if not destination.has(field): destination[field] = []
		for record: Variant in incoming.get(field, []):
			var value: Variant = record.duplicate(true)
			if field == "fire_member_cursor" and value is Array and value.size() == 2:
				value[0] = -int(_mapped(-int(value[0]), "person", prepared.mapping.maps)) if int(value[0]) < 0 else int(_mapped(value[0], "team", prepared.mapping.maps))
			destination[field].append(value)
	if not incoming.get("fire_template", {}).is_empty() and destination.get("fire_template", {}).is_empty(): destination.fire_template = incoming.fire_template.duplicate(true)
	var organization := SiteEquipmentOrders.prepare_region_arrival(destination, incoming_party.content.get("organization_refs", SiteEquipmentOrders._portable_empty()), incoming_party.content.travel_identity, prepared.mapping)
	if not organization.ok: return organization
	destination.organization_refs = organization.organization_refs
	# Foreign family membership and holder receipts stay in their original
	# archive. The joint Slot guard updates only their current owner references.
	var family_refs: Dictionary = incoming.get("family_refs", {}).duplicate(true)
	if incoming.has("family"): return fail("NPC_FAMILY_AUTHORITY", "NPC 交接不能帶入另一份原受控家族 holder")
	for field: String in ID_COUNTERS.values():
		destination.counters[field] = int(destination[field])
		destination.erase(field)
	destination.erase("id")
	destination.army_trial_active = not destination.armies.is_empty()
	_retain_identity(destination)
	var joined := destination_party.duplicate(true)
	joined.content = destination
	for field: String in ["person_ids", "team_ids", "vehicle_ids"]:
		for identity: Variant in prepared.party[field]: joined[field].append(identity)
		joined[field].sort()
	var events: Array = []
	for event: Dictionary in incoming_party.upkeep.get("events", []):
		# The accepted Slot event id/sequence/epoch is immutable. The consumer
		# gets only this original current-body mapping, never a new event id.
		var mapped_event: Dictionary = event.duplicate(true)
		if mapped_event.has("person_id"): mapped_event.person_id = int(_mapped(mapped_event.person_id, "person", prepared.mapping.maps))
		events.append(mapped_event)
	for field: String in ["original_deaths", "carriers"]:
		if not joined.upkeep.has(field): joined.upkeep[field] = {}
		for old: String in incoming_party.upkeep.get(field, {}):
			var local := str(_mapped(old, "person", prepared.mapping.maps))
			if joined.upkeep[field].has(local): return fail("DUPLICATE_OWNER", "原旅隊生命／搬運紀錄重複")
			joined.upkeep[field][local] = _remap_current(incoming_party.upkeep[field][old], prepared.mapping.maps, "carriers" if field == "carriers" else "")
	if not joined.upkeep.has("joined_sources"): joined.upkeep.joined_sources = {}
	joined.upkeep.joined_sources[incoming_token] = {"version": 1, "mapping": prepared.mapping.duplicate(true)}
	joined.speed_mps = party_speed(destination)
	var patients := validate_patients(destination)
	if not patients.ok: return patients
	if not SiteEquipmentOrders.valid_organization_refs(destination): return fail("INVALID_ORGANIZATION_TRANSFER", "原跨域組織引用未形成真合併閉包")
	return {"ok": true, "party": joined, "incoming": prepared.party, "mapping": prepared.mapping,
		"incoming_events": events, "incoming_family_refs": family_refs}

## A live party uses one contiguous view of the original selected geometry.
## These helpers translate coordinates only; refs, clocks, paid work and life
## remain in the same original records. All inputs stay unchanged.
const FRAME_GRID_POINTS := ["cell", "slot", "destination", "movement_from", "reference", "origin", "goal",
	"requested_goal", "resolved_anchor", "ingress_cell", "centered_platform_handoff", "approach_last_bottleneck_cell",
	"source_cell", "target_cell", "from_cell", "to_cell", "operator", "anchor", "waypoint"]
const FRAME_GRID_LISTS := ["macro_path", "platform_slots", "approach_queue_slots", "platform_footprint", "ingress_path",
	"queue_hold_cross_section", "ingress_buffer_cells", "ingress_staging_slots", "path", "route", "cells"]
const FRAME_GRID_VALUES := ["member_slot_map", "combat_absent_slots", "_combat_absent_slots", "member_recovery_vacated_cell",
	"member_transit_slots", "pre_route_staging_slots", "member_paths", "member_checkpoint_cell", "member_pending_from_cell",
	"member_pending_to_cell", "member_route_target", "member_entry_waypoint", "member_vacancy_chain_target",
	"member_vacancy_chain_start_cell", "member_queue_egress_waypoint", "start_cells", "targets", "formation_slots"]
const FRAME_GRID_KEYS := ["_current_occupancy", "_retained_occupancy", "grid_committed_occupancy", "slot_owners",
	"slot_owner_map", "slot_tactical_roles", "slot_lease_timers", "slot_lease_owner_map", "slot_lease_role_map",
	"slot_lease_queue_index_map", "fire_suspended_slots"]
const FRAME_PIXELS := ["position", "ground", "end_ground", "screen_origin", "screen_goal", "_attack_aim_point"]
const FRAME_HISTORY := ["family", "family_refs", "travel_identity", "receipts", "history", "original_owner",
	"appearance", "ship_deck_position", "facing", "final_facing", "velocity", "ground_velocity", "direction",
	"_attack_offset", "_stance_offset", "cargo", "item_state", "rng", "rng_state", "rule", "technology"]

static func _frame_point(value: Variant, offset: Vector2i, pixels: bool = false, sentinel: bool = true) -> Variant:
	var delta := Vector2(offset) * (float(TerrainRenderer.CELL_PIXELS) if pixels else 1.0)
	if value is Vector2i:
		return value if sentinel and value == Vector2i(-1, -1) else value + offset
	if value is Vector2:
		return value if sentinel and value == Vector2(-1, -1) else value + delta
	if value is Vector3: return value + Vector3(delta.x, delta.y, 0.0)
	if value is Array and value.size() == 2 and (value[0] is int or value[0] is float):
		if not (value[1] is int or value[1] is float): return value
		if sentinel and not pixels and value == [-1, -1]: return value
		return [value[0] + (int(delta.x) if value[0] is int else delta.x), value[1] + (int(delta.y) if value[1] is int else delta.y)]
	return value

static func _frame_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value[0] is int and value[1] is int

static func _frame_clone(value: Variant, originals: Array, copies: Array) -> Variant:
	if value is PackedVector2Array:
		for index: int in originals.size():
			if is_same(originals[index], value): return copies[index]
		var polygon: PackedVector2Array = value.duplicate()
		originals.append(value); copies.append(polygon)
		return polygon
	if not (value is Dictionary or value is Array): return value
	for index: int in originals.size():
		if is_same(originals[index], value): return copies[index]
	var copy: Variant = {} if value is Dictionary else value.duplicate(false)
	if copy is Array: copy.clear()
	originals.append(value)
	copies.append(copy)
	if value is Dictionary:
		for key: Variant in value: copy[key] = _frame_clone(value[key], originals, copies)
	else:
		for item: Variant in value: copy.append(_frame_clone(item, originals, copies))
	return copy

static func _frame_offset(projection: Dictionary, kind: String, identity: Variant, fallback: Vector2i) -> Vector2i:
	var record: Dictionary = projection.get(kind, {}).get(str(identity), {})
	return Vector2i(int(record.offset[0]), int(record.offset[1])) if _frame_pair(record.get("offset")) else fallback

static func _frame_walk(value: Variant, offset: Vector2i, projection: Dictionary, field: String,
		seen: Array, offsets: Array, error: Dictionary, pixel_motion: bool = false) -> Variant:
	if field in FRAME_HISTORY: return value
	if field == "_frame_pixel_polygon" and value is PackedVector2Array:
		for index: int in seen.size():
			var memo: Variant = seen[index]
			if memo is Dictionary and memo.size() == 2 and memo.get("_frame_packed_polygon") is PackedVector2Array \
				and is_same(memo._frame_packed_polygon, value):
				if offsets[index] != offset: error.code = "AMBIGUOUS_FRAME_ALIAS"
				return memo.translated
		var translated: PackedVector2Array = value.duplicate()
		for vertex: int in translated.size(): translated[vertex] = _frame_point(translated[vertex], offset, true, false)
		seen.append({"_frame_packed_polygon": value, "translated": translated}); offsets.append(offset)
		return translated
	if field == "_frame_pixel_polygon" and value is Array:
		for index: int in seen.size():
			if is_same(seen[index], value):
				if offsets[index] != offset: error.code = "AMBIGUOUS_FRAME_ALIAS"
				return value
		seen.append(value); offsets.append(offset)
		for vertex: int in value.size(): value[vertex] = _frame_point(value[vertex], offset, true, false)
		return value
	if field in ["bounds", "anchor_bounds", "sweep_bounds"] and value is Rect2:
		return Rect2(value.position + Vector2(offset) * TerrainRenderer.CELL_PIXELS, value.size)
	if field in FRAME_PIXELS or field in ["start", "from", "to", "origin", "goal", "anchor"] and pixel_motion:
		return _frame_point(value, offset, true, false)
	if field in FRAME_GRID_POINTS or field in ["from", "to"]:
		if value is int and field == "cell":
			var at := Vector2i(value % int(projection.source_width), value / int(projection.source_width)) + offset
			return at.y * int(projection.size[0]) + at.x
		var translated: Variant = _frame_point(value, offset)
		if not (value is Dictionary) and not is_same(value, translated): return translated
	if not (value is Dictionary or value is Array):
		if field in FRAME_GRID_LISTS and value is PackedVector2Array:
			var points := PackedVector2Array()
			for point: Vector2 in value: points.append(point + Vector2(offset))
			return points
		return value
	for index: int in seen.size():
		if is_same(seen[index], value):
			if offsets[index] != offset: error.code = "AMBIGUOUS_FRAME_ALIAS"
			return value
	seen.append(value)
	offsets.append(offset)
	if value is Array:
		for index: int in value.size():
			if field in FRAME_GRID_LISTS: value[index] = _frame_point(value[index], offset)
			elif field in ["previous", "previous_weapon", "body", "shield", "bodies", "shields", "current_weapon"] and (value[index] is Array or value[index] is PackedVector2Array):
				value[index] = _frame_walk(value[index], offset, projection, "_frame_pixel_polygon", seen, offsets, error, true)
			elif field == "leases" and value[index] is Array and value[index].size() == 2:
				var local := offset
				if value[index][1] is Array and value[index][1].size() == 6: local = _frame_offset(projection, "people", value[index][1][2], offset)
				value[index][0] = _frame_point(value[index][0], local)
				if value[index][1] is Array and value[index][1].size() == 6: value[index][1][4] = _frame_point(value[index][1][4], local)
			else: value[index] = _frame_walk(value[index], offset, projection, "", seen, offsets, error, pixel_motion)
		return value
	var entries: Dictionary = value.duplicate(false)
	if field in FRAME_GRID_KEYS or field == "reference_objects": value.clear()
	for key: Variant in entries:
		var local := offset
		if field in ["army_hot", "plans"]: local = _frame_offset(projection, "teams", key, offset)
		elif field in ["actor_hot", "_fire_motion", "_member_lookup"]: local = _frame_offset(projection, "people", key, offset)
		elif field == "reference_objects" and str(key).begins_with("team:"): local = _frame_offset(projection, "teams", str(key).split(":")[1], offset)
		if entries.get("person_id") is int: local = _frame_offset(projection, "people", entries.person_id, local)
		if field in ["_current_occupancy", "_retained_occupancy", "grid_committed_occupancy", "slot_owner_map", "slot_lease_owner_map"] and entries[key] is int:
			local = _frame_offset(projection, "people", entries[key], local)
		if field == "formation_slots": local = _frame_offset(projection, "runtime_offsets", key, local)
		if field == "values" and entries.get("member_id") is int: local = _frame_offset(projection, "people", entries.member_id, local)
		var next: Variant = entries[key]
		if field == "navigation" and str(key) == "target":
			# Only the original NPC navigation goal; STOP sentinel is preserved.
			next = _frame_point(next, local)
		elif field in FRAME_GRID_VALUES:
			if next is Array and not _frame_pair(next):
				for index: int in next.size(): next[index] = _frame_point(next[index], local)
			else: next = _frame_point(next, local)
		else: next = _frame_walk(next, local, projection, str(key), seen, offsets, error,
			pixel_motion or str(key) in ["movement", "_fire_motion", "projectiles"])
		var translated_key: Variant = _frame_point(key, local) if field in FRAME_GRID_KEYS else key
		if field in FRAME_GRID_KEYS and translated_key is String:
			var parts := str(translated_key).split(",")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int(): translated_key = "%d,%d" % [int(parts[0]) + local.x, int(parts[1]) + local.y]
		if field == "reference_objects" and str(key).begins_with("lease:"):
			var lease_cell: Variant = next.get("values", {}).get("cell") if next is Dictionary else null
			if not (lease_cell is Vector2i or _frame_pair(lease_cell)):
				error.code = "INVALID_PARTY_LEASE_REFERENCE"
				return value
			translated_key = "lease:%d:%d" % [int(lease_cell.x) if lease_cell is Vector2i else int(lease_cell[0]), int(lease_cell.y) if lease_cell is Vector2i else int(lease_cell[1])]
		if field == "reference_objects" and value.has(translated_key):
			error.code = "DUPLICATE_PARTY_FRAME_REFERENCE"
			return value
		value[translated_key] = next
	return value

static func project_owner_coordinates(roots: Dictionary, projection: Dictionary) -> Dictionary:
	if not _valid_projection(projection): return fail("INVALID_PARTY_FRAME", "原 graph 投影規格非法")
	var copy: Dictionary = _frame_clone(roots, [], [])
	var semantic := projection.duplicate(true)
	semantic.runtime_offsets = {}
	for lease: Variant in roots.get("registry", {}).get("leases", []):
		if lease is Array and lease.size() == 2 and lease[1] is Array and lease[1].size() == 6:
			var offset := _frame_offset(projection, "people", lease[1][2], Vector2i(int(projection.default_offset[0]), int(projection.default_offset[1])))
			var key := str(int(lease[1][0]))
			if semantic.runtime_offsets.has(key) and semantic.runtime_offsets[key].offset != [offset.x, offset.y]: return fail("NONRIGID_ORIGINAL_FORMATION", "同一原 formation 的既有 leases 不能分離平移")
			semantic.runtime_offsets[key] = {"offset": [offset.x, offset.y]}
	var error := {"code": ""}
	_frame_walk(copy, Vector2i(int(projection.default_offset[0]), int(projection.default_offset[1])), semantic, "", [], [], error)
	if not str(error.code).is_empty(): return fail(str(error.code), "同一原 graph alias 被要求置於不同座標域")
	# Rebuild the original fire broadphase from the translated paid motion.
	if copy.get("lab") is Dictionary and copy.lab.get("_fire_motion") is Dictionary and copy.lab.has("_fire_body_buckets"):
		var buckets := {}
		for identity: Variant in copy.lab._fire_motion:
			var person: Dictionary = copy.lab._fire_motion[identity]
			if not person.get("ground") is Vector2 or not person.get("end_ground") is Vector2 or float(person.get("radius", 0.0)) <= 0.0: continue
			var bounds := Rect2(person.ground, Vector2.ZERO).expand(person.end_ground).grow(float(person.radius) + 1.8 * 48.0 + 1.0)
			for y in range(floori(bounds.position.y / 128.0), floori(bounds.end.y / 128.0) + 1):
				for x in range(floori(bounds.position.x / 128.0), floori(bounds.end.x / 128.0) + 1):
					var cell := Vector2i(x, y)
					if not buckets.has(cell): buckets[cell] = []
					buckets[cell].append(identity)
		copy.lab._fire_body_buckets = buckets
	return {"ok": true, "roots": copy}

static func _valid_projection(projection: Dictionary) -> bool:
	if projection.get("version") != 1 or not projection.get("source_width") is int or int(projection.source_width) <= 0 \
			or not projection.get("source_height") is int or int(projection.source_height) <= 0 or not _frame_pair(projection.get("size")) \
			or not _frame_pair(projection.get("world_origin")) or not _frame_pair(projection.get("default_offset")):
		return false
	if int(projection.size[0]) not in [100, 200] or int(projection.size[1]) not in [100, 200]: return false
	for field: String in ["people", "teams", "vehicles"]:
		if not projection.get(field) is Dictionary: return false
		for record: Variant in projection[field].values():
			if not record is Dictionary or not _frame_pair(record.get("offset")): return false
	return true

static func project_party_coordinates(party: Dictionary, projection: Dictionary) -> Dictionary:
	if not _valid_projection(projection) or not validate_identity(party.get("content", {}).get("travel_identity")):
		return fail("INVALID_PARTY_FRAME", "原 party 座標投影未准入")
	var copy: Dictionary = party.duplicate(true)
	var content: Dictionary = copy.content
	var bodies := _body_records(content)
	for kind: String in ["person", "vehicle"]:
		var records: Dictionary = projection.people if kind == "person" else projection.vehicles
		var originals: Dictionary = bodies if kind == "person" else content.get("vehicles", {})
		if records.size() != originals.size(): return fail("PARTY_FRAME_CLOSURE", "投影未覆蓋每一原人與車")
		for key: Variant in originals:
			var record: Dictionary = records.get(str(key), {})
			if record.get("reference") != content.travel_identity.refs[kind].get(str(key)) or not _frame_pair(record.get("from")) or not _frame_pair(record.get("to")):
				return fail("PARTY_FRAME_IDENTITY", "投影必須沿原 typed ref")
			var offset := Vector2i(int(record.offset[0]), int(record.offset[1]))
			var original: Dictionary = originals[key]
			var original_cell: Variant = original.get("cell")
			var original_point: Variant = [int(original_cell) % int(projection.source_width), int(original_cell) / int(projection.source_width)] if original_cell is int else original_cell
			if original_point != record.from: return fail("PARTY_FRAME_COORDINATE", "from 必須是原 selected body 座標")
			if Vector2i(int(record.from[0]), int(record.from[1])) + offset != Vector2i(int(record.to[0]), int(record.to[1])):
				return fail("PARTY_FRAME_COORDINATE", "投影不等於原語意座標平移")
			if int(record.to[0]) < 0 or int(record.to[1]) < 0 or int(record.to[0]) >= int(projection.size[0]) or int(record.to[1]) >= int(projection.size[1]):
				return fail("PARTY_FRAME_BOUNDS", "原 body 必須位於連續實體 frame 中")
	for actor: Dictionary in content.get("actors", {}).values():
		var shifted := project_owner_coordinates(actor, projection.merged({"default_offset": projection.people[str(int(actor.person_id))].offset}, true))
		if not shifted.ok: return shifted
		actor.merge(shifted.roots, true)
	for army: Dictionary in content.get("armies", []):
		var key := str(int(army.team_id))
		if not projection.teams.has(key): return fail("PARTY_FRAME_CLOSURE", "原隊未投影")
		var units: Array = army.units
		army.units = []
		var shifted := project_owner_coordinates(army, projection.merged({"default_offset": projection.teams[key].offset}, true))
		if not shifted.ok: return shifted
		army.merge(shifted.roots, true)
		for row: Dictionary in units:
			var moved := project_owner_coordinates(row, projection.merged({"default_offset": projection.people[str(int(row.person_id))].offset}, true))
			if not moved.ok: return moved
			army.units.append(moved.roots)
	for key: Variant in content.get("vehicles", {}):
		var vehicle: Dictionary = content.vehicles[key]
		var shifted := project_owner_coordinates(vehicle, projection.merged({"default_offset": projection.vehicles[str(key)].offset}, true))
		if not shifted.ok: return shifted
		vehicle.merge(shifted.roots, true)
	for loot: Dictionary in content.get("ground_loot", {}).values():
		var holder := str(loot.get("vehicle_id", loot.get("attached_vehicle_id", "")))
		var offset: Array = projection.vehicles.get(holder, {}).get("offset", projection.default_offset)
		var shifted := project_owner_coordinates(loot, projection.merged({"default_offset": offset}, true))
		if not shifted.ok: return shifted
		loot.merge(shifted.roots, true)
	return {"ok": true, "party": copy, "projection": projection.duplicate(true)}

static func project_party_frame(party: Dictionary, frame: Dictionary) -> Dictionary:
	if frame.get("version") != 1 or not _frame_pair(frame.get("world_origin")) or not _frame_pair(frame.get("size")) \
			or not frame.get("people") is Dictionary or not frame.get("vehicles") is Dictionary:
		return fail("INVALID_PARTY_FRAME", "原 world frame 缺少真邊界位置")
	var previous: Dictionary = party.get("upkeep", {}).get("live", {}).get("frame", {})
	var origin := Vector2i(int(frame.world_origin[0]), int(frame.world_origin[1]))
	var source_origin := Vector2i.ZERO
	if _frame_pair(previous.get("world_origin")):
		source_origin = Vector2i(int(previous.world_origin[0]), int(previous.world_origin[1]))
	elif _frame_pair(party.get("origin")):
		source_origin = Vector2i(int(party.origin[0]) * 100, -int(party.origin[1]) * 100)
	else:
		var parts := str(party.get("origin_site_id", "")).split(":")
		if parts.size() < 3 or not parts[-2].is_valid_int() or not parts[-1].is_valid_int(): return fail("INVALID_PARTY_FRAME", "原 party 缺少 true source frame")
		source_origin = Vector2i(int(parts[-2]) * 100, -int(parts[-1]) * 100)
	var source_size: Array = previous.get("size", [100, 100])
	var projection := {"version": 1, "source_width": int(source_size[0]), "source_height": int(source_size[1]),
		"world_origin": frame.world_origin.duplicate(), "size": frame.size.duplicate(),
		"default_offset": [source_origin.x - origin.x, source_origin.y - origin.y], "people": {}, "teams": {}, "vehicles": {}}
	var content: Dictionary = party.get("content", {})
	var bodies := _body_records(content)
	for key: Variant in bodies:
		var reference: Variant = content.get("travel_identity", {}).get("refs", {}).get("person", {}).get(str(key))
		var target: Dictionary = frame.people.get(str(key), {})
		var from: Variant = bodies[key].get("cell")
		if reference != target.get("reference") or not _frame_pair(from) or not _frame_pair(target.get("world_cell")):
			return fail("PARTY_FRAME_IDENTITY", "真 world frame 未對應原 body")
		var to := Vector2i(int(target.world_cell[0]), int(target.world_cell[1])) - origin
		var offset := to - Vector2i(int(from[0]), int(from[1]))
		projection.people[str(key)] = {"reference": reference.duplicate(), "from": from.duplicate(), "to": [to.x, to.y], "offset": [offset.x, offset.y]}
	for army: Dictionary in content.get("armies", []):
		var people: Array = []
		for row: Dictionary in army.units: people.append(int(row.person_id))
		var leader := int(army.units[clampi(int(army.get("current_commander", 0)), 0, army.units.size() - 1)].person_id) if not army.units.is_empty() else int(army.get("player_member", {}).get("id", 0))
		var offset: Array = projection.people.get(str(leader), {}).get("offset", projection.default_offset)
		projection.teams[str(int(army.team_id))] = {"offset": offset.duplicate(), "person_ids": people}
	for key: Variant in content.get("vehicles", {}):
		var vehicle: Dictionary = content.vehicles[key]
		var target: Dictionary = frame.vehicles.get(str(key), {})
		var reference: Variant = content.travel_identity.refs.vehicle.get(str(key))
		if reference != target.get("reference") or not _frame_pair(target.get("world_cell")) or not vehicle.get("cell") is int:
			return fail("PARTY_FRAME_IDENTITY", "真 world frame 未對應原車 hull")
		var from := Vector2i(int(vehicle.cell) % int(source_size[0]), int(vehicle.cell) / int(source_size[0]))
		var to := Vector2i(int(target.world_cell[0]), int(target.world_cell[1])) - origin
		var offset := to - from
		projection.vehicles[str(key)] = {"reference": reference.duplicate(), "from": [from.x, from.y], "to": [to.x, to.y],
			"offset": [offset.x, offset.y], "from_index": int(vehicle.cell), "to_index": to.y * int(frame.size[0]) + to.x}
	return project_party_coordinates(party, projection)

static func step_game_seconds() -> float:
	return (STEP_ACTION_SECONDS * 60.0) * STEP_SCALE

## Slowest member decides: people walk, carts and wagons are slower.
static func party_speed(content: Dictionary) -> float:
	var sea: bool = content.get("vehicles", {}).values().any(func(vehicle: Dictionary) -> bool: return str(vehicle.get("kind", "")) == "ship")
	var speed := INF if sea else WALK_MPS
	for body: Dictionary in _body_records(content).values():
		if float(body.get("hp", 0.0)) > 0.0 and _ko(body) <= 0.0 and str(body.get("embarked_vehicle_id", "")).is_empty():
			speed = minf(speed, WALK_MPS / (1.0 + Fatigue.slowdown(float(body.get("fatigue", 0.0)))))
	var people := _body_records(content)
	for vehicle: Dictionary in content.get("vehicles", {}).values():
		var rate := float(ship_metrics(content, vehicle).speed) if str(vehicle.get("kind", "")) == "ship" else float(VEHICLE_MPS.get(str(vehicle.get("kind", "")), WALK_MPS)) / (1.0 + Fatigue.slowdown(float(people.get(int(vehicle.get("operator_id", 0)), {}).get("fatigue", 0.0))))
		speed = minf(speed, rate)
	return speed if is_finite(speed) else 0.0

## Exact original ship load: bodies, their holders, attached remains and food.
static func ship_metrics(content: Dictionary, vehicle: Dictionary) -> Dictionary:
	var identity := str(vehicle.get("id", ""))
	var passengers := 0
	var crew := 0
	var driver_ready := false
	var teams := _body_teams(content)
	var holder: Dictionary = vehicle.get("holder", {})
	var load: float = Runtime.carried_load(content, vehicle.get("cargo", {}), holder) + float(holder.get("equipped", {}).size())
	for body: Dictionary in _body_records(content).values():
		if str(body.get("embarked_vehicle_id", "")) != identity: continue
		if float(body.get("hp", 0.0)) > 0.0: passengers += 1
		var kind := str(vehicle.get("ship_type", ""))
		var berth := int(body.get("berth_id", -1))
		var local := TerrainArmy._saved_ship_deck_position(body, kind)
		var duty := Ship.local_position(kind, berth)
		var destination: Array = body.get("destination", [-1, -1])
		var capable: bool = _able(body) and not _busy_role(body) and int(teams.get(int(body.person_id), -1)) == int(vehicle.get("team_id", 0)) \
			and local.is_finite() and local.is_equal_approx(duty) and str(body.get("pose", "idle")) == "idle" \
			and float(body.get("exchange_stagger", 0.0)) <= 0.0 and destination.size() == 2 and int(destination[0]) < 0 and int(destination[1]) < 0
		crew += int(capable and berth in Ship.crew_berths(kind))
		if capable and berth == 0 and int(body.person_id) == int(vehicle.get("operator_id", 0)): driver_ready = true
		var cargo: Dictionary = body.get("cargo", {})
		for actor: Dictionary in content.get("actors", {}).values():
			if int(actor.person_id) == int(body.person_id): cargo = content.get("manual_cargo", {})
		var items: Dictionary = body.get("item_state", {})
		load += Runtime.carried_load(content, cargo, items) + float(items.get("equipped", {}).size())
	for container: Dictionary in content.get("ground_loot", {}).values():
		if str(container.get("vehicle_id", "")) == identity: load += Runtime.carried_load(content, container.get("cargo", {}), container) + float(container.get("equipped", {}).size())
	for supply: Dictionary in content.get("team_supply", {}).values():
		var stock: Dictionary = supply.get("locations", {}).get("vehicle:" + identity, {})
		load += float(Runtime.inventory_size(stock.get("inventory", {}))) + float(stock.get("open_rations", 0.0))
	return {"people": passengers, "crew": crew, "load": load, "driver_ready": driver_ready,
		"speed": Ship.speed(str(vehicle.get("ship_type", "")), passengers, load, crew) if driver_ready else 0.0}

static func _body_records(content: Dictionary) -> Dictionary:
	var people := {}
	for actor: Dictionary in content.get("actors", {}).values(): people[int(actor.person_id)] = actor
	for army: Dictionary in content.get("armies", []):
		for row: Dictionary in army.get("units", []): people[int(row.person_id)] = row
	return people

static func _body_teams(content: Dictionary) -> Dictionary:
	var teams := {}
	for army: Dictionary in content.get("armies", []):
		for row: Dictionary in army.get("units", []): teams[int(row.person_id)] = int(army.team_id)
		if not army.get("player_member", {}).is_empty(): teams[int(army.player_member.id)] = int(army.team_id)
	return teams

static func _ko(body: Dictionary) -> float:
	return float(body.get("ko", body.get("knockout_left", 0.0)))

static func _able(body: Dictionary) -> bool:
	return float(body.get("hp", 0.0)) > 0.0 and _ko(body) <= 0.0 and not bool(body.get("captive", false)) \
		and not bool(body.get("surrender_pending", false)) and not bool(body.get("departed", false)) \
		and str(body.get("pose", "idle")) not in ["unconscious", "get_up", "down"] and not bool(body.get("_getting_up", false))

static func _busy_role(body: Dictionary) -> bool:
	return not body.get("work_task", {}).is_empty() or not str(body.get("siege_vehicle_id", "")).is_empty() \
		or bool(body.get("attack", false)) or float(body.get("action_time", 0.0)) > 0.0

static func validate_patients(content: Dictionary) -> Dictionary:
	var people := _body_records(content)
	var teams := _body_teams(content)
	var seen := {}
	for vehicle: Dictionary in content.get("vehicles", {}).values():
		var seats: Variant = vehicle.get("travel_patients", {})
		if not seats is Dictionary: return fail("INVALID_PATIENTS", "車載患者資料不是原引用")
		if seats.is_empty(): continue
		var maximum := int(PATIENT_SEATS.get(str(vehicle.get("kind", "")), 0))
		if seats.size() != 3 or seats.get("version") != 1 or not seats.get("person_ids") is Array \
				or seats.person_ids.size() > maximum or seats.get("reserved_capacity") != seats.person_ids.size() * PATIENT_CAPACITY:
			return fail("INVALID_PATIENTS", "車載患者席位／容量不符")
		var holder: Dictionary = vehicle.get("holder", {})
		if Runtime.carried_load(content, vehicle.get("cargo", {}), holder) + holder.get("equipped", {}).size() + int(seats.reserved_capacity) > SiteVehicleTransport.capacity_of(vehicle):
			return fail("CAPACITY", "原貨物加患者預留超過車輛容量")
		for person: Variant in seats.person_ids:
			if not person is int or seen.has(person) or not people.has(person) or float(people[person].hp) <= 0.0 or _ko(people[person]) <= 0.0 \
					or int(teams.get(person, -1)) != int(vehicle.get("team_id", 0)) or int(vehicle.get("operator_id", 0)) == person \
					or bool(people[person].get("departed", false)) or not str(people[person].get("embarked_vehicle_id", "")).is_empty():
				return fail("INVALID_PATIENTS", "患者不是唯一原倒地人物")
			seen[person] = true
	return {"ok": true, "patients": seen}

## The first land vehicle (cart/wagon) that prepare_transport's operator rule
## would refuse, in the same stable order and with the same shared-role
## accounting; empty when every one has a capable, unshared operator.
static func land_vehicle_operator_gap(content: Dictionary) -> Dictionary:
	var people := _body_records(content)
	var taken := {}
	var vehicles: Array = content.get("vehicles", {}).keys()
	vehicles.sort()
	for vehicle_id: String in vehicles:
		var vehicle: Dictionary = content.vehicles[vehicle_id]
		var operator_id := int(vehicle.get("operator_id", 0))
		if str(vehicle.get("kind", "")) in PATIENT_SEATS:
			if not people.has(operator_id) or not _able(people[operator_id]) or _busy_role(people[operator_id]) or taken.has(operator_id):
				return {"vehicle_id": vehicle_id, "kind": str(vehicle.get("kind", "")), "operator_id": operator_id}
			taken[operator_id] = true
		for crew: Variant in vehicle.get("crew_slots", {}).values():
			if int(crew) > 0: taken[int(crew)] = true
		if str(vehicle.get("kind", "")) == "ship":
			for person: int in people:
				if str(people[person].get("embarked_vehicle_id", "")) == vehicle_id and int(people[person].get("berth_id", -1)) in Ship.crew_berths(str(vehicle.ship_type)): taken[person] = true
	return {}

## Allocate original-person roles in stable order, not one pair per loop visit.
static func prepare_transport(party: Dictionary, patient_schema: bool = true) -> Dictionary:
	var content: Dictionary = party.content
	var people := _body_records(content)
	var teams := _body_teams(content)
	var taken := {}
	var patients: Array[int] = []
	var available: Array[int] = []
	var vehicles: Array = content.get("vehicles", {}).keys()
	vehicles.sort()
	for identity: Variant in people:
		var body: Dictionary = people[identity]
		if _able(body) and not _busy_role(body): available.append(int(identity))
		elif float(body.get("hp", 0.0)) > 0.0 and _ko(body) > 0.0: patients.append(int(identity))
	available.sort()
	patients.sort()
	for vehicle_id: String in vehicles:
		var vehicle: Dictionary = content.vehicles[vehicle_id]
		var operator_id := int(vehicle.get("operator_id", 0))
		if str(vehicle.get("kind", "")) in PATIENT_SEATS:
			if not people.has(operator_id) or not _able(people[operator_id]) or _busy_role(people[operator_id]) or taken.has(operator_id):
				return {"ok": true, "can_move": false, "reason": "車輛操作者失能、缺席或兼任", "carriers": {}}
			taken[operator_id] = true
		for crew: Variant in vehicle.get("crew_slots", {}).values():
			if int(crew) > 0: taken[int(crew)] = true
		if str(vehicle.get("kind", "")) == "ship":
			var metrics := ship_metrics(content, vehicle)
			if float(metrics.speed) <= 0.0: return {"ok": true, "can_move": false, "reason": "原船缺少有效船員或超載", "carriers": {}}
			for person: int in people:
				if str(people[person].get("embarked_vehicle_id", "")) == vehicle_id and int(people[person].get("berth_id", -1)) in Ship.crew_berths(str(vehicle.ship_type)): taken[person] = true
		vehicle.erase("travel_patients")
	var assigned := {}
	for patient: int in patients:
		var boat := str(people[patient].get("embarked_vehicle_id", ""))
		if not boat.is_empty() and str(content.vehicles.get(boat, {}).get("kind", "")) == "ship": assigned[patient] = true
	if patient_schema:
		for vehicle_id: String in vehicles:
			var vehicle: Dictionary = content.vehicles[vehicle_id]
			var maximum := int(PATIENT_SEATS.get(str(vehicle.get("kind", "")), 0))
			var holder: Dictionary = vehicle.get("holder", {})
			var free: float = SiteVehicleTransport.capacity_of(vehicle) - Runtime.carried_load(content, vehicle.get("cargo", {}), holder) - holder.get("equipped", {}).size()
			var boarding: Array[int] = []
			for patient: int in patients:
				if assigned.has(patient) or boarding.size() >= maximum or free < PATIENT_CAPACITY or int(teams.get(patient, -1)) != int(vehicle.get("team_id", 0)): continue
				boarding.append(patient)
				assigned[patient] = true
				free -= PATIENT_CAPACITY
			if not boarding.is_empty(): vehicle.travel_patients = {"version": 1, "person_ids": boarding, "reserved_capacity": boarding.size() * PATIENT_CAPACITY}
	var carriers := {}
	for patient: int in patients:
		if assigned.has(patient): continue
		var pair: Array[int] = []
		for carrier: int in available:
			if not taken.has(carrier):
				pair.append(carrier)
				if pair.size() == 2: break
		if pair.size() != 2:
			return {"ok": true, "can_move": false, "reason": "倒地者沒有足夠的原患者席位或兩名抬運者", "carriers": carriers}
		for carrier: int in pair: taken[carrier] = true
		carriers[str(patient)] = pair
	var checked := validate_patients(content)
	if not checked.ok: return checked
	return {"ok": true, "can_move": not available.is_empty(), "reason": "全隊不能行動" if available.is_empty() else "", "carriers": carriers,
		"carry_factor": 0.5 if not carriers.is_empty() else 1.0}

static func _feeding(content: Dictionary, people: Dictionary) -> Array[Dictionary]:
	var owners: Array[Dictionary] = []
	for supply: Dictionary in content.get("team_supply", {}).values():
		var sustain: Dictionary = supply.get("sustain", {})
		if sustain.is_empty(): continue
		var stock: Dictionary = supply.get("locations", {}) if int(supply.get("version", 0)) == 3 else supply.get("inventory", {})
		var locations := {}
		var keys := stock.keys()
		keys.sort()
		for person: int in Sustain._ids(sustain):
			var body: Dictionary = people.get(person, {})
			var boat := str(body.get("embarked_vehicle_id", ""))
			if not boat.is_empty():
				locations[person] = "vehicle:" + boat if stock.has("vehicle:" + boat) else ""
			else:
				locations[person] = str(keys[0]) if not keys.is_empty() else ""
		owners.append({"sustain": sustain, "stock": stock, "owner": supply, "context": {"food_locations": locations} if int(sustain.get("version", 1)) == 2 else {}})
	for key: String in content.get("person_supply", {}):
		var body: Dictionary = people.get(int(key), {})
		var cargo: Dictionary = body.get("cargo", {})
		for actor_key: String in content.get("actors", {}):
			if int(content.actors[actor_key].person_id) == int(key): cargo = content.get("manual_cargo", {})
		owners.append({"sustain": content.person_supply[key], "stock": cargo, "owner": body, "context": {}})
	return owners


static func _pools(content: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var claimed := {}
	var people := _body_records(content)
	for army: Dictionary in content.get("armies", []):
		var members: Array[int] = []
		for body: Dictionary in army.get("units", []):
			if bool(body.get("member", true)) and float(body.get("hp", 0.0)) > 0.0 and not bool(body.get("departed", false)): members.append(int(body.person_id))
		var actor_id := int(army.get("player_member", {}).get("id", -1))
		if people.has(actor_id) and float(people[actor_id].hp) > 0.0: members.append(actor_id)
		if army.has("team_fatigue") and not members.is_empty():
			result.append({"state": army.team_fatigue, "ids": members, "count": members.size()})
			for person: int in members: claimed[person] = true
	for person: int in people:
		if not claimed.has(person) and float(people[person].hp) > 0.0: result.append({"state": people[person], "ids": [person], "count": 1})
	return result

static func _crew_roles(content: Dictionary, people: Dictionary, options: Dictionary = {}) -> Dictionary:
	var result := {}
	for person: int in people:
		var body: Dictionary = people[person]
		var boat := str(body.get("embarked_vehicle_id", ""))
		if boat.is_empty() or options.has("active_ship_ids") and boat not in options.active_ship_ids: continue
		var ship: Dictionary = content.get("vehicles", {}).get(boat, {})
		if str(ship.get("kind", "")) == "ship" and int(body.get("berth_id", -1)) in Ship.crew_berths(str(ship.get("ship_type", ""))): result[person] = true
	return result

static func _pool_rate(pool: Dictionary, people: Dictionary, moving: bool, crew_roles: Dictionary = {}) -> float:
	if not moving: return 0.0
	var workers := 0
	for person: int in pool.ids:
		if _able(people[person]):
			var body: Dictionary = people[person]
			var boat := str(body.get("embarked_vehicle_id", ""))
			if boat.is_empty() or crew_roles.has(person): workers += 1
	return Fatigue.WORK_RATE * workers / float(maxi(1, int(pool.count)))

## Only speed curves are derived; no second fatigue/person state is kept.
static func _distance(content: Dictionary, pools: Array[Dictionary], people: Dictionary, seconds: float, carry_factor: float, crew_roles: Dictionary = {}) -> float:
	var curves: Array[Dictionary] = []
	var per_person := {}
	for pool: Dictionary in pools:
		var value := float(pool.state.get("fatigue", 0.0))
		var rate := _pool_rate(pool, people, true, crew_roles)
		var slope := Fatigue.MAX_SLOWDOWN / (Fatigue.LIMIT - Fatigue.THRESHOLD) * rate if value >= Fatigue.THRESHOLD - EPS else 0.0
		var curve := {"base": WALK_MPS, "a": 1.0 + Fatigue.slowdown(value), "b": slope}
		for person: int in pool.ids:
			per_person[person] = curve
			if _able(people[person]) and str(people[person].get("embarked_vehicle_id", "")).is_empty(): curves.append(curve)
	for vehicle: Dictionary in content.get("vehicles", {}).values():
		var kind := str(vehicle.get("kind", ""))
		if kind in VEHICLE_MPS:
			var curve: Dictionary = per_person.get(int(vehicle.get("operator_id", 0)), {"a": 1.0, "b": 0.0}).duplicate()
			curve.base = float(VEHICLE_MPS[kind])
			curves.append(curve)
		elif kind == "ship":
			curves.append({"base": float(ship_metrics(content, vehicle).speed), "a": 1.0, "b": 0.0})
	if curves.is_empty(): return 0.0
	var cuts: Array[float] = [0.0, seconds]
	for first: Dictionary in curves:
		for second: Dictionary in curves:
			var denominator := float(first.base) * float(second.b) - float(second.base) * float(first.b)
			if absf(denominator) <= 0.000000000000001: continue
			var crossing := (float(second.base) * float(first.a) - float(first.base) * float(second.a)) / denominator
			if crossing > EPS and crossing < seconds - EPS: cuts.append(crossing)
	cuts.sort()
	var metres := 0.0
	for index: int in range(1, cuts.size()):
		var begin := cuts[index - 1]
		var end := cuts[index]
		var middle := (begin + end) * 0.5
		var chosen: Dictionary = curves[0]
		for curve: Dictionary in curves:
			if float(curve.base) / (float(curve.a) + float(curve.b) * middle) < float(chosen.base) / (float(chosen.a) + float(chosen.b) * middle): chosen = curve
		metres += float(chosen.base) * (log((float(chosen.a) + float(chosen.b) * end) / (float(chosen.a) + float(chosen.b) * begin)) / float(chosen.b) if float(chosen.b) > 0.000000000000001 else (end - begin) / float(chosen.a))
	return metres * carry_factor

static func next_upkeep_event(party: Dictionary, options: Dictionary = {}) -> Dictionary:
	var content: Dictionary = party.get("content", {})
	var at := float(party.get("upkeep", {}).get("at", options.get("at", 0.0)))
	var people := _body_records(content)
	var crew_roles := _crew_roles(content, people, options)
	var delta := INF
	for body: Dictionary in people.values():
		if float(body.get("hp", 0.0)) > 0.0 and _ko(body) > 0.0: delta = minf(delta, _ko(body))
	var resting := bool(party.get("upkeep", {}).get("resting", false))
	for pool: Dictionary in _pools(content):
		var value := float(pool.state.get("fatigue", 0.0))
		var rested := float(pool.state.get("fatigue_rest", 0.0))
		if resting:
			if bool(options.get("safe_rest", true)) and value > Fatigue.WORK_RESUME_AT + EPS:
				delta = minf(delta, Fatigue.REST_DELAY - rested if rested < Fatigue.REST_DELAY - EPS else (value - Fatigue.WORK_RESUME_AT) / Fatigue.RECOVERY_RATE)
		elif value < Fatigue.WORK_REST_AT - EPS:
			var rate := _pool_rate(pool, people, true, crew_roles)
			if rate > EPS: delta = minf(delta, ((Fatigue.THRESHOLD if value < Fatigue.THRESHOLD - EPS else Fatigue.WORK_REST_AT) - value) / rate)
	for owner: Dictionary in _feeding(content, people):
		for cohort: Dictionary in owner.sustain.get("cohorts", []):
			var until := float(cohort.get("meal_until", at))
			if until > at + EPS: delta = minf(delta, until - at)
			var deficit := 1.0 - float(cohort.get("coverage", 0.0))
			if deficit > EPS:
				for person: Variant in cohort.ids:
					if people.has(int(person)) and float(people[int(person)].hp) > 0.0:
						delta = minf(delta, (maxf(0.0, 48.0 - float(cohort.hunger)) + float(people[int(person)].hp)) / deficit * Sustain.HOUR)
	var until := float(options.get("until", INF))
	if is_finite(until): delta = minf(delta, maxf(0.0, until - at))
	return {"ok": true, "at": at + delta, "delta": delta}

## Caller commits this detached party and distance with the same Slot receipt.
static func advance_upkeep(party: Dictionary, to_game_seconds: float, options: Dictionary = {}) -> Dictionary:
	var speed_multiplier: Variant = options.get("speed_multiplier", 1.0)
	if not (speed_multiplier is float or speed_multiplier is int) or not is_finite(float(speed_multiplier)) or float(speed_multiplier) <= 0.0 or float(speed_multiplier) > 1.0:
		return fail("INVALID_ROUTE_SPEED", "原路線地類／坡度速度須是有效倍率")
	var candidate := party.duplicate(true)
	var content: Dictionary = candidate.get("content", {})
	var upkeep: Dictionary = candidate.get("upkeep", {"version": 1, "at": float(options.get("from_game_seconds", to_game_seconds)), "resting": false, "carriers": {}, "events": [], "sequence": 0})
	if int(upkeep.get("version", 0)) != 1 or not is_finite(to_game_seconds) or to_game_seconds < float(upkeep.at) - EPS:
		return fail("INVALID_UPKEEP", "在途消耗時間倒退或版本不符")
	candidate.upkeep = upkeep
	var pending: Array = upkeep.get("events", []).filter(func(event: Dictionary) -> bool: return event.get("status") == "pending")
	if not pending.is_empty():
		return {"ok": true, "party": candidate, "at": float(upkeep.at), "metres": 0.0, "consumed_rations": 0.0, "events": pending, "can_move": false, "resting": bool(upkeep.resting), "reason": "原生命端點效果尚未消費", "speed_mps": 0.0}
	var people := _body_records(content)
	# One original feeding owner per original body, before any food is spent.
	var owners := _feeding(content, people)
	var ledgers: Array = []
	var members := {}
	for person: int in people: members[person] = {"hp": float(people[person].hp), "ko": _ko(people[person]), "captive": bool(people[person].get("captive", false)), "present": true}
	for owner: Dictionary in owners: ledgers.append(owner.sustain)
	if not Sustain.validate_owners(ledgers, members): return fail("INVALID_SUPPLY_OWNERS", "原供養人物不唯一或供養狀態不符")
	var metres := 0.0
	var consumed := 0.0
	var events: Array = []
	while float(upkeep.at) < to_game_seconds - EPS:
		var pools := _pools(content)
		for pool: Dictionary in pools:
			if float(pool.state.get("fatigue", 0.0)) >= Fatigue.WORK_REST_AT - EPS: upkeep.resting = true
		if bool(upkeep.resting) and pools.all(func(pool: Dictionary) -> bool: return float(pool.state.get("fatigue", 0.0)) <= Fatigue.WORK_RESUME_AT + EPS): upkeep.resting = false
		var transport := prepare_transport(candidate, bool(options.get("patient_schema", true)))
		if not transport.ok: return transport
		upkeep.carriers = transport.carriers
		var moving := bool(options.get("moving", true)) and bool(transport.can_move) and not bool(upkeep.resting)
		var safe := bool(options.get("safe_rest", true)) and not bool(options.get("threat", false)) and not bool(options.get("committed_action", false))
		var endpoint_options := options.duplicate()
		endpoint_options.safe_rest = safe
		var endpoint := next_upkeep_event(candidate, endpoint_options)
		var end := minf(to_game_seconds, float(endpoint.at))
		var seconds := end - float(upkeep.at)
		if seconds <= EPS: return fail("UPKEEP_EVENT", "在途端點須先由原事件出口處理")
		var rates: Array[float] = []
		var crew_roles := _crew_roles(content, people, options)
		for pool: Dictionary in pools: rates.append(_pool_rate(pool, people, moving, crew_roles))
		# Sea displacement is measured by original completed ACTION steps. The
		# Slot supplies the same journal interval; game upkeep never invents it.
		if moving and str(options.get("distance_mode", "land")) != "sea_action": metres += _distance(content, pools, people, seconds, float(transport.get("carry_factor", 1.0)), crew_roles) * float(speed_multiplier)
		members = {}
		for person: int in people: members[person] = {"hp": float(people[person].hp), "ko": _ko(people[person]), "captive": bool(people[person].get("captive", false)), "present": true}
		for owner: Dictionary in owners:
			var context: Dictionary = owner.context.duplicate()
			context.safe = safe
			context.stopped = not moving
			context.committed_action = bool(options.get("committed_action", false))
			var outcome := Sustain.advance_to(owner.sustain, members, owner.stock, end, context)
			if not outcome.ok: return outcome
			consumed += float(outcome.consumed_rations)
			if float(outcome.consumed_rations) > EPS:
				if owner.owner.has("revision"): owner.owner.revision = int(owner.owner.revision) + 1
				if owner.owner.get("holder") is Dictionary: owner.owner.holder.version = int(owner.owner.holder.get("version", 0)) + 1
		for person: int in people:
			var body: Dictionary = people[person]
			var old_hp := float(body.hp)
			var ending_hp := float(members[person].hp)
			if ending_hp < old_hp:
				upkeep.sequence = int(upkeep.sequence) + 1
				var event := {"kind": "supply_damage", "death": ending_hp <= 0.0, "person_id": person, "old_hp": old_hp, "ending_hp": ending_hp, "loss": old_hp - ending_hp, "at": end, "sequence": int(upkeep.sequence), "controlled": str(candidate.get("controller", "player")) == "player" and person == int(content.get("controlled_person_id", -1)), "status": "pending"}
				var apply_damage: Callable = options.get("apply_damage", Callable())
				if apply_damage.is_valid():
					var applied: Dictionary = apply_damage.call(content, person, event)
					if not bool(applied.get("ok", false)): return applied
					event.status = "complete"
					body.hp = float(applied.get("hp", body.hp))
				else: events.append(event)
				upkeep.events.append(event)
			# Accepted original Supply outcome takes precedence at this endpoint.
			# The immutable body still has old_hp until its original consumer runs;
			# that must not produce a wake for the person who just died.
			if float(members[person].hp) > 0.0 and float(body.hp) > 0.0 and _ko(body) > 0.0:
				var left := maxf(0.0, _ko(body) - seconds)
				body["ko" if body.has("ko") else "knockout_left"] = left
				if left <= EPS:
					upkeep.sequence = int(upkeep.sequence) + 1
					var event := {"kind": "wake", "person_id": person, "at": end, "sequence": int(upkeep.sequence), "controlled": str(candidate.get("controller", "player")) == "player" and person == int(content.get("controlled_person_id", -1)), "status": "pending"}
					events.append(event)
					upkeep.events.append(event)
		for pool_index: int in range(pools.size()):
			var pool: Dictionary = pools[pool_index]
			var advanced := Fatigue.advance(float(pool.state.get("fatigue", 0.0)), float(pool.state.get("fatigue_rest", 0.0)), seconds, rates[pool_index], safe and rates[pool_index] <= 0.0)
			pool.state.fatigue = advanced[0]
			pool.state.fatigue_rest = advanced[1]
			if pool.state.has("active"): pool.state.active = moving and rates[pool_index] > 0.0
			for person: int in pool.ids:
				people[person].fatigue = advanced[0]
				people[person].fatigue_rest = advanced[1]
		upkeep.at = end
		if not events.is_empty(): break # Original death/action cleanup, never another loop's travel.
	var final_pools := _pools(content)
	for pool: Dictionary in final_pools:
		if float(pool.state.get("fatigue", 0.0)) >= Fatigue.WORK_REST_AT - EPS: upkeep.resting = true
	if bool(upkeep.resting) and final_pools.all(func(pool: Dictionary) -> bool: return float(pool.state.get("fatigue", 0.0)) <= Fatigue.WORK_RESUME_AT + EPS): upkeep.resting = false
	candidate.speed_mps = party_speed(content)
	var transport := prepare_transport(candidate, bool(options.get("patient_schema", true)))
	if not transport.ok: return transport
	var can_move := bool(transport.can_move) and not bool(upkeep.resting) and events.is_empty()
	candidate.speed_mps = float(candidate.speed_mps) * float(transport.get("carry_factor", 1.0)) * float(speed_multiplier) if can_move else 0.0
	return {"ok": true, "party": candidate, "at": float(upkeep.at), "metres": metres, "consumed_rations": consumed, "events": events,
		"can_move": can_move, "resting": bool(upkeep.resting), "reason": str(transport.get("reason", "")), "speed_mps": float(candidate.speed_mps)}

## Decision A2 (Nekki, 2026-10-10): a settled dead row (hp <= 0 and its loot
## already settled) and a discharged row (member = false) do not block a team's
## departure. They are non-departing members that travel inert with their
## container, every field unchanged, and stay in it at the destination.
static func _row_inert(row: Dictionary) -> bool:
	if bool(row.get("departed", false)) or bool(row.get("site_exited", false)): return false
	if float(row.get("hp", 0.0)) <= 0.0: return bool(row.get("loot_settled", false))
	return not bool(row.get("member", true))

## Inert rows of a travelling content: _row_inert rows that are not the
## leader and whose container still holds at least one departing row (a solo
## container's own detached row is never inert).
static func _inert_people(content: Dictionary, leader_id: int) -> Dictionary:
	var inert := {}
	for army: Dictionary in content.get("armies", []):
		var candidates: Array[int] = []
		var departing := false
		for row: Dictionary in army.get("units", []):
			if _row_inert(row) and int(row.person_id) != leader_id: candidates.append(int(row.person_id))
			else: departing = true
		if departing:
			for person: int in candidates: inert[person] = true
	return inert

static func _row_ready(row: Dictionary, independent: bool = false, sea: bool = false) -> String:
	if float(row.get("hp", 0.0)) <= 0.0 or bool(row.get("departed", false)) or bool(row.get("site_exited", false)):
		return "隊內有陣亡或已離場者；R1 只帶全員在世的隊伍出發"
	if float(row.get("ko", 0.0)) > 0.0 or str(row.get("pose", "")) in ["unconscious", "get_up", "down"]:
		return "有隊員倒地；須先救起或包紮才能出發"
	if bool(row.get("captive", false)) or bool(row.get("surrender_pending", false)):
		return "有隊員被俘或投降中"
	if not independent and not bool(row.get("member", true)):
		return "原隊容器內仍有已退隊者；R1 不拆隊出發"
	if not sea and (row.has("embarked_vehicle_id") or row.has("berth_id")):
		return "有隊員在船上；陸路旅行前須先下船"
	if not row.get("work_task", {}).is_empty() or bool(row.get("attack", false)):
		return "有隊員仍在作業或攻擊"
	var destination: Array = row.get("destination", [-1, -1])
	if destination.size() == 2 and int(destination[0]) >= 0:
		return "有隊員仍在移動"
	return ""

## Use a detached original Army snapshot. Rejection never calls live leave_row.
## The one-person container owns the same row, with no team membership/office.
static func _detach_row(origin: Dictionary, person_id: int) -> Dictionary:
	var selected: Dictionary = {}
	var selected_index := -1
	for army: Dictionary in origin.get("armies", []):
		for index: int in range(army.get("units", []).size()):
			if int(army.units[index].person_id) == person_id:
				selected = army
				selected_index = index
	if selected.is_empty(): return fail("NO_TARGET", "找不到單走的原隊員")
	if selected.units.size() == 1 and selected.get("player_member", {}).is_empty() and not bool(selected.units[0].get("member", true)):
		return {"ok": true, "team_id": int(selected.team_id)}
	if int(selected.get("formal_commander", -1)) == selected_index: return fail("CAPTAIN_REQUIRED", "正式隊長須沿整隊出發")
	if not str(selected.get("garrison_feature_id", "")).is_empty() or not selected.get("rescues", []).is_empty() \
			or int(selected.get("combat_order", 0)) != 0: return fail("BUSY", "原隊須先守位並收束駐營／救助")
	var reason := _row_ready(selected.units[selected_index], true)
	if not reason.is_empty(): return fail("NOT_READY", reason)
	var people := _body_records(origin)
	var solo: Dictionary = selected.duplicate(true)
	var row: Dictionary = selected.units[selected_index]
	var selected_abilities: Array = []
	for ability: Dictionary in selected.get("abilities", []):
		if int(ability.unit) == selected_index: selected_abilities.append({"unit": 0, "values": ability.values.duplicate(true)})
	var reference: Array = selected.get("reference", row.cell)
	var used := {}
	for army: Dictionary in origin.armies: used[int(army.team_id)] = true
	var team_id := maxi(1, int(origin.get("army_next_team", 1)))
	while used.has(team_id): team_id += 1
	if team_id > 999999: return fail("ID_LIMIT", "原隊伍容器編號已達上限")
	var supply: Dictionary = origin.get("team_supply", {}).get(str(int(selected.team_id)), {})
	if not supply.is_empty() and person_id in Sustain._ids(supply.get("sustain", {})):
		var personal: Dictionary = origin.get("person_supply", {}).get(str(person_id), Sustain.create(float(supply.sustain.at)))
		var moved := Sustain.move_members(supply.sustain, personal, people, [person_id])
		if not moved.ok: return moved
		origin.person_supply[str(person_id)] = personal
		if supply.has("revision"): supply.revision = int(supply.revision) + 1
		if supply.has("life_checkpoint"): supply.life_checkpoint.erase(str(person_id))
	selected.units.remove_at(selected_index)
	for field: String in ["formal_commander", "acting_commander", "current_commander"]:
		var index := int(selected.get(field, -1))
		selected[field] = -1 if index == selected_index else (index - 1 if index > selected_index and index != TerrainArmy.PLAYER_MEMBER else index)
	for field: String in ["officers", "officer_service"]:
		var kept: Array = []
		for index: Variant in selected.get(field, []):
			if int(index) != selected_index: kept.append(int(index) - 1 if int(index) > selected_index and int(index) != TerrainArmy.PLAYER_MEMBER else int(index))
		selected[field] = kept
	var abilities: Array = []
	for ability: Dictionary in selected.get("abilities", []):
		if int(ability.unit) == selected_index: continue
		if int(ability.unit) > selected_index and int(ability.unit) != TerrainArmy.PLAYER_MEMBER: ability.unit = int(ability.unit) - 1
		abilities.append(ability)
	selected.abilities = abilities
	selected.vacancies = []
	if selected.has("offices"): SiteOffices.vacate_unless(selected.offices, func(holder: int) -> bool: return holder != person_id)
	_settle_team(selected, Vector2i(int(reference[0]), int(reference[1])))
	row.member = false
	row.present = false
	solo.units = [row]
	solo.team_id = team_id
	solo.player_member = {}
	solo.officers = []
	solo.officer_service = []
	solo.offices = SiteOffices.default_offices("team", -1, false)
	solo.abilities = selected_abilities
	solo.vacancies = []
	solo.rescues = []
	for field: String in ["formal_commander", "acting_commander", "current_commander"]: solo[field] = -1
	solo.erase("team_fatigue")
	if solo.has("tactical_ai"): solo.tactical_ai.enabled = false
	_settle_team(solo, Vector2i(int(row.cell[0]), int(row.cell[1])))
	if selected.units.is_empty() and selected.get("player_member", {}).is_empty(): origin.armies.erase(selected)
	origin.armies.append(solo)
	origin.army_next_team = team_id + 1
	return {"ok": true, "team_id": team_id}

static func _detach_actor(origin: Dictionary, person_id: int) -> Dictionary:
	for army: Dictionary in origin.get("armies", []):
		if int(army.get("player_member", {}).get("id", -1)) != person_id: continue
		if int(army.get("formal_commander", -1)) == TerrainArmy.PLAYER_MEMBER: return fail("CAPTAIN_REQUIRED", "正式隊長須沿整隊出發")
		if not str(army.get("garrison_feature_id", "")).is_empty() or not army.get("rescues", []).is_empty(): return fail("BUSY", "原隊駐營／救助尚未收束")
		var people := _body_records(origin)
		var body: Dictionary = people.get(person_id, {})
		if body.is_empty(): return fail("NO_TARGET", "原 Actor 不在來源 owner")
		var reason := _actor_ready(body)
		if not reason.is_empty(): return fail("NOT_READY", reason)
		var supply: Dictionary = origin.get("team_supply", {}).get(str(int(army.team_id)), {})
		if not supply.is_empty() and person_id in Sustain._ids(supply.get("sustain", {})):
			if not origin.has("person_supply"): origin.person_supply = {}
			var personal: Dictionary = origin.person_supply.get(str(person_id), Sustain.create(float(supply.sustain.at)))
			var moved := Sustain.move_members(supply.sustain, personal, people, [person_id])
			if not moved.ok: return moved
			origin.person_supply[str(person_id)] = personal
			if supply.has("revision"): supply.revision = int(supply.revision) + 1
			if supply.has("life_checkpoint"): supply.life_checkpoint.erase(str(person_id))
		var fatigue: Dictionary = army.get("team_fatigue", {})
		if not fatigue.is_empty():
			body.fatigue = float(fatigue.get("fatigue", body.get("fatigue", 0.0)))
			body.fatigue_rest = float(fatigue.get("fatigue_rest", body.get("fatigue_rest", 0.0)))
		army.player_member = {}
		for field: String in ["formal_commander", "acting_commander", "current_commander"]:
			if int(army.get(field, -1)) == TerrainArmy.PLAYER_MEMBER: army[field] = -1
		for field: String in ["officers", "officer_service"]: army[field] = army.get(field, []).filter(func(index: Variant) -> bool: return int(index) != TerrainArmy.PLAYER_MEMBER)
		army.abilities = army.get("abilities", []).filter(func(ability: Dictionary) -> bool: return int(ability.unit) != TerrainArmy.PLAYER_MEMBER)
		if army.has("offices"): SiteOffices.vacate_unless(army.offices, func(holder: int) -> bool: return holder != person_id)
		return {"ok": true}
	return fail("NO_TARGET", "原 Actor 尚未入此隊")

static func _actor_ready(actor: Dictionary) -> String:
	if float(actor.get("hp", 0.0)) <= 0.0: return "人物已死亡"
	if float(actor.get("knockout_left", 0.0)) > 0.0 or bool(actor.get("_getting_up", false)):
		return "人物倒地；須先起身"
	if bool(actor.get("captive", false)) or bool(actor.get("surrender_pending", false)) or bool(actor.get("site_exited", false)):
		return "人物被俘、投降中或已離場"
	if float(actor.get("movement_left", 0.0)) > 0.0 or float(actor.get("action_time", 0.0)) > 0.0 \
			or not actor.get("projectiles", []).is_empty() or int(actor.get("attack_target", 0)) != 0 \
			or int(actor.get("rescue_target", 0)) != 0 or float(actor.get("_rescue_left", 0.0)) > 0.0:
		return "人物仍在移動、攻擊或救助"
	if bool(actor.get("appearance", {}).get("mounted", false)):
		return "R1 陸路旅行先下馬再出發"
	return ""

## Fire transport in its JSON wire shape (arrays), from either the live
## normalized-map form or the wire form — same rules as SiteStore's boundary.
static func wire_transport(raw: Dictionary) -> Dictionary:
	var wire: Dictionary = raw.duplicate(true)
	if wire.get("orders") is Dictionary:
		var rows: Array = []
		for group: Variant in wire.orders:
			var order: Dictionary = wire.orders[group]
			order.group = int(group)
			rows.append(order)
		wire.orders = rows
	for order: Variant in wire.get("orders", []):
		if order is Dictionary and order.get("release_ids") is Dictionary:
			var releases: Array = []
			for identity: Variant in order.release_ids: releases.append([int(identity), int(order.release_ids[identity])])
			order.release_ids = releases
	if wire.get("reservations") is Dictionary:
		var reservations: Array = []
		for identity: Variant in wire.reservations:
			var reservation: Dictionary = wire.reservations[identity]
			reservation.person_id = int(identity)
			reservations.append(reservation)
		wire.reservations = reservations
	if wire.get("member_cursor") is Dictionary:
		var cursors: Array = []
		for group: Variant in wire.member_cursor: cursors.append([int(group), int(wire.member_cursor[group])])
		wire.member_cursor = cursors
	return wire

## Lift the party's exact record closure out of `state` (a detached copy).
## spec: {"person_id": controlled id, "actor_key": "player"/"npc"/"", "team_id": 0 or captained team}
## Whole-number float team and person ids of one army row become ints, in place.
static func _int_army_ids(army: Dictionary) -> void:
	var team: Variant = army.get("team_id")
	if team is float and is_finite(team) and team == floorf(team): army.team_id = int(team)
	for row: Dictionary in army.get("units", []):
		var person: Variant = row.get("person_id")
		if person is float and is_finite(person) and person == floorf(person): row.person_id = int(person)

## P4 S2 guard: a version 4 family identity cannot yet travel with a player party
## (the destination adopts no family registry for non-technology families, and the
## family registry is P6). Refused before anything is copied or changed.
static func family_departure_guard(state: Dictionary, controller: String) -> Dictionary:
	var family: Variant = state.get("family", {})
	if controller == "player" and family is Dictionary and int(family.get("version", 0)) == 4:
		return fail("RELATION_OPEN", "家族身分（v4）尚未能隨旅行移交；先保留在原地")
	return {"ok": true}

## P4 S2 guard: a settlement whose nation would leave the origin (every member of
## that equipment nation is a mover) would be left pointing at nothing. Partial
## departures keep the nation at origin and stay allowed.
static func settlement_nation_guard(state: Dictionary, movers: Dictionary) -> Dictionary:
	var settlement: Variant = state.get("settlement", {})
	var nation_id: Variant = settlement.get("nation_id") if settlement is Dictionary else null
	if not nation_id is String: return {"ok": true}
	var nations: Variant = state.get("equipment_nations", {})
	if not nations is Dictionary or not nations.has(nation_id): return {"ok": true}
	var nation: Variant = nations[nation_id]
	if not nation is Dictionary or not nation.get("members") is Array or nation.members.is_empty(): return {"ok": true}
	for member: Variant in nation.members:
		if not movers.has(int(member)): return {"ok": true}
	return fail("RELATION_OPEN", "聚落所屬國家會整國離開；先改派或解除聚落國家")

static func extract(state: Dictionary, spec: Dictionary, token: String) -> Dictionary:
	if state.has("crowd"): return fail("UNSUPPORTED", "群眾模式（Crowd）暫不支援整隊出發")
	if state.has("family"):
		var version := int(state.family.get("version", 0))
		if version not in [1, 2, 3, 4] or version != 3 and not Family.validate_family(state.family, str(state.get("id", ""))): return fail("INVALID_FAMILY", "必要原家族 schema 未准入")
	var p4_family_guard: Dictionary = family_departure_guard(state, str(spec.get("controller", "player")))
	if not p4_family_guard.ok: return p4_family_guard
	var family_transfer := {}
	var prepared := prepare_identity(state, str(spec.get("namespace", "")))
	if not prepared.ok: return prepared
	var origin: Dictionary = prepared.state
	origin.actor_presence_version = 1 # Explicit presence: the departed Actor is absent, never respawned.
	Runtime.initialize_item_storage(origin)
	for field: String in CONTENT_DICTS + ["captivity", "escort_orders", "housing", "ground_loot"]:
		if not origin.has(field): origin[field] = {}
	if not origin.has("armies"): origin.armies = []
	if int(spec.get("solo_actor", -1)) > 0:
		var detached := _detach_actor(origin, int(spec.solo_actor))
		if not detached.ok: return detached
	if int(spec.get("solo_row", -1)) > 0:
		var detached := _detach_row(origin, int(spec.solo_row))
		if not detached.ok: return detached
		spec = spec.duplicate()
		spec.team_id = int(detached.team_id)
		prepared = prepare_identity(origin)
		if not prepared.ok: return prepared
		origin = prepared.state
	var content := {"armies": [], "manual_cargo": {}, "fire_orders": [], "fire_member_cursor": [],
		"controlled_person_id": int(spec.get("person_id", -1)) if str(spec.get("controller", "player")) == "player" else -1, "army_trial_active": false, "counters": {}}
	for field: String in CONTENT_DICTS: content[field] = {}
	var movers := {}
	var inert_movers := {} # Decision A2: non-departing rows travelling inert with their container.
	var team_id := int(spec.get("team_id", 0))
	var sea := str(spec.get("mode", "land")) == "sea"
	var selected_teams := {}
	if team_id > 0: selected_teams[team_id] = true
	if spec.has("team_ids"):
		if not sea or not spec.team_ids is Array or spec.team_ids.is_empty(): return fail("INVALID_TEAM_CLOSURE", "多原隊容器只沿真船隊整閉包移交")
		for identity: Variant in spec.team_ids:
			if not identity is int or int(identity) <= 0: return fail("INVALID_TEAM_CLOSURE", "原隊編號須唯一正整數")
			selected_teams[int(identity)] = true
	var actor_key := str(spec.get("actor_key", ""))
	if not selected_teams.is_empty():
		var remaining: Array = []
		for army: Dictionary in origin.armies:
			if not selected_teams.has(int(army.get("team_id", 0))): remaining.append(army); continue
			if bool(army.get("crowd", false)) or not str(army.get("garrison_feature_id", "")).is_empty():
				return fail("RELATION_OPEN", "駐營或群眾隊伍不能整隊出發")
			if not army.get("rescues", []).is_empty(): return fail("BUSY", "隊伍仍在救助傷者")
			if int(army.get("combat_order", 0)) != 0: return fail("BUSY", "隊伍須先停在守位（取消移動、追擊、撤退）")
			for row: Dictionary in army.get("units", []):
				var independent := int(spec.get("solo_row", -1)) == int(row.person_id)
				if not independent and _row_inert(row):
					movers[int(row.person_id)] = true # Inert: travels with its container, unchanged.
					inert_movers[int(row.person_id)] = true
					continue
				var reason := _row_ready(row, independent, sea)
				if not reason.is_empty(): return fail("NOT_READY", reason)
				movers[int(row.person_id)] = true
			# A Site state read back from its saved JSON carries whole-number ids as
			# floats. The party owns int ids, so every later identity map and body index
			# sees the same key; a non-integral id stays as is for validation to refuse.
			_int_army_ids(army)
			content.armies.append(army)
			var member: Dictionary = army.get("player_member", {})
			if not member.is_empty(): movers[int(member.id)] = true
		if content.armies.size() != selected_teams.size(): return fail("NO_TARGET", "選定原隊容器缺失，拒絕部分船隊")
		origin.armies = remaining
	if not actor_key.is_empty():
		var actor: Dictionary = origin.actors.get(actor_key, {})
		if actor.is_empty() or int(actor.get("person_id", -1)) != int(spec.get("person_id", -1)):
			return fail("NO_TARGET", "受控人物不在此地")
		var reason := _actor_ready(actor)
		if not reason.is_empty(): return fail("NOT_READY", reason)
		movers[int(actor.person_id)] = true
	for army: Dictionary in content.armies:
		var member: Dictionary = army.get("player_member", {})
		if not member.is_empty():
			var found := false
			for key: String in origin.actors:
				if int(origin.actors[key].get("person_id", -1)) == int(member.id):
					found = key == actor_key
			if not found: return fail("RELATION_OPEN", "隊伍的玩家隊員必須與受控人物一起出發")
	if movers.is_empty(): return fail("NO_TARGET", "沒有可出發的人物")
	# Remaining people must not reference any mover.
	for actor: Dictionary in origin.actors.values():
		if movers.has(int(actor.get("attack_target", 0))) or movers.has(int(actor.get("rescue_target", 0))):
			return fail("RELATION_OPEN", "此地仍有人物攻擊或救助隊員")
	for army: Dictionary in origin.armies:
		if movers.has(int(army.get("player_member", {}).get("id", -1))): return fail("RELATION_OPEN", "受控人物仍是另一隊的隊員；請先退隊")
		if movers.has(int(army.get("pursuit_target", -1))): return fail("RELATION_OPEN", "此地仍有隊伍追擊隊員")
		for row: Dictionary in army.get("units", []):
			if movers.has(int(row.get("target", -1))): return fail("RELATION_OPEN", "此地仍有人物鎖定隊員")
		for rescue: Dictionary in army.get("rescues", []):
			if movers.has(int(rescue.get("target_id", -1))): return fail("RELATION_OPEN", "此地仍有人救助隊員")
	# Custody, escort and corps relations are never split across Sites.
	for key: String in origin.captivity:
		var relation: Dictionary = origin.captivity[key]
		if movers.has(int(key)) or movers.has(int(relation.get("captor_id", -1))) or movers.has(int(relation.get("guard_id", -1))):
			return fail("RELATION_OPEN", "拘押／看守關係須先結束才能出發")
	for key: String in origin.escort_orders:
		if movers.has(int(key)): return fail("RELATION_OPEN", "押送尚未結束")
		for identity: Variant in origin.escort_orders[key].get("captives", []):
			if movers.has(int(identity)): return fail("RELATION_OPEN", "押送尚未結束")
	var settlement_guard := settlement_nation_guard(origin, movers)
	if not settlement_guard.ok: return settlement_guard
	# Partial national/corps membership remains in its ORIGINAL organisation
	# owner. Only its immutable original-person/team references accompany us.
	var organization := SiteEquipmentOrders.prepare_region_departure(state, movers, selected_teams, token, origin.travel_identity)
	if not organization.ok: return organization
	origin.equipment_nations = organization.source_nations
	origin.corps = organization.source_corps
	origin.organization_refs = organization.source_refs
	content.equipment_nations = organization.moving_nations
	content.corps = organization.moving_corps
	content.organization_refs = organization.moving_refs
	# Leaving the Site vacates the movers' house slots (same as 離住).
	var vacated: Array = []
	for identity: int in movers:
		if origin.housing.has(str(identity)):
			origin.housing.erase(str(identity))
			vacated.append(identity)
	# Vehicles: the team's carts and wagons travel; ships/siege engines do not.
	var moving_vehicles := {}
	for identity: String in origin.vehicles.keys():
		var vehicle: Dictionary = origin.vehicles[identity]
		var owned: bool = selected_teams.has(int(vehicle.get("team_id", 0)))
		if not owned:
			if movers.has(int(vehicle.get("operator_id", 0))): return fail("RELATION_OPEN", "隊員仍在操作不屬本隊的車輛")
			for value: Variant in vehicle.get("crew_slots", {}).values():
				if movers.has(int(value)): return fail("RELATION_OPEN", "隊員仍在操作攻城器")
			continue
		if str(vehicle.get("kind", "")) not in (["ship"] if sea else ["cart", "wagon"]):
			return fail("UNSUPPORTED", "船隻與攻城器不隨陸路旅行；請先讓它們脫離本隊")
		if not vehicle.get("move", {}).is_empty() or bool(vehicle.get("stop_pending", false)) or not vehicle.get("action", {}).is_empty():
			return fail("BUSY", "車輛須先停穩")
		moving_vehicles[identity] = true
		content.vehicles[identity] = vehicle
		origin.vehicles.erase(identity)
	if sea:
		var bodies := _body_records(origin)
		bodies.merge(_body_records(content))
		for person: int in movers:
			if inert_movers.has(person): continue # S1: inert rows go with the container but onto no ship.
			if not bodies.has(person) or not moving_vehicles.has(str(bodies[person].get("embarked_vehicle_id", ""))): return fail("NOT_EMBARKED", "海路須先沿原登船 owner 讓旅隊全員上船")
	# Meal ledgers.
	for key: String in origin.person_supply.keys():
		var personal: Dictionary = origin.person_supply[key]
		var ids: Array[int] = Sustain._ids(personal)
		var mine := movers.has(int(key))
		for identity: int in ids:
			if mine != movers.has(identity): return fail("RELATION_OPEN", "私人餐份仍與留下的人共用")
		if mine:
			content.person_supply[key] = personal
			origin.person_supply.erase(key)
	for key: String in origin.team_supply.keys():
		var supply: Dictionary = origin.team_supply[key]
		var ids: Array[int] = Sustain._ids(supply.get("sustain", {}))
		var mine: bool = selected_teams.has(int(key))
		for identity: int in ids:
			if mine != movers.has(identity): return fail("RELATION_OPEN", "隊伍餐份仍與留下的人共用")
		if not mine: continue
		if not supply.get("delivery", {}).is_empty() or bool(supply.get("training_order", false)):
			return fail("BUSY", "交糧或訓練令尚未結束")
		if int(supply.get("version", 0)) == 3:
			for location: String in supply.get("locations", {}).keys():
				var carried := location.begins_with("vehicle:") and moving_vehicles.has(location.trim_prefix("vehicle:")) \
					or location.begins_with("person:") and movers.has(int(location.trim_prefix("person:")))
				if carried: continue
				var stock: Dictionary = supply.locations[location]
				if Runtime.inventory_size(stock.get("inventory", {})) > 0 or float(stock.get("open_rations", 0.0)) > 0.0:
					return fail("SHORE_STOCK", "隊伍共糧仍存放在據點；請先裝車或由隊員攜帶")
				supply.locations.erase(location)
		content.team_supply[key] = supply
		origin.team_supply.erase(key)
	# Carried items and their definitions.
	var holders := {}
	for identity: int in movers: holders["person:" + str(identity)] = true
	for identity: String in moving_vehicles: holders["vehicle:" + identity] = true
	var definitions := {}
	for key: String in origin.item_records.keys():
		var record: Dictionary = origin.item_records[key]
		if not holders.has(str(record.get("holder", ""))): continue
		content.item_records[key] = record
		definitions[str(record.get("definition", ""))] = true
		origin.item_records.erase(key)
	for key: String in definitions:
		if not origin.item_definitions.has(key): return fail("CORRUPT_SAVE", "攜帶物定義缺失")
		content.item_definitions[key] = origin.item_definitions[key].duplicate(true)
	for key: String in origin.ground_loot.keys():
		var loot: Dictionary = origin.ground_loot[key]
		if not moving_vehicles.has(str(loot.get("vehicle_id", ""))): continue
		content.ground_loot[key] = loot
		origin.ground_loot.erase(key)
		for item: String in origin.item_records.keys():
			if str(origin.item_records[item].get("holder", "")) != "ground:" + key: continue
			var record: Dictionary = origin.item_records[item]
			var definition := str(record.get("definition", ""))
			if not origin.item_definitions.has(definition): return fail("CORRUPT_SAVE", "攜行原遺物缺少定義")
			content.item_records[item] = record
			content.item_definitions[definition] = origin.item_definitions[definition].duplicate(true)
			origin.item_records.erase(item)
	# The controlled Actor and its hand cargo.
	if not actor_key.is_empty():
		content.actors[actor_key] = origin.actors[actor_key]
		origin.actors.erase(actor_key)
		var activity_key := "manual" if actor_key == "player" else "worker"
		var activity: Dictionary = origin.get(activity_key, {})
		if not str(activity.get("target", "")).is_empty() or float(activity.get("progress", 0.0)) != 0.0:
			return fail("BUSY", "人物工作尚未結束")
		content.manual_cargo = activity.get("cargo", {}).duplicate(true)
		if origin.has(activity_key): origin[activity_key].cargo = {}
		if actor_key == "npc": origin.worker_enabled = false
	# Fire command rows move with their team/person group.
	var groups := {}
	for identity: int in selected_teams: groups[identity] = true
	if not actor_key.is_empty(): groups[-int(spec.person_id)] = true
	var owners: Dictionary = origin.get("fire_owners", {})
	for group: int in groups:
		if group in owners.get("teams", []): return fail("BUSY", "火攻行動尚未收束")
	var raw_transport: Variant = origin.get("fire_transport", {})
	if raw_transport is Dictionary and not raw_transport.is_empty():
		var transport := wire_transport(raw_transport)
		if not transport.get("projectiles", []).is_empty() or not transport.get("reservations", []).is_empty():
			return fail("BUSY", "射擊飛行／準備尚未收束")
		var kept: Array = []
		for row: Dictionary in transport.get("orders", []):
			if groups.has(int(row.get("group", 0))): content.fire_orders.append(row)
			else: kept.append(row)
		transport.orders = kept
		var kept_cursors: Array = []
		for pair: Array in transport.get("member_cursor", []):
			if groups.has(int(pair[0])): content.fire_member_cursor.append(pair.duplicate())
			else: kept_cursors.append(pair)
		transport.member_cursor = kept_cursors
		origin.fire_transport = transport
		content.fire_template = transport.duplicate(true)
		content.fire_template.orders = []
		content.fire_template.member_cursor = []
	# Control passes to someone who stays, as after a ground crossing.
	if str(spec.get("controller", "player")) != "player" and movers.has(int(origin.get("controlled_person_id", -1))):
		return fail("PLAYER_CONTROL", "NPC 派遣不能移出原受控人物")
	if movers.has(int(origin.get("controlled_person_id", -1))):
		origin.erase("controlled_person_id")
		if not origin.actors.is_empty(): origin.controlled_person_id = int(origin.actors.values()[0].person_id)
	if origin.armies.is_empty(): origin.army_trial_active = false
	content.army_trial_active = not content.armies.is_empty()
	for field: String in ["next_person_id", "army_next_team", "next_vehicle", "next_item", "next_loot"]:
		content.counters[field] = int(origin.get(field, 1))
	content.travel_identity = origin.travel_identity.duplicate(true)
	# Existing refs retain their immutable birthplace. New original belongings
	# produced in transit use this one party's birthplace, so the source and
	# travelling allocator cannot mint the same stable lineage after departure.
	content.travel_identity.namespace = "travel:" + token
	content.travel_identity.next_sequence = 1
	if int(state.get("family", {}).get("version", 0)) == 3:
		var family_guard: Callable = spec.get("family_transfer_guard", Callable())
		if not family_guard.is_valid(): return fail("UNSUPPORTED_FAMILY_TRANSFER", "族科技 holder 尚未接同代旅行移交")
		var extraction_spec := spec.duplicate(true)
		extraction_spec.region_movers = movers.duplicate()
		extraction_spec.source_site_id = str(state.id)
		extraction_spec.transfer_token = token
		extraction_spec.travel_holder_site_id = "travel:" + token
		family_transfer = family_guard.call(state, extraction_spec)
		if not bool(family_transfer.get("ok", false)): return family_transfer
		if not family_transfer.get("source_family") is Dictionary or not family_transfer.get("moving_family") is Dictionary:
			return fail("INVALID_FAMILY_TRANSFER", "原族科技移交缺少 source／moving 同代候選")
		origin.family = family_transfer.source_family.duplicate(true)
	# A control registry follows only the player; NPCs carry their own references.
	if origin.has("family"):
		if str(spec.get("controller", "player")) == "player": content.family = family_transfer.moving_family.duplicate(true) if not family_transfer.is_empty() else origin.family.duplicate(true)
		else:
			var references: Array = []
			for member: Dictionary in origin.family.members:
				if str(member.site_id) == str(origin.id) and movers.has(int(member.person_id)): references.append(member.duplicate(true))
			if not references.is_empty():
				content.family_refs = {"reference": origin.travel_identity.refs.family.controlled.duplicate(true), "members": references}
				if not family_transfer.is_empty():
					var moving_family: Dictionary = family_transfer.moving_family
					if not Technology.is_holder_reference(moving_family.get("technology")): return fail("INVALID_FAMILY_TRANSFER", "NPC 只能攜帶原科技 holder 引用")
					content.family_refs.family_id = str(moving_family.family_id)
					content.family_refs.technology = moving_family.technology.duplicate(true)
		for member: Dictionary in origin.family.members:
			if str(member.site_id) == str(origin.id) and movers.has(int(member.person_id)):
				var old_key := JSON.stringify([str(member.site_id), int(member.person_id)])
				var reference: Dictionary = origin.travel_identity.family_members.get(old_key, {})
				member.site_id = "travel:" + token
				member.path = ""
				origin.travel_identity.family_members.erase(old_key)
				if not reference.is_empty(): origin.travel_identity.family_members[JSON.stringify([member.site_id, int(member.person_id)])] = reference
		# Both original registries describe current locations. Their stable
		# PersonRefs, explicit membership, labels and ages stay unchanged.
		var registry: Dictionary = content.get("family", content.get("family_refs", {}))
		for member: Dictionary in registry.get("members", []):
			if str(member.site_id) != str(origin.id) or not movers.has(int(member.person_id)): continue
			var old_key := JSON.stringify([str(member.site_id), int(member.person_id)])
			var reference: Dictionary = content.travel_identity.family_members.get(old_key, {})
			member.site_id = "travel:" + token
			member.path = ""
			content.travel_identity.family_members.erase(old_key)
			if not reference.is_empty(): content.travel_identity.family_members[JSON.stringify([member.site_id, int(member.person_id)])] = reference
		# Original automatic departure rule only vacates holders absent from
		# this exact owner; it does not appoint or copy a second local holder.
		if origin.family.get("offices") is Dictionary:
			var local := Family.member_ids(origin.family, str(origin.id))
			SiteOffices.vacate_unless(origin.family.offices, func(holder: int) -> bool: return local.has(holder))
		if content.get("family", {}).get("offices") is Dictionary:
			var local := Family.member_ids(content.family, "travel:" + token)
			SiteOffices.vacate_unless(content.family.offices, func(holder: int) -> bool: return local.has(holder))
	var people: Array = movers.keys()
	people.sort()
	var vehicles: Array = moving_vehicles.keys()
	vehicles.sort()
	var teams: Array = selected_teams.keys()
	teams.sort()
	if not sea:
		# A land party never moves while a carried cart/wagon lacks its driver;
		# refuse here instead of publishing a party that stays at distance 0.
		var gap := land_vehicle_operator_gap(content)
		if not gap.is_empty():
			return fail("VEHICLE_OPERATOR", "車輛 %s（%s）沒有可行動且未兼任的操作者；先指派操作者，或不帶此車出發" % [str(gap.vehicle_id), str(gap.kind)])
	var party := {"version": VERSION, "kind": "travel_party", "party_id": token, "controller": "player",
		"leader_person_id": int(spec.get("person_id", -1)), "person_ids": people,
		"team_ids": teams, "vehicle_ids": vehicles,
		"origin_site_id": str(origin.get("id", "")), "speed_mps": party_speed(content), "content": content}
	party.controller = str(spec.get("controller", "player"))
	party.mode = "sea" if sea else "land"
	var at := float(spec.get("game_seconds", state.get("simulation_settlement", {}).get("last_settled_game_seconds", 0.0)))
	party.upkeep = {"version": 1, "at": at, "resting": false, "carriers": {}, "events": [], "sequence": 0}
	_retain_identity(content)
	# The registry is a stable reference, including for an NPC's partial member list.
	if content.has("family_refs"): content.travel_identity.refs.family["controlled"] = content.family_refs.reference.duplicate(true)
	_retain_identity(origin)
	return {"ok": true, "origin": origin, "party": party, "vacated_housing": vacated}

## Inventory of everything a party carries, for conservation checks.
static func census(party: Dictionary) -> Dictionary:
	var content: Dictionary = party.get("content", {})
	var people: Array = []
	for army: Dictionary in content.get("armies", []):
		for row: Dictionary in army.get("units", []): people.append(int(row.person_id))
	for actor: Dictionary in content.get("actors", {}).values(): people.append(int(actor.person_id))
	people.sort()
	var items: Array = content.get("item_records", {}).keys()
	items.sort()
	var vehicles: Array = content.get("vehicles", {}).keys()
	vehicles.sort()
	return {"people": people, "items": items, "vehicles": vehicles}

## Shift the party's meal clocks across the trip (R1 stasis): coverage that
## remained at departure remains at arrival, capped at the next meal boundary.
static func rebase_clocks(content: Dictionary, departure_seconds: float, arrival_seconds: float) -> void:
	var shift := arrival_seconds - departure_seconds
	var ledgers: Array = []
	for supply: Dictionary in content.get("team_supply", {}).values(): ledgers.append(supply.get("sustain", {}))
	for personal: Dictionary in content.get("person_supply", {}).values(): ledgers.append(personal)
	for sustain: Dictionary in ledgers:
		if sustain.is_empty(): continue
		var old_at := float(sustain.get("at", departure_seconds))
		sustain.at = arrival_seconds
		for cohort: Dictionary in sustain.get("cohorts", []):
			var remaining := maxf(0.0, float(cohort.get("meal_until", old_at)) - old_at)
			cohort.meal_until = minf(arrival_seconds + remaining, Sustain._next_meal(arrival_seconds))
	if shift < 0.0: push_warning("Travel arrival precedes departure")

static func _free_cells(nav: TerrainData, state: Dictionary, entry: Vector2i) -> Dictionary:
	var occupied := {}
	for actor: Dictionary in state.get("actors", {}).values():
		occupied[Vector2i(int(actor.cell[0]), int(actor.cell[1]))] = true
	for army: Dictionary in state.get("armies", []):
		for row: Dictionary in army.get("units", []):
			if row.has("embarked_vehicle_id"): continue
			occupied[Vector2i(int(row.cell[0]), int(row.cell[1]))] = true
			var destination: Array = row.get("destination", [-1, -1])
			if int(destination[0]) >= 0: occupied[Vector2i(int(destination[0]), int(destination[1]))] = true
	for vehicle: Dictionary in state.get("vehicles", {}).values():
		for cell: Vector2i in SiteVehicleTransport.footprint(nav, vehicle): occupied[cell] = true
		for cell: Vector2i in SiteVehicleTransport.footprint(nav, vehicle, true): occupied[cell] = true
	var order: Array[Vector2i] = []
	if not nav.contains(entry) or not nav.is_walkable(entry):
		return {"order": order, "occupied": occupied}
	var seen := {entry: true}
	var queue: Array[Vector2i] = [entry]
	var head := 0
	while head < queue.size() and order.size() < 400:
		var cell := queue[head]
		head += 1
		if not occupied.has(cell): order.append(cell)
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if seen.has(next) or not nav.contains(next) or not nav.can_step(cell, next): continue
			seen[next] = true
			queue.append(next)
	return {"order": order, "occupied": occupied}

static func _place_actor(actor: Dictionary, cell: Vector2i) -> void:
	var at: Vector2 = (Vector2(cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	actor.cell = [cell.x, cell.y]
	actor.position = [at.x, at.y]
	actor.movement_from = actor.cell.duplicate()
	actor.movement_left = 0.0
	if actor.has("movement"):
		actor.movement.start = actor.position.duplicate()
		actor.movement.duration = 0.0
		actor.movement.elapsed = 0.0
	if actor.has("navigation"): actor.erase("navigation")

static func _settle_team(army: Dictionary, leader: Vector2i) -> void:
	army.combat_order = 0
	army.goal = [-1, -1]
	army.reference = [leader.x + 0.5, leader.y + 0.5]
	army.pursuit_target = -1
	army.pursuit_left = 0.0
	army.combat_batches = []
	for field: String in ["combat_deployment_plan", "combat_move_plan", "combat_absent_slots", "combat_batch_move_members",
		"combat_batch_retreat_members", "structure_waiting", "retreat_pairs_used", "retreat_resolution",
		"corps_reposition_source", "crowd_state", "crowd_source_sha256", "formation_change_pending"]:
		army.erase(field)

static func _sea_arrival(content: Dictionary, destination: Dictionary, nav: TerrainData, poses: Dictionary, leader_id: int) -> Dictionary:
	var occupied := {}
	for vehicle: Dictionary in destination.get("vehicles", {}).values():
		if str(vehicle.get("kind", "")) == "ship":
			for cell: Vector2i in Ship.footprint(str(vehicle.ship_type), nav.cell_from_index(int(vehicle.cell)), Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))): occupied[cell] = true
	for identity: String in content.vehicles:
		var vehicle: Dictionary = content.vehicles[identity]
		if str(vehicle.get("kind", "")) != "ship": return fail("MIXED_MODE", "海路到站須先沿原模式切換出口")
		var pose: Dictionary = poses.get(identity, {})
		var anchor := nav.cell_from_index(int(vehicle.cell)) if pose.is_empty() else Vector2i(int(pose.anchor[0]), int(pose.anchor[1]))
		var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1])) if pose.is_empty() else Vector2i(int(pose.facing[0]), int(pose.facing[1]))
		var footprint := Ship.footprint(str(vehicle.ship_type), anchor, facing)
		if footprint.is_empty(): return fail("INVALID_HULL", "原船體姿向無效")
		for cell: Vector2i in footprint:
			if not nav.can_navigate_water(cell) or occupied.has(cell): return fail("HULL_BLOCKED", "到站原船完整船體沒有合法水域或與原船重疊")
			occupied[cell] = true
		vehicle.cell = nav.index(anchor)
		vehicle.facing = [facing.x, facing.y]
		vehicle.move = {}
		vehicle.stop_pending = false
		vehicle.command = {}
		for loot: Dictionary in content.get("ground_loot", {}).values():
			if str(loot.get("vehicle_id", "")) == identity and loot.has("cell") and not loot.has("local_position"): loot.cell = int(vehicle.cell)
	var leader_cell := Vector2i(-1, -1)
	var inert := _inert_people(content, leader_id)
	for body: Dictionary in _body_records(content).values():
		if inert.has(int(body.person_id)): continue # S1: no ship, no position, fields unchanged.
		var boat: Dictionary = content.vehicles.get(str(body.get("embarked_vehicle_id", "")), {})
		if boat.is_empty(): return fail("NOT_EMBARKED", "原海路人物沒有原船引用")
		var berth := int(body.get("berth_id", -1))
		var local := Ship.local_position(str(boat.ship_type), berth)
		if not local.is_finite(): return fail("INVALID_BERTH", "原海路人物床位引用無效")
		var anchor := nav.cell_from_index(int(boat.cell))
		var facing := Vector2i(int(boat.facing[0]), int(boat.facing[1]))
		var cell := Ship.world_cell(anchor, facing, local)
		body.cell = [cell.x, cell.y]
		if body.has("slot"): body.slot = [cell.x, cell.y]
		if body.has("destination"): body.destination = [-1, -1]
		if body.has("progress"): body.progress = 0.0
		if body.has("previous"): body.previous = []
		if int(body.person_id) == leader_id: leader_cell = cell
	if leader_cell == Vector2i(-1, -1): return fail("NO_TARGET", "原船受控人物不在旅隊")
	for army: Dictionary in content.armies: _settle_team(army, leader_cell)
	return {"ok": true, "leader_cell": leader_cell}

## Merge the party into a destination state at `entry` (a local edge cell).
## `nav` is the destination TerrainData (with its buildings) used for placement.
static func insert(destination_state: Dictionary, party: Dictionary, nav: TerrainData, entry: Vector2i,
		destination_path: String, departure_seconds: float, arrival_seconds: float, options: Dictionary = {}) -> Dictionary:
	if party.get("content", {}).has("family"):
		var version := int(party.content.family.get("version", 0))
		if version not in [1, 2, 3, 4] or version != 3 and not Family.validate_family(party.content.family, str(party.get("origin_site_id", ""))): return fail("INVALID_FAMILY", "旅隊必要原家族 schema 未准入")
	var original_party := party
	var remapped := prepare_arrival(destination_state, party, int(options.get("generation", 0)))
	if not remapped.ok: return remapped
	party = remapped.party
	var destination: Dictionary = remapped.state
	var technology_transfer: bool = int(original_party.get("content", {}).get("family", {}).get("version", 0)) == 3 \
		or original_party.get("content", {}).get("family_refs", {}).has("technology")
	if technology_transfer:
		var family_guard: Callable = options.get("family_transfer_guard", Callable())
		if not family_guard.is_valid(): return fail("UNSUPPORTED_FAMILY_TRANSFER", "族科技 holder 尚未接同代到站移交")
		# The original technology holder receives current-reference ID mapping;
		# immutable paid/attempt receipts remain untouched by RegionTravel.
		var admitted: Dictionary = family_guard.call(destination_state, party)
		if not bool(admitted.get("ok", false)): return admitted
		if not admitted.get("destination_family") is Dictionary:
			return fail("INVALID_FAMILY_TRANSFER", "原族科技移交缺少 destination 同代候選")
		if str(party.get("controller", "player")) == "player":
			destination.family = admitted.destination_family.duplicate(true)
			destination.travel_identity.refs.family["controlled"] = original_party.content.travel_identity.refs.family.controlled.duplicate(true)
		elif admitted.destination_family != destination_state.get("family", {}):
			return fail("NPC_FAMILY_AUTHORITY", "NPC 科技引用到站不能改寫原受控家族 holder")
	if destination.has("crowd"): return fail("UNSUPPORTED", "目的地群眾容器不接收 R1 旅隊")
	var content: Dictionary = party.content.duplicate(true)
	destination.actor_presence_version = 1
	Runtime.initialize_item_storage(destination)
	for field: String in CONTENT_DICTS + ["captivity", "escort_orders"]:
		if not destination.has(field): destination[field] = {}
	if not destination.has("armies"): destination.armies = []
	# Local collisions are already mapped; this is now a genuine owner conflict.
	var present := {}
	for actor: Dictionary in destination.actors.values(): present[int(actor.person_id)] = true
	for army: Dictionary in destination.armies:
		for row: Dictionary in army.get("units", []): present[int(row.person_id)] = true
		for incoming: Dictionary in content.armies:
			if int(army.team_id) == int(incoming.team_id): return fail("ID_CONFLICT", "目的地已有同一原隊伍編號")
	for identity: Variant in party.person_ids:
		if present.has(int(identity)): return fail("ID_CONFLICT", "目的地已有同一原人物")
	for field: String in CONTENT_DICTS:
		for key: String in content.get(field, {}):
			if field == "item_definitions":
				if destination[field].has(key) and destination[field][key] != content[field][key]:
					return fail("ID_CONFLICT", "物品定義同 ID 內容不同")
			elif destination[field].has(key):
				return fail("ID_CONFLICT", "目的地已有同一原紀錄：%s %s" % [field, key])
	var patients := validate_patients(content)
	if not patients.ok: return patients
	var policy := RegionRoute.travel_policy(nav, options.get("resource_cover", PackedByteArray()))
	if not policy.ok: return policy
	for vehicle: Dictionary in content.vehicles.values():
		var admitted := RegionRoute.vehicle_entry_policy(policy, str(vehicle.get("kind", "")))
		if not admitted.ok: return admitted
	var leader_cell := Vector2i(-1, -1)
	if options.has("contact_frame"):
		if str(party.get("controller", "")) != "npc" or str(party.get("mode", "land")) != "land" or not options.get("contact_source") is Dictionary or not options.get("contact_frame") is Dictionary: return fail("CONTACT_FOOT_UNSUPPORTED", "Original NPC foot contact closure required")
		var frame: Dictionary = options.contact_frame
		if frame.get("game_seconds") != arrival_seconds or frame.get("size") != [100, 100] or not frame.get("action_seconds") is float or not is_finite(float(frame.action_seconds)) or float(frame.action_seconds) < 0.0: return fail("CONTACT_FOOT_UNPLACED", "Original contact frame clock or bounds changed")
		var projected := project_party_frame(options.contact_source, frame)
		if not projected.ok: return projected
		if var_to_bytes(projected.party) != var_to_bytes(original_party): return fail("CONTACT_FOOT_UNPLACED", "Contact must preserve the complete original projection")
		var exact := _region_contact_land_placement(content, destination, nav, entry, int(party.leader_person_id))
		if not exact.ok: return exact
		leader_cell = exact.leader_cell
	elif str(party.get("mode", "land")) == "sea":
		var poses := {}
		for old: String in options.get("vehicle_poses", {}): poses[str(_mapped(old, "vehicle", remapped.mapping.maps))] = options.vehicle_poses[old]
		var sea := _sea_arrival(content, destination, nav, poses, int(party.leader_person_id))
		if not sea.ok: return sea
		leader_cell = sea.leader_cell
	else:
		# Placement next to the entry pass, inside the actual destination Site.
		var free := _free_cells(nav, destination, entry)
		var cells: Array[Vector2i] = free.order
		var used := {}
		var cursor := 0
		var people_needed := 0
		for army: Dictionary in content.armies: people_needed += army.units.size()
		people_needed += content.actors.size()
		if cells.size() < people_needed: return fail("NO_SPACE", "目的地入口附近沒有足夠的可站位置")
		leader_cell = cells[0]
		for key: String in content.actors:
			var actor: Dictionary = content.actors[key]
			_place_actor(actor, cells[cursor])
			used[cells[cursor]] = true
			if int(actor.person_id) == int(party.leader_person_id): leader_cell = cells[cursor]
			cursor += 1
		var inert := _inert_people(content, int(party.leader_person_id))
		for army: Dictionary in content.armies:
			for row: Dictionary in army.units:
				# A settled dead row has no body: like on a sea leg it gets no position.
				# Discharged (alive) inert rows still walk in with their team.
				if inert.has(int(row.person_id)) and float(row.get("hp", 0.0)) <= 0.0: continue
				var cell := cells[cursor]
				cursor += 1
				used[cell] = true
				row.cell = [cell.x, cell.y]
				row.slot = [cell.x, cell.y]
				row.destination = [-1, -1]
				row.progress = 0.0
				row.previous = []
				row.target = -1
				row.hits = []
				if int(row.person_id) == int(party.leader_person_id): leader_cell = cell
			_settle_team(army, leader_cell)
			if not army.get("player_member", {}).is_empty():
				army.player_member.goal = [leader_cell.x, leader_cell.y]
		var blocked: Dictionary = free.occupied.duplicate()
		blocked.merge(used)
		for identity: String in content.vehicles:
			var vehicle: Dictionary = content.vehicles[identity]
			var length := int(SiteVehicleTransport.LENGTH.get(str(vehicle.kind), 1))
			var chosen := false
			for anchor: Vector2i in cells:
				if blocked.has(anchor): continue
				for facing: Vector2i in TerrainData.DIRECTIONS:
					var footprint: Array[Vector2i] = []
					var fits := true
					for step: int in range(length):
						var cell := anchor + facing * step
						if not nav.contains(cell) or not nav.is_walkable(cell) or blocked.has(cell) \
								or step > 0 and not nav.can_step(footprint.back(), cell):
							fits = false
							break
						footprint.append(cell)
					if not fits: continue
					vehicle.cell = nav.index(anchor)
					vehicle.facing = [facing.x, facing.y]
					for cell: Vector2i in footprint: blocked[cell] = true
					chosen = true
					break
				if chosen: break
			if not chosen: return fail("NO_SPACE", "目的地入口附近沒有足夠空間停放車輛")
			vehicle.move = {}
			vehicle.operator_id = 0
			vehicle.stop_pending = false
			# Attached ground containers remain the original holder at the new anchor.
			for loot: Dictionary in content.get("ground_loot", {}).values():
				if str(loot.get("attached_vehicle_id", loot.get("vehicle_id", ""))) == identity: loot.cell = int(vehicle.cell)
			# Patients retain their body rows; their effective position is the vehicle.
			for patient: Variant in vehicle.get("travel_patients", {}).get("person_ids", []):
				var body: Dictionary = _body_records(content)[int(patient)]
				var anchor := nav.cell_from_index(int(vehicle.cell))
				body.cell = [anchor.x, anchor.y]
				if body.has("slot"): body.slot = [anchor.x, anchor.y]
	if not party.has("upkeep") or absf(float(party.upkeep.get("at", -1.0)) - arrival_seconds) > EPS:
		return fail("UNSETTLED_PARTY", "旅隊原供養／生命尚未結算至到站端點")
	# Merge every record into the destination.
	destination.armies.append_array(content.armies)
	for field: String in CONTENT_DICTS:
		for key: String in content.get(field, {}):
			destination[field][key] = content[field][key]
	if content.actors.has("player"):
		destination.player_cell = nav.index(Vector2i(int(content.actors.player.cell[0]), int(content.actors.player.cell[1])))
		if Runtime.inventory_size(destination.get("manual", {}).get("cargo", {})) != 0:
			return fail("RELATION_OPEN", "目的地玩家容器仍有無主貨物")
		if destination.has("manual"): destination.manual.cargo = content.manual_cargo.duplicate(true)
	elif content.actors.has("npc"):
		if Runtime.inventory_size(destination.get("worker", {}).get("cargo", {})) != 0:
			return fail("RELATION_OPEN", "目的地工人容器仍有無主貨物")
		if destination.has("worker"):
			destination.worker.cargo = content.manual_cargo.duplicate(true)
			destination.worker.cell = nav.index(Vector2i(int(content.actors.npc.cell[0]), int(content.actors.npc.cell[1])))
	if bool(content.get("army_trial_active", false)): destination.army_trial_active = true
	for field: String in content.get("counters", {}):
		destination[field] = maxi(int(destination.get(field, 1)), int(content.counters[field]))
	for identity: Variant in party.person_ids:
		destination.next_person_id = maxi(int(destination.get("next_person_id", 1)), int(identity) + 1)
	if str(party.get("controller", "player")) == "player" and int(content.get("controlled_person_id", -1)) > 0: destination.controlled_person_id = int(content.controlled_person_id)
	# Fire command rows.
	if not content.get("fire_orders", []).is_empty() or not content.get("fire_member_cursor", []).is_empty():
		var target: Dictionary = wire_transport(destination.get("fire_transport", {})) if destination.get("fire_transport") is Dictionary else {}
		if target.is_empty():
			target = content.get("fire_template", {}).duplicate(true)
			target.orders = []
			target.member_cursor = []
			target.projectiles = []
			target.reservations = []
			target.round_robin = 0
			var settlement: Dictionary = destination.get("fire_settlement", {})
			if settlement.has("action_seconds"): target.action_cursor = float(settlement.action_seconds)
		var incoming_groups := {}
		for incoming: Dictionary in content.fire_orders: incoming_groups[int(incoming.get("group", 0))] = true
		var kept_orders: Array = []
		for row: Dictionary in target.orders:
			if not incoming_groups.has(int(row.get("group", 0))):
				kept_orders.append(row)
			elif bool(row.get("enabled", false)) or not row.get("target", {}).is_empty():
				return fail("ID_CONFLICT", "目的地已有同一火攻命令")
			# else: a disabled placeholder for the absent owner; the owner's own row replaces it.
		var kept_cursors: Array = []
		for pair: Variant in target.member_cursor:
			if pair is Array and pair.size() == 2 and incoming_groups.has(int(pair[0])): continue
			kept_cursors.append(pair)
		target.orders = kept_orders
		target.member_cursor = kept_cursors
		target.orders.append_array(content.fire_orders)
		target.member_cursor.append_array(content.fire_member_cursor)
		# Same JSON projection as a saved transport (runtime int keys become strings).
		destination.fire_transport = JSON.parse_string(JSON.stringify(target, "", true, true))
	var family_sync := sync_family(destination, original_party, remapped.mapping, destination_path)
	if not family_sync.ok: return family_sync
	var organization := SiteEquipmentOrders.prepare_region_arrival(destination, original_party.content.get("organization_refs", SiteEquipmentOrders._portable_empty()),
		original_party.content.travel_identity, remapped.mapping)
	if not organization.ok: return organization
	destination.organization_refs = organization.organization_refs
	_retain_identity(destination)
	return {"ok": true, "state": destination, "leader_cell": leader_cell, "leader_person_id": int(party.leader_person_id), "mapping": remapped.mapping}


static func sync_family(destination: Dictionary, party: Dictionary, mapping: Dictionary, destination_path: String) -> Dictionary:
	var content: Dictionary = party.content
	var incoming_ref: Dictionary = content.get("travel_identity", {}).get("refs", {}).get("family", {}).get("controlled", {})
	var destination_ref: Dictionary = destination.get("travel_identity", {}).get("refs", {}).get("family", {}).get("controlled", {})
	var incoming: Dictionary = content.get("family", {})
	var references: Array = incoming.get("members", content.get("family_refs", {}).get("members", []))
	if incoming_ref.is_empty() or references.is_empty(): return {"ok": true}
	var player := str(party.get("controller", "player")) == "player"
	var same := not destination_ref.is_empty() and stable_key(incoming_ref) == stable_key(destination_ref)
	if not same and not destination_ref.is_empty():
		return fail("DIFFERENT_FAMILY", "目的地另一家族須先沿原控制／家族 owner 接續") if player else {"ok": true}
	if not same and not player: return {"ok": true}
	var family: Dictionary = destination.family.duplicate(true) if same else incoming.duplicate(true)
	if family.is_empty(): return fail("INVALID_FAMILY", "原家族控制名冊缺失")
	var entries := {}
	for reference: Dictionary in family.members: entries[JSON.stringify([reference.site_id, int(reference.person_id)])] = reference.duplicate(true)
	var incoming_index: Dictionary = content.get("travel_identity", {}).get("family_members", {})
	var destination_index: Dictionary = destination.travel_identity.get("family_members", {}).duplicate(true)
	for reference: Dictionary in references:
		var copy := reference.duplicate(true)
		var old_key := JSON.stringify([str(copy.site_id), int(copy.person_id)])
		var stable: Dictionary = incoming_index.get(old_key, {})
		var current_person := int(_mapped(int(copy.person_id), "person", mapping.maps))
		var moving: bool = (int(copy.person_id) in party.person_ids or current_person in party.person_ids) \
			and str(copy.site_id) in [str(party.origin_site_id), "travel:" + str(party.party_id)]
		if moving:
			if stable.is_empty(): return fail("INVALID_FAMILY_REF", "移動家人缺少原穩定人物引用")
			for existing: String in destination_index.keys():
				if stable_key(destination_index[existing]) == stable_key(stable):
					entries.erase(existing)
					destination_index.erase(existing)
			entries.erase(old_key)
			copy.person_id = int(_mapped(copy.person_id, "person", mapping.maps))
			copy.site_id = str(destination.id)
			copy.path = destination_path
		var key := JSON.stringify([str(copy.site_id), int(copy.person_id)])
		if moving or not entries.has(key): entries[key] = copy
		if not stable.is_empty(): destination_index[key] = stable
	family.members = entries.values()
	destination.travel_identity.family_members = destination_index
	if not same:
		for seat: Dictionary in family.get("offices", {}).get("positions", []):
			if int(seat.get("holder", -1)) in party.person_ids: seat.holder = int(_mapped(seat.holder, "person", mapping.maps))
		destination.travel_identity.refs.family["controlled"] = incoming_ref.duplicate(true)
	destination.family = family
	return {"ok": true}


static func _region_contact_land_placement(content: Dictionary, destination: Dictionary, nav: TerrainData, entry: Vector2i, leader_id: int) -> Dictionary:
	if not content.get("actors", {}).is_empty() or not content.get("vehicles", {}).is_empty(): return fail("CONTACT_FOOT_UNSUPPORTED", "Vehicles and actors retain their original complete frame lane")
	if nav == null or not nav.contains(entry) or not nav.is_walkable(entry): return fail("CONTACT_FOOT_UNPLACED", "Accepted entry is currently blocked")
	var free := _free_cells(nav, destination, entry)
	var occupied: Dictionary = free.occupied
	var used := {}
	var leader_cell := Vector2i(-1, -1)
	for army: Dictionary in content.get("armies", []):
		for row: Dictionary in army.get("units", []):
			if row.has("embarked_vehicle_id") or not _frame_pair(row.get("cell")) or not _frame_pair(row.get("slot")): return fail("CONTACT_FOOT_UNSUPPORTED", "Original complete foot row required")
			var cell := Vector2i(int(row.cell[0]), int(row.cell[1]))
			var slot := Vector2i(int(row.slot[0]), int(row.slot[1]))
			if not nav.contains(cell) or not nav.is_walkable(cell) or not nav.contains(slot) or not nav.is_walkable(slot) or occupied.has(cell) or used.has(cell): return fail("CONTACT_FOOT_UNPLACED", "Original formation cannot be relocated to force contact")
			used[cell] = true
			if int(row.person_id) == leader_id: leader_cell = cell
	if leader_cell != entry or used.is_empty(): return fail("CONTACT_FOOT_UNPLACED", "Actual leader must retain the exact accepted entry")
	return {"ok": true, "leader_cell": leader_cell}
