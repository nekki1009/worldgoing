extends RefCounted
## One synchronous query's columns, not authoritative people or a cross-tick cache.
## Only actual melee candidates materialize the old Dictionary query interface.

var owners: Array[Node2D] = []
var owner_slots := PackedInt32Array()
var units := PackedInt32Array()
var identities := PackedInt64Array()
var xs := PackedInt32Array()
var ys := PackedInt32Array()
var factions := PackedInt64Array()
var _people: Dictionary = {}

func capture(actors: Array[TerrainTestCharacter], armies: Array[TerrainArmy]) -> void:
	for actor: TerrainTestCharacter in actors:
		if not is_instance_valid(actor) or not actor.can_act(): continue
		owners.append(actor)
		var ordinal := units.size()
		_append(owners.size() - 1, -1, actor.person_id, actor.terrain_cell, actor.faction_id)
		# The original actor readiness is eager, unlike Army readiness.
		_people[ordinal] = {"owner": actor, "unit": -1, "id": actor.person_id,
			"cell": actor.terrain_cell, "faction": actor.faction_id,
			"ready": actor.exchange_ready(), "receive": actor.exchange_can_receive()}
	for team: TerrainArmy in armies:
		if not team.combat_enabled: continue
		owners.append(team)
		var owner_slot := owners.size() - 1
		var packet := team.capture_exchange_people()
		if packet.size() == 4:
			var slots := PackedInt32Array()
			slots.resize(packet[0].size())
			slots.fill(owner_slot)
			var team_factions := PackedInt64Array()
			team_factions.resize(packet[0].size())
			team_factions.fill(team.faction_id)
			owner_slots.append_array(slots)
			units.append_array(packet[0])
			identities.append_array(packet[1])
			xs.append_array(packet[2])
			ys.append_array(packet[3])
			factions.append_array(team_factions)
			continue
		for index in range(team.combat_units.size()):
			if team.combat_can_act(index):
				_append(owner_slot, index, team.combat_identity(index), team.cells[index], team.faction_id)

func _append(owner_slot: int, index: int, identity: int, cell: Vector2i, faction: int) -> void:
	owner_slots.append(owner_slot)
	units.append(index)
	identities.append(identity)
	xs.append(cell.x)
	ys.append(cell.y)
	factions.append(faction)

func person(ordinal: int) -> Dictionary:
	if not _people.has(ordinal):
		_people[ordinal] = {"owner": owners[owner_slots[ordinal]], "unit": units[ordinal],
			"id": identities[ordinal], "cell": Vector2i(xs[ordinal], ys[ordinal]),
			"faction": factions[ordinal], "ready": null, "receive": null}
	return _people[ordinal]

func front_order(round_id: int, kernel: RefCounted) -> PackedInt32Array:
	if kernel != null: return kernel.FrontOrder(xs, ys, factions, round_id)
	# Same conservative fallback when the optional .NET assembly is unavailable.
	var occupied := {}
	for i in range(units.size()):
		var cell := Vector2i(xs[i], ys[i])
		if not occupied.has(cell): occupied[cell] = {}
		occupied[cell][factions[i]] = true
	var result := PackedInt32Array()
	for offset in range(units.size()):
		var i := (offset + round_id) % units.size()
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var neighbours: Dictionary = occupied.get(Vector2i(xs[i], ys[i]) + direction, {})
			if neighbours.size() > 1 or (not neighbours.is_empty() and not neighbours.has(factions[i])):
				result.append(i)
				break
	return result

func ranged_people() -> Array[Dictionary]:
	# Called AFTER melee and its signals. Equipment/ammo may have changed; do
	# not cache a pre-hit weapon classification. Retain pre-hit cells and order.
	var kernel := TerrainArmy._get_idle_kernel()
	var accelerated := kernel != null and kernel.has_method("empty_cargo_prefix")
	var checked_owner := -1
	var i := 0
	var end := units.size() # Same fixed bound as the original range.
	while i < end:
		var original: Variant = owners[owner_slots[i]]
		var index := units[i]
		if accelerated and checked_owner != owner_slots[i] and index >= 0 and original.get_script() == TerrainArmy and original.native_queries_enabled:
			checked_owner = owner_slots[i] # At most one attempt per contiguous owner.
			var next := int(kernel.empty_cargo_prefix(original.combat_units, units, owner_slots, i))
			if next > i:
				i = next
				continue
		i += 1
		var ammunition: Dictionary = original.combat_units[index].get("cargo", {}) if index >= 0 else original.ammo_inventory
		if ammunition.is_empty(): continue # No weapon can fire from an empty inventory.
		var profile: Dictionary = original.ranged_profile(index) if index >= 0 else original.ranged_profile()
		if profile.is_empty() or int(ammunition.get(str(profile.ammo), 0)) < 1: continue
		# ponytail: armed ranged battles retain the original all-target scan;
		# spatial ranged selection needs its own ordering/occlusion parity slice.
		var all_people: Array[Dictionary] = []
		for ordinal in range(units.size()): all_people.append(person(ordinal))
		return all_people
	return []
