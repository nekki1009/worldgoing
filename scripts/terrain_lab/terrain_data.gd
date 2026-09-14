class_name TerrainData
extends RefCounted

enum Surface { GRASS, FOREST_GROUND, DIRT, ROCK, SAND, WETLAND, WATER }
enum Flag { WALKABLE = 1, CLIFF = 2, RAMP = 4, SHORE = 8, WET = 16, BLOCKED = 32 }
const SURFACE_NAMES: Array[String] = ["GRASS", "FOREST_GROUND", "DIRT", "ROCK", "SAND", "WETLAND", "WATER"]
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var size := Vector2i(100, 100)
var height_levels := PackedByteArray()
var surface_types := PackedByteArray()
var flags := PackedByteArray()
# Four positive high-to-low drops per cell, N/E/S/W. Zero does not mean a ramp.
var cliff_drops := PackedByteArray()
# Reciprocal N/E/S/W bits mark legal one-level crossings, independently of art.
var ramp_edges := PackedByteArray()
var detail_variation := PackedByteArray()
var spawn_cell := Vector2i(-1, -1)
var preset: int = 0
var seed_value: int = 0
var parameters: Dictionary = {}

# Generated environment and sparse Site changes share this map owner.
var fertility := PackedByteArray()
var moisture := PackedByteArray()
var drainage := PackedByteArray()
var foundation := PackedByteArray()
var groundwater := PackedByteArray()
var water_kind := PackedByteArray() # 0 none, 1 fresh, 2 sea, 3 brine.
var water_body := PackedInt32Array()
var resource_base: Dictionary = {}
var resources_at: Dictionary = {}
var site: Dictionary = {}
# Rebuildable indexes; never serialized as a second authority.
var static_blocked := PackedByteArray()
var feature_at := PackedInt32Array()
var navigation_revision := 0
var environment_revision := 0
var ground_loot_at: Dictionary = {} # Rebuilt from site.ground_loot; never a second item owner.
var ground_loot_dirty_rows: Dictionary = {} # Event-only presentation invalidation, never saved.

func allocate(grid_size: Vector2i) -> void:
	size = grid_size
	var count: int = size.x * size.y
	height_levels.resize(count)
	surface_types.resize(count)
	flags.resize(count)
	cliff_drops.resize(count * 4)
	ramp_edges.resize(count)
	detail_variation.resize(count)

func contains(terrain_cell: Vector2i) -> bool:
	return terrain_cell.x >= 0 and terrain_cell.y >= 0 and terrain_cell.x < size.x and terrain_cell.y < size.y

func index(terrain_cell: Vector2i) -> int:
	return terrain_cell.y * size.x + terrain_cell.x

func is_walkable(terrain_cell: Vector2i) -> bool:
	return is_terrain_walkable(terrain_cell) and (static_blocked.is_empty() or static_blocked[index(terrain_cell)] == 0)

func is_terrain_walkable(terrain_cell: Vector2i) -> bool:
	return contains(terrain_cell) and (flags[index(terrain_cell)] & Flag.WALKABLE) != 0

func can_step(from: Vector2i, to: Vector2i) -> bool:
	# The terrain predicate already checks both cells' bounds/walkable flags.
	return can_terrain_step(from, to) and (static_blocked.is_empty() \
		or (static_blocked[index(from)] == 0 and static_blocked[index(to)] == 0))

func can_terrain_step(from: Vector2i, to: Vector2i) -> bool:
	if not is_terrain_walkable(from) or not is_terrain_walkable(to):
		return false
	var direction: int = DIRECTIONS.find(to - from)
	if direction < 0:
		return false
	var a: int = index(from)
	var b: int = index(to)
	var difference: int = absi(int(height_levels[a]) - int(height_levels[b]))
	if difference == 0:
		return true
	return difference == 1 and (ramp_edges[a] & (1 << direction)) != 0 \
		and (ramp_edges[b] & (1 << ((direction + 2) % 4))) != 0

func can_attack_across(from: Vector2i, to: Vector2i) -> bool:
	# Current tall resource/building obstacles block both travel and weapons.
	# Low plants, underground deposits and fields do neither.
	return can_terrain_step(from, to) and (static_blocked.is_empty() \
		or (static_blocked[index(from)] == 0 and static_blocked[index(to)] == 0))

func cell_from_index(cell_index: int) -> Vector2i:
	return Vector2i(cell_index % size.x, floori(float(cell_index) / float(size.x)))

func path_between(start: Vector2i, goal: Vector2i, blocked: Callable = Callable()) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_walkable(start) or not is_walkable(goal) or start == goal:
		return result
	var previous := {start: start}
	var pending: Array[Vector2i] = [start]
	var head := 0
	while head < pending.size():
		var current := pending[head]
		head += 1
		if current == goal:
			break
		for direction: Vector2i in DIRECTIONS:
			var next := current + direction
			if previous.has(next) or not can_step(current, next):
				continue
			if blocked.is_valid() and bool(blocked.call(next)):
				continue
			previous[next] = current
			pending.append(next)
	if not previous.has(goal):
		return result
	var cursor := goal
	while cursor != start:
		result.append(cursor)
		cursor = previous[cursor]
	result.reverse()
	return result

func fingerprint() -> String:
	var bytes := PackedByteArray()
	for field: PackedByteArray in [height_levels, surface_types, flags, cliff_drops, ramp_edges, detail_variation]:
		bytes.append_array(field)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
