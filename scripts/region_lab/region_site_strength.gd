extends RefCounted
## 土匪 B4d-3b 前置：跨 Site 兵力情報. At each Region evaluation of a settled original Site, every officer present
## (team commanders and nation office holders, as for visible features) records what his faction's people on this Site
## can see of everyone else: the number of able, armed (non-civilian) people of other factions within sight of any of
## his faction's able people here, by faction. The receipt's object is this Site's id, so a decider who later stands at
## another Site finds it through RegionAI.dispatch_known_targets (value.power). The receipt follows the officer by his
## stable person ref, not by scope: he carries what he saw.
## Handing over: at the same evaluation an officer standing beside a same-faction office holder tells him in person
## every unexpired strength receipt about another Site (a "report" copy addressed to the holder). Nothing reaches a
## person who is not physically present.
const Sight = preload("res://scripts/terrain_lab/site_army_ai.gd")
const RegionAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

const KIND := "officer_site_strength"
const GAME_SECONDS := 7.0 * 86400.0
const BUCKET := 12

## Able people on the Site: [{id, cell, faction, armed}].
static func people(lab: TerrainLab) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for team: Variant in lab.team_owners():
		if not team.combat_enabled: continue
		for index: int in indices(team):
			if not team.combat_can_act(index): continue
			var identity: int = team.combat_identity(index)
			var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
			if person.is_empty() or float(person.get("hp", 0.0)) <= 0.0: continue
			var role := str(person.get("body", {}).get("military_role", "")) if person.get("body") is Dictionary else ""
			result.append({"id": identity, "cell": person.cell, "faction": int(team.faction_id), "armed": role != "civilian"})
	return result

## Unit indices of a GD army (Array) or a crowd person owner (Dictionary keyed by index).
static func indices(team: Variant) -> Array:
	return team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())

static func _key(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / BUCKET), floori(float(cell.y) / BUCKET))

## What `faction`'s able people see here: {power, factions: {id: count}}.
static func seen_by(lab: TerrainLab, faction: int, everyone: Array[Dictionary]) -> Dictionary:
	var buckets := {}
	for person: Dictionary in everyone:
		if int(person.faction) != faction: continue
		var key := _key(person.cell)
		if not buckets.has(key): buckets[key] = []
		buckets[key].append({"cell": person.cell})
	var factions := {}
	var power := 0
	for person: Dictionary in everyone:
		if int(person.faction) == faction or not bool(person.armed): continue
		var near: Array = []
		var key := _key(person.cell)
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2): near.append_array(buckets.get(key + Vector2i(dx, dy), []))
		if near.is_empty() or not Sight._observed_cell(lab, near, person.cell, Sight.THREAT_DISTANCE): continue
		power += 1
		factions[str(int(person.faction))] = int(factions.get(str(int(person.faction)), 0)) + 1
	return {"power": power, "factions": factions}

static func officers(lab: TerrainLab) -> Array[int]:
	var result: Array[int] = []
	for team: Variant in lab.team_owners():
		if not team.combat_enabled: continue
		var identity := -1
		if team.current_commander >= 0: identity = team.combat_identity(team.current_commander)
		elif team is CrowdPersonOwner: identity = int(lab.crowd_site.formation_state(team.formation_index).get("formal_person", -1)) # seated next step
		if identity > 0 and not result.has(identity): result.append(identity)
	for nation: Dictionary in lab.terrain.site.get("equipment_nations", {}).values():
		if not SiteOffices.validate(nation.get("offices", {}), "nation"): continue
		for position: Dictionary in nation.offices.positions:
			var holder := int(position.holder)
			if holder > 0 and not result.has(holder): result.append(holder)
	result.sort()
	return result

## Records this Site's strength for every officer present and hands carried strength receipts to office holders
## standing here. Returns {ok, observed, told}.
static func record(slot: Variant, lab: TerrainLab) -> Dictionary:
	var registry: Dictionary = slot.region_registry()
	var scope := str(lab.terrain.site.id)
	var now := float(slot.control.logical_game_seconds)
	var everyone := people(lab)
	var faction_of := {}
	for person: Dictionary in everyone: faction_of[int(person.id)] = int(person.faction)
	var seen := {}
	var observed := 0
	var present: Array[int] = []
	for officer: int in officers(lab):
		if not faction_of.has(officer): continue
		var reference := RegionAI.person_ref(lab.terrain.site, officer)
		if not RegionAI.valid_person_ref(reference): continue
		present.append(officer)
		var faction := int(faction_of[officer])
		if not seen.has(faction): seen[faction] = seen_by(lab, faction, everyone)
		var value: Dictionary = seen[faction].duplicate(true)
		value["settlement_owner"] = int(Settlement.record(lab.terrain).get("owner_faction", -1)) # public: whose settlement this is
		var known := RegionAI.view(registry, officer, now, scope, reference)
		var prior: Dictionary = known.get(scope, {})
		if prior.get("observation_kind") == KIND and prior.get("value") == value and str(prior.get("source", "")) == "site_observation": continue
		var receipt := {"id": "officer-strength:%s:%s:%.6f" % [scope, RegionTravel.stable_key(reference), now],
			"source": "site_observation", "observation_kind": KIND, "observer": officer, "receiver": officer,
			"observer_scope": scope, "receiver_scope": scope, "object_scope": scope,
			"observer_ref": reference.duplicate(true), "receiver_ref": reference.duplicate(true), "object": scope, "value": value,
			"game_time": now, "expires_at": now + GAME_SECONDS, "confidence": 1.0}
		var recorded := RegionAI.observe(registry, receipt)
		if not recorded.ok:
			if str(recorded.get("code", "")) == "OBSERVATION_CONFLICT": continue # a second change in the same instant waits
			return recorded
		observed += 1
	var told := 0
	var holders := _holders(lab)
	for officer: int in present:
		var reference := RegionAI.person_ref(lab.terrain.site, officer)
		var carried := RegionAI.view(registry, officer, now, scope, reference)
		for holder: int in holders:
			if holder == officer or not faction_of.has(holder) or int(faction_of[holder]) != int(faction_of[officer]): continue
			# A holder who never travelled has no stable ref yet: he is told here, addressed by id and this scope.
			var holder_ref := RegionAI.person_ref(lab.terrain.site, holder)
			var theirs := RegionAI.view(registry, holder, now, scope, holder_ref)
			for object: String in carried:
				var receipt: Dictionary = carried[object]
				if receipt.get("observation_kind") != KIND or str(receipt.get("object", "")) == scope: continue
				if theirs.has(object) and float(theirs[object].game_time) >= float(receipt.game_time): continue
				var copy: Dictionary = receipt.duplicate(true)
				copy.id = "told:%s:%s:%s" % [str(receipt.id), RegionTravel.stable_key(holder_ref) if not holder_ref.is_empty() else str(holder), scope]
				copy.source = "report"
				copy.receiver = holder
				copy.receiver_scope = scope
				if holder_ref.is_empty(): copy.erase("receiver_ref")
				else: copy.receiver_ref = holder_ref.duplicate(true)
				copy["received_at"] = now
				var told_receipt := RegionAI.observe(registry, copy)
				if not told_receipt.ok: return told_receipt
				told += 1
	return {"ok": true, "observed": observed, "told": told}

static func _holders(lab: TerrainLab) -> Array[int]:
	var result: Array[int] = []
	for nation: Dictionary in lab.terrain.site.get("equipment_nations", {}).values():
		if not SiteOffices.validate(nation.get("offices", {}), "nation"): continue
		for position: Dictionary in nation.offices.positions:
			var holder := int(position.holder)
			if holder > 0 and not result.has(holder): result.append(holder)
	result.sort()
	return result
