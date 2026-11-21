extends SceneTree
## Pure original-owner travel contracts. Slot/bind/fault publication is covered
## by the separate snapshot/clock/lifecycle tests; this test creates no Site save.

const Travel = preload("res://scripts/region_lab/region_travel.gd")
const Route = preload("res://scripts/region_lab/region_route.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const Ships = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
var checks := 0
var failures: Array[String] = []

class FixtureSource:
	extends RegionData
	var builds := 0
	var terrain: TerrainData
	func make_terrain_data(_x: int, _y: int) -> Dictionary:
		builds += 1
		return {"ok": true, "data": terrain}
	func site_resource_cover(_site: Vector2i) -> Dictionary:
		var cover := PackedByteArray()
		cover.resize(100)
		cover.fill(2)
		return {"ok": true, "cover": cover}

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("REGION_GAMEPLAY_TRAVEL_FAIL: " + message)

func _close(a: float, b: float, epsilon: float = 0.000001) -> bool:
	return absf(a - b) <= epsilon

func _body(identity: int, ko: float = 0.0) -> Dictionary:
	return {"person_id": identity, "hp": 100.0, "ko": ko, "member": true,
		"captive": false, "departed": false, "fatigue": 0.0, "fatigue_rest": 0.0,
		"cargo": {}, "item_state": Travel.Runtime.new_item_state("person:%d" % identity),
		"cell": [50 + identity, 50], "pose": "unconscious" if ko > 0.0 else "idle"}

func _state(site: String, identity_namespace: String, offset: int = 0) -> Dictionary:
	var local := 1 + offset
	var state := {"id": site, "next_person_id": local + 1, "army_next_team": local + 1,
		"next_vehicle": local + 1, "next_item": local + 1, "next_loot": local + 1,
		"actors": {}, "armies": [{"team_id": local, "faction_id": 0, "units": [_body(local)]}],
		"vehicles": {str(local): {"id": str(local), "team_id": local, "operator_id": local,
			"kind": "cart", "cell": 5050, "facing": [1, 0], "cargo": {},
			"holder": {"version": 1, "holder": "vehicle:" + str(local), "equipped": {}, "item_ids": [str(local)]}}},
		"item_records": {str(local): {"id": str(local), "holder": "vehicle:" + str(local), "definition": "token", "original_owner": local}},
		"item_definitions": {"token": {"id": "token"}}, "ground_loot": {},
		"team_supply": {}, "person_supply": {}, "equipment_nations": {}, "corps": {},
		"controlled_person_id": local}
	return Travel.prepare_identity(state, identity_namespace).state

func _party(state: Dictionary, token: String = "travel_test") -> Dictionary:
	var local := int(state.armies[0].units[0].person_id)
	var content := state.duplicate(true)
	content.counters = {"next_person_id": local + 1, "army_next_team": local + 1, "next_vehicle": local + 1, "next_item": local + 1, "next_loot": local + 1}
	return {"version": Travel.VERSION, "kind": "travel_party", "party_id": token,
		"controller": "player", "leader_person_id": local, "person_ids": [local],
		"team_ids": [int(state.armies[0].team_id)], "vehicle_ids": state.vehicles.keys(),
		"origin_site_id": state.id, "content": content, "mode": "land",
		"upkeep": {"version": 1, "at": 0.0, "resting": false, "carriers": {}, "events": [], "sequence": 0}}

func _identity_contract() -> void:
	var a := _state("A", "world:creation:A")
	var b := _state("B", "world:creation:B")
	var c := _state("C", "world:creation:C")
	_check(Travel.validate_identity(a.travel_identity), "Original identity schema")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(a.travel_identity))
	_check(Travel.validate_identity(decoded), "Strict identity admits exact integer JSON floats")
	var normalized := Travel.normalize_identity(decoded)
	_check(normalized.version is int and normalized.next_sequence is int and normalized.refs.person["1"].lineage is int,
		"Validated JSON identity canonicalizes only metadata integer fields")
	_check(Travel.stable_key(decoded.refs.person["1"]) == Travel.stable_key(a.travel_identity.refs.person["1"]),
		"Stable reference key is identical before and after JSON integer decoding")
	var bad_json := decoded.duplicate(true)
	bad_json.refs.person["1"].lineage = 1.5
	_check(not Travel.validate_identity(bad_json) and Travel.normalize_identity(bad_json).is_empty(), "Fractional lineage is never coerced into an identity")
	bad_json = decoded.duplicate(true)
	bad_json.next_sequence = INF
	_check(not Travel.validate_identity(bad_json), "Infinite JSON allocator is rejected")
	bad_json.next_sequence = NAN
	_check(not Travel.validate_identity(bad_json), "NaN allocator is rejected")
	bad_json = decoded.duplicate(true)
	bad_json.next_sequence = "2"
	_check(not Travel.validate_identity(bad_json), "String allocator is rejected before normalization")
	bad_json = decoded.duplicate(true)
	bad_json.unknown_field = true
	_check(not Travel.validate_identity(bad_json), "Unknown identity schema field is rejected")
	bad_json = decoded.duplicate(true)
	bad_json.refs.person["1"].unknown_field = true
	_check(not Travel.validate_identity(bad_json), "Unknown typed reference schema field is rejected")
	decoded.family_members = {"[\"A\",1.0]": decoded.refs.person["1"].duplicate(true)}
	_check(Travel.validate_identity(decoded) and Travel.normalize_identity(decoded).family_members.has(JSON.stringify(["A", 1])),
		"Family location JSON integer floats normalize without minting a person")
	decoded.family_members["[\"A\",1]"] = {"type": "person", "namespace": "other", "lineage": 8.0}
	_check(not Travel.validate_identity(decoded), "Two numeric spellings of one family location cannot claim two identities")
	_check(Travel.stable_key(a.travel_identity.refs.person["1"]) != Travel.stable_key(b.travel_identity.refs.person["1"]), "Same local person number from two origins remains distinct")
	_check(Travel.stable_key(b.travel_identity.refs.person["1"]) != Travel.stable_key(c.travel_identity.refs.person["1"]), "Third origin remains distinct")
	var split := Travel.extract(a, {"person_id": 1, "team_id": 1, "namespace": "world:creation:A"}, "birth_split")
	_check(split.ok, "Original source and travelling owner form a closed allocator split")
	if split.ok:
		var source_new: Dictionary = split.origin.duplicate(true)
		var transit_new: Dictionary = split.party.content.duplicate(true)
		source_new.ground_loot["99"] = {}
		transit_new.ground_loot["99"] = {}
		source_new = Travel.prepare_identity(source_new).state
		transit_new = Travel.prepare_identity(transit_new).state
		_check(Travel.stable_key(source_new.travel_identity.refs.loot["99"]) != Travel.stable_key(transit_new.travel_identity.refs.loot["99"]),
			"New original belongings produced at source and in transit cannot share a stable birthplace")
	var source_hash := JSON.stringify(a)
	var destination_hash := JSON.stringify(b)
	var party := _party(a)
	party.content.receipts = [{"person_id": 1, "vehicle_id": "1"}]
	var prepared := Travel.prepare_arrival(b, party, 4)
	_check(prepared.ok, "Colliding destination accepts original closure through remapping")
	if not prepared.ok: return
	_check(JSON.stringify(a) == source_hash and JSON.stringify(b) == destination_hash, "Arrival preflight is detached")
	var moved: Dictionary = prepared.party
	var person := int(prepared.mapping.maps.person["1"])
	var team := int(prepared.mapping.maps.team["1"])
	var vehicle := str(prepared.mapping.maps.vehicle["1"])
	var item := str(prepared.mapping.maps.item["1"])
	_check(person != 1 and team != 1 and vehicle != "1" and item != "1", "Every collided original owner obtains a free local number")
	_check(int(moved.content.armies[0].units[0].person_id) == person and int(moved.content.vehicles[vehicle].operator_id) == person, "Body and operator current references remap together")
	_check(int(moved.content.vehicles[vehicle].team_id) == team and moved.content.item_records[item].holder == "vehicle:" + vehicle, "Team and inventory holder references remap together")
	_check(moved.content.vehicles[vehicle].holder.item_ids == [item], "Original holder item membership remaps")
	_check(int(moved.content.item_records[item].original_owner) == 1 and int(moved.content.receipts[0].person_id) == 1, "Immutable provenance and historical receipts remain historical")
	_check(Travel.stable_key(moved.content.travel_identity.refs.person[str(person)]) == Travel.stable_key(a.travel_identity.refs.person["1"]), "Stable identity survives local number remapping")
	_check(Travel.validate_arrival_mapping(prepared.mapping), "Arrival receipt carries all typed original-to-current injective maps")
	var malformed: Dictionary = prepared.mapping.duplicate(true)
	malformed.maps.person["99"] = malformed.maps.person["1"]
	_check(not Travel.validate_arrival_mapping(malformed), "Two original people cannot merge into one local arrival target")
	var retry := Travel.prepare_arrival(b, moved, 5)
	_check(retry.ok, "Retry against unchanged destination reuses mapping")
	if retry.ok:
		_check(int(retry.party.leader_person_id) == person, "Retry preserves reserved person number")
		_check(retry.mapping.maps.person.has("1") and int(retry.mapping.maps.person["1"]) == person,
			"Retry keeps original-to-current receipt keys for original technology/family history")
	var reserved := b.duplicate(true)
	reserved.armies.append({"team_id": 7, "units": [_body(person)]})
	reserved.next_person_id = person + 1
	reserved = Travel.prepare_identity(reserved).state
	var stale := Travel.prepare_arrival(reserved, party.merged({"arrival_mapping": prepared.mapping}, true))
	_check(not stale.ok and stale.code == "STALE_MAPPING", "Occupied reservation refuses stale mapping")
	var duplicate := Travel.prepare_arrival(a, party)
	_check(not duplicate.ok and duplicate.code == "DUPLICATE_OWNER", "One stable asset cannot exist in Site and party simultaneously")
	var extracted := a.duplicate(true)
	extracted.armies = []
	extracted.vehicles = {}
	extracted.item_records = {}
	Travel._retain_identity(extracted)
	var returned := Travel.prepare_arrival(extracted, moved)
	_check(not returned.ok and returned.code == "STALE_MAPPING", "Old destination receipt cannot silently redirect a returning party")
	moved.erase("arrival_mapping")
	returned = Travel.prepare_arrival(extracted, moved)
	_check(returned.ok, "Fresh returning leg preserves original lineage")
	if returned.ok: _check(Travel.stable_key(returned.party.content.travel_identity.refs.person[str(returned.party.leader_person_id)]) == Travel.stable_key(a.travel_identity.refs.person["1"]), "Return does not mint another person")

func _family_contract() -> void:
	var source := _state("A", "world:creation:A")
	var member := {"site_id": "A", "path": "", "person_id": 1, "label": "A", "age_years": 30}
	source.family = {"version": 1, "complete": true, "members": [member]}
	source = Travel.prepare_identity(source).state
	var party := _party(source, "family_trip")
	var target := _state("B", "world:creation:B", 5)
	target.family = {"version": 1, "complete": true, "members": [{"site_id": "B", "path": "", "person_id": 6, "label": "B", "age_years": 30}]}
	target = Travel.prepare_identity(target).state
	var before := JSON.stringify(target.family)
	party.controller = "npc"
	var result := Travel.sync_family(target, party, {"maps": {"person": {"1": "7"}}}, "B.tsite")
	_check(result.ok and JSON.stringify(target.family) == before, "NPC admission preserves unrelated controlled-family registry")
	party.controller = "player"
	result = Travel.sync_family(target, party, {"maps": {"person": {"1": "7"}}}, "B.tsite")
	_check(not result.ok and result.code == "DIFFERENT_FAMILY", "Player cannot replace unrelated family authority")
	target.family = source.family.duplicate(true)
	target.family.members[0].site_id = "travel:family_trip"
	target.travel_identity.refs.family.controlled = source.travel_identity.refs.family.controlled.duplicate(true)
	target.travel_identity.family_members = {JSON.stringify(["travel:family_trip", 1]): source.travel_identity.refs.person["1"].duplicate(true)}
	result = Travel.sync_family(target, party, {"maps": {"person": {"1": "7"}}}, "B.tsite")
	_check(result.ok and target.family.members.size() == 1, "Same FamilyRef replaces prior travel location by stable PersonRef")
	if result.ok: _check(int(target.family.members[0].person_id) == 7 and target.family.members[0].site_id == "B", "Family reference uses arriving local number and exact Site")
	var future := source.duplicate(true)
	future.family.version = 3
	var denied := Travel.extract(future, {"person_id": 1, "team_id": 1, "namespace": "world:creation:A"}, "missing_tech_guard")
	_check(not denied.ok and denied.code == "UNSUPPORTED_FAMILY_TRANSFER", "Technology family needs original same-epoch transfer guard")

func _upkeep_party(awake: int, downed: int = 0) -> Dictionary:
	var rows: Array = []
	var members := {}
	var ids: Array[int] = []
	for index: int in range(awake + downed):
		var row := _body(index + 1, 999999.0 if index >= awake else 0.0)
		rows.append(row)
		ids.append(index + 1)
		members[index + 1] = {"hp": 100.0, "ko": row.ko, "captive": false, "present": true}
	var sustain := Sustain.create()
	Sustain.add_members(sustain, members, ids)
	return {"version": Travel.VERSION, "party_id": "upkeep", "controller": "player", "person_ids": ids,
		"content": {"controlled_person_id": 1, "actors": {}, "armies": [{"team_id": 1, "units": rows,
			"team_fatigue": {"fatigue": 29.0, "fatigue_rest": 0.0, "active": false}}],
			"vehicles": {}, "item_records": {}, "person_supply": {},
			"team_supply": {"1": {"version": 1, "revision": 0, "inventory": {"grain": 10000}, "sustain": sustain}}},
		"upkeep": {"version": 1, "at": 0.0, "resting": false, "carriers": {}, "events": [], "sequence": 0}}

func _transport_contract() -> void:
	var party := _upkeep_party(1, 1)
	var one := Travel.prepare_transport(party)
	_check(one.ok and not one.can_move, "One awake person cannot carry one unconscious original body")
	party = _upkeep_party(3, 2)
	var three := Travel.prepare_transport(party)
	_check(three.ok and not three.can_move and three.carriers.size() == 1, "Three awake people cannot reuse carriers for two patients")
	party = _upkeep_party(3, 2)
	party.content.vehicles = {"1": {"id": "1", "kind": "wagon", "team_id": 1, "operator_id": 1,
		"cell": 5050, "facing": [1, 0], "cargo": {"wood": 200}, "holder": {"version": 1, "equipped": {}, "item_ids": []}}}
	var wagon := Travel.prepare_transport(party)
	_check(wagon.ok and wagon.can_move and wagon.carriers.is_empty(), "Original wagon patient seats allow two patients with one exclusive operator")
	_check(party.content.vehicles["1"].travel_patients.reserved_capacity == 100, "Two patients reserve 100 original cargo capacity")
	_check(Travel.validate_patients(party.content).ok, "Original patient reservation validates against living original team rows")
	party.content.vehicles["1"].cargo.wood = 201
	_check(not Travel.validate_patients(party.content).ok, "Patient reservation cannot exceed original cargo capacity")
	party = _upkeep_party(3, 1)
	party.content.vehicles = {"1": {"id": "1", "kind": "cart", "team_id": 1, "operator_id": 1,
		"cargo": {"wood": 100}, "holder": {"version": 1, "equipped": {}, "item_ids": []}}}
	var carried := Travel.prepare_transport(party)
	_check(carried.ok and carried.can_move and carried.carriers["4"] == [2, 3], "Operator is excluded from an original two-person carrying pair")
	_check(_close(float(carried.carry_factor), 0.5), "Carrying penalty applies once to whole-party speed")

func _upkeep_contract() -> void:
	var seed := _upkeep_party(2)
	var source := JSON.stringify(seed)
	var large := Travel.advance_upkeep(seed, 10.0 * Sustain.DAY)
	_check(large.ok and _close(float(large.at), 10.0 * Sustain.DAY), "Ten-day upkeep reaches exact common endpoint")
	if not large.ok: return
	_check(JSON.stringify(seed) == source, "Upkeep candidate preserves live source until atomic publication")
	var fine := seed.duplicate(true)
	var metres := 0.0
	var consumed := 0.0
	for hour: int in range(1, 241):
		var interval := Travel.advance_upkeep(fine, float(hour) * Sustain.HOUR)
		_check(interval.ok, "Hourly partition upkeep")
		if not interval.ok: return
		fine = interval.party
		metres += float(interval.metres)
		consumed += float(interval.consumed_rations)
		if hour == 117: fine = JSON.parse_string(JSON.stringify(fine)) # Save/reopen representation.
	_check(_close(metres, float(large.metres), 0.0001), "Big step, hourly steps, and reopen have equal integrated distance")
	_check(_close(consumed, float(large.consumed_rations)), "Big step and partition consume equal original rations")
	_check(fine.content.team_supply["1"].inventory == large.party.content.team_supply["1"].inventory, "Original food inventory is partition invariant")
	_check(_close(float(fine.content.armies[0].team_fatigue.fatigue), float(large.party.content.armies[0].team_fatigue.fatigue)), "30/80/50 rest endpoints are partition invariant")
	var weighted := _upkeep_party(2, 1)
	weighted.content.armies[0].team_fatigue.fatigue = 0.0
	var advance := Travel.advance_upkeep(weighted, Sustain.HOUR, {"patient_schema": false})
	_check(advance.ok and _close(float(advance.party.content.armies[0].team_fatigue.fatigue), 20.0 / 3.0), "Original living-member denominator includes unconscious member")
	var unsafe := _upkeep_party(1)
	unsafe.content.armies[0].team_fatigue.fatigue = 90.0
	advance = Travel.advance_upkeep(unsafe, 300.0, {"moving": false, "threat": true})
	_check(advance.ok and _close(float(advance.party.content.armies[0].team_fatigue.fatigue), 90.0), "Threat blocks safe fatigue recovery")
	var wake := _upkeep_party(1, 1)
	wake.content.armies[0].units[1].ko = 10.0
	advance = Travel.advance_upkeep(wake, 30.0)
	_check(advance.ok and _close(float(advance.at), 10.0) and advance.events.size() == 1, "Wake stops exactly at original life endpoint")
	if advance.ok:
		_check(advance.events[0].kind == "wake" and advance.events[0].size() == 6 and advance.party.content.armies[0].units[1].pose == "unconscious", "Wake queue preserves original pose until original wake consumer")
		var pending := Travel.advance_upkeep(advance.party, 60.0)
		_check(pending.ok and _close(float(pending.at), 10.0) and _close(float(pending.metres), 0.0), "Pending original life receipt blocks further travel")
	var starved := _upkeep_party(1)
	starved.content.armies[0].units[0].hp = 1.0
	starved.content.team_supply["1"].inventory = {}
	var cohort: Dictionary = starved.content.team_supply["1"].sustain.cohorts[0]
	cohort.hunger = 48.0
	cohort.meal_until = Sustain.MEAL
	var fatigue_endpoint := (Fatigue.THRESHOLD - float(starved.content.armies[0].team_fatigue.fatigue)) / Fatigue.WORK_RATE
	var partial_damage := Travel.advance_upkeep(starved, Sustain.DAY)
	_check(partial_damage.ok and _close(float(partial_damage.at), fatigue_endpoint) and partial_damage.events.size() == 1, "Original fatigue endpoint first captures already accepted starvation damage")
	if partial_damage.ok and partial_damage.events.size() == 1:
		_check(partial_damage.events[0].kind == "supply_damage" and not bool(partial_damage.events[0].death) and _close(float(partial_damage.events[0].loss), fatigue_endpoint / Sustain.HOUR), "Partial original starvation damage cannot be skipped until a later death")
	starved.content.armies[0].team_fatigue.fatigue = 0.0
	advance = Travel.advance_upkeep(starved, Sustain.DAY)
	_check(advance.ok and _close(float(advance.at), Sustain.HOUR) and advance.events.size() == 1, "Starvation endpoint stops before future travel")
	if advance.ok:
		_check(advance.events[0].kind == "supply_damage" and advance.events[0].size() == 10 and bool(advance.events[0].death), "Strict original damage event contains exact death evidence")
		_check(_close(float(advance.party.content.armies[0].units[0].hp), 1.0), "Damage queue preserves original HP until original damage consumer")
	starved.content.armies[0].units[0].ko = Sustain.HOUR
	starved.content.armies[0].units[0].pose = "unconscious"
	advance = Travel.advance_upkeep(starved, Sustain.DAY)
	_check(advance.ok and advance.events.size() == 1 and advance.events[0].kind == "supply_damage", "Accepted death suppresses simultaneous KO wake")
	if advance.ok: _check(_close(float(advance.party.content.armies[0].units[0].ko), Sustain.HOUR), "Death does not advance retained body KO before original settlement")
	var dead := _upkeep_party(0, 1)
	dead.content.armies[0].units[0].hp = 0.0
	dead.content.armies[0].units[0].ko = 1.0
	advance = Travel.advance_upkeep(dead, 10.0)
	_check(advance.ok and advance.events.is_empty() and _close(float(advance.party.content.armies[0].units[0].ko), 1.0), "Already dead original body neither advances KO nor queues wake")

func _terrain(water: bool = false) -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(100, 100))
	data.height_levels.fill(2)
	data.flags.fill(0 if water else TerrainData.Flag.WALKABLE)
	data.surface_types.fill(TerrainData.Surface.WATER if water else TerrainData.Surface.GRASS)
	data.water_kind.resize(10000)
	data.water_kind.fill(2 if water else 0)
	data.water_body.resize(10000)
	data.water_body.fill(1 if water else 0)
	data.parameters = {"navigable_water_version": 1, "navigable_water_bodies": [1]}
	return data

func _route_contract() -> void:
	var land := _terrain()
	var cover := PackedByteArray()
	cover.resize(100)
	cover.fill(2)
	for index: int in range(30): cover[index] = 1
	var policy := Route.travel_policy(land, cover)
	_check(policy.ok and policy.cart and not policy.wagon, "Exact forest 30 percent forbids wagon admission")
	for index: int in range(30, 50): cover[index] = 1
	policy = Route.travel_policy(land, cover)
	_check(policy.ok and not policy.cart, "Exact forest 50 percent forbids cart admission")
	cover.fill(2)
	for index: int in range(50): cover[index] = 3
	policy = Route.travel_policy(land, cover)
	_check(policy.ok and policy.cart and not policy.wagon, "Exact scrub 50 percent forbids wagon admission")
	for index: int in range(1000): land.water_kind[index] = 4
	policy = Route.travel_policy(land, cover)
	_check(policy.ok and _close(float(policy.water), 0.10) and _close(float(policy.speed_multiplier), 0.5) and not policy.cart and not policy.wagon, "Fine unknown-salinity water participates in exact 10 percent policy")
	land = _terrain()
	var other := _terrain()
	_check(Route.seam_step(land, other, 1, 50), "Actual matching Site seam admits walking")
	other.height_levels[other.index(Vector2i(0, 50))] = 4
	_check(not Route.seam_step(land, other, 1, 50), "Actual changed destination height closes cached base seam")
	var step := Route.land_step(land, land, Vector2i.ZERO, "wagon", Vector2i(50, 50), Vector2i.RIGHT, Vector2i(50, 51))
	_check(step.ok, "Original wagon turn succeeds in clear swept rectangle")
	land.static_blocked.resize(10000)
	land.static_blocked[land.index(Vector2i(48, 49))] = 1
	_check(land.can_step(Vector2i(50, 50), Vector2i(50, 51)), "Walking still fits the isolated turn fixture")
	_check(not Route.land_step(land, land, Vector2i.ZERO, "wagon", Vector2i(50, 50), Vector2i.RIGHT, Vector2i(50, 51)).ok, "Wagon swept corner cannot substitute a foot path")
	var source := FixtureSource.new()
	source.manifest = {"base_revision": "travel_contract_only"}
	source.manifest_hash = "travel_contract_only"
	source.terrain = _terrain()
	var frozen := _terrain()
	frozen.static_blocked.resize(10000)
	for y: int in range(100): frozen.static_blocked[frozen.index(Vector2i(50, y))] = 1
	var context := {"effective_terrain": func(site: Vector2i) -> Dictionary:
		return {"ok": true, "data": frozen, "revision": "visited:wall:v1"} if site == Vector2i.ZERO else {"ok": true, "data": null}}
	var table := Route.site_table(source, Vector2i.ZERO, context)
	_check(table.size() == Route.TABLE_BYTES and int(table[400]) == 2, "Visited original wall replaces base connectivity before cache lookup")
	_check(source.builds == 0, "Visited route projection builds no regenerated Site")
	var unvisited := Route.effective_terrain(source, Vector2i(9, 9), context)
	_check(unvisited.ok and not unvisited.visited and source.builds == 1, "Unvisited route uses deterministic source without saving or advancing a Site")
	var failed := Route.effective_terrain(source, Vector2i.ZERO, {"effective_terrain": func(_site: Vector2i) -> Dictionary: return {"ok": false, "code": "CORRUPT_SAVE"}})
	_check(not failed.ok and failed.code == "CORRUPT_SAVE" and source.builds == 1, "Corrupt visited original never silently regenerates base terrain")
	var sea := _terrain(true)
	var anchor := Vector2i(50, 50)
	_check(Route._ship_sweep(sea, sea, Vector2i.ZERO, "ferry", anchor, Vector2i.RIGHT, anchor + Vector2i.RIGHT, Vector2i.RIGHT), "Original full ferry sweep admits clear ocean")
	sea.ramp_edges[sea.index(Vector2i(51, 50))] = 1 << 5
	_check(not Route._ship_sweep(sea, sea, Vector2i.ZERO, "ferry", anchor, Vector2i.RIGHT, anchor + Vector2i.RIGHT, Vector2i.RIGHT), "Original water edge prohibition blocks full ship sweep")
	sea.ramp_edges.fill(0)
	sea.static_blocked.resize(10000)
	sea.static_blocked[sea.index(Vector2i(51, 51))] = 1
	_check(sea.can_navigate_water(anchor + Vector2i.RIGHT) and not Route._ship_sweep(sea, sea, Vector2i.ZERO, "ferry", anchor, Vector2i.RIGHT, anchor + Vector2i.RIGHT, Vector2i.RIGHT), "Clear ship anchor cannot substitute for blocked full hull")
	sea = _terrain(true)
	var passenger := _upkeep_party(1)
	passenger.content.armies[0].units[0].embarked_vehicle_id = "1"
	passenger.content.armies[0].units[0].berth_id = 0
	var ship := {"id": "1", "kind": "ship", "ship_type": "ferry", "team_id": 1, "operator_id": 1,
		"cell": 5050, "facing": [1, 0], "cargo": {}, "holder": {"version": 1, "equipped": {}, "item_ids": []}}
	passenger.content.vehicles = {"1": ship}
	passenger.content.armies[0].units[0].cargo = {"grain": 2}
	passenger.content.armies[0].units[0].item_state.item_ids = ["held_item"]
	passenger.content.armies[0].units[0].item_state.equipped = {"weapon": "held_item"}
	_check(_close(float(Travel.ship_metrics(passenger.content, ship).load), 3.0), "Ship load uses original person item_state including equipped real items")
	passenger.content.armies[0].units[0].cargo = {}
	passenger.content.armies[0].units[0].item_state = Travel.Runtime.new_item_state("person:1")
	var poses := {"1": {"anchor": [50, 50], "operator": [50, 50], "facing": [1, 0]}}
	var paths := {"1": [[50, 50, 1, 0], [51, 50, 1, 0], [51, 50, 0, 1], [51, 51, 0, 1]]}
	var timeline := Route.sea_action_steps(sea, sea, [ship], poses, paths, 1, passenger.content)
	_check(timeline.ok and timeline.actions.size() == 3 and _close(float(timeline.metres), 4.0), "Sea route stores actual completed cells and original turn actions")
	if timeline.ok:
		var original_speed := Ships.speed("ferry", 1, 0.0, 1)
		_check(_close(float(timeline.action_seconds), 2.0 / original_speed + Ships.turn_seconds("ferry", 1)), "Sea route uses original ACTION step/turn durations without a 200 m proxy")
		_check(_close(float(timeline.actions[1].action_begin), float(timeline.actions[0].action_end)) and _close(float(timeline.actions[2].action_begin), float(timeline.actions[1].action_end)), "Original sea action boundaries are continuous")
	paths["1"] = [[50, 50, 1, 0], [49, 50, 1, 0]]
	timeline = Route.sea_action_steps(sea, sea, [ship], poses, paths, 1, passenger.content)
	_check(timeline.ok and _close(float(timeline.action_seconds), 1.0 / Ships.speed("ferry", 1, 0.0, 1, false, true)), "Reverse sea step uses original reverse speed")
	paths["1"] = [[50, 50, 1, 0], [51, 50, 1, 0], [51, 50, 0, 1]]
	var second_ship := ship.duplicate(true)
	second_ship.id = "2"
	second_ship.cell = 5250
	poses["2"] = {"anchor": [50, 52], "operator": [50, 52], "facing": [1, 0]}
	paths["2"] = [[50, 52, 1, 0], [51, 52, 1, 0]]
	timeline = Route.sea_action_steps(sea, sea, [ship, second_ship], poses, paths, 1, passenger.content)
	_check(not timeline.ok and timeline.code == "FLEET_SWEEP_CONFLICT", "Original fleet turn cannot sweep through another original hull")

func _contact_point(at: float, x: int, component: int = 0, seam: Dictionary = {}) -> Dictionary:
	var point := {"at": at, "position": {"site": [x, 0], "component": component}}
	if not seam.is_empty(): point.seam = seam
	return point

func _contact_contract() -> void:
	var a: Array = [_contact_point(0.0, 0), _contact_point(5.0, 1, 0, {"edge": 1, "offset": 50}), _contact_point(10.0, 2, 0, {"edge": 1, "offset": 50})]
	var b: Array = [_contact_point(0.0, 1), _contact_point(5.0, 0, 0, {"edge": 3, "offset": 50})]
	var found := Route.route_contact_candidates(a, b, 0.0, 10.0)
	_check(found.ok and found.candidates.size() == 1 and found.candidates[0].kind == "reverse_seam" and _close(float(found.candidates[0].at), 5.0), "Exact reverse Site swap retains shared seam endpoint contact")
	b[1].seam.offset = 51
	found = Route.route_contact_candidates(a, b, 0.0, 10.0)
	_check(found.ok and found.candidates.is_empty(), "Reverse travel through different boundary offsets is not an invented seam contact")
	b = [_contact_point(0.0, 2), _contact_point(11.0, 3)]
	found = Route.route_contact_candidates(a, b, 0.0, 10.0)
	_check(found.ok and not found.candidates.is_empty() and _close(float(found.candidates[0].at), 10.0), "Multiple Site crossings inside one forecast find first stationary-player contact")
	b = [_contact_point(0.0, 1), _contact_point(8.0, 2, 0, {"edge": 1, "offset": 50})]
	found = Route.route_contact_candidates(a, b, 0.0, 10.0)
	_check(found.ok and not found.candidates.is_empty() and _close(float(found.candidates[0].at), 5.0), "Pursuit detects interval overlap before either final position")
	b = [_contact_point(0.0, 0, 1)]
	found = Route.route_contact_candidates(a, b, 0.0, 4.0)
	_check(found.ok and found.candidates.is_empty(), "Same Site with separate original navigation components is not forcibly merged")
	b = [_contact_point(0.0, 0, 10000)]
	found = Route.route_contact_candidates(a, b, 0.0, 4.0)
	_check(found.ok and found.candidates.is_empty(), "Ground/ocean label scopes cannot alias into a contact")
	b = [_contact_point(0.0, 0)]
	found = Route.route_contact_candidates(a, b, 0.0, 0.0)
	_check(found.ok and found.candidates.size() == 1 and _close(float(found.candidates[0].at), 0.0), "Already due original contact is a zero-time barrier")
	found = Route.route_contact_candidates([{"at": 0.0}], b, 0.0, 1.0)
	_check(not found.ok, "Malformed route timeline rejects the whole contact forecast")

func _join_contract() -> void:
	var player := _party(_state("A", "world:A"), "player_live")
	var npc := _party(_state("B", "world:B"), "npc_join")
	npc.controller = "npc"
	npc.content.controlled_person_id = -1
	player.content.family = {"version": 1, "complete": true, "members": [{"site_id": "travel:player_live", "person_id": 1, "path": "", "label": "Player", "age_years": 30}]}
	player.content = Travel.prepare_identity(player.content).state
	npc.content.armies[0].units[0].technology = {"version": 1, "learned": ["F07"]}
	npc.content.receipts = [{"person_id": 1, "item_id": "1", "paid": 7}]
	npc.content.fire_orders = [{"group": 1, "release_ids": [[1, 4]]}]
	npc.content.fire_member_cursor = [[1, 9]]
	npc.upkeep.events = [{"sequence": 7, "kind": "wake", "person_id": 1, "at": 0.0, "status": "pending"}]
	npc.upkeep.original_deaths = {"1": 1.5}
	var before_player := var_to_bytes(player)
	var before_npc := var_to_bytes(npc)
	var joined := Travel.join_party(player, npc, 8)
	_check(joined.ok, "Original NPC typed body closure joins original player party: " + str(joined.get("code", "OK")))
	_check(var_to_bytes(player) == before_player and var_to_bytes(npc) == before_npc, "Party join reserves without mutating either selected source")
	if not joined.ok: return
	var person := int(joined.mapping.maps.person["1"])
	var team := int(joined.mapping.maps.team["1"])
	var vehicle := str(joined.mapping.maps.vehicle["1"])
	var item := str(joined.mapping.maps.item["1"])
	_check(person != 1 and team != 1 and vehicle != "1" and item != "1", "Two colliding party-local identity scopes map without conflating original refs")
	_check(Travel.census(joined.party).people.size() == 2 and Travel.census(joined.party).vehicles.size() == 2, "Joined party owns both original body and vehicle closures exactly once")
	var bodies := Travel._body_records(joined.party.content)
	_check(bodies[person].technology == npc.content.armies[0].units[0].technology and float(bodies[1].hp) == 100.0, "Original personal technology travels while existing player body stays unchanged")
	_check(joined.party.content.family == player.content.family, "Foreign NPC join preserves original player family registry")
	_check(joined.party.content.item_records[item].holder == "vehicle:" + vehicle and int(joined.party.content.vehicles[vehicle].operator_id) == person, "Joint typed closure remaps original cargo holder and vehicle operator together")
	_check(int(joined.party.content.fire_orders[0].group) == team and int(joined.party.content.fire_orders[0].release_ids[0][0]) == person and int(joined.party.content.fire_member_cursor[0][0]) == team, "Original fire current references follow typed join mapping")
	_check(joined.party.upkeep.original_deaths.has(str(person)) and _close(float(joined.party.upkeep.original_deaths[str(person)]), 1.5), "Original pending death timer keeps accepted ACTION remainder under mapped body")
	_check(int(joined.incoming_events[0].person_id) == person and int(joined.incoming_events[0].sequence) == 7 and not joined.party.upkeep.events.has(joined.incoming_events[0]), "Original incoming life event keeps provenance and is not requeued under player's event sequence")
	_check(joined.party.content.get("receipts", []) == player.content.get("receipts", []), "Foreign historical paid archive is not copied as another player authority")
	var retry := Travel.join_party(player, npc, 8)
	_check(retry.ok and var_to_bytes(retry.party) == var_to_bytes(joined.party), "Joint mapping is deterministic before marker publication")
	var twice := Travel.join_party(joined.party, npc, 9)
	_check(not twice.ok and twice.code == "ALREADY_JOINED", "Original NPC source cannot retire or join twice")
	var duplicate := npc.duplicate(true)
	duplicate.content.travel_identity.refs.person["1"] = player.content.travel_identity.refs.person["1"].duplicate(true)
	_check(not Travel.join_party(player, duplicate, 8).ok, "Same stable body in two source parties refuses joint publication")
	var unsynced := npc.duplicate(true)
	unsynced.upkeep.at = 1.0
	_check(not Travel.join_party(player, unsynced, 8).ok, "Unsettled source cannot join a current player endpoint")
	var malformed: Dictionary = npc.duplicate(true)
	malformed.person_ids = []
	_check(not Travel.join_party(player, malformed, 8).ok, "Missing original body closure refuses partial union")
	var third := _party(_state("C", "world:C"), "npc_third")
	third.controller = "npc"
	var reinforced := Travel.join_party(joined.party, third, 9)
	_check(reinforced.ok and Travel.census(reinforced.party).people.size() == 3, "A third original origin joins without reusing the prior two bodies")
	if reinforced.ok:
		var third_person := int(reinforced.mapping.maps.person["1"])
		_check(Travel.stable_key(reinforced.party.content.travel_identity.refs.person[str(third_person)]) == Travel.stable_key(third.content.travel_identity.refs.person["1"]), "Third reinforcement retains its own immutable birthplace")

func _frame_contract() -> void:
	var party := _party(_state("A", "world:frame:A"), "frame_owner")
	party.origin = [0, 0]
	var row: Dictionary = party.content.armies[0].units[0]
	row.slot = [51, 50]
	row.destination = [-1, -1]
	row.facing = [1, 0]
	row.previous = [[[3200.0, 3210.0], [3210.0, 3210.0], [3200.0, 3220.0]]]
	party.content.armies[0].reference = [51.5, 50.5]
	party.content.armies[0].goal = [-1, -1]
	var identity: Dictionary = party.content.travel_identity
	var frame := {"version": 1, "world_origin": [-100, 0], "size": [200, 100],
		"people": {"1": {"reference": identity.refs.person["1"], "world_cell": [51, 50]}},
		"vehicles": {"1": {"reference": identity.refs.vehicle["1"], "world_cell": [50, 50]}}}
	var before := var_to_bytes(party)
	var projected := Travel.project_party_frame(party, frame)
	_check(projected.ok, "Same true body admits original contiguous boundary frame")
	_check(var_to_bytes(party) == before, "Coordinate preflight leaves selected original party unchanged")
	if not projected.ok: return
	var moved: Dictionary = projected.party.content.armies[0].units[0]
	_check(moved.cell == [151, 50] and moved.slot == [151, 50] and moved.destination == [-1, -1], "Body and final slot translate once; invalid target stays invalid")
	_check(projected.party.content.vehicles["1"].cell == 50 * 200 + 150, "Original vehicle index uses frame width, preserving true world anchor")
	_check(moved.facing == row.facing and moved.hp == row.hp and projected.party.upkeep == party.upkeep, "Original facing, life and both time authorities stay unchanged")
	_check(_close(float(moved.previous[0][0][0]), 9600.0), "Paid original weapon polygon translates in pixels")
	_check(projected.party.content.item_records == party.content.item_records and projected.party.content.travel_identity == identity, "Original cargo and typed refs stay the same owner")
	var wrong: Dictionary = projected.projection.duplicate(true)
	wrong.people["1"].reference.namespace = "another-world"
	_check(not Travel.project_party_coordinates(party, wrong).ok, "Forged PersonRef cannot use a coordinate preflight to replace original body")
	wrong = projected.projection.duplicate(true)
	wrong.people["1"].from = [52, 50]
	wrong.people["1"].offset = [99, 0]
	_check(not Travel.project_party_coordinates(party, wrong).ok, "Projection cannot invent an old source cell")
	var plan := {"resolved_anchor": Vector2i(51, 50), "macro_path": [Vector2i(51, 50), Vector2i(52, 50)], "final_facing": Vector2i.RIGHT}
	var polygon := PackedVector2Array([Vector2(3260, 3198), Vector2(3268, 3198), Vector2(3264, 3205)])
	var motion := {"ground": Vector2(3264, 3200), "end_ground": Vector2(3328, 3200), "anchor": Vector2(3264, 3201), "radius": 10.0,
		"motion": {"from": Vector2(3264, 3200), "to": Vector2(3328, 3200)}, "velocity": Vector2(64, 0),
		"geometry": {"body": [polygon], "shield": [polygon], "bounds": Rect2(Vector2(3260, 3198), Vector2(8, 7))}}
	var projectile := {"mode": "cell", "source_cell": Vector2i(51, 50), "target_cell": Vector2i(52, 50),
		"origin": Vector2(3264, 3200), "position": Vector2(3280, 3200), "goal": Vector2(3328, 3200),
		"velocity": Vector2(64, 0), "elapsed": 0.25, "shot_id": 7}
	var roots := {"plans": {"1": {"move": plan}}, "reference_objects": {"team:1:move": {"kind": "move", "values": plan}},
		"coordinator": {"_current_occupancy": {Vector2i(51, 50): 1}}, "lab": {"_fire_motion": {1: motion}, "_fire_body_buckets": {}, "projectiles": [projectile]},
		"registry": {"formation_slots": {3: [Vector2i(51, 50)]}, "leases": [[Vector2i(51, 50), [3, 1, 1, 0, Vector2i(51, 50), 2.0]]]},
		"symbol": {"@region_reference": "person:1:body", "type": TYPE_DICTIONARY}}
	var original := var_to_bytes(roots)
	var graph := Travel.project_owner_coordinates(roots, projected.projection)
	_check(graph.ok and var_to_bytes(roots) == original, "Original full graph projection is pure")
	if graph.ok:
		_check(is_same(graph.roots.plans["1"].move, graph.roots.reference_objects["team:1:move"].values), "Full graph retains shared plan alias after one translation")
		_check(graph.roots.plans["1"].move.resolved_anchor == Vector2i(151, 50) and graph.roots.plans["1"].move.final_facing == Vector2i.RIGHT, "Original plan coordinates translate while direction stays relative")
		_check(graph.roots.coordinator._current_occupancy == {Vector2i(151, 50): 1}, "Original reservation keys follow physical cells")
		_check(graph.roots.registry.leases[0][0] == Vector2i(151, 50) and graph.roots.registry.leases[0][1][4] == Vector2i(151, 50), "Original lease and registry cell remain the same reservation")
		_check(graph.roots.lab._fire_motion[1].motion.from == Vector2(9664, 3200) and graph.roots.lab._fire_motion[1].velocity == Vector2(64, 0), "Original paid fire motion translates in pixels without changing velocity")
		_check(graph.roots.lab._fire_motion[1].anchor == Vector2(9664, 3201) and graph.roots.lab._fire_motion[1].geometry.body[0][0] == Vector2(9660, 3198), "Original fire anchor and packed body polygons translate in pixels")
		_check(graph.roots.lab._fire_motion[1].geometry.shield[0][0] == Vector2(9660, 3198) and graph.roots.lab._fire_motion[1].geometry.bounds == Rect2(Vector2(9660, 3198), Vector2(8, 7)), "Original shield and contact bounds retain their exact shape after translation")
		_check(is_same(graph.roots.lab._fire_motion[1].geometry.body[0], graph.roots.lab._fire_motion[1].geometry.shield[0]) and polygon[0] == Vector2(3260, 3198), "Packed body/shield alias publishes the same translated output while the selected original buffer stays unchanged")
		var flight: Dictionary = graph.roots.lab.projectiles[0]
		_check(flight.source_cell == Vector2i(151, 50) and flight.target_cell == Vector2i(152, 50) and flight.origin == Vector2(9664, 3200) and flight.goal == Vector2(9728, 3200), "Original normal cell flight uses grid endpoints and pixel motion origins")
		_check(flight.velocity == Vector2(64, 0) and flight.elapsed == 0.25 and flight.shot_id == 7, "Paid original projectile speed, time and accepted ID stay unchanged")
		_check(graph.roots.symbol == roots.symbol and not graph.roots.lab._fire_body_buckets.is_empty(), "Original symbolic refs stay bound and fire broadphase rebuilds from paid motion")
	var first := _terrain()
	var second := _terrain()
	first.static_blocked.resize(10000)
	first.static_blocked[first.index(Vector2i(99, 49))] = 1
	second.walk_height_levels = second.height_levels.duplicate()
	second.walk_height_levels[second.index(Vector2i(0, 50))] = 1
	second.walk_ramp_edges = second.ramp_edges.duplicate()
	second.walk_ramp_edges[second.index(Vector2i(0, 50))] = 1 << 3
	second.has_raised_surfaces = true
	second.has_navigation_overrides = true
	first.walk_ramp_edges = first.ramp_edges.duplicate()
	first.walk_ramp_edges[first.index(Vector2i(99, 50))] = 1 << 1
	first.has_navigation_overrides = true
	var fixture := FixtureSource.new()
	fixture.terrain = first
	var provider := func(site: Vector2i) -> Dictionary:
		return {"ok": true, "data": first if site.x == -1 else second, "revision": "actual:" + str(site), "visited": true}
	var geometry := Route.party_frame_geometry(fixture, frame, {"effective_terrain": provider})
	_check(geometry.ok, "Derived frame borrows both actual selected geometries")
	if geometry.ok:
		_check(not geometry.data.is_walkable(Vector2i(99, 49)) and geometry.data.effective_height(Vector2i(100, 50)) == 1, "Actual changed blocker and raised bridge survive frame derivation")
		_check(geometry.data.can_step(Vector2i(99, 50), Vector2i(100, 50)), "Original reciprocal ramp permits the true reverse seam")
		var lookup := Route.party_frame_source(geometry.data, Vector2i(100, 50))
		_check(lookup.ok and lookup.data == second and lookup.cell == Vector2i(0, 50), "Original effects resolve to the actual source owner through frame lookup")
		_check(geometry.data.site.is_empty() and geometry.sources.size() == 2 and fixture.builds == 0, "Frame has no virtual Site and never replaces selected geometry with fixed base")

func _run() -> void:
	_identity_contract()
	_family_contract()
	_transport_contract()
	_upkeep_contract()
	_route_contract()
	_contact_contract()
	_join_contract()
	_frame_contract()
	print("REGION_GAMEPLAY_TRAVEL_REPORT: " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty(): print("REGION_GAMEPLAY_TRAVEL_PASS")
	quit(0 if failures.is_empty() else 1)
