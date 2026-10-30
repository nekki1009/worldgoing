extends RefCounted
## Pure presentation projection of the original vehicle/person action facts.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Clips = preload("site_siege_work_clips.gd")
const INVALID_CELL := Vector2i(-1, -1)
# Native crowd crew may stand off-centre, up to this distance (in cells) from the station centre.
const CROWD_STATION_RADIUS := 0.75

static func sample(data: TerrainData, vehicle: Dictionary, identity: int, person: Dictionary) -> Dictionary:
	if vehicle.is_empty() or not Runtime.SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) or not vehicle.get("crew_slots", {}).values().has(identity): return {}
	if not bool(person.get("can_act", false)) or float(person.get("hp", 0.0)) <= 0.0 or float(person.get("ko", 1.0)) > 0.0 or bool(person.get("reacting", true)) or str(person.get("pose", "")) not in ["idle", "walk", "run"]: return {}
	var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var cell: Vector2i = person.cell
	var move: Dictionary = vehicle.get("move", {})
	if not move.is_empty():
		for member: Dictionary in move.get("participants", []):
			if int(member.person_id) == identity and int(member.from) == data.index(cell) and person.get("moving_to", INVALID_CELL) == data.cell_from_index(int(member.to)):
				return {"clip": "siege_push", "time": clampf(float(person.progress), 0.0, 1.0) * float(Clips.DURATIONS.siege_push), "facing": facing}
		return {}
	var action: Dictionary = vehicle.get("action", {})
	var stage := str(action.get("stage", ""))
	if stage == "rotate":
		for contact: Dictionary in Runtime.siege_turn_contacts(data, vehicle):
			if int(vehicle.crew_slots.get(str(contact.slot), 0)) != identity or cell != contact.station or person.get("moving_to", INVALID_CELL) != INVALID_CELL: continue
			var axis: Vector2 = contact.attachment - (Vector2(contact.station) + Vector2.ONE * 0.5)
			if axis.is_zero_approx(): return {}
			facing = Vector2i(1 if axis.x >= 0.0 else -1, 0) if absf(axis.x) >= absf(axis.y) else Vector2i(0, 1 if axis.y >= 0.0 else -1)
			return {"clip": "siege_pull", "time": float(action.elapsed), "facing": facing}
		return {}
	if stage in ["loading", "preparing", "tower_deploy", "tower_retract"] and person.get("moving_to", INVALID_CELL) == INVALID_CELL:
		for slot: String in vehicle.crew_slots:
			if int(vehicle.crew_slots[slot]) == identity and at_crew_station(data, vehicle, slot, cell, bool(person.get("crowd", false)), Vector2(person.get("position", Vector2.ZERO))):
				return {"clip": "siege_load" if stage == "loading" else "siege_pull", "time": float(action.elapsed), "facing": facing}
	return {}

static func at_crew_station(data: TerrainData, vehicle: Dictionary, slot: String, cell: Vector2i, crowd: bool, native_position: Vector2 = Vector2.ZERO, turning: bool = false) -> bool:
	var station: Vector2i = Runtime.siege_crew_cell(data, vehicle, slot, turning)
	# Grid people keep the exact cell test. Crowd input carries the native position, so its floor cell may be a neighbour.
	if not crowd: return cell == station
	var at: Vector2 = native_position / 64.0
	return at.distance_to(Vector2(station) + Vector2.ONE * 0.5) <= CROWD_STATION_RADIUS
