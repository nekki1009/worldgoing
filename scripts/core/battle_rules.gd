class_name BattleRules
extends RefCounted

const DEPLOYMENT_ZONE_RATIO: float = 0.20
const PERSONNEL_PER_FORMATION_MARKER: int = 50
const FORMATIONS_PER_RANK: int = 10

static func combat_frontage(terrain_type: int) -> int:
	match terrain_type:
		TerrainType.PLAINS:
			return 1500
		TerrainType.FOREST:
			return 500
		TerrainType.MOUNTAIN:
			return 250
		TerrainType.WATER:
			return 0
		_:
			return 0

static func deployment(total_personnel: int, terrain_type: int) -> Dictionary:
	var total: int = maxi(total_personnel, 0)
	var frontage: int = combat_frontage(terrain_type)
	var deployed: int = mini(total, frontage)
	return {
		"total_personnel": total,
		"combat_frontage": frontage,
		"initial_deployed_personnel": deployed,
		"reserve_personnel": total - deployed,
	}

static func deployment_zone(battle_size_meters: Vector2, entry_direction: int) -> Rect2:
	var depth_x: float = battle_size_meters.x * DEPLOYMENT_ZONE_RATIO
	var depth_y: float = battle_size_meters.y * DEPLOYMENT_ZONE_RATIO
	match entry_direction:
		BattleSiteContext.EntryDirection.NORTH:
			return Rect2(Vector2.ZERO, Vector2(battle_size_meters.x, depth_y))
		BattleSiteContext.EntryDirection.EAST:
			return Rect2(
				Vector2(battle_size_meters.x - depth_x, 0.0),
				Vector2(depth_x, battle_size_meters.y)
			)
		BattleSiteContext.EntryDirection.SOUTH:
			return Rect2(
				Vector2(0.0, battle_size_meters.y - depth_y),
				Vector2(battle_size_meters.x, depth_y)
			)
		BattleSiteContext.EntryDirection.WEST:
			return Rect2(Vector2.ZERO, Vector2(depth_x, battle_size_meters.y))
		_:
			return Rect2()

static func formation_marker_count(personnel: int) -> int:
	return ceili(float(maxi(personnel, 0)) / float(PERSONNEL_PER_FORMATION_MARKER))

static func formation_marker_positions(
		zone: Rect2,
		entry_direction: int,
		marker_count: int
	) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if marker_count <= 0 or not zone.has_area():
		return result
	var rank_count: int = ceili(float(marker_count) / float(FORMATIONS_PER_RANK))
	var horizontal_edge: bool = entry_direction == BattleSiteContext.EntryDirection.NORTH \
		or entry_direction == BattleSiteContext.EntryDirection.SOUTH
	for marker_index: int in range(marker_count):
		var rank: int = marker_index / FORMATIONS_PER_RANK
		var slot: int = marker_index % FORMATIONS_PER_RANK
		var markers_in_rank: int = mini(
			FORMATIONS_PER_RANK,
			marker_count - rank * FORMATIONS_PER_RANK
		)
		if horizontal_edge:
			var x: float = zone.position.x + zone.size.x * float(slot + 1) / float(markers_in_rank + 1)
			var y_step: float = zone.size.y / float(rank_count + 1)
			var y: float = zone.position.y + y_step * float(rank + 1)
			if entry_direction == BattleSiteContext.EntryDirection.SOUTH:
				y = zone.end.y - y_step * float(rank + 1)
			result.append(Vector2(x, y))
		else:
			var y: float = zone.position.y + zone.size.y * float(slot + 1) / float(markers_in_rank + 1)
			var x_step: float = zone.size.x / float(rank_count + 1)
			var x: float = zone.position.x + x_step * float(rank + 1)
			if entry_direction == BattleSiteContext.EntryDirection.EAST:
				x = zone.end.x - x_step * float(rank + 1)
			result.append(Vector2(x, y))
	return result

static func facing_vector(entry_direction: int) -> Vector2:
	return -Vector2(BattleSiteContext.entry_vector(entry_direction))

static func deployment_preview(
		participant: BattleParticipantData,
		terrain_type: int,
		battle_size_meters: Vector2,
		entry_direction: int
	) -> Dictionary:
	var split: Dictionary = deployment(participant.total_personnel, terrain_type)
	var zone: Rect2 = deployment_zone(battle_size_meters, entry_direction)
	var marker_count: int = formation_marker_count(int(split["initial_deployed_personnel"]))
	split["participant"] = participant
	split["entry_direction"] = entry_direction
	split["zone_meters"] = zone
	split["marker_count"] = marker_count
	split["marker_positions_meters"] = formation_marker_positions(zone, entry_direction, marker_count)
	split["facing"] = facing_vector(entry_direction)
	return split
