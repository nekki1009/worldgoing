extends RefCounted
## B0 read-only vocabulary. The original vehicle/row/holder remains authority.
## Q1 fixed hulls; Q2 closing blocks entrants, drains one existing cross;
## Q3 exact point and original withdrawal/water/death owners; Q4 no capture;
## Q5 original hostile AI; Q6 one channel/one crosser; Q7 stable saves only;
## Q8 original action seconds, no material charge. No producer in B0.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const VERSION: int = 1
# B2 must pay this duration in original PersonActions; B0 starts no job.
const LINK_ACTION_SECONDS: float = 4.0
# B2S2 legal link state moves. "establishing" is only written by a creator.
const TRANSITIONS: Dictionary = {"establishing": ["linked", "invalid"], "linked": ["closing", "invalid"], "closing": ["linked", "invalid"], "invalid": []}

static func _empty(value: Variant) -> bool:
	return value == null or value is Dictionary and value.is_empty()

static func _fields(value: Variant, names: Array) -> bool:
	if not value is Dictionary or value.size() != names.size(): return false
	for name: String in names:
		if not value.has(name): return false
	return true

# Match original Store JSON integer semantics without coercing source values.
static func _integer(value: Variant, lower: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= 2147483647.0 and float(value) == floorf(float(value))

static func _naval_guard(vehicle: Dictionary) -> Dictionary:
	if vehicle.has("boarding_link"): return Runtime.fail("CORRUPT_SAVE", "Link belongs to original naval owner")
	if not vehicle.has("naval"): return Runtime.ok()
	var naval: Variant = vehicle.naval
	if naval is Dictionary and naval.has("link_epoch") and not (_integer(naval.link_epoch, 0)): return Runtime.fail("CORRUPT_SAVE", "Link epoch type")
	if not naval is Dictionary or not _integer(naval.get("version"), 1) or float(naval.version) not in [1.0, 2.0]: return Runtime.fail("CORRUPT_SAVE", "Unknown naval version/type")
	if naval.size() != 4 + int(naval.has("boarding_link")) + int(naval.has("link_epoch")) or not (naval.get("hp") is int or naval.get("hp") is float) or not is_finite(float(naval.hp)) or float(naval.hp) < 0.0 or not naval.get("state") is String or naval.state not in ["afloat", "sinking", "wrecked"] or not naval.get("repair") is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "Original naval hull state/type")
	if (naval.state == "afloat") != (float(naval.hp) > 0.0): return Runtime.fail("CORRUPT_SAVE", "Original naval hp/state")
	if naval.version == 1 and not _empty(naval.get("boarding_link")): return Runtime.fail("CORRUPT_SAVE", "Active link requires naval v2")
	if naval.version == 2 and _empty(naval.get("boarding_link")): return Runtime.fail("CORRUPT_SAVE", "Naval v2 requires both ends")
	return Runtime.ok()

static func _point(value: Variant, integral: bool = false) -> bool:
	if not value is Array or value.size() != 2: return false
	for number: Variant in value:
		if integral:
			if not _integer(number, -2147483647): return false
		elif not (number is int or number is float) or not is_finite(float(number)): return false
	return true

static func _ref(value: Variant) -> bool:
	return _fields(value, ["site_id", "vehicle_id"]) and value.site_id is String and not value.site_id.is_empty() and value.vehicle_id is String and not value.vehicle_id.is_empty()

static func _frame(value: Variant) -> bool:
	if not _fields(value, ["site_id", "anchor", "facing"]) or not value.site_id is String or value.site_id.is_empty() or not _point(value.anchor, true) or not _point(value.facing, true): return false
	return absi(int(value.facing[0])) + absi(int(value.facing[1])) == 1

static func _link(value: Variant) -> bool:
	if not _fields(value, ["version", "id", "epoch", "self", "peer", "frame", "peer_frame", "local", "world_point", "state", "crosser_id"]): return false
	if not _integer(value.version, 1) or value.version != VERSION or not value.id is String or value.id.is_empty() or not _integer(value.epoch, 1): return false
	if not _ref(value.self) or not _ref(value.peer) or not _frame(value.frame) or not _frame(value.peer_frame) or not _point(value.local) or not _point(value.world_point): return false
	return value.state is String and value.state in ["establishing", "linked", "closing", "invalid"] and _integer(value.crosser_id)

## Snapshot frame is the fixed Site cell-center frame, independent of revision.
## world_point = anchor + lateral*local.x + facing*local.y (cell units).
static func query(state: Dictionary, vehicle_id: String, data: TerrainData = null) -> Dictionary:
	var vehicles: Variant = state.get("vehicles", {})
	if not vehicles is Dictionary: return Runtime.fail("CORRUPT_SAVE", "Original vehicle dictionary")
	var vehicle: Variant = vehicles.get(vehicle_id)
	if not vehicle is Dictionary: return Runtime.fail("NO_TARGET")
	var naval_checked: Dictionary = _naval_guard(vehicle)
	if not naval_checked.ok: return naval_checked
	var link: Variant = vehicle.get("naval", {}).get("boarding_link")
	if _empty(link): return Runtime.ok("", {"linked": false})
	if not _link(link): return Runtime.fail("CORRUPT_SAVE", "Boarding link schema/version")
	if link.self.vehicle_id != vehicle_id or link.self.site_id != link.peer.site_id or link.self.vehicle_id == link.peer.vehicle_id or link.frame.site_id != link.self.site_id or link.peer_frame.site_id != link.peer.site_id:
		return Runtime.fail("CORRUPT_SAVE", "Boarding typed references/frame")
	if state.has("id") and (not state.id is String or link.self.site_id != state.id): return Runtime.fail("CORRUPT_SAVE", "Boarding Site reference")
	var peer: Variant = vehicles.get(link.peer.vehicle_id)
	if not peer is Dictionary: return Runtime.fail("CORRUPT_SAVE", "Half boarding link")
	var peer_checked: Dictionary = _naval_guard(peer)
	if not peer_checked.ok: return peer_checked
	if not _link(peer.get("naval", {}).get("boarding_link")): return Runtime.fail("CORRUPT_SAVE", "Half boarding link")
	var other: Dictionary = peer.naval.boarding_link
	if other.id != link.id or other.epoch != link.epoch or other.self != link.peer or other.peer != link.self or other.frame != link.peer_frame or other.peer_frame != link.frame or other.state != link.state or other.crosser_id != link.crosser_id:
		return Runtime.fail("CORRUPT_SAVE", "Boarding peer closure/epoch/frame/state")
	for end: Dictionary in [vehicle, peer]:
		var endpoint: Dictionary = end.naval.boarding_link
		if not end.get("kind") is String or end.kind != "ship" or not end.get("id") is String or end.id != endpoint.self.vehicle_id or not end.get("ship_type") is String or not Ship.is_kind(end.ship_type) or not _point(end.get("facing"), true) or end.facing != endpoint.frame.facing:
			return Runtime.fail("CORRUPT_SAVE", "Boarding original hull/frame")
		var definition: Dictionary = Ship.definition(end.ship_type)
		if float(endpoint.local[0]) < -0.25 or float(endpoint.local[0]) > float(definition.width) - 0.75 or float(endpoint.local[1]) < -0.25 or float(endpoint.local[1]) > float(definition.length) - 0.75:
			return Runtime.fail("CORRUPT_SAVE", "Boarding endpoint outside real deck")
		if data != null:
			if not _integer(end.get("cell")) or end.cell < 0 or end.cell >= data.size.x * data.size.y or data.cell_from_index(int(end.cell)) != Vector2i(int(endpoint.frame.anchor[0]), int(endpoint.frame.anchor[1])): return Runtime.fail("CORRUPT_SAVE", "Boarding changed anchor")
		var direction := Vector2(endpoint.frame.facing[0], endpoint.frame.facing[1])
		var actual := Vector2(endpoint.frame.anchor[0], endpoint.frame.anchor[1]) + Vector2(-direction.y, direction.x) * float(endpoint.local[0]) + direction * float(endpoint.local[1])
		if actual != Vector2(endpoint.world_point[0], endpoint.world_point[1]): return Runtime.fail("CORRUPT_SAVE", "Boarding actual endpoint")
		if not end.get("move", {}) is Dictionary or not end.get("command", {}) is Dictionary: return Runtime.fail("CORRUPT_SAVE", "Original hull move/command type")
		if link.state in ["establishing", "linked", "closing"] and end.naval.state != "afloat": return Runtime.fail("BUSY", "Original hull lost support; preserve actual point")
		if not end.get("move", {}).is_empty() or not end.get("command", {}).is_empty(): return Runtime.fail("BUSY", "Linked hull must remain fixed")
	if link.crosser_id > 0:
		var found: int = 0
		var actors: Variant = state.get("actors", {})
		var armies: Variant = state.get("armies", [])
		if not actors is Dictionary or not armies is Array: return Runtime.fail("CORRUPT_SAVE", "Original crosser owners")
		for row: Variant in actors.values():
			if not row is Dictionary: return Runtime.fail("CORRUPT_SAVE", "Original crosser row")
			if _integer(row.get("person_id"), 1) and row.person_id == link.crosser_id: found += 1
		for army: Variant in armies:
			if not army is Dictionary or not army.get("units", []) is Array: return Runtime.fail("CORRUPT_SAVE", "Original crosser Army")
			for row: Variant in army.get("units", []):
				if not row is Dictionary: return Runtime.fail("CORRUPT_SAVE", "Original crosser row")
				if _integer(row.get("person_id"), 1) and row.person_id == link.crosser_id: found += 1
		if found != 1: return Runtime.fail("CORRUPT_SAVE", "Crosser must be exactly one original person")
	# Traffic state only. B2/B3 must prove support/path/auth/cost before execution.
	return Runtime.ok("", {"linked": true, "link": link.duplicate(true), "peer_link": other.duplicate(true), "entrants_open": link.state == "linked" and link.crosser_id == 0, "can_execute": false})

## Position lives on the original person row or ground_loot holder, never a clone.
## Channel points are Site-frame cell units; they are never ship-local/clamped.
static func position_guard(row: Dictionary) -> Dictionary:
	var position: Variant = row.get("boarding_position")
	if _empty(position): return Runtime.ok()
	if not _fields(position, ["version", "kind", "link_id", "epoch", "frame", "world_point"]) or not _integer(position.version, 1) or position.version != VERSION or not position.kind is String or position.kind != "channel" or not position.link_id is String or position.link_id.is_empty() or not _integer(position.epoch, 1) or not _frame(position.frame) or not _point(position.world_point):
		return Runtime.fail("CORRUPT_SAVE", "Boarding exact channel position schema")
	return Runtime.fail("BUSY", "Channel position unsupported before B5; retain exact original point")

## Pure Store entry may receive a stale snapshot while original live rows exist.
## The existing Site garrison metadata resolves that original owner, read-only.
static func data_save_guard(data: TerrainData) -> Dictionary:
	var checked: Dictionary = save_guard(data.site, data)
	if not checked.ok or not data.has_meta(&"site_garrison_lab"): return checked
	var original: Variant = data.get_meta(&"site_garrison_lab")
	if original is WeakRef: original = original.get_ref()
	if not original is Object or not is_instance_valid(original) or not original.has_method("capture_region_owner_state") or not is_same(original.get("terrain"), data):
		return Runtime.fail("BUSY", "Original boarding row owner unavailable")
	var controller: Variant = original.get("site_controller")
	if not controller is Object or not is_instance_valid(controller): return Runtime.fail("BUSY", "Original boarding controller unavailable")
	var vehicles: Variant = controller.get("vehicles")
	if not vehicles is Object or not is_instance_valid(vehicles) or not vehicles.has_method("boarding_save_guard"): return Runtime.fail("BUSY", "Original boarding vehicle owner unavailable")
	return vehicles.boarding_save_guard()

static func save_guard(state: Dictionary, data: TerrainData = null) -> Dictionary:
	var vehicles: Variant = state.get("vehicles", {})
	if not vehicles is Dictionary: return Runtime.fail("CORRUPT_SAVE", "Original vehicles")
	for identity: Variant in vehicles:
		if not vehicles[identity] is Dictionary: return Runtime.fail("CORRUPT_SAVE", "Original vehicle row")
		var naval_checked: Dictionary = _naval_guard(vehicles[identity])
		if not naval_checked.ok: return naval_checked
		if not _empty(vehicles[identity].get("naval", {}).get("boarding_link")):
			if not identity is String: return Runtime.fail("CORRUPT_SAVE", "Original vehicle ID")
			var checked: Dictionary = query(state, identity, data)
			if not checked.ok: return checked
			# B5S1: only a steady link saves. An invalid record is not a steady state (sinking clears the link).
			var link: Dictionary = vehicles[identity].naval.boarding_link
			if str(link.state) == "invalid": return Runtime.fail("CORRUPT_SAVE", "失效接舷不得保存；沉沒時已清除")
			if str(link.state) != "linked": return Runtime.fail("BUSY", "接舷未收束（建立或解除中）；收束後再存")
			if int(link.crosser_id) != 0: return Runtime.fail("BUSY", "通道中仍有原人；通道結束後才存（Q7 A）")
	var actors: Variant = state.get("actors", {})
	var armies: Variant = state.get("armies", [])
	var loot: Variant = state.get("ground_loot", {})
	if not actors is Dictionary or not armies is Array or not loot is Dictionary: return Runtime.fail("CORRUPT_SAVE", "Original row containers")
	for row: Variant in actors.values() + loot.values():
		if not row is Dictionary: return Runtime.fail("CORRUPT_SAVE", "Original person/holder row")
		var checked: Dictionary = position_guard(row)
		if not checked.ok: return checked
	for army: Variant in armies:
		if not army is Dictionary or not army.get("units", []) is Array: return Runtime.fail("CORRUPT_SAVE", "Original Army rows")
		for row: Variant in army.get("units", []):
			if not row is Dictionary: return Runtime.fail("CORRUPT_SAVE", "Original person row")
			var checked: Dictionary = position_guard(row)
			if not checked.ok: return checked
	return Runtime.ok()

## B2S1 pure pair constructor. It copies the state and writes only the two
## original naval records; it starts no person job, UI or NPC order. A linked
## copy is still refused by save_guard (BUSY) until B5 admits persistence.
static func make_pair(state: Dictionary, self_id: String, peer_id: String, link_id: String, epoch: int,
		self_anchor: Vector2i, peer_anchor: Vector2i, self_local: Array, peer_local: Array) -> Dictionary:
	var site_id: Variant = state.get("id")
	var vehicles: Variant = state.get("vehicles", {})
	if not site_id is String or site_id.is_empty() or not vehicles is Dictionary or self_id.is_empty() or peer_id.is_empty() or self_id == peer_id or link_id.is_empty() or not _integer(epoch, 1):
		return Runtime.fail("NO_TARGET")
	if not vehicles.get(self_id) is Dictionary or not vehicles.get(peer_id) is Dictionary: return Runtime.fail("NO_TARGET")
	if not _point(self_local) or not _point(peer_local): return Runtime.fail("CORRUPT_SAVE", "Boarding local point type")
	var pair: Dictionary = state.duplicate(true)
	var first: Dictionary = pair.vehicles[self_id]
	var second: Dictionary = pair.vehicles[peer_id]
	for vehicle: Dictionary in [first, second]:
		if vehicle.get("kind") != "ship" or not vehicle.get("naval") is Dictionary or vehicle.naval.get("version") != 1 or vehicle.naval.get("state") != "afloat" or vehicle.naval.has("boarding_link"):
			return Runtime.fail("BUSY", "Boarding pair needs two afloat v1 ships without a link")
		if not vehicle.get("move") is Dictionary or not vehicle.get("move").is_empty() or not vehicle.get("command") is Dictionary or not vehicle.get("command").is_empty():
			return Runtime.fail("BUSY", "Boarding pair needs two stopped ships with no command")
	var first_link: Dictionary = _end_record(site_id, link_id, epoch, first, second, self_anchor, peer_anchor, self_local)
	var second_link: Dictionary = _end_record(site_id, link_id, epoch, second, first, peer_anchor, self_anchor, peer_local)
	first.naval.version = 2
	first.naval.boarding_link = first_link
	second.naval.version = 2
	second.naval.boarding_link = second_link
	var checked: Dictionary = query(pair, self_id)
	if not checked.ok: return checked
	return Runtime.ok("", {"state": pair, "linked": true, "entrants_open": checked.entrants_open, "can_execute": false})

# One end of a link, in the same arithmetic query() uses to check world_point.
static func _end_record(site_id: String, link_id: String, epoch: int, vehicle: Dictionary, peer: Dictionary,
		anchor: Vector2i, peer_anchor: Vector2i, local: Array) -> Dictionary:
	var direction := Vector2(float(vehicle.facing[0]), float(vehicle.facing[1]))
	var point: Vector2 = Vector2(anchor.x, anchor.y) + Vector2(-direction.y, direction.x) * float(local[0]) + direction * float(local[1])
	return {"version": VERSION, "id": link_id, "epoch": epoch,
		"self": {"site_id": site_id, "vehicle_id": str(vehicle.id)},
		"peer": {"site_id": site_id, "vehicle_id": str(peer.id)},
		"frame": {"site_id": site_id, "anchor": [anchor.x, anchor.y], "facing": vehicle.facing.duplicate()},
		"peer_frame": {"site_id": site_id, "anchor": [peer_anchor.x, peer_anchor.y], "facing": peer.facing.duplicate()},
		"local": [float(local[0]), float(local[1])], "world_point": [point.x, point.y], "state": "linked", "crosser_id": 0}

## B2S2 pure transitions. Each returns a copy; both ends are written together,
## and the copy is accepted only if query() passes. Epochs never change here.
static func set_state(state: Dictionary, self_id: String, next_state: String) -> Dictionary:
	var current: Dictionary = query(state, self_id)
	if not current.ok: return current
	if not current.linked: return Runtime.fail("NO_TARGET", "No boarding link")
	var link: Dictionary = current.link
	if not (next_state in TRANSITIONS.get(str(link.state), [])): return Runtime.fail("BUSY", "Illegal link transition")
	var pair: Dictionary = state.duplicate(true)
	pair.vehicles[self_id].naval.boarding_link.state = next_state
	pair.vehicles[str(link.peer.vehicle_id)].naval.boarding_link.state = next_state
	return _accepted(pair, self_id)

static func enter_crosser(state: Dictionary, self_id: String, person_id: int) -> Dictionary:
	var current: Dictionary = query(state, self_id)
	if not current.ok: return current
	if not current.linked: return Runtime.fail("NO_TARGET", "No boarding link")
	var link: Dictionary = current.link
	if link.state != "linked": return Runtime.fail("BUSY", "Entrants are closed")
	if int(link.crosser_id) != 0: return Runtime.fail("BUSY", "One crosser at a time")
	if not _integer(person_id, 1): return Runtime.fail("NO_TARGET", "Crosser id")
	var pair: Dictionary = state.duplicate(true)
	pair.vehicles[self_id].naval.boarding_link.crosser_id = person_id
	pair.vehicles[str(link.peer.vehicle_id)].naval.boarding_link.crosser_id = person_id
	return _accepted(pair, self_id)

static func leave_crosser(state: Dictionary, self_id: String) -> Dictionary:
	var current: Dictionary = query(state, self_id)
	if not current.ok: return current
	if not current.linked: return Runtime.fail("NO_TARGET", "No boarding link")
	var link: Dictionary = current.link
	if not (link.state in ["linked", "closing"]): return Runtime.fail("BUSY", "Crosser cannot leave a link in this state")
	if int(link.crosser_id) == 0: return Runtime.fail("NO_TARGET", "No crosser")
	var pair: Dictionary = state.duplicate(true)
	pair.vehicles[self_id].naval.boarding_link.crosser_id = 0
	pair.vehicles[str(link.peer.vehicle_id)].naval.boarding_link.crosser_id = 0
	return _accepted(pair, self_id)

static func _accepted(pair: Dictionary, self_id: String) -> Dictionary:
	var checked: Dictionary = query(pair, self_id)
	if not checked.ok: return checked
	return Runtime.ok("", {"state": pair, "link_state": str(checked.link.state), "crosser_id": int(checked.link.crosser_id), "entrants_open": checked.entrants_open, "can_execute": false})

## B3S1 pure crossing ledger on top of the B2S2 crosser slot. A crossing is one
## original person moving across one linked pair. This only records who is in
## the channel; it moves no body, row, cargo or position (B3S2+ owns that).
static func crossing_begin(state: Dictionary, from_id: String, to_id: String, person_id: int) -> Dictionary:
	var current: Dictionary = query(state, from_id)
	if not current.ok: return current
	if not current.linked: return Runtime.fail("NO_TARGET", "No boarding link")
	var link: Dictionary = current.link
	if str(link.peer.vehicle_id) != to_id: return Runtime.fail("NO_TARGET", "Not the linked peer hull")
	return enter_crosser(state, from_id, person_id)

static func crossing_end(state: Dictionary, from_id: String, person_id: int) -> Dictionary:
	var current: Dictionary = query(state, from_id)
	if not current.ok: return current
	if not current.linked: return Runtime.fail("NO_TARGET", "No boarding link")
	var link: Dictionary = current.link
	if int(link.crosser_id) == 0: return Runtime.fail("NO_TARGET", "No crosser in the channel")
	if int(link.crosser_id) != person_id: return Runtime.fail("BUSY", "Only the recorded crosser may leave the channel")
	return leave_crosser(state, from_id)
